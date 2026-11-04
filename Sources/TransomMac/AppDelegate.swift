import AppKit
import TransomEngine
import os

/// Transom's application delegate: the quit restore (SAFE-01, D-15, RESEARCH Pattern 11) and the `transom://` URL commands
/// (SAFE-03, TILE-15, TILE-17, Pattern 16).
@MainActor public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let restore: () -> Void
    private let writeCleanExit: () -> Void
    private let reply: (Bool) -> Void
    private let open: (Command) -> Void
    private let gate: CommandGate
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "url")
    private var sigterm: (any DispatchSourceSignal)?

    init(
        restore: @escaping () -> Void, writeCleanExit: @escaping () -> Void, open: @escaping (Command) -> Void,
        gate: CommandGate, reply: @escaping (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    ) {
        self.open = open
        self.gate = gate
        self.restore = restore
        self.writeCleanExit = writeCleanExit
        self.reply = reply
    }

    /// Every normal quit (menu, ⌘Q, logout, SIGTERM) waits for the bounded restore, then records the clean exit. A quit
    /// interrupted before that write is treated as a crash at the next launch (03-14).
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.restore()
                self.writeCleanExit()
                self.reply(true)
            }
        }
        return .terminateLater
    }

    /// `killall Transom` and logout send SIGTERM: quit through AppKit so they restore too. `kill -9` is the crash path.
    func handleSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        sigterm = source
    }

    /// Each URL that parses strictly and is admitted by the rate limit goes to `open`, the dispatcher its hotkey and menu
    /// item use. A rejected one is logged without its contents and shows nothing (Pitfall 21).
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch gate.admit(url, at: .now) {
            case .rejected: logger.notice("rejected a URL")
            case .rateLimited: logger.info("rate-limited a URL command")
            case .command(let command): open(command)
            }
        }
    }
}
