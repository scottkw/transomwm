import Foundation

/// The band a tab group reserves at the top of its frame for its strip (D-04): the selected member fills the rest, the
/// content rect. Top-left global coordinates, so the band is at the smaller y.
public enum TabBand {
    /// The strip (28 pt) plus a 4 pt gap above the content rect.
    public static let height: Double = 32
    public static let stripHeight: Double = 28

    /// The group frame without the band; its height is floored at 0.
    public static func content(of frame: Rect) -> Rect {
        Rect(x: frame.x, y: frame.y + height, width: frame.width, height: max(0, frame.height - height))
    }

    /// The group frame whose content rect is `content`.
    public static func frame(ofContent content: Rect) -> Rect {
        Rect(x: content.x, y: content.y - height, width: content.width, height: content.height + height)
    }

    /// Where the strip sits: the top `stripHeight` of the group frame.
    public static func strip(of frame: Rect) -> Rect {
        Rect(x: frame.x, y: frame.y, width: frame.width, height: min(stripHeight, frame.height))
    }
}
