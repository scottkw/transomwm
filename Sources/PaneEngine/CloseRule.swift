import PaneModel

/// Whether the window's app is still running, per NSWorkspace (`didTerminateApplication` / `isTerminated`).
/// AX cannot say: a killed app answers -25204, the same as a frozen one.
public enum AppLiveness: Equatable, Sendable {
    case alive, terminated
}

/// What AX said about one known window in this refresh.
public enum AXWindowFact: Equatable, Sendable {
    /// The element answered. `listed` is false for a window probed through its cached element after it left `AXWindows`.
    case valid(listed: Bool, minimized: Bool, appHidden: Bool, fullScreen: Bool)
    /// -25202: the element is gone.
    case invalidElement
    /// -25204, or no answer at all: the app may be frozen, killed or blanked by the lock screen.
    case timedOut
    case otherFailure
}

/// What to do with a known window. `.recheck` keeps the window and its state and decides again next refresh.
public enum CloseDecision: Equatable, Sendable {
    case noChange, recheck, state(WindowState), closed
}

/// The two-source close rule (D-09, WIN-09). A window closes only when AX (-25202, element gone) or NSWorkspace
/// (app terminated) agrees with the CG window list (id absent). Verified signals: a closed window answers
/// -25202 and leaves the CG list; a frozen or killed app answers -25204, so a timeout never closes anything.
///
/// | Session | App        | AX                         | CG      | Decision                          |
/// |---------|------------|----------------------------|---------|-----------------------------------|
/// | paused  | any        | any                        | any     | noChange                          |
/// | active  | terminated | any                        | absent  | closed                            |
/// | active  | terminated | any                        | present | recheck (WindowServer lag)        |
/// | active  | alive      | invalidElement             | absent  | closed                            |
/// | active  | alive      | invalidElement             | present | recheck (.absent for a tab member)|
/// | active  | alive      | timedOut / otherFailure    | any     | noChange                          |
/// | active  | alive      | valid, minimised or hidden | any     | state(.absent)                    |
/// | active  | alive      | valid, fullscreen          | any     | state(.fullscreen)                |
/// | active  | alive      | valid, unlisted            | present | noChange (hidden tab, other Space)|
/// | active  | alive      | valid                      | absent  | recheck (transient)               |
/// | active  | alive      | valid, listed              | present | state(.present)                   |
public enum CloseRule {
    public static func decide(sessionActive: Bool, app: AppLiveness, ax: AXWindowFact, inCGList: Bool, isKnownTabMember: Bool) -> CloseDecision {
        guard sessionActive else { return .noChange }
        switch (app, ax, inCGList) {
        case (.terminated, _, false): return .closed
        case (.terminated, _, true): return .recheck
        case (.alive, .invalidElement, false): return .closed
        case (.alive, .invalidElement, true): return isKnownTabMember ? .state(.absent) : .recheck
        case (.alive, .timedOut, _), (.alive, .otherFailure, _): return .noChange
        case (.alive, .valid(_, let minimized, let appHidden, _), _) where minimized || appHidden: return .state(.absent)
        case (.alive, .valid(_, _, _, true), _): return .state(.fullscreen)
        case (.alive, .valid(false, _, _, _), true): return .noChange
        case (.alive, .valid, false): return .recheck
        case (.alive, .valid(true, _, _, _), true): return .state(.present)
        }
    }
}

/// Recently closed window identities, so a reused ID is never taken for the closed window (D-14 id churn).
public struct ClosedIDCache: Equatable, Sendable {
    public static let ttl: Duration = .seconds(60)

    private var closedAt: [WindowIdentity: ContinuousClock.Instant] = [:]

    public init() {}

    public mutating func insert(_ identity: WindowIdentity, at now: ContinuousClock.Instant) {
        closedAt[identity] = now
    }

    /// True while `now < closed + ttl`.
    public func contains(_ identity: WindowIdentity, at now: ContinuousClock.Instant) -> Bool {
        closedAt[identity].map { now < $0 + Self.ttl } ?? false
    }

    public mutating func purge(at now: ContinuousClock.Instant) {
        closedAt = closedAt.filter { now < $0.value + Self.ttl }
    }
}
