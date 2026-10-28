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

/// The contents of layout.json: the World (with each desk's Desktop tile, D-24), the home frames, the wanted frames
/// and the session record, in one file so they can never disagree (D-16, RESEARCH Pattern 10).
public struct LayoutFile: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var world: World
    /// Sorted by identity, so equal contents give equal bytes.
    public var homeFrames: [HomeFrame]
    /// Each window's wanted frame (G-03-11), so a docked window's pre-dock frame survives a relaunch. Sorted by identity.
    public var wantedFrames: [HomeFrame]
    public var session: SessionRecord

    public init(
        world: World, homeFrames: [WindowIdentity: Rect], wantedFrames: [WindowIdentity: Rect] = [:], session: SessionRecord
    ) {
        schemaVersion = Self.schemaVersion
        self.world = world
        self.homeFrames = Self.sorted(homeFrames)
        self.wantedFrames = Self.sorted(wantedFrames)
        self.session = session
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, world, homeFrames, wantedFrames, session
    }

    /// A layout.json written before 03-26 has no `wantedFrames` key: it loads with none. The key is optional, so the
    /// schema version stays 1 and an older Transom ignores it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        world = try container.decode(World.self, forKey: .world)
        homeFrames = try container.decode([HomeFrame].self, forKey: .homeFrames)
        wantedFrames = try container.decodeIfPresent([HomeFrame].self, forKey: .wantedFrames) ?? []
        session = try container.decode(SessionRecord.self, forKey: .session)
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
}
