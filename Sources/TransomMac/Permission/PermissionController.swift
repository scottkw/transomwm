import AppKit
import ApplicationServices
import Combine
import TransomEngine
import os

/// Runs the effects `PermissionReducer` decides (D-02, WIN-01). Every UI click, poll tick and
/// probe/reset result goes through `send(_:)`; nothing here changes the state on its own.
@MainActor public final class PermissionController: ObservableObject {
    @Published public private(set) var state = PermissionState()
    private let system: AXWindowSystem
    private let launchedAt = ContinuousClock.now
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "permission")
    private var pollTask: Task<Void, Never>?
    private var trackingStarted = false
    /// The setup window, brought forward once when access becomes ready (only if still open).
    weak var setupWindow: NSWindow?
    /// Runs after the first tracking sweep, e.g. to refresh the status menu's cached inventory.
    var onTrackingStarted: (() async -> Void)?

    init(system: AXWindowSystem) {
        self.system = system
    }

    /// Time since launch; the reducer's clock for the stale-form-B delay.
    var elapsed: Duration { ContinuousClock.now - launchedAt }

    public func send(_ event: PermissionEvent) {
        let before = state.phase
        var next = state
        let effects = PermissionReducer.reduce(&next, event)
        if next != state { state = next }
        if next.phase != before {
            logger.info("permission \(String(describing: before), privacy: .public) -> \(String(describing: next.phase), privacy: .public)")
        }
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: PermissionEffect) {
        switch effect {
        case .promptForTrust:
            // String literal: the kAXTrustedCheckOptionPrompt global is a Swift 6 error (Pitfall 10).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .openSettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case .startPolling:
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                while true {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self else { return }
                    self.send(.pollTick(trusted: AXIsProcessTrusted(), at: self.elapsed))
                }
            }
        case .stopPolling:
            pollTask?.cancel()
            pollTask = nil
        case .runProbe:
            Task { send(.probeFinished(await PermissionProbe.run())) }
        case .runReset:
            Task { send(.resetFinished(exitCode: await TCCReset.run(bundleID: Bundle.main.bundleIdentifier))) }
        case .startTracking:
            guard !trackingStarted else { return }
            trackingStarted = true
            Task {
                await system.start()
                await onTrackingStarted?()
            }
        case .bringWindowForward:
            guard let window = setupWindow, window.isVisible else { return }
            NSApp.activate()
            window.orderFrontRegardless()
        }
    }
}
