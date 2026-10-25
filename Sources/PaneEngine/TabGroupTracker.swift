import PaneModel

/// How one refresh's listed windows of an app map onto native tab groups.
public struct TabResolution: Equatable, Sendable {
    public var groupFor: [UInt32: WindowIdentity]
    public var memberIDs: Set<UInt32>
    public var tabCount: [WindowIdentity: Int]
    /// Tracked standalone windows that became a tab of another window's group: no longer separate windows.
    public var folded: [WindowIdentity]

    public init(
        groupFor: [UInt32: WindowIdentity] = [:], memberIDs: Set<UInt32> = [], tabCount: [WindowIdentity: Int] = [:],
        folded: [WindowIdentity] = []
    ) {
        self.groupFor = groupFor
        self.memberIDs = memberIDs
        self.tabCount = tabCount
        self.folded = folded
    }
}

/// Native AppKit tab groups (D-08, WIN-06). AX lists only the selected tab, which has an `AXTabGroup` child;
/// the other tabs exist only in the CG list: same pid, layer 0, offscreen, bounds within `boundsTolerance`.
///
/// A group's identity is the `WindowIdentity` of its oldest already-tracked member, else of its first-seen visible
/// member (the leader), for the group's whole life, even after the leader tab itself closes. Phases 3-4 must therefore address the window through
/// `WindowInfo.visibleMemberID`, never through the identity's window ID.
public struct TabGroupTracker: Equatable, Sendable {
    public static let boundsTolerance: Double = 1.0

    private struct Group: Equatable, Sendable {
        var leader: WindowIdentity
        var members: Set<UInt32>
        var tabCount: Int
    }

    private var groups: [Int32: [Group]] = [:]

    public init() {}

    /// Resolves one refresh of `pid`: `visible` are its listed windows with their `AXTabs` count. Members are
    /// recomputed from `cgWindows` every time; a group whose members all left the CG list ends. `tracked` are the
    /// app's tracked window identities, oldest first: a standalone one that gains a tab (Cmd-T) leads the new group.
    public mutating func update(
        pid: Int32, bundleID: String, visible: [(id: UInt32, frame: Rect, tabCount: Int)], cgWindows: [CGWindowEntry],
        tracked: [WindowIdentity] = []
    ) -> TabResolution {
        let cg = cgWindows.filter { $0.pid == pid }
        let inCG = Set(cg.map(\.windowID))
        let onScreen = Set(cg.filter(\.onScreen).map(\.windowID))
        var list = (groups[pid] ?? []).map { group in
            var group = group
            group.members.formIntersection(inCG)
            group.tabCount = group.members.count
            return group
        }
        let leaders = Set(list.map(\.leader.windowID))
        let standalone = tracked.filter { identity in identity.pid == pid && !list.contains { $0.leader == identity } }
        // Two listed members of one group (a tab being dragged out): the onscreen leader, then the tab bar, binds first.
        func rank(_ v: (id: UInt32, frame: Rect, tabCount: Int)) -> [Int] {
            [onScreen.contains(v.id) ? 1 : 0, leaders.contains(v.id) ? 1 : 0, v.tabCount, -Int(v.id)]
        }
        var groupFor: [UInt32: WindowIdentity] = [:]
        for v in visible.sorted(by: { rank($0).lexicographicallyPrecedes(rank($1)) }).reversed() {
            let members = Set(cg.filter { $0.windowID != v.id && $0.layer == 0 && !$0.onScreen && Self.matches($0.bounds, v.frame) }.map(\.windowID))
                .union([v.id])
            let index = list.firstIndex { $0.members.contains(v.id) }
                ?? (v.tabCount >= 2 ? list.firstIndex { !$0.members.isDisjoint(with: members) } : nil)
            if let index {
                list[index].members = members
                list[index].tabCount = max(v.tabCount, 1)
                groupFor[v.id] = list[index].leader
            } else if v.tabCount >= 2 {
                let leader = standalone.first { members.contains($0.windowID) } ?? WindowIdentity(windowID: v.id, pid: pid, bundleID: bundleID)
                list.append(Group(leader: leader, members: members, tabCount: v.tabCount))
                groupFor[v.id] = leader
            }
        }
        list.removeAll { $0.members.isEmpty }
        groups[pid] = list.isEmpty ? nil : list
        let memberIDs = list.reduce(into: Set<UInt32>()) { $0.formUnion($1.members) }
        return TabResolution(
            groupFor: groupFor,
            memberIDs: memberIDs,
            tabCount: Dictionary(uniqueKeysWithValues: list.map { ($0.leader, $0.tabCount) }),
            folded: standalone.filter { identity in memberIDs.contains(identity.windowID) && !list.contains { $0.leader == identity } }
        )
    }

    /// A member closed by the two-source rule. The group keeps its leader while any member remains.
    public mutating func memberClosed(_ id: UInt32, pid: Int32) {
        guard var list = groups[pid] else { return }
        for index in list.indices { list[index].members.remove(id) }
        list.removeAll { $0.members.isEmpty }
        groups[pid] = list.isEmpty ? nil : list
    }

    public func isKnownMember(_ id: UInt32, pid: Int32) -> Bool {
        groups[pid]?.contains { $0.members.contains(id) } == true
    }

    /// The members of the group led by `leader`; empty when it is not a group.
    public func members(of leader: WindowIdentity) -> Set<UInt32> {
        groups[leader.pid]?.first { $0.leader == leader }?.members ?? []
    }

    private static func matches(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.x - b.x) <= boundsTolerance && abs(a.y - b.y) <= boundsTolerance
            && abs(a.width - b.width) <= boundsTolerance && abs(a.height - b.height) <= boundsTolerance
    }
}
