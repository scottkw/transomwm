import PaneEngine
import PaneModel
import Testing

private let pid: Int32 = 500
private let bundleID = "com.example.tabs"
private let frame = Rect(x: 100, y: 100, width: 600, height: 400)

private func identity(_ id: UInt32) -> WindowIdentity {
    WindowIdentity(windowID: id, pid: pid, bundleID: bundleID)
}

private func cg(_ id: UInt32, _ bounds: Rect = frame, onScreen: Bool = false, layer: Int = 0, pid: Int32 = pid) -> CGWindowEntry {
    CGWindowEntry(windowID: id, pid: pid, bounds: bounds, layer: layer, onScreen: onScreen, alpha: 1)
}

private func visible(_ id: UInt32, _ tabCount: Int, _ bounds: Rect = frame) -> (id: UInt32, frame: Rect, tabCount: Int) {
    (id: id, frame: bounds, tabCount: tabCount)
}

/// A tracker that has seen visible 10 with tabCount 3 and hidden siblings 11 and 12.
private func threeTabs() -> (TabGroupTracker, TabResolution) {
    var tracker = TabGroupTracker()
    let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 3)], cgWindows: [cg(10, onScreen: true), cg(11), cg(12)])
    return (tracker, resolution)
}

@Suite struct TabGroupTrackerTests {
    @Test func aVisibleTabAndItsHiddenSiblingsFormOneGroupLedByTheVisibleTab() {
        let (tracker, resolution) = threeTabs()
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(resolution.memberIDs == [10, 11, 12])
        #expect(resolution.tabCount == [identity(10): 3])
        #expect(tracker.isKnownMember(11, pid: pid))
    }

    @Test func switchingTabsRebindsTheVisibleTabToTheSameLeader() {
        var (tracker, _) = threeTabs()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(11, 3)], cgWindows: [cg(10), cg(11, onScreen: true), cg(12)])
        #expect(resolution.groupFor == [11: identity(10)])
        #expect(resolution.memberIDs == [10, 11, 12])
        #expect(resolution.tabCount == [identity(10): 3])
    }

    @Test(arguments: [(1.0, true), (1.01, false)])
    func aSiblingIsAMemberOnlyWithinOnePointOnEverySide(offset: Double, member: Bool) {
        var tracker = TabGroupTracker()
        let shifted = Rect(x: frame.x + offset, y: frame.y, width: frame.width, height: frame.height)
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), cg(11, shifted)])
        #expect(resolution.memberIDs.contains(11) == member)
        #expect(tracker.isKnownMember(11, pid: pid) == member)
    }

    @Test(arguments: [(1, false), (2, true)])
    func onlyTwoOrMoreTabsMakeAGroup(tabCount: Int, grouped: Bool) {
        var tracker = TabGroupTracker()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, tabCount)], cgWindows: [cg(10, onScreen: true), cg(11)])
        #expect((resolution.groupFor[10] != nil) == grouped)
        #expect(resolution.memberIDs == (grouped ? [10, 11] : []))
    }

    @Test(arguments: [cg(11, onScreen: true), cg(11, layer: 3), cg(11, pid: pid + 1)])
    func onscreenOtherLayerOrOtherPIDWindowsAreNeverMembers(entry: CGWindowEntry) {
        var tracker = TabGroupTracker()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(10, 2)], cgWindows: [cg(10, onScreen: true), entry])
        #expect(resolution.memberIDs == [10])
        #expect(!tracker.isKnownMember(11, pid: pid))
    }

    @Test func aClosedLeaderLeavesTheGroupItsIdentity() {
        var (tracker, _) = threeTabs()
        _ = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(11, 3)], cgWindows: [cg(10), cg(11, onScreen: true), cg(12)])
        tracker.memberClosed(10, pid: pid)
        #expect(!tracker.isKnownMember(10, pid: pid))
        #expect(tracker.isKnownMember(11, pid: pid))
        #expect(tracker.isKnownMember(12, pid: pid))
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(11, 2)], cgWindows: [cg(11, onScreen: true), cg(12)])
        #expect(resolution.groupFor == [11: identity(10)])
        #expect(resolution.memberIDs == [11, 12])
        #expect(resolution.tabCount == [identity(10): 2])
    }

    @Test func twoGroupsOfOneAppWithDifferentBoundsStaySeparate() {
        var tracker = TabGroupTracker()
        let other = Rect(x: 800, y: 100, width: 600, height: 400)
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2), visible(20, 2, other)],
            cgWindows: [cg(10, onScreen: true), cg(11), cg(20, other, onScreen: true), cg(21, other)]
        )
        #expect(resolution.groupFor == [10: identity(10), 20: identity(20)])
        #expect(resolution.tabCount == [identity(10): 2, identity(20): 2])
        #expect(tracker.members(of: identity(10)) == [10, 11])
        #expect(tracker.members(of: identity(20)) == [20, 21])
    }

    @Test func aNewTabJoinsTheExistingGroup() {
        var (tracker, _) = threeTabs()
        let resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [visible(13, 4)], cgWindows: [cg(10), cg(11), cg(12), cg(13, onScreen: true)])
        #expect(resolution.groupFor == [13: identity(10)])
        #expect(resolution.tabCount == [identity(10): 4])
    }

    @Test func aTabDraggedOutOfTheGroupIsNoLongerAMember() {
        var (tracker, _) = threeTabs()
        let away = Rect(x: 900, y: 300, width: 600, height: 400)
        let resolution = tracker.update(
            pid: pid, bundleID: bundleID, visible: [visible(10, 2), visible(11, 1, away)],
            cgWindows: [cg(10, onScreen: true), cg(11, away, onScreen: true), cg(12)]
        )
        #expect(resolution.groupFor == [10: identity(10)])
        #expect(resolution.memberIDs == [10, 12])
    }

    @Test func membersThatLeaveTheCGListLeaveTheGroupAndTheLastOneEndsIt() {
        var (tracker, _) = threeTabs()
        var resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [], cgWindows: [cg(11)])
        #expect(resolution.memberIDs == [11])
        #expect(resolution.tabCount == [identity(10): 1])
        resolution = tracker.update(pid: pid, bundleID: bundleID, visible: [], cgWindows: [])
        #expect(resolution == TabResolution(groupFor: [:], memberIDs: [], tabCount: [:]))
        #expect(tracker.members(of: identity(10)).isEmpty)
    }
}
