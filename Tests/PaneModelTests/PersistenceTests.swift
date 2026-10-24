import Foundation
import Testing
@testable import PaneModel

// MARK: Hand-built JSON fixtures, in the exact shape World.encoded() writes

private func identityJSON(_ id: Int) -> String {
    #"{"bundleID":"com.example.app","pid":100,"windowID":\#(id)}"#
}

private func windowJSON(_ id: Int) -> String {
    #"{"creationOrder":0,"identity":\#(identityJSON(id)),"titleHint":""}"#
}

private func panelJSON(_ id: Int) -> String { #"{"panel":{"_0":\#(windowJSON(id))}}"# }

private func splitJSON(_ children: [Int], _ weights: [Double], axis: String = "horizontal") -> String {
    #"{"split":{"axis":"\#(axis)","children":\#(children),"weights":\#(weights)}}"#
}

/// `nodes` maps NodeID to node JSON; `windows` are the window IDs that get a `present` state.
private func deskJSON(
    key: String = "D1", root: Int?, nodes: [Int: String], windows: [Int], floating: [String] = []
) -> String {
    let nodeList = nodes.sorted { $0.key < $1.key }.map { #""\#($0.key)":\#($0.value)"# }.joined(separator: ",")
    let states = windows.sorted().map { #"{"state":"present","window":\#(identityJSON($0))}"# }.joined(separator: ",")
    let rootPart = root.map { #","root":\#($0)"# } ?? ""
    return #"{"desk":{"desktop":{"windows":[\#(floating.joined(separator: ","))]},"tree":{"nodes":{\#(nodeList)}\#(rootPart),"states":[\#(states)]}},"key":{"displayUUID":"\#(key)"}}"#
}

private func worldJSON(_ desks: [String], next: UInt64 = 100_000) -> Data {
    Data(#"{"desks":[\#(desks.joined(separator: ","))],"ids":{"next":\#(next)},"schemaVersion":1}"#.utf8)
}

private func floatingJSON(_ id: Int, x: String = "0", width: String = "100") -> String {
    #"{"frame":{"height":100,"width":\#(width),"x":\#(x),"y":0},"state":"present","window":\#(windowJSON(id))}"#
}

/// H[1: w1, 2: w2] under split 3: the valid baseline every structural corpus item is one change away from.
private let validPair = deskJSON(root: 3, nodes: [1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2], [0.5, 0.5])], windows: [1, 2])

/// `splits` nested splits with alternating axes, each holding a panel and the next split.
private func chainDesk(splits: Int) -> String {
    var nodes: [Int: String] = [:]
    var windows: [Int] = []
    for i in 1...splits {
        let second = i == splits ? 2000 : i + 1
        nodes[1000 + i] = panelJSON(1000 + i)
        windows.append(1000 + i)
        nodes[i] = splitJSON([1000 + i, second], [0.5, 0.5], axis: i % 2 == 1 ? "horizontal" : "vertical")
    }
    nodes[2000] = panelJSON(2000)
    windows.append(2000)
    return deskJSON(root: 1, nodes: nodes, windows: windows)
}

private func manyNodesDesk(_ count: Int) -> String {
    var nodes: [Int: String] = [:]
    for i in 1...count { nodes[i] = panelJSON(i) }
    return deskJSON(root: 1, nodes: nodes, windows: Array(1...count))
}

struct CorruptCase: Sendable, CustomTestStringConvertible {
    let name: String
    let data: Data
    /// True for files that parse but describe an invalid layout; false for files that do not parse.
    let invalidLayout: Bool
    var testDescription: String { name }
}

private let corruptCorpus: [CorruptCase] = [
    CorruptCase(name: "empty data", data: Data(), invalidLayout: false),
    CorruptCase(name: "truncated JSON", data: worldJSON([validPair]).prefix(120), invalidLayout: false),
    CorruptCase(name: "JSON array", data: Data("[]".utf8), invalidLayout: false),
    CorruptCase(name: "null", data: Data("null".utf8), invalidLayout: false),
    CorruptCase(name: "cycle", data: worldJSON([deskJSON(root: 1, nodes: [
        1: splitJSON([2, 3], [0.5, 0.5]), 2: splitJSON([1, 4], [0.5, 0.5], axis: "vertical"), 3: panelJSON(3), 4: panelJSON(4),
    ], windows: [3, 4])]), invalidLayout: true),
    CorruptCase(name: "dangling child", data: worldJSON([deskJSON(root: 3, nodes: [
        1: panelJSON(1), 3: splitJSON([1, 2], [0.5, 0.5]),
    ], windows: [1])]), invalidLayout: true),
    CorruptCase(name: "single-child split", data: worldJSON([deskJSON(root: 3, nodes: [
        1: panelJSON(1), 3: splitJSON([1], [1.0]),
    ], windows: [1])]), invalidLayout: true),
    CorruptCase(name: "weights sum to 0.9", data: worldJSON([deskJSON(root: 3, nodes: [
        1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2], [0.4, 0.5]),
    ], windows: [1, 2])]), invalidLayout: true),
    CorruptCase(name: "negative weight", data: worldJSON([deskJSON(root: 3, nodes: [
        1: panelJSON(1), 2: panelJSON(2), 3: splitJSON([1, 2], [-0.5, 1.5]),
    ], windows: [1, 2])]), invalidLayout: true),
    CorruptCase(name: "tabs selected out of range", data: worldJSON([deskJSON(root: 1, nodes: [
        1: #"{"tabs":{"selected":5,"windows":[\#(windowJSON(1)),\#(windowJSON(2))]}}"#,
    ], windows: [1, 2])]), invalidLayout: true),
    CorruptCase(name: "duplicate window across desks", data: worldJSON([
        deskJSON(key: "D1", root: 1, nodes: [1: panelJSON(1)], windows: [1]),
        deskJSON(key: "D2", root: 2, nodes: [2: panelJSON(1)], windows: [1]),
    ]), invalidLayout: true),
    CorruptCase(name: "NodeID >= ids.next", data: worldJSON([validPair], next: 3), invalidLayout: true),
    CorruptCase(name: "ids.next = UInt64.max", data: worldJSON([], next: .max), invalidLayout: true),
    CorruptCase(name: "ids.next within maxNodes of exhaustion", data: worldJSON([validPair], next: .max - 100), invalidLayout: true),
    CorruptCase(name: "floating frame width -1", data: worldJSON([
        deskJSON(root: nil, nodes: [:], windows: [], floating: [floatingJSON(7, width: "-1")]),
    ]), invalidLayout: true),
    CorruptCase(name: "coordinate 1e300", data: worldJSON([
        deskJSON(root: nil, nodes: [:], windows: [], floating: [floatingJSON(7, x: "1e300")]),
    ]), invalidLayout: true),
    CorruptCase(name: "unknown Node case", data: worldJSON([deskJSON(root: 1, nodes: [
        1: #"{"stack":{"_0":\#(windowJSON(1))}}"#,
    ], windows: [1])]), invalidLayout: false),
    CorruptCase(name: "100-deep split chain", data: worldJSON([chainDesk(splits: 100)]), invalidLayout: true),
    CorruptCase(name: "5000 nodes", data: worldJSON([manyNodesDesk(5000)], next: 10_000), invalidLayout: true),
]

// MARK: Rich world for the exact round-trip

private let k1 = DeskKey(displayUUID: "D1", spaceID: nil)
private let k1s7 = DeskKey(displayUUID: "D1", spaceID: 7)
private let k2 = DeskKey(displayUUID: "D2", spaceID: nil)

private func hinted(_ id: UInt32, title: String, ax: String?, order: UInt64) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 200, bundleID: "com.example.editor"), titleHint: title, axIdentifier: ax, creationOrder: order)
}

