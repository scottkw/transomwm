import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let d = makeWindow(4)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

/// H[A, B]: A n1, B n2 under split n3.
private func pair() throws -> (LayoutTree, IDSource) {
    var tree = LayoutTree()
    var ids = IDSource()
    try tree.insertRoot(a, ids: &ids)
    try tree.insert(b, at: .right, of: n(1), ids: &ids)
    return (tree, ids)
}

/// Encodes, decodes and re-encodes: the decoded World is equal and its bytes are identical.
private func expectRoundTrip(_ world: World) throws {
    let data = try world.encoded()
    let decoded = try World.decode(from: data)
    #expect(decoded == world)
    #expect(try decoded.encoded() == data)
}

@Suite struct ScenarioTests {
    @Test func emptyLayoutDropBecomesTheRootOnlyOnAnEmptyTree() throws {
        var tree = LayoutTree()
        var ids = IDSource()
        try tree.applyDrop(.emptyLayout, window: a, ids: &ids)
        #expect(tree.root == n(1))
        #expect(tree.node(n(1)) == .panel(a))
        #expect(throws: LayoutError.treeNotEmpty) { try tree.applyDrop(.emptyLayout, window: b, ids: &ids) }

        var empty = LayoutTree()
        var emptyIDs = IDSource()
        try empty.applyDrop(.layoutEdge(.left), window: a, ids: &emptyIDs)
        #expect(empty == tree)
    }

    @Test(arguments: Edge.allCases)
    func tileEdgeDropIsInsertAtThatEdge(edge: Edge) throws {
        var (dropped, dropIDs) = try pair()
        var (inserted, insertIDs) = try pair()
        try dropped.applyDrop(.tile(n(2), .edge(edge)), window: c, ids: &dropIDs)
        try inserted.insert(c, at: edge, of: n(2), ids: &insertIDs)
        #expect(dropped == inserted)
        #expect(dropIDs == insertIDs)
    }

    @Test func tileCentreDropIsGroup() throws {
        var (dropped, dropIDs) = try pair()
        var (grouped, groupIDs) = try pair()
        try dropped.applyDrop(.tile(n(2), .center), window: c, ids: &dropIDs)
        try grouped.group(c, into: n(2))
        #expect(dropped == grouped)
        #expect(dropIDs == groupIDs)
        #expect(dropped.node(n(2)) == .tabs(windows: [b, c], selected: 1))
    }

    @Test func layoutEdgeDropIsInsertBesideTheRoot() throws {
        var (dropped, dropIDs) = try pair()
        var (inserted, insertIDs) = try pair()
        try dropped.applyDrop(.layoutEdge(.left), window: c, ids: &dropIDs)
        try inserted.insert(c, at: .left, of: n(3), ids: &insertIDs)
        #expect(dropped == inserted)
        #expect(dropIDs == insertIDs)
        #expect(dropped.windows == [c, a, b])
    }

    @Test func staleNodeIDThrowsAndChangesNothing() throws {
        var (tree, ids) = try pair()
        let before = tree
        let idsBefore = ids
        for zone in [DropZone.center, .edge(.left), .edge(.bottom)] {
            #expect(throws: LayoutError.nodeNotFound(n(42))) { try tree.applyDrop(.tile(n(42), zone), window: c, ids: &ids) }
        }
        #expect(tree == before)
        #expect(ids == idsBefore)
    }

