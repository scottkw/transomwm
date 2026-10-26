import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3)

/// The Arranger's latest info for `window`, with a learned minimum `width` wide.
private func learned(_ harness: Harness, _ window: WindowRef, width: Double) throws -> WindowInfo {
    var info = try #require(harness.arranger.windows[window.identity])
    info.learnedMinimum = Size(width: width, height: 100)
    return info
}

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

/// [a | b | Desktop] on the 1440 pt display (inner width 1424 with the 8 pt gap).
private func twoDocked() async -> Harness {
    var harness = await Harness.started()
    await harness.send(.command(.dock, focused: a))
    await harness.send(.command(.dock, focused: b))
    return harness
}

/// D-26, TILE-03: a docked window that loses its room after docking floats to the Desktop with no undo step and a
/// notice, instead of overlapping its neighbours.
@Suite struct ArrangerReflowTests {
    @Test func aDockedWindowThatLosesItsRoomFloatsToTheDesktopWithANotice() async throws {
        var harness = await twoDocked()
        let depth = harness.arranger.history.depth(for: key)
        // b's 610 pt minimum still fits beside a.
        let fits = await harness.send(.event(.windowChanged(try learned(harness, b, width: 610))))
        #expect(notices(fits).isEmpty)
        #expect(harness.arranger.world[key]?.tree.state(of: b) == .present)
        // 800 + 610 + Desktop 1 + two gaps > 1424; beside a Desktop tile holding a, b still fits (610 + 800 + 8).
        let before = try #require(await harness.frame(a))
        let effects = await harness.send(.event(.windowChanged(try learned(harness, a, width: 800))))

        let desk = try #require(harness.arranger.world[key])
        #expect(desk.tree.state(of: a) == nil && desk.desktop.contains(a))
        #expect(desk.tree.state(of: b) == .present)
        let mins = [a: Size(width: 800, height: 100), b: Size(width: 610, height: 100)]
        let desktop = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: mins).desktopRect)
        #expect(desk.desktop.frame(of: a) == Planner.clamp(before, into: desktop))
        #expect(harness.arranger.history.depth(for: key) == depth, "a lost-room float added an undo step")
        #expect(notices(effects) == [.lostRoom([a])])
        let frames = setFrames(effects)
        let floated = try #require(frames[a]), docked = try #require(frames[b])
        #expect(!floated.overlaps(docked))
        #expect(await harness.frame(a) == floated)
    }

    @Test func windowsLosingRoomInOneReplanGiveOneNotice() async throws {
        var harness = await Harness.started(frames: [
            1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
            3: Rect(x: 1000, y: 400, width: 100, height: 120),
        ])
        for window in [a, b, c] { await harness.send(.command(.dock, focused: window)) }
        let docked = try #require(harness.arranger.world[key]).tree
        #expect(docked.state(of: a) == .present && docked.state(of: b) == .present && docked.state(of: c) == .present)

        // a (760) cannot share the row with c (700); floated, its minimum sizes the Desktop tile, and then c cannot
        // share the row with that tile either. b (no minimum) keeps its tile.
        var inventory = await harness.fake.inventory()
        for i in inventory.windows.indices {
            let width: Double? = [1: 760, 3: 700][inventory.windows[i].window.windowID]
            inventory.windows[i].learnedMinimum = width.map { Size(width: $0, height: 100) }
        }
        let effects = await harness.send(.inventory(inventory))
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.contains(a) && desk.desktop.contains(c))
        #expect(desk.tree.state(of: b) == .present)
        #expect(notices(effects) == [.lostRoom([a, c])])
    }
}

extension ArrangerReflowTests {
    /// The live scenario through the fake: the minimums come from refused writes (02-15), not from the test.
    /// 783 + 627 cannot share the 1424 pt row with the Desktop tile (+ 17), but 627 fits beside a Desktop tile
    /// holding the 783 pt window (+ 8).
    @Test func minimumsLearnedFromRefusedWritesFloatTheWiderWindowClearOfItsNeighbour() async throws {
        var harness = await Harness.started(frames: [
            1: Rect(x: 40, y: 312, width: 823, height: 300), 2: Rect(x: 900, y: 312, width: 667, height: 300),
        ])
        await harness.fake.update(1) { $0.hiddenMinimum = Size(width: 783, height: 150) }
        await harness.fake.update(2) { $0.hiddenMinimum = Size(width: 627, height: 150) }
        await harness.send(.command(.dock, focused: a))
        await harness.fake.advance(by: .seconds(1.1))
        _ = await harness.refresh()
        #expect(harness.arranger.windows[a.identity]?.learnedMinimum?.width == 783)

        await harness.send(.command(.dock, focused: b))
        #expect(harness.arranger.world[key]?.tree.state(of: b) == .present)
        await harness.fake.advance(by: .seconds(1.1))
        let effects = await harness.refresh()
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.contains(a) && desk.tree.state(of: b) == .present)
        #expect(notices(effects) == [.lostRoom([a])])
        let floated = try #require(await harness.frame(a)), docked = try #require(await harness.frame(b))
        #expect(!floated.overlaps(docked))
        #expect(floated.width == 783, "the floated window was written below its minimum")
    }
}

