import Testing
import TransomEngine
import TransomModel
import TransomTestSupport

private let pid: Int32 = 300
private let bundleID = "com.example.lifecycle"
private let key = DeskKey(displayUUID: "D1", spaceID: nil)
private let frame = Rect(x: 0, y: 25, width: 800, height: 600)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1)
private let b = ref(2)
private let c = ref(3)
private let y = ref(9)

private func info(_ window: WindowRef) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: .present, displayUUID: "D1")
}

/// Desk `key` with `windows` docked left to right, one user edit (and so one undo snapshot) per window.
private func world(_ windows: [WindowRef], history: inout UndoHistory) throws -> World {
    var world = World()
    try world.addDesk(key)
    var previous: WindowRef?
    for window in windows {
        try world.edit(key, history: &history) { (desk: inout Desk, ids: inout IDSource) throws(LayoutError) in
            if let previous, let leaf = desk.tree.leaf(containing: previous) {
                try desk.tree.insert(window, at: .right, of: leaf, ids: &ids)
            } else {
                try desk.tree.applyDrop(.layoutEdge(.right), window: window, ids: &ids)
            }
        }
        previous = window
    }
    return world
}

/// The user takes `window` off `key`'s desk with an undoable edit.
private func userRemoves(_ window: WindowRef, from world: inout World, history: inout UndoHistory) throws {
    try world.edit(key, history: &history) { (desk: inout Desk, _: inout IDSource) throws(LayoutError) in
        try desk.tree.remove(window)
    }
}

private func onAnyDesk(_ window: WindowRef, _ world: World) -> Bool {
    world.desks.values.contains { $0.contains(window) }
}

/// Undoes until history runs out, failing if any step brings `window` back.
private func undoAllNeverRevives(_ window: WindowRef, world: inout World, history: inout UndoHistory) throws {
    while try world.undo(key, history: &history) != nil {
        #expect(!onAnyDesk(window, world))
    }
}

/// A fake that knows `known` (one standard window per ID, all present after the initial sweep), with
/// `minimised` minimised and refreshed.
private func fake(knowing known: [WindowRef], minimised: [WindowRef] = []) async -> FakeWindowSystem {
    let fake = FakeWindowSystem()
    await fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    for window in known { await fake.open(.standard(id: window.windowID, pid: pid, frame: frame)) }
    await fake.refreshAll()
    for window in minimised { await fake.update(window.windowID) { $0.snapshot.minimized = true } }
    await fake.refreshAll()
    return fake
}

@Suite struct LifecycleSyncTests {
    // MARK: Task 1 — events reach the model only through World.apply

    @Test func stateChangedOnADockedWindowAppliesItWithoutTouchingUndo() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        let depth = history.depth(for: key)

