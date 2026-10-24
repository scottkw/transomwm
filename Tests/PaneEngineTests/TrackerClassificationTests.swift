import Testing
import PaneEngine
import PaneModel

private let pid: Int32 = 100
private let bundleID = "com.example.app"
private let frame = Rect(x: 40, y: 80, width: 320, height: 232)
private let t0 = ContinuousClock.now

private func snapshot(
    role: String = "AXWindow", subrole: String = "AXStandardWindow", minimized: Bool = false,
    fullScreenButton: ButtonFact = .enabled
) -> WindowSnapshot {
    WindowSnapshot(
        role: role, subrole: subrole, modal: false, minimized: minimized, fullScreen: false,
        close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: fullScreenButton, frame: frame
    )
}

private func app(_ id: UInt32, _ snapshot: WindowSnapshot = snapshot(), title: String = "Doc") -> AppObservation {
    AppObservation(pid: pid, bundleID: bundleID, windows: [
        WindowObservation(windowID: id, idSource: .axPrivate, read: .success(snapshot), title: title),
    ])
}

private func at(_ ms: Int, initial: Bool = false, cg: [CGWindowEntry] = []) -> ObservationContext {
    ObservationContext(cgWindows: cg, initialSweep: initial, now: t0 + .milliseconds(ms))
}

private func identity(_ id: UInt32) -> WindowIdentity {
    WindowIdentity(windowID: id, pid: pid, bundleID: bundleID)
}

private func created(_ events: [WindowEvent]) -> [WindowInfo] {
    events.compactMap { if case .windowCreated(let info) = $0 { info } else { nil } }
}

/// A tracker that already reports window 7 as dockable from the initial sweep.
private func trackerWithDockable() -> WindowTracker {
    var tracker = WindowTracker()
    _ = tracker.ingest(app(7), context: at(0, initial: true))
    return tracker
}

@Suite struct TrackerClassificationTests {
    @Test func aNewWindowIsWithheldUntilItHasSettledFor250ms() throws {
        var tracker = WindowTracker()
        #expect(created(tracker.ingest(app(7), context: at(0))).isEmpty)
        #expect(tracker.hasPendingWindows(pid: pid))
        #expect(created(tracker.ingest(app(7), context: at(249))).isEmpty)
        #expect(tracker.hasPendingWindows(pid: pid))
        let reported = created(tracker.ingest(app(7), context: at(250)))
        #expect(reported.map(\.window.identity) == [identity(7)])
        #expect(reported.first?.kind == .dockable)
        #expect(!tracker.hasPendingWindows(pid: pid))
    }

    @Test func aPendingWindowThatDisappearsIsDroppedSilently() {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(7), context: at(0))
        let gone = AppObservation(pid: pid, bundleID: bundleID, windows: [])
        #expect(tracker.ingest(gone, context: at(100)).isEmpty)
        #expect(!tracker.hasPendingWindows(pid: pid))
        #expect(tracker.info(for: identity(7)) == nil)
    }

    @Test func anInitialSweepWindowIsReportedImmediately() {
        var tracker = WindowTracker()
        let reported = created(tracker.ingest(app(7), context: at(0, initial: true)))
        #expect(reported.map(\.window.identity) == [identity(7)])
        #expect(!tracker.hasPendingWindows(pid: pid))
    }

    @Test func aMinimisedDialogSubroleKeepsTheWindowDockable() throws {
        var tracker = trackerWithDockable()
        let events = tracker.ingest(app(7, snapshot(subrole: "AXDialog", minimized: true)), context: at(1000))
        #expect(events == [.windowStateChanged(WindowRef(identity: identity(7)), .absent)])
        #expect(try #require(tracker.info(for: identity(7))).kind == .dockable)
    }

    @Test func aFullscreenButtonTurningDisabledDoesNotDemote() throws {
        var tracker = trackerWithDockable()
        let disabled = ButtonFact(present: true, enabled: false)
        #expect(tracker.ingest(app(7, snapshot(fullScreenButton: disabled)), context: at(1000)).isEmpty)
        #expect(try #require(tracker.info(for: identity(7))).kind == .dockable)
    }

    @Test func aButtonDisabledWhileStillPresentNeverDemotesEvenWithANewTitle() throws {
        var tracker = trackerWithDockable()
        let disabled = ButtonFact(present: true, enabled: false)
        _ = tracker.ingest(app(7, snapshot(fullScreenButton: disabled), title: "Renamed"), context: at(1000))
        #expect(try #require(tracker.info(for: identity(7))).kind == .dockable)
    }

    @Test func aVisibleSubroleChangeToDialogReclassifies() throws {
        var tracker = trackerWithDockable()
        let events = tracker.ingest(app(7, snapshot(subrole: "AXDialog")), context: at(1000))
        let info = try #require(tracker.info(for: identity(7)))
        #expect(info.kind == .neverDock(.subrole))
        #expect(events == [.windowChanged(info)])
    }

    @Test func theCGEntryWithTheSameIDSuppliesTheLayer() throws {
        var tracker = WindowTracker()
        let cg = [
            CGWindowEntry(windowID: 8, pid: pid, bounds: frame, layer: 0, onScreen: true, alpha: 1),
            CGWindowEntry(windowID: 7, pid: pid, bounds: frame, layer: 3, onScreen: true, alpha: 1),
        ]
        _ = tracker.ingest(app(7), context: at(0, initial: true, cg: cg))
        #expect(try #require(tracker.info(for: identity(7))).kind == .neverDock(.floatingLevel))
    }

    @Test func aFirstSightingWhileMinimisedIsReclassifiedWhenReliable() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(7, snapshot(subrole: "AXDialog", minimized: true)), context: at(0, initial: true))
        #expect(try #require(tracker.info(for: identity(7))).kind == .dockable)
        // Restored, it turns out to have no fullscreen button: the provisional kind is replaced.
        _ = tracker.ingest(app(7, snapshot(fullScreenButton: .absent)), context: at(1000))
        #expect(try #require(tracker.info(for: identity(7))).kind == .neverDock(.noFullscreenButton))
    }

    @Test func aScrollAreaNeverBecomesAWindow() {
        var tracker = WindowTracker()
        #expect(tracker.ingest(app(7, snapshot(role: "AXScrollArea")), context: at(0, initial: true)).isEmpty)
        #expect(tracker.ingest(app(7, snapshot(role: "AXScrollArea")), context: at(1000)).isEmpty)
        #expect(tracker.windows.isEmpty)
        #expect(!tracker.hasPendingWindows(pid: pid))
    }
}
