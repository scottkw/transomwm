import AppKit
import ApplicationServices
import Foundation
import TransomModel
import os

/// Gate for suites that need a real Accessibility grant. Opt-in with `TRANSOM_LIVE=1`: these suites open and move real
/// windows, so they run only in the test VM (scripts/vm-live-test.sh), never by default on a developer's Mac.
enum IntegrationEnv {
    static let trusted = AXIsProcessTrusted() && ProcessInfo.processInfo.environment["TRANSOM_LIVE"] == "1"

    /// Running inside a virtual machine (`kern.hv_vmm_present` is 1), as the spike's `requireVM()` checks. Suites that
    /// change system state a crash cannot undo (symbolic hotkeys, the current Space) need it besides `trusted` (WR-11).
    static let inVM: Bool = {
        var vmm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &vmm, &size, nil, 0) == 0 && vmm == 1
    }()

    /// Tests/TransomMacIntegrationTests/IntegrationSupport.swift -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    struct FixtureNotFound: Error, CustomStringConvertible {
        let path: String
        var description: String { "TransomFixtureApp not found at \(path); set TRANSOM_FIXTURE_APP" }
    }

    /// `TRANSOM_FIXTURE_APP`, else next to the `.xctest` bundle, else `.build/debug`.
    static func fixtureExecutable() throws -> URL {
        let url: URL
        if let path = ProcessInfo.processInfo.environment["TRANSOM_FIXTURE_APP"] {
            url = URL(fileURLWithPath: path)
        } else if let products = productsDirectory {
            url = products.appendingPathComponent("TransomFixtureApp")
        } else {
            url = repoRoot.appendingPathComponent(".build/debug/TransomFixtureApp")
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw FixtureNotFound(path: url.path) }
        return url
    }

    /// `Transom Debug.app` staged next to the `.xctest` bundle (`TRANSOM_VM_APP` in scripts/vm-live-test.sh), if any.
    static let bundledApp: URL? = {
        guard let app = productsDirectory?.appendingPathComponent("Transom Debug.app") else { return nil }
        return FileManager.default.fileExists(atPath: app.path) ? app : nil
    }()

    /// swiftpm-testing-helper gets `--test-bundle-path <dir>/X.xctest/Contents/MacOS/X`.
    private static var productsDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--test-bundle-path"), i + 1 < args.count,
              let r = args[i + 1].range(of: ".xctest")
        else { return nil }
        return URL(fileURLWithPath: String(args[i + 1][..<r.upperBound])).deletingLastPathComponent()
    }
}

/// One `window` line printed by the fixture. `frame` is top-left global points.
struct FixtureWindow: Equatable, Sendable {
    let index: Int
    let id: UInt32
    let kind: String
    let frame: Rect

    /// Parses `window index=<i> id=<id> kind=<spec> frame=<x>,<y>,<w>,<h>`.
    init?(line: String) {
        guard line.hasPrefix("window ") else { return nil }
        var fields: [String: String] = [:]
        for part in line.split(separator: " ").dropFirst() {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { fields[String(kv[0])] = String(kv[1]) }
        }
        let numbers = fields["frame"]?.split(separator: ",").compactMap { Double($0) } ?? []
        guard let index = fields["index"].flatMap({ Int($0) }), let id = fields["id"].flatMap({ UInt32($0) }),
              let kind = fields["kind"], numbers.count == 4
        else { return nil }
        self.index = index
        self.id = id
        self.kind = kind
        frame = Rect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

/// A running TransomFixtureApp. Always terminated in deinit, even if it was stopped.
final class FixtureProcess: @unchecked Sendable {
    let process = Process()
    private(set) var pid: Int32 = 0
    private(set) var windows: [FixtureWindow] = []
    private let output = Pipe()
    private let input = Pipe()
    private let lines = OSAllocatedUnfairLock(initialState: (buffer: "", lines: [String]()))

    /// Launches the fixture with one `--window` per spec, waits for `ready` and reads its windows with `list`.
    nonisolated(nonsending) static func launch(_ specs: [String], timeout: Duration = .seconds(10)) async throws -> FixtureProcess {
        let fixture = FixtureProcess()
        try fixture.start(specs)
        guard await waitUntil(timeout: timeout, { fixture.readyPID != nil }), let pid = fixture.readyPID else {
            throw FixtureError(description: "fixture did not report ready: \(fixture.allLines())")
        }
        fixture.pid = pid
        _ = try await fixture.send("list")
        return fixture
    }

    /// Sends one stdin command and returns the lines it printed, up to and including its `ok` line.
    /// Throws on an `error` reply or no reply within `timeout`. `list` also refreshes `windows`.
    nonisolated(nonsending) func send(_ command: String, timeout: Duration = .seconds(5)) async throws -> [String] {
        let start = allLines().count
        try input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8))
        let replied = await waitUntil(timeout: timeout) {
            self.allLines().dropFirst(start).contains { $0 == "ok \(command)" || $0.hasPrefix("error \(command):") }
        }
        let reply = Array(allLines().dropFirst(start))
        guard replied else { throw FixtureError(description: "no reply to \(command): \(reply)") }
        if let error = reply.first(where: { $0.hasPrefix("error ") }) { throw FixtureError(description: error) }
        if command == "list" { windows = reply.compactMap(FixtureWindow.init(line:)) }
        return reply
    }

    private func start(_ specs: [String]) throws {
        process.executableURL = try IntegrationEnv.fixtureExecutable()
        process.arguments = specs.flatMap { ["--window", $0] }
        process.standardOutput = output
        process.standardInput = input
        output.fileHandleForReading.readabilityHandler = { [lines] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            lines.withLock { state in
                state.buffer += chunk
                while let newline = state.buffer.firstIndex(of: "\n") {
                    state.lines.append(String(state.buffer[..<newline]))
                    state.buffer = String(state.buffer[state.buffer.index(after: newline)...])
                }
            }
        }
        try process.run()
    }

    func allLines() -> [String] { lines.withLock { $0.lines } }

    private var readyPID: Int32? {
        allLines().first { $0.hasPrefix("ready pid=") }.flatMap { Int32($0.dropFirst("ready pid=".count)) }
    }

    func stop() { kill(process.processIdentifier, SIGSTOP) }
    func resume() { kill(process.processIdentifier, SIGCONT) }
    func terminate() {
        guard process.isRunning else { return }
        resume()
        process.terminate()
    }

    deinit {
        output.fileHandleForReading.readabilityHandler = nil
        terminate()
    }
}

/// Sends AppKit's queued events (this process runs no NSApplication) from inside a nested run of the main run loop.
/// AppKit's tracking-area manager stops the current run to wake event waits (`-[NSEvent _postAtStart:]`); NSApp.run
/// shrugs that off, but outside a nested run the stop lands on the test helper's own main loop, which then exits the
/// process with status 0 and no test results.
@MainActor func dispatchAppKitEvents() {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
        MainActor.assumeIsolated {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
        }
    }
    CFRunLoopRunInMode(.defaultMode, 0.02, false)
}

/// Polls `condition` every 50 ms until it is true or `timeout` passes.
nonisolated(nonsending) func waitUntil(timeout: Duration, _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}
