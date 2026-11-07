import Foundation
import TransomModel

/// A display arrangement: the set of connected displays, by UUID (D-09, OVER-06). Sorted and unique, so the same
/// displays in any order are one arrangement. `[]` is unknown (a file migrated from schema 1).
public struct ArrangementID: Hashable, Comparable, Codable, Sendable {
    public let displayUUIDs: [String]

    public init(_ uuids: [String]) {
        displayUUIDs = Set(uuids).sorted()
    }

    public var isUnknown: Bool { displayUUIDs.isEmpty }

    /// Sorted and unique; a decoded ID is not normalised, so `LayoutFile.validate()` rejects one that is not.
    public var isNormalised: Bool { zip(displayUUIDs, displayUUIDs.dropFirst()).allSatisfy { $0 < $1 } }

    /// The first 4 hex digits of FNV-1a 64 over the UUIDs joined by ",": the `{id}` in the Debug S2 line and the
    /// `displays` log. Stable across runs and builds, unlike `hashValue`.
    public var shortHash: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in displayUUIDs.joined(separator: ",").utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(String(hash, radix: 16).leftPadded(to: 16).prefix(4))
    }

    public static func < (lhs: ArrangementID, rhs: ArrangementID) -> Bool {
        lhs.displayUUIDs.lexicographicallyPrecedes(rhs.displayUUIDs)
    }
}

/// The World saved for a display arrangement other than the current one (D-09). Switching rules come in 06-04.
public struct LayoutSet: Codable, Equatable, Sendable {
    public var arrangement: ArrangementID
    public var world: World
    public var lastUsed: Date

    public init(arrangement: ArrangementID, world: World, lastUsed: Date) {
        self.arrangement = arrangement
        self.world = world
        self.lastUsed = lastUsed
    }
}

/// The stored layout sets (D-09), sorted by arrangement as layout.json keeps them, at most `limit`: storing one more
/// drops the least recently used.
public struct LayoutSets: Equatable, Sendable {
    public static let limit = LayoutFile.maxLayoutSets
    public private(set) var all: [LayoutSet] = []

    public init(_ sets: [LayoutSet] = []) {
        for set in sets { store(set.world, for: set.arrangement, at: set.lastUsed) }
    }

    public subscript(id: ArrangementID) -> LayoutSet? { all.first { $0.arrangement == id } }

    /// Stores `world` as `id`'s set, replacing any older one.
    public mutating func store(_ world: World, for id: ArrangementID, at date: Date) {
        all.removeAll { $0.arrangement == id }
        all.append(LayoutSet(arrangement: id, world: world, lastUsed: date))
        if all.count > Self.limit, let oldest = all.indices.min(by: { (all[$0].lastUsed, all[$0].arrangement) < (all[$1].lastUsed, all[$1].arrangement) }) {
            all.remove(at: oldest)
        }
        all.sort { $0.arrangement < $1.arrangement }
    }

    /// Removes and returns `id`'s set: it becomes the current layout.
    public mutating func take(_ id: ArrangementID) -> LayoutSet? {
        all.firstIndex { $0.arrangement == id }.map { all.remove(at: $0) }
    }
}

/// What a settled display change does (OVER-06, UI-SPEC Surface 6).
public enum ArrangementSwitch: Equatable, Sendable {
    /// The same displays (rearranged, re-scaled, or a sleep/wake): tiles re-plan to the new frames.
    case same
    /// An arrangement seen before: its stored set is applied.
    case known(LayoutSet)
    /// Never seen: the current layouts carry over, a vanished display's desks go dormant.
    case new

    public static func decide(from current: ArrangementID, to next: ArrangementID, sets: LayoutSets) -> ArrangementSwitch {
        if next == current { return .same }
        return sets[next].map(ArrangementSwitch.known) ?? .new
    }

    /// Where windows floated from a vanished display go (D-10): each at its own size, 24 pt right of and below the one
    /// before, the first at `start` (the receiving visible frame's top-left), clamped inside `visible`.
    public static func cascade(frames: [Rect], from start: Point, in visible: Rect) -> [Rect] {
        frames.enumerated().map { index, frame in
            let offset = 24 * Double(index)
            return Planner.clamp(Rect(x: start.x + offset, y: start.y + offset, width: frame.width, height: frame.height), into: visible)
        }
    }
}

/// A saved desk's runtime Space ID with the Space's durable UUID (D-13); an empty macOS uuid is `default:<displayUUID>`.
public struct SavedSpace: Codable, Equatable, Sendable {
    public var id: UInt64
    public var uuid: String

    public init(id: UInt64, uuid: String) {
        self.id = id
        self.uuid = uuid
    }
}

private extension String {
    func leftPadded(to length: Int) -> String { String(repeating: "0", count: max(0, length - count)) + self }
}
