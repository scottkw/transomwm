import Foundation
import Testing
@testable import TransomModel

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private let names: [String: UInt32] = ["W": 9, "A": 1, "B": 2, "C": 3]

/// A flat tree along `axis` with the named children and stored weights, "D" being the Desktop tile. A single child is a
/// leaf root.
private func flat(_ children: [(String, Double)], _ axis: Axis) throws -> LayoutTree {
    var nodes: [NodeID: Node] = [:]
    var states: [WindowIdentity: WindowState] = [:]
    var ids: [NodeID] = []
    for (i, child) in children.enumerated() {
        let id = child.0 == "D" ? NodeID.desktop : n(UInt64(i + 2))
        if child.0 == "D" {
            nodes[id] = .desktop(hidden: false)
        } else {
            let window = makeWindow(names[child.0]!)
            nodes[id] = .panel(window)
            states[window.identity] = .present
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
}
