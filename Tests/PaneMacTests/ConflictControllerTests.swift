import Foundation
import PaneEngine
@testable import PaneMac
import Testing

/// An in-memory stand-in for the WindowManager preferences. Keys in `stuck` ignore writes, as a managed or refused setting would.
@MainActor final class MemoryPreferences: PreferencesStore {
    var values: [String: PrefValue] = [:]
    var stuck: Set<String> = []
    private(set) var writes: [String] = []

    func value(_ key: String) -> PrefValue { values[key] ?? .absent }

    func set(_ key: String, _ value: Bool?) {
        writes.append(key)
        guard !stuck.contains(key) else { return }
        values[key] = value.map(PrefValue.bool) ?? .absent
    }

    func synchronize() {}
}

/// SAFE-04, D-19, D-20, D-22: the poll, Stage Manager's pause, and Turn Off with its read-back.
@Suite @MainActor struct ConflictControllerTests {
    /// A throwaway defaults suite, never Pane's real one.
    static func defaults() -> (UserDefaults, () -> Void) {
        let suite = "com.eightabyte.pane.tests.conflicts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func stageManagerOnPausesAndItsMenuLineTurnsItOffAndResumes() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = ["GloballyEnabled": .bool(true), "EnableStandardClickToShowDesktop": .bool(false)]
        let controller = ConflictController(store: prefs, defaults: defaults, osMajor: 14, readBackDelay: .zero)
        var paused: [Bool] = []
        controller.setStageManagerPaused = { paused.append($0) }
        controller.poll()
        #expect(paused == [true])
        #expect(controller.active == [.stageManager])
        controller.poll()
        #expect(paused == [true], "an unchanged poll sends nothing")

        await controller.turnOff(.stageManager)
        #expect(controller.originals == ["GloballyEnabled": .bool(true)])
        #expect(prefs.values["GloballyEnabled"] == .bool(false))
        #expect(paused == [true, false])
        #expect(controller.active.isEmpty)
        // The originals survive a relaunch.
        #expect(ConflictController(store: prefs, defaults: defaults, osMajor: 14).originals == ["GloballyEnabled": .bool(true)])
    }

    @Test func stageManagerOffAtLaunchStillReportsUnpaused() {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        let controller = ConflictController(store: prefs, defaults: defaults, osMajor: 14, readBackDelay: .zero)
        var paused: [Bool] = []
        controller.setStageManagerPaused = { paused.append($0) }
        controller.poll()
        #expect(paused == [false])
        #expect(prefs.writes.isEmpty, "a poll never writes")
    }

