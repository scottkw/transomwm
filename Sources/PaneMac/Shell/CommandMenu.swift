import AppKit
import KeyboardShortcuts
import PaneEngine

/// The status menu's command items (TILE-09, D-09). Each is created once and given its hotkey once, so
/// KeyboardShortcuts' `setShortcut` observers never pile up across menu opens (RESEARCH Pattern 9); the menu
/// re-inserts these same items every time it opens. Every item calls `dispatch` with its Command, the same
/// call its hotkey makes. Later plans add their rows to `commands`.
@MainActor final class CommandMenu: NSObject, NSMenuItemValidation {
    /// Every command with a menu item, in no particular order: the status menu places them.
    static let commands: [Command] = [
        .dock, .float, .undo, .toggleDesktop, .focus(.left), .focus(.right), .focus(.top), .focus(.bottom), .finderSplit,
        .togglePause, .toggleExcludeFrontmost,
    ]

    let focusMenu = NSMenuItem(title: "Focus", action: nil, keyEquivalent: "")
    let splitMenu = NSMenuItem(title: "Split", action: nil, keyEquivalent: "")
    private let dispatch: (Command) -> Void
    private var items: [Command: NSMenuItem] = [:]

    init(dispatch: @escaping (Command) -> Void) {
        self.dispatch = dispatch
        super.init()
        for (index, command) in Self.commands.enumerated() {
            let item = NSMenuItem(title: MenuCopy.commandTitle(command), action: #selector(run), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let name = Hotkeys.entries.first(where: { $0.command == command })?.name { item.setShortcut(for: name) }
            items[command] = item
        }
        focusMenu.submenu = submenu("Focus", [.focus(.left), .focus(.right), .focus(.top), .focus(.bottom)])
        splitMenu.submenu = submenu("Split", [.finderSplit])
    }

    func item(for command: Command) -> NSMenuItem {
        guard let item = items[command] else { preconditionFailure("\(command) has no menu item; add it to CommandMenu.commands") }
        return item
    }

    /// Greys each item the availability rule refuses; titles stay as they are (UI-SPEC disabled-state rules).
    func update(availability: (Command) -> Bool) {
        for (command, item) in items { item.isEnabled = availability(command) }
    }

    /// NSMenu re-validates on open and on key equivalents; the state `update` set is the answer.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.isEnabled
    }

    @objc private func run(_ sender: NSMenuItem) {
        dispatch(Self.commands[sender.tag])
    }

    private func submenu(_ title: String, _ commands: [Command]) -> NSMenu {
        let menu = NSMenu(title: title)
        for command in commands { menu.addItem(item(for: command)) }
        return menu
    }
}
