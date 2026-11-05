import AppKit
import CoreGraphics
import Foundation
import TransomEngine
@testable import TransomMac
import TransomModel
import Testing

/// D-19 and success criteria 3 and 4 on the real app: stored options take effect at launch and survive a relaunch, the URL
/// route docks, and with the keys gone the defaults are back. Run with scripts/vm-bundle-check.sh, which stages the app. VM
/// only: it writes the app's defaults and replaces Application Support/Transom for the run.
@Suite(
    .serialized,
    .enabled(
        if: IntegrationEnv.trusted && IntegrationEnv.inVM && IntegrationEnv.bundledApp != nil
            && ProcessInfo.processInfo.environment["TRANSOM_LIVE_DRAG"] == "1",
        "needs the VM, a staged Transom Debug.app and TRANSOM_LIVE_DRAG=1"))
@MainActor struct OptionsBundleIntegrationTests {
    /// Connects to the window server first, as ZoomSettleIntegrationTests does.
    init() { _ = NSApplication.shared }

    @Test(.timeLimit(.minutes(3)))
    func theOptionsApplyAndSurviveARelaunchInTheRealApp() async throws {
        let guest = try Guest()
        defer { guest.restore() }
        try guest.write(key: "dragToDock", "holdOption")
        try guest.write(key: "newWindows", "tile")
        let fixture = try await FixtureProcess.launch(["standard"])
        defer { fixture.terminate() }
        defer { guest.stopApp() }
        try await guest.launchApp()
        let visible = try LiveArrange.visibleFrame()

        // Step 1, URL: `open -a` so the URL goes to this copy (D-13, D-14).
        try run("/usr/bin/open", ["-a", guest.app, "transom-debug://dock-column-1"])
        var first: Rect?
        let docked = await waitUntil(timeout: .seconds(5)) {
            first = try? await LiveArrange.frame(fixture, 0)
            return first.map { $0.minX <= visible.minX + 16 && $0.width < visible.width * 0.3 } ?? false
        }
        #expect(docked, "dock-column-1 left window 0 at \(String(describing: first)) in \(visible)")

        // Step 2, new window (D-02).
        try await expectNewWindowDocks(1, beside: 0, in: fixture)

        // Step 3, Hold ⌥ (D-08).
        try await expectPlainDragFloats(0, by: { CGPoint(x: $0.width + 16, y: 25) }, in: fixture)

        try await guest.quitApp()
        try await guest.launchApp()

        // Step 4: both still act after a relaunch (D-19). Nothing is focused yet, so window 2 goes below the largest tile, the
        // Desktop, which is the only way it can move and still fit once the Desktop takes its room back.
        try await expectNewWindowDocks(2, beside: 1, in: fixture)
        try await expectPlainDragFloats(2, by: { _ in CGPoint(x: 0, y: -120) }, in: fixture)

        try await guest.quitApp()
        try guest.delete(key: "dragToDock")
        try guest.delete(key: "newWindows")
        try await guest.launchApp()

        // Step 5, defaults (D-01, D-07): a new window floats where it opened, and a plain drag is a docking drag again.
        _ = try await fixture.send("open standard")
        try await Task.sleep(for: .seconds(3))
        let opened = openingFrame(of: 3)
        let floating = try #require(try await LiveArrange.frame(fixture, 3))
        #expect(LiveArrange.near(floating, opened), "with the keys gone window 3 is at \(floating), opened at \(opened)")
        let (start, released) = try await plainDrag(1, by: { CGPoint(x: -($0.width + 16), y: 25) }, in: fixture)
        try await Task.sleep(for: .seconds(2))
        let end = try #require(try await LiveArrange.frame(fixture, 1))
        #expect(!LiveArrange.near(end, released, within: 20), "from \(start) a plain drag in Automatically mode floated at \(end)")
    }

