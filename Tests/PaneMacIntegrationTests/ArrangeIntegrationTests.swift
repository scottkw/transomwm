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
