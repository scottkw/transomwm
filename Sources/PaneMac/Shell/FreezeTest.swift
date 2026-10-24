import Darwin
import Foundation

/// Debug-only Freeze test (D-01, RESEARCH Pitfall 8).
@MainActor public final class FreezeTest {
    public static let defaultsKey = "freezeTestPID"
    public private(set) var frozenPID: pid_t?

    public init(
        defaults: UserDefaults = .standard, signal: @escaping (pid_t, Int32) -> Int32 = Darwin.kill,
        resumeAfter: Duration = .seconds(10)
    ) {}

    public static func isAllowed(pid: pid_t, bundleID: String?, ownPID: pid_t) -> Bool { true }

    @discardableResult public func freeze(pid: pid_t) -> Bool { false }

    public func resumeNow() {}

    public func resumeRecordedPID() {}
}
