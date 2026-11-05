import TransomModel

/// A saved window waiting to come back (VIEW-04, D-10 to D-12a): an untracked ref kept in the World, so its tile stays
/// reserved and gets no write, with a deadline on the Arranger's wake clock, so it can never become a permanent hole. A
/// tile on a desk not showing (another Space, a display not connected) has no hole to show and can't be filled, as AX lists
/// only what shows: its deadline waits until the desk shows (UI-SPEC Surface 2, CR-02). Only `.leftCGList` runs regardless.
/// shortcut: one on a Space that no longer exists waits in layout.json for good, unseen, like the dormant desk it is on;
/// prune it if the Spaces snapshot ever reaches the engine.
public struct Placeholder: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case launch, appQuit, tie
        /// A dormant docked window the CG list lost with no quit reported yet: closed, or its app is quitting.
        case leftCGList
    }

    /// Which deadline runs (D-12, D-12a), named as the expiry log says it.
    public enum Wait: String, Equatable, Sendable {
        case afterQuit = "30 s after quit", afterLaunch = "10 s after launch", neverOpened = "5 min, no launch", leftCGList = "10 s after leaving the CG list"
    }

    public var ref: WindowRef
    public var origin: Origin
    public var wait: Wait
    public var deadline: ContinuousClock.Instant
    /// When the app's launch or new windows first moved `deadline`, for `launchWaitLimit`.
    public var slideStart: ContinuousClock.Instant? = nil
    /// The size the window refused to go below, so its tile, and with it the neighbours, stay as they were.
    public var minimum: Size? = nil

    public var bundleID: String { ref.bundleID }
}

/// A tile held for a window that has not come back, in global top-left points. A group whose members all wait has one,
/// for its selected member, over the whole group frame.
public struct PlaceholderTile: Equatable, Sendable {
    public var window: WindowRef
    public var bundleID: String
    public var frame: Rect

    public init(window: WindowRef, frame: Rect) {
        self.window = window
        self.bundleID = window.bundleID
        self.frame = frame
    }
}

/// Every window waiting to come back, the apps that just quit, and the windows that may fill them.
public struct PlaceholderState: Sendable {
    var table: [WindowIdentity: Placeholder] = [:]
    /// The apps `.appTerminated` reported, for the `.windowDestroyed` of each of their windows that follows.
    var quitting: [Int32: (bundleID: String, at: ContinuousClock.Instant)] = [:]
    /// Windows that may fill a placeholder: created after the app's placeholders appeared and not touched by the user.
    var fresh: Set<WindowIdentity> = []
    /// Windows matched into a tile on another display, until their first write lands: `rehome` would float them (CR-03).
    var arriving: Set<WindowIdentity> = []
    /// The tiles last sent per display, so only a change is sent again.
    var shown: [String: [PlaceholderTile]] = [:]

    func waits(for bundleID: String) -> Bool { table.values.contains { $0.bundleID == bundleID } }

    /// The app launched or opened another window: its placeholders wait `launchWait` from now (D-12), up to
    /// `launchWaitLimit` after the first of these, so an app that keeps opening windows can't hold a tile for ever.
    mutating func restartLaunchWait(of bundleID: String, now: ContinuousClock.Instant) {
        for (id, placeholder) in table where placeholder.bundleID == bundleID {
            let start = placeholder.slideStart ?? now
            table[id]?.slideStart = start
            table[id]?.deadline = min(now + Arranger.launchWait, start + Arranger.launchWaitLimit)
            table[id]?.wait = .afterLaunch
        }
    }

    /// After a World change: what no desk holds any more waits for nothing, and a docked or grouped window is the user's.
    /// A window of an app still quitting stays fresh: its placeholders are about to appear (`holdForQuit`).
    mutating func prune(_ world: World) {
        table = table.filter { id, _ in world.desks.values.contains { $0.contains(WindowRef(identity: id)) } }
        let quittingBundles = Set(quitting.values.map(\.bundleID))
        fresh = fresh.filter { id in
            let window = WindowRef(identity: id)
            return (waits(for: id.bundleID) || quittingBundles.contains(id.bundleID))
                && !world.desks.values.contains { $0.tree.state(of: window) != nil || $0.desktop.group(containing: window) != nil }
        }
    }
}

