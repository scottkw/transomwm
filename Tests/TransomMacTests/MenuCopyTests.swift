import TransomEngine
import TransomMac
import TransomModel
import Testing

@Suite struct MenuCopyTests {
    @Test(arguments: [
        (0, 0, "No windows to track"),
        (1, 1, "Tracking 1 window in 1 app"),
        (2, 1, "Tracking 2 windows in 1 app"),
        (12, 5, "Tracking 12 windows in 5 apps"),
    ])
    func headerIsPluralCorrect(windows: Int, apps: Int, expected: String) {
        #expect(MenuCopy.header(windows: windows, apps: apps) == expected)
    }

    @Test func degradedLineIsAbsentAtZeroAndPluralCorrect() {
        #expect(MenuCopy.degradedLine(count: 0) == nil)
        #expect(MenuCopy.degradedLine(count: 1) == "1 app not responding")
        #expect(MenuCopy.degradedLine(count: 3) == "3 apps not responding")
    }

    @Test func capabilityItemNamesTheWindowIDLookupState() {
        #expect(MenuCopy.capabilityItem(windowIDLookupAvailable: true) == "Window ID lookup: available")
        #expect(MenuCopy.capabilityItem(windowIDLookupAvailable: false) == "Window ID lookup: off, matching by frame")
    }

    @Test func spacesItemNamesTheSpacesLookupState() {
        #expect(MenuCopy.spacesItem(available: true) == "Spaces lookup: available")
        #expect(MenuCopy.spacesItem(available: false) == "Spaces lookup: off, single Space")
    }

    @Test func appNamesUpToTheLimitAreUnchanged() {
        let name = String(repeating: "a", count: MenuCopy.maxAppNameLength)
        #expect(MenuCopy.maxAppNameLength == 32)
        #expect(MenuCopy.truncatedAppName(name) == name)
        #expect(MenuCopy.truncatedAppName("") == "")
    }

    @Test func longAppNamesAreCutToTheLimitPlusAnEllipsis() {
        let name = String(repeating: "b", count: 32) + "c"
        #expect(MenuCopy.truncatedAppName(name) == String(repeating: "b", count: 32) + "\u{2026}")
    }

    @Test func truncationCountsGraphemesNotScalars() {
        // Each family emoji is one grapheme made of several scalars.
        let family = "👨‍👩‍👧‍👦"
        let name = String(repeating: family, count: 33)
        let cut = MenuCopy.truncatedAppName(name)
        #expect(cut == String(repeating: family, count: 32) + "\u{2026}")
        #expect(cut.count == 33)
    }

    @Test(arguments: [
        (PermissionPhase.notTrusted, "Accessibility access needed"),
        (.waitingForGrant, "Accessibility access needed"),
        (.probing, "Checking Accessibility access\u{2026}"),
        (.staleTrustedButFailing, "Accessibility access isn't working"),
    ])
    func permissionHeaderNamesTheState(phase: PermissionPhase, expected: String) {
        #expect(MenuCopy.permissionHeader(phase) == expected)
    }

    @Test func permissionHeaderIsAbsentWhenReady() {
        #expect(MenuCopy.permissionHeader(.ready) == nil)
    }

    @Test func permissionItemSaysFixWhenStale() {
        #expect(MenuCopy.permissionItem(stale: false) == "Grant Accessibility Access\u{2026}")
        #expect(MenuCopy.permissionItem(stale: true) == "Fix Accessibility Access\u{2026}")
    }

    @Test func resetFailedBodyNamesTheCodeAndTheApp() {
        let body = MenuCopy.resetFailedBody(code: 64, appName: "Transom Debug")
        #expect(body.contains("tccutil stopped with code 64"))
        #expect(body.contains("\u{201C}Transom Debug\u{201D}"))
    }

    @Test func sectionTitlesNameTheThreeGroups() {
        #expect(MenuCopy.arrangeSection == "Arrange")
        #expect(MenuCopy.safetySection == "Safety")
        #expect(MenuCopy.exclusionsSection == "Exclusions")
    }

    /// 02-UI-REVIEW fix 1: no count before the first sweep, and closed windows are never counted.
    @Test func headerWaitsForTheFirstSweepAndSkipsClosedWindows() {
        let ref = { (id: UInt32, pid: Int32) in WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: "com.example.\(pid)")) }
        let frame = Rect(x: 0, y: 0, width: 100, height: 100)
        let windows = [
            WindowInfo(window: ref(1, 1), frame: frame, state: .present, displayUUID: "main", kind: .dockable),
            WindowInfo(window: ref(2, 1), frame: frame, state: .absent, displayUUID: "main", kind: .dockable),
            WindowInfo(window: ref(3, 2), frame: frame, state: .closed, displayUUID: "main", kind: .dockable),
        ]
        #expect(MenuCopy.header(WindowInventory(displays: [], windows: windows)) == "Looking for windows\u{2026}")
        #expect(MenuCopy.header(WindowInventory(displays: [], windows: windows, initialRefreshComplete: true)) == "Tracking 2 windows in 1 app")
    }

    @Test func thePauseLineNamesTheHighestPriorityReason() {
        #expect(MenuCopy.pauseLine([]) == nil)
        #expect(MenuCopy.pauseLine([.user]) == "Arranging paused")
        #expect(MenuCopy.pauseLine([.user, .crashLoop]) == "Arranging paused after Transom quit unexpectedly")
        #expect(MenuCopy.pauseLine([.user, .crashLoop, .stageManager]) == "Arranging paused: Stage Manager is on")
    }

    @Test func pauseAndGapTitles() {
        #expect(MenuCopy.pauseToggle(paused: false) == "Pause Arranging")
        #expect(MenuCopy.pauseToggle(paused: true) == "Resume Arranging")
        #expect(MenuCopy.gapsMenu == "Gaps")
        #expect([0.0, 4, 8, 12, 16, 24].map(MenuCopy.gapTitle) == ["None", "4 pt", "8 pt", "12 pt", "16 pt", "24 pt"])
        #expect(MenuCopy.pausedGlyphDescription == "Transom: arranging paused")
    }

    @Test func zoomItemTitles() {
        #expect(MenuCopy.commandTitle(.camera(.zoomOutAll)) == "Zoom Out to All Windows")
        #expect(MenuCopy.commandTitle(.camera(.stepOut)) == "Zoom Out One Level")
        #expect(MenuCopy.commandTitle(.camera(.stepIn)) == "Zoom In One Level")
    }

    @Test func exclusionCopyQuotesTheAppName() {
        #expect(MenuCopy.dontArrange(appName: "Safari") == "Don't Arrange \u{201C}Safari\u{201D}")
        #expect(MenuCopy.dontArrangeFallback == "Don't Arrange Frontmost App")
        #expect(MenuCopy.noExclusions == "No apps excluded")
    }
}

@Suite struct NudgeMenuCopyTests {
    @Test func nudgeItemAndItsDisabledTitles() {
        #expect(MenuCopy.nudgeItem == "Nudge Focused Window")
        #expect(MenuCopy.nudgeExcluded == "Nudge Focused Window (app excluded)")
        #expect(MenuCopy.nudgeNoWindow == "Nudge Focused Window (no window)")
    }

    @Test func theDebugTapLineNamesTheTapState() {
        #expect(MenuCopy.tapRunning == "Event tap: running")
        #expect(MenuCopy.tapOff == "Event tap: off, drags not detected")
        #expect(MenuCopy.tapItem(running: true) == MenuCopy.tapRunning)
        #expect(MenuCopy.tapItem(running: false) == MenuCopy.tapOff)
    }
}
