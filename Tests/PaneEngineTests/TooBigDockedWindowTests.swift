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
/// `height` is b's frame and minimum height: 887 is 28 pt over the 859 pt tile height, like Reminders' 692 in 664.
/// b's centre stays level with the Desktop tile's middle, so Dock puts it in the row beside a.
private func dockedBesideAWindowAtItsMinimum(height: Double = 300) async throws -> (Harness, Rect) {
    var harness = await Harness.started(frames: [
        1: Rect(x: 40, y: 312, width: 667, height: 300), 2: Rect(x: 600, y: max(33, 462 - height / 2), width: 783, height: height),
    ])
    await harness.fake.update(1) { $0.hiddenMinimum = Size(width: 627, height: 150) }
    await harness.fake.update(2) { $0.hiddenMinimum = Size(width: 783, height: height) }
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

    /// Reminders-like: width refused by hundreds of points, height by 28 pt. Only the width is learned; it still floats.
    @Test func aWindowRefusingWidthByHundredsAndHeightBy28LearnsTheWidthOnlyAndFloats() async throws {
        var (harness, tile) = try await dockedBesideAWindowAtItsMinimum(height: 887)
        #expect(tile.height == 859)
        await advance(&harness, by: .seconds(1))
        #expect(setFrames(await harness.send(.tick))[b] == tile)
        await advance(&harness, by: .seconds(1))
        let effects = await harness.refresh()
        #expect(harness.arranger.windows[b.identity]?.learnedMinimum == Size(width: 783, height: 0))
        #expect(notices(effects) == [.lostRoom([b])])
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.contains(b) && desk.tree.state(of: a) == .present)
        let floated = try #require(await harness.frame(b)), docked = try #require(await harness.frame(a))
        #expect(!floated.overlaps(docked))
    }

    /// The under-32 pt decision: a docked window refusing only its height by 28 pt is never retried or learned.
    @Test func anOverflowWithinTheMarginIsNeverRetriedOrLearned() async throws {
        var harness = await Harness.started(frames: [1: Rect(x: 40, y: 33, width: 320, height: 887)])
        await harness.fake.update(1) { $0.hiddenMinimum = Size(width: 0, height: 887) }
        let tile = try #require(setFrames(await harness.send(.command(.dock, focused: a)))[a])
        #expect(try #require(await harness.frame(a)).height == tile.height + 28)
        let writes = await harness.fake.performed.count
        for _ in 0..<3 {
            await advance(&harness, by: .seconds(1))
            #expect(setFrames(await harness.send(.tick)).isEmpty)
            _ = await harness.refresh()
        }
        #expect(await harness.fake.performed.count == writes)
        #expect(harness.arranger.windows[a.identity]?.learnedMinimum == nil)
        #expect(harness.arranger.world[key]?.tree.state(of: a) == .present)
    }
}

/// a docked alone, with its tile.
private func dockedAlone() async throws -> (Harness, Rect) {
    var harness = await Harness.started()
    let tile = try #require(setFrames(await harness.send(.command(.dock, focused: a)))[a])
    return (harness, tile)
}

/// A read-back of `tile` refused by 100 pt in width (as FrameWriter reports it: frameApplied, then the resize).
private func refuse(_ harness: inout Harness, _ window: WindowRef, _ tile: Rect) async -> [ArrangerEffect] {
    let actual = Rect(x: tile.x, y: tile.y, width: tile.width + 100, height: tile.height)
    return await harness.send(.event(.frameApplied(window, requested: tile, actual: actual)))
        + harness.send(.event(.windowResized(window, actual)))
}

private func hasWake(_ effects: [ArrangerEffect]) -> Bool {
    effects.contains { if case .wake = $0 { true } else { false } }
}

/// T-03-61: at most one retry per window and tile, and none for a floating, excluded, dragged or paused window.
@Suite struct RefusalRetryBoundTests {
    @Test func aRefusedTileIsRetriedOnceAndANewTileGetsOneNewRetry() async throws {
        var (harness, tile) = try await dockedAlone()
        #expect(hasWake(await refuse(&harness, a, tile)))
        await advance(&harness, by: .seconds(1))
        #expect(setFrames(await harness.send(.tick))[a] == tile)
        #expect(!hasWake(await refuse(&harness, a, tile)), "the same tile is not retried again")
        await advance(&harness, by: .seconds(1))
        #expect(setFrames(await harness.send(.tick))[a] == nil)

        let newTile = try #require(setFrames(await harness.send(.command(.dock, focused: b)))[a])
        #expect(newTile != tile)
        #expect(hasWake(await refuse(&harness, a, newTile)))
        await advance(&harness, by: .seconds(1))
        #expect(setFrames(await harness.send(.tick))[a] == newTile)
    }

    @Test func aFloatingWindowGetsNoRetry() async throws {
        var (harness, tile) = try await dockedAlone()
        await harness.send(.command(.float, focused: a))
        #expect(harness.arranger.isFloating(a))
        #expect(!hasWake(await refuse(&harness, a, tile)))
    }

    @Test func anExcludedWindowGetsNoRetry() async throws {
        var (harness, tile) = try await dockedAlone()
        var info = try #require(harness.arranger.windows[a.identity])
        info.isExcluded = true
        await harness.send(.event(.windowChanged(info)))
        #expect(!hasWake(await refuse(&harness, a, tile)))
    }

    @Test func theDraggedWindowGetsNoRetry() async throws {
        var (harness, tile) = try await dockedAlone()
        let press = PointerEvent(kind: .down, location: Point(x: tile.midX, y: tile.y + 10), modifiers: [], pressWindow: a)
        await harness.send(.pointer(press))
        #expect(harness.arranger.drag?.window == a)
        #expect(!hasWake(await refuse(&harness, a, tile)))
    }

    @Test func aPausedArrangerGetsNoRetry() async throws {
        var (harness, tile) = try await dockedAlone()
        await harness.send(.command(.togglePause, focused: nil))
        #expect(!harness.arranger.pauseReasons.isEmpty)
        #expect(!hasWake(await refuse(&harness, a, tile)))
    }
}
