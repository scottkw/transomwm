import AppKit
import ApplicationServices
import PanePrivate

/// Entry point shared by the PaneApp executable and the Xcode-built app bundle.
public enum PaneMacApp {
    /// Keeps the menu-bar item (and through it the window system) alive for the process lifetime.
    private static var statusItem: StatusItemController?

    public static func run(arguments: [String]) -> Never {
        Capabilities.logReport()
        if arguments.contains("--print-inventory-summary") { printInventorySummary() }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let system = AXWindowSystem()
        let controller = StatusItemController(system: system)
        statusItem = controller
        if AXIsProcessTrusted() {
            Task {
                await system.start()
                await controller.refresh()
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
