import Foundation
import Testing
@testable import TransomModel

/// A tree to build: a named window ("A", "B", "W", …), an empty area, or a split of weighted children.
indirect enum Shape: Sendable {
    case window(String)
    case empty
    case split(Axis, [(Shape, Double)])
}

private func h(_ children: (Shape, Double)...) -> Shape { .split(.horizontal, children) }
private func v(_ children: (Shape, Double)...) -> Shape { .split(.vertical, children) }
private func w(_ name: String) -> Shape { .window(name) }
private let gap = Shape.empty

/// The window named `name`: its ID is the name's first character, so names stay distinct.
private func window(_ name: String) -> WindowRef { makeWindow(UInt32(name.unicodeScalars.first!.value)) }

/// Builds and validates `shape`, NodeIDs from 1 in pre-order. Every window is present unless named in `absent`.
/// `validated: false` skips `validate()`, for shapes only `normalize()` may see.
private func build(_ shape: Shape, absent: Set<String> = [], validated: Bool = true) throws -> LayoutTree {
    var nodes: [NodeID: Node] = [:]
    var states: [WindowIdentity: WindowState] = [:]
    var next: UInt64 = 1
    func add(_ shape: Shape) -> NodeID {
        let id = NodeID(raw: next)
        next += 1
        switch shape {
        case let .window(name):
            nodes[id] = .panel(window(name))
            states[window(name).identity] = absent.contains(name) ? .absent : .present
        case .empty:
            nodes[id] = .spacer
        case let .split(axis, children):
            nodes[id] = .split(axis: axis, children: [], weights: [])
            let ids = children.map { add($0.0) }
            nodes[id] = .split(axis: axis, children: ids, weights: children.map(\.1))
        }
        return id
    }
    let root = add(shape)
    guard validated else {
        var tree = LayoutTree()
        (tree.root, tree.nodes, tree.states) = (root, nodes, states)
        return tree
    }
    return try LayoutTree(root: root, nodes: nodes, states: states)
}

/// The tree written back: `H[A 0.5, _ 0.5]`, `_` an empty area, `T` a tab group, `-` an empty tree.
private func describe(_ tree: LayoutTree) -> String {
    func text(_ id: NodeID) -> String {
        switch tree.node(id) {
        case let .panel(window)?: String(UnicodeScalar(window.windowID).map(Character.init) ?? "?")
        case .tabs?: "T"
        case .spacer?: "_"
        case let .split(axis, children, weights)?:
            (axis == .horizontal ? "H[" : "V[")
                + zip(children, weights).map { "\(text($0)) \(($1 * 1000).rounded() / 1000)" }.joined(separator: ", ") + "]"
        case nil: "?"
        }
    }
    return tree.root.map(text) ?? "-"
}

private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)

/// 8.1.1 D-16, rules E4–E7: the empty-area leaf (`Node.spacer`) in resolve, validate, normalise and the edits.
@Suite struct EmptyAreaTests {
    // MARK: Resolve

    @Test func aSavedEmptyAreaKeepsTheDockedWindowToItsHalf() throws {
        let empty = try build(h((w("W"), 0.5), (gap, 0.5)))
        let pair = try build(h((w("W"), 0.5), (w("X"), 0.5)))
        let withEmpty = try resolve(empty, in: visible, mins: [:], gap: 8)
        let withPair = try resolve(pair, in: visible, mins: [:], gap: 8)
        #expect(withEmpty.windowRects[window("W")] == withPair.windowRects[window("W")])
        let spacer = NodeID(raw: 3)
        #expect(empty.node(spacer) == .spacer)
        #expect(withEmpty.nodeRects[spacer] == withPair.windowRects[window("X")])
        #expect(withEmpty.windowRects.count == 1)
        #expect(withEmpty.unfit.isEmpty)
    }

    /// The empty area needs no room, so water-filling gives the window its minimum.
    @Test func anEmptyAreaNeverMakesAWindowUnfit() throws {
        let tree = try build(h((w("W"), 0.5), (gap, 0.5)))
        let result = try resolve(tree, in: Rect(x: 0, y: 0, width: 1440, height: 900), mins: [window("W"): Size(width: 1000, height: 100)], gap: 8)
        #expect(result.unfit.isEmpty)
        #expect(result.windowRects[window("W")]?.width == 1000)
    }

