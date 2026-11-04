import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// D-07, D-19: Drag to Dock survives a re-init; a bad value in the user-writable plist reads and stores as automatic.
@Suite @MainActor struct DragToDockPreferenceTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.dragToDock.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func aMissingValueIsAutomaticAndWritesNothing() throws {
        try withDefaults { defaults in
            #expect(DragToDockPreference(defaults: defaults).value == .automatic)
            #expect(defaults.object(forKey: DragToDockPreference.key) == nil)
        }
    }

    @Test(arguments: [("automatic", DragToDockMode.automatic), ("holdOption", .holdOption)])
    func aStoredModeLoads(stored: String, mode: DragToDockMode) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: DragToDockPreference.key)
            #expect(DragToDockPreference(defaults: defaults).value == mode)
        }
    }

    @Test func aBadStoredValueIsReplacedByAutomatic() throws {
        for stored in [7, "nope", true] as [Any] {
            try withDefaults { defaults in
                defaults.set(stored, forKey: DragToDockPreference.key)
                #expect(DragToDockPreference(defaults: defaults).value == .automatic, "\(stored) was accepted")
                #expect(defaults.string(forKey: DragToDockPreference.key) == "automatic")
            }
        }
    }

    @Test func settingTheCurrentValueFiresNothingAndWritesNothing() throws {
        try withDefaults { defaults in
            let preference = DragToDockPreference(defaults: defaults)
            var changes: [DragToDockMode] = []
            preference.onChange = { changes.append($0) }
            preference.set(.automatic)
            #expect(changes.isEmpty)
            #expect(defaults.object(forKey: DragToDockPreference.key) == nil)
        }
    }

    @Test func settingTheOtherValueStoresItAndFiresOnce() throws {
        try withDefaults { defaults in
            let preference = DragToDockPreference(defaults: defaults)
            var changes: [DragToDockMode] = []
            preference.onChange = { changes.append($0) }
            preference.set(.holdOption)
            #expect(preference.value == .holdOption && changes == [.holdOption])
            #expect(DragToDockPreference(defaults: defaults).value == .holdOption)
        }
    }
}
