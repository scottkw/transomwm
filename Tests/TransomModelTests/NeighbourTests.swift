import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)
private let area = Rect(x: 0, y: 0, width: 1200, height: 800)
private let gap = 8.0

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private func tree(root: UInt64, _ nodes: [UInt64: Node]) throws -> LayoutTree {
    var states: [WindowIdentity: WindowState] = [:]
    for node in nodes.values { if case let .panel(window) = node { states[window.identity] = .present } }
    return try LayoutTree(root: n(root), nodes: Dictionary(uniqueKeysWithValues: nodes.map { (n($0.key), $0.value) }), states: states)
}

/// [a | b | Desktop], side by side.
private func abDesktop() throws -> LayoutTree {
    try tree(root: 1, [
        1: .split(axis: .horizontal, children: [n(2), n(3), .desktop], weights: [0.3, 0.3, 0.4]),
        2: .panel(a), 3: .panel(b), 0: .desktop(hidden: false),
    ])
}

/// [a | V[b, c]]
private func aBesideBC() throws -> LayoutTree {
    try tree(root: 1, [
        1: .split(axis: .horizontal, children: [n(2), n(3)], weights: [0.5, 0.5]),
        2: .panel(a), 3: .split(axis: .vertical, children: [n(4), n(5)], weights: [0.5, 0.5]), 4: .panel(b), 5: .panel(c),
    ])
}

private func neighbour(_ t: LayoutTree, of leaf: NodeID, _ edge: Edge, recency: [NodeID] = []) throws -> NodeID? {
    let r = try resolve(t, in: area, mins: [:], gap: gap)
    return Neighbours.neighbour(of: r.nodeRects[leaf]!, excluding: leaf, toward: edge, tree: t, resolution: r, gap: gap, recency: recency)
}

@Suite struct NeighbourTests {
    @Test func neighbourAcrossEachEdge() throws {
        let t = try abDesktop()
        #expect(try neighbour(t, of: n(2), .right) == n(3))
        #expect(try neighbour(t, of: n(2), .left) == nil)
        #expect(try neighbour(t, of: n(3), .right) == .desktop)
        #expect(try neighbour(t, of: n(3), .left) == n(2))
        #expect(try neighbour(t, of: n(2), .top) == nil)
    }

    @Test func tiesGoToRecencyThenSmallerNodeID() throws {
        let t = try aBesideBC()
        #expect(try neighbour(t, of: n(2), .right, recency: [n(5), n(4)]) == n(5))
        #expect(try neighbour(t, of: n(2), .right, recency: [n(4), n(5)]) == n(4))
        #expect(try neighbour(t, of: n(2), .right) == n(4))
        // b is above c and both touch a; the leaf below b is c, not a.
        #expect(try neighbour(t, of: n(4), .bottom) == n(5))
        #expect(try neighbour(t, of: n(5), .left) == n(2))
    }

    @Test func aFloatingFrameNeedsPerpendicularOverlap() throws {
        let t = try abDesktop()
        let r = try resolve(t, in: area, mins: [:], gap: gap)
        let desktop = r.desktopRect!
        // A floating window inside the Desktop tile: its left neighbour is b.
        let floating = Rect(x: desktop.minX + 50, y: desktop.minY + 50, width: 200, height: 200)
        #expect(Neighbours.neighbour(of: floating, excluding: nil, toward: .left, tree: t, resolution: r, gap: gap, recency: []) == n(3))
        // A frame entirely below the layout overlaps nothing vertically.
        let below = Rect(x: 0, y: area.maxY + 10, width: 400, height: 50)
        #expect(Neighbours.neighbour(of: below, excluding: nil, toward: .right, tree: t, resolution: r, gap: gap, recency: []) == nil)
    }

    @Test func boundaryNamesTheSplitOnAnEdge() throws {
        let pair = try tree(root: 1, [1: .split(axis: .horizontal, children: [n(2), n(3)], weights: [0.5, 0.5]), 2: .panel(a), 3: .panel(b)])
        #expect(Neighbours.boundary(for: n(3), edge: .left, in: pair) == TreeBoundary(split: n(1), index: 0))
        #expect(Neighbours.boundary(for: n(2), edge: .right, in: pair) == TreeBoundary(split: n(1), index: 0))
        #expect(Neighbours.boundary(for: n(2), edge: .left, in: pair) == nil)
        #expect(Neighbours.boundary(for: n(2), edge: .top, in: pair) == nil)

        let t = try aBesideBC()
        #expect(Neighbours.boundary(for: n(5), edge: .left, in: t) == TreeBoundary(split: n(1), index: 0))
        #expect(Neighbours.boundary(for: n(5), edge: .top, in: t) == TreeBoundary(split: n(3), index: 0))
        #expect(Neighbours.boundary(for: n(5), edge: .bottom, in: t) == nil)
        #expect(Neighbours.boundary(for: n(5), edge: .right, in: t) == nil)
    }
}
