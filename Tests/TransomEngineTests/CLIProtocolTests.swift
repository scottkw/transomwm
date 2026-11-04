import Foundation
import TransomEngine
import Testing

/// 08 UI-SPEC Surface 5: every reply and send failure maps to its exit code and stderr line.
@Suite struct CLIProtocolTests {
    @Test func okIsSilent() {
        let outcome = CLIProtocol.exitCode(reply: "ok", command: "view/3")
        #expect(outcome.code == 0)
        #expect(outcome.message == nil)
    }

    @Test func aRefusalPrintsItsReason() {
        let outcome = CLIProtocol.exitCode(reply: "refused\tNo view in slot 3", command: "view/3")
        #expect(outcome.code == 1)
        #expect(outcome.message == "transom: refused: No view in slot 3")
    }

    @Test func aRefusalReasonIsMadeASCII() {
        let outcome = CLIProtocol.exitCode(reply: "refused\tThe focused window isn\u{2019}t in a tab group", command: "next-tab")
        #expect(outcome.message == "transom: refused: The focused window isn't in a tab group")
    }

    @Test func aRefusalWithNoTextNamesTheCommand() {
        let outcome = CLIProtocol.exitCode(reply: "refused\t", command: "zoom-out")
        #expect(outcome.code == 1)
        #expect(outcome.message == "transom: refused: zoom-out can't act right now")
    }

    @Test func theRateLimitHasItsOwnLine() {
        let outcome = CLIProtocol.exitCode(reply: "rate", command: "view/3")
        #expect(outcome.code == 1)
        #expect(outcome.message == "transom: refused (rate limit). Each command runs at most once per second.")
    }

    @Test func rejectedIsAUsageError() {
        let outcome = CLIProtocol.exitCode(reply: "rejected", command: "view/3")
        #expect(outcome.code == 64)
        #expect(outcome.message == "transom: unknown command \"view/3\". Run \"transom help\" to see every command.")
    }

    @Test func aReplyNobodyDefinedIsNoAnswer() {
        let outcome = CLIProtocol.exitCode(reply: "what", command: "view/3")
        #expect(outcome.code == 1)
        #expect(outcome.message == "transom: Transom didn't answer")
    }

    @Test(arguments: [-1, -2, -3, -4, -5] as [Int32])
    func aSendFailureIsNoAnswer(status: Int32) {
        let outcome = CLIProtocol.exitCode(sendStatus: status)
        #expect(outcome.code == 1)
        #expect(outcome.message == "transom: Transom didn't answer")
    }

    @Test func thePortIsNamedFromTheBundle() {
        #expect(CLIProtocol.portName(bundleID: "com.eightabyte.transom") == "com.eightabyte.transom.cli")
        #expect(CLIProtocol.portName(bundleID: "com.eightabyte.transom.debug") == "com.eightabyte.transom.debug.cli")
    }

    @Test func theAppBundleIsFoundFromTheHelpersPath() {
        let app = CLIProtocol.appBundle(executable: URL(fileURLWithPath: "/Applications/Transom.app/Contents/Helpers/transom"))
        #expect(app?.path == "/Applications/Transom.app")
        #expect(CLIProtocol.appBundle(executable: URL(fileURLWithPath: "/usr/local/bin/transom-cli")) == nil)
        #expect(CLIProtocol.appBundle(executable: URL(fileURLWithPath: "/Applications/Transom.app/Contents/MacOS/transom")) == nil)
    }

    /// Pitfall 11: the README installs a symlink at /usr/local/bin/transom.
    @Test func theAppBundleIsFoundThroughASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let helpers = root.appendingPathComponent("Transom Debug.app/Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let tool = helpers.appendingPathComponent("transom")
        try Data().write(to: tool)
        let link = root.appendingPathComponent("transom")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        let app = CLIProtocol.appBundle(executable: link)
        #expect(app?.lastPathComponent == "Transom Debug.app")
    }
}
