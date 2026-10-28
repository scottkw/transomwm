import TransomEngine
import TransomMac
import Testing

/// UI-SPEC Surface 1 (conflict lines) and Surface 5 (alerts), word for word.
@Suite struct ConflictCopyTests {
    @Test func menuTitles() {
        #expect(ConflictCopy.menuTitle(.stageManager) == "Turn Off Stage Manager")
        #expect(ConflictCopy.menuTitle(.edgeTiling) == "Turn Off macOS Edge Tiling")
        #expect(ConflictCopy.menuTitle(.clickWallpaper) == "Turn Off Click Wallpaper to Reveal Desktop")
        #expect(ConflictCopy.imageDescription == "Conflict")
        #expect(ConflictCopy.restoreItem == "Restore macOS Window Settings")
    }

    @Test func tooltips() {
        #expect(ConflictCopy.tooltip(.stageManager) == "Stage Manager moves windows by itself, so Transom has paused arranging.")
        #expect(ConflictCopy.tooltip(.edgeTiling) == "macOS tiles windows dragged to screen edges, which competes with Transom's docking.")
        #expect(ConflictCopy.tooltip(.clickWallpaper) == "Clicking the wallpaper or a gap between windows moves every window off screen.")
    }

    @Test func alertText() {
        #expect(ConflictCopy.alertMessage(.stageManager) == "Turn off Stage Manager?")
        #expect(ConflictCopy.alertInfo(.stageManager)
            == "Stage Manager moves and groups windows by itself, so Transom has paused arranging. Turning it off lets Transom arrange your windows again. You can turn it back on with Restore macOS Window Settings in the Transom menu.")
        #expect(ConflictCopy.alertMessage(.edgeTiling) == "Turn off macOS edge tiling?")
        #expect(ConflictCopy.alertInfo(.edgeTiling)
            == "macOS also tiles a window when you drag it to a screen edge or the menu bar, so a drag meant for Transom can be tiled by macOS instead. Transom keeps working either way. You can turn macOS tiling back on with Restore macOS Window Settings in the Transom menu.")
        #expect(ConflictCopy.alertMessage(.clickWallpaper) == "Turn off Click Wallpaper to Reveal Desktop?")
        #expect(ConflictCopy.alertInfo(.clickWallpaper)
            == "With this on, clicking the wallpaper, including a gap between docked windows, moves every window off screen. Turning it off sets it to Only in Stage Manager. You can change it back with Restore macOS Window Settings in the Transom menu.")
        #expect(ConflictCopy.turnOffButton == "Turn Off")
        #expect(ConflictCopy.notNowButton == "Not Now")
    }

    @Test func featureNamesForTheFailureToast() {
        #expect(ConflictCopy.featureName(.stageManager) == "Stage Manager")
        #expect(ConflictCopy.featureName(.edgeTiling) == "macOS edge tiling")
        #expect(ConflictCopy.featureName(.clickWallpaper) == "Click Wallpaper to Reveal Desktop")
    }
}
