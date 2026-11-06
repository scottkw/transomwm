import AppKit
import CoreGraphics
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// TILE-23 on real windows, through the same command every route sends. VM only: it moves windows.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "moves real windows; VM only"))
@MainActor struct FourthsIntegrationTests {
    /// Connects to the window server first, as ZoomSettleIntegrationTests does.
    init() { _ = NSApplication.shared }

    /// WR-06, UI-SPEC Surface 3: the Arranger sends guides only when their bands change, so a rebuild of the panels mid-drag
    /// has to keep them "until ⌃ is released or the drag ends".
    @Test(.timeLimit(.minutes(1)))
    func theGuidesSurviveAPanelRebuild() async throws {
        let presenter = PreviewPresenter()
        let display = try #require(Displays.current().first)
        let bands = FourthZones.bands(in: display.visibleFrame, axis: .horizontal)
        presenter.showFourthGuides(bands, on: display.uuid)
        #expect(presenter.fourthGuideRects(on: display.uuid) == bands)

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(300))

        #expect(presenter.fourthGuideRects(on: display.uuid) == bands, "the rebuild dropped the guides")
        #expect(presenter.isPanelVisible(on: display.uuid), "the rebuilt panel is not ordered in")

        presenter.showFourthGuides([], on: display.uuid)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!presenter.isPanelVisible(on: display.uuid), "the panel outlived its guides")
    }

    @Test(.timeLimit(.minutes(1)))
    func theCommandDocksAFloatingWindowAsTheFirstColumn() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await LiveArrange.start(fixture)
        defer { withExtendedLifetime(arrange) {} }
        let ref = try #require(refs.first)

        await arrange.dispatch(.dockFourth(.first, .horizontal), focused: ref)

        let key = try #require(arrange.arranger.deskKey(of: ref))
        let desk = try #require(arrange.arranger.world[key])
        let root = try #require(desk.tree.root)
        guard case let .split(axis, _, weights)? = desk.tree.node(root) else {
            Issue.record("the root is not a split: \(desk.tree)")
            return
        }
        #expect(axis == .horizontal)
        #expect(weights.count == 2)
        #expect(abs(weights[0] - 0.25) <= 1e-9 && abs(weights[1] - 0.75) <= 1e-9, "root weights \(weights)")
        let visible = try LiveArrange.visibleFrame()
        let planned = try #require(try Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames[ref])
        let settled = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, 0) else { return false }
            return LiveArrange.near(now, planned)
        }
        #expect(settled, "the window never reached \(planned)")
    }

    /// 08.1.1 D-10: a half takes the fourth path on a real window. No weight check: until 08.1.1-09 a Desktop tile still
    /// shares the desk, so only the window's place at the left edge holds before and after.
    @Test(.timeLimit(.minutes(1)))
    func aHalfCommandDocksAFloatingWindowAtTheLeftEdge() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await LiveArrange.start(fixture)
        defer { withExtendedLifetime(arrange) {} }
        let ref = try #require(refs.first)

        await arrange.dispatch(.dockFourth(.firstHalf, .horizontal), focused: ref)

        let key = try #require(arrange.arranger.deskKey(of: ref))
        let desk = try #require(arrange.arranger.world[key])
        #expect(desk.tree.state(of: ref) != nil, "the window is not docked")
        let visible = try LiveArrange.visibleFrame()
        let frames = try Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames
        let planned = try #require(frames[ref])
        #expect(frames.values.allSatisfy { planned.minX <= $0.minX }, "not the leftmost: \(frames)")
        let settled = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, 0) else { return false }
            return LiveArrange.near(now, planned)
        }
        #expect(settled, "the window never reached \(planned)")
    }

    /// ⌃ pressed during a real title-bar drag docks to the column under the pointer (D-18).
    @Test(
        .timeLimit(.minutes(1)),
        .enabled(if: ProcessInfo.processInfo.environment["TRANSOM_LIVE_DRAG"] == "1", "posts synthetic drags; set TRANSOM_LIVE_DRAG=1"))
    func aControlDragDocksToTheColumnUnderThePointer() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await LiveArrange.start(fixture)
        defer { withExtendedLifetime(arrange) {} }
        let ref = try #require(refs.first)
        let visible = try LiveArrange.visibleFrame()
        let size = try #require(fixture.windows.first).frame.size
        let x = (visible.midX - size.width / 2).rounded(), y = (visible.midY - size.height / 2).rounded()
        _ = try await fixture.send("move 0 \(Int(x)) \(Int(y))")
        let seen = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[ref.identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
        }
        try #require(seen, "the Arranger never saw the window move")
        try await Task.sleep(for: .milliseconds(300))  // the fixture activates itself
        let frame = try #require(try await LiveArrange.frame(fixture, 0))
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }

        let drag = PostedDrag()
        defer { drag.finish() }
        let grab = try LiveArrange.titleBar(of: ref.windowID, frame: frame)
        try await drag.press(at: grab)
        try await drag.move(to: CGPoint(x: grab.x + 40, y: grab.y + 20))
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.isDragging }, "the press was never a move")
        try await drag.hold(.control)
        let uuid = try #require(Displays.current().first).uuid
        try await drag.move(to: CGPoint(x: visible.minX + visible.width / 8, y: visible.midY))
        try await Task.sleep(for: .milliseconds(300))  // past the dwell
        let guides = arrange.previews?.fourthGuideRects(on: uuid) ?? []
        #expect(guides.count == 5, "guides \(guides)")
        try await drag.move(to: CGPoint(x: visible.minX + visible.width * 7 / 8, y: visible.midY))
        try await Task.sleep(for: .milliseconds(300))
        #expect(arrange.previews?.fourthGuideRects(on: uuid) == guides, "the guides moved with the pointer")
        guard case .fourth(_, let label)? = arrange.arranger.drag?.shown else {
            Issue.record("no fourth preview after the dwell: \(String(describing: arrange.arranger.drag?.shown))")
            return
        }
        #expect(label == "4th column")

        drag.release()
        try await drag.letGo(.control)
        try await Task.sleep(for: .milliseconds(300))
        #expect(arrange.previews?.fourthGuideRects(on: uuid) == [], "the guides outlived the drag")
        #expect(arrange.previews?.isPanelVisible(on: uuid) == false, "the panel is still ordered in")

        let docked = await waitUntil(timeout: .seconds(3)) { !arrange.arranger.isFloating(ref) }
        try #require(docked, "the release did not dock the window")
        let key = try #require(arrange.arranger.deskKey(of: ref))
        let desk = try #require(arrange.arranger.world[key])
        guard case let .split(axis, _, weights)? = desk.tree.node(try #require(desk.tree.root)) else {
            Issue.record("the root is not a split: \(desk.tree)")
            return
        }
        #expect(axis == .horizontal)
        #expect(abs((weights.last ?? 0) - 0.25) <= 1e-9, "root weights \(weights)")
        let planned = try #require(try Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames[ref])
        let settled = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, 0) else { return false }
            return LiveArrange.near(now, planned)
        }
        #expect(settled, "the window never reached \(planned)")
    }

    /// ⌃ then ⌘ during a real drag turns the guides from columns to rows, and the narrow 2nd band is reachable and docks (D-18).
    @Test(
        .timeLimit(.minutes(1)),
        .enabled(if: ProcessInfo.processInfo.environment["TRANSOM_LIVE_DRAG"] == "1", "posts synthetic drags; set TRANSOM_LIVE_DRAG=1"))
    func aControlCommandDragDocksToTheRowUnderThePointer() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, ref, frame) = try await Self.centredWindow(fixture)
        defer { withExtendedLifetime(arrange) {} }
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }
        let display = try #require(arrange.arranger.displays.first)
        let visible = display.visibleFrame

        let drag = PostedDrag()
        defer { drag.finish() }
        let grab = try LiveArrange.titleBar(of: ref.windowID, frame: frame)
        try await drag.press(at: grab)
        try await drag.move(to: CGPoint(x: grab.x + 40, y: grab.y + 20))
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.isDragging }, "the press was never a move")
        try await drag.hold(.control)
        try await drag.move(to: CGPoint(x: visible.minX + visible.width / 8, y: visible.midY))
        try await Task.sleep(for: .milliseconds(300))  // past the dwell
        #expect(arrange.previews?.fourthGuideRects(on: display.uuid) == FourthZones.bands(in: visible, axis: .horizontal), "⌃ shows the columns")

        try await drag.hold(.command)
        // The middle of the 2nd band, 12.5 percent of the height and the narrowest there is.
        try await drag.move(to: CGPoint(x: visible.midX, y: visible.minY + visible.height * 0.3125))
        try await Task.sleep(for: .milliseconds(300))
        #expect(arrange.previews?.fourthGuideRects(on: display.uuid) == FourthZones.bands(in: visible, axis: .vertical), "⌃⌘ shows the rows")
        guard case .fourth(_, let label)? = arrange.arranger.drag?.shown else {
            Issue.record("no fourth preview after the dwell: \(String(describing: arrange.arranger.drag?.shown))")
            return
        }
        #expect(label == "Top half")  // alone with the Desktop tile, the window grows into the empty side (D-14, D-23)

        drag.release()
        try await drag.letGo(.command, .control)
        try await Task.sleep(for: .milliseconds(300))
        #expect(arrange.previews?.fourthGuideRects(on: display.uuid) == [], "the guides outlived the drag")

        try #require(await waitUntil(timeout: .seconds(3)) { !arrange.arranger.isFloating(ref) }, "the release did not dock the window")
        let key = try #require(arrange.arranger.deskKey(of: ref))
        let desk = try #require(arrange.arranger.world[key])
        guard case let .split(axis, _, _)? = desk.tree.node(try #require(desk.tree.root)) else {
            Issue.record("the root is not a split: \(desk.tree)")
            return
        }
        #expect(axis == .vertical)
        let planned = try #require(try Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames[ref])
        let settled = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, 0) else { return false }
            return LiveArrange.near(now, planned)
        }
        #expect(settled, "the window never reached \(planned)")
    }

    /// In Automatically mode ⌃⌥ is a ⌃ drag: Transom ignores ⌥, and the tap keeps it from macOS once ⌃ is down (D-07a, 08.1-01).
    @Test(
        .timeLimit(.minutes(1)),
        .enabled(if: ProcessInfo.processInfo.environment["TRANSOM_LIVE_DRAG"] == "1", "posts synthetic drags; set TRANSOM_LIVE_DRAG=1"))
    func optionWithControlChangesNothingInAutomaticMode() async throws {
        // Means nothing unless macOS's ⌥ tiling is on. Read only: nothing here writes the setting.
        let tiling = CFPreferencesCopyAppValue("EnableTilingOptionAccelerator" as CFString, ConflictPolicy.domain as CFString)
        try #require(tiling == nil || (tiling as? Bool) == true, "EnableTilingOptionAccelerator is off in this guest")
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, ref, frame) = try await Self.centredWindow(fixture)
        defer { withExtendedLifetime(arrange) {} }
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }
        let visible = try #require(arrange.arranger.displays.first).visibleFrame

        let drag = PostedDrag()
        defer { drag.finish() }
        var guideSeen = false
        let sample = { guideSeen = guideSeen || MacOSGuide.isOnScreen() }
        let grab = try LiveArrange.titleBar(of: ref.windowID, frame: frame)
        try await drag.press(at: grab)
        try await drag.move(to: CGPoint(x: grab.x + 40, y: grab.y + 20), each: sample)
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.dragOptionStrip == .withControl }, "the press was never a move")
        try await drag.hold(.control)
        try await drag.move(to: CGPoint(x: grab.x + 60, y: grab.y + 30), steps: 3, each: sample)
        try await drag.hold(.option)
        try await drag.move(to: CGPoint(x: visible.minX + visible.width / 8, y: visible.midY), each: sample)
        for _ in 0..<15 {  // 300 ms at rest, past the dwell
            try await Task.sleep(for: .milliseconds(20))
            sample()
        }
        #expect(!guideSeen, "macOS drew its Drag Guide Window during a ⌃⌥ drag")
        guard case .fourth(_, let label)? = arrange.arranger.drag?.shown else {
            Issue.record("no fourth preview after the dwell: \(String(describing: arrange.arranger.drag?.shown))")
            return
        }
        #expect(label == "1st column")

        drag.release()
        try await drag.letGo(.option, .control)
        try #require(await waitUntil(timeout: .seconds(3)) { !arrange.arranger.isFloating(ref) }, "the release did not dock the window")
        let desk = try #require(arrange.arranger.deskKey(of: ref).flatMap { arrange.arranger.world[$0] })
        guard case let .split(axis, _, weights)? = desk.tree.node(try #require(desk.tree.root)) else {
            Issue.record("the root is not a split: \(desk.tree)")
            return
        }
        #expect(axis == .horizontal)
        #expect(abs((weights.first ?? 0) - 0.25) <= 1e-9, "root weights \(weights)")
    }

    /// A fourth for a window the view has parked widens the camera to show it, in its tile at desk level (D-16, UI-SPEC Surface 3).
    @Test(.timeLimit(.minutes(1)))
    func aFourthWhileZoomedInLandsWhereThePreviewSaid() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.start()
        try #require(arrange.arranger.zoomEnabled)

        var refs: [TransomModel.WindowRef] = []
        for window in fixture.windows {
            func find() -> TransomModel.WindowRef? {
                arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
            }
            _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
            refs.append(try #require(find(), "window \(window.id) never reached a desk"))
        }
        let display = try #require(Displays.current().first)
        let key = try #require(arrange.arranger.deskKey(of: refs[0]))
        func visible() -> Rect { arrange.arranger.displays.first { $0.uuid == display.uuid }?.visibleFrame ?? display.visibleFrame }

        // Small windows docking from the Desktop tile's right edge band, as ZoomSettleIntegrationTests does.
        for index in refs.indices { _ = try await fixture.send("resize \(index) 120 120") }
        for (index, ref) in refs.enumerated() {
            try await Task.sleep(for: .milliseconds(500))  // earlier docks' writes and clamps land first
            let desk = try #require(arrange.arranger.world[key])
            let desktop = try #require(try Planner.plan(desk: desk, area: display.visibleFrame, gap: 8, mins: [:]).desktopRect)
            let x = (desktop.minX + desktop.width * 0.8 - 60).rounded(), y = (desktop.midY - 60).rounded()
            _ = try await fixture.send("move \(index) \(Int(x)) \(Int(y))")
            let moved = await waitUntil(timeout: .seconds(2)) {
                arrange.arranger.windows[ref.identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
            }
            try #require(moved, "the Arranger never saw window \(index) at \(x),\(y)")
            await arrange.dispatch(.dock, focused: ref)
            try #require(arrange.arranger.world[key]?.tree.state(of: ref) == .present, "window \(index) did not dock")
        }
        try await Task.sleep(for: .seconds(1))

        await arrange.zoom(to: .node(try #require(arrange.arranger.leafNode(of: refs[0]))), displayUUID: display.uuid)
        let parked = await waitUntil(timeout: .seconds(3)) {
            guard let other = try? await LiveArrange.frame(fixture, 1) else { return false }
            return Recovery.isStranded(other, displays: [display]) && arrange.zoomController?.isIdle == true
        }
        try #require(parked, "window 1 was never outside the view")

        await arrange.dispatch(.dockFourth(.first, .horizontal), focused: refs[1])

        let desk = try #require(arrange.arranger.world[key])
        let planned = try #require(try Planner.plan(desk: desk, area: visible(), gap: arrange.arranger.gap, mins: [:]).frames[refs[1]])
        // Horizontal geometry is exact and vertical is loose: ZoomSettleIntegrationTests explains the VM's menu bar.
        var last: Rect?, zoomedWindow: Rect?
        let landed = await waitUntil(timeout: .seconds(5)) {
            guard arrange.zoomController?.isIdle == true, let now = try? await LiveArrange.frame(fixture, 1) else { return false }
            last = now
            zoomedWindow = try? await LiveArrange.frame(fixture, 0)
            return abs(now.x - planned.x) <= 2 && abs(now.width - planned.width) <= 2 && now.minY >= visible().minY - 2 && now.maxY <= visible().maxY + 32
        }
        #expect(landed, "the window is at \(String(describing: last)), its desk-level frame is \(planned)")
        // The camera widened to hold both, rather than jumping away from what was in view.
        let kept = try #require(zoomedWindow, "window 0 has no frame")
        #expect(!Recovery.isStranded(kept, displays: [display]), "the window that was in view is now parked at \(kept)")
    }

    // MARK: Helpers

    /// One fixture window, floating in the middle of the main display, with a controller tracking it.
    private static func centredWindow(_ fixture: FixtureProcess) async throws -> (ArrangeController, TransomModel.WindowRef, Rect) {
        let (arrange, refs) = try await LiveArrange.start(fixture)
        let ref = try #require(refs.first)
        let visible = try LiveArrange.visibleFrame()
        let size = try #require(fixture.windows.first).frame.size
        let x = (visible.midX - size.width / 2).rounded(), y = (visible.midY - size.height / 2).rounded()
        _ = try await fixture.send("move 0 \(Int(x)) \(Int(y))")
        let seen = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[ref.identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
        }
        try #require(seen, "the Arranger never saw the window move")
        try await Task.sleep(for: .milliseconds(300))  // the fixture activates itself
        return (arrange, ref, try #require(try await LiveArrange.frame(fixture, 0)))
    }
}
