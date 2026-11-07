import Testing
@testable import TransomModel

private let key = DeskKey(displayUUID: "main", spaceID: nil)
private let other = DeskKey(displayUUID: "other", spaceID: nil)
private let frame = Rect(x: 10, y: 20, width: 300, height: 200)

private func ref(_ id: UInt32, pid: Int32 = 100) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: "com.example.app"))
}

private let waiting = ref(1), neighbour = ref(2), member = ref(3)
private let returning = ref(11, pid: 101)

/// [waiting | neighbour], with `returning` floating on `key`; undoing the one edit leaves the empty desk.
private func docked(history: inout UndoHistory) throws -> World {
    var world = World()
    try world.addDesk(key)
    try world.reflow(key) { desk, _ throws(LayoutError) in try desk.desktop.add(returning, frame: frame) }
    try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.applyDrop(.layoutEdge(.right), window: waiting, ids: &ids)
        guard let leaf = desk.tree.leaf(containing: waiting) else { throw .windowNotFound(waiting) }
        try desk.tree.insert(neighbour, at: .right, of: leaf, ids: &ids)
    }
    return world
}

/// `docked`, with `waiting` and `member` tabbed in one leaf and `selected` showing.
private func tabbed(selected: WindowRef) throws -> World {
    var history = UndoHistory()
    var world = try docked(history: &history)
    try world.reflow(key) { desk, _ throws(LayoutError) in
        guard let leaf = desk.tree.leaf(containing: waiting) else { throw .windowNotFound(waiting) }
        try desk.tree.group(member, into: leaf)
        try desk.tree.selectTab(selected)
    }
    return world
}

/// World.adopt (D-11): a returning window takes a placeholder's place, as an OS fact.
@Suite struct WorldAdoptTests {
    @Test func aReturningWindowTakesAPanelLeafAndLeavesTheDesktopLayer() throws {
        var history = UndoHistory()
        var world = try docked(history: &history)
        let leaf = world[key]?.tree.leaf(containing: waiting)
        let depth = history.depth(for: key)
        try world.adopt(waiting, by: returning, history: &history)
        let desk = try #require(world[key])
        #expect(desk.tree.leaf(containing: returning) == leaf)
        #expect(desk.tree.windows == [returning, neighbour])
        #expect(!desk.contains(waiting))
        #expect(!desk.desktop.contains(returning))
        #expect(desk.state(of: returning) == .present)
        #expect(history.depth(for: key) == depth, "an OS fact pushes no undo step")
    }

    @Test func aWindowNoDeskHoldsYetIsPresentEvenWhenThePlaceholderWasAbsent() throws {
        var history = UndoHistory()
        var world = try docked(history: &history)
        try world.apply(.absent, for: waiting, on: key, history: &history)
        let arriving = ref(12, pid: 101)
        try world.adopt(waiting, by: arriving, history: &history)
        #expect(world[key]?.tree.state(of: arriving) == .present)
    }

    @Test func aHiddenTabMemberRejoinsHiddenInItsPosition() throws {
        var world = try tabbed(selected: member)
        let leaf = try #require(world[key]?.tree.leaf(containing: waiting))
        var history = UndoHistory()
        try world.adopt(waiting, by: returning, history: &history)
        #expect(world[key]?.tree.node(leaf) == .tabs(windows: [returning, member], selected: 1))
    }

    @Test func aSelectedTabMemberRejoinsSelected() throws {
        var world = try tabbed(selected: waiting)
        let leaf = try #require(world[key]?.tree.leaf(containing: waiting))
        var history = UndoHistory()
        try world.adopt(waiting, by: returning, history: &history)
        #expect(world[key]?.tree.node(leaf) == .tabs(windows: [returning, member], selected: 0))
    }

    @Test func aWindowFloatingOnAnotherDeskMovesToTheLeaf() throws {
        var history = UndoHistory()
        var world = try docked(history: &history)
        let elsewhere = ref(12, pid: 101)
        try world.addDesk(other)
        try world.reflow(other) { desk, _ throws(LayoutError) in try desk.desktop.add(elsewhere, frame: frame) }
        try world.adopt(waiting, by: elsewhere, history: &history)
        #expect(world[key]?.tree.windows == [elsewhere, neighbour])
        #expect(world[other]?.contains(elsewhere) == false)
    }

    @Test func aFloatingPlaceholderKeepsItsFrame() throws {
        var history = UndoHistory()
        var world = try docked(history: &history)
        try world.adopt(returning, by: ref(12, pid: 101), history: &history)
        #expect(world[key]?.desktop.frame(of: ref(12, pid: 101)) == frame)
        #expect(world[key]?.contains(returning) == false)
    }

    @Test func undoSnapshotsFollowThePlaceholderAndForgetTheWindowsFloatingEntry() throws {
        var history = UndoHistory()
        var world = try docked(history: &history)
        try world.edit(key, history: &history) { desk, _ throws(LayoutError) in try desk.tree.swap(waiting, neighbour) }
        try world.adopt(waiting, by: returning, history: &history)
        try #require(world[key]?.tree.windows == [neighbour, returning])
        try world.undo(key, history: &history)
        #expect(world[key]?.tree.windows == [returning, neighbour], "the undo brings the tile back under the new identity")
        #expect(world[key]?.desktop.contains(returning) == false)
    }

    @Test func aThrowLeavesTheWorldAndHistoryUnchanged() throws {
        var history = UndoHistory()
        var world = try docked(history: &history)
        let before = world, beforeHistory = history
        // No desk holds the placeholder.
        #expect(throws: LayoutError.self) { try world.adopt(ref(99), by: returning, history: &history) }
        // The user docked the window: it is not the matcher's to move.
        #expect(throws: LayoutError.self) { try world.adopt(waiting, by: neighbour, history: &history) }
        #expect(world == before)
        #expect(history == beforeHistory)
    }
}
