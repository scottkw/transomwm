@testable import TransomMac
import Testing

/// The menu-bar glyph per state (UI-SPEC Surface 8): nil is the warning symbol.
struct StatusGlyphTests {
    @Test func theWarningShowsUntilAccessIsReady() {
        #expect(StatusItemController.glyphName(ready: false, paused: false, zoomed: false) == nil)
        #expect(StatusItemController.glyphName(ready: false, paused: true, zoomed: true) == nil)
    }

    @Test func theZoomedGlyphIsUsedOnlyWhenZoomedIn() {
        #expect(StatusItemController.glyphName(ready: true, paused: false, zoomed: true) == "TransomZoomedTemplate")
        #expect(StatusItemController.glyphName(ready: true, paused: false, zoomed: false) == "TransomTemplate")
    }

    @Test func pausedUsesTheNormalGlyph() {
        #expect(StatusItemController.glyphName(ready: true, paused: true, zoomed: true) == "TransomTemplate")
        #expect(StatusItemController.glyphName(ready: true, paused: true, zoomed: false) == "TransomTemplate")
    }
}
