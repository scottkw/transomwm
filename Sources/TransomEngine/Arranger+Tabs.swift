import TransomModel

/// A tab-group change to speak (UI-SPEC Accessibility); the shell words it (`TabCopy`).
public enum TabAnnouncement: Equatable, Sendable {
    /// A new group of `tabs` windows was made.
    case grouped(tabs: Int)
    /// A window was added to a group, which now has `tabs`.
    case added(tabs: Int)
}

/// Making tab groups by a centre drop (D-01 to D-03). Each drop is one `World.edit`, dry-run first like a dock (Pattern 4).
extension Arranger {
    /// Whether a drop on leaf `id` of `key`'s desk may group: a docked panel or an existing group.
    func groupable(_ id: NodeID, on key: DeskKey) -> Bool {
        switch world[key]?.tree.node(id) {
        case .panel?, .tabs?: true
        case .split?, .desktop?, nil: false
        }
    }

    /// The group dry run for a centre held for the group dwell (UI-SPEC Surface 1): the drop applied to a copy of the
    /// World, then planned. The preview is the group frame that plan gives; with no room it is Blocked (zoom off) or
    /// Collapsed (zoom on), over the frame ignoring minimums. A target gone stale is the Phase 3 decision.
    mutating func decideGroup(_ hover: Hover, window: WindowRef) -> Decision {
        guard case .tile(let key, let id)? = hover.groupTarget, let display = display(for: key), let node = world[key]?.tree.node(id) else {
            return decide(hover, window: window)
        }
        let action = DropAction.group(key, .tile(key, id))
        let label = if case .tabs = node { GroupCopy.addTab } else { GroupCopy.newGroup }
        func preview(_ frame: Rect) -> PreviewState { .group(frame: frame, strip: TabBand.strip(of: frame), label: label) }
        do throws(LayoutError) {
            guard let desk = try dropping(window, on: key, at: .tile(id, .center)).world[key] else { return decide(hover, window: window) }
            let plan = try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: minimums)
            if plan.unfit.isEmpty, let frame = plan.resolution.nodeRects[id] {
                return Decision(preview: preview(frame), action: action, display: display.uuid)
            }
            let loose = try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: [:]).resolution.nodeRects[id]
            // D-A: with zoom on the drop is accepted and the windows without room collapse.
            if let collapsed = try collapse(desk, area: display.visibleFrame) {
                let copy = Self.collapseCopy(collapsed.newly, moving: window)
                let shown = loose.map { rect in copy.map { PreviewState.collapsed(rect, label: $0.label) } ?? preview(rect) }
                return Decision(preview: shown, action: action, display: display.uuid)
            }
            return Decision(preview: loose.map(PreviewState.blocked), action: .refuse(Self.noRoom), display: display.uuid)
        } catch {
            return decide(hover, window: window)  // the target went stale since the hit test
        }
    }

    /// A release on a held group preview: the dock commit at the target's centre, which groups (one undo step), then
    /// the announcement. A collapse speaks its own announcement instead (Phase 4), and a refusal its own.
    mutating func commitGroup(_ window: WindowRef, on key: DeskKey, into target: GroupTarget) throws(LayoutError) -> [ArrangerEffect] {
        guard case .tile(_, let id) = target else { return try missed(window) }
        let before = world[key]?.tree.node(id)
        let effects = try commitDock(window, on: key, at: .tile(id, .center))
        guard case .tabs(let members, _)? = world[key]?.tree.node(id), members.last == window,
            !effects.contains(where: { if case .announce = $0 { true } else { false } })
        else { return effects }
        if case .panel(let other)? = before {
            return effects + [.tabAnnouncement(.grouped(tabs: 2)), .info("group \(id): created from \(window) + \(other) (docked)")]
        }
        return effects + [.tabAnnouncement(.added(tabs: members.count)), .info("group \(id): added \(window), \(members.count) tabs")]
    }
}
