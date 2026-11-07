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

    /// "Overview, 5 windows" · "Overview, 1 window" · "Overview, no windows", plus " on {d} displays" with several.
    public static func openedAnnouncement(windows: Int, displays: Int) -> String {
        let count = windows == 0 ? "no windows" : windows == 1 ? "1 window" : "\(windows) windows"
        return "Overview, \(count)" + (displays > 1 ? " on \(displays) displays" : "")
    }

    /// A main-area tile: "“{App}”, {title}", the title left out when empty.
    public static func tileAnnouncement(app: String, title: String) -> String {
        "\u{201C}\(app)\u{201D}" + (title.isEmpty ? "" : ", \(title)")
    }

    /// A mini tile: "“{App}”, {title}, Desktop {n}".
    public static func miniTileAnnouncement(app: String, title: String, desktop: Int) -> String {
        tileAnnouncement(app: app, title: title) + ", " + desktopLabel(desktop)
    }

    /// A desktop thumbnail: "Desktop {n}, current", else its window count.
    public static func thumbnailAnnouncement(desktop: Int, current: Bool, windows: Int) -> String {
        let detail = current ? "current" : windows == 0 ? "no windows" : windows == 1 ? "1 window" : "\(windows) windows"
        return "\(desktopLabel(desktop)), \(detail)"
    }

    /// A full-screen Space's thumbnail: "“{App}”, full screen".
    public static func thumbnailAnnouncement(fullScreenApp app: String) -> String { "\u{201C}\(app)\u{201D}, full screen" }

    /// Selection moved to another display: "“{Display}”: " then the item.
    public static func displayPrefix(_ display: String, _ item: String) -> String { "\u{201C}\(display)\u{201D}: \(item)" }

    public static let closedAnnouncement = "Overview closed"

    // MARK: Replace Mission Control (Surface 5). Swipe verdict "kept" (06-SPIKE): only the [swipe kept] variant ships.

    public static let replaceMissionControl = "Replace Mission Control"
    public static let takeoverAlertMessage = "Use the Mission Control keys for Transom's overview?"
    public static let takeoverNotNow = "Not Now"

    /// What macOS has for Mission Control (hotkey 32): its default ⌃↑, the user's chord in glyphs, or turned off.
    public enum Chord: Equatable, Sendable {
        case standard, custom(String), off
    }

    /// The alert's {Keys}.
    public static func takeoverAlertKeys(_ chord: Chord) -> String {
        switch chord {
        case .standard: "The Mission Control key (F3) and Control-Up Arrow"
        case .custom(let glyphs): "The Mission Control key (F3) and \(glyphs)"
        case .off: "The Mission Control key (F3)"
        }
    }

    public static func takeoverAlertInformative(_ chord: Chord) -> String {
        "\(takeoverAlertKeys(chord)) will show Transom's overview instead of Mission Control. Swiping up with four fingers still opens Mission Control. Transom gives Mission Control its keys back when you turn this off or quit, and the next time it opens if it quits unexpectedly."
    }

    public static let takeoverOnAnnouncement = "Mission Control keys show the overview"
    public static let takeoverOffAnnouncement = "Mission Control keys restored"

    // MARK: S5 Mission Control takeover

    public enum TakeoverLine: Equatable, Sendable {
        /// `on` carries hotkey 32's chord, `.off` when only F3 is taken.
        case off, on(Chord), liftedForZoom, offAfterCrash, offApplyFailed, unavailable
    }

    public static func takeoverLine(_ line: TakeoverLine) -> String {
        let value =
            switch line {
            case .off: "off"
            case .on(.standard): "on, F3 and \u{2303}\u{2191}"
            case .on(.custom(let glyphs)): "on, F3 and \(glyphs)"
            case .on(.off): "on, F3"
            case .liftedForZoom: "lifted while zoom is off"
            case .offAfterCrash: "off after a crash last launch"
            case .offApplyFailed: "off, couldn't apply"
            case .unavailable: "unavailable (private API off)"
            }
        return "Mission Control takeover: \(value)"
    }

    // MARK: S6 Last overview

    /// "Last overview: none yet" · "Last overview: {ms} ms to open, {n} windows, {s} snapshots" (1 window / 1 snapshot).
    public static func lastOverviewLine(_ last: (ms: Int, windows: Int, snapshots: Int)?) -> String {
        guard let last else { return "Last overview: none yet" }
        let windows = last.windows == 1 ? "1 window" : "\(last.windows) windows"
        let snapshots = last.snapshots == 1 ? "1 snapshot" : "\(last.snapshots) snapshots"
        return "Last overview: \(last.ms) ms to open, \(windows), \(snapshots)"
    }

    /// The main area of a current Space with no shown windows.
    public static let noWindows = "No windows on this desktop"
}
