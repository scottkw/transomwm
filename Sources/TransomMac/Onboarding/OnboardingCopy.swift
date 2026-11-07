/// Onboarding copy (09 UI-SPEC Surface 2). The Accessibility step keeps the Phase 2 copy in `SetupView`.
nonisolated public enum OnboardingCopy {
    public static func caption(number: Int, total: Int) -> String { "Step \(number) of \(total)" }

    public static let welcomeHeading = "Welcome to Transom"
    public static let welcomeBody =
        "Transom docks your windows into tiles that never overlap, and lets you zoom out to see them all. Setup takes about a minute: one permission is required, the rest is optional."

    public static let doneHeading = "Transom is ready"
    public static let doneBody =
        "Transom lives in the menu bar. Drag a window to a screen edge to dock it, or click the Transom icon for every command and Settings."

    public static let continueButton = "Continue"
    public static let quitButton = "Quit Transom"
    public static let doneButton = "Done"
}
