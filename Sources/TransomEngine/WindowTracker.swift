import TransomModel

/// Pure tracking core: turns `AppObservation`s into `WindowInfo`s and the `WindowEvent`s between them.
///
/// Shared by `AXWindowSystem` and `FakeWindowSystem`, so scenario tests run the production decisions.
/// Every known window's state and removal is decided by `CloseRule` (two sources, D-09); a window with no
/// answer counts as timed out and is left untouched. Windows are keyed by ID, never merged by frame, except that the
/// tabs of a native tab group are one window under its leader's identity (`TabGroupTracker`, D-08). A window's ID
/// only ever changes through `rekey(from:to:)`, reported as `windowRekeyed`.
public struct WindowTracker: Sendable {
    /// How long a window first seen outside the initial sweep settles before it is reported and classified.
    public let settleDelay: Duration
    public private(set) var windows: [WindowIdentity: WindowInfo] = [:]
    private var nextCreationOrder: UInt64 = 1
    /// First-sight times of windows withheld until they settle; never reported yet.
    private var pending: [WindowIdentity: ContinuousClock.Instant] = [:]
    /// The facts behind each window's kind at its last reliable observation. Absent = kind is provisional.
    private var lastReliable: [WindowIdentity: ClassificationFacts] = [:]
    /// Closed and not seen again. A closed window is removed, so a reused ID is always reported as a new window.
    private var closedIDs = ClosedIDCache()
    /// Apps NSWorkspace reported terminated that still have tracked windows.
    private var terminatedPIDs: Set<Int32> = []
    /// Windows whose last decision was `.recheck`, with how many in a row.
    private var rechecks: [WindowIdentity: Int] = [:]
    private var tabGroups = TabGroupTracker()
    /// Windows folded into another window's tab group, not destroyed yet: the group's shown tab and how many
    /// consecutive full refreshes they stayed folded under it.
    private var foldPending: [WindowIdentity: (shown: UInt32, refreshes: Int)] = [:]
    private var learner = MinimumSizeLearner()
    /// The exclusion list, lowercased (D-12).
    private var excluded: Set<String> = []
    /// Per-bundle minimums (D-13): the hints of earlier sessions plus the minimums learned in this one.
    private var bundleHints: [String: Size] = [:]
    /// The displays of the latest observation, so a frame write can place its window too.
    private var displays: [DisplayInfo] = []
    /// Quick follow-ups per window before it is left to the sweep: WindowServer drops a closed window a few
    /// hundred ms after AX reports it invalid, so the decision must be retried soon, but not forever.
    public static let maxQuickRechecks = 8

    private struct ClassificationFacts: Equatable, Sendable {
        var subrole: String?
        var layer: Int?
        var title: String
    }

    public init(settleDelay: Duration = .milliseconds(250)) {
        self.settleDelay = settleDelay
    }

