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
    /// A window left its group (tear-off); `dissolved` when that left the group with one window (D-12).
    case movedOut(dissolved: Bool)
    /// Esc canceled a tear-off; nothing changed.
    case tearOffCanceled
}

/// The tear-off ghost (UI-SPEC Surface 4): the torn tab's window, its live title, and the pointer it follows.
public struct TearOffGhost: Equatable, Sendable {
    public var member: WindowRef
    public var title: String
    public var pointer: Point

    public init(member: WindowRef, title: String, pointer: Point) {
        self.member = member
        self.title = title
        self.pointer = pointer
    }
}

/// A press on a strip tab (D-10): a tear-off once the pointer leaves `strip`, else the strip's own click.
struct TearPress: Equatable, Sendable {
    var member: WindowRef
    var group: GroupKey
    var strip: Rect
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

/// Where a Move Out of Group came from (logged).
public enum TabLeaveSource: Equatable, Sendable {
    case menu, hotkey, url, voiceOver
}

/// A tab action from the strip, a hotkey, a menu or a URL.
public enum TabAction: Equatable, Sendable {
    case select(WindowRef, via: TabSelectSource)
    /// The tab context menu's Move Out of Group (D-11): the member floats beside its group.
    case moveOut(WindowRef, via: TabLeaveSource)
    /// The tab context menu's Close Tab: one member through the close queue.
    case closeTab(WindowRef)
    case closeGroup(GroupKey)
    case minimizeGroup(GroupKey)
    /// The strip's Float Group (docked group) or Dock Group (floating group) button.
    case toggleGroupFloat(GroupKey)
    /// Esc during a tear-off (its temporary hotkeys).
    case cancelTearOff
    /// Next Tab, Previous Tab or Move Out of Group on `focused`'s group, from a hotkey, menu item or URL (Surface 7).
    case command(TabCommand, focused: WindowRef?, via: TabLeaveSource)
}

/// Close Group in progress (D-06): one member at a time, each hidden one shown first. `current` was sent its close
/// press and must be gone by `deadline`.
struct CloseQueue: Equatable, Sendable {
    var group: GroupKey
    var remaining: [WindowRef]
    var current: WindowRef?
    var deadline: ContinuousClock.Instant?
    var closed = 0
    /// Close Tab: one member, so a dissolve on the way is announced like any other.
    var oneTab = false
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
    /// The tab pressed and not yet torn off or released.
    var tearPress: TearPress?
    /// The torn-off tab, which moves alone (never its whole group), from the tear until its release commits.
    var tearing: WindowRef?
    /// Members Minimize Group minimised: their absence keeps the group's selection (D-06), unlike ⌘M on one (WR-02).
    var minimizing: Set<WindowIdentity> = []
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

    /// Docked and floating groups on every desk, and their members: the Debug line (UI-SPEC Surface 7).
    public func tabGroupCounts() -> (groups: Int, tabs: Int) {
        world.desks.values.reduce(into: (groups: 0, tabs: 0)) { counts, desk in
            for case .tabs(let members, _) in desk.tree.nodes.values { counts = (counts.groups + 1, counts.tabs + members.count) }
            for group in desk.desktop.groups { counts = (counts.groups + 1, counts.tabs + group.members.count) }
        }
    }

