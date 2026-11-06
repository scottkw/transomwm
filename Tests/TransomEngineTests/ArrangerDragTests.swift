import TransomEngine
import TransomModel
import TransomTestSupport
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
            case .setFrame(let w, _), .park(let w, _, _), .focus(let w), .raise(let w), .setHidden(let w, _), .close(let w), .minimize(let w): w == window
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

/// Presses `window`'s title bar (10 pt below the top of `frame`, centred), drags 10 pt right (the session starts), then
/// on to `point`, the frame following the pointer.
private func drag(
    _ harness: inout Harness, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = []
) async -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = await harness.send(pointer(.down, grab.x, grab.y, modifiers, press: window))
    effects += await harness.send(pointer(.dragged, grab.x + 10, grab.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, 10)))
    effects += await harness.send(pointer(.dragged, point.x, point.y, modifiers))
    effects += await harness.send(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)))
    return effects
}

/// The same drag on an Arranger with no window system behind it.
private func drag(
    _ arranger: inout Arranger, _ window: WindowRef, from frame: Rect, to point: Point, _ modifiers: Modifiers = [],
    at now: ContinuousClock.Instant
) -> [ArrangerEffect] {
    let grab = Point(x: frame.midX, y: frame.minY + 10)
    var effects = arranger.handle(pointer(.down, grab.x, grab.y, modifiers, press: window), now: now)
    effects += arranger.handle(pointer(.dragged, grab.x + 10, grab.y, modifiers), now: now)
    effects += arranger.handle(.dragFrame(window.identity, shifted(frame, 10)), now: now)
    effects += arranger.handle(pointer(.dragged, point.x, point.y, modifiers), now: now)
    effects += arranger.handle(.dragFrame(window.identity, shifted(frame, point.x - grab.x, point.y - grab.y)), now: now)
    return effects
}

/// The release frame `drag` leaves `frame` at.
private func released(_ frame: Rect, at point: Point) -> Rect {
    shifted(frame, point.x - frame.midX, point.y - frame.minY - 10)
}

private func dragFloating(_ harness: inout Harness, to x: Double, _ y: Double, _ modifiers: Modifiers = []) async -> [ArrangerEffect] {
    await drag(&harness, f, from: floatingFrame, to: Point(x: x, y: y), modifiers)
}

private func previews(_ effects: [ArrangerEffect]) -> [PreviewState] {
    effects.compactMap { if case .preview(let state?, _) = $0 { state } else { nil } }
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

    /// WR-04: an inventory fed mid-drag (a display change, or a CG list change while a window is dormant) never
    /// re-homes the pressed window: where it lands is decided at mouse-up, as for a windowChanged.
    @Test func anInventoryMidDragNeverRehomesThePressedWindow() throws {
        let start = ContinuousClock.now
        let right = DisplayInfo(uuid: "right", frame: Rect(x: 1440, y: 0, width: 1440, height: 900),
                                visibleFrame: Rect(x: 1440, y: 25, width: 1440, height: 875), currentSpaceID: nil)
        var arranger = Arranger()
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay, right], windows: [info(2, frame: floatingFrame)], initialRefreshComplete: true)), now: start)
        try #require(arranger.deskKey(of: f) == mainKey)
        _ = drag(&arranger, f, from: floatingFrame, to: Point(x: 1500, y: 310), at: start)
        try #require(arranger.isDragging)

        var crossed = info(2, frame: shifted(floatingFrame, 1000))
        crossed.displayUUID = "right"
        _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay, right], windows: [crossed], initialRefreshComplete: true)), now: start)
        #expect(arranger.deskKey(of: f) == mainKey, "the pressed window was re-homed mid-drag")
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

// MARK: - The UI-SPEC Surface 2 state matrix (D-01..D-06, D-26, TILE-02, TILE-11)

