import TransomEngine
import TransomModel

/// A simulated app in `FakeWindowSystem`.
public struct FakeApp: Sendable {
    public var pid: Int32
    public var bundleID: String
    public var hung: Bool
    public var responseDelay: Duration
    public var hidden: Bool
    public var terminated: Bool

    public init(pid: Int32, bundleID: String, hung: Bool = false, responseDelay: Duration = .zero, hidden: Bool = false, terminated: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.hung = hung
        self.responseDelay = responseDelay
        self.hidden = hidden
        self.terminated = terminated
    }
}

/// A simulated window in `FakeWindowSystem`. `frame` is authoritative; it replaces `snapshot.frame` on every refresh.
public struct FakeWindow: Sendable {
    public var id: UInt32
    public var pid: Int32
    public var title: String
    public var frame: Rect
    public var snapshot: WindowSnapshot
    public var hiddenMinimum: Size?
    public var axValid: Bool
    public var inCGList: Bool
    public var listedInAX: Bool
    public var cgLayer: Int
    public var onScreen: Bool
    /// The Space the window is on; nil for scenarios that do not model Spaces.
    public var space: UInt64?
    /// The native tab group the window is a tab of (`tabGroup` and `newTab` set it).
    public var tabGroupID: UInt32?

    public init(
        id: UInt32, pid: Int32, title: String, frame: Rect, snapshot: WindowSnapshot, hiddenMinimum: Size? = nil,
        axValid: Bool = true, inCGList: Bool = true, listedInAX: Bool = true, cgLayer: Int = 0, onScreen: Bool = true,
        space: UInt64? = nil, tabGroupID: UInt32? = nil
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
        self.snapshot = snapshot
        self.hiddenMinimum = hiddenMinimum
        self.axValid = axValid
        self.inCGList = inCGList
        self.listedInAX = listedInAX
        self.cgLayer = cgLayer
        self.onScreen = onScreen
        self.space = space
        self.tabGroupID = tabGroupID
    }

    /// An `AXStandardWindow` with all four title-bar buttons present and enabled.
    public static func standard(id: UInt32, pid: Int32, frame: Rect, title: String = "", space: UInt64? = nil) -> FakeWindow {
        FakeWindow(
            id: id, pid: pid, title: title, frame: frame,
            snapshot: WindowSnapshot(
                role: "AXWindow", subrole: "AXStandardWindow", modal: false, main: false, minimized: false, fullScreen: false,
                close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
            ),
            space: space
        )
    }
}