    /// The quit restore's group targets (D-07, Pitfall 3): every member of every group on every desk, at home or not, at
    /// its group's home-view content rect (a docked group's leaf rect, a floating group's planned or stored frame, minus
    /// the band). A docked group with no planned rect (collapsed, or its selected member absent, 07-05) or a desk that
    /// cannot be planned gives none, so its members keep the stranded rule: a parked one comes back centred on screen.
    public func groupContentRects() -> [WindowIdentity: Rect] {
        var rects: [WindowIdentity: Rect] = [:]
        for (key, desk) in world.desks {
            guard let display = displays.first(where: { $0.uuid == key.displayUUID }),
                let plan = try? ViewPlanner.plan(
                    desk: desk, view: .home, area: display.visibleFrame, gap: gap, mins: learnedMinimums, wanted: wantedFrames,
                    collapsible: camera.collapsible)
            else { continue }
            for case let (id, .tabs(members, selected)) in desk.tree.nodes where plan.collapsed[members[selected]] == nil {
                guard let rect = plan.resolution.nodeRects[id] else { continue }
                for member in members { rects[member.identity] = TabBand.content(of: rect) }
            }
            for group in desk.desktop.groups {
                let content = plan.frames[group.members[group.selected]] ?? TabBand.content(of: group.frame)
                for member in group.members { rects[member.identity] = content }
            }
        }
        return rects
    }

    /// The quit restore's writes (SAFE-01, D-D, D-07): every parked or off-screen window Transom may move, back on
    /// screen; a camera-parked or zoomed docked window at its home-view tile, every group member at its content rect.
    public func restorePlan() -> [WindowRef: Rect] {
        let groupRects = groupContentRects()
        let docked = Set(world.desks.values.flatMap { $0.tree.windows.map(\.identity) }).union(groupRects.keys)
        return Recovery.terminationPlan(
            windows: Array(windows.values), homeFrames: homeFrames, displays: displays, docked: docked,
            homeTiles: homeTiles().merging(groupRects) { $1 })
    }

    /// CR-01: the windows of apps about to join the exclusion list that the restore would move, and where: once
    /// excluded they are never written again, so a hidden tab must leave its park first. The window system writes these
    /// before it applies the list.
    public func releaseFrames(forExcluding bundleIDs: Set<String>) -> [WindowRef: Rect] {
        restorePlan().filter { ExclusionFilter.isExcluded($0.key.bundleID, in: bundleIDs) }
    }

    /// Every group's selected member that is present, every desk: the quit restore raises these last, over their hidden members.
    public func selectedGroupMembers() -> [WindowRef] {
        world.desks.values.flatMap { desk in
            desk.tree.nodes.values.compactMap { if case .tabs(let members, let selected) = $0 { members[selected] } else { nil } }
                + desk.desktop.groups.map { $0.members[$0.selected] }
        }
        .filter { windows[$0.identity]?.state == .present }
    }

    /// The members of the group holding `window` and its selected index, docked or floating (the overview's group tiles).
    public func tabGroupMembers(holding window: WindowRef) -> (members: [WindowRef], selected: Int)? {
        tabGroup(holding: window).map { ($0.members, $0.selected) }
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
        case .moveOut(let window, let source): moveOut(window, via: source, ready: ready)
        case .closeTab(let window): closeTab(window, ready: ready, now: now)
        case .closeGroup(let group): closeGroup(group, ready: ready, now: now)
        case .minimizeGroup(let group): minimizeGroup(group, ready: ready, now: now)
        case .toggleGroupFloat(let group): toggleGroupFloat(group, ready: ready)
        case .cancelTearOff: cancelTearOff()
        case .command(let command, let focused, let source): tabCommand(command, focused: focused, via: source, ready: ready, now: now)
        }
    }

