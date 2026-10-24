import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let d = makeWindow(4)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

/// A validated tree from raw-ID nodes; every window in it is present.
private func tree(root: UInt64, _ nodes: [UInt64: Node]) throws -> LayoutTree {
    var states: [WindowIdentity: WindowState] = [:]
    for node in nodes.values {
        switch node {
        case let .panel(window): states[window.identity] = .present
        case let .tabs(windows, _): for window in windows { states[window.identity] = .present }
        case .split: break
        }
    }
    return try LayoutTree(root: n(root), nodes: Dictionary(uniqueKeysWithValues: nodes.map { (n($0.key), $0.value) }), states: states)
}

private func h(_ children: UInt64..., weights: [Double]) -> Node {
    .split(axis: .horizontal, children: children.map(n), weights: weights)
}

private func v(_ children: UInt64..., weights: [Double]) -> Node {
    .split(axis: .vertical, children: children.map(n), weights: weights)
}

private func expectWeights(_ actual: [Double], _ expected: [Double], tolerance: Double = 1e-12) {
    #expect(actual.count == expected.count)
    for (x, y) in zip(actual, expected) { #expect(abs(x - y) <= tolerance, "\(actual) != \(expected)") }
}

/// (selected before, index removed, windows after, selected after) for a tab group [A, B, C].
private let tabRemovals: [(selected: Int, removed: Int, after: [WindowRef], selectedAfter: Int)] = [
    (2, 2, [a, b], 1),  // removing the selected last tab selects the new last
    (0, 0, [b, c], 0),  // removing the selected first tab selects the tab that took its index
    (1, 1, [a, c], 1),  // removing the selected middle tab selects the tab that took its index
    (2, 0, [b, c], 1),  // removing a tab before the selected one keeps the same window selected
    (0, 2, [a, b], 0),  // removing a tab after the selected one leaves the index alone
]

@Suite struct TreeEditTests {
    @Test func removeRedistributesShareProportionally() throws {
        var t = try tree(root: 1, [1: h(2, 3, 4, weights: [0.2, 0.3, 0.5]), 2: .panel(a), 3: .panel(b), 4: .panel(c)])
        try t.remove(b)
        guard case let .split(axis, children, weights)? = t.node(n(1)) else {
            Issue.record("root is not a split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children == [n(2), n(4)])
        expectWeights(weights, [0.2 / 0.7, 0.5 / 0.7])
        #expect(t.node(n(3)) == nil)
        #expect(t.state(of: b) == nil)
    }

    @Test func removingOneOfTwoCollapsesTheSplit() throws {
        var t = try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: .panel(b)])
        try t.remove(b)
        #expect(t.root == n(2))
        #expect(t.nodes == [n(2): .panel(a)])
    }

    @Test func innerSplitTakesTheRootSlot() throws {
        var t = try tree(root: 1, [
            1: v(2, 5, weights: [0.5, 0.5]), 2: h(3, 4, weights: [0.3, 0.7]), 3: .panel(a), 4: .panel(b), 5: .panel(c),
        ])
        try t.remove(c)
        #expect(t.root == n(2))
        #expect(t.node(n(2)) == h(3, 4, weights: [0.3, 0.7]))
        #expect(t.nodes.count == 3)
    }

    @Test func collapseMergesSameAxisChildIntoParent() throws {
        // H[A 0.5, V[B 0.5, H[C 0.5, D 0.5]] 0.5] minus B → H[A 0.5, C 0.25, D 0.25]
        var t = try tree(root: 1, [
            1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a),
            3: v(4, 5, weights: [0.5, 0.5]), 4: .panel(b),
            5: h(6, 7, weights: [0.5, 0.5]), 6: .panel(c), 7: .panel(d),
        ])
        try t.remove(b)
        guard case let .split(axis, children, weights)? = t.node(n(1)) else {
            Issue.record("root is not a split")
            return
        }
        #expect(t.root == n(1))
        #expect(axis == .horizontal)
        #expect(children == [n(2), n(6), n(7)])
        expectWeights(weights, [0.5, 0.25, 0.25])
        #expect(t.nodes.count == 4)
    }

    @Test func mergedWeightsBelowMinimumAreClamped() throws {
        // The merged split had slot weight 0.01, so its children would get 0.005 each.
        var t = try tree(root: 1, [
            1: h(2, 3, weights: [0.99, 0.01]), 2: .panel(a),
            3: v(4, 5, weights: [0.5, 0.5]), 4: .panel(b),
            5: h(6, 7, weights: [0.5, 0.5]), 6: .panel(c), 7: .panel(d),
        ])
        try t.remove(b)
        guard case let .split(_, children, weights)? = t.node(n(1)) else {
            Issue.record("root is not a split")
            return
        }
        #expect(children == [n(2), n(6), n(7)])
        expectWeights(weights, [0.98, 0.01, 0.01], tolerance: 1e-9)
        #expect(weights.allSatisfy { $0 >= LayoutTree.minWeight })
        #expect(abs(weights.reduce(0, +) - 1) <= 1e-9)
    }

    @Test func removingTheLastWindowEmptiesTheTree() throws {
        var t = try tree(root: 1, [1: .panel(a)])
        try t.remove(a)
        #expect(t.root == nil)
        #expect(t.nodes.isEmpty)
        #expect(t.states.isEmpty)
        try t.validate()
    }

    @Test func removingAnUnknownWindowThrowsAndChangesNothing() throws {
        var t = try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: .panel(b)])
        let before = t
        #expect(throws: LayoutError.windowNotFound(d)) { try t.remove(d) }
        #expect(t == before)
    }

    @Test(arguments: tabRemovals)
    func removingFromThreeTabsKeepsATabGroup(_ removal: (selected: Int, removed: Int, after: [WindowRef], selectedAfter: Int)) throws {
        var t = try tree(root: 1, [1: .tabs(windows: [a, b, c], selected: removal.selected)])
        try t.remove([a, b, c][removal.removed])
        #expect(t.node(n(1)) == .tabs(windows: removal.after, selected: removal.selectedAfter))
        #expect(Set(t.states.keys) == Set(removal.after.map(\.identity)))
    }

    @Test func removingFromTwoTabsLeavesAPanelWithTheSameID() throws {
        var t = try tree(root: 1, [1: h(2, 3, weights: [0.4, 0.6]), 2: .panel(c), 3: .tabs(windows: [a, b], selected: 1)])
        try t.remove(a)
        #expect(t.node(n(3)) == .panel(b))
        #expect(t.node(n(1)) == h(2, 3, weights: [0.4, 0.6]))
        #expect(t.state(of: a) == nil)
    }

    @Test func insertBesideANearMinimumSiblingClampsIt() throws {
        // n/(n+1) scaling gives [0.01 * 2/3, 0.99 * 2/3, 1/3]; A is pinned to 0.01 and the others share 0.99.
        var t = try tree(root: 1, [1: h(2, 3, weights: [0.01, 0.99]), 2: .panel(a), 3: .panel(b)])
        var ids = IDSource(next: 10)
        try t.insert(c, at: .right, of: n(3), ids: &ids)
        guard case let .split(_, children, weights)? = t.node(n(1)) else {
            Issue.record("root is not a split")
            return
        }
        #expect(children.count == 3)
        let free = 0.99 * 2 / 3 + 1.0 / 3
        expectWeights(weights, [0.01, 0.99 * 2 / 3 / free * 0.99, 1.0 / 3 / free * 0.99], tolerance: 1e-12)
        #expect(weights.allSatisfy { $0 >= LayoutTree.minWeight })
        #expect(abs(weights.reduce(0, +) - 1) <= 1e-9)
    }

    @Test func anIDSourceThatLagsTheTreeThrowsInsteadOfOverwritingNodes() throws {
        // H[A n1, B n2] under n3. Rule 1 would reuse n1 for the new leaf; rule 3 gets a fresh leaf n0
        // but would reuse n1 for the new split.
        let t = try tree(root: 3, [3: h(1, 2, weights: [0.5, 0.5]), 1: .panel(a), 2: .panel(b)])
        for (edge, next) in [(Edge.right, UInt64(1)), (.bottom, 0)] {
            var edited = t
            var ids = IDSource(next: next)
            #expect(throws: LayoutError.invariantViolated("ID source issued n1, which is already in the tree")) {
                try edited.insert(c, at: edge, of: n(2), ids: &ids)
            }
            #expect(edited == t)
            #expect(ids == IDSource(next: next))
        }
    }

    @Test func closingAWindowWhoseMergeWouldPassMaxChildrenKeepsTheChildSplitNested() throws {
        // H[50 panels, V[B, H[60 panels]]] minus B would merge into one split of 109 children, which
        // cannot keep every weight >= minWeight. A confirmed close must still remove B, so the inner
        // H stays nested under the outer H until a later edit makes the merge fit.
        var nodes: [UInt64: Node] = [3: .panel(b)]
        let outer = Array(UInt64(100)..<150), inner = Array(UInt64(200)..<260)
        for raw in outer + inner { nodes[raw] = .panel(makeWindow(UInt32(raw))) }
        nodes[1] = .split(axis: .horizontal, children: (outer + [2]).map(n), weights: Array(repeating: 1 / 51, count: 51))
        nodes[2] = v(3, 4, weights: [0.5, 0.5])
        let innerSplit = Node.split(axis: .horizontal, children: inner.map(n), weights: Array(repeating: 1 / 60, count: 60))
        nodes[4] = innerSplit
        var t = try tree(root: 1, nodes)

        try t.setState(.closed, for: b)
        #expect(t.state(of: b) == nil)
        #expect(t.node(n(2)) == nil)
        guard case let .split(.horizontal, children, _)? = t.node(n(1)) else {
            Issue.record("root is not a horizontal split")
            return
        }
        #expect(children == (outer + [4]).map(n))
        #expect(t.node(n(4)) == innerSplit)
        try t.validate()

        // 40 outer panels + 60 inner = 100 children: now the merge fits and normalisation does it.
        for raw in outer.prefix(10) { try t.remove(makeWindow(UInt32(raw))) }
        #expect(t.node(n(4)) == nil)
        guard case let .split(_, merged, _)? = t.node(n(1)) else {
            Issue.record("root is not a split")
            return
        }
        #expect(merged == (outer.dropFirst(10) + inner).map(n))
        try t.validate()
    }

    @Test func sameAxisNestingIsRejectedWhenTheMergeWouldFit() {
        // The overflow exception above must not admit an ordinary unmerged H[A, H[B, C]].
        #expect(throws: LayoutError.self) {
            try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: h(4, 5, weights: [0.5, 0.5]), 4: .panel(b), 5: .panel(c)])
        }
    }

    // MARK: resizeBoundary (D-07)

    private func threeWide() throws -> LayoutTree {
        try tree(root: 1, [1: h(2, 3, 4, weights: [0.5, 0.3, 0.2]), 2: .panel(a), 3: .panel(b), 4: .panel(c)])
    }

    private func weights(_ t: LayoutTree) -> [Double] {
        if case let .split(_, _, weights)? = t.node(n(1)) { return weights }
        return []
    }

    @Test func resizeMovesWeightBetweenTheTwoNeighboursOnly() throws {
        var t = try threeWide()
        let before = weights(t)
        try t.resizeBoundary(in: n(1), after: 0, by: 0.1)
        let after = weights(t)
        expectWeights(after, [0.6, 0.2, 0.2])
        #expect(after[2] == before[2])
    }

    @Test func resizeClampsBothNeighboursToTheMinimum() throws {
        var t = try threeWide()
        let before = weights(t)
        try t.resizeBoundary(in: n(1), after: 1, by: 0.5)
        var after = weights(t)
        #expect(abs(after[1] + after[2] - 0.5) <= 1e-12)
        #expect(abs(after[2] - LayoutTree.minWeight) <= 1e-12)
        #expect(after[0] == before[0])

        try t.resizeBoundary(in: n(1), after: 0, by: -1)
        after = weights(t)
        #expect(abs(after[0] - LayoutTree.minWeight) <= 1e-12)
        #expect(abs(after[0] + after[1] - 0.99) <= 1e-12)
    }

    @Test func resizeRejectsUnknownNodesAndNonSplits() throws {
        var t = try threeWide()
        let before = t
        #expect(throws: LayoutError.nodeNotFound(n(99))) { try t.resizeBoundary(in: n(99), after: 0, by: 0.1) }
        #expect(throws: LayoutError.notASplit(n(2))) { try t.resizeBoundary(in: n(2), after: 0, by: 0.1) }
        #expect(t == before)
    }

    @Test(arguments: [-1, 2, 3])
    func resizeRejectsBoundariesOutsideTheSplit(index: Int) throws {
        var t = try threeWide()
        let before = t
        #expect(throws: LayoutError.invalidBoundary(split: n(1), index: index)) { try t.resizeBoundary(in: n(1), after: index, by: 0.1) }
        #expect(t == before)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func resizeRejectsNonFiniteDeltas(delta: Double) throws {
        var t = try threeWide()
        let before = t
        #expect(throws: LayoutError.invalidGeometry("delta must be finite")) { try t.resizeBoundary(in: n(1), after: 0, by: delta) }
        #expect(t == before)
    }
}
