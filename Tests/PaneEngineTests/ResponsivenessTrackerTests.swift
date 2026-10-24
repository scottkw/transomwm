import PaneEngine
import Testing

private let pid: Int32 = 7
private let fast: Duration = .milliseconds(10)

@Suite struct ResponsivenessTrackerTests {
    let t0 = ContinuousClock.now

    @Test func oneCannotCompleteIsNotDegraded() {
        var tracker = ResponsivenessTracker()
        #expect(tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0) == nil)
        #expect(tracker.degraded.isEmpty)
        #expect(tracker.shouldRefresh(pid: pid))
    }

    @Test func theSecondConsecutiveCannotCompleteDegradesOnce() {
        var tracker = ResponsivenessTracker()
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        #expect(tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0) == .degraded(pid))
        #expect(tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0) == nil)
        #expect(tracker.degraded == [pid])
    }

    @Test func aSuccessInBetweenResetsTheCount() {
        var tracker = ResponsivenessTracker()
        for outcome in [JobOutcome.cannotComplete, .success, .cannotComplete] {
            #expect(tracker.record(pid: pid, outcome: outcome, duration: fast, at: t0) == nil)
        }
        #expect(tracker.degraded.isEmpty)
    }

    @Test func anOtherFailureNeitherResetsNorAdvancesTheCount() {
        var tracker = ResponsivenessTracker()
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        #expect(tracker.record(pid: pid, outcome: .otherFailure, duration: fast, at: t0) == nil)
        #expect(tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0) == .degraded(pid))

        var other = ResponsivenessTracker()
        for _ in 0..<5 { _ = other.record(pid: pid, outcome: .otherFailure, duration: fast, at: t0) }
        #expect(other.degraded.isEmpty)
    }

    @Test func aJobOfExactly1_5sIsNotSlowButOneMillisecondMoreIs() {
        var tracker = ResponsivenessTracker()
        #expect(tracker.record(pid: pid, outcome: .success, duration: .milliseconds(1500), at: t0) == nil)
        #expect(tracker.record(pid: pid, outcome: .success, duration: .milliseconds(1501), at: t0) == .degraded(pid))
    }

    @Test func aDegradedAppIsNotRefreshedAndIsProbedEvery2s() {
        var tracker = ResponsivenessTracker()
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        #expect(!tracker.shouldRefresh(pid: pid))
        #expect(!tracker.needsProbe(pid: pid, at: t0 + .milliseconds(1900)))
        #expect(tracker.needsProbe(pid: pid, at: t0 + .seconds(2)))
    }

    @Test func aHealthyAppNeedsNoProbe() {
        var tracker = ResponsivenessTracker()
        _ = tracker.record(pid: pid, outcome: .success, duration: fast, at: t0)
        #expect(!tracker.needsProbe(pid: pid, at: t0 + .seconds(10)))
    }

    @Test func aSuccessfulProbeRecovers() {
        var tracker = ResponsivenessTracker()
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        #expect(tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0 + .seconds(2)) == nil)
        #expect(tracker.record(pid: pid, outcome: .success, duration: fast, at: t0 + .seconds(4)) == .recovered(pid))
        #expect(tracker.shouldRefresh(pid: pid))
        #expect(tracker.degraded.isEmpty)
        // The count starts again from zero after a recovery.
        #expect(tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0 + .seconds(5)) == nil)
    }

    @Test func forgetClearsAllStateForThatPid() {
        var tracker = ResponsivenessTracker()
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        _ = tracker.record(pid: pid, outcome: .cannotComplete, duration: fast, at: t0)
        _ = tracker.record(pid: 8, outcome: .cannotComplete, duration: fast, at: t0)
        tracker.forget(pid: pid)
        tracker.forget(pid: 8)
        #expect(tracker == ResponsivenessTracker())
        #expect(tracker.record(pid: 8, outcome: .cannotComplete, duration: fast, at: t0) == nil)
    }
}
