import AppKit

// Test fixture for PaneMacIntegrationTests: opens real windows of every shape the classifier, tab,
// close, freeze and frame tests need, changes them on stdin commands, and reports their CGWindowIDs
// and top-left global frames on stdout. It never sends AX requests itself.
//
// Launch: PaneFixtureApp --window <spec> [--window <spec> ...]
// Specs: standard | nofullscreen | borderless-floating | utility-panel | sheet | minsize:<W>x<H> | tabs:<N>
//
// stdout protocol (one line each, space-separated key=value, flushed per line):
//   ready pid=<pid>                                              once, after the launch windows settle
//   window index=<i> id=<CGWindowID> kind=<spec> frame=<x>,<y>,<w>,<h>   top-left global points, integers
//   ok <command> | error <message>                               ends every command's reply
// stdin commands (one per line; any window lines a command prints come before its ok):
//   open <spec> | close <i> | move <i> <x> <y> | resize <i> <w> <h> | minimize <i> | deminimize <i>
//   select-tab <i> | hide-app | unhide-app | list | quit
// Closing stdin quits the fixture, so a crashed test never leaves it running.

/// Global top-left -> AppKit bottom-left, computed here independently of PaneEngine (an oracle).
func primaryHeight() -> Double { Double(NSScreen.screens[0].frame.height) }

func appKitRect(x: Double, y: Double, width: Double, height: Double) -> NSRect {
    NSRect(x: x, y: primaryHeight() - y - height, width: width, height: height)
}

func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

struct FixtureFailure: Error {
    let message: String
}

final class Fixture: NSObject, NSApplicationDelegate {
    /// Every window ever opened; an index stays valid after its window closes.
    var entries: [(window: NSWindow, kind: String, open: Bool)] = []
    let launchSpecs: [String]
    /// AppKit animates sheets and tab groups in; report frames once they settle.
    let settle: Duration = .milliseconds(300)

    init(specs: [String]) {
        launchSpecs = specs
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var opened: [Int] = []
        for spec in launchSpecs {
            do throws(FixtureFailure) { opened += try open(spec) } catch { emit("error \(spec): \(error.message)") }
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            try? await Task.sleep(for: settle)
            emit("ready pid=\(ProcessInfo.processInfo.processIdentifier)")
            for index in opened { emitWindow(index) }
        }
    }

    /// Opens the windows for one spec and returns their indices.
    func open(_ spec: String) throws(FixtureFailure) -> [Int] {
        let index = entries.count
        let frame = appKitRect(x: 40 + 40 * Double(index), y: 80 + 40 * Double(index), width: 320, height: 232)
        switch spec {
        case "standard":
            return [add(standardWindow(frame), spec)]
        case "nofullscreen":
            let window = standardWindow(frame)
            window.collectionBehavior = [.fullScreenNone]
            return [add(window, spec)]
        case "borderless-floating":
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            window.backgroundColor = .systemTeal
            return [add(window, spec)]
        case "utility-panel":
            let panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.setFrame(frame, display: true)
            return [add(panel, spec)]
        case "sheet":
            let host = standardWindow(frame)
            let hostIndex = add(host, spec)
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            sheet.isReleasedWhenClosed = false
            host.beginSheet(sheet)
            entries.append((sheet, "sheet-child", true))
            return [hostIndex, entries.count - 1]
        case let spec where spec.hasPrefix("minsize:"):
            let parts = spec.dropFirst("minsize:".count).split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { throw FixtureFailure(message: "bad minsize spec \(spec)") }
            let window = standardWindow(frame)
            window.contentMinSize = NSSize(width: parts[0], height: parts[1])
            return [add(window, spec)]
        case let spec where spec.hasPrefix("tabs:"):
            guard let count = Int(spec.dropFirst("tabs:".count)), count >= 1 else {
                throw FixtureFailure(message: "bad tabs spec \(spec)")
            }
            let first = standardWindow(frame, tabbing: .preferred)
            var indices = [add(first, spec)]
            for _ in 1..<count {
                let member = standardWindow(frame, tabbing: .preferred)
                member.isReleasedWhenClosed = false
                first.addTabbedWindow(member, ordered: .above)
                entries.append((member, spec, true))
                indices.append(entries.count - 1)
            }
            return indices
        default:
            throw FixtureFailure(message: "unknown window spec \(spec)")
        }
    }

