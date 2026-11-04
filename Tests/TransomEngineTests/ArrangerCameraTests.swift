@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
private let side = DisplayInfo(
    uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
    currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)
/// A single tile filling the display: the visibleFrame less resolve's 8 pt outer gap.
private let full = Rect(x: 8, y: 33, width: 1424, height: 859)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3)

/// a, b and c docked one after another (Phase 3 tiles), zoom still off.
private func threeDocked() async throws -> Harness {
    var harness = await Harness.started(frames: [
        1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
        3: Rect(x: 1100, y: 600, width: 150, height: 120),
    ])
    for window in [a, b, c] { await harness.send(.command(.dock, focused: window)) }
    let desk = try #require(harness.arranger.world[key])
    #expect(Set(desk.tree.windows) == [a, b, c])
    return harness
}

private func leaf(_ window: WindowRef, _ harness: Harness) throws -> NodeID {
    try #require(harness.arranger.world[key]?.tree.leaf(containing: window))
}

private func moves(_ effects: [ArrangerEffect]) -> [CameraMove] {
    effects.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }
}

private func performs(_ effects: [ArrangerEffect]) -> [[WindowCommand]] {
    effects.compactMap { if case .perform(let commands) = $0 { commands } else { nil } }
}

private func infos(_ effects: [ArrangerEffect]) -> [String] {
    effects.compactMap { if case .info(let text) = $0 { text } else { nil } }
}

private func parks(_ effects: [ArrangerEffect]) -> [WindowCommand] {
    performs(effects).flatMap { $0.filter { if case .park = $0 { true } else { false } } }
}

private func frames(_ harness: Harness) async -> [WindowRef: Rect] {
    var result: [WindowRef: Rect] = [:]
    for window in [a, b, c] { result[window] = await harness.frame(window) }
    return result
}

