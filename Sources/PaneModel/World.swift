import Foundation

public struct Desk: Codable, Equatable, Sendable {
    public var tree: LayoutTree
    public var desktop: DesktopLayer

    public init(tree: LayoutTree = .withDesktop(), desktop: DesktopLayer = DesktopLayer()) {
        self.tree = tree
        self.desktop = desktop
    }

    /// True when `window` is docked in the tree or floats on the Desktop layer.
    public func contains(_ window: WindowRef) -> Bool {
        tree.state(of: window) != nil || desktop.contains(window)
    }

    /// Lifecycle state of a docked or floating window, nil if the desk has no such window.
    public func state(of window: WindowRef) -> WindowState? {
        tree.state(of: window) ?? desktop.windows.first { $0.window == window }?.state
    }

    /// Lifecycle transition for a docked or floating window (D-17). Docked windows go through
    /// `LayoutTree.setState`; a floating window keeps its frame. The same contract applies: lock, sleep
    /// and AX timeouts are `.absent` (PITFALLS.md Pitfall 2). `.closed` is rejected: a close made here,
    /// for example inside `World.edit`, would be undoable, so only `World.apply(.closed, …)` closes.
    /// Throws `windowNotFound` if the desk has no such window.
    public mutating func setState(_ state: WindowState, for window: WindowRef) throws(LayoutError) {
        if tree.state(of: window) != nil {
            try tree.setState(state, for: window)
        } else {
            try desktop.setState(state, for: window)
        }
    }

    /// Removes a window the OS confirmed closed. Internal so that every close goes through
    /// `World.apply`, which also purges the window from undo history.
    mutating func close(_ window: WindowRef) throws(LayoutError) {
        if tree.state(of: window) != nil {
            try tree.remove(window)
        } else {
            try desktop.remove(window)
        }
    }

    /// Tree and Desktop layer are each valid, the tree holds the Desktop tile (D-24), and no window is
    /// both docked and floating.
    public func validate() throws(LayoutError) {
        try tree.validate()
        guard tree.isDesktopHidden != nil else { throw .invariantViolated("desk has no Desktop tile \(NodeID.desktop)") }
        try desktop.validate()
        if let both = desktop.windows.first(where: { tree.state(of: $0.window) != nil }) {
            throw .duplicateWindow(both.window)
        }
    }
}

extension Desk {
    /// Re-points a docked or floating window to its corrected ID. Internal: only `World.rekey` and
    /// `UndoHistory.rekey` call it, so every rekey reaches the desks and the snapshots together.
    mutating func rekey(from: WindowRef, to: WindowRef) throws(LayoutError) {
        if tree.state(of: from) != nil {
            try tree.rekey(from: from, to: to)
        } else {
            try desktop.rekey(from: from, to: to)
        }
    }
}

