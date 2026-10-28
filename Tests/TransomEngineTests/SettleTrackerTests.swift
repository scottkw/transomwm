import TransomEngine
import TransomModel
import Testing

private func id(_ n: UInt32) -> WindowIdentity {
    WindowIdentity(windowID: n, pid: 720, bundleID: "com.example.settle")
}

/// UI-SPEC Surface 1 step 7: reveal at the last write's return + 50 ms once every write is back, or at the 1500 ms cap.
@Suite struct SettleTrackerTests {
    let t0 = ContinuousClock.now

    @Test func allReturnedRevealsFiftyMillisecondsAfterTheLast() {
        var tracker = SettleTracker(pending: [id(1), id(2)], started: t0)
        tracker.applied(id(1), at: t0 + .milliseconds(100))
        tracker.applied(id(2), at: t0 + .milliseconds(200))

        #expect(tracker.isComplete)
        #expect(tracker.revealAt() == t0 + .milliseconds(250))
    }

    @Test func stillPendingRevealsAtTheCap() {
        var tracker = SettleTracker(pending: [id(1), id(2)], started: t0)
        tracker.applied(id(1), at: t0 + .milliseconds(100))

        #expect(!tracker.isComplete)
        #expect(tracker.revealAt() == t0 + .milliseconds(1500))
    }

    @Test func aLateLastReturnIsCappedAt1500Milliseconds() {
        var tracker = SettleTracker(pending: [id(1)], started: t0)
        tracker.applied(id(1), at: t0 + .milliseconds(1480))

        #expect(tracker.revealAt() == t0 + .milliseconds(1500))
    }

    @Test func anIDNotPendingChangesNothing() {
        var tracker = SettleTracker(pending: [id(1)], started: t0)
        tracker.applied(id(3), at: t0 + .milliseconds(100))
        #expect(!tracker.isComplete)
        #expect(tracker.revealAt() == t0 + .milliseconds(1500))

        tracker.applied(id(1), at: t0 + .milliseconds(200))
        tracker.applied(id(1), at: t0 + .milliseconds(900))
        tracker.applied(id(4), at: t0 + .milliseconds(900))
        #expect(tracker.revealAt() == t0 + .milliseconds(250))
    }

    @Test func nothingPendingRevealsAfterTheRedrawWait() {
        let tracker = SettleTracker(pending: [], started: t0)

        #expect(tracker.isComplete)
        #expect(tracker.revealAt() == t0 + .milliseconds(50))
    }
}
