import TransomModel

/// A tab-group change to speak (UI-SPEC Accessibility); the shell words it (`TabCopy`).
public enum TabAnnouncement: Equatable, Sendable {
    /// A new group of `tabs` windows was made.
    case grouped(tabs: Int)
    /// A window was added to a group, which now has `tabs`.
    case added(tabs: Int)
    /// A selection's window gave no matching read-back within 1 s; the previous tab stayed (UI-SPEC Surface 3).
    case couldNotShow(WindowRef)
    /// Tab `index` (from 1) of `count` was selected by the user (click, overflow, hotkey, menu).
    case selected(index: Int, count: Int)
    /// A tab action that changed no window.
    case refused(TabRefusal)
}

/// Why a tab action changed no window (UI-SPEC Surface 2, "While paused, or Accessibility not ready").
public enum TabRefusal: Equatable, Sendable {
    case notInGroup, paused, notReady
}

/// One docked tab group: its desk and its leaf.
public struct GroupKey: Hashable, Sendable {
    public var desk: DeskKey
    public var node: NodeID

    public init(desk: DeskKey, node: NodeID) {
        self.desk = desk
        self.node = node
    }
}

/// What a group's strip panel shows (RESEARCH Pattern 6). `titles` are the live titles: `WindowRef ==` ignores
/// `titleHint`, so a title change must change this value (Pitfall 7).
public struct TabStrip: Equatable, Sendable {
    public var group: GroupKey
    /// `TabBand.strip(of:)` of the group frame, global top-left.
    public var frame: Rect
    public var members: [WindowRef]
    public var titles: [String]
    public var selected: Int
    public var floating: Bool

    public init(group: GroupKey, frame: Rect, members: [WindowRef], titles: [String], selected: Int, floating: Bool) {
        self.group = group
        self.frame = frame
        self.members = members
        self.titles = titles
        self.selected = selected
        self.floating = floating
    }
}

/// Where a tab selection came from: only `.activation` (D-08) is not announced.
public enum TabSelectSource: Equatable, Sendable {
    case click, overflow, hotkey, menu, url, activation
}

/// A tab action from the strip, a hotkey, a menu or a URL.
public enum TabAction: Equatable, Sendable {
    case select(WindowRef, via: TabSelectSource)
}

/// A selection waiting for its window's read-back (RESEARCH Pattern 5): until then `previous` keeps covering the
/// content rect and is not parked.
struct PendingReveal: Equatable, Sendable {
    var group: GroupKey
    var revealed: WindowRef
    var previous: WindowRef
    var source: TabSelectSource
    var started: ContinuousClock.Instant
    var deadline: ContinuousClock.Instant
}

/// The engine's tab-group state.
struct TabGroupState: Sendable {
    var pendingReveal: PendingReveal?
    /// Per group, until when a focus of a hidden member does not select it (Pitfall 6).
    var suppressedUntil: [GroupKey: ContinuousClock.Instant] = [:]
    /// The strips last sent per display, so only a change is sent again.
    var shownStrips: [String: [TabStrip]] = [:]
}

