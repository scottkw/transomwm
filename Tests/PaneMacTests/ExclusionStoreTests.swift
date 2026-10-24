import Foundation
import PaneMac
import Testing

@MainActor @Suite struct ExclusionStoreTests {
    /// A private defaults suite per test, removed afterwards.
    final class Suite {
        let name = "pane-test-\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { UserDefaults().removePersistentDomain(forName: name) }
    }

    @Test func aFreshStoreIsEmpty() {
        let suite = Suite()
        #expect(ExclusionStore(defaults: suite.defaults).bundleIDs.isEmpty)
    }

    @Test func matchingIsCaseInsensitiveAndExact() throws {
        let suite = Suite()
        let store = ExclusionStore(defaults: suite.defaults)
        try store.add("com.apple.Safari")
        #expect(store.contains("com.apple.safari"))
        #expect(store.contains("com.apple.Safari"))
        #expect(!store.contains("com.apple.SafariTechnologyPreview"))
        #expect(store.bundleIDs == ["com.apple.Safari"])
    }

    @Test func toggleTwiceRestoresTheOriginalList() throws {
        let suite = Suite()
        let store = ExclusionStore(defaults: suite.defaults)
        try store.add("com.example.a")
        let original = store.bundleIDs
        try store.toggle("com.apple.Safari")
        #expect(store.contains("com.apple.Safari"))
        try store.toggle("com.apple.Safari")
        #expect(store.bundleIDs == original)
    }

    @Test(arguments: ["", "   ", "unbundled:Foo", String(repeating: "a", count: 256), "com.apple/Safari"])
    func invalidIDsAreRejected(_ bad: String) throws {
        let suite = Suite()
        let store = ExclusionStore(defaults: suite.defaults)
        try store.add("com.example.keep")
        #expect(throws: ExclusionError.invalidBundleID) { try store.add(bad) }
        #expect(throws: ExclusionError.invalidBundleID) { try store.toggle(bad) }
        #expect(store.bundleIDs == ["com.example.keep"])
    }

    @Test func a255CharacterIDIsAccepted() throws {
        let suite = Suite()
        let store = ExclusionStore(defaults: suite.defaults)
        let id = String(repeating: "a", count: 255)
        try store.add(id)
        #expect(store.contains(id))
    }

    @Test func invalidStoredEntriesAreDroppedOnLoad() {
        let suite = Suite()
        suite.defaults.set(["com.apple.Safari", "", "bad id"], forKey: ExclusionStore.key)
        #expect(ExclusionStore(defaults: suite.defaults).bundleIDs == ["com.apple.Safari"])
    }

    @Test func entriesSurviveARelaunch() throws {
        let suite = Suite()
        try ExclusionStore(defaults: suite.defaults).add("com.apple.Safari")
        #expect(ExclusionStore(defaults: suite.defaults).contains("com.apple.Safari"))
    }

    @Test func onChangeFiresAfterEachSuccessfulMutation() throws {
        let suite = Suite()
        let store = ExclusionStore(defaults: suite.defaults)
        var changes = 0
        store.onChange = { changes += 1 }
        try store.add("com.apple.Safari")
        try? store.add("bad id")
        store.remove("com.apple.Safari")
        #expect(changes == 2)
    }

    @Test func entriesSortByDisplayNameThenBundleID() {
        let suite = Suite()
        let store = ExclusionStore(defaults: suite.defaults)
        for id in ["a.app", "b.app", "c.app"] { try? store.add(id) }
        let entries = store.sortedEntries(displayNames: ["b.app": "alpha", "a.app": "Beta"])
        #expect(entries.map(\.bundleID) == ["b.app", "a.app", "c.app"])
        #expect(entries.map(\.title) == ["alpha", "Beta", "c.app"])
    }
}
