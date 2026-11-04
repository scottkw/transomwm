import Foundation

/// The wire format between the `transom` tool and the running app (D-07, RESEARCH Pattern 7): one CFMessagePort request
/// holding the URL text, one reply. Pure, so both ends and the tests share it.
public enum CLIProtocol {
    /// The msgid of every request.
    public static let version: Int32 = 1
    public static let maxRequestBytes = 256
    /// How long the tool waits to send, and then for the reply (UI-SPEC Surface 5).
    public static let timeout: TimeInterval = 2
    public static let ok = "ok"
    public static let rate = "rate"
    public static let rejected = "rejected"
    /// Test hook: the port name to use instead of the bundle's.
    public static let portEnvironmentKey = "TRANSOM_CLI_PORT"

    public static func refused(_ reason: String) -> String { "refused\t\(reason)" }

    /// The channel is named from the bundle, so a Debug build's tool talks to the Debug app.
    public static func portName(bundleID: String) -> String { bundleID + ".cli" }

    /// The exit code and the stderr line for a reply to `command`.
    public static func exitCode(reply: String, command: String) -> (code: Int32, message: String?) {
        if reply == ok { return (0, nil) }
        if reply == rate { return (1, CLICopy.rateLimited) }
        if reply.hasPrefix(refused("")) { return (1, CLICopy.refused(String(reply.dropFirst(refused("").count)))) }
        return (1, CLICopy.didNotAnswer)
    }

    /// The exit code and the stderr line for a `CFMessagePortSendRequest` failure.
    public static func exitCode(sendStatus: Int32) -> (code: Int32, message: String?) { (1, CLICopy.didNotAnswer) }

    /// The `.app` a tool at `…/X.app/Contents/Helpers/transom` ships in, through any symlink to it; nil outside a bundle.
    public static func appBundle(executable: URL) -> URL? {
        let tool = executable.resolvingSymlinksInPath()
        let helpers = tool.deletingLastPathComponent()
        let contents = helpers.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard tool.lastPathComponent == "transom", helpers.lastPathComponent == "Helpers", contents.lastPathComponent == "Contents",
            app.pathExtension == "app"
        else { return nil }
        return app
    }
}
