import TransomEngine
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

    @Test func edgeTilingNeverExistsOnMacOS14() {
        for value in [PrefValue.absent, .bool(true), .bool(false), .other] {
            let values = ["EnableTilingByEdgeDrag": value, "EnableTopTilingByEdgeDrag": value]
            #expect(!ConflictPolicy.active(values: values, osMajor: 14).contains(.edgeTiling))
        }
    }

    @Test func edgeTilingOnMacOS15IsOnUnlessBothKeysAreFalse() {
        #expect(ConflictPolicy.active(values: [:], osMajor: 15).contains(.edgeTiling), "absent is on")
        #expect(ConflictPolicy.active(values: ["EnableTilingByEdgeDrag": .bool(false)], osMajor: 15).contains(.edgeTiling),
            "top tiling is still on")
        let off: [String: PrefValue] = ["EnableTilingByEdgeDrag": .bool(false), "EnableTopTilingByEdgeDrag": .bool(false)]
        #expect(!ConflictPolicy.active(values: off, osMajor: 15).contains(.edgeTiling))
        #expect(!ConflictPolicy.active(values: off, osMajor: 27).contains(.edgeTiling))
    }

    @Test func clickWallpaperIsOnWhenAbsentOrTrue() {
        #expect(ConflictPolicy.active(values: [:], osMajor: 14).contains(.clickWallpaper))
        #expect(ConflictPolicy.active(values: ["EnableStandardClickToShowDesktop": .bool(true)], osMajor: 14).contains(.clickWallpaper))
        #expect(!ConflictPolicy.active(values: ["EnableStandardClickToShowDesktop": .bool(false)], osMajor: 14).contains(.clickWallpaper))
    }

    /// D-05: hold-⌥-to-tile is the user's, never in a write plan.
    @Test func turningOffEdgeTilingWritesBothEdgeKeysAndNeverTheOptionAccelerator() {
        #expect(ConflictPolicy.turnOffWrites(for: .edgeTiling) == ["EnableTilingByEdgeDrag": false, "EnableTopTilingByEdgeDrag": false])
        #expect(ConflictPolicy.turnOffWrites(for: .clickWallpaper) == ["EnableStandardClickToShowDesktop": false])
        for conflict in Conflict.allCases {
            #expect(ConflictPolicy.turnOffWrites(for: conflict)["EnableTilingOptionAccelerator"] == nil)
        }
        #expect(!ConflictPolicy.allKeys.contains("EnableTilingOptionAccelerator"))
    }

    @Test func restoreWritesTheBooleanBackAndDeletesAKeyThatWasAbsent() {
        let writes = ConflictPolicy.restoreWrites(originals: ["GloballyEnabled": .bool(true), "EnableTilingByEdgeDrag": .absent])
        let expected: [String: Bool?] = ["GloballyEnabled": true, "EnableTilingByEdgeDrag": nil]
        #expect(writes == expected)
    }

    @Test func restoreNeverWritesAKeyOutsideTheAllowList() {
        #expect(ConflictPolicy.restoreWrites(originals: ["SomethingElse": .bool(true), "GloballyEnabled": .other]).isEmpty)
    }

    /// D-19: one alert per on-episode.
    @Test func anAlertIsDueOnlyWhenAFeatureTurnsOn() {
        #expect(ConflictPolicy.alertsDue(active: [.stageManager], previous: [], notNow: [], restoredByTransom: []) == [.stageManager],
            "first launch with it on")
        #expect(ConflictPolicy.alertsDue(active: [.stageManager], previous: [.stageManager], notNow: [], restoredByTransom: []).isEmpty,
            "already on at the last poll")
        #expect(ConflictPolicy.alertsDue(active: [.stageManager], previous: [], notNow: [.stageManager], restoredByTransom: []).isEmpty,
            "Not Now")
        #expect(ConflictPolicy.alertsDue(active: [.stageManager], previous: [], notNow: [], restoredByTransom: [.stageManager]).isEmpty,
            "Transom turned it back on")
        #expect(ConflictPolicy.alertsDue(active: [], previous: [.stageManager], notNow: [], restoredByTransom: []).isEmpty)
    }

    @Test func dueAlertsComeInTheFixedOrder() {
        #expect(ConflictPolicy.alertsDue(active: [.clickWallpaper, .stageManager, .edgeTiling], previous: [], notNow: [], restoredByTransom: [])
            == [.stageManager, .edgeTiling, .clickWallpaper])
    }
}
