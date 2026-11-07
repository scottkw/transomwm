import AppKit
import CoreGraphics
import Foundation
@testable import TransomEngine
@testable import TransomMac
import TransomModel
import TransomPrivate
import Testing

/// A synthetic magnify event (type 29, zoom sub-type) carrying `value`. VM only.
private func magnify(_ phase: Int64, _ value: Double, flags: CGEventFlags) -> (CGPoint) -> CGEvent? {
    { point in
        guard let event = CGEvent(source: nil), let type = CGEventType(rawValue: GestureEventFields.gestureType) else { return nil }
        event.type = type
        event.setIntegerValueField(GestureEventFields.hidType, value: GestureEventFields.hidZoom)
        event.setIntegerValueField(GestureEventFields.phase, value: phase)
        event.setDoubleValueField(GestureEventFields.zoomValue, value: value)
        event.flags = flags
        event.location = point
        return event
    }
}

/// A continuous scroll moving `dx` points horizontally.
private func scroll(_ phase: Int64, dx: Int32, momentum: Int64 = 0, flags: CGEventFlags) -> (CGPoint) -> CGEvent? {
    { point in
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: dx, wheel3: 0) else { return nil }
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        event.flags = flags
        event.location = point
        return event
    }
}

/// Began, ten changes summing to `total` magnification, ended.
private func pinch(_ total: Double, flags: CGEventFlags = .maskAlternate) -> [(CGPoint) -> CGEvent?] {
    [magnify(1, 0, flags: flags)] + Array(repeating: magnify(2, total / 10, flags: flags), count: 10) + [magnify(4, 0, flags: flags)]
}

/// Began, eight changes summing to `total` points on x, ended; optionally momentum 1, 2, 3 with ⌥ released.
private func pan(_ total: Double, momentum: Bool, flags: CGEventFlags = .maskAlternate) -> [(CGPoint) -> CGEvent?] {
    let step = Int32((total / 8).rounded())
    var events = [scroll(1, dx: 0, flags: flags)] + Array(repeating: scroll(2, dx: step, flags: flags), count: 8) + [scroll(4, dx: 0, flags: flags)]
    if momentum { events += [1, 2, 3].map { scroll(0, dx: step, momentum: $0, flags: []) } }
    return events
}

/// Posts `events` at `point` through the HID tap, `gap` apart, then lets them settle; returns how many reached `downstream`.
/// `warp` false: the pointer is already there, and the events go out at once (a gesture during a move).
private func post(
    _ events: [(CGPoint) -> CGEvent?], at point: CGPoint, gap: Duration = .milliseconds(8), warp: Bool = true, downstream: Downstream
) async throws -> Int {
    if warp {
        CGWarpMouseCursorPosition(point)
        try await Task.sleep(for: .milliseconds(300))
    }
    let before = downstream.value
    for make in events {
        make(point)?.post(tap: .cghidEventTap)
        try await Task.sleep(for: gap)
    }
    try await Task.sleep(for: .milliseconds(400))
    return downstream.value - before
}