extension Arranger {
    /// How long a quit app's placeholders wait with no relaunch (D-12a).
    public static let quitWait: Duration = .seconds(30)
    /// How long placeholders wait after their app launched or opened its latest window (D-12).
    public static let launchWait: Duration = .seconds(10)
    /// The most new windows can keep sliding `launchWait` (WR-04).
    public static let launchWaitLimit: Duration = .seconds(60)
    /// How long placeholders wait after Transom's launch for an app that never opens (D-12).
    public static let neverOpenedWait: Duration = .seconds(300)

    /// Whether `window` holds a tile for a window that has not come back.
    public func isPlaceholder(_ window: WindowRef) -> Bool {
        placeholders.table[window.identity] != nil && world.desks.values.contains { $0.tree.state(of: window) != nil }
    }

    /// The tiles held for windows that have not come back.
    public var placeholderCount: Int {
        placeholders.table.values.count { isPlaceholder($0.ref) }
    }

    /// The tiles held on desks now showing: what Clear Waiting Tiles would close (D-24).
    public var shownPlaceholderCount: Int { shownPlaceholders.count }

    /// shortcut: counts waiting windows, so a saved tab group is several "tiles" in the announcement; count leaves if that's noticed.
    private var shownPlaceholders: [Placeholder] {
        placeholders.table.values.filter { isPlaceholder($0.ref) && isOnShownDesk($0.ref) }
    }

    /// The desks on screen.
    var shownDesks: Set<DeskKey> { Set(displays.map(Self.key)) }

    /// Whether a display shows the desk holding `window`.
    private func isOnShownDesk(_ window: WindowRef) -> Bool {
        deskKey(of: window).map(shownDesks.contains) ?? true
    }

    /// Whether its deadline runs: one on a desk not showing waits, unless nothing says its app quit.
    private func deadlineRuns(_ placeholder: Placeholder) -> Bool {
        placeholder.origin == .leftCGList || isOnShownDesk(placeholder.ref)
    }

    /// The next placeholder due. One whose deadline isn't running is not, so a past deadline can't spin the wake clock.
    var earliestPlaceholderDeadline: ContinuousClock.Instant? {
        placeholders.table.values.filter(deadlineRuns).map(\.deadline).min()
    }

    /// A placeholder whose desk just came on screen gets at least `launchWait` for its window to be listed and match
    /// (CR-02). The deadlines of D-12 and D-12a only ever move later here.
    mutating func extendPlaceholdersShown(since previous: [DisplayInfo], now: ContinuousClock.Instant) {
        let before = Set(previous.map(Self.key))
        for (id, placeholder) in placeholders.table {
            guard let key = deskKey(of: placeholder.ref), !before.contains(key), isOnShownDesk(placeholder.ref) else { continue }
            placeholders.table[id]?.slideStart = nil  // what its app did while it was hidden doesn't count against it
            guard placeholder.deadline < now + Self.launchWait else { continue }
            placeholders.table[id]?.deadline = now + Self.launchWait
            placeholders.table[id]?.wait = .afterLaunch
        }
    }

    /// Each placeholder in these planned rects, collapsed ones included, in ID order.
    func placeholderTiles(frames: [WindowRef: Rect], collapsed: [WindowRef: Rect], resolution: Resolution) -> [PlaceholderTile] {
        frames.merging(collapsed) { frame, _ in frame }.filter { isPlaceholder($0.key) }
            .map { window, rect in
                PlaceholderTile(window: window, frame: tabGroup(holding: window).flatMap { resolution.nodeRects[$0.key.node] } ?? rect)
            }
            .sorted { $0.window.identity < $1.window.identity }
    }