/// ZOOM-01, ZOOM-07, D-A: the engine half of the camera. A camera command emits one `.cameraMove` and writes nothing;
/// only its `.cameraSettle` commits the view, through `planShown` (save before park, parks first, changed frames only).
@Suite struct ArrangerCameraTests {
    @Test func zoomIsOffByDefault() async throws {
        var harness = try await threeDocked()
        #expect(harness.arranger.zoomEnabled == false)

        let effects = await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))

        #expect(moves(effects).isEmpty)
        #expect(performs(effects).isEmpty)
        #expect(infos(effects).count == 1)
        #expect(infos(effects).first?.contains("zoom off") == true)
    }

    @Test func zoomingToANodeMovesTheCameraThenWritesAtSettle() async throws {
        var harness = try await threeDocked()
        let home = await frames(harness)
        await harness.send(.zoomEnabled(true))
        let target = ViewTarget.node(try leaf(a, harness))

        let effects = await harness.send(.zoomTo(target, displayUUID: "main"))

        #expect(performs(effects).isEmpty)
        #expect(!effects.contains { if case .save = $0 { true } else { false } })
        let move = try #require(moves(effects).first)
        #expect(moves(effects).count == 1)
        #expect(move.displayUUID == "main" && move.from == .home && move.to == target)
        let tiles = Dictionary(uniqueKeysWithValues: move.tiles.map { ($0.window, $0) })
        #expect(tiles[a]?.kind == .stay && tiles[a]?.end == full && tiles[a]?.start == home[a])
        #expect(tiles[b]?.kind == .leaving && tiles[c]?.kind == .leaving)
        #expect(harness.arranger.view(on: "main") == .home, "the view changed before the settle")

        let settled = await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))

        let save = try #require(settled.firstIndex(of: .save(.now)), "no immediate save before the parks")
        let perform = try #require(settled.firstIndex { if case .perform = $0 { true } else { false } })
        #expect(save < perform)
        #expect(performs(settled).count == 1)
        let commands = try #require(performs(settled).first)
        #expect(Array(commands.prefix(2)) == [.park(b, displayUUID: "main"), .park(c, displayUUID: "main")])
        #expect(commands.dropFirst(2).allSatisfy { if case .setFrame = $0 { true } else { false } })
        #expect(setFrames(settled) == [a: full])
        #expect(harness.arranger.view(on: "main") == target)
        #expect(await harness.frame(a) == full)
        #expect(await harness.frame(b)?.size == home[b]?.size, "a parked window was resized")
        #expect(await harness.frame(c)?.size == home[c]?.size, "a parked window was resized")
    }

    /// RESEARCH Pitfall 8: a fourth lands at the desk's root, so one outside a zoomed view would be parked out of sight.
    @Test func aFourthLandingOutsideTheViewWidensTheCamera() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let into = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: into.id))

        let effects = await harness.send(.command(.dockFourth(.fourth, .horizontal), focused: b))

        let move = try #require(moves(effects).first, "no camera move: \(effects)")
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        #expect(harness.arranger.view(on: "main") == .home)
    }

    /// The drag path of the same pitfall: the preview is the desk-level frame, and a release outside the view widens it.
    @Test func aFourthByDragShowsTheDeskFrameAndWidensTheCamera() async throws {
        // [[a, b, c] | d | Desktop], viewing the inner split: it outlives a leaving it, so the view is still there to widen.
        var harness = await Harness.started(frames: [
            1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
            3: Rect(x: 1100, y: 600, width: 150, height: 120), 4: Rect(x: 300, y: 600, width: 150, height: 120),
        ])
        let d = ref(4)
        for window in [a, b, c, d] { await harness.send(.command(.dock, focused: window)) }
        let bLeaf = try leaf(b, harness)
        try harness.arranger.world.edit(key, history: &harness.arranger.history) { desk, ids throws(LayoutError) in
            try desk.tree.remove(a)
            try desk.tree.remove(c)
            try desk.tree.insert(a, at: .top, of: bLeaf, ids: &ids)
            try desk.tree.insert(c, at: .bottom, of: bLeaf, ids: &ids)
        }
        await harness.send(.gap(8))
        let split = try #require(harness.arranger.world[key]?.tree.parent(of: bLeaf), "no inner split")
        await harness.send(.zoomEnabled(true))
        let into = try #require(moves(await harness.send(.zoomTo(.node(split), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: into.id))
        let tile = try #require(await harness.frame(a))
        let grab = Point(x: tile.midX, y: tile.minY + 10)
        let point = Point(x: 1300, y: 310)
        await harness.send(.pointer(PointerEvent(kind: .down, location: grab, pressWindow: a)))
        await harness.send(.pointer(PointerEvent(kind: .dragged, location: Point(x: grab.x + 10, y: grab.y))))
        await harness.send(.dragFrame(a.identity, Rect(x: tile.x + 10, y: tile.y, width: tile.width, height: tile.height)))
        await harness.send(.pointer(PointerEvent(kind: .dragged, location: point, modifiers: .control)))
        await harness.send(.dragFrame(a.identity, Rect(x: tile.x + point.x - grab.x, y: tile.y, width: tile.width, height: tile.height)))
        var desk = try #require(harness.arranger.world[key])
        var ids = harness.arranger.world.ids
        try desk.tree.remove(a)
        try desk.tree.applyDrop(.fourth(.fourth, .horizontal), window: a, ids: &ids)
        let frame = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).frames[a])

        harness.now += .milliseconds(150)
        let shown = await harness.send(.tick)
        #expect(shown.contains(.preview(.fourth(frame, label: "4th column"), displayUUID: "main")), "tick gave \(shown)")

        let up = await harness.send(.pointer(PointerEvent(kind: .up, location: point, modifiers: .control)))

        let move = try #require(moves(up).first, "no camera move: \(up)")
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        #expect(harness.arranger.view(on: "main") == .home)
    }

    @Test func zoomingHomeUnparksEveryWindow() async throws {
        var harness = try await threeDocked()
        let home = await frames(harness)
        await harness.send(.zoomEnabled(true))
        let target = ViewTarget.node(try leaf(a, harness))
        let into = try #require(moves(await harness.send(.zoomTo(target, displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: into.id))

        let effects = await harness.send(.zoomTo(.home, displayUUID: "main"))
        let back = try #require(moves(effects).first)
        #expect(back.from == target && back.to == .home)
        let tiles = Dictionary(uniqueKeysWithValues: back.tiles.map { ($0.window, $0) })
        #expect(tiles[a]?.kind == .stay && tiles[b]?.kind == .entering && tiles[c]?.kind == .entering)
        let settled = await harness.send(.cameraSettle(displayUUID: "main", moveID: back.id))

        #expect(parks(settled).isEmpty)
        #expect(setFrames(settled) == home)
        #expect(await frames(harness) == home)
        #expect(await harness.fake.parked.isEmpty)
        #expect(harness.arranger.view(on: "main") == .home)
    }

    @Test func aSecondSettleOrAStaleOneDoesNothing() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let first = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        #expect(!(await harness.send(.cameraSettle(displayUUID: "main", moveID: first.id))).isEmpty)
        #expect(await harness.send(.cameraSettle(displayUUID: "main", moveID: first.id)).isEmpty)

        let older = try #require(moves(await harness.send(.zoomTo(.node(try leaf(b, harness)), displayUUID: "main"))).first)
        let newer = try #require(moves(await harness.send(.zoomTo(.node(try leaf(c, harness)), displayUUID: "main"))).first)

        #expect(await harness.send(.cameraSettle(displayUUID: "main", moveID: older.id)).isEmpty)
        #expect(await harness.send(.cameraSettle(displayUUID: "main", moveID: 9_999)).isEmpty)
        #expect(harness.arranger.view(on: "main") == .node(try leaf(a, harness)))
        #expect(!(await harness.send(.cameraSettle(displayUUID: "main", moveID: newer.id))).isEmpty)
        #expect(harness.arranger.view(on: "main") == .node(try leaf(c, harness)))
    }

    @Test func aRetargetStartsFromThePendingTarget() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let target = ViewTarget.node(try leaf(a, harness))
        let first = try #require(moves(await harness.send(.zoomTo(target, displayUUID: "main"))).first)

        let second = try #require(moves(await harness.send(.zoomTo(.home, displayUUID: "main"))).first)

        #expect(second.from == target && second.to == .home)
        #expect(second.id > first.id)
    }

    @Test func zoomingToTheCurrentViewIsRefused() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))

        let effects = await harness.send(.zoomTo(.home, displayUUID: "main"))

        #expect(moves(effects).isEmpty)
        #expect(infos(effects).count == 1)
        #expect(infos(effects).first?.hasPrefix("refused zoomTo") == true)
        #expect(infos(effects).first?.contains("already showing") == true)
    }

    @Test func aDisplayWithNoDeskIsRefused() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))

        let effects = await harness.send(.zoomTo(.home, displayUUID: "nowhere"))

        #expect(moves(effects).isEmpty)
        #expect(infos(effects).count == 1)
        #expect(infos(effects).first?.hasPrefix("refused zoomTo") == true)
    }

    @Test func turningZoomOffReturnsHome() async throws {
        var harness = try await threeDocked()
        let home = await frames(harness)
        await harness.send(.zoomEnabled(true))
        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))

        let effects = await harness.send(.zoomEnabled(false))

        #expect(harness.arranger.zoomEnabled == false)
        #expect(setFrames(effects) == home)
        #expect(await frames(harness) == home)
        #expect(harness.arranger.view(on: "main") == .home)
    }

    /// RESEARCH Pitfall 1: a parked sliver reported on another display is not a move to that display, nor a user move.
    @Test func aParkedDockedWindowIsNeverRehomed() async throws {
        var harness = try await threeDocked()
        await harness.fake.setDisplays([mainDisplay, side])
        await harness.send(.inventory(await harness.fake.inventory()))
        await harness.send(.zoomEnabled(true))
        let node = try leaf(b, harness)
        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        #expect(await harness.fake.parked.contains(b.identity))
        var reported = try #require(harness.arranger.windows[b.identity])
        reported.displayUUID = "side"
        reported.frame = Rect(x: 1440, y: 899, width: reported.frame.width, height: reported.frame.height)

        let changed = await harness.send(.event(.windowChanged(reported)))
        let moved = await harness.send(.event(.windowMoved(b, reported.frame)))

        #expect(harness.arranger.deskKey(of: b) == key)
        #expect(harness.arranger.world[key]?.tree.state(of: b) == .present)
        #expect(try leaf(b, harness) == node)
        #expect(setFrames(changed)[b] == nil && setFrames(moved)[b] == nil)
        #expect(harness.arranger.world[DeskKey(displayUUID: "side", spaceID: nil)]?.contains(b) != true)
    }

    /// ZOOM-06 (engine): a click's zoom focuses its window right after the settle's writes.
    @Test func zoomToWithFocusFocusesAfterTheWrites() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))

        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(b, harness)), displayUUID: "main", focus: b))).first)
        let settled = await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))

        #expect(settled.last == .perform([.focus(b)]))
        let writes = try #require(settled.firstIndex { if case .perform(let commands) = $0 { commands.contains { if case .setFrame = $0 { true } else { false } } } else { false } })
        #expect(writes < settled.count - 1)
        #expect(harness.arranger.focusOrder.first == b.identity)
    }

    /// D-D, 04-08: the quit's home tiles are the home view's frames, whatever the camera shows.
    @Test func homeTilesAreTheHomeViewWhileZoomed() async throws {
        var harness = try await threeDocked()
        let home = await frames(harness)
        await harness.send(.zoomEnabled(true))
        #expect(harness.arranger.homeTiles().isEmpty, "at home the quit leaves docked windows alone (Phase 3)")
        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        try #require(await harness.frame(a) == full)

        let tiles = harness.arranger.homeTiles()

        #expect(tiles == [a.identity: home[a], b.identity: home[b], c.identity: home[c]].compactMapValues { $0 })
    }

    /// 06 UI-SPEC Surface 4 / Surface 1 Availability: Show Overview needs zoom and access, not a display, and works paused.
    @Test func showOverviewIsAvailableWhilePausedButNotWithoutAccessOrZoom() async throws {
        var harness = try await threeDocked()
        let ready = CommandContext(focused: nil, ready: true), notReady = CommandContext(focused: nil, ready: false)
        #expect(!harness.arranger.availability(.camera(.overview), context: ready), "zoom off")
        await harness.send(.zoomEnabled(true))
        #expect(harness.arranger.availability(.camera(.overview), context: ready))
        #expect(!harness.arranger.availability(.camera(.overview), context: notReady))
        await harness.send(.setPaused(.user, true))
        #expect(harness.arranger.availability(.camera(.overview), context: ready))
        #expect(!harness.arranger.availability(.camera(.zoomOutAll), context: CommandContext(focused: nil, ready: true, displayUUID: "main")))
    }

    /// 06-06: the overview's main area on a zoomed display is the home view, never the parked frames.
    @Test func homeViewIsNilAtHomeAndTheHomeTilesWhileZoomed() async throws {
        var harness = try await threeDocked()
        let home = await frames(harness)
        await harness.send(.zoomEnabled(true))
        #expect(harness.arranger.homeView(on: "main") == nil)
        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))

        let view = try #require(harness.arranger.homeView(on: "main"))

        #expect(view.frames[a] == home[a] && view.frames[b] == home[b] && view.frames[c] == home[c])
        #expect(view.collapsed.isEmpty)
    }

    @Test func tilesAreSortedByIdentity() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))

        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(b, harness)), displayUUID: "main"))).first)

        let ids = move.tiles.map(\.window.identity)
        #expect(ids == ids.sorted())
        #expect(ids.count == 3)
    }

    // 05-02: the gesture preview (E-03) and targets (D-02). Previews change no camera state; the commit is zoomTo.

    @Test func previewMoveIsTheNextZoomToMoveAndChangesNothing() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let target = ViewTarget.node(try leaf(a, harness))
        let pending = harness.arranger.camera.pending, nextID = harness.arranger.camera.nextMoveID

        let preview = try #require(harness.arranger.previewMove(to: target, displayUUID: "main"))

        #expect(harness.arranger.camera.pending == pending && harness.arranger.camera.nextMoveID == nextID)
        #expect(preview.id == 0 && preview.displayUUID == "main" && preview.from == .home && preview.to == target)
        let move = try #require(moves(await harness.send(.zoomTo(target, displayUUID: "main"))).first)
        #expect(move.tiles == preview.tiles)
        #expect(move.from == preview.from && move.to == preview.to)
    }

    @Test func previewMoveWhilePendingStartsFromThePendingTarget() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let first = ViewTarget.node(try leaf(a, harness))
        try #require(moves(await harness.send(.zoomTo(first, displayUUID: "main"))).count == 1)  // never settled
        let pending = harness.arranger.camera.pending, nextID = harness.arranger.camera.nextMoveID

        let preview = try #require(harness.arranger.previewMove(to: .home, displayUUID: "main"))

        #expect(preview.from == first && preview.to == .home)
        #expect(harness.arranger.camera.pending == pending && harness.arranger.camera.nextMoveID == nextID)
        let retarget = try #require(moves(await harness.send(.zoomTo(.home, displayUUID: "main"))).first)
        #expect(retarget.tiles == preview.tiles)
    }

    @Test func previewMoveIsNilWhenTheCameraCannotMove() async throws {
        var harness = try await threeDocked()
        let target = ViewTarget.node(try leaf(a, harness))
        #expect(harness.arranger.previewMove(to: target, displayUUID: "main") == nil, "zoom off")
        await harness.send(.zoomEnabled(true))
        #expect(harness.arranger.previewMove(to: target, displayUUID: "nowhere") == nil, "unknown display")
        #expect(harness.arranger.previewMove(to: .home, displayUUID: "main") == nil, "already shown")
        #expect(harness.arranger.previewMove(to: .node(NodeID(raw: 9_999)), displayUUID: "main") == nil, "no such node")
        #expect(harness.arranger.stillMove(displayUUID: "nowhere") == nil)

        await harness.send(.command(.togglePause, focused: nil))

        #expect(harness.arranger.previewMove(to: target, displayUUID: "main") == nil, "paused")
        #expect(harness.arranger.stillMove(displayUUID: "main") == nil, "paused")
    }

    @Test func stillMoveIsTheShownTilesStandingStill() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let target = ViewTarget.node(try leaf(a, harness))
        let move = try #require(moves(await harness.send(.zoomTo(target, displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        let camera = harness.arranger.camera

        let still = try #require(harness.arranger.stillMove(displayUUID: "main"))

        #expect(still.id == 0 && still.from == target && still.to == target)
        #expect(still.tiles.map(\.window) == [a])
        #expect(still.tiles.allSatisfy { $0.start == $0.end && $0.kind == .stay })
        #expect(still.tiles.first?.end == full)
        #expect(harness.arranger.camera.pending == camera.pending && harness.arranger.camera.nextMoveID == camera.nextMoveID)
        #expect(harness.arranger.camera.views == camera.views)
    }

    @Test func gestureTargetsFollowThePinchPoint() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))
        let tree = try #require(harness.arranger.world[key]?.tree)
        let frameB = try #require(await harness.frame(b))
        let underB = Navigator.ancestors(of: try leaf(b, harness), in: tree)[1]  // the root's child holding b
        let pointer = Point(x: frameB.midX, y: frameB.midY)

        #expect(harness.arranger.gestureTarget(.pinchIn, displayUUID: "main", pointer: pointer) == .success(.node(underB)))
        #expect(harness.arranger.gestureTarget(.pinchOut, displayUUID: "main", pointer: pointer) == .failure(.alreadyHome))
        #expect(harness.arranger.gestureTarget(.pan(.right), displayUUID: "main", pointer: pointer) == .failure(.noArea(.right)))

        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))

        #expect(harness.arranger.gestureTarget(.pinchIn, displayUUID: "main", pointer: pointer) == .failure(.nothingToZoomIn))
    }
}

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

