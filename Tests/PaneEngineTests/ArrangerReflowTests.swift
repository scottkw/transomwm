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
