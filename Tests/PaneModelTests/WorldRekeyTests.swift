import Testing
@testable import PaneModel

private let x = makeWindow(1)
private let t = makeWindow(2)
private let y = makeWindow(9)
private let k1 = DeskKey(displayUUID: "D1", spaceID: nil)
private let k2 = DeskKey(displayUUID: "D2", spaceID: nil)
private let frame = Rect(x: 10, y: 20, width: 400, height: 300)

private func onAnyDesk(_ window: WindowRef, _ world: World) -> Bool {
    world.desks.values.contains { $0.contains(window) }
}

/// Desk k1 with `x` docked beside the Desktop tile (one snapshot: the empty desk).
private func dockedX(history: inout UndoHistory) throws -> World {
    var world = World()
    try world.addDesk(k1)
    try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.insert(x, at: .left, of: .desktop, ids: &ids)
    }
    return world
}

@Suite struct WorldRekeyTests {
    // MARK: Task 1 — rekey re-points desks and undo snapshots

    @Test func aDockedWindowKeepsItsPanelAndStateAndUndoStillFindsIt() throws {
        var history = UndoHistory()
        var world = try dockedX(history: &history)
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in
            try desk.tree.resizeBoundary(in: desk.tree.root!, after: 0, by: 0.1)
        }
        try world.apply(.absent, for: x, on: k1, history: &history)
        let depth = history.depth(for: k1)

        try world.rekey(from: x, to: y, history: &history)
        #expect(world[k1]?.tree.windows == [y])
        #expect(world[k1]?.state(of: y) == .absent)
        #expect(!onAnyDesk(x, world))
        #expect(history.depth(for: k1) == depth)

        // Undo of the resize restores the snapshot under the new ID: nothing is revived.
        #expect(try world.undo(k1, history: &history) == [])
        #expect(world[k1]?.tree.windows == [y])
        #expect(world[k1]?.state(of: y) == .absent)
    }

    @Test func aFloatingWindowKeepsItsFrameAndState() throws {
        var history = UndoHistory()
        var world = World()
        try world.addDesk(k1)
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(x, frame: frame) }
        try world.apply(.fullscreen, for: x, on: k1, history: &history)

        try world.rekey(from: x, to: y, history: &history)
        #expect(world[k1]?.desktop.windows == [FloatingWindow(window: y, frame: frame, state: .fullscreen)])
        #expect(!onAnyDesk(x, world))
    }

    @Test func aTabGroupKeepsItsOrderAndSelection() throws {
        var history = UndoHistory()
        var world = try dockedX(history: &history)
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in
            try desk.tree.group(t, into: desk.tree.leaf(containing: x)!)
        }
        let leaf = try #require(world[k1]?.tree.leaf(containing: x))

        try world.rekey(from: x, to: y, history: &history)
        #expect(world[k1]?.tree.nodes[leaf] == .tabs(windows: [y, t], selected: 1))
        #expect(world[k1]?.state(of: y) == .present)
    }

    @Test func aRekeyOntoAWindowAnotherDeskHoldsClosesTheOldID() throws {
        var history = UndoHistory()
        var world = try dockedX(history: &history)
        try world.addDesk(k2)
        try world.edit(k2, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(y, frame: frame) }
        let k2Before = world[k2]
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in
            try desk.tree.resizeBoundary(in: desk.tree.root!, after: 0, by: 0.1)
        }

        try world.rekey(from: x, to: y, history: &history)
        #expect(!onAnyDesk(x, world))
        #expect(world[k2] == k2Before)
        while try world.undo(k1, history: &history) != nil {
            #expect(!onAnyDesk(x, world))
        }
    }

    @Test func aWindowOnNoDeskIsRekeyedInItsSnapshotsOnly() throws {
        var history = UndoHistory()
        var world = try dockedX(history: &history)
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.tree.remove(x) }
        let worldBefore = world

        try world.rekey(from: x, to: y, history: &history)
        #expect(world == worldBefore)
        #expect(try world.undo(k1, history: &history) == [y])
        #expect(world[k1]?.tree.windows == [y])
    }

    @Test func aSnapshotHoldingBothIDsDropsTheOldOne() throws {
        var history = UndoHistory()
        var world = try dockedX(history: &history)
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(y, frame: frame) }
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in
            try desk.tree.remove(x)
            try desk.desktop.remove(y)
        }

        try world.rekey(from: x, to: y, history: &history)
        #expect(try world.undo(k1, history: &history) == [y])
        #expect(world[k1]?.contains(x) == false)
        #expect(world[k1]?.desktop.contains(y) == true)
    }

    @Test func aRekeyToTheSameIDChangesNothing() throws {
        var history = UndoHistory()
        var world = try dockedX(history: &history)
        let (worldBefore, historyBefore) = (world, history)

        try world.rekey(from: x, to: x, history: &history)
        #expect(world == worldBefore)
        #expect(history == historyBefore)
    }
}
