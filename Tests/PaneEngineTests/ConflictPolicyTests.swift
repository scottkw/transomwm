import PaneEngine
import Testing

/// SAFE-04, D-19, D-22, Pitfall 12: which macOS features are on, read from the WindowManager preference values.
@Suite struct ConflictPolicyTests {
    @Test func stageManagerIsOnOnlyWhenGloballyEnabledIsTrue() {
        #expect(ConflictPolicy.active(values: ["GloballyEnabled": .bool(true)], osMajor: 14).contains(.stageManager))
        #expect(!ConflictPolicy.active(values: ["GloballyEnabled": .absent], osMajor: 14).contains(.stageManager))
        #expect(!ConflictPolicy.active(values: [:], osMajor: 14).contains(.stageManager))
        #expect(!ConflictPolicy.active(values: ["GloballyEnabled": .bool(false)], osMajor: 14).contains(.stageManager))
    }

    @Test func aValueThatIsNotABooleanCountsAsOffAndIsReported() {
        let values: [String: PrefValue] = ["GloballyEnabled": .other, "EnableStandardClickToShowDesktop": .bool(false)]
        #expect(!ConflictPolicy.active(values: values, osMajor: 14).contains(.stageManager))
        #expect(ConflictPolicy.badKeys(values: values) == ["GloballyEnabled"])
    }

    @Test func theKeyTableIsFixed() {
        #expect(ConflictPolicy.keys(for: .stageManager) == ["GloballyEnabled"])
        #expect(ConflictPolicy.keys(for: .edgeTiling) == ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"])
        #expect(ConflictPolicy.keys(for: .clickWallpaper) == ["EnableStandardClickToShowDesktop"])
        #expect(Conflict.allCases == [.stageManager, .edgeTiling, .clickWallpaper])
    }

    @Test func turnOffWritesFalseToTheFeaturesKeysOnly() {
        #expect(ConflictPolicy.turnOffWrites(for: .stageManager) == ["GloballyEnabled": false])
    }
}
