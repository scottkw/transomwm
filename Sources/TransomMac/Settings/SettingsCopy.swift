import TransomEngine

/// Settings window copy (09 UI-SPEC Surface 1). The UI-SPEC lists "Settings…" under MenuCopy; it lives here so the
/// Settings window owns one copy type.
nonisolated public enum SettingsCopy {
    public static let menuItem = "Settings\u{2026}"

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
