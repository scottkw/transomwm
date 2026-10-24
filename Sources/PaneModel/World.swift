import Foundation

public struct Desk: Codable, Equatable, Sendable {
    public var tree: LayoutTree
    public var desktop: DesktopLayer

    public init(tree: LayoutTree = LayoutTree(), desktop: DesktopLayer = DesktopLayer()) {
        self.tree = tree
        self.desktop = desktop
    }

    /// True when `window` is docked in the tree or floats on the Desktop layer.
    public func contains(_ window: WindowRef) -> Bool {
        tree.state(of: window) != nil || desktop.contains(window)
    }

    /// Tree and Desktop layer are each valid, and no window is both docked and floating.
    public func validate() throws(LayoutError) {
        try tree.validate()
        try desktop.validate()
        if let both = desktop.windows.first(where: { tree.state(of: $0.window) != nil }) {
            throw .duplicateWindow(both.window)
        }
    }
}

/// All desks, keyed by display (and optionally Space), plus the ID source their node IDs come from.
public struct World: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public private(set) var ids: IDSource
    public private(set) var desks: [DeskKey: Desk]

    public init() {
        ids = IDSource()
        desks = [:]
    }

    public init(ids: IDSource, desks: [DeskKey: Desk]) throws(LayoutError) {
        self.ids = ids
        self.desks = desks
        try validate()
    }

    /// Every desk is valid, no window (docked or floating) is on two desks, and every NodeID came from `ids`.
    public func validate() throws(LayoutError) {
        var seen: Set<WindowIdentity> = []
        for (_, desk) in desks.sorted(by: { $0.key < $1.key }) {
            try desk.validate()
            for window in desk.tree.windows + desk.desktop.windows.map(\.window) where !seen.insert(window.identity).inserted {
                throw .duplicateWindow(window)
            }
            if let id = desk.tree.nodes.keys.first(where: { $0.raw >= ids.next }) {
                throw .invariantViolated("node \(id) is not below the ID source's next value \(ids.next)")
            }
        }
    }

    public subscript(key: DeskKey) -> Desk? { desks[key] }

    public mutating func addDesk(_ key: DeskKey) throws(LayoutError) {
        guard desks[key] == nil else { throw .deskExists(key) }
        desks[key] = Desk()
    }

    /// The one way to change a desk. `change` runs on copies of the desk and the ID source; the
    /// result is committed, and the pre-edit desk pushed onto `history`, only if `change` succeeds
    /// and the whole World still validates. Any throw leaves `self`, `history` and `ids` unchanged.
    public mutating func edit(_ key: DeskKey, history: inout UndoHistory, _ change: (inout Desk, inout IDSource) throws(LayoutError) -> Void) throws(LayoutError) {
        guard let before = desks[key] else { throw .deskNotFound(key) }
        var candidate = self
        var desk = before
        try change(&desk, &candidate.ids)
        candidate.desks[key] = desk
        try candidate.validate()
        history.push(before, for: key)
        self = candidate
    }

    /// Restores the newest snapshot of `key`'s desk. Returns false when there is none. `ids` is
    /// never rewound, so NodeIDs are not reused. Throws, changing nothing, if the restored desk
    /// would make the World invalid (for example a window that has since moved to another desk).
    @discardableResult
    public mutating func undo(_ key: DeskKey, history: inout UndoHistory) throws(LayoutError) -> Bool {
        guard desks[key] != nil else { throw .deskNotFound(key) }
        var nextHistory = history
        guard let snapshot = nextHistory.pop(for: key) else { return false }
        var candidate = self
        candidate.desks[key] = snapshot
        try candidate.validate()
        self = candidate
        history = nextHistory
        return true
    }

    // MARK: Codable — deterministic output, validated input

    private enum CodingKeys: String, CodingKey { case schemaVersion, ids, desks }

    /// Desks are stored as records sorted by key, so output is deterministic.
    private struct DeskRecord: Codable {
        let key: DeskKey
        let desk: Desk
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "unsupported schema version \(version)")
        }
        let ids = try container.decode(IDSource.self, forKey: .ids)
        let records = try container.decode([DeskRecord].self, forKey: .desks)
        let world: World
        do throws(LayoutError) {
            var desks: [DeskKey: Desk] = [:]
            for record in records {
                if desks.updateValue(record.desk, forKey: record.key) != nil { throw .deskExists(record.key) }
            }
            world = try World(ids: ids, desks: desks)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "invalid world", underlyingError: error))
        }
        self = world
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(ids, forKey: .ids)
        let records = desks.sorted { $0.key < $1.key }.map { DeskRecord(key: $0.key, desk: $0.value) }
        try container.encode(records, forKey: .desks)
    }
}
