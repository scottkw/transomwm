import Foundation
import Observation
import TransomEngine
import os

/// New Windows (D-01, D-19), kept in UserDefaults. The plist is user-writable: anything but the two modes is logged and
/// replaced by the default.
@Observable @MainActor final class NewWindowsPreference {
    static let key = "newWindows"
    static let defaultValue = NewWindowsMode.float
    private(set) var value: NewWindowsMode
    /// Fires after every change; choosing the current value is not one.
    @ObservationIgnored var onChange: ((NewWindowsMode) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = Self.defaultValue
        guard let stored = defaults.object(forKey: Self.key) else { return }
        if let mode = (stored as? String).flatMap(NewWindowsMode.init(rawValue:)) {
            value = mode
        } else {
            Self.logger.error("replaced a stored newWindows outside the allowed values with \(Self.defaultValue.rawValue, privacy: .public)")
            defaults.set(Self.defaultValue.rawValue, forKey: Self.key)
        }
    }

    func set(_ mode: NewWindowsMode) {
        guard mode != value else { return }
        value = mode
        defaults.set(mode.rawValue, forKey: Self.key)
        Self.logger.info("new windows: \(mode.rawValue, privacy: .public)")
        onChange?(mode)
    }
}
