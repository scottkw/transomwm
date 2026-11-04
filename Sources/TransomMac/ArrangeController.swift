import AppKit
import KeyboardShortcuts
import TransomEngine
import TransomModel
import TransomPrivate
import os

/// The thin MainActor shell around `Arranger` (RESEARCH Pattern 1). It is the only reader of `system.events`
/// (Pitfall 2), fans each re-read inventory out through `onInventory`, and runs the Arranger's effects in order.
/// Every window command goes through `system.perform`, where `ExclusionFilter.admit` guards it (02-13).
@MainActor public final class ArrangeController {
    private let system: AXWindowSystem
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "arrange")
    private let displaysLog = Logger(subsystem: "com.eightabyte.transom", category: "displays")
    private let viewsLog = Logger(subsystem: "com.eightabyte.transom", category: "views")
    /// The Phase 6 Space-switch path, shared by the overview and going to a saved view.
    private lazy var spaceSwitcher = SpaceSwitcher(spaces: { [unowned self] in self.system.spacesSnapshot })
    /// The N15 whose text the reveal announcement carries: its toast says nothing (08 UI-SPEC Announcements).
    private var joinedNotice: Notice?
    /// The saved arrangement differs from the live displays: one settle runs once the saved layout is re-attached.
    private var launchSettlePending = false
    /// One debug line per press and per release (WR-03); see them with `log stream --level debug`.
    private let dragLog = Logger(subsystem: "com.eightabyte.transom", category: "drag")
    /// What the press has seen so far: dragged tap events, and the first and last CG samples of the frame poll.
    private var dragTrace: (dragged: Int, polls: Int, firstCG: Rect?, lastCG: Rect?) = (0, 0, nil, nil)
    private var started = false
    /// Each re-read inventory: the menu header and the Tracked Windows feed.
    public var onInventory: ((WindowInventory) -> Void)?
    /// Each window-system event, just before the Arranger gets it: the order integration tests read (08-04 Assumption A1).
    var onEvent: ((WindowEvent) -> Void)?
    public private(set) var arranger: Arranger {
        didSet {
            publishGreenButtons()
            zoomInput.publish()
            gestures.publish()
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
    private(set) var previews: PreviewPresenter?
    /// The gap handles (TILE-05). A panel is made only when a handle first shows.
    private let gapPanels = GapHandlePanels()
    /// The collapsed blocks at rest (ZOOM-13). A panel is made only when a block first shows.
    private let collapsedPanels = CollapsedPanels()
    /// The tab strips (TABS-02). A panel is made only when a group's strip first shows.
    let tabStripPanels = TabStripPanels()
    let placeholderPanels = PlaceholderPanels()
    private let closeGroupConfirmation = CloseGroupConfirmation()
    private let ghostPanel = TearOffGhostPanel()
    /// The temporary Esc hotkeys while a tear-off ghost shows (UI-SPEC Surface 4), as for the zoom band.
    private var tearOffEscapes: [Task<Void, Never>] = []
    /// Whether Accessibility access is ready, so the watchdog may bring the tap back.
    private var tapAllowed = true
    private var watchdog: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var loggedTapRefusal = false

    /// Whether zoom is on (the `zoomEnabled` preference; tests default to off, D-D). Turn Off / Turn On Zoom change it.
    private var zoomEnabled: Bool
    public var isZoomEnabled: Bool { zoomEnabled }
    private let zoomInputLog = Logger(subsystem: "com.eightabyte.transom", category: "zoomInput")
    private let cameraLog = Logger(subsystem: "com.eightabyte.transom", category: "camera")
    /// Fires after each reveal and when zoom turns off (the status item's "zoomed in" description).
    public var onViewChanged: (() -> Void)?
    /// Turn Off Zoom in progress: the displays whose move home has not revealed yet.
    private var turningOff = false
    /// Gestures stay disarmed through it, so none takes the home move over (WR-09).
    var isTurningOff: Bool { turningOff }
    private var awaitingHome: [String: UInt64] = [:]
    private let zoomOffFallback = WakeTimer()
    /// The stage side of camera moves, made on the first `.cameraMove`; never with zoom off.
    private(set) var zoomController: ZoomController?
    var hasZoomController: Bool { zoomController != nil }
    /// The overview (06-06), made on the first Show Overview; never with zoom off.
    private(set) var overviewController: OverviewController?
    /// The Mission Control takeover (06-10), set by the app; nil in tests that don't own one.
    var takeover: MissionControlTakeover? {
        didSet {
            guard let takeover else { return }
            takeover.onTrigger = { [weak self] in Task { await self?.missionControlKey() } }
            takeover.post = { [weak self] in self?.post($0) }
            takeover.announce = { postAnnouncement($0) }
            if takeover.state == .offApplyFailed { post(.takeoverApplyFailed) }  // the launch apply ran before this wiring
        }
    }
    /// The last overview's open time, tiles and snapshots (Debug S6); kept across zoom off.
    private(set) var lastOverview: (ms: Int, windows: Int, snapshots: Int)?
    /// Pointer input for the camera: ⌘⇧-drag, pick mode, double-clicks (04-06).
    private lazy var zoomInput = ZoomInput(controller: self, tap: tap)
    /// The gesture session tap (05-03): runs only while zoom is on and the mouse tap runs (D-07).
    private let gestureTap = GestureTap()
    private(set) lazy var gestures = GestureController(tap: gestureTap, controller: self)
    public var isGestureTapRunning: Bool { gestureTap.isRunning }
    /// Multitouch devices are open (05-07): only while the gesture tap runs, never with zoom off (D-07).
    public var isMultitouchRunning: Bool { gestures.multitouch.isRunning }
    /// The Debug G4 value.
    public var multitouchStatus: GestureCopy.Multitouch { gestures.multitouch.status }
    /// Debug ▸ Turn Multitouch Back On (WR-08): forgets a tripped crash canary; with gestures running, the trackpads open
    /// at once, otherwise at the next gesture tap start.
    public func turnMultitouchBackOn() {
        MultitouchCanary.turnBackOn()
        if gestures.isActive { gestures.multitouch.start() }
    }
    /// The last start attempt was refused (the Debug line tells "unavailable" from "not running").
    public private(set) var gestureTapFailedToStart = false
    var isRectZoomActive: Bool { zoomInput.isBandActive }

    public init(
        system: AXWindowSystem, store: LayoutStore? = nil, exclusions: ExclusionStore? = nil, gap: Double = 8, zoomEnabled: Bool = false
    ) {
        self.system = system
        self.store = store
        self.exclusions = exclusions
        self.zoomEnabled = zoomEnabled
        arranger = Arranger(gap: gap)
        system.releaseFramesBeforeExcluding = { [weak self] bundleIDs in self?.arranger.releaseFrames(forExcluding: bundleIDs) ?? [:] }
        gapPanels.onDrag = { [weak self] handle, delta, ended in
            Task { [weak self] in
                guard let self else { return }
                await self.run(self.arranger.handle(.gapDrag(handle, delta: delta, ended: ended), now: .now))
            }
        }
        collapsedPanels.onDoubleClick = { [weak self] window, uuid in
            Task { await self?.openBlock(window, displayUUID: uuid) }
        }
        tabStripPanels.onAction = { [weak self] action in
            guard let self else { return }
            // Close Group asks first (UI-SPEC Surface 4); the strip's × is its only trigger.
            if case .closeGroup(let group) = action, let count = tabStripPanels.memberCount(of: group),
                !closeGroupConfirmation.confirm(count: count)
            {
                logger.info("group \(group.node, privacy: .public): close canceled")
                return
            }
            Task { await self.tabAction(action) }
        }
        tabStripPanels.bounds = { [weak self] window in
            let id = self?.arranger.windows[window.identity]?.visibleMemberID ?? window.windowID
            return id < WindowIdentity.syntheticIDBase ? DragFramePoller.bounds(of: id) : nil
        }
    }

    /// A new gap from the Gaps submenu: applied at once, or on Resume while paused (D-27).
    public func setGap(_ gap: Double) async {
        await run(arranger.handle(.gap(gap), now: .now))
    }

    /// Queues a toast from outside the Arranger (ConflictController's N7 and N8).
    public func post(_ notice: Notice) {
        logger.info("notice \(String(describing: notice), privacy: .public)")  // toasts don't show over VNC
        let change = notices.post(notice, at: .now)
        // A brief notice dropped behind a crash notice is still announced (08 UI-SPEC View toasts).
        if change == .unchanged, notice.isBrief, notice != joinedNotice { postAnnouncement(NoticeCopy.text(for: notice, appName: Self.appName)) }
        present(change)
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
            launchMode = Recovery.launchMode(previous: store.contents?.session, unreadable: store.loadError != nil)
            await run(arranger.handle(.launch(launchMode), now: .now))
            if let due = Recovery.survivedMinuteDue(launchedAt: .now, mode: launchMode) {
                survivalTimer.set(due) { [weak self] in
                    self?.survivedMinute = true
                    self?.write()
                }
            }
            if let saved = store.contents {
                let (world, layoutSets, views) = rekeyed(saved)
                await run(arranger.handle(
                    .restore(
                        world, homeFrames: saved.homeFrameMap, wantedFrames: saved.wantedFrameMap, arrangement: saved.arrangement,
                        layoutSets: layoutSets, views: views,
                        bootChanged: BootSession.changed(saved: saved.session.bootSession, current: BootSession.current())),
                    now: .now))
                launchSettlePending = !saved.arrangement.isUnknown && saved.arrangement != ArrangementID(inventory.displays.map(\.uuid))
            }
            // This launch's session record (cleanExit false) goes down at once, with the saved layout still in it. It says this
            // boot, which is right even now: after a boot change `.restore` has retired every saved identity.
            write()
        }
        fedCompleteInventory = inventory.initialRefreshComplete
        await run(arranger.handle(.inventory(inventory), now: .now))
        await settleIfLaunchArrangementChanged()
        takeover?.postCrashNotice()  // after the launch's N2/N3, so it queues behind them
        system.onDisplaysSettling = { [weak self] in
            guard let self else { return }
            self.overviewController?.interrupt(reason: .displayChange)
            // Synchronous, so no inventory from the change itself is fed before the Arranger is settling.
            let effects = self.arranger.handle(.displaysSettling, now: .now)
            Task { await self.run(effects) }
        }
        system.onDisplaysSettled = { [weak self] in
            Task { await self?.displaysSettled() }
        }
        if zoomEnabled { await run(arranger.handle(.zoomEnabled(true), now: .now)) }
        onInventory?(inventory)
        Task { [weak self, system] in
            for await event in system.events {
                guard let self else { return }
                // Before the replan, which sends the new desk's strips.
                if case .spaceChanged(let uuid, let space) = event {
                    self.tabStripPanels.spaceChanged(displayUUID: uuid, to: space)
                    self.placeholderPanels.spaceChanged(displayUUID: uuid, to: space)
                }
                self.onEvent?(event)
                await self.run(self.arranger.handle(.event(event), now: .now))
                if case .frameApplied(let window, _, _) = event { self.zoomController?.frameApplied(window.identity) }
                if case .spaceChanged(let uuid, let space) = event {
                    self.zoomInput.endPick(reason: "space changed")
                    self.overviewController?.interrupt(reason: .spaceChange)
                    if self.zoomEnabled { self.overview().spaceDidSettle(display: uuid, space: space) }  // D-03 visit capture
                    self.gestures.republish(reason: "space change")
                }
                // Back at the keyboard (⌘-Tab, a Dock click): pick mode's Esc hotkey must not keep Esc from that app (WR-02).
                if case .windowFocused = event { self.zoomInput.endPick(reason: "focus changed") }
                if case .displaysChanged = event {
                    self.zoomInput.endPick(reason: "displays changed")
                    self.overviewController?.displaysChanged()
                    self.zoomController?.displaysChanged()
                    self.zoomInput.publish()  // a move whose display went away never reveals
                    self.gestures.republish(reason: "display change")
                }
                if case .windowDestroyed(let window) = event {
                    self.zoomController?.windowClosed(window)
                    self.overviewController?.windowClosed(window)
                }
                if case .sessionPaused(true) = event { self.overviewController?.interrupt(reason: .sleep) }
                // A tile fades in or out; the CG list catches a new window that was not on screen yet at its creation.
                switch event {
                case .windowCreated, .liveWindowsChanged: self.overviewController?.windowsChanged()
                default: break
                }
                // inventory() serves the cache immediately, so re-reading it after each event is cheap.
                let inventory = await system.inventory()
                // New displays reach the Arranger as an inventory, which re-plans every shown desk (TILE-03). So does
                // every complete inventory until a saved layout is re-attached, since it waits for an unlocked session
                // and a usable CG list (SAFE-06, CR-03), and a changed CG list while a saved window is dormant, whose
                // `liveWindows` prunes the ones that closed (G-03-8).
                // New displays arrive through `.displaysSettled` (D-11); nothing is fed while they settle.
                var feed = (self.arranger.awaitsRestore || !self.fedCompleteInventory) && inventory.initialRefreshComplete
                if case .liveWindowsChanged = event, self.arranger.hasDormantWindows { feed = true }
                if feed, !self.arranger.settling {
                    self.fedCompleteInventory = self.fedCompleteInventory || inventory.initialRefreshComplete
                    await self.run(self.arranger.handle(.inventory(inventory), now: .now))
                    await self.settleIfLaunchArrangementChanged()
                }
                self.onInventory?(inventory)
            }
        }
    }

    /// Whether the event tap is running: drags are detected only while it is (the Debug line).
    public var isTapRunning: Bool { tap.isRunning }

    /// Starts the event tap and its single reader, and the watchdog. False when macOS refuses the tap (no Accessibility
    /// access). TransomMacApp calls it once tracking has started; tests that only arrange never install a tap.
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
        updateGestureTap(reason: "")
        return true
    }

    /// Takes the tap down (Accessibility left `.ready`, Pitfall 4). Hotkeys and the menu keep working.
    public func stopTap() {
        tap.stop()
        updateGestureTap(reason: "access lost")
        zoomInput.reset(reason: "tap stopped")
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
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                // ⌘-Tab sends no focused-window change, so pick mode must also end here (G-04-12).
                if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self?.zoomInput.endPick(reason: "app activated")
                    // The frontmost app changed (⌘-Tab, the Dock). Not on a focus change inside the app: a window that
                    // opens while the overview is open takes focus and fades its tile in instead (Surface 1 While open).
                    self?.overviewController?.interrupt(reason: .appSwitch)
                }
                self?.watchdogTick()
            }
        }
    }

    private func watchdogTick() {
        defer {
            gestureTap.watchdogTick()
            updateGestureTap(reason: "access lost")
            gestures.noteReEnables()
        }
        guard tap.isRunning else {
            if tapAllowed, isReady() { startTap() }
            return
        }
        tap.watchdogTick()
        guard !tap.isRunning else { return }
        logger.error("event tap refused by macOS; taken down, drags are not detected")
        loggedTapRefusal = true
        zoomInput.reset(reason: "tap stopped")
        dragPoller.stop()
        previews?.show(nil, on: nil)
    }

    /// Accessibility access changed (PermissionController's phase entered or left `.ready`).
    /// Losing access takes the tap down at once; hotkeys and the menu keep working, only drags stop.
    public func accessChanged(ready: Bool) {
        tapAllowed = ready
        if ready { startTap() } else { stopTap() }
        zoomInput.publish()
        gestures.publish()
    }

    /// Starts the gesture tap when zoom is on and the mouse tap runs, else stops it (D-07). A tap macOS took down is
    /// started again.
    func updateGestureTap(reason: String) {
        if zoomEnabled && tap.isRunning {
            guard !gestureTap.isRunning else { return }
            gestures.stop(reason: reason)
            gestureTapFailedToStart = !gestures.start()
        } else {
            gestures.stop(reason: reason)
        }
    }

    /// The green buttons the tap last got, so an unchanged set is not swapped in again.
    private var publishedGreenButtons: [UInt32: CGRect] = [:]

    /// Hands the tap the global green-button rect of every present, dockable, non-excluded window on a desk, by the CG
    /// window it shows; none while paused (TILE-06, T-03-34). Runs after every Arranger change, so the rects follow
    /// every frame Transom knows of without an AX read.
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
    func trackedWindow(cgID id: UInt32) -> TransomModel.WindowRef? {
        arranger.windows.values.first { ($0.visibleMemberID ?? $0.window.windowID) == id }?.window
    }

    /// Feeds one tap event to the Arranger. The press window is resolved on mouse-down only.
    private func handle(_ event: TapEvent) async {
        if case .zoom(let kind) = event.kind {
            await zoomInput.tapEvent(kind, event)
            return
        }
        // A press on a tab strip is the strip's own AppKit click: never a window drag on the window behind (Pitfall 4).
        let location = Point(x: event.location.x, y: event.location.y)
        let strip = event.type == .leftMouseDown
            ? tabStripPanels.panelNumber(underPointer: Int(event.windowUnderPointer), at: location) : nil
        let onStrip = strip != nil
        if event.type == .leftMouseDown, !onStrip { zoomInput.pointerDown(event) }
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
        let press = kind == .down && !onStrip ? pressWindow(underPointer: event.windowUnderPointer, at: location) : nil
        // A press on a tab may tear it off (Pattern 7); on a button or the background it is only the strip's click.
        // A ⌃-click opens the tab context menu, so it never tears the tab off (the menu's tracking drags must not).
        let tab = strip.flatMap { event.flags.contains(.maskControl) ? nil : tabStripPanels.member(atWindowNumber: $0, point: location) }
        let pointer = PointerEvent(kind: kind, location: location, modifiers: Self.modifiers(event.flags), pressWindow: press, pressTab: tab)
        let session = arranger.drag  // mouse-up ends it
        if kind == .dragged { dragTrace.dragged += 1 }
        await run(arranger.handle(.pointer(pointer), now: .now))
        if kind == .down { logPress(press, underPointer: event.windowUnderPointer, at: location) }
        if kind == .up, let session { logRelease(session, at: location) }
    }

    /// The drag log's press line: whether a session started, with its AX start frame and the CG bounds beside it.
    private func logPress(_ press: TransomModel.WindowRef?, underPointer number: Int64, at point: Point) {
        dragTrace = (0, 0, nil, nil)
        guard let press else {
            dragLog.debug("press at \(Self.text(point), privacy: .public) on CG window \(number, privacy: .public): no tracked window")
            return
        }
        let info = arranger.windows[press.identity]
        let cgID = info?.visibleMemberID ?? press.windowID
        let cg = Self.text(DragFramePoller.bounds(of: cgID))
        guard let session = arranger.drag else {
            dragLog.debug(
                "press on \(press.bundleID, privacy: .public) window \(press.windowID, privacy: .public) (CG \(number, privacy: .public)): no session; kind \(String(describing: info?.kind), privacy: .public) state \(String(describing: info?.state), privacy: .public) excluded \(String(describing: info?.isExcluded), privacy: .public) desk \(self.arranger.deskKey(of: press) != nil, privacy: .public) paused \(!self.arranger.pauseReasons.isEmpty, privacy: .public)"
            )
            return
        }
        dragLog.debug(
            "start \(press.bundleID, privacy: .public) window \(press.windowID, privacy: .public) (CG \(number, privacy: .public), member \(cgID, privacy: .public)) at \(Self.text(point), privacy: .public): AX \(Self.text(session.startFrame), privacy: .public) CG \(cg, privacy: .public)"
        )
    }

    /// The drag log's release line: how the press was classified and what the release did with it.
    private func logRelease(_ session: DragSession, at point: Point) {
        let travel = hypot(session.pointer.x - session.start.x, session.pointer.y - session.start.y)
        let upTravel = hypot(point.x - session.start.x, point.y - session.start.y)
        let info = arranger.windows[session.window.identity]
        let cgNow = Self.text(DragFramePoller.bounds(of: info?.visibleMemberID ?? session.window.windowID))
        dragLog.debug(
            "end \(session.window.bundleID, privacy: .public) window \(session.window.windowID, privacy: .public): kind \(String(describing: session.kind), privacy: .public) travel \(travel, privacy: .public) (up \(upTravel, privacy: .public)) dragged \(self.dragTrace.dragged, privacy: .public) polls \(self.dragTrace.polls, privacy: .public) polling \(session.polling, privacy: .public) AX start \(Self.text(session.startFrame), privacy: .public) first CG \(Self.text(self.dragTrace.firstCG), privacy: .public) last CG \(Self.text(self.dragTrace.lastCG), privacy: .public) CG at up \(cgNow, privacy: .public) dry runs \(session.dryRuns, privacy: .public) decision \(session.decisionSummary, privacy: .public) shown \(String(describing: session.shown), privacy: .public)"
        )
    }

    private static func text(_ point: Point) -> String { "\(point.x),\(point.y)" }
    private static func text(_ rect: Rect?) -> String { rect.map { "\($0.x),\($0.y) \($0.width)x\($0.height)" } ?? "nil" }

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
    private func pressWindow(underPointer number: Int64, at point: Point) -> TransomModel.WindowRef? {
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
    private func pollDragFrame(_ window: TransomModel.WindowRef?) {
        guard let window, let info = arranger.windows[window.identity] else {
            dragPoller.stop()
            return
        }
        let id = info.visibleMemberID ?? window.windowID
        guard id < WindowIdentity.syntheticIDBase else { return }
        dragPoller.start(windowID: id) { [weak self] frame in
            Task { [weak self] in
                guard let self else { return }
                self.dragTrace.polls += 1
                if self.dragTrace.firstCG == nil { self.dragTrace.firstCG = frame }
                self.dragTrace.lastCG = frame
                // The dragged window is a group's selected member: its strip moves with it every poll (D-04).
                if let group = self.tabStripPanels.group(selecting: window) { self.tabStripPanels.follow(group, contentBounds: frame) }
                await self.run(self.arranger.handle(.dragFrame(window.identity, frame), now: .now))
            }
        }
    }

    /// Whether Transom has working Accessibility access; TransomMacApp wires it to the permission state.
    public var isReady: () -> Bool = { true }

    /// The frontmost app's focused tracked window and the access state: what availability depends on.
    public func commandContext(from source: CommandSource = .hotkey) -> CommandContext {
        let pid = Self.commandPID(
            frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier, beforeTransom: system.lastOtherFrontmostPID, from: source)
        return CommandContext(
            focused: pid.flatMap { system.focusedWindow(of: $0) }?.window, ready: isReady(), displayUUID: pointerDisplay().uuid)
    }

    /// The app whose focused window a command acts on: the frontmost one, except that a URL arriving with Transom
    /// frontmost acts on the app frontmost before it, since `open` activates Transom to deliver the URL (07 UAT Bug 2).
    static func commandPID(
        frontmost: Int32?, beforeTransom: Int32?, from source: CommandSource, own: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> Int32? {
        source.isSilent && frontmost == own ? beforeTransom : frontmost
    }

    /// The pointer in top-left global points and the display under it: where every camera command acts (UI-SPEC: hotkeys,
    /// menu items and URLs act on the pointer's display; the status menu opens on it).
    func pointerDisplay() -> (point: Point, uuid: String?) {
        let location = NSEvent.mouseLocation
        let point = Point(x: location.x, y: Double(NSScreen.screens.first?.frame.height ?? 0) - location.y)
        let displays = arranger.displays
        let uuid = displays.first { $0.frame.contains(point) }?.uuid
            ?? Coordinates.displayUUID(for: Rect(x: point.x, y: point.y, width: 0, height: 0), among: displays)
        return (point, uuid)
    }

    /// The command-line tool's channel (D-07); the app keeps it for its lifetime and the Debug submenu reads it.
    var cliListener: CLIListener?

    /// The refusal sound; a seam for tests.
    var beep: () -> Void = { NSSound.beep() }

    /// Every route (hotkey, menu item, URL) calls this. A command that cannot act beeps (UI-SPEC: no hotkey fails
    /// silently), except from a URL, whose user may not be at the keyboard (Pitfall 21).
    public func dispatch(_ command: Command, from source: CommandSource = .hotkey) async {
        guard let pending = viewSwitch(for: command) else { return await act(on: decide(command, from: source).effects) }
        zoomInput.noteCommand()
        overviewController?.interrupt(reason: .command)
        guard await switchSpace(pending, from: source) else { return }
        await act(on: decide(command, from: source, afterSwitch: true).effects)
    }

    /// The CLI's way in (D-07): the reply leaves now and the command acts after it. A view on another Space replies `ok`
    /// when its switch starts; a later switch failure shows only on screen, as "accepted" allows (RESEARCH A8).
    public func answerCLI(_ command: Command) -> String {
        if viewSwitch(for: command) != nil {
            Task { await dispatch(command, from: .cli) }
            return CLIProtocol.ok
        }
        let decision = decide(command, from: .cli)
        Task { await act(on: decision.effects) }
        return decision.reply
    }

    /// What `command` does now, before any effect runs: the CLI's reply and the effects, already silenced for a URL or CLI
    /// route. Going to a view on another Space must switch first (`viewSwitch(for:)`); here the engine would refuse it.
    public func decide(_ command: Command, from source: CommandSource, afterSwitch: Bool = false) -> (reply: String, effects: [ArrangerEffect]) {
        zoomInput.noteCommand()
        let effects = refusableEffects(of: command, from: source, afterSwitch: afterSwitch)
        return (Self.cliReply(for: effects), source.isSilent ? Self.silenced(effects, of: command) : effects)
    }

    private func refusableEffects(of command: Command, from source: CommandSource, afterSwitch: Bool) -> [ArrangerEffect] {
        if command == .toggleExcludeFrontmost {
            // The store's onChange hands the list to the window system, whose windowChanged events float the windows.
            if let exclusions, Self.toggleExclusion(of: NSWorkspace.shared.frontmostApplication, in: exclusions) { return [] }
            return [.beep]
        }
        if command != .camera(.overview) { overviewController?.interrupt(reason: .command) }
        if case .camera(let camera) = command { return cameraEffects(camera, from: source, afterSwitch: afterSwitch) }
        let context = commandContext(from: source)
        if case .tabs(let tab) = command {
            // The engine refuses with an announcement (Surface 7); a URL refusal only logs.
            let via: TabLeaveSource = switch source { case .hotkey: .hotkey; case .menu: .menu; case .url, .cli: .url }
            return arranger.handle(.tab(.command(tab, focused: context.focused, via: via), ready: context.ready), now: .now)
        }
        guard arranger.availability(command, context: context) else { return [.beep] }
        return arranger.handle(.command(command, focused: context.focused), now: .now)
    }

    /// What a URL or CLI route keeps of `effects`: no beep, and a refusal shows nothing on screen (Phase 3 rule, UI-SPEC
    /// N16). A camera command says nothing either way; its toasts still show.
    static func silenced(_ effects: [ArrangerEffect], of command: Command) -> [ArrangerEffect] {
        let quiet = if case .camera = command { true } else { effects.contains(.beep) }
        return effects.filter {
            switch $0 {
            case .beep, .tabAnnouncement(.refused), .notice(.viewEmpty), .notice(.viewDisplayGone), .notice(.viewNothingToSave): false
            case .announce: !quiet
            default: true
            }
        }
    }

    /// The CLI's reply to `effects` before they are silenced: a beep means refused, with the text VoiceOver would hear.
    static func cliReply(for effects: [ArrangerEffect]) -> String {
        guard effects.contains(.beep) else { return CLIProtocol.ok }
        for effect in effects {
            switch effect {
            case .announce(let text): return CLIProtocol.refused(text)
            case .tabAnnouncement(let announcement): return CLIProtocol.refused(TabCopy.announcement(announcement, appName: appName))
            case .notice(let notice): return CLIProtocol.refused(NoticeCopy.text(for: notice, appName: appName))
            default: continue
            }
        }
        return CLIProtocol.refused("")
    }

    private func act(on effects: [ArrangerEffect]) async {
        await run(effects)
        joinedNotice = nil
    }

    /// A camera command on the pointer's display. A refusal beeps and announces (Surface 1), except from a URL, which
    /// only logs; with zoom off a URL is ignored and logged (its hotkeys are disabled then, D-D) and the CLI is told.
    private func cameraEffects(_ camera: CameraCommand, from source: CommandSource, afterSwitch: Bool) -> [ArrangerEffect] {
        guard zoomEnabled else {
            if camera == .overview { logger.info("refused overview: zoom off") }
            if source.isSilent { zoomInputLog.info("\(String(describing: source), privacy: .public) \(String(describing: camera), privacy: .public) ignored: zoom off") }
            return source == .cli ? [.beep, .announce(CLICopy.zoomOff)] : []
        }
        let context = commandContext(from: source)
        if case .overview = camera {  // the shell's: it needs no pointer display and is allowed while paused
            guard context.ready else { return [.beep, .announce(OverviewCopy.refusedNotReady), .info("refused overview: not ready")] }
            if toggleOverview(trigger: String(describing: source)) { return [] }
            return [.beep, .announce(OverviewCopy.refusedFullScreen), .info("refused overview: full screen")]
        }
        let pointer = pointerDisplay()
        var target = pointer.uuid
        if case .view(let slot) = camera, context.ready {
            let route = viewRoute(slot, pointer: pointer.uuid)
            target = route.display
            if let destination = route.destination {
                viewsLog.info(
                    "go view \(slot.number, privacy: .public) via \(String(describing: source), privacy: .public): desk \(String(describing: destination.key), privacy: .public), \(destination.alive, privacy: .public) of \(destination.total, privacy: .public) windows, target \(String(describing: destination.target), privacy: .public)\(afterSwitch ? ", space switch" : "", privacy: .public)")
            }
        }
        var effects: [ArrangerEffect]
        if let uuid = target, context.ready {
            effects = arranger.handle(.camera(camera, displayUUID: uuid, focused: context.focused, pointer: pointer.point), now: .now)
        } else if !context.ready {  // the engine never sees "not ready"; the shell refuses for it
            let refusal = Navigator.Refusal.notReady
            effects = [.beep, .announce(refusal.announcement), .info("refused \(camera): \(refusal)")]
        } else {
            effects = [.beep, .info("refused \(camera): no display under the pointer")]
        }
        if camera == .zoomOutAll || camera == .stepOut {
            for case .cameraMove(let move) in effects { zoomInput.expectPick(moveID: move.id) }  // its reveal starts pick mode
        }
        // A view that moves the camera says one line, at the reveal: the toast stays quiet (Announcements).
        if case .view(let slot) = camera {
            for case .cameraMove(let move) in effects where effects.contains(.notice(.viewShown(slot, displayUUID: move.displayUUID))) {
                zoom().joinedView = (move.id, slot.number)
                joinedNotice = .viewShown(slot, displayUUID: move.displayUUID)
            }
        }
        return effects
    }

    /// D-03: the display going to view `slot` acts on (the pointer's when the engine will refuse: empty slot, paused, display
    /// gone) and the Space to show first when that is another one. Saved windows all gone on a Space no longer listed: no
    /// switch, the engine goes home there.
    private func viewRoute(_ slot: ViewSlot, pointer: String?) -> (display: String?, space: SpaceInfo?, destination: (key: DeskKey, target: ViewTarget, allGone: Bool, alive: Int, total: Int)?) {
        guard arranger.pauseReasons.isEmpty, !arranger.sessionPaused, let destination = arranger.viewDestination(slot: slot),
            let display = arranger.displays.first(where: { $0.uuid == destination.key.displayUUID })
        else { return (pointer, nil, nil) }
        let space = destination.key.spaceID.flatMap { id in
            id == display.currentSpaceID ? nil : system.spacesSnapshot?.displays.first { $0.displayUUID == display.uuid }?.spaces.first { $0.id == id }
        }
        return (display.uuid, space, destination)
    }

    /// The Space that must be shown before going to `command`'s view, when that is another one.
    private func viewSwitch(for command: Command) -> (slot: ViewSlot, display: String, space: SpaceInfo)? {
        guard case .camera(.view(let slot)) = command, zoomEnabled, isReady() else { return nil }
        let route = viewRoute(slot, pointer: nil)
        guard let display = route.display, let space = route.space else { return nil }
        return (slot, display, space)
    }

    /// False: the switch failed and was refused here, with the camera unchanged.
    /// shortcut: a second view pressed during a switch posts its own chords; serialize them if that shows up in use.
    private func switchSpace(_ pending: (slot: ViewSlot, display: String, space: SpaceInfo), from source: CommandSource) async -> Bool {
        let (slot, display, space) = pending
        let switched = await spaceSwitcher.switchTo(space: space.id, on: display)
        // RESEARCH Pitfall 7: the Arranger hears of the new Space from a later `.spaceChanged`, and plans its desk from that.
        let deadline = ContinuousClock.now + .milliseconds(500)
        while switched, arranger.displays.first(where: { $0.uuid == display })?.currentSpaceID != space.id, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard switched, arranger.displays.first(where: { $0.uuid == display })?.currentSpaceID == space.id else {
            viewsLog.info("refused view \(slot.number, privacy: .public): couldn't switch to space \(space.id, privacy: .public)")
            await run(source.isSilent ? [] : [.beep, .announce(OverviewCopy.couldNotSwitch(desktop: space.index))])
            return false
        }
        return true
    }

    /// A camera command from pointer input, on a given display with a given window (title-bar and Desktop double-clicks).
    func camera(_ camera: CameraCommand, displayUUID: String, focused: TransomModel.WindowRef?, pointer: Point) async {
        await run(arranger.handle(.camera(camera, displayUUID: displayUUID, focused: focused, pointer: pointer), now: .now))
    }

    public func dispatch(_ command: Command, focused: TransomModel.WindowRef?) async {
        await run(arranger.handle(.command(command, focused: focused), now: .now))
    }

    /// Registers Esc, ⇧Esc, ⌘Esc and ⌘⇧Esc (never ⌥⌘Esc, Force Quit) for the tear-off's duration; any cancels it.
    private func listenForTearOffEscape() {
        for task in tearOffEscapes { task.cancel() }
        tearOffEscapes = ZoomInput.escapeModifiers.map { modifiers in
            Task { [weak self] in
                for await key in KeyboardShortcuts.events(for: KeyboardShortcuts.Shortcut(.escape, modifiers: modifiers)) where key == .keyDown {
                    await self?.tabAction(.cancelTearOff)
                }
            }
        }
    }

    /// A tab action from a strip (and later the menu, hotkeys and URLs); the engine refuses it while paused or not ready.
    func tabAction(_ action: TabAction) async {
        await run(arranger.handle(.tab(action, ready: isReady()), now: .now))
    }

    /// The bundle ID Don't Arrange would toggle for `app`: a regular app other than Transom, with a valid bundle ID.
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
                logger.info("\(text, privacy: .public)")  // refusals are otherwise only a beep and a VoiceOver line
                postAnnouncement(text)
            case .fault(let message):
                logger.error("\(message, privacy: .public)")
            case .info(let message):
                logger.info("\(message, privacy: .public)")
            case .notice(let notice):
                post(notice)
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
            case .collapsedBlocks(let blocks, let displayUUID):
                collapsedPanels.show(blocks, on: displayUUID)
            case .tabStrips(let strips, let displayUUID):
                tabStripPanels.show(strips, on: displayUUID, space: arranger.displays.first { $0.uuid == displayUUID }?.currentSpaceID)
            case .placeholders(let tiles, let displayUUID):
                placeholderPanels.show(tiles, on: displayUUID, space: arranger.displays.first { $0.uuid == displayUUID }?.currentSpaceID)
            case .tabRevealed(let window):
                if zoomEnabled { zoom().captureRevealed(window) }
            case .checkClosePrompt(let window):
                // Its own task: the AX read waits on the app, which must never hold up the effects behind it.
                Task {
                    let showing = await system.showsSheet(window)
                    await run(arranger.handle(.closePrompt(window, showing: showing), now: .now))
                }
            case .raiseStrip(let group):
                tabStripPanels.raise(group)
            case .tearOffGhost(let ghost?):
                if ghostPanel.isShown {
                    ghostPanel.move(to: ghost.pointer)
                } else {
                    ghostPanel.show(ghost)
                    listenForTearOffEscape()
                }
            case .tearOffGhost(nil):
                ghostPanel.hide()
                for task in tearOffEscapes { task.cancel() }  // each stream unregisters its hotkey (T-07-17)
                tearOffEscapes = []
            case .tabAnnouncement(let announcement):
                let text = TabCopy.announcement(announcement, appName: Self.appName)
                logger.info("\(text, privacy: .public)")
                postAnnouncement(text)
            case .cameraMove(let move):
                guard zoomEnabled else {
                    // Never expected: zoom off never enables the engine's camera. Settle at once so windows stay right.
                    logger.fault("camera move \(move.id, privacy: .public) with zoom off; settling without a stage")
                    await settle(displayUUID: move.displayUUID, moveID: move.id)
                    continue
                }
                hidePanels(on: move.displayUUID)  // the stage draws the blocks and strips until the reveal
                zoom().run(move) { [weak self] id in
                    Task { await self?.settle(displayUUID: move.displayUUID, moveID: id) }
                }
                zoomInput.publish()  // no zoom presses taken until it reveals
            }
        }
    }

    /// A stage orders in on that display: the collapsed-block, tab strip and placeholder panels go out, since the stage
    /// draws all three.
    private func hidePanels(on displayUUID: String) {
        collapsedPanels.hide(on: displayUUID)
        tabStripPanels.hide(on: displayUUID)
        placeholderPanels.hide(on: displayUUID)
    }

    /// That display's stage is gone: every kind of panel fades back in over 120 ms.
    private func showPanels(on displayUUID: String) {
        collapsedPanels.fadeIn(on: displayUUID)
        tabStripPanels.fadeIn(on: displayUUID)
        placeholderPanels.fadeIn(on: displayUUID)
    }

    private func zoom() -> ZoomController {
        if let zoomController { return zoomController }
        let zoom = ZoomController()
        zoom.windowInfo = { [weak self] in self?.arranger.windows[$0] }
        zoom.announce = { postAnnouncement($0) }
        zoom.appName = { Self.appName($0) }
        zoom.isPointerBusy = { [weak self] in self?.arranger.isDragging ?? false }
        zoom.onRevealed = { [weak self] uuid, move in
            self?.showPanels(on: uuid)
            self?.revealed(uuid, moveID: move.id)
            self?.zoomInput.revealed(displayUUID: uuid, move: move)
        }
        zoom.onTileClick = { [weak self] uuid, id in
            Task { await self?.zoomInput.stageClick(cgID: id, displayUUID: uuid) }
        }
        zoom.onFollowEnded = { [weak self] uuid in
            self?.showPanels(on: uuid)
            self?.zoomInput.publish()
        }
        zoom.bringNoticesFront = { [weak self] in
            self?.toast.bringFront()
            self?.previews?.bringFront()
        }
        zoomController = zoom
        return zoom
    }

    private func overview() -> OverviewController {
        if let overviewController { return overviewController }
        let overview = OverviewController(
            arranger: { [unowned self] in self.arranger }, spaces: { [unowned self] in self.system.spacesSnapshot }, zoom: { [unowned self] in self.zoom() },
            switcher: spaceSwitcher)
        overview.onClosed = { [weak self] in
            guard let self else { return }
            for display in self.arranger.displays { self.showPanels(on: display.uuid) }
            self.gestures.publish()  // armed again
        }
        overview.onOpened = { [weak self] stats in self?.lastOverview = stats }
        overview.onSwitchFailed = { [weak self] text in Task { await self?.run([.beep, .announce(text)]) } }
        overview.focused = { [weak self] in self?.commandContext().focused }
        // AX lists a window only while its Space shows: read the app again before focusing (06-SPIKE, AX after switch).
        overview.focusWindow = { [weak self] window in
            guard let self else { return }
            await self.system.refresh(app: window.pid)
            await self.system.perform([.focus(window)])
        }
        // Frame Focused Window for the picked window: its leaf (or the Desktop tile) framed, focus at settle. Paused, the
        // camera stays put and the pick only focuses (Surface 1 Availability).
        overview.frameWindow = { [weak self] window, uuid in
            guard let self else { return }
            guard self.arranger.pauseReasons.isEmpty, let leaf = self.arranger.leafNode(of: window),
                let tree = self.arranger.deskKey(of: window).flatMap({ self.arranger.world[$0]?.tree })
            else { return await self.system.perform([.focus(window)]) }
            await self.zoom(to: Navigator.target(leaf, in: tree), displayUUID: uuid, focus: window)
        }
        overviewController = overview
        return overview
    }

    /// Opens or closes the overview with pick mode and any rubber band ended and the collapsed panels hidden (they would
    /// sit above it); gestures are disarmed while it is open. Every display in full screen refuses.
    /// False, with nothing shown, when it could not open.
    private func toggleOverview(trigger: String) -> Bool {
        let overview = overview()
        if !overview.isOpen {
            zoomInput.reset(reason: "overview")
            for display in arranger.displays { hidePanels(on: display.uuid) }
        }
        guard !overview.toggle(trigger: trigger) else {
            gestures.publish()
            return true
        }
        for display in arranger.displays { showPanels(on: display.uuid) }
        return false
    }

    /// A taken Mission Control chord (Surface 5): dismisses or opens the overview; when it can't open, macOS Mission
    /// Control through CoreDock; without CoreDock, beep and the overview refusal.
    func missionControlKey() async {
        let log = Logger(subsystem: "com.eightabyte.transom", category: "missionControl")
        let ready = commandContext().ready
        let coreDock = Capabilities.isAvailable(.coreDock)
        var action = TakeoverPolicy.trigger(overviewOpen: overviewController?.isOpen == true, canOpen: zoomEnabled && ready, coreDockAvailable: coreDock)
        if action == .dismiss || action == .open {
            if toggleOverview(trigger: "missionControlKey") { return log.info("mission control key → overview") }
            action = TakeoverPolicy.trigger(overviewOpen: false, canOpen: false, coreDockAvailable: coreDock)
        }
        if action == .missionControl, CoreDock.send(CoreDock.missionControl) { return log.info("mission control key → macOS Mission Control") }
        log.info("mission control key → refused")
        await run([.beep, .announce(ready ? OverviewCopy.refusedFullScreen : OverviewCopy.refusedNotReady)])
    }

    /// Pick mode ends (a taken gesture, 05-05).
    func endPick(reason: String) { zoomInput.endPick(reason: reason) }
    /// Pick mode is on (tests).
    var isPicking: Bool { zoomInput.isPicking }

    /// The stage a gesture follows on (05-04), made with zoom on like a move's.
    func followStage() -> ZoomController { zoom() }

    /// A gesture's stage orders in: as for `.cameraMove`, collapsed panels hide and zoom presses wait for the end.
    @discardableResult func beginFollow(_ move: CameraMove, gesture: String) -> Bool {
        hidePanels(on: move.displayUUID)
        guard zoom().beginFollow(move, gesture: gesture) else {
            showPanels(on: move.displayUUID)
            return false
        }
        zoomInput.publish()
        return true
    }

    /// Answers a finished stage move: the engine commits the view and plans the writes, and the stage learns which
    /// read-backs to wait for before any write goes out.
    private func settle(displayUUID: String, moveID: UInt64) async {
        let effects = arranger.handle(.cameraSettle(displayUUID: displayUUID, moveID: moveID), now: .now)
        let writes = effects.flatMap { effect -> [WindowCommand] in if case .perform(let commands) = effect { commands } else { [] } }
        zoomController?.beginSettle(displayUUID: displayUUID, moveID: moveID, writes: writes)
        await run(effects)
    }

    private func revealed(_ uuid: String, moveID: UInt64) {
        zoomInput.publish()
        onViewChanged?()
        // Only the home move's own reveal counts: an older move revealing first must not end zoom early (WR-06).
        guard awaitingHome[uuid] == moveID else { return }
        awaitingHome[uuid] = nil
        guard awaitingHome.isEmpty else { return }
        Task { await finishZoomOff() }
    }

    /// Turn Off Zoom (D-D): every zoomed display moves home first, then, once those moves have revealed, the engine drops
    /// the camera (collapsed windows float with N1), every zoom piece goes and the zoom hotkeys are disabled. Turn On Zoom
    /// moves nothing. Either way the choice is saved as the `zoomEnabled` preference.
    public func setZoomEnabled(_ on: Bool) async {
        UserDefaults.standard.set(on, forKey: ZoomController.enabledKey)
        guard on else {
            guard zoomEnabled, !turningOff else { return }
            turningOff = true
            takeover?.zoomChanged(on: false)  // F3 goes back to macOS at once, not after the home moves
            gestures.publish()
            zoomInput.reset(reason: "zoom off")
            for display in arranger.displays {
                let effects = arranger.handle(.zoomTo(.home, displayUUID: display.uuid), now: .now)
                for case .cameraMove(let move) in effects { awaitingHome[display.uuid] = move.id }
                await run(effects)
            }
            guard awaitingHome.isEmpty else {
                // A move that never reveals (its display went away) must not keep zoom on forever: settle cap + fades < 3 s.
                zoomOffFallback.set(.now + .seconds(3)) { [weak self] in await self?.finishZoomOff() }
                return
            }
            await finishZoomOff()
            return
        }
        guard !zoomEnabled else { return }
        zoomEnabled = true
        zoomInput.publish()
        updateGestureTap(reason: "")
        await run(arranger.handle(.zoomEnabled(true), now: .now))
        Hotkeys.setZoomHotkeys(enabled: true)
        takeover?.zoomChanged(on: true)
        postAnnouncement(ZoomCopy.zoomOnAnnouncement)
        cameraLog.info("zoom on")
    }

    private func finishZoomOff() async {
        guard turningOff else { return }
        turningOff = false
        awaitingHome = [:]
        zoomOffFallback.cancel()
        zoomEnabled = false
        zoomInput.publish()
        updateGestureTap(reason: "zoom off")
        let effects = arranger.handle(.zoomEnabled(false), now: .now)
        let floated = effects.reduce(0) { count, effect in if case .notice(.lostRoom(let windows)) = effect { count + windows.count } else { count } }
        await run(effects)
        overviewController?.displaysChanged()  // closes it and drops its panels
        overviewController = nil
        zoomController?.purge()
        zoomController = nil
        for display in arranger.displays { showPanels(on: display.uuid) }  // a stage purged before its reveal leaves none out
        Hotkeys.setZoomHotkeys(enabled: false)
        postAnnouncement(ZoomCopy.zoomOffAnnouncement)
        cameraLog.info("zoom off (\(floated, privacy: .public) collapsed windows floated)")
        onViewChanged?()
    }

    /// Zooms `displayUUID`'s camera to `target`, focusing `focus` after the settle (the shell entry point; pointer input
    /// uses it).
    public func zoom(to target: ViewTarget, displayUUID: String, focus: TransomModel.WindowRef? = nil) async {
        await run(arranger.handle(.zoomTo(target, displayUUID: displayUUID, focus: focus), now: .now))
    }

    /// A collapsed block double-clicked (or pressed with VoiceOver): zoom to its leaf and focus it once it settles. While
    /// paused: beep and say so (UI-SPEC Surface 3).
    private func openBlock(_ window: TransomModel.WindowRef, displayUUID uuid: String) async {
        guard arranger.pauseReasons.isEmpty else {
            beep()
            postAnnouncement(Navigator.Refusal.paused.announcement)
            return
        }
        await zoomInput.zoom(toLeafOf: window, displayUUID: uuid)
    }

    /// Presses Finder's ⌘N menu item on Finder's AX thread (RESEARCH Pattern 14): no Apple Events, no Automation
    /// prompt. A quit Finder is launched first and pressed once Transom tracks it, within most of the Arranger's 2 s wait.
    /// With no such item to press, Transom opens the home folder instead; the Arranger docks whatever new window comes.
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

    /// Before Transom exits (SAFE-01, D-15): every parked or off-screen window Transom may move goes back on screen, within
    /// `limit` in total; a docked window parked or zoomed by the camera goes back to its home-view tile (D-D). Synchronous,
    /// so it never waits on MainActor work (Pitfall 14). Every member of every tab group goes to its group's content rect
    /// and each group's selected window is raised last (D-07). Returns how many writes finished.
    @discardableResult
    public func restoreForTermination(limit: Duration = .seconds(2)) -> Int {
        gestures.stop(reason: "quit")
        let plan = arranger.restorePlan()
        guard !plan.isEmpty else { return 0 }
        let groupRects = arranger.groupContentRects()
        let (seconds, attoseconds) = limit.components
        let restored = system.restoreForTermination(
            plan, raising: arranger.selectedGroupMembers(), deadline: .now() + Double(seconds) + Double(attoseconds) / 1e18)
        let members = plan.keys.filter { groupRects[$0.identity] != nil }.count
        if members > 0 { logger.info("quit: \(members, privacy: .public) group members placed at their content rects") }
        logger.info("quit restore: \(restored, privacy: .public) of \(plan.count, privacy: .public) windows")
        return restored
    }

    /// Writes layout.json one last time with `cleanExit: true` when Transom quits normally. Nothing is written if
    /// tracking never started, so a quit before the first sweep cannot replace a saved layout with an empty one.
    public func writeCleanExit() {
        guard started else { return }
        saveTimer.cancel()
        survivalTimer.cancel()  // a later write would record the clean exit as unclean
        write(cleanExit: true)
    }

    /// D-13: the saved World, every layout set (CR-02) and every saved view with each desk moved to its Space's current
    /// ID, before `.restore`. A Space the file's table lacks (every Space of a migrated schema-1 file) is taken as unchanged since
    /// the save: the same-login assumption (RESEARCH Pattern 2). With the Spaces lookup off the desks keep their saved IDs.
    private func rekeyed(_ saved: LayoutFile) -> (World, [LayoutSet], [SavedView]) {
        guard let live = system.spacesSnapshot else {
            logger.info("spaces lookup off: \(LayoutStore.fileName, privacy: .public) desks keep their saved Space IDs")
            return (saved.world, saved.layoutSets, saved.views)
        }
        do {
            let (result, layoutSets, setsQuarantined, views) = try SpaceRekey.rekey(saved, live: live)
            logger.info(
                "\(LayoutStore.fileName, privacy: .public) migrated: \(result.rekeyed, privacy: .public) desks re-keyed by Space UUID, \(result.unmatched.count, privacy: .public) unmatched kept dormant")
            let quarantined = result.quarantined + setsQuarantined
            for key in quarantined {
                let space = key.spaceID.map(String.init) ?? "none"
                logger.error(
                    "\(LayoutStore.fileName, privacy: .public) desk on display \(key.displayUUID, privacy: .public) space \(space, privacy: .public) quarantined: its Space is gone and the ID now names another")
            }
            // WR-04: the launch write drops quarantined desks, so the file is copied first; with no copy nothing is dropped.
            if !quarantined.isEmpty, store?.backUp("pre-rekey") != true {
                logger.error("no backup of \(LayoutStore.fileName, privacy: .public): keeping saved Space IDs rather than drop \(quarantined.count, privacy: .public) desks")
                return (saved.world, saved.layoutSets, saved.views)
            }
            return (result.world, layoutSets, views)
        } catch {
            // Unreachable for a decoded World (same windows and IDs); restoring it unchanged keeps the layout.
            logger.error("could not re-key \(LayoutStore.fileName, privacy: .public) desks: \(String(describing: error), privacy: .public); keeping saved Space IDs")
            return (saved.world, saved.layoutSets, saved.views)
        }
    }

    private func write(cleanExit: Bool = false) {
        guard let store else { return }
        let snapshot = arranger.snapshot
        let session = SessionRecord(
            cleanExit: cleanExit, launchedAt: launchedAt, recoveryLaunch: launchMode != .normal, survivedMinute: survivedMinute,
            bootSession: BootSession.current())
        // Live Space UUIDs win; a dormant desk's Space (not live now) keeps the UUID it was loaded with (D-13).
        let uuids = (store.contents?.spaceMap ?? [:]).merging(system.spacesSnapshot?.uuidByID ?? [:]) { _, live in live }
        let file = LayoutFile(
            world: snapshot.world, homeFrames: snapshot.homeFrames, wantedFrames: snapshot.wantedFrames, session: session,
            arrangement: snapshot.arrangement, layoutSets: snapshot.layoutSets,
            spaces: SpaceRekey.table(for: snapshot.world, layoutSets: snapshot.layoutSets, views: snapshot.views, uuids: uuids), views: snapshot.views)
        do {
            try store.save(file)
        } catch {
            logger.error("could not save \(LayoutStore.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Displays are quiet again (D-11): the Arranger gets the new arrangement, the names captured before any display
    /// left, and a fresh inventory.
    private func displaysSettled() async {
        // WR-08: a change that began after this settle was queued gets its own settle; a mid-change inventory decides nothing.
        guard system.settlerState == .idle else { return }
        let inventory = await system.inventory()
        guard system.settlerState == .idle else { return }
        let id = ArrangementID(inventory.displays.map(\.uuid))
        let stored = id == arranger.arrangement ? nil : arranger.layoutSets[id]
        let known = stored != nil || id == arranger.arrangement
        displaysLog.info(
            "arrangement \(id.shortHash, privacy: .public): \(inventory.displays.count, privacy: .public) displays (\(id.displayUUIDs.joined(separator: ", "), privacy: .public)), \(known ? "known" : "new", privacy: .public)")
        let before = Set(arranger.displays.map(\.uuid)), after = Set(id.displayUUIDs)
        let leaving = Dictionary(uniqueKeysWithValues: before.subtracting(after).map { ($0, deskWindows(on: $0)) })
        await run(arranger.handle(.displaysSettled(id, names: system.displayNames, inventory: inventory), now: .now))
        // WR-09: a settle after the re-attach has handled the launch; while the restore still waits, the launch settle
        // stays armed only if the live displays differ from the saved arrangement.
        launchSettlePending = arranger.awaitsRestore && !arranger.arrangement.isUnknown && arranger.arrangement != id
        for (uuid, windows) in leaving.sorted(by: { $0.key < $1.key }) {
            let floated = windows.filter { arranger.windows[$0.identity] != nil && arranger.isFloating($0) }
            let target = floated.first.flatMap { arranger.windows[$0.identity]?.displayUUID } ?? "none"
            displaysLog.info(
                "display \(uuid, privacy: .public) gone: \(self.deskCount(on: uuid), privacy: .public) desks dormant, \(floated.count, privacy: .public) windows floated on \(target, privacy: .public)")
        }
        for uuid in after.subtracting(before).sorted() {
            let returned = deskWindows(on: uuid).filter { arranger.windows[$0.identity]?.displayUUID == uuid }.count
            displaysLog.info(
                "display \(uuid, privacy: .public) back: \(self.deskCount(on: uuid), privacy: .public) desks woken, \(returned, privacy: .public) windows returned")
        }
        if let stored {
            let placed = Set(stored.world.desks.values.flatMap { $0.tree.windows }.map(\.identity)).filter { arranger.windows[$0] != nil }.count
            displaysLog.info("applied layout set for arrangement \(id.shortHash, privacy: .public): \(placed, privacy: .public) windows placed")
        }
        onInventory?(inventory)
    }

    /// The windows the desks of display `uuid` hold, docked or floating.
    private func deskWindows(on uuid: String) -> [TransomModel.WindowRef] {
        arranger.world.desks.filter { $0.key.displayUUID == uuid }.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }
    }

    private func deskCount(on uuid: String) -> Int { arranger.world.desks.keys.filter { $0.displayUUID == uuid }.count }

    /// Launched on other displays than the layout was saved on: once the saved layout is re-attached, a settle stores
    /// it under its own arrangement and applies the live arrangement's set, if one is known (06-04 hand-off).
    private func settleIfLaunchArrangementChanged() async {
        guard launchSettlePending, !arranger.awaitsRestore else { return }
        launchSettlePending = false
        await run(arranger.handle(.displaysSettling, now: .now))
        await displaysSettled()
    }

    /// Shows or hides the toast as the queue says, and schedules the visible notice's expiry.
    private func present(_ change: NoticeQueue<Notice>.Change) {
        switch change {
        case .show(let notice):
            toast.show(
                NoticeCopy.text(for: notice, appName: Self.appName), glyph: NoticeCopy.glyph(for: notice),
                warning: NoticeCopy.isWarning(notice), on: displayUUID(of: notice), announce: notice != joinedNotice)
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

    /// The display the toast belongs on: the first named window's, N12's main display, or a view notice's own display.
    private func displayUUID(of notice: Notice) -> String? {
        switch notice {
        case .lostRoom(let windows): windows.first.flatMap { arranger.windows[$0.identity]?.displayUUID }
        // N12 belongs on the display that received the windows: the main display (UI-SPEC Surface 6).
        case .displaysDisconnected: arranger.displays.first?.uuid
        case .viewSaved(_, _, let uuid), .viewShown(_, let uuid), .viewEmpty(_, let uuid), .viewWindowsClosed(_, let uuid), .viewDisplayGone(_, let uuid),
            .viewNothingToSave(let uuid): uuid
        case .finderNoWindow, .floatedAll, .arrangeLeftovers, .crashRecovered, .crashLoop, .restored, .turnOffFailed, .settingsRestored, .takeoverCrashed,
            .takeoverApplyFailed: nil
        }
    }

    private static func appName(_ window: TransomModel.WindowRef) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? window.bundleID
    }
}

/// Where a command came from: a URL or CLI dispatch is silent on screen when it cannot act; the CLI gets a reply instead.
public enum CommandSource {
    case hotkey, menu, url, cli

    var isSilent: Bool { self == .url || self == .cli }
}

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
