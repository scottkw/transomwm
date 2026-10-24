import Foundation
import Testing
@testable import PaneModel

/// Shared test helper: a window of one fake app, identified by `id`.
func makeWindow(_ id: UInt32, title: String = "") -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 100, bundleID: "com.example.app"), titleHint: title)
}

@Suite struct SkeletonTests {
    let a = makeWindow(1, title: "Quarterly Report.docx")
    let b = makeWindow(2)
    let c = makeWindow(3)

    /// A then B docked on A's right: H[A, B].
    func pair(_ ids: inout IDSource) throws -> LayoutTree {
        var tree = LayoutTree()
        try tree.insertRoot(a, ids: &ids)
        try tree.insert(b, at: .right, of: #require(tree.leaf(containing: a)), ids: &ids)
        return tree
    }

    @Test func dockResolveStoreAndRoundTrip() throws {
        var ids = IDSource()
        let tree = try pair(&ids)

        let resolution = try resolve(tree, in: Rect(x: 0, y: 0, width: 1000, height: 500), mins: [:], gap: 10)
        #expect(resolution.windowRects[a] == Rect(x: 10, y: 10, width: 485, height: 480))
        #expect(resolution.windowRects[b] == Rect(x: 505, y: 10, width: 485, height: 480))
        #expect(resolution.unfit.isEmpty)

        let world = try World(ids: ids, desks: [DeskKey(displayUUID: "D1", spaceID: nil): Desk(tree: tree)])
        let data = try world.encoded()
        #expect(String(decoding: data, as: UTF8.self).contains("\"schemaVersion\":1"))
        let decoded = try World.decode(from: data)
        #expect(decoded == world)
        #expect(try decoded.encoded() == data)
    }

    @Test(arguments: Edge.allCases)
    func dockOnEdgeSplitsOnItsAxisWithWindowOnThatSide(edge: Edge) throws {
        var ids = IDSource()
        var tree = LayoutTree()
        try tree.insertRoot(a, ids: &ids)
        let leafA = try #require(tree.leaf(containing: a))
        try tree.insert(b, at: edge, of: leafA, ids: &ids)
        let leafB = try #require(tree.leaf(containing: b))

        let root = try #require(tree.root.flatMap(tree.node))
        #expect(root == .split(axis: edge.axis, children: edge.isLeading ? [leafB, leafA] : [leafA, leafB], weights: [0.5, 0.5]))

        let rects = try resolve(tree, in: Rect(x: 0, y: 0, width: 800, height: 600), mins: [:], gap: 0).windowRects
        let ra = try #require(rects[a])
        let rb = try #require(rects[b])
        switch edge {
        case .left: #expect(rb.maxX <= ra.minX)
        case .right: #expect(rb.minX >= ra.maxX)
        case .top: #expect(rb.maxY <= ra.minY)
        case .bottom: #expect(rb.minY >= ra.maxY)
        }
    }

    @Test func dockingBesideSameAxisSiblingAddsNarySibling() throws {
        var ids = IDSource()
        var tree = try pair(&ids)
        try tree.insert(c, at: .right, of: #require(tree.leaf(containing: b)), ids: &ids)

        guard case let .split(axis, children, weights)? = tree.root.flatMap(tree.node) else {
            Issue.record("root is not a split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children == [a, b, c].map { tree.leaf(containing: $0)! })
        #expect(weights.allSatisfy { abs($0 - 1.0 / 3) <= 1e-12 })
        #expect(tree.nodes.count == 4)
    }

    @Test func dockingBesideSameAxisSplitAddsItsFirstChild() throws {
        var ids = IDSource()
        var tree = try pair(&ids)
        try tree.insert(c, at: .left, of: #require(tree.root), ids: &ids)

        guard case let .split(_, children, weights)? = tree.root.flatMap(tree.node) else {
            Issue.record("root is not a split")
            return
        }
        #expect(children.count == 3)
        #expect(children.first == tree.leaf(containing: c))
        #expect(abs(weights[0] - 1.0 / 3) <= 1e-12)
    }

    @Test func badInsertThrowsAndLeavesTreeAndIDsUnchanged() throws {
        var ids = IDSource()
        var tree = try pair(&ids)
        let before = tree
        let idsBefore = ids
        let leafA = try #require(tree.leaf(containing: a))

        let renamedA = WindowRef(identity: a.identity, titleHint: "Other title")
        #expect(throws: LayoutError.duplicateWindow(renamedA)) {
            try tree.insert(renamedA, at: .bottom, of: leafA, ids: &ids)
        }
        let unknown = NodeID(raw: 999)
        #expect(throws: LayoutError.nodeNotFound(unknown)) {
            try tree.insert(c, at: .left, of: unknown, ids: &ids)
        }
        #expect(tree == before)
        #expect(ids == idsBefore)
    }

    @Test func windowRefIdentityIgnoresTitleAndDescriptionHidesIt() {
        let renamed = WindowRef(identity: a.identity, titleHint: "Something else", axIdentifier: "x", creationOrder: 7)
        #expect(renamed == a)
        #expect(renamed.hashValue == a.hashValue)
        #expect(!a.description.contains("Quarterly"))
        #expect(!String(describing: LayoutError.duplicateWindow(a)).contains("Quarterly"))
        #expect(!String(reflecting: LayoutError.windowNotFound(a)).contains("Quarterly"))
    }

    @Test func negativeOriginIsValidAndResolves() throws {
        let area = Rect(x: -1440, y: -900, width: 1440, height: 900)
        #expect(area.isValidGeometry)

        var ids = IDSource()
        var tree = LayoutTree()
        try tree.insertRoot(a, ids: &ids)
        let rects = try resolve(tree, in: area, mins: [:], gap: 10).windowRects
        #expect(rects[a] == Rect(x: -1430, y: -890, width: 1420, height: 880))
    }
}
