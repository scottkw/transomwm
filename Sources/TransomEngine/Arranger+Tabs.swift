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
    /// Close Group stopped: this member was still open `closeConfirmation` after its close press (UI-SPEC Surface 4).
    case didNotClose(WindowRef)
    /// The group was left with one window and dissolved (D-12).
    case ended
}

/// Why a tab action changed no window (UI-SPEC Surface 2, "While paused, or Accessibility not ready").
public enum TabRefusal: Equatable, Sendable {
    case notInGroup, paused, notReady
}

/// One tab group: its desk and its leaf, or for a floating group its ID (minted from the same IDSource, so never equal).
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

/// Where a tab selection came from: `.activation` (D-08) and `.close` (Close Group showing a hidden member before
/// its close) are not announced.
public enum TabSelectSource: Equatable, Sendable {
    case click, overflow, hotkey, menu, url, activation, close
}

/// A tab action from the strip, a hotkey, a menu or a URL.
public enum TabAction: Equatable, Sendable {
    case select(WindowRef, via: TabSelectSource)
    case closeGroup(GroupKey)
    case minimizeGroup(GroupKey)
    /// The strip's Float Group (docked group) or Dock Group (floating group) button.
    case toggleGroupFloat(GroupKey)
}

/// Close Group in progress (D-06): one member at a time, each hidden one shown first. `current` was sent its close
/// press and must be gone by `deadline`.
struct CloseQueue: Equatable, Sendable {
    var group: GroupKey
    var remaining: [WindowRef]
    var current: WindowRef?
    var deadline: ContinuousClock.Instant?
    var closed = 0
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
    var closeQueue: CloseQueue?
    /// Per group, until when a focus of a hidden member does not select it (Pitfall 6).
    var suppressedUntil: [GroupKey: ContinuousClock.Instant] = [:]
    /// The strips last sent per display, so only a change is sent again.
    var shownStrips: [String: [TabStrip]] = [:]
}

/// A tab group holding some window, docked or floating, as select, reveal, D-08 and strips see it.
struct TabGroupRef: Equatable, Sendable {
    var key: GroupKey
    var members: [WindowRef]
    var selected: Int
    var floating: Bool
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
        switch hover.groupTarget {
        case .floating(let key, _)?, .floatingGroup(let key, _)?:
            return decideFloatingGroup(hover, on: key, window: window)
        case .tile?, nil: break
        }
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
        guard case .tile(_, let id) = target else { return try commitFloatingGroup(window, on: key, into: target) }
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

/// Floating tab groups (D-02, TABS-05): made on the Desktop tile, kept as a sidecar on `DesktopLayer`.
extension Arranger {
    /// The floating centre under `point` on `key`'s desk (RESEARCH Pattern 3): the topmost floating window under the
    /// pointer, never `dragged` or a hidden member, if `point` is in the middle 50% of its frame. A group's selected
    /// member stands for its group (its frame is the content rect). An excluded or never-dock window there groups nothing.
    func floatingGroupTarget(at point: Point, on key: DeskKey, dragging dragged: WindowRef) -> GroupTarget? {
        guard let desk = world[key], desk.tree.isDesktopHidden != true else { return nil }
        let layer = desk.desktop
        guard let top = layer.windows.reversed().first(where: { floating in
            guard floating.window != dragged, floating.state == .present else { return false }
            if let group = layer.group(containing: floating.window), group.members[group.selected] != floating.window { return false }
            return (windows[floating.window.identity]?.frame ?? floating.frame).contains(point)
        }) else { return nil }
        guard let info = windows[top.window.identity], !info.isExcluded, info.kind == .dockable else { return nil }
        let frame = info.frame, band = DropZones.edgeBandFraction
        let fx = (point.x - frame.minX) / frame.width, fy = (point.y - frame.minY) / frame.height
        guard (band...(1 - band)).contains(fx), (band...(1 - band)).contains(fy) else { return nil }
        if let group = layer.group(containing: top.window) { return .floatingGroup(key, group.id) }
        return .floating(key, top.window)
    }

