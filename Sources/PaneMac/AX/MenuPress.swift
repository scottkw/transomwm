import ApplicationServices

/// Finds and presses an app's ⌘N menu item through AX (RESEARCH Pattern 14), so Pane opens a new Finder window
/// with no Apple Events and no Automation prompt.
nonisolated enum MenuPress {
    struct ItemFact: Equatable, Sendable {
        let commandCharacter: String?
        let modifiers: Int?
        let depth: Int
        let enabled: Bool
    }

    static func firstCommandN(_ items: [ItemFact]) -> Int? {
        nil
    }

    static func pressCommandN(in app: AXUIElement) -> Bool {
        false
    }
}
