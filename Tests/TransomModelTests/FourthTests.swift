import Foundation
import Testing
@testable import TransomModel

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private let names: [String: UInt32] = ["W": 9, "A": 1, "B": 2, "C": 3]

/// A flat tree along `axis` with the named children and stored weights, "D" being the Desktop tile. A single child is a
/// leaf root. A name in `absent` takes no part: the Desktop is hidden, a window is not present.
private func flat(_ children: [(String, Double)], _ axis: Axis, absent: Set<String> = []) throws -> LayoutTree {
    var nodes: [NodeID: Node] = [:]
    var states: [WindowIdentity: WindowState] = [:]
    var ids: [NodeID] = []
    for (i, child) in children.enumerated() {
        let id = child.0 == "D" ? NodeID.desktop : n(UInt64(i + 2))
        if child.0 == "D" {
            nodes[id] = .desktop(hidden: absent.contains("D"))
        } else {
            let window = makeWindow(names[child.0]!)
            nodes[id] = .panel(window)
            states[window.identity] = absent.contains(child.0) ? .absent : .present
        }
        ids.append(id)
    }
    guard children.count > 1 else { return try LayoutTree(root: ids[0], nodes: nodes, states: states) }
    nodes[n(1)] = .split(axis: axis, children: ids, weights: children.map(\.1))
    return try LayoutTree(root: n(1), nodes: nodes, states: states)
}

/// The tree with window W inserted, as `flat` built it, or with a fourth.
private func inserted(_ tree: LayoutTree, _ slot: FourthSlot, _ axis: Axis) throws -> LayoutTree {
    var tree = tree
    var ids = IDSource(next: 100)
    let w = makeWindow(names["W"]!)
    try tree.insertFourth(.panel(w), states: [w.identity: .present], slot: slot, axis: axis, ids: &ids)
    return tree
}

/// The root's children named by their windows ("(…)" for a nested split), with their stored weights.
private func rootChildren(_ tree: LayoutTree) -> [(String, Double)] {
    guard let root = tree.root, case let .split(_, children, weights)? = tree.node(root) else { return [] }
    return zip(children, weights).map { id, weight -> (String, Double) in
        switch tree.node(id) {
        case .desktop?: ("D", weight)
        case let .panel(window)?: (names.first { $0.value == window.windowID }?.key ?? "?", weight)
        case .tabs?: ("tabs", weight)
        case .split?, nil: ("(…)", weight)
        }
    }
}

private func expectChildren(
    _ tree: LayoutTree, _ expected: [(String, Double)], sourceLocation: SourceLocation = #_sourceLocation
) {
    let actual = rootChildren(tree)
    #expect(actual.map(\.0) == expected.map(\.0), "children \(actual)", sourceLocation: sourceLocation)
    for (got, want) in zip(actual, expected) {
        #expect(abs(got.1 - want.1) <= 1e-9, "\(got.0) has \(got.1), not \(want.1)", sourceLocation: sourceLocation)
    }
}

/// One row of RESEARCH Finding 3's table.
struct FourthTableRow: Sendable, CustomTestStringConvertible {
    let before: [(String, Double)]
    let slot: FourthSlot
    let after: [(String, Double)]
    var testDescription: String { "\(before.map(\.0)) \(slot)" }
}

private let zeroDocked = [("D", 1.0)]
private let oneDocked = [("A", 0.5), ("D", 0.5)]
private let twoDocked = [("A", 1.0 / 3), ("B", 1.0 / 3), ("D", 1.0 / 3)]
private let threeDocked = [("A", 0.6), ("B", 0.2), ("C", 0.1), ("D", 0.1)]

