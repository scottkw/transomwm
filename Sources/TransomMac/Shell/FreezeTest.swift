import Darwin
import Foundation
import os

/// Debug-only Freeze test (D-01, RESEARCH Pitfall 8, T-02-21): SIGSTOPs one ordinary app for a while so
/// the developer can watch Transom stay responsive. The pid is persisted before SIGSTOP, so a crash or quit
/// mid-freeze is undone by `resumeRecordedPID()` at the next launch, which runs in every build.
@MainActor public final class FreezeTest {
    public static let defaultsKey = "freezeTestPID"
    /// Processes whose stop would hang the login session or the Mac's UI.
    static let refusedBundleIDs: Set<String> = [
        "com.apple.loginwindow", "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
    ]
    public private(set) var frozenPID: pid_t?
    private let defaults: UserDefaults
    private let signal: (pid_t, Int32) -> Int32
    private let resumeAfter: Duration
    public private(set) var resumeTask: Task<Void, Never>?  // readable so a test can await the resume, not a clock
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "freeze")

    public init(
        defaults: UserDefaults = .standard, signal: @escaping (pid_t, Int32) -> Int32 = Darwin.kill,
        resumeAfter: Duration = .seconds(10)
    ) {
        self.defaults = defaults
        self.signal = signal
        self.resumeAfter = resumeAfter
    }

    public static func isAllowed(pid: pid_t, bundleID: String?, ownPID: pid_t) -> Bool {
        pid > 1 && pid != ownPID && !refusedBundleIDs.contains(bundleID?.lowercased() ?? "")
    }

    /// Stops `pid` and schedules its resume. Refused (false) while another app is frozen.
    /// The caller checks `isAllowed` with the app's bundle ID; this re-checks the pid itself.
    @discardableResult public func freeze(pid: pid_t) -> Bool {
        guard frozenPID == nil, Self.isAllowed(pid: pid, bundleID: nil, ownPID: getpid()) else { return false }
        defaults.set(Int(pid), forKey: Self.defaultsKey)  // before SIGSTOP, so a crash can't leave it stopped
        guard signal(pid, SIGSTOP) == 0 else {
            logger.error("SIGSTOP to pid \(pid, privacy: .public) failed: errno \(errno, privacy: .public)")
            defaults.removeObject(forKey: Self.defaultsKey)
            return false
        }
        logger.notice("froze pid \(pid, privacy: .public)")
        frozenPID = pid
        resumeTask = Task { [weak self, resumeAfter] in
            try? await Task.sleep(for: resumeAfter)
            guard !Task.isCancelled else { return }
            self?.resumeNow()
        }
        return true
    }

    public func resumeNow() {
        resumeTask?.cancel()
        resumeTask = nil
        guard let pid = frozenPID else { return }
        frozenPID = nil
        resume(pid)
    }

    /// Resumes a pid left by a crash or quit during a freeze. SIGCONT to a running process is harmless.
    public func resumeRecordedPID() {
        let pid = pid_t(truncatingIfNeeded: defaults.integer(forKey: Self.defaultsKey))
        guard pid > 1 else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        logger.notice("resuming pid \(pid, privacy: .public) left frozen by an earlier run")
        resume(pid)
    }

    private func resume(_ pid: pid_t) {
        if signal(pid, SIGCONT) != 0 {
            logger.error("SIGCONT to pid \(pid, privacy: .public) failed: errno \(errno, privacy: .public)")
        }
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
