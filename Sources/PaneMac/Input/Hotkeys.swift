import KeyboardShortcuts
import PaneEngine

enum Hotkeys {
    static let entries: [(name: KeyboardShortcuts.Name, command: Command)] = []

    static func register(_ dispatch: @escaping @MainActor (Command) -> Void) {}
}