    /// Hit test → edit → resolve → lifecycle → undo → JSON, every mutation through World (`edit` or `apply`).
    @Test func dropTabAbsentPresentUndoAndPersist() throws {
        let key = DeskKey(displayUUID: "D1", spaceID: nil)
        let area = Rect(x: 0, y: 0, width: 1200, height: 800)
        let gap = 8.0
        var world = World()
        try world.addDesk(key)
        var history = UndoHistory()
        func desk() throws -> Desk { try #require(world[key]) }
        func layout() throws -> Resolution { try resolve(desk().tree, in: area, mins: [:], gap: gap) }
        try expectRoundTrip(world)

        // 1. Drop A on the left band of the Desktop tile, which fills a new desk (D-24).
        let desktop = try #require(layout().desktopRect)
        let leftBand = Point(x: desktop.minX + desktop.width * 0.1, y: desktop.midY)
        let first = try #require(DropZones.target(at: leftBand, in: area, tree: desk().tree, resolution: layout()))
        #expect(first == .tile(.desktop, .edge(.left)))
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in try desk.tree.applyDrop(first, window: a, ids: &ids) }
        let leafA = try #require(desk().tree.leaf(containing: a))
        try expectRoundTrip(world)

        // 2. Drop B on the right band of A.
        let rectA = try #require(layout().windowRects[a])
        let bandPoint = Point(x: rectA.minX + rectA.width * 0.9, y: rectA.midY)
        let second = try #require(DropZones.target(at: bandPoint, in: area, tree: desk().tree, resolution: layout()))
        #expect(second == .tile(leafA, .edge(.right)))
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in try desk.tree.applyDrop(second, window: b, ids: &ids) }
        let leafB = try #require(desk().tree.leaf(containing: b))
        try expectRoundTrip(world)

        // 3. Drop C on the centre of B: a tab group [B, C].
        let rectB = try #require(layout().windowRects[b])
        let centreB = Point(x: rectB.midX, y: rectB.midY)
        let third = try #require(DropZones.target(at: centreB, in: area, tree: desk().tree, resolution: layout()))
        #expect(third == .tile(leafB, .center))
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in try desk.tree.applyDrop(third, window: c, ids: &ids) }
        #expect(try desk().tree.node(leafB) == .tabs(windows: [b, c], selected: 1))
        try expectRoundTrip(world)

        // 4. A on the left, the tab group on the right, no overlap, nothing unfit.
        let docked = try layout()
        let a4 = try #require(docked.windowRects[a])
        let tabs4 = try #require(docked.nodeRects[leafB])
        #expect(docked.windowRects[b] == tabs4)
        #expect(docked.windowRects[c] == tabs4)
        #expect(a4.maxX < tabs4.minX)
        #expect(!a4.overlaps(tabs4))
        #expect(docked.unfit.isEmpty)

        // 5. A goes absent: the tab group and the Desktop share A's space, A keeps its node.
        try world.apply(.absent, for: a, on: key, history: &history)
        let hidden = try layout()
        #expect(hidden.windowRects[a] == nil)
        let half = (area.width - 3 * gap) / 2
        #expect(hidden.nodeRects[leafB] == Rect(x: gap, y: gap, width: half, height: area.height - 2 * gap))
        #expect(hidden.desktopRect == Rect(x: 2 * gap + half, y: gap, width: half, height: area.height - 2 * gap))
        #expect(try desk().tree.leaf(containing: a) == leafA)
        try expectRoundTrip(world)

        // 6. A comes back to exactly the step 4 layout.
        try world.apply(.present, for: a, on: key, history: &history)
        #expect(try layout() == docked)
        try expectRoundTrip(world)

        // 8. (Step 7, the JSON round-trip, runs after every step.) Three user edits, three undos back to the
        // Desktop tile alone; the lifecycle reports of steps 5 and 6 are not on the stack, and a fourth has nothing to undo.
        #expect(history.depth(for: key) == 3)
        for _ in 0..<3 {
            #expect(try world.undo(key, history: &history) != nil)
            try expectRoundTrip(world)
        }
        #expect(try desk() == Desk())
        #expect(try world.undo(key, history: &history) == nil)
    }

    @Test func aDropOfAWindowAlreadyOnTheDeskIsRejectedByTheFunnel() throws {
        let key = DeskKey(displayUUID: "D1", spaceID: nil)
        var world = World()
        try world.addDesk(key)
        var history = UndoHistory()
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            try desk.tree.applyDrop(.tile(.desktop, .edge(.left)), window: a, ids: &ids)
            try desk.desktop.add(d, frame: Rect(x: 0, y: 0, width: 100, height: 100))
        }
        let before = world
        #expect(throws: LayoutError.duplicateWindow(d)) {
            try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
                try desk.tree.applyDrop(.tile(n(1), .center), window: d, ids: &ids)
            }
        }
        #expect(world == before)
        #expect(history.depth(for: key) == 1)
    }
}
