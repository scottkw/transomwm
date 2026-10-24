import AppKit

/// Lock, sleep and session signals (D-09). RED stub: never pauses.
@MainActor public final class SessionGate {
    public init(
        workspaceCenter: NotificationCenter, distributedCenter: NotificationCenter,
        sessionDictionary: @escaping () -> [String: Any]?, frontmostBundleID: @escaping () -> String?,
        onPause: @escaping () -> Void, onResume: @escaping () -> Void
    ) {}

    public var isPaused: Bool { false }

    public func evaluate() {}
}
