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
    static let finderSplit = Self("finderSplit", initial: .init(.n, modifiers: [.control, .option, .command]))
    static let togglePause = Self("togglePause", initial: .init(.p, modifiers: [.control, .option, .command]))
    static let toggleExcludeFrontmost = Self("toggleExcludeFrontmost", initial: .init(.e, modifiers: [.control, .option, .command]))
    static let moveLeft = Self("moveLeft", initial: .init(.leftArrow, modifiers: [.control, .option, .command, .shift]))
    static let moveRight = Self("moveRight", initial: .init(.rightArrow, modifiers: [.control, .option, .command, .shift]))
    static let moveUp = Self("moveUp", initial: .init(.upArrow, modifiers: [.control, .option, .command, .shift]))
    static let moveDown = Self("moveDown", initial: .init(.downArrow, modifiers: [.control, .option, .command, .shift]))
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
        (.finderSplit, .finderSplit),
        (.togglePause, .togglePause),
        (.toggleExcludeFrontmost, .toggleExcludeFrontmost),
        (.moveLeft, .moveOrSnap(.left)),
        (.moveRight, .moveOrSnap(.right)),
        (.moveUp, .moveOrSnap(.top)),
        (.moveDown, .moveOrSnap(.bottom)),
    ]

    /// Installs a key-down handler per entry. Call once.
    static func register(_ dispatch: @escaping @MainActor (Command) -> Void) {
        for entry in entries {
            KeyboardShortcuts.onKeyDown(for: entry.name) { dispatch(entry.command) }
        }
    }
}
