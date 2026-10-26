import PaneEngine

/// Conflict copy from UI-SPEC Surface 1 (menu lines) and Surface 5 (alerts). Pure strings, no AppKit types. The
/// approved wording "Click Wallpaper to Reveal Desktop" stays, though macOS 27 says "show desktop" (UAT note only).
nonisolated public enum ConflictCopy {
    public static let imageDescription = "Conflict"
    public static let restoreItem = "Restore macOS Window Settings"
    public static let turnOffButton = "Turn Off"
    public static let notNowButton = "Not Now"

    public static func menuTitle(_ conflict: Conflict) -> String {
        switch conflict {
        case .stageManager: "Turn Off Stage Manager"
        case .edgeTiling: "Turn Off macOS Edge Tiling"
        case .clickWallpaper: "Turn Off Click Wallpaper to Reveal Desktop"
        }
    }

    public static func tooltip(_ conflict: Conflict) -> String {
        switch conflict {
        case .stageManager: "Stage Manager moves windows by itself, so Pane has paused arranging."
        case .edgeTiling: "macOS tiles windows dragged to screen edges, which competes with Pane's docking."
        case .clickWallpaper: "Clicking the wallpaper or a gap between windows moves every window off screen."
        }
    }

    public static func alertMessage(_ conflict: Conflict) -> String {
        switch conflict {
        case .stageManager: "Turn off Stage Manager?"
        case .edgeTiling: "Turn off macOS edge tiling?"
        case .clickWallpaper: "Turn off Click Wallpaper to Reveal Desktop?"
        }
    }

    public static func alertInfo(_ conflict: Conflict) -> String {
        switch conflict {
        case .stageManager:
            "Stage Manager moves and groups windows by itself, so Pane has paused arranging. Turning it off lets Pane arrange your windows again. You can turn it back on with Restore macOS Window Settings in the Pane menu."
        case .edgeTiling:
            "macOS also tiles a window when you drag it to a screen edge or the menu bar, so a drag meant for Pane can be tiled by macOS instead. Pane keeps working either way. You can turn macOS tiling back on with Restore macOS Window Settings in the Pane menu."
        case .clickWallpaper:
            "With this on, clicking the wallpaper, including a gap between docked windows, moves every window off screen. Turning it off sets it to Only in Stage Manager. You can change it back with Restore macOS Window Settings in the Pane menu."
        }
    }

    /// `{Feature}` in toast N7.
    public static func featureName(_ conflict: Conflict) -> String {
        switch conflict {
        case .stageManager: "Stage Manager"
        case .edgeTiling: "macOS edge tiling"
        case .clickWallpaper: "Click Wallpaper to Reveal Desktop"
        }
    }
}
