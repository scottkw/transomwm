import CoreGraphics

/// The tap's green-button rule (TILE-06, TILE-19, RESEARCH Pattern 5). Pure, so the callback stays a lookup.
nonisolated enum GreenButton {
    /// Whether the tap takes this event. A left press inside `rects[windowID]` without ⌥ is taken, and so is the rest of
    /// that click (its drags and its release), so no app sees half a click (T-03-34). With ⌥ held everything passes,
    /// and macOS zooms (TILE-19). `swallowing` is the tap thread's state between the press and the release.
    static func shouldSwallow(
        type: CGEventType, location: CGPoint, flags: CGEventFlags, windowID: UInt32, rects: [UInt32: CGRect], swallowing: inout Bool
    ) -> Bool {
        switch type {
        case .leftMouseDown:
            swallowing = !flags.contains(.maskAlternate) && rects[windowID]?.contains(location) == true
            return swallowing
        case .leftMouseDragged:
            return swallowing
        case .leftMouseUp:
            defer { swallowing = false }
            return swallowing
        default:
            return false
        }
    }
}
