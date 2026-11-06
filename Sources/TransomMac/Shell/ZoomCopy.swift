import TransomEngine
import TransomModel

/// Zoom copy from the UI-SPEC (Surface 2, Accessibility, Copywriting Contract, Logging). Pure strings, no AppKit types.
nonisolated public enum ZoomCopy {
    // MARK: Screen Recording explainer (Surface 2)

    public static let explainerMessage = "Show window previews while zooming?"
    public static let explainerInformative =
        "Transom takes still pictures of your windows using Screen Recording. Without it, zoom shows app icons instead."
    public static let allowPreviews = "Allow Previews"
    public static let notNow = "Not Now"

    // MARK: Reveal announcements (Accessibility)

    /// "Showing all windows", "Showing “Safari”", "Showing 3 windows", plus ", 1 collapsed" / ", 2 collapsed".
    /// `appName` names the one window of a one-window view.
    public static func revealAnnouncement(view: ViewTarget, appName: String?, windowCount: Int, collapsed: Int) -> String {
        let shown: String
        switch view {
        case .home: shown = "Showing all windows"
        case .node:
            if windowCount == 1, let appName {
                shown = "Showing \u{201C}\(MenuCopy.truncatedAppName(appName))\u{201D}"
            } else {
                shown = windowCount == 1 ? "Showing 1 window" : "Showing \(windowCount) windows"
            }
        }
        switch collapsed {
        case 0: return shown
        case 1: return shown + ", 1 collapsed"
        default: return shown + ", \(collapsed) collapsed"
        }
    }

    // MARK: Capture state (Debug line, 04-05)

    public static let capturePreviews = "window previews"
    public static let captureNoPermission = "app-icon tiles (no Screen Recording)"
    public static let captureFailing = "app-icon tiles (capture failing)"

    // MARK: Menu (Surface 6) and the zoom toggle's announcements (Accessibility)

    public static let zoomSection = "Zoom"
    public static let moveViewMenu = "Move View"
    public static let allowWindowPreviews = "Allow Window Previews\u{2026}"
    public static let turnOffZoom = "Turn Off Zoom"
    public static let turnOnZoom = "Turn On Zoom"
    public static let shortcutsItem = "Shortcuts\u{2026}"
    public static let zoomedInDescription = "Transom: zoomed in"
    public static let zoomOffAnnouncement = "Zoom off"
    public static let zoomOnAnnouncement = "Zoom on"

    // MARK: Shortcuts window (Surface 8, Copywriting Contract)

    public static let shortcutsWindowTitle = "Shortcuts"
    public static let mouseSection = "Mouse"
    public static let doubleClickToggle = "Double-click a title bar to frame its window"
    public static let doubleClickFooterOn = "When off, double-clicking a title bar does what Desktop & Dock settings say."
    public static let doubleClickFooterZoomOff = "Turn on zoom to use this."
    public static let restoreDefaults = "Restore Defaults"
    public static let restoreDefaultsMessage = "Restore all shortcuts to their defaults?"
    public static let restoreDefaultsInformative = "Every shortcut you changed or cleared goes back to its default. This can't be undone."

    /// A Recorder row's title: the menu title, naming the submenu where the item title alone ("Left") is ambiguous.
    public static func shortcutTitle(_ command: Command) -> String {
        switch command {
        case .camera(.pan(let edge)): "Move View \(MenuCopy.direction(edge))"
        case .focus(let edge): "Focus \(MenuCopy.direction(edge))"
        case .moveOrSnap(let edge): "Move Window \(MenuCopy.direction(edge)) or Snap to \(MenuCopy.snapTitle(half(edge)))"
        case .togglePause: "Pause or Resume Arranging"
        case .dock: "Dock Window Where It Is"
        case .dockFourth(let slot, let axis): "Dock to \(MenuCopy.fourthTitle(slot, axis))"
        default: MenuCopy.commandTitle(command)
        }
    }

    private static func half(_ edge: Edge) -> SnapTarget {
        switch edge {
        case .left: .leftHalf
        case .right: .rightHalf
        case .top: .topHalf
        case .bottom: .bottomHalf
        }
    }

    public static func duplicateShortcut(usedBy title: String) -> String {
        "This shortcut is already used by \u{201C}\(title)\u{201D} in Transom."
    }

    // MARK: Debug submenu lines (Surface 6)

    /// "Zoom: on, {capture state}" or "Zoom: off"; `capture` is one of the capture strings above.
    public static func zoomStateLine(enabled: Bool, capture: String) -> String {
        enabled ? "Zoom: on, \(capture)" : "Zoom: off"
    }

    public static func lastSettleLine(_ settle: (ms: Int, windows: Int)?) -> String {
        guard let settle else { return "Last settle: none yet" }
        return "Last settle: \(settle.ms) ms, " + (settle.windows == 1 ? "1 window" : "\(settle.windows) windows")
    }

    public static func snapshotCacheLine(windows: Int, bytes: Int) -> String {
        guard windows > 0 else { return "Snapshot cache: empty" }
        let mb = Int((Double(bytes) / 1_048_576).rounded())
        return "Snapshot cache: " + (windows == 1 ? "1 window" : "\(windows) windows") + ", \(mb) MB"
    }

    // MARK: Capture log lines (Logging, category capture)

    public static let logGranted = "screen recording: granted"
    public static let logNotGranted = "screen recording: not granted, using app-icon tiles"
    public static let logRevoked = "screen recording: revoked mid-session, using app-icon tiles"
    public static let logFailing = "capture failing while granted; macOS may need Transom reopened"
    public static let logExplainerShown = "explainer shown"
    public static let logExplainerAllow = "explainer: allow"
    public static let logExplainerNotNow = "explainer: not now"

    // MARK: Pointer input (Surface 4, 5, 9; Logging, category zoomInput)

    /// Announced when Esc cancels a rubber band (ZOOM-12).
    public static let zoomCanceled = "Zoom canceled"
    public static func logRectZoom(_ node: String) -> String { "rect zoom \u{2192} \(node)" }
    public static let logRectNoTarget = "rect zoom: no target"
    public static let logRectCanceled = "rect zoom canceled (Esc)"
    public static let logRepost = "\u{2318}\u{21E7}-click re-posted"
    public static let logPickOn = "pick mode on"
    public static func logPick(_ windowID: UInt32) -> String { "pick \u{2192} window \(windowID)" }
    public static func logPickOff(_ reason: String) -> String { "pick mode off: \(reason)" }
    public static func logTitleBarDoubleClick(_ windowID: UInt32) -> String { "title bar double-click \u{2192} frame window \(windowID)" }
}
