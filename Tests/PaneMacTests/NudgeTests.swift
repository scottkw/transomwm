import PaneMac
import PaneModel
import Testing

/// D-01 / UI-SPEC Debug submenu: the first press nudges, the next restores the frame from before the first.
@Suite struct NudgeTests {
    static let window = WindowIdentity(windowID: 7, pid: 700, bundleID: "com.example.app")
    static let other = WindowIdentity(windowID: 8, pid: 700, bundleID: "com.example.app")

    @Test func pressesAlternateBetweenNudgedAndRestored() {
        var planner = NudgePlanner()
        let start = Rect(x: 100, y: 100, width: 800, height: 600)
        let nudged = Rect(x: 132, y: 132, width: 736, height: 536)
        #expect(planner.target(for: Self.window, current: start) == nudged)
        #expect(planner.target(for: Self.window, current: nudged) == start)
        #expect(planner.target(for: Self.window, current: start) == nudged)
    }

    @Test func theRestoreIgnoresWhereTheWindowEndedUp() {
        var planner = NudgePlanner()
        let start = Rect(x: 100, y: 100, width: 800, height: 600)
        _ = planner.target(for: Self.window, current: start)
        // The app refused the shrink: the next press still returns to the frame before the first.
        #expect(planner.target(for: Self.window, current: Rect(x: 132, y: 132, width: 800, height: 600)) == start)
    }

    @Test func aSmallWindowNeverShrinksBelowOnePoint() {
        var planner = NudgePlanner()
        let target = planner.target(for: Self.window, current: Rect(x: 0, y: 0, width: 50, height: 40))
        #expect(target == Rect(x: 32, y: 32, width: 1, height: 1))
    }

    @Test func windowsKeepSeparateRestoreFrames() {
        var planner = NudgePlanner()
        let a = Rect(x: 100, y: 100, width: 800, height: 600)
        let b = Rect(x: 1000, y: 200, width: 500, height: 400)
        _ = planner.target(for: Self.window, current: a)
        _ = planner.target(for: Self.other, current: b)
        #expect(planner.target(for: Self.other, current: Rect(x: 0, y: 0, width: 10, height: 10)) == b)
        #expect(planner.target(for: Self.window, current: Rect(x: 0, y: 0, width: 10, height: 10)) == a)
    }

    @Test func theStepsAreThoseOfTheSpec() {
        #expect(NudgePlanner.offset == 32)
        #expect(NudgePlanner.shrink == 64)
    }
}
