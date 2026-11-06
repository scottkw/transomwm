import Foundation

public enum Node: Codable, Equatable, Sendable {
    /// `weights.count == children.count`, each weight >= `LayoutTree.minWeight`, sum 1.
    case split(axis: Axis, children: [NodeID], weights: [Double])
    case panel(WindowRef)
    case tabs(windows: [WindowRef], selected: Int)
    /// The Desktop tile (D-24): floating windows live inside its rect. Hidden means it gets no rect,
    /// its space goes to the docked tiles and its floating windows are parked. Only `NodeID.desktop` holds it.
    case desktop(hidden: Bool)
}

/// Messages name NodeIDs and window identities only, never window titles.
public enum LayoutError: Error, Equatable, Sendable {
    case nodeNotFound(NodeID)
    case windowNotFound(WindowRef)
    case duplicateWindow(WindowRef)
    case treeNotEmpty
    case notASplit(NodeID)
    case notALeaf(NodeID)
    case notATabGroup(NodeID)
    case invalidBoundary(split: NodeID, index: Int)
    case splitFull(NodeID, limit: Int)
    case tooDeep(limit: Int)
    case tooManyNodes(limit: Int)
    case invalidGeometry(String)
    case invalidGap
    case invalidMinimum(WindowRef)
    case deskNotFound(DeskKey)
    case deskExists(DeskKey)
    case invariantViolated(String)
    /// Hiding the Desktop tile was asked while no window is docked; it would leave the desk with no tile.
    case nothingDocked
    /// The edit cannot apply to the Desktop tile at this NodeID (it holds no windows and never tabs).
    case desktopTile(NodeID)
    /// A grow or shrink of a child of this split changed nothing: every weight it could move is at `minWeight`.
    case atSizeLimit(NodeID)
}

/// A flat value tree: nodes refer to children by ID, so the whole layout is a cheap copy-on-write
/// snapshot. `init`, decoding and `insert` run `validate()` in every build and throw rather than
/// commit an invalid tree; the other edits add no nodes and check it in debug builds (`assertValid`).
public struct LayoutTree: Codable, Equatable, Sendable {
    // internal(set) rather than private(set): the edits in TreeEdits.swift write these; callers outside
    // the module still only read them.
    public internal(set) var root: NodeID?
    public internal(set) var nodes: [NodeID: Node]
    /// Lifecycle state of every window in the tree, keyed by identity.
    public internal(set) var states: [WindowIdentity: WindowState]

    public static let minWeight = 0.01
    public static let maxDepth = 64
    public static let maxNodes = 4096
    public static let maxChildren = 100

    public init() {
        root = nil
        nodes = [:]
        states = [:]
    }

    public init(root: NodeID?, nodes: [NodeID: Node], states: [WindowIdentity: WindowState]) throws(LayoutError) {
        self.root = root
        self.nodes = nodes
        self.states = states
        try validate()
    }

