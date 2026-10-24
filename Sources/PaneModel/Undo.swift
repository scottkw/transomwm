import Foundation

public struct UndoHistory: Equatable, Sendable {
    public static let limit = 50

    public init() {}

    public func depth(for key: DeskKey) -> Int { 0 }

    mutating func push(_ desk: Desk, for key: DeskKey) {}

    mutating func pop(for key: DeskKey) -> Desk? { nil }
}
