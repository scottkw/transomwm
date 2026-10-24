// The Accessibility permission flow (D-02, WIN-01) as one pure state machine. The controller in PaneMac
// feeds it UI clicks, 1 s poll ticks and probe/reset results, then runs the returned effects in order.
// Times are `Duration`s since app launch, measured by the caller, so tests need no clock.

/// Where the grant flow is. Each case names the "Set Up Pane" state it shows (02-UI-SPEC Surface 2).
public enum PermissionPhase: Equatable, Sendable {
    /// S1, first view: Pane is not trusted and the user hasn't opened System Settings yet.
    case notTrusted
    /// S1 + "Waiting for access…" (callout B once `showStaleFormB`); S4 when `afterReset`.
    case waitingForGrant
    /// S2: trusted; the AX probe is checking that window requests really work.
    case probing
    /// S5: tracking runs.
    case ready
    /// S3, stale form A: macOS says trusted, but AX requests fail with -25211.
    case staleTrustedButFailing
    /// "Resetting permission…": tccutil is running; every button is disabled.
    case resetting
}

public struct PermissionState: Equatable, Sendable {
    public var phase: PermissionPhase = .notTrusted
    /// First "Open System Settings" click of this grant cycle; nil until it happens (and after a reset).
    public var cycleStartedAt: Duration?
    /// Callout B "Already turned on?" (stale form B).
    public var showStaleFormB = false
    /// The last reset succeeded, so waitingForGrant shows S4 instead of S1.
    public var afterReset = false
    /// Callout E: tccutil's non-zero exit status.
    public var resetFailedCode: Int32?
    /// The phase a reset returns to when tccutil fails.
    public var phaseBeforeReset: PermissionPhase?

    public init() {}
}

public enum ProbeOutcome: Equatable, Sendable {
    /// AXRole read succeeded.
    case success
    /// -25211 (kAXErrorAPIDisabled): stale form A.
    case apiDisabled
    /// Every attempt timed out; treated as ready so the spinner never hangs.
    case inconclusive
}

public enum PermissionEvent: Equatable, Sendable {
    case launched(trusted: Bool)
    case openSettingsClicked(at: Duration)
    case pollTick(trusted: Bool, at: Duration)
    case probeFinished(ProbeOutcome)
    case resetClicked
    case resetFinished(exitCode: Int32)
}

public enum PermissionEffect: Equatable, Sendable {
    /// `AXIsProcessTrustedWithOptions` with the prompt option: only the first click of a cycle.
    case promptForTrust
    case openSettings
    case startPolling
    case stopPolling
    case runProbe
    case runReset
    case startTracking
    case bringWindowForward
}

public enum PermissionReducer {
    /// Stale form B appears when a poll this long after the cycle's first Settings click is still untrusted.
    public static let staleFormBDelay: Duration = .seconds(15)

    /// Total: every (phase, event) pair not handled below keeps the state and returns no effects.
    public static func reduce(_ state: inout PermissionState, _ event: PermissionEvent) -> [PermissionEffect] {
        switch (state.phase, event) {
        case (.notTrusted, .launched(let trusted)):
            if !trusted { return [] }
            state.phase = .probing
            return [.runProbe]

        case (.notTrusted, .openSettingsClicked(let at)):
            state.phase = .waitingForGrant
            state.cycleStartedAt = at
            return [.promptForTrust, .openSettings, .startPolling]

        case (.waitingForGrant, .openSettingsClicked(let at)):
            // After a reset polling already runs; the first click of the new cycle prompts again.
            if state.cycleStartedAt != nil { return [.openSettings] }
            state.cycleStartedAt = at
            return [.promptForTrust, .openSettings]

        case (.staleTrustedButFailing, .openSettingsClicked):
            return [.openSettings]

        case (.waitingForGrant, .pollTick(let trusted, let at)):
            if trusted {
                state.phase = .probing
                return [.stopPolling, .runProbe]
            }
            if let start = state.cycleStartedAt, at - start >= staleFormBDelay { state.showStaleFormB = true }
            return []

        case (.probing, .probeFinished(let outcome)):
            if outcome == .apiDisabled {
                state.phase = .staleTrustedButFailing
                return []
            }
            state = PermissionState()
            state.phase = .ready
            return [.startTracking, .bringWindowForward]

        case (.staleTrustedButFailing, .resetClicked), (.waitingForGrant, .resetClicked) where state.showStaleFormB:
            state.phaseBeforeReset = state.phase
            state.phase = .resetting
            state.resetFailedCode = nil
            return [.runReset]

        case (.resetting, .resetFinished(let exitCode)):
            if exitCode == 0 {
                state = PermissionState()
                state.phase = .waitingForGrant
                state.afterReset = true
                return [.startPolling]
            }
            state.phase = state.phaseBeforeReset ?? .notTrusted
            state.phaseBeforeReset = nil
            state.resetFailedCode = exitCode
            return []

        default:
            return []
        }
    }
}
