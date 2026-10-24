import AppKit
import PaneEngine
import os

/// The menu-bar status item (D-01). The menu is rebuilt from the cached inventory each time it opens.
/// Later plans add their sections as `add…Items(to:)` methods here.
@MainActor final class StatusItemController: NSObject, NSMenuDelegate {
    private let system: AXWindowSystem
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "shell")
    private(set) var latest = WindowInventory(displays: [], windows: [])

    init(system: AXWindowSystem) {
        self.system = system
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Pane")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
            image?.isTemplate = true
            button.image = image
            button.toolTip = Self.bundleName(logger: logger)
        }
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

    private func addStatusItems(to menu: NSMenu) {
        let apps = Set(latest.windows.map(\.window.pid)).count
        menu.addItem(Self.info(MenuCopy.header(windows: latest.windows.count, apps: apps)))
        if let degraded = MenuCopy.degradedLine(count: latest.degradedPIDs.count) {
            menu.addItem(Self.info(degraded))
        }
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