extension LayoutTree {
    /// Replaces `from` with `to` in its panel or tab group under the same NodeID, keeping its state and the
    /// tab selection. Kept here rather than in TreeEdits.swift: it is an OS fact, not a user edit.
    mutating func rekey(from: WindowRef, to: WindowRef) throws(LayoutError) {
        guard let leaf = leaf(containing: from), let state = states[from.identity] else { throw .windowNotFound(from) }
        guard states[to.identity] == nil else { throw .duplicateWindow(to) }
        switch nodes[leaf] {
        case .panel?: nodes[leaf] = .panel(to)
        case let .tabs(windows, selected)?: nodes[leaf] = .tabs(windows: windows.map { $0 == from ? to : $0 }, selected: selected)
        case .split?, .desktop?, nil: throw .notALeaf(leaf) // leaf(containing:) only returns panels and tab groups
        }
        states[from.identity] = nil
        states[to.identity] = state
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

    /// The load path (`init(from:)` uses it). Besides `validate()`, requires `ids` to have half its range
    /// left, which no real session approaches, so a hostile file cannot load with an ID source about to
    /// run out. Edits are not held to this bound: they stop only where `IDSource.make()` throws. Also
    /// requires `ids.next >= 1`, so the source can never mint the reserved `NodeID.desktop`.
    public init(ids: IDSource, desks: [DeskKey: Desk]) throws(LayoutError) {
        guard ids.next >= 1 else { throw .invariantViolated("ID source 0 would mint the Desktop tile's \(NodeID.desktop)") }
        guard ids.next <= UInt64.max / 2 else {
            throw .invariantViolated("ID source \(ids.next) is too close to exhaustion")
        }
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

    /// The one way to make a user edit to a desk. `change` runs on copies of the desk and the ID
    /// source; the result is committed, and the pre-edit desk pushed onto `history`, only if `change`
    /// succeeds and the whole World still validates. Any throw leaves `self`, `history` and `ids`
    /// unchanged. Lifecycle states reported by the OS go through `apply` instead.
    public mutating func edit(_ key: DeskKey, history: inout UndoHistory, _ change: (inout Desk, inout IDSource) throws(LayoutError) -> Void) throws(LayoutError) {
        guard let before = desks[key] else { throw .deskNotFound(key) }
        try reflow(key, change)
        history.push(before, for: key)
    }

    /// `edit`'s exact contract minus the history push: `change` runs on copies, and is committed only if it
    /// succeeds and the whole World still validates; any throw leaves `self` and `ids` unchanged. For OS facts
    /// and automatic floats (a window that lost its room, D-26), never for user commands, which must be undoable.
    public mutating func reflow(_ key: DeskKey, _ change: (inout Desk, inout IDSource) throws(LayoutError) -> Void) throws(LayoutError) {
        guard var desk = desks[key] else { throw .deskNotFound(key) }
        var candidate = self
        try change(&desk, &candidate.ids)
        candidate.desks[key] = desk
        try candidate.validate()
        self = candidate
    }

    /// Records where a floating window now is (TILE-07): a fact, so no undo step. Throws `invalidGeometry` for a
    /// non-finite or out-of-range frame and `windowNotFound` when no desk floats the window; either way nothing changes.
    public mutating func recordFloatingFrame(_ frame: Rect, for window: WindowRef) throws(LayoutError) {
        guard let key = desks.first(where: { $0.value.desktop.contains(window) })?.key else { throw .windowNotFound(window) }
        try reflow(key) { desk, _ throws(LayoutError) in try desk.desktop.setFrame(frame, for: window) }
    }

    /// Records a lifecycle fact the OS reported (D-17) for a window on `key`'s desk, with the same
    /// rules as `Desk.setState`. Undo is for user edits only, so nothing is pushed onto `history`.
    /// `.closed` is about the window, not the desk: it removes the window from whichever desk holds it,
    /// if any, and always from every snapshot, so no undo brings a closed window back, even one that an
    /// undo or a move had already taken off every desk. `key` is ignored for `.closed` and need not have
    /// a desk. Any throw leaves `self` and `history` unchanged.
    public mutating func apply(_ state: WindowState, for window: WindowRef, on key: DeskKey, history: inout UndoHistory) throws(LayoutError) {
        var candidate = self
        if state == .closed {
            if let holder = desks.first(where: { $0.value.contains(window) })?.key {
                try candidate.desks[holder]?.close(window)
            }
        } else {
            guard desks[key] != nil else { throw .deskNotFound(key) }
            try candidate.desks[key]?.setState(state, for: window)
        }
        try candidate.validate()
        self = candidate
        if state == .closed { history.forget(window) }
    }

    /// An OS fact (02-16): macOS corrected `from`'s ID to `to`, and it is the same window. Re-points it on
    /// whichever desk holds it (panel, tab or Desktop layer, keeping its state and frame) and in every undo
    /// snapshot, so a later undo brings it back under its new ID (Pitfall 3). Pushes no undo step. A window no
    /// desk holds is re-pointed in the snapshots only. If a desk already holds `to`, the tracker merged two
    /// entries: `from` is closed instead, exactly as `apply(.closed, …)`, so no window is held twice. Any throw
    /// leaves `self` and `history` unchanged.
    public mutating func rekey(from: WindowRef, to: WindowRef, history: inout UndoHistory) throws(LayoutError) {
        guard from != to else { return }
        if desks.values.contains(where: { $0.contains(to) }) {
            try apply(.closed, for: from, on: DeskKey(displayUUID: "", spaceID: nil), history: &history)
            return
        }
        var candidate = self
        if let holder = desks.first(where: { $0.value.contains(from) })?.key {
            try candidate.desks[holder]?.rekey(from: from, to: to)
        }
        try candidate.validate()
        self = candidate
        history.rekey(from: from, to: to)
    }

    /// Restores the newest snapshot of `key`'s desk, keeping the current lifecycle state of every
    /// window still on the desk, and the current frame of every window floating both now and in the snapshot
    /// (those are OS facts, not something the user edited; Pitfall 10). `ids` is never
    /// rewound, so NodeIDs are not reused. If the restored desk would make the World invalid (for
    /// example a window that has since moved to another desk), throws and leaves the World unchanged,
    /// but the snapshot is still consumed so it cannot block the older ones.
    ///
    /// Returns nil when there is nothing to undo. Otherwise returns the windows the undo brought back
    /// that no desk held before it (in snapshot order, usually empty). The model tracks no state for a
    /// window on no desk, so these keep the state their snapshot held, which may be stale: the caller
    /// must re-report each one's real state through `apply`.
    @discardableResult
    public mutating func undo(_ key: DeskKey, history: inout UndoHistory) throws(LayoutError) -> [WindowRef]? {
        guard let current = desks[key] else { throw .deskNotFound(key) }
        guard var snapshot = history.pop(for: key) else { return nil }
        var revived: [WindowRef] = []
        for window in snapshot.tree.windows + snapshot.desktop.windows.map(\.window) {
            if let state = current.state(of: window) {
                try snapshot.setState(state, for: window)
            } else {
                revived.append(window) // a window on another desk instead makes validate() throw below
            }
        }
        for floating in snapshot.desktop.windows {
            if let frame = current.desktop.frame(of: floating.window) { try snapshot.desktop.setFrame(frame, for: floating.window) }
        }
        var candidate = self
        candidate.desks[key] = snapshot
        try candidate.validate()
        self = candidate
        return revived
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
