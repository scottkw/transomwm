import CoreGraphics

/// The tap's green-button rule (TILE-06, TILE-19, RESEARCH Pattern 5): pure, so the callback stays a lookup.
nonisolated enum GreenButton {
    static func shouldSwallow(
        type: CGEventType, location: CGPoint, flags: CGEventFlags, windowID: UInt32, rects: [UInt32: CGRect], swallowing: inout Bool
    ) -> Bool {
        false
    }
}