/// Same windows, every rect within 1 pt (the fake reports whole points; plans can be half points).
private func sameTiles(_ x: [WindowRef: Rect], _ y: [WindowRef: Rect?]) -> Bool {
    let y = y.compactMapValues { $0 }
    return Set(x.keys) == Set(y.keys) && x.allSatisfy { window, r in
        y[window].map { abs(r.x - $0.x) <= 1 && abs(r.y - $0.y) <= 1 && abs(r.width - $0.width) <= 1 && abs(r.height - $0.height) <= 1 } ?? false
    }
}

private let d = ref(4), e = ref(5)
private let sideKey = DeskKey(displayUUID: "side", spaceID: nil)

/// D-D, 04-08: parked windows come back through Restore All, a crash relaunch and a crash-loop relaunch.
extension ArrangerCameraTests {
    /// a, b, c docked on main; d, e docked on the side display; zoom on.
    private func twoDisplays() async throws -> (Harness, home: [WindowRef: Rect]) {
        var harness = try await threeDocked()
        await harness.fake.setDisplays([mainDisplay, side])
        await harness.fake.open(.standard(id: 4, pid: pid, frame: Rect(x: 1600, y: 100, width: 300, height: 200)))
        await harness.fake.open(.standard(id: 5, pid: pid, frame: Rect(x: 2600, y: 600, width: 300, height: 200)))
        await harness.refresh()
        await harness.fake.advance(by: .milliseconds(300))  // new windows wait out the settle delay
        await harness.refresh()
        await harness.send(.inventory(await harness.fake.inventory()))
        for window in [d, e] { await harness.send(.command(.dock, focused: window)) }
        try #require(harness.arranger.world[sideKey].map { Set($0.tree.windows) } == [d, e])
        var home: [WindowRef: Rect] = [:]
        for window in [a, b, c, d, e] { home[window] = try #require(await harness.frame(window)) }
        await harness.send(.zoomEnabled(true))
        return (harness, home)
    }

    private func zoom(_ harness: inout Harness, to window: WindowRef, on uuid: String) async throws {
        let target = try #require(harness.arranger.world[DeskKey(displayUUID: uuid, spaceID: nil)]?.tree.leaf(containing: window))
        let move = try #require(moves(await harness.send(.zoomTo(.node(target), displayUUID: uuid))).first)
        await harness.send(.cameraSettle(displayUUID: uuid, moveID: move.id))
    }

    @Test func restoreAllReturnsEveryCameraHome() async throws {
        var (harness, home) = try await twoDisplays()
        try await zoom(&harness, to: a, on: "main")
        try await zoom(&harness, to: d, on: "side")
        try #require(await harness.fake.parked.isSuperset(of: [b.identity, c.identity, e.identity]))

        let effects = await harness.send(.command(.restoreAll, focused: nil))

        #expect(harness.arranger.view(on: "main") == .home && harness.arranger.view(on: "side") == .home)
        for window in [a, b, c, d, e] { #expect(await harness.frame(window) == home[window], "\(window) is not back in its tile") }
        #expect(notices(effects) == [.restored(count: 3)], "N6 counts the three un-parked windows")
    }

    /// Paused: the rescue brings the parked windows on screen at once; the tiles wait for Resume (Phase 3).
    @Test func restoreAllWhilePausedUnparksAndResumeTilesEveryWindow() async throws {
        var (harness, home) = try await twoDisplays()
        try await zoom(&harness, to: a, on: "main")
        await harness.send(.command(.togglePause, focused: nil))

        let effects = await harness.send(.command(.restoreAll, focused: nil))

        #expect(harness.arranger.view(on: "main") == .home)
        #expect(notices(effects) == [.restored(count: 2)])
        for window in [b, c] {
            let frame = try #require(await harness.frame(window))
            #expect(!Recovery.isStranded(frame, displays: [mainDisplay, side]), "\(window) is still parked at \(frame)")
        }
        await harness.send(.command(.togglePause, focused: nil))
        for window in [a, b, c, d, e] { #expect(await harness.frame(window) == home[window], "\(window) is not back in its tile") }
    }

    /// A session that crashed zoomed to a: b and c parked, a filling the display. Returns the fresh Arranger's launch
    /// effects (launch, restore, first inventory, zoom on, as ArrangeController.start sends them) and the home tiles.
    private func relaunchAfterACrashWhileZoomed(_ mode: LaunchMode) async throws -> (Arranger, [ArrangerEffect], home: [WindowRef: Rect], Harness) {
        var source = try await threeDocked()
        let home = await frames(source)
        await source.send(.zoomEnabled(true))
        try await zoom(&source, to: a, on: "main")
        try #require(await source.fake.parked == [b.identity, c.identity])
        let snapshot = source.arranger.snapshot
        var restored = Arranger()
        var effects = restored.handle(.launch(mode), now: .now)
        effects += restored.handle(.restore(snapshot.world, homeFrames: snapshot.homeFrames, wantedFrames: snapshot.wantedFrames), now: .now)
        effects += restored.handle(.inventory(await source.fake.inventory()), now: .now)
        effects += restored.handle(.zoomEnabled(true), now: .now)
        return (restored, effects, home, source)
    }

    @Test func aRecoveryLaunchBringsParkedDockedWindowsBack() async throws {
        let (restored, effects, home, _) = try await relaunchAfterACrashWhileZoomed(.recovery)

        let sent = performs(effects)
        try #require(sent.count >= 2, "expected the rescue, then the layout: \(effects)")
        #expect(Set(setFrames([.perform(sent[0])]).keys) == [b, c], "the rescue moves the parked windows first")
        #expect(sameTiles(setFrames(effects), [a: home[a], b: home[b], c: home[c]]), "\(setFrames(effects)) vs \(home)")
        #expect(!sent.joined().contains { if case .park = $0 { true } else { false } }, "a window was parked again")
        #expect(restored.view(on: "main") == .home)
        #expect(notices(effects) == [.crashRecovered(unplaced: 0)])
    }

    @Test func aCrashLoopLaunchStillRescuesParkedDockedWindows() async throws {
        var (restored, effects, home, source) = try await relaunchAfterACrashWhileZoomed(.crashLoop)

        #expect(restored.pauseReasons == [.crashLoop])
        let rescued = setFrames(effects)
        #expect(Set(rescued.keys) == [b, c], "only the stranded windows move while paused: \(rescued)")
        for (window, frame) in rescued { #expect(!Recovery.isStranded(frame, displays: [mainDisplay]), "\(window) stays parked at \(frame)") }
        #expect(notices(effects) == [.crashLoop])
        await source.fake.perform(performs(effects).flatMap { $0 })
        let resumed = restored.handle(.command(.togglePause, focused: nil), now: .now)
        await source.fake.perform(performs(resumed).flatMap { $0 })
        var after: [WindowRef: Rect] = [:]
        for window in [a, b, c] { after[window] = await source.frame(window) }
        #expect(sameTiles(after, [a: home[a], b: home[b], c: home[c]]), "Resume puts every window in its tile: \(after)")
    }
}

/// CR-01, CR-02 (04-REVIEW): Restore All and Turn Off Zoom leave no window parked, collapsed ones included (D-D).
extension ArrangerCameraTests {
    /// a (870 pt tall at least, taller than the tile column; learned from a refused write) docked with zoom on,
    /// so a is collapsed and parked; b floats.
    private func collapsedA() async throws -> Harness {
        var harness = await Harness.started(frames: [
            1: Rect(x: 40, y: 10, width: 1360, height: 885), 2: Rect(x: 900, y: 400, width: 300, height: 200),
        ])
        await harness.fake.update(1) { $0.hiddenMinimum = Size(width: 100, height: 870) }
        // Zoom off: docked, written below its minimum, learned a second later, floated as lost room.
        await harness.send(.command(.dock, focused: a))
        await harness.fake.advance(by: .seconds(1.1))
        await harness.refresh()
        try #require(harness.arranger.windows[a.identity]?.learnedMinimum?.height == 870)
        try #require(harness.arranger.world[key]?.desktop.contains(a) == true)
        await harness.send(.zoomEnabled(true))
        await harness.send(.command(.dock, focused: a))
        try #require(harness.arranger.world[key]?.tree.state(of: a) == .present)
        try #require(await harness.fake.parked == [a.identity], "a was not collapsed")
        return harness
    }

    private func onScreen(_ window: WindowRef, _ harness: Harness) async throws {
        let frame = try #require(await harness.frame(window))
        #expect(!Recovery.isStranded(frame, displays: [mainDisplay]), "\(window) is still parked at \(frame)")
        #expect(await !harness.fake.parked.contains(window.identity), "\(window) was parked again")
    }

    @Test func restoreAllBringsACollapsedWindowBackOnScreen() async throws {
        var harness = try await collapsedA()

        let effects = await harness.send(.command(.restoreAll, focused: nil))

        try await onScreen(a, harness)
        #expect(!parks(effects).contains(.park(a, displayUUID: "main")), "a was parked again in the same perform")
        #expect(notices(effects).contains(.restored(count: 1)), "got \(notices(effects))")
        #expect(notices(effects).contains(.lostRoom([a])), "a floats with N1, as with zoom off")
        #expect(effects.contains(.collapsedBlocks([], displayUUID: "main")))
    }

    /// At home a is collapsed; zoomed to its leaf it is still collapsed and b, outside the view, is camera-parked.
    @Test(arguments: [false, true]) func turningZoomOffWhilePausedLeavesNoWindowParked(zoomedIn: Bool) async throws {
        var harness = try await collapsedA()
        if zoomedIn {
            let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(a, harness)), displayUUID: "main"))).first)
            await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
            try #require(await harness.fake.parked == [a.identity, b.identity])
        }
        await harness.send(.command(.togglePause, focused: nil))

        await harness.send(.zoomEnabled(false))

        #expect(harness.arranger.zoomEnabled == false)
        for window in [a, b] { try await onScreen(window, harness) }
    }
}

/// WR-05 (04-REVIEW): a move dropped because its display went away leaves no stale pending target behind.
extension ArrangerCameraTests {
    @Test func aMoveOnADisplayThatWentAwayIsForgotten() async throws {
        var (harness, _) = try await twoDisplays()
        try await zoom(&harness, to: d, on: "side")
        #expect(moves(await harness.send(.zoomTo(.home, displayUUID: "side"))).count == 1)  // never settles: the display goes

        await harness.send(.inventory(WindowInventory(displays: [mainDisplay], windows: Array(harness.arranger.windows.values), initialRefreshComplete: true)))
        await harness.send(.inventory(await harness.fake.inventory()))

        try #require(harness.arranger.view(on: "side") != .home, "the committed view is still the node")
        let effects = await harness.send(.zoomTo(.home, displayUUID: "side"))
        #expect(moves(effects).count == 1, "Zoom Out was refused against the dropped move's target: \(infos(effects))")
    }
}
