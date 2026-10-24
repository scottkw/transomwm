import AppKit

// Test fixture for PaneMacIntegrationTests: opens real windows and reports their CGWindowIDs and
// top-left global frames on stdout. It never sends AX requests itself.
//
// stdout protocol (one line each, space-separated key=value):
//   ready pid=<pid>
//   window index=<i> id=<CGWindowID> kind=<spec> frame=<x>,<y>,<w>,<h>

/// Global top-left -> AppKit bottom-left, computed here independently of PaneEngine (an oracle).
func primaryHeight() -> Double { Double(NSScreen.screens[0].frame.height) }

func appKitRect(topLeftX x: Double, y: Double, width: Double, height: Double) -> NSRect {
    NSRect(x: x, y: primaryHeight() - y - height, width: width, height: height)
}

func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

final class Fixture: NSObject, NSApplicationDelegate {
    var windows: [(window: NSWindow, kind: String)] = []
    let specs: [String]

    init(specs: [String]) {
        self.specs = specs
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for spec in specs { open(spec) }
        NSApp.activate(ignoringOtherApps: true)
        emit("ready pid=\(ProcessInfo.processInfo.processIdentifier)")
        for index in windows.indices { emitWindow(index) }
    }

    func open(_ spec: String) {
        let index = windows.count
        let window = NSWindow(
            contentRect: appKitRect(topLeftX: 40 + 40 * Double(index), y: 80 + 40 * Double(index), width: 320, height: 232),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Fixture \(index)"
        // contentRect sized the content; pin the whole frame to the requested top-left rect.
        window.setFrame(appKitRect(topLeftX: 40 + 40 * Double(index), y: 80 + 40 * Double(index), width: 320, height: 232), display: true)
        window.makeKeyAndOrderFront(nil)
        windows.append((window, spec))
    }

    func emitWindow(_ index: Int) {
        let (window, kind) = windows[index]
        let f = window.frame
        let y = primaryHeight() - f.maxY
        emit("window index=\(index) id=\(window.windowNumber) kind=\(kind) frame=\(Int(f.minX)),\(Int(y)),\(Int(f.width)),\(Int(f.height))")
    }
}

var specs: [String] = []
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    if argument == "--window", let spec = arguments.next() { specs.append(spec) }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let fixture = Fixture(specs: specs)
app.delegate = fixture
app.run()
