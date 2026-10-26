import Foundation
import PaneModel

/// Where a window goes back to when it is shown or restored (a parked window's pre-park frame, plan 08).
public struct HomeFrame: Codable, Equatable, Sendable {
    public var window: WindowIdentity
    public var frame: Rect

    public init(window: WindowIdentity, frame: Rect) {
        self.window = window
        self.frame = frame
    }
}

/// One launch of Pane: written with `cleanExit: false` at launch and `true` when Pane quits normally (D-16).
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

/// The contents of layout.json: the World (with each desk's Desktop tile, D-24), the home frames and the session
/// record, in one file so they can never disagree (D-16, RESEARCH Pattern 10).
public struct LayoutFile: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var world: World
    /// Sorted by identity, so equal contents give equal bytes.
    public var homeFrames: [HomeFrame]
    public var session: SessionRecord

    public init(world: World, homeFrames: [WindowIdentity: Rect], session: SessionRecord) {
        schemaVersion = Self.schemaVersion
        self.world = world
        self.homeFrames = homeFrames.sorted { $0.key < $1.key }.map { HomeFrame(window: $0.key, frame: $0.value) }
        self.session = session
    }

    /// The home frames by identity. A file with a duplicate identity is rejected on load, so the last one never wins.
    public var homeFrameMap: [WindowIdentity: Rect] {
        Dictionary(homeFrames.map { ($0.window, $0.frame) }, uniquingKeysWith: { $1 })
    }
}
