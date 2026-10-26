import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, pid: Int32 = pid, bundleID: String = bundleID) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), f = ref(2), g = ref(3)
/// f and g sit well inside the right half, so docking a on the left leaves them clear of its tile.
private let homeF = Rect(x: 900, y: 100, width: 300, height: 200)
private let homeG = Rect(x: 950, y: 500, width: 300, height: 200)

/// Where `park` puts a window of `size`: the visibleFrame's bottom-right corner minus 1 pt, size kept.
private func parked(_ size: Size) -> Rect {
    Rect(x: visible.maxX - 1, y: visible.maxY - 1, width: size.width, height: size.height)
}

/// [a | Desktop] with f and g floating on the Desktop.
private func docked() async -> Harness {
    var harness = await Harness.started(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: homeF, 3: homeG])
    await harness.send(.command(.dock, focused: a))
    return harness
}

private func parks(_ effects: [ArrangerEffect]) -> [WindowCommand] {
    effects.flatMap { effect -> [WindowCommand] in
        guard case .perform(let commands) = effect else { return [] }
        return commands.filter { if case .park = $0 { true } else { false } }
    }
}

/// TILE-15, D-16, D-24, D-31: Hide Desktop Tile parks the floating windows (saving their home frames first) and gives
/// the docked tiles the whole screen; showing it again, or a new window arriving, brings every one of them home.
@Suite struct ArrangerDesktopTests {
    @Test func hidingSavesHomeFramesAtOnceThenParksTheFloatingWindowsAndTheTilesFillTheArea() async throws {
        var harness = await docked()
        let depth = harness.arranger.history.depth(for: key)

        let effects = await harness.send(.command(.toggleDesktop, focused: a))

        let desk = try #require(harness.arranger.world[key])
        #expect(desk.tree.isDesktopHidden == true)
        #expect(harness.arranger.history.depth(for: key) == depth + 1)
        #expect(parks(effects) == [.park(f, displayUUID: "main"), .park(g, displayUUID: "main")])
        let save = try #require(effects.firstIndex(of: .save(.now)), "no immediate save")
        let park = try #require(effects.firstIndex { if case .perform(let c) = $0 { c.contains(.park(f, displayUUID: "main")) } else { false } })
        #expect(save < park, "a window was parked before layout.json was written")
        #expect(harness.arranger.homeFrames == [f.identity: homeF, g.identity: homeG])
        let tile = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: [:]).frames[a])
        #expect(setFrames(effects)[a] == tile)
        #expect(tile.width >= visible.width - 17, "a does not fill the area: \(tile)")
        #expect(await harness.frame(f) == parked(homeF.size))
        #expect(await harness.frame(g) == parked(homeG.size))
        #expect(await harness.fake.parked == [f.identity, g.identity])
    }

    @Test func showingReturnsEachParkedWindowToItsHomeFrame() async throws {
        var harness = await docked()
        let before = try #require(await harness.frame(a))
        await harness.send(.command(.toggleDesktop, focused: a))
        let depth = harness.arranger.history.depth(for: key)

        let effects = await harness.send(.command(.toggleDesktop, focused: a))

        #expect(harness.arranger.world[key]?.tree.isDesktopHidden == false)
        #expect(harness.arranger.history.depth(for: key) == depth + 1)
        #expect(setFrames(effects)[f] == homeF && setFrames(effects)[g] == homeG)
        #expect(await harness.frame(f) == homeF)
        #expect(await harness.frame(g) == homeG)
        #expect(await harness.frame(a) == before)
        #expect(harness.arranger.homeFrames.isEmpty)
        #expect(await harness.fake.parked.isEmpty)
        #expect(parks(effects).isEmpty)
    }

    @Test func hidingIsRefusedWithABeepWhileNoDockedWindowIsPresent() async throws {
        var harness = await Harness.started(frames: [2: homeF, 3: homeG])
        #expect(!harness.arranger.isAvailable(.toggleDesktop, focused: f))
        let world = harness.arranger.world
        #expect(await harness.send(.command(.toggleDesktop, focused: f)) == [.beep])
        #expect(harness.arranger.world == world)

        var minimized = await docked()
        await minimized.send(.event(.windowStateChanged(a, .absent)))
        let before = minimized.arranger.world
        #expect(await minimized.send(.command(.toggleDesktop, focused: f)) == [.beep])
        #expect(minimized.arranger.world == before)
        #expect(await minimized.fake.parked.isEmpty)
    }

    @Test func aNewWindowWhileHiddenShowsTheDesktopAndFloatsThere() async throws {
        var harness = await docked()
        await harness.send(.command(.toggleDesktop, focused: a))
        #expect(harness.arranger.world[key]?.tree.isDesktopHidden == true)
        let depth = harness.arranger.history.depth(for: key)
        let n = ref(4), frame = Rect(x: 1000, y: 300, width: 200, height: 150)

        await harness.fake.open(.standard(id: 4, pid: pid, frame: frame))
        _ = await harness.refresh()
        await harness.fake.advance(by: .milliseconds(300))  // a new window settles before it is reported
        _ = await harness.refresh()

        let desk = try #require(harness.arranger.world[key])
        #expect(desk.tree.isDesktopHidden == false)
        #expect(desk.desktop.contains(n))
        #expect(harness.arranger.history.depth(for: key) == depth, "showing for a new window added an undo step")
        #expect(await harness.frame(f) == homeF)
        #expect(await harness.frame(g) == homeG)
        #expect(await harness.fake.parked.isEmpty)
        #expect(harness.arranger.homeFrames.isEmpty)
    }

    /// CR-02: with a second display to the right, hiding the Desktop must not park its windows onto that display.
    @Test func hidingNeverParksAWindowOntoTheDisplayBeside() async throws {
        var harness = await docked()
        let side = DisplayInfo(
            uuid: "side", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
            currentSpaceID: nil)
        await harness.fake.setDisplays([DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible, currentSpaceID: nil), side])

        await harness.send(.command(.toggleDesktop, focused: a))

        #expect(await harness.fake.parked == [f.identity, g.identity])
        for window in [f, g] {
            let frame = try #require(await harness.frame(window))
            #expect(!frame.overlaps(side.frame), "\(window) was parked onto the display beside: \(frame)")
        }
    }

    @Test func undoOfTheHideShowsTheDesktopAndUnparks() async throws {
        var harness = await docked()
        let before = try #require(await harness.frame(a))
        await harness.send(.command(.toggleDesktop, focused: a))

        await harness.send(.command(.undo, focused: a))

        #expect(harness.arranger.world[key]?.tree.isDesktopHidden == false)
        #expect(await harness.frame(f) == homeF)
        #expect(await harness.frame(g) == homeG)
        #expect(await harness.frame(a) == before)
        #expect(await harness.fake.parked.isEmpty)
        #expect(harness.arranger.homeFrames.isEmpty)
    }

    @Test func anExcludedFloatingWindowIsNeverParked() async throws {
        var harness = await docked()
        let excludedBundle = "com.example.excluded"
        let x = ref(5, pid: 901, bundleID: excludedBundle), frame = Rect(x: 1100, y: 300, width: 200, height: 150)
        await harness.fake.addApp(FakeApp(pid: 901, bundleID: excludedBundle))
        await harness.fake.open(.standard(id: 5, pid: 901, frame: frame))
        await harness.fake.refreshAll()
        await harness.fake.advance(by: .milliseconds(300))  // a new window settles before it is reported
        await harness.fake.refreshAll()
        await harness.settle()
        #expect(harness.arranger.world[key]?.desktop.contains(x) == true)
        await harness.fake.setExcluded([excludedBundle])
        await harness.settle()

        await harness.send(.command(.toggleDesktop, focused: a))

        #expect(await harness.fake.parked == [f.identity, g.identity])
        // D-29: the Arranger no longer even sends the park for the window system's filter to drop.
        #expect(await harness.fake.dropped.isEmpty)
        #expect(await harness.frame(x) == frame)
        #expect(harness.arranger.homeFrames[x.identity] == nil)
    }
}
