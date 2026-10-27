import Foundation
import TransomMac
import Testing

@Suite struct TCCResetTests {
    @Test func argumentsAreTheFixedResetArgv() {
        #expect(TCCReset.arguments(bundleID: "com.eightabyte.transom.debug") == ["reset", "Accessibility", "com.eightabyte.transom.debug"])
    }

    @Test func noBundleIDRefusesWithoutRunning() async {
        #expect(await TCCReset.run(bundleID: nil) == -1)
    }

    /// tccutil rejects bundle IDs LaunchServices doesn't know with 64, so this resets nothing real.
    @Test func unknownBundleIDReturnsTccutilsStatus() async {
        #expect(await TCCReset.run(bundleID: "com.eightabyte.transom.unknown-test-\(UUID().uuidString)") == 64)
    }
}
