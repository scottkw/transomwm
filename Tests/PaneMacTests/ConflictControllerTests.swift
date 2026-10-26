import Foundation
import PaneEngine
@testable import PaneMac
import Testing

/// An in-memory com.apple.WindowManager. Keys in `stuck` ignore writes, as a managed or refused setting would.
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
}
