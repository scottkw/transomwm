/// The result of one AX job for an app, as the responsiveness tracker sees it.
public enum JobOutcome: Equatable, Sendable {
    case success
    /// `kAXErrorCannotComplete` (-25204): the app did not answer in time.
    case cannotComplete
    case otherFailure
}

/// A change in an app's responsiveness, emitted once per transition.
public enum ResponsivenessChange: Equatable, Sendable {
    case degraded(Int32)
    case recovered(Int32)
}

/// RED stub: compiles, decides nothing.
public struct ResponsivenessTracker: Equatable, Sendable {
    public static let consecutiveFailureLimit = 2
    public static let slowJobLimit: Duration = .milliseconds(1500)
    public static let probeInterval: Duration = .seconds(2)

    public private(set) var degraded: Set<Int32> = []

    public init() {}

    public mutating func record(pid: Int32, outcome: JobOutcome, duration: Duration, at instant: ContinuousClock.Instant) -> ResponsivenessChange? {
        nil
    }

    public func needsProbe(pid: Int32, at instant: ContinuousClock.Instant) -> Bool { false }

    public func shouldRefresh(pid: Int32) -> Bool { true }

    public mutating func forget(pid: Int32) {}
}