private let a = window(1), b = window(3)
private let frameA = Rect(x: 40, y: 80, width: 320, height: 232)
private let frameB = Rect(x: 730, y: 400, width: 150, height: 120)
/// Small, at the bottom right: over b once a and b dock.
private let smallF = Rect(x: 1250, y: 700, width: 150, height: 100)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)
private let noRoom = "Not enough room to dock here"

private func centre(_ rect: Rect) -> Point { Point(x: rect.midX, y: rect.midY) }

/// [a | b] across the whole visible frame with f floating over b, and the plan of that desk.
private func docked() async throws -> (Harness, FramePlan) {
    var harness = await Harness.started(frames: [1: frameA, 2: smallF, 3: frameB])
    await harness.send(.command(.dock, focused: a))
    await harness.send(.command(.dock, focused: b))
    let plan = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
    let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
    #expect(plan.frames[f] == nil, "f is planned as a tile")
    #expect(abs(rb.minX - ra.maxX - 8) < 0.5, "a and b are not side by side: \(ra) \(rb)")
    return (harness, plan)
}

/// An Arranger fed `infos` (and a saved `world`), with no window system behind it.
private func bare(_ infos: [WindowInfo], world: World? = nil) -> Arranger {
    var arranger = Arranger()
    if let world { _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now) }
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
    return arranger
}

