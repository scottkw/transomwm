import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// TILE-21 on real windows. VM only: it opens and moves windows.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "moves real windows; VM only"))
@MainActor struct NewWindowsIntegrationTests {
    /// Connects to the window server first, as ZoomSettleIntegrationTests does.
    init() { _ = NSApplication.shared }

    /// Opens `spec` and returns the fixture's lines for its windows. Their frames may be Transom's already: the fixture
    /// prints after its settle delay, so use `openingFrame(of:)` for where one opened.
    private func open(_ spec: String, in fixture: FixtureProcess) async throws -> [FixtureWindow] {
        try await fixture.send("open \(spec)").compactMap(FixtureWindow.init(line:))
    }

    /// Where the fixture opens its window number `index` (`TransomFixtureApp.open`).
    private func openingFrame(of index: Int) -> Rect {
        Rect(x: 40 + 40 * Double(index), y: 80 + 40 * Double(index), width: 320, height: 232)
    }

    @Test(.timeLimit(.minutes(1)))
    func aNewWindowDocksWhenTileIsChosen() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let (arrange, _) = try await LiveArrange.start(fixture)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.setNewWindows(.tile)
        let visible = try LiveArrange.visibleFrame()

        let new = try #require(try await open("standard", in: fixture).first, "the fixture opened nothing")

        func ref() -> TransomModel.WindowRef? {
            arrange.arranger.windows.values.first { $0.window.pid == fixture.pid && $0.window.windowID == new.id }?.window
        }
        let docked = await waitUntil(timeout: .seconds(3)) { ref().map { !arrange.arranger.isFloating($0) && arrange.arranger.deskKey(of: $0) != nil } ?? false }
        try #require(docked, "the new window never docked")
        let window = try #require(ref())
        let key = try #require(arrange.arranger.deskKey(of: window))
        let desk = try #require(arrange.arranger.world[key])
        #expect(desk.tree.windows == [window], "the window found at launch must not dock: \(desk.tree.windows)")
        let index = new.index
        let opened = openingFrame(of: index)
        var last: Rect?
        let inPlace = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, index) else { return false }
            last = now
            guard let planned = try? Planner.plan(desk: desk, area: visible, gap: arrange.arranger.gap, mins: [:]).frames[window] else { return false }
            return LiveArrange.inside(now, visible) && LiveArrange.near(now, planned)
        }
        #expect(inPlace, "the window is at \(String(describing: last)), inside \(visible)")

        await arrange.dispatch(.undo, focused: window)
        let floated = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, index) else { return false }
            last = now
            return arrange.arranger.isFloating(window) && LiveArrange.near(now, opened)
        }
        #expect(floated, "undo left it at \(String(describing: last)), opened at \(opened)")
    }
}
