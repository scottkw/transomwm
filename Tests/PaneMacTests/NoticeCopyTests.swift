import PaneEngine
import PaneMac
import PaneModel
import Testing

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 42, bundleID: "com.example.notice"))
}

/// N1 copy from UI-SPEC Surface 4, with explicit singular and plural branches.
@Suite struct NoticeCopyTests {
    @Test func oneWindowThatLostItsRoomIsNamedByItsApp() {
        #expect(NoticeCopy.text(for: .lostRoom([ref(1)]), appName: { _ in "Safari" })
            == "A \u{201C}Safari\u{201D} window no longer fits its tile, so it's floating on the Desktop.")
    }

    @Test func severalWindowsThatLostTheirRoomAreCounted() {
        #expect(NoticeCopy.text(for: .lostRoom([ref(1), ref(2)]), appName: { _ in "Safari" })
            == "2 windows no longer fit their tiles, so they're floating on the Desktop.")
    }

    @Test func aLongAppNameIsTruncatedTo32Characters() {
        let name = String(repeating: "x", count: 40)
        #expect(NoticeCopy.text(for: .lostRoom([ref(1)]), appName: { _ in name })
            == "A \u{201C}\(MenuCopy.truncatedAppName(name))\u{201D} window no longer fits its tile, so it's floating on the Desktop.")
    }

    @Test func theLostRoomGlyphIsMacwindow() {
        #expect(NoticeCopy.glyph(for: .lostRoom([ref(1)])) == "macwindow")
    }

    @Test func finderNoWindowIsN9() {
        #expect(NoticeCopy.text(for: .finderNoWindow, appName: { _ in "Finder" }) == "Finder didn't open a new window.")
        #expect(NoticeCopy.glyph(for: .finderNoWindow) == "info.circle")
    }

    @Test func floatedAllIsN4WithSingularAndPlural() {
        #expect(NoticeCopy.text(for: .floatedAll(count: 1), appName: { _ in "" }) == "Floated 1 window. Undo with \u{2303}\u{2325}\u{2318}Z.")
        #expect(NoticeCopy.text(for: .floatedAll(count: 3), appName: { _ in "" }) == "Floated 3 windows. Undo with \u{2303}\u{2325}\u{2318}Z.")
        #expect(NoticeCopy.glyph(for: .floatedAll(count: 3)) == "macwindow")
    }

    @Test func arrangeLeftoversIsN5WithSingularAndPlural() {
        #expect(NoticeCopy.text(for: .arrangeLeftovers(count: 1), appName: { _ in "" }) == "1 window didn't fit, so it stays floating on the Desktop.")
        #expect(NoticeCopy.text(for: .arrangeLeftovers(count: 2), appName: { _ in "" }) == "2 windows didn't fit, so they stay floating on the Desktop.")
        #expect(NoticeCopy.glyph(for: .arrangeLeftovers(count: 2)) == "macwindow")
    }

    @Test func crashRecoveredIsN2WithTheUnplacedSuffix() {
        let base = "Pane quit unexpectedly. Your windows are back on screen and your layout is restored."
        #expect(NoticeCopy.text(for: .crashRecovered(unplaced: 0), appName: { _ in "" }) == base)
        #expect(NoticeCopy.text(for: .crashRecovered(unplaced: 1), appName: { _ in "" })
            == base + " 1 window couldn't be placed and is floating on the Desktop.")
        #expect(NoticeCopy.text(for: .crashRecovered(unplaced: 3), appName: { _ in "" })
            == base + " 3 windows couldn't be placed and are floating on the Desktop.")
        #expect(NoticeCopy.glyph(for: .crashRecovered(unplaced: 0)) == "lifepreserver")
        #expect(Notice.crashRecovered(unplaced: 0).isCrashNotice)
    }

    @Test func crashLoopIsN3() {
        #expect(NoticeCopy.text(for: .crashLoop, appName: { _ in "" })
            == "Pane quit unexpectedly twice in a minute, so arranging is paused. Your windows are on screen. Choose Resume Arranging from the Pane menu when you're ready.")
        #expect(NoticeCopy.glyph(for: .crashLoop) == "lifepreserver")
        #expect(Notice.crashLoop.isCrashNotice)
    }
}
