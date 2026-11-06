@testable import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"  // Harness's app
// The VM's desk (G-03-11 report): 1024x768, visible maxY 713.
private let visible = Rect(x: 0, y: 37, width: 1024, height: 676)
private let vm = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1024, height: 768), visibleFrame: visible, currentSpaceID: nil)
private let key = DeskKey(displayUUID: "main", spaceID: nil)
private let gap = 12.0

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
/// The apps' real minimums, which Transom does not know: each refuses to get smaller.
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

/// Wanted frames: what Float and Undo give back. D-05: Transom never moves a floater on its own.
@Suite struct WantedFrameTests {
    /// D-05: a gap drag that sweeps a docked tile over the floaters never moves them.
    @Test func aGapDragNeverMovesAFloater() async throws {
        var harness = await vmDesk()
        try await drag(&harness, [50, 100, 150, 190])
        try await drag(&harness, [-50, -100, -150, -190])
        for window in floaters {
            let frame = await harness.frame(window)
            #expect(frame == start[window.windowID], "floater \(window.windowID) is not back")
        }
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

    /// WR-02 (review 03-26): Float All lands at the tile rect (TILE-16); undoing it gives back the pre-dock frame.
    @Test func undoingFloatAllGivesBackThePreDockFrames() async throws {
        let w1 = ref(1), frame1 = Rect(x: 40, y: 80, width: 320, height: 232)
        var harness = await Harness.started(frames: [1: frame1, 2: Rect(x: 730, y: 400, width: 150, height: 120)])
        let dock = await harness.send(.command(.dock, focused: w1))
        let tile = try #require(setFrames(dock)[w1])
        await harness.send(.command(.floatAll, focused: w1))
        #expect(await harness.frame(w1) == tile)
        await harness.send(.command(.undo, focused: w1))
        #expect(harness.arranger.world[key]?.tree.state(of: w1) != nil, "the undo did not dock w1 again")
        await harness.send(.command(.float, focused: w1))
        #expect(await harness.frame(w1) == frame1)
    }

    /// CR-01 (review 03-26): a floater zoomed by a title-bar double-click, then un-zoomed back to where Float put it,
    /// stays un-zoomed. Transom's last write is history once the window has been anywhere else.
    @Test func aFloaterMovedBackOntoTransomsLastWriteIsNotMovedAway() async throws {
        let w1 = ref(1)
        var harness = await Harness.started(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232)])
        await harness.send(.command(.dock, focused: w1))
        await harness.send(.greenButton(w1))
        let floated = try #require(await harness.frame(w1))
        await harness.fake.userMove(1, to: Rect(x: 0, y: 25, width: 1440, height: 875))
        await harness.settle()
        await harness.fake.userMove(1, to: floated)
        await harness.settle()
        let focus = await harness.send(.event(.windowFocused(w1)))
        #expect(setFrames(focus)[w1] == nil)
        #expect(await harness.frame(w1) == floated)
        #expect(harness.arranger.wantedFrames[w1.identity] == floated)
    }

    /// CR-01, Window > Center: with no pre-dock frame Float centres the window; the user moves it, then centres it again.
    @Test func aFloaterCentredAgainByTheUserStaysCentred() async throws {
        let w1 = ref(1)
        var harness = await Harness.started(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232)])
        await harness.send(.command(.dock, focused: w1))
        harness.arranger.wantedFrames[w1.identity] = nil  // a window with no pre-dock frame, e.g. one restored docked
        await harness.send(.command(.float, focused: w1))
        let centred = try #require(await harness.frame(w1))
        #expect(abs(centred.midX - 720) < 1, "Float did not centre the window: \(centred)")
        await harness.fake.userMove(1, to: Rect(x: 100, y: 100, width: 400, height: 300))
        await harness.settle()
        await harness.fake.userMove(1, to: centred)
        await harness.settle()
        let focus = await harness.send(.event(.windowFocused(w1)))
        #expect(setFrames(focus)[w1] == nil)
        #expect(await harness.frame(w1) == centred)
    }
}