    /// Selects the next or previous tab of `focused`'s group (wrapping), or moves `focused` out of it; refusals beep,
    /// announce and log "refused {command}: {reason}".
    mutating func tabCommand(
        _ command: TabCommand, focused: WindowRef?, via source: TabLeaveSource, ready: Bool, now: ContinuousClock.Instant
    ) -> [ArrangerEffect] {
        let name = switch command { case .next: "next tab"; case .previous: "previous tab"; case .moveOut: "move out of group" }
        func refused(_ refusal: TabRefusal, _ why: String) -> [ArrangerEffect] {
            [.beep, .tabAnnouncement(.refused(refusal)), .info("refused \(name): \(why)")]
        }
        guard pauseReasons.isEmpty, !sessionPaused else { return refused(.paused, "arranging is paused") }
        guard ready else { return refused(.notReady, "not ready") }
        guard let focused, let ref = tabGroup(holding: focused) else { return refused(.notInGroup, "not in a tab group") }
        let count = ref.members.count
        let via: TabSelectSource = switch source { case .menu: .menu; case .hotkey: .hotkey; case .url: .url; case .voiceOver: .click }
        switch command {
        case .next: return select(ref.members[(ref.selected + 1) % count], via: via, ready: ready, now: now)
        case .previous: return select(ref.members[(ref.selected + count - 1) % count], via: via, ready: ready, now: now)
        case .moveOut: return moveOut(focused, via: source, ready: ready)
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

    /// A read-back of the pending reveal's window at its content rect's origin (2 pt), at any smaller size and at most
    /// the docked correction's margin larger (an app that snaps its size to whole cells, WR-01): the previous member parks now.
    mutating func revealed(_ window: WindowRef, actual: Rect, now: ContinuousClock.Instant) -> [ArrangerEffect]? {
        let t = 2.0, margin = MinimumSizeLearner.refusalMargin
        guard let pending = tabs.pendingReveal, pending.revealed == window, let planned = lastRequested[window.identity],
            abs(actual.x - planned.x) <= t, abs(actual.y - planned.y) <= t,
            actual.width <= planned.width + margin, actual.height <= planned.height + margin
        else { return nil }
        tabs.pendingReveal = nil
        let ms = Int((now - pending.started) / .milliseconds(1))
        return [.info("group \(pending.group.node): select \(window) via \(pending.source), \(ms) ms")] + replan() + closeProgress(now: now)
            + [.tabRevealed(window)]
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
        // The reveal focused its window, which the replan parks again: the kept member takes focus back (WR-01).
        let refocus: [ArrangerEffect] = windows[pending.previous.identity]?.state == .present ? [.perform([.focus(pending.previous)])] : []
        return refocus + [.beep, .tabAnnouncement(.couldNotShow(pending.revealed)),
            .info("group \(pending.group.node): select \(pending.revealed) failed, no read-back after 1 s; kept \(pending.previous)")]
            + replan()
    }

    /// D-08: a hidden member focused another way (⌘Tab, the Dock, its app) becomes the selected tab, unless it is the
    /// window being revealed or its group changed within `focusSuppression`. Runs before the camera widen.
    mutating func activated(_ window: WindowRef, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused, tabs.pendingReveal?.revealed != window, let ref = tabGroup(holding: window),
            ref.members[ref.selected] != window
        else { return [] }
        if let until = tabs.suppressedUntil[ref.key], now < until {
            // WR-02: with the group minimised, the parked member macOS focused would be an invisible key window. The last
            // window focused that is on screen gets focus back; with none, the member is shown.
            guard windows[ref.members[ref.selected].identity]?.state != .present else { return [] }
            let shown = Set(displays.map(Self.key))
            let back = focusOrder.compactMap { windows[$0] }.first { info in
                info.window != window && info.state == .present && !parkRequested.contains(info.window.identity)
                    && !isHiddenTab(info.window) && deskKey(of: info.window).map(shown.contains) == true
            }
            guard let back else { return select(window, via: .activation, ready: true, now: now) }
            return [.perform([.focus(back.window)]), .info("group \(ref.key.node): minimized, focus of \(window) handed to \(back.window)")]
        }
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
        let closing = tabs.closeQueue.map { $0.group == group.key && !$0.oneTab } ?? false
        let spoken: [ArrangerEffect] = closing ? [] : [.tabAnnouncement(.ended)]
        return spoken + [.info("group \(group.key.node): dissolved, \(survivor) keeps the \(group.floating ? "frame" : "tile")")]
    }

    /// A member of a group closed or went absent: macOS may focus another member next, which must not flip the group.
    mutating func suppressFocus(ofGroupHolding window: WindowRef, now: ContinuousClock.Instant) {
        guard let ref = tabGroup(holding: window) else { return }
        tabs.suppressedUntil[ref.key] = now + Self.focusSuppression
    }

    /// WR-02: the selected member went absent (⌘M on it, its app hidden, native full screen), not by Minimize Group. The
    /// nearest present member, right else left, takes the selection, so the group keeps its tile and strip, and the
    /// absent one's return keeps it. No focus suppression: whichever member macOS focuses next is shown, never parked.
    mutating func selectNeighbour(ofAbsent window: WindowRef) throws(LayoutError) {
        guard let ref = tabGroup(holding: window), ref.members[ref.selected] == window, !tabs.minimizing.contains(window.identity)
        else { return }
        let i = ref.selected
        let order = Array(ref.members[(i + 1)...]) + ref.members[..<i].reversed()
        guard let next = order.first(where: { windows[$0.identity]?.state == .present }) else { return }
        try selectInWorld(next, in: ref)
        if ref.floating { wantedFrames[next.identity] = wantedFrames.removeValue(forKey: window.identity) }
        if tabs.pendingReveal?.group == ref.key { tabs.pendingReveal = nil }
        tabs.suppressedUntil[ref.key] = nil
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

    /// Close Tab: `member` alone through the close queue, shown first if hidden; a stop keeps nothing to resume.
    mutating func closeTab(_ member: WindowRef, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "close tab \(member)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "close tab \(member)", "Accessibility is not ready") }
        guard let ref = tabGroup(holding: member) else { return refuse(.notInGroup, "close tab \(member)", "not in a tab group") }
        guard tabs.closeQueue?.group != ref.key else { return [] }  // already closing
        tabs.closeQueue = CloseQueue(group: ref.key, remaining: [member], oneTab: true)
        return closeProgress(now: now) + (nextWake.map { [.wake(at: $0)] } ?? [])
    }

    /// Minimises the selected member only (D-07): hidden members stay parked, and the participation rule hides the
    /// strip once it reads back absent. macOS focusing another member of the same app then must not flip the group.
    mutating func minimizeGroup(_ group: GroupKey, ready: Bool, now: ContinuousClock.Instant) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "minimize group \(group.node)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "minimize group \(group.node)", "Accessibility is not ready") }
        guard let ref = tabGroup(group) else { return refuse(.notInGroup, "minimize group \(group.node)", "no such group") }
        tabs.suppressedUntil[group] = now + Self.focusSuppression
        tabs.minimizing.insert(ref.members[ref.selected].identity)
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

    /// The group a drag of `window` moves whole: its group when it is the selected member (Surface 5), unless it is
    /// a torn-off tab, which moves alone (D-10).
    func movingGroup(_ window: WindowRef) -> TabGroupRef? {
        guard tabs.tearing != window else { return nil }
        return tabGroup(holding: window).flatMap { $0.members[$0.selected] == window ? $0 : nil }
    }

    /// Takes `ref`'s group off `desk` as one leaf node with its members' states: its tree leaf, or its floating group.
    static func takeGroup(_ ref: TabGroupRef, from desk: inout Desk) throws(LayoutError) -> (node: Node, states: [WindowIdentity: WindowState]) {
        guard ref.floating else { return try desk.tree.removeLeaf(ref.key.node) }
        let (group, states) = try desk.desktop.removeGroup(ref.key.node)
        return (.tabs(windows: group.members, selected: group.selected), states)
    }
}

/// Tearing a tab out (D-10, RESEARCH Pattern 7): a press on a strip tab that leaves the strip becomes a move session of
/// that tab's window, through the same hover, dwell, dry run and preview as a title-bar drag.
extension Arranger {
    /// A press on `member`'s tab: remembered until the pointer leaves the strip. Nothing starts while paused, for a
    /// window not present, excluded or never-dock, or a group whose strip is not on screen.
    mutating func pressTab(_ member: WindowRef) {
        guard pauseReasons.isEmpty, !sessionPaused, let ref = tabGroup(holding: member), let info = windows[member.identity],
            info.state == .present, !info.isExcluded, info.kind == .dockable,
            let strip = tabs.shownStrips.values.joined().first(where: { $0.group == ref.key })?.frame
        else { return }
        tabs.tearPress = TearPress(member: member, group: ref.key, strip: strip)
    }

    /// The pointer left the pressed tab's strip: the tear-off session starts, already a move, with no frame poll (the
    /// window stays put until release). It lands at its saved pre-group size, else the content size.
    mutating func tearOff(_ press: TearPress, at point: Point, modifiers: Modifiers) {
        tabs.tearPress = nil
        guard let ref = tabGroup(press.group), ref.members.contains(press.member), let content = contentRect(of: ref) else { return }
        let size = wantedFrames[press.member.identity].map { Size(width: $0.width, height: $0.height) }
            ?? Size(width: content.width, height: content.height)
        var session = DragSession(window: press.member, start: point, startFrame: content, modifiers: modifiers)
        session.origin = .tearOff(press.group, stripRect: press.strip, landingSize: size)
        session.kind = .move
        drag = session
        tabs.tearing = press.member
    }

    /// The ghost at the session's pointer.
    func tearOffGhost(_ session: DragSession) -> ArrangerEffect {
        .tearOffGhost(TearOffGhost(member: session.window, title: windows[session.window.identity]?.window.titleHint ?? "", pointer: session.pointer))
    }

    /// A group's content rect: its planned leaf rect minus the band, or its floating frame minus the band.
    func contentRect(of ref: TabGroupRef) -> Rect? {
        guard let desk = world[ref.key.desk] else { return nil }
        if ref.floating { return desk.desktop.groups.first { $0.id == ref.key.node }.map { TabBand.content(of: $0.frame) } }
        guard let area = display(for: ref.key.desk)?.visibleFrame,
            let rect = try? Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution.nodeRects[ref.key.node]
        else { return nil }
        return TabBand.content(of: rect)
    }

    /// The Desktop rect a torn-off `window` floats into on `key`'s desk: with it out of its group and the Desktop shown.
    func tearOffDesktop(_ window: WindowRef, on key: DeskKey) throws(LayoutError) -> Rect? {
        guard let area = display(for: key)?.visibleFrame else { return nil }
        var desk = world[key] ?? Desk()
        if desk.desktop.contains(window) { try desk.desktop.remove(window) } else if desk.tree.state(of: window) != nil { try desk.tree.remove(window) }
        try desk.tree.setDesktopHidden(false)
        return try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).desktopRect
    }

    /// A tear-off with no dock or group target: the float, its landing frame shown as the clamp ghost (always, since
    /// the window is not under the pointer). Back over the strip: no preview.
    func tearOffMiss(_ hover: Hover, window: WindowRef) -> Decision {
        guard !hover.overStrip, let uuid = hover.displayUUID, let display = displays.first(where: { $0.uuid == uuid }) else {
            return Decision(action: .miss)
        }
        let key = Self.key(display)
        do throws(LayoutError) {
            return Decision(action: .tearOffFloat(key), display: uuid, clampInto: try tearOffDesktop(window, on: key) ?? display.visibleFrame)
        } catch {
            return Decision(action: .miss)
        }
    }

    /// Esc: the tear-off ends with nothing changed; the rest of its press finds no session and does nothing.
    mutating func cancelTearOff() -> [ArrangerEffect] {
        tabs.tearPress = nil
        guard let group = drag?.tearOffGroup else { return [] }
        return endDrag() + [.tabAnnouncement(.tearOffCanceled), .info("group \(group.node): tear-off canceled (esc)")]
    }

    /// Mouse-up of a tear-off (UI-SPEC Surface 4 release table): over the source strip it cancels; otherwise exactly
    /// the decision shown (Dock, Group, a refusal), else the float at the landing frame under the pointer.
    mutating func releaseTearOff(_ session: DragSession) -> [ArrangerEffect] {
        guard case .tearOff(let group, let strip, _) = session.origin else { return [] }
        let window = session.window
        if strip.contains(session.pointer) { return [.info("group \(group.node): tear-off canceled (strip)")] }
        guard let ref = tabGroup(holding: window), ref.key == group else { return replan() }
        tabs.tearing = window  // the commit takes the tab alone
        defer { tabs.tearing = nil }
        let floatKey = displays.first { $0.frame.contains(session.pointer) }.map(Self.key)
        let action = session.current?.action ?? floatKey.map(DropAction.tearOffFloat) ?? .miss
        do throws(LayoutError) {
            switch action {
            case .tearOffFloat(let key):
                return try commitTearOff(window, from: ref, landing: session.landingFrame(at: session.pointer), on: key)
            case .dock(let key, let target):
                let effects = try commitDock(window, on: key, at: target)
                guard tabGroup(holding: window)?.key != ref.key else { return effects }  // refused: still in the group
                return effects + movedOut(window, from: ref, landed: "docked")
            case .group(let key, let target):
                return try commitGroup(window, on: key, into: target)
            case .refuse(let text):
                return [.announce(text)]
            case .miss, .swap, .undock:
                return []
            }
        } catch {
            return [.fault("group \(group.node): tear-off of \(window) failed: \(error)")] + replan()
        }
    }

    /// The float: `window` leaves its group and floats at `landing` clamped into the Desktop of `key`'s desk, a hidden
    /// Desktop shown first (D-31). One undo step; raised and focused.
    mutating func commitTearOff(
        _ window: WindowRef, from ref: TabGroupRef, landing: Rect, on key: DeskKey, via source: String = "tear-off"
    ) throws(LayoutError) -> [ArrangerEffect] {
        guard let from = deskKey(of: window), let area = display(for: key)?.visibleFrame else { return replan() }
        let show = showingDesktop(), gap = gap, mins = minimums
        var frame = landing
        if from != key {
            // Leaving another display's desk is a fact of where it was dropped, not a second undo step.
            try world.reflow(from) { desk, _ throws(LayoutError) in
                if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
            }
            if world[key] == nil { try world.addDesk(key) }
        }
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            if from == key {
                if desk.desktop.contains(window) { try desk.desktop.remove(window) } else { try desk.tree.remove(window) }
            }
            if desk.tree.isDesktopHidden == true { try show(&desk, &ids) }
            frame = Planner.clamp(landing, into: try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).desktopRect ?? area)
            try desk.desktop.add(window, frame: frame)
        }
        wantedFrames[window.identity] = frame
        lastRequested[window.identity] = nil
        return replan() + [.perform([.raise(window), .focus(window)])] + movedOut(window, from: ref, landed: "floating", via: source)
    }

