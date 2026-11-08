@testable import TransomMac
import Testing

@MainActor private final class Fired {
    var names: [String] = []
    var at: [ContinuousClock.Instant] = []
}

/// The Arranger's wake-up (RESEARCH Pattern 1): one pending timer, replaced by a newer wake.
@MainActor @Suite struct WakeTimerTests {
    @Test func twoWakesBeforeTheFirstFiresGiveOneTickAtTheLaterInstant() async {
        let timer = WakeTimer()
        let fired = Fired()
        let now = ContinuousClock.now
        timer.set(now + .milliseconds(50)) { fired.names.append("first"); fired.at.append(.now) }
        timer.set(now + .milliseconds(100)) { fired.names.append("second"); fired.at.append(.now) }
        // When it fired, not a mid-way wall-clock look: a loaded CI runner overslept a 60 ms sleep past 100 ms.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(fired.names == ["second"])
        #expect(fired.at.allSatisfy { $0 >= now + .milliseconds(100) })
    }
}