    @Test func anOriginalIsRecordedOnceAndNeverOverwritten() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = ["EnableTilingByEdgeDrag": .bool(true)]  // top tiling absent
        let controller = ConflictController(store: prefs, defaults: defaults, osMajor: 15, readBackDelay: .zero)
        controller.poll()
        await controller.turnOff(.edgeTiling)
        #expect(controller.originals == ["EnableTilingByEdgeDrag": .bool(true), "EnableTopTilingByEdgeDrag": .absent])
        prefs.values["EnableTilingByEdgeDrag"] = .bool(true)  // the user turns it back on in System Settings
        await controller.turnOff(.edgeTiling)
        #expect(controller.originals == ["EnableTilingByEdgeDrag": .bool(true), "EnableTopTilingByEdgeDrag": .absent])
        #expect(!prefs.writes.contains("EnableTilingOptionAccelerator"))
    }

    @Test func aWriteThatDoesNotTakeOpensDesktopAndDockAndShowsN7() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.stuck = ["EnableTopTilingByEdgeDrag"]
        let controller = ConflictController(store: prefs, defaults: defaults, osMajor: 15, readBackDelay: .zero)
        var opened: [URL] = []
        var posted: [Notice] = []
        controller.openSettings = { opened.append($0) }
        controller.post = { posted.append($0) }
        controller.poll()
        await controller.turnOff(.edgeTiling)
        #expect(opened == [URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!])
        #expect(posted == [.turnOffFailed(.edgeTiling)])
        #expect(controller.active.contains(.edgeTiling))

        opened = []
        posted = []
        await controller.turnOff(.clickWallpaper)
        #expect(opened.isEmpty && posted.isEmpty, "a write that takes opens nothing")
    }

    /// D-21: the only way originals come back, and the only time Pane writes a true.
    @Test func restoreWritesEveryOriginalBackDeletingAbsentKeysAndShowsN8() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = ["GloballyEnabled": .bool(true), "EnableStandardClickToShowDesktop": .bool(true)]
        let controller = ConflictController(store: prefs, defaults: defaults, osMajor: 15, readBackDelay: .zero)
        var posted: [Notice] = []
        controller.post = { posted.append($0) }
        controller.poll()
        #expect(!controller.canRestore)
        controller.restore()
        #expect(prefs.writes.isEmpty && posted.isEmpty, "nothing recorded, nothing restored")

        await controller.turnOff(.stageManager)
        await controller.turnOff(.edgeTiling)
        #expect(controller.canRestore)
        controller.restore()
        #expect(prefs.values["GloballyEnabled"] == .bool(true))
        #expect(prefs.values["EnableTilingByEdgeDrag"] == .absent && prefs.values["EnableTopTilingByEdgeDrag"] == .absent)
        #expect(prefs.values["EnableStandardClickToShowDesktop"] == .bool(true), "never turned off, never touched")
        #expect(posted == [.settingsRestored])
        #expect(!controller.canRestore)
        #expect(controller.originals.isEmpty)
        #expect(ConflictController(store: prefs, defaults: defaults, osMajor: 15).originals.isEmpty, "cleared on disk too")
        #expect(controller.active.contains(.stageManager))
    }

    /// T-03-45: a crafted plist cannot make Restore write any other key.
    @Test func recordedOriginalsOutsideTheAllowListAreDropped() throws {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let crafted: [String: PrefValue] = ["GloballyEnabled": .bool(true), "AppleShowAllFiles": .bool(true), "EnableTilingByEdgeDrag": .other]
        defaults.set(try JSONEncoder().encode(crafted), forKey: ConflictController.originalsKey)
        #expect(ConflictController(store: MemoryPreferences(), defaults: defaults, osMajor: 15).originals == ["GloballyEnabled": .bool(true)])
        defaults.set(Data("not json".utf8), forKey: ConflictController.originalsKey)
        #expect(ConflictController(store: MemoryPreferences(), defaults: defaults, osMajor: 15).originals.isEmpty)
    }

    /// A controller whose alerts are recorded instead of shown.
    private static func alerting(_ prefs: MemoryPreferences, _ defaults: UserDefaults, presented: @escaping (Conflict) -> Void)
        -> ConflictController
    {
        let controller = ConflictController(store: prefs, defaults: defaults, osMajor: 15, readBackDelay: .zero)
        controller.presentAlert = presented
        return controller
    }

    private static let everythingOff: [String: PrefValue] = [
        "EnableTilingByEdgeDrag": .bool(false), "EnableTopTilingByEdgeDrag": .bool(false), "EnableStandardClickToShowDesktop": .bool(false),
    ]

    @Test func twoFeaturesOnAtOnceAlertOneAtATimeInOrder() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = Self.everythingOff.merging(["GloballyEnabled": .bool(true), "EnableStandardClickToShowDesktop": .bool(true)]) { $1 }
        var presented: [Conflict] = []
        let controller = Self.alerting(prefs, defaults) { presented.append($0) }
        controller.poll()
        #expect(presented == [.stageManager])
        controller.poll()
        #expect(presented == [.stageManager], "one alert per episode, one at a time")
        await controller.answer(.stageManager, turnOff: false)
        #expect(presented == [.stageManager, .clickWallpaper])
        await controller.answer(.clickWallpaper, turnOff: true)
        #expect(prefs.values["EnableStandardClickToShowDesktop"] == .bool(false), "Turn Off is the menu line's path")
        #expect(controller.shownAlert == nil)
    }

    @Test func notNowIsRememberedAcrossRelaunchesWhileTheFeatureStaysOn() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = Self.everythingOff.merging(["GloballyEnabled": .bool(true)]) { $1 }
        var presented: [Conflict] = []
        let first = Self.alerting(prefs, defaults) { presented.append($0) }
        first.poll()
        await first.answer(.stageManager, turnOff: false)
        #expect(defaults.stringArray(forKey: ConflictController.notNowKey) == ["stageManager"])

        let relaunched = Self.alerting(prefs, defaults) { presented.append($0) }
        relaunched.poll()
        #expect(presented == [.stageManager], "no second alert after a relaunch")

        prefs.values["GloballyEnabled"] = .bool(false)
        relaunched.poll()
        #expect(defaults.stringArray(forKey: ConflictController.notNowKey) == [], "off ends the episode")
        prefs.values["GloballyEnabled"] = .bool(true)
        relaunched.poll()
        #expect(presented == [.stageManager, .stageManager], "the next episode alerts again")
    }

    @Test func aDueAlertWaitsForTheDragToEnd() {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = Self.everythingOff.merging(["GloballyEnabled": .bool(true)]) { $1 }
        var presented: [Conflict] = []
        var dragging = true
        let controller = Self.alerting(prefs, defaults) { presented.append($0) }
        controller.isDragging = { dragging }
        controller.poll()
        #expect(presented.isEmpty)
        dragging = false
        controller.showNextAlert()
        #expect(presented == [.stageManager])
    }

    @Test func aFeaturePaneTurnedBackOnRaisesNoAlert() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = Self.everythingOff.merging(["GloballyEnabled": .bool(true)]) { $1 }
        var presented: [Conflict] = []
        let controller = Self.alerting(prefs, defaults) { presented.append($0) }
        controller.poll()
        await controller.answer(.stageManager, turnOff: true)
        #expect(!controller.active.contains(.stageManager))
        controller.restore()
        #expect(controller.active.contains(.stageManager))
        #expect(presented == [.stageManager], "Restore turned it back on, so no alert")
    }

    @Test func anAlertWhoseFeatureTurnsOffIsWithdrawn() async {
        let (defaults, cleanUp) = Self.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = Self.everythingOff.merging(["GloballyEnabled": .bool(true)]) { $1 }
        let controller = Self.alerting(prefs, defaults) { _ in }
        controller.poll()
        #expect(controller.shownAlert == .stageManager)
        await controller.turnOff(.stageManager)  // from the menu line while the alert is up
        #expect(controller.shownAlert == nil)
    }
}
