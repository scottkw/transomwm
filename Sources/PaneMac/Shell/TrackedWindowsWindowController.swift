import AppKit
import SwiftUI

/// Owns the "Tracked Windows" window (02-UI-SPEC Surface 3). Closing it stops nothing: tracking continues
/// and the feed keeps receiving inventories.
@MainActor final class TrackedWindowsWindowController {
    let feed = TrackedWindowsFeed()
    private let permission: PermissionController
    private let exclusions: ExclusionStore
    private let windowIDLookupAvailable: () -> Bool
    private let showSetup: () -> Void
    private var window: NSWindow?

    init(
        permission: PermissionController, exclusions: ExclusionStore, windowIDLookupAvailable: @escaping () -> Bool,
        showSetup: @escaping () -> Void
    ) {
        self.permission = permission
        self.exclusions = exclusions
        self.windowIDLookupAvailable = windowIDLookupAvailable
        self.showSetup = showSetup
    }

    func show() {
        let window = window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = TrackedWindowsView(
            feed: feed, permission: permission, exclusions: exclusions,
            windowIDLookupAvailable: windowIDLookupAvailable, showSetup: showSetup
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []  // the window, not the table's ideal size, decides the frame
        let window = KeyClosableWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Tracked Windows"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 960, height: 480))
        window.contentMinSize = NSSize(width: 720, height: 320)
        if !window.setFrameUsingName("TrackedWindows") { window.center() }
        window.setFrameAutosaveName("TrackedWindows")
        self.window = window
        return window
    }
}