    /// "Moved out of the tab group", joined with "Tab group ended" when that dissolved it (D-12), and the Leave log line.
    func movedOut(_ window: WindowRef, from ref: TabGroupRef, landed: String, via source: String = "tear-off") -> [ArrangerEffect] {
        let ended = dissolved(ref, losing: window).filter { if case .tabAnnouncement = $0 { false } else { true } }
        return [.tabAnnouncement(.movedOut(dissolved: !ended.isEmpty)), .info("group \(ref.key.node): \(window) moved out via \(source), landed \(landed)")]
            + ended
    }
}

/// Move Out of Group (D-11, UI-SPEC Surface 4): the member floats beside its group.
extension Arranger {
    /// The gap between the group and the moved-out window, and the cascade offset when neither side has room.
    static let moveOutGap = 8.0, moveOutCascade = 24.0

    /// Where a moved-out window of `size` lands: 8 pt right of `group`, top edges aligned; else 8 pt left; else its
    /// top-left 24 pt right of and below the group's. A side "fits" when it lies inside `desktop`; the result is clamped.
    static func moveOutFrame(size: Size, group: Rect, desktop: Rect) -> Rect {
        func inside(_ r: Rect) -> Bool { r.minX >= desktop.minX && r.maxX <= desktop.maxX && r.minY >= desktop.minY && r.maxY <= desktop.maxY }
        let right = Rect(x: group.maxX + moveOutGap, y: group.minY, width: size.width, height: size.height)
        if inside(right) { return right }
        let left = Rect(x: group.minX - moveOutGap - size.width, y: group.minY, width: size.width, height: size.height)
        if inside(left) { return left }
        let cascade = Rect(x: group.minX + moveOutCascade, y: group.minY + moveOutCascade, width: size.width, height: size.height)
        return Planner.clamp(cascade, into: desktop)
    }

