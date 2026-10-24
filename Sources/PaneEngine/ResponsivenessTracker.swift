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

/// Decides which apps are degraded (D-16): 2 consecutive `cannotComplete` results, or one job longer than
/// `slowJobLimit`. A degraded app gets no refreshes, only a probe every `probeInterval`; the first fast
/// success recovers it. `otherFailure` neither resets nor advances the failure count.
public struct ResponsivenessTracker: Equatable, Sendable {
    public static let consecutiveFailureLimit = 2
    public static let slowJobLimit: Duration = .milliseconds(1500)
    public static let probeInterval: Duration = .seconds(2)

    public private(set) var degraded: Set<Int32> = []
    private var failures: [Int32: Int] = [:]
    private var lastAttempt: [Int32: ContinuousClock.Instant] = [:]

    public init() {}

    /// Records one finished job; returns a change only on a transition.
    public mutating func record(pid: Int32, outcome: JobOutcome, duration: Duration, at instant: ContinuousClock.Instant) -> ResponsivenessChange? {
        lastAttempt[pid] = instant
        switch outcome {
        case .success: failures[pid] = nil
        case .cannotComplete: failures[pid, default: 0] += 1
        case .otherFailure: break
        }
        if failures[pid, default: 0] >= Self.consecutiveFailureLimit || duration > Self.slowJobLimit {
            return degraded.insert(pid).inserted ? .degraded(pid) : nil
        }
        if outcome == .success, degraded.remove(pid) != nil { return .recovered(pid) }
        return nil
    }

    /// True for a degraded app whose last attempt was at least `probeInterval` ago.
    public func needsProbe(pid: Int32, at instant: ContinuousClock.Instant) -> Bool {
        guard degraded.contains(pid) else { return false }
        return lastAttempt[pid].map { instant >= $0 + Self.probeInterval } ?? true
    }

    public func shouldRefresh(pid: Int32) -> Bool { !degraded.contains(pid) }

    public mutating func forget(pid: Int32) {
        degraded.remove(pid)
        failures[pid] = nil
        lastAttempt[pid] = nil
    }
}
