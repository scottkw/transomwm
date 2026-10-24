import PaneEngine
import PaneMac
import PaneModel
import Testing

@Suite struct TrackedWindowsModelTests {
    static func info(
        _ windowID: UInt32, pid: Int32 = 10, bundleID: String = "com.example.app", title: String = "Doc",
        kind: WindowKind = .dockable, state: WindowState = .present, idSource: WindowIDSource = .axPrivate,
        displayUUID: String? = "D1", tabCount: Int = 1, isExcluded: Bool = false, learnedMinimum: Size? = nil
    ) -> WindowInfo {
        WindowInfo(
            window: WindowRef(identity: WindowIdentity(windowID: windowID, pid: pid, bundleID: bundleID), titleHint: title),
            frame: Rect(x: 0, y: 0, width: 100, height: 100), state: state, displayUUID: displayUUID, kind: kind,
            idSource: idSource, tabCount: tabCount, isExcluded: isExcluded, learnedMinimum: learnedMinimum
        )
    }

    static func rows(_ windows: [WindowInfo], names: [Int32: String] = [10: "App"], degraded: Set<Int32> = [], exclusions: Set<String> = []) -> [TrackedWindowRow] {
        TrackedWindowsModel.rows(
            WindowInventory(displays: [], windows: windows, degradedPIDs: degraded, initialRefreshComplete: true),
            exclusions: exclusions, appNames: names, displayNames: ["D1": "Built-in Display"]
        )
    }

    @Test func rowsSortByAppNameIgnoringCaseAndDiacriticsThenWindowID() {
        let windows = [
            Self.info(5, pid: 3), Self.info(2, pid: 1), Self.info(9, pid: 2), Self.info(1, pid: 3),
        ]
        let names: [Int32: String] = [1: "safari", 2: "Finder", 3: "éclair"]
        let rows = Self.rows(windows, names: names)
        #expect(rows.map(\.appName) == ["éclair", "éclair", "Finder", "safari"])
        #expect(rows.map(\.id.windowID) == [1, 5, 9, 2])
        #expect(Self.rows(windows.reversed(), names: names) == rows)
    }

    @Test func closedWindowsAreNotRows() {
        #expect(Self.rows([Self.info(1, state: .closed), Self.info(2)]).map(\.id.windowID) == [2])
    }

    @Test(arguments: [
        (WindowKind.dockable, "Dockable"),
        (.neverDock(.floatingLevel), "Never dock · Floating"),
        (.neverDock(.subrole), "Never dock · Dialog or panel"),
        (.neverDock(.modal), "Never dock · Modal"),
        (.neverDock(.noCloseButton), "Never dock · No close button"),
        (.neverDock(.noFullscreenButton), "Never dock · No full-screen button"),
    ])
    func kindTextUsesTheReasonVocabulary(kind: WindowKind, expected: String) {
        #expect(TrackedWindowsModel.kindText(kind) == expected)
    }

    @Test func frameTextRoundsToNearestIntegers() {
        #expect(TrackedWindowsModel.frameText(Rect(x: 10.4, y: 20.6, width: 300, height: 200.5)) == "10, 21  300 × 201")
        #expect(TrackedWindowsModel.frameText(Rect(x: -0.5, y: 0, width: 1, height: 1)) == "-1, 0  1 × 1")
    }