    /// That display's placeholder tiles at home (the overview draws them), whatever the view.
    /// shortcut: a waiting window whose learned minimum no longer fits gets no tile here or in a zoomed plan until it
    /// expires (zoom off, planFloatingLostRoom relaxes it); relax it in ViewPlanner if that hole is ever noticed.
    public func homePlaceholders(on displayUUID: String) -> [PlaceholderTile] {
        guard !placeholders.table.isEmpty, let display = displays.first(where: { $0.uuid == displayUUID }), let desk = world[Self.key(display)],
            let plan = try? ViewPlanner.plan(
                desk: desk, view: .home, area: display.visibleFrame, gap: gap, mins: learnedMinimums, wanted: wantedFrames, collapsible: camera.collapsible)
        else { return [] }
        return placeholderTiles(frames: plan.frames, collapsed: plan.collapsed, resolution: plan.resolution)
    }

    /// `resolution` without the nodes holding only waiting windows, for what looks for a place to go: there is no window
    /// there to focus or zoom to (RESEARCH Pitfall 8). `keeping` stays, for the view the camera is already on.
    func withoutWaiting(_ resolution: Resolution, tree: LayoutTree, keeping: NodeID? = nil) -> Resolution {
        guard !placeholders.table.isEmpty else { return resolution }
        var kept = resolution
        kept.nodeRects = resolution.nodeRects.filter { id, _ in
            guard id != keeping, let sub = try? tree.subtree(at: id), sub.nodes[.desktop] == nil, !sub.windows.isEmpty else { return true }
            return !sub.windows.allSatisfy(isPlaceholder)
        }
        return kept
    }

    /// Sends each display's placeholder tiles that changed; a display with none (or gone) gets an empty list.
    mutating func showPlaceholders(_ tiles: [String: [PlaceholderTile]]) -> [ArrangerEffect] {
        let uuids = Set(tiles.keys).union(placeholders.shown.keys).sorted()
        return uuids.compactMap { uuid in
            let next = tiles[uuid] ?? []
            guard next != placeholders.shown[uuid] ?? [] else { return nil }
            placeholders.shown[uuid] = next.isEmpty ? nil : next
            return .placeholders(next, displayUUID: uuid)
        }
    }

    /// A docked window of a quitting app keeps its tile (D-12a); nil when `window` closes as usual (⌘W, or a floater).
    /// The ref keeps the latest real title, which the matcher and layout.json need once `windows` has forgotten it.
    mutating func holdForQuit(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect]? {
        guard let quit = placeholders.quitting[window.pid], let key = deskKey(of: window), let leaf = world[key]?.tree.leaf(containing: window)
        else { return nil }
        let info = windows[window.identity]
        var ref = info?.window ?? window
        if ref.titleHint.isEmpty, let held = world[key]?.tree.windows.first(where: { $0 == window }) { ref.titleHint = held.titleHint }
        world = world.refreshingTitles([ref.identity: ref.titleHint])
        placeholders.table[ref.identity] = Placeholder(
            ref: ref, origin: .appQuit, wait: .afterQuit, deadline: quit.at + Self.quitWait, minimum: info?.learnedMinimum)
        try selectNeighbour(ofAbsent: ref)
        return [.info("placeholder \(leaf) for \(ref.bundleID): shown (app quit)")] + fillPlaceholders(of: ref.bundleID)
    }

    /// The CG list can lose a quitting app's windows before `.appTerminated` arrives, so a dormant docked window it lost
    /// waits `launchWait`: the quit takes it over (D-12b), or it closes as the closed window it is.
    /// shortcut: a quit slower than that after its windows go still closes the tile, as WR-06 for a tracked window; check on ⌘Q.
    mutating func holdLeftCGList(_ left: [WindowRef], now: ContinuousClock.Instant) {
        for window in left where world.desks.values.contains(where: { $0.tree.leaf(containing: window) != nil }) {
            placeholders.table[window.identity] = Placeholder(ref: window, origin: .leftCGList, wait: .leftCGList, deadline: now + Self.launchWait)
        }
    }

