import PaneModel

/// Pure tracking core: turns `AppObservation`s into `WindowInfo`s and the `WindowEvent`s between them.
///
/// Shared by `AXWindowSystem` and `FakeWindowSystem`, so scenario tests run the production decisions.
/// Windows missing from an observation are left untouched: closing needs two sources (Plan 09), and
/// never closing is the safe direction. Windows are keyed by ID, never merged by frame.
public struct WindowTracker: Sendable {
    /// How long a new window settles before it is classified (used once classification is scheduled).
    public let settleDelay: Duration
    public private(set) var windows: [WindowIdentity: WindowInfo] = [:]
    private var nextCreationOrder: UInt64 = 1

    public init(settleDelay: Duration = .milliseconds(250)) {
        self.settleDelay = settleDelay
    }

    public mutating func ingest(_ app: AppObservation, context: ObservationContext) -> [WindowEvent] {
        var events: [WindowEvent] = []
        for observation in app.windows {
            // Fallback IDs (nil windowID) arrive in Plan 11; non-windows such as Finder's desktop are never tracked.
            guard case .success(let snapshot) = observation.read, snapshot.role == "AXWindow",
                  let windowID = observation.windowID
            else { continue }
            let identity = WindowIdentity(windowID: windowID, pid: app.pid, bundleID: app.bundleID)
            let old = windows[identity]
            // A window whose frame could not be read is picked up by a later refresh.
            guard let frame = snapshot.frame ?? old?.frame else { continue }

            let state: WindowState =
                snapshot.minimized == true || app.appHidden ? .absent
                : snapshot.fullScreen == true ? .fullscreen
                : .present
            // Subrole reads AXDialog while minimised or hidden (Pitfall 3), so keep the known kind then.
            let kind: WindowKind =
                if let old, state == .absent { old.kind }
                else if snapshot.subrole == "AXStandardWindow" { .dockable }
                else { .neverDock(.subrole) }

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
            windows[identity] = info

            guard let old else {
                nextCreationOrder += 1
                events.append(.windowCreated(info))
                continue
            }
            if old.frame.origin != frame.origin { events.append(.windowMoved(ref, frame)) }
            if old.frame.size != frame.size { events.append(.windowResized(ref, frame)) }
            if old.state != state { events.append(.windowStateChanged(ref, state)) }
            if old.window.titleHint != ref.titleHint || old.kind != kind || old.tabCount != info.tabCount {
                events.append(.windowChanged(info))
            }
        }
        return events
    }

    public func hasPendingWindows(pid: Int32) -> Bool {
        false
    }

    public func info(for identity: WindowIdentity) -> WindowInfo? {
        windows[identity]
    }

    /// Every tracked window, ordered by identity (pid, windowID, bundleID).
    public func sortedWindows() -> [WindowInfo] {
        windows.values.sorted { $0.window.identity < $1.window.identity }
    }
}
