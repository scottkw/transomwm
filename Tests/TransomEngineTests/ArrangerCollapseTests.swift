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

/// An Arranger fed `infos` on the main display (and a saved `world`), with zoom on or off.
private func bare(_ infos: [WindowInfo], world: World? = nil, zoom: Bool) -> Arranger {
    var arranger = Arranger()
    if let world { _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now) }
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
    if zoom { _ = arranger.handle(.zoomEnabled(true), now: .now) }
    return arranger
}

/// Drags `window` by its title bar to `point` and holds it past the dwell; returns the tick's effects.
private func hold(
    _ arranger: inout Arranger, _ window: WindowRef, from frame: Rect, at point: Point, _ modifiers: Modifiers = [], start: ContinuousClock.Instant
) -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    _ = arranger.handle(pointer(.down, grab.x, grab.y, modifiers, press: window), now: start)
    _ = arranger.handle(pointer(.dragged, grab.x + 10, grab.y, modifiers), now: start)
    _ = arranger.handle(.dragFrame(window.identity, shifted(frame, 10)), now: start)
    _ = arranger.handle(pointer(.dragged, point.x, point.y, modifiers), now: start)
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

/// f's frame on the main desk with every minimum ignored.
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
        let block = CollapsedBlock(window: f, rect: try loose(arranger))
        #expect(up.contains(.collapsedBlocks([block], displayUUID: "main")), "got \(up)")
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
        #expect(blocks(effects).allSatisfy { $0.isEmpty })
    }

    @Test func aCollapsedWindowIsATileKindCollapsedInAMove() throws {
        // a docked first gives the camera somewhere to zoom to; f drops on a's left edge: [f | a].
        var arranger = bare([info(1, frame: Rect(x: 100, y: 100, width: 300, height: 200)), info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        _ = arranger.handle(.command(.dock, focused: a), now: .now)
        _ = dropF(&arranger)
        try #require(arranger.camera.collapsible == [f.identity])
        let block = try loose(arranger)
        let leafA = try #require(arranger.world[mainKey]?.tree.leaf(containing: a))
        let away = try #require(moves(arranger.handle(.zoomTo(.node(leafA), displayUUID: "main"), now: .now)).first)
        _ = arranger.handle(.cameraSettle(displayUUID: "main", moveID: away.id), now: .now)

        let back = try #require(moves(arranger.handle(.zoomTo(.home, displayUUID: "main"), now: .now)).first)

        let tile = try #require(back.tiles.first { $0.window == f })
        #expect(tile.kind == .collapsed)
        #expect(tile.end == block)
    }
}

private let b = window(3), c = window(4), g = window(5)

/// A saved main desk built by `build`, so its shape does not depend on where Dock would put each window.
private func world(_ build: (inout LayoutTree, inout IDSource) throws -> Void) throws -> World {
    var tree = LayoutTree()
    var ids = IDSource()
    try build(&tree, &ids)
    return try World(ids: ids, desks: [mainKey: Desk(tree: tree)])
}

/// a alone, 1420 pt wide at least: it fits the 1424 pt row, but any other window docked beside it (an 8 pt gap and at
/// least 1 pt) leaves a without room.
private func wideA(zoom: Bool, floating: Rect = floatingFrame) throws -> Arranger {
    let saved = try world { tree, ids in try tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids) }
    return bare([info(1, frame: floatingFrame, minimum: Size(width: 1420, height: 100)), info(2, frame: floating)], world: saved, zoom: zoom)
}

private func announcements(_ effects: [ArrangerEffect]) -> [String] {
    effects.compactMap { if case .announce(let text) = $0 { text } else { nil } }
}

