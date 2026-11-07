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

    @Test func newWindowsChosenInSettingsFiresOnce() throws {
        try withDefaults { defaults in
            let newWindows = NewWindowsPreference(defaults: defaults)
            var changes: [NewWindowsMode] = []
            newWindows.onChange = { changes.append($0) }
            ArrangingTab.newWindowsBinding(newWindows).wrappedValue = .tile
            ArrangingTab.newWindowsBinding(newWindows).wrappedValue = .tile
            #expect(newWindows.value == .tile)
            #expect(changes == [.tile], "choosing the current mode again fires nothing")
            #expect(NewWindowsPreference(defaults: defaults).value == .tile)
        }
    }

    @Test func dragToDockChosenInSettingsFiresOnce() throws {
        try withDefaults { defaults in
            let dragToDock = DragToDockPreference(defaults: defaults)
            var changes: [DragToDockMode] = []
            dragToDock.onChange = { changes.append($0) }
            ArrangingTab.dragToDockBinding(dragToDock).wrappedValue = .holdOption
            #expect(dragToDock.value == .holdOption)
            #expect(changes == [.holdOption])
            #expect(DragToDockPreference(defaults: defaults).value == .holdOption)
        }
    }

    @Test func theModeFootersAreTheMenuTooltips() {
        for mode in NewWindowsMode.allCases { #expect(ArrangingTab.footer(mode) == MenuCopy.newWindowsTooltip(mode)) }
        for mode in DragToDockMode.allCases { #expect(ArrangingTab.footer(mode) == MenuCopy.dragToDockTooltip(mode)) }
    }

    @Test func turningAFeatureOffIsSeenBySettings() async {
        let (defaults, cleanUp) = ConflictControllerTests.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = ["GloballyEnabled": .bool(true), "EnableStandardClickToShowDesktop": .bool(false)]
        let conflicts = ConflictController(store: prefs, defaults: defaults, osMajor: 14, readBackDelay: .zero)
        let told = Count()
        withObservationTracking({ _ = conflicts.active }, onChange: { told.value += 1 })
        conflicts.poll()
        #expect(told.value == 1)
        #expect(conflicts.active == [.stageManager])

        withObservationTracking({ _ = conflicts.active }, onChange: { told.value += 1 })
        await conflicts.turnOff(.stageManager)
        #expect(told.value == 2)
        #expect(!conflicts.active.contains(.stageManager))
    }

    @Test func theFeatureRowsAreTheThreeConflictsInOrder() async {
        let (defaults, cleanUp) = ConflictControllerTests.defaults()
        defer { cleanUp() }
        let prefs = MemoryPreferences()
        prefs.values = ["GloballyEnabled": .bool(true), "EnableStandardClickToShowDesktop": .bool(false)]
        let conflicts = ConflictController(store: prefs, defaults: defaults, osMajor: 14, readBackDelay: .zero)
        conflicts.poll()
        let rows = ArrangingTab.featureRows(conflicts)
        #expect(rows.map(\.conflict) == [.stageManager, .edgeTiling, .clickWallpaper])
        #expect(rows.map(\.name) == ["Stage Manager", "macOS edge tiling", "Click wallpaper to reveal desktop"])
        #expect(rows.map(\.detail) == Conflict.allCases.map(ConflictCopy.tooltip))
        #expect(rows.map(\.isOn) == [true, false, false])
        #expect(!conflicts.canRestore, "nothing turned off yet, nothing to restore")

        await conflicts.turnOff(.stageManager)
        #expect(ArrangingTab.featureRows(conflicts).map(\.isOn) == [false, false, false])
        #expect(conflicts.canRestore)
    }
}