extension ArrangerDragTests {
    @Test func aDropThatLeavesAWindowWithoutRoomShowsBlockedAndIsRefused() throws {
        let start = ContinuousClock.now
        let huge = Size(width: 1500, height: 100)
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)])
        _ = drag(&arranger, f, from: floatingFrame, to: Point(x: 10, y: 310), at: start)
        let tick = arranger.handle(.tick, now: start + .milliseconds(150))
        let loose = try #require(try dryRun(arranger, f, .layoutEdge(.left), mins: [:]))
        #expect(tick.contains(.preview(.blocked(loose), displayUUID: "main")), "tick gave \(tick)")

        let up = arranger.handle(pointer(.up, 10, 310), now: start + .milliseconds(200))
        #expect(up.contains(.announce(noRoom)))
        let desk = try #require(arranger.world[mainKey])
        #expect(desk.tree.windows.isEmpty, "a blocked drop docked the window")
        #expect(desk.desktop.frame(of: f) == released(floatingFrame, at: Point(x: 10, y: 310)))
        #expect(arranger.history.depth(for: mainKey) == 0)
    }

    @Test func commandOverAnotherDockedTileSwapsTheTwoWindows() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: Point(x: rb.minX + 20, y: rb.midY), [.command])
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        #expect(tick.contains(.preview(.swap(target: rb, origin: ra), displayUUID: "main")), "tick gave \(tick)")
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, rb.minX + 20, rb.midY, [.command]))
        #expect(up.contains(.announce("Swapped")))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        let after = try Planner.plan(desk: try #require(harness.arranger.world[mainKey]), area: area, gap: 8, mins: [:])
        #expect(after.frames[a] == rb && after.frames[b] == ra)
        #expect(setFrames(up)[a] == rb && setFrames(up)[b] == ra)
    }

    @Test func commandIsIgnoredForAFloatingWindow() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let point = Point(x: rb.minX + rb.width * 0.1, y: rb.midY)
        _ = await drag(&harness, f, from: smallF, to: point, [.command])
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        let leaf = try #require(harness.arranger.world[mainKey]?.tree.leaf(containing: b))
        let r = try #require(try dryRun(harness.arranger, f, .tile(leaf, .edge(.left))))
        #expect(previews(tick) == [.dock(r)])
    }

    @Test(arguments: ["own tile", "a tile centre", "a gap", "outside every zone"])
    func aDockedWindowReleasedOnAMissSnapsBackToItsTile(over place: String) async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        let point: Point = switch place {
        case "own tile": Point(x: ra.minX + ra.width * 0.1, y: ra.midY)
        case "a tile centre": centre(rb)
        case "a gap": Point(x: ra.maxX + 4, y: ra.midY)
        default: Point(x: 1460, y: 400)  // right of the only display
        }
        _ = await drag(&harness, a, from: ra, to: point)
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.snapBack(ra, label: nil)], "over \(place) the tick gave \(tick)")
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, point.x, point.y))
        #expect(setFrames(up)[a] == ra, "over \(place) a was not put back")
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
    }

    @Test func aFloatingWindowOverAGapGetsNoPreviewAndAPlainMove() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a])
        let point = Point(x: ra.maxX + 4, y: ra.midY)
        _ = await drag(&harness, f, from: smallF, to: point)
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)).isEmpty)
        let up = await harness.send(pointer(.up, point.x, point.y))
        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: f) == released(smallF, at: point))
        #expect(setFrames(up)[f] == nil)
    }

    /// D-05 (UI-SPEC Surface 2 row 1): no clamp ghost while dragging, and the release keeps the frame across a tile.
    @Test func aFloatingWindowWhoseReleaseFrameCrossesATileStaysWhereItIsReleased() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let point = centre(rb)
        _ = await drag(&harness, f, from: smallF, to: point)
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)).isEmpty)
        let up = await harness.send(pointer(.up, point.x, point.y))
        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: f) == released(smallF, at: point))
        #expect(setFrames(up)[f] == nil)
    }

    @Test func shiftUndocksADockedWindowAtItsReleaseFrame() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let point = Point(x: rb.midX, y: rb.minY + 40)
        _ = await drag(&harness, b, from: rb, to: point, [.shift])
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)).isEmpty, "a bypass over its own tile showed a preview")
        let depth = harness.arranger.history.depth(for: mainKey)

        await harness.send(pointer(.up, point.x, point.y, [.shift]))
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.state(of: b) == nil)
        #expect(desk.desktop.frame(of: b) == released(rb, at: point))
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
    }

    /// D-05 (UI-SPEC Surface 2 row 2): ⇧ pulls a docked window out at its release frame over another tile, with no
    /// ghost, no clamp and one undo step; the tile left takes the room.
    @Test func shiftPullsADockedWindowOutAtItsReleaseFrameOverAnotherTile() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        let point = Point(x: rb.midX, y: rb.minY + 40)
        #expect(released(ra, at: point).overlaps(rb), "the release frame is not over b")
        let during = await drag(&harness, a, from: ra, to: point, [.shift])
        harness.now += .milliseconds(150)
        #expect(previews(during + (await harness.send(.tick))).isEmpty, "a pull-out showed a preview")
        let depth = harness.arranger.history.depth(for: mainKey)

        let up = await harness.send(pointer(.up, point.x, point.y, [.shift]))
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.state(of: a) == nil)
        #expect(desk.desktop.frame(of: a) == released(ra, at: point))
        #expect(setFrames(up)[a] == nil, "the pulled-out window was moved")
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
        let refilled = try #require(try Planner.plan(desk: desk, area: area, gap: 8, mins: [:]).frames[b])
        #expect(refilled.width > rb.width)
        #expect(await harness.frame(b) == refilled)
    }

    /// WR-02 (review 03-26): undoing a ⇧-undock docks the window again with its pre-dock frame, where Float sends it.
    @Test func undoingAShiftUndockGivesBackThePreDockFrame() async throws {
        var (harness, plan) = try await docked()
        let rb = try #require(plan.frames[b])
        let point = Point(x: rb.midX, y: rb.minY + 40)
        _ = await drag(&harness, b, from: rb, to: point, [.shift])
        harness.now += .milliseconds(150)
        await harness.send(.tick)
        await harness.send(pointer(.up, point.x, point.y, [.shift]))
        #expect(harness.arranger.world[mainKey]?.desktop.frame(of: b) == released(rb, at: point))
        await harness.send(.command(.undo, focused: b))
        #expect(harness.arranger.world[mainKey]?.tree.state(of: b) != nil, "the undo did not dock b again")
        await harness.send(.command(.float, focused: b))
        #expect(await harness.frame(b) == frameB)
    }

    /// UI-SPEC Surface 2 row 4 (row gone): pulling a window out of the layout never lacks room, whatever its minimum.
    @Test func shiftWithAWindowTooBigForAnyRoomStillUndocksAtItsReleaseFrame() throws {
        var tree = LayoutTree()
        var ids = IDSource()
        try tree.applyDrop(.layoutEdge(.bottom), window: a, ids: &ids)
        try tree.insert(b, at: .right, of: try #require(tree.leaf(containing: a)), ids: &ids)
        let world = try World(ids: ids, desks: [mainKey: Desk(tree: tree)])
        let mins = [a: Size(width: 100, height: 600), b: Size(width: 100, height: 300)]
        let start = ContinuousClock.now
        var arranger = bare([info(1, frame: frameA, minimum: mins[a]), info(3, frame: frameB, minimum: mins[b])], world: world)
        let infoA = try #require(arranger.windows[a.identity])
        let point = Point(x: 700, y: 800)

        _ = drag(&arranger, a, from: infoA.frame, to: point, [.shift], at: start)
        let tick = arranger.handle(.tick, now: start + .milliseconds(150))
        #expect(previews(tick).isEmpty, "tick gave \(tick)")
        let up = arranger.handle(pointer(.up, point.x, point.y, [.shift]), now: start + .milliseconds(200))
        #expect(!up.contains(.announce(noRoom)))
        #expect(arranger.world[mainKey]?.tree.state(of: a) == nil)
        #expect(arranger.world[mainKey]?.desktop.frame(of: a) == released(infoA.frame, at: point))
    }

    /// D-08, UI-SPEC Surface 2 row 6: on an empty desk the pointer 10 pt from the left edge previews the whole visible
    /// frame, and the release docks the window as the first tile in one undo step.
    @Test func anEmptyDeskDocksFromItsEdgeBandAsTheWholeVisibleFrame() throws {
        let run = try dragOnAnEmptyDesk(to: Point(x: 10, y: 460))
        #expect(previews(run.tick) == [.dock(wholeVisibleTile)], "tick gave \(run.tick)")
        let desk = try #require(run.arranger.world[mainKey])
        #expect(desk.tree.root == desk.tree.leaf(containing: f) && desk.tree.root != nil)
        #expect(setFrames(run.up)[f] == wholeVisibleTile)
        #expect(run.arranger.history.depth(for: mainKey) == run.steps + 1)
    }

    /// UI-SPEC planner note 1 (corrected by RESEARCH): the keyboard Dock still docks anywhere on an empty desk.
    @Test func theKeyboardDockTargetOnAnEmptyDeskIsTheWholeLayoutEvenInTheMiddle() throws {
        let desk = Desk(tree: LayoutTree())
        let plan = try Planner.plan(desk: desk, area: area, gap: 8, mins: [:])
        #expect(Planner.dockTarget(at: Point(x: 720, y: 460), desk: desk, area: area, resolution: plan.resolution) == .emptyLayout)
    }

    @Test func shiftPressedAfterADockPreviewWithdrawsItAndRestartsTheDwell() async throws {
        var harness = await Harness.started(frames: [2: floatingFrame])
        _ = await dragFloating(&harness, to: 10, 310)
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)).count == 1)

        let flags = await harness.send(pointer(.flagsChanged, 10, 310, [.shift]))
        #expect(flags.contains(.preview(nil, displayUUID: "main")), "the dock preview stayed: \(flags)")
        #expect(flags.contains { if case .wake = $0 { true } else { false } }, "no dwell restart")
        harness.now += .milliseconds(150)
        #expect(previews(await harness.send(.tick)).isEmpty, "a bypass showed a dock preview")
        await harness.send(pointer(.up, 10, 310, [.shift]))
        #expect(harness.arranger.world[mainKey]?.tree.windows.isEmpty == true)
    }

    @Test func excludedNeverDockOrPausedWindowsGetNoSession() async throws {
        let start = ContinuousClock.now
        let panel = window(4), excluded = window(5)
        var arranger = bare([
            info(4, frame: floatingFrame, kind: .neverDock(.subrole)), info(5, frame: floatingFrame, excluded: true),
        ])
        for w in [panel, excluded] {
            let effects = drag(&arranger, w, from: floatingFrame, to: Point(x: 10, y: 310), at: start)
                + arranger.handle(.tick, now: start + .milliseconds(150))
            #expect(effects.isEmpty, "\(w) got \(effects)")
            #expect(arranger.drag == nil)
        }

        var harness = await Harness.started(frames: [2: floatingFrame])
        await harness.send(.setPaused(.user, true))
        var effects = await dragFloating(&harness, to: 10, 310)
        harness.now += .milliseconds(150)
        effects += await harness.send(.tick)
        effects += await harness.send(pointer(.up, 10, 310))
        #expect(!effects.contains(.pollDragFrame(f)))
        #expect(previews(effects).isEmpty)
        #expect(harness.arranger.drag == nil)
    }

    @Test func aRefusedKeyboardDockFlashesTheBlockedPreview() throws {
        let huge = Size(width: 1500, height: 100)
        var arranger = bare([info(2, frame: floatingFrame, minimum: huge)])
        let effects = arranger.handle(.command(.dock, focused: f), now: .now)
        #expect(effects.prefix(2) == [.beep, .announce(noRoom)])
        let desk = try #require(arranger.world[mainKey])
        let resolution = try Planner.plan(desk: desk, area: area, gap: 8, mins: [f: huge]).resolution
        let target = try #require(Planner.dockTarget(at: centre(floatingFrame), desk: desk, area: area, resolution: resolution))
        let loose = try #require(try dryRun(arranger, f, target, mins: [:]))
        #expect(effects.contains(.flashBlocked(loose, displayUUID: "main")), "got \(effects)")
    }
}

