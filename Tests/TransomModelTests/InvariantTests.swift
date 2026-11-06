import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private let b = makeWindow(2)
private let c = makeWindow(3)

private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }

private func present(_ windows: WindowRef...) -> [WindowIdentity: WindowState] {
    Dictionary(uniqueKeysWithValues: windows.map { ($0.identity, .present) })
}

private func h(_ children: UInt64..., weights: [Double]? = nil) -> Node {
    .split(axis: .horizontal, children: children.map(n), weights: weights ?? children.map { _ in 1 / Double(children.count) })
}

/// `splits` nested splits with alternating axes (n1 horizontal). Each holds a panel and the next
/// split; the last holds two panels, at depth `splits` (the root is depth 0).
func chain(splits: Int) -> (root: NodeID, nodes: [NodeID: Node], states: [WindowIdentity: WindowState], deepest: NodeID, deepestAxis: Axis) {
    var nodes: [NodeID: Node] = [:]
    var states: [WindowIdentity: WindowState] = [:]
    func panel(_ raw: UInt64) -> NodeID {
        let window = makeWindow(UInt32(raw))
        nodes[n(raw)] = .panel(window)
        states[window.identity] = .present
        return n(raw)
    }
    let axis = { (i: Int) -> Axis in i % 2 == 1 ? .horizontal : .vertical }
    for i in 1...splits {
        let second = i == splits ? panel(2000) : n(UInt64(i + 1))
        nodes[n(UInt64(i))] = .split(axis: axis(i), children: [panel(UInt64(1000 + i)), second], weights: [0.5, 0.5])
    }
    return (n(1), nodes, states, n(2000), axis(splits))
}

private let malformedSplits: [(children: [UInt64], weights: [Double])] = [
    ([2], [1.0]),  // one child
    ([2, 3], [1.0]),  // weights count mismatch
    ([2, 3], [0.5, 0.4]),  // sums to 0.9
    ([2, 3], [0.005, 0.995]),  // below minWeight
    ([2, 3], [Double.nan, 1]),  // non-finite
    ([2, 3], [Double.infinity, -Double.infinity]),  // non-finite
]

private let malformedTabs: [(windows: [WindowRef], selected: Int)] = [([a], 0), ([a, b], -1), ([a, b], 2)]