    /// The World and history with `window` taken off its desk and dropped into the floating `target` on `key`'s desk:
    /// grouped with a plain floater at its frame, or added as a group's last tab. One undo step there (Pattern 4).
    func droppingIntoFloating(_ window: WindowRef, on key: DeskKey, target: GroupTarget) throws(LayoutError) -> (world: World, history: UndoHistory) {
        var candidate = world, candidateHistory = history
        if let from = deskKey(of: window), from != key {
            // Leaving another display's desk is a fact of where it was dropped, not a second undo step.
            try candidate.reflow(from) { desk, _ throws(LayoutError) in
                if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
            }
        }
        try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            if desk.desktop.contains(window) {
                try desk.desktop.remove(window)
            } else if desk.tree.state(of: window) != nil {
                try desk.tree.remove(window)
            }
            switch target {
            case .floating(_, let other): try desk.desktop.group(id: try ids.make(), target: other, adding: window)
            case .floatingGroup(_, let id): try desk.desktop.addTab(window, to: id)
            case .tile(_, let id): throw .notATabGroup(id)
            }
        }
        return (candidate, candidateHistory)
    }

    /// The group dry run on a floating centre: the drop applied to a copy of the World, then planned. The preview is the
    /// group frame (the target's frame, or the group's, clamped like any floater); with no room for the selected member
    /// plus its band it is Blocked (zoom off) or Collapsed (zoom on) over that frame.
    private mutating func decideFloatingGroup(_ hover: Hover, on key: DeskKey, window: WindowRef) -> Decision {
        guard let target = hover.groupTarget, let display = display(for: key) else { return decide(hover, window: window) }
        let action = DropAction.group(key, target)
        let label = if case .floatingGroup = target { GroupCopy.addTab } else { GroupCopy.newGroup }
        func preview(_ frame: Rect) -> PreviewState { .group(frame: frame, strip: TabBand.strip(of: frame), label: label) }
        do throws(LayoutError) {
            guard let desk = try droppingIntoFloating(window, on: key, target: target).world[key], let group = desk.desktop.group(containing: window)
            else { return decide(hover, window: window) }
            let plan = try Planner.plan(desk: desk, area: display.visibleFrame, gap: gap, mins: minimums)
            let frame = TabBand.frame(ofContent: plan.frames[window] ?? TabBand.content(of: group.frame))
            if plan.unfit.isEmpty { return Decision(preview: preview(frame), action: action, display: display.uuid) }
            if let collapsed = try collapse(desk, area: display.visibleFrame) {
                let copy = Self.collapseCopy(collapsed.newly, moving: window)
                return Decision(preview: copy.map { .collapsed(frame, label: $0.label) } ?? preview(frame), action: action, display: display.uuid)
            }
            return Decision(preview: .blocked(frame), action: .refuse(Self.noRoom), display: display.uuid)
        } catch {
            return decide(hover, window: window)  // the target went stale since the hit test
        }
    }