extension ArrangerDragTests {
    /// A mouse-up the tap never delivered (it was disabled for a moment): the next press settles the old drag by the miss
    /// rules, so a docked window does not stay off its tile.
    @Test func aPressAfterALostMouseUpSnapsTheOldDragBack() async throws {
        var (harness, plan) = try await docked()
        let ra = try #require(plan.frames[a]), rb = try #require(plan.frames[b])
        _ = await drag(&harness, a, from: ra, to: centre(rb))
        let next = await harness.send(pointer(.down, rb.midX, rb.minY + 10, press: b))
        #expect(setFrames(next)[a] == ra, "the old drag was dropped without the miss rules")
        #expect(harness.arranger.drag?.window == b)
    }
}

// MARK: - Empty areas (8.1.1 D-16, rule E6)

/// a docked to the left half on an empty desk, so the right half is an empty area, with f floating; Hold ⌥ when asked.
private func leftHalfDocked(_ mode: DragToDockMode) async -> Harness {
    var harness = await Harness.started(frames: [1: frameA, 2: floatingFrame])
    await harness.send(.dragToDock(mode))
    await harness.send(.command(.dockFourth(.firstHalf, .horizontal), focused: a))
    return harness
}

/// The right child of [a .5 | X .5] in the visible frame (0, 25, 1440, 875) with gap 8: inner (8, 33, 1424, 859),
/// each half (1424 - 8) / 2 = 708 wide.
private let rightHalf = Rect(x: 724, y: 33, width: 708, height: 859)
private let leftHalf = Rect(x: 8, y: 33, width: 708, height: 859)

