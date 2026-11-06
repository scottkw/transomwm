import Foundation
import Testing
@testable import TransomModel

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private let names: [String: UInt32] = ["W": 9, "A": 1, "B": 2, "C": 3, "X": 10, "Y": 11]

/// A flat tree along `axis` with the named docked children and stored weights. A single child is a leaf root, and "_" is an
/// empty area (8.1.1 D-16). A name in `absent` takes no part: its window is not present.
private func flat(_ children: [(String, Double)], _ axis: Axis, absent: Set<String> = []) throws -> LayoutTree {
    var nodes: [NodeID: Node] = [:]
    var states: [WindowIdentity: WindowState] = [:]
    var ids: [NodeID] = []
    for (i, child) in children.enumerated() {
        let id = n(UInt64(i + 2))
        ids.append(id)
        guard child.0 != "_" else {
            nodes[id] = .spacer
            continue
        }
        let window = makeWindow(names[child.0]!)
        nodes[id] = .panel(window)
        states[window.identity] = absent.contains(child.0) ? .absent : .present
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
        case let .panel(window)?: (names.first { $0.value == window.windowID }?.key ?? "?", weight)
        case .tabs?: ("tabs", weight)
        case .spacer?: ("_", weight)
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

/// 8.1.1 D-04: docked tiles only. An empty desk has its own test (`onAnEmptyDeskTheWindowGetsExactlyItsSpan`). "_" is an
/// empty area: since 8.1.1 D-16 a side with no tile stays empty (E3) instead of the window growing into it.
private let oneDocked = [("A", 1.0)]
private let twoDocked = [("A", 1.0 / 2), ("B", 1.0 / 2)]
private let threeDocked = [("A", 2.0 / 3), ("B", 2.0 / 9), ("C", 1.0 / 9)]

private let table: [FourthTableRow] = [
    FourthTableRow(before: oneDocked, slot: .first, after: [("W", 1.0 / 4), ("A", 3.0 / 4)]),
    // E1, E3: A goes after (before) the window and the side with no tile stays empty.
    FourthTableRow(before: oneDocked, slot: .second, after: [("_", 1.0 / 4), ("W", 1.0 / 4), ("A", 1.0 / 2)]),
    FourthTableRow(before: oneDocked, slot: .third, after: [("A", 1.0 / 2), ("W", 1.0 / 4), ("_", 1.0 / 4)]),
    FourthTableRow(before: oneDocked, slot: .fourth, after: [("A", 3.0 / 4), ("W", 1.0 / 4)]),
    FourthTableRow(before: oneDocked, slot: .middle, after: [("_", 1.0 / 4), ("W", 1.0 / 2), ("A", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .first, after: [("W", 1.0 / 4), ("A", 3.0 / 8), ("B", 3.0 / 8)]),
    FourthTableRow(before: twoDocked, slot: .second, after: [("A", 1.0 / 4), ("W", 1.0 / 4), ("B", 1.0 / 2)]),
    FourthTableRow(before: twoDocked, slot: .third, after: [("A", 1.0 / 2), ("W", 1.0 / 4), ("B", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .fourth, after: [("A", 3.0 / 8), ("B", 3.0 / 8), ("W", 1.0 / 4)]),
    FourthTableRow(before: twoDocked, slot: .middle, after: [("A", 1.0 / 4), ("W", 1.0 / 2), ("B", 1.0 / 4)]),
    FourthTableRow(before: threeDocked, slot: .first, after: [("W", 1.0 / 4), ("A", 1.0 / 2), ("B", 1.0 / 6), ("C", 1.0 / 12)]),
    // E3: B and C move aside and keep their widths; the space they leave stays empty.
    FourthTableRow(before: threeDocked, slot: .second, after: [("A", 1.0 / 4), ("W", 1.0 / 4), ("_", 1.0 / 6), ("B", 2.0 / 9), ("C", 1.0 / 9)]),
    FourthTableRow(before: threeDocked, slot: .third, after: [("A", 1.0 / 2), ("W", 1.0 / 4), ("B", 1.0 / 6), ("C", 1.0 / 12)]),
    FourthTableRow(before: threeDocked, slot: .fourth, after: [("A", 1.0 / 2), ("B", 1.0 / 6), ("C", 1.0 / 12), ("W", 1.0 / 4)]),
    FourthTableRow(before: threeDocked, slot: .middle, after: [("A", 1.0 / 4), ("W", 1.0 / 2), ("B", 1.0 / 6), ("C", 1.0 / 12)]),
]

private let leftHalf = [("A", 1.0 / 2), ("_", 1.0 / 2)]

/// 8.1.1 D-16, rules E2 and E3: empty space is used first, a tile moved aside keeps its length, and nothing grows.
private let emptyFirst: [FourthTableRow] = [
    // E2: the empty area is filled and A doesn't move.
    FourthTableRow(before: leftHalf, slot: .secondHalf, after: [("A", 1.0 / 2), ("W", 1.0 / 2)]),
    FourthTableRow(before: leftHalf, slot: .fourth, after: [("A", 1.0 / 2), ("_", 1.0 / 4), ("W", 1.0 / 4)]),
    FourthTableRow(before: leftHalf, slot: .third, after: [("A", 1.0 / 2), ("W", 1.0 / 4), ("_", 1.0 / 4)]),
    // E2: A keeps its length and moves right into the empty area.
    FourthTableRow(before: leftHalf, slot: .firstThird, after: [("W", 1.0 / 3), ("A", 1.0 / 2), ("_", 1.0 / 6)]),
    // E2: no empty area on A's side, so A shrinks.
    FourthTableRow(before: leftHalf, slot: .middle, after: [("A", 1.0 / 4), ("W", 1.0 / 2), ("_", 1.0 / 4)]),
    // E3: B moves aside and the space it leaves stays empty.
    FourthTableRow(before: [("A", 0.25), ("B", 0.75)], slot: .third, after: [("A", 1.0 / 4), ("_", 1.0 / 4), ("W", 1.0 / 4), ("B", 1.0 / 4)]),
    // E2: A moves into the empty area on its side and keeps its length.
    FourthTableRow(before: [("_", 0.25), ("A", 0.5), ("_", 0.25)], slot: .firstHalf, after: [("W", 1.0 / 2), ("A", 1.0 / 2)]),
]

private let otherWay: [(FourthSlot, [(String, Double)])] = [
    (.first, [("W", 1.0 / 4), ("(…)", 3.0 / 4)]),
    // E1, E3: the side with no tile stays empty.
    (.third, [("(…)", 1.0 / 2), ("W", 1.0 / 4), ("_", 1.0 / 4)]),
    (.middle, [("_", 1.0 / 4), ("W", 1.0 / 2), ("(…)", 1.0 / 4)]),
]

/// D-14: a fourth's arithmetic, in stored weights (RESEARCH Finding 3).
@Suite struct FourthTests {
    @Test(arguments: table, [Axis.horizontal, .vertical])
    func theWeightsMatchTheTable(row: FourthTableRow, axis: Axis) throws {
        let tree = try inserted(try flat(row.before, axis), row.slot, axis)
        expectChildren(tree, row.after)
        if case let .split(rootAxis, _, _)? = tree.root.flatMap(tree.node) { #expect(rootAxis == axis) }
    }

    @Test(arguments: emptyFirst, [Axis.horizontal, .vertical])
    func emptySpaceIsUsedFirstAndNothingGrows(row: FourthTableRow, axis: Axis) throws {
        expectChildren(try inserted(try flat(row.before, axis), row.slot, axis), row.after)
    }

    /// E1, E3, WR-07: every docked window minimised, W still gets exactly the left half and A keeps its stored weight.
    @Test func withEveryDockedWindowMinimisedTheLeftHalfIsExact() throws {
        let tree = try inserted(try flat([("A", 1)], .horizontal, absent: ["A"]), .firstHalf, .horizontal)
        let leaf = try #require(tree.leaf(containing: makeWindow(names["W"]!)))
        let area = Rect(x: 0, y: 0, width: 1000, height: 500)
        #expect(try resolve(tree, in: area, mins: [:], gap: 0).nodeRects[leaf] == Rect(x: 0, y: 0, width: 500, height: 500))
        expectChildren(tree, [("W", 1.0 / 4), ("_", 1.0 / 4), ("A", 1.0 / 2)])
    }

    /// A root split the other way with no empty margin along the axis: it is one child, beside the window (E3 keeps it
    /// at half, the space it had).
    @Test(arguments: [Axis.horizontal, .vertical])
    func aRootSplitTheOtherWayWithNoMarginIsOneChild(axis: Axis) throws {
        let other: Axis = axis == .horizontal ? .vertical : .horizontal
        let before = try flat([("A", 0.5), ("_", 0.5)], other)
        let tree = try inserted(before, .firstHalf, axis)
        expectChildren(tree, [("W", 1.0 / 2), ("(…)", 1.0 / 2)])
        #expect(tree.node(n(1)) == before.node(n(1)), "the old root changed")
    }

    /// 8.1.1 D-17's corner case (E2): after the Top Left and Bottom Left quarters, the Right Half takes the right half
    /// from both rows' empty margins, and X and Y keep their size.
    @Test(arguments: [Axis.horizontal, .vertical])
    func aRootSplitTheOtherWayGivesUpItsEmptyMarginsFirst(axis: Axis) throws {
        let other: Axis = axis == .horizontal ? .vertical : .horizontal
        let x = makeWindow(1), y = makeWindow(2)
        let before = try LayoutTree(
            root: n(1),
            nodes: [
                n(1): .split(axis: other, children: [n(2), n(3)], weights: [0.5, 0.5]),
                n(2): .split(axis: axis, children: [n(4), n(5)], weights: [0.5, 0.5]), n(4): .panel(x), n(5): .spacer,
                n(3): .split(axis: axis, children: [n(6), n(7)], weights: [0.5, 0.5]), n(6): .panel(y), n(7): .spacer,
            ],
            states: [x.identity: .present, y.identity: .present])
        let tree = try inserted(before, .secondHalf, axis)
        expectChildren(tree, [("(…)", 1.0 / 2), ("W", 1.0 / 2)])
        #expect(tree.node(n(1)) == .split(axis: other, children: [n(4), n(6)], weights: [0.5, 0.5]))
        #expect(tree.node(n(5)) == nil && tree.node(n(7)) == nil, "the used empty areas are gone")
    }

    /// The window overload of `applyDrop` gives the same result.
    @Test func applyDropInsertsTheFourth() throws {
        var tree = try flat(twoDocked, .horizontal)
        var ids = IDSource(next: 100)
        try tree.applyDrop(.fourth(.second, .horizontal), window: makeWindow(names["W"]!), ids: &ids)
        expectChildren(tree, [("A", 1.0 / 4), ("W", 1.0 / 4), ("B", 1.0 / 2)])
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
        expectChildren(tree, [("A", 1.0 / 2), ("tabs", 1.0 / 4), ("_", 1.0 / 4)])  // E1, E3

        let tabbed = try LayoutTree(root: n(2), nodes: [n(2): .tabs(windows: [b, c], selected: 1)], states: [b.identity: .present, c.identity: .present])
        expectChildren(try inserted(tabbed, .first, .horizontal), [("W", 1.0 / 4), ("tabs", 3.0 / 4)])
    }

    /// B is absent, so positions are worked out over A and C only: A's centre ⅓ is before ⅜ and C's ⅚ after it. E3: C
    /// keeps its width (⅓ of the room A and C share) and the rest of its side stays empty.
    @Test func aChildNotPresentKeepsItsWeightAndTakesNoPartInThePosition() throws {
        let before = try flat([("A", 0.5), ("B", 0.25), ("C", 0.25)], .horizontal, absent: ["B"])
        expectChildren(
            try inserted(before, .second, .horizontal), [("A", 3.0 / 16), ("B", 1.0 / 4), ("W", 3.0 / 16), ("_", 1.0 / 8), ("C", 1.0 / 4)])
    }

    /// E1: with nothing else taking part the window still gets exactly its span, not the whole desk.
    @Test func withNothingElseTakingPartTheWindowGetsExactlyItsSpan() throws {
        let before = try flat([("A", 0.5), ("B", 0.5)], .horizontal, absent: ["A", "B"])
        let tree = try inserted(before, .second, .horizontal)
        let w = makeWindow(names["W"]!)
        let leaf = try #require(tree.leaf(containing: w))
        let area = Rect(x: 0, y: 0, width: 1000, height: 500)
        #expect(try resolve(tree, in: area, mins: [:], gap: 0).nodeRects[leaf] == Rect(x: 250, y: 0, width: 250, height: 500))
    }

    /// WR-07: filling the desk while it's the only one taking part must not leave the window a sliver when the others return.
    @Test func withNothingElseTakingPartTheWindowKeepsARealShareForWhenTheOthersReturn() throws {
        let before = try flat([("A", 0.5), ("B", 0.5)], .horizontal, absent: ["A", "B"])
        // E1, E3: the window and the empty areas share the stored total; A and B keep their weights.
        expectChildren(
            try inserted(before, .second, .horizontal), [("A", 1.0 / 4), ("B", 1.0 / 4), ("_", 1.0 / 8), ("W", 1.0 / 8), ("_", 1.0 / 4)])
        // A lone absent leaf root: the root the window wraps.
        let lone = try flat([("A", 1)], .horizontal, absent: ["A"])
        expectChildren(try inserted(lone, .firstHalf, .horizontal), [("W", 1.0 / 4), ("_", 1.0 / 4), ("A", 1.0 / 2)])
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

    // MARK: Halves and thirds (08.1.1 D-10), on trees with no Desktop node

    /// 8.1.1 D-16, E1 and E3: with nothing docked the window gets exactly its span, and the rest stays empty.
    @Test(arguments: FourthSlot.allCases, [Axis.horizontal, .vertical])
    func onAnEmptyDeskTheWindowGetsExactlyItsSpan(slot: FourthSlot, axis: Axis) throws {
        let tree = try inserted(LayoutTree(), slot, axis)
        let (a, b) = slot.span
        let expected = (a > 0 ? [("_", a)] : []) + [("W", b - a)] + (b < 1 ? [("_", 1 - b)] : [])
        expectChildren(tree, expected)
        if case let .split(rootAxis, _, _)? = tree.root.flatMap(tree.node) { #expect(rootAxis == axis) }
    }

    @Test(arguments: [
        FourthTableRow(before: [("A", 1)], slot: .firstHalf, after: [("W", 1.0 / 2), ("A", 1.0 / 2)]),
        FourthTableRow(before: [("A", 1)], slot: .secondHalf, after: [("A", 1.0 / 2), ("W", 1.0 / 2)]),
        FourthTableRow(before: [("A", 1)], slot: .firstThird, after: [("W", 1.0 / 3), ("A", 2.0 / 3)]),
        FourthTableRow(before: [("A", 1)], slot: .lastThird, after: [("A", 2.0 / 3), ("W", 1.0 / 3)]),
        // A is centred at ½, the window's position, so it goes after; E1, E3: the left third stays empty.
        FourthTableRow(before: [("A", 1)], slot: .middleThird, after: [("_", 1.0 / 3), ("W", 1.0 / 3), ("A", 1.0 / 3)]),
        FourthTableRow(before: [("A", 0.5), ("B", 0.5)], slot: .middleThird, after: [("A", 1.0 / 3), ("W", 1.0 / 3), ("B", 1.0 / 3)]),
        FourthTableRow(before: [("A", 0.5), ("B", 0.5)], slot: .firstHalf, after: [("W", 1.0 / 2), ("A", 1.0 / 4), ("B", 1.0 / 4)]),
    ])
    func halvesAndThirdsUseTheFourthArithmetic(row: FourthTableRow) throws {
        for axis in [Axis.horizontal, .vertical] {
            expectChildren(try inserted(try flat(row.before, axis), row.slot, axis), row.after)
        }
    }

    /// D-12: the user's collapsed window was not the Desktop tile's doing. On two equal tiles a 3rd-column fourth leaves the
    /// trailing one a quarter of the width, with no Desktop tile at all.
    @Test func theD12ThirdColumnGivesTheTrailingTileAQuarter() throws {
        let tree = try inserted(try flat([("A", 0.5), ("B", 0.5)], .horizontal), .third, .horizontal)
        expectChildren(tree, [("A", 1.0 / 2), ("W", 1.0 / 4), ("B", 1.0 / 4)])
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

    /// 8.1.1 D-16, E1: whatever the desk holds, the window gets exactly its slot's span, read back off the weights along
    /// either axis. Several of these rows used to grow into an empty side.
    @Test(arguments: [
        ([("A", 1.0)], Set<String>(), FourthSlot.first),
        ([("A", 1)], [], .second),
        ([("A", 1)], [], .middle),
        ([("A", 1)], [], .third),
        ([("A", 1)], [], .fourth),
        ([("A", 1)], ["A"], .third),
        ([("A", 1)], [], .middleThird),
        ([("A", 0.5), ("B", 0.5)], [], .second),
        ([("A", 0.5), ("B", 0.5)], [], .middle),
        ([("A", 0.5), ("B", 0.5)], [], .third),
        ([("A", 0.5), ("B", 0.5)], ["B"], .middle),
        ([("A", 0.5), ("B", 0.5)], ["A", "B"], .second),
        ([("A", 0.5), ("B", 0.5)], [], .lastThird),
        ([("A", 0.2), ("B", 0.8)], [], .third),
        ([("A", 0.8), ("B", 0.2)], [], .second),
        ([("A", 0.8), ("B", 0.2)], [], .third),
        ([("A", 0.2), ("B", 0.8)], [], .first),
        ([("A", 0.125), ("B", 0.875)], [], .third),
    ] as [([(String, Double)], Set<String>, FourthSlot)])
    func theWindowGetsExactlyItsSpan(children: [(String, Double)], absent: Set<String>, slot: FourthSlot) throws {
        let (start, end) = slot.span
        for axis in [Axis.horizontal, .vertical] {
            let tree = try flat(children, axis, absent: absent)
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

/// The whole tree, nested: "(a:w|b:w)" for columns, "(a:w/b:w)" for rows, "_" an empty area, weights to three places.
private func shape(_ tree: LayoutTree, _ id: NodeID? = nil) -> String {
    guard let id = id ?? tree.root else { return "empty" }
    switch tree.node(id) {
    case let .panel(window)?: return names.first { $0.value == window.windowID }?.key ?? "?"
    case .tabs?: return "tabs"
    case .spacer?: return "_"
    case let .split(axis, children, weights)?:
        let parts = zip(children, weights).map { "\(shape(tree, $0)):\(String(format: "%.3f", $1))" }
        return "(" + parts.joined(separator: axis == .horizontal ? "|" : "/") + ")"
    case nil: return "?"
    }
}

/// The tree with `name` docked to `corner`.
private func cornered(_ tree: LayoutTree, _ corner: DockCorner, _ name: String = "W") throws -> LayoutTree {
    var tree = tree
    var ids = IDSource(next: max(100, (tree.nodes.keys.map(\.raw).max() ?? 0) + 1))
    let w = makeWindow(names[name]!)
    try tree.insertCorner(.panel(w), states: [w.identity: .present], corner: corner, ids: &ids)
    return tree
}

/// Corner quarters (8.1.1 D-17): a row half and a column half at once, exactly that quarter (D-16, E1).
extension FourthTests {
    @Test(arguments: [
        (DockCorner.topLeft, "((W:0.500|_:0.500):0.500/_:0.500)"),
        (.topRight, "((_:0.500|W:0.500):0.500/_:0.500)"),
        (.bottomLeft, "(_:0.500/(W:0.500|_:0.500):0.500)"),
        (.bottomRight, "(_:0.500/(_:0.500|W:0.500):0.500)"),
    ])
    func onAnEmptyDeskACornerTakesOnlyItsQuarter(corner: DockCorner, expected: String) throws {
        #expect(shape(try cornered(LayoutTree(), corner)) == expected)
    }

    /// A docked child spanning exactly the corner's half takes the window inside it; otherwise empty space is used first.
    @Test func aSecondCornerBesideTheFirstUsesItsEmptyHalf() throws {
        let first = try cornered(LayoutTree(), .topLeft)
        #expect(shape(try cornered(first, .topRight, "X")) == "((W:0.500|X:0.500):0.500/_:0.500)")
        #expect(shape(try cornered(first, .bottomLeft, "X")) == "((W:0.500|_:0.500):0.500/(X:0.500|_:0.500):0.500)")
    }

    /// E2 through 08.1.1-21's margin rule: two left corners then Right Half keep both quarters at full size.
    @Test func twoLeftCornersThenRightHalfKeepTheirSize() throws {
        var tree = try cornered(try cornered(LayoutTree(), .topLeft), .bottomLeft, "X")
        var ids = IDSource(next: 500)
        let y = makeWindow(names["Y"]!)
        try tree.insertFourth(.panel(y), states: [y.identity: .present], slot: .secondHalf, axis: .horizontal, ids: &ids)
        #expect(shape(tree) == "((W:0.500/X:0.500):0.500|Y:0.500)")
    }

    /// The root's own axis goes first, and rows for a leaf root (C6, C7); a child spanning exactly the half takes the
    /// window (C7), and with none the others move aside and shrink (E2).
    @Test(arguments: [
        ([("A", 1.0)], Axis.vertical, DockCorner.topLeft, "((W:0.500|_:0.500):0.500/A:0.500)"),
        ([("A", 0.5), ("B", 0.5)], .horizontal, .topLeft, "((W:0.500/A:0.500):0.500|B:0.500)"),
        ([("A", 1.0 / 3), ("B", 2.0 / 3)], .horizontal, .topLeft, "((W:0.500/_:0.500):0.500|A:0.167|B:0.333)"),
        ([("A", 0.5), ("B", 0.5)], .vertical, .bottomRight, "(A:0.500/(B:0.500|W:0.500):0.500)"),
    ])
    func aCornerBesideDockedWindows(children: [(String, Double)], axis: Axis, corner: DockCorner, expected: String) throws {
        #expect(shape(try cornered(try flat(children, axis), corner)) == expected)
    }

    /// E4: a window moved between corners leaves its old quarter empty (the Arranger vacates it first).
    @Test func movingBetweenCornersLeavesTheOldQuarterEmpty() throws {
        let w = makeWindow(names["W"]!)
        var alone = try cornered(LayoutTree(), .topLeft)
        _ = try alone.vacate(try #require(alone.leaf(containing: w)))
        #expect(shape(try cornered(alone, .topRight)) == "((_:0.500|W:0.500):0.500/_:0.500)")

        var pair = try cornered(try cornered(LayoutTree(), .topLeft, "X"), .topRight)
        _ = try pair.vacate(try #require(pair.leaf(containing: w)))
        #expect(shape(try cornered(pair, .bottomLeft)) == "((X:0.500|_:0.500):0.500/(W:0.500|_:0.500):0.500)")
    }

    @Test func aFailedCornerChangesNothing() throws {
        let tree = try cornered(LayoutTree(), .topLeft)
        var copy = tree
        var ids = IDSource(next: 900)
        let w = makeWindow(names["W"]!)
        #expect(throws: LayoutError.self) { try copy.insertCorner(.panel(w), states: [w.identity: .present], corner: .bottomRight, ids: &ids) }
        #expect(copy == tree)
    }
}
