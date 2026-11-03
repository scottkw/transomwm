import Foundation
import TransomModel

/// A window and a frame: a home frame (a parked window's pre-park frame, plan 08) or a wanted frame (the frame a
/// window goes back to when it floats, G-03-11).
public struct HomeFrame: Codable, Equatable, Sendable {
    public var window: WindowIdentity
    public var frame: Rect

    public init(window: WindowIdentity, frame: Rect) {
        self.window = window
        self.frame = frame
    }
}

/// One launch of Transom: written with `cleanExit: false` at launch and `true` when Transom quits normally (D-16).
public struct SessionRecord: Codable, Equatable, Sendable {
    public var cleanExit: Bool
    public var launchedAt: Date
    public var recoveryLaunch: Bool
    public var survivedMinute: Bool

    public init(cleanExit: Bool, launchedAt: Date, recoveryLaunch: Bool = false, survivedMinute: Bool = false) {
        self.cleanExit = cleanExit
        self.launchedAt = launchedAt
        self.recoveryLaunch = recoveryLaunch
        self.survivedMinute = survivedMinute
    }
}

/// Why `LayoutFile.validate()` rejected a decoded file.
public struct LayoutFileError: Error, Equatable, Sendable {
    public let reason: String
}

/// The contents of layout.json: the World (with each desk's Desktop tile, D-24), the home frames, the wanted frames
/// and the session record, in one file so they can never disagree (D-16, RESEARCH Pattern 10). Schema 2 (06-SPIKE
/// "Schema decision") adds the current display `arrangement`, the other arrangements' `layoutSets` (D-09) and the
/// `spaces` table giving each desk's Space ID its durable UUID (D-13). Schema 3 (D-10, D-14) keeps window titles, so
/// windows are re-matched after a relaunch; it has the same shape, and the bump stops an older Transom overwriting a
/// file whose titles it would strip. Every array is sorted, so equal contents give equal bytes.
public struct LayoutFile: Codable, Equatable, Sendable {
    public static let schemaVersion = 3
    /// Cap on stored arrangements (T-06-07).
    public static let maxLayoutSets = 16

    public var schemaVersion: Int
    /// The current arrangement's World; the Arranger works on this one.
    public var world: World
    /// Sorted by identity, so equal contents give equal bytes.
    public var homeFrames: [HomeFrame]
    /// Each window's wanted frame (G-03-11), so a docked window's pre-dock frame survives a relaunch. Sorted by identity.
    public var wantedFrames: [HomeFrame]
    public var session: SessionRecord
    /// The arrangement `world` was saved under; unknown (`[]`) for a file migrated from schema 1.
    public var arrangement: ArrangementID
    /// Sorted by arrangement.
    public var layoutSets: [LayoutSet]
    /// Sorted by ID.
    public var spaces: [SavedSpace]

    public init(
        world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect] = [:], session: SessionRecord,
        arrangement: ArrangementID = ArrangementID([]), layoutSets: [LayoutSet] = [], spaces: [SavedSpace] = []
    ) {
        schemaVersion = Self.schemaVersion
        self.world = world
        self.homeFrames = Self.sorted(homeFrames)
        self.wantedFrames = Self.sorted(wantedFrames)
        self.session = session
        self.arrangement = arrangement
        self.layoutSets = layoutSets.sorted { $0.arrangement < $1.arrangement }
        self.spaces = spaces.sorted { $0.id < $1.id }
    }

    private static func sorted(_ frames: [WindowIdentity: Rect]) -> [HomeFrame] {
        frames.sorted { $0.key < $1.key }.map { HomeFrame(window: $0.key, frame: $0.value) }
    }

    /// The home frames by identity. A file with a duplicate identity is rejected on load, so the last one never wins.
    public var homeFrameMap: [WindowIdentity: Rect] {
        Dictionary(homeFrames.map { ($0.window, $0.frame) }, uniquingKeysWith: { $1 })
    }

    /// The wanted frames by identity; like home frames, a duplicate identity is rejected on load.
    public var wantedFrameMap: [WindowIdentity: Rect] {
        Dictionary(wantedFrames.map { ($0.window, $0.frame) }, uniquingKeysWith: { $1 })
    }

    /// The Space UUIDs by ID; `validate()` rejects a repeated ID, so none is lost here.
    public var spaceMap: [UInt64: String] {
        Dictionary(spaces.map { ($0.id, $0.uuid) }, uniquingKeysWith: { $1 })
    }

    /// The rules a decoded file must meet beyond its decode (each World validates itself while decoding, T-06-07):
    /// sorted unique arrangements and Space IDs, non-empty Space UUIDs, at most `maxLayoutSets` sets.
    public func validate() throws(LayoutFileError) {
        guard arrangement.isNormalised else { throw LayoutFileError(reason: "arrangement is not sorted and unique") }
        guard layoutSets.count <= Self.maxLayoutSets else {
            throw LayoutFileError(reason: "\(layoutSets.count) layout sets, over \(Self.maxLayoutSets)")
        }
        for (index, set) in layoutSets.enumerated() where !set.arrangement.isNormalised {
            throw LayoutFileError(reason: "layout set \(index): arrangement is not sorted and unique")
        }
        guard zip(layoutSets, layoutSets.dropFirst()).allSatisfy({ $0.arrangement < $1.arrangement }) else {
            throw LayoutFileError(reason: "layout sets are not sorted by unique arrangement")
        }
        guard zip(spaces, spaces.dropFirst()).allSatisfy({ $0.id < $1.id }) else {
            throw LayoutFileError(reason: "spaces are not sorted by unique ID")
        }
        if let index = spaces.firstIndex(where: { $0.uuid.isEmpty }) {
            throw LayoutFileError(reason: "space \(index): empty uuid")
        }
    }
}

/// layout.json as schema 1 wrote it: no arrangement, layout sets or Space table, and `wantedFrames` optional (it
/// arrived in 03-26). Loaded only to migrate (RESEARCH Pitfall 1): the next save writes the current schema.
public struct LayoutFileV1: Decodable, Sendable {
    public var schemaVersion: Int
    public var world: World
    public var homeFrames: [HomeFrame]
    public var wantedFrames: [HomeFrame]?
    public var session: SessionRecord

    /// The same contents as schema 2: unknown arrangement, no layout sets, an empty Space table (ArrangeController
    /// fills it from the live Spaces, the same-login assumption of RESEARCH Pattern 2). Frames are copied as stored,
    /// so the load checks still see a duplicate.
    public func migrated() -> LayoutFile {
        var file = LayoutFile(world: world, homeFrames: [:], session: session)
        file.homeFrames = homeFrames
        file.wantedFrames = wantedFrames ?? []
        return file
    }
}
