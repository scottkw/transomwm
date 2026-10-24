import PaneModel

/// Pure tracking core: turns `AppObservation`s into `WindowInfo`s and the `WindowEvent`s between them.
///
/// Shared by `AXWindowSystem` and `FakeWindowSystem`, so scenario tests run the production decisions.
/// Every known window's state and removal is decided by `CloseRule` (two sources, D-09); a window with no
/// answer counts as timed out and is left untouched. Windows are keyed by ID, never merged by frame.
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
        var events: [WindowEvent] = []
        var seen: Set<WindowIdentity> = []
        var created: Set<WindowIdentity> = []
        let cgByID = Dictionary(context.cgWindows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        // Probes of windows that left AXWindows only feed the close decision below.
        for observation in app.windows where observation.listedInAXWindows {
            // Fallback IDs (nil windowID) arrive in Plan 11.
            guard case .success(var snapshot) = observation.read, let windowID = observation.windowID else { continue }
            if let cg = cgByID[windowID] {
                snapshot.cg = CGWindowFact(layer: cg.layer, onScreen: cg.onScreen, alpha: cg.alpha)
            }
            // Non-windows such as Finder's desktop are never tracked.
            guard case .window(let classified, let reliable) = Classifier.classify(snapshot, bundleID: app.bundleID, appHidden: app.appHidden)
            else { continue }
            let identity = WindowIdentity(windowID: windowID, pid: app.pid, bundleID: app.bundleID)
            seen.insert(identity)
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
            info.tabCount = snapshot.tabGroup?.tabCount ?? 1
            info.displayUUID = Coordinates.displayUUID(for: frame, among: context.displays)
            windows[identity] = info

            guard let old else {
                nextCreationOrder += 1
                created.insert(identity)
                closedIDs.remove(identity)  // a reused ID is this new window from now on
                events.append(.windowCreated(info))
                continue
            }
            if old.frame.origin != frame.origin { events.append(.windowMoved(ref, frame)) }
            if old.frame.size != frame.size { events.append(.windowResized(ref, frame)) }
            if old.window.titleHint != ref.titleHint || old.kind != kind || old.tabCount != info.tabCount
                || old.displayUUID != info.displayUUID
            {
                events.append(.windowChanged(info))
            }
        }
        let byID = Dictionary(app.windows.compactMap { o in o.windowID.map { ($0, o) } }, uniquingKeysWith: { a, b in a.listedInAXWindows ? a : b })
        let liveness: AppLiveness = terminatedPIDs.contains(app.pid) ? .terminated : .alive
        events += decide(pid: app.pid, app: liveness, context: context, skipping: created) { identity in
            guard app.listFailure == nil, let observation = byID[identity.windowID] else { return .timedOut }
            switch observation.read {
            case .success(let snapshot):
                return .valid(listed: observation.listedInAXWindows, minimized: snapshot.minimized == true,
                              appHidden: app.appHidden, fullScreen: snapshot.fullScreen == true)
            case .failure(.invalidElement): return .invalidElement
            case .failure(.cannotComplete): return .timedOut
            case .failure: return .otherFailure
            }
        }
        // A pending window that left the list was never reported, so it is dropped silently.
        if app.listFailure == nil {
            for identity in pending.keys where identity.pid == app.pid && !seen.contains(identity) {
                pending[identity] = nil
            }
        }
        return events
    }

    /// NSWorkspace says `pid` quit. AX can no longer answer for it, so each window closes once it leaves the CG list.
    public mutating func appTerminated(pid: Int32, context: ObservationContext) -> [WindowEvent] {
        terminatedPIDs.insert(pid)
        for identity in pending.keys where identity.pid == pid { pending[identity] = nil }
        return decide(pid: pid, app: .terminated, context: context) { _ in .timedOut }
    }

    /// Decides the windows of terminated apps again against a fresh CG list (WindowServer lags behind the quit).
    public mutating func recheckTerminated(context: ObservationContext) -> [WindowEvent] {
        var events: [WindowEvent] = []
        for pid in terminatedPIDs.sorted() {
            events += decide(pid: pid, app: .terminated, context: context) { _ in .timedOut }
        }
        return events
    }

    /// The tracked window IDs of `pid`, ascending: the ones its app thread probes when they leave AXWindows.
    public func knownWindowIDs(pid: Int32) -> [UInt32] {
        windows.keys.filter { $0.pid == pid }.map(\.windowID).sorted()
    }

    /// Applies `CloseRule` to every tracked window of `pid` except `skipping` (reported this pass).
    private mutating func decide(
        pid: Int32, app: AppLiveness, context: ObservationContext, skipping: Set<WindowIdentity> = [],
        fact: (WindowIdentity) -> AXWindowFact
    ) -> [WindowEvent] {
        let inCG = Set(context.cgWindows.map(\.windowID))
        var events: [WindowEvent] = []
        for identity in windows.keys.sorted() where identity.pid == pid && !skipping.contains(identity) {
            let decision = CloseRule.decide(
                sessionActive: context.sessionActive, app: app, ax: fact(identity),
                inCGList: inCG.contains(identity.windowID), isKnownTabMember: false
            )
            switch decision {
            case .closed:
                guard let info = windows.removeValue(forKey: identity) else { continue }
                lastReliable[identity] = nil
                closedIDs.insert(identity, at: context.now)
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

    /// True while a window of `pid` is withheld waiting for its settle delay; the caller refreshes again then.
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
