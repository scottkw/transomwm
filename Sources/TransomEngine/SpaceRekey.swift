import TransomModel

/// Re-keys saved desks by Space UUID (D-13, RESEARCH Pattern 2). Pure: ArrangeController runs it once, on the loaded
/// World before `.restore`, with layout.json's Space table and the live Spaces list.
public enum SpaceRekey {
    public struct Result: Equatable, Sendable {
        public let world: World
        /// Desks whose key changed.
        public let rekeyed: Int
        /// Desks whose Space is unknown now: kept under their old key, dormant.
        public let unmatched: [DeskKey]
        /// Desks dropped from `world` because their stale ID is a live Space's now (OVER-04 adjacency edge).
        public let quarantined: [DeskKey]
    }

    /// The Space table for layout.json: each Space ID a desk of `world` uses that `uuids` knows, sorted by ID.
    public static func table(for world: World, uuids: [UInt64: String]) -> [SavedSpace] {
        Set(world.desks.keys.compactMap(\.spaceID)).sorted().compactMap { id in uuids[id].map { SavedSpace(id: id, uuid: $0) } }
    }

    /// Moves each desk whose saved UUID (`saved`, by old ID) has a current ID (`current`, by UUID) to that ID. A desk
    /// with no Space is untouched. The World is rebuilt through its validated initialiser; it holds the same windows
    /// and IDs, so it throws only on a World that was already invalid.
    public static func rekey(_ world: World, saved: [UInt64: String], current: [String: UInt64]) throws(LayoutError) -> Result {
        var desks: [DeskKey: Desk] = [:]
        var rekeyed = 0
        for (key, desk) in world.desks {
            var target = key
            if let id = key.spaceID, let uuid = saved[id], let now = current[uuid] {
                target = DeskKey(displayUUID: key.displayUUID, spaceID: now)
            }
            if target != key { rekeyed += 1 }
            desks[target] = desk
        }
        return Result(world: try World(ids: world.ids, desks: desks), rekeyed: rekeyed, unmatched: [], quarantined: [])
    }
}
