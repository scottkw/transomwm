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

/// The two-source close rule (D-09, WIN-09).
public enum CloseRule {
    /// RED stub: decides nothing.
    public static func decide(sessionActive: Bool, app: AppLiveness, ax: AXWindowFact, inCGList: Bool, isKnownTabMember: Bool) -> CloseDecision {
        .noChange
    }
}

/// Recently closed window identities, so a reused ID is never taken for the closed window (D-14 id churn).
public struct ClosedIDCache: Equatable, Sendable {
    public static let ttl: Duration = .seconds(60)

    public init() {}

    public mutating func insert(_ identity: WindowIdentity, at now: ContinuousClock.Instant) {}

    public func contains(_ identity: WindowIdentity, at now: ContinuousClock.Instant) -> Bool { false }

    public mutating func purge(at now: ContinuousClock.Instant) {}
}
