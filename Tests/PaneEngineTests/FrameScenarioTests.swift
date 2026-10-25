import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 800
private let otherPID: Int32 = 801
private let bundleID = "com.example.frames"
private let start = Rect(x: 40, y: 80, width: 400, height: 300)

private func ref(_ id: UInt32, pid: Int32 = pid, bundleID: String = bundleID) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

/// Every event already yielded (the fake yields synchronously). Ends the stream, so call it once per fake.
private func drain(_ stream: AsyncStream<WindowEvent>) async -> [WindowEvent] {
    let reader = Task {
        var events: [WindowEvent] = []
        for await event in stream { events.append(event) }
        return events
    }
    try? await Task.sleep(for: .milliseconds(100))
    reader.cancel()
    return await reader.value
}

private func applied(_ events: [WindowEvent]) -> [(WindowRef, Rect, Rect)] {
    events.compactMap { if case .frameApplied(let ref, let requested, let actual) = $0 { (ref, requested, actual) } else { nil } }
}

private let t0 = ContinuousClock.now
private let confirmDelay = MinimumSizeLearner.confirmDelay

private func r(_ width: Double, _ height: Double) -> Rect {
    Rect(x: 40, y: 80, width: width, height: height)
}

/// Window 7 of the app at `frame`, listed by AX and in the CG list.
private func observation(_ frame: Rect, fullScreen: Bool = false) -> (AppObservation, [CGWindowEntry]) {
    let snapshot = WindowSnapshot(
        role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullScreen: fullScreen,
        close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
    )
    let app = AppObservation(pid: pid, bundleID: bundleID, windows: [WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(snapshot), title: "")])
    return (app, [CGWindowEntry(windowID: 7, pid: pid, bounds: frame, layer: 0, onScreen: true, alpha: 1)])
}

/// A tracker that already reports window 7 at `frame` (initial sweep at `t0`, so no settle delay).
private func tracker(at frame: Rect = start, fullScreen: Bool = false) -> WindowTracker {
    var tracker = WindowTracker()
    let (app, cg) = observation(frame, fullScreen: fullScreen)
    _ = tracker.ingest(app, context: ObservationContext(cgWindows: cg, initialSweep: true, now: t0))
    return tracker
}

/// A refresh at `time` that sees window 7 at `frame`.
@discardableResult
private func refresh(_ tracker: inout WindowTracker, at frame: Rect, time: ContinuousClock.Instant, fullScreen: Bool = false) -> [WindowEvent] {
    let (app, cg) = observation(frame, fullScreen: fullScreen)
    return tracker.ingest(app, context: ObservationContext(cgWindows: cg, now: time))
}

@discardableResult
private func write(_ tracker: inout WindowTracker, _ requested: Rect, readsBack actual: Rect, at time: ContinuousClock.Instant) -> [WindowEvent] {
    tracker.applyFrameResult(FrameWriteResult(window: ref(7), requested: requested, actual: actual, failure: nil), at: time)
}

private func learned(_ tracker: WindowTracker) -> Size? {
    tracker.info(for: ref(7).identity)?.learnedMinimum
}

/// probe3c's grid app: height snaps to the nearest 16-pt row plus 22 pt of chrome; width is honoured.
private func snapH(_ height: Double) -> Double { ((height - 22) / 16).rounded() * 16 + 22 }

/// One app with window 1 (hidden minimum 250×150) and another app with window 2, after the initial sweep.
private func twoApps(hiddenMinimum: Size? = Size(width: 250, height: 150)) async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await fake.addApp(FakeApp(pid: otherPID, bundleID: "com.example.other"))
    var refusing = FakeWindow.standard(id: 1, pid: pid, frame: start)
    refusing.hiddenMinimum = hiddenMinimum
    await fake.open(refusing)
    await fake.open(.standard(id: 2, pid: otherPID, frame: Rect(x: 500, y: 80, width: 400, height: 300)))
    await fake.refreshAll()
    return fake
}

