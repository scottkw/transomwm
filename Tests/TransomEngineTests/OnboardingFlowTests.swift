import TransomEngine
import Testing

/// SHIP-02, D-05: which onboarding steps show, their captions and their order.
@Suite struct OnboardingFlowTests {
    @Test func aFirstRunShowsWelcomeAccessibilityDone() {
        #expect(OnboardingFlow.steps(completed: false) == [.welcome, .accessibility, .done])
    }

    @Test func afterCompletionOnlyAccessibilityShows() {
        #expect(OnboardingFlow.steps(completed: true) == [.accessibility])
        #expect(OnboardingFlow.caption(for: .accessibility, in: [.accessibility]) == nil)
    }

    @Test func captionsCountOnlyNumberedSteps() {
        let firstRun = OnboardingFlow.steps(completed: false)
        #expect(OnboardingFlow.caption(for: .welcome, in: firstRun).map { [$0.number, $0.total] } == [1, 2])
        #expect(OnboardingFlow.caption(for: .accessibility, in: firstRun).map { [$0.number, $0.total] } == [2, 2])
        #expect(OnboardingFlow.caption(for: .done, in: firstRun) == nil)
        let all = OnboardingStep.allCases
        #expect(OnboardingFlow.caption(for: .move, in: all) == nil)
        #expect(OnboardingFlow.caption(for: .launchAtLogin, in: all).map { [$0.number, $0.total] } == [5, 5])
        #expect(OnboardingFlow.caption(for: .screenRecording, in: firstRun) == nil)
    }

    @Test func nextFollowsTheList() {
        let firstRun = OnboardingFlow.steps(completed: false)
        #expect(OnboardingFlow.next(after: .welcome, in: firstRun) == .accessibility)
        #expect(OnboardingFlow.next(after: .accessibility, in: firstRun) == .done)
        #expect(OnboardingFlow.next(after: .done, in: firstRun) == nil)
        #expect(OnboardingFlow.next(after: .accessibility, in: [.accessibility]) == nil)
        #expect(OnboardingFlow.next(after: .move, in: firstRun) == nil)
    }
}
