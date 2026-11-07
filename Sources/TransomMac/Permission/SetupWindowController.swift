import AppKit
import Combine
import TransomEngine
import SwiftUI
import os

/// Owns the "Set Up Transom" window (02-UI-SPEC Surface 2, 09 UI-SPEC Surface 2). On the first run it opens at
/// launch at Welcome and walks the onboarding steps; after completion it opens by itself at most once, at launch,
/// and only when access isn't ready, showing only the Accessibility step. After that only `show()` (menu, Tracked
/// Windows) opens it.
@MainActor final class SetupWindowController: NSObject, NSWindowDelegate {
    static let completedKey = "onboarding.completed"
    private let permission: PermissionController
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "onboarding")
    let model: OnboardingModel
    private var window: NSWindow?
    private var userClosed = false
    private var awaitingLaunchDecision = false
    private var subscription: AnyCancellable?

    init(permission: PermissionController, defaults: UserDefaults = .standard) {
        self.permission = permission
        self.defaults = defaults
        model = OnboardingModel(steps: OnboardingFlow.steps(completed: defaults.bool(forKey: Self.completedKey)))
        super.init()
        subscription = permission.$state.sink { [weak self] state in self?.stateChanged(state) }
    }

    private var completed: Bool { defaults.bool(forKey: Self.completedKey) }

    /// Call right after `.launched`. A trusted launch waits for its probe, so a working grant never
    /// flashes the window; any other outcome shows it. The first run shows it either way.
    func decideAtLaunch() {
        awaitingLaunchDecision = true
        stateChanged(permission.state)
    }

    func show() {
        let steps = OnboardingFlow.steps(completed: completed)
        if model.steps != steps {
            model.steps = steps
            go(to: steps[0])
        }
        let window = window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// `state` is the new value: `@Published` delivers it before `permission.state` changes.
    private func stateChanged(_ state: PermissionState) {
        // Mid-flow, ready access moves on by itself, with no "Transom is ready" stop on the Accessibility step.
        if model.current == .accessibility, state.phase == .ready,
            let next = OnboardingFlow.next(after: .accessibility, in: model.steps)
        {
            go(to: next)
        }
        guard awaitingLaunchDecision, state.phase != .probing else { return }
        awaitingLaunchDecision = false
        if (!completed || state.phase != .ready) && !userClosed { show() }
    }

    /// Continue: the next step, passing the Accessibility step when access is already ready.
    func advance() {
        guard var step = OnboardingFlow.next(after: model.current, in: model.steps) else { return }
        if step == .accessibility, permission.state.phase == .ready,
            let after = OnboardingFlow.next(after: step, in: model.steps)
        {
            step = after
        }
        go(to: step)
    }

    /// Done: the first run is over; later launches keep Phase 2's rule.
    func finish() {
        defaults.set(true, forKey: Self.completedKey)
        logger.info("completed")
        window?.performClose(nil)
    }

    private func go(to step: OnboardingStep) {
        guard model.current != step else { return }
        model.current = step
        logger.info("step \(step.rawValue, privacy: .public)")
    }

    func makeWindow() -> NSWindow {
        if let window { return window }  // a second window would orphan the first, still delegate-wired
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
        let view = OnboardingView(
            model: model, permission: permission, appName: appName,
            advance: { [weak self] in self?.advance() },
            finish: { [weak self] in self?.finish() },
            close: { [weak self] in self?.window?.performClose(nil) })
        let hosting = NSHostingController(rootView: view)
        // The hosting controller publishes SwiftUI's size as preferredContentSize, which the window applies,
        // so its height follows each state's content (G-02-1).
        hosting.sizingOptions = [.preferredContentSize]
        let window = KeyClosableWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Set Up Transom"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.layoutIfNeeded()
        // AppKit may apply preferredContentSize only on a later layout pass (measured on macOS 27), so size the
        // window once now, before the centring reads window.frame; later states are sized by preferredContentSize.
        window.setContentSize(hosting.view.fittingSize)
        // Centred on the menu-bar screen (the first screen), on first show only.
        if let screen = NSScreen.screens.first?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        }
        self.window = window
        permission.setupWindow = window
        return window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        permission.state.phase != .resetting
    }

    func windowWillClose(_ notification: Notification) {
        userClosed = true
    }
}

/// Esc and ⌘W close the window (an accessory app has no main menu to supply ⌘W); both go through
/// `performClose`, so a delegate can still block them (the setup window does while a reset runs).
/// Shared by the Set Up Transom and Tracked Windows windows.
final class KeyClosableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            event.charactersIgnoringModifiers == "w"
        {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