    public mutating func ingest(_ app: AppObservation, context: ObservationContext) -> [WindowEvent] {
        closedIDs.purge(at: context.now)
        displays = context.displays
        var events: [WindowEvent] = []
        // Corrected IDs first, so the rest of this refresh sees each window under its new ID.
        for o in app.windows {
            guard let old = o.replacesWindowID, let new = o.windowID, old != new else { continue }
            let from = WindowIdentity(windowID: old, pid: app.pid, bundleID: app.bundleID)
            windows[from]?.idSource = o.idSource
            events += rekey(from: from, to: WindowIdentity(windowID: new, pid: app.pid, bundleID: app.bundleID))
        }
        var seen: Set<WindowIdentity> = []
        var created: Set<WindowIdentity> = []
        // Reported after CloseRule, so a window going fullscreen carries its new state with its new Space (WIN-07).
        var changed: [WindowIdentity] = []
        let cgByID = Dictionary(context.cgWindows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        // A failed AXWindows says nothing about which tab is showing, so groups are only re-resolved on a full answer.
        var tabs = TabResolution()
        if app.listFailure == nil {
            let visible = app.windows.compactMap { o -> (id: UInt32, frame: Rect, tabCount: Int)? in
                guard o.listedInAXWindows, case .success(let snapshot) = o.read, let id = o.windowID, let frame = snapshot.frame else { return nil }
                return (id: id, frame: frame, tabCount: snapshot.tabGroup?.tabCount ?? 1)
            }
            let tracked = windows.values.filter { $0.window.pid == app.pid }.sorted { $0.window.creationOrder < $1.window.creationOrder }.map(\.window.identity)
            let invalid = Set(app.windows.compactMap { o -> UInt32? in
                guard case .failure(.invalidElement) = o.read else { return nil }
                return o.windowID
            })
            tabs = tabGroups.update(pid: app.pid, bundleID: app.bundleID, visible: visible, cgWindows: context.cgWindows, tracked: tracked,
                                     spaces: context.windowSpaces, invalid: invalid, spaceChanged: context.spaceChanged,
                                     listed: Set(app.windows.compactMap { $0.listedInAXWindows ? $0.windowID : nil }))
            // Merged into another window's tab group: gone as a separate window once two consecutive refreshes with
            // the same shown tab agree, so one wrong fold never removes a live window (D-09).
            var folds: [WindowIdentity: (shown: UInt32, refreshes: Int)] = [:]
            // A Space switch without Space data decides no fold: the window may be live on the other Space.
            let holdFolds = context.spaceChanged && context.windowSpaces == nil
            for identity in tabs.folded {
                let shown = tabGroups.shownTab(containing: identity.windowID, pid: app.pid) ?? identity.windowID
                let previous = foldPending[identity]
                if holdFolds {
                    // Same shown tab: the count is kept, not advanced. Otherwise it starts at 1 at the next update.
                    if let previous, previous.shown == shown { folds[identity] = previous }
                    continue
                }
                let refreshes = previous?.shown == shown ? (previous?.refreshes ?? 0) + 1 : 1
                if refreshes >= 2, let info = remove(identity, at: context.now) {
                    events.append(.windowDestroyed(info.window))
                } else {
                    folds[identity] = (shown, refreshes)
                }
            }
            foldPending = foldPending.filter { $0.key.pid != app.pid }.merging(folds) { $1 }
        }
        // Probes of windows that left AXWindows only feed the close decision below.
        for observation in app.windows where observation.listedInAXWindows {
            // No ID: a non-window, or one the frame fallback could not identify this time.
            guard case .success(var snapshot) = observation.read, let windowID = observation.windowID else { continue }
            if let cg = cgByID[windowID] {
                snapshot.cg = CGWindowFact(layer: cg.layer, onScreen: cg.onScreen, alpha: cg.alpha)
            }
            // Non-windows such as Finder's desktop are never tracked.
            guard case .window(let classified, let reliable) = Classifier.classify(snapshot, bundleID: app.bundleID, appHidden: app.appHidden)
            else { continue }
            // A listed tab is its group's window (identity = leader); hidden tabs are never separate windows.
            let identity = tabs.groupFor[windowID] ?? WindowIdentity(windowID: windowID, pid: app.pid, bundleID: app.bundleID)
            // shortcut: two listed tabs of one group (mid drag-out) keep AX order, not the tracker's ranking; fine for one refresh.
            guard seen.insert(identity).inserted else { continue }
            let old = windows[identity]
            // A window whose frame could not be read is picked up by a later refresh.
            guard let frame = snapshot.frame ?? old?.frame else { continue }

            if old == nil, !context.initialSweep {
                // Titles and buttons arrive late, so a new window waits out the settle delay first.
                let firstSeen = pending[identity, default: context.now]
                guard context.now >= firstSeen + settleDelay else {
                    pending[identity] = firstSeen
                    continue
                }
                pending[identity] = nil
            }

            let facts = ClassificationFacts(subrole: snapshot.subrole, layer: snapshot.cg?.layer, title: observation.title)
            let kind: WindowKind
            if let old {
                kind = reliable ? Self.reclassify(old.kind, classified, snapshot, changed: lastReliable[identity].map { $0 != facts }) : old.kind
            } else {
                kind = classified
            }
            if reliable { lastReliable[identity] = facts }

            // A known window's state is decided by CloseRule below; a new one starts from its snapshot.
            let state: WindowState =
                old?.state
                ?? (snapshot.minimized == true || app.appHidden ? .absent : snapshot.fullScreen == true ? .fullscreen : .present)
            let ref = WindowRef(
                identity: identity, titleHint: observation.title, axIdentifier: snapshot.identifier,
                creationOrder: old?.window.creationOrder ?? nextCreationOrder
            )
            var info = old ?? WindowInfo(window: ref, frame: frame, state: state, displayUUID: nil)
            info.window = ref
            info.frame = frame
            info.state = state
            info.kind = kind
            info.idSource = observation.idSource
            info.visibleMemberID = windowID
            info.tabCount = tabs.tabCount[identity] ?? 1
            info.displayUUID = Coordinates.displayUUID(for: frame, among: context.displays)
            info.isExcluded = excluded.contains(identity.bundleID.lowercased())
            info.spaces = context.windowSpaces?[windowID]
            // Drift under a point keeps the old offset, so it never adds up unreported.
            if old == nil || Self.buttonMoved(old?.greenButton, snapshot.greenButton) { info.greenButton = snapshot.greenButton }
            if old == nil, let hint = bundleHints[identity.bundleID] {
                learner.seed(identity, minimum: hint)
                info.learnedMinimum = learner.minimum(for: identity)
                info.persistableMinimum = learner.persistableMinimum(for: identity)
            }
            // A refused write is learned once a refresh a second later still sees the window at its read-back size.
            if state == .present, let observed = snapshot.frame?.size,
               let minimum = learner.confirm(window: identity, observed: observed, at: context.now)
            {
                info.learnedMinimum = minimum
                info.persistableMinimum = learner.persistableMinimum(for: identity)
                // Later windows of this bundle start from it in this session too (REVIEW IN-04), but never from an
                // unmoved refusal's minimum: that may be one fixed-size window's size (CR-02).
                if let shared = info.persistableMinimum {
                    let hint = bundleHints[identity.bundleID] ?? shared
                    bundleHints[identity.bundleID] = Size(width: max(hint.width, shared.width), height: max(hint.height, shared.height))
                }
            }
            windows[identity] = info

            guard let old else {
                nextCreationOrder += 1
                created.insert(identity)
                closedIDs.remove(identity)  // a reused ID is this new window from now on
                events.append(.windowCreated(info))
                continue
            }
            // A tab switch: the group follows the shown tab and is never reported as closed and reopened.
            if old.visibleMemberID != windowID { events.append(.windowFocused(ref)) }
            if old.frame.origin != frame.origin { events.append(.windowMoved(ref, frame)) }
            if old.frame.size != frame.size { events.append(.windowResized(ref, frame)) }
            if old.window.titleHint != ref.titleHint || old.kind != kind || old.tabCount != info.tabCount
                || old.displayUUID != info.displayUUID || old.learnedMinimum != info.learnedMinimum
                || old.persistableMinimum != info.persistableMinimum || old.spaces != info.spaces
                || Self.buttonMoved(old.greenButton, info.greenButton)
            {
                changed.append(identity)
            }
        }
        learner.dropDue(pid: app.pid, at: context.now)
        let byID = Dictionary(app.windows.compactMap { o in o.windowID.map { ($0, o) } }, uniquingKeysWith: { a, b in a.listedInAXWindows ? a : b })
        let liveness: AppLiveness = terminatedPIDs.contains(app.pid) ? .terminated : .alive
        events += decide(pid: app.pid, app: liveness, context: context, skipping: created) { windowID in
            guard app.listFailure == nil, let observation = byID[windowID] else { return .timedOut }
            switch observation.read {
            case .success(let snapshot):
                return .valid(listed: observation.listedInAXWindows, minimized: snapshot.minimized == true,
                              appHidden: app.appHidden, fullScreen: snapshot.fullScreen == true)
            case .failure(.invalidElement): return .invalidElement
            case .failure(.cannotComplete): return .timedOut
            case .failure: return .otherFailure
            }
        }
        events += changed.compactMap { windows[$0].map { .windowChanged($0) } }
        // A pending window that left the list was never reported, so it is dropped silently.
        if app.listFailure == nil {
            for identity in pending.keys where identity.pid == app.pid && !seen.contains(identity) {
                pending[identity] = nil
            }
        }
        return events
    }

    /// The window known as `from` is the same window as `to` (a corrected ID, D-15): everything known about it moves
    /// to `to`, and it is reported as one windowRekeyed, never as destroyed and created. A window tracked under both IDs
    /// merges into the `to` entry with the older creation order and the larger minimum per axis. A tab of a group that
    /// is not the group's identity is renamed in the group; the group window showing it reports one windowChanged. A
    /// window not reported yet keeps its settle start under the new ID, silently. An unknown `from` changes nothing.
    public mutating func rekey(from: WindowIdentity, to: WindowIdentity) -> [WindowEvent] {
        guard from != to, from.pid == to.pid else { return [] }
        guard let moving = windows.removeValue(forKey: from) else {
            if let firstSeen = pending.removeValue(forKey: from) {
                pending[to] = min(pending[to] ?? firstSeen, firstSeen)
                return []
            }
            guard tabGroups.isKnownMember(from.windowID, pid: from.pid) else { return [] }
            tabGroups.rekey(pid: from.pid, from: from.windowID, to: to.windowID, newLeader: nil)
            guard let shown = windows.first(where: { $0.key.pid == from.pid && $0.value.visibleMemberID == from.windowID })?.key,
                  var info = windows[shown]
            else { return [] }
            info.visibleMemberID = to.windowID
            windows[shown] = info
            return [.windowChanged(info)]
        }
        tabGroups.rekey(pid: from.pid, from: from.windowID, to: to.windowID, newLeader: to)
        let old = moving.window
        let merging = windows[to] != nil
        var info = windows[to] ?? moving
        info.window = WindowRef(
            identity: to, titleHint: info.window.titleHint, axIdentifier: info.window.axIdentifier,
            creationOrder: min(old.creationOrder, info.window.creationOrder))
        if info.visibleMemberID == from.windowID { info.visibleMemberID = to.windowID }
        if !merging {
            lastReliable[to] = lastReliable[from]
            rechecks[to] = rechecks[from]
            foldPending[to] = foldPending[from]
        }
        (lastReliable[from], rechecks[from], foldPending[from], pending[from]) = (nil, nil, nil, nil)
        learner.rekey(from: from, to: to)
        info.learnedMinimum = learner.minimum(for: to)
        info.persistableMinimum = learner.persistableMinimum(for: to)
        closedIDs.remove(to)
        windows[to] = info
        return [.windowRekeyed(from: old, to: info)]
    }

    /// NSWorkspace says `pid` quit. AX can no longer answer for it, so each window closes once it leaves the CG list.
    public mutating func appTerminated(pid: Int32, context: ObservationContext) -> [WindowEvent] {
        terminatedPIDs.insert(pid)
        for identity in pending.keys where identity.pid == pid { pending[identity] = nil }
        return decide(pid: pid, app: .terminated, context: context) { _ in .timedOut }
    }

    /// `pid` stopped being tracked without quitting (it is no longer a regular app): its windows are dropped and
    /// reported destroyed, so none waits forever on a thread that no longer refreshes it.
    public mutating func appStopped(pid: Int32) -> [WindowEvent] {
        for identity in pending.keys where identity.pid == pid { pending[identity] = nil }
        terminatedPIDs.remove(pid)
        tabGroups.forget(pid: pid)
        let now = ContinuousClock.now
        return windows.keys.filter { $0.pid == pid }.sorted().compactMap { remove($0, at: now).map { .windowDestroyed($0.window) } }
    }

    /// Marks every tracked window of an excluded app (D-12); a windowChanged for each window whose flag flipped.
    public mutating func setExcluded(_ bundleIDs: Set<String>) -> [WindowEvent] {
        excluded = Set(bundleIDs.map { $0.lowercased() })
        var events: [WindowEvent] = []
        for identity in windows.keys.sorted() {
            guard var info = windows[identity] else { continue }
            let isExcluded = excluded.contains(identity.bundleID.lowercased())
            guard info.isExcluded != isExcluded else { continue }
            info.isExcluded = isExcluded
            windows[identity] = info
            events.append(.windowChanged(info))
        }
        return events
    }

    /// A green button that appeared, went or moved by more than 1 pt; smaller drift is no event (RESEARCH Pattern 5).
    private static func buttonMoved(_ old: Rect?, _ new: Rect?) -> Bool {
        guard let old, let new else { return (old == nil) != (new == nil) }
        return abs(old.x - new.x) > 1 || abs(old.y - new.y) > 1 || abs(old.width - new.width) > 1 || abs(old.height - new.height) > 1
    }

    /// Per-bundle minimums from earlier sessions (D-13): the learned minimum a window of that bundle starts from.
    public mutating func setBundleHints(_ hints: [String: Size]) {
        bundleHints = hints
    }

    /// A finished frame write (D-17): the read-back becomes the window's frame, and a refused size the window moved
    /// to from its tracked frame becomes a minimum candidate that a refresh `MinimumSizeLearner.confirmDelay` later
    /// confirms. A failed write changes nothing; a later refresh decides the window's state through CloseRule.
    public mutating func applyFrameResult(_ result: FrameWriteResult, at now: ContinuousClock.Instant) -> [WindowEvent] {
        let identity = result.window.identity
        guard result.failure == nil, let actual = result.actual, actual.isValidGeometry, var info = windows[identity] else { return [] }
        let old = info
        // A fullscreen or minimized window does not take the requested size, so it teaches nothing.
        if info.state == .present { learner.recordWrite(window: identity, requested: result.requested, actual: actual, before: info.frame.size, at: now) }
        info.frame = actual
        info.displayUUID = Coordinates.displayUUID(for: actual, among: displays)
        windows[identity] = info
        var events: [WindowEvent] = [.frameApplied(info.window, requested: result.requested, actual: actual)]
        if old.frame.origin != actual.origin { events.append(.windowMoved(info.window, actual)) }
        if old.frame.size != actual.size { events.append(.windowResized(info.window, actual)) }
        if old.displayUUID != info.displayUUID { events.append(.windowChanged(info)) }
        return events
    }

    /// Decides the windows of terminated apps again against a fresh CG list (WindowServer lags behind the quit).
    public mutating func recheckTerminated(context: ObservationContext) -> [WindowEvent] {
        var events: [WindowEvent] = []
        for pid in terminatedPIDs.sorted() {
            events += decide(pid: pid, app: .terminated, context: context) { _ in .timedOut }
        }
        return events
    }

    /// The shown window IDs of terminated apps still tracked: the ones the terminated recheck decides.
    public var terminatedWindowIDs: [UInt32] { terminatedPIDs.sorted().flatMap(knownWindowIDs) }

    /// The window IDs of `pid` currently shown (a tab group's visible tab), ascending: the ones its app thread
    /// probes when they leave AXWindows.
    public func knownWindowIDs(pid: Int32) -> [UInt32] {
        windows.filter { $0.key.pid == pid }.map { $0.value.visibleMemberID ?? $0.key.windowID }.sorted()
    }

    /// Applies `CloseRule` to every tracked window of `pid` except `skipping` (reported this pass), through the
    /// window ID it shows: for a tab group, the visible tab, which `fact` describes.
    private mutating func decide(
        pid: Int32, app: AppLiveness, context: ObservationContext, skipping: Set<WindowIdentity> = [],
        fact: (UInt32) -> AXWindowFact
    ) -> [WindowEvent] {
        let inCG = Set(context.cgWindows.map(\.windowID))
        var events: [WindowEvent] = []
        for identity in windows.keys.sorted() where identity.pid == pid && !skipping.contains(identity) {
            let shown = windows[identity]?.visibleMemberID ?? identity.windowID
            let decision = CloseRule.decide(
                sessionActive: context.sessionActive, app: app, ax: fact(shown),
                inCGList: inCG.contains(shown),
                // nil (lookup off, or not asked) is unknown, never empty.
                cgSpacesKnownEmpty: inCG.contains(shown) && context.windowSpaces?[shown] == [],
                isKnownTabMember: tabGroups.isKnownMember(shown, pid: pid)
            )
            if decision == .recheck { rechecks[identity, default: 0] += 1 } else { rechecks[identity] = nil }
            switch decision {
            case .closed:
                // The shown tab closed but others are still in the CG list: the group lives on, and the next
                // listed tab rebinds it. It closes only when its last member is gone.
                tabGroups.memberClosed(shown, pid: pid)
                let remaining = tabGroups.members(of: identity).intersection(inCG)
                if !remaining.isEmpty {
                    guard var info = windows[identity], info.tabCount != remaining.count else { continue }
                    info.tabCount = remaining.count
                    windows[identity] = info
                    events.append(.windowChanged(info))
                    continue
                }
                for member in tabGroups.members(of: identity) { tabGroups.memberClosed(member, pid: pid) }
                guard let info = remove(identity, at: context.now) else { continue }
                events.append(.windowDestroyed(info.window))
            case .state(let state):
                guard var info = windows[identity], info.state != state else { continue }
                info.state = state
                windows[identity] = info
                events.append(.windowStateChanged(info.window, state))
            case .noChange, .recheck:
                continue
            }
        }
        if app == .terminated, !windows.keys.contains(where: { $0.pid == pid }) { terminatedPIDs.remove(pid) }
        return events
    }

    /// Drops a window and everything learned about it; the caller reports it destroyed.
    private mutating func remove(_ identity: WindowIdentity, at now: ContinuousClock.Instant) -> WindowInfo? {
        guard let info = windows.removeValue(forKey: identity) else { return nil }
        lastReliable[identity] = nil
        rechecks[identity] = nil
        learner.forget(identity)
        foldPending[identity] = nil
        closedIDs.insert(identity, at: now)
        return info
    }

    /// Sticky kinds: a reliable observation re-classifies only a provisional kind (`changed == nil`) or one whose
    /// subrole, layer or title changed, and a button that is merely disabled never demotes a dockable window.
    private static func reclassify(_ old: WindowKind, _ classified: WindowKind, _ snapshot: WindowSnapshot, changed: Bool?) -> WindowKind {
        guard let changed else { return classified }
        guard changed else { return old }
        if old == .dockable {
            if classified == .neverDock(.noCloseButton), snapshot.close.present { return old }
            if classified == .neverDock(.noFullscreenButton), snapshot.fullScreenButton.present { return old }
        }
        return classified
    }

    /// True while a window of `pid` awaits a quick recheck (at most `maxQuickRechecks` in a row); the caller
    /// refreshes again after `settleDelay`.
    public func needsQuickRecheck(pid: Int32) -> Bool {
        rechecks.contains { $0.key.pid == pid && $0.value <= Self.maxQuickRechecks }
    }

    /// True while a window of `pid` is withheld waiting for its settle delay; the caller refreshes again then.
    /// True while a refused write to a window of `pid` awaits its confirming refresh; the caller refreshes again
    /// after `MinimumSizeLearner.confirmDelay`.
    public func awaitsMinimumConfirmation(pid: Int32) -> Bool {
        windows.keys.contains { $0.pid == pid && learner.awaitsConfirmation($0) }
    }

    public func hasPendingWindows(pid: Int32) -> Bool {
        pending.keys.contains { $0.pid == pid }
    }

    public func info(for identity: WindowIdentity) -> WindowInfo? {
        windows[identity]
    }

    /// Every tracked window, ordered by identity (pid, windowID, bundleID).
    public func sortedWindows() -> [WindowInfo] {
        windows.values.sorted { $0.window.identity < $1.window.identity }
    }
}
