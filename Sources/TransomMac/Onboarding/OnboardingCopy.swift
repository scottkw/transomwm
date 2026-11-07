import TransomEngine

/// Onboarding copy (09 UI-SPEC Surface 2). The Accessibility step keeps the Phase 2 copy in `SetupView`.
nonisolated public enum OnboardingCopy {
    public static func caption(number: Int, total: Int) -> String { "Step \(number) of \(total)" }

    public static let moveHeading = "Move Transom to Applications"
    public static func moveBody(_ place: InstallLocation.Place) -> String {
        let name: String
        switch place {
        case .diskImage: name = "a disk image"
        case .downloads: name = "your Downloads folder"
        case .translocated: name = "a temporary folder"
        case .applications, .other: preconditionFailure("no Move step from \(place)")
        }
        return "Transom is running from \(name). macOS can forget the permissions you give it there, so move it to the Applications folder first."
    }
    public static let moveButton = "Move to Applications"
    public static let moveQuitButton = "Quit"
    /// Continues setup without moving, so a copy that can't move still reaches Accessibility (WR-03).
    public static let moveNotNowButton = "Not Now"
    public static let moveFailed = "Couldn't move Transom. Drag it to the Applications folder yourself, then open it from there."
    public static let replaceMessage = "Replace the Transom in Applications?"
    public static let replaceInformative = "The copy that's there now goes to the Trash."
    public static let replaceButton = "Replace"

    public static let welcomeHeading = "Welcome to Transom"
    public static let welcomeBody =
        "Transom docks your windows into tiles that never overlap, and lets you zoom out to see them all. Setup takes about a minute: one permission is required, the rest is optional."

    public static let screenRecordingHeading = "Show window previews (optional)"
    public static let screenRecordingBody =
        "When you zoom out, Transom can show live pictures of your windows. That needs Screen Recording access. Without it, zoomed-out views show each app's icon. Transom never records or saves your screen."
    public static let screenRecordingMonthly =
        "On macOS 15 and later, macOS asks you to confirm this about once a month. Choose Allow to keep previews."
    public static let screenRecordingWaiting = "Waiting for Screen Recording\u{2026}"
    public static let screenRecordingWaitingHelp =
        "Turn on \u{201C}Transom\u{201D} in System Settings \u{25B8} Privacy & Security \u{25B8} Screen & System Audio Recording. You can also turn it on later in Settings \u{25B8} Zoom & Gestures."
    public static let screenRecordingOn = "Screen Recording is on."
    public static let allowScreenRecordingButton = "Allow Screen Recording"
    public static let skipButton = "Skip"
    public static let backButton = "Back"

    public static let featuresHeading = "Turn off macOS features that move windows"
    public static let featuresBody =
        "These move windows by themselves and fight with Transom. You can turn them back on any time with Restore macOS Window Settings in the Transom menu."
    public static let openDesktopDockButton = "Open Desktop & Dock Settings"

    public static let launchHeading = "Open Transom when you log in"
    public static let launchBody =
        "Transom arranges windows only while it's running. You can change this in Settings \u{25B8} General."

    public static let doneHeading = "Transom is ready"
    public static let doneBody =
        "Transom lives in the menu bar. Drag a window to a screen edge to dock it, or click the Transom icon for every command and Settings."

    public static let continueButton = "Continue"
    public static let quitButton = "Quit Transom"
    public static let doneButton = "Done"
    public static let openSettingsButton = "Open Settings"
}