/// D-13, D-14, D-17 on the tracker and the fake: every write is read back and reported, and a refusal is learned once
/// a refresh a second later confirms it (lead decision 2026-10-25). The probe3c cases are the reviewer's scenarios.
@Suite struct FrameScenarioTests {
    @Test func aReadBackFrameMovesAndResizesAndOneRefusalIsLearnedWhenARefreshASecondLaterConfirmsIt() throws {
        var tracker = tracker()
        let requested = Rect(x: 100, y: 120, width: 100, height: 80)
        let actual = Rect(x: 100, y: 120, width: 250, height: 150)
        var events = write(&tracker, requested, readsBack: actual, at: t0)
        #expect(try #require(tracker.info(for: ref(7).identity)).frame == actual)
        #expect(learned(tracker) == nil, "nothing is learned at write time")
        #expect(events == [.frameApplied(ref(7), requested: requested, actual: actual), .windowMoved(ref(7), actual), .windowResized(ref(7), actual)])
        #expect(tracker.awaitsMinimumConfirmation(pid: pid))
        // Too soon: the candidate waits.
        #expect(refresh(&tracker, at: actual, time: t0 + .milliseconds(999)).isEmpty)
        #expect(learned(tracker) == nil)
        events = refresh(&tracker, at: actual, time: t0 + confirmDelay)
        let info = try #require(tracker.info(for: ref(7).identity))
        #expect(info.learnedMinimum == Size(width: 250, height: 150))
        #expect(events == [.windowChanged(info)])
        #expect(!tracker.awaitsMinimumConfirmation(pid: pid))
    }

    /// probe3c "one shrink then static": shrunk once from 800, then the layout keeps asking for 300.
    @Test func aWindowThatStaysClampedLearnsAfterTheNextRefresh() throws {
        var tracker = tracker(at: r(800, 600))
        for k in 0..<3 { write(&tracker, r(300, 600), readsBack: r(500, 600), at: t0 + .milliseconds(10 * k)) }
        #expect(learned(tracker) == nil)
        let events = refresh(&tracker, at: r(500, 600), time: t0 + .milliseconds(20) + confirmDelay)
        let info = try #require(tracker.info(for: ref(7).identity))
        #expect(info.learnedMinimum == Size(width: 500, height: 0))
        #expect(events.filter { if case .windowChanged = $0 { true } else { false } } == [.windowChanged(info)])
    }

    /// probe3c "at-min static": the window opens at its minimum, so the read-back equals the frame it had.
    @Test func aWindowThatOpensAtItsMinimumLearnsIt() {
        var tracker = tracker(at: r(500, 600))
        write(&tracker, r(300, 600), readsBack: r(500, 600), at: t0)
        refresh(&tracker, at: r(500, 600), time: t0 + confirmDelay)
        #expect(learned(tracker) == Size(width: 500, height: 0))
    }

    /// probe3c "snap": a 16-pt row snap rounds 510 up to 518, which is under the 32-pt margin.
    @Test func aGridSnapIsNeverLearnedButARealRefusalStillIs() {
        var tracker = tracker(at: r(800, 822))
        var time = t0
        for height in [510.0, 790, 510] {
            write(&tracker, r(800, height), readsBack: r(800, snapH(height)), at: time)
            refresh(&tracker, at: r(800, snapH(height)), time: time + confirmDelay)
            #expect(learned(tracker) == nil, "learned a snap of \(height) to \(snapH(height))")
            time += .seconds(2)
        }
        // Positive control, so the snap rows cannot pass vacuously.
        write(&tracker, r(300, 822), readsBack: r(500, 822), at: time)
        refresh(&tracker, at: r(500, 822), time: time + confirmDelay)
        #expect(learned(tracker) == Size(width: 500, height: 0))
    }

