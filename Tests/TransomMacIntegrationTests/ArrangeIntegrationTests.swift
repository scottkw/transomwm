import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// A system and an ArrangeController that track only `fixture`, started, with every fixture window on a desk.
@MainActor private func arranging(_ fixture: FixtureProcess, store: LayoutStore? = nil) async throws -> (ArrangeController, [TransomModel.WindowRef]) {
    let fixturePID = fixture.pid
    let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
    await system.start()
    let arrange = ArrangeController(system: system, store: store)
    await arrange.start()
    var refs: [TransomModel.WindowRef] = []
    for window in fixture.windows {
        func find() -> TransomModel.WindowRef? {
            arrange.arranger.windows.values.first { $0.window.pid == fixturePID && $0.window.windowID == window.id }?.window
        }
        _ = await waitUntil(timeout: .seconds(3)) { find().map { arrange.arranger.deskKey(of: $0) != nil } ?? false }
        let ref = try #require(find(), "window \(window.id) never reached the Arranger")
        try #require(arrange.arranger.deskKey(of: ref) != nil, "window \(window.id) is on no desk")
        refs.append(ref)
    }
    return (arrange, refs)
}

/// The main display's visible frame, top-left (what the Arranger lays out in).
@MainActor private func mainVisibleFrame() throws -> Rect {
    try #require(Displays.current().first).visibleFrame
}

/// The fixture's current frame for window `index`, from `list`.
private func listedFrame(_ fixture: FixtureProcess, _ index: Int) async throws -> Rect? {
    _ = try await fixture.send("list")
    return fixture.windows.first { $0.index == index }?.frame
}

/// Inside `outer`, allowing 1 pt for the fixture's integer rounding.
private func inside(_ rect: Rect, _ outer: Rect) -> Bool {
    rect.minX >= outer.minX - 1 && rect.minY >= outer.minY - 1 && rect.maxX <= outer.maxX + 1 && rect.maxY <= outer.maxY + 1
}

/// Within 2 pt on every side (the fixture reports whole points; AppKit may round a restored frame).
private func near(_ a: Rect, _ b: Rect) -> Bool {
    abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
}

/// Two fixture windows docked side by side: [0 | 1]. Returns the controller, the refs and both tile frames.
@MainActor private func dockedPair(
    _ fixture: FixtureProcess, store: LayoutStore? = nil
) async throws -> (ArrangeController, [TransomModel.WindowRef], Rect, Rect) {
    let (arrange, refs) = try await arranging(fixture, store: store)
    try #require(refs.count == 2)
    let visible = try mainVisibleFrame()
    // Dock acts where a drop at the window's centre lands (D-12), so place both centres at mid-height: window 0
    // in the left part of the screen, window 1 in the right edge band of window 0's tile, which fills the visible
    // frame once window 0 has docked. Then window 1 docks beside window 0 on any display size.
    let placed = [(visible.minX + visible.width * 0.15, visible.midY), (visible.minX + visible.width * 0.85, visible.midY)]
    for (index, centre) in placed.enumerated() {
        let size = try #require(fixture.windows.first { $0.index == index }).frame.size
        let x = (centre.0 - size.width / 2).rounded(), y = (centre.1 - size.height / 2).rounded()
        _ = try await fixture.send("move \(index) \(Int(x)) \(Int(y))")
        let seen = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[refs[index].identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
        }
        try #require(seen, "the Arranger never saw window \(index) move")
    }

    await arrange.dispatch(.dock, focused: refs[0])
    await arrange.dispatch(.dock, focused: refs[1])
    var frames: [Rect] = []
    let tiled = await waitUntil(timeout: .seconds(2)) {
        guard let a = try? await listedFrame(fixture, 0), let b = try? await listedFrame(fixture, 1) else { return false }
        frames = [a, b]
        return inside(a, visible) && inside(b, visible) && !a.overlaps(b) && a.maxX < b.minX
    }
    try #require(tiled, "fixture frames \(frames) are not two side-by-side tiles inside \(visible)")
    return (arrange, refs, frames[0], frames[1])
}

/// Whether the Arranger sees `window` within 1 pt of `frame` within 2 s.
@MainActor private func seen(_ arrange: ArrangeController, _ window: TransomModel.WindowRef, _ frame: Rect) async -> Bool {
    await waitUntil(timeout: .seconds(2)) {
        arrange.arranger.windows[window.identity].map { info in
            abs(info.frame.x - frame.x) <= 1 && abs(info.frame.y - frame.y) <= 1
                && abs(info.frame.width - frame.width) <= 1 && abs(info.frame.height - frame.height) <= 1
        } ?? false
    }
}

