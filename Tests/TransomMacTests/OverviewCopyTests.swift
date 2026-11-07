import TransomMac
import Testing

/// UI-SPEC Surface 7: the S1-S4 Debug lines.
@Suite struct OverviewCopyTests {
    @Test(arguments: [
        (OverviewCopy.SpacesLine.counts(spaces: 3, displays: 1, shared: false), "Spaces: 3 on 1 display"),
        (.counts(spaces: 5, displays: 2, shared: false), "Spaces: 5 across 2 displays"),
        (.counts(spaces: 4, displays: 2, shared: true), "Spaces: 4, shared by 2 displays"),
        (.visited(2), "Spaces: 2 visited since launch"),
    ])
    func theSpacesLineMatchesTheContract(line: OverviewCopy.SpacesLine, expected: String) {
        #expect(OverviewCopy.spacesLine(line) == expected)
    }

    @Test(arguments: [
        (OverviewCopy.DisplaysLine.settled(displays: 2, arrangement: "3f9a"), "Displays: 2, arrangement 3f9a"),
        (.settled(displays: 1, arrangement: "0b12"), "Displays: 1, arrangement 0b12"),
        (.settling, "Displays: settling\u{2026}"),
        (.waitingForWake, "Displays: waiting for wake"),
    ])
    func theDisplaysLineMatchesTheContract(line: OverviewCopy.DisplaysLine, expected: String) {
        #expect(OverviewCopy.displaysLine(line) == expected)
    }

    @Test func theSavedArrangementsLineSaysNoneYetForZero() {
        #expect(OverviewCopy.savedArrangementsLine(0) == "Saved arrangements: none yet")
        #expect(OverviewCopy.savedArrangementsLine(2) == "Saved arrangements: 2")
    }

    @Test(arguments: [
        (0, 0, "Dormant desks: none"),
        (1, 1, "Dormant desks: 1 (1 display away)"),
        (3, 1, "Dormant desks: 3 (1 display away)"),
        (4, 2, "Dormant desks: 4 (2 displays away)"),
    ])
    func theDormantDesksLineHasExplicitBranches(desks: Int, away: Int, expected: String) {
        #expect(OverviewCopy.dormantDesksLine(desks: desks, awayDisplays: away) == expected)
    }

    // MARK: Overlay (06 UI-SPEC Copywriting Contract)

    @Test func desktopLabelsAreNumbered() {
        #expect(OverviewCopy.desktopLabel(1) == "Desktop 1")
        #expect(OverviewCopy.desktopLabel(12) == "Desktop 12")
    }

    @Test func fullScreenLabelsNameTheAppOrBothApps() {
        #expect(OverviewCopy.fullScreenLabel(["Safari"]) == "Safari")
        #expect(OverviewCopy.fullScreenLabel(["Safari", "Notes"]) == "Safari and Notes")
        let long = String(repeating: "x", count: 40)
        #expect(OverviewCopy.fullScreenLabel([long]) == String(repeating: "x", count: 32) + "\u{2026}")
    }

    @Test func theEmptyCapsuleCopy() {
        #expect(OverviewCopy.noWindows == "No windows on this desktop")
        #expect(OverviewCopy.refusedFullScreen == "The overview isn't available in full screen")
    }

    @Test func aFailedSpaceSwitchNamesTheDesktopOrTheApp() {
        #expect(OverviewCopy.couldNotSwitch(desktop: 2) == "Couldn't switch to Desktop 2")
        #expect(OverviewCopy.couldNotSwitch(app: "Safari") == "Couldn't switch to Safari")
    }

    @Test func aSelectedWindowShowsItsTitleElseItsAppName() {
        #expect(OverviewCopy.titleOrApp(title: "Notes.txt", app: "TextEdit") == "Notes.txt")
        #expect(OverviewCopy.titleOrApp(title: "", app: "TextEdit") == "TextEdit")
    }

    // MARK: Availability and interruptions (Surface 1, Logging)

    @Test func refusalsMatchTheContract() {
        #expect(OverviewCopy.refusedFullScreen == "The overview isn't available in full screen")
        #expect(OverviewCopy.refusedNotReady == "Transom needs Accessibility access")
    }

    @Test(arguments: [
        (OverviewCopy.Interruption.command, "interrupted: command"), (.menu, "interrupted: menu"), (.spaceChange, "interrupted: space change"),
        (.displayChange, "interrupted: display change"), (.sleep, "interrupted: sleep"), (.appSwitch, "interrupted: app switch"),
    ])
    func interruptionsAreLoggedByReason(reason: OverviewCopy.Interruption, expected: String) {
        #expect(OverviewCopy.interruptedLog(reason) == expected)
    }

    // MARK: Announcements (Accessibility) and S6

