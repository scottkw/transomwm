import Foundation
@testable import TransomMac
import Testing

/// D-27, TILE-04, T-03-25: the gap is one of six values; anything else in the user-writable plist reads as 8.
@Suite @MainActor struct GapPreferenceTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.gap.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func theDefaultIs8() throws {
        try withDefaults { defaults in
            #expect(GapPreference(defaults: defaults).value == 8)
            #expect(GapPreference.allowed == [0, 4, 8, 12, 16, 24])
        }
    }

    @Test func anAllowedValuePersistsAndNotifies() throws {
        try withDefaults { defaults in
            let gaps = GapPreference(defaults: defaults)
            var changes: [Double] = []
            gaps.onChange = { changes.append($0) }
            #expect(gaps.set(16))
            #expect(gaps.value == 16 && changes == [16])
            #expect(GapPreference(defaults: defaults).value == 16)
        }
    }

    @Test func aValueOutsideTheListIsRefused() throws {
        try withDefaults { defaults in
            let gaps = GapPreference(defaults: defaults)
            var changes: [Double] = []
            gaps.onChange = { changes.append($0) }
            #expect(!gaps.set(5))
            #expect(gaps.value == 8 && changes.isEmpty)
        }
    }

    @Test func aBadStoredValueReadsAs8() throws {
        for stored in [7, "12", -4.0, 1e9, true] as [Any] {
            try withDefaults { defaults in
                defaults.set(stored, forKey: GapPreference.key)
                #expect(GapPreference(defaults: defaults).value == 8, "\(stored) was accepted")
            }
        }
    }
}