extension ArrangerDragTests {
    /// E6: within 24 pt of the screen edge over the empty half, the preview is exactly that half and the release docks
    /// there in one undo step; the docked window doesn't move. Hold ⌥ with ⌥ held behaves the same.
    @Test(arguments: [(DragToDockMode.automatic, Modifiers()), (DragToDockMode.holdOption, Modifiers.option)])
    func aFloaterDraggedToTheEdgeOverAnEmptyHalfDocksIntoIt(mode: DragToDockMode, modifiers: Modifiers) async throws {
        var harness = await leftHalfDocked(mode)
        #expect(await harness.frame(a) == leftHalf)
        let depth = harness.arranger.history.depth(for: mainKey)
        _ = await dragFloating(&harness, to: 1430, 460, modifiers)
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.dock(rightHalf)], "tick gave \(tick)")

        let up = await harness.send(pointer(.up, 1430, 460, modifiers))
        let tree = try #require(harness.arranger.world[mainKey]?.tree)
        let root = try #require(tree.root)
        #expect(tree.node(root) == .split(
            axis: .horizontal, children: [try #require(tree.leaf(containing: a)), try #require(tree.leaf(containing: f))], weights: [0.5, 0.5]))
        #expect(setFrames(up)[f] == rightHalf)
        #expect(setFrames(up)[a] == nil, "the docked window moved")
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
    }

    /// E6: anywhere else over the empty half the drag shows nothing and the release only moves the window.
    @Test(arguments: [(DragToDockMode.automatic, Modifiers()), (DragToDockMode.holdOption, Modifiers.option)])
    func aFloaterDraggedIntoTheMiddleOfAnEmptyHalfJustMoves(mode: DragToDockMode, modifiers: Modifiers) async throws {
        var harness = await leftHalfDocked(mode)
        let depth = harness.arranger.history.depth(for: mainKey)
        let during = await dragFloating(&harness, to: 1000, 460, modifiers)
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        #expect(previews(tick).isEmpty, "tick gave \(tick)")

        let up = await harness.send(pointer(.up, 1000, 460, modifiers))
        let desk = try #require(harness.arranger.world[mainKey])
        #expect(desk.tree.windows == [a])
        #expect(desk.desktop.frame(of: f) == released(floatingFrame, at: Point(x: 1000, y: 460)))
        #expect(harness.arranger.history.depth(for: mainKey) == depth)
        #expect(!writes(during + up, f))
    }
}