    func standardWindow(_ frame: NSRect, tabbing: NSWindow.TabbingMode = .disallowed) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.tabbingMode = tabbing
        window.tabbingIdentifier = "PaneFixtureTabs"
        // contentRect sized the content; pin the whole frame (title bar included) to the requested rect.
        window.setFrame(frame, display: true)
        return window
    }

    func add(_ window: NSWindow, _ kind: String) -> Int {
        window.isReleasedWhenClosed = false
        window.title = "Fixture \(entries.count)"
        window.makeKeyAndOrderFront(nil)
        entries.append((window, kind, true))
        return entries.count - 1
    }

    func emitWindow(_ index: Int) {
        let (window, kind, _) = entries[index]
        let f = window.frame
        emit("window index=\(index) id=\(window.windowNumber) kind=\(kind) frame=\(Int(f.minX.rounded())),\(Int((primaryHeight() - f.maxY).rounded())),\(Int(f.width.rounded())),\(Int(f.height.rounded()))")
    }

    func window(_ argument: String?) throws(FixtureFailure) -> NSWindow {
        guard let argument, let index = Int(argument), entries.indices.contains(index), entries[index].open else {
            throw FixtureFailure(message: "no open window \(argument ?? "<missing>")")
        }
        return entries[index].window
    }

    func numbers(_ parts: [String], _ count: Int) throws(FixtureFailure) -> [Double] {
        let values = parts.dropFirst(2).compactMap { Double($0) }
        guard parts.count == count + 2, values.count == count else { throw FixtureFailure(message: "expected \(count) numbers") }
        return values
    }

    /// Runs one stdin command and answers it.
    func handle(_ command: String) async {
        let parts = command.split(separator: " ").map(String.init)
        do throws(FixtureFailure) {
            switch parts.first {
            case "open":
                guard parts.count == 2 else { throw FixtureFailure(message: "usage: open <spec>") }
                let opened = try open(parts[1])
                try? await Task.sleep(for: settle)
                for index in opened { emitWindow(index) }
            case "close":
                let target = try window(parts.dropFirst().first)
                target.close()
                if let index = entries.firstIndex(where: { $0.window === target }) { entries[index].open = false }
            case "move":
                let target = try window(parts.dropFirst().first)
                let p = try numbers(parts, 2)
                target.setFrame(appKitRect(x: p[0], y: p[1], width: target.frame.width, height: target.frame.height), display: true)
            case "resize":
                let target = try window(parts.dropFirst().first)
                let s = try numbers(parts, 2)
                let topLeftY = primaryHeight() - target.frame.maxY
                target.setFrame(appKitRect(x: target.frame.minX, y: topLeftY, width: s[0], height: s[1]), display: true)
            case "minimize":
                try window(parts.dropFirst().first).miniaturize(nil)
            case "deminimize":
                try window(parts.dropFirst().first).deminiaturize(nil)
            case "select-tab":
                let target = try window(parts.dropFirst().first)
                guard let group = target.tabGroup else { throw FixtureFailure(message: "window is not in a tab group") }
                group.selectedWindow = target
            case "hide-app":
                NSApp.hide(nil)
            case "unhide-app":
                NSApp.unhide(nil)
            case "list":
                for index in entries.indices where entries[index].open { emitWindow(index) }
            case "quit":
                emit("ok quit")
                exit(0)
            default:
                throw FixtureFailure(message: "unknown command")
            }
            emit("ok \(command)")
        } catch {
            emit("error \(command): \(error.message)")
        }
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

// Commands run one at a time on MainActor; the reader waits for each to finish.
let stdinReader = Thread {
    while let line = readLine() {
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await fixture.handle(line.trimmingCharacters(in: .whitespaces))
            done.signal()
        }
        done.wait()
    }
    exit(0)
}
stdinReader.start()
app.run()
