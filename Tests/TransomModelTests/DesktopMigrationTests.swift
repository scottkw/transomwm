import Foundation
import Testing
@testable import TransomModel

// Hand-built World schema 1 JSON, in the shape PersistenceTests' helpers write (theirs are private).

private func identityJSON(_ id: Int) -> String {
    #"{"bundleID":"com.example.app","pid":100,"windowID":\#(id)}"#
}

private func panelJSON(_ id: Int) -> String {
    #"{"panel":{"_0":{"creationOrder":0,"identity":\#(identityJSON(id)),"titleHint":""}}}"#
}

private func splitJSON(_ children: [Int], _ weights: [Double], axis: String = "horizontal") -> String {
    #"{"split":{"axis":"\#(axis)","children":\#(children),"weights":\#(weights)}}"#
}

private func desktopJSON(hidden: Bool = false) -> String { #"{"desktop":{"hidden":\#(hidden)}}"# }

/// One desk "D1"; `nodes` maps NodeID to node JSON, `windows` get a `present` state.
private func legacyWorld(root: Int?, nodes: [Int: String], windows: [Int], version: Int = 1, stateJSON: String? = nil) -> Data {
    let nodeList = nodes.sorted { $0.key < $1.key }.map { #""\#($0.key)":\#($0.value)"# }.joined(separator: ",")
    let states = stateJSON ?? windows.sorted().map { #"{"state":"present","window":\#(identityJSON($0))}"# }.joined(separator: ",")
    let rootPart = root.map { #","root":\#($0)"# } ?? ""
    let desk = #"{"desk":{"desktop":{"windows":[]},"tree":{"nodes":{\#(nodeList)}\#(rootPart),"states":[\#(states)]}},"key":{"displayUUID":"D1"}}"#
    return Data(#"{"desks":[\#(desk)],"ids":{"next":100},"schemaVersion":\#(version)}"#.utf8)
}

private let key = DeskKey(displayUUID: "D1", spaceID: nil)

private func window(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 100, bundleID: "com.example.app"))
}

private func tree(_ data: Data) throws -> LayoutTree {
    try #require(try World.decode(from: data)[key]?.tree)
}

private func expectInvalidLayout(_ data: Data, _ name: String) {
    do {
        _ = try World.decode(from: data)
        Issue.record("\(name) decoded without error")
    } catch {
        guard case .invalidLayout = error else { Issue.record("\(name) threw \(error), not invalidLayout"); return }
    }
}

/// 8.1.1 D-02: a World schema 1 (layout.json schema 3 and older) loses its Desktop tile on decode. The tile's share goes
/// back to its siblings by weight, a split left with one child collapses, and a hostile file is rejected, never repaired.
@Suite struct DesktopMigrationTests {
    @Test func theDesktopShareGoesBackToItsSiblingsByWeight() throws {
        let t = try tree(legacyWorld(root: 3, nodes: [
            1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2, 0], [0.25, 0.25, 0.5]), 0: desktopJSON(hidden: true),
        ], windows: [1, 2]))
        #expect(t.root == NodeID(raw: 3))
        #expect(t.node(NodeID(raw: 3)) == .split(axis: .horizontal, children: [NodeID(raw: 1), NodeID(raw: 2)], weights: [0.5, 0.5]))
        #expect(t.nodes[.desktop] == nil)
        #expect(t.states == [window(1).identity: .present, window(2).identity: .present])
    }

    @Test func aPanelBesideTheDesktopBecomesTheRoot() throws {
        let t = try tree(legacyWorld(root: 3, nodes: [1: panelJSON(1), 3: splitJSON([1, 0], [0.5, 0.5]), 0: desktopJSON()], windows: [1]))
        #expect(t.root == NodeID(raw: 1))
        #expect(t.nodes == [NodeID(raw: 1): .panel(window(1))])
    }

    @Test func aDeskHoldingOnlyTheDesktopBecomesEmpty() throws {
        let t = try tree(legacyWorld(root: 0, nodes: [0: desktopJSON()], windows: []))
        #expect(t.root == nil)
        #expect(t.nodes.isEmpty)
        #expect(t.states.isEmpty)
    }

    @Test func aOneChildSplitCollapses() throws {
        // V[H[A, Desktop], B] → V[A, B].
        let t = try tree(legacyWorld(root: 4, nodes: [
            1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 0], [0.5, 0.5]), 4: splitJSON([3, 2], [0.5, 0.5], axis: "vertical"),
            0: desktopJSON(),
        ], windows: [1, 2]))
        #expect(t.root == NodeID(raw: 4))
        #expect(t.node(NodeID(raw: 4)) == .split(axis: .vertical, children: [NodeID(raw: 1), NodeID(raw: 2)], weights: [0.5, 0.5]))
        #expect(t.nodes.count == 3)
    }

    @Test func aCollapseLeavesNoSameAxisNesting() throws {
        // H[A, V[B, Desktop]] → H[A, B].
        let t = try tree(legacyWorld(root: 4, nodes: [
            1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([2, 0], [0.5, 0.5], axis: "vertical"), 4: splitJSON([1, 3], [0.5, 0.5]),
            0: desktopJSON(),
        ], windows: [1, 2]))
        #expect(t.node(NodeID(raw: 4)) == .split(axis: .horizontal, children: [NodeID(raw: 1), NodeID(raw: 2)], weights: [0.5, 0.5]))
    }

    @Test func aCollapsedSplitMergesIntoItsSameAxisGrandparent() throws {
        // H[A, V[H[B, C], Desktop]] → H[A, B, C].
        let t = try tree(legacyWorld(root: 12, nodes: [
            1: panelJSON(1), 2: panelJSON(2), 3: panelJSON(3),
            10: splitJSON([2, 3], [0.5, 0.5]), 11: splitJSON([10, 0], [0.5, 0.5], axis: "vertical"), 12: splitJSON([1, 11], [0.5, 0.5]),
            0: desktopJSON(),
        ], windows: [1, 2, 3]))
        let root = try #require(t.root)
        guard case let .split(axis, children, weights)? = t.node(root) else { Issue.record("root is not a split"); return }
        #expect(axis == .horizontal)
        #expect(children == [NodeID(raw: 1), NodeID(raw: 2), NodeID(raw: 3)])
        #expect(weights == [0.5, 0.25, 0.25])
        #expect(abs(weights.reduce(0, +) - 1) < 1e-12)
        #expect(t.nodes.count == 4)
    }

    @Test func aHiddenAndAVisibleDesktopGiveTheSameTree() throws {
        let nodes = [1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2, 0], [0.25, 0.25, 0.5])]
        let visible = try tree(legacyWorld(root: 3, nodes: nodes.merging([0: desktopJSON(hidden: false)]) { $1 }, windows: [1, 2]))
        let hidden = try tree(legacyWorld(root: 3, nodes: nodes.merging([0: desktopJSON(hidden: true)]) { $1 }, windows: [1, 2]))
        #expect(visible == hidden)
    }

    @Test func floatingWindowsAndGroupsKeepFramesMembersAndSelection() throws {
        var world = World()
        try world.addDesk(key)
        var history = UndoHistory()
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            try desk.tree.insert(window(1), at: .left, of: .desktop, ids: &ids)
            try desk.desktop.add(window(4), frame: Rect(x: 900, y: 300, width: 400, height: 300))
            try desk.desktop.add(window(5), frame: Rect(x: 950, y: 350, width: 300, height: 200))
            try desk.desktop.add(window(6), frame: Rect(x: -1440, y: -0.5, width: 800.25, height: 600))
            try desk.desktop.group(id: try ids.make(), target: window(4), adding: window(5))
            try desk.desktop.selectTab(window(4))
        }
        let legacy = String(decoding: try world.encoded(), as: UTF8.self)
            .replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":1"#)
        let desk = try #require(try World.decode(from: Data(legacy.utf8))[key])
        let before = try #require(world[key])
        #expect(desk.desktop == before.desktop)
        #expect(desk.tree.nodes[.desktop] == nil)
        #expect(desk.tree.windows == [window(1)])
    }

    @Test func aDeskWithoutADesktopTileLoadsUnchanged() throws {
        let t = try tree(legacyWorld(root: 3, nodes: [1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2], [0.3, 0.7])], windows: [1, 2]))
        #expect(t.node(NodeID(raw: 3)) == .split(axis: .horizontal, children: [NodeID(raw: 1), NodeID(raw: 2)], weights: [0.3, 0.7]))
    }

    nonisolated static let hostile: [(String, Data)] = [
        ("Desktop under NodeID 7", legacyWorld(root: 3, nodes: [1: panelJSON(1), 7: desktopJSON(), 3: splitJSON([1, 7], [0.5, 0.5])], windows: [1])),
        ("Desktop at NodeIDs 0 and 7", legacyWorld(root: 3, nodes: [
            1: panelJSON(1), 0: desktopJSON(), 7: desktopJSON(), 3: splitJSON([1, 7, 0], [0.5, 0.25, 0.25]),
        ], windows: [1])),
        ("cycle through the Desktop's split", legacyWorld(root: 1, nodes: [
            1: splitJSON([2, 3, 0], [0.25, 0.25, 0.5]), 2: splitJSON([1, 4], [0.5, 0.5], axis: "vertical"), 3: panelJSON(3), 4: panelJSON(4),
            0: desktopJSON(),
        ], windows: [3, 4])),
        ("single-child split elsewhere", legacyWorld(root: 4, nodes: [
            1: panelJSON(1), 3: splitJSON([1], [1.0]), 4: splitJSON([3, 0], [0.5, 0.5], axis: "vertical"), 0: desktopJSON(),
        ], windows: [1])),
        ("weights sum to 0.9", legacyWorld(root: 3, nodes: [
            1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2, 0], [0.4, 0.3, 0.2]), 0: desktopJSON(),
        ], windows: [1, 2])),
        ("the Desktop stand-in's identity", legacyWorld(
            root: 3,
            nodes: [
                1: #"{"panel":{"_0":{"creationOrder":0,"identity":{"bundleID":"","pid":-1,"windowID":0},"titleHint":""}}}"#,
                3: splitJSON([1, 0], [0.5, 0.5]), 0: desktopJSON(),
            ],
            windows: [], stateJSON: #"{"state":"present","window":{"bundleID":"","pid":-1,"windowID":0}}"#)),
    ]

    @Test(arguments: hostile)
    func aHostileLegacyFileIsRejected(name: String, data: Data) {
        expectInvalidLayout(data, name)
    }

    @Test func schema2DecodesStrictlyWithoutTheLegacyPath() throws {
        // Node still has the Desktop case until 08.1.1-16; schema 2 keeps what it holds rather than migrating it.
        let t = try tree(legacyWorld(root: 3, nodes: [1: panelJSON(1), 3: splitJSON([1, 0], [0.5, 0.5]), 0: desktopJSON()], windows: [1], version: 2))
        #expect(t.isDesktopHidden == false)
    }

    @Test func schema3IsNewer() {
        do {
            _ = try World.decode(from: legacyWorld(root: nil, nodes: [:], windows: [], version: 3))
            Issue.record("schema 3 decoded")
        } catch {
            #expect(error == .newerVersion(found: 3, supported: 2))
        }
    }

    @Test func schema0ChainsToTheLegacyPath() throws {
        let data = legacyWorld(root: 3, nodes: [1: panelJSON(1), 3: splitJSON([1, 0], [0.5, 0.5]), 0: desktopJSON(hidden: true)], windows: [1], version: 0)
        let world = try World.decode(from: data, migrations: MigrationChain(steps: [0: { _ in }]))
        #expect(world[key]?.tree.nodes == [NodeID(raw: 1): .panel(window(1))])
    }
}
