import TransomModel

/// A saved window waiting to come back (VIEW-04, D-10 to D-12a): an untracked ref kept in the World, so its tile stays
/// reserved and gets no write, with a deadline on the Arranger's wake clock, so it can never become a permanent hole.
public struct Placeholder: Equatable, Sendable {
    public enum Origin: Equatable, Sendable {
        case launch, appQuit, tie
    }

    public var ref: WindowRef
    public var origin: Origin
    public var deadline: ContinuousClock.Instant
    /// The size the window refused to go below, so its tile, and with it the neighbours, stay as they were.
    public var minimum: Size?

    public var bundleID: String { ref.bundleID }
}

/// Every window waiting to come back, the apps that just quit, and the windows that may fill them.
public struct PlaceholderState: Sendable {
    var table: [WindowIdentity: Placeholder] = [:]
    /// The apps `.appTerminated` reported, for the `.windowDestroyed` of each of their windows that follows.
    var quitting: [Int32: (bundleID: String, at: ContinuousClock.Instant)] = [:]
    /// Windows that may fill a placeholder: created after the app's placeholders appeared and not touched by the user.
    var fresh: Set<WindowIdentity> = []

    func waits(for bundleID: String) -> Bool { table.values.contains { $0.bundleID == bundleID } }

    /// After a World change: what no desk holds any more waits for nothing, and a docked or grouped window is the user's.
    mutating func prune(_ world: World) {
        table = table.filter { id, _ in world.desks.values.contains { $0.contains(WindowRef(identity: id)) } }
        fresh = fresh.filter { id in
            let window = WindowRef(identity: id)
            return waits(for: id.bundleID) && !world.desks.values.contains { $0.tree.state(of: window) != nil || $0.desktop.group(containing: window) != nil }
        }
    }
}

extension Arranger {
    /// How long a quit app's placeholders wait with no relaunch (D-12a).
    public static let quitWait: Duration = .seconds(30)
    /// How long placeholders wait after their app launched or opened its latest window (D-12).
    public static let launchWait: Duration = .seconds(10)
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

    /// A docked window of a quitting app keeps its tile (D-12a); nil when `window` closes as usual (⌘W, or a floater).
    /// The ref keeps the latest title, which the matcher and layout.json need once `windows` has forgotten it.
    mutating func holdForQuit(_ window: WindowRef) throws(LayoutError) -> [ArrangerEffect]? {
        guard let quit = placeholders.quitting[window.pid], let key = deskKey(of: window), let leaf = world[key]?.tree.leaf(containing: window)
        else { return nil }
        let info = windows[window.identity], ref = info?.window ?? window
        world = world.refreshingTitles([ref.identity: ref.titleHint])
        placeholders.table[ref.identity] = Placeholder(ref: ref, origin: .appQuit, deadline: quit.at + Self.quitWait, minimum: info?.learnedMinimum)
        try selectNeighbour(ofAbsent: ref)
        return [.info("placeholder \(leaf) for \(ref.bundleID): shown (app quit)")] + fillPlaceholders(of: ref.bundleID)
    }

    /// A new window of an app with waiting (or about to wait) placeholders may fill one.
    mutating func noteCreated(_ info: WindowInfo) {
        let bundle = info.window.bundleID
        guard info.kind == .dockable, placeholders.waits(for: bundle) || placeholders.quitting.values.contains(where: { $0.bundleID == bundle })
        else { return }
        placeholders.fresh.insert(info.window.identity)
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
            saved: waiting.map { HintMatcher.Saved(ref: $0.ref, frame: frames[$0.ref.identity]) },
            candidates: candidates.map { HintMatcher.Candidate(ref: $0.window, frame: $0.frame) })
        var effects: [ArrangerEffect] = []
        for match in assigned.matches {
            let tile = tileName(of: match.saved)
            do throws(LayoutError) {
                try world.adopt(match.saved, by: match.window, history: &history)
                placeholders.table[match.saved.identity] = nil
                placeholders.fresh.remove(match.window.identity)
                forget(match.saved)
                remapViews(from: match.saved.identity, to: match.window.identity)
                lastRequested[match.window.identity] = nil
                if wantedFrames[match.window.identity] == nil { wantedFrames[match.window.identity] = windows[match.window.identity]?.frame }
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
