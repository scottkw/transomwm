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
        // When it fired, not a wall-clock look: a loaded CI runner overslept a 60 ms sleep past 100 ms, and under
        // parallel tests the tick took over 300 ms to arrive. Wait for it (up to 5 s), then a beat for any second tick.
        let deadline = ContinuousClock.now + .seconds(5)
        while fired.names.isEmpty, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fired.names == ["second"])
        #expect(fired.at.allSatisfy { $0 >= now + .milliseconds(100) })
    }
}
