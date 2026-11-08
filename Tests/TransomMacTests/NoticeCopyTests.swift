import TransomEngine
import TransomMac
import TransomModel
import Testing

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 42, bundleID: "com.example.notice"))
}

/// N1 copy from UI-SPEC Surface 4, with explicit singular and plural branches.
@Suite struct NoticeCopyTests {
    @Test func oneWindowThatLostItsRoomIsNamedByItsApp() {
        #expect(NoticeCopy.text(for: .lostRoom([ref(1)]), appName: { _ in "Safari" })
            == "A \u{201C}Safari\u{201D} window no longer fits its tile, so it's floating.")
    }

    @Test func severalWindowsThatLostTheirRoomAreCounted() {
        #expect(NoticeCopy.text(for: .lostRoom([ref(1), ref(2)]), appName: { _ in "Safari" })
            == "2 windows no longer fit their tiles, so they're floating.")
    }

    @Test func aLongAppNameIsTruncatedTo32Characters() {
        let name = String(repeating: "x", count: 40)
        #expect(NoticeCopy.text(for: .lostRoom([ref(1)]), appName: { _ in name })
            == "A \u{201C}\(MenuCopy.truncatedAppName(name))\u{201D} window no longer fits its tile, so it's floating.")
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
        #expect(NoticeCopy.text(for: .arrangeLeftovers(count: 1), appName: { _ in "" }) == "1 window didn't fit, so it stays floating.")
        #expect(NoticeCopy.text(for: .arrangeLeftovers(count: 2), appName: { _ in "" }) == "2 windows didn't fit, so they stay floating.")
        #expect(NoticeCopy.glyph(for: .arrangeLeftovers(count: 2)) == "macwindow")
    }

    @Test func crashRecoveredIsN2WithTheUnplacedSuffix() {
        let base = "Transom quit unexpectedly. Your windows are back on screen and your layout is restored."
        #expect(NoticeCopy.text(for: .crashRecovered(unplaced: 0), appName: { _ in "" }) == base)
        #expect(NoticeCopy.text(for: .crashRecovered(unplaced: 1), appName: { _ in "" })
            == base + " 1 window couldn't be placed and is floating.")
        #expect(NoticeCopy.text(for: .crashRecovered(unplaced: 3), appName: { _ in "" })
            == base + " 3 windows couldn't be placed and are floating.")
        #expect(NoticeCopy.glyph(for: .crashRecovered(unplaced: 0)) == "lifepreserver")
        #expect(Notice.crashRecovered(unplaced: 0).isCrashNotice)
    }

    @Test func crashLoopIsN3() {
        #expect(NoticeCopy.text(for: .crashLoop, appName: { _ in "" })
            == "Transom quit unexpectedly twice in a minute, so arranging is paused. Your windows are on screen. Choose Resume Arranging from the Transom menu when you're ready.")
        #expect(NoticeCopy.glyph(for: .crashLoop) == "lifepreserver")
        #expect(Notice.crashLoop.isCrashNotice)
    }

    @Test func restoredIsN6WithSingularPluralAndNone() {
        #expect(NoticeCopy.text(for: .restored(count: 1), appName: { _ in "" }) == "Moved 1 window back on screen.")
        #expect(NoticeCopy.text(for: .restored(count: 2), appName: { _ in "" }) == "Moved 2 windows back on screen.")
        #expect(NoticeCopy.text(for: .restored(count: 0), appName: { _ in "" }) == "All windows were already on screen.")
        #expect(NoticeCopy.glyph(for: .restored(count: 2)) == "checkmark.circle")
        #expect(!Notice.restored(count: 1).isCrashNotice)
    }

    @Test func turnOffFailedIsN7WithTheOrangeWarningGlyph() {
        #expect(NoticeCopy.text(for: .turnOffFailed(.edgeTiling), appName: { _ in "" })
            == "Couldn't turn off macOS edge tiling. Turn it off here in Desktop & Dock.")
        #expect(NoticeCopy.text(for: .turnOffFailed(.stageManager), appName: { _ in "" })
            == "Couldn't turn off Stage Manager. Turn it off here in Desktop & Dock.")
        #expect(NoticeCopy.glyph(for: .turnOffFailed(.clickWallpaper)) == "exclamationmark.triangle.fill")
        #expect(NoticeCopy.isWarning(.turnOffFailed(.clickWallpaper)))
        #expect(!NoticeCopy.isWarning(.settingsRestored))
    }

    @Test func displaysDisconnectedIsN12WithOneDisplayAndOneOrSeveralWindows() {
        #expect(NoticeCopy.text(for: .displaysDisconnected(names: ["DELL U2723QE"], windows: 1), appName: { _ in "" })
            == "\u{201C}DELL U2723QE\u{201D} was disconnected, so 1 window from it is floating here until you reconnect it.")
        #expect(NoticeCopy.text(for: .displaysDisconnected(names: ["DELL U2723QE"], windows: 3), appName: { _ in "" })
            == "\u{201C}DELL U2723QE\u{201D} was disconnected, so 3 windows from it are floating here until you reconnect it.")
    }

    @Test func displaysDisconnectedIsN12WithSeveralDisplays() {
        #expect(NoticeCopy.text(for: .displaysDisconnected(names: ["A", "B"], windows: 4), appName: { _ in "" })
            == "2 displays were disconnected, so 4 windows from them are floating here until you reconnect them.")
        #expect(NoticeCopy.text(for: .displaysDisconnected(names: ["A", "B"], windows: 1), appName: { _ in "" })
            == "2 displays were disconnected, so 1 window from them is floating here until you reconnect them.")
    }

    @Test func aLongDisplayNameIsTruncatedTo32Characters() {
        let name = String(repeating: "d", count: 40)
        #expect(NoticeCopy.text(for: .displaysDisconnected(names: [name], windows: 1), appName: { _ in "" })
            == "\u{201C}\(String(repeating: "d", count: 32))\u{2026}\u{201D} was disconnected, so 1 window from it is floating here until you reconnect it.")
    }

    @Test func displaysDisconnectedUsesTheDisplayGlyphAndIsNoWarning() {
        let notice = Notice.displaysDisconnected(names: ["A"], windows: 1)
        #expect(NoticeCopy.glyph(for: notice) == "display")
        #expect(!NoticeCopy.isWarning(notice))
        #expect(!notice.isCrashNotice)
    }

    @Test func settingsRestoredIsN8() {
        #expect(NoticeCopy.text(for: .settingsRestored, appName: { _ in "" }) == "macOS window settings restored.")
        #expect(NoticeCopy.glyph(for: .settingsRestored) == "checkmark.circle")
    }

    @Test func takeoverCrashedIsN10() {
        #expect(NoticeCopy.text(for: .takeoverCrashed, appName: { _ in "" })
            == "Transom quit unexpectedly, so Mission Control has its keys back. Turn on Settings ▸ Zoom & Gestures ▸ Use the Mission Control keys for the overview to use them again.")
        #expect(NoticeCopy.glyph(for: .takeoverCrashed) == "lifepreserver")
        #expect(!NoticeCopy.isWarning(.takeoverCrashed))
        #expect(!Notice.takeoverCrashed.isCrashNotice, "queued behind N2/N3, never holding the toast like them")
    }

    @Test func takeoverApplyFailedIsN11() {
        #expect(NoticeCopy.text(for: .takeoverApplyFailed, appName: { _ in "" })
            == "Couldn't take over Mission Control's keys, so Mission Control works as before.")
        #expect(NoticeCopy.glyph(for: .takeoverApplyFailed) == "exclamationmark.triangle.fill")
        #expect(NoticeCopy.isWarning(.takeoverApplyFailed))
        #expect(!Notice.takeoverApplyFailed.isCrashNotice)
    }

    /// 08 UI-SPEC View toasts N13–N19, for slot 3 and slot 9.
    @Test(arguments: [3, 9])
    func theViewNoticesMatchTheContract(number: Int) throws {
        let slot = try #require(ViewSlot(number))
        let n = number
        let rows: [(Notice, String, String)] = [
            (.viewSaved(slot, replaced: false, displayUUID: nil), "Saved view \(n)", "bookmark"),
            (.viewSaved(slot, replaced: true, displayUUID: nil), "Replaced view \(n)", "bookmark"),
            (.viewShown(slot, displayUUID: nil), "View \(n)", "viewfinder"),
            (.viewEmpty(slot, displayUUID: nil), "No view in slot \(n)", "viewfinder"),
            (.viewWindowsClosed(slot, displayUUID: nil), "The windows in view \(n) have closed. Showing all windows.", "info.circle"),
            (.viewDisplayGone(slot, displayUUID: nil), "View \(n) is on a display that isn't connected.", "display"),
            (.viewNothingToSave(displayUUID: nil), "There are no windows in this view to save.", "info.circle"),
        ]
        for (notice, text, glyph) in rows {
            #expect(NoticeCopy.text(for: notice, appName: { _ in "" }) == text)
            #expect(NoticeCopy.glyph(for: notice) == glyph)
            #expect(!NoticeCopy.isWarning(notice))
        }
    }
}
