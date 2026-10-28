import TransomModel

/// The one place y is flipped (D-18).
///
/// Transom's global space (AX, CG window bounds, `CGDisplayBounds`) has its origin at the top-left of the
/// primary display with y growing down; those values are used as they are. AppKit (`NSScreen.frame`,
/// `NSScreen.visibleFrame`, `NSWindow.frame`) has its origin at the bottom-left of the primary display
/// with y growing up; only those values pass through here.
public enum Coordinates {
    /// `y_top = H_primary − (y + h)`.
    public static func topLeft(fromAppKit rect: Rect, primaryHeight: Double) -> Rect {
        Rect(x: rect.x, y: primaryHeight - (rect.y + rect.height), width: rect.width, height: rect.height)
    }

    /// The same flip in reverse (the formula is its own inverse).
    public static func appKit(fromTopLeft rect: Rect, primaryHeight: Double) -> Rect {
        topLeft(fromAppKit: rect, primaryHeight: primaryHeight)
    }

    /// The display with the largest intersection; ties and no intersection go to the nearest display
    /// centre, then to the smaller UUID. nil only when there are no displays.
    public static func displayUUID(for frame: Rect, among displays: [DisplayInfo]) -> String? {
        func area(_ d: Rect) -> Double {
            max(0, min(frame.maxX, d.maxX) - max(frame.minX, d.minX)) * max(0, min(frame.maxY, d.maxY) - max(frame.minY, d.minY))
        }
        func distance(_ d: Rect) -> Double {
            ((frame.midX - d.midX) * (frame.midX - d.midX) + (frame.midY - d.midY) * (frame.midY - d.midY)).squareRoot()
        }
        return displays.min { l, r in
            (-area(l.frame), distance(l.frame), l.uuid) < (-area(r.frame), distance(r.frame), r.uuid)
        }?.uuid
    }
}
