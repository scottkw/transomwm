import AppKit
@testable import PaneMac
import Testing

/// SAFE-01, Pattern 11: a quit waits for the restore, then records the clean exit, then lets AppKit terminate.
@Suite @MainActor struct AppDelegateTests {
    @Test func quittingRestoresThenWritesTheCleanExitThenReplies() async {
        var steps: [String] = []
        let delegate = AppDelegate(
            restore: { steps.append("restore") }, writeCleanExit: { steps.append("cleanExit") }, reply: { steps.append("reply \($0)") })
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        let replied = await waitFor { steps.count == 3 }
        #expect(replied)
        #expect(steps == ["restore", "cleanExit", "reply true"])
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}
