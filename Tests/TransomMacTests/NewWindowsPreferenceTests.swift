import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// D-01, D-19: New Windows survives a re-init; a bad value in the user-writable plist reads and stores as float.
@Suite @MainActor struct NewWindowsPreferenceTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.newWindows.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func aMissingValueIsFloatAndWritesNothing() throws {
        try withDefaults { defaults in
            #expect(NewWindowsPreference(defaults: defaults).value == .float)
            #expect(defaults.object(forKey: NewWindowsPreference.key) == nil)
        }
    }

    @Test(arguments: [("float", NewWindowsMode.float), ("tile", .tile)])
    func aStoredModeLoads(stored: String, mode: NewWindowsMode) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: NewWindowsPreference.key)
            #expect(NewWindowsPreference(defaults: defaults).value == mode)
        }
    }

    @Test func aBadStoredValueIsReplacedByFloat() throws {
        for stored in [7, "nope", true] as [Any] {
            try withDefaults { defaults in
                defaults.set(stored, forKey: NewWindowsPreference.key)
                #expect(NewWindowsPreference(defaults: defaults).value == .float, "\(stored) was accepted")
                #expect(defaults.string(forKey: NewWindowsPreference.key) == "float")
            }
        }
    }

    @Test func settingTheCurrentValueFiresNothingAndWritesNothing() throws {
        try withDefaults { defaults in
            let preference = NewWindowsPreference(defaults: defaults)
            var changes: [NewWindowsMode] = []
            preference.onChange = { changes.append($0) }
            preference.set(.float)
            #expect(changes.isEmpty)
            #expect(defaults.object(forKey: NewWindowsPreference.key) == nil)
        }
    }

    @Test func settingTheOtherValueStoresItAndFiresOnce() throws {
        try withDefaults { defaults in
            let preference = NewWindowsPreference(defaults: defaults)
            var changes: [NewWindowsMode] = []
            preference.onChange = { changes.append($0) }
            preference.set(.tile)
            #expect(preference.value == .tile && changes == [.tile])
            #expect(NewWindowsPreference(defaults: defaults).value == .tile)
        }
    }
}