    @Test(arguments: [
        (0, 1, "Overview, no windows"), (1, 1, "Overview, 1 window"), (5, 1, "Overview, 5 windows"), (5, 2, "Overview, 5 windows on 2 displays"),
        (1, 2, "Overview, 1 window on 2 displays"),
    ])
    func theOpenedAnnouncementCountsWindowsAndDisplays(windows: Int, displays: Int, expected: String) {
        #expect(OverviewCopy.openedAnnouncement(windows: windows, displays: displays) == expected)
    }

    @Test func selectionAnnouncementsMatchTheContract() {
        #expect(OverviewCopy.tileAnnouncement(app: "Safari", title: "Docs") == "\u{201C}Safari\u{201D}, Docs")
        #expect(OverviewCopy.tileAnnouncement(app: "Safari", title: "") == "\u{201C}Safari\u{201D}")
        #expect(OverviewCopy.miniTileAnnouncement(app: "Notes", title: "", desktop: 2) == "\u{201C}Notes\u{201D}, Desktop 2")
        #expect(OverviewCopy.miniTileAnnouncement(app: "Notes", title: "List", desktop: 2) == "\u{201C}Notes\u{201D}, List, Desktop 2")
        #expect(OverviewCopy.thumbnailAnnouncement(desktop: 2, current: true, windows: 3) == "Desktop 2, current")
        #expect(OverviewCopy.thumbnailAnnouncement(desktop: 3, current: false, windows: 0) == "Desktop 3, no windows")
        #expect(OverviewCopy.thumbnailAnnouncement(desktop: 3, current: false, windows: 1) == "Desktop 3, 1 window")
        #expect(OverviewCopy.thumbnailAnnouncement(desktop: 3, current: false, windows: 4) == "Desktop 3, 4 windows")
        #expect(OverviewCopy.thumbnailAnnouncement(fullScreenApp: "Safari") == "\u{201C}Safari\u{201D}, full screen")
        #expect(OverviewCopy.displayPrefix("DELL", "Desktop 1, current") == "\u{201C}DELL\u{201D}: Desktop 1, current")
        #expect(OverviewCopy.closedAnnouncement == "Overview closed")
    }

    @Test func theLastOverviewLineHasExplicitBranches() {
        #expect(OverviewCopy.lastOverviewLine(nil) == "Last overview: none yet")
        #expect(OverviewCopy.lastOverviewLine((ms: 180, windows: 1, snapshots: 1)) == "Last overview: 180 ms to open, 1 window, 1 snapshot")
        #expect(OverviewCopy.lastOverviewLine((ms: 212, windows: 7, snapshots: 5)) == "Last overview: 212 ms to open, 7 windows, 5 snapshots")
        #expect(OverviewCopy.lastOverviewLine((ms: 90, windows: 0, snapshots: 0)) == "Last overview: 90 ms to open, 0 windows, 0 snapshots")
    }

    @Test(arguments: [
        (OverviewCopy.TakeoverLine.off, "Mission Control takeover: off"),
        (.on(.standard), "Mission Control takeover: on, F3 and \u{2303}\u{2191}"),
        (.on(.custom("\u{2325}\u{2318}\u{2191}")), "Mission Control takeover: on, F3 and \u{2325}\u{2318}\u{2191}"),
        (.on(.off), "Mission Control takeover: on, F3"),
        (.liftedForZoom, "Mission Control takeover: lifted while zoom is off"),
        (.offAfterCrash, "Mission Control takeover: off after a crash last launch"),
        (.offApplyFailed, "Mission Control takeover: off, couldn't apply"),
        (.unavailable, "Mission Control takeover: unavailable (private API off)"),
    ])
    func theTakeoverLineMatchesS5(line: OverviewCopy.TakeoverLine, expected: String) {
        #expect(OverviewCopy.takeoverLine(line) == expected)
    }

    /// Surface 5: the alert's {Keys} branches and the [swipe kept] informative text (06-SPIKE verdict).
    @Test func theTakeoverAlertFollowsSurface5() {
        #expect(OverviewCopy.takeoverAlertMessage == "Use the Mission Control keys for Transom's overview?")
        #expect(OverviewCopy.takeoverAlertKeys(.standard) == "The Mission Control key (F3) and Control-Up Arrow")
        #expect(OverviewCopy.takeoverAlertKeys(.custom("\u{2325}\u{2318}\u{2191}")) == "The Mission Control key (F3) and \u{2325}\u{2318}\u{2191}")
        #expect(OverviewCopy.takeoverAlertKeys(.off) == "The Mission Control key (F3)")
        #expect(
            OverviewCopy.takeoverAlertInformative(.off)
                == "The Mission Control key (F3) will show Transom's overview instead of Mission Control. Swiping up with four fingers still opens Mission Control. Transom gives Mission Control its keys back when you turn this off or quit, and the next time it opens if it quits unexpectedly.")
    }
}
