import Foundation
import Observation
import TransomEngine
@testable import TransomMac
import Testing

/// Counts observation callbacks, which arrive in a `@Sendable` closure; the change fires synchronously on this actor.
private final class Count: @unchecked Sendable { var value = 0 }

/// D-02, SHIP-01: Settings ▸ Arranging and the menu share one store, and a Settings write takes the menu's path.
@Suite @MainActor struct SettingsModelTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func aGapChosenInSettingsFiresTheSameChangeAsTheMenu() throws {
        try withDefaults { defaults in
            let gaps = GapPreference(defaults: defaults)
            var changes: [Double] = []
            gaps.onChange = { changes.append($0) }
            ArrangingTab.gapBinding(gaps).wrappedValue = 16
            #expect(gaps.value == 16)
            #expect(defaults.double(forKey: GapPreference.key) == 16)
            #expect(changes == [16])
        }
    }

    @Test func aGapChosenInTheMenuIsSeenBySettings() throws {
        try withDefaults { defaults in
            let gaps = GapPreference(defaults: defaults)
            let told = Count()
            withObservationTracking({ _ = gaps.value }, onChange: { told.value += 1 })
            _ = gaps.set(4)
            #expect(told.value == 1)
            #expect(ArrangingTab.gapBinding(gaps).wrappedValue == 4)
        }
    }
}
