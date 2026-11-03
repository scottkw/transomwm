import Foundation

/// A window floating on a desk's Desktop layer, with its frame in desk coordinates (the global
/// top-left space described in Geometry.swift).
public struct FloatingWindow: Codable, Equatable, Sendable {
    public let window: WindowRef
    public var frame: Rect
    public var state: WindowState
}

/// A tab group on the Desktop layer (D-02): a grouping over floating windows that stay in `DesktopLayer.windows`, each
/// with its stored frame equal to the group's content rect (RESEARCH Pattern 2, add-alongside).
public struct FloatingTabGroup: Codable, Equatable, Sendable {
    /// Minted from the World's IDSource; never a tree NodeID of the same desk.
    public let id: NodeID
    /// Tab order (D-03 appends).
    public var members: [WindowRef]
    public var selected: Int
    /// The group frame, the 32 pt band included.
    public var frame: Rect

    public init(id: NodeID, members: [WindowRef], selected: Int, frame: Rect) {
        self.id = id
        self.members = members
        self.selected = selected
        self.frame = frame
    }
}

/// The floating windows of one desk, back to front, and the tab groups over them. Every method checks before it
/// mutates, so a throwing call leaves the layer unchanged.
public struct DesktopLayer: Codable, Equatable, Sendable {
    public private(set) var windows: [FloatingWindow]
    public private(set) var groups: [FloatingTabGroup]

    public init() {
        windows = []
        groups = []
    }

    /// Adds `window` in front of the others, as `.present`.
    public mutating func add(_ window: WindowRef, frame: Rect) throws(LayoutError) {
        guard !contains(window) else { throw .duplicateWindow(window) }
        guard frame.isValidGeometry else { throw .invalidGeometry("floating frame of \(window) is not finite or out of range") }
        windows.append(FloatingWindow(window: window, frame: frame, state: .present))
    }

    /// Removes `window`, and takes it out of its group: a group left with one member is dissolved, the survivor
    /// getting the whole group frame back (the band returns to it).
    public mutating func remove(_ window: WindowRef) throws(LayoutError) {
        guard let index = index(of: window) else { throw .windowNotFound(window) }
        windows.remove(at: index)
        guard let g = groupIndex(of: window) else { return }
        var group = groups[g]
        let member = group.members.firstIndex(of: window)!
        group.members.remove(at: member)
        if group.members.count == 1 {
            if let survivor = self.index(of: group.members[0]) { windows[survivor].frame = group.frame }
            groups.remove(at: g)
            return
        }
        // Removing the selected tab selects the one that took its index, clamped to the last (as LayoutTree.remove).
        group.selected = member < group.selected ? group.selected - 1 : min(group.selected, group.members.count - 1)
        groups[g] = group
    }

    /// Records a floating window's frame. For a group member it is the content rect: the group frame and every
    /// member's frame follow.
    public mutating func setFrame(_ frame: Rect, for window: WindowRef) throws(LayoutError) {
        guard let index = index(of: window) else { throw .windowNotFound(window) }
        guard frame.isValidGeometry else { throw .invalidGeometry("floating frame of \(window) is not finite or out of range") }
        guard let g = groupIndex(of: window) else {
            windows[index].frame = frame
            return
        }
        let groupFrame = TabBand.frame(ofContent: frame)
        guard groupFrame.isValidGeometry else { throw .invalidGeometry("floating group frame of \(window) is out of range") }
        groups[g].frame = groupFrame
        setMemberFrames(of: g)
    }

    /// Stores a lifecycle state, keeping the frame. `.closed` is not storable: `World.apply(.closed, …)`
    /// closes a floating window through `remove`, after the same two-source confirmation as docked windows.
    public mutating func setState(_ state: WindowState, for window: WindowRef) throws(LayoutError) {
        guard let index = index(of: window) else { throw .windowNotFound(window) }
        guard state != .closed else { throw .invariantViolated("closed is a transition, not a stored state; close \(window) through World.apply") }
        windows[index].state = state
    }

    /// Re-points a floating window to the ID macOS corrected it to (02-16), keeping its frame, state, place in the
    /// stacking order and place in its group.
    public mutating func rekey(from: WindowRef, to: WindowRef) throws(LayoutError) {
        guard let index = index(of: from) else { throw .windowNotFound(from) }
        guard !contains(to) else { throw .duplicateWindow(to) }
        windows[index] = FloatingWindow(window: to, frame: windows[index].frame, state: windows[index].state)
        if let g = groupIndex(of: from) { groups[g].members = groups[g].members.map { $0 == from ? to : $0 } }
    }

    /// Replaces each window's ref with `change(ref)`, which must keep its identity (World.withoutTitleHints).
    mutating func mapWindows(_ change: (WindowRef) -> WindowRef) {
        windows = windows.map { FloatingWindow(window: change($0.window), frame: $0.frame, state: $0.state) }
        for g in groups.indices { groups[g].members = groups[g].members.map(change) }
    }

    // MARK: Tab groups

    /// Groups `window` with the floating `target` under `id` (D-02, D-03): the group takes the target's frame, both
    /// members its content rect, `window` selected. `window` is added in front of the others if it is not floating.
    public mutating func group(id: NodeID, target: WindowRef, adding window: WindowRef) throws(LayoutError) {
        guard let frame = frame(of: target) else { throw .windowNotFound(target) }
        guard window != target, group(containing: target) == nil else { throw .duplicateWindow(target) }
        guard group(containing: window) == nil else { throw .duplicateWindow(window) }
        guard !groups.contains(where: { $0.id == id }) else { throw .invariantViolated("floating group \(id) already exists") }
        var next = self
        if !next.contains(window) { try next.add(window, frame: TabBand.content(of: frame)) }
        next.groups.append(FloatingTabGroup(id: id, members: [target, window], selected: 1, frame: frame))
        next.setMemberFrames(of: next.groups.count - 1)
        self = next
    }

