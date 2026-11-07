import TransomEngine
import Testing

/// SHIP-02, D-05: which onboarding steps show, their captions and their order.
@Suite struct OnboardingFlowTests {
    @Test func aFirstRunShowsWelcomeAccessibilityScreenRecordingDone() {
        #expect(OnboardingFlow.steps(completed: false) == [.welcome, .accessibility, .screenRecording, .done])
    }

    @Test func afterCompletionOnlyAccessibilityShows() {
        #expect(OnboardingFlow.steps(completed: true) == [.accessibility])
        #expect(OnboardingFlow.caption(for: .accessibility, in: [.accessibility]) == nil)
    }

    @Test func captionsCountOnlyNumberedSteps() {
        let firstRun = OnboardingFlow.steps(completed: false)
        #expect(OnboardingFlow.caption(for: .welcome, in: firstRun).map { [$0.number, $0.total] } == [1, 3])
        #expect(OnboardingFlow.caption(for: .accessibility, in: firstRun).map { [$0.number, $0.total] } == [2, 3])
        #expect(OnboardingFlow.caption(for: .done, in: firstRun) == nil)
        let all = OnboardingStep.allCases
        #expect(OnboardingFlow.caption(for: .move, in: all) == nil)
        #expect(OnboardingFlow.caption(for: .launchAtLogin, in: all).map { [$0.number, $0.total] } == [5, 5])
        #expect(OnboardingFlow.caption(for: .screenRecording, in: firstRun).map { [$0.number, $0.total] } == [3, 3])
        #expect(OnboardingFlow.caption(for: .features, in: firstRun) == nil)
    }

    @Test func nextFollowsTheList() {
        let firstRun = OnboardingFlow.steps(completed: false)
        #expect(OnboardingFlow.next(after: .welcome, in: firstRun) == .accessibility)
        #expect(OnboardingFlow.next(after: .accessibility, in: firstRun) == .screenRecording)
        #expect(OnboardingFlow.next(after: .screenRecording, in: firstRun) == .done)
        #expect(OnboardingFlow.next(after: .done, in: firstRun) == nil)
        #expect(OnboardingFlow.next(after: .accessibility, in: [.accessibility]) == nil)
        #expect(OnboardingFlow.next(after: .move, in: firstRun) == nil)
    }

    @Test func resumeSkipsPastScreenRecording() {
        let firstRun = OnboardingFlow.steps(completed: false)
        #expect(OnboardingFlow.resume(stored: "screenRecording", in: firstRun) == .done)
        #expect(OnboardingFlow.resume(stored: "welcome", in: firstRun) == .welcome)
        #expect(OnboardingFlow.resume(stored: "accessibility", in: firstRun) == .accessibility)
    }

    @Test func resumeFallsBackToTheFirstStep() {
        let firstRun = OnboardingFlow.steps(completed: false)
        #expect(OnboardingFlow.resume(stored: nil, in: firstRun) == .welcome)
        #expect(OnboardingFlow.resume(stored: "nonsense", in: firstRun) == .welcome)
        #expect(OnboardingFlow.resume(stored: "launchAtLogin", in: firstRun) == .welcome)
    }
}
