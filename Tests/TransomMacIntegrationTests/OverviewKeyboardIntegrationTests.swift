import AppKit
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// D-04 live: in the overview → moves the one selection to the window on the right and Return focuses it and closes
/// the overview; other keys do nothing while it is open; Tab with one display stays put. The open overview's panel is
/// key without activating Transom, and after every close path the frontmost app gets keys again; the pointer moving
/// onto a tile selects it. VM only: it posts keys, pointer moves and clicks. Fixture windows only.
@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, "needs a process with the Accessibility grant"))
@MainActor struct OverviewKeyboardIntegrationTests {
    /// Connects to the window server first (see ZoomSettleIntegrationTests), as an agent app like Transom (LSUIElement).
    init() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    /// Pumps AppKit's queue (the test helper runs no NSApplication: key events, fades) until `done` or the timeout.
    private func pump(timeout: Duration = .seconds(2), until done: () async -> Bool) async -> Bool {
        await waitUntil(timeout: timeout) {
            dispatchAppKitEvents()
            return await done()
        }
    }

    /// Posts a key press, then pumps until `done` or the timeout.
    private func press(_ key: CGKeyCode, flags: CGEventFlags = [], timeout: Duration = .seconds(2), until done: () async -> Bool) async -> Bool {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        return await pump(timeout: timeout, until: done)
    }

    @Test(.timeLimit(.minutes(2)))
    func overviewKeysThenEveryCloseHandsKeysBack() async throws {
        let fixture = try await FixtureProcess.launch(["standard", "standard"])
        defer { fixture.terminate() }
        let fixturePID = fixture.pid
        let system = AXWindowSystem(appFilter: { pid, _ in pid == fixturePID })
        await system.start()
        let arrange = ArrangeController(system: system, zoomEnabled: true)
        defer { withExtendedLifetime(arrange) {} }
        await arrange.start()

        func tracked() -> [WindowInfo] { arrange.arranger.windows.values.filter { $0.window.pid == fixturePID } }
        // Docked side by side: two tracked windows at different x.
        let sideBySide = await waitUntil(timeout: .seconds(3)) { Set(tracked().map(\.frame.x)).count == 2 }
        try #require(sideBySide, "the fixture windows were never docked side by side: \(tracked().map(\.frame))")
        try await Task.sleep(for: .milliseconds(500))  // past the arrange
        let ordered = tracked().sorted { $0.frame.x < $1.frame.x }.map(\.window)
        let (left, right) = (ordered[0], ordered[1])
        func index(_ window: TransomModel.WindowRef) throws -> Int {
            try #require(fixture.windows.first { $0.id == window.windowID }?.index)
        }
        func frontmost(_ window: TransomModel.WindowRef) async throws -> Bool {
            let expected = "frontmost index=\(try index(window))"
            return await pump { ((try? await fixture.send("frontmost")) ?? []).contains(expected) }
        }
        func typed() async -> String {
            ((try? await fixture.send("typed")) ?? []).first { $0.hasPrefix("typed") }.map { String($0.dropFirst("typed".count)) } ?? ""
        }

        await system.perform([.focus(left)])
        try #require(try await frontmost(left), "the left fixture window never took focus")
        try await Task.sleep(for: .milliseconds(500))  // its .windowFocused must not interrupt the overview below

        await arrange.dispatch(.camera(.overview))
        let overview = try #require(arrange.overviewController)
        /// Opens the overview (the fixture frontmost first, so a key that missed the panel lands in the fixture only).
        func open(_ step: String) async throws {
            if !overview.isOpen {
                let active = await pump { ((try? await fixture.send("frontmost")) ?? []).contains { $0.hasPrefix("frontmost index=") } }
                try #require(active, "\(step): the fixture is not frontmost; refusing to type")
                await arrange.dispatch(.camera(.overview))
            }
            try #require(await pump { overview.selection.selected != nil }, "\(step): the overview never showed")
            try #require(await pump { overview.holdsKeys }, "\(step): the overview panel never became key")
        }
        /// After a close, the panel lets go of key and the fixture (frontmost) gets the next key press.
        func keysReturn(_ step: String, letter: String, key: CGKeyCode) async throws {
            #expect(!overview.isOpen, "\(step) did not close the overview")
            #expect(await pump(timeout: .seconds(1)) { !overview.holdsKeys }, "\(step): the overview panel stayed key")
            try #require(try await frontmost(right), "\(step): the fixture is not frontmost; refusing to type")
            #expect(await press(key) { await typed().contains(letter) }, "\(step): the frontmost app did not get keys back")
        }

        try await open("first open")
        #expect(overview.selection.selected == .tile(left), "the focused window was not the initial selection")
        #expect(await press(124) { overview.selection.selected == .tile(right) }, "→ did not select the right window")  // →
        _ = await press(124, timeout: .milliseconds(300)) { false }  // → at the right edge: nothing moves
        #expect(overview.selection.selected == .tile(right), "→ at the edge moved the selection")
        if arrange.arranger.displays.count == 1 {
            _ = await press(48, timeout: .milliseconds(300)) { false }  // Tab
            #expect(overview.selection.selected == .tile(right), "Tab with one display moved the selection")
        }
        // The pointer moving onto a tile selects it; the keys go on from there.
        let leftTile = try #require(overview.layout?.displays.flatMap(\.tiles).first { $0.window == left }).rect
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: leftTile.midX, y: leftTile.midY), mouseButton: .left)?
            .post(tap: .cghidEventTap)
        #expect(await pump { overview.selection.selected == .tile(left) }, "moving the pointer onto the left tile did not select it")
        #expect(await press(124) { overview.selection.selected == .tile(right) }, "→ after hovering did not select the right window")
        // Any other key does nothing while open: the overview stays, and the app behind does not get it.
        _ = await press(7, timeout: .milliseconds(500)) { !overview.isOpen }  // x
        #expect(overview.isOpen, "x closed the overview")
        #expect(await !typed().contains("x"), "x reached the app behind the open overview")
        #expect(await press(36) { !overview.isOpen }, "Return did not close the overview")  // Return
        #expect(try await frontmost(right), "Return did not focus the selected window")
        try await keysReturn("Return (pick)", letter: "a", key: 0)

        try await Task.sleep(for: .milliseconds(500))  // the pick's .windowFocused must not interrupt the next open
        try await open("Esc")
        _ = await press(53) { !overview.isOpen }  // Esc
        try await keysReturn("Esc", letter: "b", key: 11)

        try await open("toggle")
        await arrange.dispatch(.camera(.overview))  // Show Overview again
        try await keysReturn("toggle", letter: "c", key: 8)

        try await open("interrupt")
        overview.interrupt(reason: .command)  // a Space switch, focus change, command or session pause
        try await keysReturn("interrupt", letter: "d", key: 2)

        try await open("displays changed")
        overview.displaysChanged()  // a display change, or zoom off
        try await keysReturn("displays changed", letter: "e", key: 14)

        // A click near the main display's right edge: the backdrop (dismiss), or a tile there (pick). Either closes it.
        try await open("click")
        let screen = try #require(NSScreen.screens.first)
        let point = CGPoint(x: screen.frame.maxX - 4, y: screen.frame.height / 2)  // top-left global
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        _ = await pump { !overview.isOpen }
        try await keysReturn("click", letter: "f", key: 3)
    }
}
