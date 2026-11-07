/// Onboarding copy (09 UI-SPEC Surface 2). The Accessibility step keeps the Phase 2 copy in `SetupView`.
nonisolated public enum OnboardingCopy {
    public static func caption(number: Int, total: Int) -> String { "Step \(number) of \(total)" }

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

    public static let doneHeading = "Transom is ready"
    public static let doneBody =
        "Transom lives in the menu bar. Drag a window to a screen edge to dock it, or click the Transom icon for every command and Settings."

    public static let continueButton = "Continue"
    public static let quitButton = "Quit Transom"
    public static let doneButton = "Done"
}