    /// 08.1-06's checklist: with Tile, a real Finder window docks and its Get Info panel floats (D-02, D-04).
    @Test(.timeLimit(.minutes(1)))
    func aRealFinderWindowDocksAndItsGetInfoPanelFloats() async throws {
        let guest = try Guest()
        defer { guest.restore() }
        try guest.write(key: "newWindows", "tile")
        defer { guest.stopApp() }
        try await guest.launchApp()
        let visible = try LiveArrange.visibleFrame()
        let finderPID = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first).processIdentifier
        func finderWindows() -> [CGWindowEntry] {
            (CGWindowList.onScreenFrontToBack() ?? []).filter { $0.pid == finderPID && $0.layer == 0 && $0.bounds.width > 100 }
        }
        let before = Set(finderWindows().map(\.windowID))
        // A new folder, so Finder can't just bring back a window it already has open.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try run("/usr/bin/open", [folder.path])
        // ⌘W closes the two windows this test opened, once each. Finder keeps any others.
        var opened = 0
        defer { for _ in 0..<opened { postCommand(key: 13) } }

        var window: CGWindowEntry?
        let tiled = await waitUntil(timeout: .seconds(5)) {
            window = finderWindows().first { !before.contains($0.windowID) }
            return window.map { $0.bounds.height >= visible.height - 40 } ?? false
        }
        if window != nil { opened += 1 }
        try #require(tiled, "the new Finder window never docked: \(String(describing: window?.bounds)) in \(visible)")
        try await Task.sleep(for: .seconds(1))
        let tile = try #require(finderWindows().first { $0.windowID == window?.windowID }?.bounds)

