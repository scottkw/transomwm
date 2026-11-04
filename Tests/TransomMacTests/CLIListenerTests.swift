import CoreFoundation
import Foundation
import TransomEngine
@testable import TransomMac
import Testing

/// D-06..D-08: the built `transom-cli` talks to a `CLIListener` over CFMessagePort. Host-safe: IPC only, on a private port
/// name, with a stub decision; no window, event, URL open or real Transom port is involved.
@Suite @MainActor struct CLIListenerTests {
    struct ToolNotFound: Error {}
    private let three = ViewSlot(3)!

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

    /// D-07: the refusal's reason crosses the port and the tool prints it.
    @Test func aRefusalReachesStderrWithExitOne() async throws {
        let port = uniquePort()
        let listening = listener(port: port) { _ in CLIProtocol.refused("No view in slot 3") }
        let result = try await run(["view", "3"], port: port)
        #expect(result.code == 1)
        #expect(result.stderr == "transom: refused: No view in slot 3\n")
        #expect(listening.isListening)
    }

    /// A bad command line never reaches a port.
    @Test func aBadCommandLineExits64() async throws {
        let result = try await run(["foo"], port: uniquePort())
        #expect(result.code == 64)
        #expect(result.stderr == "transom: unknown command \"foo\". Run \"transom help\" to see every command.\n")
    }

    /// T-08-15: any local process can send here, so a wrong message ID, an oversized request or a URL off the allow-list
    /// is rejected without reaching the decision.
    @Test func badRequestsAreRejected() async throws {
        let port = uniquePort()
        var decided = 0
        let listening = listener(port: port) { _ in
            decided += 1
            return CLIProtocol.ok
        }
        let cases: [(Int32, String)] = [
            (CLIProtocol.version + 1, "transom://view/3"), (CLIProtocol.version, "transom://view/3?" + String(repeating: "x", count: 256)),
            (CLIProtocol.version, "transom://view/0"), (CLIProtocol.version, "not a url"),
        ]
        for (msgid, text) in cases {
            // On its own thread: the send waits in a run loop while the main queue serves the port.
            let reply = await Task.detached {
                let remote = CFMessagePortCreateRemote(nil, port as CFString)
                var data: Unmanaged<CFData>?
                _ = CFMessagePortSendRequest(remote, msgid, Data(text.utf8) as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &data)
                return data.map { String(decoding: $0.takeRetainedValue() as Data, as: UTF8.self) }
            }.value
            #expect(reply == CLIProtocol.rejected, "\(text)")
        }
        #expect(decided == 0)
        #expect(listening.isListening)
    }

    // D-07: the reply carries what VoiceOver would hear; on screen a CLI or URL refusal stays silent.


    @Test func aRefusalRepliesItsAnnouncement() {
        #expect(ArrangeController.cliReply(for: [.beep, .announce("Arranging is paused"), .info("refused")]) == "refused\tArranging is paused")
    }

    @Test func anEmptySlotRepliesItsToastText() {
        #expect(ArrangeController.cliReply(for: [.beep, .notice(.viewEmpty(three, displayUUID: nil)), .info("refused")]) == "refused\tNo view in slot 3")
    }

    @Test func aTabRefusalRepliesItsAnnouncement() {
        #expect(ArrangeController.cliReply(for: [.beep, .tabAnnouncement(.refused(.notInGroup))]) == "refused\tThe focused window isn't in a tab group")
    }

    @Test func aRefusalWithNoAnnouncementHasNoText() {
        #expect(ArrangeController.cliReply(for: [.beep, .info("refused")]) == "refused\t")
    }

    @Test func aSuccessRepliesOK() {
        #expect(ArrangeController.cliReply(for: [.notice(.viewShown(three, displayUUID: nil)), .info("went")]) == "ok")
        #expect(ArrangeController.cliReply(for: []) == "ok")
    }

    @Test func zoomOffRefusesTheCLIAndNothingElseSeesIt() {
        let arrange = ArrangeController(system: AXWindowSystem(), zoomEnabled: false)
        arrange.beep = {}
        let decision = arrange.decide(.camera(.view(three)), from: .cli)
        #expect(decision.reply == "refused\tZoom is off")
        #expect(decision.effects.isEmpty)
        #expect(arrange.decide(.camera(.zoomOutAll), from: .url).effects.isEmpty)
        #expect(arrange.decide(.camera(.zoomOutAll), from: .hotkey).effects.isEmpty)
    }

    @Test func aSilentRouteKeepsToastsButNotRefusals() {
        let shown = ArrangerEffect.notice(.viewShown(three, displayUUID: nil))
        #expect(ArrangeController.silenced([shown, .info("went")], of: .camera(.view(three))) == [shown, .info("went")])
        for notice in [Notice.viewEmpty(three, displayUUID: nil), .viewDisplayGone(three, displayUUID: nil), .viewNothingToSave(displayUUID: nil)] {
            #expect(ArrangeController.silenced([.beep, .notice(notice), .info("refused")], of: .camera(.view(three))) == [.info("refused")])
        }
        #expect(ArrangeController.silenced([.beep, .announce("No room"), .info("refused")], of: .restoreAll) == [.info("refused")])
        #expect(ArrangeController.silenced([.beep, .tabAnnouncement(.refused(.paused))], of: .tabs(.next)).isEmpty)
    }

    /// A non-refusal announcement of a command other than the camera's keeps speaking, as it did.
    @Test func aSilentRouteKeepsASuccessAnnouncement() {
        #expect(ArrangeController.silenced([.announce("Swapped")], of: .restoreAll) == [.announce("Swapped")])
        #expect(ArrangeController.silenced([.announce("Collapsed")], of: .camera(.stepIn)).isEmpty)
    }

    /// Not started: not ready, so a real command through the real path answers with the text it would announce.
    @Test func answeringACameraCommandWhenNotReadyRepliesWhy() {
        let arrange = ArrangeController(system: AXWindowSystem(), zoomEnabled: true)
        arrange.beep = {}
        #expect(arrange.answerCLI(.camera(.view(three))).hasPrefix("refused\t"))
    }
}
