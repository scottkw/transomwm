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
    private var forceWindowIDFallback: Bool
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "ax")
    private var tracker = WindowTracker()
    private var threads: [Int32: AXAppThread] = [:]
    private var started = false
    /// An unpaused sweep observed every app (G-03-10): a sweep while paused reads nothing and does not count.
    private var initialRefreshComplete = false
    /// Bumped on each pause, so a sweep can tell a pause began during it, even one that already ended.
    private var pauseCount = 0
    private var displays: [DisplayInfo] = []
    private var screenObserver: (any NSObjectProtocol)?
    /// `NSWorkspace.activeSpaceDidChangeNotification`: marks every app's next full update `spaceChanged` (02-17).
    private var spaceObserver: (any NSObjectProtocol)?
    private var spaceSwitches = SpaceSwitchMarks()
    private var registry: AppRegistry?
    private var scheduler: RefreshScheduler?
    /// False while the registry starts the apps already running, which are not "launched".
    private var followingLaunches = false
    /// The latest focus hint per pid, emitted as `windowFocused` after the refresh in which its window is tracked.
    private var pendingFocus = PendingFocus()
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
    /// `inventory().liveWindows`: the latest sweep's layer-0 CG windows of tracked apps, nil when unknown (G-03-8).
    private var liveWindows: [CGWindowEntry]?
    /// The IDs of the latest non-nil `liveWindows`; a change yields `.liveWindowsChanged`.
    private var liveWindowIDs: Set<UInt32>?

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
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        hintContinuation.finish()
    }

    /// Test seam: identify windows by frame (true) or through `_AXUIElementGetWindow` again (false), for every app.
    func setForceWindowIDFallback(_ force: Bool) {
        forceWindowIDFallback = force
        for thread in threads.values { thread.forceWindowIDFallback = force }
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
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.spaceSwitches.spaceDidChange(pids: self.threads.keys)
                self.spaceDidChange()
            }
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
        await sweep()
        // Hints queued during the initial sweep are handled now; each only schedules a refresh (T-02-18).
        Task { [weak self, hints] in
            for await hint in hints { self?.handle(hint) }
        }
        // Started while locked: the post-resume refresh is the initial sweep and starts the sweep loop.
        if !paused { scheduler.startSweep() }
    }

    /// Re-reads displays, re-checks which apps are eligible and refreshes every tracked app concurrently.
    public func refreshAll() async {
        displays = Displays.current()
        registry?.recheck()
        await sweep()
    }

    public func inventory() async -> WindowInventory {
        WindowInventory(
            displays: displays, windows: tracker.sortedWindows(), degradedPIDs: responsiveness.degraded,
            sessionPaused: sessionPaused, initialRefreshComplete: initialRefreshComplete,
            liveWindows: sessionPaused ? nil : liveWindows
        )
    }

    /// The user's exclusion list (D-12): those apps' windows stay tracked, marked `isExcluded`, and never touched.
    public func setExcludedBundleIDs(_ bundleIDs: Set<String>) {
        excluded = bundleIDs
        loggedExcluded = loggedExcluded.filter { ExclusionFilter.isExcluded($0, in: bundleIDs) }
        // Frames already queued, or held while an app was degraded, must not be written either (WR-04).
        for thread in threads.values { thread.excluded = ExclusionFilter.isExcluded(thread.bundleID, in: bundleIDs) }
        emit(tracker.setExcluded(bundleIDs))
    }

    /// Per-bundle minimums from earlier sessions (D-13): a new window of that bundle starts from its hint.
    public func setBundleHints(_ hints: [String: Size]) {
        tracker.setBundleHints(hints)
    }

    /// Called with a window's bundle ID and its new persistable minimum whenever it grows (`WindowInfo.persistableMinimum`).
    public var onLearnedMinimum: ((String, Size) -> Void)?
    /// The learned minimum last reported (or seeded) per window, so each growth reaches `onLearnedMinimum` once.
    private var reportedMinimums: [WindowIdentity: Size] = [:]

    /// Routes each `.setFrame` to its app's thread, addressed to the window's visible tab (D-16): the thread keeps
    /// only the latest frame per window and writes it with read-back. Rects that are not finite or are beyond
    /// `Geometry.maxCoordinate`, and windows Pane does not track, are dropped and logged (T-02-32). `.park` is a
    /// frame write through the same slot, to its display's `parkedFrame` at the window's tracked size (Pattern 15).
    /// `.focus` and `.raise` run as jobs on the app's thread and never hold up the caller (`focus(_:of:on:)`).
    /// `setHidden` is logged and dropped: no phase needs it yet, and it stays in the protocol for later ones.
    /// Commands for an excluded app are dropped before anything else, logged once per bundle ID (D-12).
    public func perform(_ commands: [WindowCommand]) async {
        let split = ExclusionFilter.admit(commands, excluded: excluded)
        for bundleID in Set(split.dropped.map(\.window.bundleID)) where loggedExcluded.insert(bundleID).inserted {
            logger.notice("dropping commands for excluded app \(bundleID, privacy: .public)")
        }
        for command in split.admitted {
            let ref = command.window
            guard let info = tracker.info(for: ref.identity), let thread = threads[ref.pid] else {
                logger.info("dropping a command for \(ref.description, privacy: .public): window not tracked")
                continue
            }
            let windowID = info.visibleMemberID ?? ref.windowID
            switch command {
            case .setFrame(_, let rect):
                guard rect.isValidGeometry else {
                    logger.error("dropping setFrame for \(ref.description, privacy: .public): rect not finite or out of range")
                    continue
                }
                thread.enqueueFrame(windowID: windowID, rect: rect, ref: info.window)
            case .park(_, let uuid):
                guard let display = displays.first(where: { $0.uuid == uuid }) else {
                    logger.error("dropping park for \(ref.description, privacy: .public): display \(uuid, privacy: .public) unknown")
                    continue
                }
                thread.enqueueFrame(windowID: windowID, rect: display.parkedFrame(size: info.frame.size, among: displays), ref: info.window)
            case .focus:
                Task { await focus(windowID, of: info.window, on: thread) }
            case .raise:
                Task {
                    if !(await thread.raiseWindow(windowID: windowID)) {
                        logger.info("raise of \(ref.description, privacy: .public) failed")
                    }
                }
            case .setHidden:
                logger.info("dropping setHidden for \(ref.description, privacy: .public): not implemented yet")
            }
        }
    }

    /// The quit restore (SAFE-01, Pattern 11, Pitfall 14): writes each frame synchronously on its app's thread, one
    /// app per worker, and blocks the caller until every write finished or `deadline` passed. Nothing here needs the main
    /// queue, which AppKit runs in modal-panel mode during `terminateLater`. Excluded apps, untracked windows and invalid
    /// rects are skipped, as in `perform`. Returns how many writes finished.
    public func restoreForTermination(_ frames: [PaneModel.WindowRef: Rect], deadline: DispatchTime) -> Int {
        var jobs: [Int32: (thread: AXAppThread, writes: [(UInt32, Rect)])] = [:]
        for (ref, rect) in frames {
            guard rect.isValidGeometry, !ExclusionFilter.isExcluded(ref.bundleID, in: excluded), let info = tracker.info(for: ref.identity),
                let thread = threads[ref.pid]
            else {
                logger.info("quit restore skips \(ref.description, privacy: .public)")
                continue
            }
            jobs[ref.pid, default: (thread, [])].writes.append((info.visibleMemberID ?? ref.windowID, rect))
        }
        let finished = OSAllocatedUnfairLock(initialState: 0)
        let group = DispatchGroup()
        for (thread, writes) in jobs.values {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                for (windowID, rect) in writes where thread.writeForTermination(windowID: windowID, rect: rect, deadline: deadline) {
                    finished.withLock { $0 += 1 }
                }
            }
        }
        if group.wait(timeout: deadline) == .timedOut { logger.notice("quit restore: an app did not answer in time; abandoned") }
        return finished.withLock { $0 }
    }

    /// AXMain and AXRaise on the app's thread, then activation on main. macOS 14+ activation is cooperative, so
    /// when the app is still not frontmost about 200 ms later its AXFrontmost is set instead (Pattern 15).
    private func focus(_ windowID: UInt32, of ref: PaneModel.WindowRef, on thread: AXAppThread) async {
        if !(await thread.focusWindow(windowID: windowID)) {
            logger.info("focus of \(ref.description, privacy: .public): AXMain or AXRaise failed")
        }
        NSRunningApplication(processIdentifier: ref.pid)?.activate()
        try? await Task.sleep(for: .milliseconds(200))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ref.pid else { return }
        if !(await thread.setFrontmost()) { logger.info("focus of \(ref.description, privacy: .public): AXFrontmost failed") }
    }

    /// One frame write finished on `thread`. A write the app did not answer counts toward degrading it.
    private func frameWritten(_ result: FrameWriteResult, on thread: AXAppThread) {
        guard threads[thread.pid] === thread else { return }
        // FrameWriteResult carries no duration; the failure count alone degrades a hung app.
        if result.failure == .cannotComplete { record(thread.pid, .cannotComplete, .zero) }
        emit(tracker.applyFrameResult(result, at: .now))
        // A refused size is learned only by a refresh a second later that still sees the window there.
        if tracker.awaitsMinimumConfirmation(pid: thread.pid) { scheduler?.schedule(pid: thread.pid, after: MinimumSizeLearner.confirmDelay) }
    }

    /// Presses the app's ⌘N menu item on its thread (RESEARCH Pattern 14). False when the app is not tracked.
    public func pressNewWindowItem(pid: Int32) async -> Bool {
        guard let thread = threads[pid] else { return false }
        return await thread.perform { MenuPress.pressCommandN(in: $0) } ?? false
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
    /// runs on its own (T-02-20). Initial until one runs with no pause from start to end (G-03-10).
    private func sweep() async {
        let initial = !initialRefreshComplete
        let pausesBefore = pauseCount
        // One CG list per refresh: the window layer fact for the classifier (and the close rule's second source).
        // nil when it failed: each refresh then reads its own. The reads begin here, so the Space-switch generation too.
        let readGeneration = spaceSwitches.generation
        let cgWindows = CGWindowList.snapshot()
        // Windows on Spaces AX does not list are still here, in the tracked apps' scope (G-03-8), each with its Spaces.
        liveWindows = paused ? nil : cgWindows.map { all in
            let live = all.filter { $0.layer == 0 && threads[$0.pid] != nil }
            let spaces = SkyLightSpaces.spaces(of: live.map(\.windowID))
            return live.map { entry in
                var entry = entry
                entry.spaces = spaces?[entry.windowID]
                return entry
            }
        }
        if let ids = liveWindows.map({ Set($0.map(\.windowID)) }) {
            if let previous = liveWindowIDs, previous != ids { emit([.liveWindowsChanged]) }
            liveWindowIDs = ids
        }
        let pids = threads.keys.filter { responsiveness.shouldRefresh(pid: $0) }
        await withTaskGroup(of: Void.self) { group in
            for pid in pids {
                group.addTask { await self.refresh(pid: pid, initial: initial, cgWindows: cgWindows, readGeneration: readGeneration) }
            }
        }
        if initial, !paused, pauseCount == pausesBefore { initialRefreshComplete = true }
    }

    /// One app's refresh, from the sweep, a hint, a launch or a settle follow-up. Dropped while the app is
    /// degraded; collapsed into one follow-up while a job for it is in flight. `readGeneration`: the Space-switch
    /// generation when the sweep's reads began; nil records it here, just before this refresh's own reads.
    private func refresh(pid: Int32, initial: Bool = false, cgWindows: [CGWindowEntry]? = nil, readGeneration: UInt64? = nil) async {
        // Polls the CGSession lock flag too (A3: belt and braces); a paused session refreshes nothing.
        gate?.evaluate()
        guard !paused, let thread = threads[pid], responsiveness.shouldRefresh(pid: pid) else { return }
        guard inFlight.insert(pid).inserted else {
            followUp.insert(pid)
            return
        }
        let readGeneration = readGeneration ?? spaceSwitches.generation
        let observation = await thread.observe(known: tracker.knownWindowIDs(pid: pid))
        inFlight.remove(pid)
        // The app may have quit meanwhile; its windows are decided by the terminated path now.
        guard let observation, threads[pid] === thread else { return }
        record(pid, Self.outcome(of: observation), observation.duration)
        // Read after AX answered, so a window AX just reported invalid has had the most time to leave the CG list. A
        // sweep's shared list predates every app's AX read instead; TabGroupTracker allows for a tab missing from it.
        guard let cgWindows = cgWindows ?? CGWindowList.snapshot() else {
            // No second source: no close decision and no tab update now; refresh again soon (WR-01).
            followUp.remove(pid)
            scheduler?.schedule(pid: pid, after: tracker.settleDelay)
            return
        }
        ingest(observation, cgWindows: cgWindows, initial: initial, readGeneration: readGeneration)
        // A hint for a window still settling stays until a later refresh tracks it (G-03-5). A no-ID hint resolves
        // through AXMain from this observation only if its AXWindows read succeeded (T-03-54).
        let mainID = observation.listFailure == nil ? mainWindowIDs[pid] : nil
        if let ref = pendingFocus.resolve(pid: pid, mainID: mainID, windows: tracker.sortedWindows()) {
            emit([.windowFocused(ref)])
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
                guard !Task.isCancelled, let self, let thread = self.threads[pid] else { return }
                switch self.responsiveness.probeStep(pid: pid, at: .now) {
                case .stop: return
                case .wait: continue
                case .probe: break
                }
                let (outcome, duration) = await thread.probe()
                guard !Task.isCancelled, self.threads[pid] === thread else { return }
                self.record(pid, outcome, duration)
            }
        }
    }

    private func ingest(_ observation: AppObservation, cgWindows: [CGWindowEntry], initial: Bool, readGeneration: UInt64) {
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
        // WindowServer IPC, not AX: fine on main. Nil while the Spaces capability is off (single-Space behaviour).
        let windowSpaces = observation.listFailure == nil
            ? SkyLightSpaces.spaces(of: cgWindows.filter { $0.pid == observation.pid && $0.layer == 0 }.map(\.windowID)) : nil
        // Only a full answer consumes a mark; a notification during the reads keeps it for the next update.
        let spaceChanged = observation.listFailure == nil && spaceSwitches.take(pid: observation.pid, readGeneration: readGeneration)
        let context = ObservationContext(
            cgWindows: withSyntheticPresence(cgWindows, shown: shown), displays: displays, sessionActive: !paused,
            initialSweep: initial, now: .now, windowSpaces: windowSpaces, spaceChanged: spaceChanged)
        emit(tracker.ingest(observation, context: context))
        emit(tracker.recheckTerminated(context: context))
        // A new window is withheld until it settles, a close AX reported waits for the CG list to agree, and a window
        // whose ID lookup failed for the first time waits for its own CG entry: refresh again soon.
        if tracker.hasPendingWindows(pid: observation.pid) || tracker.needsQuickRecheck(pid: observation.pid) || observation.identityPending {
            scheduler?.schedule(pid: observation.pid, after: tracker.settleDelay)
        } else if tracker.awaitsMinimumConfirmation(pid: observation.pid) {
            // This refresh came too soon to confirm a refused write.
            scheduler?.schedule(pid: observation.pid, after: MinimumSizeLearner.confirmDelay)
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
            switch event {
            case .windowFocused(let ref): focusedIdentities[ref.pid] = ref.identity
            // A seeded minimum came from the store, so it is never reported back.
            case .windowCreated(let info): reportedMinimums[info.window.identity] = info.persistableMinimum
            case .windowChanged(let info):
                // Only the persistable part is saved per bundle: an unmoved refusal's minimum is session-only (CR-02).
                if let minimum = info.persistableMinimum, minimum != reportedMinimums[info.window.identity] {
                    reportedMinimums[info.window.identity] = minimum
                    onLearnedMinimum?(info.window.bundleID, minimum)
                }
            case .windowDestroyed(let ref): reportedMinimums[ref.identity] = nil
            case .windowRekeyed(let from, let info):
                // Every per-window record follows the new ID; the minimum it carries was reported or seeded already.
                let pid = from.pid
                if focusedIdentities[pid] == from.identity { focusedIdentities[pid] = info.window.identity }
                if mainWindowIDs[pid] == from.windowID { mainWindowIDs[pid] = info.visibleMemberID ?? info.window.windowID }
                pendingFocus.rekey(pid: pid, from: from.windowID, to: info.visibleMemberID ?? info.window.windowID)
                reportedMinimums[from.identity] = nil
                reportedMinimums[info.window.identity] = info.persistableMinimum
            default: break
            }
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
                guard let cgWindows = CGWindowList.snapshot() else { continue }
                let context = ObservationContext(
                    cgWindows: self.withSyntheticPresence(cgWindows), displays: self.displays, sessionActive: !self.paused, now: .now)
                self.emit(self.tracker.recheckTerminated(context: context))
            }
        }
    }

    /// A hint never decides anything: it only schedules its pid's refresh (D-09). A destroyed notification
    /// included: the refresh probes the cached element, and CloseRule needs the CG list to agree.
    private func handle(_ hint: AXEventHint) {
        guard threads[hint.pid] != nil else { return }
        let focus = hint.notification == kAXFocusedWindowChangedNotification || hint.notification == kAXMainWindowChangedNotification
        // A nil ID (an element the thread has not cached yet, such as a new window) resolves through AXMain.
        if focus { pendingFocus.hint(pid: hint.pid, windowID: hint.windowID) }
        scheduler?.schedule(pid: hint.pid)
    }

    private func appStarted(_ app: NSRunningApplication) {
        guard let key = bundleKey(app), appFilter(app.processIdentifier, key) else { return }
        let pid = app.processIdentifier
        let thread = AXAppThread(pid: pid, bundleID: key, hints: hintContinuation, forceWindowIDFallback: forceWindowIDFallback)
        thread.excluded = ExclusionFilter.isExcluded(key, in: excluded)
        threads[pid] = thread
        Task { [weak self] in
            for await result in thread.frameResults { self?.frameWritten(result, on: thread) }
        }
        guard followingLaunches else { return }
        continuation.yield(.appLaunched(pid: pid, bundleID: key))
        scheduler?.schedule(pid: pid)
    }

    /// Stops the app's thread. On a quit, each of its windows closes once it has also left the CG list; an app that
    /// only stopped being regular loses its windows at once, since no thread refreshes them any more (WR-02).
    private func appStopped(_ pid: Int32, terminated: Bool) {
        guard let thread = threads.removeValue(forKey: pid) else { return }
        thread.stop()
        scheduler?.cancel(pid: pid)
        pendingFocus.forget(pid: pid)
        focusedIdentities[pid] = nil
        mainWindowIDs[pid] = nil
        probes.removeValue(forKey: pid)?.cancel()
        responsiveness.forget(pid: pid)
        spaceSwitches.forget(pid: pid)
        inFlight.remove(pid)
        followUp.remove(pid)
        guard terminated else {
            emit(tracker.appStopped(pid: pid))
            return
        }
        continuation.yield(.appTerminated(pid: pid))
        let cgWindows = CGWindowList.snapshot()
        // Without the CG list nothing closes yet (an inactive context decides nothing); the rechecks below decide.
        let context = ObservationContext(
            cgWindows: withSyntheticPresence(cgWindows ?? []), displays: displays, sessionActive: !paused && cgWindows != nil, now: .now)
        emit(tracker.appTerminated(pid: pid, context: context))
        if !tracker.knownWindowIDs(pid: pid).isEmpty { recheckTerminatedSoon(pid) }
    }

    private var paused: Bool { gate?.isPaused ?? false }

    /// Locked or asleep: report it once, drop scheduled refreshes and stop the sweep (T-02-26).
    private func sessionDidPause() {
        pauseCount += 1
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
    /// Re-reads the displays and reports each one whose current Space changed (D-25).
    private func spaceDidChange() {
        let old = Dictionary(displays.map { ($0.uuid, $0.currentSpaceID) }, uniquingKeysWith: { first, _ in first })
        displays = Displays.current()
        for display in displays where old[display.uuid] != .some(display.currentSpaceID) {
            continuation.yield(.spaceChanged(displayUUID: display.uuid, spaceID: display.currentSpaceID))
        }
    }

    private func displaysDidChange() {
        // Read now, so the inventory the Arranger re-plans against already has the new visible frames (TILE-03).
        displays = Displays.current()
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