/// Making tab groups by a centre drop (D-01 to D-03). Each drop is one `World.edit`, dry-run first like a dock (Pattern 4).
extension Arranger {
    /// Whether a drop on leaf `id` of `key`'s desk may group (UI-SPEC Surface 1): a docked panel or an existing group,
    /// none of whose windows is collapsed, excluded or never-dock.
    func groupable(_ id: NodeID, on key: DeskKey) -> Bool {
        let members: [WindowRef]
        switch world[key]?.tree.node(id) {
        case .panel(let window)?: members = [window]
        case .tabs(let windows, _)?: members = windows
        case .split?, .desktop?, nil: return false
        }
        return members.allSatisfy { window in
            !camera.collapsible.contains(window.identity) && windows[window.identity].map { !$0.isExcluded && $0.kind == .dockable } ?? false
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

/// Showing and switching tabs (D-04, D-05, D-08): reveal the new member, read it back, then park the old one.
extension Arranger {
    /// How long the select waits for the revealed window's read-back before it reverts (UI-SPEC Surface 3).
    static let revealTimeout: Duration = .seconds(1)
    /// How long after a selection change, or a member's close or minimise, a focused hidden member is not selected (Pitfall 6).
    public static let focusSuppression: Duration = .seconds(1)

    /// A tab action; `ready` is the shell's Accessibility state.
    mutating func tab(_ action: TabAction, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        switch action {
        case .select(let window, let source): select(window, via: source, ready: ready, now: now)
        }
    }

    /// Makes `window` its group's selected tab (no undo step). The new member is written into the content rect and
    /// focused; the previous one parks only after that write reads back (`revealed(_:actual:now:)`).
    mutating func select(_ window: WindowRef, via source: TabSelectSource, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, window, "arranging is paused") }
        guard ready else { return refuse(.notReady, window, "Accessibility is not ready") }
        guard let key = deskKey(of: window), let leaf = world[key]?.tree.leaf(containing: window),
            case .tabs(let members, let selected)? = world[key]?.tree.node(leaf), let index = members.firstIndex(of: window)
        else { return refuse(.notInGroup, window, "not in a tab group") }
        let group = GroupKey(desk: key, node: leaf), previous = members[selected]
        guard previous != window else { return [.perform([.focus(window)])] }
        guard world[key]?.tree.state(of: window) == .present else {
            return [.beep, .tabAnnouncement(.couldNotShow(window)), .info("group \(leaf): select \(window) via \(source) refused, not present")]
        }
        do throws(LayoutError) {
            try world.reflow(key) { desk, _ throws(LayoutError) in try desk.tree.selectTab(window) }
        } catch {
            return [.beep, .fault("group \(leaf): select \(window) failed: \(error)")]
        }
        tabs.suppressedUntil[group] = now + Self.focusSuppression
        // The window covering the content rect now: a reveal still pending in this group keeps its cover.
        let cover = tabs.pendingReveal?.group == group ? tabs.pendingReveal?.previous : previous
        if let cover, cover != window, !parkRequested.contains(cover.identity), windows[cover.identity]?.state == .present {
            tabs.pendingReveal = PendingReveal(
                group: group, revealed: window, previous: cover, source: source, started: now, deadline: now + Self.revealTimeout)
        } else {
            // Nothing covers the content rect (the camera parked the group): nothing to wait for.
            tabs.pendingReveal = nil
        }
        let spoken: [ArrangerEffect] = source == .activation ? [] : [.tabAnnouncement(.selected(index: index + 1, count: members.count))]
        let logged: [ArrangerEffect] = tabs.pendingReveal == nil ? [.info("group \(leaf): select \(window) via \(source)")] : []
        return spoken + logged + replan() + [.raiseStrip(group)] + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    private func refuse(_ refusal: TabRefusal, _ window: WindowRef, _ why: String) -> [ArrangerEffect] {
        [.beep, .tabAnnouncement(.refused(refusal)), .info("group: select \(window) refused, \(why)")]
    }

    /// A read-back of the pending reveal's window within 2 pt of its content rect: the previous member parks now.
    mutating func revealed(_ window: WindowRef, actual: Rect, now: ContinuousClock.Instant) -> [ArrangerEffect]? {
        guard let pending = tabs.pendingReveal, pending.revealed == window, let planned = lastRequested[window.identity],
            Planner.near(actual, planned, within: 2)
        else { return nil }
        tabs.pendingReveal = nil
        let ms = Int((now - pending.started) / .milliseconds(1))
        return [.info("group \(pending.group.node): select \(window) via \(pending.source), \(ms) ms")] + replan()
    }

    /// On every tick: expired focus suppressions go, and a pending reveal whose deadline passed with no matching
    /// read-back reverts; the previous member, never parked, stays (UI-SPEC Surface 3 error state).
    mutating func revealTimedOut(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        tabs.suppressedUntil = tabs.suppressedUntil.filter { $0.value > now }
        guard let pending = tabs.pendingReveal, now >= pending.deadline else { return [] }
        tabs.pendingReveal = nil
        let key = pending.group.desk
        guard world[key]?.tree.leaf(containing: pending.previous) == pending.group.node else { return replan() }
        do throws(LayoutError) {
            try world.reflow(key) { desk, _ throws(LayoutError) in try desk.tree.selectTab(pending.previous) }
        } catch {
            return [.fault("group \(pending.group.node): could not keep \(pending.previous): \(error)")] + replan()
        }
        tabs.suppressedUntil[pending.group] = now + Self.focusSuppression
        return [.beep, .tabAnnouncement(.couldNotShow(pending.revealed)),
            .info("group \(pending.group.node): select \(pending.revealed) failed, no read-back after 1 s; kept \(pending.previous)")]
            + replan()
    }

    /// D-08: a hidden member focused another way (⌘Tab, the Dock, its app) becomes the selected tab, unless it is the
    /// window being revealed or its group changed within `focusSuppression`. Runs before the camera widen.
    mutating func activated(_ window: WindowRef, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused, tabs.pendingReveal?.revealed != window, let key = deskKey(of: window),
            let leaf = world[key]?.tree.leaf(containing: window), case .tabs(let members, let selected)? = world[key]?.tree.node(leaf),
            members[selected] != window
        else { return [] }
        if let until = tabs.suppressedUntil[GroupKey(desk: key, node: leaf)], now < until { return [] }
        return select(window, via: .activation, ready: true, now: now)
    }

    /// A member of a group closed or went absent: macOS may focus another member next, which must not flip the group.
    mutating func suppressFocus(ofGroupHolding window: WindowRef, now: ContinuousClock.Instant) {
        guard let key = deskKey(of: window), let leaf = world[key]?.tree.leaf(containing: window),
            case .tabs? = world[key]?.tree.node(leaf)
        else { return }
        tabs.suppressedUntil[GroupKey(desk: key, node: leaf)] = now + Self.focusSuppression
    }

    /// One strip per docked group of `desk` whose selected member is planned on screen (not parked, collapsed,
    /// absent or fullscreen), in node order. Titles are the live ones (Pitfall 7, D-09).
    func tabStrips(_ key: DeskKey, desk: Desk, plan: FramePlan) -> [TabStrip] {
        desk.tree.nodes.compactMap { id, node -> TabStrip? in
            guard case .tabs(let members, let selected) = node, plan.frames[members[selected]] != nil, let rect = plan.resolution.nodeRects[id]
            else { return nil }
            return TabStrip(
                group: GroupKey(desk: key, node: id), frame: TabBand.strip(of: rect), members: members,
                titles: members.map { windows[$0.identity]?.window.titleHint ?? "" }, selected: selected, floating: false)
        }
        .sorted { $0.group.node < $1.group.node }
    }

    /// Sends each display's strips that changed; a display with none (or gone) gets an empty list.
    mutating func showStrips(_ strips: [String: [TabStrip]]) -> [ArrangerEffect] {
        let uuids = Set(strips.keys).union(tabs.shownStrips.keys).sorted()
        return uuids.compactMap { uuid in
            let next = strips[uuid] ?? []
            guard next != tabs.shownStrips[uuid] ?? [] else { return nil }
            tabs.shownStrips[uuid] = next.isEmpty ? nil : next
            return .tabStrips(next, displayUUID: uuid)
        }
    }
}
