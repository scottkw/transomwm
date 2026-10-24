import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let w = makeWindow(9)
private let k1 = DeskKey(displayUUID: "D1", spaceID: nil)
private let k2 = DeskKey(displayUUID: "D2", spaceID: nil)
private let frame = Rect(x: 0, y: 0, width: 400, height: 300)

/// Docks `window` as the root, or to the right of the first window already in the tree.
private func dock(_ window: WindowRef, _ desk: inout Desk, _ ids: inout IDSource) throws(LayoutError) {
    if let first = desk.tree.windows.first, let leaf = desk.tree.leaf(containing: first) {
        try desk.tree.insert(window, at: .right, of: leaf, ids: &ids)
    } else {
        try desk.tree.insertRoot(window, ids: &ids)
    }
}

private func worldWithDesks(_ keys: DeskKey...) throws -> World {
    var world = World()
    for key in keys { try world.addDesk(key) }
    return world
}

@Suite struct UndoTests {
    @Test func addDeskCreatesEmptyDeskAndUnknownKeysThrow() throws {
        var world = try worldWithDesks(k1)
        #expect(world[k1] == Desk())
        #expect(throws: LayoutError.deskExists(k1)) { try world.addDesk(k1) }

        var history = UndoHistory()
        #expect(throws: LayoutError.deskNotFound(k2)) { try world.edit(k2, history: &history) { _, _ in } }
        #expect(throws: LayoutError.deskNotFound(k2)) { try world.undo(k2, history: &history) }
    }

