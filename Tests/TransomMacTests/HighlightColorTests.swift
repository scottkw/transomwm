import AppKit
import Foundation
@testable import TransomMac
import Testing

/// D-03, T-09-14: the highlight is the macOS accent unless a valid "#RRGGBB" override is stored.
@Suite @MainActor struct HighlightColorTests {
    /// A throwaway defaults domain, never the user's.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.eightabyte.transom.tests.highlight.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func withNoOverrideItIsTheSystemAccent() throws {
        try withDefaults { defaults in
            #expect(HighlightColor.current(in: defaults) == NSColor.controlAccentColor)
        }
    }

    @Test func aCustomColorRoundTripsAsHex() throws {
        try withDefaults { defaults in
            HighlightColor.set(NSColor(srgbRed: 1, green: 0x80 / 255.0, blue: 0, alpha: 1), in: defaults)
            #expect(defaults.string(forKey: HighlightColor.key) == "#FF8000")
            #expect(HighlightColor.hex(HighlightColor.current(in: defaults)) == "#FF8000")
            let lower = try #require(HighlightColor.parse("#ff8000"))
            #expect(lower.red == 1 && lower.green == 128.0 / 255 && lower.blue == 0)
            HighlightColor.set(nil, in: defaults)
            #expect(defaults.object(forKey: HighlightColor.key) == nil)
        }
    }

    @Test(arguments: ["blue", "#12345", "#GGGGGG", "#+12345", "FF8000", "#FF80001"])
    func anInvalidStoredValueIsRemovedAndTheAccentUsed(_ value: String) throws {
        try withDefaults { defaults in
            defaults.set(value, forKey: HighlightColor.key)
            #expect(HighlightColor.current(in: defaults) == NSColor.controlAccentColor)
            #expect(defaults.object(forKey: HighlightColor.key) == nil)
        }
    }

    @Test func aNonStringStoredValueIsRemoved() throws {
        try withDefaults { defaults in
            defaults.set(42, forKey: HighlightColor.key)
            #expect(HighlightColor.current(in: defaults) == NSColor.controlAccentColor)
            #expect(defaults.object(forKey: HighlightColor.key) == nil)
        }
    }

    @Test func settingPostsDidChange() throws {
        try withDefaults { defaults in
            final class Count: @unchecked Sendable { var value = 0 }
            let count = Count()
            let observer = NotificationCenter.default.addObserver(forName: HighlightColor.didChange, object: nil, queue: nil) { _ in
                count.value += 1
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            HighlightColor.set(.systemPink, in: defaults)
            HighlightColor.set(nil, in: defaults)
            #expect(count.value == 2)
        }
    }
}
