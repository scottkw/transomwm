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
    /// The last step reached, so a relaunch mid-setup resumes (UI-SPEC Surface 2).
    static let stepKey = "onboarding.step"
    private let permission: PermissionController
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.eightabyte.transom", category: "onboarding")
    let model: OnboardingModel
    private var window: NSWindow?
    private var userClosed = false
    private var awaitingLaunchDecision = false
    private var subscription: AnyCancellable?
    /// Screen Recording through `SnapshotCapture`, injected so tests never touch it (RESEARCH Pitfall 5).
    var screenRecordingGranted: (() -> Bool)?
    var requestScreenRecording: (() -> Bool)?
    /// Done's Open Settings: nil opens the last tab shown.
    var openSettings: ((SettingsPane?) -> Void)?
    /// Launch at login (SHIP-03), injected so tests never register the real login item.
    var loginItem: (any LoginItemService)?
    private var screenRecordingPoll: Task<Void, Never>?

    init(permission: PermissionController, defaults: UserDefaults = .standard) {
        self.permission = permission
        self.defaults = defaults
        model = OnboardingModel(steps: OnboardingFlow.steps(completed: defaults.bool(forKey: Self.completedKey), conflictsActive: false))
        super.init()
        subscription = permission.$state.sink { [weak self] state in self?.stateChanged(state) }
    }

    private var completed: Bool { defaults.bool(forKey: Self.completedKey) }

    /// Call right after `.launched`. A trusted launch waits for its probe, so a working grant never
    /// flashes the window; any other outcome shows it. The first run shows it either way.
    func decideAtLaunch() {
        if !completed { go(to: OnboardingFlow.resume(stored: defaults.string(forKey: Self.stepKey), in: model.steps)) }
        awaitingLaunchDecision = true
        stateChanged(permission.state)
    }

    /// Whether the window opens by itself once the launch probe has settled, and with which steps. The first run
    /// always opens (step 2 passes by itself when access is ready); later launches only when access isn't ready.
    static func launchDecision(completed: Bool, phase: PermissionPhase) -> (show: Bool, steps: [OnboardingStep]) {
        (!completed || phase != .ready, OnboardingFlow.steps(completed: completed, conflictsActive: false))
    }

    /// Opens the steps for the current completion state: after completion, the lone Accessibility step.
    func show() {
        let steps = Self.launchDecision(completed: completed, phase: permission.state.phase).steps
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
        if Self.launchDecision(completed: completed, phase: state.phase).show && !userClosed { show() }
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

    /// Done's Open Settings: completes onboarding, closes the window, then opens Settings on its last tab.
    func openSettingsFromDone() {
        guard let openSettings else { preconditionFailure("openSettings not wired") }
        finish()
        openSettings(nil)
    }

    /// Launch at login's Continue: registers only while ticked (D-07). A refusal or pending approval keeps the step to
    /// show why; the next Continue moves on.
    func continueLaunchAtLogin() {
        guard let loginItem else { preconditionFailure("loginItem not wired") }
        guard model.launchAtLogin, model.loginResult == nil else { return advance() }
        let result = LoginItemToggle.toggled(true, service: loginItem)
        if result.status == .enabled { advance() } else { model.loginResult = result }
    }

    /// Back: the step before this one.
    func back() {
        guard let index = model.steps.firstIndex(of: model.current), index > 0 else { return }
        go(to: model.steps[index - 1])
    }

    /// Allow Screen Recording: one system request per click; after that the step only polls (D-06).
    func allowScreenRecording() {
        guard let request = requestScreenRecording else { preconditionFailure("requestScreenRecording not wired") }
        model.screenRecordingAsked = true
        model.screenRecordingOn = request()
        logger.info("screen recording requested")
    }

    /// One poll tick: preflight only, never a prompt. The 1 s loop calls it while the step shows.
    func pollScreenRecording() {
        guard let granted = screenRecordingGranted else { preconditionFailure("screenRecordingGranted not wired") }
        model.screenRecordingOn = granted()
    }

    private func go(to step: OnboardingStep) {
        guard model.current != step else { return }
        model.current = step
        defaults.set(step.rawValue, forKey: Self.stepKey)
        screenRecordingPoll?.cancel()
        screenRecordingPoll = nil
        logger.info("step \(step.rawValue, privacy: .public)")
        if step == .screenRecording { enterScreenRecording() }
        if step == .launchAtLogin {
            guard loginItem != nil else { preconditionFailure("loginItem not wired") }
            model.loginResult = nil
        }
    }

    /// Reaching the step answers the Phase 4 previews alert, so it never asks again (UI-SPEC Surface 2).
    private func enterScreenRecording() {
        guard requestScreenRecording != nil else { preconditionFailure("requestScreenRecording not wired") }
        defaults.set(true, forKey: ZoomController.explainerShownKey)
        pollScreenRecording()
        screenRecordingPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.pollScreenRecording()
            }
        }
    }

    func makeWindow() -> NSWindow {
        if let window { return window }  // a second window would orphan the first, still delegate-wired
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
        let view = OnboardingView(
            model: model, permission: permission, appName: appName,
            advance: { [weak self] in self?.advance() },
            back: { [weak self] in self?.back() },
            allowScreenRecording: { [weak self] in self?.allowScreenRecording() },
            finish: { [weak self] in self?.finish() },
            openSettings: { [weak self] in self?.openSettingsFromDone() },
            continueLaunchAtLogin: { [weak self] in self?.continueLaunchAtLogin() },
            openLoginItems: { [weak self] in self?.loginItem?.openSystemSettingsLoginItems() },
            close: { [weak self] in self?.closeAccessibilityStep() })
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

    /// The Accessibility step's Done (shown on ready): mid-flow, after Back from Screen Recording, it moves on.
    private func closeAccessibilityStep() {
        if OnboardingFlow.next(after: model.current, in: model.steps) != nil { advance() } else { window?.performClose(nil) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        permission.state.phase != .resetting
    }

    /// Closing from Screen Recording onward completes the first run; closing earlier leaves it pending. Quits nothing.
    func windowWillClose(_ notification: Notification) {
        userClosed = true
        if [.screenRecording, .features, .launchAtLogin, .done].contains(model.current) {
            defaults.set(true, forKey: Self.completedKey)
            logger.info("completed by close")
        }
        screenRecordingPoll?.cancel()
        screenRecordingPoll = nil
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
