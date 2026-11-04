import Foundation
import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

/// Harness.refresh() refreshes this pid (ArrangerLifecycleTests).
private let pid: Int32 = 900
private let bundleID = "com.example.arranger"

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

/// Display A (Spaces 1, 2) and display B to its right (Spaces 3, 4), each with its own current Space.
private let visibleA = Rect(x: 0, y: 25, width: 1440, height: 875)
private let visibleB = Rect(x: 1440, y: 25, width: 1920, height: 1055)
private let displayA = DisplayInfo(uuid: "A", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visibleA, currentSpaceID: 1)
private let displayB = DisplayInfo(uuid: "B", frame: Rect(x: 1440, y: 0, width: 1920, height: 1080), visibleFrame: visibleB, currentSpaceID: 3)

/// Two windows per desk, both docked: [first | second | Desktop].
private struct DeskPlan {
    let key: DeskKey
    let ids: [UInt32]
    let visible: Rect
}

private let plans = [
    DeskPlan(key: DeskKey(displayUUID: "A", spaceID: 1), ids: [1, 2], visible: visibleA),
    DeskPlan(key: DeskKey(displayUUID: "A", spaceID: 2), ids: [3, 4], visible: visibleA),
    DeskPlan(key: DeskKey(displayUUID: "B", spaceID: 3), ids: [5, 6], visible: visibleB),
    DeskPlan(key: DeskKey(displayUUID: "B", spaceID: 4), ids: [7, 8], visible: visibleB),
]

/// The first window on the left of its display; the second small and inside the right half, as in ArrangerLifecycleTests.
private func startFrame(_ index: Int, on visible: Rect) -> Rect {
    index == 0
        ? Rect(x: visible.minX + 40, y: 80, width: 320, height: 232)
        : Rect(x: visible.minX + 730, y: 400, width: 150, height: 120)
}

/// A real relaunch (G-03-8): a NEW window system, whose tracker knows nothing, over the same running windows. Each
/// display shows its Space in `shown` with no notification, then the initial sweep runs. The caller feeds `.launch`,
/// `.restore` and the first inventory. `locked`: the screen is locked during that sweep (G-03-10).
private func relaunched(
    with windows: [FakeWindow], displays: [DisplayInfo], showing shown: [String: UInt64],
    apps: [FakeApp] = [FakeApp(pid: pid, bundleID: bundleID)], locked: Bool = false
) async -> Harness {
    let harness = Harness()
    await harness.fake.setDisplays(displays)
    await harness.fake.setSpacesAvailable(true)
    for app in apps { await harness.fake.addApp(app) }
    for window in windows.sorted(by: { $0.id < $1.id }) { await harness.fake.open(window) }
    for (uuid, space) in shown.sorted(by: { $0.key < $1.key }) { await harness.fake.showSpace(space, onDisplay: uuid, notifies: false) }
    if locked { await harness.fake.setLocked(true) }
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    return harness
}

private let deskA1 = DeskKey(displayUUID: "A", spaceID: 1)
private let deskA2 = DeskKey(displayUUID: "A", spaceID: 2)

/// Session 1 on display A alone: window 1 docked on Space 1, then `space2` docked on Space 2 in order, and Space 1
/// shown at the end. Returns the session, its saved layout and every docked window's tile.
private func firstSession(space2: [UInt32]) async throws -> (harness: Harness, saved: World, homeFrames: [WindowIdentity: Rect], tiles: [WindowRef: Rect]) {
    var harness = Harness()
    await harness.fake.setDisplays([displayA])
    await harness.fake.setSpacesAvailable(true)
    await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await harness.fake.open(.standard(id: 1, pid: pid, frame: startFrame(0, on: visibleA), space: 1))
    for (index, id) in space2.enumerated() {
        await harness.fake.open(.standard(id: id, pid: pid, frame: startFrame(index, on: visibleA), space: 2))
    }
    await harness.fake.showSpace(1, onDisplay: "A", notifies: false)
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.inventory(await harness.fake.inventory()))
    await harness.send(.command(.dock, focused: ref(1)))
    _ = await harness.switchDisplay("A", to: 2)
    for id in space2 {
        try #require(harness.arranger.deskKey(of: ref(id)) == deskA2, "window \(id) is not on Space 2")
        await harness.send(.command(.dock, focused: ref(id)))
    }
    _ = await harness.switchDisplay("A", to: 1)
    let saved = harness.arranger.world
    try #require(saved[deskA1]?.tree.windows == [ref(1)] && saved[deskA2]?.tree.windows == space2.map(ref))
    var tiles: [WindowRef: Rect] = [:]
    for id in [1] + space2 { tiles[ref(id)] = try #require(await harness.frame(ref(id))) }
    return (harness, saved, harness.arranger.snapshot.homeFrames, tiles)
}