extension ArrangerDragTests {
    /// Review WR-01 (E4, E6, E1): a docked window dragged to the screen edge over the empty area beside it previews that
    /// area, docks into it at exactly its span, and leaves an empty area where it was: [a | _] becomes [_ | a] and
    /// [_ | a | _] (the center third) becomes [_ | a], a in exactly the right third.
    @Test(arguments: [(FourthSlot.firstHalf, FourthSlot.secondHalf), (.middleThird, .lastThird)])
    func aDockedWindowDraggedIntoTheEmptyAreaBesideItMovesThere(from slot: FourthSlot, to expected: FourthSlot) async throws {
        var reference = await Harness.started(frames: [1: frameA])
        await reference.send(.command(.dockFourth(expected, .horizontal), focused: a))
        let target = try #require(await reference.frame(a))
        var harness = await Harness.started(frames: [1: frameA])
        await harness.send(.command(.dockFourth(slot, .horizontal), focused: a))
        let start = try #require(await harness.frame(a))
        let depth = harness.arranger.history.depth(for: mainKey)

        _ = await drag(&harness, a, from: start, to: Point(x: 1430, y: 460))
        harness.now += .milliseconds(150)
        let tick = await harness.send(.tick)
        #expect(previews(tick) == [.dock(target)], "tick gave \(tick)")
        let up = await harness.send(pointer(.up, 1430, 460))

        let tree = try #require(harness.arranger.world[mainKey]?.tree)
        guard case let .split(_, children, weights)? = tree.node(try #require(tree.root)) else {
            Issue.record("no root split: \(tree)")
            return
        }
        #expect(children.map { tree.node($0) } == [.spacer, .panel(a)])
        #expect(weights == (reference.arranger.world[mainKey]?.tree.root).flatMap { root in
            if case let .split(_, _, w)? = reference.arranger.world[mainKey]?.tree.node(root) { w } else { nil }
        })
        #expect(setFrames(up)[a] == target)
        #expect(harness.arranger.history.depth(for: mainKey) == depth + 1)
    }
}
