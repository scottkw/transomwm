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
            "dock", "float", "undo", "focusLeft", "focusRight", "focusUp", "focusDown", "finderSplit",
            "togglePause", "toggleExcludeFrontmost", "moveLeft", "moveRight", "moveUp", "moveDown",
            "swapPrevious", "growTile", "shrinkTile", "balanceSplit", "rotateSplit", "flipSplit", "snapLeftThird", "snapCenterThird",
            "snapRightThird", "snapTopLeft", "snapTopRight", "snapBottomLeft", "snapBottomRight", "snapMaximize", "snapCenter",
            "arrangeAll", "floatAll", "restoreAll",
            "zoomOutAll", "stepOut", "stepIn", "zoomBack", "zoomForward", "panLeft", "panRight", "panUp", "panDown", "frameWindow",
            "showOverview", "nextTab", "previousTab", "moveOutOfGroup",
            "view1", "view2", "view3", "view4", "view5", "view6", "view7", "view8", "view9",
            "saveView1", "saveView2", "saveView3", "saveView4", "saveView5", "saveView6", "saveView7", "saveView8", "saveView9",
            "dockColumn1", "dockColumn2", "dockColumn3", "dockColumn4", "dockColumnMiddle",
            "dockRow1", "dockRow2", "dockRow3", "dockRow4", "dockRowMiddle",
        ])
        #expect(Hotkeys.entries.map(\.command) == [
            .dock, .float, .undo, .focus(.left), .focus(.right), .focus(.top), .focus(.bottom), .finderSplit,
            .togglePause, .toggleExcludeFrontmost, .moveOrSnap(.left), .moveOrSnap(.right), .moveOrSnap(.top), .moveOrSnap(.bottom),
            .swapPrevious, .growTile, .shrinkTile, .balanceSplit, .rotateSplit, .flipSplit, .snap(.leftThird), .snap(.centerThird),
            .snap(.rightThird), .snap(.topLeft), .snap(.topRight), .snap(.bottomLeft), .snap(.bottomRight), .snap(.maximize), .snap(.center),
            .arrangeAll, .floatAll, .restoreAll,
            .camera(.zoomOutAll), .camera(.stepOut), .camera(.stepIn), .camera(.back), .camera(.forward), .camera(.pan(.left)),
            .camera(.pan(.right)), .camera(.pan(.top)), .camera(.pan(.bottom)), .camera(.frameWindow),
            .camera(.overview), .tabs(.next), .tabs(.previous), .tabs(.moveOut),
        ] + ViewSlot.all.map { .camera(.view($0)) } + ViewSlot.all.map { .camera(.saveView($0)) } + [
            .dockFourth(.first, .horizontal), .dockFourth(.second, .horizontal), .dockFourth(.third, .horizontal), .dockFourth(.fourth, .horizontal),
            .dockFourth(.middle, .horizontal), .dockFourth(.first, .vertical), .dockFourth(.second, .vertical), .dockFourth(.third, .vertical),
            .dockFourth(.fourth, .vertical), .dockFourth(.middle, .vertical),
        ])
    }

    @Test func defaultsAreControlOptionCommandPlusALetter() {
        let expected: [KeyboardShortcuts.Shortcut] = [
            .init(.d, modifiers: base), .init(.f, modifiers: base), .init(.z, modifiers: base),
            .init(.leftArrow, modifiers: base), .init(.rightArrow, modifiers: base), .init(.upArrow, modifiers: base),
            .init(.downArrow, modifiers: base), .init(.n, modifiers: base), .init(.p, modifiers: base),
            .init(.e, modifiers: base), .init(.leftArrow, modifiers: shifted), .init(.rightArrow, modifiers: shifted),
            .init(.upArrow, modifiers: shifted), .init(.downArrow, modifiers: shifted),
            .init(.s, modifiers: base), .init(.equal, modifiers: base), .init(.minus, modifiers: base), .init(.b, modifiers: base),
            .init(.r, modifiers: base), .init(.x, modifiers: base), .init(.one, modifiers: base), .init(.two, modifiers: base),
            .init(.three, modifiers: base), .init(.u, modifiers: base), .init(.i, modifiers: base), .init(.j, modifiers: base),
            .init(.k, modifiers: base), .init(.return, modifiers: base), .init(.c, modifiers: base),
            .init(.d, modifiers: shifted), .init(.f, modifiers: shifted), .init(.zero, modifiers: base),
            // UI-SPEC Hotkeys and URLs (04): O , . [ ] Home End PageUp PageDown M (G retired, 8.1.1 D-13)
            .init(.o, modifiers: base), .init(.comma, modifiers: base), .init(.period, modifiers: base),
            .init(.leftBracket, modifiers: base), .init(.rightBracket, modifiers: base), .init(.home, modifiers: base),
            .init(.end, modifiers: base), .init(.pageUp, modifiers: base), .init(.pageDown, modifiers: base),
            .init(.m, modifiers: base),
            // 06 UI-SPEC Surface 4: Show Overview
            .init(.a, modifiers: base),
            // 07 UI-SPEC Surface 7: Next Tab, Previous Tab, Move Out of Group
            .init(.t, modifiers: base), .init(.t, modifiers: shifted), .init(.l, modifiers: base),
        ]
        // 08 UI-SPEC Surface 3: the saved views follow the OS-version rule (ViewChords), not ⌃⌥⌘.
        #expect(Array(Hotkeys.entries.map(\.name.defaultShortcut).prefix(46)) == expected)
    }

    /// 08.1 UI-SPEC Surface 4: the digit row by key position, columns then rows, 0 last.
    @Test func theFourthsAreAllFourModifiersPlusADigit() {
        let digits: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero]
        #expect(Hotkeys.fourthNames.map(\.defaultShortcut) == digits.map { .init($0, modifiers: shifted) })
    }

    @Test func noTwoEntriesShareADefaultChord() {
        let chords = Hotkeys.entries.compactMap(\.name.defaultShortcut)
        #expect(chords.count == Hotkeys.entries.count)
        #expect(Set(chords).count == chords.count)
    }

    /// TILE-10: zoom off disables zoom names only, so the fourths must stay out of them.
    @Test func theFourthsAreNotZoomNames() {
        #expect(Hotkeys.fourthNames.count == 10)
        #expect(Set(Hotkeys.zoomNames).isDisjoint(with: Hotkeys.fourthNames))
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

    /// Every Phase 3 name, verbatim from 03-UI-SPEC.md Surface 6, so a rename fails here (Pitfall 13); toggleDesktop is
    /// retired (8.1.1 D-09).
    @Test func theTableKeepsThe32LivePhase3Names() {
        let spec: Set<String> = [
            "focusLeft", "focusRight", "focusUp", "focusDown", "moveLeft", "moveRight", "moveUp", "moveDown", "dock", "float",
            "swapPrevious", "undo", "growTile", "shrinkTile", "balanceSplit", "rotateSplit", "flipSplit", "finderSplit",
            "snapLeftThird", "snapCenterThird", "snapRightThird", "snapTopLeft", "snapTopRight", "snapBottomLeft", "snapBottomRight",
            "snapMaximize", "snapCenter", "arrangeAll", "floatAll", "togglePause", "restoreAll", "toggleExcludeFrontmost",
        ]
        #expect(spec.count == 32)
        #expect(spec.isSubset(of: Set(Hotkeys.entries.map(\.name.rawValue))))
    }

    /// The 11 zoom names, verbatim from 04-UI-SPEC.md Hotkeys and URLs, less frameDesktop (retired, 8.1.1 D-13), plus
    /// Show Overview (06 UI-SPEC Surface 4) and the 18 saved-view names (08 UI-SPEC Surface 3, D-17), which zoom off disables with them; 32 + 11 + the 3 tab names (07
    /// Surface 7, enabled with zoom off) + 18 + the 10 fourths (08.1 Surface 4, enabled with zoom off) = 74.
    @Test func theZoomNamesAreTheUISpecTenPlusShowOverviewAndTheSavedViews() {
        let zoom = [
            "zoomOutAll", "stepOut", "stepIn", "zoomBack", "zoomForward", "panLeft", "panRight", "panUp", "panDown", "frameWindow",
            "showOverview",
        ] + (1...9).map { "view\($0)" } + (1...9).map { "saveView\($0)" }
        #expect(Hotkeys.zoomNames.map(\.rawValue) == zoom)
        #expect(Hotkeys.entries.count == 74)
        #expect(Set(Hotkeys.entries.filter { if case .camera = $0.command { true } else { false } }.map(\.name.rawValue)) == Set(zoom))
    }

    /// T-08.1.1-06: a binding stored under a retired raw value must never fire another command.
    @Test func theRetiredDesktopNamesAreNotInTheTable() {
        let names = Set(Hotkeys.entries.map(\.name.rawValue))
        #expect(!names.isEmpty)
        #expect(names.isDisjoint(with: ["toggleDesktop", "frameDesktop"]))
        #expect(!Hotkeys.entries.contains { $0.name.defaultShortcut == .init(.h, modifiers: base) }, "⌃⌥⌘H reaches apps")
        #expect(!Hotkeys.entries.contains { $0.name.defaultShortcut == .init(.g, modifiers: base) }, "⌃⌥⌘G reaches apps")
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

    /// D-01 fallback: macOS 15.0 and 15.1 refuse Option-only and Option+Shift-only hotkeys, so they get ⌃⌥ / ⇧⌃⌥.
    @Test(arguments: [(15, 0), (15, 1)])
    func viewChordsAddControlOn15Point0And15Point1(major: Int, minor: Int) {
        let os = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        #expect(ViewChords.modifiers(save: false, os: os) == [.control, .option])
        #expect(ViewChords.modifiers(save: true, os: os) == [.shift, .control, .option])
    }

    @Test(arguments: [(14, 6), (15, 2), (26, 0), (27, 0)])
    func viewChordsAreOptionElsewhere(major: Int, minor: Int) {
        let os = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
        #expect(ViewChords.modifiers(save: false, os: os) == [.option])
        #expect(ViewChords.modifiers(save: true, os: os) == [.shift, .option])
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
