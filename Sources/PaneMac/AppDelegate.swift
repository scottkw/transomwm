import AppKit
import PaneEngine

/// Pane's application delegate: the quit restore (SAFE-01, D-15, RESEARCH Pattern 11).
@MainActor public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let restore: () -> Void
    private let writeCleanExit: () -> Void
    private let reply: (Bool) -> Void
    private let open: (Command) -> Void
    private let urlScheme: String?
    private var sigterm: (any DispatchSourceSignal)?

    init(
        restore: @escaping () -> Void, writeCleanExit: @escaping () -> Void, open: @escaping (Command) -> Void,
        urlScheme: String?, reply: @escaping (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    ) {
        self.open = open
        self.urlScheme = urlScheme
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

    /// `killall Pane` and logout send SIGTERM: quit through AppKit so they restore too. `kill -9` is the crash path.
    func handleSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        sigterm = source
    }

    public func application(_ application: NSApplication, open urls: [URL]) {}  // RED stub
}
