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
private func build(_ shape: Shape, absent: Set<String> = []) throws -> LayoutTree {
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
}
