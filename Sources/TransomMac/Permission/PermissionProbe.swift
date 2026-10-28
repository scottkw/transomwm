import AppKit
import ApplicationServices
import TransomEngine
import os

/// Checks that a trusted grant really works by reading another app's AXRole (D-02, T-02-14).
///
/// Never Transom's own pid, and never the system-wide focused-application attribute (RESEARCH Open
/// Question 1). Each read runs on a detached task with a 1 s timeout: Finder once plus 3 retries,
/// then the frontmost regular app once, so the probe resolves in about 5 s at worst.
enum PermissionProbe {
    static func run() async -> ProbeOutcome {
        let logger = Logger(subsystem: "com.eightabyte.transom", category: "permission")
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first(where: { $0.processIdentifier != ownPID })
        {
            for _ in 0..<4 {
                let code = await readRole(pid: finder.processIdentifier)
                if code != AXError.cannotComplete.rawValue { return outcome(code, logger: logger) }
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
            front.processIdentifier != ownPID
        {
            let code = await readRole(pid: front.processIdentifier)
            if code != AXError.cannotComplete.rawValue { return outcome(code, logger: logger) }
        }
        logger.info("probe inconclusive: every AXRole read timed out; treating access as working")
        return .inconclusive
    }

    /// Only -25211 means the grant is stale; any other answer proves the AX API is reachable.
    private static func outcome(_ code: Int32, logger: Logger) -> ProbeOutcome {
        if code == AXError.apiDisabled.rawValue { return .apiDisabled }
        if code != AXError.success.rawValue { logger.info("probe AXRole read returned \(code, privacy: .public); API reachable") }
        return .success
    }

    private nonisolated static func readRole(pid: pid_t) async -> Int32 {
        await Task.detached {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 1.0)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &value).rawValue
        }.value
    }
}
