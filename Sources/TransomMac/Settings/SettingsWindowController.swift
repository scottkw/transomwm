import AppKit
import SwiftUI
import TransomEngine
import os

/// Owns the one Settings window (09 UI-SPEC Surface 1, D-01): toolbar tabs, one per pane that has a factory, in
/// `SettingsPane.allCases` order. Opening it again brings the same window forward; without a requested pane it reopens
/// on the last tab shown.
@MainActor final class SettingsWindowController {
    static let lastPaneKey = "settings.lastPane"

    private let tabs: TabController
    private var window: NSWindow?
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "settings")

    init(defaults: UserDefaults = .standard, tabs factories: [SettingsPane: () -> NSViewController]) {
        tabs = TabController()
        tabs.defaults = defaults
        tabs.tabStyle = .toolbar
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { tabs.transitionOptions = [] }
        let panes = SettingsPane.allCases.filter { factories[$0] != nil }
        for pane in panes {
            guard let factory = factories[pane] else { continue }
            let content = factory()
            content.title = SettingsCopy.tabLabel(pane)
            let item = NSTabViewItem(viewController: content)
            item.label = SettingsCopy.tabLabel(pane)
            item.image = NSImage(systemSymbolName: SettingsCopy.tabSymbol(pane), accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        tabs.panes = panes  // set last, so adding the first item does not overwrite the stored last pane
    }

    /// The pane of the selected tab.
    var selectedPane: SettingsPane? {
        tabs.panes.indices.contains(tabs.selectedTabViewItemIndex) ? tabs.panes[tabs.selectedTabViewItemIndex] : nil
    }

    /// `pane`'s tab, else the stored last pane, else the first tab. The stored value is parsed only through
    /// `SettingsPane(rawValue:)` (T-09-01).
    func select(_ pane: SettingsPane?) {
        let stored = tabs.defaults.string(forKey: Self.lastPaneKey).flatMap(SettingsPane.init(rawValue:))
        let index = [pane, stored].compactMap { $0 }.compactMap { tabs.panes.firstIndex(of: $0) }.first ?? 0
        guard tabs.panes.indices.contains(index) else { return }
        tabs.selectedTabViewItemIndex = index
        tabs.selectionChanged()  // didSelect does not fire when the tab is already selected
    }

    func show(_ pane: SettingsPane?, from source: String) {
        let window = window ?? makeWindow()
        select(pane)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()  // a URL or CLI open must come forward too (RESEARCH Pitfall 9)
        let shown = selectedPane?.rawValue ?? "none"
        logger.info("opened pane \(shown, privacy: .public) from \(source, privacy: .public)")
    }

    /// Built without showing it, so tests can run headless.
    func makeWindow() -> NSWindow {
        if let window { return window }
        let window = KeyClosableWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("Settings"), let screen = NSScreen.screens.first?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        }
        window.setFrameAutosaveName("Settings")
        self.window = window
        return window
    }

    /// One tab's content: `view` at the 560 pt Settings width (and `height` when given). The window follows each
    /// tab's preferred size.
    static func hosting(_ view: some View, height: CGFloat? = nil) -> NSViewController {
        let hosting = NSHostingController(rootView: view.frame(width: 560, height: height))
        hosting.sizingOptions = [.preferredContentSize]
        return hosting
    }
}

/// Remembers the selected pane and titles the window with its label.
private final class TabController: NSTabViewController {
    var defaults = UserDefaults.standard
    var panes: [SettingsPane] = []

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        selectionChanged()
    }

    func selectionChanged() {
        guard panes.indices.contains(selectedTabViewItemIndex) else { return }
        let pane = panes[selectedTabViewItemIndex]
        defaults.set(pane.rawValue, forKey: SettingsWindowController.lastPaneKey)
        view.window?.title = SettingsCopy.tabLabel(pane)
    }
}
