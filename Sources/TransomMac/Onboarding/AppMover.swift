import AppKit
import os

/// Move to Applications (D-08, RESEARCH Pattern 6): copy this bundle, strip quarantine from the copy, relaunch it once
/// this process has exited. No SPI: the copy comes from `Bundle.main.bundleURL`, which reads through a translocated path.
@MainActor enum AppMover {
    /// The copy lands in a staging folder beside `destination` first, so a failed copy never costs the installed one and
    /// a translocated source that *is* the installed copy is read before it moves (WR-01). Then an existing `destination`
    /// goes through `trash` (never removed) and the staged copy is renamed into place; if that rename fails, the trashed
    /// copy is put back. Quarantine comes off the fresh copy only, or macOS would translocate it again (Pitfall 6); this
    /// bundle already passed Gatekeeper to be running. `trash` returns where the old copy went.
    static func copy(from source: URL, to destination: URL, trash: (URL) throws -> URL?) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).moving-\(UUID().uuidString)")
        var trashed: URL?
        do {
            try FileManager.default.copyItem(at: source, to: staging)
            var paths = [staging.path]
            if let items = FileManager.default.enumerator(atPath: staging.path) {
                for case let item as String in items { paths.append(staging.appendingPathComponent(item).path) }
            }
            // A missing attribute (ENOATTR) is the normal case, so the result isn't checked.
            for path in paths { removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) }
            if FileManager.default.fileExists(atPath: destination.path) { trashed = try trash(destination) }
            try FileManager.default.moveItem(at: staging, to: destination)  // same folder: a rename
        } catch {
            // The rename failed after the trash: put the installed copy back rather than leave none (WR-01, round 2).
            if let trashed { try? FileManager.default.moveItem(at: trashed, to: destination) }
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// The real `trash` for `copy`: the Finder Trash, so a replaced Transom can be put back (T-09-49).
    static func moveToTrash(_ url: URL) throws -> URL? {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

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
