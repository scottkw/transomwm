import TransomMac
import Testing

/// 08 UI-SPEC Surface 3: the Shortcuts window's Saved Views section.
@Suite struct ViewCopyTests {
    @Test func theShortcutsSectionCopyMatchesTheContract() {
        #expect(ViewCopy.savedViewsSection == "Saved Views")
        #expect(ViewCopy.shortcutsFooter == "Saved views work while zoom is on. If \u{2325} with a number types a character you need, choose another shortcut here.")
    }
}
