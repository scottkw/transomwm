/// Phase 6 copy from the UI-SPEC (Surface 7, Copywriting Contract). Pure strings, no AppKit types.
nonisolated public enum OverviewCopy {
    // MARK: Selection (Surface 3)

    /// The selected window's title capsule and a selected mini tile's label: the AX title, else the app name.
    public static func titleOrApp(title: String, app: String) -> String { title.isEmpty ? app : title }

    // MARK: S1 Spaces

    public enum SpacesLine: Equatable, Sendable {
        /// From the Spaces lookup; `shared` when "Displays have separate Spaces" is off.
        case counts(spaces: Int, displays: Int, shared: Bool)
        /// Lookup off: Spaces visited since launch (co-visibility, D-15).
        case visited(Int)
    }

    /// "Spaces: 3 on 1 display" · "Spaces: 5 across 2 displays" · "Spaces: 4, shared by 2 displays" ·
    /// "Spaces: 2 visited since launch".
    public static func spacesLine(_ line: SpacesLine) -> String {
        switch line {
        case .counts(let spaces, 1, _): "Spaces: \(spaces) on 1 display"
        case .counts(let spaces, let displays, false): "Spaces: \(spaces) across \(displays) displays"
        case .counts(let spaces, let displays, true): "Spaces: \(spaces), shared by \(displays) displays"
        case .visited(let visited): "Spaces: \(visited) visited since launch"
        }
    }

    // MARK: S2-S4 Displays

    public enum DisplaysLine: Equatable, Sendable {
        /// `arrangement` is `ArrangementID.shortHash`, the value the `displays` log lines print.
        case settled(displays: Int, arrangement: String)
        /// Within the 1.5 s debounce (D-11).
        case settling
        /// SessionGate holds a change until wake or unlock.
        case waitingForWake
    }

    public static func displaysLine(_ line: DisplaysLine) -> String {
        switch line {
        case .settled(let displays, let arrangement): "Displays: \(displays), arrangement \(arrangement)"
        case .settling: "Displays: settling\u{2026}"
        case .waitingForWake: "Displays: waiting for wake"
        }
    }

    public static func savedArrangementsLine(_ count: Int) -> String {
        count == 0 ? "Saved arrangements: none yet" : "Saved arrangements: \(count)"
    }

    public static func dormantDesksLine(desks: Int, awayDisplays: Int) -> String {
        if desks == 0 { "Dormant desks: none" } else if awayDisplays == 1 { "Dormant desks: \(desks) (1 display away)" } else {
            "Dormant desks: \(desks) (\(awayDisplays) displays away)"
        }
    }

    // MARK: Overlay

    /// A desktop Space's label, numbered in strip order per display.
    public static func desktopLabel(_ index: Int) -> String { "Desktop \(index)" }

    /// A full-screen Space's label: its app, or both apps of a split full-screen Space; names truncated (32 + "…").
    public static func fullScreenLabel(_ apps: [String]) -> String {
        apps.prefix(2).map(MenuCopy.truncatedAppName).joined(separator: " and ")
    }

    /// The Shortcuts window's Zoom-section footer (Surface 4).
    public static let shortcutsZoomFooter = "With Replace Mission Control on, the Mission Control keys also show the overview."

    /// Show Overview refused: every display is in full screen.
    public static let refusedFullScreen = "The overview isn't available in full screen"
    /// Show Overview refused: Accessibility is not ready (the Phase 4 text).
    public static let refusedNotReady = "Transom needs Accessibility access"

    /// What closed the overview at once, with no reverse animation (Surface 1 Motion "Interrupted").
    public enum Interruption: String, Sendable {
        case command, menu, spaceChange = "space change", displayChange = "display change", sleep, appSwitch = "app switch"
    }

    /// The overview log line for an interruption.
    public static func interruptedLog(_ reason: Interruption) -> String { "interrupted: \(reason.rawValue)" }

    /// A pick's Space switch did not land within 1 s (Surface 2): the desktop's number, or a full-screen Space's app.
    public static func couldNotSwitch(desktop index: Int) -> String { "Couldn't switch to \(desktopLabel(index))" }
    public static func couldNotSwitch(app: String) -> String { "Couldn't switch to \(app)" }

    // MARK: Announcements (Accessibility)

    public static func openedAnnouncement(windows: Int, displays: Int) -> String { "" }
    public static func tileAnnouncement(app: String, title: String) -> String { "" }
    public static func miniTileAnnouncement(app: String, title: String, desktop: Int) -> String { "" }
    public static func thumbnailAnnouncement(desktop: Int, current: Bool, windows: Int) -> String { "" }
    public static func thumbnailAnnouncement(fullScreenApp app: String) -> String { "" }
    public static func displayPrefix(_ display: String, _ item: String) -> String { "" }
    public static let closedAnnouncement = ""

    // MARK: S6 Last overview

    public static func lastOverviewLine(_ last: (ms: Int, windows: Int, snapshots: Int)?) -> String { "" }

    /// The main area of a current Space with no shown windows.
    public static let noWindows = "No windows on this desktop"
}
