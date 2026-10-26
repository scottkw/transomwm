@testable import PaneEngine
import PaneModel
import Testing

private let window = WindowRef(identity: WindowIdentity(windowID: 7, pid: 1, bundleID: "com.example.drag"))
private let frame = Rect(x: 100, y: 100, width: 400, height: 300)
private let press = Point(x: 300, y: 110)

private func moved(_ dx: Double) -> Rect { Rect(x: frame.x + dx, y: frame.y, width: frame.width, height: frame.height) }

private func session() -> DragSession { DragSession(window: window, start: press, startFrame: frame, modifiers: []) }

/// RESEARCH Pattern 1 classification and the 150 ms dwell (D-01, D-05, Pitfall 6).
@Suite struct DragSessionTests {
    @Test func underThreePointsOfTravelIsNoSession() {
        var s = session()
        s.pointer = Point(x: press.x + 2, y: press.y)
        s.observe(moved(2), lastApplied: nil)
        #expect(!s.travelled)
        #expect(s.kind == nil)
    }

    @Test func aMovedOriginWithTheSameSizeAfterTravelIsAMove() {
        var s = session()
        s.pointer = Point(x: press.x + 10, y: press.y)
        s.observe(moved(10), lastApplied: nil)
        #expect(s.travelled)
        #expect(s.kind == .move)
    }

    @Test func aChangedSizeIsAnEdgeResizeNotAMove() {
        var s = session()
        s.pointer = Point(x: press.x + 10, y: press.y)
        s.observe(Rect(x: frame.x, y: frame.y, width: frame.width + 10, height: frame.height), lastApplied: nil)
        #expect(s.kind == .resize)
        s.observe(moved(30), lastApplied: nil)
        #expect(s.kind == .resize, "the first verdict changed")
    }

    @Test func aFrameWithinTwoPointsOfTheLastWriteIsAnEcho() {
        var s = session()
        s.pointer = Point(x: press.x + 10, y: press.y)
        s.observe(moved(10), lastApplied: moved(11.5))
        #expect(s.kind == nil)
    }

    @Test func aTargetOrModifierChangeRestartsTheDwell() {
        var s = session()
        let t0 = ContinuousClock.now
        let left = Hover(displayUUID: "main", target: .layoutEdge(.left))
        let first = s.update(hover: left, at: t0)
        #expect(first)
        #expect(s.dwellEnds == t0 + .milliseconds(150))
        let same = s.update(hover: left, at: t0 + .milliseconds(50))
        #expect(!same)
        #expect(s.dwellEnds == t0 + .milliseconds(150))
        var shifted = left
        shifted.modifiers = [.shift]
        let modifier = s.update(hover: shifted, at: t0 + .milliseconds(100))
        #expect(modifier)
        #expect(s.dwellEnds == t0 + .milliseconds(250))
        let target = s.update(hover: Hover(displayUUID: "main", target: .layoutEdge(.right)), at: t0 + .milliseconds(120))
        #expect(target)
        #expect(s.dwellEnds == t0 + .milliseconds(270))
    }

    @Test func theDryRunRunsOncePerHeldHoverNeverPerMove() {
        var s = session()
        let t0 = ContinuousClock.now
        var runs = 0
        let decision = Decision(preview: .dock(frame), action: .miss, display: "main")
        let left = Hover(displayUUID: "main", target: .layoutEdge(.left))
        _ = s.update(hover: left, at: t0)
        let early = s.settle(at: t0 + .milliseconds(100)) { _ in runs += 1; return decision }
        #expect(early == nil)
        let due = s.settle(at: t0 + .milliseconds(150)) { _ in runs += 1; return decision }
        #expect(due == decision)
        #expect(s.dryRuns == 1)
        // More pointer samples over the same target: no new dry run.
        _ = s.update(hover: left, at: t0 + .milliseconds(200))
        let again = s.settle(at: t0 + .milliseconds(400)) { _ in runs += 1; return decision }
        #expect(again == nil)
        #expect(runs == 1)
        _ = s.update(hover: Hover(displayUUID: "main", target: .layoutEdge(.top)), at: t0 + .milliseconds(500))
        let next = s.settle(at: t0 + .milliseconds(650)) { _ in runs += 1; return decision }
        #expect(next == decision)
        #expect(runs == 2 && s.dryRuns == 2)
    }
}
