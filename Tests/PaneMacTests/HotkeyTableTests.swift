import AppKit
import KeyboardShortcuts
import PaneEngine
@testable import PaneMac
import Testing

/// D-08, D-10, UI-SPEC Surface 6: fixed ⌃⌥⌘ defaults under stable names (a persistent contract, Pitfall 13).
@Suite @MainActor struct HotkeyTableTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]
    private let shifted: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    @Test func entriesMapStableNamesToCommands() {
        #expect(Hotkeys.entries.map(\.name.rawValue) == [
            "dock", "float", "undo", "toggleDesktop", "focusLeft", "focusRight", "focusUp", "focusDown", "finderSplit",
            "togglePause", "toggleExcludeFrontmost", "moveLeft", "moveRight", "moveUp", "moveDown",
        ])
        #expect(Hotkeys.entries.map(\.command) == [
            .dock, .float, .undo, .toggleDesktop, .focus(.left), .focus(.right), .focus(.top), .focus(.bottom), .finderSplit,
            .togglePause, .toggleExcludeFrontmost, .moveOrSnap(.left), .moveOrSnap(.right), .moveOrSnap(.top), .moveOrSnap(.bottom),
        ])
    }

    @Test func defaultsAreControlOptionCommandPlusALetter() {
        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.d, modifiers: base), .init(.f, modifiers: base), .init(.z, modifiers: base), .init(.h, modifiers: base),
            .init(.leftArrow, modifiers: base), .init(.rightArrow, modifiers: base), .init(.upArrow, modifiers: base),
            .init(.downArrow, modifiers: base), .init(.n, modifiers: base), .init(.p, modifiers: base),
            .init(.e, modifiers: base), .init(.leftArrow, modifiers: shifted), .init(.rightArrow, modifiers: shifted),
            .init(.upArrow, modifiers: shifted), .init(.downArrow, modifiers: shifted),
        ]
        #expect(Hotkeys.entries.map(\.name.defaultShortcut) == expected)
    }

    @Test func togglePauseIsControlOptionCommandP() {
        #expect(KeyboardShortcuts.Name.togglePause.rawValue == "togglePause")
        #expect(KeyboardShortcuts.Name.togglePause.defaultShortcut == .init(.p, modifiers: base))
    }

    @Test func toggleExcludeFrontmostIsControlOptionCommandE() {
        #expect(KeyboardShortcuts.Name.toggleExcludeFrontmost.rawValue == "toggleExcludeFrontmost")
        #expect(KeyboardShortcuts.Name.toggleExcludeFrontmost.defaultShortcut == .init(.e, modifiers: base))
    }

    @Test func namesAreUnique() {
        let names = Hotkeys.entries.map(\.name.rawValue)
        #expect(!names.isEmpty)
        #expect(Set(names).count == names.count)
    }

    @Test func noTwoEntriesShareAChord() {
        let chords = Hotkeys.entries.compactMap(\.name.defaultShortcut)
        #expect(chords.count == Hotkeys.entries.count)
        for (i, chord) in chords.enumerated() {
            #expect(!chords[(i + 1)...].contains(chord), "\(Hotkeys.entries[i].name.rawValue) shares its chord")
        }
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
