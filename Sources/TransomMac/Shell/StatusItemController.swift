import AppKit
import Combine
import KeyboardShortcuts
import TransomEngine
import TransomModel
import os

/// The menu-bar status item (D-01). The menu is rebuilt from the cached inventory each time it opens, grouped into
/// Arrange, Safety and Exclusions (UI-SPEC Surface 1, D-28). Command items come from `CommandMenu`, built once.
@MainActor final class StatusItemController: NSObject, NSMenuDelegate {
    private let system: AXWindowSystem
    private let arrange: ArrangeController
    private let commands: CommandMenu
    private let permission: PermissionController
    private let gaps: GapPreference
    private let exclusions: ExclusionStore
    private let freezeTest: FreezeTest
    private let conflicts: ConflictController
    private let showSetup: () -> Void
    private let showTrackedWindows: () -> Void
    private var permissionSubscription: AnyCancellable?
    /// The last access state the subscription saw (it fires before `permission.state` updates).
    private var ready = false
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "shell")
    private(set) var latest = WindowInventory(displays: [], windows: []) {
        didSet { onInventory?(latest) }
    }
    /// Fan-out of each inventory passed to `update(_:)` (the Tracked Windows feed).
    var onInventory: ((WindowInventory) -> Void)?
    /// The frontmost app when the menu opened; opening a status menu does not activate Transom.
    private var frontmost: NSRunningApplication?
    /// Restore frames for Debug ▸ Nudge Focused Window (D-01).
    private var nudgePlanner = NudgePlanner()
    /// Installed apps' display names by bundle ID, so a menu rebuild does not ask Launch Services per row (02-UI-REVIEW).
    private var displayNames: [String: String] = [:]
    private lazy var shortcutsWindow = ShortcutsWindowController()

    /// `showSetup` opens the "Set Up Transom" window from the Grant/Fix item. `dispatch` is the call every hotkey makes.
    init(
        system: AXWindowSystem, arrange: ArrangeController, dispatch: @escaping (Command) -> Void, permission: PermissionController,
        gaps: GapPreference, exclusions: ExclusionStore, freezeTest: FreezeTest, conflicts: ConflictController, showTrackedWindows: @escaping () -> Void, showSetup: @escaping () -> Void
    ) {
        self.system = system
        self.arrange = arrange
        commands = CommandMenu(dispatch: dispatch)
        self.permission = permission
        self.gaps = gaps
        self.exclusions = exclusions
        self.freezeTest = freezeTest
        self.conflicts = conflicts
        self.showTrackedWindows = showTrackedWindows
        self.showSetup = showSetup
        super.init()
        permissionSubscription = permission.$state.map { $0.phase == .ready }.removeDuplicates()
            .sink { [weak self] ready in
                self?.ready = ready
                self?.updateGlyph()
            }
        arrange.onPauseChanged = { [weak self] in self?.updateGlyph() }
        arrange.onViewChanged = { [weak self] in self?.updateGlyph() }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The latest inventory, re-read by `ArrangeController` after each event (it is the only events reader).
    func update(_ inventory: WindowInventory) {
        latest = inventory
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        frontmost = NSWorkspace.shared.frontmostApplication
        addStatusItems(to: menu)
        addConflictItems(to: menu)
        menu.addItem(.separator())
        let context = arrange.commandContext()
        addArrangeItems(to: menu, context: context)
        menu.addItem(.separator())
        addZoomItems(to: menu, context: context)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: MenuCopy.safetySection))
        let pause = commands.item(for: .togglePause)
        pause.title = MenuCopy.pauseToggle(paused: !arrange.arranger.pauseReasons.isEmpty)
        menu.addItem(pause)
        menu.addItem(commands.item(for: .restoreAll))  // enabled while paused (Arranger.availability)
        // Item 22, deliberately unbound (it changes macOS settings). No action greys it out under auto-enabling.
        let restore = NSMenuItem(title: ConflictCopy.restoreItem, action: conflicts.canRestore ? #selector(restoreSettings) : nil, keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: MenuCopy.exclusionsSection))
        addExclusionItems(to: menu)
        if NSEvent.modifierFlags.contains(.option) {
            menu.addItem(.separator())
            menu.addItem(debugMenuItem())
        }
        menu.addItem(.separator())
        let shortcuts = NSMenuItem(title: ZoomCopy.shortcutsItem, action: #selector(openShortcuts), keyEquivalent: "")
        shortcuts.target = self
        menu.addItem(shortcuts)
        let quit = NSMenuItem(title: "Quit Transom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// A chord pressed while the menu is open runs its menu item once, instead of being buffered and fired again by the
    /// hotkey when the menu closes (KeyboardShortcuts' `setShortcut` note, RESEARCH Pattern 9).
    func menuWillOpen(_ menu: NSMenu) {
        arrange.overviewController?.interrupt(reason: .menu)  // Surface 1: the status menu opening interrupts the overview
        KeyboardShortcuts.disable(Hotkeys.entries.map(\.name))
    }

    func menuDidClose(_ menu: NSMenu) {
        let zoomOn = arrange.isZoomEnabled  // zoom off keeps the zoom chords disabled (D-D)
        KeyboardShortcuts.enable(Hotkeys.entries.map(\.name).filter { zoomOn || !Hotkeys.zoomNames.contains($0) })
    }

    /// Items 6–18: the Arrange section, enabled by the one availability rule (which also greys the camera items).
    private func addArrangeItems(to menu: NSMenu, context: CommandContext) {
        commands.update(focusedFloats: arrange.arranger.isFloating(context.focused)) { arrange.arranger.availability($0, context: context) }
        commands.item(for: .toggleDesktop).title = MenuCopy.desktopToggle(hidden: arrange.arranger.isDesktopHidden(focused: context.focused))
        menu.addItem(.sectionHeader(title: MenuCopy.arrangeSection))
        for command in [Command.dock, .float, .swapPrevious, .undo] { menu.addItem(commands.item(for: command)) }
        menu.addItem(commands.focusMenu)
        menu.addItem(commands.moveMenu)
        menu.addItem(commands.splitMenu)
        menu.addItem(commands.snapMenu)
        menu.addItem(.separator())
        menu.addItem(commands.item(for: .arrangeAll))
        menu.addItem(commands.item(for: .floatAll))
        menu.addItem(commands.item(for: .toggleDesktop))
        menu.addItem(gapsMenuItem())
    }

    /// The Zoom section (Surface 6), on the pointer's display. Screen Recording is never checked while zoom is off.
    private func addZoomItems(to menu: NSMenu, context: CommandContext) {
        let on = arrange.isZoomEnabled
        var previews: NSMenuItem?
        if on, !SnapshotCapture.isGranted() {
            let item = NSMenuItem(title: ZoomCopy.allowWindowPreviews, action: #selector(allowPreviews), keyEquivalent: "")
            item.target = self
            previews = item
        }
        let toggle = NSMenuItem(title: "", action: #selector(toggleZoom), keyEquivalent: "")
        toggle.target = self
        let arranger = arrange.arranger
        let uuid = context.displayUUID
        let section = commands.zoomSection(
            enabled: on, framingWindow: uuid.map { arranger.isFramingFocused(displayUUID: $0, focused: context.focused) } ?? false,
            framingDesktop: uuid.map(arranger.isFramingDesktop) ?? false, previews: previews, toggle: toggle)
        for item in section { menu.addItem(item) }
    }

    @objc private func toggleZoom() {
        Task { await arrange.setZoomEnabled(!arrange.isZoomEnabled) }
    }

    /// Surface 2 recovery path: user-initiated, so not a re-prompt loop. Once the user has decided, macOS shows no prompt
    /// and Transom opens the Screen Recording pane instead.
    @objc private func allowPreviews() {
        guard !SnapshotCapture.request(),
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Gaps ▸, a radio list; enabled while paused, where the change waits for Resume (D-27).
    private func gapsMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: MenuCopy.gapsMenu)
        for (index, gap) in GapPreference.allowed.enumerated() {
            let item = NSMenuItem(title: MenuCopy.gapTitle(gap), action: #selector(chooseGap), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = gap == gaps.value ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: MenuCopy.gapsMenu, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func chooseGap(_ sender: NSMenuItem) {
        _ = gaps.set(GapPreference.allowed[sender.tag])
    }

    /// Template glyph per the UI-SPEC glyph table: the warning triangle until access is ready, dimmed while paused.
    /// While the pointer display's view is not home it reads "Transom: zoomed in" (paused and not ready win).
    private func updateGlyph() {
        guard let button = statusItem.button else { return }
        let paused = ready && !arrange.arranger.pauseReasons.isEmpty
        let zoomed = arrange.isZoomEnabled && arrange.pointerDisplay().uuid.map { arrange.arranger.view(on: $0) != .home } == true
        let (symbol, description) =
            !ready ? ("exclamationmark.triangle", "Transom: Accessibility access needed")
            : paused ? ("rectangle.split.2x1", MenuCopy.pausedGlyphDescription)
            : zoomed ? ("rectangle.split.2x1", ZoomCopy.zoomedInDescription) : ("rectangle.split.2x1", "Transom")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = paused
        button.toolTip = ready && !paused && !zoomed ? Self.bundleName(logger: logger) : description
    }

    private func addStatusItems(to menu: NSMenu) {
        let state = permission.state
        if let header = MenuCopy.permissionHeader(state.phase) {
            menu.addItem(Self.info(header))
            let stale = state.phase == .staleTrustedButFailing || state.phase == .resetting || state.showStaleFormB
            let item = NSMenuItem(title: MenuCopy.permissionItem(stale: stale), action: #selector(openSetup), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return
        }
        menu.addItem(Self.info(MenuCopy.header(latest)))
        if let line = MenuCopy.pauseLine(arrange.arranger.pauseReasons) { menu.addItem(Self.info(line)) }
        if let degraded = MenuCopy.degradedLine(count: latest.degradedPIDs.count) {
            menu.addItem(Self.info(degraded))
        }
    }

    /// Item 5: one line per active conflict, in the fixed order; a click turns the feature off at once (D-19).
    private func addConflictItems(to menu: NSMenu) {
        for conflict in Conflict.allCases where conflicts.active.contains(conflict) {
            let item = NSMenuItem(title: ConflictCopy.menuTitle(conflict), action: #selector(turnOffConflict), keyEquivalent: "")
            item.target = self
            item.representedObject = conflict.rawValue
            item.toolTip = ConflictCopy.tooltip(conflict)
            let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: ConflictCopy.imageDescription)
            image?.isTemplate = true
            item.image = image
            menu.addItem(item)
        }
    }

    @objc private func turnOffConflict(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let conflict = Conflict(rawValue: raw) else { return }
        Task { await conflicts.turnOff(conflict) }
    }

    @objc private func restoreSettings() {
        conflicts.restore()
    }

    /// Items 24 and 25: the frontmost app's Don't Arrange toggle (⌃⌥⌘E, D-29) and the Never Arrange submenu (D-12).
    private func addExclusionItems(to menu: NSMenu) {
        let toggle = commands.item(for: .toggleExcludeFrontmost)
        if let app = frontmost, let id = ArrangeController.excludableBundleID(of: app) {
            toggle.title = MenuCopy.dontArrange(appName: MenuCopy.truncatedAppName(app.localizedName ?? id))
            toggle.state = exclusions.contains(id) ? .on : .off
            toggle.isEnabled = true
        } else {
            toggle.title = MenuCopy.dontArrangeFallback
            toggle.state = .off
            toggle.isEnabled = false
        }
        menu.addItem(toggle)

        let submenu = NSMenu(title: "Never Arrange")
        let names = Dictionary(uniqueKeysWithValues: exclusions.bundleIDs.compactMap { id in displayName(of: id).map { (id, $0) } })
        for entry in exclusions.sortedEntries(displayNames: names) {
            let item = NSMenuItem(title: entry.title, action: #selector(removeExclusion), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.bundleID
            item.state = .on
            submenu.addItem(item)
        }
        if submenu.items.isEmpty { submenu.addItem(Self.info(MenuCopy.noExclusions)) }
        let item = NSMenuItem(title: "Never Arrange", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func removeExclusion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        exclusions.remove(id)
    }

    /// The installed app's display name, or nil when no app has this bundle ID (not cached, so a later install shows).
    private func displayName(of bundleID: String) -> String? {
        if let name = displayNames[bundleID] { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        displayNames[bundleID] = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return displayNames[bundleID]
    }

    @objc private func openTrackedWindows() {
        showTrackedWindows()
    }

    @objc private func openSetup() {
        showSetup()
    }

    @objc private func turnMultitouchBackOn() {
        arrange.turnMultitouchBackOn()
    }

    @objc private func openShortcuts() {
        shortcutsWindow.show()
    }

    private func debugMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Debug")
        let tracked = NSMenuItem(title: "Show Tracked Windows", action: #selector(openTrackedWindows), keyEquivalent: "")
        tracked.target = self
        submenu.addItem(tracked)
        submenu.addItem(nudgeMenuItem())
        #if DEBUG
            submenu.addItem(freezeMenuItem())
        #endif
        submenu.addItem(.separator())
        let available = system.capabilityReport[.axWindowID] == true
        submenu.addItem(Self.info(MenuCopy.capabilityItem(windowIDLookupAvailable: available)))
        submenu.addItem(Self.info(MenuCopy.spacesItem(available: system.capabilityReport[.spaces] == true)))
        submenu.addItem(Self.info(MenuCopy.tapItem(running: arrange.isTapRunning)))
        let zoom = arrange.zoomController
        submenu.addItem(Self.info(ZoomCopy.zoomStateLine(enabled: arrange.isZoomEnabled, capture: arrange.isZoomEnabled ? captureLine(zoom) : "")))
        submenu.addItem(Self.info(ZoomCopy.lastSettleLine(zoom?.lastSettle)))
        let cache = zoom?.cacheStats ?? (windows: 0, bytes: 0)
        submenu.addItem(Self.info(ZoomCopy.snapshotCacheLine(windows: cache.windows, bytes: cache.bytes)))
        let source: GestureCopy.Source =
            if !arrange.isZoomEnabled { .offZoom } else if arrange.isGestureTapRunning {
                arrange.isMultitouchRunning ? .onWithMultitouch : .on
            } else if arrange.gestureTapFailedToStart {
                .unavailable
            } else { .offTapNotRunning }
        submenu.addItem(Self.info(GestureCopy.gesturesLine(source)))
        let gestures = arrange.gestures
        submenu.addItem(Self.info(GestureCopy.takenLine(taken: gestures.taken, timeouts: gestures.timeouts)))
        submenu.addItem(Self.info(gestures.lastGesture.map(Self.lastGestureLine) ?? GestureCopy.lastGestureNone))
        let multitouch = arrange.multitouchStatus
        submenu.addItem(Self.info(GestureCopy.multitouchLine(multitouch)))
        let spaces: OverviewCopy.SpacesLine =
            if let snapshot = system.spacesSnapshot {
                .counts(spaces: snapshot.spaceCount, displays: snapshot.displays.count, shared: !snapshot.separateSpaces)
            } else { .visited(system.visitedSpaces) }
        submenu.addItem(Self.info(OverviewCopy.spacesLine(spaces)))
        let arranger = arrange.arranger
        let displays: OverviewCopy.DisplaysLine =
            switch system.settlerState {
            case .idle: .settled(displays: arranger.displays.count, arrangement: arranger.arrangement.shortHash)
            case .settling: .settling
            case .waitingForWake: .waitingForWake
            }
        submenu.addItem(Self.info(OverviewCopy.displaysLine(displays)))
        submenu.addItem(Self.info(OverviewCopy.savedArrangementsLine(arranger.layoutSets.all.count)))
        submenu.addItem(Self.info(OverviewCopy.dormantDesksLine(desks: arranger.dormantDeskCount, awayDisplays: arranger.awayDisplayCount)))
        if multitouch == .offAfterCrash {
            let retry = NSMenuItem(title: GestureCopy.multitouchBackOnItem, action: #selector(turnMultitouchBackOn), keyEquivalent: "")
            retry.target = self
            submenu.addItem(retry)
        }
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The capture half of the "Zoom: on, …" line. Before the first move there is no controller and its state would be a
    /// placeholder, so a fresh preflight answers (only reached with zoom on).
    private func captureLine(_ zoom: ZoomController?) -> String {
        switch zoom?.captureState {
        case .previews?: ZoomCopy.capturePreviews
        case .noPermission?: ZoomCopy.captureNoPermission
        case .failing?: ZoomCopy.captureFailing
        case nil: SnapshotCapture.isGranted() ? ZoomCopy.capturePreviews : ZoomCopy.captureNoPermission
        }
    }

    /// "Nudge Focused Window" for the frontmost app's focused tracked dockable window; disabled with an explanatory
    /// title when the app is excluded or has no such window (UI-SPEC Debug submenu).
    private func nudgeMenuItem() -> NSMenuItem {
        guard let app = frontmost else { return Self.info(MenuCopy.nudgeNoWindow) }
        let window = system.focusedWindow(of: app.processIdentifier)
        if window?.isExcluded == true || app.bundleIdentifier.map(exclusions.contains) == true {
            return Self.info(MenuCopy.nudgeExcluded)
        }
        guard let window, window.kind == .dockable else { return Self.info(MenuCopy.nudgeNoWindow) }
        let item = NSMenuItem(title: MenuCopy.nudgeItem, action: #selector(nudge), keyEquivalent: "")
        item.target = self
        item.representedObject = window.window
        return item
    }

    /// Nudges from the window's current frame, or restores the frame it had before the last nudge.
    @objc private func nudge(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? TransomModel.WindowRef else { return }
        Task { [weak self, system] in
            guard let info = await system.windowInfo(ref), let self else { return }
            let target = self.nudgePlanner.target(for: ref.identity, current: info.frame)
            await system.perform([.setFrame(info.window, target)])
        }
    }

    #if DEBUG
        /// "Freeze “App” for 10 Seconds…" for the frontmost app, or "Resume “App” Now" while one is frozen.
        private func freezeMenuItem() -> NSMenuItem {
            if let pid = freezeTest.frozenPID {
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
                let item = NSMenuItem(
                    title: MenuCopy.resumeItem(appName: MenuCopy.truncatedAppName(name)), action: #selector(resumeFrozen),
                    keyEquivalent: "")
                item.target = self
                return item
            }
            guard let app = frontmost,
                FreezeTest.isAllowed(pid: app.processIdentifier, bundleID: app.bundleIdentifier, ownPID: getpid())
            else { return Self.info(MenuCopy.freezeNotAllowed) }
            let name = MenuCopy.truncatedAppName(app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)")
            let item = NSMenuItem(title: MenuCopy.freezeItem(appName: name), action: #selector(confirmFreeze), keyEquivalent: "")
            item.target = self
            item.representedObject = app
            return item
        }

        /// Surface 4: Return and Esc cancel; only a click on the red "Freeze" button freezes.
        @objc private func confirmFreeze(_ sender: NSMenuItem) {
            guard let app = sender.representedObject as? NSRunningApplication else { return }
            let name = MenuCopy.truncatedAppName(app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = MenuCopy.freezeAlertMessage(appName: name)
            alert.informativeText = MenuCopy.freezeAlertInfo(appName: name)
            let freeze = alert.addButton(withTitle: "Freeze")  // first button: rightmost
            freeze.keyEquivalent = ""
            freeze.hasDestructiveAction = true
            let cancel = alert.addButton(withTitle: "Cancel")
            cancel.keyEquivalent = "\r"  // NSAlert itself has no hasDestructiveAction; the button carries it
            // Cancel now holds Return, so map Esc (key code 53) to it while the alert is up.
            let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                cancel.performClick(nil)
                return nil
            }
            NSApp.activate()
            let response = alert.runModal()
            if let escape { NSEvent.removeMonitor(escape) }
            guard response == .alertFirstButtonReturn else { return }
            // Re-check: the app may have changed while the alert was up.
            guard FreezeTest.isAllowed(pid: app.processIdentifier, bundleID: app.bundleIdentifier, ownPID: getpid()),
                !app.isTerminated
            else { return }
            freezeTest.freeze(pid: app.processIdentifier)
        }

        @objc private func resumeFrozen() {
            freezeTest.resumeNow()
        }
    #endif

    /// A disabled informational item (no action, so NSMenu's auto-enabling greys it out).
    private static func lastGestureLine(_ last: GestureController.LastGesture) -> String {
        let outcome: GestureCopy.Outcome =
            switch last.outcome {
            case .moved: .moved
            case .sprangBack: .sprangBack
            case .refused(let refusal): .refused(refusal)
            case .tooSmall: .tooSmall
            }
        return GestureCopy.lastGestureLine(kind: last.kind == .pinch ? .pinch : .pan, direction: last.direction, outcome: outcome)
    }

    private static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// CFBundleName ("Transom Debug" in Debug); the process name when run unbundled via `swift run`.
    private static func bundleName(logger: Logger) -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String { return name }
        let name = ProcessInfo.processInfo.processName
        logger.info("no CFBundleName (unbundled run); tooltip uses process name \(name, privacy: .public)")
        return name
    }
}
