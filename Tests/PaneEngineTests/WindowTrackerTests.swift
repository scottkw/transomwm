import Testing
@testable import PaneEngine
import PaneModel

private let pid: Int32 = 100
private let bundleID = "com.example.app"
private let frame = Rect(x: 40, y: 80, width: 320, height: 232)
// Initial-sweep context: these tests are about tracking, not the settle delay (TrackerClassificationTests).
private let context = ObservationContext(initialSweep: true, now: .now)

private func snapshot(role: String = "AXWindow", subrole: String = "AXStandardWindow", minimized: Bool = false, frame: Rect = frame) -> WindowSnapshot {
    WindowSnapshot(
        role: role, subrole: subrole, minimized: minimized, fullScreen: false,
        close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
    )
}

private func window(_ id: UInt32?, _ read: Result<WindowSnapshot, AXFailure> = .success(snapshot())) -> WindowObservation {
    WindowObservation(windowID: id, idSource: .axPrivate, read: read, title: "Secret Plan.txt")
}

private func app(_ windows: WindowObservation...) -> AppObservation {
    AppObservation(pid: pid, bundleID: bundleID, windows: windows)
}

private func identity(_ id: UInt32, pid: Int32 = pid) -> WindowIdentity {
    WindowIdentity(windowID: id, pid: pid, bundleID: bundleID)
}

@Suite struct WindowTrackerTests {
    @Test func aWindowObservationWithAnIDCreatesOneWindowInfo() throws {
        var tracker = WindowTracker()
        let events = tracker.ingest(app(window(7)), context: context)
        let info = try #require(tracker.info(for: identity(7)))
        #expect(events == [.windowCreated(info)])
        #expect(tracker.windows.count == 1)
        #expect(info.frame == frame)
        #expect(info.state == .present)
        #expect(info.kind == .dockable)
        #expect(info.tabCount == 1)
        #expect(info.window.titleHint == "Secret Plan.txt")
    }

    @Test func theSameObservationAgainReturnsNoEvents() {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(window(7)), context: context)
        #expect(tracker.ingest(app(window(7)), context: context).isEmpty)
    }

    @Test func aMovedFrameReturnsWindowMoved() {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(window(7)), context: context)
        let moved = Rect(x: 200, y: 200, width: 320, height: 232)
        let events = tracker.ingest(app(window(7, .success(snapshot(frame: moved)))), context: context)
        #expect(events == [.windowMoved(WindowRef(identity: identity(7)), moved)])
    }

    @Test func aMinimizedSnapshotChangesTheStateToAbsentAndKeepsTheKind() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(window(7)), context: context)
        // Minimised windows report AXDialog; that must not demote the window to never-dock.
        let events = tracker.ingest(app(window(7, .success(snapshot(subrole: "AXDialog", minimized: true)))), context: context)
        #expect(events == [.windowStateChanged(WindowRef(identity: identity(7)), .absent)])
        #expect(try #require(tracker.info(for: identity(7))).kind == .dockable)
    }

    @Test(arguments: [
        window(7, .success(snapshot(role: "AXScrollArea"))),
        window(nil),
        window(7, .failure(.invalidElement)),
        window(7, .failure(.cannotComplete)),
    ])
    func nonWindowsUnidentifiedAndFailedReadsCreateNothing(observation: WindowObservation) {
        var tracker = WindowTracker()
        #expect(tracker.ingest(app(observation), context: context).isEmpty)
        #expect(tracker.windows.isEmpty)
    }

    @Test func twoWindowsWithIdenticalFramesStayTwoEntries() {
        var tracker = WindowTracker()
        let events = tracker.ingest(app(window(10), window(11)), context: context)
        #expect(events.count == 2)
        #expect(tracker.sortedWindows().map(\.window.windowID) == [10, 11])
    }

    @Test func aNewTrackerHasNoWindows() {
        #expect(WindowTracker().sortedWindows().isEmpty)
    }

    @Test func sortedWindowsAreOrderedByIdentity() {
        var tracker = WindowTracker()
        _ = tracker.ingest(AppObservation(pid: 300, bundleID: bundleID, windows: [window(1)]), context: context)
        _ = tracker.ingest(app(window(9), window(3)), context: context)
        let order = tracker.sortedWindows().map(\.window.identity)
        #expect(order == [identity(3), identity(9), identity(1, pid: 300)])
    }

    @Test func aWindowMissingFromAnObservationIsNotClosed() {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(window(7)), context: context)
        #expect(tracker.ingest(app(), context: context).isEmpty)
        #expect(tracker.info(for: identity(7)) != nil)
    }

    @Test func anAppThatStopsBeingTrackedLosesItsWindowsAndTheyComeBackAsNew() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(window(7), window(8)), context: context)
        _ = tracker.ingest(AppObservation(pid: 300, bundleID: bundleID, windows: [window(1)]), context: context)
        // A window still settling is dropped too.
        _ = tracker.ingest(app(window(7), window(8), window(9)), context: ObservationContext(now: .now))
        #expect(tracker.hasPendingWindows(pid: pid))

        let events = tracker.appStopped(pid: pid)
        #expect(events == [.windowDestroyed(WindowRef(identity: identity(7))), .windowDestroyed(WindowRef(identity: identity(8)))])
        #expect(tracker.sortedWindows().map(\.window.identity) == [identity(1, pid: 300)])
        #expect(!tracker.hasPendingWindows(pid: pid))
        #expect(tracker.knownWindowIDs(pid: pid).isEmpty)

        let again = tracker.ingest(app(window(7)), context: context)
        #expect(again == [.windowCreated(try #require(tracker.info(for: identity(7))))])
    }
}

