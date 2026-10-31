@testable import TransomMac
import Testing

/// A sleep the test ends by hand, so no test waits 1.5 s. A cancelled sleeper still returns when fired; the
/// settler then sees `Task.isCancelled` and stops, as it would after a real cancelled `Task.sleep`.
@MainActor private final class ManualSleep {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Ends every pending sleep and lets the woken tasks run.
    func fire() async {
        let woken = waiters
        waiters = []
        for waiter in woken { waiter.resume() }
        for _ in 0..<10 { await Task.yield() }
    }

    /// Lets a just-started quiet task reach its sleep.
    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor private final class Calls {
    var settling = 0
    var settled = 0
    var paused = false
}

/// D-11: settling starts at the first signal, every change restarts the 1.5 s quiet, and nothing settles while the
/// session is asleep or locked.
@MainActor @Suite struct DisplaySettlerTests {
    private let sleep = ManualSleep()
    private let calls = Calls()

    private func makeSettler() -> DisplaySettler {
        DisplaySettler(
            sleep: { [sleep] in await sleep.sleep($0) }, isPaused: { [calls] in calls.paused },
            onSettling: { [calls] in calls.settling += 1 }, onSettled: { [calls] in calls.settled += 1 })
    }

    @Test func oneTouchSettlesOnceAfterTheQuietPeriod() async {
        let settler = makeSettler()
        settler.touch()
        #expect(calls.settling == 1)
        #expect(settler.state == .settling)
        await sleep.settle()
        #expect(calls.settled == 0)
        await sleep.fire()
        #expect(calls.settled == 1)
        #expect(settler.state == .idle)
        #expect(sleep.durations == [.seconds(1.5)])
    }

    @Test func touchesHalfASecondApartSettleOnceAfterTheLast() async {
        let settler = makeSettler()
        for _ in 0..<3 {
            settler.touch()
            await sleep.settle()
        }
        #expect(calls.settling == 1)
        #expect(sleep.durations.count == 3)  // each touch restarted the full quiet period
        await sleep.fire()
        #expect(calls.settled == 1)
        #expect(calls.settling == 1)
    }

    @Test func beginAndTouchShareOneSettling() async {
        let settler = makeSettler()
        settler.begin()
        settler.touch()
        await sleep.settle()
        await sleep.fire()
        #expect(calls.settling == 1)
        #expect(calls.settled == 1)
    }

    @Test func nothingSettlesWhilePausedAndResumeRestartsTheFullQuietPeriod() async {
        let settler = makeSettler()
        settler.touch()
        await sleep.settle()
        calls.paused = true
        await sleep.fire()
        #expect(settler.state == .waitingForWake)
        #expect(calls.settled == 0)
        calls.paused = false
        settler.sessionResumed()
        #expect(settler.state == .settling)
        await sleep.settle()
        #expect(calls.settled == 0)
        await sleep.fire()
        #expect(calls.settled == 1)
        #expect(calls.settling == 1)
        #expect(sleep.durations == [.seconds(1.5), .seconds(1.5)])
    }

    @Test func resumeWhileIdleDoesNothing() async {
        let settler = makeSettler()
        settler.sessionResumed()
        await sleep.settle()
        #expect(settler.state == .idle)
        #expect(sleep.durations.isEmpty)
    }

    @Test func aTouchAfterSettlingStartsANewSettling() async {
        let settler = makeSettler()
        settler.touch()
        await sleep.settle()
        await sleep.fire()
        settler.touch()
        await sleep.settle()
        await sleep.fire()
        #expect(calls.settling == 2)
        #expect(calls.settled == 2)
    }
}
