import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let newPID: Int32 = 901
private let bundleID = "com.example.arranger"
private let otherBundle = "com.example.other"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32, title: String = "", pid: Int32 = pid, bundle: String = bundleID, order: UInt64 = 0) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundle), titleHint: title, creationOrder: order)
}

private func tracked(_ window: WindowRef, frame: Rect = Rect(x: 300, y: 300, width: 400, height: 300)) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "main")
}

/// A window of the relaunched app, under a new pid.
private func returning(_ id: UInt32, title: String) -> WindowInfo { tracked(ref(id, title: title, pid: newPID)) }

/// [Notes (1) | Plan (2) | Other (3) | Desktop]: two docked windows of one app, titled, beside another app's.
private func threeDocked() async -> Harness {
    var harness = Harness()
    await harness.fake.setDisplays([DisplayInfo(
        uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875), currentSpaceID: nil)])
    await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await harness.fake.addApp(FakeApp(pid: 950, bundleID: otherBundle))
    await harness.fake.open(.standard(id: 1, pid: pid, frame: Rect(x: 40, y: 80, width: 320, height: 232), title: "Notes"))
    await harness.fake.open(.standard(id: 2, pid: pid, frame: Rect(x: 730, y: 400, width: 150, height: 120), title: "Plan"))
    await harness.fake.open(.standard(id: 3, pid: 950, frame: Rect(x: 1000, y: 600, width: 150, height: 120), title: "Other"))
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.inventory(await harness.fake.inventory()))
    for window in [ref(1), ref(2), ref(3, pid: 950, bundle: otherBundle)] { await harness.send(.command(.dock, focused: window)) }
    return harness
}

/// ⌘Q as the shell reports it: `.appTerminated`, then each window's `.windowDestroyed`.
private func quit(_ harness: inout Harness) async -> [ArrangerEffect] {
    var effects = await harness.send(.event(.appTerminated(pid: pid)))
    for id: UInt32 in [1, 2] { effects += await harness.send(.event(.windowDestroyed(ref(id)))) }
    return effects
}

private func tiles(_ harness: Harness) async -> [Rect] {
    var rects: [Rect] = []
    for id: UInt32 in [1, 2] { if let frame = await harness.frame(ref(id)) { rects.append(frame) } }
    return rects
}

private let openFrame = Rect(x: 300, y: 300, width: 400, height: 300)
private let otherApp = FakeWindow.standard(id: 3, pid: 950, frame: Rect(x: 1000, y: 600, width: 150, height: 120), title: "Other")

/// A saved layout. The saved windows belong to the last session's pid.
private func saved(_ build: (inout Desk, inout IDSource) throws(LayoutError) -> Void) throws -> World {
    var world = World()
    try world.addDesk(key)
    try world.reflow(key, build)
    return world
}

/// [Notes (1) | Plan (2) | Desktop] saved, under the last session's pid.
private func savedTwo() throws -> World {
    try saved { desk, ids throws(LayoutError) in
        try desk.tree.insert(ref(1, title: "Notes"), at: .left, of: .desktop, ids: &ids)
        guard let leaf = desk.tree.leaf(containing: ref(1)) else { throw .windowNotFound(ref(1)) }
        try desk.tree.insert(ref(2, title: "Plan"), at: .right, of: leaf, ids: &ids)
    }
}

/// Transom launches on `layout` with `open` tracked. Another app's window is always open: an empty CG list decides nothing.
private func launched(_ layout: World, open: [FakeWindow] = []) async -> Harness {
    var harness = Harness()
    await harness.fake.setDisplays([DisplayInfo(
        uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: Rect(x: 0, y: 25, width: 1440, height: 875), currentSpaceID: nil)])
    await harness.fake.addApp(FakeApp(pid: newPID, bundleID: bundleID))
    await harness.fake.addApp(FakeApp(pid: 950, bundleID: otherBundle))
    for window in open + [otherApp] { await harness.fake.open(window) }
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.restore(layout, homeFrames: [:]))
    await harness.send(.inventory(await harness.fake.inventory()))
    return harness
}

private func wakes(_ effects: [ArrangerEffect]) -> [ContinuousClock.Instant] {
    effects.compactMap { if case .wake(let at) = $0 { at } else { nil } }
}

private func logged(_ effects: [ArrangerEffect], _ text: String) -> Bool {
    effects.contains { if case .info(let line) = $0 { line.contains(text) } else { false } }
}

private func ticked(_ harness: inout Harness, at instant: ContinuousClock.Instant) async -> [ArrangerEffect] {
    harness.now = instant
    return await harness.send(.tick)
}