private func center(_ rect: Rect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

/// Three fixture windows docked on one desk (ZoomSettleIntegrationTests' steps), zoom on, both taps running.
@MainActor private struct Desk {
    let fixture: FixtureProcess
    let arrange: ArrangeController
    let refs: [TransomModel.WindowRef]
    let display: DisplayInfo
    /// Each window's home tile.
    let tiles: [Rect]
    let downstream: Downstream

    var uuid: String { display.uuid }
    var view: ViewTarget { arrange.arranger.view(on: uuid) }
    var visible: Rect { arrange.arranger.displays.first { $0.uuid == uuid }?.visibleFrame ?? display.visibleFrame }

    func listed(_ index: Int) async throws -> Rect? {
        _ = try await fixture.send("list")
        return fixture.windows.first { $0.index == index }?.frame
    }

    func idle() async -> Bool { await waitUntil(timeout: .seconds(3)) { arrange.zoomController?.isIdle ?? true } }

    /// Replaces the refusal announcement and the beep with recorders (UI-SPEC Surface 3: a gesture never beeps).
    func recordFeedback() -> Feedback {
        let feedback = Feedback()
        arrange.gestures.announce = { feedback.announcements.append($0) }
        arrange.beep = { feedback.beeps += 1 }
        return feedback
    }

    func target(_ direction: GestureRecognizer.Direction, at point: CGPoint) -> ViewTarget? {
        guard case .success(let target)? = arrange.arranger.gestureTarget(direction, displayUUID: uuid, pointer: Point(x: point.x, y: point.y))
        else { return nil }
        return target
    }

    /// Zooms to a docked window's leaf that has a horizontal neighbour: fingers left show the area to the right, fingers
    /// right the left.
    func zoomToAViewWithANeighbour() async throws -> (edge: Edge, target: ViewTarget) {
        for ref in refs {
            try await zoom(to: .node(try #require(arrange.arranger.leafNode(of: ref))))
            for edge in [Edge.right, .left] {
                if let target = target(.pan(edge), at: center(visible)) { return (edge, target) }
            }
        }
        throw FixtureError(description: "no docked window has a horizontal neighbour")
    }

    /// Hotkey-style zoom to `target`, waited out.
    func zoom(to target: ViewTarget) async throws {
        await arrange.zoom(to: target, displayUUID: uuid)
        try #require(await idle(), "the stage never revealed")
        try #require(view == target)
    }
}

@MainActor private final class Feedback {
    var announcements: [String] = []
    var beeps = 0
}

@MainActor private func withDesk(_ body: (Desk) async throws -> Void) async throws {
    let fixture = try await FixtureProcess.launch(["standard", "standard", "standard"])
    defer { fixture.terminate() }
    let fixturePID = fixture.pid
    let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
    await system.start()
    let arrange = ArrangeController(system: system, zoomEnabled: true)
    defer {
        arrange.stopTap()
        withExtendedLifetime(arrange) {}
    }
    await arrange.start()
    try #require(arrange.arranger.zoomEnabled)

    var refs: [TransomModel.WindowRef] = []
    for window in fixture.windows.sorted(by: { $0.index < $1.index }) {
        func find() -> TransomModel.WindowRef? {
            arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
        }
        _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
        refs.append(try #require(find(), "window \(window.id) never reached a desk"))
    }
    let key = try #require(arrange.arranger.deskKey(of: refs[0]))
    let display = try #require(Displays.current().first { $0.uuid == key.displayUUID })
    for index in refs.indices { _ = try await fixture.send("resize \(index) 120 120") }
    for (index, ref) in refs.enumerated() {
        try await Task.sleep(for: .milliseconds(500))
        let area = display.visibleFrame
        let x = (area.minX + area.width * 0.9 - 60).rounded(), y = (area.midY - 60).rounded()
        _ = try await fixture.send("move \(index) \(Int(x)) \(Int(y))")
        let moved = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[ref.identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
        }
        try #require(moved, "the Arranger never saw window \(index) at \(x),\(y)")
        await arrange.dispatch(.dock, focused: ref)
        try #require(arrange.arranger.world[key]?.tree.state(of: ref) == .present, "window \(index) did not dock")
    }
    var tiles: [Rect] = []
    let tiled = await waitUntil(timeout: .seconds(3)) {
        tiles = []
        _ = try? await fixture.send("list")
        for index in refs.indices { if let frame = fixture.windows.first(where: { $0.index == index })?.frame { tiles.append(frame) } }
        return tiles.count == 3 && refs.indices.allSatisfy { i in refs.indices.allSatisfy { j in i == j || !tiles[i].overlaps(tiles[j]) } }
    }
    try #require(tiled, "the three fixture windows never tiled: \(tiles)")
    try #require(arrange.startTap())
    try #require(await waitUntil(timeout: .seconds(2)) { arrange.isGestureTapRunning }, "no gesture tap with zoom on")
    let downstream = try Downstream()
    defer { downstream.stop() }
    try await body(Desk(fixture: fixture, arrange: arrange, refs: refs, display: display, tiles: tiles, downstream: downstream))
}

/// GEST-01 / GEST-02 / GEST-03 live (05-04), synthetic gestures in the VM only: a taken gesture follows on the stage and
/// either commits one level through Phase 4's zoomTo, settle and history, or springs back with no settle.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct GestureFollowIntegrationTests {
    /// The window server connection first (ZoomSettleIntegrationTests: `CGS_REQUIRE_INIT`).
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(1)))
    func anOptionPinchInPastHalfZoomsOneLevel() async throws {
        try await withDesk { desk in
            let point = center(desk.tiles[0])
            let expected = try #require(desk.target(.pinchIn, at: point), "no pinch-in target at home")
            #expect(try await post(pinch(1.2), at: point, downstream: desk.downstream) == 0, "pinch events reached the app")
            #expect(await desk.idle(), "the stage never revealed")
            print("pinch in: \(desk.view), last gesture \(String(describing: desk.arrange.gestures.lastGesture))")
            #expect(desk.view == expected)
            guard case .node(let node) = desk.view, let leaf = desk.arrange.arranger.leafNode(of: desk.refs[0]) else {
                Issue.record("not a node view: \(desk.view)")
                return
            }
            let tree = try #require(desk.arrange.arranger.world[ZoomInput.deskKey(desk.display)]?.tree)
            #expect(node == leaf || Navigator.ancestors(of: leaf, in: tree).contains(node), "the view does not contain window 0")
            #expect(desk.arrange.arranger.camera.histories[desk.uuid]?.back.last?.target == .home)
            #expect(desk.arrange.gestures.lastGesture?.outcome == .moved(expected))
            // Window 0 at its frame in the new view's plan (horizontal exact; vertical has the VM's menu bar quirk).
            let plan = try ViewPlanner.plan(
                desk: try #require(desk.arrange.arranger.world[ZoomInput.deskKey(desk.display)]), view: desk.view, area: desk.visible, gap: 8,
                mins: [:])
            let planned = try #require(plan.frames[desk.refs[0]])
            let placed = await waitUntil(timeout: .seconds(2)) {
                guard let frame = try? await desk.listed(0) else { return false }
                return abs(frame.x - planned.x) <= 2 && abs(frame.width - planned.width) <= 2
            }
            let frame = try await desk.listed(0)
            #expect(placed, "window 0 at \(String(describing: frame)), planned \(planned)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func anOptionPinchOutPastHalfGoesHome() async throws {
        try await withDesk { desk in
            let leaf = try #require(desk.arrange.arranger.leafNode(of: desk.refs[0]))
            try await desk.zoom(to: .node(leaf))
            let point = center(desk.visible)
            let expected = try #require(desk.target(.pinchOut, at: point))
            #expect(try await post(pinch(-0.8), at: point, downstream: desk.downstream) == 0)
            #expect(await desk.idle(), "the stage never revealed")
            #expect(desk.view == expected, "pinch out went to \(desk.view), not one level up (\(expected))")
            #expect(desk.arrange.arranger.camera.histories[desk.uuid]?.back.last?.target == .node(leaf))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aShortPinchSpringsBackWithoutASettle() async throws {
        try await withDesk { desk in
            let settled = desk.arrange.zoomController?.lastSettle.map { [$0.ms, $0.windows] }
            // Slow, so the release is no flick either.
            let survived = try await post(pinch(0.2), at: center(desk.tiles[0]), gap: .milliseconds(100), downstream: desk.downstream)
            #expect(survived == 0)
            #expect(await waitUntil(timeout: .seconds(1)) { desk.arrange.zoomController?.isIdle ?? true }, "the stage stayed up")
            #expect(desk.view == .home)
            #expect(desk.arrange.zoomController?.lastSettle.map { [$0.ms, $0.windows] } == settled, "a spring back settled")
            #expect(desk.arrange.gestures.lastGesture?.outcome == .sprangBack)
            #expect(desk.arrange.arranger.camera.histories[desk.uuid]?.back.isEmpty ?? true)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func anOptionPanPastAThirdMovesToTheNeighbour() async throws {
        try await withDesk { desk in
            let (edge, expected) = try await desk.zoomToAViewWithANeighbour()
            let total = (edge == .right ? -0.4 : 0.4) * desk.visible.width
            #expect(try await post(pan(total, momentum: true), at: center(desk.visible), downstream: desk.downstream) == 0)
            #expect(await desk.idle(), "the stage never revealed")
            #expect(desk.view == expected, "pan \(edge) went to \(desk.view), not \(expected)")
            // The momentum tail after the release must not overwrite the outcome.
            #expect(desk.arrange.gestures.lastGesture?.outcome == .moved(expected))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aShortPanSpringsBack() async throws {
        try await withDesk { desk in
            let (edge, _) = try await desk.zoomToAViewWithANeighbour()
            let before = desk.view
            let total = (edge == .right ? -0.1 : 0.1) * desk.visible.width
            let survived = try await post(pan(total, momentum: false), at: center(desk.visible), gap: .milliseconds(100), downstream: desk.downstream)
            #expect(survived == 0)
            #expect(await waitUntil(timeout: .seconds(1)) { desk.arrange.zoomController?.isIdle ?? true }, "the stage stayed up")
            #expect(desk.view == before)
            #expect(desk.arrange.gestures.lastGesture?.outcome == .sprangBack)
        }
    }

    /// GEST-03: no ⌥, the pointer over bare wallpaper. Docked tiles fill the visible frame (08.1.1 D-01), and only fixture
    /// windows may be touched, so it is any bare wallpaper on the display, such as the band behind the Dock.
    @Test(.timeLimit(.minutes(1)))
    func aNoOptionPinchOnWallpaperZooms() async throws {
        try await withDesk { desk in
            let list = try #require(CGWindowList.onScreenFrontToBack())
            let bounds = CGDisplayBounds(CGMainDisplayID())
            let screen = Rect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
            var point: CGPoint?
            for x in stride(from: screen.minX + 8, to: screen.maxX - 8, by: 8) where point == nil {
                for y in stride(from: screen.minY + 8, to: screen.maxY - 8, by: 8) where point == nil {
                    let p = CGPoint(x: x, y: y)
                    if GestureTapRules.surface(at: p, in: list, excludingPID: getpid(), display: bounds) == .wallpaper { point = p }
                }
            }
            let wallpaper = try #require(point, "no bare wallpaper on the display")
            print("wallpaper pinch at \(wallpaper)")
            #expect(try await post(pinch(1.2, flags: []), at: wallpaper, downstream: desk.downstream) == 0)
            #expect(await desk.idle(), "the stage never revealed")
            #expect(desk.view != .home, "a no-⌥ pinch on the wallpaper did not zoom in")
        }
    }

    // MARK: Refused gestures and the one-level clamp (05-05)

    @Test(.timeLimit(.minutes(1)))
    func aPanAtHomeOverscrollsAndSpringsBackSilently() async throws {
        try await withDesk { desk in
            let feedback = desk.recordFeedback()
            let total = -0.2 * desk.visible.width
            let survived = try await post(pan(total, momentum: false), at: center(desk.tiles[0]), gap: .milliseconds(100), downstream: desk.downstream)
            #expect(survived == 0, "pan events reached the app")
            #expect(await desk.idle(), "the stage stayed up")
            #expect(desk.view == .home)
            #expect(feedback.announcements.isEmpty, "a sub-threshold overscroll announced \(feedback.announcements)")
            #expect(feedback.beeps == 0)
            #expect(desk.arrange.gestures.lastGesture?.outcome == .refused(.noArea(.right)))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aDecisivePanAtHomeAnnouncesNoArea() async throws {
        try await withDesk { desk in
            let feedback = desk.recordFeedback()
            let total = -0.5 * desk.visible.width
            let survived = try await post(pan(total, momentum: false), at: center(desk.tiles[0]), downstream: desk.downstream)
            #expect(survived == 0)
            #expect(await desk.idle(), "the stage stayed up")
            #expect(desk.view == .home)
            #expect(feedback.announcements == [Navigator.Refusal.noArea(.right).announcement])
            #expect(feedback.beeps == 0)
            #expect(desk.arrange.gestures.lastGesture?.outcome == .refused(.noArea(.right)))
        }
    }

    /// E-02: Σ +3.0 is two levels of finger spread; the camera still goes exactly one level in.
    @Test(.timeLimit(.minutes(1)))
    func aLongPinchGoesExactlyOneLevel() async throws {
        try await withDesk { desk in
            let point = center(desk.tiles[0])
            let expected = try #require(desk.target(.pinchIn, at: point), "no pinch-in target at home")
            let survived = try await post(pinch(3.0), at: point, downstream: desk.downstream)
            #expect(survived == 0)
            #expect(await desk.idle(), "the stage never revealed")
            #expect(desk.view == expected, "a long pinch went to \(desk.view), not one level in (\(expected))")
            let tree = try #require(desk.arrange.arranger.world[ZoomInput.deskKey(desk.display)]?.tree)
            if case .node(let node) = desk.view { #expect(Navigator.ancestors(of: node, in: tree).count == 2, "not depth 1") }
            #expect(desk.arrange.gestures.lastGesture?.outcome == .moved(expected))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aPinchInOnALeafAnnouncesNothingToZoomIn() async throws {
        try await withDesk { desk in
            let leaf = try #require(desk.arrange.arranger.leafNode(of: desk.refs[0]))
            try await desk.zoom(to: .node(leaf))
            let feedback = desk.recordFeedback()
            let survived = try await post(pinch(1.2), at: center(desk.visible), downstream: desk.downstream)
            #expect(survived == 0)
            #expect(await desk.idle(), "the stage stayed up")
            #expect(desk.view == .node(leaf))
            #expect(feedback.announcements == [Navigator.Refusal.nothingToZoomIn.announcement])
            #expect(feedback.beeps == 0)
            #expect(desk.arrange.gestures.lastGesture?.outcome == .refused(.nothingToZoomIn))
        }
    }

    // MARK: Gestures during a move (E-03) and pick mode (05-05)

    /// From a leaf view, a hotkey Zoom Out One Level is started and a gesture is posted at once, while it is in flight.
    /// Returns the step-out's target and the pinch-in target from it (both read while the move is pending).
    private func stepOutThenPinch(_ desk: Desk, _ total: Double) async throws -> (step: ViewTarget, pinchIn: ViewTarget?, busy: Bool) {
        let leaf = try #require(desk.arrange.arranger.leafNode(of: desk.refs[0]))
        try await desk.zoom(to: .node(leaf))
        let point = center(desk.tiles[0])
        CGWarpMouseCursorPosition(point)
        try await Task.sleep(for: .milliseconds(300))
        await desk.arrange.dispatch(.camera(.stepOut))
        let step = try #require(desk.arrange.arranger.camera.pending[desk.uuid]?.target, "the step-out did not start")
        let pinchIn = desk.target(.pinchIn, at: point)
        let busy = !(desk.arrange.zoomController?.isIdle ?? true)
        let survived = try await post(pinch(total), at: point, warp: false, downstream: desk.downstream)
        #expect(survived == 0, "pinch events reached the app")
        #expect(await desk.idle(), "the stage never revealed")
        return (step, pinchIn, busy)
    }

    @Test(.timeLimit(.minutes(1)))
    func aGestureDuringAHotkeyMoveRetargetsWithoutStranding() async throws {
        try await withDesk { desk in
            let (step, pinchIn, busy) = try await stepOutThenPinch(desk, 1.2)
            let expected = try #require(pinchIn, "no pinch-in target from the step-out's target")
            #expect(busy, "the step-out was not in flight when the gesture began")
            #expect(expected != step)
            #expect(desk.view == expected, "the gesture went to \(desk.view), not one level in from \(step) (\(expected))")
            #expect(desk.arrange.arranger.camera.pending.isEmpty, "a pending move stranded")
            #expect(desk.arrange.gestures.lastGesture?.outcome == .moved(expected))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aSpringBackDuringAMoveLetsThatMoveSettle() async throws {
        try await withDesk { desk in
            let leaf = try #require(desk.arrange.arranger.leafNode(of: desk.refs[0]))
            let (step, _, busy) = try await stepOutThenPinch(desk, 0.1)
            #expect(busy, "the step-out was not in flight when the gesture began")
            #expect(desk.view == step, "the interrupted step-out did not settle: \(desk.view)")
            #expect(desk.arrange.arranger.camera.pending.isEmpty, "a pending move stranded")
            #expect(desk.arrange.arranger.camera.histories[desk.uuid]?.back.last?.target == .node(leaf), "the step-out pushed no history")
            #expect(desk.arrange.gestures.lastGesture?.outcome == .sprangBack)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aGestureEndsPickMode() async throws {
        try await withDesk { desk in
            let leaf = try #require(desk.arrange.arranger.leafNode(of: desk.refs[0]))
            try await desk.zoom(to: .node(leaf))
            CGWarpMouseCursorPosition(center(desk.visible))
            try await Task.sleep(for: .milliseconds(300))
            await desk.arrange.dispatch(.camera(.zoomOutAll))
            #expect(await desk.idle(), "the zoom-out never revealed")
            try #require(await waitUntil(timeout: .seconds(1)) { desk.arrange.isPicking }, "no pick mode after Zoom Out to All Windows")
            let survived = try await post(pinch(0.2), at: center(desk.tiles[0]), gap: .milliseconds(100), downstream: desk.downstream)
            #expect(survived == 0)
            #expect(!desk.arrange.isPicking, "a taken gesture left pick mode on")
            #expect(await desk.idle(), "the stage stayed up")
        }
    }
}
