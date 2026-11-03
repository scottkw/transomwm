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
            "zoomOutAll", "stepOut", "stepIn", "zoomBack", "zoomForward", "panLeft", "panRight", "panUp", "panDown", "frameWindow",
            "frameDesktop", "showOverview", "nextTab", "previousTab", "moveOutOfGroup",
            "view1", "view2", "view3", "view4", "view5", "view6", "view7", "view8", "view9",
            "saveView1", "saveView2", "saveView3", "saveView4", "saveView5", "saveView6", "saveView7", "saveView8", "saveView9",
        ])
        #expect(Hotkeys.entries.map(\.command) == [
            .dock, .float, .undo, .toggleDesktop, .focus(.left), .focus(.right), .focus(.top), .focus(.bottom), .finderSplit,
            .togglePause, .toggleExcludeFrontmost, .moveOrSnap(.left), .moveOrSnap(.right), .moveOrSnap(.top), .moveOrSnap(.bottom),
            .swapPrevious, .growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit, .snap(.leftThird), .snap(.centerThird),
            .snap(.rightThird), .snap(.topLeft), .snap(.topRight), .snap(.bottomLeft), .snap(.bottomRight), .snap(.maximize), .snap(.center),
            .arrangeAll, .floatAll, .restoreAll,
            .camera(.zoomOutAll), .camera(.stepOut), .camera(.stepIn), .camera(.back), .camera(.forward), .camera(.pan(.left)),
            .camera(.pan(.right)), .camera(.pan(.top)), .camera(.pan(.bottom)), .camera(.frameWindow), .camera(.frameDesktop),
            .camera(.overview), .tabs(.next), .tabs(.previous), .tabs(.moveOut),
        ] + ViewSlot.all.map { .camera(.view($0)) } + ViewSlot.all.map { .camera(.saveView($0)) })
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
            // UI-SPEC Hotkeys and URLs (04): O , . [ ] Home End PageUp PageDown M G
            .init(.o, modifiers: base), .init(.comma, modifiers: base), .init(.period, modifiers: base),
            .init(.leftBracket, modifiers: base), .init(.rightBracket, modifiers: base), .init(.home, modifiers: base),
            .init(.end, modifiers: base), .init(.pageUp, modifiers: base), .init(.pageDown, modifiers: base),
            .init(.m, modifiers: base), .init(.g, modifiers: base),
            // 06 UI-SPEC Surface 4: Show Overview
            .init(.a, modifiers: base),
            // 07 UI-SPEC Surface 7: Next Tab, Previous Tab, Move Out of Group
            .init(.t, modifiers: base), .init(.t, modifiers: shifted), .init(.l, modifiers: base),
        ]
        // 08 UI-SPEC Surface 3: the saved views follow the OS-version rule (ViewChords), not ⌃⌥⌘.
        #expect(Array(Hotkeys.entries.map(\.name.defaultShortcut).prefix(48)) == expected)
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
    @Test func theTableKeepsThe33Phase3Names() {
        let spec: Set<String> = [
            "focusLeft", "focusRight", "focusUp", "focusDown", "moveLeft", "moveRight", "moveUp", "moveDown", "dock", "float",
            "swapPrevious", "undo", "growTile", "shrinkTile", "balanceSplit", "rotateSplit", "flipSplit", "finderSplit",
            "snapLeftThird", "snapCenterThird", "snapRightThird", "snapTopLeft", "snapTopRight", "snapBottomLeft", "snapBottomRight",
            "snapMaximize", "snapCenter", "arrangeAll", "floatAll", "toggleDesktop", "togglePause", "restoreAll", "toggleExcludeFrontmost",
        ]
        #expect(spec.count == 33)
        #expect(spec.isSubset(of: Set(Hotkeys.entries.map(\.name.rawValue))))
    }

    /// The 11 zoom names, verbatim from 04-UI-SPEC.md Hotkeys and URLs, plus Show Overview (06 UI-SPEC Surface 4) and the
    /// 18 saved-view names (08 UI-SPEC Surface 3, D-17), which zoom off disables with them; 33 + 12 + the 3 tab names (07
    /// Surface 7, enabled with zoom off) + 18 = 66.
    @Test func theZoomNamesAreTheUISpecElevenPlusShowOverviewAndTheSavedViews() {
        let zoom = [
            "zoomOutAll", "stepOut", "stepIn", "zoomBack", "zoomForward", "panLeft", "panRight", "panUp", "panDown", "frameWindow", "frameDesktop",
            "showOverview",
        ] + (1...9).map { "view\($0)" } + (1...9).map { "saveView\($0)" }
        #expect(Hotkeys.zoomNames.map(\.rawValue) == zoom)
        #expect(Hotkeys.entries.count == 66)
        #expect(Set(Hotkeys.entries.filter { if case .camera = $0.command { true } else { false } }.map(\.name.rawValue)) == Set(zoom))
    }

    /// 07 UI-SPEC Surface 7: persistent names (Pitfall 13), not zoom names.
    @Test func theTabNamesKeepTheirRawValuesAndDefaults() {
        #expect(KeyboardShortcuts.Name.nextTab.rawValue == "nextTab")
        #expect(KeyboardShortcuts.Name.previousTab.rawValue == "previousTab")
        #expect(KeyboardShortcuts.Name.moveOutOfGroup.rawValue == "moveOutOfGroup")
        #expect(KeyboardShortcuts.Name.nextTab.defaultShortcut == .init(.t, modifiers: base))
        #expect(KeyboardShortcuts.Name.previousTab.defaultShortcut == .init(.t, modifiers: shifted))
        #expect(KeyboardShortcuts.Name.moveOutOfGroup.defaultShortcut == .init(.l, modifiers: base))
        #expect(![KeyboardShortcuts.Name.nextTab, .previousTab, .moveOutOfGroup].contains { Hotkeys.zoomNames.contains($0) })
    }

    /// 08 UI-SPEC Surface 3: persistent names (Pitfall 13) mapping to the slot's camera command, digit keys 1–9.
    @Test func theSavedViewNamesMapToTheirSlots() {
        for slot in ViewSlot.all {
            let go = Hotkeys.entries.first { $0.name.rawValue == "view\(slot.number)" }
            let save = Hotkeys.entries.first { $0.name.rawValue == "saveView\(slot.number)" }
            #expect(go?.command == .camera(.view(slot)))
            #expect(save?.command == .camera(.saveView(slot)))
            #expect(go?.name.defaultShortcut == .init(ViewChords.digits[slot.number - 1], modifiers: ViewChords.modifiers(save: false)))
            #expect(save?.name.defaultShortcut == .init(ViewChords.digits[slot.number - 1], modifiers: ViewChords.modifiers(save: true)))
        }
        #expect(ViewChords.digits == [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine])
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

    /// ⌃⌥⌘8 is a macOS Accessibility shortcut (Invert Colors), so nothing uses it (UI-SPEC system-shortcut check).
    @Test func noEntryUsesAShortcutReservedByMacOSAccessibility() {
        #expect(!Hotkeys.entries.isEmpty)
        let reserved: [KeyboardShortcuts.Shortcut] = [.init(.eight, modifiers: base)]
        for entry in Hotkeys.entries {
            #expect(!reserved.contains { $0 == entry.name.defaultShortcut }, "\(entry.name.rawValue) uses a reserved shortcut")
        }
    }

    /// ⌃⌥⌘, and ⌃⌥⌘. (macOS contrast shortcuts, off by default) are kept by decision for step out and in only (CONTEXT C).
    @Test func commaAndPeriodAreUsedOnlyByStepOutAndStepIn() {
        let users = { (key: KeyboardShortcuts.Key) in
            Hotkeys.entries.filter { $0.name.defaultShortcut == .init(key, modifiers: base) }.map(\.name.rawValue)
        }
        #expect(users(.comma) == ["stepOut"])
        #expect(users(.period) == ["stepIn"])
    }
}
