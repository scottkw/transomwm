import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// D-06..D-08: the built `transom-cli` talks to a `CLIListener` over CFMessagePort. Host-safe: IPC only, on a private port
/// name, with a stub decision; no window, event, URL open or real Transom port is involved.
@Suite @MainActor struct CLIListenerTests {
    struct ToolNotFound: Error {}

    /// swiftpm-testing-helper gets `--test-bundle-path <dir>/X.xctest/Contents/MacOS/X`; the tool sits beside the bundle.
    private func tool() throws -> URL {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var url = root.appendingPathComponent(".build/debug/transom-cli")
        if let i = args.firstIndex(of: "--test-bundle-path"), i + 1 < args.count, let r = args[i + 1].range(of: ".xctest") {
            url = URL(fileURLWithPath: String(args[i + 1][..<r.upperBound])).deletingLastPathComponent().appendingPathComponent("transom-cli")
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw ToolNotFound() }
        return url
    }

    private func uniquePort() -> String { "com.eightabyte.transom.test.\(UUID().uuidString).cli" }

    /// Runs the tool against `port`, draining the main queue (the listener's) while it runs.
    private func run(_ arguments: [String], port: String) async throws -> (code: Int32, stderr: String) {
        let process = Process()
        process.executableURL = try tool()
        process.arguments = arguments
        process.environment = [CLIProtocol.portEnvironmentKey: port]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        while process.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        let text = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, text)
    }

    /// The clock stays still, so "within the second" doesn't depend on how long a process takes to start.
    private func listener(port: String, decide: @escaping (Command) -> String = { _ in CLIProtocol.ok }) -> CLIListener {
        let start = ContinuousClock.now
        return CLIListener(name: port, gate: CommandGate(scheme: "transom"), now: { start }, decide: decide)
    }

    @Test func aCommandCrossesThePortAndExitsZeroSilently() async throws {
        let port = uniquePort()
        var decided: [Command] = []
        let listening = listener(port: port) {
            decided.append($0)
            return CLIProtocol.ok
        }
        #expect(listening.isListening)
        let result = try await run(["view", "3"], port: port)
        #expect(result.code == 0)
        #expect(result.stderr.isEmpty)
        #expect(try decided == [.camera(.view(#require(ViewSlot(3))))])
    }

    @Test func theSameCommandWithinASecondIsRateLimited() async throws {
        let port = uniquePort()
        let listening = listener(port: port)
        #expect(try await run(["view", "3"], port: port).code == 0)
        let second = try await run(["view/3"], port: port)
        #expect(second.code == 1)
        #expect(second.stderr == "transom: refused (rate limit). Each command runs at most once per second.\n")
        #expect(try await run(["view", "4"], port: port).code == 0)
        #expect(listening.isListening)
    }

    @Test func noListenerExitsTwoAndSaysSo() async throws {
        let result = try await run(["view", "3"], port: uniquePort())
        #expect(result.code == 2)
        #expect(result.stderr == "transom: Transom is not running\n")
    }

    /// One limiter for both routes (D-07): a URL open uses up the CLI's second, and the other way round.
    @Test func urlsAndTheCLIShareALimiter() throws {
        let gate = CommandGate(scheme: "transom")
        let url = try #require(URL(string: "transom://view/3"))
        let now = ContinuousClock.now
        #expect(try gate.admit(url, at: now) == .command(.camera(.view(#require(ViewSlot(3))))))
        #expect(gate.admit(url, at: now + .milliseconds(10)) == .rateLimited)
        #expect(gate.admit(try #require(URL(string: "transom://view/3?x=1")), at: now) == .rejected)
    }
}
