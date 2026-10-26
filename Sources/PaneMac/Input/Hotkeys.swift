import KeyboardShortcuts
import PaneEngine

// These raw names are a persistent contract (Pitfall 13): KeyboardShortcuts stores each binding under
// `KeyboardShortcuts_<name>`, so the Phase 4 recorder reuses them. Never rename one.
extension KeyboardShortcuts.Name {
    static let dock = Self("dock", initial: .init(.d, modifiers: [.control, .option, .command]))
    static let float = Self("float", initial: .init(.f, modifiers: [.control, .option, .command]))
    static let undo = Self("undo", initial: .init(.z, modifiers: [.control, .option, .command]))
    static let toggleDesktop = Self("toggleDesktop", initial: .init(.h, modifiers: [.control, .option, .command]))
    static let focusLeft = Self("focusLeft", initial: .init(.leftArrow, modifiers: [.control, .option, .command]))
    static let focusRight = Self("focusRight", initial: .init(.rightArrow, modifiers: [.control, .option, .command]))
    static let focusUp = Self("focusUp", initial: .init(.upArrow, modifiers: [.control, .option, .command]))
    static let focusDown = Self("focusDown", initial: .init(.downArrow, modifiers: [.control, .option, .command]))
}

/// The hotkey table (UI-SPEC Surface 6): fixed ⌃⌥⌘ defaults, each running the same dispatch as every other route.
enum Hotkeys {
    static let entries: [(name: KeyboardShortcuts.Name, command: Command)] = [
        (.dock, .dock),
        (.float, .float),
        (.undo, .undo),
        (.toggleDesktop, .toggleDesktop),
        (.focusLeft, .focus(.left)),
        (.focusRight, .focus(.right)),
        (.focusUp, .focus(.top)),
        (.focusDown, .focus(.bottom)),
    ]

    /// Installs a key-down handler per entry. Call once.
    static func register(_ dispatch: @escaping @MainActor (Command) -> Void) {
        for entry in entries {
            KeyboardShortcuts.onKeyDown(for: entry.name) { dispatch(entry.command) }
        }
    }
}