@Suite struct InvariantTests {
    @Test func rejectsChildListedTwiceAndSplitContainingItself() {
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: n(1), nodes: [n(1): h(2, 2), n(2): .panel(a)], states: present(a))
        }
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: n(1), nodes: [n(1): h(1, 2), n(2): .panel(a)], states: present(a))
        }
    }

    @Test func rejectsDanglingChildOrphanAndNilRootWithNodes() {
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: n(1), nodes: [n(1): h(2, 3), n(2): .panel(a)], states: present(a))
        }
        #expect(throws: LayoutError.self) {
            try LayoutTree(
                root: n(1), nodes: [n(1): h(2, 3), n(2): .panel(a), n(3): .panel(b), n(4): .panel(c)],
                states: present(a, b, c))
        }
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: nil, nodes: [n(1): .panel(a)], states: present(a))
        }
    }

    @Test(arguments: malformedSplits)
    func rejectsMalformedSplit(children: [UInt64], weights: [Double]) {
        var nodes: [NodeID: Node] = [n(1): .split(axis: .horizontal, children: children.map(n), weights: weights)]
        var states: [WindowIdentity: WindowState] = [:]
        for raw in children {
            let window = makeWindow(UInt32(raw))
            nodes[n(raw)] = .panel(window)
            states[window.identity] = .present
        }
        #expect(throws: LayoutError.self) { try LayoutTree(root: n(1), nodes: nodes, states: states) }
    }

    @Test func rejectsChildSplitWithParentsAxis() {
        #expect(throws: LayoutError.self) {
            try LayoutTree(
                root: n(1), nodes: [n(1): h(2, 3), n(2): .panel(a), n(3): h(4, 5), n(4): .panel(b), n(5): .panel(c)],
                states: present(a, b, c))
        }
    }

    @Test(arguments: malformedTabs)
    func rejectsMalformedTabs(windows: [WindowRef], selected: Int) {
        let states = Dictionary(uniqueKeysWithValues: windows.map { ($0.identity, WindowState.present) })
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: n(1), nodes: [n(1): .tabs(windows: windows, selected: selected)], states: states)
        }
    }

    @Test func rejectsWindowInTwoLeavesOrTwiceInOneTabGroup() {
        #expect(throws: LayoutError.duplicateWindow(a)) {
            try LayoutTree(root: n(1), nodes: [n(1): h(2, 3), n(2): .panel(a), n(3): .panel(a)], states: present(a))
        }
        #expect(throws: LayoutError.duplicateWindow(a)) {
            try LayoutTree(root: n(1), nodes: [n(1): .tabs(windows: [a, b, a], selected: 0)], states: present(a, b))
        }
    }

    @Test func rejectsStatesThatDoNotMatchTheWindowsOrAreClosed() {
        let nodes: [NodeID: Node] = [n(1): h(2, 3), n(2): .panel(a), n(3): .panel(b)]
        #expect(throws: LayoutError.self) { try LayoutTree(root: n(1), nodes: nodes, states: present(a)) }
        #expect(throws: LayoutError.self) { try LayoutTree(root: n(1), nodes: nodes, states: present(a, b, c)) }
        #expect(throws: LayoutError.self) {
            try LayoutTree(root: n(1), nodes: nodes, states: [a.identity: .present, b.identity: .closed])
        }
    }

    @Test func rejectsChainDeeperThanLimit() throws {
        let ok = chain(splits: 64)
        _ = try LayoutTree(root: ok.root, nodes: ok.nodes, states: ok.states)

        let deep = chain(splits: 65)
        #expect(throws: LayoutError.tooDeep(limit: 64)) {
            try LayoutTree(root: deep.root, nodes: deep.nodes, states: deep.states)
        }
    }

    @Test func rejectsMoreThanMaxNodes() {
        var nodes: [NodeID: Node] = [:]
        var states: [WindowIdentity: WindowState] = [:]
        for raw in 1...UInt64(LayoutTree.maxNodes + 1) {
            let window = makeWindow(UInt32(raw))
            nodes[n(raw)] = .panel(window)
            states[window.identity] = .present
        }
        #expect(throws: LayoutError.tooManyNodes(limit: 4096)) {
            try LayoutTree(root: n(1), nodes: nodes, states: states)
        }
    }

    @Test func acceptsValidTreeWithTabsAndKeptSlotStates() throws {
        let tree = try LayoutTree(
            root: n(1),
            nodes: [n(1): h(2, 3, weights: [0.3, 0.7]), n(2): .panel(a), n(3): .tabs(windows: [b, c], selected: 1)],
            states: [a.identity: .absent, b.identity: .fullscreen, c.identity: .present])
        #expect(tree.windows == [a, b, c])
        #expect(tree.state(of: a) == .absent)
    }

    @Test func insertBeyondDepthLimitThrowsAndLeavesTreeUnchanged() throws {
        let deep = chain(splits: 64)
        var tree = try LayoutTree(root: deep.root, nodes: deep.nodes, states: deep.states)
        let before = tree
        var ids = IDSource(next: 3000)
        let across: Edge = deep.deepestAxis == .horizontal ? .bottom : .right
        #expect(throws: LayoutError.tooDeep(limit: 64)) {
            try tree.insert(makeWindow(5000), at: across, of: deep.deepest, ids: &ids)
        }
        #expect(tree == before)
        #expect(ids == IDSource(next: 3000))

        // Along the same axis the window becomes a sibling at the same depth, which fits.
        let along: Edge = deep.deepestAxis == .horizontal ? .right : .bottom
        try tree.insert(makeWindow(5000), at: along, of: deep.deepest, ids: &ids)
    }

    @Test func layoutEdgeDropThatWrapsAFullDepthRootThrowsAndLeavesTreeUnchanged() throws {
        // The root is horizontal, so a top drop wraps the whole tree in a new vertical split.
        let deep = chain(splits: 64)
        var tree = try LayoutTree(root: deep.root, nodes: deep.nodes, states: deep.states)
        let before = tree
        var ids = IDSource(next: 3000)
        #expect(throws: LayoutError.tooDeep(limit: 64)) {
            try tree.applyDrop(.layoutEdge(.top), window: makeWindow(5000), ids: &ids)
        }
        #expect(tree == before)
        #expect(ids == IDSource(next: 3000))
    }

    @Test func insertBeyondNodeLimitThrowsAndLeavesTreeUnchanged() throws {
        // Root H holding 40 V splits of 100 panels each plus 54 panels: 1 + 40 + 4000 + 54 = 4095 nodes.
        var nodes: [NodeID: Node] = [:]
        var states: [WindowIdentity: WindowState] = [:]
        var next: UInt64 = 2
        func panel() -> NodeID {
            let id = n(next)
            next += 1
            let window = makeWindow(UInt32(id.raw))
            nodes[id] = .panel(window)
            states[window.identity] = .present
            return id
        }
        var rootChildren: [NodeID] = []
        for _ in 0..<40 {
            let split = n(next)
            next += 1
            let children = (0..<100).map { _ in panel() }
            nodes[split] = .split(axis: .vertical, children: children, weights: Array(repeating: 0.01, count: 100))
            rootChildren.append(split)
        }
        rootChildren += (0..<54).map { _ in panel() }
        nodes[n(1)] = .split(axis: .horizontal, children: rootChildren, weights: rootChildren.map { _ in 1.0 / 94 })
        var tree = try LayoutTree(root: n(1), nodes: nodes, states: states)
        #expect(tree.nodes.count == 4095)

        let before = tree
        var ids = IDSource(next: next)
        let target = n(3)  // a panel inside the first V split; docking across it adds a split and a panel
        #expect(throws: LayoutError.tooManyNodes(limit: 4096)) {
            try tree.insert(makeWindow(9000), at: .left, of: target, ids: &ids)
        }
        #expect(tree == before)
        #expect(ids == IDSource(next: next))
    }

    @Test func anExhaustedIDSourceThrowsInsteadOfTrapping() throws {
        var ids = IDSource(next: .max)
        #expect(throws: LayoutError.self) { try ids.make() }
        #expect(ids == IDSource(next: .max))

        var tree = LayoutTree()
        #expect(throws: LayoutError.self) { try tree.insertRoot(a, ids: &ids) }
        #expect(tree == LayoutTree())

        var almost = IDSource(next: .max - 1)
        try tree.insertRoot(a, ids: &almost)
        let before = tree
        #expect(throws: LayoutError.self) { try tree.insert(b, at: .right, of: n(.max - 1), ids: &almost) }
        #expect(tree == before)
        #expect(almost == IDSource(next: .max))
    }

    @Test func decodingInvalidTreeThrowsDecodingErrorWrappingLayoutError() {
        let json = """
            {"nodes":{"1":{"split":{"axis":"horizontal","children":[1,2],"weights":[0.5,0.5]}},
            "2":{"panel":{"_0":{"creationOrder":0,"identity":{"bundleID":"x","pid":9,"windowID":1},"titleHint":""}}}},
            "root":1,"states":[{"state":"present","window":{"bundleID":"x","pid":9,"windowID":1}}]}
            """
        do {
            _ = try JSONDecoder().decode(LayoutTree.self, from: Data(json.utf8))
            Issue.record("decoding a cyclic tree succeeded")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.underlyingError is LayoutError)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
