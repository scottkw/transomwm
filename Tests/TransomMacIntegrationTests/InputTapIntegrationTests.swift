import CoreGraphics
import Foundation
@testable import TransomMac
import Testing

/// RESEARCH Patterns 4 and 6 live: the active session tap runs on its own thread and run loop and comes down cleanly.
/// No events are synthesised; every tap is stopped in a defer.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct InputTapIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func theTapRunsOnItsOwnThreadAndStopsCleanly() async throws {
        let tap = InputTap()
        defer { tap.stop() }
        #expect(tap.start())
        let port = try #require(tap.port)
        #expect(tap.thread.map { !$0.isMainThread } == true, "the tap thread is the main thread")
        try await Task.sleep(for: .seconds(1))
        #expect(tap.isRunning)
        #expect(CGEvent.tapIsEnabled(tap: port))
        tap.stop()
        #expect(!CGEvent.tapIsEnabled(tap: port))
        #expect(!tap.isRunning)
    }

    @Test(.timeLimit(.minutes(1)))
    func oneWatchdogTickReenablesADisabledTap() async throws {
        let tap = InputTap()
        defer { tap.stop() }
        #expect(tap.start())
        let port = try #require(tap.port)
        // macOS answers this disable with tapDisabledByUserInput, which the callback may already have re-enabled;
        // either way one tick must leave the tap enabled.
        CGEvent.tapEnable(tap: port, enable: false)
        tap.watchdogTick()
        #expect(CGEvent.tapIsEnabled(tap: port), "the watchdog left the tap disabled")
        #expect(tap.isRunning)
    }

    /// Pitfall 4: leaving `.ready` takes the tap down at once; coming back brings drags back.
    @Test(.timeLimit(.minutes(1)))
    func losingAccessStopsTheTapAndRegainingItRestartsIt() async throws {
        let controller = ArrangeController(system: AXWindowSystem())
        defer { controller.stopTap() }
        #expect(controller.startTap())
        #expect(controller.isTapRunning)
        controller.accessChanged(ready: false)
        #expect(!controller.isTapRunning, "the tap kept running without access")
        controller.accessChanged(ready: true)
        #expect(controller.isTapRunning, "the tap did not come back with access")
    }
}