/// Every setFrame Transom sent `window` on this fake.
private func writes(to window: WindowRef, on fake: FakeWindowSystem) async -> [Rect] {
    await fake.performed.compactMap { if case .setFrame(window, let rect) = $0 { rect } else { nil } }
}

/// A fresh-fake relaunch with Space 1 shown: window 1 tracked and docked on Space 1, window 3 dormant on Space 2.
private func dormantRelaunch() async throws -> (harness: Harness, tiles: [WindowRef: Rect]) {
    let first = try await firstSession(space2: [3])
    var harness = await relaunched(with: Array(await first.harness.fake.windows.values), displays: [displayA], showing: ["A": 1])
    await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
    await harness.send(.inventory(await harness.fake.inventory()))
    try #require(harness.arranger.world[deskA2]?.tree.windows == [ref(3)])
    return (harness, first.tiles)
}

extension Harness {
    /// A Space switch on one display as the live shell sees it: the notification's events, then a refresh, then the
    /// settle delay, so windows first seen on that Space are reported.
    mutating func switchDisplay(_ uuid: String, to space: UInt64) async -> [ArrangerEffect] {
        await fake.showSpace(space, onDisplay: uuid)
        var effects: [ArrangerEffect] = []
        for event in await inbox.take() {
            let next = arranger.handle(.event(event), now: now)
            effects += next
            for case .perform(let commands) in next { await fake.perform(commands) }
        }
        effects += await refresh()
        await fake.advance(by: .milliseconds(300))
        effects += await refresh()
        return effects
    }
}

/// D-16, D-25, SAFE-06: every (display, Space) desk survives layout.json and a relaunch, and each window comes back
/// on its own display and Space, in its own tile.
@Suite struct ArrangerMultiDeskRestoreTests {
    @Test func twoDisplaysWithTwoSpacesEachRestoreEveryDeskToItsOwnDisplayAndSpace() async throws {
        var harness = Harness()
        await harness.fake.setDisplays([displayA, displayB])
        await harness.fake.setSpacesAvailable(true)
        await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        for plan in plans {
            for (index, id) in plan.ids.enumerated() {
                await harness.fake.open(.standard(id: id, pid: pid, frame: startFrame(index, on: plan.visible), space: plan.key.spaceID))
            }
        }
        await harness.fake.showSpace(1, onDisplay: "A", notifies: false)
        await harness.fake.showSpace(3, onDisplay: "B", notifies: false)
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.inventory(await harness.fake.inventory()))

        // Dock the shown desks, then show each display's second Space and dock that one: A on 2, B on 4 at the end.
        for plan in plans {
            if let space = plan.key.spaceID, space == 2 || space == 4 {
                _ = await harness.switchDisplay(plan.key.displayUUID, to: space)
            }
            for id in plan.ids {
                try #require(harness.arranger.deskKey(of: ref(id)) == plan.key, "window \(id) is not on \(plan.key)")
                await harness.send(.command(.dock, focused: ref(id)))
            }
        }
        try #require(harness.arranger.displays.map(\.currentSpaceID) == [2, 4])

