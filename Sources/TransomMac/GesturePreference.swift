import Foundation
import Observation
import os

/// Settings ▸ Zoom & Gestures ▸ Trackpad (09 UI-SPEC Tab 3): ⌥-held pinch and pan, and bare pinch and pan on the
/// wallpaper. Both default on, today's behaviour. The plist is user-writable (T-09-10): a value that is not a Bool is
/// logged and removed, the GapPreference rule. The tap never reads these: GestureController publishes them.
@Observable @MainActor final class GesturePreference {
    static let optionKey = "gestures.option"
    static let wallpaperKey = "gestures.wallpaper"
    private(set) var takesOption: Bool
    private(set) var takesWallpaper: Bool
    /// Fires after every change.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        takesOption = Self.read(Self.optionKey, defaults)
        takesWallpaper = Self.read(Self.wallpaperKey, defaults)
    }

    func setOption(_ on: Bool) {
        takesOption = on
        defaults.set(on, forKey: Self.optionKey)
        onChange?()
    }

    func setWallpaper(_ on: Bool) {
        takesWallpaper = on
        defaults.set(on, forKey: Self.wallpaperKey)
        onChange?()
    }

    private static func read(_ key: String, _ defaults: UserDefaults) -> Bool {
        guard let stored = defaults.object(forKey: key) else { return true }
        // A number or a string is not a switch, even when it would convert to one.
        if let number = stored as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        logger.error("removed a stored \(key, privacy: .public) that is not on or off")
        defaults.removeObject(forKey: key)
        return true
    }
}
