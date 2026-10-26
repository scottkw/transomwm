import Foundation
import Testing
@testable import PaneModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let d = makeWindow(4)
private let k1 = DeskKey(displayUUID: "D1", spaceID: nil)
private let area = Rect(x: 0, y: 0, width: 1200, height: 800)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

/// A validated tree from raw-ID nodes (0 is the Desktop tile); every window in it is present.
private func tree(root: UInt64, _ nodes: [UInt64: Node]) throws -> LayoutTree {
    var states: [WindowIdentity: WindowState] = [:]
    for node in nodes.values {
        switch node {
        case let .panel(window): states[window.identity] = .present
        case let .tabs(windows, _): for window in windows { states[window.identity] = .present }
        case .split, .desktop: break
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

private func weights(_ t: LayoutTree, _ split: UInt64) -> [Double] {
    guard case let .split(_, _, w)? = t.node(n(split)) else { return [] }
    return w
}

private func expectWeights(_ actual: [Double], _ expected: [Double], tolerance: Double = 1e-12) {
    #expect(actual.count == expected.count)
    for (x, y) in zip(actual, expected) { #expect(abs(x - y) <= tolerance, "\(actual) != \(expected)") }
}

/// A World whose desk is [a | b | Desktop] side by side.
private func worldABDesktop() throws -> World {
    var world = World()
    try world.addDesk(k1)
    var history = UndoHistory()
    try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.insert(a, at: .left, of: .desktop, ids: &ids)
        try desk.tree.insert(b, at: .right, of: desk.tree.leaf(containing: a)!, ids: &ids)
    }
    return world
}

@Suite struct LayoutEditTests {
    // MARK: swap

    @Test func swapTradesRectsInOneUndoStep() throws {
        var world = try worldABDesktop()
        var history = UndoHistory()
        let before = try resolve(world[k1]!.tree, in: area, mins: [:], gap: 8)
        try world.edit(k1, history: &history) { desk, _ throws(LayoutError) in try desk.tree.swap(a, b) }
        #expect(history.depth(for: k1) == 1)
        let after = try resolve(world[k1]!.tree, in: area, mins: [:], gap: 8)
        #expect(after.windowRects[a] == before.windowRects[b])
        #expect(after.windowRects[b] == before.windowRects[a])
        #expect(world[k1]!.tree.state(of: a) == .present)
        #expect(try world.undo(k1, history: &history) != nil)
        #expect(try resolve(world[k1]!.tree, in: area, mins: [:], gap: 8) == before)
    }

    @Test func swapRejectsSelfTabsAndUnknownWindows() throws {
        let original = try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .panel(a), 3: .tabs(windows: [b, c], selected: 0)])
        var t = original
        let selfSwap = #expect(throws: LayoutError.self) { try t.swap(a, a) }
        #expect({ if case .invariantViolated? = selfSwap { true } else { false } }())
        #expect(throws: LayoutError.notALeaf(n(3))) { try t.swap(a, b) }
        #expect(throws: LayoutError.windowNotFound(d)) { try t.swap(a, d) }
        #expect(t == original)
    }

    // MARK: balance and flip

    @Test func balanceEqualisesWeights() throws {
        var t = try tree(root: 1, [1: h(2, 3, 4, weights: [0.7, 0.2, 0.1]), 2: .panel(a), 3: .panel(b), 4: .panel(c)])
        try t.balance(split: n(1))
        expectWeights(weights(t, 1), [1.0 / 3, 1.0 / 3, 1.0 / 3])
        #expect(throws: LayoutError.notASplit(n(2))) { try t.balance(split: n(2)) }
        #expect(throws: LayoutError.nodeNotFound(n(9))) { try t.balance(split: n(9)) }
        try t.validate()
    }

    @Test func flipReversesChildrenAndWeights() throws {
        var t = try tree(root: 1, [1: h(2, 3, 4, weights: [0.5, 0.3, 0.2]), 2: .panel(a), 3: .panel(b), 4: .panel(c)])
        try t.flip(split: n(1))
        #expect(t.node(n(1)) == h(4, 3, 2, weights: [0.2, 0.3, 0.5]))
        #expect(throws: LayoutError.notASplit(n(2))) { try t.flip(split: n(2)) }
        try t.validate()
    }

    // MARK: rotate (D-32)

    @Test func rotateRootFlipsEveryAxisAndIsItsOwnInverse() throws {
        let original = try tree(root: 1, [
            1: h(2, 3, weights: [0.4, 0.6]), 2: .panel(a), 3: v(4, 5, weights: [0.3, 0.7]), 4: .panel(b), 5: .panel(c),
        ])
        var t = original
        try t.rotate(split: n(1))
        #expect(t.node(n(1)) == v(2, 3, weights: [0.4, 0.6]))
        #expect(t.node(n(3)) == h(4, 5, weights: [0.3, 0.7]))
        try t.validate()
        try t.rotate(split: n(1))
        #expect(t == original)
    }

    @Test func rotateNestedSplitStartsAtTheRoot() throws {
        let original = try tree(root: 1, [
            1: h(2, 3, 0, weights: [0.3, 0.4, 0.3]), 2: .panel(a), 3: v(4, 5, weights: [0.5, 0.5]),
            4: .panel(b), 5: .panel(c), 0: .desktop(hidden: false),
        ])
        var t = original
        try t.rotate(split: n(3))
        #expect(t.node(n(1)) == v(2, 3, 0, weights: [0.3, 0.4, 0.3]))
        #expect(t.node(n(3)) == h(4, 5, weights: [0.5, 0.5]))
        try t.validate()
        try t.rotate(split: n(3))
        #expect(t == original)
        #expect(throws: LayoutError.notASplit(n(2))) { try t.rotate(split: n(2)) }
    }
}
