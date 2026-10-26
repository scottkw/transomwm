import Foundation
import PaneEngine
@testable import PaneMac
import PaneModel
import Testing

/// A system and an ArrangeController that track only `fixture`, started, with every fixture window on a desk.
@MainActor private func arranging(_ fixture: FixtureProcess) async throws -> (ArrangeController, [PaneModel.WindowRef]) {
    let fixturePID = fixture.pid
    let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
    await system.start()
    let arrange = ArrangeController(system: system)
    await arrange.start()
    var refs: [PaneModel.WindowRef] = []
    for window in fixture.windows {
        func find() -> PaneModel.WindowRef? {
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

/// Two fixture windows docked side by side: [0 | 1 | Desktop]. Returns the controller, the refs and both tile frames.
@MainActor private func dockedPair(_ fixture: FixtureProcess) async throws -> (ArrangeController, [PaneModel.WindowRef], Rect, Rect) {
    let (arrange, refs) = try await arranging(fixture)
    try #require(refs.count == 2)
    let visible = try mainVisibleFrame()
    // Dock acts where a drop at the window's centre lands (D-12), so place both centres at mid-height: window 0
    // in the left part of the screen, window 1 just right of the middle, in the Desktop tile's left edge band
    // once window 0 has docked. Then window 1 docks beside window 0 on any display size.
    let placed = [(visible.minX + visible.width * 0.15, visible.midY), (visible.midX + visible.width * 0.1, visible.midY)]
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

/// TILE-03, D-12, TILE-20, WIN-07 live: Pane docks fixture windows (only ones these tests launched) into
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

    /// D-26 live: window 0's real minimum is learned only after it docks, and with window 1's it leaves no room for
    /// both tiles beside the Desktop tile. Window 0 floats to the Desktop tile and no longer overlaps window 1.
    @Test(.timeLimit(.minutes(1)))
    func aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop() async throws {
        let visible = try mainVisibleFrame()
        // The Arranger's inner width (8 pt gaps at the area edges). [0 | 1 | Desktop] needs min0 + min1 + 17; with
        // window 0 floating, [1 | Desktop] needs min1 + min0 + 8. A sum of inner - 14 fails the first and passes
        // the second, with 2 pt to spare either way.
        let inner = (visible.maxX.rounded(.down) - 8) - (visible.minX.rounded(.up) + 8)
        let min0 = Int(inner * 0.55), min1 = Int(inner) - 14 - min0
        let fixture = try await FixtureProcess.launch(["minsize:\(min0)x150", "minsize:\(min1)x150"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await arranging(fixture)
        defer { withExtendedLifetime(arrange) {} }  // its events loop ends with it
        let height = 300.0, top = (visible.midY - height / 2).rounded()

        // Both start wider than their minimums, so a refused tile write moves them toward it: that is how a
        // minimum is learned (02-15). Window 0's centre is in the left half, so it docks on the left.
        _ = try await fixture.send("resize 0 \(min0 + 40) \(Int(height))")
        _ = try await fixture.send("resize 1 \(min1 + 40) \(Int(height))")
        _ = try await fixture.send("move 0 \(Int(visible.minX) + 40) \(Int(top))")
        let moved = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[refs[0].identity].map { abs($0.frame.x - visible.minX - 40) <= 1 } ?? false
        }
        try #require(moved, "the Arranger never saw window 0 move")
        await arrange.dispatch(.dock, focused: refs[0])
        let learned = await waitUntil(timeout: .seconds(4)) { arrange.arranger.windows[refs[0].identity]?.learnedMinimum != nil }
        try #require(learned, "window 0's minimum was never learned")

        // Window 1's centre at mid-height inside the Desktop tile, so Dock puts it beside that tile, in the same row.
        let key = try #require(arrange.arranger.deskKey(of: refs[0]))
        let desk = try #require(arrange.arranger.world[key])
        let mins = Dictionary(uniqueKeysWithValues: arrange.arranger.windows.values.compactMap { info in
            info.learnedMinimum.map { (info.window, $0) }
        })
        let desktop = try #require(try Planner.plan(desk: desk, area: visible, gap: 8, mins: mins).desktopRect)
        _ = try await fixture.send("move 1 \(Int(desktop.minX)) \(Int(top))")
        let seen = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[refs[1].identity].map { abs($0.frame.x - desktop.minX) <= 1 } ?? false
        }
        try #require(seen, "the Arranger never saw window 1 move")
        await arrange.dispatch(.dock, focused: refs[1])
        try #require(arrange.arranger.world[key]?.tree.state(of: refs[1]) == .present, "window 1 did not dock")

        var frames: [Rect] = []
        let floated = await waitUntil(timeout: .seconds(5)) {
            guard let desk = arrange.arranger.world[key], desk.desktop.contains(refs[0]), desk.tree.state(of: refs[1]) == .present,
                let f0 = try? await listedFrame(fixture, 0), let f1 = try? await listedFrame(fixture, 1)
            else { return false }
            frames = [f0, f1]
            return !f0.overlaps(f1)
        }
        #expect(floated, "window 0 did not float clear of window 1 within 5 s (fixture frames \(frames))")
    }

    /// Native fullscreen moves the window to its own Space, so macOS switches Spaces; opt in with PANE_LIVE_FULLSCREEN=1.
    @Test(
        .timeLimit(.minutes(1)),
        .enabled(if: ProcessInfo.processInfo.environment["PANE_LIVE_FULLSCREEN"] != nil, "switches Spaces; set PANE_LIVE_FULLSCREEN=1")
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
