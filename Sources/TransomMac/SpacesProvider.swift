import AppKit
import TransomEngine
import TransomPrivate
import os

/// The live Spaces list (D-12, D-13, D-15): SkyLight's managed-display dictionaries parsed into Engine values.
public enum SpacesProvider {
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "spaces")
    private static var loggedModeDisagreement = false

    /// Nil while the Spaces lookup is off. Call only after `NSApplication.shared` exists: before that
    /// `screensHaveSeparateSpaces` reads false on a separate-Spaces Mac (06-RESEARCH Pitfall 5).
    public static func snapshot() -> SpacesSnapshot? {
        guard let raw = SkyLightSpaces.managedDisplaySpaces(),
              let main = NSScreen.screens.first, let id = Displays.displayID(main), let mainUUID = Displays.uuid(id)
        else { return nil }
        let separate = NSScreen.screensHaveSeparateSpaces
        if let mode = SkyLightSpaces.managementMode(), (mode == 1) != separate, !loggedModeDisagreement {
            loggedModeDisagreement = true
            logger.error("Space management mode \(mode, privacy: .public) disagrees with screensHaveSeparateSpaces \(separate, privacy: .public); using the latter")
        }
        return SpacesSnapshot.parse(raw, mainDisplayUUID: mainUUID, separateSpaces: separate)
    }
}
