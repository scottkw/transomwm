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

    /// Removes `window` from every snapshot of every desk (it was confirmed closed).
    mutating func forget(_ window: WindowRef) {
        for (key, stack) in stacks {
            stacks[key] = stack.map { snapshot in
                guard snapshot.contains(window) else { return snapshot }
                var desk = snapshot
                // Cannot fail: the snapshot is a valid desk that holds the window, and removal only throws windowNotFound.
                try! desk.close(window)
                return desk
            }
        }
    }

    /// Re-points `from` to `to` in every snapshot of every desk (macOS corrected the window's ID). A snapshot
    /// that already holds `to` drops `from` instead, as `forget` does, so no snapshot holds the window twice.
    mutating func rekey(from: WindowRef, to: WindowRef) {
        for (key, stack) in stacks {
            stacks[key] = stack.map { snapshot in
                guard snapshot.contains(from) else { return snapshot }
                var desk = snapshot
                // Cannot fail: the desk holds `from`, and is renamed only when it does not hold `to`.
                if snapshot.contains(to) { try! desk.close(from) } else { try! desk.rekey(from: from, to: to) }
                return desk
            }
        }
    }
}
