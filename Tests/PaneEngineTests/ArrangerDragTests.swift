import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let dragPID: Int32 = 900
private let dragBundle = "com.example.arranger"
private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainKey = DeskKey(displayUUID: "main", spaceID: nil)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: dragPID, bundleID: dragBundle))
}

private let f = window(2)
/// f floats in the middle of the main display.
private let floatingFrame = Rect(x: 600, y: 300, width: 400, height: 300)

private func shifted(_ rect: Rect, _ dx: Double, _ dy: Double = 0) -> Rect {
    Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
}

private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press))
}

/// Whether any `.perform` in `effects` names `window`.
private func writes(_ effects: [ArrangerEffect], _ window: WindowRef) -> Bool {
    effects.contains { effect in
        guard case .perform(let commands) = effect else { return false }
        return commands.contains { command in
            switch command {
            case .setFrame(let w, _), .park(let w, _), .focus(let w), .raise(let w), .setHidden(let w, _): w == window
            }
        }
    }
}

/// The frame a dry run of `target` gives `window` on the main desk: out of its tree or Desktop layer, `applyDrop`, plan.
private func dryRun(_ arranger: Arranger, _ window: WindowRef, _ target: DropTarget, mins: [WindowRef: Size] = [:]) throws -> Rect? {
    var desk = try #require(arranger.world[mainKey])
    var ids = arranger.world.ids
    if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
    try desk.tree.applyDrop(target, window: window, ids: &ids)
    return try Planner.plan(desk: desk, area: area, gap: 8, mins: mins).frames[window]
}

/// Presses f's title bar at (800, 310), then drags 10 pt (the session starts) and on to (x, y), the frame following.
private func dragFloating(_ harness: inout Harness, to x: Double, _ y: Double, _ modifiers: Modifiers = []) async -> [ArrangerEffect] {
    var effects = await harness.send(pointer(.down, 800, 310, modifiers, press: f))
    effects += await harness.send(pointer(.dragged, 790, 310, modifiers))
    effects += await harness.send(.dragFrame(f.identity, shifted(floatingFrame, -10)))
    effects += await harness.send(pointer(.dragged, x, y, modifiers))
    effects += await harness.send(.dragFrame(f.identity, shifted(floatingFrame, x - 800, y - 310)))
    return effects
}

/// TILE-01, D-01, D-23 and the echo rule through the pure Arranger and the fake (RESEARCH Pattern 4).
@Suite struct ArrangerDragTests {
    @Test func aFloatingWindowHeldInTheLeftEdgeBandDocksAtThePreviewedFrame() async throws {
        var harness = await Harness.started(frames: [2: floatingFrame])
        var during = await dragFloating(&harness, to: 10, 310)
        #expect(during.contains(.pollDragFrame(f)), "no frame poll at the session start")
        #expect(harness.arranger.isDragging)

        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        during += tick
        let r = try #require(try dryRun(harness.arranger, f, .layoutEdge(.left)))
        #expect(tick.contains(.preview(.dock(r), displayUUID: "main")), "tick gave \(tick)")
        #expect(!writes(during, f), "the dragged window was written before mouse-up")

        let depth = harness.arranger.history.depth(for: mainKey)
        let up = await harness.send(pointer(.up, 10, 310))
        #expect(setFrames(up)[f] == r)
        #expect(up.contains(.preview(nil, displayUUID: "main")))
        #expect(up.contains(.pollDragFrame(nil)))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        #expect(harness.arranger.world[mainKey]?.tree.state(of: f) == .present)
        #expect(await harness.frame(f) == r)
        #expect(!harness.arranger.isDragging)
    }

    @Test func aReleaseInsideTheDwellIsAPlainMove() async throws {
        var harness = await Harness.started(frames: [2: floatingFrame])
        let during = await dragFloating(&harness, to: 10, 310)
        harness.now += .milliseconds(100)
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, 10, 310))

        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.windows.isEmpty, "a release with no preview docked the window")
        #expect(desk.desktop.frame(of: f) == shifted(floatingFrame, -790))
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(!up.contains { if case .preview(.some, _) = $0 { true } else { false } })
        #expect(!writes(during + up, f))
        #expect(up.contains(.pollDragFrame(nil)))
    }

    @Test func aClickWithoutTravelStartsNoPollAndChangesNothing() async throws {
        var harness = await Harness.started(frames: [2: floatingFrame])
        let world = harness.arranger.world
        var effects = await harness.send(pointer(.down, 800, 310, press: f))
        effects += await harness.send(pointer(.dragged, 801, 310))
        effects += await harness.send(pointer(.up, 801, 310))
        #expect(!effects.contains(.pollDragFrame(f)))
        #expect(harness.arranger.world == world)
        #expect(!harness.arranger.isDragging)
    }
}