    /// A new window of an app with waiting (or about to wait) placeholders may fill one, and restarts their 10 s (D-12).
    mutating func noteCreated(_ info: WindowInfo, now: ContinuousClock.Instant) {
        let bundle = info.window.bundleID
        guard info.kind == .dockable, placeholders.waits(for: bundle) || placeholders.quitting.values.contains(where: { $0.bundleID == bundle })
        else { return }
        placeholders.fresh.insert(info.window.identity)
        placeholders.restartLaunchWait(of: bundle, now: now)
    }

    /// The saved windows the launch could not attach wait (D-10, D-12): 10 s when their app already runs (a tracked window
    /// of the bundle), else 5 min. A tied window, or any other its app left unplaced, may match later as its title settles
    /// (RESEARCH Pitfall 4). A live member takes a waiting one's selection, so a group's tile shows what is there. A stored
    /// arrangement's tiles on desks not showing wait the same way (D-12b).
    mutating func holdAtLaunch(
        _ waiting: [WindowRef], tracked: [WindowInfo], unplaced: [WindowInfo], ties: [HintMatcher.Tie], now: ContinuousClock.Instant
    ) -> [ArrangerEffect] {
        let tied = Set(ties.flatMap(\.saved))
        let running = Set(tracked.map(\.window.bundleID))
        var faults: [ArrangerEffect] = []
        for window in waiting {
            let opened = running.contains(window.bundleID)
            placeholders.table[window.identity] = Placeholder(
                ref: window, origin: tied.contains(window) ? .tie : .launch, wait: opened ? .afterLaunch : .neverOpened,
                deadline: now + (opened ? Self.launchWait : Self.neverOpenedWait))
        }
        for window in waiting {
            do throws(LayoutError) { try selectNeighbour(ofAbsent: window) } catch {
                faults.append(.fault("could not select a live member beside \(window): \(error)"))
            }
        }
        placeholders.fresh.formUnion(ties.flatMap(\.candidates).map(\.identity))
        placeholders.fresh.formUnion(unplaced.filter { placeholders.waits(for: $0.window.bundleID) }.map(\.window.identity))
        return faults
    }

    /// Closes every placeholder past a running deadline through the close path, as if its window had closed
    /// (D-12): no undo step, and the neighbours reflow, whose writes wait out a pause (RESEARCH Pitfall 14).
    mutating func expirePlaceholders(now: ContinuousClock.Instant) -> [ArrangerEffect] {
        let due = placeholders.table.values.filter { now >= $0.deadline && deadlineRuns($0) }
        let effects = closePlaceholders(due) { "expired (\($0.wait.rawValue))" }
        placeholders.quitting = placeholders.quitting.filter { now < $0.value.at + Self.quitWait || placeholders.waits(for: $0.value.bundleID) }
        return effects
    }

    /// Clear Waiting Tiles (D-24): the tiles on the desks showing close as expiry closes them, with no undo step.
    /// Tiles on hidden desks still wait (D-12b). A floating saved window has no tile to clear.
    mutating func clearWaitingTiles() -> [ArrangerEffect] {
        let shown = shownPlaceholders
        guard !shown.isEmpty else { return [] }
        return closePlaceholders(shown) { _ in "cleared" } + [.announce(shown.count == 1 ? "Cleared 1 waiting tile" : "Cleared \(shown.count) waiting tiles")]
    }

    /// Takes `waiting` off the desks through the close path, as if each window had closed.
    private mutating func closePlaceholders(_ waiting: [Placeholder], logging outcome: (Placeholder) -> String) -> [ArrangerEffect] {
        guard !waiting.isEmpty else { return [] }
        var effects: [ArrangerEffect] = []
        for placeholder in waiting.sorted(by: { $0.ref.identity < $1.ref.identity }) {
            let tile = tileName(of: placeholder.ref)
            placeholders.table[placeholder.ref.identity] = nil
            forget(placeholder.ref)
            do throws(LayoutError) {
                _ = try LifecycleSync.handle(.windowDestroyed(placeholder.ref), world: &world, history: &history)
                effects.append(.info("placeholder \(tile) \(outcome(placeholder))"))
            } catch {
                effects.append(.fault("could not close the placeholder \(placeholder.ref): \(error)"))
            }
        }
        // The trim is for a pause, whose replan sends nothing: a closed tile goes at once, a filled one at Resume.
        return effects + replan() + showPlaceholders(placeholders.shown.mapValues { $0.filter { isPlaceholder($0.window) } })
    }