/// UI-SPEC Surface 7 and the CONTEXT E boundaries: only drops and keyboard Dock/Move collapse, only with zoom on.
extension ArrangerCollapseTests {
    @Test func theDragPreviewIsCollapsedForTheDraggedWindow() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        let (tick, up) = dropF(&arranger)
        #expect(previews(tick) == [.collapsed(try loose(arranger), label: "Collapsed until you zoom in")], "tick gave \(tick)")
        #expect(announcements(up) == ["Docked. Zoom in to see it."])
    }

    @Test func theDragPreviewIsCollapsedForOtherWindows() throws {
        var arranger = try wideA(zoom: true)
        let (tick, up) = dropF(&arranger)
        let preview = try #require(previews(tick).last)
        guard case .collapsed(_, let label) = preview else { Issue.record("tick gave \(tick)"); return }
        #expect(label == "1 window collapses")
        #expect(announcements(up) == ["Docked. 1 window collapsed."])
        #expect(arranger.camera.collapsible == [a.identity])
        #expect(arranger.world[mainKey]?.tree.state(of: f) == .present)
    }

    @Test func theCollapseCopyCountsWindows() {
        #expect(CollapseCopy.draggedLabel == "Collapsed until you zoom in")
        #expect(CollapseCopy.othersLabel(1) == "1 window collapses")
        #expect(CollapseCopy.othersLabel(2) == "2 windows collapse")
        #expect(CollapseCopy.dockedAnnouncement(dragged: true, others: 2) == "Docked. Zoom in to see it.")
        #expect(CollapseCopy.dockedAnnouncement(dragged: false, others: 1) == "Docked. 1 window collapsed.")
        #expect(CollapseCopy.dockedAnnouncement(dragged: false, others: 2) == "Docked. 2 windows collapsed.")
    }

    @Test func keyboardDockAndMoveCollapseWithZoomOn() throws {
        var alone = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        let docked = alone.handle(.command(.dock, focused: f), now: .now)
        #expect(announcements(docked) == ["Docked. Zoom in to see it."], "got \(docked)")
        #expect(alone.world[mainKey]?.tree.state(of: f) == .present && alone.camera.collapsible == [f.identity])
        #expect(!docked.contains(.beep))

        // f's centre over the left of a's tile: Dock puts it on a's left edge.
        var beside = try wideA(zoom: true, floating: Rect(x: 50, y: 400, width: 100, height: 100))
        let other = beside.handle(.command(.dock, focused: f), now: .now)
        #expect(announcements(other) == ["Docked. 1 window collapsed."], "got \(other)")
        #expect(beside.camera.collapsible == [a.identity])

        // [a | V[b, c]]; c moved left: a + c + b side by side need 400 + 600 + 450, more than the row.
        let saved = try world { tree, ids in
            try tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
            try tree.insert(b, at: .right, of: try #require(tree.leaf(containing: a)), ids: &ids)
            try tree.insert(c, at: .bottom, of: try #require(tree.leaf(containing: b)), ids: &ids)
        }
        let infos = [
            info(1, frame: floatingFrame, minimum: Size(width: 400, height: 100)), info(3, frame: floatingFrame, minimum: Size(width: 450, height: 100)),
            info(4, frame: floatingFrame, minimum: Size(width: 600, height: 100)),
        ]
        var columns = bare(infos, world: saved, zoom: true)
        let moved = columns.handle(.command(.moveOrSnap(.left), focused: c), now: .now)
        #expect(announcements(moved) == ["Docked. Zoom in to see it."], "got \(moved)")
        #expect(columns.camera.collapsible == [c.identity])

        var refused = bare(infos, world: saved, zoom: false)
        let before = refused.world
        #expect(Array(refused.handle(.command(.moveOrSnap(.left), focused: c), now: .now).prefix(2)) == [.beep, .announce(Arranger.noRoom)])
        #expect(refused.world == before)
        var off = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: false)
        #expect(Array(off.handle(.command(.dock, focused: f), now: .now).prefix(2)) == [.beep, .announce(Arranger.noRoom)])
    }

    @Test func growShrinkRotateFlipBalanceStillRefuseWithZoomOn() throws {
        // [a | b], each 500 pt tall at least: stacked they need more than the 859 pt column.
        let saved = try world { tree, ids in
            try tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
            try tree.insert(b, at: .right, of: try #require(tree.leaf(containing: a)), ids: &ids)
        }
        let tall = Size(width: 100, height: 500)
        var arranger = bare([info(1, frame: floatingFrame, minimum: tall), info(3, frame: floatingFrame, minimum: tall)], world: saved, zoom: true)
        let before = arranger.world
        let rotated = arranger.handle(.command(.rotateSplit, focused: a), now: .now)
        #expect(Array(rotated.prefix(2)) == [.beep, .announce(Arranger.noRoom)], "got \(rotated)")
        #expect(arranger.world == before && arranger.camera.collapsible.isEmpty)
        for command in [Command.growTile, .shrinkTile, .flipSplit, .balanceSplit] {
            _ = arranger.handle(.command(command, focused: a), now: .now)
            #expect(arranger.camera.collapsible.isEmpty, "\(command) collapsed a window")
        }
    }

    @Test func arrangeAllStillFloatsWhatDoesNotFit() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge), info(5, frame: Rect(x: 100, y: 100, width: 300, height: 200))], zoom: true)
        let effects = arranger.handle(.command(.arrangeAll, focused: g), now: .now)
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.state(of: g) == .present && desk.desktop.contains(f))
        #expect(effects.contains(.notice(.arrangeLeftovers(count: 1))), "got \(effects)")
        #expect(arranger.camera.collapsible.isEmpty)
    }

    /// UI-SPEC Surface 2 row 4 (row gone): with zoom on too, a ⇧ pull-out never lacks room; it floats and nothing collapses.
    @Test func theShiftBypassOfABigWindowFloatsItWithNothingCollapsed() throws {
        let saved = try world { tree, ids in
            try tree.applyDrop(.layoutEdge(.bottom), window: a, ids: &ids)
            try tree.insert(b, at: .right, of: try #require(tree.leaf(containing: a)), ids: &ids)
        }
        let frameA = Rect(x: 40, y: 80, width: 320, height: 232)
        var arranger = bare(
            [info(1, frame: frameA, minimum: Size(width: 100, height: 600)), info(3, frame: frameA, minimum: Size(width: 100, height: 300))],
            world: saved, zoom: true)
        let start = ContinuousClock.now
        let infoA = try #require(arranger.windows[a.identity])
        let tick = hold(&arranger, a, from: infoA.frame, at: Point(x: 700, y: 800), [.shift], start: start)
        #expect(previews(tick).isEmpty, "tick gave \(tick)")
        let up = arranger.handle(pointer(.up, 700, 800, [.shift]), now: start + .milliseconds(200))
        #expect(!up.contains(.announce(Arranger.noRoom)))
        #expect(arranger.world[mainKey]?.tree.state(of: a) == nil && arranger.world[mainKey]?.desktop.contains(a) == true)
        #expect(arranger.camera.collapsible.isEmpty)
    }

    @Test func turningZoomOffFloatsCollapsedWindowsWithTheLostRoomNotice() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        _ = dropF(&arranger)
        #expect(arranger.camera.collapsible == [f.identity])

        let effects = arranger.handle(.zoomEnabled(false), now: .now)

        #expect(effects.contains(.notice(.lostRoom([f]))), "got \(effects)")
        #expect(effects.contains(.collapsedBlocks([], displayUUID: "main")))
        #expect(arranger.world[mainKey]?.desktop.contains(f) == true)
        #expect(arranger.camera.collapsible.isEmpty)
    }

    /// RESEARCH Pitfall 11: the set is never saved, so a relaunch floats a formerly collapsed window as lost room.
    @Test func aRelaunchFloatsAFormerlyCollapsedWindow() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        _ = dropF(&arranger)
        var relaunched = Arranger()
        _ = relaunched.handle(.restore(arranger.world, homeFrames: [:]), now: .now)
        _ = relaunched.handle(.zoomEnabled(true), now: .now)
        let infos = [info(2, frame: floatingFrame, minimum: huge)]
        _ = relaunched.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
        #expect(relaunched.world[mainKey]?.desktop.contains(f) == true, "a formerly collapsed window stayed docked")
        #expect(relaunched.camera.collapsible.isEmpty)
    }
}