    /// Checks every structural invariant. Iterative with a visited set and a depth limit, never
    /// recursive, so a hostile decoded file cannot overflow the stack or loop forever.
    public func validate() throws(LayoutError) {
        guard nodes.count <= Self.maxNodes else { throw .tooManyNodes(limit: Self.maxNodes) }
        guard let root else {
            guard nodes.isEmpty, states.isEmpty else {
                throw .invariantViolated("root is nil but the tree has \(nodes.count) nodes and \(states.count) states")
            }
            return
        }
        var visited: Set<NodeID> = []
        var seen: Set<WindowIdentity> = []
        func see(_ window: WindowRef) throws(LayoutError) {
            guard seen.insert(window.identity).inserted else { throw .duplicateWindow(window) }
        }
        // The root is depth 0.
        var stack: [(id: NodeID, depth: Int, parentAxis: Axis?, siblings: Int)] = [(root, 0, nil, 0)]
        while let (id, depth, parentAxis, siblings) = stack.popLast() {
            guard visited.insert(id).inserted else { throw .invariantViolated("node \(id) is reachable more than once") }
            guard depth <= Self.maxDepth else { throw .tooDeep(limit: Self.maxDepth) }
            guard let node = nodes[id] else { throw .invariantViolated("node \(id) is referenced but does not exist") }
            switch node {
            case let .split(axis, children, weights):
                guard (2...Self.maxChildren).contains(children.count) else {
                    throw .invariantViolated("split \(id) has \(children.count) children, needs 2...\(Self.maxChildren)")
                }
                guard weights.count == children.count else {
                    throw .invariantViolated("split \(id) has \(weights.count) weights for \(children.count) children")
                }
                guard weights.allSatisfy({ $0.isFinite && $0 >= Self.minWeight - 1e-12 }) else {
                    throw .invariantViolated("split \(id) has a weight that is not finite or below \(Self.minWeight)")
                }
                guard abs(weights.reduce(0, +) - 1) <= 1e-9 else {
                    throw .invariantViolated("weights of split \(id) do not sum to 1")
                }
                // Same-axis nesting is allowed only where merging would pass maxChildren (see normalize()).
                guard axis != parentAxis || siblings - 1 + children.count > Self.maxChildren else {
                    throw .invariantViolated("split \(id) has the same axis as its parent split")
                }
                stack.append(contentsOf: children.map { ($0, depth + 1, axis, children.count) })
            case let .panel(window):
                try see(window)
            case let .tabs(windows, selected):
                guard windows.count >= 2 else { throw .invariantViolated("tab group \(id) has fewer than 2 windows") }
                guard windows.indices.contains(selected) else {
                    throw .invariantViolated("tab group \(id) selects \(selected) of \(windows.count) tabs")
                }
                for window in windows { try see(window) }
            case .desktop:
                guard id == .desktop else { throw .invariantViolated("node \(id) is a Desktop tile; only \(NodeID.desktop) may be") }
            }
        }
        guard visited.count == nodes.count else {
            throw .invariantViolated("tree has \(nodes.count - visited.count) nodes not reachable from root \(root)")
        }
        guard Set(states.keys) == seen else {
            throw .invariantViolated("window states do not match the windows in the tree")
        }
        guard !states.values.contains(.closed) else {
            throw .invariantViolated("a stored window state is closed; closed windows must be removed")
        }
    }

    public func node(_ id: NodeID) -> Node? { nodes[id] }

    /// Linear scan; the tree keeps no parent index.
    public func parent(of id: NodeID) -> NodeID? {
        nodes.first { _, node in
            if case let .split(_, children, _) = node { return children.contains(id) }
            return false
        }?.key
    }

    /// Pre-order, tabs in tab order.
    public var windows: [WindowRef] {
        var result: [WindowRef] = []
        var stack = root.map { [$0] } ?? []
        while let id = stack.popLast() {
            switch nodes[id] {
            case let .split(_, children, _)?: stack.append(contentsOf: children.reversed())
            case let .panel(window)?: result.append(window)
            case let .tabs(windows, _)?: result.append(contentsOf: windows)
            case .desktop?, nil: break
            }
        }
        return result
    }

    public func leaf(containing w: WindowRef) -> NodeID? {
        nodes.first { _, node in
            switch node {
            case let .panel(window): window == w
            case let .tabs(windows, _): windows.contains(w)
            case .split, .desktop: false
            }
        }?.key
    }

    public func state(of w: WindowRef) -> WindowState? { states[w.identity] }

    /// A layout holding only the visible Desktop tile: what every new desk starts as (D-24).
    public static func withDesktop() -> LayoutTree {
        var tree = LayoutTree()
        tree.root = .desktop
        tree.nodes[.desktop] = .desktop(hidden: false)
        return tree
    }

    /// Whether the Desktop tile is hidden; nil when the tree has no Desktop tile.
    public var isDesktopHidden: Bool? {
        guard case let .desktop(hidden)? = nodes[.desktop] else { return nil }
        return hidden
    }

    func assertValid() {
        #if DEBUG
        do { try validate() } catch { preconditionFailure("LayoutTree invariant violated: \(error)") }
        #endif
    }

    // MARK: Codable — deterministic output, validated input

    private enum CodingKeys: String, CodingKey { case root, nodes, states }

