@testable import TransomEngine
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainKey = DeskKey(displayUUID: "main", spaceID: nil)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 900, bundleID: "com.example.arranger"))
}

private let a = window(1), f = window(2)
private let floatingFrame = Rect(x: 600, y: 300, width: 400, height: 300)
/// Wider than the whole display: f never fits a tile.
private let huge = Size(width: 1500, height: 100)

private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press))
}

private func shifted(_ rect: Rect, _ dx: Double, _ dy: Double = 0) -> Rect {
    Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
}

/// An Arranger fed `infos` on the main display, with zoom on or off.
private func bare(_ infos: [WindowInfo], zoom: Bool) -> Arranger {
    var arranger = Arranger()
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
    if zoom { _ = arranger.handle(.zoomEnabled(true), now: .now) }
    return arranger
}

/// Drags `window` by its title bar to `point` and holds it past the dwell; returns the tick's effects.
private func hold(_ arranger: inout Arranger, _ window: WindowRef, from frame: Rect, at point: Point, start: ContinuousClock.Instant) -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    _ = arranger.handle(pointer(.down, grab.x, grab.y, press: window), now: start)
    _ = arranger.handle(pointer(.dragged, grab.x + 10, grab.y), now: start)
    _ = arranger.handle(.dragFrame(window.identity, shifted(frame, 10)), now: start)
    _ = arranger.handle(pointer(.dragged, point.x, point.y), now: start)
    _ = arranger.handle(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)), now: start)
    return arranger.handle(.tick, now: start + .milliseconds(150))
}

/// f dropped on the left edge band of an empty desk and released.
private func dropF(_ arranger: inout Arranger) -> (tick: [ArrangerEffect], up: [ArrangerEffect]) {
    let start = ContinuousClock.now
    let tick = hold(&arranger, f, from: floatingFrame, at: Point(x: 10, y: 310), start: start)
    let up = arranger.handle(pointer(.up, 10, 310), now: start + .milliseconds(200))
    return (tick, up)
}

/// f's frame on the main desk with every minimum ignored: [f | Desktop].
private func loose(_ arranger: Arranger) throws -> Rect {
    let desk = try #require(arranger.world[mainKey])
    return try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[f])
}

private func previews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    effects.compactMap { if case .preview(let state?, _) = $0 { state } else { nil } }
}

private func blocks(_ effects: [ArrangerEffect]) -> [[CollapsedBlock]] {
    effects.compactMap { if case .collapsedBlocks(let blocks, _) = $0 { blocks } else { nil } }
}

private func parks(_ effects: [ArrangerEffect]) -> [WindowCommand] {
    effects.flatMap { effect -> [WindowCommand] in
        guard case .perform(let commands) = effect else { return [] }
        return commands.filter { if case .park = $0 { true } else { false } }
    }
}

private func moves(_ effects: [ArrangerEffect]) -> [CameraMove] {
    effects.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }
}

/// ZOOM-13, D-A, CONTEXT E: with zoom on, a drop that does not fit is accepted and the windows that lose room become
/// collapsed blocks in their tiles; with zoom off Phase 3's refusal stands.
@Suite struct ArrangerCollapseTests {
    @Test func anOversizedDropIsAcceptedWithZoomOn() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        let (tick, up) = dropF(&arranger)

        #expect(!previews(tick).contains { if case .blocked = $0 { true } else { false } }, "tick gave \(tick)")
        #expect(!up.contains(.announce(Arranger.noRoom)))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.state(of: f) == .present, "the drop was refused")
        #expect(arranger.camera.collapsible == [f.identity])
        let save = try #require(up.firstIndex(of: .save(.now)), "no immediate save before the park")
        let park = try #require(up.firstIndex { parks([$0]).contains(.park(f, displayUUID: "main")) }, "f was not parked: \(up)")
        #expect(save < park)
        #expect(up.contains(.collapsedBlocks([CollapsedBlock(window: f, rect: try loose(arranger))], displayUUID: "main")), "got \(up)")
    }

    @Test func theSameDropIsRefusedWithZoomOff() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: false)
        let (tick, up) = dropF(&arranger)

        #expect(previews(tick).contains { if case .blocked = $0 { true } else { false } }, "tick gave \(tick)")
        #expect(up.contains(.announce(Arranger.noRoom)))
        #expect(arranger.world[mainKey]?.tree.windows.isEmpty == true)
        #expect(arranger.camera.collapsible.isEmpty)
        #expect(blocks(up).isEmpty)
    }

    @Test func collapsedBlocksAreSentOnlyWhenTheyChange() throws {
        let infos = [info(2, frame: floatingFrame, minimum: huge)]
        var arranger = bare(infos, zoom: true)
        let (_, up) = dropF(&arranger)
        #expect(blocks(up).count == 1)

        let again = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
        #expect(blocks(again).isEmpty, "unchanged blocks were sent again: \(again)")

        let closed = arranger.handle(.event(.windowDestroyed(f)), now: .now)
        #expect(closed.contains(.collapsedBlocks([], displayUUID: "main")), "got \(closed)")
        #expect(arranger.camera.collapsible.isEmpty, "a closed window stayed collapsible")
    }

    @Test func anOSCausedLossOfRoomStillFloats() throws {
        var arranger = bare([info(1, frame: floatingFrame)], zoom: true)
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        #expect(arranger.world[mainKey]?.tree.state(of: a) == .present)

        let grown = [info(1, frame: floatingFrame, minimum: huge)]
        let effects = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: grown, initialRefreshComplete: true)), now: .now)

        #expect(effects.contains(.notice(.lostRoom([a]))), "got \(effects)")
        #expect(arranger.world[mainKey]?.desktop.contains(a) == true)
        #expect(arranger.camera.collapsible.isEmpty)
        #expect(blocks(effects).allSatisfy(\.isEmpty))
    }

    @Test func aCollapsedWindowIsATileKindCollapsedInAMove() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        _ = dropF(&arranger)
        let block = try loose(arranger)
        let away = try #require(moves(arranger.handle(.zoomTo(.node(.desktop), displayUUID: "main"), now: .now)).first)
        _ = arranger.handle(.cameraSettle(displayUUID: "main", moveID: away.id), now: .now)

        let back = try #require(moves(arranger.handle(.zoomTo(.home, displayUUID: "main"), now: .now)).first)

        let tile = try #require(back.tiles.first { $0.window == f })
        #expect(tile.kind == .collapsed)
        #expect(tile.end == block)
    }
}
