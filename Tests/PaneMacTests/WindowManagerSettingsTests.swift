import Foundation
import PaneEngine
@testable import PaneMac
import Testing

/// T-03-47: a test-only domain, cleaned before and after; the real WindowManager domain is never named in Tests.
@Suite(.serialized) @MainActor struct WindowManagerSettingsTests {
    private static let domain = "com.eightabyte.pane.tests.windowmanager"
    private static let key = "GloballyEnabled"

    private func clean() {
        CFPreferencesSetAppValue(Self.key as CFString, nil, Self.domain as CFString)
        _ = CFPreferencesAppSynchronize(Self.domain as CFString)
    }

    @Test func aBooleanRoundTripsAndNilDeletesTheKey() {
        clean()
        defer { clean() }
        let store = CFPreferencesStore(domain: Self.domain)
        #expect(store.value(Self.key) == .absent)
        store.set(Self.key, true)
        store.synchronize()
        #expect(store.value(Self.key) == .bool(true))
        store.set(Self.key, false)
        #expect(store.value(Self.key) == .bool(false))
        store.set(Self.key, nil)
        #expect(store.value(Self.key) == .absent)
    }

    @Test func aStringReadsAsOther() {
        clean()
        defer { clean() }
        CFPreferencesSetAppValue(Self.key as CFString, "yes" as CFString, Self.domain as CFString)
        _ = CFPreferencesAppSynchronize(Self.domain as CFString)
        #expect(CFPreferencesStore(domain: Self.domain).value(Self.key) == .other)
    }

    @Test func aNumberIsNotABoolean() {
        clean()
        defer { clean() }
        CFPreferencesSetAppValue(Self.key as CFString, 1 as CFNumber, Self.domain as CFString)
        _ = CFPreferencesAppSynchronize(Self.domain as CFString)
        #expect(CFPreferencesStore(domain: Self.domain).value(Self.key) == .other)
    }
}
