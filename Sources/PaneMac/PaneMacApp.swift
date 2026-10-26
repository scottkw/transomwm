import AppKit
import ApplicationServices
import Combine
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
    /// Takes the event tap down the moment access leaves `.ready`, and brings it back with access (Pitfall 4).
    private static var accessSubscription: AnyCancellable?
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
        // The only reader of system.events: it re-reads the inventory after each event and feeds the menu.
        // The layout survives a quit and relaunch (SAFE-06); the store loads when tracking starts.
        let layoutStore = LayoutStore(directory: MinimumHintsStore.defaultDirectory)
        let gaps = GapPreference()
        let arrangeController = ArrangeController(system: system, store: layoutStore, exclusions: exclusions, gap: gaps.value)
        gaps.onChange = { gap in Task { await arrangeController.setGap(gap) } }
        arrangeController.isReady = { permissionController.state.phase == .ready }
        // The one dispatcher: every hotkey and every command menu item runs exactly this (TILE-09).
        let dispatch: @MainActor (Command) -> Void = { command in Task { await arrangeController.dispatch(command) } }
        let controller = StatusItemController(
            system: system, arrange: arrangeController, dispatch: dispatch, permission: permissionController, gaps: gaps,
            exclusions: exclusions, freezeTest: freezeTest, showTrackedWindows: { trackedController.show() },
            showSetup: { setupController.show() }
        )
        controller.onInventory = { trackedController.feed.inventory = $0 }
        arrangeController.onInventory = { controller.update($0) }
        trackedWindows = trackedController
        statusItem = controller
        arrange = arrangeController
        permission = permissionController
        setupWindow = setupController
        permissionController.onTrackingStarted = {
            await arrangeController.start()
            arrangeController.startTap()  // drags (TILE-01)
        }
        accessSubscription = permissionController.$state.map { $0.phase == .ready }.removeDuplicates().dropFirst()
            .sink { ready in arrangeController.accessChanged(ready: ready) }
        Hotkeys.register(dispatch)
        permissionController.send(.launched(trusted: AXIsProcessTrusted()))
        setupController.decideAtLaunch()
        // Quit Pane during a freeze resumes the app now rather than at the next launch. A normal quit is recorded
        // as cleanExit in layout.json (plan 15 moves this after the quit restore).
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                freezeTest.resumeNow()
                arrangeController.writeCleanExit()
            }
        }
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