    /// probe3c "lag-2 slow drag": each read-back is the request from two writes earlier; the app catches up.
    @Test func aSlowAppDuringADragLearnsNothing() {
        var tracker = tracker(at: r(800, 600))
        var requests: [Double] = [800, 800]
        var time = t0
        for _ in 0..<20 {
            requests.append(requests[requests.count - 1] - 1.5)
            write(&tracker, r(requests[requests.count - 1], 600), readsBack: r(requests[requests.count - 3], 600), at: time)
            time += .milliseconds(16)
        }
        refresh(&tracker, at: r(requests[requests.count - 1], 600), time: time + confirmDelay)
        #expect(learned(tracker) == nil)
    }

    /// probe3c "lag2" back and forth: some read-backs lag 100 pt or more, then the app catches up with 500.
    @Test func aSlowAppDraggedBackAndForthLearnsNothing() {
        var tracker = tracker(at: r(800, 600))
        let requests: [Double] = [800, 800, 700, 600, 500, 600, 700, 800, 700, 600, 500]
        var time = t0
        for k in 2..<requests.count {
            write(&tracker, r(requests[k], 600), readsBack: r(requests[k - 2], 600), at: time)
            time += .milliseconds(16)
        }
        refresh(&tracker, at: r(500, 600), time: time + confirmDelay)
        #expect(learned(tracker) == nil)
    }

    @Test func aWindowResizedByTheUserBeforeTheRefreshLearnsNothing() {
        var tracker = tracker(at: r(800, 600))
        write(&tracker, r(300, 600), readsBack: r(500, 600), at: t0)
        refresh(&tracker, at: r(640, 600), time: t0 + confirmDelay)
        #expect(learned(tracker) == nil)
        #expect(!tracker.awaitsMinimumConfirmation(pid: pid))
    }

    @Test func aFullscreenWindowLearnsNothing() throws {
        var tracker = tracker(fullScreen: true)
        #expect(tracker.info(for: ref(7).identity)?.state == .fullscreen)
        write(&tracker, Rect(x: 0, y: 0, width: 100, height: 80), readsBack: start, at: t0)
        #expect(!tracker.awaitsMinimumConfirmation(pid: pid))
        refresh(&tracker, at: start, time: t0 + confirmDelay, fullScreen: true)
        #expect(learned(tracker) == nil)
    }

    @Test func anHonouredWriteReportsNoWindowChanged() {
        var tracker = tracker()
        let moved = Rect(x: 200, y: 80, width: 400, height: 300)
        let events = write(&tracker, moved, readsBack: moved, at: t0)
        #expect(events == [.frameApplied(ref(7), requested: moved, actual: moved), .windowMoved(ref(7), moved)])
    }

    @Test func aFailedWriteLearnsNothingAndClosesNothing() throws {
        var tracker = tracker()
        let requested = Rect(x: 100, y: 120, width: 100, height: 80)
        let failed = FrameWriteResult(window: ref(7), requested: requested, actual: Rect(x: 100, y: 120, width: 250, height: 150), failure: .invalidElement)
        #expect(tracker.applyFrameResult(failed, at: t0).isEmpty)
        #expect(!tracker.awaitsMinimumConfirmation(pid: pid))
        let info = try #require(tracker.info(for: ref(7).identity))
        #expect(info.frame == start)
        #expect(info.learnedMinimum == nil)
    }

    @Test func theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsItFromOneWrite() async throws {
        let fake = await twoApps()
        let requested = Rect(x: 100, y: 120, width: 100, height: 80)
        await fake.perform([.setFrame(ref(1), requested)])
        #expect(await fake.inventory().windows.first { $0.window == ref(1) }?.learnedMinimum == nil, "nothing is learned at write time")
        await fake.advance(by: MinimumSizeLearner.confirmDelay)
        await fake.refreshAll()
        let writes = applied(await drain(fake.events))
        #expect(writes.count == 1)
        #expect(writes.first?.0 == ref(1))
        #expect(writes.first?.1 == requested)
        #expect(writes.first?.2 == Rect(x: 100, y: 120, width: 250, height: 150))
        let info = try #require(await fake.inventory().windows.first { $0.window == ref(1) })
        #expect(info.learnedMinimum == Size(width: 250, height: 150))
        #expect(await fake.performed == [.setFrame(ref(1), requested)])
    }

