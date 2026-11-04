import TransomMac
import Testing

/// 08 UI-SPEC Surface 3 (the Shortcuts window's Saved Views section), Debug lines and Announcements.
@Suite struct ViewCopyTests {
    @Test func theShortcutsSectionCopyMatchesTheContract() {
        #expect(ViewCopy.savedViewsSection == "Saved Views")
        #expect(ViewCopy.shortcutsFooter == "Saved views work while zoom is on. If \u{2325} with a number types a character you need, choose another shortcut here.")
    }

    @Test func theDebugLineCountsSlots() {
        #expect(ViewCopy.savedViewsLine(slots: []) == "Saved views: none")
        #expect(ViewCopy.savedViewsLine(slots: [3]) == "Saved views: 1 slot (3)")
        #expect(ViewCopy.savedViewsLine(slots: [1, 3, 5]) == "Saved views: 3 slots (1, 3, 5)")
    }

    @Test func theCommandLineToolLine() {
        #expect(ViewCopy.cliLine(listening: true) == "Command-line tool: listening")
        #expect(ViewCopy.cliLine(listening: false) == "Command-line tool: off (couldn't listen)")
    }

    @Test func theJoinedAnnouncementPrefixesTheReveal() {
        #expect(ViewCopy.joinedAnnouncement(slot: 3, reveal: "Showing 2 windows") == "View 3. Showing 2 windows")
    }
}