/// WR-01 (04-REVIEW): a window is collapsible only while it is collapsed, so CONTEXT E's refusals and floats still hold
/// for it afterwards.
extension ArrangerCollapseTests {
    @Test func aWindowThatFitsAgainIsNoLongerCollapsible() throws {
        var arranger = try wideA(zoom: true)
        _ = dropF(&arranger)
        try #require(arranger.camera.collapsible == [a.identity])

        _ = arranger.handle(.event(.windowDestroyed(f)), now: .now)
        #expect(arranger.camera.collapsible.isEmpty, "a fits alone again but stayed collapsible")

        let grown = [info(1, frame: floatingFrame, minimum: huge)]
        let effects = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: grown, initialRefreshComplete: true)), now: .now)
        #expect(effects.contains(.notice(.lostRoom([a]))), "an OS-caused loss of room collapsed a instead of floating it: \(effects)")
        #expect(arranger.world[mainKey]?.desktop.contains(a) == true)
    }

    @Test func aCollapsedWindowThatFloatsIsNoLongerCollapsible() throws {
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)], zoom: true)
        _ = dropF(&arranger)
        try #require(arranger.camera.collapsible == [f.identity])

        _ = arranger.handle(.command(.float, focused: f), now: .now)

        #expect(arranger.world[mainKey]?.desktop.contains(f) == true)
        #expect(arranger.camera.collapsible.isEmpty)
    }
}
