import AppKit

/// App lifecycle from NSWorkspace: which apps get an `AXAppThread`.
///
/// An app is started once it is `.regular` and has finished launching (Pitfall 11); it is never Transom itself
/// or the lock screen. An app seen too early is retried on its activation and on each sweep (`recheck()`),
/// and one that stops being `.regular` is stopped.
@MainActor final class AppRegistry {
    private let onStart: (NSRunningApplication) -> Void
    /// `(pid, terminated)`: true when the app quit, false when it only stopped being eligible.
    private let onStop: (Int32, Bool) -> Void
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var started: Set<Int32> = []
    private var observers: [any NSObjectProtocol] = []

    init(onStart: @escaping (NSRunningApplication) -> Void, onStop: @escaping (Int32, Bool) -> Void) {
        self.onStart = onStart
        self.onStop = onStop
    }

    isolated deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Starts every eligible running app, then follows launches, quits, activations and hide/unhide.
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let checked: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in checked {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.check(app) }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.terminated(pid) }
        })
        recheck()
    }

    /// Re-checks every running app (each sweep), and stops apps that have gone without a termination notice.
    func recheck() {
        let running = NSWorkspace.shared.runningApplications
        for app in running { check(app) }
        let alive = Set(running.map(\.processIdentifier))
        for pid in started where !alive.contains(pid) { terminated(pid) }
    }

    private func check(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let eligible = app.activationPolicy == .regular && app.isFinishedLaunching && !app.isTerminated
            && pid != ownPID && app.bundleIdentifier != "com.apple.loginwindow"
        if eligible, !started.contains(pid) {
            started.insert(pid)
            onStart(app)
        } else if !eligible, started.contains(pid) {
            started.remove(pid)
            onStop(pid, app.isTerminated)
        }
    }

    private func terminated(_ pid: Int32) {
        guard started.remove(pid) != nil else { return }
        onStop(pid, true)
    }
}