    /// Move Out of Group: `member` leaves its group and floats at `moveOutFrame` (its saved pre-group size, else the
    /// content size), a hidden Desktop shown first; raised and focused. One undo step (the tear-off float commit).
    mutating func moveOut(_ member: WindowRef, via source: TabLeaveSource, ready: Bool) -> [ArrangerEffect] {
        guard pauseReasons.isEmpty, !sessionPaused else { return refuse(.paused, "move out \(member)", "arranging is paused") }
        guard ready else { return refuse(.notReady, "move out \(member)", "Accessibility is not ready") }
        guard let ref = tabGroup(holding: member), let content = contentRect(of: ref) else {
            return refuse(.notInGroup, "move out \(member)", "not in a tab group")
        }
        let key = ref.key.desk
        let size = wantedFrames[member.identity]?.size ?? content.size
        do throws(LayoutError) {
            guard let desktop = try tearOffDesktop(member, on: key) else { return [.beep] }
            let landing = Self.moveOutFrame(size: size, group: TabBand.frame(ofContent: content), desktop: desktop)
            return try commitTearOff(member, from: ref, landing: landing, on: key, via: "\(source)")
        } catch {
            return [.beep, .fault("group \(ref.key.node): move out of \(member) failed: \(error)")] + replan()
        }
    }
}

