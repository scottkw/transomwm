@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"  // Harness's app
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = pid, bundleID: String = bundleID) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), f = ref(2)
/// Over the left half, where a's tile lands once a docks.
private let overA = Rect(x: 500, y: 100, width: 300, height: 200)

/// a docked on the left, f floating partly over a's tile.
private func docked() async -> Harness {
    var harness = await Harness.started(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: overA])
    await harness.send(.command(.dock, focused: a))
    return harness
}

/// Every command the window system ran that moves, parks or raises `window`.
private func touches(_ window: WindowRef, _ harness: Harness) async -> [WindowCommand] {
    await harness.fake.performed.filter { command in
        switch command {
        case .setFrame(let w, _), .park(let w, _, _), .raise(let w): w == window
        default: false
        }
    }
}

/// D-05, D-06, D-14: floating windows are plain macOS windows; Transom never frames, clamps, parks or raises them.
@Suite struct ArrangerFloatingTests {
    @Test func aFloatingWindowOverADockedTileIsNeverMoved() async throws {
        var harness = await docked()
        let tile = try #require(await harness.frame(a))
        try #require(overA.overlaps(tile), "f is clear of a's tile")
        await harness.send(.inventory(await harness.fake.inventory()))
        await harness.send(.tick)
        let further = Rect(x: 200, y: 150, width: 300, height: 200)
        await harness.fake.userMove(2, to: further)
        _ = await harness.refresh()
        await harness.send(.tick)

        #expect(await touches(f, harness).isEmpty)
        #expect(await harness.frame(f) == further)
        #expect(harness.arranger.world[key]?.desktop.frame(of: f) == further)
        #expect(await harness.frame(a) == tile)
    }

    /// D-06: a new floating window stays where its app opened it, even over a docked tile.
    @Test func aNewFloatingWindowStaysWhereItsAppPutIt() async throws {
        var harness = await docked()
        let n = ref(3), frame = Rect(x: 100, y: 300, width: 400, height: 250)
        await harness.fake.open(.standard(id: 3, pid: pid, frame: frame))
        await harness.fake.refreshAll()
        await harness.fake.advance(by: .milliseconds(300))  // a new window settles before it is reported
        await harness.fake.refreshAll()
        await harness.settle()

        #expect(harness.arranger.world[key]?.desktop.frame(of: n) == frame)
        #expect(await touches(n, harness).isEmpty)
        #expect(await harness.frame(n) == frame)
    }

    /// D-29: an excluded floating window is never moved or parked (from ArrangerDesktopTests).
    @Test func anExcludedFloatingWindowIsNeverMoved() async throws {
        var harness = await docked()
        let excludedBundle = "com.example.excluded"
        let x = ref(5, pid: 901, bundleID: excludedBundle), frame = Rect(x: 300, y: 300, width: 200, height: 150)
        await harness.fake.addApp(FakeApp(pid: 901, bundleID: excludedBundle))
        await harness.fake.open(.standard(id: 5, pid: 901, frame: frame))
        await harness.fake.refreshAll()
        await harness.fake.advance(by: .milliseconds(300))
        await harness.fake.refreshAll()
        await harness.settle()
        #expect(harness.arranger.world[key]?.desktop.contains(x) == true)
        await harness.fake.setExcluded([excludedBundle])
        await harness.settle()

        #expect(await harness.fake.parked.isEmpty)
        // D-29: the Arranger sends nothing for x for the window system's filter to drop.
        #expect(await harness.fake.dropped.isEmpty)
        #expect(await touches(x, harness).isEmpty)
        #expect(await harness.fake.windows[5]?.frame == frame)
    }

