import PaneModel

// RED stub: replaced by the real conversion in the GREEN commit.
public enum Coordinates {
    public static func topLeft(fromAppKit rect: Rect, primaryHeight: Double) -> Rect { rect }
    public static func appKit(fromTopLeft rect: Rect, primaryHeight: Double) -> Rect { rect }
    public static func displayUUID(for frame: Rect, among displays: [DisplayInfo]) -> String? { nil }
}
