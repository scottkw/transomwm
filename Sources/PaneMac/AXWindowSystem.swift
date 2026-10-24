import AppKit
import ApplicationServices
import PaneEngine
import PaneModel
import PanePrivate
import os

/// The live `WindowSystem`: one `AXAppThread` per regular app, a `WindowTracker` on MainActor.
///
/// MainActor only enqueues jobs and awaits Sendable results; every AX call runs on the app's own
/// thread (D-16, T-02-03). `inventory()` serves the cache and never waits for an app.
@MainActor public final class AXWindowSystem: WindowSystem {
    public nonisolated let events: AsyncStream<WindowEvent>
    private let continuation: AsyncStream<WindowEvent>.Continuation
    /// AX notification hints from every app thread; read only by the hint loop started in `start()`.
    let hints: AsyncStream<AXEventHint>
    private let hintContinuation: AsyncStream<AXEventHint>.Continuation
    private let appFilter: @MainActor (Int32, String) -> Bool
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "ax")
    private var tracker = WindowTracker()
    private var threads: [Int32: AXAppThread] = [:]
    private var started = false
    private var initialRefreshComplete = false
    private var displays: [DisplayInfo] = []
    private var screenObserver: (any NSObjectProtocol)?
    private var registry: AppRegistry?
    private var scheduler: RefreshScheduler?
    /// False while the registry starts the apps already running, which are not "launched".
    private var followingLaunches = false
    /// The window a focus hint named, emitted as `windowFocused` after its pid's refresh.
    private var pendingFocus: [Int32: UInt32] = [:]

    /// `appFilter(pid, bundleKey)` limits which apps get a thread (tests track only the fixture).
    public init(appFilter: @escaping @MainActor (Int32, String) -> Bool = { _, _ in true }) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1024))
        (hints, hintContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.appFilter = appFilter
    }

    isolated deinit {
        for thread in threads.values { thread.stop() }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        hintContinuation.finish()
    }

    public var capabilityReport: [Capability: Bool] { Capabilities.report() }

    /// Sets the global AX timeout, starts a thread per regular app, runs the initial sweep, then follows
    /// app launches, AX hints and screen changes, with a 5 s safety sweep.
    public func start() async {
        guard !started else { return }
        started = true
        // Per-element timeouts do not reach equal or child elements (Pitfall 1), so set the global one.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        displays = Displays.current()
        let scheduler = RefreshScheduler(
            refresh: { [weak self] pid in await self?.refresh(pid: pid) },
            refreshAll: { [weak self] in await self?.refreshAll() }
        )
        self.scheduler = scheduler
        let registry = AppRegistry(
            onStart: { [weak self] app in self?.appStarted(app) },
            onStop: { [weak self] pid, terminated in self?.appStopped(pid, terminated: terminated) }
        )
        self.registry = registry
        registry.start()
        followingLaunches = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysDidChange() }
        }
        await sweep(initial: true)
        initialRefreshComplete = true
        // Hints queued during the initial sweep are handled now; each only schedules a refresh (T-02-18).
        Task { [weak self, hints] in
            for await hint in hints { self?.handle(hint) }
        }
        scheduler.startSweep()
    }

    /// Re-reads displays, re-checks which apps are eligible and refreshes every tracked app concurrently.
    public func refreshAll() async {
        displays = Displays.current()
        registry?.recheck()
        await sweep(initial: false)
    }

    public func inventory() async -> WindowInventory {
        WindowInventory(displays: displays, windows: tracker.sortedWindows(), initialRefreshComplete: initialRefreshComplete)
    }

    public func perform(_ commands: [WindowCommand]) async {
        // shortcut: commands are dropped until the frame write pipeline lands (Plan 12).
        logger.info("dropping \(commands.count, privacy: .public) commands: no write pipeline yet")
    }

    public func windowInfo(_ window: PaneModel.WindowRef) async -> WindowInfo? {
        tracker.info(for: window.identity)
    }

    private func sweep(initial: Bool) async {
        let threads = Array(threads.values)
        // One CG list per refresh: the window layer fact for the classifier (and the close rule's second source).
        let cgWindows = CGWindowList.snapshot()
        await withTaskGroup(of: AppObservation?.self) { group in
            for thread in threads {
                group.addTask { await thread.observe() }
            }
            for await observation in group {
                guard let observation else { continue }
                ingest(observation, cgWindows: cgWindows, initial: initial)
            }
        }
    }

    /// One app's refresh, scheduled by a hint, a launch or a settle follow-up.
    private func refresh(pid: Int32) async {
        guard let thread = threads[pid] else { return }
        let cgWindows = CGWindowList.snapshot()
        guard let observation = await thread.observe() else { return }
        ingest(observation, cgWindows: cgWindows, initial: false)
        if let windowID = pendingFocus.removeValue(forKey: pid),
           let info = tracker.info(for: WindowIdentity(windowID: windowID, pid: pid, bundleID: thread.bundleID))
        {
            continuation.yield(.windowFocused(info.window))
        }
    }

    private func ingest(_ observation: AppObservation, cgWindows: [CGWindowEntry], initial: Bool) {
        if let failure = observation.listFailure {
            logger.info("pid \(observation.pid, privacy: .public) AXWindows failed: \(String(describing: failure), privacy: .public)")
        }
        let context = ObservationContext(cgWindows: cgWindows, displays: displays, initialSweep: initial, now: .now)
        for event in tracker.ingest(observation, context: context) {
            continuation.yield(event)
        }
        // A new window is withheld until it settles; refresh again once it has.
        if tracker.hasPendingWindows(pid: observation.pid) {
            scheduler?.schedule(pid: observation.pid, after: tracker.settleDelay)
        }
    }

    /// A hint never decides anything: it only schedules its pid's refresh (D-09).
    private func handle(_ hint: AXEventHint) {
        guard threads[hint.pid] != nil else { return }
        let focus = hint.notification == kAXFocusedWindowChangedNotification || hint.notification == kAXMainWindowChangedNotification
        if focus, let windowID = hint.windowID { pendingFocus[hint.pid] = windowID }
        scheduler?.schedule(pid: hint.pid)
    }

    private func appStarted(_ app: NSRunningApplication) {
        guard let key = bundleKey(app), appFilter(app.processIdentifier, key) else { return }
        let pid = app.processIdentifier
        threads[pid] = AXAppThread(pid: pid, bundleID: key, hints: hintContinuation)
        guard followingLaunches else { return }
        continuation.yield(.appLaunched(pid: pid, bundleID: key))
        scheduler?.schedule(pid: pid)
    }

    /// Stops the app's thread. Its windows stay tracked: closing them needs two sources (Plan 09).
    private func appStopped(_ pid: Int32, terminated: Bool) {
        guard let thread = threads.removeValue(forKey: pid) else { return }
        thread.stop()
        scheduler?.cancel(pid: pid)
        pendingFocus[pid] = nil
        if terminated { continuation.yield(.appTerminated(pid: pid)) }
    }

    /// Reports the change at once, then re-reads displays and refreshes every app after 500 ms of quiet.
    private func displaysDidChange() {
        continuation.yield(.displaysChanged)
        scheduler?.scheduleAll(after: .milliseconds(500))
    }

    /// The app's bundle ID, or `unbundled:<executable name>` for a bare executable; nil (logged) when neither exists.
    private func bundleKey(_ app: NSRunningApplication) -> String? {
        if let bundleID = app.bundleIdentifier { return bundleID }
        guard let name = app.executableURL?.lastPathComponent else {
            logger.error("pid \(app.processIdentifier, privacy: .public) has no bundle ID or executable; not tracked")
            return nil
        }
        logger.info("pid \(app.processIdentifier, privacy: .public) has no bundle ID; keyed unbundled:\(name, privacy: .public)")
        return "unbundled:" + name
    }
}
