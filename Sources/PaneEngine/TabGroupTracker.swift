import PaneModel

/// How one refresh's listed windows of an app map onto native tab groups.
public struct TabResolution: Equatable, Sendable {
    public var groupFor: [UInt32: WindowIdentity]
    public var memberIDs: Set<UInt32>
    public var tabCount: [WindowIdentity: Int]

    public init(groupFor: [UInt32: WindowIdentity] = [:], memberIDs: Set<UInt32> = [], tabCount: [WindowIdentity: Int] = [:]) {
        self.groupFor = groupFor
        self.memberIDs = memberIDs
        self.tabCount = tabCount
    }
}

public struct TabGroupTracker: Equatable, Sendable {
    public static let boundsTolerance: Double = 1.0

    public init() {}

    public mutating func update(pid: Int32, bundleID: String, visible: [(id: UInt32, frame: Rect, tabCount: Int)], cgWindows: [CGWindowEntry]) -> TabResolution {
        TabResolution()
    }

    public mutating func memberClosed(_ id: UInt32, pid: Int32) {}

    public func isKnownMember(_ id: UInt32, pid: Int32) -> Bool { false }

    public func members(of leader: WindowIdentity) -> Set<UInt32> { [] }
}
