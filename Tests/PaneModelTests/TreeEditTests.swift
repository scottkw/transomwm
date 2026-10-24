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
}
