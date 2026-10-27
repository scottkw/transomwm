@testable import TransomMac
import Testing

@MainActor private final class Fired {
    var names: [String] = []
}

/// The Arranger's wake-up (RESEARCH Pattern 1): one pending timer, replaced by a newer wake.
@MainActor @Suite struct WakeTimerTests {
    @Test func twoWakesBeforeTheFirstFiresGiveOneTickAtTheLaterInstant() async {
        let timer = WakeTimer()
        let fired = Fired()
        let now = ContinuousClock.now
        timer.set(now + .milliseconds(50)) { fired.names.append("first") }
        timer.set(now + .milliseconds(100)) { fired.names.append("second") }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(fired.names.isEmpty)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(fired.names == ["second"])
    }
}
