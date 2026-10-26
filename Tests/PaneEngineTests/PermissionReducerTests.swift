import PaneEngine
import Testing

/// Runs `events` from `state` and returns every effect emitted, in order.
private func run(_ events: [PermissionEvent], from state: inout PermissionState) -> [PermissionEffect] {
    events.flatMap { PermissionReducer.reduce(&state, $0) }
}

private func state(after events: [PermissionEvent]) -> PermissionState {
    var state = PermissionState()
    _ = run(events, from: &state)
    return state
}

private let firstClick = PermissionEvent.openSettingsClicked(at: .zero)
private let staleA: [PermissionEvent] = [.launched(trusted: true), .probeFinished(.apiDisabled)]
private let staleB: [PermissionEvent] = [.launched(trusted: false), firstClick, .pollTick(trusted: false, at: .seconds(15))]

@Suite struct PermissionReducerTests {
    @Test func initialStateIsNotTrusted() {
        let state = PermissionState()
        #expect(state.phase == .notTrusted)
        #expect(state.cycleStartedAt == nil)
        #expect(!state.showStaleFormB && !state.afterReset)
        #expect(state.resetFailedCode == nil && state.phaseBeforeReset == nil)
    }

    @Test func untrustedLaunchStaysNotTrustedAndPolls() {
        var state = PermissionState()
        #expect(PermissionReducer.reduce(&state, .launched(trusted: false)) == [.startPolling])
        #expect(state.phase == .notTrusted)
    }

    /// WR-02: a grant made in System Settings or the system prompt, without the Set Up button, is still noticed.
    @Test func aGrantMadeWithoutTheSettingsButtonIsNoticedByThePoll() {
        var state = state(after: [.launched(trusted: false)])
        #expect(PermissionReducer.reduce(&state, .pollTick(trusted: false, at: .seconds(20))).isEmpty)
        #expect(state.phase == .notTrusted)
        #expect(!state.showStaleFormB)
        #expect(PermissionReducer.reduce(&state, .pollTick(trusted: true, at: .seconds(21))) == [.stopPolling, .runProbe])
        #expect(state.phase == .probing)
    }

    @Test func trustedLaunchProbes() {
        var state = PermissionState()
        #expect(PermissionReducer.reduce(&state, .launched(trusted: true)) == [.runProbe])
        #expect(state.phase == .probing)
    }

    @Test func firstSettingsClickPromptsOpensAndPolls() {
        var state = state(after: [.launched(trusted: false)])
        #expect(PermissionReducer.reduce(&state, firstClick) == [.promptForTrust, .openSettings, .startPolling])
        #expect(state.phase == .waitingForGrant)
        #expect(state.cycleStartedAt == .zero)
    }

    @Test func laterSettingsClickOnlyOpensSettingsAndKeepsTheCycleStart() {
        var state = state(after: [.launched(trusted: false), firstClick])
        #expect(PermissionReducer.reduce(&state, .openSettingsClicked(at: .seconds(5))) == [.openSettings])
        #expect(state.cycleStartedAt == .zero)
        #expect(state.phase == .waitingForGrant)
    }

    @Test func staleFormBAppearsAtFifteenSecondsNotBefore() {
        var state = state(after: [.launched(trusted: false), firstClick])
        #expect(PermissionReducer.reduce(&state, .pollTick(trusted: false, at: .milliseconds(14_900))).isEmpty)
        #expect(!state.showStaleFormB)
        #expect(PermissionReducer.reduce(&state, .pollTick(trusted: false, at: .seconds(15))).isEmpty)
        #expect(state.showStaleFormB)
        _ = PermissionReducer.reduce(&state, .pollTick(trusted: false, at: .seconds(30)))
        #expect(state.showStaleFormB)
        #expect(state.phase == .waitingForGrant)
        #expect(PermissionReducer.staleFormBDelay == .seconds(15))
    }

    @Test func staleFormBTimerDoesNotRestartOnLaterClicks() {
        var state = state(after: [.launched(trusted: false), firstClick, .openSettingsClicked(at: .seconds(10))])
        _ = PermissionReducer.reduce(&state, .pollTick(trusted: false, at: .seconds(15)))
        #expect(state.showStaleFormB)
    }

    @Test func trustedPollStopsPollingAndProbes() {
        var state = state(after: [.launched(trusted: false), firstClick])
        #expect(PermissionReducer.reduce(&state, .pollTick(trusted: true, at: .seconds(3))) == [.stopPolling, .runProbe])
        #expect(state.phase == .probing)
    }