        let saved = harness.arranger.world
        #expect(Set(saved.desks.keys) == Set(plans.map(\.key)))
        var tiles: [WindowRef: Rect] = [:]
        for plan in plans {
            let desk = try #require(saved[plan.key])
            #expect(desk.tree.windows == plan.ids.map(ref), "desk \(plan.key): \(desk.tree.windows)")
            for id in plan.ids {
                let tile = try #require(await harness.frame(ref(id)))
                #expect(inside(tile, plan.visible), "window \(id) tile \(tile) is not on display \(plan.key.displayUUID)")
                tiles[ref(id)] = tile
            }
        }

        // Saved as LayoutStore saves it (sorted keys), read back as it loads.
        let snapshot = harness.arranger.snapshot
        let file = LayoutFile(world: snapshot.world, homeFrames: snapshot.homeFrames,
                              session: SessionRecord(cleanExit: true, launchedAt: Date()))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let decoded = try JSONDecoder().decode(LayoutFile.self, from: try encoder.encode(file))
        #expect(decoded == file)
        #expect(Set(decoded.world.desks.keys) == Set(plans.map(\.key)))

        // While Transom is not running, one window on each shown desk is moved out of its tile.
        let movedA = ref(3), movedB = ref(7)
        await harness.fake.userMove(movedA.windowID, to: Rect(x: 200, y: 200, width: 400, height: 300))
        await harness.fake.userMove(movedB.windowID, to: Rect(x: 1700, y: 200, width: 400, height: 300))
        _ = await harness.inbox.take()

