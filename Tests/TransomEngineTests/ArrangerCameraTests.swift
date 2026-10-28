import TransomEngine
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

    @Test func tilesAreSortedByIdentity() async throws {
        var harness = try await threeDocked()
        await harness.send(.zoomEnabled(true))

        let move = try #require(moves(await harness.send(.zoomTo(.node(try leaf(b, harness)), displayUUID: "main"))).first)

        let ids = move.tiles.map(\.window.identity)
        #expect(ids == ids.sorted())
        #expect(ids.count == 3)
    }
}
