import Foundation
import TransomEngine
import os

/// Drag to Dock (D-07, D-19), kept in UserDefaults. The plist is user-writable: anything but the two modes is logged and
/// replaced by the default.
@MainActor final class DragToDockPreference {
    static let key = "dragToDock"
    static let defaultValue = DragToDockMode.automatic
    private(set) var value: DragToDockMode
    /// Fires after every change; choosing the current value is not one.
    var onChange: ((DragToDockMode) -> Void)?
    private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = Self.defaultValue
        guard let stored = defaults.object(forKey: Self.key) else { return }
        if let mode = (stored as? String).flatMap(DragToDockMode.init(rawValue:)) {
            value = mode
        } else {
            Self.logger.error("replaced a stored dragToDock outside the allowed values with \(Self.defaultValue.rawValue, privacy: .public)")
            defaults.set(Self.defaultValue.rawValue, forKey: Self.key)
        }
    }

    func set(_ mode: DragToDockMode) {
        guard mode != value else { return }
        value = mode
        defaults.set(mode.rawValue, forKey: Self.key)
        Self.logger.info("drag to dock: \(mode == .automatic ? "automatic" : "hold option", privacy: .public)")
        onChange?(mode)
    }
}
