import CoreGraphics
import Foundation
@testable import PaneMac
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
}
