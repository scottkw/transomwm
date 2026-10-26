import AppKit
import ApplicationServices
import PaneEngine
import PanePrivate
import os

/// Entry point shared by the PaneApp executable and the Xcode-built app bundle.
public enum PaneMacApp {
    /// Keeps the menu-bar item (and through it the window system) alive for the process lifetime.
    private static var statusItem: StatusItemController?
    private static var arrange: ArrangeController?
    private static var permission: PermissionController?
    private static var setupWindow: SetupWindowController?
    private static var trackedWindows: TrackedWindowsWindowController?
    private static let freezeTest = FreezeTest()
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "hints")

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
        // The window system enforces the list (D-12); the store only validates and keeps it.
        system.setExcludedBundleIDs(Set(exclusions.bundleIDs))
        exclusions.onChange = { system.setExcludedBundleIDs(Set(exclusions.bundleIDs)) }
        // Learned minimums survive relaunch per bundle (D-13); a rejected file is logged and set aside by load().
        let hints = MinimumHintsStore(directory: MinimumHintsStore.defaultDirectory)
        hints.load()
        system.setBundleHints(hints.hints)
        system.onLearnedMinimum = { bundleID, minimum in
            guard hints.record(bundleID: bundleID, minimum: minimum) else { return }
            do {
                try hints.save()
            } catch {
                logger.error("could not save \(MinimumHintsStore.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        let trackedController = TrackedWindowsWindowController(
            permission: permissionController, exclusions: exclusions,
            windowIDLookupAvailable: { system.capabilityReport[.axWindowID] == true }
        ) { setupController.show() }
        let controller = StatusItemController(
            system: system, permission: permissionController, exclusions: exclusions, freezeTest: freezeTest,
            showTrackedWindows: { trackedController.show() }, showSetup: { setupController.show() }
        )
        controller.onInventory = { trackedController.feed.inventory = $0 }
        // The only reader of system.events: it re-reads the inventory after each event and feeds the menu.
        let arrangeController = ArrangeController(system: system)
        arrangeController.onInventory = { controller.update($0) }
        trackedWindows = trackedController
        statusItem = controller
        arrange = arrangeController
        permission = permissionController
        setupWindow = setupController
        permissionController.onTrackingStarted = { await arrangeController.start() }
        // ⌃⌥⌘D/F/Z; a command the Arranger refuses beeps (UI-SPEC: no hotkey fails silently).
        Hotkeys.register { command in Task { await arrangeController.dispatch(command) } }
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
