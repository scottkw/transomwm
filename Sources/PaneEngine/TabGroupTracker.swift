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
/// Bounds alone cannot tell a hidden tab from a same-app twin with the same frame (a twin on another Space: AX lists
/// only the current Space's windows). So a group takes at most `AXTabs - 1` hidden tabs, ranked: its own members,
/// the window a brand-new tab was opened from (Cmd-T), candidates on the shown tab's Space, untracked windows, and a
/// tracked standalone window only to fill the count. With Space data (SkyLight, `spaces`) a candidate known to be on
/// another Space is never taken; a hidden tab may report no Space, so while a window known to be on another Space
/// shares the frame slot no candidate of unknown Space is taken either (own members and the Cmd-T window excepted).
/// A shown tab that was not in the previous refresh's CG list is brand new (Cmd-T, New Tab): it takes the tracked
/// standalone window listed last refresh and leads a new group with it. A window listed in AXWindows without a tab
/// bar of its own is never a hidden tab, and leaves any group it was in unless it is the group's leader, its shown
/// tab, or all that is left of it. A tracked standalone window not listed at the last refresh is never taken either.
/// shortcut: without Space data (capability off or missing) Pane runs single-Space behaviour, and two same-frame tab
/// groups of one app on two Spaces can be tracked as one window; with Space data, an unknown-Space hidden tab can stay
/// out of its group until a tab switch shows it. Also, a non-leader tab left alone by closing the shown tab only
/// rebinds once WindowServer drops the closed one (within the settle delay).
///
/// A group's identity is the `WindowIdentity` of its oldest already-tracked member, else of its first-seen visible
/// member (the leader), for the group's whole life, even after the leader tab itself closes. Phases 3-4 must
/// therefore address the window through `WindowInfo.visibleMemberID`, never through the identity's window ID.
public struct TabGroupTracker: Equatable, Sendable {
    public static let boundsTolerance: Double = 1.0

    private struct Group: Equatable, Sendable {
        var leader: WindowIdentity
        var members: Set<UInt32>
        var tabCount: Int
        /// The member last bound as the listed tab.
        var shown: UInt32
    }

    private var groups: [Int32: [Group]] = [:]
    /// The IDs each app listed at its last update.
    private var lastListed: [Int32: Set<UInt32>] = [:]
    /// Each app's layer-0 CG entries at its last update, onscreen and offscreen.
    private var lastCG: [Int32: [CGWindowEntry]] = [:]

    public init() {}

