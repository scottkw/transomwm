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

/// A tracker that already reports window 7 at `start` (initial sweep, so no settle delay).
private func trackerWithOneWindow() -> WindowTracker {
    var tracker = WindowTracker()
    let snapshot = WindowSnapshot(
        role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullScreen: false,
        close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: start
    )
    let app = AppObservation(pid: pid, bundleID: bundleID, windows: [WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(snapshot), title: "")])
    _ = tracker.ingest(app, context: ObservationContext(initialSweep: true, now: .now))
    return tracker
}

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

/// D-13, D-14, D-17 on the tracker and the fake: every write is read back, reported and learned from.
@Suite struct FrameScenarioTests {
    @Test func aReadBackFrameMovesAndResizesAndASecondAgreeingOneLearns() throws {
        var tracker = trackerWithOneWindow()
        let requested = Rect(x: 100, y: 120, width: 100, height: 80)
        let actual = Rect(x: 100, y: 120, width: 250, height: 150)
        let result = FrameWriteResult(window: ref(7), requested: requested, actual: actual, failure: nil)
        var events = tracker.applyFrameResult(result)
        #expect(try #require(tracker.info(for: ref(7).identity)).frame == actual)
        #expect(try #require(tracker.info(for: ref(7).identity)).learnedMinimum == nil)
        #expect(events == [.frameApplied(ref(7), requested: requested, actual: actual), .windowMoved(ref(7), actual), .windowResized(ref(7), actual)])
        // Back to the start (honoured), then the same refusal from the larger frame confirms it.
        _ = tracker.applyFrameResult(FrameWriteResult(window: ref(7), requested: start, actual: start, failure: nil))
        events = tracker.applyFrameResult(result)
        let info = try #require(tracker.info(for: ref(7).identity))
        #expect(info.learnedMinimum == Size(width: 250, height: 150))
        #expect(events == [
            .frameApplied(ref(7), requested: requested, actual: actual), .windowMoved(ref(7), actual), .windowResized(ref(7), actual),
            .windowChanged(info),
        ])
    }

    @Test func readBacksStillAtThePreWriteSizeTeachNothing() throws {
        var tracker = trackerWithOneWindow()
        // A busy app answers every write with the frame it had before, until it catches up.
        let result = FrameWriteResult(window: ref(7), requested: Rect(x: 40, y: 80, width: 100, height: 80), actual: start, failure: nil)
        _ = tracker.applyFrameResult(result)
        _ = tracker.applyFrameResult(result)
        #expect(try #require(tracker.info(for: ref(7).identity)).learnedMinimum == nil)
    }

    @Test func aFullscreenWindowLearnsNothing() throws {
        var tracker = WindowTracker()
        let snapshot = WindowSnapshot(
            role: "AXWindow", subrole: "AXStandardWindow", minimized: false, fullScreen: true,
            close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: start
        )
        let app = AppObservation(pid: pid, bundleID: bundleID, windows: [WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(snapshot), title: "")])
        _ = tracker.ingest(app, context: ObservationContext(initialSweep: true, now: .now))
        #expect(tracker.info(for: ref(7).identity)?.state == .fullscreen)
        let result = FrameWriteResult(window: ref(7), requested: Rect(x: 0, y: 0, width: 100, height: 80), actual: start, failure: nil)
        _ = tracker.applyFrameResult(result)
        _ = tracker.applyFrameResult(result)
        #expect(try #require(tracker.info(for: ref(7).identity)).learnedMinimum == nil)
    }

    @Test func anHonouredWriteReportsNoWindowChanged() {
        var tracker = trackerWithOneWindow()
        let moved = Rect(x: 200, y: 80, width: 400, height: 300)
        let events = tracker.applyFrameResult(FrameWriteResult(window: ref(7), requested: moved, actual: moved, failure: nil))
        #expect(events == [.frameApplied(ref(7), requested: moved, actual: moved), .windowMoved(ref(7), moved)])
    }

    @Test func aFailedWriteLearnsNothingAndClosesNothing() throws {
        var tracker = trackerWithOneWindow()
        let requested = Rect(x: 100, y: 120, width: 100, height: 80)
        let failed = FrameWriteResult(window: ref(7), requested: requested, actual: Rect(x: 100, y: 120, width: 250, height: 150), failure: .invalidElement)
        #expect(tracker.applyFrameResult(failed).isEmpty)
        let info = try #require(tracker.info(for: ref(7).identity))
        #expect(info.frame == start)
        #expect(info.learnedMinimum == nil)
    }

    @Test func theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsIt() async throws {
        let fake = await twoApps()
        let requested = Rect(x: 100, y: 120, width: 100, height: 80)
        // Refused, back to the start, refused again from the larger frame: confirmed.
        let writes3 = [WindowCommand.setFrame(ref(1), requested), .setFrame(ref(1), start), .setFrame(ref(1), requested)]
        await fake.perform(writes3)
        let writes = applied(await drain(fake.events))
        #expect(writes.count == 3)
        #expect(writes.first?.0 == ref(1))
        #expect(writes.first?.1 == requested)
        #expect(writes.first?.2 == Rect(x: 100, y: 120, width: 250, height: 150))
        let info = try #require(await fake.inventory().windows.first { $0.window == ref(1) })
        #expect(info.learnedMinimum == Size(width: 250, height: 150))
        #expect(await fake.performed == writes3)
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

    @Test func aClosedWindowsLearnedMinimumIsForgotten() async throws {
        let fake = await twoApps()
        let small = WindowCommand.setFrame(ref(1), Rect(x: 100, y: 120, width: 100, height: 80))
        let back = WindowCommand.setFrame(ref(1), start)
        await fake.perform([small, back, small])
        #expect(await fake.inventory().windows.first { $0.window == ref(1) }?.learnedMinimum == Size(width: 250, height: 150))
        await fake.close(1)
        await fake.refreshAll()
        // The ID comes back as a new window with a smaller minimum.
        var reused = FakeWindow.standard(id: 1, pid: pid, frame: start)
        reused.hiddenMinimum = Size(width: 120, height: 90)
        await fake.open(reused)
        await fake.refreshAll()
        await fake.advance(by: .milliseconds(250))
        await fake.refreshAll()
        await fake.perform([small, back, small])
        let info = try #require(await fake.inventory().windows.first { $0.window == ref(1) })
        #expect(info.learnedMinimum == Size(width: 120, height: 90))
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