/// Polls window `index`'s listed frame until `condition` holds; returns that frame, or nil after `timeout`.
private func waitFor(_ fixture: FixtureProcess, _ index: Int, timeout: Duration, _ condition: @escaping @Sendable (Rect) -> Bool) async -> Rect? {
    var last: Rect?
    let met = await waitUntil(timeout: timeout) {
        last = try? await listedFrame(fixture, index)
        return last.map(condition) ?? false
    }
    return met ? last : nil
}

private func grew(_ before: Rect) -> @Sendable (Rect) -> Bool {
    { $0.width > before.width + 1 || $0.height > before.height + 1 }
}

/// TILE-03, D-12, TILE-20, WIN-07 live: Transom docks fixture windows (only ones these tests launched) into
/// non-overlapping tiles, and reflows when one closes, minimises or goes fullscreen.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ArrangeIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func twoDockedWindowsTileWithoutOverlapAndReflowOnClose() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, _, a, _) = try await dockedPair(fixture)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        _ = try await fixture.send("close 1")
        let after = await waitFor(fixture, 0, timeout: .seconds(3), grew(a))
        #expect(after != nil, "window 0 stayed \(a) after its neighbour closed")
    }

    @Test(.timeLimit(.minutes(1)))
    func aMinimisedDockedWindowLendsItsTileAndComesBack() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, _, a, b) = try await dockedPair(fixture)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        _ = try await fixture.send("minimize 0")
        #expect(await waitFor(fixture, 1, timeout: .seconds(3), grew(b)) != nil, "window 1 did not grow while window 0 was minimised")
        _ = try await fixture.send("deminimize 0")
        #expect(await waitFor(fixture, 0, timeout: .seconds(3)) { near($0, a) } != nil, "window 0 did not return to \(a)")
        #expect(await waitFor(fixture, 1, timeout: .seconds(3)) { near($0, b) } != nil, "window 1 did not shrink back to \(b)")
    }

    /// TILE-13 live: ⌃⌥⌘⇧← on the right-hand window of [0 | 1] moves it into window 0's tile area.
    @Test(.timeLimit(.minutes(1)))
    func moveLeftPutsTheRightWindowWhereTheLeftOneWas() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, refs, a, _) = try await dockedPair(fixture)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        await arrange.dispatch(.moveOrSnap(.left), focused: refs[1])
        var frames: [Rect] = []
        let moved = await waitUntil(timeout: .seconds(2)) {
            guard let f0 = try? await listedFrame(fixture, 0), let f1 = try? await listedFrame(fixture, 1) else { return false }
            frames = [f0, f1]
            return f1.minX >= a.minX - 1 && f1.maxX <= a.maxX + 1 && !f0.overlaps(f1)
        }
        #expect(moved, "window 1 is not in \(a)'s x-range clear of window 0 (fixture frames \(frames))")
    }

    /// D-26 live: window 0's real minimum is learned only once it shares the desk, and with window 1's it leaves no room
    /// for both tiles. Window 0, the larger minimum, floats on screen at its own frame (08.1.1 D-05) and window 1 takes
    /// the whole visible frame.
    @Test(.timeLimit(.minutes(1)))
    func aDockedWindowThatTurnsOutTooBigFloatsOnScreen() async throws {
        let visible = try mainVisibleFrame()
        // The Arranger's inner width (8 pt gaps at the area edges); each half of [0 | 1] is (inner - 8) / 2. min0 refuses
        // its half and, once min0 is learned, min1 refuses what is left beside it, each by more than the learner's 32 pt
        // margin. min0 + min1 + 8 > inner, so with both learned window 0, the larger, is unfit.
        let inner = (visible.maxX.rounded(.down) - 8) - (visible.minX.rounded(.up) + 8)
        let min0 = Int(inner * 0.6), min1 = Int(inner * 0.45)
        let fixture = try await FixtureProcess.launch(["minsize:\(min0)x150", "minsize:\(min1)x150"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await arranging(fixture)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        let height = 300.0, top = (visible.midY - height / 2).rounded()

        // Both start wider than their minimums, so a refused tile write moves them toward it: that is how a
        // minimum is learned (02-15). The whole frame, not just x: a write is learned from only if the tracker saw the
        // window at its size first.
        _ = try await fixture.send("resize 0 \(min0 + 40) \(Int(height))")
        _ = try await fixture.send("resize 1 \(min1 + 40) \(Int(height))")
        let start0 = Rect(x: visible.minX + 40, y: top, width: Double(min0 + 40), height: height)
        let start1 = Rect(x: (visible.maxX - 40 - Double(min1 + 40)).rounded(), y: top, width: Double(min1 + 40), height: height)
        _ = try await fixture.send("move 0 \(Int(start0.x)) \(Int(start0.y))")
        _ = try await fixture.send("move 1 \(Int(start1.x)) \(Int(start1.y))")
        try #require(await seen(arrange, refs[0], start0), "the Arranger never saw window 0 at \(start0)")
        try #require(await seen(arrange, refs[1], start1), "the Arranger never saw window 1 at \(start1)")

        await arrange.dispatch(.dock, focused: refs[0])  // the empty desk's root
        await arrange.dispatch(.dockFourth(.secondHalf, .horizontal), focused: refs[1])  // the right half beside it
        let key = try #require(arrange.arranger.deskKey(of: refs[0]))
        try #require(arrange.arranger.world[key]?.tree.state(of: refs[1]) == .present, "window 1 did not dock")

        var frames: [Rect] = []
        let floated = await waitUntil(timeout: .seconds(10)) {
            guard let desk = arrange.arranger.world[key], desk.desktop.contains(refs[0]), desk.tree.windows == [refs[1]],
                let f0 = try? await listedFrame(fixture, 0), let f1 = try? await listedFrame(fixture, 1)
            else { return false }
            frames = [f0, f1]
            return inside(f0, visible) && f1.width >= inner - 2
        }
        let learned = refs.map { arrange.arranger.windows[$0.identity]?.learnedMinimum }
        #expect(floated, "window 0 did not float on screen beside a full-width window 1 within 10 s (fixture frames \(frames), learned \(learned))")
    }

    /// SAFE-06 live: a fresh window system and controller on the same layout.json, with the fixture still running,
    /// put each docked window back in its tile and move nothing. The store is a temporary directory, never the
    /// user's real layout.json.
    @Test(.timeLimit(.minutes(1)))
    func aFreshControllerOnTheSameStoreReattachesDockedWindowsWithoutMovingThem() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "transom-layout-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, refs, a, b) = try await dockedPair(fixture, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        let saved = await waitUntil(timeout: .seconds(2)) {
            let store = LayoutStore(directory: directory)
            store.load()
            return store.contents.map { $0.world == arrange.arranger.world && $0.world.desks.values.contains { $0.tree.windows.count == 2 } } ?? false
        }
        try #require(saved, "layout.json never held the docked pair")

        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let fresh = ArrangeController(system: system, store: LayoutStore(directory: directory))
        defer { withExtendedLifetime(fresh) {} }
        await fresh.start()
        let same = await waitUntil(timeout: .seconds(5)) { fresh.arranger.world == arrange.arranger.world }
        #expect(same, "the fresh controller's World differs from the saved one")
        #expect(refs.allSatisfy { ref in fresh.arranger.world.desks.values.contains { $0.tree.state(of: ref) == .present } })
        try await Task.sleep(for: .milliseconds(500))  // room for any write the fresh controller made to land
        let after = [try await listedFrame(fixture, 0), try await listedFrame(fixture, 1)]
        #expect(after[0].map { near($0, a) } == true && after[1].map { near($0, b) } == true, "fixture frames moved: \(after) vs \([a, b])")
    }

    /// Native fullscreen moves the window to its own Space, so macOS switches Spaces; opt in with TRANSOM_LIVE_FULLSCREEN=1.
    @Test(
        .timeLimit(.minutes(1)),
        .enabled(if: ProcessInfo.processInfo.environment["TRANSOM_LIVE_FULLSCREEN"] != nil, "switches Spaces; set TRANSOM_LIVE_FULLSCREEN=1")
    )
    func aFullscreenDockedWindowKeepsItsTileAndComesBack() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, _, a, b) = try await dockedPair(fixture)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        do {
            _ = try await fixture.send("fullscreen 0", timeout: .seconds(6))
            #expect(await waitFor(fixture, 1, timeout: .seconds(5), grew(b)) != nil, "window 1 did not grow while window 0 was fullscreen")
            _ = try await fixture.send("exit-fullscreen 0", timeout: .seconds(6))
            #expect(await waitFor(fixture, 0, timeout: .seconds(5)) { near($0, a) } != nil, "window 0 did not return to \(a)")
        } catch {
            // Never leave a fixture window fullscreen (it would hold its own Space).
            _ = try? await fixture.send("exit-fullscreen 0", timeout: .seconds(6))
            throw error
        }
    }
}
