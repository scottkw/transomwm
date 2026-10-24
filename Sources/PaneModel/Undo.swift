import Foundation

/// Per-desk undo stacks of Desk snapshots, newest last. Desks are value types with copy-on-write
/// storage, so a snapshot is cheap until the live desk changes.
///
/// Session state only: not Codable and not part of World, so saved layouts never carry undo stacks.
public struct UndoHistory: Equatable, Sendable {
    public static let limit = 50

    private var stacks: [DeskKey: [Desk]] = [:]

    public init() {}

    public func depth(for key: DeskKey) -> Int { stacks[key]?.count ?? 0 }

    /// Appends `desk`, dropping the oldest snapshots beyond `limit`.
    mutating func push(_ desk: Desk, for key: DeskKey) {
        var stack = stacks[key] ?? []
        stack.append(desk)
        stack.removeFirst(max(0, stack.count - Self.limit))
        stacks[key] = stack
    }

    mutating func pop(for key: DeskKey) -> Desk? { stacks[key]?.popLast() }
}
