@testable import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"  // Harness's app
// The VM's desk (G-03-11 report): 1024x768, visible maxY 713, so the Desktop's bottom is 701 with a 12 pt gap.
private let visible = Rect(x: 0, y: 37, width: 1024, height: 676)
private let vm = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1024, height: 768), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)
private let gap = 12.0
private let desktopBottom = visible.maxY - gap

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let docked = ref(10)
private let finder = ref(1), safari = ref(2), textEdit = ref(3)
private let floaters = [finder, safari, textEdit]
/// Inside the Desktop rect docking 10 at the top leaves (y 381...701).
private let start: [UInt32: Rect] = [
    1: Rect(x: 40, y: 390, width: 460, height: 300),
    2: Rect(x: 420, y: 400, width: 574, height: 290),
    3: Rect(x: 270, y: 420, width: 729, height: 260),
]
/// The apps' real minimums, which Pane does not know: each refuses to get smaller.
private let hidden: [UInt32: Size] = [1: Size(width: 460, height: 252), 2: Size(width: 574, height: 224), 3: Size(width: 143, height: 70)]

/// Window 10 docked at the top, the three floaters below it on the Desktop.
private func vmDesk() async -> Harness {
    var harness = Harness()
    harness.arranger = Arranger(gap: gap)
    await harness.fake.setDisplays([vm])
    await harness.fake.addApp(FakeApp(pid: pid, bundleID: bundleID))
    await harness.fake.open(.standard(id: 10, pid: pid, frame: Rect(x: 12, y: 49, width: 1000, height: 200)))
    for (id, frame) in start.sorted(by: { $0.key < $1.key }) { await harness.fake.open(.standard(id: id, pid: pid, frame: frame)) }
    for (id, minimum) in hidden { await harness.fake.update(id) { $0.hiddenMinimum = minimum } }
    await harness.fake.refreshAll()
    _ = await harness.inbox.take()
    await harness.send(.inventory(await harness.fake.inventory()))
    await harness.send(.command(.dock, focused: docked))
    return harness
}

/// The handle between the docked tile and the Desktop.
private func rootHandle(_ harness: Harness) throws -> GapHandle {
    let desk = try #require(harness.arranger.world[key])
    let plan = try Planner.plan(desk: desk, area: visible, gap: gap, mins: harness.arranger.minimums)
    return try #require(GapHandles.handles(tree: desk.tree, resolution: plan.resolution, gap: gap).first { $0.split == desk.tree.root })
}

/// Drags the root handle by each of `steps` live, then releases it at the last one.
private func drag(_ harness: inout Harness, _ steps: [Double]) async throws {
    let handle = try rootHandle(harness)
    for delta in steps { await harness.send(.gapDrag(handle, delta: delta, ended: false)) }
    await harness.send(.gapDrag(handle, delta: try #require(steps.last), ended: true))
}

/// G-03-11: Pane's own clamps during a gap drag never replace the frame a floater goes back to (its wanted frame).
@Suite struct WantedFrameTests {
    @Test func aDesktopThatShrinksAndGrowsBackReturnsFloatersToTheirFrames() async throws {
        var harness = await vmDesk()
        try await drag(&harness, [50, 100, 150, 190])
        try await drag(&harness, [-50, -100, -150, -190])
        for window in floaters {
            let frame = await harness.frame(window)
            #expect(frame == start[window.windowID], "floater \(window.windowID) is not back")
        }
    }

    /// G-03-11 B: the drag stops at the floaters' real size, so none hangs below the Desktop or over the docked tile.
    @Test func aFloaterWhoseMinimumIsAboveTheShrunkenDesktopNeverEndsBelowIt() async throws {
        var harness = await vmDesk()
        let handle = try rootHandle(harness)
        func check(_ step: String) async throws {
            let top = try #require(await harness.frame(docked))
            for window in floaters {
                let frame = try #require(await harness.frame(window))
                #expect(frame.maxY <= desktopBottom + 0.5, "floater \(window.windowID) below the Desktop at \(step): \(frame)")
                #expect(!frame.overlaps(top), "floater \(window.windowID) overlaps the docked tile at \(step): \(frame)")
            }
        }
        for delta in [50.0, 100, 150, 190] {
            await harness.send(.gapDrag(handle, delta: delta, ended: false))
            try await check("+\(delta)")
        }
        await harness.send(.gapDrag(handle, delta: 190, ended: true))
        try await check("release")
    }

    /// Plan-check W1: an app that applies the clamp late reads back its old frame, then reports the clamped one.
    @Test func aClampTheAppAppliesLateIsStillPanesOwn() async throws {
        var harness = await vmDesk()
        let handle = try rootHandle(harness)
        let step = harness.arranger.handle(.gapDrag(handle, delta: 100, ended: false), now: harness.now)
        let clamp = try #require(setFrames(step)[textEdit])
        let old = try #require(start[3])
        #expect(clamp != old)
        // Everything but textEdit's write lands at once.
        let others = step.map { effect -> ArrangerEffect in
            guard case .perform(let commands) = effect else { return effect }
            return .perform(commands.filter { if case .setFrame(textEdit, _) = $0 { false } else { true } })
        }
        for case .perform(let commands) in others { await harness.fake.perform(commands) }
        var late = harness.arranger.handle(.event(.frameApplied(textEdit, requested: clamp, actual: old)), now: harness.now)
        await harness.fake.update(3) { $0.frame = clamp }
        late += harness.arranger.handle(.event(.windowMoved(textEdit, clamp)), now: harness.now)
        late += harness.arranger.handle(.event(.windowResized(textEdit, clamp)), now: harness.now)
        for case .perform(let commands) in late { await harness.fake.perform(commands) }
        await harness.settle()
        await harness.send(.gapDrag(handle, delta: 100, ended: true))
        try await drag(&harness, [-100])
        #expect(harness.arranger.wantedFrames[textEdit.identity] == old)
        let frame = await harness.frame(textEdit)
        #expect(frame == old)
    }

    /// D-23: a floater the user moved while paused is not moved back at Resume.
    @Test func aFloaterTheUserMovesWhilePausedStaysWhereTheyLeftIt() async throws {
        var harness = await Harness.started()
        let w1 = ref(1), w2 = ref(2)
        await harness.send(.command(.dock, focused: w1))
        await harness.send(.command(.togglePause, focused: nil))
        let moved = Rect(x: 1000, y: 500, width: 150, height: 120)
        await harness.fake.userMove(2, to: moved)
        await harness.refresh()
        let resume = await harness.send(.command(.togglePause, focused: nil))
        #expect(setFrames(resume)[w2] == nil)
        #expect(await harness.frame(w2) == moved)
        #expect(harness.arranger.wantedFrames[w2.identity] == moved)
    }
}
