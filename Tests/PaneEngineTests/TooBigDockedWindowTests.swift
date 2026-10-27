import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2)

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

/// Moves the Arranger's clock and the fake's (the tracker's) together.
private func advance(_ harness: inout Harness, by duration: Duration) async {
    harness.now += duration
    await harness.fake.advance(by: duration)
}

/// G-03-6 through the fake: a opens 40 pt above its 627 pt minimum, so its refused tile write moves it; b opens at
/// its 783 pt minimum (Reminders' Welcome window), so no write moves it. 627 + 783 cannot share the 1424 pt row with
/// the Desktop tile, but b fits on a Desktop tile beside a. Returns the harness and b's first tile.
private func dockedBesideAWindowAtItsMinimum() async throws -> (Harness, Rect) {
    var harness = await Harness.started(frames: [
        1: Rect(x: 40, y: 312, width: 667, height: 300), 2: Rect(x: 600, y: 312, width: 783, height: 300),
    ])
    await harness.fake.update(1) { $0.hiddenMinimum = Size(width: 627, height: 150) }
    await harness.fake.update(2) { $0.hiddenMinimum = Size(width: 783, height: 150) }
    await harness.send(.command(.dock, focused: a))
    let tile = try #require(setFrames(await harness.send(.command(.dock, focused: b)))[b])
    #expect(try #require(await harness.frame(b)).width == 783, "b refused its tile")
    return (harness, tile)
}

/// D-26, TILE-01: a docked window that cannot fit its tile floats to the Desktop instead of overlapping its neighbour.
@Suite struct TooBigDockedWindowTests {
    @Test func aDockedWindowAlreadyAtAMinimumWiderThanItsTileIsRetriedOnceThenFloats() async throws {
        var (harness, tile) = try await dockedBesideAWindowAtItsMinimum()
        #expect(harness.arranger.windows[b.identity]?.learnedMinimum == nil)

        await advance(&harness, by: .seconds(1))
        #expect(setFrames(await harness.send(.tick))[b] == tile, "the refused tile is written once more")
        #expect(setFrames(await harness.send(.tick))[b] == nil, "and only once")

        await advance(&harness, by: .seconds(1))
        let effects = await harness.refresh()
        #expect(harness.arranger.windows[b.identity]?.learnedMinimum?.width == 783)
        #expect(notices(effects) == [.lostRoom([b])])
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.contains(b) && desk.tree.state(of: a) == .present)
        let floated = try #require(await harness.frame(b)), docked = try #require(await harness.frame(a))
        #expect(!floated.overlaps(docked))
    }
}
