import AppKit
import Combine
import PaneEngine
import os

/// The menu-bar status item (D-01). The menu is rebuilt from the cached inventory each time it opens.
/// Later plans add their sections as `add…Items(to:)` methods here.
@MainActor final class StatusItemController: NSObject, NSMenuDelegate {
    private let system: AXWindowSystem
    private let permission: PermissionController
    private let exclusions: ExclusionStore
    private let freezeTest: FreezeTest
    private let showSetup: () -> Void
    private let showTrackedWindows: () -> Void
    private var permissionSubscription: AnyCancellable?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "shell")
    private(set) var latest = WindowInventory(displays: [], windows: []) {
        didSet { onInventory?(latest) }
    }
    /// Fan-out of each re-read inventory (the Tracked Windows feed); `system.events` has only this reader.
    var onInventory: ((WindowInventory) -> Void)?
    /// The frontmost app when the menu opened; opening a status menu does not activate Pane.
    private var frontmost: NSRunningApplication?

    /// `showSetup` opens the "Set Up Pane" window from the Grant/Fix item.
    init(
        system: AXWindowSystem, permission: PermissionController, exclusions: ExclusionStore, freezeTest: FreezeTest,
        showTrackedWindows: @escaping () -> Void, showSetup: @escaping () -> Void
    ) {
        self.system = system
        self.permission = permission
        self.exclusions = exclusions
        self.freezeTest = freezeTest
        self.showTrackedWindows = showTrackedWindows
        self.showSetup = showSetup
        super.init()
        permissionSubscription = permission.$state.map { $0.phase == .ready }.removeDuplicates()
            .sink { [weak self] ready in self?.updateGlyph(ready: ready) }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // inventory() serves the cache immediately, so re-reading it after each event is cheap.
        Task { [weak self, system] in
            for await _ in system.events {
                self?.latest = await system.inventory()
            }
        }
    }

    /// Re-reads the cached inventory, e.g. once the initial sweep has finished.
    func refresh() async {
        latest = await system.inventory()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        frontmost = NSWorkspace.shared.frontmostApplication
        addStatusItems(to: menu)
        menu.addItem(.separator())
        let tracked = NSMenuItem(title: "Show Tracked Windows", action: #selector(openTrackedWindows), keyEquivalent: "")
        tracked.target = self
        menu.addItem(tracked)
        menu.addItem(.separator())
        addExclusionItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(debugMenuItem())
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Pane", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// Template glyph per UI-SPEC Surface 1: the warning triangle until access is ready.
    private func updateGlyph(ready: Bool) {
        guard let button = statusItem.button else { return }
        let (symbol, description) =
            ready ? ("rectangle.split.2x1", "Pane") : ("exclamationmark.triangle", "Pane: Accessibility access needed")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        image?.isTemplate = true
        button.image = image
        button.toolTip = ready ? Self.bundleName(logger: logger) : description
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
        let apps = Set(latest.windows.map(\.window.pid)).count
        menu.addItem(Self.info(MenuCopy.header(windows: latest.windows.count, apps: apps)))
        if let degraded = MenuCopy.degradedLine(count: latest.degradedPIDs.count) {
            menu.addItem(Self.info(degraded))
        }
    }

    /// Items 4 and 5: the frontmost app's Don't Arrange toggle and the Never Arrange submenu (D-12).
    private func addExclusionItems(to menu: NSMenu) {
        let toggle: NSMenuItem
        if let app = frontmost, let id = app.bundleIdentifier, app.processIdentifier != getpid(),
            app.activationPolicy == .regular, ExclusionStore.isValid(id)
        {
            let name = MenuCopy.truncatedAppName(app.localizedName ?? id)
            toggle = NSMenuItem(title: MenuCopy.dontArrange(appName: name), action: #selector(toggleFrontmost), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = id
            toggle.state = exclusions.contains(id) ? .on : .off
        } else {
            toggle = Self.info(MenuCopy.dontArrangeFallback)
        }
        menu.addItem(toggle)

        let submenu = NSMenu(title: "Never Arrange")
        let names = Dictionary(uniqueKeysWithValues: exclusions.bundleIDs.compactMap { id in Self.displayName(of: id).map { (id, $0) } })
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

    @objc private func toggleFrontmost(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        do {
            try exclusions.toggle(id)
        } catch {
            logger.error("could not toggle exclusion for \(id, privacy: .public)")
        }
    }

    @objc private func removeExclusion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        exclusions.remove(id)
    }

    /// The installed app's display name, or nil when no app has this bundle ID.
    private static func displayName(of bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    @objc private func openTrackedWindows() {
        showTrackedWindows()
    }

    @objc private func openSetup() {
        showSetup()
    }

    private func debugMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Debug")
        #if DEBUG
            submenu.addItem(freezeMenuItem())
            submenu.addItem(.separator())
        #endif
        let available = system.capabilityReport[.axWindowID] == true
        submenu.addItem(Self.info(MenuCopy.capabilityItem(windowIDLookupAvailable: available)))
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
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
    private static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// CFBundleName ("Pane Debug" in Debug); the process name when run unbundled via `swift run`.
    private static func bundleName(logger: Logger) -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String { return name }
        let name = ProcessInfo.processInfo.processName
        logger.info("no CFBundleName (unbundled run); tooltip uses process name \(name, privacy: .public)")
        return name
    }
}