    /// E7: a minimised window's siblings, empty areas included, share its space; nothing is drawn.
    @Test func anEmptyAreaBesideAnAbsentWindowTakesTheWholeArea() throws {
        let tree = try build(h((w("W"), 0.5), (gap, 0.5)), absent: ["W"])
        let result = try resolve(tree, in: Rect(x: 0, y: 0, width: 1000, height: 500), mins: [:], gap: 8)
        #expect(result.windowRects.isEmpty)
        #expect(result.unfit.isEmpty)
        #expect(result.nodeRects[NodeID(raw: 3)] == Rect(x: 8, y: 8, width: 984, height: 484))
        #expect(result.nodeRects[NodeID(raw: 2)] == nil)
    }

    // MARK: Validate

    static let badShapes: [(String, Shape)] = [
        ("an empty root", gap),
        ("two adjacent empty areas", h((w("A"), 0.5), (gap, 0.25), (gap, 0.25))),
        ("a split with no window", h((w("A"), 0.5), (v((gap, 0.5), (h((gap, 0.5), (gap, 0.5)), 0.5)), 0.5))),
    ]

    @Test(arguments: badShapes)
    func aBadEmptyAreaShapeIsRejected(name: String, shape: Shape) {
        do {
            _ = try build(shape)
            Issue.record("\(name) was accepted")
        } catch LayoutError.invariantViolated {
        } catch {
            Issue.record("\(name) threw \(error), not invariantViolated")
        }
    }

    @Test func emptyAreasBetweenAndAroundWindowsAreValid() throws {
        _ = try build(h((gap, 0.25), (w("A"), 0.5), (gap, 0.25)))
        _ = try build(h((gap, 0.5), (v((gap, 0.5), (h((w("A"), 0.5), (gap, 0.5)), 0.5)), 0.5)))
    }

    @Test func emptyAreasHoldNoWindow() throws {
        let tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        #expect(tree.windows == [window("A")])
        #expect(tree.leaf(containing: window("A")) == NodeID(raw: 2))
        #expect(describe(tree) == "H[A 0.5, _ 0.5]")
    }

    @Test func anEmptyAreaRoundTripsThroughJSON() throws {
        let tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        let data = try JSONEncoder().encode(tree)
        #expect(String(decoding: data, as: UTF8.self).contains("\"spacer\""))
        #expect(try JSONDecoder().decode(LayoutTree.self, from: data) == tree)
    }

    // MARK: Normalise