    /// G-03-6 retired: a floater takes no room, so one wider than the screen never floats a docked window.
    @Test func aFloaterBiggerThanTheScreenLeavesTheDockedWindowsAlone() async throws {
        var harness = await docked()
        let tile = try #require(await harness.frame(a))
        var info = try #require(harness.arranger.windows[f.identity])
        info.learnedMinimum = Size(width: 2000, height: 1000)

        let effects = await harness.send(.event(.windowChanged(info)))

        #expect(!effects.contains { if case .notice = $0 { true } else { false } })
        #expect(harness.arranger.world[key]?.tree.state(of: a) == .present)
        #expect(await harness.frame(a) == tile)
        #expect(await touches(f, harness).isEmpty)
    }

    /// D-14: zoomed into a's leaf, docked b is parked; floating f stays where it is, above the zoomed tile.
    @Test func aZoomedInViewLeavesFloatingWindowsOnScreen() async throws {
        let b = ref(3)
        var harness = await Harness.started(frames: [
            1: Rect(x: 40, y: 80, width: 320, height: 232), 2: overA, 3: Rect(x: 900, y: 500, width: 300, height: 200),
        ])
        await harness.send(.command(.dock, focused: a))
        await harness.send(.command(.dock, focused: b))
        await harness.send(.zoomEnabled(true))
        let leaf = try #require(harness.arranger.world[key]?.tree.leaf(containing: a))
        let zoom = await harness.send(.zoomTo(.node(leaf), displayUUID: "main"))
        let move = try #require(zoom.compactMap { if case .cameraMove(let move) = $0 { move } else { nil } }.first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))

        #expect(await harness.fake.parked == [b.identity])
        #expect(await touches(f, harness).isEmpty)
        #expect(await harness.frame(f) == overA)
    }