    @Test func undoRestoresSnapshotsLastInFirstOut() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        let afterA = try #require(world[k1])
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(b, &desk, &ids) }
        #expect(world[k1]?.tree.windows == [a, b])
        #expect(history.depth(for: k1) == 2)

        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1] == afterA)
        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1] == Desk())
        #expect(history.depth(for: k1) == 0)
    }

    @Test func undoWithEmptyHistoryReturnsNilAndChangesNothing() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        let before = world
        #expect(try world.undo(k1, history: &history) == nil)
        #expect(world == before)
        #expect(history == UndoHistory())
    }

    @Test func fiftyOneEditsAllowExactlyFiftyUndos() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        var afterFirst: Desk?
        for i in 0..<51 {
            try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
                try dock(makeWindow(UInt32(100 + i)), &desk, &ids)
            }
            if i == 0 { afterFirst = world[k1] }
        }
        #expect(UndoHistory.limit == 50)
        #expect(history.depth(for: k1) == 50)

        var undos = 0
        while try world.undo(k1, history: &history) != nil { undos += 1 }
        #expect(undos == 50)
        #expect(world[k1] == afterFirst)
        #expect(try world.undo(k1, history: &history) == nil)
    }

    @Test func historiesArePerDesk() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        try world.edit(k2, history: &history) { desk, ids throws(LayoutError) in try dock(b, &desk, &ids) }
        #expect(history.depth(for: k1) == 1)
        #expect(history.depth(for: k2) == 1)

        let deskA = world[k1]
        #expect(try world.undo(k2, history: &history) != nil)
        #expect(world[k1] == deskA)
        #expect(world[k2] == Desk())
        #expect(history.depth(for: k1) == 1)
        #expect(history.depth(for: k2) == 0)
    }

    @Test func throwingChangeCommitsNothingAndConsumesNoIDs() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        let before = world
        let historyBefore = history

        #expect(throws: LayoutError.duplicateWindow(b)) {
            try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
                try dock(b, &desk, &ids)  // succeeds on the copy and issues NodeIDs
                try dock(b, &desk, &ids)  // then fails
            }
        }
        #expect(world == before)
        #expect(world.ids == before.ids)
        #expect(history == historyBefore)
    }

    @Test func changeThatLeavesWorldInvalidCommitsNothing() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        let before = world
        let historyBefore = history

        // Valid on its own desk, but a is already docked on k1.
        #expect(throws: LayoutError.duplicateWindow(a)) {
            try world.edit(k2, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(a, frame: frame) }
        }
        #expect(world == before)
        #expect(history == historyBefore)
    }

    @Test func undoNeverRewindsTheIDSource() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(b, &desk, &ids) }
        let issuedBefore = world.ids.next
        try world.undo(k1, history: &history)
        #expect(world.ids.next == issuedBefore)

        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(w, &desk, &ids) }
        let newLeaf = try #require(world[k1]?.tree.leaf(containing: w))
        #expect(newLeaf.raw >= issuedBefore)
    }

    @Test func aWorldAtTheLoadHeadroomBoundStillEditsUntilTheIDSourceRunsOut() throws {
        // Headroom is a load-time gate only (review iteration 2, WR-02); edits stop only where make() does.
        var world = try World(ids: IDSource(next: UInt64.max / 2), desks: [k1: Desk()])
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            ids = IDSource(next: .max - 2)
            try dock(b, &desk, &ids)
        }
        #expect(world.ids.next == .max)
        let before = world
        #expect(throws: LayoutError.invariantViolated("ID source exhausted")) {
            try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(c, &desk, &ids) }
        }
        #expect(world == before)
    }

    // MARK: Lifecycle facts are not user edits (WR-03)

    @Test func lifecycleChangesUseNoUndoLevelsAndUndoKeepsTheCurrentStates() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            try dock(a, &desk, &ids)
            try desk.desktop.add(w, frame: frame)
        }
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(b, &desk, &ids) }
        try world.apply(.absent, for: a, on: k1, history: &history)
        try world.apply(.fullscreen, for: w, on: k1, history: &history)
        #expect(history.depth(for: k1) == 2)

        // Cmd-Z undoes the user's last edit (docking b), not the OS reports, and a and w stay hidden.
        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1]?.tree.windows == [a])
        #expect(world[k1]?.state(of: a) == .absent)
        #expect(world[k1]?.state(of: w) == .fullscreen)
    }

    @Test func undoNeverBringsBackAClosedWindow() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            try dock(a, &desk, &ids)
            try dock(b, &desk, &ids)
        }
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(w, &desk, &ids) }
        try world.edit(k2, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(c, frame: frame) }
        try world.edit(k2, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.remove(c) }

        try world.apply(.closed, for: b, on: k1, history: &history)
        #expect(world[k1]?.contains(b) == false)
        #expect(history.depth(for: k1) == 2)

        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1]?.tree.windows == [a])
        #expect(world[k1]?.contains(b) == false)
        try world.validate()
        // Other desks' snapshots keep their own windows.
        #expect(try world.undo(k2, history: &history) != nil)
        #expect(world[k2]?.desktop.contains(c) == true)
    }

    @Test func applyToAnUnknownDeskOrWindowThrowsAndChangesNothing() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        let before = world
        let historyBefore = history
        #expect(throws: LayoutError.deskNotFound(k2)) { try world.apply(.absent, for: a, on: k2, history: &history) }
        #expect(throws: LayoutError.windowNotFound(b)) { try world.apply(.absent, for: b, on: k1, history: &history) }
        // A confirmed close of a window no desk holds is not an error: there is nothing left to remove.
        try world.apply(.closed, for: b, on: k1, history: &history)
        #expect(world == before)
        #expect(history == historyBefore)
    }

    // MARK: A closed window stays closed (review iteration 2, WR-01)

    @Test func closingAWindowThatUndoTookOffEveryDeskStillPurgesHistory() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        // Move w from k1 to k2, then Cmd-Z on k2: w is on no desk, but k1's snapshots still hold it.
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            try dock(a, &desk, &ids)
            try dock(w, &desk, &ids)
        }
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.tree.remove(w) }
        try world.edit(k2, history: &history) { desk, ids throws(LayoutError) in try desk.tree.insertRoot(w, ids: &ids) }
        #expect(try world.undo(k2, history: &history) != nil)
        #expect(world[k1]?.contains(w) == false)
        #expect(world[k2]?.contains(w) == false)

        try world.apply(.closed, for: w, on: k1, history: &history)
        try world.apply(.closed, for: w, on: k2, history: &history)

        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1]?.tree.windows == [a])
        #expect(world[k1]?.contains(w) == false)
        try world.validate()
    }

    // MARK: Undo reports windows whose state it cannot know (review iteration 3, WR-01)

    @Test func undoReportsAWindowItBroughtBackFromNoDeskSoItsRealStateCanBeReapplied() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        // Move w from k1 to k2, the user minimises it, then Cmd-Z on k2: w is on no desk.
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            try dock(a, &desk, &ids)
            try dock(w, &desk, &ids)
        }
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.tree.remove(w) }
        try world.edit(k2, history: &history) { desk, ids throws(LayoutError) in try desk.tree.insertRoot(w, ids: &ids) }
        try world.apply(.absent, for: w, on: k2, history: &history)
        #expect(try world.undo(k2, history: &history) == [])
        #expect(throws: LayoutError.windowNotFound(w)) { try world.apply(.absent, for: w, on: k1, history: &history) }

        // Cmd-Z on k1 brings w back with its snapshot's stale `.present`, and says so.
        #expect(try world.undo(k1, history: &history) == [w])
        #expect(world[k1]?.state(of: w) == .present)
        try world.apply(.absent, for: w, on: k1, history: &history)
        #expect(world[k1]?.state(of: w) == .absent)
        #expect(world[k1]?.state(of: a) == .present)
    }

    @Test func closingIsAboutTheWindowNotTheDeskKey() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        try world.edit(k2, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(w, frame: frame) }
        try world.apply(.closed, for: w, on: k1, history: &history)
        #expect(world[k2]?.contains(w) == false)
        #expect(try world.undo(k2, history: &history) != nil)
        #expect(world[k2] == Desk())
    }

    @Test func closingAWindowNoDeskHoldsNeedsNoExistingDeskKey() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            try dock(a, &desk, &ids)
            try dock(w, &desk, &ids)
        }
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.tree.remove(w) }
        // k2 has no desk; `.closed` ignores the key, so it must not block the history purge (review iteration 3, WR-02).
        try world.apply(.closed, for: w, on: k2, history: &history)
        #expect(try world.undo(k1, history: &history) == [])
        #expect(world[k1]?.contains(w) == false)
        #expect(world[k1]?.tree.windows == [a])
    }

    @Test func closingInsideAnEditIsRejectedSoUndoCannotReviveIt() throws {
        var world = try worldWithDesks(k1)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
            try dock(a, &desk, &ids)
            try dock(b, &desk, &ids)
            try desk.desktop.add(w, frame: frame)
        }
        let before = world
        let historyBefore = history
        // A close pushed by `edit` would sit on the undo stack, never forgotten: only `apply` may close.
        for window in [b, w] {
            #expect(throws: LayoutError.self) {
                try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.setState(.closed, for: window) }
            }
        }
        #expect(throws: LayoutError.self) {
            try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.tree.setState(.closed, for: b) }
        }
        #expect(world == before)
        #expect(history == historyBefore)
    }

    @Test func undoThatWouldPutAWindowOnTwoDesksThrowsAndDiscardsOnlyThatSnapshot() throws {
        var world = try worldWithDesks(k1, k2)
        var history = UndoHistory()
        try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in try dock(a, &desk, &ids) }
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(w, frame: frame) }
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.remove(w) }
        try world.edit(k2, history: &history) { desk, _ throws(LayoutError) in try desk.desktop.add(w, frame: frame) }
        let before = world

        // The newest k1 snapshot has w floating, but w is on k2 now: it cannot be restored.
        #expect(throws: LayoutError.duplicateWindow(w)) { try world.undo(k1, history: &history) }
        #expect(world == before)
        #expect(history.depth(for: k1) == 2)
        #expect(history.depth(for: k2) == 1)

        // The stale entry is gone, so it no longer blocks the older ones.
        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1]?.tree.windows == [a])
        #expect(world[k1]?.desktop.windows.isEmpty == true)
        #expect(try world.undo(k1, history: &history) != nil)
        #expect(world[k1] == Desk())
    }
}