    /// States are stored as records sorted by identity, so output is deterministic and hints are not duplicated.
    private struct StateRecord: Codable {
        let window: WindowIdentity
        let state: WindowState
    }

    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, legacy: false)
    }

    /// `legacy`: the nodes are World schema 1's (`LegacyNode`), migrated off the Desktop tile.
    fileprivate init(from decoder: any Decoder, legacy: Bool) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let root = try container.decodeIfPresent(NodeID.self, forKey: .root)
        let nodes = legacy ? [:] : try container.decode([NodeID: Node].self, forKey: .nodes)
        let legacyNodes = legacy ? try container.decode([NodeID: LegacyNode].self, forKey: .nodes) : [:]
        let records = try container.decode([StateRecord].self, forKey: .states)
        let tree: LayoutTree
        do throws(LayoutError) {
            var states: [WindowIdentity: WindowState] = [:]
            for record in records {
                if states.updateValue(record.state, forKey: record.window) != nil {
                    throw .invariantViolated("duplicate state record for window \(record.window.windowID) pid \(record.window.pid)")
                }
            }
            tree = legacy
                ? try LayoutTree(legacyRoot: root, nodes: legacyNodes, states: states)
                : try LayoutTree(root: root, nodes: nodes, states: states)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "invalid layout tree", underlyingError: error))
        }
        self = tree
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(root, forKey: .root)
        try container.encode(nodes, forKey: .nodes)
        let records = states.sorted { $0.key < $1.key }.map { StateRecord(window: $0.key, state: $0.value) }
        try container.encode(records, forKey: .states)
    }
}

/// Decode-only: the node shape of World schema 1 (layout.json schema 3 and older, Phases 3–8.1), which had the Desktop
/// tile. Its case names and labels are `Node`'s, so the synthesized decoder reads the same JSON keys.
enum LegacyNode: Decodable {
    case split(axis: Axis, children: [NodeID], weights: [Double])
    case panel(WindowRef)
    case tabs(windows: [WindowRef], selected: Int)
    case desktop(hidden: Bool)
}

/// Decode-only: a World schema 1 tree, migrated off its Desktop tile as it decodes.
struct LegacyLayoutTree: Decodable {
    let tree: LayoutTree

    init(from decoder: any Decoder) throws {
        tree = try LayoutTree(from: decoder, legacy: true)
    }
}

extension LayoutTree {
    /// A World schema 1 tree without its Desktop tile (8.1.1 D-02). The tile is first swapped for a stand-in panel so
    /// the whole legacy shape goes through `validate()` (a hostile file is rejected, never repaired), and then the
    /// stand-in leaves through `removeLeaf`, as a closed window does: its share goes back to its siblings by weight, a
    /// one-child split collapses, and a tile that was alone leaves `root == nil`. The stand-in is no window and never
    /// outlives this init. A Desktop tile anywhere but NodeID 0 is rejected.
    init(legacyRoot root: NodeID?, nodes legacy: [NodeID: LegacyNode], states: [WindowIdentity: WindowState]) throws(LayoutError) {
        let standIn = WindowRef(identity: WindowIdentity(windowID: 0, pid: -1, bundleID: ""))
        let desktop = NodeID(raw: 0)
        var nodes: [NodeID: Node] = [:]
        var states = states
        var hasDesktop = false
        for (id, node) in legacy {
            switch node {
            case let .split(axis, children, weights): nodes[id] = .split(axis: axis, children: children, weights: weights)
            case let .panel(window): nodes[id] = .panel(window)
            case let .tabs(windows, selected): nodes[id] = .tabs(windows: windows, selected: selected)
            case .desktop:
                guard id == desktop else { throw .invariantViolated("node \(id) is a Desktop tile; only \(desktop) may be") }
                guard states[standIn.identity] == nil else { throw .duplicateWindow(standIn) }
                nodes[id] = .panel(standIn)
                states[standIn.identity] = .present
                hasDesktop = true
            }
        }
        var tree = try LayoutTree(root: root, nodes: nodes, states: states)
        if hasDesktop { _ = try tree.removeLeaf(desktop) }
        self = tree
    }
}
