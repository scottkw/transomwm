import Testing
import PaneEngine
import PaneModel
import PaneTestSupport

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
                try desk.tree.insertRoot(window, ids: &ids)
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
    ])
    func nonLifecycleEventsLeaveTheWorldUnchanged(event: WindowEvent) throws {
        var history = UndoHistory()
        var world = try world([a, b], history: &history)
        let (worldBefore, historyBefore) = (world, history)

        #expect(try !LifecycleSync.handle(event, world: &world, history: &history))
        #expect(world == worldBefore)
        #expect(history == historyBefore)
    }
}
