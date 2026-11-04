import CoreGraphics
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// VM-only helpers for suites that post real title-bar drags through a running ArrangeController. Copied from
/// ArrangeIntegrationTests' private `arranging` and `dockedPair`, which keep their own.
@MainActor enum LiveArrange {
    private static var last: ArrangeController?

    /// A system and an ArrangeController that track only `fixture`, started, with every fixture window on a desk. The tap
    /// is not running yet.
    static func start(_ fixture: FixtureProcess) async throws -> (ArrangeController, [TransomModel.WindowRef]) {
        // The last test's gap handles are still on screen, in this process, and would take this test's press.
        await last?.setPaused(.user, true)
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system)
        await arrange.start()
        last = arrange
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

    /// The main display's visible frame, top-left.
    static func visibleFrame() throws -> Rect {
        try #require(Displays.current().first).visibleFrame
    }

    /// Two fixture windows docked side by side: [0 | 1 | Desktop]. Returns the controller, the refs and both tile frames.
    static func dockedPair(_ fixture: FixtureProcess) async throws -> (ArrangeController, [TransomModel.WindowRef], Rect, Rect) {
        let (arrange, refs) = try await start(fixture)
        try #require(refs.count == 2)
        let visible = try visibleFrame()
        // Dock acts where a drop at the window's centre lands (D-12): see ArrangeIntegrationTests' dockedPair.
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
            guard let a = try? await frame(fixture, 0), let b = try? await frame(fixture, 1) else { return false }
            frames = [a, b]
            return inside(a, visible) && inside(b, visible) && !a.overlaps(b) && a.maxX < b.minX
        }
        try #require(tiled, "fixture frames \(frames) are not two side-by-side tiles inside \(visible)")
        return (arrange, refs, frames[0], frames[1])
    }

    /// The fixture's current frame for window `index`.
    nonisolated(nonsending) static func frame(_ fixture: FixtureProcess, _ index: Int) async throws -> Rect? {
        _ = try await fixture.send("list")
        return fixture.windows.first { $0.index == index }?.frame
    }

    /// Inside `outer`, allowing 1 pt for the fixture's integer rounding.
    static func inside(_ rect: Rect, _ outer: Rect) -> Bool {
        rect.minX >= outer.minX - 1 && rect.minY >= outer.minY - 1 && rect.maxX <= outer.maxX + 1 && rect.maxY <= outer.maxY + 1
    }

    /// Within `tolerance` on every side.
    static func near(_ a: Rect, _ b: Rect, within tolerance: Double = 2) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// A point on window `id`'s title bar at `frame`. Throws unless that window is topmost there, so nothing is posted on
    /// anything else.
    static func titleBar(of id: UInt32, frame: Rect) throws -> CGPoint {
        let grab = CGPoint(x: frame.midX, y: frame.minY + 12)
        let topmost = CGWindowList.onScreenFrontToBack()?.first { $0.layer == 0 && $0.bounds.contains(Point(x: grab.x, y: grab.y)) }
        try #require(topmost?.windowID == id, "window \(id)'s title bar is not topmost at \(grab): \(topmost.map { "\($0.windowID) pid \($0.pid)" } ?? "none")")
        return grab
    }
}

/// A modifier key a `PostedDrag` holds, by virtual key code.
enum PostedKey: CGKeyCode, CaseIterable {
    case control = 59, option = 58, command = 55, shift = 56

    var flag: CGEventFlags {
        switch self {
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        case .shift: .maskShift
        }
    }
}

/// One posted left-button drag with modifiers. Call `finish()` in a `defer`: it lets go of everything and puts the cursor back.
@MainActor final class PostedDrag {
    private let source = CGEventSource(stateID: .hidSystemState)
    private let saved = CGEvent(source: nil)?.location
    private var at = CGPoint.zero
    private var pressed = false
    private var held: [PostedKey] = []

    private var flags: CGEventFlags { CGEventFlags(rawValue: held.reduce(0) { $0 | $1.flag.rawValue }) }

    private func post(_ type: CGEventType, _ point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func postKey(_ key: PostedKey, down: Bool) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    func press(at point: CGPoint) async throws {
        at = point
        pressed = true
        post(.leftMouseDown, point)
        try await Task.sleep(for: .milliseconds(50))
    }

    /// `each` runs after every step, so a test can sample while the pointer moves.
    func move(to point: CGPoint, steps: Int = 20, each: () -> Void = {}) async throws {
        let from = at
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            at = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
            post(.leftMouseDragged, at)
            try await Task.sleep(for: .milliseconds(16))
            each()
        }
    }

    func hold(_ keys: PostedKey...) async throws {
        for key in keys {
            held.append(key)
            postKey(key, down: true)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func letGo(_ keys: PostedKey...) async throws {
        for key in keys {
            held.removeAll { $0 == key }
            postKey(key, down: false)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func release() {
        guard pressed else { return }
        pressed = false
        post(.leftMouseUp, at)
    }

    func finish() {
        release()
        for key in held.reversed() {
            held.removeAll { $0 == key }
            postKey(key, down: false)
        }
        if let saved { CGWarpMouseCursorPosition(saved) }
    }
}

/// macOS's own tile outline during an ⌥-drag (RESEARCH Finding 1).
enum MacOSGuide {
    static func isOnScreen() -> Bool {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains {
            $0[kCGWindowName as String] as? String == "Drag Guide Window" && $0[kCGWindowOwnerName as String] as? String == "WindowManager"
        }
    }
}