    /// A release on a held floating group preview: the drop (one undo step), then the announcement, unless a collapse
    /// spoke its own. The dragged window, now selected, takes over the wanted frame of the tab it replaced.
    private mutating func commitFloatingGroup(_ window: WindowRef, on key: DeskKey, into target: GroupTarget) throws(LayoutError) -> [ArrangerEffect] {
        let candidate = try droppingIntoFloating(window, on: key, target: target)
        guard let area = display(for: key)?.visibleFrame, let desk = candidate.world[key], let group = desk.desktop.group(containing: window) else {
            return [.announce(Self.noRoom)] + (try missed(window))
        }
        var collapsed: Collapse?
        if try !Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).unfit.isEmpty {
            guard let collapse = try collapse(desk, area: area) else { return [.announce(Self.noRoom)] + (try missed(window)) }
            collapsed = collapse
        }
        let replaced: WindowRef? = if case .floatingGroup(_, let id) = target, let old = world[key]?.desktop.groups.first(where: { $0.id == id }) {
            old.members[old.selected]
        } else { nil }
        world = candidate.world
        history = candidate.history
        lastRequested[window.identity] = nil
        wantedFrames[window.identity] = replaced.flatMap { wantedFrames.removeValue(forKey: $0.identity) }
        let note = accept(collapsed, moving: window)
        let effects = replan() + note
        guard !note.contains(where: { if case .announce = $0 { true } else { false } }) else { return effects }
        if case .floating(_, let other) = target {
            return effects + [.tabAnnouncement(.grouped(tabs: 2)), .info("group \(group.id): created from \(window) + \(other) (floating)")]
        }
        return effects + [.tabAnnouncement(.added(tabs: group.members.count)), .info("group \(group.id): added \(window), \(group.members.count) tabs")]
    }

    /// The group holding `window`, docked or floating.
    func tabGroup(holding window: WindowRef) -> TabGroupRef? {
        guard let key = deskKey(of: window), let desk = world[key] else { return nil }
        if let leaf = desk.tree.leaf(containing: window), case .tabs(let members, let selected)? = desk.tree.node(leaf) {
            return TabGroupRef(key: GroupKey(desk: key, node: leaf), members: members, selected: selected, floating: false)
        }
        return desk.desktop.group(containing: window).map {
            TabGroupRef(key: GroupKey(desk: key, node: $0.id), members: $0.members, selected: $0.selected, floating: true)
        }
    }

    /// The group `key` names, docked or floating.
    func tabGroup(_ key: GroupKey) -> TabGroupRef? {
        guard let desk = world[key.desk] else { return nil }
        if case .tabs(let members, let selected)? = desk.tree.node(key.node) {
            return TabGroupRef(key: key, members: members, selected: selected, floating: false)
        }
        return desk.desktop.groups.first { $0.id == key.node }.map { TabGroupRef(key: key, members: $0.members, selected: $0.selected, floating: true) }
    }

    /// Whether `window` is a non-selected member of a docked or floating group: it never shows in focus moves or the overview.
    public func isHiddenTab(_ window: WindowRef) -> Bool {
        tabGroup(holding: window).map { $0.members[$0.selected] != window } ?? false
    }

    /// Makes `window` the selected tab of `group` in the World: an OS-level fact of which tab shows, so no undo step.
    mutating func selectInWorld(_ window: WindowRef, in group: TabGroupRef) throws(LayoutError) {
        try world.reflow(group.key.desk) { desk, _ throws(LayoutError) in
            if group.floating { try desk.desktop.selectTab(window) } else { try desk.tree.selectTab(window) }
        }
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
        case .closeGroup(let group): closeGroup(group, ready: ready, now: now)
        case .minimizeGroup(let group): minimizeGroup(group, ready: ready, now: now)
        case .toggleGroupFloat(let group): toggleGroupFloat(group, ready: ready)
        }
    }

    /// Makes `window` its group's selected tab (no undo step). The new member is written into the content rect and
    /// focused; the previous one parks only after that write reads back (`revealed(_:actual:now:)`).
    mutating func select(_ window: WindowRef, via source: TabSelectSource, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "select \(window)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "select \(window)", "Accessibility is not ready") }
        guard let ref = tabGroup(holding: window), let index = ref.members.firstIndex(of: window) else {
            return refuse(.notInGroup, "select \(window)", "not in a tab group")
        }
        let group = ref.key, leaf = ref.key.node, members = ref.members, previous = members[ref.selected]
        guard previous != window else { return [.perform([.focus(window)])] }
        guard world[group.desk]?.state(of: window) == .present else {
            return [.beep, .tabAnnouncement(.couldNotShow(window)), .info("group \(leaf): select \(window) via \(source) refused, not present")]
        }
        do throws(LayoutError) {
            try selectInWorld(window, in: ref)
        } catch {
            return [.beep, .fault("group \(leaf): select \(window) failed: \(error)")]
        }
        // A floating group's wanted frame belongs to whichever member shows (Planner plans the selected one).
        if ref.floating { wantedFrames[window.identity] = wantedFrames.removeValue(forKey: previous.identity) }
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
        let spoken: [ArrangerEffect] = source == .activation || source == .close ? [] : [.tabAnnouncement(.selected(index: index + 1, count: members.count))]
        let logged: [ArrangerEffect] = tabs.pendingReveal == nil ? [.info("group \(leaf): select \(window) via \(source)")] : []
        return spoken + logged + replan() + [.raiseStrip(group)] + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    func refuse(_ refusal: TabRefusal, _ what: String, _ why: String) -> [ArrangerEffect] {
        [.beep, .tabAnnouncement(.refused(refusal)), .info("group: \(what) refused, \(why)")]
    }

    /// A read-back of the pending reveal's window within 2 pt of its content rect: the previous member parks now.
    mutating func revealed(_ window: WindowRef, actual: Rect, now: ContinuousClock.Instant) -> [ArrangerEffect]? {
        guard let pending = tabs.pendingReveal, pending.revealed == window, let planned = lastRequested[window.identity],
            Planner.near(actual, planned, within: 2)
        else { return nil }
        tabs.pendingReveal = nil
        let ms = Int((now - pending.started) / .milliseconds(1))
        return [.info("group \(pending.group.node): select \(window) via \(pending.source), \(ms) ms")] + replan() + closeProgress(now: now)
    }

    /// On every tick: expired focus suppressions go, and a pending reveal whose deadline passed with no matching
    /// read-back reverts; the previous member, never parked, stays (UI-SPEC Surface 3 error state).
    mutating func revealTimedOut(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        tabs.suppressedUntil = tabs.suppressedUntil.filter { $0.value > now }
        guard let pending = tabs.pendingReveal, now >= pending.deadline else { return [] }
        tabs.pendingReveal = nil
        // Close Group never closes a member it could not show: it stops, as at a window still open.
        if tabs.closeQueue?.group == pending.group { tabs.closeQueue = nil }
        guard let ref = tabGroup(holding: pending.previous), ref.key == pending.group else { return replan() }
        do throws(LayoutError) {
            try selectInWorld(pending.previous, in: ref)
            if ref.floating { wantedFrames[pending.previous.identity] = wantedFrames.removeValue(forKey: pending.revealed.identity) }
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
        guard pauseReasons.isEmpty, !sessionPaused, tabs.pendingReveal?.revealed != window, let ref = tabGroup(holding: window),
            ref.members[ref.selected] != window
        else { return [] }
        if let until = tabs.suppressedUntil[ref.key], now < until { return [] }
        return select(window, via: .activation, ready: true, now: now)
    }

    /// The selected member of a group was focused: its strip comes front (UI-SPEC Surface 2 Ordering), so a floating
    /// window raised over the group earlier stops covering it. Only on focus, never on a replan.
    func raisedStrip(of window: WindowRef) -> [ArrangerEffect] {
        guard let ref = tabGroup(holding: window), ref.members[ref.selected] == window else { return [] }
        return [.raiseStrip(ref.key)]
    }

    /// D-12: `window` left `group` (the model already picked the right, else left, neighbour). A group left with one
    /// window has dissolved under the same NodeID, its survivor taking the whole frame: "Tab group ended", except on
    /// Close Group's way through the members, where the windows vanishing is the feedback.
    func dissolved(_ group: TabGroupRef, losing window: WindowRef) -> [ArrangerEffect] {
        guard group.members.count == 2, let survivor = group.members.first(where: { $0 != window }), tabGroup(holding: survivor) == nil
        else { return [] }
        let spoken: [ArrangerEffect] = tabs.closeQueue?.group == group.key ? [] : [.tabAnnouncement(.ended)]
        return spoken + [.info("group \(group.key.node): dissolved, \(survivor) keeps the \(group.floating ? "frame" : "tile")")]
    }

    /// A member of a group closed or went absent: macOS may focus another member next, which must not flip the group.
    mutating func suppressFocus(ofGroupHolding window: WindowRef, now: ContinuousClock.Instant) {
        guard let ref = tabGroup(holding: window) else { return }
        tabs.suppressedUntil[ref.key] = now + Self.focusSuppression
    }

    /// One strip per docked group of `desk` whose selected member is planned on screen (not parked, collapsed,
    /// absent or fullscreen), and per floating group whose selected member is present and not parked (a hidden Desktop,
    /// a zoomed view), over its planned or stored content rect; in ID order. Titles are the live ones (Pitfall 7, D-09).
    func tabStrips(_ key: DeskKey, desk: Desk, plan: FramePlan) -> [TabStrip] {
        func titles(_ members: [WindowRef]) -> [String] { members.map { windows[$0.identity]?.window.titleHint ?? "" } }
        let docked = desk.tree.nodes.compactMap { id, node -> TabStrip? in
            guard case .tabs(let members, let selected) = node, plan.frames[members[selected]] != nil, let rect = plan.resolution.nodeRects[id]
            else { return nil }
            return TabStrip(
                group: GroupKey(desk: key, node: id), frame: TabBand.strip(of: rect), members: members, titles: titles(members),
                selected: selected, floating: false)
        }
        let parked = Set(plan.parks)
        let floating = desk.desktop.groups.compactMap { group -> TabStrip? in
            let shown = group.members[group.selected]
            guard desk.desktop.windows.contains(where: { $0.window == shown && $0.state == .present }), !parked.contains(shown) else { return nil }
            let content = plan.frames[shown] ?? TabBand.content(of: group.frame)
            return TabStrip(
                group: GroupKey(desk: key, node: group.id), frame: TabBand.strip(of: TabBand.frame(ofContent: content)), members: group.members,
                titles: titles(group.members), selected: group.selected, floating: true)
        }
        return (docked + floating).sorted { $0.group.node < $1.group.node }
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

/// Close Group and Minimize Group (D-06): the strip's buttons act on the whole group.
extension Arranger {
    /// How long after its close press a member may stay open before Close Group stops there (RESEARCH Pitfall 10, A4).
    /// It covers Transom's two-source close confirmation; a save prompt keeps the window open past it.
    public static let closeConfirmation: Duration = .seconds(1)

    /// Starts Close Group: the selected member first, then the others in strip order. A second click after a stop
    /// starts again from the group as it is now, whose selected member is the one that stopped it.
    mutating func closeGroup(_ group: GroupKey, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "close group \(group.node)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "close group \(group.node)", "Accessibility is not ready") }
        guard let ref = tabGroup(group) else { return refuse(.notInGroup, "close group \(group.node)", "no such group") }
        guard tabs.closeQueue?.group != group else { return [] }  // already closing
        let selected = ref.members[ref.selected]
        tabs.closeQueue = CloseQueue(group: group, remaining: [selected] + ref.members.filter { $0 != selected })
        return closeProgress(now: now) + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Minimises the selected member only (D-07): hidden members stay parked, and the participation rule hides the
    /// strip once it reads back absent. macOS focusing another member of the same app then must not flip the group.
    mutating func minimizeGroup(_ group: GroupKey, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "minimize group \(group.node)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "minimize group \(group.node)", "Accessibility is not ready") }
        guard let ref = tabGroup(group) else { return refuse(.notInGroup, "minimize group \(group.node)", "no such group") }
        tabs.suppressedUntil[group] = now + Self.focusSuppression
        return [.perform([.minimize(ref.members[ref.selected])]), .info("group \(group.node): minimized")]
    }

    /// Moves Close Group on: after its current member is gone the next one is shown if hidden, then pressed; past the
    /// deadline with the member still open it stops (UI-SPEC Surface 4). Runs after events, read-backs and ticks.
    mutating func closeProgress(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard var queue = tabs.closeQueue else { return [] }
        if let current = queue.current {
            if windows[current.identity] != nil {
                guard let deadline = queue.deadline, now >= deadline else { return [] }
                tabs.closeQueue = nil
                return [.tabAnnouncement(.didNotClose(current)), .info("group \(queue.group.node): close stopped at \(current) after 1 s")]
            }
            queue.current = nil
            queue.deadline = nil
            queue.closed += 1
        }
        queue.remaining.removeAll { windows[$0.identity] == nil }
        guard let next = queue.remaining.first else {
            tabs.closeQueue = nil
            return [.info("group \(queue.group.node): close \(queue.closed) windows")]
        }
        tabs.closeQueue = queue
        if tabs.pendingReveal?.revealed == next { return [] }  // shown, waiting for its read-back
        if isHiddenTab(next) {
            let shown = select(next, via: .close, ready: true, now: now)
            guard !isHiddenTab(next) else {
                tabs.closeQueue = nil
                return shown + [.info("group \(queue.group.node): close stopped, could not show \(next)")]
            }
            return shown + closeProgress(now: now)
        }
        queue.remaining.removeFirst()
        queue.current = next
        queue.deadline = now + Self.closeConfirmation
        tabs.closeQueue = queue
        return [.perform([.close(next)])]
    }
}

/// Whole-group moves (D-06, UI-SPEC Surface 5, RESEARCH Pattern 9): every path that moves a group's window moves the
/// whole group, as one leaf or one floating group, in one `World.edit`.
extension Arranger {
    /// The strip's Float Group / Dock Group button.
    mutating func toggleGroupFloat(_ group: GroupKey, ready: Bool) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "float or dock group \(group.node)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "float or dock group \(group.node)", "Accessibility is not ready") }
        guard let ref = tabGroup(group) else { return refuse(.notInGroup, "float or dock group \(group.node)", "no such group") }
        do throws(LayoutError) {
            return try ref.floating ? dockGroup(ref) : floatGroup(ref)
        } catch {
            return [.beep, .fault("group \(group.node): float or dock failed: \(error)")]
        }
    }

    /// The minimum a group needs: its largest member's per axis, plus the band. Nil when no member has one.
    func groupMinimum(_ members: [WindowRef]) -> Size? {
        let known = members.compactMap { minimums[$0] }
        guard !known.isEmpty else { return nil }
        return Size(width: known.map(\.width).max()!, height: known.map(\.height).max()! + TabBand.height)
    }

    /// Float Group: the docked group floats at `Planner.floatFrame` of its group frame (its selected member's pre-dock
    /// frame plus the band, else 90% of the tile, centred), showing a hidden Desktop first (D-31). Its tile closes and the
    /// neighbours reflow; members, order and selection stay. One undo step. Hidden members re-park at the new size.
    mutating func floatGroup(_ ref: TabGroupRef) throws(LayoutError) -> [ArrangerEffect] {
        let key = ref.key.desk, selected = ref.members[ref.selected]
        guard let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        let mins = minimums, gap = gap, show = showingDesktop(), minimum = groupMinimum(ref.members)
        guard let tile = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).resolution.nodeRects[ref.key.node]
            ?? windows[selected.identity].map({ TabBand.frame(ofContent: $0.frame) })
        else { return [.beep] }
        let wanted = wantedFrames[selected.identity]
        var frame = tile, desktop = area
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            if desk.tree.isDesktopHidden == true { try show(&desk, &ids) }
            let removed = try desk.tree.removeLeaf(ref.key.node)
            desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).desktopRect ?? area
            frame = Planner.floatFrame(wanted: wanted.map(TabBand.frame(ofContent:)), tile: tile, desktop: desktop, minimum: minimum)
            let group = FloatingTabGroup(id: try ids.make(), members: ref.members, selected: ref.selected, frame: frame)
            try desk.desktop.addGroup(group, states: removed.states)
        }
        // As Float Window: a pre-dock frame only clamped stays wanted, re-planned as the Desktop changes (WR-01).
        let content = TabBand.content(of: frame)
        wantedFrames[selected.identity] = wanted.map { Planner.clamp(TabBand.frame(ofContent: $0), into: desktop) } == frame ? wanted : content
        return replan() + [.info("group \(ref.key.node): floated")]
    }

    /// Dock Group: the floating group docks where Dock Window would dock a window at the group frame's centre; with no
    /// room it is refused with the Blocked flash and "Not enough room". One undo step.
    mutating func dockGroup(_ ref: TabGroupRef) throws(LayoutError) -> [ArrangerEffect] {
        try dock(ref.members[ref.selected])
    }

    /// The group a drag of `window` moves whole: its group when it is the selected member (Surface 5).
    func movingGroup(_ window: WindowRef) -> TabGroupRef? {
        tabGroup(holding: window).flatMap { $0.members[$0.selected] == window ? $0 : nil }
    }

    /// Takes `ref`'s group off `desk` as one leaf node with its members' states: its tree leaf, or its floating group.
    static func takeGroup(_ ref: TabGroupRef, from desk: inout Desk) throws(LayoutError) -> (node: Node, states: [WindowIdentity: WindowState]) {
        guard ref.floating else { return try desk.tree.removeLeaf(ref.key.node) }
        let (group, states) = try desk.desktop.removeGroup(ref.key.node)
        return (.tabs(windows: group.members, selected: group.selected), states)
    }
}
