import AppKit
import Combine
import PaneEngine
import os

/// The menu-bar status item (D-01). The menu is rebuilt from the cached inventory each time it opens.
/// Later plans add their sections as `add…Items(to:)` methods here.
@MainActor final class StatusItemController: NSObject, NSMenuDelegate {
    private let system: AXWindowSystem
    private let permission: PermissionController
    private let showSetup: () -> Void
    private var permissionSubscription: AnyCancellable?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "shell")
    private(set) var latest = WindowInventory(displays: [], windows: [])

    /// `showSetup` opens the "Set Up Pane" window from the Grant/Fix item.
    init(system: AXWindowSystem, permission: PermissionController, showSetup: @escaping () -> Void) {
        self.system = system
        self.permission = permission
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
        addStatusItems(to: menu)
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

    @objc private func openSetup() {
        showSetup()
    }

    private func debugMenuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Debug")
        let available = system.capabilityReport[.axWindowID] == true
        submenu.addItem(Self.info(MenuCopy.capabilityItem(windowIDLookupAvailable: available)))
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

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
