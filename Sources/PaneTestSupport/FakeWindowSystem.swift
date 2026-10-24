import PaneEngine
import PaneModel

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

    public init(
        id: UInt32, pid: Int32, title: String, frame: Rect, snapshot: WindowSnapshot, hiddenMinimum: Size? = nil,
        axValid: Bool = true, inCGList: Bool = true, listedInAX: Bool = true, cgLayer: Int = 0, onScreen: Bool = true
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
    }

    /// An `AXStandardWindow` with all four title-bar buttons present and enabled.
    public static func standard(id: UInt32, pid: Int32, frame: Rect, title: String = "") -> FakeWindow {
        FakeWindow(
            id: id, pid: pid, title: title, frame: frame,
            snapshot: WindowSnapshot(
                role: "AXWindow", subrole: "AXStandardWindow", modal: false, main: false, minimized: false, fullScreen: false,
                close: .enabled, minimize: .enabled, zoom: .enabled, fullScreenButton: .enabled, frame: frame
            )
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
    public private(set) var performed: [WindowCommand] = []
    public private(set) var clock: ContinuousClock.Instant
    private var tracker = WindowTracker()
    /// Hung and slow apps go through the production responsiveness rule (D-14, D-16).
    private var responsiveness = ResponsivenessTracker()
    private var displays: [DisplayInfo] = []
    /// Like `AXWindowSystem.start()`, the first `refreshAll()` is the initial sweep; later new windows settle first.
    private var initialSweepDone = false

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

    public func setHung(pid: Int32, _ hung: Bool) {
        apps[pid]?.hung = hung
    }

    /// The displays every later observation and `inventory()` report.
    public func setDisplays(_ displays: [DisplayInfo]) {
        self.displays = displays
    }

    public func setLocked(_ locked: Bool, gate: Bool = true) {
        self.locked = locked
    }

    /// The window closed: AX says invalid and it left the CG list.
    public func close(_ id: UInt32) {
        update(id) {
            $0.axValid = false
            $0.inCGList = false
        }
    }

    /// The process is gone: its windows leave both AX (invalid) and the CG list.
    public func terminate(pid: Int32) {
        apps[pid]?.terminated = true
        responsiveness.forget(pid: pid)
        for (id, window) in windows where window.pid == pid {
            windows[id]?.axValid = false
            windows[id]?.inCGList = false
        }
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
        let observation: AppObservation
        if app.hung {
            observation = AppObservation(pid: pid, bundleID: app.bundleID, appHidden: app.hidden, windows: [],
                                         listFailure: .cannotComplete, duration: Self.hungJobDuration)
        } else {
            let listed = windows.values.filter { $0.pid == pid && $0.listedInAX }.sorted { $0.id < $1.id }
            observation = AppObservation(
                pid: pid, bundleID: app.bundleID, appHidden: app.hidden,
                windows: listed.map { window in
                    var snapshot = window.snapshot
                    snapshot.frame = window.frame
                    return WindowObservation(
                        windowID: window.id, idSource: .axPrivate,
                        read: window.axValid ? .success(snapshot) : .failure(.invalidElement), title: window.title
                    )
                },
                duration: app.responseDelay
            )
        }
        record(pid, app.hung ? .cannotComplete : .success, observation.duration)
        // A hung app's observation never reaches the tracker, so its windows keep their last values (WIN-09).
        guard !app.hung else { return }
        let cgWindows = windows.values.filter(\.inCGList).sorted { $0.id < $1.id }.map {
            CGWindowEntry(windowID: $0.id, pid: $0.pid, bounds: $0.frame, layer: $0.cgLayer, onScreen: $0.onScreen, alpha: 1)
        }
        let context = ObservationContext(cgWindows: cgWindows, displays: displays, sessionActive: !locked, initialSweep: !initialSweepDone, now: clock)
        for event in tracker.ingest(observation, context: context) {
            continuation.yield(event)
        }
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
        initialSweepDone = true
    }

    public func inventory() async -> WindowInventory {
        WindowInventory(displays: displays, windows: tracker.sortedWindows(), degradedPIDs: responsiveness.degraded, sessionPaused: locked, initialRefreshComplete: true)
    }

    public func perform(_ commands: [WindowCommand]) async {
        performed += commands
    }

    public func windowInfo(_ window: WindowRef) async -> WindowInfo? {
        tracker.info(for: window.identity)
    }
}
