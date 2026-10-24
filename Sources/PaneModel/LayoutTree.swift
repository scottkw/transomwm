import Foundation

public enum Node: Codable, Equatable, Sendable {
    /// `weights.count == children.count`, each weight >= `LayoutTree.minWeight`, sum 1.
    case split(axis: Axis, children: [NodeID], weights: [Double])
    case panel(WindowRef)
    case tabs(windows: [WindowRef], selected: Int)
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
}

/// A flat value tree: nodes refer to children by ID, so the whole layout is a cheap copy-on-write
/// snapshot. Every way of building one (init, decoding, edits) ends in `validate()`.
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

    public func validate() throws(LayoutError) {
        guard let root else {
            guard nodes.isEmpty, states.isEmpty else {
                throw .invariantViolated("root is nil but the tree has \(nodes.count) nodes and \(states.count) states")
            }
            return
        }
        var visited: Set<NodeID> = []
        var seen: Set<WindowIdentity> = []
        var stack = [root]
        while let id = stack.popLast() {
            guard visited.insert(id).inserted, let node = nodes[id] else { continue }
            switch node {
            case let .split(_, children, weights):
                guard children.count >= 2, weights.count == children.count else {
                    throw .invariantViolated("split \(id) needs at least 2 children and one weight per child")
                }
                guard abs(weights.reduce(0, +) - 1) <= 1e-9 else {
                    throw .invariantViolated("weights of split \(id) do not sum to 1")
                }
                stack.append(contentsOf: children)
            case let .panel(window):
                seen.insert(window.identity)
            case let .tabs(windows, _):
                seen.formUnion(windows.map(\.identity))
            }
        }
        guard nodes.keys.allSatisfy(visited.contains) else {
            throw .invariantViolated("tree has nodes not reachable from root \(root)")
        }
        guard Set(states.keys) == seen else {
            throw .invariantViolated("window states do not match the windows in the tree")
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
            case nil: break
            }
        }
        return result
    }

    public func leaf(containing w: WindowRef) -> NodeID? {
        nodes.first { _, node in
            switch node {
            case let .panel(window): window == w
            case let .tabs(windows, _): windows.contains(w)
            case .split: false
            }
        }?.key
    }

    public func state(of w: WindowRef) -> WindowState? { states[w.identity] }

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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let root = try container.decodeIfPresent(NodeID.self, forKey: .root)
        let nodes = try container.decode([NodeID: Node].self, forKey: .nodes)
        let records = try container.decode([StateRecord].self, forKey: .states)
        let tree: LayoutTree
        do throws(LayoutError) {
            var states: [WindowIdentity: WindowState] = [:]
            for record in records {
                if states.updateValue(record.state, forKey: record.window) != nil {
                    throw .invariantViolated("duplicate state record for window \(record.window.windowID) pid \(record.window.pid)")
                }
            }
            tree = try LayoutTree(root: root, nodes: nodes, states: states)
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
