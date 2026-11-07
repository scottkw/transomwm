import AppKit
import os

/// The one colour every Transom-drawn accent uses (D-03): the user's override from Settings ▸ General, else the macOS
/// accent. System-drawn controls keep the macOS accent; Transom never tints AppKit controls. Read it on every draw so
/// accent, appearance and override changes apply at once.
@MainActor enum HighlightColor {
    static let key = "appearance.highlight"
    static let didChange = Notification.Name("com.eightabyte.transom.highlightColorDidChange")
    private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "preferences")

    /// Exactly "#RRGGBB", hex digits in either case; anything else is nil.
    nonisolated static func parse(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.utf8.count == 7, hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// "#RRGGBB" in sRGB, rounded, uppercase.
    static func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let byte: (CGFloat) -> Int = { (part: CGFloat) -> Int in Int((min(max(part, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    /// The stored override when one is set, nil otherwise. The plist is user-writable (T-09-14): a value that isn't
    /// "#RRGGBB" is logged, without the value, and removed.
    static func override(in defaults: UserDefaults = .standard) -> NSColor? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard let text = stored as? String, let rgb = parse(text) else {
            logger.error("replaced an invalid appearance.highlight with the system accent")
            defaults.removeObject(forKey: key)
            return nil
        }
        return NSColor(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1)
    }

    static func current(in defaults: UserDefaults) -> NSColor {
        override(in: defaults) ?? .controlAccentColor
    }

    static var current: NSColor { current(in: .standard) }

    /// nil goes back to the system accent.
    static func set(_ color: NSColor?, in defaults: UserDefaults = .standard) {
        if let color {
            defaults.set(hex(color), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
