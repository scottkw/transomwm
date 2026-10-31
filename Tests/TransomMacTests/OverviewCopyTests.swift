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
    }
}
