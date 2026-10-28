import Testing
import TransomEngine
import TransomModel
import TransomTestSupport

private let pid: Int32 = 100
private let a = DisplayInfo(uuid: "A", frame: Rect(x: 0, y: 0, width: 1000, height: 1000),
                            visibleFrame: Rect(x: 0, y: 38, width: 1000, height: 962), currentSpaceID: nil)
private let b = DisplayInfo(uuid: "B", frame: Rect(x: 1000, y: 0, width: 1920, height: 1080),
                            visibleFrame: Rect(x: 1000, y: 0, width: 1920, height: 1080), currentSpaceID: nil)

private func app(frame: Rect, fullScreen: Bool = false) -> AppObservation {
    let snapshot = WindowSnapshot(
        role: "AXWindow", subrole: "AXStandardWindow", modal: false, minimized: false, fullScreen: fullScreen,
        close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
    )
    return AppObservation(pid: pid, bundleID: "com.example.app", windows: [
        WindowObservation(windowID: 7, idSource: .axPrivate, read: .success(snapshot), title: "Doc"),
    ])
}

private func context(initial: Bool = false, spaces: [UInt32: Set<UInt64>]? = nil) -> ObservationContext {
    ObservationContext(displays: [a, b], initialSweep: initial, now: .now, windowSpaces: spaces)
}

@Suite struct TrackerDisplayTests {
    @Test func aWindowInsideBIsOnB() throws {
        var tracker = WindowTracker()
        let events = tracker.ingest(app(frame: Rect(x: 1200, y: 100, width: 600, height: 400)), context: context(initial: true))
        guard case .windowCreated(let info) = try #require(events.first) else {
            Issue.record("expected windowCreated, got \(events)")
            return
        }
        #expect(info.displayUUID == "B")
    }

    @Test func movingIntoAUpdatesTheDisplayAndEmitsWindowMoved() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(frame: Rect(x: 1200, y: 100, width: 600, height: 400)), context: context(initial: true))
        let moved = Rect(x: 100, y: 100, width: 600, height: 400)
        let events = tracker.ingest(app(frame: moved), context: context())
        let info = try #require(tracker.sortedWindows().first)
        #expect(info.displayUUID == "A")
        #expect(events.contains(.windowMoved(info.window, moved)))
        #expect(events.contains(.windowChanged(info)))
    }

    @Test func aWriteThatMovesTheWindowToBReportsBAtOnce() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(frame: Rect(x: 100, y: 100, width: 600, height: 400)), context: context(initial: true))
        let ref = try #require(tracker.sortedWindows().first).window
        let onB = Rect(x: 1200, y: 100, width: 600, height: 400)
        let events = tracker.applyFrameResult(FrameWriteResult(window: ref, requested: onB, actual: onB, failure: nil), at: .now)
        let info = try #require(tracker.info(for: ref.identity))
        #expect(info.displayUUID == "B")
        #expect(events.contains(.windowChanged(info)))
    }
}

/// D-25: each window carries the Spaces the lookup reports for its visible member.
@Suite struct TrackerSpacesTests {
    private let frame = Rect(x: 100, y: 100, width: 600, height: 400)

    @Test func aWindowsSpacesComeFromTheLookupAndAChangeIsReported() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(frame: frame), context: context(initial: true, spaces: [7: [2]]))
        #expect(try #require(tracker.sortedWindows().first).spaces == [2])
        let events = tracker.ingest(app(frame: frame), context: context(spaces: [7: [3]]))
        let info = try #require(tracker.sortedWindows().first)
        #expect(info.spaces == [3])
        #expect(events == [.windowChanged(info)])
    }

    @Test func withoutSpaceDataSpacesStayNilAndNothingIsReported() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(frame: frame), context: context(initial: true))
        #expect(try #require(tracker.sortedWindows().first).spaces == nil)
        #expect(tracker.ingest(app(frame: frame), context: context()).isEmpty)
    }

    /// A window going fullscreen moves to its own Space: its state is reported first, so no consumer sees a present
    /// window on a foreign Space (WIN-07).
    @Test func goingFullscreenReportsTheStateBeforeTheNewSpace() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(frame: frame), context: context(initial: true, spaces: [7: [1]]))
        let events = tracker.ingest(app(frame: frame, fullScreen: true), context: context(spaces: [7: [9]]))
        let info = try #require(tracker.sortedWindows().first)
        #expect(info.state == .fullscreen && info.spaces == [9])
        #expect(events == [.windowStateChanged(info.window, .fullscreen), .windowChanged(info)])
    }
}

@Suite struct FakeDisplayTests {
    @Test func theFakeReportsItsDisplaysAndAssignsWindowsToThem() async {
        let fake = FakeWindowSystem()
        await fake.setDisplays([a, b])
        await fake.addApp(FakeApp(pid: pid, bundleID: "com.example.app"))
        await fake.open(.standard(id: 7, pid: pid, frame: Rect(x: 1200, y: 100, width: 600, height: 400)))
        await fake.refreshAll()
        let inventory = await fake.inventory()
        #expect(inventory.displays == [a, b])
        #expect(inventory.windows.map(\.displayUUID) == ["B"])
    }
}
