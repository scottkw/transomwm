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

    /// WR-04: one window whose live frame cannot be recorded must not throw the whole saved layout away (the next
    /// save would then overwrite layout.json with it).
    @Test func aWindowWhoseFrameCannotBeRecordedDoesNotLoseTheSavedLayout() async throws {
        let source = await twoDocked(frames: [1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120), 3: Rect(x: 1000, y: 600, width: 150, height: 120)])
        let saved = source.arranger.snapshot.world
        try #require(saved[key]?.desktop.contains(c) == true)
        var inventory = await source.fake.inventory()
        let i = try #require(inventory.windows.firstIndex { $0.window == c })
        inventory.windows[i].frame = Rect(x: 2_000_000, y: 0, width: 150, height: 120)  // out of range: not recordable
        var restored = Arranger()
        _ = restored.handle(.restore(saved, homeFrames: [:]), now: .now)

        let effects = restored.handle(.inventory(inventory), now: .now)

        #expect(restored.world[key].map { Set($0.tree.windows) } == [a, b], "the saved layout was dropped")
        #expect(restored.world[key]?.desktop.frame(of: c) == saved[key]?.desktop.frame(of: c))
        #expect(effects.contains { if case .fault = $0 { true } else { false } })
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

private func performs(_ effects: [ArrangerEffect]) -> [[WindowCommand]] {
    effects.compactMap { if case .perform(let commands) = $0 { commands } else { nil } }
}

private func notices(_ effects: [ArrangerEffect]) -> [Notice] {
    effects.compactMap { if case .notice(let notice) = $0 { notice } else { nil } }
}

private let visibleFrame = Rect(x: 0, y: 25, width: 1440, height: 875)

/// SAFE-02, D-17: the launch after a crash brings stranded windows on screen first, then re-applies the layout.
extension ArrangerRestoreTests {
    /// [a | b | Desktop] saved, then a pushed to x = 10000; a fresh Arranger on a recovery launch.
    private func recovering(_ mode: LaunchMode = .recovery) async throws -> (Arranger, [ArrangerEffect], tileA: Rect, saved: World) {
        let source = await twoDocked()
        let saved = source.arranger.snapshot.world
        let tileA = try #require(await source.frame(a))
        await source.fake.userMove(1, to: Rect(x: 10000, y: 100, width: tileA.width, height: tileA.height))
        await source.fake.refreshAll()
        var restored = Arranger()
        _ = restored.handle(.launch(mode), now: .now)
        _ = restored.handle(.restore(saved, homeFrames: [:]), now: .now)
        let effects = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        return (restored, effects, tileA, saved)
    }

    @Test func aRecoveryLaunchMovesTheStrandedWindowOnScreenBeforeReapplyingTheLayout() async throws {
        let (restored, effects, tileA, saved) = try await recovering()
        let sent = performs(effects)
        try #require(sent.count == 2, "expected the rescue, then the layout: \(effects)")
        try #require(sent[0].count == 1)
        guard case .setFrame(let window, let rescue) = sent[0][0] else {
            Issue.record("the first command is not a frame write: \(sent[0])")
            return
        }
        #expect(window == a)
        #expect(inside(rescue, visibleFrame), "\(rescue) is not on screen")
        #expect(rescue.size == tileA.size, "the window kept its size")
        #expect(sent[1].contains(.setFrame(a, tileA)), "the layout was not re-applied: \(sent[1])")
        #expect(restored.world == saved)
        #expect(notices(effects) == [.crashRecovered(unplaced: 0)])
        let lastPerform = try #require(effects.lastIndex { if case .perform = $0 { true } else { false } })
        let notice = try #require(effects.firstIndex { if case .notice = $0 { true } else { false } })
        #expect(notice > lastPerform, "N2 comes after the layout is re-applied")
    }

    @Test func aNormalLaunchShowsNoRecoveryNoticeAndRescuesNothing() async throws {
        let (_, effects, tileA, _) = try await recovering(.normal)
        #expect(notices(effects).isEmpty)
        #expect(performs(effects).count == 1)
        #expect(setFrames(effects) == [a: tileA])
    }