    @Test func aHungAppHoldsOnlyItsLatestFrameAndAnotherAppIsWrittenAtOnce() async {
        let fake = await twoApps(hiddenMinimum: nil)
        await fake.setHung(pid: pid, true)
        await fake.refreshAll()
        await fake.refreshAll()
        let first = Rect(x: 10, y: 20, width: 300, height: 200)
        let second = Rect(x: 30, y: 40, width: 320, height: 220)
        let other = Rect(x: 600, y: 100, width: 300, height: 200)
        await fake.perform([.setFrame(ref(1), first)])
        await fake.perform([.setFrame(ref(1), second), .setFrame(ref(2, pid: otherPID, bundleID: "com.example.other"), other)])
        await fake.setHung(pid: pid, false)
        await fake.advance(by: .seconds(2))
        await fake.refresh(pid: pid)
        let writes = applied(await drain(fake.events))
        #expect(writes.map(\.0) == [ref(2, pid: otherPID, bundleID: "com.example.other"), ref(1)], "the other app first, the held frame after recovery")
        #expect(writes.last?.1 == second)
        #expect(writes.last?.2 == second)
        #expect(await fake.windows[1]?.frame == second)
    }

    @Test func aClosedWindowsLearnedMinimumAndCandidateAreForgotten() async throws {
        let fake = await twoApps()
        let small = WindowCommand.setFrame(ref(1), Rect(x: 100, y: 120, width: 100, height: 80))
        await fake.perform([small])
        await fake.advance(by: MinimumSizeLearner.confirmDelay)
        await fake.refreshAll()
        #expect(await fake.inventory().windows.first { $0.window == ref(1) }?.learnedMinimum == Size(width: 250, height: 150))
        // A candidate waits when the window closes.
        await fake.perform([.setFrame(ref(1), Rect(x: 100, y: 120, width: 100, height: 80))])
        await fake.close(1)
        await fake.refreshAll()
        // The ID comes back as a new window at the candidate's size, with a smaller minimum.
        var reused = FakeWindow.standard(id: 1, pid: pid, frame: Rect(x: 100, y: 120, width: 250, height: 150))
        reused.hiddenMinimum = Size(width: 160, height: 130)
        await fake.open(reused)
        await fake.refreshAll()
        await fake.advance(by: .milliseconds(250))
        await fake.refreshAll()
        await fake.advance(by: MinimumSizeLearner.confirmDelay)
        await fake.refreshAll()
        #expect(await fake.inventory().windows.first { $0.window == ref(1) }?.learnedMinimum == nil, "the old window's candidate was confirmed")
        await fake.perform([small])
        await fake.advance(by: MinimumSizeLearner.confirmDelay)
        await fake.refreshAll()
        let info = try #require(await fake.inventory().windows.first { $0.window == ref(1) })
        #expect(info.learnedMinimum == Size(width: 160, height: 130))
    }

    @Test func invalidRectsAndUntrackedWindowsAreNotWritten() async {
        let fake = await twoApps()
        await fake.perform([
            .setFrame(ref(1), Rect(x: .nan, y: 0, width: 300, height: 200)),
            .setFrame(ref(1), Rect(x: 0, y: 0, width: Geometry.maxCoordinate + 1, height: 200)),
            .setFrame(ref(99), Rect(x: 0, y: 0, width: 300, height: 200)),
        ])
        #expect(applied(await drain(fake.events)).isEmpty)
        #expect(await fake.windows[1]?.frame == start)
    }
}
