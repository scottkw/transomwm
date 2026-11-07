import AppKit
import TransomEngine
@testable import TransomMac
import Testing

/// D-01, D-04: one toolbar-tab Settings window that remembers its last tab. Windows are built with `makeWindow()` and
/// never shown; tabs are plain view controllers, and defaults are a throwaway suite.
@Suite @MainActor struct SettingsWindowTests {
    private func withController(
        panes: [SettingsPane] = [.general, .shortcuts, .updates], stored: String? = nil,
        _ body: (SettingsWindowController, UserDefaults) throws -> Void
    ) throws {
        let suite = "com.eightabyte.transom.tests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        if let stored { defaults.set(stored, forKey: SettingsWindowController.lastPaneKey) }
        var tabs: [SettingsPane: () -> NSViewController] = [:]
        for pane in panes { tabs[pane] = { NSViewController() } }
        try body(SettingsWindowController(defaults: defaults, tabs: tabs), defaults)
    }

    @Test func theWindowHasToolbarTabsAndIsNotShownUntilAsked() throws {
        // Given out of order, so the test shows the tabs follow SettingsPane.allCases.
        try withController(panes: [.updates, .shortcuts, .general]) { controller, _ in
            let window = controller.makeWindow()
            #expect(window.styleMask.contains(.titled) && window.styleMask.contains(.closable))
            #expect(!window.styleMask.contains(.resizable))
            #expect(!window.isVisible)
            let tabs = try #require(window.contentViewController as? NSTabViewController)
            #expect(tabs.tabStyle == .toolbar)
            #expect(tabs.tabViewItems.map(\.label) == [.general, .shortcuts, .updates].map(SettingsCopy.tabLabel))
        }
    }

    @Test func selectingAPaneShowsItsTabAndRemembersIt() throws {
        try withController { controller, defaults in
            let window = controller.makeWindow()
            controller.select(.shortcuts)
            #expect(controller.selectedPane == .shortcuts)
            #expect(defaults.string(forKey: SettingsWindowController.lastPaneKey) == "shortcuts")
            #expect(window.title == SettingsCopy.tabLabel(.shortcuts))
            controller.select(nil)  // no pane asked for: the last one shown
            #expect(controller.selectedPane == .shortcuts)
        }
    }

    @Test func anUnknownStoredPaneOpensTheFirstTab() throws {
        try withController(stored: "nope") { controller, _ in
            _ = controller.makeWindow()
            controller.select(nil)
            #expect(controller.selectedPane == .general)
        }
    }

    @Test func paneNamesAreTheSevenLowercaseTabNamesInOrder() {
        #expect(SettingsPane.allCases.map(\.rawValue) == ["general", "arranging", "zoom", "shortcuts", "exclusions", "menubar", "updates"])
    }
}