    @Test func aSavedWindowNoLongerTrackedIsNotCountedAsUnplaced() async throws {
        let source = await twoDocked()
        let saved = source.arranger.snapshot.world
        await source.fake.close(2)
        await source.fake.refreshAll()
        var restored = Arranger()
        _ = restored.handle(.launch(.recovery), now: .now)
        _ = restored.handle(.restore(saved, homeFrames: [:]), now: .now)
        let effects = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        #expect(notices(effects) == [.crashRecovered(unplaced: 0)])
    }

    @Test func aTrackedWindowTheSavedLayoutDoesNotKnowIsCountedAsUnplaced() async throws {
        let source = await twoDocked()
        let saved = source.arranger.snapshot.world
        await source.fake.open(.standard(id: 3, pid: pid, frame: Rect(x: 1000, y: 600, width: 150, height: 120)))
        await source.fake.refreshAll()
        await source.fake.advance(by: .milliseconds(300))  // a new window waits out the settle delay
        await source.fake.refreshAll()
        var restored = Arranger()
        _ = restored.handle(.launch(.recovery), now: .now)
        _ = restored.handle(.restore(saved, homeFrames: [:]), now: .now)
        let effects = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        #expect(notices(effects) == [.crashRecovered(unplaced: 1)])
        #expect(restored.world[key]?.desktop.contains(c) == true)
    }

    /// The human check's case: a hidden Desktop with a parked floating window. The parked window comes back at its home
    /// frame and the Desktop tile shows again, so the next plan does not park it again.
    @Test func aRecoveryLaunchUnparksAWindowParkedByAHiddenDesktop() async throws {
        var source = await twoDocked(frames: [
            1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120),
            3: Rect(x: 1000, y: 600, width: 150, height: 120),
        ])
        let home = Rect(x: 1000, y: 600, width: 150, height: 120)
        await source.send(.command(.toggleDesktop, focused: a))
        try #require(source.arranger.world[key]?.tree.isDesktopHidden == true)
        let parked = try #require(await source.frame(c))
        try #require(Recovery.isStranded(parked, displays: [DisplayInfo(uuid: "main", frame: visibleFrame, visibleFrame: visibleFrame, currentSpaceID: nil)]))
        let snapshot = source.arranger.snapshot
        try #require(snapshot.homeFrames[c.identity] == home)

        var restored = Arranger()
        _ = restored.handle(.launch(.recovery), now: .now)
        _ = restored.handle(.restore(snapshot.world, homeFrames: snapshot.homeFrames), now: .now)
        let effects = restored.handle(.inventory(await source.fake.inventory()), now: .now)
        let sent = performs(effects)
        try #require(!sent.isEmpty)
        #expect(sent[0] == [.setFrame(c, home)])
        #expect(!sent.joined().contains(.park(c, displayUUID: "main")), "the parked window was parked again")
        #expect(restored.world[key]?.tree.isDesktopHidden != true)
        #expect(restored.world[key]?.desktop.frame(of: c) == home)
        #expect(notices(effects) == [.crashRecovered(unplaced: 0)])
    }

    /// D-18: a crash loop starts paused. Stranded windows still come on screen; nothing else moves until Resume.
    @Test func aCrashLoopLaunchStartsPausedButStillRescuesStrandedWindows() async throws {
        let (launched, effects, tileA, saved) = try await recovering(.crashLoop)
        var restored = launched
        #expect(restored.pauseReasons.contains(.crashLoop))
        let sent = performs(effects)
        try #require(sent.count == 1, "only the rescue is sent while paused: \(effects)")
        #expect(sent[0].count == 1)
        guard case .setFrame(a, let rescue)? = sent[0].first else {
            Issue.record("the rescue is not a's frame write: \(sent[0])")
            return
        }
        #expect(inside(rescue, visibleFrame))
        #expect(notices(effects) == [.crashLoop])
        #expect(restored.world == saved, "the layout is restored in the model, only not applied")

        let resumed = restored.handle(.command(.togglePause, focused: nil), now: .now)
        #expect(restored.pauseReasons.isEmpty)
        #expect(setFrames(resumed)[a] == tileA, "Resume did not re-apply the layout: \(resumed)")
    }
}

/// SAFE-03: Restore All Windows brings every window Pane may move back on screen, on demand, even while paused.
extension ArrangerRestoreTests {
    private static let home = Rect(x: 1000, y: 600, width: 150, height: 120)