/// VIEW-04, D-11, D-12, D-12a: a window that has not come back keeps its tile until it does, or until its deadline.
@Suite struct ArrangerPlaceholderTests {
    @Test func quitThenRelaunchRefillsBothTiles() async throws {
        var harness = await threeDocked()
        let tiled = await tiles(harness)
        try #require(tiled.count == 2)

        let held = await quit(&harness)
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2, 3], "both refs stay in the tree")
        #expect(harness.arranger.isPlaceholder(ref(1)) && harness.arranger.isPlaceholder(ref(2)))
        #expect(harness.arranger.placeholderCount == 2)
        #expect(setFrames(held).isEmpty, "a quit writes nothing: the neighbour does not reflow")
        #expect(!harness.arranger.hasDormantWindows, "a placeholder is not a dormant window, so nothing prunes it")

        await harness.send(.event(.appLaunched(pid: newPID, bundleID: bundleID)))
        // Reopened in the other order, so creation order alone would swap them.
        let plan = await harness.send(.event(.windowCreated(returning(12, title: "Plan"))))
        let notes = await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))

        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [11, 12, 3], "each window is back in its own leaf")
        #expect(harness.arranger.world[key]?.desktop.windows.isEmpty == true)
        #expect(harness.arranger.placeholderCount == 0)
        #expect(setFrames(plan)[ref(12, pid: newPID)] == tiled[1])
        #expect(setFrames(notes)[ref(11, pid: newPID)] == tiled[0])
        #expect((plan + notes).contains { if case .info(let line) = $0 { line.contains("filled by window 12") } else { false } })
    }

    /// Windows come back with a new identity: an inventory's CG list that lacks the old one must not close the tile.
    @Test func anInventoryNeverClosesAPlaceholder() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        var inventory = await harness.fake.inventory()
        inventory.windows.removeAll { $0.window.pid == pid }
        inventory.liveWindows = [CGWindowEntry(windowID: 3, pid: 950, bounds: Rect(x: 0, y: 0, width: 10, height: 10), layer: 0, onScreen: true, alpha: 1)]
        await harness.send(.inventory(inventory))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2, 3])
        #expect(harness.arranger.placeholderCount == 2)
    }

    /// A ⌘W in a quitting window's app, or any other app's window, is not a placeholder.
    @Test func onlyDockedWindowsOfTheQuittingPidWait() async throws {
        var harness = await threeDocked()
        await harness.send(.event(.appTerminated(pid: pid)))
        await harness.send(.event(.windowDestroyed(ref(3, pid: 950, bundle: otherBundle))))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2])
        #expect(!harness.arranger.isPlaceholder(ref(3, pid: 950, bundle: otherBundle)))
    }

    /// A placeholder keeps the latest title, which the World's ref may not have: `windows` is forgotten at the destroy.
    @Test func aPlaceholderKeepsItsWindowsLatestTitle() async throws {
        var harness = await threeDocked()
        await harness.fake.update(1) { $0.title = "Renamed" }
        _ = await harness.refresh()
        _ = await quit(&harness)
        #expect(harness.arranger.world[key]?.tree.windows.first?.titleHint == "Renamed")
    }

    /// D-02, RESEARCH Pitfall 3: a saved view follows the window that fills the placeholder.
    @Test func aSavedViewFollowsTheFilledPlaceholder() async throws {
        var harness = await threeDocked()
        await harness.send(.zoomEnabled(true))
        let leaf = try #require(harness.arranger.world[key]?.tree.leaf(containing: ref(1)))
        let move = try #require(harness.arranger.handle(.zoomTo(.node(leaf), displayUUID: "main"), now: harness.now).compactMap { effect -> CameraMove? in
            if case .cameraMove(let move) = effect { move } else { nil }
        }.first)
        await harness.send(.cameraSettle(displayUUID: "main", moveID: move.id))
        let slot = try #require(ViewSlot(1))
        await harness.send(.camera(.saveView(slot), displayUUID: "main", focused: nil, pointer: nil))
        _ = await quit(&harness)
        await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        #expect(harness.arranger.viewDestination(slot: slot)?.alive == 1)
        #expect(harness.arranger.world[key]?.tree.leaf(containing: ref(11, pid: newPID)) == leaf)
    }

    // MARK: Deadlines

    @Test func aQuitExpiresThirtySecondsLaterThroughTheClosePath() async throws {
        var harness = await threeDocked()
        let start = harness.now
        let depth = harness.arranger.history.depth(for: key)
        let held = await quit(&harness)
        #expect(wakes(held).contains(start + .seconds(30)), "the deadline is on the wake clock")

        let early = await ticked(&harness, at: start + .milliseconds(29_900))
        #expect(harness.arranger.placeholderCount == 2)
        #expect(setFrames(early).isEmpty)

        let due = await ticked(&harness, at: start + .seconds(30))
        #expect(harness.arranger.placeholderCount == 0)
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [3])
        #expect(setFrames(due)[ref(3, pid: 950, bundle: otherBundle)] != nil, "the neighbour takes the room")
        #expect(harness.arranger.history.depth(for: key) == depth, "not an undo step")
        #expect(logged(due, "expired (30 s after quit)"))
    }

    @Test func aLaunchSwitchesToTenSecondsAndEachNewWindowRestartsThem() async throws {
        var harness = await threeDocked()
        let start = harness.now
        _ = await quit(&harness)
        harness.now = start + .seconds(5)
        let launch = await harness.send(.event(.appLaunched(pid: newPID, bundleID: bundleID)))
        #expect(wakes(launch).contains(start + .seconds(15)))

        // A window that matches neither title moves both deadlines.
        harness.now = start + .seconds(12)
        await harness.send(.event(.windowCreated(returning(11, title: "Mail"))))
        #expect(harness.arranger.placeholderCount == 2)
        _ = await ticked(&harness, at: start + .seconds(16))
        #expect(harness.arranger.placeholderCount == 2, "the new window restarted the 10 s")
        _ = await ticked(&harness, at: start + .milliseconds(21_900))
        #expect(harness.arranger.placeholderCount == 2)
        let due = await ticked(&harness, at: start + .seconds(22))
        #expect(harness.arranger.placeholderCount == 0)
        #expect(logged(due, "expired (10 s after launch)"))
    }

    /// The last session's app is not running: 5 min, then the sliding 10 s once it launches.
    @Test func aSavedWindowWhoseAppNeverOpensWaitsFiveMinutes() async throws {
        var harness = await launched(try savedTwo())
        let start = harness.now
        #expect(harness.arranger.placeholderCount == 2)
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2])
        _ = await ticked(&harness, at: start + .milliseconds(299_900))
        #expect(harness.arranger.placeholderCount == 2)
        let due = await ticked(&harness, at: start + .seconds(300))
        #expect(harness.arranger.placeholderCount == 0)
        #expect(harness.arranger.world[key]?.tree.windows.isEmpty == true)
        #expect(logged(due, "expired (5 min, no launch)"))
    }

    @Test func aSavedWindowWhoseAppLaunchesLaterTakesTheTenSeconds() async throws {
        var harness = await launched(try savedTwo())
        let start = harness.now
        harness.now = start + .seconds(60)
        await harness.send(.event(.appLaunched(pid: newPID, bundleID: bundleID)))
        _ = await ticked(&harness, at: start + .seconds(70))
        #expect(harness.arranger.placeholderCount == 0)
    }

    /// The app runs at the restore with a window that matches nothing: 10 s, restarted by each new window.
    @Test func aSavedWindowWhoseAppIsRunningWaitsTenSecondsSliding() async throws {
        var harness = await launched(try savedTwo(), open: [.standard(id: 21, pid: newPID, frame: openFrame, title: "Mail")])
        let start = harness.now
        #expect(harness.arranger.placeholderCount == 2)
        harness.now = start + .seconds(8)
        await harness.send(.event(.windowCreated(returning(22, title: "Draft"))))
        _ = await ticked(&harness, at: start + .seconds(10))
        #expect(harness.arranger.placeholderCount == 2)
        _ = await ticked(&harness, at: start + .seconds(18))
        #expect(harness.arranger.placeholderCount == 0)
    }

    /// Nothing is reserved for a floating saved window, but it is kept until the same expiry, and a match takes its place.
    @Test func aFloatingSavedWindowIsKeptUntilExpiryWithoutATile() async throws {
        let frame = Rect(x: 100, y: 100, width: 300, height: 200)
        let layout = try saved { desk, _ throws(LayoutError) in try desk.desktop.add(ref(1, title: "Notes"), frame: frame) }
        var harness = await launched(layout)
        let start = harness.now
        #expect(harness.arranger.world[key]?.desktop.contains(ref(1)) == true)
        #expect(!harness.arranger.isPlaceholder(ref(1)))
        #expect(harness.arranger.placeholderCount == 0)
        _ = await ticked(&harness, at: start + .seconds(300))
        #expect(harness.arranger.world[key]?.contains(ref(1)) == false)
    }

    // MARK: Matching

    /// D-10: a tie fills nothing; the tile waits and the tied windows float, with one log line. (Equal creation orders: a
    /// different rank would settle it, as `HintMatcher` does for an app reopening its windows in order.)
    @Test func aTieAtRelaunchFillsNothingAndTheWindowsFloat() async throws {
        let layout = try saved { desk, ids throws(LayoutError) in
            try desk.tree.insert(ref(1, title: "Notes"), at: .left, of: .desktop, ids: &ids)
            guard let leaf = desk.tree.leaf(containing: ref(1)) else { throw .windowNotFound(ref(1)) }
            try desk.tree.insert(ref(2, title: "Notes"), at: .right, of: leaf, ids: &ids)
        }
        var harness = await launched(layout)
        let first = await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        let second = await harness.send(.event(.windowCreated(returning(12, title: "Notes"))))
        #expect(harness.arranger.placeholderCount == 2)
        let desk = try #require(harness.arranger.world[key])
        #expect(desk.desktop.contains(ref(11, pid: newPID)) && desk.desktop.contains(ref(12, pid: newPID)))
        #expect(desk.tree.windows.map(\.windowID) == [1, 2])
        #expect(logged(first, "tie at") && !logged(second, "tie at"), "one line, not one per event")
    }

    @Test func aTitleThatArrivesLateStillMatches() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        await harness.send(.event(.windowCreated(returning(11, title: ""))))
        #expect(harness.arranger.placeholderCount == 2, "an empty title scores below the threshold")
        await harness.send(.event(.windowChanged(returning(11, title: "Plan"))))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 11, 3])
        #expect(harness.arranger.isPlaceholder(ref(1)))
    }

    @Test func aCommittedMatchIsNeverUndone() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        await harness.send(.event(.windowChanged(returning(11, title: "Plan"))))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [11, 2, 3])
    }

    /// Only windows the user has not touched fill a placeholder (T-08-10).
    @Test func aWindowTheUserDockedOrDraggedFillsNothing() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        let docked = ref(11, pid: newPID)
        await harness.send(.event(.windowCreated(returning(11, title: ""))))
        await harness.send(.command(.dock, focused: docked))
        await harness.send(.event(.windowChanged(returning(11, title: "Notes"))))
        #expect(harness.arranger.placeholderCount == 2)
        #expect(harness.arranger.isPlaceholder(ref(1)))

        let dragged = ref(12, pid: newPID)
        await harness.send(.event(.windowCreated(tracked(dragged))))
        let grab = Point(x: openFrame.midX, y: openFrame.minY + 10)
        await harness.send(.pointer(PointerEvent(kind: .down, location: grab, pressWindow: dragged)))
        await harness.send(.pointer(PointerEvent(kind: .dragged, location: Point(x: grab.x + 10, y: grab.y))))
        await harness.send(.dragFrame(dragged.identity, Rect(x: openFrame.x + 10, y: openFrame.y, width: openFrame.width, height: openFrame.height)))
        await harness.send(.pointer(PointerEvent(kind: .up, location: Point(x: grab.x + 10, y: grab.y))))
        await harness.send(.event(.windowChanged(returning(12, title: "Plan"))))
        #expect(harness.arranger.isPlaceholder(ref(2)))
    }

    /// A saved window kept waiting that turns out to be alive (a failed AX read at the restore) is simply back.
    @Test func thePlaceholdersOwnWindowComingBackEndsTheWait() async throws {
        var harness = await launched(try savedTwo())
        await harness.send(.event(.windowCreated(tracked(ref(1, title: "Notes")))))
        #expect(!harness.arranger.isPlaceholder(ref(1)))
        #expect(harness.arranger.isPlaceholder(ref(2)))
        var inventory = await harness.fake.inventory()
        inventory.windows.append(tracked(ref(2, title: "Plan")))
        await harness.send(.inventory(inventory))
        #expect(harness.arranger.placeholderCount == 0)
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [1, 2])
    }

    // MARK: Pause

    /// UI-SPEC: expiry runs while paused; the reflow's writes wait for Resume (RESEARCH Pitfall 14).
    @Test func expiryRunsWhilePausedAndTheWritesWaitForResume() async throws {
        var harness = await threeDocked()
        let start = harness.now
        _ = await quit(&harness)
        await harness.send(.setPaused(.user, true))
        let due = await ticked(&harness, at: start + .seconds(30))
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID) == [3])
        #expect(setFrames(due).isEmpty)
        let resumed = await harness.send(.setPaused(.user, false))
        #expect(setFrames(resumed)[ref(3, pid: 950, bundle: otherBundle)] != nil)
    }

    /// UI-SPEC: a match while paused is recorded, and the window goes to its tile at Resume.
    @Test func aMatchWhilePausedIsWrittenAtResume() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        await harness.send(.setPaused(.user, true))
        let matched = await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        #expect(harness.arranger.world[key]?.tree.windows.first?.windowID == 11)
        #expect(setFrames(matched).isEmpty)
        let resumed = await harness.send(.setPaused(.user, false))
        #expect(setFrames(resumed)[ref(11, pid: newPID)] != nil)
    }

    // MARK: Tab groups

    /// [tab group: Notes (waiting), Live (selected at the restore moves off Notes) | Desktop].
    private func savedGroup(selectWaiting: Bool, live: WindowRef) throws -> World {
        try saved { desk, ids throws(LayoutError) in
            try desk.tree.insert(ref(1, title: "Notes"), at: .left, of: .desktop, ids: &ids)
            guard let leaf = desk.tree.leaf(containing: ref(1)) else { throw .windowNotFound(ref(1)) }
            try desk.tree.group(live, into: leaf)
            if selectWaiting { try desk.tree.selectTab(ref(1)) }
        }
    }

    @Test func aHiddenMemberMatchedBeforeExpiryRejoinsInItsPosition() async throws {
        let live = ref(21, title: "Live", pid: newPID)
        var harness = await launched(
            try savedGroup(selectWaiting: true, live: live), open: [.standard(id: 21, pid: newPID, frame: openFrame, title: "Live")])
        let leaf = try #require(harness.arranger.world[key]?.tree.leaf(containing: live))
        #expect(harness.arranger.world[key]?.tree.node(leaf) == .tabs(windows: [ref(1), live], selected: 1), "a live member shows while one waits")

        await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        #expect(harness.arranger.world[key]?.tree.node(leaf) == .tabs(windows: [ref(11, pid: newPID), live], selected: 1))
    }

    @Test func aHiddenMemberUnmatchedAtExpiryIsDropped() async throws {
        let live = ref(21, title: "Live", pid: newPID)
        var harness = await launched(
            try savedGroup(selectWaiting: false, live: live), open: [.standard(id: 21, pid: newPID, frame: openFrame, title: "Live")])
        let start = harness.now
        _ = await ticked(&harness, at: start + .seconds(10))
        #expect(harness.arranger.world[key]?.tree.windows == [live])
    }

    @Test func aGroupWhoseMembersAllWaitKeepsItsLeaf() async throws {
        var harness = await launched(try savedGroup(selectWaiting: false, live: ref(2, title: "Plan")))
        let leaf = try #require(harness.arranger.world[key]?.tree.leaf(containing: ref(1)))
        #expect(harness.arranger.world[key]?.tree.node(leaf) == .tabs(windows: [ref(1), ref(2)], selected: 1))
        await harness.send(.command(.restoreAll, focused: nil))
        #expect(harness.arranger.world[key]?.tree.node(leaf) == .tabs(windows: [ref(1), ref(2)], selected: 1), "Restore All leaves it")
        // A hidden member back first shows: the tile should not wait on a window that has not come back.
        await harness.send(.event(.windowCreated(returning(11, title: "Notes"))))
        #expect(harness.arranger.world[key]?.tree.node(leaf) == .tabs(windows: [ref(11, pid: newPID), ref(2)], selected: 0))
    }

    // MARK: Commands

    @Test func restoreAllArrangeAllAndUndoLeaveAPlaceholderInItsTile() async throws {
        var harness = await threeDocked()
        _ = await quit(&harness)
        let restored = await harness.send(.command(.restoreAll, focused: nil))
        #expect(setFrames(restored)[ref(1)] == nil)
        #expect(harness.arranger.placeholderCount == 2)

        await harness.send(.event(.windowCreated(tracked(ref(30, title: "New", pid: 950, bundle: otherBundle)))))
        await harness.send(.command(.arrangeAll, focused: nil))
        #expect(harness.arranger.placeholderCount == 2)
        #expect(harness.arranger.world[key]?.tree.windows.map(\.windowID).contains(30) == true)

        await harness.send(.command(.undo, focused: nil))
        #expect(harness.arranger.world[key]?.desktop.contains(ref(30, pid: 950, bundle: otherBundle)) == true)
        #expect(harness.arranger.placeholderCount == 2)
        #expect(!harness.arranger.hasDormantWindows)
    }
}