        // Relaunch: a fresh window system and Arranger restore the decoded layout at the first complete inventory.
        harness = await relaunched(with: Array(await harness.fake.windows.values), displays: [displayA, displayB], showing: ["A": 2, "B": 4])
        await harness.send(.restore(decoded.world, homeFrames: decoded.homeFrameMap))
        let restoredEffects = await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.world == saved)
        #expect(setFrames(restoredEffects) == [movedA: tiles[movedA], movedB: tiles[movedB]],
                "only the two moved windows on shown desks are put back: \(setFrames(restoredEffects))")
        for plan in plans {
            #expect(harness.arranger.world[plan.key]?.tree.windows == plan.ids.map(ref))
            for id in plan.ids { #expect(harness.arranger.deskKey(of: ref(id)) == plan.key, "window \(id) restored off \(plan.key)") }
        }

        // The hidden desks were restored too: showing them moves nothing, and every window sits in its tile.
        let shownA = await harness.switchDisplay("A", to: 1)
        let shownB = await harness.switchDisplay("B", to: 3)
        #expect(setFrames(shownA + shownB).isEmpty, "showing a restored desk moved \(setFrames(shownA + shownB))")
        for plan in plans {
            for id in plan.ids {
                #expect(await harness.frame(ref(id)) == tiles[ref(id)], "window \(id) is not in its tile")
                #expect(harness.arranger.windows[ref(id).identity]?.displayUUID == plan.key.displayUUID)
            }
        }
        #expect(harness.arranger.world == saved)
    }

    /// G-03-8: a window docked on a Space not shown at relaunch is not tracked (AX lists only the shown Space), but it is
    /// still alive in the CG list. It stays in its desk, and showing its Space re-attaches it in its tile, writing nothing.
    @Test(arguments: [LaunchMode.normal, .recovery])
    func aDeskOnASpaceNotShownAtRelaunchKeepsItsWindowsInTheirTiles(mode: LaunchMode) async throws {
        let first = try await firstSession(space2: [3])
        var harness = await relaunched(with: Array(await first.harness.fake.windows.values), displays: [displayA], showing: ["A": 1])
        await harness.send(.launch(mode))
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.world == first.saved)
        #expect(harness.arranger.world[deskA2]?.tree.windows == [ref(3)], "the Space 2 desk lost window 3")

        _ = await harness.switchDisplay("A", to: 2)
        #expect(harness.arranger.world[deskA2]?.tree.windows == [ref(3)])
        #expect(await harness.frame(ref(3)) == first.tiles[ref(3)])
        #expect(await writes(to: ref(3), on: harness.fake) == [], "window 3 was already in its tile")
        #expect(harness.arranger.world == first.saved)
    }

    /// A dormant window whose tile changed while it was not tracked (its neighbour closed before the relaunch) is
    /// written once, to its new tile, when its Space is shown.
    @Test func aDormantWindowWhoseTileChangedIsWrittenOnceToItsNewTile() async throws {
        let first = try await firstSession(space2: [3, 4])
        // Window 4 closed while Transom was not running: the fresh window system never sees it.
        let carried = await first.harness.fake.windows.values.filter { $0.id != 4 }
        var harness = await relaunched(with: carried, displays: [displayA], showing: ["A": 1])
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        // Its tile waits like any unattached window's (D-12), so window 3's tile changes when it expires.
        #expect(harness.arranger.isPlaceholder(ref(4)))
        harness.now += Arranger.launchWait
        await harness.send(.tick)
        let desk = try #require(harness.arranger.world[deskA2])
        #expect(desk.tree.windows == [ref(3)], "window 4 is removed and window 3 kept: \(desk.tree.windows)")

        _ = await harness.switchDisplay("A", to: 2)
        let tile = try #require(try Planner.plan(desk: desk, area: visibleA, gap: harness.arranger.gap, mins: [:]).frames[ref(3)])
        let old = try #require(first.tiles[ref(3)])
        #expect(tile.width > old.width)
        #expect(await writes(to: ref(3), on: harness.fake) == [tile])
        #expect(await harness.frame(ref(3)) == tile)
        #expect(harness.arranger.world[deskA2]?.tree.windows == [ref(3)])
    }

    /// The VIEW-04 boundary: a saved window whose app relaunched has a new pid, so it is not the saved window; on a
    /// Space not shown it is not tracked either, so nothing re-matches it: its tile waits out its deadline, then closes.
    @Test func aSavedWindowWhoseAppRelaunchedOnAHiddenSpaceWaitsThenCloses() async throws {
        let first = try await firstSession(space2: [3])
        let relaunchedPID: Int32 = 901
        var carried = Array(await first.harness.fake.windows.values)
        for i in carried.indices where carried[i].id == 3 { carried[i].pid = relaunchedPID }
        var harness = await relaunched(
            with: carried, displays: [displayA], showing: ["A": 1],
            apps: [FakeApp(pid: pid, bundleID: bundleID), FakeApp(pid: relaunchedPID, bundleID: bundleID)])
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.isPlaceholder(ref(3)))
        harness.now += Arranger.launchWait
        await harness.send(.tick)
        let holds3 = harness.arranger.world.desks.values.contains { desk in
            (desk.tree.windows + desk.desktop.windows.map(\.window)).contains { $0.windowID == 3 }
        }
        #expect(!holds3, "a window of the relaunched app was kept")
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1)])
    }

    @Test func aDormantWindowIsNoLongerDormantOnceItsSpaceIsShown() async throws {
        var (harness, _) = try await dormantRelaunch()
        #expect(harness.arranger.hasDormantWindows)
        _ = await harness.switchDisplay("A", to: 2)
        #expect(!harness.arranger.hasDormantWindows)
    }

    /// G-03-8 prune: a dormant window that closed (its ID left the CG list) leaves its desk, so layout.json drops it.
    @Test func aDormantWindowThatLeftTheCGListIsPrunedWithNoUndoStep() async throws {
        var (harness, tiles) = try await dormantRelaunch()
        let history = harness.arranger.history
        await harness.fake.close(3)
        await harness.fake.refreshAll()
        let effects = await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.world[deskA2]?.contains(ref(3)) != true)
        #expect(effects.contains(.save(.debounced)))
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1)])
        #expect(await harness.frame(ref(1)) == tiles[ref(1)])
        #expect(harness.arranger.history == history)
        #expect(!harness.arranger.hasDormantWindows)
    }

    @Test func aDormantWindowStillInTheCGListIsKeptByEveryInventory() async throws {
        var (harness, _) = try await dormantRelaunch()
        let world = harness.arranger.world
        for _ in 0..<3 {
            await harness.fake.refreshAll()
            let effects = await harness.send(.inventory(await harness.fake.inventory()))
            #expect(!effects.contains(.save(.debounced)))
        }
        #expect(harness.arranger.world == world)
    }

    /// Its app quit: dormant windows of that pid close now; a tracked one of the same pid waits for its windowDestroyed.
    @Test func aDormantWindowIsPrunedWhenItsAppTerminates() async throws {
        var (harness, _) = try await dormantRelaunch()
        await harness.send(.event(.appTerminated(pid: pid)))
        #expect(harness.arranger.world[deskA2]?.contains(ref(3)) != true)
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1)], "the tracked window was closed by appTerminated")
    }

    /// Nothing is decided blind: a locked session, an unknown CG list or an empty one prunes nothing (T-03-63).
    @Test func aBlankOrUnknownCGListPrunesNothing() async throws {
        var (harness, _) = try await dormantRelaunch()
        let world = harness.arranger.world
        await harness.fake.close(3)
        await harness.fake.setLocked(true)
        let locked = await harness.fake.inventory()
        #expect(locked.sessionPaused && locked.liveWindows == nil)
        await harness.send(.inventory(locked))
        #expect(harness.arranger.world == world, "a locked inventory pruned")
        await harness.fake.setLocked(false)

        var unknown = await harness.fake.inventory()
        unknown.liveWindows = nil
        await harness.send(.inventory(unknown))
        var empty = unknown
        empty.liveWindows = []
        await harness.send(.inventory(empty))
        #expect(harness.arranger.world == world, "an unknown or empty CG list pruned")
    }

    /// CR-01: a tab group keeps its oldest member's identity for life, but a fresh window system founds it under its
    /// shown tab. The saved leader, now a hidden tab on the shown Space, is no hidden-Space window, so identity does not
    /// keep it; the hint matcher gives its tile to the group under its new leader (the sole pair of the app, D-10), so
    /// the group is docked once and never also floating. Whether the hidden tab reports the Space or none, as the live
    /// lookup may answer.
    @Test(arguments: [false, true])
    func aTabGroupShownUnderAnotherTabAtRelaunchIsNotKeptTwice(hiddenTabsReportSpace: Bool) async throws {
        func setUp(_ harness: Harness) async {
            await harness.fake.setDisplays([displayA])
            await harness.fake.setSpacesAvailable(true)
            await harness.fake.setHiddenTabsReportSpace(hiddenTabsReportSpace)
            await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        }
        var first = Harness()
        await setUp(first)
        await first.fake.open(.standard(id: 1, pid: pid, frame: startFrame(0, on: visibleA), space: 1))
        await first.fake.tabGroup(ids: [10, 11], frame: startFrame(1, on: visibleA), pid: pid, visible: 10, space: 1)
        await first.fake.showSpace(1, notifies: false)
        await first.fake.refreshAll()
        _ = await first.inbox.take()
        await first.send(.inventory(await first.fake.inventory()))
        await first.send(.command(.dock, focused: ref(1)))
        await first.send(.command(.dock, focused: ref(10)))
        await first.fake.selectTab(11)
        _ = await first.refresh()
        await first.fake.advance(by: .milliseconds(300))
        _ = await first.refresh()
        try #require(first.arranger.windows[ref(10).identity]?.visibleMemberID == 11)
        let saved = first.arranger.world
        try #require(saved[deskA1]?.tree.windows == [ref(1), ref(10)])

        var harness = Harness()
        await setUp(harness)
        for window in await first.fake.windows.values.sorted(by: { $0.id < $1.id }) { await harness.fake.open(window) }
        await harness.fake.selectTab(11)
        await harness.fake.showSpace(1, notifies: false)
        await harness.fake.refreshAll()
        _ = await harness.inbox.take()
        await harness.send(.restore(saved, homeFrames: first.arranger.snapshot.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        try #require(harness.arranger.windows[ref(11).identity] != nil, "the fresh tracker founds the group under tab 11")
        #expect(!harness.arranger.hasDormantWindows)
        #expect(harness.arranger.deskKey(of: ref(10)) == nil, "the saved leader is kept as an empty docked tile")
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1), ref(11)])
        #expect(harness.arranger.world[deskA1]?.desktop.contains(ref(11)) == false)
    }

    /// CR-02, D-17: after a crash, a floating window parked on a hidden Space's desk (its Desktop hidden) comes back on
    /// screen at its home frame once that Space is shown, although it was dormant at the recovery restore.
    @Test func aParkedDormantFloaterComesBackOnScreenAfterACrash() async throws {
        var first = Harness()
        await first.fake.setDisplays([displayA])
        await first.fake.setSpacesAvailable(true)
        await first.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
        await first.fake.open(.standard(id: 1, pid: pid, frame: startFrame(0, on: visibleA), space: 1))
        await first.fake.open(.standard(id: 4, pid: pid, frame: startFrame(0, on: visibleA), space: 2))
        await first.fake.open(.standard(id: 3, pid: pid, frame: startFrame(1, on: visibleA), space: 2))
        await first.fake.showSpace(1, onDisplay: "A", notifies: false)
        await first.fake.refreshAll()
        _ = await first.inbox.take()
        await first.send(.inventory(await first.fake.inventory()))
        await first.send(.command(.dock, focused: ref(1)))
        _ = await first.switchDisplay("A", to: 2)
        await first.send(.command(.dock, focused: ref(4)))
        let home = try #require(await first.frame(ref(3)))
        await first.send(.command(.toggleDesktop, focused: ref(4)))
        try #require(await first.fake.parked.contains(ref(3).identity))
        _ = await first.switchDisplay("A", to: 1)
        let saved = first.arranger.world
        try #require(saved[deskA2]?.tree.isDesktopHidden == true && saved[deskA2]?.desktop.contains(ref(3)) == true)

        var harness = await relaunched(with: Array(await first.fake.windows.values), displays: [displayA], showing: ["A": 1])
        await harness.send(.launch(.recovery))
        await harness.send(.restore(saved, homeFrames: first.arranger.snapshot.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        try #require(harness.arranger.world[deskA2]?.desktop.contains(ref(3)) == true, "window 3 is not dormant on its desk")
        _ = await harness.switchDisplay("A", to: 2)
        let frame = try #require(await harness.frame(ref(3)))
        #expect(!Recovery.isStranded(frame, displays: [displayA]), "window 3 stayed parked at \(frame)")
        #expect(frame == home)
    }

    /// CR-03, T-03-63: a restore inventory from a locked session, or with a blank CG list, can't tell a closed saved
    /// window from one on a hidden Space. The restore waits and removes nothing; the next usable inventory runs it.
    /// The locked case is a pause that began after an unpaused initial sweep, before the first inventory was fed; a
    /// start while locked is aStartWhileLockedKeepsEveryDeskOnceUnlocked (G-03-10).
    @Test(arguments: [true, false])
    func aRestoreWaitsForAnUnlockedSessionAndANonEmptyCGList(locked: Bool) async throws {
        let first = try await firstSession(space2: [3])
        var harness = await relaunched(with: Array(await first.harness.fake.windows.values), displays: [displayA], showing: ["A": 1])
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        var blind = await harness.fake.inventory()
        if locked {
            // Locked after the initial sweep, before the first inventory: paused, nothing tracked, no CG list.
            blind.sessionPaused = true
            blind.windows = []
            blind.liveWindows = nil
        } else {
            blind.liveWindows = []
        }
        await harness.send(.inventory(blind))
        #expect(harness.arranger.world.desks.isEmpty, "the saved layout was re-attached from a blind inventory")
        #expect(harness.arranger.snapshot.world == first.saved)
        #expect(harness.arranger.awaitsRestore)

        await harness.send(.inventory(await harness.fake.inventory()))
        #expect(!harness.arranger.awaitsRestore)
        #expect(harness.arranger.world == first.saved)
        #expect(harness.arranger.world[deskA2]?.tree.windows == [ref(3)])
    }

    /// G-03-10, SAFE-06, CR-03: Transom started while the screen is locked. Its first sweep observes nothing, so it is not
    /// the initial one: the restore waits through the lock, and the post-resume sweep, now the initial one, tracks
    /// every window with no settle hold before the inventory is fed. Both desks come back, window 1 in its tile.
    @Test func aStartWhileLockedKeepsEveryDeskOnceUnlocked() async throws {
        let first = try await firstSession(space2: [3])
        var harness = await relaunched(with: Array(await first.harness.fake.windows.values), displays: [displayA], showing: ["A": 1], locked: true)
        #expect(await harness.fake.inventory().initialRefreshComplete == false, "a sweep while locked counted as the initial one")
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.awaitsRestore)
        #expect(harness.arranger.world.desks.isEmpty, "the saved layout was re-attached while locked")
        #expect(harness.arranger.snapshot.world == first.saved)

        // Unlock: the post-resume sweep, its events to the Arranger, then the inventory, as ArrangeController does.
        await harness.fake.setLocked(false)
        await harness.fake.refreshAll()
        #expect(await harness.fake.inventory().initialRefreshComplete)
        await harness.settle()
        await harness.send(.inventory(await harness.fake.inventory()))
        #expect(!harness.arranger.awaitsRestore)
        #expect(harness.arranger.world == first.saved, "the restore after unlock lost a desk")
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1)])
        #expect(harness.arranger.world[deskA2]?.tree.windows == [ref(3)])

        // The settle follow-up refresh admits nothing new: window 1 stays docked in its tile.
        await harness.fake.advance(by: .milliseconds(300))
        _ = await harness.refresh()
        #expect(harness.arranger.world == first.saved)
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1)])
        #expect(harness.arranger.world[deskA1]?.desktop.contains(ref(1)) != true, "window 1 ended floating")
        #expect(await harness.frame(ref(1)) == first.tiles[ref(1)])
    }

    /// CR-03: an unknown CG list decides nothing, so the restore never waits on a list that may not come: it runs at
    /// once and keeps every saved window it does not track, dormant until a usable list prunes the closed ones.
    @Test func aRestoreWithAnUnknownCGListKeepsEverySavedWindow() async throws {
        let first = try await firstSession(space2: [3])
        var harness = await relaunched(with: Array(await first.harness.fake.windows.values), displays: [displayA], showing: ["A": 1])
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        var unknown = await harness.fake.inventory()
        unknown.liveWindows = nil
        await harness.send(.inventory(unknown))
        #expect(!harness.arranger.awaitsRestore)
        #expect(harness.arranger.world == first.saved)
        #expect(harness.arranger.snapshot.world == first.saved)
        #expect(harness.arranger.hasDormantWindows)

        await harness.fake.close(3)
        await harness.fake.refreshAll()
        await harness.send(.inventory(await harness.fake.inventory()))
        #expect(harness.arranger.world[deskA2]?.contains(ref(3)) != true)
        #expect(harness.arranger.world[deskA1]?.tree.windows == [ref(1)])
    }

    /// WR-01: the shell reads the inventory after each event, so it can track a dormant window before that window's
    /// buffered windowCreated is handled. It re-attaches the window with its real state, as the windowCreated would.
    @Test func anInventoryThatTracksADormantWindowFirstAppliesItsRealState() async throws {
        let first = try await firstSession(space2: [3])
        var carried = Array(await first.harness.fake.windows.values)
        for i in carried.indices where carried[i].id == 3 { carried[i].snapshot.minimized = true }
        var harness = await relaunched(with: carried, displays: [displayA], showing: ["A": 1])
        await harness.send(.restore(first.saved, homeFrames: first.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        try #require(harness.arranger.world[deskA2]?.state(of: ref(3)) == .present)

        await harness.fake.showSpace(2, onDisplay: "A")
        await harness.fake.refresh(pid: pid)
        await harness.fake.advance(by: .milliseconds(300))
        await harness.fake.refresh(pid: pid)
        // The inventory first, then (in `send`'s settle) the buffered windowCreated.
        await harness.send(.inventory(await harness.fake.inventory()))
        let tracked = try #require(harness.arranger.windows[ref(3).identity])
        #expect(tracked.state != .present)
        #expect(harness.arranger.world[deskA2]?.state(of: ref(3)) == tracked.state)
    }

    /// WR-02, D-29: a dormant window whose app was excluded while it was dormant floats when it wakes, so it never keeps
    /// a docked tile that nothing writes and its neighbours can't take.
    @Test func aDormantWindowOfAnAppExcludedMeanwhileFloatsWhenItWakes() async throws {
        let other: Int32 = 901, otherBundle = "com.example.other"
        let apps = [FakeApp(pid: pid, bundleID: bundleID), FakeApp(pid: other, bundleID: otherBundle)]
        let excludedWindow = WindowRef(identity: WindowIdentity(windowID: 3, pid: other, bundleID: otherBundle))
        /// Every app refreshed, as the sweep does: `switchDisplay` refreshes only `pid`.
        func show(_ space: UInt64, on harness: inout Harness) async {
            await harness.fake.showSpace(space, onDisplay: "A")
            await harness.fake.refreshAll()
            await harness.settle()
            await harness.fake.advance(by: .milliseconds(300))
            await harness.fake.refreshAll()
            await harness.settle()
        }
        var first = Harness()
        await first.fake.setDisplays([displayA])
        await first.fake.setSpacesAvailable(true)
        for app in apps { await first.fake.addApp(app) }
        await first.fake.open(.standard(id: 1, pid: pid, frame: startFrame(0, on: visibleA), space: 1))
        await first.fake.open(.standard(id: 4, pid: pid, frame: startFrame(0, on: visibleA), space: 2))
        await first.fake.open(.standard(id: 3, pid: other, frame: startFrame(1, on: visibleA), space: 2))
        await first.fake.showSpace(1, onDisplay: "A", notifies: false)
        await first.fake.refreshAll()
        _ = await first.inbox.take()
        await first.send(.inventory(await first.fake.inventory()))
        await first.send(.command(.dock, focused: ref(1)))
        await show(2, on: &first)
        await first.send(.command(.dock, focused: ref(4)))
        await first.send(.command(.dock, focused: excludedWindow))
        await show(1, on: &first)
        let saved = first.arranger.world
        try #require(saved[deskA2]?.tree.windows == [ref(4), excludedWindow])

        var harness = await relaunched(with: Array(await first.fake.windows.values), displays: [displayA], showing: ["A": 1], apps: apps)
        await harness.send(.restore(saved, homeFrames: first.arranger.snapshot.homeFrames))
        await harness.send(.inventory(await harness.fake.inventory()))
        try #require(harness.arranger.world[deskA2]?.tree.windows == [ref(4), excludedWindow])
        await harness.fake.setExcluded([otherBundle])
        await harness.settle()
        await show(2, on: &harness)
        try #require(harness.arranger.windows[excludedWindow.identity]?.isExcluded == true)
        #expect(harness.arranger.world[deskA2]?.tree.windows == [ref(4)])
        #expect(harness.arranger.world[deskA2]?.desktop.contains(excludedWindow) == true)
    }

    /// WR-03, G-03-9: a dormant window whose CG entry is left on no Space (a closed window's lingering entry) is pruned.
    @Test func aDormantWindowWhoseCGEntryIsOnNoSpaceIsPruned() async throws {
        var (harness, _) = try await dormantRelaunch()
        var inventory = await harness.fake.inventory()
        inventory.liveWindows = inventory.liveWindows?.map { entry in
            var entry = entry
            if entry.windowID == 3 { entry.spaces = [] }
            return entry
        }
        await harness.send(.inventory(inventory))
        #expect(harness.arranger.world[deskA2]?.contains(ref(3)) != true)
        #expect(!harness.arranger.hasDormantWindows)
    }

    @Test func liveWindowsChangedAloneDoesNothing() async throws {
        var (harness, _) = try await dormantRelaunch()
        let world = harness.arranger.world
        #expect(harness.arranger.handle(.event(.liveWindowsChanged), now: harness.now).isEmpty)
        #expect(harness.arranger.world == world)
    }
}
