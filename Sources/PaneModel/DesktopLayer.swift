import Foundation

public struct FloatingWindow: Codable, Equatable, Sendable {
    public let window: WindowRef
    public var frame: Rect
    public var state: WindowState
}

public struct DesktopLayer: Codable, Equatable, Sendable {
    public private(set) var windows: [FloatingWindow]

    public init() {
        windows = []
    }

    public mutating func add(_ window: WindowRef, frame: Rect) throws(LayoutError) {}

    public mutating func remove(_ window: WindowRef) throws(LayoutError) {}

    public mutating func setFrame(_ frame: Rect, for window: WindowRef) throws(LayoutError) {}

    public func frame(of window: WindowRef) -> Rect? { nil }

    public func contains(_ window: WindowRef) -> Bool { false }

    public func validate() throws(LayoutError) {}
}
