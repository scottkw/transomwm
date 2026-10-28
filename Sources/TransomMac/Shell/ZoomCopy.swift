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

    /// "Showing all windows", "Showing “Safari”", "Showing 3 windows", plus ", 1 collapsed" / ", 2 collapsed";
    /// "Showing the Desktop". `appName` names the one window of a one-window view.
    public static func revealAnnouncement(view: ViewTarget, appName: String?, windowCount: Int, collapsed: Int) -> String {
        let shown: String
        switch view {
        case .home: shown = "Showing all windows"
        case .node(.desktop): shown = "Showing the Desktop"
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

    // MARK: Capture log lines (Logging, category capture)

    public static let logGranted = "screen recording: granted"
    public static let logNotGranted = "screen recording: not granted, using app-icon tiles"
    public static let logRevoked = "screen recording: revoked mid-session, using app-icon tiles"
    public static let logFailing = "capture failing while granted; macOS may need Transom reopened"
    public static let logExplainerShown = "explainer shown"
    public static let logExplainerAllow = "explainer: allow"
    public static let logExplainerNotNow = "explainer: not now"
}
