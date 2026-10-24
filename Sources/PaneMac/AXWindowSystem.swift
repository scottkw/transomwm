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
    /// Which apps are degraded (D-16). A degraded app gets no refreshes, only its probe loop.
    private var responsiveness = ResponsivenessTracker()
    /// At most one refresh job per pid runs; a request meanwhile becomes one follow-up (T-02-19).
    private var inFlight: Set<Int32> = []
    private var followUp: Set<Int32> = []
    private var probes: [Int32: Task<Void, Never>] = [:]

    /// `appFilter(pid, bundleKey)` limits which apps get a thread (tests track only the fixture).
    public init(appFilter: @escaping @MainActor (Int32, String) -> Bool = { _, _ in true }) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1024))
        (hints, hintContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.appFilter = appFilter
    }

    isolated deinit {
        for thread in threads.values { thread.stop() }
        for probe in probes.values { probe.cancel() }
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
        WindowInventory(
            displays: displays, windows: tracker.sortedWindows(), degradedPIDs: responsiveness.degraded,
            initialRefreshComplete: initialRefreshComplete
        )
    }

    public func perform(_ commands: [WindowCommand]) async {
        // shortcut: commands are dropped until the frame write pipeline lands (Plan 12).
        logger.info("dropping \(commands.count, privacy: .public) commands: no write pipeline yet")
    }

    public func windowInfo(_ window: PaneModel.WindowRef) async -> WindowInfo? {
        tracker.info(for: window.identity)
    }

    /// Refreshes every responsive app concurrently. A degraded app is never awaited here: its probe loop
    /// runs on its own (T-02-20).
    private func sweep(initial: Bool) async {
        // One CG list per refresh: the window layer fact for the classifier (and the close rule's second source).
        let cgWindows = CGWindowList.snapshot()
        let pids = threads.keys.filter { responsiveness.shouldRefresh(pid: $0) }
        await withTaskGroup(of: Void.self) { group in
            for pid in pids {
                group.addTask { await self.refresh(pid: pid, initial: initial, cgWindows: cgWindows) }
            }
        }
    }

    /// One app's refresh, from the sweep, a hint, a launch or a settle follow-up. Dropped while the app is
    /// degraded; collapsed into one follow-up while a job for it is in flight.
    private func refresh(pid: Int32, initial: Bool = false, cgWindows: [CGWindowEntry]? = nil) async {
        guard let thread = threads[pid], responsiveness.shouldRefresh(pid: pid) else { return }
        guard inFlight.insert(pid).inserted else {
            followUp.insert(pid)
            return
        }
        let cgWindows = cgWindows ?? CGWindowList.snapshot()
        let observation = await thread.observe()
        inFlight.remove(pid)
        guard let observation else { return }
        record(pid, Self.outcome(of: observation), observation.duration)
        ingest(observation, cgWindows: cgWindows, initial: initial)
        if let windowID = pendingFocus.removeValue(forKey: pid),
           let info = tracker.info(for: WindowIdentity(windowID: windowID, pid: pid, bundleID: thread.bundleID))
        {
            continuation.yield(.windowFocused(info.window))
        }
        if followUp.remove(pid) != nil { scheduler?.schedule(pid: pid, after: .zero) }
    }

    private static func outcome(of observation: AppObservation) -> JobOutcome {
        switch observation.listFailure {
        case nil: .success
        case .cannotComplete: .cannotComplete
        default: .otherFailure
        }
    }

    /// Feeds one finished job to the tracker and acts on a transition: report it, start probing a degraded
    /// app, refresh a recovered one in full.
    private func record(_ pid: Int32, _ outcome: JobOutcome, _ duration: Duration) {
        switch responsiveness.record(pid: pid, outcome: outcome, duration: duration, at: .now) {
        case .degraded:
            logger.notice("pid \(pid, privacy: .public) is not responding; probing every 2 s")
            continuation.yield(.appResponsiveness(pid: pid, degraded: true))
            startProbing(pid)
        case .recovered:
            logger.notice("pid \(pid, privacy: .public) responds again")
            continuation.yield(.appResponsiveness(pid: pid, degraded: false))
            probes.removeValue(forKey: pid)?.cancel()
            scheduler?.schedule(pid: pid, after: .zero)
        case nil:
            break
        }
    }

    /// Probes a degraded app's AXRole every `probeInterval` until it recovers or stops. Its own loop, not the
    /// 5 s sweep, so a resumed app is back within about 2 s.
    private func startProbing(_ pid: Int32) {
        probes[pid]?.cancel()
        probes[pid] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ResponsivenessTracker.probeInterval)
                guard !Task.isCancelled, let self, let thread = self.threads[pid],
                      self.responsiveness.needsProbe(pid: pid, at: .now)
                else { return }
                let (outcome, duration) = await thread.probe()
                guard !Task.isCancelled, self.threads[pid] === thread else { return }
                self.record(pid, outcome, duration)
            }
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
        probes.removeValue(forKey: pid)?.cancel()
        responsiveness.forget(pid: pid)
        inFlight.remove(pid)
        followUp.remove(pid)
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