        postCommand(key: 34)  // ⌘I
        var panel: CGWindowEntry?
        let appeared = await waitUntil(timeout: .seconds(5)) {
            panel = finderWindows().first { !before.contains($0.windowID) && $0.windowID != window?.windowID }
            return panel != nil
        }
        if appeared { opened += 1 }
        try #require(appeared, "Get Info opened no window")
        try await Task.sleep(for: .seconds(1))  // its zoom-in animation
        let shown = try #require(finderWindows().first { $0.windowID == panel?.windowID }?.bounds)
        try await Task.sleep(for: .seconds(3))
        let list = finderWindows()
        let after = try #require(list.first { $0.windowID == panel?.windowID }?.bounds)
        #expect(LiveArrange.near(after, shown), "Get Info moved from \(shown) to \(after)")
        let now = try #require(list.first { $0.windowID == window?.windowID }?.bounds)
        #expect(LiveArrange.near(now, tile), "the docked window moved from \(tile) to \(now), so Get Info took a tile")
    }

    // MARK: Helpers

    /// Where the fixture opens its window number `index` (`TransomFixtureApp.open`).
    private func openingFrame(of index: Int) -> Rect {
        Rect(x: 40 + 40 * Double(index), y: 80 + 40 * Double(index), width: 320, height: 232)
    }

    private func expectNewWindowDocks(_ index: Int, beside other: Int, in fixture: FixtureProcess) async throws {
        _ = try await fixture.send("open standard")
        let opened = openingFrame(of: index)
        var new: Rect?, neighbour: Rect?
        let docked = await waitUntil(timeout: .seconds(5)) {
            new = try? await LiveArrange.frame(fixture, index)
            neighbour = try? await LiveArrange.frame(fixture, other)
            guard let new, let neighbour else { return false }
            return !LiveArrange.near(new, opened) && !new.overlaps(neighbour)
        }
        #expect(docked, "window \(index) is at \(String(describing: new)), opened at \(opened), window \(other) at \(String(describing: neighbour))")
        try await Task.sleep(for: .seconds(1))  // the neighbours' writes land before anything is grabbed
    }

    /// A plain title-bar drag by `travel(start frame)`. It has to leave the window inside the Desktop tile as it will be with the
    /// window out, or it is rightly clamped. Returns the frames before the press and at the release.
    private func plainDrag(_ index: Int, by travel: (Rect) -> CGPoint, in fixture: FixtureProcess) async throws -> (start: Rect, released: Rect) {
        let start = try #require(try await LiveArrange.frame(fixture, index))
        let id = try #require(fixture.windows.first { $0.index == index }).id
        try await Task.sleep(for: .milliseconds(300))  // the fixture activates itself
        let drag = PostedDrag()
        defer { drag.finish() }
        let grab = try LiveArrange.titleBar(of: id, frame: start)
        let by = travel(start)
        try await drag.press(at: grab)
        try await drag.move(to: CGPoint(x: grab.x + by.x, y: grab.y + by.y))
        try await Task.sleep(for: .milliseconds(100))  // the window catches up with the pointer
        let released = try #require(DragFramePoller.bounds(of: id), "the dragged window has no CG bounds")
        drag.release()
        return (start, released)
    }

    private func expectPlainDragFloats(_ index: Int, by travel: (Rect) -> CGPoint, in fixture: FixtureProcess) async throws {
        let (start, released) = try await plainDrag(index, by: travel, in: fixture)
        try await Task.sleep(for: .seconds(2))
        let end = try #require(try await LiveArrange.frame(fixture, index))
        #expect(LiveArrange.near(end, released, within: 20), "window \(index) is at \(end), released at \(released), started at \(start)")
    }

    private func postCommand(key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// The guest's app state for one test: Application Support moved aside and the two option keys kept, then all of it put back.
@MainActor private final class Guest {
    let app: String
    private let manager = FileManager.default
    private let support: URL
    private let kept: URL
    private var keys: [String: String?] = [:]
    private var didMoveSupport = false

    init() throws {
        app = try #require(IntegrationEnv.bundledApp).path
        support = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Transom")
        kept = support.appendingPathExtension("before-options-test")
        try #require(try appPID() == nil, "Transom Debug is already running")
        if manager.fileExists(atPath: support.path) {
            try manager.moveItem(at: support, to: kept)
            didMoveSupport = true
        }
        for key in ["dragToDock", "newWindows"] { keys[key] = read(key) }
    }

    func write(key: String, _ value: String) throws {
        try run("/usr/bin/defaults", ["write", OptionsBundleDomain.name, key, "-string", value])
    }

    func delete(key: String) throws {
        try run("/usr/bin/defaults", ["delete", OptionsBundleDomain.name, key])
    }

    private func read(_ key: String) -> String? {
        guard let output = try? capture("/usr/bin/defaults", ["read", OptionsBundleDomain.name, key]) else { return nil }
        return output.status == 0 ? output.text : nil
    }

    /// `open`, then the layout file and the first sweep. The layout folder may already hold a file from before the quit.
    func launchApp() async throws {
        let layout = support.appendingPathComponent("layout.json")
        try run("/usr/bin/open", [app])
        let launched = await waitUntil(timeout: .seconds(10)) { self.manager.fileExists(atPath: layout.path) && (try? self.appPID()) != nil }
        try #require(launched, "the app wrote no layout.json: is it trusted in this VM?")
        try await Task.sleep(for: .seconds(3))  // the first sweep tracks the fixture
    }

    func quitApp() async throws {
        let pid = try #require(try appPID())
        try run("/usr/bin/osascript", ["-e", "quit app id \"\(OptionsBundleDomain.name)\""], wait: false)
        let exited = await waitUntil(timeout: .seconds(10)) { kill(pid, 0) != 0 }
        try #require(exited, "still running 10 s after the quit")
    }

    /// For the `defer`s: quits, and kills what's still there.
    func stopApp() {
        guard let pid = try? appPID() else { return }
        try? run("/usr/bin/osascript", ["-e", "quit app id \"\(OptionsBundleDomain.name)\""])
        for _ in 0..<20 where kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.25) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// After `stopApp`: the app's clean-exit write would land in the restored folder otherwise.
    func restore() {
        // `open` registered this copy; a later URL or `open` should not find it.
        try? run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-u", app])
        for (key, value) in keys {
            if let value { try? write(key: key, value) } else { _ = try? capture("/usr/bin/defaults", ["delete", OptionsBundleDomain.name, key]) }
        }
        try? manager.removeItem(at: support)
        if didMoveSupport { try? manager.moveItem(at: kept, to: support) }
    }

    private func appPID() throws -> Int32? {
        Int32(try capture("/usr/bin/pgrep", ["-x", "Transom Debug"]).text)
    }
}

private enum OptionsBundleDomain {
    static let name = "com.eightabyte.transom.debug"
}

private func run(_ tool: String, _ arguments: [String], wait: Bool = true) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try process.run()
    if wait { process.waitUntilExit() }
}

private func capture(_ tool: String, _ arguments: [String]) throws -> (status: Int32, text: String) {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return (process.terminationStatus, text)
}
