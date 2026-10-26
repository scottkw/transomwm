import AppKit
import PaneEngine
import PaneModel
import os

/// The thin MainActor shell around `Arranger` (RESEARCH Pattern 1). It is the only reader of `system.events`
/// (Pitfall 2), fans each re-read inventory out through `onInventory`, and runs the Arranger's effects in order.
/// Every window command goes through `system.perform`, where `ExclusionFilter.admit` guards it (02-13).
@MainActor public final class ArrangeController {
    private let system: AXWindowSystem
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "arrange")
    private var started = false
    /// Each re-read inventory: the menu header and the Tracked Windows feed.
    public var onInventory: ((WindowInventory) -> Void)?
    public private(set) var arranger: Arranger {
        didSet {
            publishGreenButtons()
            guard arranger.pauseReasons != reportedPause else { return }
            reportedPause = arranger.pauseReasons
            onPauseChanged?()
        }
    }
    private var reportedPause: Set<PauseReason> = []
    /// Fires when the set of pause reasons changes (the status glyph dims while paused).
    public var onPauseChanged: (() -> Void)?
    private var notices = NoticeQueue<Notice>()
    private lazy var toast = ToastPresenter()
    private let noticeExpiry = WakeTimer()
    /// The Arranger's one pending wake-up; a newer `.wake` replaces it.
    private let wake = WakeTimer()

    /// layout.json; nil in tests that do not persist.
    private let store: LayoutStore?
    private let launchedAt = Date()
    /// How this launch treats the saved layout (D-17); a non-normal one is recorded as `recoveryLaunch`.
    private var launchMode: LaunchMode = .normal
    /// Set 60 s into a recovery or crash-loop launch, so a crash after that is a plain recovery again (D-18).
    private var survivedMinute = false
    private let survivalTimer = WakeTimer()
    /// The one pending debounced write: a newer request replaces it, so it lands 0.5 s after the latest.
    private let saveTimer = WakeTimer()
    private var fedCompleteInventory = false

    /// The exclusion list Don't Arrange toggles; nil in tests that never dispatch it.
    private let exclusions: ExclusionStore?

    /// The active event tap that sees title-bar drags (TILE-01), and the poll of the dragged window's frame.
    private let tap = InputTap()
    private var tapReader: Task<Void, Never>?
    private let dragPoller = DragFramePoller()
    /// The drop preview panels, one per display; made when tracking starts.
    private var previews: PreviewPresenter?
    /// The gap handles (TILE-05). A panel is made only when a handle first shows.
    private let gapPanels = GapHandlePanels()
    /// Whether Accessibility access is ready, so the watchdog may bring the tap back.
    private var tapAllowed = true
    private var watchdog: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var loggedTapRefusal = false

    public init(system: AXWindowSystem, store: LayoutStore? = nil, exclusions: ExclusionStore? = nil, gap: Double = 8) {
        self.system = system
        self.store = store
        self.exclusions = exclusions
        arranger = Arranger(gap: gap)
        gapPanels.onDrag = { [weak self] handle, delta, ended in
            Task { [weak self] in
                guard let self else { return }
                await self.run(self.arranger.handle(.gapDrag(handle, delta: delta, ended: ended), now: .now))
            }
        }
    }

    /// A new gap from the Gaps submenu: applied at once, or on Resume while paused (D-27).
    public func setGap(_ gap: Double) async {
        await run(arranger.handle(.gap(gap), now: .now))
    }

    /// Sets or clears one pause reason (Stage Manager, from ConflictController).
    public func setPaused(_ reason: PauseReason, _ on: Bool) async {
        await run(arranger.handle(.setPaused(reason, on), now: .now))
    }

    /// Feeds the current inventory, then starts the single events loop. Later calls only re-read the inventory.
    public func start() async {
        let inventory = await system.inventory()
        guard !started else {
            onInventory?(inventory)
            return
        }
        started = true
        if let store {
            store.load()
            // The record the last session left decides this launch; `contents` keeps it after this launch's first write.
            launchMode = Recovery.launchMode(previous: store.contents?.session)
            await run(arranger.handle(.launch(launchMode), now: .now))
            if let due = Recovery.survivedMinuteDue(launchedAt: .now, mode: launchMode) {
                survivalTimer.set(due) { [weak self] in
                    self?.survivedMinute = true
                    self?.write()
                }
            }
            if let saved = store.contents {
                await run(arranger.handle(.restore(saved.world, homeFrames: saved.homeFrameMap), now: .now))
            }
            // This launch's session record (cleanExit false) goes down at once, with the saved layout still in it.
            write()
        }
        fedCompleteInventory = inventory.initialRefreshComplete
        await run(arranger.handle(.inventory(inventory), now: .now))
        onInventory?(inventory)
        Task { [weak self, system] in
            for await event in system.events {
                guard let self else { return }
                await self.run(self.arranger.handle(.event(event), now: .now))
                // inventory() serves the cache immediately, so re-reading it after each event is cheap.
                let inventory = await system.inventory()
                // New displays reach the Arranger as an inventory, which re-plans every shown desk (TILE-03). So does
                // the first complete inventory, which a saved layout waits for (SAFE-06).
                var feed = !self.fedCompleteInventory && inventory.initialRefreshComplete
                if case .displaysChanged = event { feed = true }
                if feed {
                    self.fedCompleteInventory = self.fedCompleteInventory || inventory.initialRefreshComplete
                    await self.run(self.arranger.handle(.inventory(inventory), now: .now))
                }
                self.onInventory?(inventory)
            }
        }
    }

    /// Whether the event tap is running: drags are detected only while it is (the Debug line).
    public var isTapRunning: Bool { tap.isRunning }

    /// Starts the event tap and its single reader, and the watchdog. False when macOS refuses the tap (no Accessibility
    /// access). PaneMacApp calls it once tracking has started; tests that only arrange never install a tap.
    @discardableResult
    public func startTap() -> Bool {
        if previews == nil { previews = PreviewPresenter() }  // the panels exist before the first drag, never per drag

        startWatchdog()
        guard tap.start() else {
            if !loggedTapRefusal { logger.error("event tap refused; drags are not detected") }
            loggedTapRefusal = true
            return false
        }
        loggedTapRefusal = false
        if tapReader == nil {
            tapReader = Task { [weak self, tap] in
                for await event in tap.events {
                    guard let self else { return }
                    await self.handle(event)
                }
            }
        }
        return true
    }

    /// Takes the tap down (Accessibility left `.ready`, Pitfall 4). Hotkeys and the menu keep working.
    public func stopTap() {
        tap.stop()
        dragPoller.stop()
        previews?.show(nil, on: nil)
    }

    /// Every 2 s and whenever an app activates: the tap's watchdog, and a restart once access is back (Pitfall 4).
    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.watchdogTick()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
    }

    private func watchdogTick() {
        guard tap.isRunning else {
            if tapAllowed, isReady() { startTap() }
            return
        }
        tap.watchdogTick()
        guard !tap.isRunning else { return }
        logger.error("event tap refused by macOS; taken down, drags are not detected")
        loggedTapRefusal = true
        dragPoller.stop()
        previews?.show(nil, on: nil)
    }

    /// Accessibility access changed (PermissionController's phase entered or left `.ready`).
    /// Losing access takes the tap down at once; hotkeys and the menu keep working, only drags stop.
    public func accessChanged(ready: Bool) {
        tapAllowed = ready
        if ready { startTap() } else { stopTap() }
    }

    /// The green buttons the tap last got, so an unchanged set is not swapped in again.
    private var publishedGreenButtons: [UInt32: CGRect] = [:]

    /// Hands the tap the global green-button rect of every present, dockable, non-excluded window on a desk, by the CG
    /// window it shows; none while paused (TILE-06, T-03-34). Runs after every Arranger change, so the rects follow
    /// every frame Pane knows of without an AX read.
    private func publishGreenButtons() {
        var rects: [UInt32: CGRect] = [:]
        if arranger.pauseReasons.isEmpty {
            for info in arranger.windows.values where info.kind == .dockable && !info.isExcluded && info.state == .present {
                guard let offset = info.greenButton, arranger.deskKey(of: info.window) != nil else { continue }
                rects[info.visibleMemberID ?? info.window.windowID] = CGRect(
                    x: info.frame.x + offset.x, y: info.frame.y + offset.y, width: offset.width, height: offset.height)
            }
        }
        guard rects != publishedGreenButtons else { return }
        publishedGreenButtons = rects
        tap.setGreenButtons(rects)
    }

    /// The tracked window showing CG window `id` (`visibleMemberID ?? windowID`).
    private func trackedWindow(cgID id: UInt32) -> PaneModel.WindowRef? {
        arranger.windows.values.first { ($0.visibleMemberID ?? $0.window.windowID) == id }?.window
    }

    /// Feeds one tap event to the Arranger. The press window is resolved on mouse-down only.
    private func handle(_ event: TapEvent) async {
        if case .greenButton(let id) = event.kind {
            guard let window = trackedWindow(cgID: id) else { return }
            await run(arranger.handle(.greenButton(window), now: .now))
            return
        }
        let kind: PointerEvent.Kind
        switch event.type {
        case .leftMouseDown: kind = .down
        case .leftMouseDragged: kind = .dragged
        case .leftMouseUp: kind = .up
        case .flagsChanged: kind = .flagsChanged
        default: return
        }
        let location = Point(x: event.location.x, y: event.location.y)
        let press = kind == .down ? pressWindow(underPointer: event.windowUnderPointer, at: location) : nil
        let pointer = PointerEvent(kind: kind, location: location, modifiers: Self.modifiers(event.flags), pressWindow: press)
        await run(arranger.handle(.pointer(pointer), now: .now))
    }

    static func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        return modifiers
    }

    /// The tracked window the press is on: the CG window under the pointer mapped through the inventory
    /// (`visibleMemberID ?? windowID`); failing that, the topmost tracked window containing the point in CG list order.
    /// Pure geometry, no AX.
    private func pressWindow(underPointer number: Int64, at point: Point) -> PaneModel.WindowRef? {
        let tracked = arranger.windows.values
        if number > 0, let found = trackedWindow(cgID: UInt32(truncatingIfNeeded: number)) { return found }
        guard let list = CGWindowList.onScreenFrontToBack() else { return nil }
        for entry in list where entry.layer == 0 && entry.bounds.contains(point) {
            // A window under a synthetic ID matches its CG entry by app and frame.
            let synthetic = tracked.first { $0.window.pid == entry.pid && $0.window.identity.isSyntheticWindowID && $0.frame == entry.bounds }
            if let found = trackedWindow(cgID: entry.windowID) ?? synthetic?.window { return found }
        }
        return nil
    }

    /// Starts the 60 Hz frame poll of the pressed window (its visible tab), or stops it. A synthetic ID has no CG window.
    private func pollDragFrame(_ window: PaneModel.WindowRef?) {
        guard let window, let info = arranger.windows[window.identity] else {
            dragPoller.stop()
            return
        }
        let id = info.visibleMemberID ?? window.windowID
        guard id < WindowIdentity.syntheticIDBase else { return }
        dragPoller.start(windowID: id) { [weak self] frame in
            Task { [weak self] in
                guard let self else { return }
                await self.run(self.arranger.handle(.dragFrame(window.identity, frame), now: .now))
            }
        }
    }

    /// Whether Pane has working Accessibility access; PaneMacApp wires it to the permission state.
    public var isReady: () -> Bool = { true }

    /// The frontmost app's focused tracked window and the access state: what availability depends on.
    public func commandContext() -> CommandContext {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return CommandContext(focused: pid.flatMap { system.focusedWindow(of: $0) }?.window, ready: isReady())
    }

    /// The refusal sound; a seam for tests.
    var beep: () -> Void = { NSSound.beep() }

    /// Every route (hotkey, menu item, URL) calls this. A command that cannot act beeps (UI-SPEC: no hotkey fails
    /// silently), except from a URL, whose user may not be at the keyboard (Pitfall 21).
    public func dispatch(_ command: Command, from source: CommandSource = .hotkey) async {
        let refuse = source == .url ? {} : beep
        if command == .toggleExcludeFrontmost {
            // The store's onChange hands the list to the window system, whose windowChanged events float the windows.
            if let exclusions, Self.toggleExclusion(of: NSWorkspace.shared.frontmostApplication, in: exclusions) { return }
            refuse()
            return
        }
        let context = commandContext()
        guard arranger.availability(command, context: context) else {
            refuse()
            return
        }
        let effects = arranger.handle(.command(command, focused: context.focused), now: .now)
        await run(source == .url ? effects.filter { $0 != .beep } : effects)
    }

    public func dispatch(_ command: Command, focused: PaneModel.WindowRef?) async {
        await run(arranger.handle(.command(command, focused: focused), now: .now))
    }

    /// The bundle ID Don't Arrange would toggle for `app`: a regular app other than Pane, with a valid bundle ID.
    static func excludableBundleID(of app: NSRunningApplication?) -> String? {
        guard let app, let id = app.bundleIdentifier, app.processIdentifier != getpid(), app.activationPolicy == .regular,
            ExclusionStore.isValid(id)
        else { return nil }
        return id
    }

    /// Toggles `app`'s exclusion; false, with nothing changed, when it does not qualify.
    static func toggleExclusion(of app: NSRunningApplication?, in store: ExclusionStore) -> Bool {
        guard let id = excludableBundleID(of: app) else { return false }
        return (try? store.toggle(id)) != nil  // toggle only throws for an invalid ID, which was ruled out above
    }

    private func run(_ effects: [ArrangerEffect]) async {
        for effect in effects {
            switch effect {
            case .perform(let commands):
                await system.perform(commands)
            case .requery(let revived):
                let states = await LifecycleSync.requery(revived, using: system)
                await run(arranger.handle(.requeried(revived, states), now: .now))
            case .beep:
                beep()
            case .announce(let text):
                postAnnouncement(text)
            case .fault(let message):
                logger.error("\(message, privacy: .public)")
            case .info(let message):
                logger.info("\(message, privacy: .public)")
            case .notice(let notice):
                present(notices.post(notice, at: .now))
            case .save(.debounced):
                saveTimer.set(.now + .milliseconds(500)) { [weak self] in self?.write() }
            case .save(.now):
                write()
            case .openFinderWindow:
                // Its own task: an AX press waits on Finder, which must never hold up the effects behind it.
                Task { await openFinderWindow() }
            case .wake(let instant):
                wake.set(instant) { [weak self] in
                    guard let self else { return }
                    await self.run(self.arranger.handle(.tick, now: .now))
                }
            case .pollDragFrame(let window):
                pollDragFrame(window)
            case .preview(let state, let displayUUID):
                previews?.show(state, on: displayUUID)
            case .flashBlocked(let rect, let displayUUID):
                previews?.flashBlocked(rect, on: displayUUID)
            case .gapHandles(let handles, let displayUUID):
                gapPanels.show(handles, on: displayUUID)
            }
        }
    }

    /// Presses Finder's ⌘N menu item on Finder's AX thread (RESEARCH Pattern 14): no Apple Events, no Automation
    /// prompt. A quit Finder is launched first and pressed once Pane tracks it, within most of the Arranger's 2 s wait.
    /// With no such item to press, Pane opens the home folder instead; the Arranger docks whatever new window comes.
    private func openFinderWindow() async {
        let bundleID = Arranger.finderBundleID
        var giveUp = ContinuousClock.now
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                logger.error("could not launch Finder: \(String(describing: error), privacy: .public)")
            }
            giveUp = .now + .milliseconds(1500)
        }
        while true {
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
            if let pid, await system.pressNewWindowItem(pid: pid) { return }
            if ContinuousClock.now >= giveUp { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        logger.info("no New Finder Window item to press; opening the home folder")
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Before Pane exits (SAFE-01, D-15): every parked or off-screen window Pane may move goes back on screen, within
    /// `limit` in total; docked windows stay where they are. Synchronous, so it never waits on MainActor work
    /// (Pitfall 14). Returns how many writes finished.
    @discardableResult
    public func restoreForTermination(limit: Duration = .seconds(2)) -> Int {
        let docked = Set(arranger.world.desks.values.flatMap { $0.tree.windows.map(\.identity) })
        let plan = Recovery.terminationPlan(
            windows: Array(arranger.windows.values), homeFrames: arranger.homeFrames, displays: arranger.displays, docked: docked)
        guard !plan.isEmpty else { return 0 }
        let (seconds, attoseconds) = limit.components
        let restored = system.restoreForTermination(plan, deadline: .now() + Double(seconds) + Double(attoseconds) / 1e18)
        logger.info("quit restore: \(restored, privacy: .public) of \(plan.count, privacy: .public) windows")
        return restored
    }

    /// Writes layout.json one last time with `cleanExit: true` when Pane quits normally. Nothing is written if
    /// tracking never started, so a quit before the first sweep cannot replace a saved layout with an empty one.
    public func writeCleanExit() {
        guard started else { return }
        saveTimer.cancel()
        survivalTimer.cancel()  // a later write would record the clean exit as unclean
        write(cleanExit: true)
    }

    private func write(cleanExit: Bool = false) {
        guard let store else { return }
        let snapshot = arranger.snapshot
        let session = SessionRecord(
            cleanExit: cleanExit, launchedAt: launchedAt, recoveryLaunch: launchMode != .normal, survivedMinute: survivedMinute)
        let file = LayoutFile(world: snapshot.world, homeFrames: snapshot.homeFrames, session: session)
        do {
            try store.save(file)
        } catch {
            logger.error("could not save \(LayoutStore.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Shows or hides the toast as the queue says, and schedules the visible notice's expiry.
    private func present(_ change: NoticeQueue<Notice>.Change) {
        switch change {
        case .show(let notice):
            toast.show(NoticeCopy.text(for: notice, appName: Self.appName), glyph: NoticeCopy.glyph(for: notice), on: displayUUID(of: notice))
            if let at = notices.expiresAt {
                noticeExpiry.set(at) { [weak self] in
                    guard let self else { return }
                    self.present(self.notices.expire(at: .now))
                }
            }
        case .hide:
            toast.hide()
        case .unchanged:
            break
        }
    }

    /// The display the toast belongs on: the first named window's.
    private func displayUUID(of notice: Notice) -> String? {
        switch notice {
        case .lostRoom(let windows): windows.first.flatMap { arranger.windows[$0.identity]?.displayUUID }
        case .finderNoWindow, .floatedAll, .arrangeLeftovers, .crashRecovered, .crashLoop, .restored: nil
        }
    }

    private static func appName(_ window: PaneModel.WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID
    }
}

/// Where a command came from: only a URL dispatch is silent when it cannot act.
public enum CommandSource { case hotkey, menu, url }

/// One pending wake-up: `set` replaces any earlier one, so only the latest instant fires.
@MainActor final class WakeTimer {
    private var task: Task<Void, Never>?

    func cancel() { task?.cancel() }

    func set(_ instant: ContinuousClock.Instant, _ fire: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(until: instant, clock: .continuous)
            guard !Task.isCancelled else { return }
            await fire()
        }
    }
}