private let synthetic = WindowIdentity.syntheticIDBase | 1
private let real: UInt32 = 42

private func listed(_ id: UInt32, _ source: WindowIDSource, replaces: UInt32? = nil) -> WindowObservation {
    WindowObservation(windowID: id, idSource: source, read: .success(snapshot()), title: "Secret Plan.txt", replacesWindowID: replaces)
}

/// D-15, lead decision 2026-10-25: a fallback ID corrected by the lookup is re-keyed, never closed and reopened.
@Suite struct RekeyTests {
    @Test func aSyntheticWindowIsRekeyedToItsRealIDAndStaysOneWindow() throws {
        var tracker = WindowTracker()
        tracker.setBundleHints([bundleID: Size(width: 200, height: 150)])
        _ = tracker.ingest(app(listed(synthetic, .synthetic)), context: context)
        let before = try #require(tracker.info(for: identity(synthetic)))
        #expect(before.learnedMinimum == Size(width: 200, height: 150))

        let events = tracker.ingest(app(listed(real, .axPrivate, replaces: synthetic)), context: context)
        #expect(tracker.windows.count == 1)
        let after = try #require(tracker.info(for: identity(real)))
        #expect(after.window.creationOrder == before.window.creationOrder)
        #expect(after.window.titleHint == before.window.titleHint)
        #expect(after.idSource == .axPrivate)
        #expect(after.visibleMemberID == real)
        #expect(after.learnedMinimum == Size(width: 200, height: 150))
        #expect(events == [.windowRekeyed(from: before.window, to: after)])
        #expect(tracker.ingest(app(listed(real, .axPrivate)), context: context).isEmpty)
    }

    @Test func aPendingWindowRekeyedMovesSilentlyAndIsReportedOnceAfterItsSettleDelay() throws {
        let start = ContinuousClock.now
        var tracker = WindowTracker()
        #expect(tracker.ingest(app(listed(synthetic, .synthetic)), context: ObservationContext(now: start)).isEmpty)
        #expect(tracker.ingest(app(listed(real, .axPrivate, replaces: synthetic)), context: ObservationContext(now: start + .milliseconds(100))).isEmpty)
        let events = tracker.ingest(app(listed(real, .axPrivate)), context: ObservationContext(now: start + .milliseconds(250)))
        #expect(events == [.windowCreated(try #require(tracker.info(for: identity(real))))])
        #expect(tracker.windows.count == 1)
    }

    @Test func aRekeyOfAnUnknownWindowDoesNothing() {
        var tracker = WindowTracker()
        #expect(tracker.rekey(from: identity(synthetic), to: identity(real)).isEmpty)
        #expect(tracker.windows.isEmpty)
        #expect(!tracker.hasPendingWindows(pid: pid))
    }
}
