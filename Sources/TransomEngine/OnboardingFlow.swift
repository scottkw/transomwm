/// A step of the Set Up Transom window, in the 09 UI-SPEC Surface 2 order (0–6).
public enum OnboardingStep: String, CaseIterable, Sendable {
    case move, welcome, accessibility, screenRecording, features, launchAtLogin, done
}

/// Which onboarding steps show, their "Step n of total" captions and the step after each (D-05, RESEARCH Pattern 5).
/// Pure: the window controller reads `onboarding.completed` and drives the window.
public enum OnboardingFlow {
    /// The first run walks every applicable step; after completion only the Accessibility step ever shows.
    /// The macOS window features step shows only while a conflicting feature is on.
    public static func steps(completed: Bool, conflictsActive: Bool) -> [OnboardingStep] {
        if completed { return [.accessibility] }
        return [.welcome, .accessibility, .screenRecording] + (conflictsActive ? [.features] : []) + [.launchAtLogin, .done]
    }

    /// Welcome…Launch at login are numbered, counting only the ones in `steps`. Move and Done have no caption, and
    /// neither does the lone Accessibility step shown after completion.
    public static func caption(for step: OnboardingStep, in steps: [OnboardingStep]) -> (number: Int, total: Int)? {
        let numbered = steps.filter { (s: OnboardingStep) -> Bool in s != .move && s != .done }
        guard steps.count > 1, let index = numbered.firstIndex(of: step) else { return nil }
        return (index + 1, numbered.count)
    }

    /// Where a relaunch picks up from the stored last step: past Screen Recording (macOS's Quit & Reopen), at any
    /// other step still in `steps`, and at the first step for anything else.
    public static func resume(stored: String?, in steps: [OnboardingStep]) -> OnboardingStep {
        guard let step = stored.flatMap(OnboardingStep.init(rawValue:)), steps.contains(step) else { return steps[0] }
        return step == .screenRecording ? next(after: step, in: steps) ?? step : step
    }

    public static func next(after step: OnboardingStep, in steps: [OnboardingStep]) -> OnboardingStep? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }
}
