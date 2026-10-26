import AppKit
import KeyboardShortcuts
import PaneEngine
@testable import PaneMac
import Testing

/// D-08, D-10, UI-SPEC Surface 6: fixed ⌃⌥⌘ defaults under stable names (a persistent contract, Pitfall 13).
@Suite @MainActor struct HotkeyTableTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]

    @Test func entriesMapStableNamesToCommands() {
        #expect(Hotkeys.entries.map(\.name.rawValue) == ["dock", "float", "undo", "toggleDesktop"])
        #expect(Hotkeys.entries.map(\.command) == [.dock, .float, .undo, .toggleDesktop])
    }

    @Test func defaultsAreControlOptionCommandPlusALetter() {
        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.d, modifiers: base), .init(.f, modifiers: base), .init(.z, modifiers: base), .init(.h, modifiers: base),
        ]
        #expect(Hotkeys.entries.map(\.name.defaultShortcut) == expected)
    }

    @Test func namesAreUnique() {
        let names = Hotkeys.entries.map(\.name.rawValue)
        #expect(!names.isEmpty)
        #expect(Set(names).count == names.count)
    }

    /// ⌃⌥⌘8, ⌃⌥⌘, and ⌃⌥⌘. are macOS Accessibility shortcuts (UI-SPEC system-shortcut check).
    @Test func noEntryUsesAShortcutReservedByMacOSAccessibility() {
        #expect(!Hotkeys.entries.isEmpty)
        let reserved: [KeyboardShortcuts.Shortcut] = [.init(.eight, modifiers: base), .init(.comma, modifiers: base), .init(.period, modifiers: base)]
        for entry in Hotkeys.entries {
            #expect(!reserved.contains { $0 == entry.name.defaultShortcut }, "\(entry.name.rawValue) uses a reserved shortcut")
        }
    }
}
