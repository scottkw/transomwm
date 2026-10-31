import KeyboardShortcuts
import TransomEngine
@testable import TransomMac
import Testing

/// ZOOM-08, 04 UI-SPEC Surface 8: one Recorder row per hotkey, 45 in all (06 UI-SPEC Surface 4 adds Show Overview), in the
/// Surface 8 sections and titles.
@Suite @MainActor struct ShortcutsModelTests {
    @Test func theSectionsFollowSurface8() {
        #expect(ShortcutsModel.sections.map(\.title) == ["Zoom", "Arrange", "Split", "Snap Floating Window", "Safety", "Exclusions"])
    }

    @Test func the45RowsBindTheHotkeyNamesOnceEach() {
        let names = ShortcutsModel.sections.flatMap(\.rows).map(\.name)
        #expect(names.count == 45)
        #expect(Set(names).count == 45)
        #expect(Set(names) == Set(Hotkeys.entries.map(\.name)))
    }

    @Test func theRowTitlesMatchSurface8() {
        #expect(ShortcutsModel.sections.map { $0.rows.map(\.title) } == [
            [
                "Show Overview", "Zoom Out to All Windows", "Zoom Out One Level", "Zoom In One Level", "Back", "Forward", "Move View Left", "Move View Right",
                "Move View Up", "Move View Down", "Frame Focused Window", "Frame Desktop",
            ],
            [
                "Dock Window", "Float Window", "Swap with Previous Window", "Undo Layout Change", "Focus Left", "Focus Right", "Focus Up",
                "Focus Down", "Move Window Left or Snap to Left Half", "Move Window Right or Snap to Right Half",
                "Move Window Up or Snap to Top Half", "Move Window Down or Snap to Bottom Half", "Arrange All Windows", "Float All Windows",
                "Hide or Show Desktop Tile",
            ],
            ["Grow Tile", "Shrink Tile", "Balance Split", "Rotate Layout", "Flip Split", "Split with New Finder Window"],
            [
                "Left Third", "Center Third", "Right Third", "Top Left Quarter", "Top Right Quarter", "Bottom Left Quarter",
                "Bottom Right Quarter", "Maximize", "Center",
            ],
            ["Pause or Resume Arranging", "Restore All Windows"],
            ["Don't Arrange Frontmost App"],
        ])
    }

    /// The stored bindings are the defaults in the test process (nothing records a shortcut there).
    @Test func aChordAnotherTransomCommandUsesIsRejectedWithItsTitle() {
        let dock = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option, .command])
        #expect(ShortcutsModel.conflictMessage(for: dock, excluding: .float) == "This shortcut is already used by \u{201C}Dock Window\u{201D} in Transom.")
        #expect(ShortcutsModel.conflictMessage(for: dock, excluding: .dock) == nil, "a row's own chord is not a conflict")
        #expect(ShortcutsModel.conflictMessage(for: .init(.l, modifiers: [.control, .option, .command]), excluding: .float) == nil)
        #expect(
            ShortcutsModel.conflictMessage(for: .init(.a, modifiers: [.control, .option, .command]), excluding: .float)
                == "This shortcut is already used by \u{201C}Show Overview\u{201D} in Transom.")
    }

    @Test func showOverviewIsTheFirstZoomRowAndTheZoomSectionHasTheTakeoverFooter() {
        #expect(ShortcutsModel.sections.first?.rows.first?.name == .showOverview)
        #expect(ShortcutsModel.zoomFooter == "With Replace Mission Control on, the Mission Control keys also show the overview.")
    }

    @Test func theWindowCopyMatchesTheContract() {
        #expect(ZoomCopy.shortcutsWindowTitle == "Shortcuts")
        #expect(ZoomCopy.mouseSection == "Mouse")
        #expect(ZoomCopy.doubleClickToggle == "Double-click a title bar to frame its window")
        #expect(ZoomCopy.doubleClickFooterOn == "When off, double-clicking a title bar does what Desktop & Dock settings say.")
        #expect(ZoomCopy.doubleClickFooterZoomOff == "Turn on zoom to use this.")
        #expect(ZoomCopy.restoreDefaults == "Restore Defaults")
        #expect(ZoomCopy.restoreDefaultsMessage == "Restore all shortcuts to their defaults?")
        #expect(ZoomCopy.restoreDefaultsInformative == "Every shortcut you changed or cleared goes back to its default. This can't be undone.")
    }
}
