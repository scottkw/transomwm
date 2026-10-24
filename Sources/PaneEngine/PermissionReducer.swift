public enum PermissionPhase: Equatable, Sendable {
    case notTrusted, waitingForGrant, probing, ready, staleTrustedButFailing, resetting
}

public struct PermissionState: Equatable, Sendable {
    public var phase: PermissionPhase = .notTrusted
    public var cycleStartedAt: Duration?
    public var showStaleFormB = false
    public var afterReset = false
    public var resetFailedCode: Int32?
    public var phaseBeforeReset: PermissionPhase?

    public init() {}
}

public enum ProbeOutcome: Equatable, Sendable {
    case success, apiDisabled, inconclusive
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
    case promptForTrust, openSettings, startPolling, stopPolling, runProbe, runReset, startTracking, bringWindowForward
}

public enum PermissionReducer {
    public static let staleFormBDelay: Duration = .seconds(15)

    public static func reduce(_ state: inout PermissionState, _ event: PermissionEvent) -> [PermissionEffect] {
        []
    }
}
