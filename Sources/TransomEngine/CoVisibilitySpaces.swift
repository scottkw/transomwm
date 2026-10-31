public struct CoVisibilitySpaces: Equatable, Sendable {
    public static let syntheticBase: UInt64 = 0x8000_0000_0000_0000
    public init() {}
    public var visitedCount: Int { 0 }
    @discardableResult public mutating func visit(display: String, windowIDs: Set<UInt32>) -> UInt64 { 0 }
    public mutating func forget(windowID: UInt32) {}
}
