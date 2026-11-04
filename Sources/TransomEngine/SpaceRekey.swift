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

    /// The Space table for layout.json: each Space ID a desk of `world` or of a layout set, or a saved view's desk, uses
    /// that `uuids` knows, sorted by ID. A set's Spaces are listed too, so its desks can be re-keyed after a reboot (CR-02).
    public static func table(for world: World, layoutSets: [LayoutSet] = [], views: [SavedView] = [], uuids: [UInt64: String]) -> [SavedSpace] {
        let ids = Set(([world] + layoutSets.map(\.world)).flatMap { $0.desks.keys.compactMap(\.spaceID) } + views.compactMap(\.desk.spaceID))
        return ids.sorted().compactMap { id in uuids[id].map { SavedSpace(id: id, uuid: $0) } }
    }

    /// A loaded file's World, every layout set's World and every saved view's desk re-keyed with one table, the file's
    /// Space table over the live one (D-13, CR-02). A set whose World cannot be rebuilt (only an already invalid one) keeps
    /// its saved keys. A view whose Space is unknown now keeps its key, so going there takes the N17 path.
    /// shortcut: a view on a gone Space whose ID a new Space reused goes to the new Space's home; quarantine it if that shows up.
    public static func rekey(
        _ file: LayoutFile, live: SpacesSnapshot
    ) throws(LayoutError) -> (result: Result, layoutSets: [LayoutSet], setsQuarantined: [DeskKey], views: [SavedView]) {
        let table = live.uuidByID.merging(file.spaceMap) { _, saved in saved }
        var quarantined: [DeskKey] = []
        let sets = file.layoutSets.map { set in
            guard let result = try? rekey(set.world, saved: table, current: live.idByUUID) else { return set }
            quarantined += result.quarantined
            return LayoutSet(arrangement: set.arrangement, world: result.world, lastUsed: set.lastUsed)
        }
        let views = file.views.map { view -> SavedView in
            guard let id = view.desk.spaceID, let uuid = table[id], let now = live.idByUUID[uuid] else { return view }
            return SavedView(slot: view.slot, desk: DeskKey(displayUUID: view.desk.displayUUID, spaceID: now), home: view.home, windows: view.windows)
        }
        return (try rekey(file.world, saved: table, current: live.idByUUID), sets, quarantined, views)
    }

    /// Moves each desk whose saved UUID (`saved`, by old ID) has a current ID (`current`, by UUID) to that ID. A desk
    /// with no Space is untouched. A desk whose UUID has no current ID keeps its key, dormant (`unmatched`), unless that
    /// key's ID is a live Space's now: then it is `quarantined`, dropped so a new Space never inherits a stale layout.
    /// Every target is computed before the World is rebuilt, so two desks exchanging IDs never collide; a second desk
    /// aiming at a taken key is quarantined too. The World is rebuilt through its validated initialiser; it holds a
    /// subset of the same windows and IDs, so it throws only on a World that was already invalid.
    public static func rekey(_ world: World, saved: [UInt64: String], current: [String: UInt64]) throws(LayoutError) -> Result {
        let live = Set(current.values)
        var desks: [DeskKey: Desk] = [:]
        var rekeyed = 0
        var unmatched: [DeskKey] = []
        var quarantined: [DeskKey] = []
        // A dormant desk keeps only an ID no live Space has, so it never meets a matched desk's (live) target.
        let sorted = world.desks.sorted { $0.key < $1.key }
        var targets: [(key: DeskKey, target: DeskKey?)] = sorted.map { key, _ in
            guard let id = key.spaceID else { return (key, key) }
            guard let uuid = saved[id], let now = current[uuid] else { return (key, nil) }
            return (key, DeskKey(displayUUID: key.displayUUID, spaceID: now))
        }
        for index in targets.indices where targets[index].target == nil {
            let key = targets[index].key
            if let id = key.spaceID, live.contains(id) {
                quarantined.append(key)
            } else {
                unmatched.append(key)
                targets[index].target = key
            }
        }
        for ((key, target), (_, desk)) in zip(targets, sorted) {
            guard let target else { continue }
            guard desks[target] == nil else {
                quarantined.append(key)
                continue
            }
            if target != key { rekeyed += 1 }
            desks[target] = desk
        }
        return Result(
            world: try World(ids: world.ids, desks: desks), rekeyed: rekeyed, unmatched: unmatched, quarantined: quarantined.sorted())
    }
}
