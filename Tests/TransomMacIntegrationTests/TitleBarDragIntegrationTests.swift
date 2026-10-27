import CoreGraphics
import Foundation
@testable import TransomMac
import TransomModel
import Testing
import os

/// Assumptions A1 and A16 on a fixture window: during a native title-bar drag the active tap sees the down, dragged and
/// up events, the press resolves to the fixture window, and event locations are global top-left points (the window
/// frame's space). Opt-in (`TRANSOM_LIVE_DRAG=1`): it posts synthetic mouse events, only on the fixture's own title bar, and puts
/// the cursor back. The tap is stopped and a pending mouse-up is posted in a defer.
@Suite(
    .serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"),
    .enabled(if: ProcessInfo.processInfo.environment["TRANSOM_LIVE_DRAG"] == "1", "posts synthetic drags; set TRANSOM_LIVE_DRAG=1"))
@MainActor struct TitleBarDragIntegrationTests {
    @Test(.timeLimit(.minutes(1)))
    func aTitleBarDragOfAFixtureWindowReachesTheTapInWindowCoordinates() async throws {
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        let window = try #require(fixture.windows.first)
        try await Task.sleep(for: .milliseconds(300))  // the fixture activates itself
        let grab = CGPoint(x: window.frame.midX, y: window.frame.minY + 12)
        // Post nothing unless the fixture's own window is topmost under the title-bar point.
        let topmost = CGWindowList.onScreenFrontToBack()?.first { $0.layer == 0 && $0.bounds.contains(Point(x: grab.x, y: grab.y)) }
        try #require(
            topmost?.windowID == window.id,
            "the fixture's title bar is not topmost at \(grab): window \(topmost.map { "\($0.windowID) pid \($0.pid)" } ?? "none"), fixture \(window.id) pid \(fixture.pid)")

        let saved = CGEvent(source: nil)?.location ?? grab
        let tap = InputTap()
        let seen = OSAllocatedUnfairLock(initialState: [TapEvent]())
        var released = false
        func post(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            if type == .leftMouseUp { released = true }
        }
        let step = 10.0, steps = 10
        let end = CGPoint(x: grab.x + step * Double(steps), y: grab.y)
        defer {
            if !released { post(.leftMouseUp, end) }
            tap.stop()
            CGWarpMouseCursorPosition(saved)
        }
        try #require(tap.start())
        let reader = Task { for await event in tap.events { seen.withLock { $0.append(event) } } }
        defer { reader.cancel() }

        post(.leftMouseDown, grab)
        try await Task.sleep(for: .milliseconds(50))
        for i in 1...steps {
            post(.leftMouseDragged, CGPoint(x: grab.x + step * Double(i), y: grab.y))
            try await Task.sleep(for: .milliseconds(16))
        }
        post(.leftMouseUp, end)
        try await Task.sleep(for: .milliseconds(300))

        let events = seen.withLock { $0 }
        let down = try #require(events.first { $0.type == .leftMouseDown }, "the tap saw no mouse-down")
        // At the session tap the window-under-pointer field can be 0 (seen live); the shell then takes the topmost
        // on-screen window under the point, which must be the fixture.
        let named = UInt32(truncatingIfNeeded: down.windowUnderPointer)
        let underDown = CGWindowList.onScreenFrontToBack()?.first {
            $0.layer == 0 && $0.bounds.contains(Point(x: down.location.x, y: down.location.y))
        }
        #expect(named == window.id || (named == 0 && underDown?.windowID == window.id), "the down named window \(named)")
        #expect(abs(down.location.x - grab.x) <= 1 && abs(down.location.y - grab.y) <= 1, "down at \(down.location), posted at \(grab)")
        #expect(events.filter { $0.type == .leftMouseDragged }.count >= steps / 2, "the tap saw too few drags: \(events.count) events")
        #expect(events.contains { $0.type == .leftMouseUp })
        // The window followed the native title-bar drag, so the tap watched a real one (A1).
        let moved = try #require(DragFramePoller.bounds(of: window.id))
        // AppKit keeps the first few points of travel as its drag threshold, so the window trails the pointer a little.
        #expect(moved.x - window.frame.x >= step * Double(steps) / 2, "fixture at \(moved), started at \(window.frame)")
        #expect(abs(moved.y - window.frame.y) <= 2)
    }
}
