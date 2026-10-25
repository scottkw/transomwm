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
    private let forceWindowIDFallback: Bool
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
    /// Per pid: the window named by the latest `windowFocused`, and the visible window ID whose latest
    /// observation was AXMain. `focusedWindow(of:)` reads them.
    private var focusedIdentities: [Int32: WindowIdentity] = [:]
    private var mainWindowIDs: [Int32: UInt32] = [:]
    /// Which apps are degraded (D-16). A degraded app gets no refreshes, only its probe loop.
    private var responsiveness = ResponsivenessTracker()
    /// At most one refresh job per pid runs; a request meanwhile becomes one follow-up (T-02-19).
    private var inFlight: Set<Int32> = []
    private var followUp: Set<Int32> = []
    private var probes: [Int32: Task<Void, Never>] = [:]
    /// Lock, sleep and session signals (D-09). While paused no refresh runs and nothing is closed.
    private var gate: SessionGate?
    /// `inventory().sessionPaused`: true from the pause until the post-resume full refresh has finished.
    private var sessionPaused = false
    private var resumeTask: Task<Void, Never>?
    /// Quiet time after the last session signal before the post-resume full refresh.
    static let resumeQuiet: Duration = .milliseconds(1500)
    /// The user's exclusion list (D-12), and the bundle IDs whose dropped commands were already logged.
    private var excluded: Set<String> = []
    private var loggedExcluded: Set<String> = []

    /// `appFilter(pid, bundleKey)` limits which apps get a thread (tests track only the fixture).
    /// `forceWindowIDFallback` (test seam) identifies windows by frame even when `_AXUIElementGetWindow` works.
    public init(appFilter: @escaping @MainActor (Int32, String) -> Bool = { _, _ in true }, forceWindowIDFallback: Bool = false) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1024))
        (hints, hintContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
        self.appFilter = appFilter
        self.forceWindowIDFallback = forceWindowIDFallback
    }

    isolated deinit {
        for thread in threads.values { thread.stop() }
        for probe in probes.values { probe.cancel() }
        resumeTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        hintContinuation.finish()
    }

    /// Session-aware: a lookup switched off mid-session reads as off here, in the menu and in the footer.
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
        let gate = SessionGate(
            workspaceCenter: NSWorkspace.shared.notificationCenter, distributedCenter: DistributedNotificationCenter.default(),
            sessionDictionary: { CGSessionCopyCurrentDictionary() as? [String: Any] },
            frontmostBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
            onPause: { [weak self] in self?.sessionDidPause() },
            onResume: { [weak self] in self?.sessionDidResume() }
        )
        self.gate = gate
        gate.evaluate()
        await sweep(initial: true)
        initialRefreshComplete = true
        // Hints queued during the initial sweep are handled now; each only schedules a refresh (T-02-18).
        Task { [weak self, hints] in
            for await hint in hints { self?.handle(hint) }
        }
        // Started while locked: the post-resume refresh starts the sweep.
        if !paused { scheduler.startSweep() }
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
            sessionPaused: sessionPaused, initialRefreshComplete: initialRefreshComplete
        )
    }

    /// The user's exclusion list (D-12): those apps' windows stay tracked, marked `isExcluded`, and never touched.
    public func setExcludedBundleIDs(_ bundleIDs: Set<String>) {
        excluded = bundleIDs
        loggedExcluded = loggedExcluded.filter { ExclusionFilter.isExcluded($0, in: bundleIDs) }
        emit(tracker.setExcluded(bundleIDs))
    }

    /// Per-bundle minimums from earlier sessions (D-13): a new window of that bundle starts from its hint.
    public func setBundleHints(_ hints: [String: Size]) {
        tracker.setBundleHints(hints)
    }

    /// Called with a window's bundle ID and its new learned minimum whenever a frame write raises it.
    public var onLearnedMinimum: ((String, Size) -> Void)?

    /// Routes each `.setFrame` to its app's thread, addressed to the window's visible tab (D-16): the thread keeps
    /// only the latest frame per window and writes it with read-back. Rects that are not finite or are beyond
    /// `Geometry.maxCoordinate`, and windows Pane does not track, are dropped and logged (T-02-32).
    /// `park`, `focus`, `raise` and `setHidden` are logged and dropped: Phase 3 implements them.
    /// Commands for an excluded app are dropped before anything else, logged once per bundle ID (D-12).
    public func perform(_ commands: [WindowCommand]) async {
        let split = ExclusionFilter.admit(commands, excluded: excluded)
        for bundleID in Set(split.dropped.map(\.window.bundleID)) where loggedExcluded.insert(bundleID).inserted {
            logger.notice("dropping commands for excluded app \(bundleID, privacy: .public)")
        }
        for command in split.admitted {
            guard case .setFrame(let ref, let rect) = command else {
                logger.info("dropping a command other than setFrame: not implemented before Phase 3")
                continue
            }
            guard rect.isValidGeometry else {
                logger.error("dropping setFrame for \(ref.description, privacy: .public): rect not finite or out of range")
                continue
            }
            guard let info = tracker.info(for: ref.identity), let thread = threads[ref.pid] else {
                logger.info("dropping setFrame for \(ref.description, privacy: .public): window not tracked")
                continue
            }
            thread.enqueueFrame(windowID: info.visibleMemberID ?? ref.windowID, rect: rect, ref: info.window)
        }
    }

    /// One frame write finished on `thread`. A write the app did not answer counts toward degrading it.
    private func frameWritten(_ result: FrameWriteResult, on thread: AXAppThread) {
        guard threads[thread.pid] === thread else { return }
        // FrameWriteResult carries no duration; the failure count alone degrades a hung app.
        if result.failure == .cannotComplete { record(thread.pid, .cannotComplete, .zero) }
        let before = tracker.info(for: result.window.identity)?.learnedMinimum
        emit(tracker.applyFrameResult(result))
        if let after = tracker.info(for: result.window.identity)?.learnedMinimum, after != before {
            onLearnedMinimum?(result.window.bundleID, after)
        }
    }

    public func windowInfo(_ window: PaneModel.WindowRef) async -> WindowInfo? {
        tracker.info(for: window.identity)
    }

    /// The app's focused tracked window: the one its latest `windowFocused` named, else the one whose visible
    /// member was AXMain at its latest observation; nil when neither is tracked.
    public func focusedWindow(of pid: Int32) -> WindowInfo? {
        if let identity = focusedIdentities[pid], let info = tracker.info(for: identity) { return info }
        guard let id = mainWindowIDs[pid] else { return nil }
        return tracker.sortedWindows().first { $0.window.pid == pid && ($0.visibleMemberID ?? $0.window.windowID) == id }
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
        // Polls the CGSession lock flag too (A3: belt and braces); a paused session refreshes nothing.
        gate?.evaluate()
        guard !paused, let thread = threads[pid], responsiveness.shouldRefresh(pid: pid) else { return }
        guard inFlight.insert(pid).inserted else {
            followUp.insert(pid)
            return
        }
        let observation = await thread.observe(known: tracker.knownWindowIDs(pid: pid))
        inFlight.remove(pid)
        // The app may have quit meanwhile; its windows are decided by the terminated path now.
        guard let observation, threads[pid] === thread else { return }
        // Read after AX answered, so a window AX just reported invalid has had the most time to leave the CG list.
        let cgWindows = cgWindows ?? CGWindowList.snapshot()
        record(pid, Self.outcome(of: observation), observation.duration)
        ingest(observation, cgWindows: cgWindows, initial: initial)
        // Through the shown tab: a focus hint on a non-leader tab names the group's visible member, not its identity.
        if let windowID = pendingFocus.removeValue(forKey: pid),
           let info = tracker.sortedWindows().first(where: { $0.window.pid == pid && ($0.visibleMemberID ?? $0.window.windowID) == windowID })
        {
            emit([.windowFocused(info.window)])
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
        // Held while degraded; true again retries a write the app did not answer, or flushes the latest frames.
        threads[pid]?.drainEnabled = responsiveness.shouldRefresh(pid: pid)
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
        } else {
            mainWindowIDs[observation.pid] = observation.windows.first { o in
                guard o.listedInAXWindows, case .success(let snapshot) = o.read else { return false }
                return snapshot.main == true
            }?.windowID
        }
        let shown = Dictionary(
            observation.windows.compactMap { o -> (UInt32, Rect)? in
                guard o.listedInAXWindows, let id = o.windowID, case .success(let snapshot) = o.read, let frame = snapshot.frame else { return nil }
                return (id, frame)
            },
            uniquingKeysWith: { first, _ in first })
        let context = ObservationContext(
            cgWindows: withSyntheticPresence(cgWindows, shown: shown), displays: displays, sessionActive: !paused,
            initialSweep: initial, now: .now)
        emit(tracker.ingest(observation, context: context))
        emit(tracker.recheckTerminated(context: context))
        // A new window is withheld until it settles, and a close AX reported waits for the CG list to agree:
        // refresh again soon.
        if tracker.hasPendingWindows(pid: observation.pid) || tracker.needsQuickRecheck(pid: observation.pid) {
            scheduler?.schedule(pid: observation.pid, after: tracker.settleDelay)
        }
    }

    /// `cgWindows` plus a presence entry for each tracked synthetic ID, which no CG entry carries (D-15): such a window
    /// closes only once AX reports it invalid and no same-pid CG window with its bounds is left. Windows AX lists now
    /// (`shown`, with their current frames) claim entries first, so of two identical windows the closed one goes.
    private func withSyntheticPresence(_ cgWindows: [CGWindowEntry], shown: [UInt32: Rect] = [:]) -> [CGWindowEntry] {
        let tracked = tracker.sortedWindows().map { info in
            let id = info.visibleMemberID ?? info.window.windowID
            return (identity: WindowIdentity(windowID: id, pid: info.window.pid, bundleID: info.window.bundleID), frame: shown[id] ?? info.frame)
        }
        guard tracked.contains(where: { $0.identity.isSyntheticWindowID }) else { return cgWindows }
        let ordered = tracked.filter { shown[$0.identity.windowID] != nil } + tracked.filter { shown[$0.identity.windowID] == nil }
        return cgWindows + FallbackMatcher.syntheticPresence(ordered, cgWindows: cgWindows)
    }

    private func emit(_ events: [WindowEvent]) {
        for event in events {
            if case .windowFocused(let ref) = event { focusedIdentities[ref.pid] = ref.identity }
            continuation.yield(event)
        }
    }

    /// A quitting app's windows can stay in the CG list briefly: recheck every 250 ms for up to 5 s, then leave
    /// any rest to the rechecks that follow every refresh.
    private func recheckTerminatedSoon(_ pid: Int32) {
        Task { [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !self.tracker.knownWindowIDs(pid: pid).isEmpty else { return }
                let context = ObservationContext(
                    cgWindows: self.withSyntheticPresence(CGWindowList.snapshot()), displays: self.displays, sessionActive: !self.paused, now: .now)
                self.emit(self.tracker.recheckTerminated(context: context))
            }
        }
    }

    /// A hint never decides anything: it only schedules its pid's refresh (D-09). A destroyed notification
    /// included: the refresh probes the cached element, and CloseRule needs the CG list to agree.
    private func handle(_ hint: AXEventHint) {
        guard threads[hint.pid] != nil else { return }
        let focus = hint.notification == kAXFocusedWindowChangedNotification || hint.notification == kAXMainWindowChangedNotification
        if focus, let windowID = hint.windowID { pendingFocus[hint.pid] = windowID }
        scheduler?.schedule(pid: hint.pid)
    }

    private func appStarted(_ app: NSRunningApplication) {
        guard let key = bundleKey(app), appFilter(app.processIdentifier, key) else { return }
        let pid = app.processIdentifier
        let thread = AXAppThread(pid: pid, bundleID: key, hints: hintContinuation, forceWindowIDFallback: forceWindowIDFallback)
        threads[pid] = thread
        Task { [weak self] in
            for await result in thread.frameResults { self?.frameWritten(result, on: thread) }
        }
        guard followingLaunches else { return }
        continuation.yield(.appLaunched(pid: pid, bundleID: key))
        scheduler?.schedule(pid: pid)
    }

    /// Stops the app's thread. On a quit, each of its windows closes once it has also left the CG list.
    private func appStopped(_ pid: Int32, terminated: Bool) {
        guard let thread = threads.removeValue(forKey: pid) else { return }
        thread.stop()
        scheduler?.cancel(pid: pid)
        pendingFocus[pid] = nil
        focusedIdentities[pid] = nil
        mainWindowIDs[pid] = nil
        probes.removeValue(forKey: pid)?.cancel()
        responsiveness.forget(pid: pid)
        inFlight.remove(pid)
        followUp.remove(pid)
        guard terminated else { return }
        continuation.yield(.appTerminated(pid: pid))
        let context = ObservationContext(cgWindows: withSyntheticPresence(CGWindowList.snapshot()), displays: displays, sessionActive: !paused, now: .now)
        emit(tracker.appTerminated(pid: pid, context: context))
        if !tracker.knownWindowIDs(pid: pid).isEmpty { recheckTerminatedSoon(pid) }
    }

    private var paused: Bool { gate?.isPaused ?? false }

    /// Locked or asleep: report it once, drop scheduled refreshes and stop the sweep (T-02-26).
    private func sessionDidPause() {
        resumeTask?.cancel()
        resumeTask = nil
        scheduler?.stop()
        guard !sessionPaused else { return }
        sessionPaused = true
        logger.notice("session paused: locked or asleep")
        continuation.yield(.sessionPaused(true))
    }

    /// After `resumeQuiet` with no new pause, one full refresh of every app, then the pause ends and the sweep
    /// restarts. A pause meanwhile cancels this, and the next resume waits the full quiet time again.
    private func sessionDidResume() {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.resumeQuiet)
            guard !Task.isCancelled, let self else { return }
            self.gate?.evaluate()
            guard !self.paused else { return }
            await self.refreshAll()
            guard !Task.isCancelled, !self.paused else { return }
            self.resumeTask = nil
            self.sessionPaused = false
            self.logger.notice("session resumed after a full refresh")
            self.continuation.yield(.sessionPaused(false))
            self.scheduler?.startSweep()
        }
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