private func setFrameCount(_ effects: [ArrangerEffect]) -> Int {
    effects.reduce(0) { count, effect in
        guard case .perform(let commands) = effect else { return count }
        return count + commands.filter { if case .setFrame = $0 { true } else { false } }.count
    }
}

private func wakes(_ effects: [ArrangerEffect]) -> [ContinuousClock.Instant] {
    effects.compactMap { if case .wake(let at) = $0 { at } else { nil } }
}

private func moved(_ rect: Rect, by dx: Double, _ dy: Double) -> Rect {
    Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
}

/// The echo rule (03-01 discretion) and TILE-07: Pane's own writes are not moves; a docked window its app moved
/// goes back to its tile at most once per second; a floating window stays where it was left unless that is on a tile.
extension ArrangerReflowTests {
    @Test func panesOwnWriteComingBackWithin2PointsIsNotAMove() async throws {
        var harness = await twoDocked()
        let tile = try #require(await harness.frame(a))
        let performed = await harness.fake.performed.count
        let effects = await harness.send(.event(.windowMoved(a, moved(tile, by: 1.5, -1))))
        #expect(effects.isEmpty)
        #expect(await harness.fake.performed.count == performed)
    }

    @Test func aDockedWindowItsAppMovedIsPutBackAtMostOncePerSecond() async throws {
        var harness = await twoDocked()
        let tile = try #require(await harness.frame(a))
        let t0 = harness.now
        await harness.fake.userMove(1, to: moved(tile, by: 40, 30))
        let first = await harness.refresh()
        #expect(setFrameCount(first) == 1)
        #expect(setFrames(first)[a] == tile)
        #expect(await harness.frame(a) == tile)

        harness.now = t0 + .milliseconds(300)
        await harness.fake.userMove(1, to: moved(tile, by: 60, 10))
        let second = await harness.refresh()
        #expect(setFrameCount(second) == 0, "corrected twice within a second")
        #expect(wakes(second) == [t0 + .seconds(1)])

        harness.now = t0 + .seconds(1)
        let tick = await harness.send(.tick)
        #expect(setFrameCount(tick) == 1)
        #expect(setFrames(tick)[a] == tile)
        #expect(await harness.frame(a) == tile)
    }

    @Test func aFloatingWindowMovedInsideTheDesktopIsRecordedWhereItWasLeft() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: a))
        let depth = harness.arranger.history.depth(for: key)
        let target = Rect(x: 900, y: 300, width: 150, height: 120)
        await harness.fake.userMove(2, to: target)
        let effects = await harness.refresh()
        #expect(harness.arranger.world[key]?.desktop.frame(of: b) == target)
        #expect(harness.arranger.history.depth(for: key) == depth)
        #expect(setFrameCount(effects) == 0)
    }

    @Test func aFloatingWindowMovedOntoADockedTileIsClampedIntoTheDesktop() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.dock, focused: a))
        let depth = harness.arranger.history.depth(for: key)
        let target = Rect(x: 600, y: 300, width: 150, height: 120)
        await harness.fake.userMove(2, to: target)
        let effects = await harness.refresh()
        let desk = try #require(harness.arranger.world[key])
        let desktop = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).desktopRect)
        let clamped = Planner.clamp(target, into: desktop)
        #expect(setFrameCount(effects) == 1)
        #expect(setFrames(effects)[b] == clamped)
        #expect(desk.desktop.frame(of: b) == clamped)
        #expect(harness.arranger.history.depth(for: key) == depth)
    }

    @Test func aRefusedWriteReadBackIsAnEchoNotAMoveToUndo() async throws {
        var harness = await Harness.started()
        await harness.fake.update(1) { $0.hiddenMinimum = Size(width: 900, height: 100) }
        let effects = await harness.send(.command(.dock, focused: a))
        #expect(setFrameCount(effects) == 1)
        let actual = try #require(await harness.frame(a))
        #expect(actual.width == 900)
        // The frameApplied and windowResized the write caused were fed by `send`: nothing was written again.
        #expect(await harness.fake.performed.count == 1)
        let again = await harness.send(.event(.windowResized(a, actual)))
        #expect(again.isEmpty)
        #expect(await harness.fake.performed.count == 1)
    }

    @Test func aNarrowerDisplayThatLeavesADockedWindowNoRoomFloatsItWithOneNotice() async throws {
        var harness = await twoDocked()
        var inventory = await harness.fake.inventory()
        for i in inventory.windows.indices {
            inventory.windows[i].learnedMinimum = Size(width: inventory.windows[i].window == a ? 700 : 400, height: 100)
        }
        #expect(notices(await harness.send(.inventory(inventory))).isEmpty)
        let narrow = Rect(x: 0, y: 25, width: 1100, height: 875)
        inventory.displays = [DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1100, height: 900), visibleFrame: narrow, currentSpaceID: nil)]
        let effects = await harness.send(.inventory(inventory))
        let lost = notices(effects)
        #expect(lost.count == 1)
        guard case .lostRoom(let windows)? = lost.first else { return }
        #expect(windows.contains(a))
        #expect(harness.arranger.world[key]?.desktop.contains(a) == true)
    }
}