private let table: [FourthTableRow] = [
    FourthTableRow(before: zeroDocked, slot: .first, after: [("W", 1.0 / 4), ("D", 3.0 / 4)]),
    FourthTableRow(before: zeroDocked, slot: .second, after: [("W", 1.0 / 2), ("D", 1.0 / 2)]),
    FourthTableRow(before: zeroDocked, slot: .third, after: [("D", 1.0 / 2), ("W", 1.0 / 2)]),
    FourthTableRow(before: zeroDocked, slot: .fourth, after: [("D", 3.0 / 4), ("W", 1.0 / 4)]),
    FourthTableRow(before: zeroDocked, slot: .middle, after: [("W", 3.0 / 4), ("D", 1.0 / 4)]),
    FourthTableRow(before: oneDocked, slot: .first, after: [("W", 1.0 / 4), ("A", 3.0 / 8), ("D", 3.0 / 8)]),
    FourthTableRow(before: oneDocked, slot: .second, after: [("A", 1.0 / 4), ("W", 1.0 / 4), ("D", 1.0 / 2)]),
    FourthTableRow(before: oneDocked, slot: .third, after: [("A", 1.0 / 2), ("W", 1.0 / 4), ("D", 1.0 / 4)]),
    FourthTableRow(before: oneDocked, slot: .fourth, after: [("A", 3.0 / 8), ("D", 3.0 / 8), ("W", 1.0 / 4)]),
    FourthTableRow(before: oneDocked, slot: .middle, after: [("A", 1.0 / 4), ("W", 1.0 / 2), ("D", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .first, after: [("W", 1.0 / 4), ("A", 1.0 / 4), ("B", 1.0 / 4), ("D", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .second, after: [("A", 1.0 / 4), ("W", 1.0 / 4), ("B", 1.0 / 4), ("D", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .third, after: [("A", 1.0 / 4), ("B", 1.0 / 4), ("W", 1.0 / 4), ("D", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .fourth, after: [("A", 1.0 / 4), ("B", 1.0 / 4), ("D", 1.0 / 4), ("W", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .middle, after: [("A", 1.0 / 4), ("W", 1.0 / 2), ("B", 1.0 / 8), ("D", 1.0 / 8)]),
    FourthTableRow(before: threeDocked, slot: .first, after: [("W", 1.0 / 4), ("A", 0.45), ("B", 0.15), ("C", 0.075), ("D", 0.075)]),
    FourthTableRow(before: threeDocked, slot: .second, after: [("A", 1.0 / 4), ("W", 1.0 / 4), ("B", 1.0 / 4), ("C", 1.0 / 8), ("D", 1.0 / 8)]),
    FourthTableRow(before: threeDocked, slot: .third, after: [("A", 1.0 / 2), ("W", 1.0 / 4), ("B", 1.0 / 8), ("C", 1.0 / 16), ("D", 1.0 / 16)]),
    FourthTableRow(before: threeDocked, slot: .fourth, after: [("A", 0.45), ("B", 0.15), ("C", 0.075), ("D", 0.075), ("W", 1.0 / 4)]),
    FourthTableRow(before: threeDocked, slot: .middle, after: [("A", 1.0 / 4), ("W", 1.0 / 2), ("B", 1.0 / 8), ("C", 1.0 / 16), ("D", 1.0 / 16)]),
]

private let otherWay: [(FourthSlot, [(String, Double)])] = [
    (.first, [("W", 1.0 / 4), ("(…)", 3.0 / 4)]),
    (.third, [("(…)", 1.0 / 2), ("W", 1.0 / 2)]),
    (.middle, [("W", 3.0 / 4), ("(…)", 1.0 / 4)]),
]

/// D-14: a fourth's arithmetic, in stored weights (RESEARCH Finding 3).
@Suite struct FourthTests {
    @Test(arguments: table, [Axis.horizontal, .vertical])
    func theWeightsMatchTheTable(row: FourthTableRow, axis: Axis) throws {
        let tree = try inserted(try flat(row.before, axis), row.slot, axis)
        expectChildren(tree, row.after)
        if case let .split(rootAxis, _, _)? = tree.root.flatMap(tree.node) { #expect(rootAxis == axis) }
    }

    /// The window overload of `applyDrop` gives the same result.
    @Test func applyDropInsertsTheFourth() throws {
        var tree = try flat(oneDocked, .horizontal)
        var ids = IDSource(next: 100)
        try tree.applyDrop(.fourth(.second, .horizontal), window: makeWindow(names["W"]!), ids: &ids)
        expectChildren(tree, [("A", 1.0 / 4), ("W", 1.0 / 4), ("D", 1.0 / 2)])
    }

    @Test func aNestedSplitMovesAsOneChildWithItsInnerWeightsUntouched() throws {
        let l = makeWindow(1), c = makeWindow(2), d = makeWindow(3)
        let inner = Node.split(axis: .vertical, children: [n(4), n(5)], weights: [0.3, 0.7])
        let before = try LayoutTree(
            root: n(1),
            nodes: [
                n(1): .split(axis: .horizontal, children: [n(2), n(3)], weights: [0.5, 0.5]), n(2): .panel(l), n(3): inner,
                n(4): .panel(c), n(5): .panel(d),
            ],
            states: [l.identity: .present, c.identity: .present, d.identity: .present])
        let tree = try inserted(before, .second, .horizontal)
        expectChildren(tree, [("A", 1.0 / 4), ("W", 1.0 / 4), ("(…)", 1.0 / 2)])
        #expect(tree.node(n(3)) == inner)
    }

    @Test(arguments: otherWay)
    func aRootSplitTheOtherWayBecomesOneChild(slot: FourthSlot, expected: [(String, Double)]) throws {
        let before = try flat([("A", 0.5), ("B", 0.5)], .vertical)
        let tree = try inserted(before, slot, .horizontal)
        expectChildren(tree, expected)
        guard case let .split(axis, _, _)? = tree.root.flatMap(tree.node) else {
            Issue.record("no new root")
            return
        }
        #expect(axis == .horizontal)
        #expect(tree.node(n(1)) == before.node(n(1)), "the old root's weights changed")
    }

    @Test func aDockedSingleRootLeafBehavesLikeTheDesktopLeaf() throws {
        expectChildren(try inserted(try flat([("A", 1)], .horizontal), .first, .horizontal), [("W", 1.0 / 4), ("A", 3.0 / 4)])
        expectChildren(try inserted(try flat([("A", 1)], .horizontal), .middle, .vertical), [("W", 3.0 / 4), ("A", 1.0 / 4)])
    }

    /// The window comes off first, the split left with one child collapses, and the root then runs the other way.
    @Test func removingTheWindowCanTurnTheRootTheOtherWay() throws {
        let w = makeWindow(names["W"]!), a = makeWindow(1), b = makeWindow(2)
        var tree = try LayoutTree(
            root: n(1),
            nodes: [
                n(1): .split(axis: .horizontal, children: [n(2), n(3)], weights: [0.5, 0.5]), n(2): .panel(w),
                n(3): .split(axis: .vertical, children: [n(4), n(5)], weights: [0.5, 0.5]), n(4): .panel(a), n(5): .panel(b),
            ],
            states: [w.identity: .present, a.identity: .present, b.identity: .present])
        try tree.remove(w)
        expectChildren(try inserted(tree, .first, .horizontal), [("W", 1.0 / 4), ("(…)", 3.0 / 4)])
    }

    @Test func aTabGroupIsOneChildGoingInAndWhenAlreadyThere() throws {
        let b = makeWindow(2), c = makeWindow(3)
        var tree = try flat(oneDocked, .horizontal)
        var ids = IDSource(next: 100)
        try tree.insertFourth(
            .tabs(windows: [b, c], selected: 0), states: [b.identity: .present, c.identity: .present], slot: .third, axis: .horizontal, ids: &ids)
        expectChildren(tree, [("A", 1.0 / 2), ("tabs", 1.0 / 4), ("D", 1.0 / 4)])

        let tabbed = try LayoutTree(
            root: n(1),
            nodes: [n(1): .split(axis: .horizontal, children: [n(2), .desktop], weights: [0.5, 0.5]), n(2): .tabs(windows: [b, c], selected: 1), .desktop: .desktop(hidden: false)],
            states: [b.identity: .present, c.identity: .present])
        expectChildren(try inserted(tabbed, .first, .horizontal), [("W", 1.0 / 4), ("tabs", 3.0 / 8), ("D", 3.0 / 8)])
    }

    /// A hidden Desktop keeps its stored weight and the others scale into the rest, so W still gets ¼ of what shows.
    @Test func aHiddenDesktopKeepsItsWeightAndTheOthersScaleIntoTheRest() throws {
        let before = try flat([("A", 0.25), ("B", 0.25), ("D", 0.5)], .horizontal, absent: ["D"])
        expectChildren(try inserted(before, .first, .horizontal), [("W", 1.0 / 8), ("A", 3.0 / 16), ("B", 3.0 / 16), ("D", 1.0 / 2)])
    }

    /// B is absent, so positions are worked out over A and D only: A's centre ⅓ is before ⅜ and D's ⅚ after it.
    @Test func aChildNotPresentKeepsItsWeightAndTakesNoPartInThePosition() throws {
        let before = try flat([("A", 0.5), ("B", 0.25), ("D", 0.25)], .horizontal, absent: ["B"])
        expectChildren(try inserted(before, .second, .horizontal), [("A", 3.0 / 16), ("B", 1.0 / 4), ("W", 3.0 / 16), ("D", 3.0 / 8)])
    }

    @Test func withNothingElseTakingPartTheWindowFillsTheDesk() throws {
        let before = try flat([("A", 0.5), ("D", 0.5)], .horizontal, absent: ["A", "D"])
        let tree = try inserted(before, .second, .horizontal)
        let w = makeWindow(names["W"]!)
        let leaf = try #require(tree.leaf(containing: w))
        let area = Rect(x: 0, y: 0, width: 1000, height: 500)
        #expect(try resolve(tree, in: area, mins: [:], gap: 0).nodeRects[leaf] == area)
        #expect(tree.isDesktopHidden == true)
    }

    /// WR-07: filling the desk while it's the only one taking part must not leave the window a sliver when the others return.
    @Test func withNothingElseTakingPartTheWindowKeepsARealShareForWhenTheOthersReturn() throws {
        let before = try flat([("A", 0.5), ("D", 0.5)], .horizontal, absent: ["A", "D"])
        expectChildren(try inserted(before, .second, .horizontal), [("A", 1.0 / 4), ("D", 1.0 / 4), ("W", 1.0 / 2)])
        // A lone hidden Desktop: the root the window wraps.
        let lone = try flat([("D", 1)], .horizontal, absent: ["D"])
        expectChildren(try inserted(lone, .first, .horizontal), [("W", 1.0 / 2), ("D", 1.0 / 2)])
    }

    @Test func aRootAtMaxChildrenThrowsAndChangesNothing() throws {
        var nodes: [NodeID: Node] = [:]
        var states: [WindowIdentity: WindowState] = [:]
        let children = (0..<LayoutTree.maxChildren).map { n(UInt64($0 + 2)) }
        for (i, id) in children.enumerated() {
            let window = makeWindow(UInt32(i + 1000))
            nodes[id] = .panel(window)
            states[window.identity] = .present
        }
        nodes[n(1)] = .split(axis: .horizontal, children: children, weights: children.map { _ in 1.0 / Double(LayoutTree.maxChildren) })
        var tree = try LayoutTree(root: n(1), nodes: nodes, states: states)
        let before = tree
        var ids = IDSource(next: 3000)
        let w = makeWindow(names["W"]!)
        #expect(throws: LayoutError.splitFull(n(1), limit: LayoutTree.maxChildren)) {
            try tree.insertFourth(.panel(w), states: [w.identity: .present], slot: .second, axis: .horizontal, ids: &ids)
        }
        #expect(tree == before)
        #expect(ids == IDSource(next: 3000))
    }

    @Test func aWrapPastMaxDepthThrowsAndChangesNothing() throws {
        let deep = chain(splits: LayoutTree.maxDepth)  // its root is horizontal, so a row wraps the whole tree
        var tree = try LayoutTree(root: deep.root, nodes: deep.nodes, states: deep.states)
        let before = tree
        var ids = IDSource(next: 3000)
        let w = makeWindow(names["W"]!)
        #expect(throws: LayoutError.tooDeep(limit: LayoutTree.maxDepth)) {
            try tree.insertFourth(.panel(w), states: [w.identity: .present], slot: .first, axis: .vertical, ids: &ids)
        }
        #expect(tree == before)
        #expect(ids == IDSource(next: 3000))
    }

    // MARK: Zones (UI-SPEC Surface 3)

    private static let visible = Rect(x: 100, y: 50, width: 1600, height: 800)

    /// `p` along the axis from the visible frame's left or top, with the other coordinate anywhere inside it.
    private static func point(_ p: Double, _ axis: Axis) -> Point {
        axis == .horizontal
            ? Point(x: visible.minX + p * visible.width, y: visible.midY)
            : Point(x: visible.midX, y: visible.minY + p * visible.height)
    }

    @Test(arguments: [Axis.horizontal, .vertical])
    func theZonesFollowTheSurface3Table(axis: Axis) {
        let below = 1e-6
        let cases: [(Double, FourthSlot)] = [
            (0, .first), (0.25 - below, .first), (0.25, .second), (0.375 - below, .second), (0.375, .middle), (0.625 - below, .middle),
            (0.625, .third), (0.75 - below, .third), (0.75, .fourth), (1, .fourth), (-0.5, .first), (1.5, .fourth),
        ]
        for (p, slot) in cases {
            #expect(FourthZones.slot(at: Self.point(p, axis), in: Self.visible, axis: axis) == slot, "p \(p)")
        }
    }

    /// D-23: `fourthSpan` says what `insertFourth` then does, read back off the weights, along either axis.
    @Test(arguments: [
        ([("D", 1.0)], Set<String>(), FourthSlot.first, 0.0, 0.25),
        ([("D", 1)], [], .second, 0, 0.5),
        ([("D", 1)], [], .middle, 0, 0.75),
        ([("D", 1)], [], .third, 0.5, 1),
        ([("D", 1)], [], .fourth, 0.75, 1),
        ([("D", 1)], ["D"], .third, 0, 1),
        ([("A", 0.5), ("D", 0.5)], [], .second, 0.25, 0.5),
        ([("A", 0.5), ("D", 0.5)], [], .middle, 0.25, 0.75),
        ([("A", 0.5), ("D", 0.5)], [], .third, 0.5, 0.75),
        ([("A", 0.5), ("D", 0.5)], ["D"], .middle, 0, 0.75),
        ([("A", 0.5), ("D", 0.5)], ["A", "D"], .second, 0, 1),
        ([("A", 0.2), ("D", 0.8)], [], .third, 0.5, 1),
        ([("A", 0.8), ("D", 0.2)], [], .second, 0, 0.5),
        ([("A", 0.8), ("D", 0.2)], [], .third, 0.5, 0.75),
        ([("A", 0.2), ("D", 0.8)], [], .first, 0, 0.25),
        ([("A", 0.125), ("B", 0.875)], [], .third, 0.5, 1),
    ] as [([(String, Double)], Set<String>, FourthSlot, Double, Double)])
    func theSpanIsWhatTheWindowGets(children: [(String, Double)], absent: Set<String>, slot: FourthSlot, start: Double, end: Double) throws {
        for axis in [Axis.horizontal, .vertical] {
            let tree = try flat(children, axis, absent: absent)
            let span = tree.fourthSpan(slot, axis: axis)
            #expect(span.start == start && span.end == end, "\(span)")
            let result = try inserted(tree, slot, axis)
            let root = rootChildren(result)
            let index = try #require(root.firstIndex { $0.0 == "W" })
            let taking = root.enumerated().filter { $0.element.0 == "W" || !absent.contains($0.element.0) }
            let total = taking.reduce(0) { $0 + $1.element.1 }
            let before = taking.filter { $0.offset < index }.reduce(0) { $0 + $1.element.1 }
            #expect(abs(before / total - start) <= 1e-9, "\(root)")
            #expect(abs((before + root[index].1) / total - end) <= 1e-9, "\(root)")
        }
    }

    @Test(arguments: [Axis.horizontal, .vertical])
    func theBandsCoverTheVisibleFrameInHitOrder(axis: Axis) throws {
        let bands = FourthZones.bands(in: Self.visible, axis: axis)
        try #require(bands.count == 5)
        #expect(bands.map { FourthZones.slot(at: Point(x: $0.midX, y: $0.midY), in: Self.visible, axis: axis) } == [.first, .second, .middle, .third, .fourth])
        for band in bands {
            if axis == .horizontal {
                #expect(band.y == Self.visible.y && band.height == Self.visible.height)
            } else {
                #expect(band.x == Self.visible.x && band.width == Self.visible.width)
            }
        }
        for (one, next) in zip(bands, bands.dropFirst()) {
            #expect(axis == .horizontal ? one.maxX == next.minX : one.maxY == next.minY, "a gap or overlap: \(one), \(next)")
        }
        #expect(axis == .horizontal ? bands[0].minX == Self.visible.minX : bands[0].minY == Self.visible.minY)
        #expect(axis == .horizontal ? bands[4].maxX == Self.visible.maxX : bands[4].maxY == Self.visible.maxY)
    }
}