    /// Resolves one refresh of `pid`: `visible` are its listed windows with their `AXTabs` count. Members are
    /// recomputed from `cgWindows` every time; a group whose members all left the CG list ends. `tracked` are the
    /// app's tracked window identities, oldest first: a standalone one that gains a tab (Cmd-T) leads the new group.
    /// `spaces` are the CG windows' Spaces; nil means no Space data (single-Space behaviour).
    public mutating func update(
        pid: Int32, bundleID: String, visible: [(id: UInt32, frame: Rect, tabCount: Int)], cgWindows: [CGWindowEntry],
        tracked: [WindowIdentity] = [], spaces: [UInt32: Set<UInt64>]? = nil
    ) -> TabResolution {
        let cg = cgWindows.filter { $0.pid == pid }
        let inCG = Set(cg.map(\.windowID))
        let onScreen = Set(cg.filter(\.onScreen).map(\.windowID))
        let listedSingles = Set(visible.filter { $0.tabCount < 2 }.map(\.id))
        var list = (groups[pid] ?? []).map { group in
            var group = group
            group.members.formIntersection(inCG)
            if group.members.count > 1 { group.members.subtract(listedSingles.subtracting([group.leader.windowID, group.shown])) }
            group.tabCount = group.members.count
            return group
        }
        let leaders = Set(list.map(\.leader.windowID))
        let standalone = tracked.filter { identity in identity.pid == pid && !list.contains { $0.leader == identity } }
        let listedTabCount = Dictionary(visible.map { ($0.id, $0.tabCount) }, uniquingKeysWith: max)
        let wasListed = lastListed[pid] ?? []
        func canBeHiddenTab(_ id: UInt32) -> Bool {
            if let tabCount = listedTabCount[id], tabCount < 2 { return false }
            return wasListed.contains(id) || !standalone.contains { $0.windowID == id }
        }
        // Two listed members of one group (a tab being dragged out): the onscreen leader, then the tab bar, binds first.
        func rank(_ v: (id: UInt32, frame: Rect, tabCount: Int)) -> [Int] {
            [onScreen.contains(v.id) ? 1 : 0, leaders.contains(v.id) ? 1 : 0, v.tabCount, -Int(v.id)]
        }
        let previousCG = lastCG[pid]
        func space(_ id: UInt32) -> Set<UInt64> { spaces?[id] ?? [] }
        var groupFor: [UInt32: WindowIdentity] = [:]
        for v in visible.sorted(by: { rank($0).lexicographicallyPrecedes(rank($1)) }).reversed() {
            let shownSpace = space(v.id)
            let slot = cg.filter { $0.windowID != v.id && $0.layer == 0 && Self.matches($0.bounds, v.frame) }
            let candidates = slot.filter {
                !$0.onScreen && canBeHiddenTab($0.windowID) && !Self.differ(space($0.windowID), shownSpace)
            }.map(\.windowID)
            // Brand new (Cmd-T, New Tab): the tracked standalone window listed last refresh is the one it was opened from.
            let isNew = previousCG.map { !$0.contains { $0.windowID == v.id } } ?? false
            let opener = isNew ? standalone.first { wasListed.contains($0.windowID) && candidates.contains($0.windowID) }?.windowID : nil
            // A new tab joins the group whose members it finds, if they leave it room under its AXTabs count.
            let index = list.firstIndex { $0.members.contains(v.id) }
                ?? (v.tabCount >= 2 && opener == nil
                    ? list.firstIndex { $0.members.count < v.tabCount && !$0.members.isDisjoint(with: candidates) } : nil)
            let own = index.map { list[$0].members } ?? []
            // A hidden tab may report no Space, so it cannot be told from a hidden tab of a same-slot group on another Space.
            let ambiguous = slot.contains { Self.differ(space($0.windowID), shownSpace) }
            func confirmed(_ id: UInt32) -> Bool { !space(id).isDisjoint(with: shownSpace) }
            func tier(_ id: UInt32) -> Int {
                if own.contains(id) { return 0 }
                if id == opener { return 1 }
                if confirmed(id) { return 2 }
                return standalone.contains { $0.windowID == id } || list.contains { $0.members.contains(id) } ? 4 : 3
            }
            let eligible = candidates.filter { !ambiguous || own.contains($0) || $0 == opener || confirmed($0) }
            let hidden = eligible.sorted { (tier($0), $0) < (tier($1), $1) }.prefix(max(v.tabCount - 1, 0))
            let members = Set(hidden).union([v.id])
            if let index {
                list[index].members = members
                list[index].tabCount = max(v.tabCount, 1)
                list[index].shown = v.id
                groupFor[v.id] = list[index].leader
            } else if v.tabCount >= 2 {
                let leader = standalone.first { members.contains($0.windowID) } ?? WindowIdentity(windowID: v.id, pid: pid, bundleID: bundleID)
                list.append(Group(leader: leader, members: members, tabCount: v.tabCount, shown: v.id))
                groupFor[v.id] = leader
            }
        }
        list.removeAll { $0.members.isEmpty }
        groups[pid] = list.isEmpty ? nil : list
        lastListed[pid] = visible.isEmpty ? nil : Set(visible.map(\.id))
        lastCG[pid] = cg.filter { $0.layer == 0 }
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

    public mutating func forget(pid: Int32) {
        groups[pid] = nil
        lastListed[pid] = nil
        lastCG[pid] = nil
    }

    public func isKnownMember(_ id: UInt32, pid: Int32) -> Bool {
        groups[pid]?.contains { $0.members.contains(id) } == true
    }

    /// The members of the group led by `leader`; empty when it is not a group.
    public func members(of leader: WindowIdentity) -> Set<UInt32> {
        groups[leader.pid]?.first { $0.leader == leader }?.members ?? []
    }

    /// Both Space sets known and disjoint: the windows are on different Spaces.
    private static func differ(_ a: Set<UInt64>, _ b: Set<UInt64>) -> Bool {
        !a.isEmpty && !b.isEmpty && a.isDisjoint(with: b)
    }

    private static func matches(_ a: Rect, _ b: Rect) -> Bool {
        abs(a.x - b.x) <= boundsTolerance && abs(a.y - b.y) <= boundsTolerance
            && abs(a.width - b.width) <= boundsTolerance && abs(a.height - b.height) <= boundsTolerance
    }
}
