import Foundation
import PaneMac
import Testing

@Suite struct TCCResetTests {
    @Test func argumentsAreTheFixedResetArgv() {
        #expect(TCCReset.arguments(bundleID: "com.eightabyte.pane.debug") == ["reset", "Accessibility", "com.eightabyte.pane.debug"])
    }

    @Test func noBundleIDRefusesWithoutRunning() async {
        #expect(await TCCReset.run(bundleID: nil) == -1)
    }

    /// tccutil rejects bundle IDs LaunchServices doesn't know with 64, so this resets nothing real.
    @Test func unknownBundleIDReturnsTccutilsStatus() async {
        #expect(await TCCReset.run(bundleID: "com.eightabyte.pane.unknown-test-\(UUID().uuidString)") == 64)
    }
}
