import PaneEngine
import PaneModel
import Testing

private let area = Rect(x: 0, y: 0, width: 1000, height: 800)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 1, bundleID: "com.example.gaps"))
}

private let a = window(1), b = window(2), c = window(3)
private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

/// A tree from raw-ID nodes; every window present unless listed in `absent`.
private func tree(root: UInt64, _ nodes: [UInt64: Node], absent: [WindowRef] = []) throws -> LayoutTree {
    var states: [WindowIdentity: WindowState] = [:]
    for case .panel(let w) in nodes.values { states[w.identity] = absent.contains(w) ? .absent : .present }
    return try LayoutTree(root: n(root), nodes: Dictionary(uniqueKeysWithValues: nodes.map { (n($0.key), $0.value) }), states: states)
}

private func handles(_ tree: LayoutTree, gap: Double = 8) throws -> [GapHandle] {
    GapHandles.handles(tree: tree, resolution: try resolve(tree, in: area, mins: [:], gap: gap), gap: gap)
}

/// TILE-05, UI-SPEC Surface 3: one handle per boundary between taking-part siblings, exactly over the gap.
@Suite struct GapHandleGeometryTests {
    @Test func aPairGetsOneHandleOverTheWholeStripBetweenThem() throws {
        let t = try tree(root: 10, [10: .split(axis: .horizontal, children: [n(1), n(2)], weights: [0.5, 0.5]), 1: .panel(a), 2: .panel(b)])
        let resolution = try resolve(t, in: area, mins: [:], gap: 8)
        let ra = try #require(resolution.windowRects[a]), rb = try #require(resolution.windowRects[b])
        let found = try handles(t)
        #expect(found == [GapHandle(split: n(10), first: 0, second: 1, axis: .horizontal, rect: Rect(x: ra.maxX, y: 8, width: 8, height: 784))])
        #expect(rb.minX - ra.maxX == 8)
        // No click is taken from either window.
        #expect(found.allSatisfy { !$0.rect.overlaps(ra) && !$0.rect.overlaps(rb) })
    }

    @Test func atATJunctionTheParentHandleRunsThroughAndTheChildStopsAtItsEdge() throws {
        let t = try tree(root: 10, [
            10: .split(axis: .horizontal, children: [n(1), n(11)], weights: [0.5, 0.5]), 1: .panel(a),
            11: .split(axis: .vertical, children: [n(2), n(3)], weights: [0.5, 0.5]), 2: .panel(b), 3: .panel(c),
        ])
        let resolution = try resolve(t, in: area, mins: [:], gap: 8)
        let column = try #require(resolution.nodeRects[n(11)])
        let found = try handles(t)
        #expect(found.count == 2)
        let root = try #require(found.first { $0.split == n(10) })
        let inner = try #require(found.first { $0.split == n(11) })
        #expect(root.axis == .horizontal && root.rect.minY == 8 && root.rect.height == 784)
        #expect(inner.axis == .vertical && inner.rect.minX == column.minX && inner.rect.maxX == column.maxX && inner.rect.height == 8)
        #expect(!root.rect.overlaps(inner.rect))
    }

    @Test func aMinimisedMiddleChildLeavesOneHandleBetweenItsVisibleSiblings() throws {
        let t = try tree(
            root: 10, [10: .split(axis: .horizontal, children: [n(1), n(2), n(3)], weights: [0.3, 0.4, 0.3]), 1: .panel(a), 2: .panel(b), 3: .panel(c)],
            absent: [b])
        let found = try handles(t)
        #expect(found.count == 1)
        #expect(found.first?.first == 0 && found.first?.second == 2)
    }

    @Test func gapsUnderFourPointsGetNoHandles() throws {
        let t = try tree(root: 10, [10: .split(axis: .horizontal, children: [n(1), n(2)], weights: [0.5, 0.5]), 1: .panel(a), 2: .panel(b)])
        #expect(try handles(t, gap: 0).isEmpty)
        #expect(try handles(t, gap: 2).isEmpty)
        #expect(try handles(t, gap: 4).count == 1)
    }

    @Test func aSingleWindowHasNoHandleInItsOuterGap() throws {
        let t = try tree(root: 1, [1: .panel(a)])
        #expect(try handles(t).isEmpty)
    }
}
