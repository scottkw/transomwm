import AppKit
import os

/// Move to Applications (D-08, RESEARCH Pattern 6): copy this bundle, strip quarantine from the copy, relaunch it once
/// this process has exited. No SPI: the copy comes from `Bundle.main.bundleURL`, which reads through a translocated path.
@MainActor enum AppMover {
    /// An existing `destination` goes through `trash` first (never removed). Quarantine comes off the fresh copy only,
    /// or macOS would translocate it again (Pitfall 6); this bundle already passed Gatekeeper to be running.
    static func copy(from source: URL, to destination: URL, trash: (URL) throws -> Void) throws {
        if FileManager.default.fileExists(atPath: destination.path) { try trash(destination) }
        try FileManager.default.copyItem(at: source, to: destination)
        var paths = [destination.path]
        if let items = FileManager.default.enumerator(atPath: destination.path) {
            for case let item as String in items { paths.append(destination.appendingPathComponent(item).path) }
        }
        // A missing attribute (ENOATTR) is the normal case, so the result isn't checked.
        for path in paths { removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }

    /// The real `trash` for `copy`: the Finder Trash, so a replaced Transom can be put back (T-09-49).
    static func moveToTrash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }

    /// `/bin/sh` waits for `pid` to exit (it holds the CLI port name, Pitfall 8), then opens `path`. Both are argv
    /// (`$1`, `$2`), never part of the script (T-09-47).
    nonisolated static func relaunchArguments(pid: Int32, path: String) -> [String] {
        ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"", "sh", "\(pid)", path]
    }

    /// Starts the relaunch helper and quits. A helper that won't start is logged; Transom quits anyway, since the copy
    /// is already in Applications to open.
    static func relaunchAndQuit(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = relaunchArguments(pid: ProcessInfo.processInfo.processIdentifier, path: path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Logger(subsystem: "com.eightabyte.transom", category: "onboarding")
                .error("relaunch helper could not launch: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }
}
