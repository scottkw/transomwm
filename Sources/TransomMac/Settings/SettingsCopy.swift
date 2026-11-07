import TransomEngine

/// Settings window copy (09 UI-SPEC Surface 1). The UI-SPEC lists "Settings…" under MenuCopy; it lives here so the
/// Settings window owns one copy type.
nonisolated public enum SettingsCopy {
    public static let menuItem = "Settings\u{2026}"

    // General (Tab 1)
    public static let appearanceSection = "Appearance"
    public static let highlightColor = "Highlight color"
    public static let matchSystemAccent = "Match system accent color"
    public static let customHighlight = "Custom"
    /// The colour well's accessibility label; the radio row shows no text beside it.
    public static let customHighlightWell = "Custom highlight color"
    public static let highlightFooter = "Used for docking previews, rings and gap handles."

    // Arranging (Tab 2)
    public static let layoutSection = "Layout"
    public static let gaps = "Gaps"
    public static let newWindows = "New windows"
    public static let dragToDock = "Drag to dock"
    public static let tabGroupsSection = "Tab groups"
    public static let confirmCloseGroup = "Ask before Close Group closes every window"
    public static let confirmCloseGroupFooter = "Turn this back on if you chose not to be asked."
    public static let featuresSection = "macOS window features"
    public static let featureOn = "On"
    public static let featureOff = "Off"
    public static let restoreFooter = "Puts back the settings Transom turned off."

    // Zoom & Gestures (Tab 3)
    public static let zoomSection = "Zoom"
    public static let useZoom = "Use zoom"
    public static let useZoomFooter = "Zoom lets you see every window at once and step in to any of them. Tiling works with zoom off."
    public static let trackpadSection = "Trackpad"
    public static let gestureOption = "Pinch and pan with \u{2325} held"
    public static let gestureOptionFooter = "Hold \u{2325} and pinch to zoom, or move two fingers to pan, over any window."
    public static let gestureWallpaper = "Pinch and pan on the wallpaper without \u{2325}"
    public static let missionControlSection = "Mission Control"
    public static let useMissionControlKeys = "Use the Mission Control keys for the overview"
    public static let takeoverUnavailable = "Not available on this version of macOS."

    // Exclusions (Tab 5)
    public static let addApp = "Add App"
    public static let removeApp = "Remove App"
    public static let addAppMessage = "Choose an app whose windows Transom should never arrange"
    public static let addAppPrompt = "Exclude"
    public static let cantExcludeSelf = "Transom can't exclude itself."
    /// {app} is the chosen file's display name, truncated like the rows.
    public static func noBundleID(_ app: String) -> String { "\(app) has no bundle ID, so it can't be excluded." }
    public static let exclusionsFooter =
        "Transom never moves or docks these apps' windows. You can also choose Don't Arrange in the Transom menu while the app is in front."

    /// {keys} is `OverviewCopy.takeoverAlertKeys`, the user's real chord.
    public static func takeoverFooter(_ keys: String) -> String {
        "\(keys) show Transom's overview instead of Mission Control. Swiping up with four fingers still opens Mission Control."
    }

    /// Sentence case, as the UI-SPEC writes the rows (the menu and toasts keep `ConflictCopy.featureName`).
    public static func featureName(_ conflict: Conflict) -> String {
        switch conflict {
        case .stageManager: "Stage Manager"
        case .edgeTiling: "macOS edge tiling"
        case .clickWallpaper: "Click wallpaper to reveal desktop"
        }
    }

    public static func tabLabel(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General"
        case .arranging: "Arranging"
        case .zoom: "Zoom & Gestures"
        case .shortcuts: ZoomCopy.shortcutsWindowTitle
        case .exclusions: "Exclusions"
        case .menubar: "Menu Bar"
        case .updates: "Updates"
        }
    }

    /// The SF Symbol over each toolbar tab's label.
    public static func tabSymbol(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "gearshape"
        case .arranging: "rectangle.split.3x1"
        case .zoom: "plus.magnifyingglass"
        case .shortcuts: "keyboard"
        case .exclusions: "hand.raised"
        case .menubar: "menubar.rectangle"
        case .updates: "arrow.down.circle"
        }
    }
}
