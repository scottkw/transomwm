import AppKit

/// Lock, sleep and session signals (D-09). Paused while any signal family says locked or asleep; resumed only
/// when every family has cleared. `onPause` fires on the not-paused → paused edge, `onResume` on the reverse.
///
/// Belt and braces (RESEARCH A3, confirmed on macOS 27 while locked): `com.apple.screenIsLocked` /
/// `screenIsUnlocked`, system sleep and wake, display sleep and wake, fast user switching, `loginwindow`
/// frontmost, and the `CGSSessionScreenIsLocked` session flag polled by `evaluate()`. A spoofed lock
/// notification can only pause (nothing closes); the matching unlock or wake clears it (T-02-25).
@MainActor public final class SessionGate {
    private enum Signal { case screenLocked, systemAsleep, displaysAsleep, sessionInactive, loginWindowFrontmost, sessionLockFlag }

    private let sessionDictionary: () -> [String: Any]?
    private let frontmostBundleID: () -> String?
    private let onPause: () -> Void
    private let onResume: () -> Void
    private var on: Set<Signal> = []
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    public init(
        workspaceCenter: NotificationCenter, distributedCenter: NotificationCenter,
        sessionDictionary: @escaping () -> [String: Any]?, frontmostBundleID: @escaping () -> String?,
        onPause: @escaping () -> Void, onResume: @escaping () -> Void
    ) {
        self.sessionDictionary = sessionDictionary
        self.frontmostBundleID = frontmostBundleID
        self.onPause = onPause
        self.onResume = onResume
        observe(distributedCenter, Notification.Name("com.apple.screenIsLocked")) { $0.set(.screenLocked, true) }
        observe(distributedCenter, Notification.Name("com.apple.screenIsUnlocked")) { $0.set(.screenLocked, false) }
        observe(workspaceCenter, NSWorkspace.willSleepNotification) { $0.set(.systemAsleep, true) }
        observe(workspaceCenter, NSWorkspace.didWakeNotification) { $0.set(.systemAsleep, false) }
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification) { $0.set(.displaysAsleep, true) }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification) { $0.set(.displaysAsleep, false) }
        observe(workspaceCenter, NSWorkspace.sessionDidResignActiveNotification) { $0.set(.sessionInactive, true) }
        observe(workspaceCenter, NSWorkspace.sessionDidBecomeActiveNotification) { $0.set(.sessionInactive, false) }
        observe(workspaceCenter, NSWorkspace.didActivateApplicationNotification) { $0.evaluate() }
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    public var isPaused: Bool { !on.isEmpty }

    /// Polls the two signals that have no notification: `loginwindow` frontmost and the session lock flag.
    public func evaluate() {
        set(.loginWindowFrontmost, frontmostBundleID() == "com.apple.loginwindow")
        set(.sessionLockFlag, sessionDictionary()?["CGSSessionScreenIsLocked"] as? Bool == true)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handle: @escaping @MainActor (SessionGate) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        }
        observers.append((center, observer))
    }

    private func set(_ signal: Signal, _ value: Bool) {
        let wasPaused = isPaused
        if value { on.insert(signal) } else { on.remove(signal) }
        if !wasPaused, isPaused { onPause() }
        if wasPaused, !isPaused { onResume() }
    }
}