    /// D-26 with D-05: a docked window whose app grows past the screen floats at its own frame clamped into the visible
    /// frame, in one pass and one notice; its neighbours stay docked.
    @Test func aWindowThatLosesItsRoomFloatsOnScreenInOnePass() async throws {
        let b = ref(3), c = ref(4)
        let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
        var harness = await Harness.started(frames: [
            1: Rect(x: 40, y: 80, width: 320, height: 232), 3: Rect(x: 600, y: 500, width: 300, height: 200),
            4: Rect(x: 1000, y: 500, width: 300, height: 200),
        ])
        for window in [a, b, c] { await harness.send(.command(.dock, focused: window)) }
        var info = try #require(harness.arranger.windows[a.identity])
        info.frame = Rect(x: 900, y: 100, width: 1000, height: 300)  // past the right edge
        info.learnedMinimum = Size(width: 1430, height: 100)  // wider than the 1424 pt inner area

        let effects = await harness.send(.event(.windowChanged(info)))

        let clamped = Rect(x: 440, y: 100, width: 1000, height: 300)
        #expect(Planner.clamp(info.frame, into: visible) == clamped)
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.frame(of: a) == clamped)
        #expect(desk.tree.state(of: b) == .present && desk.tree.state(of: c) == .present)
        let notices = effects.compactMap { effect -> Notice? in if case .notice(let notice) = effect { notice } else { nil } }
        #expect(notices == [.lostRoom([a])])
        #expect(setFrames(effects)[a] == clamped)
    }

    /// D-08, UI-SPEC Surface 2: Dock Window ▸ Where It Is on a desk with no tree makes the window the first tile, filling
    /// the visible frame, as one undo step with no announcement.
    @Test func dockWhereItIsOnAnEmptyDeskFillsTheVisibleFrame() throws {
        let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
        var arranger = Arranger()
        _ = arranger.handle(.restore(try World(ids: IDSource(), desks: [key: Desk(tree: LayoutTree())]), homeFrames: [:]), now: .now)
        let info = WindowInfo(window: f, frame: overA, state: .present, displayUUID: "main")
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: [info], initialRefreshComplete: true)), now: .now)
        let steps = arranger.history.depth(for: key)

        let effects = arranger.handle(.command(.dock, focused: f), now: .now)

        let desk = try #require(arranger.world[key])
        let root = try #require(desk.tree.root)
        #expect(desk.tree.leaf(containing: f) == root)
        #expect(!desk.desktop.contains(f))
        #expect(setFrames(effects)[f] == Rect(x: 8, y: 33, width: 1424, height: 859))
        #expect(arranger.history.depth(for: key) == steps + 1)
        #expect(!effects.contains(.beep))
        #expect(!effects.contains { if case .announce = $0 { true } else { false } }, "\(effects)")
    }

    /// RESEARCH Pitfall 3: a desk with no Desktop node, holding one docked tab group [b, c] filling the screen (c selected)
    /// and f floating.
    private func groupWithNoDesktopTile() throws -> (Arranger, GroupKey, frame: Rect) {
        let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
        let display = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil)
        let b = ref(3), c = ref(4)
        var arranger = Arranger()
        _ = arranger.handle(.restore(try World(ids: IDSource(), desks: [key: Desk(tree: LayoutTree())]), homeFrames: [:]), now: .now)
        let infos = [b, c, f].enumerated().map { i, window in
            WindowInfo(window: window, frame: Rect(x: 100 + 300 * Double(i), y: 100, width: 400, height: 300), state: .present, displayUUID: "main")
        }
        _ = arranger.handle(.inventory(WindowInventory(displays: [display], windows: infos, initialRefreshComplete: true)), now: .now)
        try arranger.world.edit(key, history: &arranger.history) { desk, ids throws(LayoutError) in
            try desk.desktop.remove(b)
            try desk.desktop.remove(c)
            try desk.tree.applyDrop(.emptyLayout, window: b, ids: &ids)
            guard let root = desk.tree.root else { throw .windowNotFound(b) }
            try desk.tree.group(c, into: root)
        }
        _ = arranger.handle(.gap(8), now: .now)  // re-plans
        let desk = try #require(arranger.world[key])
        try #require(!desk.tree.nodes.values.contains { if case .desktop = $0 { true } else { false } }, "precondition: the desk has a Desktop tile")
        let leaf = try #require(desk.tree.root)
        let frame = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).resolution.nodeRects[leaf])
        return (arranger, GroupKey(desk: key, node: leaf), frame)
    }

    @Test func moveOutOfGroupWorksOnADeskWithNoDesktopTile() throws {
        var (arranger, group, frame) = try groupWithNoDesktopTile()
        let b = ref(3), content = TabBand.content(of: frame)
        let size = arranger.wantedFrames[b.identity]?.size ?? content.size
        let expected = Arranger.moveOutFrame(size: size, group: frame, desktop: Rect(x: 0, y: 25, width: 1440, height: 875))

        let effects = arranger.handle(.tab(.moveOut(b, via: .menu), ready: true), now: .now)

        #expect(!effects.contains { if case .fault = $0 { true } else { false } }, "\(effects)")
        #expect(!effects.contains(.beep))
        let desk = try #require(arranger.world[key])
        #expect(desk.desktop.frame(of: b) == expected)
        #expect(desk.tree.node(group.node) == .panel(ref(4)))
    }

    @Test func floatGroupAndRestoreAllWorkOnADeskWithNoDesktopTile() throws {
        var (floating, _, _) = try groupWithNoDesktopTile()
        let toggled = floating.handle(.tab(.toggleGroupFloat(floating.tabGroup(holding: ref(4))!.key), ready: true), now: .now)
        #expect(!toggled.contains { if case .fault = $0 { true } else { false } } && !toggled.contains(.beep), "\(toggled)")
        #expect(floating.world[key]?.desktop.groups.count == 1)
        #expect(floating.world[key]?.tree.root == nil)

        var (restoring, _, _) = try groupWithNoDesktopTile()
        let restored = restoring.handle(.command(.restoreAll, focused: nil), now: .now)
        #expect(!restored.contains { if case .fault = $0 { true } else { false } }, "\(restored)")
        #expect(restoring.world[key]?.desktop.contains(ref(3)) == true)
    }
}
