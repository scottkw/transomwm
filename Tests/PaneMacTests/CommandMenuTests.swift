import AppKit
import KeyboardShortcuts
import PaneEngine
import PaneModel
@testable import PaneMac
import Testing

/// TILE-09, D-09: every command item is built once, shows its hotkey and runs the same dispatch with the same Command.
@Suite @MainActor struct CommandMenuTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]

    @Test(arguments: [
        (Command.dock, "Dock Window"), (.float, "Float Window"), (.undo, "Undo Layout Change"),
        (.toggleDesktop, "Hide Desktop Tile"), (.finderSplit, "Split with New Finder Window"),
        (.focus(.left), "Left"), (.focus(.right), "Right"), (.focus(.top), "Up"), (.focus(.bottom), "Down"),
        (.swapPrevious, "Swap with Previous Window"), (.growTile, "Grow Tile"), (.shrinkTile, "Shrink Tile"),
        (.balanceSplit, "Balance Split"), (.rotateSplit, "Rotate Layout"), (.flipSplit, "Flip Split"),
        (.snap(.leftThird), "Left Third"), (.snap(.centerThird), "Center Third"), (.snap(.rightThird), "Right Third"),
        (.snap(.topLeft), "Top Left Quarter"), (.snap(.topRight), "Top Right Quarter"), (.snap(.bottomLeft), "Bottom Left Quarter"),
        (.snap(.bottomRight), "Bottom Right Quarter"), (.snap(.maximize), "Maximize"), (.snap(.center), "Center"),
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

    @Test(arguments: [(Command.arrangeAll, "Arrange All Windows", "d"), (.floatAll, "Float All Windows", "f")])
    func theAllWindowItemsShowTheirShiftedChordAndDispatchTheirCommand(command: Command, title: String, key: String) throws {
        var sent: [Command] = []
        let item = CommandMenu { sent.append($0) }.item(for: command)
        #expect(item.title == title && item.keyEquivalent == key && item.keyEquivalentModifierMask == base.union(.shift))
        _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item)
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

    /// UI-SPEC halves alias: Move Window ▸ Left and Snap Floating Window ▸ Left Half both run moveOrSnap(.left) on
    /// ⌃⌥⌘⇧←, and exactly one of the pair is enabled for any focused window.
    @Test(arguments: [(Edge.left, "Left", "Left Half"), (.right, "Right", "Right Half"), (.top, "Up", "Top Half"), (.bottom, "Down", "Bottom Half")])
    func moveAndSnapHalfShareTheirCommandAndShortcutAndOnlyOneIsEnabled(edge: Edge, move: String, half: String) throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        let moveItem = menu.item(for: .moveOrSnap(edge)), halfItem = menu.halfItem(edge)
        #expect(moveItem.title == move && halfItem.title == half)
        #expect(menu.moveMenu.title == "Move Window" && menu.moveMenu.submenu?.items.contains { $0 === moveItem } == true)
        #expect(menu.snapMenu.title == "Snap Floating Window" && menu.snapMenu.submenu?.items.contains { $0 === halfItem } == true)
        #expect(!moveItem.keyEquivalent.isEmpty && halfItem.keyEquivalent == moveItem.keyEquivalent)
        #expect(moveItem.keyEquivalentModifierMask == base.union(.shift) && halfItem.keyEquivalentModifierMask == moveItem.keyEquivalentModifierMask)
        for item in [moveItem, halfItem] { _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item) }
        #expect(sent == [.moveOrSnap(edge), .moveOrSnap(edge)])

        menu.update(focusedFloats: false) { _ in true }
        #expect(moveItem.isEnabled && !halfItem.isEnabled)
        menu.update(focusedFloats: true) { _ in true }
        #expect(!moveItem.isEnabled && halfItem.isEnabled)
        menu.update(focusedFloats: true) { _ in false }
        #expect(!moveItem.isEnabled && !halfItem.isEnabled)
    }

    /// UI-SPEC Surface 1 submenu orders; nil is a separator.
    @Test func theSplitAndSnapSubmenusFollowTheUISpecOrder() throws {
        let menu = CommandMenu { _ in }
        func titles(_ item: NSMenuItem) throws -> [String?] {
            try #require(item.submenu).items.map { $0.isSeparatorItem ? nil : $0.title }
        }
        #expect(try titles(menu.splitMenu) == [
            "Grow Tile", "Shrink Tile", nil, "Balance Split", "Rotate Layout", "Flip Split", nil, "Split with New Finder Window",
        ])
        #expect(try titles(menu.snapMenu) == [
            "Left Half", "Right Half", "Top Half", "Bottom Half", nil, "Left Third", "Center Third", "Right Third", nil,
            "Top Left Quarter", "Top Right Quarter", "Bottom Left Quarter", "Bottom Right Quarter", nil, "Maximize", "Center",
        ])
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
