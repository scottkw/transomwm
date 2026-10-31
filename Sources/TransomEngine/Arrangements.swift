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
