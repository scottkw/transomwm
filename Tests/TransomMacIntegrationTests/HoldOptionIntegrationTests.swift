import CoreGraphics
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// TILE-22 on real windows: Hold ⌥ on posted title-bar drags. VM only: it posts mouse and key events on the session.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: IntegrationEnv.inVM, "posts events on the session; VM only"),
    .enabled(if: ProcessInfo.processInfo.environment["TRANSOM_LIVE_DRAG"] == "1", "posts synthetic drags; set TRANSOM_LIVE_DRAG=1"))
@MainActor struct HoldOptionIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aPlainDragFloatsADockedWindowAtItsReleaseFrame() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let (arrange, refs, _, tile) = try await LiveArrange.dockedPair(fixture)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.setDragToDock(.holdOption)
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }
        try await Task.sleep(for: .milliseconds(300))  // the fixture activates itself

        let id = refs[1].windowID
        let grab = try LiveArrange.titleBar(of: id, frame: tile)
        let drag = PostedDrag()
        defer { drag.finish() }
        try await drag.press(at: grab)
        // One tile's width right, so the release frame fits where the Desktop tile is once window 0 has reflowed: a shorter
        // drag on the VM's 1024 pt display crosses window 0's new tile and is rightly clamped.
        try await drag.move(to: CGPoint(x: grab.x + tile.width + 8, y: grab.y + 25))
        try await Task.sleep(for: .milliseconds(100))  // the window catches up with the pointer
        let last = try #require(DragFramePoller.bounds(of: id), "the dragged window has no CG bounds")
        drag.release()

        let floated = await waitUntil(timeout: .seconds(3)) { arrange.arranger.isFloating(refs[1]) }
        #expect(floated, "the window is not floating")
        let frame = try #require(try await LiveArrange.frame(fixture, 1))
        #expect(LiveArrange.near(frame, last, within: 4), "floats at \(frame), last polled \(last)")

        await arrange.dispatch(.undo, focused: refs[1])
        let back = await waitUntil(timeout: .seconds(3)) {
            guard let now = try? await LiveArrange.frame(fixture, 1) else { return false }
            return !arrange.arranger.isFloating(refs[1]) && LiveArrange.near(now, tile)
        }
        #expect(back, "undo did not put the window back in its tile \(tile)")
    }
}
