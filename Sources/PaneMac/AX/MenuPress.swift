import ApplicationServices
import Foundation

/// Finds and presses an app's ⌘N menu item through AX (RESEARCH Pattern 14), so Pane opens a new Finder window
/// with no Apple Events and no Automation prompt. The item is found by its key equivalent, so it matches in any
/// localisation; menu titles are untrusted strings and are never read (T-03-23).
nonisolated enum MenuPress {
    struct ItemFact: Equatable, Sendable {
        let commandCharacter: String?
        let modifiers: Int?
        let depth: Int
        let enabled: Bool
    }

    /// Menu bar items are depth 1, their menus 2, those menus' items 3; deeper is a submenu.
    static let maxDepth = 3

    /// The first enabled item at depth <= 3 whose key equivalent is ⌘N alone (modifiers 0 is
    /// `kAXMenuItemModifierNone`: Command only, so ⇧⌘N, ⌥⌘N and the like are skipped).
    static func firstCommandN(_ items: [ItemFact]) -> Int? {
        items.firstIndex { $0.depth <= maxDepth && $0.enabled && $0.modifiers == 0 && $0.commandCharacter?.uppercased() == "N" }
    }

    /// Walks the app's menu bar to depth 3 and presses its ⌘N item. Run it on the app's own thread.
    static func pressCommandN(in app: AXUIElement) -> Bool {
        guard let bar = attribute(app, kAXMenuBarAttribute).flatMap(element) else { return false }
        var elements: [AXUIElement] = []
        var facts: [ItemFact] = []
        func walk(_ parent: AXUIElement, depth: Int) {
            guard depth <= maxDepth, let children = attribute(parent, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for child in children {
                elements.append(child)
                facts.append(ItemFact(
                    commandCharacter: attribute(child, kAXMenuItemCmdCharAttribute) as? String,
                    modifiers: (attribute(child, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue,
                    depth: depth,
                    enabled: attribute(child, kAXEnabledAttribute) as? Bool == true))
                walk(child, depth: depth + 1)
            }
        }
        walk(bar, depth: 1)
        guard let index = firstCommandN(facts) else { return false }
        return AXUIElementPerformAction(elements[index], kAXPressAction as CFString) == .success
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ value: CFTypeRef) -> AXUIElement? {
        CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
    }
}
