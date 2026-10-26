import AppKit
import PaneEngine
import os

/// Pane's application delegate: the quit restore (SAFE-01, D-15, RESEARCH Pattern 11) and the `pane://` URL commands
/// (SAFE-03, TILE-15, TILE-17, Pattern 16).
@MainActor public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let restore: () -> Void
    private let writeCleanExit: () -> Void
    private let reply: (Bool) -> Void
    private let open: (Command) -> Void
    /// The scheme this build registered (`pane`, or `pane-debug` in Debug, A8); nil when run outside the app bundle.
    private let urlScheme: String?
    private var limiter = PaneURLRateLimiter()
    private let logger = Logger(subsystem: "com.eightabyte.pane", category: "url")
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

    /// Each URL that parses strictly and is admitted by the rate limit goes to `open`, the dispatcher its hotkey and menu
    /// item use. A rejected one is logged without its contents and shows nothing (Pitfall 21).
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let urlScheme, let command = PaneURL.parse(url, scheme: urlScheme) else {
                logger.notice("rejected a URL")
                continue
            }
            guard limiter.admit(command, at: .now) else {
                logger.info("rate-limited a URL command")
                continue
            }
            open(command)
        }
    }

    /// The first `CFBundleURLSchemes` entry of the main bundle's Info.plist.
    static func registeredScheme(in bundle: Bundle = .main) -> String? {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first
    }
}