private func richWorld() throws -> World {
    // D1: nested splits from inserts only. H[D, A, V[B, C]].
    var ids = IDSource()
    var nested = LayoutTree()
    let a = makeWindow(1), b = makeWindow(2), c = makeWindow(3), d = makeWindow(4)
    try nested.insertRoot(a, ids: &ids)
    try nested.insert(b, at: .right, of: #require(nested.leaf(containing: a)), ids: &ids)
    try nested.insert(c, at: .bottom, of: #require(nested.leaf(containing: b)), ids: &ids)
    try nested.insert(d, at: .left, of: #require(nested.leaf(containing: a)), ids: &ids)

    // D1 Space 7: tabs plus kept-slot states, through the validating init. H[E, tabs(F, G)] at 1/3, 2/3.
    let e = hinted(10, title: "Notes.txt", ax: "AXWindow-1", order: 3)
    let f = hinted(11, title: "", ax: nil, order: 4)
    let g = hinted(12, title: "Ünïcode ✓ \"quoted\"", ax: "", order: 5)
    let tabs = try LayoutTree(
        root: NodeID(raw: 102),
        nodes: [
            NodeID(raw: 100): .panel(e),
            NodeID(raw: 101): .tabs(windows: [f, g], selected: 1),
            NodeID(raw: 102): .split(axis: .horizontal, children: [NodeID(raw: 100), NodeID(raw: 101)], weights: [1.0 / 3.0, 2.0 / 3.0]),
        ],
        states: [e.identity: .absent, f.identity: .fullscreen, g.identity: .present])

    // D2: a 0.1 / 0.9 vertical split plus two floating windows, one at a negative origin.
    let h = hinted(20, title: "a", ax: "AXWin-20", order: 9_007_199_254_740_993)
    let i = makeWindow(21)
    let thin = try LayoutTree(
        root: NodeID(raw: 202),
        nodes: [
            NodeID(raw: 200): .panel(h),
            NodeID(raw: 201): .panel(i),
            NodeID(raw: 202): .split(axis: .vertical, children: [NodeID(raw: 200), NodeID(raw: 201)], weights: [0.1, 0.9]),
        ],
        states: [h.identity: .present, i.identity: .present])
    var desktop = DesktopLayer()
    try desktop.add(hinted(30, title: "Float", ax: "AXFloat", order: 1), frame: Rect(x: -1440, y: -0.5, width: 800.25, height: 600))
    try desktop.add(makeWindow(31), frame: Rect(x: 100, y: 100, width: 1.0 / 3.0, height: 0.1))

    return try World(ids: IDSource(next: 9_007_199_254_740_993), desks: [
        k1: Desk(tree: nested),
        k1s7: Desk(tree: tabs),
        k2: Desk(tree: thin, desktop: desktop),
    ])
}

private func replacing(_ data: Data, _ target: String, with replacement: String) throws -> Data {
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(target), "fixture no longer contains \(target)")
    return Data(text.replacingOccurrences(of: target, with: replacement).utf8)
}

private func expectPersistenceError(_ expected: PersistenceError, _ body: () throws(PersistenceError) -> World) {
    do {
        _ = try body()
        Issue.record("expected \(expected), but decoding succeeded")
    } catch {
        #expect(error == expected)
    }
}

@Suite struct PersistenceTests {
    @Test func richWorldRoundTripsExactly() throws {
        let world = try richWorld()
        let data = try world.encoded()
        let decoded = try World.decode(from: data)
        #expect(decoded == world)
        #expect(try decoded.encoded() == data)
        #expect(decoded.ids.next == 9_007_199_254_740_993)

        // WindowRef equality ignores hints, so check them field by field too.
        let floating = try #require(decoded[k2]?.desktop.windows.first)
        #expect(floating.window.axIdentifier == "AXFloat")
        #expect(floating.window.titleHint == "Float")
        #expect(floating.frame == Rect(x: -1440, y: -0.5, width: 800.25, height: 600))
        let tabs = try #require(decoded[k1s7]?.tree.node(NodeID(raw: 102)))
        #expect(tabs == .split(axis: .horizontal, children: [NodeID(raw: 100), NodeID(raw: 101)], weights: [1.0 / 3.0, 2.0 / 3.0]))
        let thin = try #require(decoded[k2]?.tree.node(NodeID(raw: 202)))
        #expect(thin == .split(axis: .vertical, children: [NodeID(raw: 200), NodeID(raw: 201)], weights: [0.1, 0.9]))
        #expect(decoded[k1s7]?.tree.state(of: makeWindow(10)) == nil)  // different pid/bundle: not the same window
        let e = hinted(10, title: "", ax: nil, order: 0)
        #expect(decoded[k1s7]?.tree.state(of: e) == .absent)
        #expect(decoded[k2]?.tree.windows.first?.creationOrder == 9_007_199_254_740_993)
    }

    /// Assumption-delta companion (01-01-PLAN.md): a nil Space and Space 7 on one display are two desks.
    @Test func nilAndNonNilSpaceOnOneDisplayAreDistinctDesks() throws {
        let perDisplay = DeskKey(displayUUID: "D1", spaceID: nil)
        let perSpace = DeskKey(displayUUID: "D1", spaceID: 7)
        #expect(perDisplay != perSpace)

        var world = World()
        try world.addDesk(perDisplay)
        try world.addDesk(perSpace)
        var history = UndoHistory()
        try world.edit(perSpace, history: &history) { desk, ids throws(LayoutError) in try desk.tree.insertRoot(makeWindow(1), ids: &ids) }
        #expect(world.desks.count == 2)

        let decoded = try World.decode(from: world.encoded())
        #expect(decoded[perDisplay] == Desk())
        #expect(decoded[perSpace]?.tree.windows == [makeWindow(1)])
        #expect(decoded == world)
    }

    @Test func handBuiltBaselineFixtureIsValid() throws {
        let world = try World.decode(from: worldJSON([validPair]))
        #expect(world[k1]?.tree.windows == [makeWindow(1), makeWindow(2)])
        // The chain helper is valid at the depth limit, so the 100-deep item fails for its depth only.
        _ = try World.decode(from: worldJSON([chainDesk(splits: LayoutTree.maxDepth)]))
    }

    @Test func versionOneLoads() throws {
        let data = try richWorld().encoded()
        #expect(String(decoding: data, as: UTF8.self).contains(#""schemaVersion":1"#))
        _ = try World.decode(from: data)
    }

    @Test func newerVersionIsRefused() throws {
        let data = try replacing(richWorld().encoded(), #""schemaVersion":1"#, with: #""schemaVersion":2"#)
        expectPersistenceError(.newerVersion(found: 2, supported: 1)) { () throws(PersistenceError) in try World.decode(from: data) }
    }

    @Test func olderVersionWithoutMigrationIsRefused() throws {
        let data = try replacing(richWorld().encoded(), #""schemaVersion":1"#, with: #""schemaVersion":0"#)
        expectPersistenceError(.missingMigration(from: 0)) { () throws(PersistenceError) in try World.decode(from: data) }
    }

    @Test(arguments: [#","schemaVersion":1"#, #""schemaVersion":"1""#])
    func missingOrNonIntegerVersionIsCorrupt(replacement: String) throws {
        let original = try richWorld().encoded()
        let data = replacement.hasPrefix(",")
            ? try replacing(original, replacement, with: "")
            : try replacing(original, #""schemaVersion":1"#, with: replacement)
        do {
            _ = try World.decode(from: data)
            Issue.record("expected corrupt")
        } catch {
            guard case .corrupt = error else { Issue.record("expected corrupt, got \(error)"); return }
        }
    }

    @Test func migrationChainRunsStepsInOrder() throws {
        let chain = MigrationChain(steps: [
            1: { object in object["trail"] = (object["trail"] as? [Int] ?? []) + [1] },
            2: { object in object["trail"] = (object["trail"] as? [Int] ?? []) + [2] },
        ])
        var object: [String: Any] = ["schemaVersion": 1]
        try chain.migrate(&object, from: 1, to: 3)
        #expect(object["trail"] as? [Int] == [1, 2])
        #expect(object["schemaVersion"] as? Int == 3)
    }

    @Test func migrationChainGapThrowsMissingMigrationForFirstGap() throws {
        let onlyTwo = MigrationChain(steps: [2: { _ in }])
        var object: [String: Any] = ["schemaVersion": 1]
        #expect(throws: PersistenceError.missingMigration(from: 1)) { try onlyTwo.migrate(&object, from: 1, to: 3) }
        let onlyOne = MigrationChain(steps: [1: { _ in }])
        #expect(throws: PersistenceError.missingMigration(from: 2)) { try onlyOne.migrate(&object, from: 1, to: 3) }
    }

    @Test func throwingMigrationStepIsCorrupt() throws {
        struct StepFailed: Error {}
        let chain = MigrationChain(steps: [0: { _ in throw StepFailed() }])
        var object: [String: Any] = ["schemaVersion": 0]
        do {
            try chain.migrate(&object, from: 0, to: 1)
            Issue.record("expected corrupt")
        } catch {
            guard case .corrupt = error else { Issue.record("expected corrupt, got \(error)"); return }
        }
    }

    @Test func olderFileDecodesThroughTheChain() throws {
        // A hypothetical schema 0 that called desks "spaces".
        let v1 = try richWorld().encoded()
        var v0 = try replacing(v1, #""schemaVersion":1"#, with: #""schemaVersion":0"#)
        v0 = try replacing(v0, #""desks":"#, with: #""spaces":"#)
        let chain = MigrationChain(steps: [0: { object in object["desks"] = object.removeValue(forKey: "spaces") }])
        let migrated = try World.decode(from: v0, migrations: chain)
        // IDSource is above 2^53, which JSONSerialization may not keep exact, so compare the desks.
        #expect(migrated.desks == (try richWorld()).desks)
    }

    @Test(arguments: corruptCorpus)
    func corruptFileThrowsPersistenceError(item: CorruptCase) {
        do {
            _ = try World.decode(from: item.data)
            Issue.record("\(item.name) decoded without error")
        } catch {
            switch error {
            case .invalidLayout: #expect(item.invalidLayout, "\(item.name) should be corrupt, got \(error)")
            case .corrupt: #expect(!item.invalidLayout, "\(item.name) should be invalidLayout, got \(error)")
            default: Issue.record("\(item.name) threw unexpected \(error)")
            }
        }
    }

    @Test func oversizedInputIsRejectedBeforeParsing() {
        #expect(World.maxEncodedBytes == 16 * 1024 * 1024)
        let data = Data(count: World.maxEncodedBytes + 1)
        expectPersistenceError(.tooLarge(bytes: World.maxEncodedBytes + 1, limit: World.maxEncodedBytes)) { () throws(PersistenceError) in
            try World.decode(from: data)
        }
    }
}
