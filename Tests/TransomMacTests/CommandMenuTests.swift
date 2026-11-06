import AppKit
import KeyboardShortcuts
import TransomEngine
import TransomModel
@testable import TransomMac
import Testing

/// TILE-09, D-09: every command item is built once, shows its hotkey and runs the same dispatch with the same Command.
@Suite @MainActor struct CommandMenuTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]

    @Test(arguments: [
        (Command.dock, "Dock Window"), (.float, "Float Window"), (.undo, "Undo Layout Change"),
        (.finderSplit, "Split with New Finder Window"),
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
        let menu = CommandMenu { sent.append($0) }
        let item = menu.item(for: command)
        #expect(item.title == title && item.keyEquivalent == key && item.keyEquivalentModifierMask == base.union(.shift))
        _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item)
        #expect(sent == [command])
    }

    @Test func restoreAllShowsControlOptionCommandZeroAndDispatchesItsCommand() throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        let item = menu.item(for: .restoreAll)
        #expect(item.title == "Restore All Windows" && item.keyEquivalent == "0" && item.keyEquivalentModifierMask == base)
        _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item)
        #expect(sent == [.restoreAll])
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

    /// 07 UI-SPEC Surface 7: the Tabs submenu's items carry their hotkeys, dispatch their commands and follow availability.
    @Test func theTabsSubmenuHoldsTheThreeTabCommandsWithTheirShortcuts() throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        #expect(menu.tabsMenu.title == "Tabs")
        let items = try #require(menu.tabsMenu.submenu).items
        #expect(items.map(\.title) == ["Next Tab", "Previous Tab", "Move Out of Group"])
        #expect(items.map(\.keyEquivalent) == ["t", "t", "l"])
        #expect(items.map(\.keyEquivalentModifierMask) == [base, base.union(.shift), base])
        for item in items { _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item) }
        #expect(sent == [.tabs(.next), .tabs(.previous), .tabs(.moveOut)])
        menu.update { if case .tabs = $0 { false } else { true } }
        #expect(items.allSatisfy { !$0.isEnabled }, "with no group every Tabs item is disabled")
        #expect(items.map(\.title) == ["Next Tab", "Previous Tab", "Move Out of Group"], "disabled items keep their titles")
        #expect(menu.tabsMenu.isEnabled, "the submenu item itself stays enabled")
    }

    /// 08.1 UI-SPEC Surface 4: five columns, a separator, five rows.
    @Test func theFourthSubmenuFollowsTheUISpecOrder() throws {
        let menu = CommandMenu { _ in }
        #expect(menu.fourthMenu.title == "Dock to Fourth")
        let items = try #require(menu.fourthMenu.submenu).items
        #expect(items.map { $0.isSeparatorItem ? nil : $0.title } == [
            "1st Column", "2nd Column", "3rd Column", "4th Column", "Middle Half Column", nil,
            "1st Row", "2nd Row", "3rd Row", "4th Row", "Middle Half Row",
        ])
    }

    /// D-17: each item shows its chord and runs its command. Every chord is ⇧⌃⌥⌘ and a digit.
    @Test func eachFourthItemShowsItsChordAndDispatchesItsCommand() throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        let items = try #require(menu.fourthMenu.submenu).items.filter { !$0.isSeparatorItem }
        #expect(items.map(\.keyEquivalent) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        #expect(items.allSatisfy { $0.keyEquivalentModifierMask == base.union(.shift) })
        for item in items { _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item) }
        let slots: [FourthSlot] = [.first, .second, .third, .fourth, .middle]
        #expect(sent == slots.map { .dockFourth($0, .horizontal) } + slots.map { .dockFourth($0, .vertical) })
    }

    /// D-15, D-17: one availability rule, for a floating window and a docked one alike; a disabled item keeps its title.
    @Test func aFourthItemFollowsAvailabilityAlone() throws {
        let menu = CommandMenu { _ in }
        let items = try #require(menu.fourthMenu.submenu).items.filter { !$0.isSeparatorItem }
        let titles = items.map(\.title)
        #expect(titles.count == 10)
        for floats in [true, false] {
            menu.update(focusedFloats: floats) { _ in true }
            #expect(items.allSatisfy { $0.isEnabled })
        }
        menu.update { if case .dockFourth = $0 { false } else { true } }
        #expect(items.allSatisfy { !$0.isEnabled })
        #expect(items.map(\.title) == titles)
    }

    @Test func theFocusAndSplitSubmenusHoldThePersistentItems() {
        let menu = CommandMenu { _ in }
        #expect(menu.focusMenu.title == "Focus")
        #expect(menu.focusMenu.submenu?.items.contains { $0 === menu.item(for: .focus(.left)) } == true)
        #expect(menu.splitMenu.title == "Split")
        #expect(menu.splitMenu.submenu?.items.contains { $0 === menu.item(for: .finderSplit) } == true)
    }

    /// UI-SPEC Surface 1: the shape both options share, enabled with no availability rule.
    @Test func optionMenuBuildsARadioSubmenu() throws {
        final class Target: NSObject {
            var chosen: [Int] = []
            @objc func choose(_ sender: NSMenuItem) { chosen.append(sender.tag) }
        }
        let target = Target()
        let item = CommandMenu.optionMenu(
            title: "Option: B",
            choices: [("A", "First.", false), ("B", "Second.", true)],
            target: target, action: #selector(Target.choose))
        #expect(item.title == "Option: B")
        #expect(item.action == #selector(NSMenu.submenuAction(_:)), "AppKit's own, for any item with a submenu")
        let choices = try #require(item.submenu).items
        #expect(choices.map(\.title) == ["A", "B"])
        #expect(choices.map(\.state) == [.off, .on])
        #expect(choices.map(\.toolTip) == ["First.", "Second."])
        #expect(choices.map(\.tag) == [0, 1])
        #expect(choices.allSatisfy { $0.target === target && $0.keyEquivalent.isEmpty && $0.isEnabled })
        _ = target.perform(try #require(choices[1].action), with: choices[1])
        #expect(target.chosen == [1])
    }
}

/// 04 UI-SPEC Surface 6: the Zoom section's items, toggle, checkmarks and greying.
@Suite @MainActor struct ZoomCommandMenuTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]
    private nonisolated static let cameraCommands: [CameraCommand] = [
        .zoomOutAll, .stepOut, .stepIn, .back, .forward, .pan(.left), .pan(.right), .pan(.top), .pan(.bottom), .frameWindow, .frameDesktop,
        .overview,
    ]

    private func toggle() -> NSMenuItem { NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "") }

    @Test(arguments: cameraCommands)
    func eachCameraItemShowsItsHotkeyAndDispatchesItsCommand(command: CameraCommand) throws {
        var sent: [Command] = []
        let menu = CommandMenu { sent.append($0) }
        #expect(CommandMenu.commands.contains(.camera(command)))
        let item = menu.item(for: .camera(command))
        #expect(item.title == MenuCopy.cameraTitle(command))
        #expect(!item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.intersection([.control, .option, .command, .shift]) == base)
        _ = (item.target as? NSObject)?.perform(try #require(item.action), with: item)
        #expect(sent == [.camera(command)])
    }

    @Test func theMoveViewSubmenuListsLeftRightUpDown() throws {
        let menu = CommandMenu { _ in }
        #expect(menu.moveViewMenu.title == "Move View")
        let items = try #require(menu.moveViewMenu.submenu).items
        #expect(items.map(\.title) == ["Left", "Right", "Up", "Down"])
        #expect(items[0] === menu.item(for: .camera(.pan(.left))) && items[3] === menu.item(for: .camera(.pan(.bottom))))
    }

    @Test func withZoomOnTheSectionFollowsSurface6() {
        let menu = CommandMenu { _ in }
        let previews = NSMenuItem(title: "Allow Window Previews\u{2026}", action: nil, keyEquivalent: "")
        let section = menu.zoomSection(enabled: true, framingWindow: false, framingDesktop: false, previews: previews, toggle: toggle())
        #expect(section.map(\.title) == [
            "Zoom", "Show Overview", "Zoom Out to All Windows", "Zoom Out One Level", "Zoom In One Level", "Back", "Forward", "Move View",
            "Frame Focused Window", "Frame Desktop", "Allow Window Previews\u{2026}", "Turn Off Zoom",
        ])
        #expect(section[0].isSectionHeader)
        let granted = menu.zoomSection(enabled: true, framingWindow: false, framingDesktop: false, previews: nil, toggle: toggle())
        #expect(!granted.map(\.title).contains("Allow Window Previews\u{2026}"))
    }

    @Test func withZoomOffTheSectionIsTheHeaderAndTurnOnZoom() {
        let menu = CommandMenu { _ in }
        let previews = NSMenuItem(title: "Allow Window Previews\u{2026}", action: nil, keyEquivalent: "")
        let section = menu.zoomSection(enabled: false, framingWindow: true, framingDesktop: true, previews: previews, toggle: toggle())
        #expect(section.map(\.title) == ["Zoom", "Turn On Zoom"])
    }

    @Test func whilePausedTheCameraItemsAreDisabledAndTurnOffZoomStaysEnabled() {
        let menu = CommandMenu { _ in }
        menu.update { if case .camera = $0 { false } else { true } }  // paused: the availability rule refuses every camera command
        let off = toggle()
        let section = menu.zoomSection(enabled: true, framingWindow: false, framingDesktop: false, previews: nil, toggle: off)
        for command in Self.cameraCommands { #expect(!menu.item(for: .camera(command)).isEnabled) }
        #expect(section.last === off && off.isEnabled && off.title == "Turn Off Zoom")
    }

    @Test func theFrameItemsCarryTheirCheckmarks() {
        let menu = CommandMenu { _ in }
        _ = menu.zoomSection(enabled: true, framingWindow: true, framingDesktop: false, previews: nil, toggle: toggle())
        #expect(menu.item(for: .camera(.frameWindow)).state == .on)
        #expect(menu.item(for: .camera(.frameDesktop)).state == .off)
        _ = menu.zoomSection(enabled: true, framingWindow: false, framingDesktop: true, previews: nil, toggle: toggle())
        #expect(menu.item(for: .camera(.frameWindow)).state == .off)
        #expect(menu.item(for: .camera(.frameDesktop)).state == .on)
    }
}

/// TILE-18: Don't Arrange acts on the frontmost regular app only; with none (or Transom itself) it changes nothing,
/// and the caller beeps.
@Suite @MainActor struct FrontmostExclusionTests {
    @Test func withNoQualifyingFrontmostAppNothingChanges() throws {
        let suite = "com.eightabyte.transom.tests.exclusions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExclusionStore(defaults: defaults)
        #expect(!ArrangeController.toggleExclusion(of: nil, in: store))
        #expect(!ArrangeController.toggleExclusion(of: NSRunningApplication.current, in: store), "Transom excluded itself")
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
