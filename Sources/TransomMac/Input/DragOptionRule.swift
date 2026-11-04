import CoreGraphics
import TransomEngine

/// The tap's rule for removing ⌥ from a passed event during a window move, so macOS's own ⌥ tiling stays away (D-07a).
/// Pure, so the callback stays a lookup.
nonisolated enum DragOptionRule {
    static func strips(type: CGEventType, flags: CGEventFlags, state: DragOptionStrip) -> Bool {
        false
    }
}