    /// Adds `window` as the last, selected tab of group `id`, at its content rect.
    public mutating func addTab(_ window: WindowRef, to id: NodeID) throws(LayoutError) {
        guard let g = groups.firstIndex(where: { $0.id == id }) else { throw .notATabGroup(id) }
        guard group(containing: window) == nil else { throw .duplicateWindow(window) }
        var next = self
        if !next.contains(window) { try next.add(window, frame: TabBand.content(of: groups[g].frame)) }
        next.groups[g].members.append(window)
        next.groups[g].selected = next.groups[g].members.count - 1
        next.setMemberFrames(of: g)
        self = next
    }

    /// Makes `window` the selected tab of its group.
    public mutating func selectTab(_ window: WindowRef) throws(LayoutError) {
        guard let g = groupIndex(of: window) else { throw .windowNotFound(window) }
        groups[g].selected = groups[g].members.firstIndex(of: window)!
    }

    /// Takes group `id` and its members off the layer as one unit (Pattern 9), returning it and the members' states.
    public mutating func removeGroup(_ id: NodeID) throws(LayoutError) -> (group: FloatingTabGroup, states: [WindowIdentity: WindowState]) {
        guard let g = groups.firstIndex(where: { $0.id == id }) else { throw .notATabGroup(id) }
        let group = groups.remove(at: g)
        var states: [WindowIdentity: WindowState] = [:]
        for floating in windows where group.members.contains(floating.window) { states[floating.window.identity] = floating.state }
        windows.removeAll { group.members.contains($0.window) }
        return (group, states)
    }

    /// Adds `group` in front of the others, each member at its content rect with its state from `states` (else present).
    public mutating func addGroup(_ group: FloatingTabGroup, states: [WindowIdentity: WindowState]) throws(LayoutError) {
        guard !groups.contains(where: { $0.id == group.id }) else { throw .invariantViolated("floating group \(group.id) already exists") }
        guard group.members.count >= 2, group.members.indices.contains(group.selected) else { throw .notATabGroup(group.id) }
        guard group.frame.isValidGeometry else { throw .invalidGeometry("floating group \(group.id) frame is not finite or out of range") }
        var next = self
        for member in group.members {
            try next.add(member, frame: TabBand.content(of: group.frame))
            if let state = states[member.identity], state != .present { try next.setState(state, for: member) }
        }
        next.groups.append(group)
        self = next
    }

    /// The group holding `window`, if any.
    public func group(containing window: WindowRef) -> FloatingTabGroup? {
        groupIndex(of: window).map { groups[$0] }
    }

    public func frame(of window: WindowRef) -> Rect? {
        index(of: window).map { windows[$0].frame }
    }

    public func contains(_ window: WindowRef) -> Bool { index(of: window) != nil }

    /// Unique identities, valid frames, and no stored `.closed` state; groups of 2 or more floating members, each in
    /// one group, a selection in range, a valid frame, unique IDs and at most `LayoutTree.maxNodes` of them. Decoding
    /// does not check this on its own; `World` validates every desk it is built from. Linear in windows and members.
    public func validate() throws(LayoutError) {
        var seen: Set<WindowIdentity> = []
        for floating in windows {
            guard seen.insert(floating.window.identity).inserted else { throw .duplicateWindow(floating.window) }
            guard floating.frame.isValidGeometry else {
                throw .invalidGeometry("floating frame of \(floating.window) is not finite or out of range")
            }
            guard floating.state != .closed else {
                throw .invariantViolated("floating \(floating.window) is stored as closed; closed windows must be removed")
            }
        }
        guard groups.count <= LayoutTree.maxNodes else { throw .tooManyNodes(limit: LayoutTree.maxNodes) }
        var ids: Set<NodeID> = [], grouped: Set<WindowIdentity> = []
        for group in groups {
            guard ids.insert(group.id).inserted else { throw .invariantViolated("floating group \(group.id) appears twice") }
            guard group.members.count >= 2 else { throw .invariantViolated("floating group \(group.id) has fewer than 2 members") }
            guard group.members.indices.contains(group.selected) else {
                throw .invariantViolated("floating group \(group.id) selects \(group.selected) of \(group.members.count)")
            }
            guard group.frame.isValidGeometry else { throw .invalidGeometry("floating group \(group.id) frame is not finite or out of range") }
            for member in group.members {
                guard seen.contains(member.identity) else { throw .windowNotFound(member) }
                guard grouped.insert(member.identity).inserted else { throw .duplicateWindow(member) }
            }
        }
    }

    private func index(of window: WindowRef) -> Int? {
        windows.firstIndex { $0.window == window }
    }

    private func groupIndex(of window: WindowRef) -> Int? {
        groups.firstIndex { $0.members.contains(window) }
    }

    /// Every member of group `g` at its content rect.
    private mutating func setMemberFrames(of g: Int) {
        let content = TabBand.content(of: groups[g].frame)
        for member in groups[g].members {
            if let index = index(of: member) { windows[index].frame = content }
        }
    }

    // MARK: Codable — `groups` is optional on disk

    private enum CodingKeys: String, CodingKey { case windows, groups }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windows = try container.decode([FloatingWindow].self, forKey: .windows)
        // Files written before floating groups have no key; that absence is the one sanctioned default.
        groups = try container.decodeIfPresent([FloatingTabGroup].self, forKey: .groups) ?? []
    }

    /// Omits `groups` when there are none, so a layer without groups encodes byte for byte as before.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windows, forKey: .windows)
        if !groups.isEmpty { try container.encode(groups, forKey: .groups) }
    }
}
