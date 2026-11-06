import KeyboardShortcuts
import TransomEngine
@testable import TransomMac
import Testing

/// ZOOM-08, 04 UI-SPEC Surface 8: one Recorder row per hotkey, 74 in all (06 Surface 4 adds Show Overview, 07 Surface 7 the Tabs rows,
/// 08 Surface 3 the Saved Views rows, 08.1 Surface 4 the Dock to Fourth rows), in the Surface 8 sections and titles.
@Suite @MainActor struct ShortcutsModelTests {
    @Test func theSectionsFollowSurface8() {
        #expect(ShortcutsModel.sections.map(\.title) == ["Zoom", "Saved Views", "Arrange", "Dock to Fourth", "Split", "Snap Floating Window", "Tabs", "Safety", "Exclusions"])
    }

    @Test func the74RowsBindTheHotkeyNamesOnceEach() {
        let names = ShortcutsModel.sections.flatMap(\.rows).map(\.name)
        #expect(ShortcutsModel.sections.count == 9)
        #expect(names.count == 74)
        #expect(Set(names).count == 74)
        #expect(Set(names) == Set(Hotkeys.entries.map(\.name)))
    }

    @Test func theRowTitlesMatchSurface8() {
        #expect(ShortcutsModel.sections.map { $0.rows.map(\.title) } == [
            [
                "Show Overview", "Zoom Out to All Windows", "Zoom Out One Level", "Zoom In One Level", "Back", "Forward", "Move View Left", "Move View Right",
                "Move View Up", "Move View Down", "Frame Focused Window",
            ],
            (1...9).map { "Go to View \($0)" } + (1...9).map { "Save View \($0)" },
            [
                "Dock Window", "Float Window", "Swap with Previous Window", "Undo Layout Change", "Focus Left", "Focus Right", "Focus Up",
                "Focus Down", "Move Window Left or Snap to Left Half", "Move Window Right or Snap to Right Half",
                "Move Window Up or Snap to Top Half", "Move Window Down or Snap to Bottom Half", "Arrange All Windows", "Float All Windows",
            ],
            [
                "Dock to 1st Column", "Dock to 2nd Column", "Dock to 3rd Column", "Dock to 4th Column", "Dock to Middle Half Column",
                "Dock to 1st Row", "Dock to 2nd Row", "Dock to 3rd Row", "Dock to 4th Row", "Dock to Middle Half Row",
            ],
            ["Grow Tile", "Shrink Tile", "Balance Split", "Rotate Layout", "Flip Split", "Split with New Finder Window"],
            [
                "Left Third", "Center Third", "Right Third", "Top Left Quarter", "Top Right Quarter", "Bottom Left Quarter",
                "Bottom Right Quarter", "Maximize", "Center",
            ],
            ["Next Tab", "Previous Tab", "Move Out of Group"],
            ["Pause or Resume Arranging", "Restore All Windows"],
            ["Don't Arrange Frontmost App"],
        ])
    }

    /// The stored bindings are the defaults in the test process (nothing records a shortcut there).
    @Test func aChordAnotherTransomCommandUsesIsRejectedWithItsTitle() {
        let dock = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option, .command])
        #expect(ShortcutsModel.conflictMessage(for: dock, excluding: .float) == "This shortcut is already used by \u{201C}Dock Window\u{201D} in Transom.")
        #expect(ShortcutsModel.conflictMessage(for: dock, excluding: .dock) == nil, "a row's own chord is not a conflict")
        #expect(ShortcutsModel.conflictMessage(for: .init(.y, modifiers: [.control, .option, .command]), excluding: .float) == nil)
        #expect(
            ShortcutsModel.conflictMessage(for: .init(.a, modifiers: [.control, .option, .command]), excluding: .float)
                == "This shortcut is already used by \u{201C}Show Overview\u{201D} in Transom.")
    }

    /// 08.1 UI-SPEC Surface 4: directly after Arrange, with no footer.
    @Test func theDockToFourthSectionFollowsArrange() {
        let titles = ShortcutsModel.sections.map(\.title)
        #expect(titles.firstIndex(of: "Dock to Fourth") == titles.firstIndex(of: "Arrange").map { $0 + 1 })
        #expect(ShortcutsModel.sections.first { $0.title == "Dock to Fourth" }?.rows.map(\.name) == Hotkeys.fourthNames)
    }

    @Test func theTabsSectionFollowsSnapWithItsThreeNames() {
        let titles = ShortcutsModel.sections.map(\.title)
        #expect(titles.firstIndex(of: "Tabs") == titles.firstIndex(of: "Snap Floating Window").map { $0 + 1 })
        #expect(ShortcutsModel.sections.first { $0.title == "Tabs" }?.rows.map(\.name) == [.nextTab, .previousTab, .moveOutOfGroup])
    }

    /// 08 UI-SPEC Surface 3: the section right after Zoom, go rows first, with its footer.
    @Test func theSavedViewsSectionFollowsZoom() {
        #expect(ShortcutsModel.sections[1].title == ViewCopy.savedViewsSection)
        #expect(ShortcutsModel.sections[1].rows.map(\.name) == [
            .view1, .view2, .view3, .view4, .view5, .view6, .view7, .view8, .view9,
            .saveView1, .saveView2, .saveView3, .saveView4, .saveView5, .saveView6, .saveView7, .saveView8, .saveView9,
        ])
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
