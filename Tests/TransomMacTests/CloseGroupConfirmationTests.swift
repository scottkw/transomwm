import Foundation
@testable import TransomMac
import Testing

/// UI-SPEC Surface 4 (2026-11-02): Close Group asks until "Do not show this again" is kept as `tabs.confirmCloseGroup`.
/// No alert is shown here: only the preference is read and written.
@Suite @MainActor struct CloseGroupConfirmationTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.closeGroup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func itAsksUntilSuppressedAndTheSuppressionPersists() throws {
        try withDefaults { defaults in
            let confirmation = CloseGroupConfirmation(defaults: defaults)
            #expect(confirmation.isEnabled, "a fresh domain does not ask")
            confirmation.isEnabled = false
            #expect(defaults.object(forKey: "tabs.confirmCloseGroup") as? Bool == false)
            #expect(!CloseGroupConfirmation(defaults: defaults).isEnabled)
            // Suppressed, it confirms without an alert.
            #expect(CloseGroupConfirmation(defaults: defaults).confirm(count: 3))
        }
    }

    @Test func aNonBoolValueAsks() throws {
        try withDefaults { defaults in
            defaults.set("no", forKey: CloseGroupConfirmation.key)
            #expect(CloseGroupConfirmation(defaults: defaults).isEnabled)
        }
    }
}
