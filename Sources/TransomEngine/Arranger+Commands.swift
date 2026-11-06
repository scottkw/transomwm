import TransomModel

/// The keyboard layout commands (TILE-11 to 14, TILE-16). Each user edit is one `World.edit`, dry-run first, so a
/// refusal changes nothing (D-26); a floating window's snap is a frame fact with no undo step (TILE-07).
extension Arranger {
    /// Grow Tile and Shrink Tile move this fraction of the split's length (UI-SPEC Surface 6).
    static let resizeStep = 0.1

    /// Moves a docked window into the tile across `edge`, docking it on that tile's near edge (D-11, TILE-13), or
    /// snaps a floating one to that half of the Desktop tile (TILE-14). No neighbour: beep.
    mutating func moveOrSnap(_ window: WindowRef, toward edge: Edge) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        if desk.desktop.contains(window) { return try snap(window, to: edge.half) }
        let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
        guard let leaf = desk.tree.leaf(containing: window), let rect = resolution.nodeRects[leaf],
            let neighbour = Neighbours.neighbour(
                of: rect, excluding: leaf, toward: edge, tree: desk.tree, resolution: resolution, gap: gap, recency: recency(on: desk))
        else { return [.beep] }
        // A sibling's near edge is the window's own slot, so docking there changes nothing: it goes past the sibling.
        let side = desk.tree.parent(of: leaf) == desk.tree.parent(of: neighbour) ? edge : edge.opposite
        // The neighbour's NodeID survives the remove: only splits collapse. A tab group moves as its whole leaf.
        return try commit(key, flashing: window, collapsible: true) { desk, ids throws(LayoutError) in
            let taken = try desk.tree.removeLeaf(leaf)
            try desk.tree.insertLeaf(taken.node, states: taken.states, at: side, of: neighbour, ids: &ids)
        }
    }

    /// Docks `window`, or moves it if docked, to a share of the whole desk (D-14, D-15): one undo step. A group member
    /// moves its whole group. Without room it collapses with zoom on, and with zoom off it is refused and changes
    /// nothing (D-16). A docked window already there only beeps; `commit` can't tell, because it compares rects by node
    /// and the new leaf has a new ID.
    mutating func dockFourth(_ window: WindowRef, slot: FourthSlot, axis: Axis) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        let group = tabGroup(holding: window)
        let shown = group.map { $0.members[$0.selected] } ?? window
        let candidate = try dropping(window, on: key, at: .fourth(slot, axis), moving: group)
        guard let edited = candidate.world[key], let label = candidate.fourthLabel else { return [.beep] }
        let plan = try Planner.plan(desk: edited, area: area, gap: gap, mins: minimums)
        let collapsed = plan.unfit.isEmpty ? nil : try collapse(edited, area: area)
        guard plan.unfit.isEmpty || collapsed != nil else {
            let loose = try Planner.plan(desk: edited, area: area, gap: gap, mins: [:])
            let frame = group == nil ? loose.frames[window] : edited.tree.leaf(containing: shown).flatMap { loose.resolution.nodeRects[$0] }
            return [.beep, .announce(Self.noRoom)] + (frame.map { [.flashBlocked($0, displayUUID: key.displayUUID)] } ?? [])
        }
        if collapsed == nil, try fourthChangesNothing(shown, on: desk, area: area, to: plan) { return [.beep] }
        world = candidate.world
        history = candidate.history
        lastRequested[window.identity] = nil  // settles exactly into the new tile
        let note = accept(collapsed, moving: shown)
        return widen(toShow: window, new: false) + replan() + (note.isEmpty ? [.announce(FourthCopy.docked(label))] : note)
    }

    /// `window` is already docked on `desk` and the edit moves no frame. `commit` can't tell, because the new leaf has a new
    /// ID. A floating window docking is a change even if no frame moves.
    func fourthChangesNothing(_ window: WindowRef, on desk: Desk, area: Rect, to plan: FramePlan) throws(LayoutError) -> Bool {
        guard desk.tree.state(of: window) != nil else { return false }
        return try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).frames == plan.frames
    }

    /// Restore All Windows (SAFE-03): every camera home first (D-D), then every stranded window back on screen, each
    /// rescued floater recorded at its rescue frame (a frame fact, no undo step). Runs while paused; N6 counts the windows
    /// moved, camera-parked ones included. Collapsed windows come back too and float with N1, as with zoom off (CR-01).
    /// Tab groups dissolve first (D-07), their hidden members floating beside the group and counted in N6.
    mutating func restoreAll() throws(LayoutError) -> [ArrangerEffect] {
        goHome()
        camera.collapsible = []  // else the replan parks them again in the same perform
        let dissolved = dissolveAllGroups()
        let log: [ArrangerEffect] = dissolved.groups == 0
            ? [] : [.info("restore all: dissolved \(dissolved.groups) groups, \(dissolved.windows.count) windows brought back")]
        // The dissolved members float at their cascade frames; the rescue would move them elsewhere.
        let moves = rescueStranded(desks: world, sparing: Set(dissolved.windows.map(\.identity)))
        for case .setFrame(let window, let frame) in moves where isFloating(window) { try world.recordFloatingFrame(frame, for: window) }
        let count = moves.count + dissolved.windows.count
        return dissolved.faults + (moves.isEmpty ? [] : [.perform(moves)]) + replan() + showBlocks([:]) + log + [.notice(.restored(count: count))]
    }

    /// Snaps a floating window to `target` inside the Desktop tile (TILE-14): a frame fact, no undo step. A floating
    /// group's member snaps the group frame, band included (UI-SPEC Surface 5).
    mutating func snap(_ window: WindowRef, to target: SnapTarget) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let frame = desk.desktop.frame(of: window),
            let area = display(for: key)?.visibleFrame,
            let desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).desktopRect
        else { return [.beep] }
        let group = desk.desktop.group(containing: window)
        let snapped = Snap.frame(target, window: group?.frame ?? frame, desktop: desktop, gap: gap)
        let shown = group.map { $0.members[$0.selected] } ?? window, content = group == nil ? snapped : TabBand.content(of: snapped)
        try world.recordFloatingFrame(content, for: shown)
        wantedFrames[shown.identity] = content
        return replan()
    }

    /// Swaps a docked window with the docked panel focused before it on its desk (TILE-11). None: beep.
    mutating func swapPrevious(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect] {
        guard let other = previousDocked(before: window), let key = deskKey(of: window) else { return [.beep] }
        return try commit(key, flashing: window) { desk, _ throws(LayoutError) in try desk.tree.swap(window, other) }
    }

    /// Grows (positive) or shrinks the window's tile by `delta` of its split's length, from or to its siblings
    /// (TILE-13). At a size limit, where no rect would change, it beeps and pushes no undo step.
    mutating func resize(_ window: WindowRef, by delta: Double) throws(LayoutError) -> [ArrangerEffect] {
        guard let (key, split, index) = parentSplit(of: window) else { return [.beep] }
        do {
            return try commit(key, flashing: window, refusingNoChange: true) { desk, _ throws(LayoutError) in
                try desk.tree.resizeChild(in: split, index: index, by: delta)
            }
        } catch {
            if case .atSizeLimit = error { return [.beep] }
            throw error
        }
    }

    /// Balance, rotate or flip with the window's parent split, as one undo step (TILE-12). Rotate turns the whole
    /// layout from the root whichever split it is given (03-02).
    mutating func editSplit(
        of window: WindowRef, _ edit: (inout LayoutTree, NodeID) throws(LayoutError) -> Void
    ) throws(LayoutError) -> [ArrangerEffect] {
        guard let (key, split, _) = parentSplit(of: window) else { return [.beep] }
        return try commit(key, flashing: window) { desk, _ throws(LayoutError) in try edit(&desk.tree, split) }
    }

    /// Docks every eligible floating window of the target desk in screen order (top to bottom, then left to right),
    /// each on the longer side of the largest tile (on an empty desk the first becomes the root), as one undo step
    /// (TILE-16, D-13). A window whose dry run leaves
    /// any window without room stays floating, and N5 counts them; when none docks: beep, and the first one's
    /// blocked frame flashes.
    mutating func arrangeAll(_ focused: WindowRef?) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        // A floating group docks as one leaf, standing in the order and the count as its selected member (Surface 5).
        let order = desk.desktop.windows.filter { floating in
            floating.state == .present && !isHiddenTab(floating.window)
                && windows[floating.window.identity].map { $0.kind == .dockable && !$0.isExcluded && $0.state == .present } == true
        }
        .sorted { ($0.frame.minY, $0.frame.minX, $0.window.identity) < ($1.frame.minY, $1.frame.minX, $1.window.identity) }
        .map(\.window)
        guard !order.isEmpty else { return [.beep] }
        let gap = gap, mins = minimums
        var skipped = 0
        var blocked: Rect?
        var candidate = world, candidateHistory = history
        try candidate.edit(key, history: &candidateHistory) { desk, ids throws(LayoutError) in
            for window in order {
                var trial = desk, trialIDs = ids
                let node: Node, states: [WindowIdentity: WindowState]
                if let group = trial.desktop.group(containing: window) {
                    let removed = try trial.desktop.removeGroup(group.id)
                    (node, states) = (.tabs(windows: removed.group.members, selected: removed.group.selected), removed.states)
                } else {
                    try trial.desktop.remove(window)
                    (node, states) = (.panel(window), [window.identity: .present])
                }
                if trial.tree.root == nil {
                    try trial.tree.applyDrop(.emptyLayout, leaf: node, states: states, ids: &trialIDs)
                } else {
                    let resolution = try Planner.plan(desk: trial, area: area, gap: gap, mins: mins).resolution
                    guard let (target, rect) = Self.largestTile(resolution, in: trial.tree) else {
                        skipped += 1
                        continue
                    }
                    do {
                        try trial.tree.insertLeaf(node, states: states, at: rect.width >= rect.height ? .right : .bottom, of: target, ids: &trialIDs)
                    } catch {
                        skipped += 1  // a full split
                        continue
                    }
                }
                if try Planner.plan(desk: trial, area: area, gap: gap, mins: mins).unfit.isEmpty {
                    desk = trial
                    ids = trialIDs
                } else {
                    skipped += 1
                    if blocked == nil {
                        let loose = try Planner.plan(desk: trial, area: area, gap: gap, mins: [:])
                        blocked = trial.tree.leaf(containing: window).flatMap { loose.resolution.nodeRects[$0] }
                    }
                }
            }
        }
        guard skipped < order.count else { return [.beep] + (blocked.map { [.flashBlocked($0, displayUUID: key.displayUUID)] } ?? []) }
        world = candidate
        history = candidateHistory
        return replan() + (skipped == 0 ? [] : [.notice(.arrangeLeftovers(count: skipped))])
    }

    /// Floats every docked window of the target desk at its tile rect, clamped into the Desktop that leaves, as one
    /// undo step that also shows a hidden Desktop (TILE-16). N4 says how many. Nothing docked: beep.
    mutating func floatAll(_ focused: WindowRef?) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = targetKey(focused), let desk = world[key], let area = display(for: key)?.visibleFrame, !desk.tree.windows.isEmpty
        else { return [.beep] }
        let plan = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums)
        // One unit per leaf in tree order: a tab group floats as one group at its group frame and counts once (Surface 5).
        var leaves: [NodeID] = []
        for window in desk.tree.windows {
            if let leaf = desk.tree.leaf(containing: window), !leaves.contains(leaf) { leaves.append(leaf) }
        }
        let docked = leaves.map { leaf -> (NodeID, Rect) in
            let shown: WindowRef? = switch desk.tree.node(leaf) {
            case .panel(let window)?: window
            case .tabs(let members, let selected)?: members[selected]
            default: nil
            }
            let grouped = if case .tabs? = desk.tree.node(leaf) { true } else { false }
            let actual = shown.flatMap { windows[$0.identity]?.frame }.map { grouped ? TabBand.frame(ofContent: $0) : $0 }
            return (leaf, plan.resolution.nodeRects[leaf] ?? actual ?? area)
        }
        let gap = gap, mins = minimums, show = showingDesktop()
        var shown: [WindowRef] = []
        try world.edit(key, history: &history) { desk, ids throws(LayoutError) in
            if desk.tree.isDesktopHidden == true { try show(&desk, &ids) }
            var taken: [NodeID: (node: Node, states: [WindowIdentity: WindowState])] = [:]
            for (leaf, _) in docked { taken[leaf] = try desk.tree.removeLeaf(leaf) }  // leaf IDs survive: only splits collapse
            let desktop = try Planner.plan(desk: desk, area: area, gap: gap, mins: mins).desktopRect ?? area
            for (leaf, tile) in docked {
                guard let (node, states) = taken[leaf] else { continue }
                switch node {
                case .panel(let window):
                    try desk.desktop.add(window, frame: Planner.clamp(tile, into: desktop))
                    if let state = states[window.identity], state != .present { try desk.desktop.setState(state, for: window) }
                    shown.append(window)
                case .tabs(let members, let selected):
                    let group = FloatingTabGroup(id: try ids.make(), members: members, selected: selected, frame: Planner.clamp(tile, into: desktop))
                    try desk.desktop.addGroup(group, states: states)
                    shown.append(members[selected])
                case .split, .desktop: throw .notALeaf(leaf)
                }
            }
        }
        for window in shown {
            undockedWanted[window.identity] = wantedFrames[window.identity]
            wantedFrames[window.identity] = world[key]?.desktop.frame(of: window)
        }
        return replan() + [.notice(.floatedAll(count: shown.count))]
    }

    /// The largest placed leaf (the Desktop tile included); ties go to the smaller NodeID.
    static func largestTile(_ resolution: Resolution, in tree: LayoutTree) -> (NodeID, Rect)? {
        let leaves = resolution.nodeRects.filter { if case .split? = tree.node($0.key) { false } else { true } }
        return leaves.max { ($0.value.width * $0.value.height, $1.key) < ($1.value.width * $1.value.height, $0.key) }
            .map { ($0.key, $0.value) }
    }

    /// The docked panel focused most recently before `window` on its desk, when `window` is present and docked; a tab
    /// group's window swaps its whole leaf with that panel (two groups never swap, UI-SPEC Surface 5).
    func previousDocked(before window: WindowRef) -> WindowRef? {
        guard let key = deskKey(of: window), let tree = world[key]?.tree, tree.state(of: window) == .present else { return nil }
        return focusOrder.lazy.filter { $0 != window.identity }
            .compactMap { id in tree.windows.first { $0.identity == id } }
            .first { Self.isPresentPanel($0, in: tree) }
    }

    /// The split holding a present docked window's leaf, and the leaf's index in it.
    func parentSplit(of window: WindowRef) -> (key: DeskKey, split: NodeID, index: Int)? {
        guard let key = deskKey(of: window), let tree = world[key]?.tree, tree.state(of: window) == .present,
            let leaf = tree.leaf(containing: window), let split = tree.parent(of: leaf),
            case .split(_, let children, _)? = tree.node(split), let index = children.firstIndex(of: leaf)
        else { return nil }
        return (key, split, index)
    }

    private static func isPresentPanel(_ window: WindowRef, in tree: LayoutTree) -> Bool {
        guard tree.state(of: window) == .present, let leaf = tree.leaf(containing: window), case .panel? = tree.node(leaf) else { return false }
        return true
    }

    /// Applies `change` to `key`'s desk as one undo step, unless the result leaves a window without room: then it
    /// beeps, announces it and flashes the blocked preview at `window`'s would-be frame, changing nothing (D-26).
    /// With `refusingNoChange`, an edit that leaves every rect where it was only beeps. With `collapsible` (Move Window,
    /// CONTEXT E) and zoom on, an edit leaving windows without room is accepted and they collapse (D-A).
    private mutating func commit(
        _ key: DeskKey, flashing window: WindowRef, refusingNoChange: Bool = false, collapsible: Bool = false,
        _ change: (inout Desk, inout IDSource) throws(LayoutError) -> Void
    ) throws(LayoutError) -> [ArrangerEffect] {
        guard let area = display(for: key)?.visibleFrame, let desk = world[key] else { return [.beep] }
        var candidate = world, candidateHistory = history
        try candidate.edit(key, history: &candidateHistory, change)
        guard let edited = candidate[key] else { return [.beep] }
        let plan = try Planner.plan(desk: edited, area: area, gap: gap, mins: minimums)
        let collapsed = plan.unfit.isEmpty || !collapsible ? nil : try collapse(edited, area: area)
        guard plan.unfit.isEmpty || collapsed != nil else {
            let frame = try Planner.plan(desk: edited, area: area, gap: gap, mins: [:]).frames[window]
            return [.beep, .announce(Self.noRoom)] + (frame.map { [.flashBlocked($0, displayUUID: key.displayUUID)] } ?? [])
        }
        if refusingNoChange, try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution == plan.resolution {
            return [.beep]
        }
        world = candidate
        history = candidateHistory
        let note = accept(collapsed, moving: window)
        return replan() + note
    }
}

extension Edge {
    fileprivate var opposite: Edge {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    /// The half of the Desktop tile ⌃⌥⌘⇧ and this arrow snap a floating window to.
    fileprivate var half: SnapTarget {
        switch self {
        case .left: .leftHalf
        case .right: .rightHalf
        case .top: .topHalf
        case .bottom: .bottomHalf
        }
    }
}
