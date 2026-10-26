import AppKit
import KeyboardShortcuts
import PaneEngine
@testable import PaneMac
import Testing

/// TILE-09, D-09: every command item is built once, shows its hotkey and runs the same dispatch with the same Command.
@Suite @MainActor struct CommandMenuTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]

    @Test(arguments: [
        (Command.dock, "Dock Window"), (.float, "Float Window"), (.undo, "Undo Layout Change"),
        (.toggleDesktop, "Hide Desktop Tile"), (.finderSplit, "Split with New Finder Window"),
        (.focus(.left), "Left"), (.focus(.right), "Right"), (.focus(.top), "Up"), (.focus(.bottom), "Down"),
    ])
    func eachItemIsBuiltOnceShowsItsHotkeyAndDispatchesItsCommand(command: Command, title: String) throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        let item = menu.item(for: command)
        #expect(menu.item(for: command) === item, "the item was rebuilt")
        #expect(item.title == title)
        #expect(!item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == base)
        let action = try #require(item.action)
        _ = (item.target as? NSObject)?.perform(action, with: item)
        #expect(sent == [command])
    }

    @Test func dockShowsControlOptionCommandD() {
        let item = CommandMenu { _ in }.item(for: .dock)
        #expect(item.keyEquivalent == "d")
        #expect(item.keyEquivalentModifierMask == base)
    }

    @Test func anUnavailableItemIsDisabledAndKeepsItsTitle() {
        let menu = CommandMenu { _ in }
        menu.update { $0 != .dock }
        #expect(!menu.item(for: .dock).isEnabled)
        #expect(menu.item(for: .dock).title == "Dock Window")
        #expect(menu.item(for: .float).isEnabled)
        menu.update { _ in true }
        #expect(menu.item(for: .dock).isEnabled)
    }

    @Test func theFocusAndSplitSubmenusHoldThePersistentItems() {
        let menu = CommandMenu { _ in }
        #expect(menu.focusMenu.title == "Focus")
        #expect(menu.focusMenu.submenu?.items.contains { $0 === menu.item(for: .focus(.left)) } == true)
        #expect(menu.splitMenu.title == "Split")
        #expect(menu.splitMenu.submenu?.items.contains { $0 === menu.item(for: .finderSplit) } == true)
    }
}

/// TILE-18: Don't Arrange acts on the frontmost regular app only; with none (or Pane itself) it changes nothing,
/// and the caller beeps.
@Suite @MainActor struct FrontmostExclusionTests {
    @Test func withNoQualifyingFrontmostAppNothingChanges() throws {
        let suite = "com.eightabyte.pane.tests.exclusions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExclusionStore(defaults: defaults)
        #expect(!ArrangeController.toggleExclusion(of: nil, in: store))
        #expect(!ArrangeController.toggleExclusion(of: NSRunningApplication.current, in: store), "Pane excluded itself")
        #expect(store.bundleIDs.isEmpty)
    }

    @Test func theExcludeItemShowsControlOptionCommandEAndDispatchesItsCommand() throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        let item = menu.item(for: .toggleExcludeFrontmost)
        #expect(item.title == "Don't Arrange Frontmost App")
        #expect(item.keyEquivalent == "e" && item.keyEquivalentModifierMask == [.control, .option, .command])
        _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item)
        #expect(sent == [.toggleExcludeFrontmost])
    }
}