    @Test(arguments: [
        (h((w("A"), 0.5), (gap, 0.25), (gap, 0.25)), "H[A 0.5, _ 0.5]"),
        (h((w("A"), 0.5), (gap, 0.25), (v((gap, 0.5), (gap, 0.5)), 0.25)), "H[A 0.5, _ 0.5]"),
        (h((gap, 0.5), (w("A"), 0.25), (v((gap, 0.5), (h((gap, 0.5), (gap, 0.5)), 0.5)), 0.25)), "H[_ 0.5, A 0.25, _ 0.25]"),
        (h((gap, 0.5), (gap, 0.5)), "-"),
        (v((gap, 0.5), (h((gap, 0.5), (gap, 0.5)), 0.5)), "-"),
    ] as [(Shape, String)])
    func normalisingMergesEmptyAreas(shape: Shape, expected: String) throws {
        var tree = try build(shape, validated: false)
        tree.normalize()
        #expect(describe(tree) == expected)
        try tree.validate()
        if expected == "-" { #expect(tree.nodes.isEmpty && tree.states.isEmpty) }
    }

    // MARK: Leaving, rule E5

    @Test(arguments: [
        (h((w("W"), 0.5), (gap, 0.5)), "W", "-"),
        (h((w("A"), 0.5), (gap, 0.25), (w("W"), 0.25)), "W", "H[A 0.5, _ 0.5]"),
        (h((gap, 0.25), (w("W"), 0.5), (gap, 0.25)), "W", "-"),
        (h((w("A"), 0.5), (w("B"), 0.5)), "B", "A"),
        (h((w("A"), 0.5), (w("W"), 0.25), (gap, 0.25)), "A", "H[W 0.5, _ 0.5]"),
        (h((w("A"), 0.25), (w("W"), 0.25), (gap, 0.5)), "W", "H[A 0.25, _ 0.75]"),
        (v((h((w("X"), 0.5), (gap, 0.5)), 0.5), (h((w("Y"), 0.5), (gap, 0.5)), 0.5)), "X", "V[_ 0.5, H[Y 0.5, _ 0.5] 0.5]"),
    ] as [(Shape, String, String)])
    func aLeavingWindowGivesItsSpaceToAnEmptyAreaBesideIt(shape: Shape, leaving: String, expected: String) throws {
        var tree = try build(shape)
        try tree.remove(window(leaving))
        #expect(describe(tree) == expected)
        #expect(tree.state(of: window(leaving)) == nil)
        try tree.validate()
    }

    // MARK: Vacate, rule E4

    @Test func vacatingALeafLeavesAnEmptyAreaInItsPlace() throws {
        var tree = try build(h((w("A"), 0.5), (w("W"), 0.5)))
        let taken = try tree.vacate(NodeID(raw: 3))
        #expect(describe(tree) == "H[A 0.5, _ 0.5]")
        #expect(tree.node(NodeID(raw: 3)) == .spacer)
        #expect(taken.node == .panel(window("W")))
        #expect(taken.states == [window("W").identity: .present])
        #expect(tree.state(of: window("W")) == nil)

        var alone = try build(w("W"))
        _ = try alone.vacate(NodeID(raw: 1))
        #expect(alone == LayoutTree())
    }

    @Test func aTabGroupVacatesWhole() throws {
        var tree = try build(h((w("A"), 0.5), (w("W"), 0.5)))
        try tree.group(window("B"), into: NodeID(raw: 3))
        let taken = try tree.vacate(NodeID(raw: 3))
        #expect(describe(tree) == "H[A 0.5, _ 0.5]")
        #expect(taken.node == .tabs(windows: [window("W"), window("B")], selected: 1))
        #expect(Set(taken.states.keys) == [window("W").identity, window("B").identity])
    }

    @Test func onlyAWindowLeafVacates() throws {
        let tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        for id in [NodeID(raw: 1), NodeID(raw: 3)] {
            var copy = tree
            #expect(throws: LayoutError.notALeaf(id)) { try copy.vacate(id) }
            #expect(copy == tree)
        }
    }

    // MARK: Fill, rule E6

    @Test func fillingAnEmptyAreaPutsTheWindowInItsPlace() throws {
        var tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        try tree.fill(NodeID(raw: 3), with: .panel(window("W")), states: [window("W").identity: .present])
        #expect(describe(tree) == "H[A 0.5, W 0.5]")
        #expect(tree.state(of: window("W")) == .present)
    }

    @Test func fillingWithATabGroupKeepsItsMembersAndSelection() throws {
        var tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        let group = Node.tabs(windows: [window("W"), window("B")], selected: 0)
        try tree.fill(NodeID(raw: 3), with: group, states: [window("W").identity: .present, window("B").identity: .absent])
        #expect(tree.node(NodeID(raw: 3)) == group)
        #expect(tree.state(of: window("B")) == .absent)
    }

    @Test func onlyAnEmptyAreaFillsAndAFailedFillChangesNothing() throws {
        let tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        var copy = tree
        #expect(throws: LayoutError.notALeaf(NodeID(raw: 2))) {
            try copy.fill(NodeID(raw: 2), with: .panel(window("W")), states: [window("W").identity: .present])
        }
        #expect(throws: LayoutError.duplicateWindow(window("A"))) {
            try copy.fill(NodeID(raw: 3), with: .panel(window("A")), states: [window("A").identity: .present])
        }
        #expect(copy == tree)
    }

    // MARK: Other edits, rule E7

    @Test func anEmptyAreaIsNoGroupTarget() throws {
        let tree = try build(h((w("A"), 0.5), (gap, 0.5)))
        var copy = tree
        #expect(throws: LayoutError.notALeaf(NodeID(raw: 3))) { try copy.group(window("W"), into: NodeID(raw: 3)) }
        #expect(copy == tree)
    }

    @Test func insertingAtAnEmptyAreasEdgeFollowsTheUsualRules() throws {
        var beside = try build(h((w("A"), 0.5), (gap, 0.5)))
        var ids = IDSource(next: 10)
        try beside.insert(window("W"), at: .right, of: NodeID(raw: 3), ids: &ids)
        #expect(describe(beside) == "H[A 0.333, _ 0.333, W 0.333]")

        var below = try build(h((w("A"), 0.5), (gap, 0.5)))
        try below.insert(window("W"), at: .bottom, of: NodeID(raw: 3), ids: &ids)
        #expect(describe(below) == "H[A 0.5, V[_ 0.5, W 0.5] 0.5]")
    }
}
