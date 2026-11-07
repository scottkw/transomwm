import Foundation
import Observation
import os

/// The gap between tiles (D-27, TILE-04), kept in UserDefaults. The plist is user-writable (T-03-25): only the six
/// allowed values are accepted; anything else is logged and replaced by the default. Observable so Settings and the
/// menu read one value (D-02).
@Observable @MainActor final class GapPreference {
    static let key = "gap"
    static let allowed: [Double] = [0, 4, 8, 12, 16, 24]
    static let defaultValue: Double = 8
    private(set) var value: Double
    /// Fires after every accepted change.
    @ObservationIgnored var onChange: ((Double) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = Self.defaultValue
        guard let stored = defaults.object(forKey: Self.key) else { return }
        // A string or a Bool is not a gap, even when it would convert to one.
        if let number = stored as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), Self.allowed.contains(number.doubleValue) {
            value = number.doubleValue
        } else {
            Self.logger.error("replaced a stored gap outside the allowed values with \(Self.defaultValue, privacy: .public)")
            defaults.set(Self.defaultValue, forKey: Self.key)
        }
    }

    /// False, with nothing changed, for a value outside `allowed`.
    func set(_ value: Double) -> Bool {
        guard Self.allowed.contains(value) else { return false }
        self.value = value
        defaults.set(value, forKey: Self.key)
        onChange?(value)
        return true
    }
}
