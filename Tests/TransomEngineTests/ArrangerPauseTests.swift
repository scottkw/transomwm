import TransomEngine
import TransomModel
import TransomTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"  // Harness's app
private let visible = Rect(x: 0, y: 25, width: 1440, height: 875)
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2)

private func performs(_ effects: [ArrangerEffect]) -> Int {
    effects.filter { if case .perform = $0 { true } else { false } }.count
}

/// [a | b | Desktop].
private func twoDocked() async -> Harness {
    var harness = await Harness.started()
    await harness.send(.command(.dock, focused: a))
    await harness.send(.command(.dock, focused: b))
    return harness
}

/// The tiles the Planner gives the current desk with `gap`.
private func tiles(_ harness: Harness, gap: Double) throws -> [WindowRef: Rect] {
    let desk = try #require(harness.arranger.world[key])
    return try Planner.plan(desk: desk, area: visible, gap: gap, mins: [:]).frames
}

/// TILE-08, D-23: while any pause reason is set Transom keeps tracking and applying facts but sends no window command;
/// leaving the paused state re-applies the layout once.
@Suite struct ArrangerPauseTests {
    @Test func whilePausedFactsApplyButNothingIsSentAndResumeReappliesTheLayout() async throws {
        var harness = await twoDocked()
        let tileB = try #require(await harness.frame(b))
        let pause = await harness.send(.command(.togglePause, focused: nil))
        #expect(harness.arranger.pauseReasons == [.user])
        #expect(performs(pause) == 0)

        // A close is still a fact: b's neighbour leaves the tree, but b is not grown yet.
        let closed = await harness.send(.event(.windowDestroyed(a)))
        #expect(performs(closed) == 0)
        #expect(harness.arranger.world[key]?.tree.state(of: a) == nil)
        // An app moving b is not corrected.
        let offTile = Rect(x: tileB.x + 40, y: tileB.y + 30, width: tileB.width, height: tileB.height)
        await harness.fake.userMove(2, to: offTile)
        let moved = await harness.refresh()
        #expect(performs(moved) == 0)
        #expect(await harness.frame(b) == offTile)

        let resume = await harness.send(.command(.togglePause, focused: nil))
        #expect(harness.arranger.pauseReasons.isEmpty)
        #expect(performs(resume) == 1)
        let expected = try #require(try tiles(harness, gap: 8)[b])
        #expect(setFrames(resume)[b] == expected)
        #expect(await harness.frame(b) == expected)
    }

    @Test func pausedCommandsAreRefusedButPauseItselfIsNot() async throws {
        var harness = await Harness.started()
        await harness.send(.command(.togglePause, focused: nil))
        let paused = CommandContext(focused: a, ready: true)
        #expect(!harness.arranger.availability(.dock, context: paused))
        #expect(!harness.arranger.availability(.finderSplit, context: paused))
        #expect(harness.arranger.availability(.togglePause, context: paused))
        #expect(harness.arranger.handle(.command(.dock, focused: a), now: .now) == [.beep])
        #expect(!harness.arranger.availability(.togglePause, context: CommandContext(focused: a, ready: false)))
    }

    @Test func stageManagerAloneCannotBeResumedFromTheMenu() async throws {
        var harness = await Harness.started()
        await harness.send(.setPaused(.stageManager, true))
        #expect(!harness.arranger.availability(.togglePause, context: CommandContext(focused: nil, ready: true)))
        #expect(harness.arranger.handle(.command(.togglePause, focused: nil), now: .now) == [.beep])

        await harness.send(.setPaused(.user, true))
        #expect(harness.arranger.availability(.togglePause, context: CommandContext(focused: nil, ready: true)))
        await harness.send(.command(.togglePause, focused: nil))
        #expect(harness.arranger.pauseReasons == [.stageManager], "Resume cleared Stage Manager's reason")
    }

    @Test func resumeClearsTheCrashLoopReasonToo() async throws {
        var harness = await twoDocked()
        await harness.send(.setPaused(.crashLoop, true))
        await harness.send(.setPaused(.user, true))
        await harness.send(.command(.togglePause, focused: nil))
        #expect(harness.arranger.pauseReasons.isEmpty)
    }

    @Test func pauseReasonsAreOrderedByPriority() {
        #expect(PauseReason.stageManager < .crashLoop && PauseReason.crashLoop < .user)
    }

    @Test func aGapChangeReplansAtOnce() async throws {
        var harness = await twoDocked()
        let effects = await harness.send(.gap(12))
        #expect(harness.arranger.gap == 12)
        let expected = try tiles(harness, gap: 12)
        #expect(setFrames(effects)[a] == expected[a] && setFrames(effects)[b] == expected[b])
        #expect(await harness.frame(a) == expected[a])
    }

    @Test func aGapChangeWhilePausedWaitsForResume() async throws {
        var harness = await twoDocked()
        await harness.send(.command(.togglePause, focused: nil))
        let tileA = await harness.frame(a)
        #expect(performs(await harness.send(.gap(12))) == 0)
        #expect(await harness.frame(a) == tileA)
        let resume = await harness.send(.command(.togglePause, focused: nil))
        let expected = try tiles(harness, gap: 12)
        #expect(setFrames(resume)[a] == expected[a] && setFrames(resume)[b] == expected[b])
    }
}
