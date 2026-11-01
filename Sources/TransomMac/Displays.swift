import AppKit
import TransomEngine
import TransomModel
import TransomPrivate
import os

/// The current displays, keyed by UUID (D-18). A `CGDirectDisplayID` is not durable across reconnects
/// (Pitfall 14), so a display without a UUID is skipped rather than keyed by index.
public enum Displays {
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "displays")

    /// `NSScreen.screens` in order (the primary first). `frame` from `CGDisplayBounds` is already top-left;
    /// `visibleFrame` is AppKit and goes through `Coordinates`. `currentSpaceID` comes from SkyLight, nil while the
    /// Spaces lookup is off (one desk per display, A7).
    public static func current() -> [DisplayInfo] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = Double(primary.frame.height)
        return screens.compactMap { screen in
            guard let id = displayID(screen), let uuid = uuid(id) else {
                logger.error("a display has no UUID; not tracked")
                return nil
            }
            let bounds = CGDisplayBounds(id)
            let visible = screen.visibleFrame
            return DisplayInfo(
                uuid: uuid,
                frame: Rect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height),
                visibleFrame: Coordinates.topLeft(
                    fromAppKit: Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
                    primaryHeight: primaryHeight
                ),
                currentSpaceID: SkyLightSpaces.currentSpace(displayUUID: uuid)
            )
        }
    }

    /// UUID → `NSScreen.localizedName`, for the Tracked Windows Display column.
    public static func localizedNames() -> [String: String] {
        var names: [String: String] = [:]
        for screen in NSScreen.screens {
            if let id = displayID(screen), let uuid = uuid(id) { names[uuid] = screen.localizedName }
        }
        return names
    }

    /// The screen with that display UUID, or nil when it is gone.
    public static func screen(uuid: String) -> NSScreen? {
        NSScreen.screens.first { screen in displayID(screen).flatMap(Self.uuid) == uuid }
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func uuid(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

extension NSWindow {
    private static let spacesLogger = Logger(subsystem: "com.eightabyte.transom", category: "spaces")

    /// True, with a notice, when this panel was ordered in before but is no longer on the shown Space; the caller then
    /// replaces it. macOS 27.2 can leave a .canJoinAllSpaces panel on the Space shown during a screen lock (host
    /// 2026-11-01): ordered in again it stays there, off screen, until a new panel is made, as a relaunch did. A deferred
    /// panel never ordered in has no window number yet and also reports isOnActiveSpace false; it is fine.
    func leftOnAnotherSpace(_ name: String) -> Bool {
        guard windowNumber > 0, !isOnActiveSpace else { return false }
        Self.spacesLogger.notice("\(name, privacy: .public) was off the shown Space; made a new one")
        return true
    }
}
