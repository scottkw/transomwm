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
        // Half a tile left, so the release frame stays on screen: window 1 is the right half of [0 | 1], and a drag right
        // would leave it off the edge, where it is rightly clamped back. A floater may cover window 0's tile (D-05).
        try await drag.move(to: CGPoint(x: grab.x - tile.width / 2, y: grab.y + 25))
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

    /// Pressing ⌥ during a drag docks, with macOS's guide and macOS's half-screen detour kept away (D-07a, D-09).
    @Test(.timeLimit(.minutes(1)))
    func pressingOptionMidDragDocksWithNoMacOSGuide() async throws {
        try Self.requireOptionTilingOn()
        let (fixture, arrange, ref, frame) = try await Self.floatingWindow()
        defer { fixture.terminate() }
        defer { withExtendedLifetime(arrange) {} }
        await arrange.setDragToDock(.holdOption)
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }

        let drag = PostedDrag()
        defer { drag.finish() }
        var guideSeen = false
        let sample = { guideSeen = guideSeen || MacOSGuide.isOnScreen() }
        let grab = try LiveArrange.titleBar(of: ref.windowID, frame: frame)
        try await drag.press(at: grab)
        try await drag.move(to: CGPoint(x: grab.x + 40, y: grab.y + 20), each: sample)
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.dragOptionStrip == .always }, "the press was never a move: strip \(arrange.arranger.dragOptionStrip), drag \(String(describing: arrange.arranger.drag)), session flags \(CGEventSource.flagsState(.combinedSessionState).rawValue)")
        try await drag.hold(.option)
        try await drag.move(to: Self.leftBand(try LiveArrange.visibleFrame()), each: sample)
        try await Self.rest(each: sample)
        let tile = try #require(Self.dockPreview(arrange), "no dock preview after the dwell: \(String(describing: arrange.arranger.drag?.shown))")
        let last = try #require(DragFramePoller.bounds(of: ref.windowID))
        #expect(!guideSeen, "macOS drew its Drag Guide Window in Hold ⌥ mode")

        drag.release()
        for wait in [100, 100, 200] {
            try await Task.sleep(for: .milliseconds(wait))
            let now = try #require(DragFramePoller.bounds(of: ref.windowID))
            #expect(LiveArrange.near(now, last, within: 3) || LiveArrange.near(now, tile, within: 3), "a detour: \(now), released at \(last), tile \(tile)")
        }
        #expect(arrange.arranger.isFloating(ref) == false, "the window did not dock")
        let reached = await waitUntil(timeout: .seconds(2)) {
            guard let now = try? await LiveArrange.frame(fixture, 0) else { return false }
            return LiveArrange.near(now, tile)
        }
        #expect(reached, "the window never reached the planned tile \(tile)")
    }

    /// Automatically mode's ⌥-drag belongs to macOS, as today. It also proves the scan can see the guide.
    @Test(.timeLimit(.minutes(1)))
    func automaticModeLeavesOptionToMacOS() async throws {
        try Self.requireOptionTilingOn()
        let (fixture, arrange, ref, frame) = try await Self.floatingWindow()
        defer { fixture.terminate() }
        defer { withExtendedLifetime(arrange) {} }
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }

        let drag = PostedDrag()
        defer { drag.finish() }
        var guideSeen = false
        let sample = { guideSeen = guideSeen || MacOSGuide.isOnScreen() }
        let grab = try LiveArrange.titleBar(of: ref.windowID, frame: frame)
        try await drag.press(at: grab)
        try await drag.move(to: CGPoint(x: grab.x + 40, y: grab.y + 20), each: sample)
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.dragOptionStrip == .withControl }, "the press was never a move: strip \(arrange.arranger.dragOptionStrip), drag \(String(describing: arrange.arranger.drag)), session flags \(CGEventSource.flagsState(.combinedSessionState).rawValue)")
        try await drag.hold(.option)
        try await drag.move(to: Self.leftBand(try LiveArrange.visibleFrame()), each: sample)
        try await Self.rest(each: sample)
        #expect(guideSeen, "macOS drew no guide for an ⌥-drag in Automatically mode")
    }

    /// A press the Arranger never saw clears the tap's strip with nothing to send it again but the Arranger's next change, so
    /// a change-only cache would leave ⌥ reaching macOS.
    @Test(.timeLimit(.minutes(1)))
    func aDragAfterALostMouseUpStillKeepsMacOSAway() async throws {
        try Self.requireOptionTilingOn()
        let (fixture, arrange, ref, frame) = try await Self.floatingWindow()
        defer { fixture.terminate() }
        defer { withExtendedLifetime(arrange) {} }
        await arrange.setDragToDock(.holdOption)
        try #require(arrange.startTap(), "the event tap was refused")
        defer { arrange.stopTap() }

        // Session A loses its mouse-up: the tap is down when it is posted.
        let lost = PostedDrag()
        defer { lost.finish() }
        let grab = try LiveArrange.titleBar(of: ref.windowID, frame: frame)
        try await lost.press(at: grab)
        try await lost.move(to: CGPoint(x: grab.x + 40, y: grab.y + 20))
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.dragOptionStrip == .always }, "session A was never a move")
        arrange.accessChanged(ready: false)
        lost.release()
        try await Task.sleep(for: .milliseconds(200))
        arrange.accessChanged(ready: true)
        try #require(arrange.tap.isRunning, "the tap did not come back")

        let second = try #require(try await LiveArrange.frame(fixture, 0))
        let drag = PostedDrag()
        defer { drag.finish() }
        var guideSeen = false
        let sample = { guideSeen = guideSeen || MacOSGuide.isOnScreen() }
        let again = try LiveArrange.titleBar(of: ref.windowID, frame: second)
        try await drag.press(at: again)
        try await drag.move(to: CGPoint(x: again.x + 40, y: again.y + 20), each: sample)
        try #require(await waitUntil(timeout: .seconds(2)) { arrange.arranger.dragOptionStrip == .always }, "the second press was never a move")
        arrange.tap.setDragOption(.off)  // what the tap thread's clear does when the Arranger never saw the press
        let end = Self.leftBand(try LiveArrange.visibleFrame())
        try await drag.move(to: CGPoint(x: again.x + 60, y: again.y + 30), steps: 3, each: sample)
        try await drag.hold(.option)
        try await drag.move(to: end, each: sample)
        try await Self.rest(each: sample)
        #expect(!guideSeen, "macOS drew its Drag Guide Window after the strip was lost")

        drag.release()
        let docked = await waitUntil(timeout: .seconds(3)) { !arrange.arranger.isFloating(ref) }
        #expect(docked, "the release did not dock the window")
    }

    // MARK: Helpers

    /// These tests mean nothing unless macOS's ⌥ tiling is on. Read only: nothing here writes the setting.
    private static func requireOptionTilingOn() throws {
        let value = CFPreferencesCopyAppValue("EnableTilingOptionAccelerator" as CFString, ConflictPolicy.domain as CFString)
        try #require(value == nil || (value as? Bool) == true, "EnableTilingOptionAccelerator is off in this guest")
    }

    /// Fixture window 0, floating in the middle of the main display, with a controller tracking it. Window 1 is docked
    /// behind it and fills the desk, so ⌥ has a tile to dock into away from the screen edge: an empty desk docks only
    /// from its edge band, where macOS's own edge tiling draws its guide (RESEARCH E1).
    private static func floatingWindow() async throws -> (FixtureProcess, ArrangeController, TransomModel.WindowRef, Rect) {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        let (arrange, refs) = try await LiveArrange.start(fixture)
        await arrange.dispatch(.dock, focused: refs[1])
        let key = try #require(arrange.arranger.deskKey(of: refs[1]))
        try #require(arrange.arranger.world[key]?.tree.windows == [refs[1]], "window 1 did not dock alone")
        _ = try await fixture.send("order-back 1")
        let visible = try LiveArrange.visibleFrame()
        let size = try #require(fixture.windows.first).frame.size
        let x = (visible.midX - size.width / 2).rounded(), y = (visible.midY - size.height / 2).rounded()
        _ = try await fixture.send("move 0 \(Int(x)) \(Int(y))")
        let seen = await waitUntil(timeout: .seconds(2)) {
            arrange.arranger.windows[refs[0].identity].map { abs($0.frame.x - x) <= 1 && abs($0.frame.y - y) <= 1 } ?? false
        }
        try #require(seen, "the Arranger never saw the window move")
        try await Task.sleep(for: .milliseconds(300))  // the fixture activates itself
        return (fixture, arrange, refs[0], try #require(try await LiveArrange.frame(fixture, 0)))
    }

    /// Window 1's tile's left band, clear of the screen edge where macOS's edge tiling acts (RESEARCH E1).
    private static func leftBand(_ visible: Rect) -> CGPoint { CGPoint(x: visible.minX + visible.width / 8, y: visible.midY) }

    /// 300 ms with the pointer at rest, past the dwell, sampling as it goes.
    private static func rest(each: () -> Void) async throws {
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(20))
            each()
        }
    }

    private static func dockPreview(_ arrange: ArrangeController) -> Rect? {
        if case .dock(let rect)? = arrange.arranger.drag?.shown { rect } else { nil }
    }
}