    /// [a | b | Desktop] with c floating at `home`, the Desktop hidden so c is parked.
    private func parkedC() async throws -> Harness {
        var harness = await twoDocked(frames: [
            1: Rect(x: 40, y: 80, width: 320, height: 232), 2: Rect(x: 730, y: 400, width: 150, height: 120), 3: Self.home,
        ])
        await harness.send(.command(.toggleDesktop, focused: a))
        try #require(harness.arranger.world[key]?.tree.isDesktopHidden == true)
        let parked = try #require(await harness.frame(c))
        try #require(!inside(parked, visibleFrame), "c was not parked: \(parked)")
        return harness
    }

    /// Pushes b far off screen while paused, so nothing puts it back.
    private func strandB(_ harness: inout Harness) async throws {
        let tileB = try #require(await harness.frame(b))
        await harness.fake.userMove(2, to: Rect(x: 10000, y: 100, width: tileB.width, height: tileB.height))
        _ = await harness.refresh()
        try #require(harness.arranger.windows[b.identity]?.frame.x == 10000)
    }

    @Test func restoreAllShowsTheHiddenDesktopAndMovesAnOffScreenWindowEvenWhilePaused() async throws {
        var harness = try await parkedC()
        await harness.send(.command(.togglePause, focused: nil))
        try await strandB(&harness)
        let depth = harness.arranger.history.depth(for: key)

        let effects = await harness.send(.command(.restoreAll, focused: nil))
        let frames = setFrames(effects)
        #expect(frames[c] == Self.home, "the parked window did not go back to its home frame")
        #expect(frames[b].map { inside($0, visibleFrame) } == true, "b is not back on screen: \(String(describing: frames[b]))")
        #expect(notices(effects) == [.restored(count: 2)])
        #expect(harness.arranger.world[key]?.tree.isDesktopHidden != true)
        #expect(harness.arranger.world[key]?.desktop.frame(of: c) == Self.home)
        #expect(harness.arranger.history.depth(for: key) == depth + 1, "showing the Desktop is the undoable part")
        #expect(harness.arranger.pauseReasons == [.user], "Restore All does not resume arranging")
        #expect(await harness.frame(c) == Self.home)
    }

    @Test func restoreAllWithNoHiddenDesktopAddsNoUndoStep() async throws {
        var harness = await twoDocked()
        await harness.send(.command(.togglePause, focused: nil))
        try await strandB(&harness)
        let depth = harness.arranger.history.depth(for: key)
        let effects = await harness.send(.command(.restoreAll, focused: nil))
        #expect(setFrames(effects).keys.sorted { $0.identity < $1.identity } == [b])
        #expect(notices(effects) == [.restored(count: 1)])
        #expect(harness.arranger.history.depth(for: key) == depth)
    }

    @Test func restoreAllWhileArrangingPutsTheShownDesktopsWindowsHome() async throws {
        var harness = try await parkedC()
        let depth = harness.arranger.history.depth(for: key)
        let effects = await harness.send(.command(.restoreAll, focused: nil))
        #expect(performs(effects).first?.first == .setFrame(c, Self.home), "the rescue goes before the layout")
        #expect(notices(effects) == [.restored(count: 1)])
        #expect(harness.arranger.history.depth(for: key) == depth + 1)
        #expect(await harness.frame(c) == Self.home)
    }

    @Test func restoreAllWithNothingStrandedOnlySaysSo() async throws {
        var harness = await twoDocked()
        let world = harness.arranger.world
        let effects = await harness.send(.command(.restoreAll, focused: nil))
        #expect(performs(effects).isEmpty)
        #expect(notices(effects) == [.restored(count: 0)])
        #expect(harness.arranger.world == world)
    }

    @Test func restoreAllIsAvailableWhilePausedForAnyReasonButNotWithoutAccess() async throws {
        var harness = await Harness.started()
        let ready = CommandContext(focused: nil, ready: true)
        #expect(harness.arranger.availability(.restoreAll, context: ready))
        await harness.send(.command(.togglePause, focused: nil))
        #expect(harness.arranger.availability(.restoreAll, context: ready))
        await harness.send(.setPaused(.stageManager, true))
        await harness.send(.setPaused(.crashLoop, true))
        #expect(harness.arranger.availability(.restoreAll, context: ready))
        #expect(!harness.arranger.availability(.restoreAll, context: CommandContext(focused: a, ready: false)))
    }
}

