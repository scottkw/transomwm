import ApplicationServices
import Foundation
import PaneModel
import os

/// Gate for suites that need a real Accessibility grant. CI sets `PANE_SKIP_AX_INTEGRATION`.
enum IntegrationEnv {
    static let trusted = AXIsProcessTrusted() && ProcessInfo.processInfo.environment["PANE_SKIP_AX_INTEGRATION"] == nil

    /// Tests/PaneMacIntegrationTests/IntegrationSupport.swift -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    struct FixtureNotFound: Error, CustomStringConvertible {
        let path: String
        var description: String { "PaneFixtureApp not found at \(path); set PANE_FIXTURE_APP" }
    }

    /// `PANE_FIXTURE_APP`, else next to the `.xctest` bundle, else `.build/debug`.
    static func fixtureExecutable() throws -> URL {
        let url: URL
        if let path = ProcessInfo.processInfo.environment["PANE_FIXTURE_APP"] {
            url = URL(fileURLWithPath: path)
        } else if let products = productsDirectory {
            url = products.appendingPathComponent("PaneFixtureApp")
        } else {
            url = repoRoot.appendingPathComponent(".build/debug/PaneFixtureApp")
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw FixtureNotFound(path: url.path) }
        return url
    }

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

/// A running PaneFixtureApp. Always terminated in deinit, even if it was stopped.
final class FixtureProcess: @unchecked Sendable {
    let process = Process()
    private(set) var pid: Int32 = 0
    private(set) var windows: [FixtureWindow] = []
    private let output = Pipe()
    private let input = Pipe()
    private let lines = OSAllocatedUnfairLock(initialState: (buffer: "", lines: [String]()))

    /// Launches the fixture with one `--window` per spec and waits for its `ready` and window lines.
    nonisolated(nonsending) static func launch(_ specs: [String], timeout: Duration = .seconds(10)) async throws -> FixtureProcess {
        let fixture = FixtureProcess()
        try fixture.start(specs)
        let expected = specs.reduce(0) { $0 + expectedWindowLines($1) }
        let ok = await waitUntil(timeout: timeout) {
            fixture.readyPID != nil && fixture.windowLines().count >= expected
        }
        guard ok, let pid = fixture.readyPID else {
            throw FixtureError(description: "fixture did not report ready with \(expected) windows: \(fixture.allLines())")
        }
        fixture.pid = pid
        fixture.windows = fixture.windowLines()
        return fixture
    }

    /// How many `window` lines one spec prints.
    static func expectedWindowLines(_ spec: String) -> Int {
        if spec == "sheet" { return 2 }
        if spec.hasPrefix("tabs:"), let n = Int(spec.dropFirst(5)) { return n }
        return 1
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

    private func windowLines() -> [FixtureWindow] { allLines().compactMap(FixtureWindow.init(line:)) }

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

/// Polls `condition` every 50 ms until it is true or `timeout` passes.
nonisolated(nonsending) func waitUntil(timeout: Duration, _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}