/// A `WindowSystem` over a simulated OS (D-14). Refreshes build `AppObservation`s from the simulation and
/// feed them through the production `WindowTracker`, so scenario tests exercise the real decisions.
public actor FakeWindowSystem: WindowSystem {
    public nonisolated let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation
    public private(set) var apps: [Int32: FakeApp] = [:]
    public private(set) var windows: [UInt32: FakeWindow] = [:]
    public private(set) var locked = false
    /// Whether a lock also pauses the session (`sessionActive: false`), as `SessionGate` does live.
    private var lockGate = true
    /// Whether AX answers during a lock with no windows and -25202 per known window, instead of timing out.
    private var lockAXInvalid = false
    public private(set) var performed: [WindowCommand] = []
    /// Commands `ExclusionFilter` kept away from excluded apps.
    public private(set) var dropped: [WindowCommand] = []
    /// Windows a `park` moved to their display's corner; a later `setFrame` takes a window out.
    public private(set) var parked: Set<WindowIdentity> = []
    /// Every admitted `.raise`, in order.
    public private(set) var raised: [WindowRef] = []
    private var excluded: Set<String> = []
    public private(set) var clock: ContinuousClock.Instant
    private var tracker = WindowTracker()
    /// Hung and slow apps go through the production responsiveness rule (D-14, D-16).
    private var responsiveness = ResponsivenessTracker()
    private var displays: [DisplayInfo] = []
    /// Like AXWindowSystem's, the first `refreshAll()` with the session active is the initial sweep; later new windows
    /// settle first. One run while locked observes nothing and does not count (G-03-10).
    private var initialSweepDone = false
    /// The latest frame per window of a hung or degraded app, applied after its next successful refresh (D-16).
    private var heldFrames: [WindowIdentity: (ref: WindowRef, rect: Rect)] = [:]
    /// Whether observations carry Space data, as when the Spaces capability is on.
    private var spacesAvailable = false
    /// Whether a hidden tab reports its Space; a real one may report none.
    private var hiddenTabsReportSpace = false
    /// The Space shown since the last `showSpace`; nil until a scenario switches Spaces.
    private var currentSpace: UInt64?
    /// The selected tab of each tab group.
    private var selectedTabs: [UInt32: UInt32] = [:]
    /// Space-switch notifications, consumed per app as `AXWindowSystem` does.
    private var spaceSwitches = SpaceSwitchMarks()
    /// Closed windows whose CG entry lingers (G-03-9), with the Space set it reports.
    private var lingering: [UInt32: Set<UInt64>] = [:]

    public init(now: ContinuousClock.Instant = .now) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        clock = now
    }

    public func addApp(_ app: FakeApp) {
        apps[app.pid] = app
    }

    public func open(_ window: FakeWindow) {
        windows[window.id] = window
    }

    public func update(_ id: UInt32, _ change: @Sendable (inout FakeWindow) -> Void) {
        guard var window = windows[id] else { return }
        change(&window)
        windows[id] = window
    }

    /// The user or the app moved or resized window `id`: its frame changes and a refresh of its app reports
    /// `windowMoved`/`windowResized`, with no `frameApplied`, as a move Transom did not make arrives live.
    public func userMove(_ id: UInt32, to frame: Rect) {
        update(id) { $0.frame = frame }
        if let pid = windows[id]?.pid { refresh(pid: pid) }
    }

    /// Native fullscreen on or off (WIN-07): sets only `snapshot.fullScreen`, like `update`; the next refresh reports it.
    public func setFullscreen(_ id: UInt32, _ on: Bool) {
        update(id) { $0.snapshot.fullScreen = on }
    }

    /// A native tab group (D-08): standard windows sharing `frame` and `space`. Only `visible` is listed in AX and
    /// onscreen; the other tabs exist only in the CG list, offscreen. Hidden tabs keep the frame they had when they
    /// were hidden, as on macOS 15.7.7 (G-02-10).
    public func tabGroup(ids: [UInt32], frame: Rect, pid: Int32, visible: UInt32, space: UInt64? = nil) {
        for id in ids {
            var tab = FakeWindow.standard(id: id, pid: pid, frame: frame, title: "Tab \(id)", space: space)
            tab.tabGroupID = ids.first
            windows[id] = tab
        }
        selectTab(visible)
    }

    /// Cmd-T in `window`: AppKit opens tab `id` on its Space at `frame`, else at the frame of the group's shown tab
    /// (the host's when it has no group yet), and shows it. The tab hidden by it keeps its own frame (G-02-10: Terminal's
    /// first Cmd-T grows the new tab by the tab bar; Finder may open it at a hidden sibling's frame).
    public func newTab(_ id: UInt32, in window: UInt32, frame: Rect? = nil) {
        guard let host = windows[window] else { return }
        let group = host.tabGroupID ?? window
        windows[window]?.tabGroupID = group
        let groupFrame = selectedTabs[group].flatMap { windows[$0]?.frame } ?? host.frame
        var tab = FakeWindow.standard(id: id, pid: host.pid, frame: frame ?? groupFrame, title: "Tab \(id)", space: host.space)
        tab.tabGroupID = group
        windows[id] = tab
        show(id)
    }

    /// Shows tab `id`, as AppKit does: it takes the frame of its group's previously shown tab (the group frame; AppKit
    /// applies it only when it shows a tab, debug E2), then becomes its group's one listed, onscreen member (while its
    /// Space is shown), and its `AXTabs` count is the number of its group's tabs AX still knows. The others go unlisted
    /// and offscreen, each keeping its own frame (G-02-10).
    public func selectTab(_ id: UInt32) {
        guard let group = windows[id]?.tabGroupID else { return }
        if let previous = selectedTabs[group], previous != id, let groupFrame = windows[previous]?.frame {
            windows[id]?.frame = groupFrame
        }
        show(id)
    }

    private func show(_ id: UInt32) {
        guard let group = windows[id]?.tabGroupID else { return }
        selectedTabs[group] = id
        let members = windows.values.filter { $0.tabGroupID == group && $0.inCGList }
        let tabCount = members.filter(\.axValid).count
        for member in members {
            let shown = member.id == id && (currentSpace == nil || member.space == nil || member.space == currentSpace)
            windows[member.id]?.listedInAX = shown
            windows[member.id]?.onScreen = shown
            windows[member.id]?.snapshot.tabGroup = TabGroupFact(tabCount: tabCount)
        }
    }

    /// A Space switch on every display: AX lists, and WindowServer shows onscreen, exactly the open windows on `space`
    /// that are not hidden tabs, and every display's `currentSpaceID` becomes `space`. With `notifies` the switch marks
    /// every app's next full update and yields `.spaceChanged` per display, as the live
    /// `activeSpaceDidChangeNotification` does; without it the notification never arrived.
    public func showSpace(_ space: UInt64, notifies: Bool = true) {
        currentSpace = space
        for i in displays.indices { displays[i].currentSpaceID = space }
        if notifies {
            spaceSwitches.spaceDidChange(pids: apps.keys)
            for display in displays { continuation.yield(.spaceChanged(displayUUID: display.uuid, spaceID: space)) }
        }
        for (id, window) in windows {
            let shown = window.space == space && !isHiddenTab(window) && window.axValid && window.inCGList
            windows[id]?.listedInAX = shown
            windows[id]?.onScreen = shown
        }
    }

    /// A Space switch on display `uuid` only (separate Spaces per display): its `currentSpaceID` becomes `space`, and
    /// AX lists exactly the open windows on any display's current Space. Notifies like `showSpace`, for that display.
    /// shortcut: tab groups still follow `showSpace`'s single current Space; extend `selectTab` if a test mixes the two.
    public func showSpace(_ space: UInt64, onDisplay uuid: String, notifies: Bool = true) {
        guard let index = displays.firstIndex(where: { $0.uuid == uuid }) else { return }
        displays[index].currentSpaceID = space
        if notifies {
            spaceSwitches.spaceDidChange(pids: apps.keys)
            continuation.yield(.spaceChanged(displayUUID: uuid, spaceID: space))
        }
        let shownSpaces = Set(displays.compactMap(\.currentSpaceID))
        for (id, window) in windows {
            let shown = window.space.map(shownSpaces.contains) == true && !isHiddenTab(window) && window.axValid && window.inCGList
            windows[id]?.listedInAX = shown
            windows[id]?.onScreen = shown
        }
    }

    /// Whether observations carry Space data (the Spaces capability on) or not (single-Space fallback).
    public func setSpacesAvailable(_ available: Bool) {
        spacesAvailable = available
    }

    /// Whether a hidden tab reports its group's Space, or none (as the live lookup may answer).
    public func setHiddenTabsReportSpace(_ report: Bool) {
        hiddenTabsReportSpace = report
    }

    private func isHiddenTab(_ window: FakeWindow) -> Bool {
        window.tabGroupID.map { selectedTabs[$0] != window.id } ?? false
    }

    /// The user's exclusion list, as `AXWindowSystem.setExcludedBundleIDs` receives it.
    public func setExcluded(_ bundleIDs: Set<String>) {
        excluded = bundleIDs
        heldFrames = heldFrames.filter { !ExclusionFilter.isExcluded($0.key.bundleID, in: bundleIDs) }
        yield(tracker.setExcluded(bundleIDs))
    }

    public func setHung(pid: Int32, _ hung: Bool) {
        apps[pid]?.hung = hung
    }

    /// The displays every later observation and `inventory()` report.
    public func setDisplays(_ displays: [DisplayInfo]) {
        self.displays = displays
    }

    /// Lock blanking (D-14): the CG list is empty and every AX read fails with -25204, or with `axInvalid` AXWindows
    /// is empty and every known window answers -25202, which only the gate keeps from closing. With `gate: false`
    /// the session stays active, as if no lock signal arrived.
    public func setLocked(_ locked: Bool, gate: Bool = true, axInvalid: Bool = false) {
        self.locked = locked
        lockGate = gate
        lockAXInvalid = axInvalid
    }

    /// The window closed: AX says invalid and it left the CG list.
    public func close(_ id: UInt32) {
        lingering[id] = nil
        update(id) {
            $0.axValid = false
            $0.inCGList = false
        }
    }

    /// The window closed but WindowServer keeps its CG entry (G-03-9): AX says invalid (-25202), and while Spaces are
    /// available the entry reports `spaces`, until `close` clears it.
    public func lingerInCG(_ id: UInt32, spaces: Set<UInt64>) {
        update(id) {
            $0.axValid = false
            $0.listedInAX = false
            $0.onScreen = false
        }
        lingering[id] = spaces
    }

    /// The process quit, as NSWorkspace reports it. Its windows stay in the CG list until a test removes them
    /// (WindowServer lag); each later `refreshAll()` rechecks them.
    public func terminate(pid: Int32) {
        apps[pid]?.terminated = true
        responsiveness.forget(pid: pid)
        spaceSwitches.forget(pid: pid)
        for (id, window) in windows where window.pid == pid {
            windows[id]?.axValid = false
        }
        yield(tracker.appTerminated(pid: pid, context: context()))
    }

    public func advance(by duration: Duration) {
        clock += duration
    }

    /// How long a simulated job for a hung app takes: the 1 s AX timeout.
    public static let hungJobDuration: Duration = .seconds(1)

    /// Builds this app's observation from the simulation and feeds it to the tracker. A degraded app is
    /// skipped unless its probe is due; a successful probe recovers it and refreshes it in full.
    public func refresh(pid: Int32) {
        guard let app = apps[pid], !app.terminated else { return }
        if !responsiveness.shouldRefresh(pid: pid) {
            guard responsiveness.needsProbe(pid: pid, at: clock) else { return }
            let change = record(pid, app.hung ? .cannotComplete : .success, app.hung ? Self.hungJobDuration : app.responseDelay)
            guard change == .recovered(pid) else { return }
        }
        // Synchronous, so the reads always begin after any earlier `showSpace`.
        let readGeneration = spaceSwitches.generation
        let observation: AppObservation
        if app.hung || (locked && !lockAXInvalid) {
            observation = AppObservation(pid: pid, bundleID: app.bundleID, appHidden: app.hidden, windows: [],
                                         listFailure: .cannotComplete, duration: app.hung ? Self.hungJobDuration : app.responseDelay)
        } else if locked {
            observation = AppObservation(
                pid: pid, bundleID: app.bundleID, appHidden: app.hidden,
                windows: tracker.knownWindowIDs(pid: pid).map {
                    WindowObservation(windowID: $0, idSource: .axPrivate, read: .failure(.invalidElement), title: "", listedInAXWindows: false)
                },
                duration: app.responseDelay
            )
        } else {
            let listed = windows.values.filter { $0.pid == pid && $0.listedInAX }.sorted { $0.id < $1.id }
            // Like AXAppThread: known windows that left AXWindows are probed through their cached element.
            let probed = tracker.knownWindowIDs(pid: pid).compactMap { windows[$0] }.filter { !$0.listedInAX }
            observation = AppObservation(
                pid: pid, bundleID: app.bundleID, appHidden: app.hidden,
                windows: listed.map { window in
                    var snapshot = window.snapshot
                    snapshot.frame = window.frame
                    return WindowObservation(
                        windowID: window.id, idSource: .axPrivate,
                        read: window.axValid ? .success(snapshot) : .failure(.invalidElement), title: window.title
                    )
                } + probed.map { window in
                    WindowObservation(
                        windowID: window.id, idSource: .axPrivate,
                        read: window.axValid ? .success(WindowSnapshot(role: window.snapshot.role)) : .failure(.invalidElement),
                        title: "", listedInAXWindows: false
                    )
                },
                duration: app.responseDelay
            )
        }
        record(pid, observation.listFailure == nil ? .success : .cannotComplete, observation.duration)
        // Like AXWindowSystem, a hung app's failed observation reaches the tracker: CloseRule must keep its windows (WIN-09).
        let spaceChanged = observation.listFailure == nil && spaceSwitches.take(pid: pid, readGeneration: readGeneration)
        yield(tracker.ingest(observation, context: context(spaceChanged: spaceChanged)))
        guard !app.hung else { return }
        for (identity, held) in heldFrames.filter({ $0.key.pid == pid }).sorted(by: { $0.key < $1.key }) {
            heldFrames[identity] = nil
            write(held.rect, to: held.ref)
        }
    }

    /// Like `FrameWriter`: the write clamps to the window's hidden minimum and is read back into the tracker.
    /// Goes to a tab group's visible member only: its hidden tabs keep their frames, as the live AX write left them
    /// (G-02-10 E4), until a tab switch shows one at the group frame.
    private func write(_ rect: Rect, to ref: WindowRef) {
        guard let info = tracker.info(for: ref.identity), let target = windows[info.visibleMemberID ?? ref.windowID] else { return }
        guard target.axValid else {
            yield(tracker.applyFrameResult(FrameWriteResult(window: ref, requested: rect, actual: nil, failure: .invalidElement), at: clock))
            return
        }
        let minimum = target.hiddenMinimum ?? Size(width: 0, height: 0)
        let actual = Rect(x: rect.x, y: rect.y, width: max(rect.width, minimum.width), height: max(rect.height, minimum.height))
        windows[target.id]?.frame = actual
        yield(tracker.applyFrameResult(FrameWriteResult(window: ref, requested: rect, actual: actual, failure: nil), at: clock))
    }

    /// The CG list (empty while locked), displays, session state, clock and, while Spaces are available, each CG
    /// window's Space (a hidden tab's is empty unless hidden tabs report it) of the simulation right now.
    private func context(spaceChanged: Bool = false) -> ObservationContext {
        let cgWindows = locked ? [] : windows.values.filter(\.inCGList).sorted { $0.id < $1.id }.map {
            CGWindowEntry(windowID: $0.id, pid: $0.pid, bounds: $0.frame, layer: $0.cgLayer, onScreen: $0.onScreen, alpha: 1)
        }
        let windowSpaces: [UInt32: Set<UInt64>]? = spacesAvailable ? Dictionary(uniqueKeysWithValues: windows.values.filter { $0.inCGList && !locked }.compactMap { window in
            if let spaces = lingering[window.id] { return (window.id, spaces) }
            return window.space.map { (window.id, isHiddenTab(window) && !hiddenTabsReportSpace ? Set<UInt64>() : [$0]) }
        }) : nil
        return ObservationContext(cgWindows: cgWindows, displays: displays, sessionActive: !(locked && lockGate),
                                  initialSweep: !initialSweepDone, now: clock, windowSpaces: windowSpaces,
                                  spaceChanged: spaceChanged)
    }

    private func yield(_ events: [WindowEvent]) {
        for event in events { continuation.yield(event) }
    }

    @discardableResult
    private func record(_ pid: Int32, _ outcome: JobOutcome, _ duration: Duration) -> ResponsivenessChange? {
        let change = responsiveness.record(pid: pid, outcome: outcome, duration: duration, at: clock)
        switch change {
        case .degraded: continuation.yield(.appResponsiveness(pid: pid, degraded: true))
        case .recovered: continuation.yield(.appResponsiveness(pid: pid, degraded: false))
        case nil: break
        }
        return change
    }

    public func refreshAll() {
        for pid in apps.keys.sorted() { refresh(pid: pid) }
        yield(tracker.recheckTerminated(context: context()))
        if !(locked && lockGate) { initialSweepDone = true }
    }

    /// `liveWindows` are the layer-0 CG windows of the apps the fake tracks (added, not terminated), as AXWindowSystem
    /// reports those of its app threads, each with its Spaces as observations see them; nil while locked, since the CG
    /// list is blank. The shell's `.liveWindowsChanged` trigger is not modelled: tests feed the inventory as
    /// ArrangeController does.
    public func inventory() async -> WindowInventory {
        let spaces = context().windowSpaces
        let live = locked ? nil : windows.values.filter { $0.inCGList && $0.cgLayer == 0 && apps[$0.pid]?.terminated == false }
            .sorted { $0.id < $1.id }
            .map { CGWindowEntry(windowID: $0.id, pid: $0.pid, bounds: $0.frame, layer: $0.cgLayer, onScreen: $0.onScreen, alpha: 1, spaces: spaces?[$0.id]) }
        return WindowInventory(displays: displays, windows: tracker.sortedWindows(), degradedPIDs: responsiveness.degraded, sessionPaused: locked && lockGate,
                               initialRefreshComplete: initialSweepDone, liveWindows: live)
    }

    /// Applies `.setFrame` to tracked windows with valid rects; a hung or degraded app's latest frame per window
    /// is held instead. `.park` is a frame write too, to its display's `parkedFrame` at the window's size, and marks
    /// the window `parked` until a `.setFrame` for it. `.focus` yields `windowFocused`; `.raise` is recorded. Every command is recorded in `performed`; those for excluded
    /// apps go to `dropped` and nowhere else (D-12). `.setHidden` does nothing (Pattern 15).
    public func perform(_ commands: [WindowCommand]) async {
        performed += commands
        let split = ExclusionFilter.admit(commands, excluded: excluded)
        dropped += split.dropped
        for command in split.admitted {
            switch command {
            case .setFrame(let ref, let rect) where rect.isValidGeometry:
                parked.remove(ref.identity)
                apply(rect, to: ref)
            case .park(let ref, let uuid):
                guard let display = displays.first(where: { $0.uuid == uuid }), let size = tracker.info(for: ref.identity)?.frame.size
                else { continue }
                parked.insert(ref.identity)
                apply(display.parkedFrame(size: size, among: displays), to: ref)
            case .focus(let ref):
                if let info = tracker.info(for: ref.identity) { continuation.yield(.windowFocused(info.window)) }
            case .raise(let ref):
                raised.append(ref)
            case .setFrame, .setHidden:
                break
            }
        }
    }

    private func apply(_ rect: Rect, to ref: WindowRef) {
        guard let app = apps[ref.pid], !app.terminated else { return }
        if app.hung || !responsiveness.shouldRefresh(pid: ref.pid) {
            heldFrames[ref.identity] = (ref, rect)
        } else {
            write(rect, to: ref)
        }
    }

    public func windowInfo(_ window: WindowRef) async -> WindowInfo? {
        tracker.info(for: window.identity)
    }
}
