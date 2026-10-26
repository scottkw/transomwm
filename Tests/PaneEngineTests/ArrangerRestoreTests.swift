import Foundation
import PaneEngine
import PaneModel
import PaneTestSupport
import Testing

private let pid: Int32 = 900
private let bundleID = "com.example.arranger"
private let key = DeskKey(displayUUID: "main", spaceID: nil)

private func ref(_ id: UInt32) -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: pid, bundleID: bundleID))
}

private let a = ref(1), b = ref(2), c = ref(3), d = ref(4)

/// [a | b | Desktop] on the 1440 pt display.
private func twoDocked(frames: [UInt32: Rect]? = nil) async -> Harness {
    var harness = if let frames { await Harness.started(frames: frames) } else { await Harness.started() }
    await harness.send(.command(.dock, focused: a))
    await harness.send(.command(.dock, focused: b))
    return harness
}

private func saves(_ effects: [ArrangerEffect]) -> [SaveUrgency] {
    effects.compactMap { if case .save(let urgency) = $0 { urgency } else { nil } }
}

private func tracked(_ window: WindowRef, frame: Rect, idSource: WindowIDSource = .axPrivate, state: WindowState = .present) -> WindowInfo {
    WindowInfo(window: window, frame: frame, state: state, displayUUID: "main", idSource: idSource)
}

/// SAFE-06, D-16, D-17: the layout saved by the last session comes back by window identity, and only by identity.
@Suite struct ArrangerRestoreTests {
    @Test func reattachKeepsOnlyWindowsTrackedUnderTheSameRealID() async throws {
        // Saved: [a | b | Desktop], c floating.
        let harness = await twoDocked(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120), 3: Rect(x: 1000, y: 600, width: 150, height: 120)])
        let saved = harness.arranger.world
        try #require(saved[key].map { Set($0.tree.windows) } == [a, b] && saved[key]?.desktop.contains(c) == true)
        let frame = Rect(x: 10, y: 40, width: 200, height: 200)

        let kept = try LayoutRestore.reattach(saved, tracked: [tracked(a, frame: frame), tracked(b, frame: frame, idSource: .cgFrameMatch)])
        #expect(kept.world[key].map { Set($0.tree.windows) } == [a, b])
        #expect(kept.removed == [c])
        #expect(kept.unplaced.isEmpty)

        let synthetic = try LayoutRestore.reattach(
            saved, tracked: [tracked(a, frame: frame, idSource: .synthetic), tracked(b, frame: frame), tracked(d, frame: frame)])
        let desk = try #require(synthetic.world[key])
        #expect(desk.tree.windows == [b])
        #expect(!desk.contains(a) && !desk.contains(c))
        #expect(Set(synthetic.removed) == [a, c])
        // a is tracked but its synthetic ID is session-only, so it is placed afresh, like d.
        #expect(Set(synthetic.unplaced.map(\.window)) == [a, d])
    }

    @Test func aRestoreWaitsForTheFirstCompleteInventoryAndThenMovesNothing() async throws {
        let source = await twoDocked()
        let saved = source.arranger.snapshot.world
        let gone = WindowIdentity(windowID: 99, pid: pid, bundleID: bundleID)
        let home = Rect(x: 100, y: 100, width: 300, height: 200)
        var restored = Arranger()
        #expect(restored.handle(.restore(saved, homeFrames: [a.identity: home, gone: home]), now: .now).isEmpty)

        var inventory = await source.fake.inventory()
        inventory.initialRefreshComplete = false
        #expect(restored.handle(.inventory(inventory), now: .now).isEmpty)
        #expect(restored.world == World(), "an incomplete inventory changed the World")
        #expect(restored.snapshot.world == saved, "a pending restore must still be what is saved")

        inventory.initialRefreshComplete = true
        let effects = restored.handle(.inventory(inventory), now: .now)
        #expect(restored.world == saved)
        #expect(setFrames(effects).isEmpty, "an unchanged layout was written: \(setFrames(effects))")
        #expect(saves(effects) == [.debounced])
        #expect(restored.homeFrames == [a.identity: home], "a home frame of an untracked window was kept")
        #expect(restored.history.depth(for: key) == 0)
    }

    @Test func reattachAppliesRealStatesAndFloatsWindowsTheLayoutDoesNotKnow() async throws {
        let source = await twoDocked()
        let saved = source.arranger.world
        let tileB = try #require(await source.frame(b))
        await source.fake.update(1) { $0.snapshot.minimized = true }
        await source.fake.open(.standard(id: 3, pid: pid, frame: Rect(x: 1000, y: 600, width: 150, height: 120)))
        await source.fake.refreshAll()
        await source.fake.advance(by: .milliseconds(300))  // a new window waits out the settle delay
        await source.fake.refreshAll()
        _ = await source.inbox.take()

        var restored = Arranger()
        _ = restored.handle(.restore(saved, homeFrames: [:]), now: .now)
        let effects = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        let desk = try #require(restored.world[key])
        #expect(desk.tree.state(of: a) == .absent)
        #expect(desk.tree.state(of: b) == .present)
        #expect(desk.desktop.frame(of: c) == Rect(x: 1000, y: 600, width: 150, height: 120))
        // b takes a's room while a is minimised; nothing else moves.
        let frames = setFrames(effects)
        #expect(Set(frames.keys) == [b])
        #expect(try #require(frames[b]).width > tileB.width)
    }

    @Test func everyWorldChangeAsksForADebouncedSave() async throws {
        var harness = await Harness.started()
        #expect(saves(await harness.send(.command(.dock, focused: a))) == [.debounced])
        #expect(saves(await harness.send(.command(.float, focused: a))) == [.debounced])
        await harness.fake.userMove(2, to: Rect(x: 900, y: 300, width: 150, height: 120))
        #expect(saves(await harness.refresh()) == [.debounced])
        // Nothing changed: no save.
        #expect(saves(await harness.send(.command(.float, focused: b))).isEmpty)
    }

    @Test func aLayoutRoundTripsThroughLayoutFileIntoAFreshArranger() async throws {
        let source = await twoDocked()
        let snapshot = source.arranger.snapshot
        let file = LayoutFile(world: snapshot.world, homeFrames: snapshot.homeFrames, session: SessionRecord(cleanExit: false, launchedAt: Date()))
        let decoded = try JSONDecoder().decode(LayoutFile.self, from: try JSONEncoder().encode(file))
        #expect(decoded == file)

        var restored = Arranger()
        _ = restored.handle(.restore(decoded.world, homeFrames: decoded.homeFrameMap), now: .now)
        let effects = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        #expect(restored.world == source.arranger.world)
        #expect(setFrames(effects).isEmpty)
    }
}
