import TransomEngine
import Testing

/// SHIP-02, D-05: which onboarding steps show, their captions and their order.
@Suite struct OnboardingFlowTests {
    let firstRun = OnboardingFlow.steps(completed: false, conflictsActive: false)

    @Test func aFirstRunShowsWelcomeThroughLaunchAtLoginThenDone() {
        #expect(firstRun == [.welcome, .accessibility, .screenRecording, .launchAtLogin, .done])
    }

    @Test func theFeaturesStepShowsOnlyWithAnActiveConflict() {
        let withFeatures = OnboardingFlow.steps(completed: false, conflictsActive: true)
        #expect(withFeatures == [.welcome, .accessibility, .screenRecording, .features, .launchAtLogin, .done])
        #expect(OnboardingFlow.caption(for: .features, in: withFeatures).map { [$0.number, $0.total] } == [4, 5])
        #expect(OnboardingFlow.caption(for: .launchAtLogin, in: withFeatures).map { [$0.number, $0.total] } == [5, 5])
        #expect(OnboardingFlow.resume(stored: "screenRecording", in: withFeatures) == .features)
        #expect(!firstRun.contains(.features))
    }

    @Test func afterCompletionOnlyAccessibilityShows() {
        #expect(OnboardingFlow.steps(completed: true, conflictsActive: true) == [.accessibility])
        #expect(OnboardingFlow.caption(for: .accessibility, in: [.accessibility]) == nil)
    }

    @Test func captionsCountOnlyNumberedSteps() {
        #expect(OnboardingFlow.caption(for: .welcome, in: firstRun).map { [$0.number, $0.total] } == [1, 4])
        #expect(OnboardingFlow.caption(for: .accessibility, in: firstRun).map { [$0.number, $0.total] } == [2, 4])
        #expect(OnboardingFlow.caption(for: .done, in: firstRun) == nil)
        let all = OnboardingStep.allCases
        #expect(OnboardingFlow.caption(for: .move, in: all) == nil)
        #expect(OnboardingFlow.caption(for: .launchAtLogin, in: all).map { [$0.number, $0.total] } == [5, 5])
        #expect(OnboardingFlow.caption(for: .screenRecording, in: firstRun).map { [$0.number, $0.total] } == [3, 4])
        #expect(OnboardingFlow.caption(for: .launchAtLogin, in: firstRun).map { [$0.number, $0.total] } == [4, 4])
        #expect(OnboardingFlow.caption(for: .features, in: firstRun) == nil)
    }

    @Test func nextFollowsTheList() {
        #expect(OnboardingFlow.next(after: .welcome, in: firstRun) == .accessibility)
        #expect(OnboardingFlow.next(after: .accessibility, in: firstRun) == .screenRecording)
        #expect(OnboardingFlow.next(after: .screenRecording, in: firstRun) == .launchAtLogin)
        #expect(OnboardingFlow.next(after: .launchAtLogin, in: firstRun) == .done)
        #expect(OnboardingFlow.next(after: .done, in: firstRun) == nil)
        #expect(OnboardingFlow.next(after: .accessibility, in: [.accessibility]) == nil)
        #expect(OnboardingFlow.next(after: .move, in: firstRun) == nil)
    }

    @Test func resumeSkipsPastScreenRecording() {
        #expect(OnboardingFlow.resume(stored: "screenRecording", in: firstRun) == .launchAtLogin)
        #expect(OnboardingFlow.resume(stored: "launchAtLogin", in: firstRun) == .launchAtLogin)
        #expect(OnboardingFlow.resume(stored: "welcome", in: firstRun) == .welcome)
        #expect(OnboardingFlow.resume(stored: "accessibility", in: firstRun) == .accessibility)
    }

    @Test func resumeFallsBackToTheFirstStep() {
        #expect(OnboardingFlow.resume(stored: nil, in: firstRun) == .welcome)
        #expect(OnboardingFlow.resume(stored: "nonsense", in: firstRun) == .welcome)
        #expect(OnboardingFlow.resume(stored: "features", in: firstRun) == .welcome)
    }
}
