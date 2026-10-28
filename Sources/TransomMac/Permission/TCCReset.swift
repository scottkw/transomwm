import Foundation
import os

/// Runs `tccutil reset Accessibility <bundle ID>` for Transom's own entry (D-02, T-02-13).
/// Fixed executable and argv, no shell; the controller only ever passes `Bundle.main.bundleIdentifier`.
nonisolated public enum TCCReset {
    public static func arguments(bundleID: String) -> [String] {
        ["reset", "Accessibility", bundleID]
    }

    /// tccutil's exit status (64 = bundle ID unknown to LaunchServices); -1 when there is no bundle ID
    /// (nothing is run) or the process could not launch.
    public static func run(bundleID: String?) async -> Int32 {
        let logger = Logger(subsystem: "com.eightabyte.transom", category: "permission")
        guard let bundleID, !bundleID.isEmpty else {
            logger.error("tccutil reset refused: no bundle identifier")
            return -1
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments(bundleID: bundleID)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                logger.error("tccutil could not launch: \(error.localizedDescription, privacy: .public)")
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
