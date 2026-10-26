import AppKit

@MainActor public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let restore: () -> Void
    private let writeCleanExit: () -> Void
    private let reply: (Bool) -> Void

    init(
        restore: @escaping () -> Void, writeCleanExit: @escaping () -> Void,
        reply: @escaping (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    ) {
        self.restore = restore
        self.writeCleanExit = writeCleanExit
        self.reply = reply
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow  // RED stub
    }
}
