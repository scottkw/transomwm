import AppKit
import KeyboardShortcuts
import TransomEngine
@testable import TransomMac
import Testing

/// D-08, D-10, UI-SPEC Surface 6: fixed ⌃⌥⌘ defaults under stable names (a persistent contract, Pitfall 13).
@Suite @MainActor struct HotkeyTableTests {
    private let base: NSEvent.ModifierFlags = [.control, .option, .command]
    private let shifted: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    @Test func entriesMapStableNamesToCommands() {
        #expect(Hotkeys.entries.map(\.name.rawValue) == [
            "dock", "float", "undo", "toggleDesktop", "focusLeft", "focusRight", "focusUp", "focusDown", "finderSplit",
            "togglePause", "toggleExcludeFrontmost", "moveLeft", "moveRight", "moveUp", "moveDown",
            "swapPrevious", "growTile", "shrinkTile", "balanceSplit", "rotateSplit", "flipSplit", "snapLeftThird", "snapCenterThird",
            "snapRightThird", "snapTopLeft", "snapTopRight", "snapBottomLeft", "snapBottomRight", "snapMaximize", "snapCenter",
            "arrangeAll", "floatAll", "restoreAll",
        ])
        #expect(Hotkeys.entries.map(\.command) == [
            .dock, .float, .undo, .toggleDesktop, .focus(.left), .focus(.right), .focus(.top), .focus(.bottom), .finderSplit,
            .togglePause, .toggleExcludeFrontmost, .moveOrSnap(.left), .moveOrSnap(.right), .moveOrSnap(.top), .moveOrSnap(.bottom),
            .swapPrevious, .growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit, .snap(.leftThird), .snap(.centerThird),
            .snap(.rightThird), .snap(.topLeft), .snap(.topRight), .snap(.bottomLeft), .snap(.bottomRight), .snap(.maximize), .snap(.center),
            .arrangeAll, .floatAll, .restoreAll,
        ])
    }

    @Test func defaultsAreControlOptionCommandPlusALetter() {
        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.d, modifiers: base), .init(.f, modifiers: base), .init(.z, modifiers: base), .init(.h, modifiers: base),
            .init(.leftArrow, modifiers: base), .init(.rightArrow, modifiers: base), .init(.upArrow, modifiers: base),
            .init(.downArrow, modifiers: base), .init(.n, modifiers: base), .init(.p, modifiers: base),
            .init(.e, modifiers: base), .init(.leftArrow, modifiers: shifted), .init(.rightArrow, modifiers: shifted),
            .init(.upArrow, modifiers: shifted), .init(.downArrow, modifiers: shifted),
            .init(.s, modifiers: base), .init(.equal, modifiers: base), .init(.minus, modifiers: base), .init(.b, modifiers: base),
            .init(.r, modifiers: base), .init(.x, modifiers: base), .init(.one, modifiers: base), .init(.two, modifiers: base),
            .init(.three, modifiers: base), .init(.u, modifiers: base), .init(.i, modifiers: base), .init(.j, modifiers: base),
            .init(.k, modifiers: base), .init(.return, modifiers: base), .init(.c, modifiers: base),
            .init(.d, modifiers: shifted), .init(.f, modifiers: shifted), .init(.zero, modifiers: base),
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

    @Test func restoreAllIsControlOptionCommandZero() {
        #expect(KeyboardShortcuts.Name.restoreAll.rawValue == "restoreAll")
        #expect(KeyboardShortcuts.Name.restoreAll.defaultShortcut == .init(.zero, modifiers: base))
    }

    /// Every Phase 3 name, verbatim from 03-UI-SPEC.md Surface 6, so a rename fails here (Pitfall 13).
    @Test func theTableHasExactlyThe33UISpecNames() {
        let spec: Set<String> = [
            "focusLeft", "focusRight", "focusUp", "focusDown", "moveLeft", "moveRight", "moveUp", "moveDown", "dock", "float",
            "swapPrevious", "undo", "growTile", "shrinkTile", "balanceSplit", "rotateSplit", "flipSplit", "finderSplit",
            "snapLeftThird", "snapCenterThird", "snapRightThird", "snapTopLeft", "snapTopRight", "snapBottomLeft", "snapBottomRight",
            "snapMaximize", "snapCenter", "arrangeAll", "floatAll", "toggleDesktop", "togglePause", "restoreAll", "toggleExcludeFrontmost",
        ]
        #expect(spec.count == 33)
        #expect(Hotkeys.entries.count == 33)
        #expect(Set(Hotkeys.entries.map(\.name.rawValue)) == spec)
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
