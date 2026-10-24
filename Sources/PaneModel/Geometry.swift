import Foundation

// All coordinates live in one global space: top-left origin, y grows downward, units are points
// (the Accessibility convention). Negative coordinates are valid: displays placed left of or above
// the primary display have negative origins.

public struct Point: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Codable, Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Rect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var origin: Point { Point(x: x, y: y) }
    public var size: Size { Size(width: width, height: height) }

    /// Half-open: the min edges are inside, the max edges are not.
    public func contains(_ p: Point) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    /// True only when the interiors intersect with positive area; touching edges do not overlap.
    public func overlaps(_ other: Rect) -> Bool {
        min(maxX, other.maxX) > max(minX, other.minX) && min(maxY, other.maxY) > max(minY, other.minY)
    }

    public var isValidGeometry: Bool {
        width >= 0 && height >= 0
            && [x, y, width, height, maxX, maxY].allSatisfy { $0.isFinite && abs($0) <= Geometry.maxCoordinate }
    }
}

public enum Geometry {
    public static let maxCoordinate: Double = 1_000_000
}

/// `horizontal` lays children out left to right along x; `vertical` lays them out top to bottom along y.
public enum Axis: String, Codable, Sendable {
    case horizontal, vertical
}

public enum Edge: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom

    public var axis: Axis {
        switch self {
        case .left, .right: .horizontal
        case .top, .bottom: .vertical
        }
    }

    /// Left and top come first along their axis.
    public var isLeading: Bool { self == .left || self == .top }
}