    @Test func partialRowsUsePlaceholders() throws {
        let row = try #require(
            Self.rows([Self.info(1, title: "", idSource: .synthetic, displayUUID: nil)]).first
        )
        #expect(row.title == "Untitled")
        #expect(row.isPlaceholderTitle)
        #expect(row.idText == "by frame")
        #expect(row.isSyntheticID)
        #expect(row.tabsText == "")
        #expect(row.displayText == "—")
        #expect(row.minSizeText == "")
    }

    @Test func populatedRowsShowEveryField() throws {
        let row = try #require(
            Self.rows([
                Self.info(42, title: "Report", state: .fullscreen, tabCount: 3, learnedMinimum: Size(width: 400.4, height: 300.6))
            ]).first
        )
        #expect(row.appName == "App")
        #expect(row.title == "Report")
        #expect(!row.isPlaceholderTitle)
        #expect(row.idText == "42")
        #expect(row.kindText == "Dockable")
        #expect(row.stateText == "Fullscreen")
        #expect(row.tabsText == "3 tabs")
        #expect(row.frameText == "0, 0  100 × 100")
        #expect(row.displayText == "Built-in Display")
        #expect(row.minSizeText == "400 × 301")
        #expect(!row.isExcluded)
        #expect(!row.isNotResponding)
    }

    @Test func unknownDisplayShowsADash() throws {
        let row = try #require(Self.rows([Self.info(1, displayUUID: "gone")]).first)
        #expect(row.displayText == "—")
    }

    @Test func badgesComeFromExclusionsAndDegradedApps() {
        let rows = Self.rows(
            [Self.info(1), Self.info(2, pid: 11, bundleID: "com.apple.Safari"), Self.info(3, pid: 12, isExcluded: true)],
            names: [10: "A", 11: "B", 12: "C"], degraded: [10], exclusions: ["com.apple.safari"]
        )
        #expect(rows.map(\.isNotResponding) == [true, false, false])
        #expect(rows.map(\.isExcluded) == [false, true, true])
    }

    @Test func aMissingAppNameFallsBackToTheBundleID() {
        #expect(Self.rows([Self.info(1, pid: 99)], names: [:]).first?.appName == "com.example.app")
    }

    @Test func footerForOneWindowInOneApp() {
        let inventory = WindowInventory(displays: [], windows: [Self.info(1)], initialRefreshComplete: true)
        let rows = TrackedWindowsModel.rows(inventory, exclusions: [], appNames: [:], displayNames: [:])
        #expect(TrackedWindowsModel.footer(inventory, rows: rows) == "1 window · 1 app")
    }

    @Test func footerCountsEverySegment() {
        var windows: [WindowInfo] = []
        for app in Int32(1)...6 {
            for n in 0..<(app == 1 ? 9 : 1) { windows.append(Self.info(UInt32(app) * 100 + UInt32(n), pid: app)) }
        }
        windows[0].kind = .neverDock(.modal)
        windows[1].kind = .neverDock(.subrole)
        windows[2].kind = .neverDock(.floatingLevel)
        windows[3].isExcluded = true
        let inventory = WindowInventory(displays: [], windows: windows, degradedPIDs: [6], initialRefreshComplete: true)
        let rows = TrackedWindowsModel.rows(inventory, exclusions: [], appNames: [:], displayNames: [:])
        #expect(windows.count == 14)
        #expect(TrackedWindowsModel.footer(inventory, rows: rows) == "14 windows · 6 apps · 3 never dock · 1 excluded · 1 not responding")

        var paused = inventory
        paused.sessionPaused = true
        #expect(TrackedWindowsModel.footer(paused, rows: rows).hasPrefix("Refreshing after wake · 14 windows"))
    }

    @Test func stateFollowsPermissionAndTheFirstRefresh() {
        let none = WindowInventory(displays: [], windows: [])
        var done = none
        done.initialRefreshComplete = true
        let some = WindowInventory(displays: [], windows: [Self.info(1)])
        #expect(TrackedWindowsModel.state(permissionReady: false, stale: true, inventory: some) == .noPermission(stale: true))
        #expect(TrackedWindowsModel.state(permissionReady: false, stale: false, inventory: none) == .noPermission(stale: false))
        #expect(TrackedWindowsModel.state(permissionReady: true, stale: false, inventory: none) == .loading)
        #expect(TrackedWindowsModel.state(permissionReady: true, stale: false, inventory: done) == .empty)
        #expect(TrackedWindowsModel.state(permissionReady: true, stale: false, inventory: some) == .populated)
    }
}
