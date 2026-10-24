import AppKit
import ApplicationServices
import PaneEngine
import PanePrivate

/// Entry point shared by the PaneApp executable and the Xcode-built app bundle.
public enum PaneMacApp {
    /// Keeps the menu-bar item (and through it the window system) alive for the process lifetime.
    private static var statusItem: StatusItemController?
    private static var permission: PermissionController?
    private static var setupWindow: SetupWindowController?
    private static var trackedWindows: TrackedWindowsWindowController?
    private static let freezeTest = FreezeTest()

    public static func run(arguments: [String]) -> Never {
        // First, in every build: a crash or quit during a Debug freeze must never leave an app stopped.
        freezeTest.resumeRecordedPID()
        Capabilities.logReport()
        if arguments.contains("--print-inventory-summary") { printInventorySummary() }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let system = AXWindowSystem()
        // Tracking starts only through the reducer's startTracking effect, once access is confirmed.
        let permissionController = PermissionController(system: system)
        let setupController = SetupWindowController(permission: permissionController)
        let exclusions = ExclusionStore()
        let trackedController = TrackedWindowsWindowController(
            permission: permissionController, exclusions: exclusions,
            windowIDLookupAvailable: system.capabilityReport[.axWindowID] == true
        ) { setupController.show() }
        let controller = StatusItemController(
            system: system, permission: permissionController, exclusions: exclusions, freezeTest: freezeTest,
            showTrackedWindows: { trackedController.show() }, showSetup: { setupController.show() }
        )
        controller.onInventory = { trackedController.feed.inventory = $0 }
        trackedWindows = trackedController
        statusItem = controller
        permission = permissionController
        setupWindow = setupController
        permissionController.onTrackingStarted = { await controller.refresh() }
        permissionController.send(.launched(trusted: AXIsProcessTrusted()))
        setupController.decideAtLaunch()
        // Quit Pane during a freeze resumes the app now rather than at the next launch.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { freezeTest.resumeNow() } }
        app.run()
        exit(0)
    }

    /// Prints `pane: tracked windows=N apps=M` after the first sweep, then exits.
    /// Exit 3: not trusted for Accessibility; exit 4: the sweep took over 10 s.
    private static func printInventorySummary() -> Never {
        guard AXIsProcessTrusted() else {
            print("pane: accessibility not trusted")
            exit(3)
        }
        Task {
            try? await Task.sleep(for: .seconds(10))
            print("pane: initial refresh timed out")
            exit(4)
        }
        Task {
            let system = AXWindowSystem()
            await system.start()
            let windows = await system.inventory().windows
            print("pane: tracked windows=\(windows.count) apps=\(Set(windows.map(\.window.pid)).count)")
            exit(0)
        }
        dispatchMain()
    }
}
