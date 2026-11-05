import CoreGraphics
import TransomEngine

/// The tap's rule for removing ⌥ from a passed event during a window move, so macOS's own ⌥ tiling stays away (D-07a).
/// Pure, so the callback stays a lookup.
nonisolated enum DragOptionRule {
    /// `leftButtonDown` is read only when it decides: a `flagsChanged` with the button up means the session's mouse-up was
    /// lost (the tap was disabled or stopped), so the published state is stale and ⌥ goes through (WR-04).
    static func strips(type: CGEventType, flags: CGEventFlags, state: DragOptionStrip, leftButtonDown: @autoclosure () -> Bool) -> Bool {
        switch type {
        case .flagsChanged, .leftMouseDragged, .leftMouseUp: break
        default: return false
        }
        guard flags.contains(.maskAlternate) else { return false }
        let wanted = switch state {
        case .off: false
        case .always: true
        case .withControl: flags.contains(.maskControl)
        }
        return wanted && (type != .flagsChanged || leftButtonDown())
    }
}
