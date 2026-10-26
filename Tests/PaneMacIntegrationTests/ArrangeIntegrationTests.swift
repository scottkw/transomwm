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

/// TILE-03, D-12 live: Pane docks fixture windows (only ones these tests launched) into non-overlapping tiles and
/// reflows when one closes.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct ArrangeIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func twoDockedWindowsTileWithoutOverlapAndReflowOnClose() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, refs) = try await arranging(fixture)
        try #require(refs.count == 2)
        let visible = try mainVisibleFrame()

        await arrange.dispatch(.dock, focused: refs[0])
        await arrange.dispatch(.dock, focused: refs[1])
        var frames: [Rect] = []
        let tiled = await waitUntil(timeout: .seconds(2)) {
            guard let a = try? await listedFrame(fixture, 0), let b = try? await listedFrame(fixture, 1) else { return false }
            frames = [a, b]
            return inside(a, visible) && inside(b, visible) && !a.overlaps(b)
        }
        #expect(tiled, "fixture frames \(frames) are not two non-overlapping tiles inside \(visible)")

        let before = try #require(try await listedFrame(fixture, 0))
        _ = try await fixture.send("close 1")
        var after = before
        let grew = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await listedFrame(fixture, 0) else { return false }
            after = now
            return now.width > before.width + 1 || now.height > before.height + 1
        }
        #expect(grew, "window 0 stayed \(after) after its neighbour closed (was \(before))")
    }
}