/// Restore All Windows and tab groups (D-07, RESEARCH Pitfall 3): groups dissolve before the rescue, or the replan
/// would park their hidden members again.
extension Arranger {
    /// Dissolves every group on every desk, one undo step per desk holding groups (in key order), a hidden Desktop
    /// shown first. The selected member keeps the group's place: its tile (a plain panel under the same NodeID), or the
    /// whole floating frame (the band returns). The others float at the content size, top-lefts 24 pt apart from the
    /// group frame's top-left, clamped inside the Desktop tile. Returns the groups dissolved, the members floated, and a
    /// fault per desk that could not be dissolved (it keeps its groups, so the rest of Restore All still runs).
    mutating func dissolveAllGroups() -> (groups: Int, windows: [WindowRef], faults: [ArrangerEffect]) {
        var groups = 0, floated: [WindowRef] = [], faults: [ArrangerEffect] = []
        for (key, desk) in world.desks.sorted(by: { $0.key < $1.key }) {
            guard !desk.desktop.groups.isEmpty || desk.tree.nodes.values.contains(where: { if case .tabs = $0 { true } else { false } }) else { continue }
            // shortcut: a desk whose display is gone keeps its groups; its members are rescued as stranded windows.
            guard let area = displays.first(where: { $0.uuid == key.displayUUID })?.visibleFrame else { continue }
            let mins = minimums, gap = gap, show = showingDesktop()
            guard let tiles = try? Planner.plan(desk: desk, area: area, gap: gap, mins: mins).resolution.nodeRects else {
                faults.append(.fault("restore all: could not plan \(key) to dissolve its groups"))
                continue
            }
            // A docked group with no planned tile (its selected member absent, 07-05) stays; its hidden members are not
            // parked then, and the rescue brings a stranded one back.
            let docked = desk.tree.nodes.compactMap { id, node -> (NodeID, [WindowRef], Int, Rect)? in
                if case .tabs(let members, let selected) = node, let tile = tiles[id] { (id, members, selected, tile) } else { nil }
            }.sorted { $0.0 < $1.0 }
            guard !docked.isEmpty || !desk.desktop.groups.isEmpty else { continue }
            var moved: [WindowRef: Rect] = [:]
            do throws(LayoutError) {
                try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
                    try Self.dissolve(docked, on: &desk, ids: &ids, area: area, gap: gap, mins: mins, show: show, moved: &moved)
                }
            } catch {
                faults.append(.fault("restore all: could not dissolve the groups of \(key): \(error)"))
                continue
            }
            groups += docked.count + desk.desktop.groups.count
            for (member, rect) in moved.sorted(by: { $0.key.identity < $1.key.identity }) {
                wantedFrames[member.identity] = rect
                lastRequested[member.identity] = nil
                floated.append(member)
            }
        }
        return (groups, floated, faults)
    }

    /// One desk's dissolve (`dissolveAllGroups`): `docked` groups with their tiles, then every floating group.
    private static func dissolve(
        _ docked: [(NodeID, [WindowRef], Int, Rect)], on desk: inout Desk, ids: inout IDSource, area: Rect, gap: Double,
        mins: [WindowRef: Size], show: (inout Desk, inout IDSource) throws(LayoutError) -> Void, moved: inout [WindowRef: Rect]
    ) throws(LayoutError) {
        if desk.tree.isDesktopHidden == true { try show(&desk, &ids) }
        var cascade: [(WindowRef, WindowState?, frame: Rect, n: Int)] = []
        for (_, members, selected, frame) in docked {
            for (n, member) in members.enumerated().filter({ $0.offset != selected }).map(\.element).enumerated() {
                cascade.append((member, desk.tree.state(of: member), frame, n + 1))
                try desk.tree.remove(member)
            }
        }
        for group in desk.desktop.groups {
            let (removed, states) = try desk.desktop.removeGroup(group.id)
            let selected = removed.members[removed.selected]
            try desk.desktop.add(selected, frame: removed.frame)
            if let state = states[selected.identity], state != .present { try desk.desktop.setState(state, for: selected) }
            for (n, member) in removed.members.filter({ $0 != selected }).enumerated() {
                cascade.append((member, states[member.identity], removed.frame, n + 1))
            }
        }
        let desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).desktopRect ?? area
        for (member, state, frame, n) in cascade {
            let content = TabBand.content(of: frame), step = Self.moveOutCascade * Double(n)
            let rect = Planner.clamp(Rect(x: frame.minX + step, y: frame.minY + step, width: content.width, height: content.height), into: desktop)
            try desk.desktop.add(member, frame: rect)
            if let state, state != .present { try desk.desktop.setState(state, for: member) }
            moved[member] = rect
        }
    }
}

/// Relaunch with tab groups (D-13, UI-SPEC "Relaunch with a member missing").
extension Arranger {
    /// One line per saved group that lost members to windows gone since the last session; silent otherwise. The close
    /// path already re-formed it without them (or dissolved it, or removed it). NodeIDs and counts only.
    func regroupedLog(saved: World) -> [ArrangerEffect] {
        let held = Set(world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) })
        return saved.desks.sorted { $0.key < $1.key }.flatMap { _, desk in
            let docked = desk.tree.nodes.compactMap { id, node -> (NodeID, [WindowRef])? in
                if case .tabs(let members, _) = node { (id, members) } else { nil }
            }
            return (docked + desk.desktop.groups.map { ($0.id, $0.members) }).sorted { $0.0 < $1.0 }.compactMap { id, members -> ArrangerEffect? in
                let left = members.filter(held.contains).count
                return left < members.count ? .info("relaunch: group \(id) re-formed with \(left) of \(members.count) members") : nil
            }
        }
    }
}
