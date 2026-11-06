import Foundation
import Testing
@testable import TransomModel

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

/// A World whose desk is [a | b] side by side.
private func worldABDesktop() throws -> World {
    var world = World()
    try world.addDesk(k1)
    var history = UndoHistory()
    try world.edit(k1, history: &history) { desk, ids throws(LayoutError) in
        try desk.tree.applyDrop(.layoutEdge(.right), window: a, ids: &ids)
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
        // A panel and one tab group swap whole leaves (07-06); two tab groups never do.
        let original = try tree(root: 1, [1: h(2, 3, weights: [0.5, 0.5]), 2: .tabs(windows: [a, d], selected: 0), 3: .tabs(windows: [b, c], selected: 0)])
        var t = original
        let selfSwap = #expect(throws: LayoutError.self) { try t.swap(a, a) }
        #expect({ if case .invariantViolated? = selfSwap { true } else { false } }())
        #expect(throws: LayoutError.notALeaf(n(3))) { try t.swap(a, b) }
        let unknown = makeWindow(9)
        #expect(throws: LayoutError.windowNotFound(unknown)) { try t.swap(a, unknown) }
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

    // MARK: resizeChild and resizeBetween (TILE-13, TILE-05)

    private func three(_ w: [Double]) throws -> LayoutTree {
        try tree(root: 1, [1: .split(axis: .horizontal, children: [n(2), n(3), n(4)], weights: w), 2: .panel(a), 3: .panel(b), 4: .panel(c)])
    }

    @Test func resizeChildTakesFromSiblingsInProportion() throws {
        var t = try three([0.5, 0.25, 0.25])
        try t.resizeChild(in: n(1), index: 0, by: 0.1)
        expectWeights(weights(t, 1), [0.6, 0.2, 0.2])
        t = try three([0.5, 0.25, 0.25])
        try t.resizeChild(in: n(1), index: 0, by: -0.1)
        expectWeights(weights(t, 1), [0.4, 0.3, 0.3])
    }

    @Test func resizeChildClampsSiblingsAndThrowsAtTheLimit() throws {
        var t = try three([0.5, 0.48, 0.02])
        try t.resizeChild(in: n(1), index: 0, by: 0.3)
        expectWeights(weights(t, 1), [0.8, 0.19, 0.01])
        try t.validate()

        let full = try three([0.98, 0.01, 0.01])
        t = full
        #expect(throws: LayoutError.atSizeLimit(n(1))) { try t.resizeChild(in: n(1), index: 0, by: 0.1) }
        #expect(t == full)
        let tiny = try three([0.01, 0.5, 0.49])
        t = tiny
        #expect(throws: LayoutError.atSizeLimit(n(1))) { try t.resizeChild(in: n(1), index: 0, by: -0.1) }
        #expect(t == tiny)
        #expect(throws: LayoutError.invalidBoundary(split: n(1), index: 3)) { try t.resizeChild(in: n(1), index: 3, by: 0.1) }
        #expect(throws: LayoutError.notASplit(n(2))) { try t.resizeChild(in: n(2), index: 0, by: 0.1) }
    }

    @Test func resizeBetweenLeavesOtherChildrenAlone() throws {
        var t = try three([0.4, 0.2, 0.4])
        try t.resizeBetween(in: n(1), 0, 2, by: 0.1)
        expectWeights(weights(t, 1), [0.5, 0.2, 0.3])
        #expect(weights(t, 1)[1] == 0.2)
        try t.resizeBetween(in: n(1), 0, 2, by: 1)
        expectWeights(weights(t, 1), [0.79, 0.2, 0.01])
        try t.resizeBetween(in: n(1), 0, 2, by: -1)
        expectWeights(weights(t, 1), [0.01, 0.2, 0.79])
        #expect(throws: LayoutError.invalidBoundary(split: n(1), index: 0)) { try t.resizeBetween(in: n(1), 0, 3, by: 0.1) }
        #expect(throws: LayoutError.invalidBoundary(split: n(1), index: 1)) { try t.resizeBetween(in: n(1), 1, 1, by: 0.1) }
    }
}