        #expect(try LifecycleSync.handle(.windowStateChanged(a, .absent), world: &world, history: &history))
        #expect(world[key]?.state(of: a) == .absent)
        #expect(history.depth(for: key) == depth)
    }

    @Test func fullscreenThenPresentEndsPresentWithUndoUnchanged() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        let depth = history.depth(for: key)

        #expect(try LifecycleSync.handle(.windowStateChanged(a, .fullscreen), world: &world, history: &history))
        #expect(world[key]?.state(of: a) == .fullscreen)
        #expect(try LifecycleSync.handle(.windowStateChanged(a, .present), world: &world, history: &history))
        #expect(world[key]?.state(of: a) == .present)
        #expect(history.depth(for: key) == depth)
    }

    @Test func destroyingADockedWindowRemovesItAndNoUndoBringsItBack() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        let depth = history.depth(for: key)

        #expect(try LifecycleSync.handle(.windowDestroyed(a), world: &world, history: &history))
        #expect(!onAnyDesk(a, world))
        #expect(world[key]?.contains(b) == true)
        #expect(history.depth(for: key) == depth)
        try undoAllNeverRevives(a, world: &world, history: &history)
    }

    @Test func destroyingAWindowOnNoDeskStillPurgesItFromUndo() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        try userRemoves(b, from: &world, history: &history)
        #expect(!onAnyDesk(b, world))

        #expect(try LifecycleSync.handle(.windowDestroyed(b), world: &world, history: &history))
        let revived = try world.undo(key, history: &history)
        #expect(revived == [])
        #expect(!onAnyDesk(b, world))
        try undoAllNeverRevives(b, world: &world, history: &history)
    }

    @Test func destroyingAWindowInAWorldWithNoDesksDoesNotThrow() throws {
        var history = UndoHistory()
        var world = World()
        #expect(try LifecycleSync.handle(.windowDestroyed(a), world: &world, history: &history))
        #expect(world == World())
    }

    @Test func stateChangedForAWindowOnNoDeskChangesNothing() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        let (worldBefore, historyBefore) = (world, history)

        #expect(try !LifecycleSync.handle(.windowStateChanged(c, .absent), world: &world, history: &history))
        #expect(world == worldBefore)
        #expect(history == historyBefore)
    }

    @Test func stateChangedToClosedIsTheSameAsDestroyed() throws {
        var history = UndoHistory()
        let start = try world([a, b], history: &history)

        var (closedWorld, closedHistory) = (start, history)
        #expect(try LifecycleSync.handle(.windowStateChanged(a, .closed), world: &closedWorld, history: &closedHistory))
        var (destroyedWorld, destroyedHistory) = (start, history)
        #expect(try LifecycleSync.handle(.windowDestroyed(a), world: &destroyedWorld, history: &destroyedHistory))

        #expect(!onAnyDesk(a, closedWorld))
        #expect(closedWorld == destroyedWorld)
        #expect(closedHistory == destroyedHistory)
    }

    @Test(arguments: [
        WindowEvent.windowCreated(WindowInfo(window: ref(1), frame: frame, state: .present, displayUUID: "D1")),
        .windowMoved(ref(1), frame),
        .windowResized(ref(1), frame),
        .windowFocused(ref(1)),
        .windowChanged(WindowInfo(window: ref(1), frame: frame, state: .absent, displayUUID: "D1")),
        .frameApplied(ref(1), requested: frame, actual: frame),
        .appResponsiveness(pid: pid, degraded: true),
        .sessionPaused(true),
        .appLaunched(pid: pid, bundleID: bundleID),
        .appTerminated(pid: pid),
        .displaysChanged,
        .spaceChanged(displayUUID: "D1", spaceID: 7),
        .liveWindowsChanged,
    ])
    func nonLifecycleEventsLeaveTheWorldUnchanged(event: WindowEvent) throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        let (worldBefore, historyBefore) = (world, history)

        #expect(try !LifecycleSync.handle(event, world: &world, history: &history))
        #expect(world == worldBefore)
        #expect(history == historyBefore)
    }

    // MARK: 03-03 — a rekey re-points the desk and undo snapshots without an undo step

    @Test func aRekeyedDockedWindowKeepsItsTileWithNoUndoStep() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        try world.apply(.absent, for: a, on: key, history: &history)
        let depth = history.depth(for: key)

        #expect(try LifecycleSync.handle(.windowRekeyed(from: a, to: info(y)), world: &world, history: &history))
        #expect(world[key]?.tree.windows == [y, b])
        #expect(world[key]?.state(of: y) == .absent)
        #expect(!onAnyDesk(a, world))
        #expect(history.depth(for: key) == depth)
        // Undo of docking b restores the snapshot under the new ID.
        #expect(try LifecycleSync.undo(key, world: &world, history: &history) == RevivedWindows(key: key, windows: []))
        #expect(world[key]?.tree.windows == [y])
    }

    @Test func undoAfterARekeyRevivesTheNewIDAndRequeryFindsIt() async throws {
        let system = await fake(knowing: [a, y])
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        try userRemoves(b, from: &world, history: &history)

        #expect(try LifecycleSync.handle(.windowRekeyed(from: b, to: info(y)), world: &world, history: &history))
        let revived = try #require(try LifecycleSync.undo(key, world: &world, history: &history))
        #expect(revived.windows == [y])
        let states = await LifecycleSync.requery(revived, using: system)
        #expect(states.map(\.1) == [.present])
        try LifecycleSync.applyRequeried(states, on: key, world: &world, history: &history)
        #expect(world[key]?.tree.windows == [a, y])
    }

    // MARK: Task 2 — undo re-queries every revived window

    @Test func undoReviveOfAMinimisedWindowEndsAbsent() async throws {
        let system = await fake(knowing: [a, b], minimised: [b])
        #expect(await system.windowInfo(b)?.state == .absent)
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        try userRemoves(b, from: &world, history: &history)

        let revived = try LifecycleSync.undo(key, world: &world, history: &history)
        #expect(revived == RevivedWindows(key: key, windows: [b]))
        let states = await LifecycleSync.requery(try #require(revived), using: system)
        #expect(states.map(\.0) == [b])
        #expect(states.map(\.1) == [.absent])
        try LifecycleSync.applyRequeried(states, on: key, world: &world, history: &history)
        #expect(world[key]?.state(of: b) == .absent)
    }

    @Test func undoReviveOfAWindowTheSystemNoLongerKnowsClosesIt() async throws {
        let system = await fake(knowing: [a])
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        try userRemoves(b, from: &world, history: &history)

        let revived = try #require(try LifecycleSync.undo(key, world: &world, history: &history))
        #expect(revived.windows == [b])
        #expect(onAnyDesk(b, world))
        let states = await LifecycleSync.requery(revived, using: system)
        #expect(states.map(\.0) == [b])
        #expect(states.map(\.1) == [.closed])
        try LifecycleSync.applyRequeried(states, on: key, world: &world, history: &history)
        #expect(!onAnyDesk(b, world))
        try undoAllNeverRevives(b, world: &world, history: &history)
    }

    @Test func undoWithNothingToUndoReturnsNil() throws {
        var history = UndoHistory()
        var world = World()
        try world.addDesk(key)
        #expect(try LifecycleSync.undo(key, world: &world, history: &history) == nil)
    }

    @Test func undoThatRevivesNothingReturnsAnEmptyListAndApplyingItChangesNothing() throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)

        let revived = try LifecycleSync.undo(key, world: &world, history: &history)
        #expect(revived == RevivedWindows(key: key, windows: []))
        #expect(world[key]?.contains(b) == false)
        let (worldBefore, historyBefore) = (world, history)
        try LifecycleSync.applyRequeried([], on: key, world: &world, history: &history)
        #expect(world == worldBefore)
        #expect(history == historyBefore)
    }

    @Test func requeryPreservesTheRevivedOrder() async {
        let system = await fake(knowing: [a, b], minimised: [b])
        let states = await LifecycleSync.requery(RevivedWindows(key: key, windows: [c, a, b]), using: system)
        #expect(states.map(\.0) == [c, a, b])
        #expect(states.map(\.1) == [.closed, .present, .absent])
    }
}
