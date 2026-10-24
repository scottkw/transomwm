import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let ghost = makeWindow(99)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

/// Panel A as the root at node 1.
private func single() throws -> (LayoutTree, IDSource) {
    var tree = LayoutTree()
    var ids = IDSource()
    try tree.insertRoot(a, ids: &ids)
    return (tree, ids)
}

/// H[A, C]: A at node 1, C at node 2, split 3.
private func pair() throws -> (LayoutTree, IDSource) {
    var (tree, ids) = try single()
    try tree.insert(c, at: .right, of: n(1), ids: &ids)
    return (tree, ids)
}

@Suite struct TabsTests {
    @Test func groupingIntoAPanelMakesATabGroupUnderTheSameNodeID() throws {
        var (tree, _) = try single()
        try tree.group(b, into: n(1))
        #expect(tree.root == n(1))
        #expect(tree.node(n(1)) == .tabs(windows: [a, b], selected: 1))
        #expect(tree.nodes.count == 1)

        try tree.group(c, into: n(1))
        #expect(tree.node(n(1)) == .tabs(windows: [a, b, c], selected: 2))
        #expect(tree.windows == [a, b, c])
    }

    @Test func groupingStoresTheNewWindowAsPresent() throws {
        var (tree, _) = try single()
        try tree.group(b, into: n(1))
        #expect(tree.state(of: b) == .present)
        #expect(tree.state(of: a) == .present)
    }

    @Test func badGroupsThrowAndLeaveTheTreeUnchanged() throws {
        var (tree, _) = try pair()
        let before = tree
        #expect(throws: LayoutError.notALeaf(n(3))) { try tree.group(b, into: n(3)) }
        #expect(throws: LayoutError.duplicateWindow(c)) { try tree.group(c, into: n(1)) }
        #expect(throws: LayoutError.duplicateWindow(a)) { try tree.group(a, into: n(1)) }
        #expect(throws: LayoutError.nodeNotFound(n(42))) { try tree.group(b, into: n(42)) }
        #expect(tree == before)
    }

    @Test func selectTabSelectsTheWindowInItsGroup() throws {
        var (tree, _) = try single()
        try tree.group(b, into: n(1))
        try tree.group(c, into: n(1))
        try tree.selectTab(a)
        #expect(tree.node(n(1)) == .tabs(windows: [a, b, c], selected: 0))
        try tree.selectTab(b)
        #expect(tree.node(n(1)) == .tabs(windows: [a, b, c], selected: 1))
    }

    @Test func selectTabRejectsPanelsAndUnknownWindows() throws {
        var (tree, _) = try pair()
        let before = tree
        #expect(throws: LayoutError.notATabGroup(n(1))) { try tree.selectTab(a) }
        #expect(throws: LayoutError.windowNotFound(ghost)) { try tree.selectTab(ghost) }
        #expect(tree == before)
    }

    @Test func aTabGroupResolvesToOneRectSizedForItsLargestMinimum() throws {
        var (tree, _) = try pair()
        try tree.group(b, into: n(1))
        let mins = [a: Size(width: 300, height: 100), b: Size(width: 500, height: 200)]
        let r = try resolve(tree, in: Rect(x: 0, y: 0, width: 1000, height: 600), mins: mins, gap: 10)
        let group = try #require(r.nodeRects[n(1)])
        #expect(group.width >= 500)
        #expect(group.height >= 200)
        #expect(r.windowRects[a] == group)
        #expect(r.windowRects[b] == group)
        #expect(r.windowRects[c].map { !$0.overlaps(group) } == true)
        #expect(r.unfit.isEmpty)
    }

    @Test func tabsSurviveAWorldJSONRoundTrip() throws {
        var (tree, ids) = try pair()
        try tree.group(b, into: n(1))
        try tree.selectTab(a)
        let key = DeskKey(displayUUID: "D1", spaceID: nil)
        let world = try World(ids: ids, desks: [key: Desk(tree: tree)])
        let decoded = try World.decode(from: world.encoded())
        #expect(decoded == world)
        #expect(decoded[key]?.tree.node(n(1)) == .tabs(windows: [a, b], selected: 0))
    }
}
