import AppKit
import Combine
import TransomEngine
import SwiftUI

/// Owns the "Set Up Transom" window (02-UI-SPEC Surface 2). It opens by itself at most once, at launch,
/// and only when access isn't ready; after that only `show()` (menu, Tracked Windows) opens it.
@MainActor final class SetupWindowController: NSObject, NSWindowDelegate {
    private let permission: PermissionController
    private var window: NSWindow?
    private var userClosed = false
    private var awaitingLaunchDecision = false
    private var subscription: AnyCancellable?

    init(permission: PermissionController) {
        self.permission = permission
        super.init()
        subscription = permission.$state.sink { [weak self] state in self?.launchDecision(state) }
    }

    /// Call right after `.launched`. A trusted launch waits for its probe, so a working grant never
    /// flashes the window; any other outcome shows it.
    func decideAtLaunch() {
        awaitingLaunchDecision = true
        launchDecision(permission.state)
    }

    func show() {
        let window = window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func launchDecision(_ state: PermissionState) {
        guard awaitingLaunchDecision, state.phase != .probing else { return }
        awaitingLaunchDecision = false
        if state.phase != .ready && !userClosed { show() }
    }

    func makeWindow() -> NSWindow {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ProcessInfo.processInfo.processName
        let view = SetupView(permission: permission, appName: appName) { [weak self] in self?.window?.performClose(nil) }
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