    /// Matches the app's waiting placeholders against its fresh windows, as the launch path does (D-11, HintMatcher), and
    /// moves each match into its tile: an OS fact, no undo step. A tie fills nothing; its windows stay floating and a later
    /// title may settle it (RESEARCH Pitfall 4). A committed match is never undone. Returns the log lines and faults.
    mutating func fillPlaceholders(of bundleID: String) -> [ArrangerEffect] {
        let waiting = placeholders.table.values.filter { $0.bundleID == bundleID }
        let candidates = placeholders.fresh.compactMap { windows[$0] }.filter {
            $0.window.bundleID == bundleID && $0.kind == .dockable && $0.state == .present && !$0.isExcluded && $0.window != drag?.window
        }
        guard !waiting.isEmpty, !candidates.isEmpty else { return [] }
        let frames = savedFrames(world)
        let assigned = HintMatcher.assign(
            saved: waiting.map { HintMatcher.Saved(ref: $0.ref, frame: frames[$0.ref.identity], desk: deskKey(of: $0.ref)) },
            candidates: candidates.map { HintMatcher.Candidate(ref: $0.window, frame: $0.frame, displayUUID: $0.displayUUID, spaces: $0.spaces) },
            shown: shownDesks)
        var effects: [ArrangerEffect] = []
        for match in assigned.matches {
            let tile = tileName(of: match.saved)
            let desk = deskKey(of: match.saved)
            do throws(LayoutError) {
                try world.adopt(match.saved, by: match.window, history: &history)
                if let desk, windows[match.window.identity]?.displayUUID != desk.displayUUID { placeholders.arriving.insert(match.window.identity) }
                placeholders.table[match.saved.identity] = nil
                placeholders.fresh.remove(match.window.identity)
                if camera.collapsible.contains(match.saved.identity) { camera.collapsible.insert(match.window.identity) }
                let wanted = wantedFrames[match.saved.identity], home = homeFrames[match.saved.identity]
                forget(match.saved)
                remapViews(from: match.saved.identity, to: match.window.identity)
                lastRequested[match.window.identity] = nil
                // What the saved window wanted before it docked, as a rekey keeps it (WR-10).
                wantedFrames[match.window.identity] = wanted ?? wantedFrames[match.window.identity] ?? windows[match.window.identity]?.frame
                if let home { homeFrames[match.window.identity] = home }
                try showLiveMember(of: match.window)
                effects.append(.info("placeholder \(tile) filled by window \(match.window.windowID)"))
            } catch {
                effects.append(.fault("could not fill the placeholder of \(match.saved) with \(match.window): \(error)"))
            }
        }
        for tie in assigned.ties {
            let new = tie.saved.filter { placeholders.table[$0.identity]?.origin != .tie }
            for window in new { placeholders.table[window.identity]?.origin = .tie }
            guard !new.isEmpty else { continue }
            let tied = tie.candidates.map { "\($0.windowID)" }.joined(separator: " and ")
            effects.append(.info("match \(bundleID): tie at \(tie.score) between windows \(tied); tile \(new.map(tileName).joined(separator: ", ")) waits, windows float"))
        }
        return effects
    }

    /// A group showing a window that has not come back shows a member that has.
    private mutating func showLiveMember(of window: WindowRef) throws(LayoutError) {
        guard let group = tabGroup(holding: window), placeholders.table[group.members[group.selected].identity] != nil else { return }
        try selectNeighbour(ofAbsent: group.members[group.selected])
    }

    private func tileName(of window: WindowRef) -> String {
        world.desks.values.lazy.compactMap { $0.tree.leaf(containing: window) }.first.map { "\($0)" } ?? "Desktop"
    }
}
