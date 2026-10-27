import Testing
@testable import TransomEngine
import TransomModel

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

private func tab(_ id: UInt32, _ source: WindowIDSource = .axPrivate, tabs: Int = 3, replaces: UInt32? = nil) -> WindowObservation {
    var read = snapshot()
    read.tabGroup = TabGroupFact(tabCount: tabs)
    return WindowObservation(windowID: id, idSource: source, read: .success(read), title: "Secret Plan.txt", replacesWindowID: replaces)
}

private func cg(_ id: UInt32, onScreen: Bool = false, bounds: Rect = frame) -> CGWindowEntry {
    CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: 0, onScreen: onScreen, alpha: 1)
}

private func sweep(_ cgWindows: [CGWindowEntry]) -> ObservationContext {
    ObservationContext(cgWindows: cgWindows, initialSweep: true, now: .now)
}

/// D-08, D-15, lead decision 2026-10-25: a re-key never loses a tab group, a learned minimum or a window.
@Suite struct RekeyGroupTests {
    @Test func aTabGroupLedByASyntheticIDKeepsItsTabsUnderTheRealID() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(tab(synthetic, .synthetic)), context: sweep([cg(synthetic, onScreen: true), cg(11), cg(12)]))
        let before = try #require(tracker.info(for: identity(synthetic)))
        #expect(before.tabCount == 3)

        let events = tracker.ingest(app(tab(real, replaces: synthetic)), context: sweep([cg(real, onScreen: true), cg(11), cg(12)]))
        let after = try #require(tracker.info(for: identity(real)))
        #expect(events == [.windowRekeyed(from: before.window, to: after)])
        #expect(tracker.windows.count == 1)
        #expect(after.tabCount == 3)
        #expect(after.visibleMemberID == real)

        // A tab switch is a focus change of the same window, never a new one.
        let switched = tracker.ingest(app(tab(11)), context: sweep([cg(real), cg(11, onScreen: true), cg(12)]))
        #expect(switched == [.windowFocused(after.window)])
        #expect(tracker.info(for: identity(real))?.visibleMemberID == 11)
        #expect(tracker.info(for: identity(real))?.tabCount == 3)
    }

    @Test func aShownTabRekeyedInsideAGroupKeepsTheGroupsIdentity() throws {
        var tracker = WindowTracker()
        _ = tracker.ingest(app(tab(10)), context: sweep([cg(10, onScreen: true), cg(synthetic), cg(12)]))
        _ = tracker.ingest(app(tab(synthetic, .synthetic)), context: sweep([cg(10), cg(synthetic, onScreen: true), cg(12)]))
        #expect(tracker.info(for: identity(10))?.visibleMemberID == synthetic)

        let events = tracker.ingest(app(tab(real, replaces: synthetic)), context: sweep([cg(10), cg(real, onScreen: true), cg(12)]))
        #expect(events.count == 1)
        guard case .windowChanged(let changed) = events.first else {
            Issue.record("expected one windowChanged, got \(events)")
            return
        }
        #expect(changed.window.identity == identity(10))
        #expect(changed.visibleMemberID == real)
        #expect(tracker.windows.count == 1)

        // The group holds the new ID in place of the old one: switching back is a focus change with three tabs.
        let back = tracker.ingest(app(tab(10)), context: sweep([cg(10, onScreen: true), cg(real), cg(12)]))
        #expect(back == [.windowFocused(WindowRef(identity: identity(10)))])
        #expect(tracker.info(for: identity(10))?.tabCount == 3)
    }

    @Test func aWindowTrackedUnderBothIDsMergesIntoOne() throws {
        let start = ContinuousClock.now
        var tracker = WindowTracker()
        let wide = Rect(x: 40, y: 80, width: 300, height: 120)
        let tall = Rect(x: 400, y: 80, width: 210, height: 400)
        func at(_ frame: Rect, _ id: UInt32, _ source: WindowIDSource) -> WindowObservation {
            WindowObservation(windowID: id, idSource: source, read: .success(snapshot(frame: frame)), title: "Secret Plan.txt")
        }
        // Both open larger, so each refused write moves its window (MinimumSizeLearner learns only from a move).
        let opened = (Rect(x: 40, y: 80, width: 500, height: 120), Rect(x: 400, y: 80, width: 210, height: 600))
        _ = tracker.ingest(app(at(opened.0, synthetic, .synthetic), at(opened.1, real, .axPrivate)), context: ObservationContext(initialSweep: true, now: start))
        let duplicate = try #require(tracker.info(for: identity(synthetic)))
        let kept = try #require(tracker.info(for: identity(real)))
        #expect(duplicate.window.creationOrder < kept.window.creationOrder)
        // Each learns a minimum on a different axis.
        _ = tracker.applyFrameResult(FrameWriteResult(window: duplicate.window, requested: Rect(x: 40, y: 80, width: 100, height: 100), actual: wide, failure: nil), at: start)
        _ = tracker.applyFrameResult(FrameWriteResult(window: kept.window, requested: Rect(x: 400, y: 80, width: 200, height: 100), actual: tall, failure: nil), at: start)
        _ = tracker.ingest(app(at(wide, synthetic, .synthetic), at(tall, real, .axPrivate)), context: ObservationContext(now: start + .seconds(1)))
        #expect(tracker.info(for: identity(synthetic))?.learnedMinimum == Size(width: 300, height: 0))
        #expect(tracker.info(for: identity(real))?.learnedMinimum == Size(width: 0, height: 400))

        let events = tracker.rekey(from: identity(synthetic), to: identity(real))
        let merged = try #require(tracker.info(for: identity(real)))
        #expect(events == [.windowRekeyed(from: duplicate.window, to: merged)])
        #expect(tracker.windows.count == 1)
        #expect(merged.window.creationOrder == duplicate.window.creationOrder)
        #expect(merged.learnedMinimum == Size(width: 300, height: 400))
        #expect(merged.frame == tall)
    }

    @Test func aWrongFrameMatchToACrossSpaceTwinIsCorrectedAndTheTwinTrackedOnItsOwn() throws {
        let start = ContinuousClock.now
        var tracker = WindowTracker()
        let twin: UInt32 = 30
        let own: UInt32 = 31
        _ = tracker.ingest(app(listed(twin, .cgFrameMatch)), context: ObservationContext(cgWindows: [cg(twin, onScreen: true)], initialSweep: true, now: start))
        let wrong = try #require(tracker.info(for: identity(twin)))

        let cgList = [cg(own, onScreen: true), cg(twin)]
        let first = tracker.ingest(
            app(listed(own, .axPrivate, replaces: twin), listed(twin, .axPrivate)), context: ObservationContext(cgWindows: cgList, now: start + .milliseconds(10)))
        let corrected = try #require(tracker.info(for: identity(own)))
        #expect(first == [.windowRekeyed(from: wrong.window, to: corrected)])
        let settled = tracker.ingest(
            app(listed(own, .axPrivate), listed(twin, .axPrivate)), context: ObservationContext(cgWindows: cgList, now: start + .milliseconds(300)))
        #expect(settled == [.windowCreated(try #require(tracker.info(for: identity(twin))))])
        #expect(tracker.sortedWindows().map(\.window.windowID) == [twin, own])
        #expect(corrected.window.creationOrder == wrong.window.creationOrder)

        // The twin's own close is decided on the twin alone.
        let closed = tracker.ingest(
            app(listed(own, .axPrivate), WindowObservation(windowID: twin, idSource: .axPrivate, read: .failure(.invalidElement), title: "", listedInAXWindows: false)),
            context: ObservationContext(cgWindows: [cg(own, onScreen: true)], now: start + .milliseconds(400)))
        #expect(closed == [.windowDestroyed(WindowRef(identity: identity(twin)))])
        #expect(tracker.info(for: identity(own)) != nil)
    }
}
