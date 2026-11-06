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
        #expect(MenuCopy.spacesItem(available: false) == "Spaces lookup: off, using Spaces visited since launch")
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

    @Test func theClearItemHasItsTitle() {
        #expect(MenuCopy.clearWaitingTiles == "Clear Waiting Tiles")
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
        #expect(MenuCopy.commandTitle(.dockFourth(.first, .horizontal)) == "1st Column")
        #expect(MenuCopy.commandTitle(.dockFourth(.middle, .vertical)) == "Middle Half Row")
        #expect(MenuCopy.commandTitle(.dock) == "Where It Is")
        #expect(MenuCopy.fourthMenu == "Dock Window")
        #expect([MenuCopy.halvesHeader, MenuCopy.thirdsHeader, MenuCopy.fourthsHeader] == ["Halves", "Thirds", "Fourths"])
        let halvesAndThirds: [(FourthSlot, Axis)] = [
            (.firstHalf, .horizontal), (.secondHalf, .horizontal), (.firstHalf, .vertical), (.secondHalf, .vertical),
            (.firstThird, .horizontal), (.middleThird, .horizontal), (.lastThird, .horizontal),
            (.firstThird, .vertical), (.middleThird, .vertical), (.lastThird, .vertical),
        ]
        #expect(halvesAndThirds.map { MenuCopy.fourthTitle($0, $1) } == [
            "Left Half", "Right Half", "Top Half", "Bottom Half", "Left Third", "Center Third", "Right Third", "Top Third",
            "Middle Third", "Bottom Third",
        ])
        #expect(MenuCopy.commandTitle(.camera(.zoomOutAll)) == "Zoom Out to All Windows")
        #expect(MenuCopy.commandTitle(.camera(.view(ViewSlot(1)!))) == "Go to View 1")
        #expect(MenuCopy.commandTitle(.camera(.saveView(ViewSlot(9)!))) == "Save View 9")
        #expect(MenuCopy.commandTitle(.camera(.stepOut)) == "Zoom Out One Level")
        #expect(MenuCopy.commandTitle(.camera(.stepIn)) == "Zoom In One Level")
        #expect(MenuCopy.commandTitle(.camera(.back)) == "Back")
        #expect(MenuCopy.commandTitle(.camera(.forward)) == "Forward")
        #expect(Edge.allCases.map { MenuCopy.commandTitle(.camera(.pan($0))) } == ["Left", "Right", "Up", "Down"])
        #expect(MenuCopy.commandTitle(.camera(.frameWindow)) == "Frame Focused Window")
    }

    @Test func exclusionCopyQuotesTheAppName() {
        #expect(MenuCopy.dontArrange(appName: "Safari") == "Don't Arrange \u{201C}Safari\u{201D}")
        #expect(MenuCopy.dontArrangeFallback == "Don't Arrange Frontmost App")
        #expect(MenuCopy.noExclusions == "No apps excluded")
    }

    @Test func dragToDockCopyFollowsTheUISpec() {
        #expect(MenuCopy.dragToDockTitle(.automatic) == "Drag to Dock: Automatically")
        #expect(MenuCopy.dragToDockTitle(.holdOption) == "Drag to Dock: Hold ⌥")
        #expect(MenuCopy.dragToDockChoice(.automatic) == "Automatically")
        #expect(MenuCopy.dragToDockChoice(.holdOption) == "Hold ⌥")
        #expect(MenuCopy.dragToDockTooltip(.automatic) == "Docking regions show on every drag.")
        #expect(MenuCopy.dragToDockTooltip(.holdOption) == "A drag moves the window and leaves it floating. Hold ⌥ to show docking regions.")
        #expect(MenuCopy.dragToDockAnnouncement(.automatic) == "Docking regions show on every drag")
        #expect(MenuCopy.dragToDockAnnouncement(.holdOption) == "Hold Option while dragging to dock")
    }

    @Test func newWindowsCopyFollowsTheUISpec() {
        #expect(MenuCopy.newWindowsTitle(.float) == "New Windows: Float")
        #expect(MenuCopy.newWindowsTitle(.tile) == "New Windows: Tile")
        #expect(MenuCopy.newWindowsChoice(.float) == "Float")
        #expect(MenuCopy.newWindowsChoice(.tile) == "Tile")
        #expect(MenuCopy.newWindowsTooltip(.float) == "New windows float until you dock them.")
        #expect(MenuCopy.newWindowsTooltip(.tile) == "New windows dock beside the focused tile. Dialogs, panels and excluded apps still float.")
        #expect(MenuCopy.newWindowsAnnouncement(.float) == "New windows float")
        #expect(MenuCopy.newWindowsAnnouncement(.tile) == "New windows tile")
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