    @Test(arguments: [ProbeOutcome.success, .inconclusive])
    func successfulOrInconclusiveProbeIsReady(outcome: ProbeOutcome) {
        var state = state(after: [.launched(trusted: true)])
        #expect(PermissionReducer.reduce(&state, .probeFinished(outcome)) == [.startTracking, .bringWindowForward])
        #expect(state.phase == .ready)
    }

    @Test func apiDisabledProbeIsStaleFormA() {
        var state = state(after: [.launched(trusted: true)])
        #expect(PermissionReducer.reduce(&state, .probeFinished(.apiDisabled)).isEmpty)
        #expect(state.phase == .staleTrustedButFailing)
    }

    @Test func settingsClickInFormAOnlyOpensSettings() {
        var state = state(after: staleA)
        #expect(PermissionReducer.reduce(&state, .openSettingsClicked(at: .seconds(2))) == [.openSettings])
        #expect(state.phase == .staleTrustedButFailing)
    }

    @Test(arguments: [staleA, staleB])
    func resetFromEitherStaleFormRunsReset(prefix: [PermissionEvent]) {
        var state = state(after: prefix)
        let before = state.phase
        #expect(PermissionReducer.reduce(&state, .resetClicked) == [.runReset])
        #expect(state.phase == .resetting)
        #expect(state.phaseBeforeReset == before)
    }

    @Test(arguments: [
        [PermissionEvent.launched(trusted: false)],
        [.launched(trusted: true), .probeFinished(.success)],
        [.launched(trusted: false), firstClick],
    ])
    func resetIsIgnoredOutsideTheStaleForms(prefix: [PermissionEvent]) {
        var state = state(after: prefix)
        let before = state
        #expect(PermissionReducer.reduce(&state, .resetClicked).isEmpty)
        #expect(state == before)
    }

    @Test func successfulResetStartsANewCycle() {
        var state = state(after: staleB + [.resetClicked])
        #expect(PermissionReducer.reduce(&state, .resetFinished(exitCode: 0)) == [.startPolling])
        #expect(state.phase == .waitingForGrant)
        #expect(state.afterReset)
        #expect(state.cycleStartedAt == nil)
        #expect(!state.showStaleFormB)
        #expect(PermissionReducer.reduce(&state, .openSettingsClicked(at: .seconds(40))) == [.promptForTrust, .openSettings])
        #expect(state.cycleStartedAt == .seconds(40))
    }

    @Test(arguments: [staleA, staleB])
    func failedResetReturnsToThePriorStateWithTheCode(prefix: [PermissionEvent]) {
        let prior = state(after: prefix).phase
        var state = state(after: prefix + [.resetClicked])
        #expect(PermissionReducer.reduce(&state, .resetFinished(exitCode: 64)).isEmpty)
        #expect(state.phase == prior)
        #expect(state.resetFailedCode == 64)
    }

    /// Twenty fixed pseudo-random sequences of every event except a Settings click, run from a fresh
    /// state and from mid-cycle: none may ever ask macOS to show its Accessibility prompt.
    @Test func noNonClickSequenceEverPrompts() {
        let alphabet: [PermissionEvent] = [
            .launched(trusted: false), .launched(trusted: true),
            .pollTick(trusted: false, at: .seconds(1)), .pollTick(trusted: false, at: .seconds(20)),
            .pollTick(trusted: true, at: .seconds(2)),
            .probeFinished(.success), .probeFinished(.apiDisabled), .probeFinished(.inconclusive),
            .resetClicked, .resetFinished(exitCode: 0), .resetFinished(exitCode: 64),
        ]
        var seed: UInt64 = 0x5EED
        var sequences: [[PermissionEvent]] = []
        for _ in 0..<20 {
            var sequence: [PermissionEvent] = []
            for _ in 0..<16 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                sequence.append(alphabet[Int(seed >> 33) % alphabet.count])
            }
            sequences.append(sequence)
        }
        #expect(sequences.count == 20)
        for sequence in sequences {
            var fresh = PermissionState()
            #expect(!run(sequence, from: &fresh).contains(.promptForTrust))
            var midCycle = state(after: [.launched(trusted: false), firstClick])
            #expect(!run(sequence, from: &midCycle).contains(.promptForTrust))
        }
    }
}
