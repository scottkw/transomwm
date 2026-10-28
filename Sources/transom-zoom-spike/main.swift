import AppKit
import Foundation
import TransomEngine
import TransomMac
import TransomModel

// Phase 4 feasibility spike (04-01, CONTEXT D). Runs only in the Tart VM through scripts/vm-spike.sh, never on the host.
// It measures the product's own AX write path (AXWindowSystem.perform -> AXAppThread -> FrameWriter, frameApplied
// read-backs) and its own SnapshotCapture. Every measurement is one JSON line with a "gate" key. Window titles and
// images are never written or logged.

let usage = """
    usage: transom-zoom-spike settle --runs N [--fixtures K] [--apps vscode,safari,terminal,textedit] [--out path] [--limit secs]
    """

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("transom-zoom-spike: \(message)\n".utf8))
    exit(code)
}

var arguments = CommandLine.arguments.dropFirst()
let subcommand: String = {
    guard let first = arguments.popFirst() else { fail(usage, 64) }
    return first
}()
var options: [String: String] = [:]
while let argument = arguments.popFirst() {
    switch argument {
    case "--runs", "--fixtures", "--apps", "--out", "--limit":
        guard let value = arguments.popFirst() else { fail("\(argument) needs a value\n\(usage)", 64) }
        options[argument] = value
    default:
        fail("unknown argument \(argument)\n\(usage)", 64)
    }
}
func intOption(_ name: String, _ fallback: Int) -> Int {
    guard let text = options[name] else { return fallback }
    guard let value = Int(text), value >= 0 else { fail("\(name) must be a non-negative integer", 64) }
    return value
}

// MARK: - Output

/// JSON lines to stdout and, with --out, to that file. The directory of --out also receives recordings and stills.
@MainActor enum Output {
    static let url = options["--out"].map { URL(fileURLWithPath: $0) }
    static let directory = url?.deletingLastPathComponent() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let handle: FileHandle? = {
        guard let url else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()

    static func emit(_ record: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        let line = data + Data("\n".utf8)
        FileHandle.standardOutput.write(line)
        handle?.write(line)
    }

    static func note(_ message: String) {
        FileHandle.standardError.write(Data("spike: \(message)\n".utf8))
    }
}

func ms(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return (Double(seconds) * 1000 + Double(attoseconds) / 1e15).rounded(toPlaces: 1)
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

// MARK: - Test windows

/// The TransomFixtureApp next to this binary, with `standard` windows. Closing its stdin quits it.
final class Fixture {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = ""

    init(windows: [String]) throws {
        process.executableURL = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("TransomFixtureApp")
        process.arguments = windows.flatMap { ["--window", $0] }
        process.standardInput = input
        process.standardOutput = output
        try process.run()
    }

    /// Waits for the fixture's `ready pid=` line.
    func ready(timeout: Duration = .seconds(15)) async -> Int32? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let data = output.fileHandleForReading.availableDataNonBlocking()
            buffer += String(decoding: data, as: UTF8.self)
            if let line = buffer.split(separator: "\n").first(where: { $0.hasPrefix("ready pid=") }) {
                return Int32(line.dropFirst("ready pid=".count))
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func quit() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

extension FileHandle {
    /// What is readable right now, without blocking.
    func availableDataNonBlocking() -> Data {
        let fd = fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { break }
            data.append(bytes, count: count)
        }
        return data
    }
}

/// The real apps of the G1 set and how many windows each contributes.
struct AppSpec {
    let name: String
    let bundleID: String
    let windows: Int
}

let appSpecs: [String: AppSpec] = [
    "vscode": AppSpec(name: "vscode", bundleID: "com.microsoft.VSCode", windows: 2),
    "safari": AppSpec(name: "safari", bundleID: "com.apple.Safari", windows: 2),
    "terminal": AppSpec(name: "terminal", bundleID: "com.apple.Terminal", windows: 2),
    "textedit": AppSpec(name: "textedit", bundleID: "com.apple.TextEdit", windows: 1),
]

@discardableResult
func run(_ path: String, _ args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
}

let work = Output.directory.appendingPathComponent("work")

/// Opens one real app's windows without Apple Events (no Automation prompt): files for Terminal and TextEdit, the VS Code
/// CLI, and Safari's own ⌘N item through AX once it is tracked (`openMoreWindows`).
func launch(_ spec: AppSpec) {
    try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    switch spec.name {
    case "terminal":
        // Long lines under `less`, and the live column count in a file for G6.
        let long = (1...200).map { "line \($0) " + String(repeating: "terminal re-wrap probe ", count: 12) }.joined(separator: "\n")
        try? long.write(to: work.appendingPathComponent("long.txt"), atomically: true, encoding: .utf8)
        for index in 1...spec.windows {
            let script = work.appendingPathComponent("term\(index).command")
            let body = """
                #!/bin/zsh
                cd '\(work.path)'
                ( while [ ! -f stop ]; do tput cols > cols\(index).txt 2>/dev/null; sleep 0.2; done ) &
                less -S long.txt
                exit 0
                """
            try? body.write(to: script, atomically: true, encoding: .utf8)
            chmod(script.path, 0o755)
            run("/usr/bin/open", ["-a", "Terminal", script.path])
        }
    case "textedit":
        let note = work.appendingPathComponent("note.txt")
        try? "Transom zoom spike\n".write(to: note, atomically: true, encoding: .utf8)
        run("/usr/bin/open", ["-a", "TextEdit", note.path])
    case "vscode":
        let cli = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        for index in 1...spec.windows {
            let folder = work.appendingPathComponent("code\(index)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            run(cli, ["-n", folder.path])
        }
    default:
        run("/usr/bin/open", ["-a", "Safari"])
    }
}

// MARK: - Measured set

@MainActor final class Spike {
    let system = AXWindowSystem()
    let capture = SnapshotCapture()
    var fixture: Fixture?
    var launchedPIDs: [Int32] = []
    /// frameApplied arrivals since the batch began.
    var applied: [TransomModel.WindowRef: (at: ContinuousClock.Instant, actual: Rect)] = [:]
    var displays: [DisplayInfo] = []
    var display: DisplayInfo!

    /// Starts the fixture and apps, the window system and its event reader; returns the measured windows by group.
    func prepare(fixtures: Int, apps: [AppSpec]) async -> [WindowInfo] {
        let preRunning = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        var wanted: [(pid: Int32?, bundleID: String?, count: Int)] = []
        if fixtures > 0 {
            guard let fixture = try? Fixture(windows: Array(repeating: "standard", count: fixtures)) else { fail("could not start TransomFixtureApp", 69) }
            self.fixture = fixture
            guard let pid = await fixture.ready() else { fail("TransomFixtureApp did not report ready", 69) }
            wanted.append((pid, nil, fixtures))
        }
        for spec in apps {
            launch(spec)
            wanted.append((nil, spec.bundleID, spec.windows))
        }
        guard AXIsProcessTrusted() else { fail("no Accessibility grant in this session", 3) }
        await system.start()
        Task { [weak self] in
            guard let events = self?.system.events else { return }
            for await event in events {
                if case .frameApplied(let ref, _, let actual) = event { self?.applied[ref] = (.now, actual) }
            }
        }
        // Wait until every group shows its windows; Safari's second window comes from its own ⌘N item.
        let deadline = ContinuousClock.now + .seconds(60)
        var chosen: [WindowInfo] = []
        while ContinuousClock.now < deadline {
            await system.refreshAll()
            let inventory = await system.inventory()
            displays = inventory.displays
            display = displays.first { $0.frame.x == 0 && $0.frame.y == 0 } ?? displays.first
            chosen = []
            var complete = true
            for group in wanted {
                let windows = inventory.windows
                    .filter { info in
                        info.state == .present && info.kind == .dockable && info.displayUUID == display?.uuid
                            && (group.pid.map { info.window.pid == $0 } ?? (info.window.bundleID == group.bundleID))
                    }
                    .sorted { $0.window.windowID < $1.window.windowID }
                if windows.count < group.count {
                    complete = false
                    if group.bundleID == "com.apple.Safari", let pid = windows.first?.window.pid {
                        _ = await system.pressNewWindowItem(pid: pid)
                    }
                }
                chosen += windows.prefix(group.count)
            }
            if complete { break }
            try? await Task.sleep(for: .seconds(2))
        }
        launchedPIDs = NSWorkspace.shared.runningApplications
            .filter { app in apps.contains { $0.bundleID == app.bundleIdentifier } && !preRunning.contains(app.processIdentifier) }
            .map(\.processIdentifier)
        if chosen.count < wanted.reduce(0, { $0 + $1.count }) {
            Output.note("only \(chosen.count) of \(wanted.reduce(0, { $0 + $1.count })) windows appeared; measuring those")
        }
        if SnapshotCapture.isGranted() { try? await capture.refreshShareable() }
        return chosen
    }

    func cleanup() {
        FileManager.default.createFile(atPath: work.appendingPathComponent("stop").path, contents: nil)
        run("/usr/bin/pkill", ["-x", "less"])
        fixture?.quit()
        for pid in launchedPIDs { NSRunningApplication(processIdentifier: pid)?.terminate() }
    }

    // MARK: Layouts

    /// Home: a column grid of every measured window in the visibleFrame.
    func homeFrames(_ windows: [WindowInfo]) -> [TransomModel.WindowRef: Rect] {
        let area = display.visibleFrame
        let columns = Int(Double(windows.count).squareRoot().rounded(.up))
        let rows = (windows.count + columns - 1) / columns
        let width = area.width / Double(columns), height = area.height / Double(rows)
        var frames: [TransomModel.WindowRef: Rect] = [:]
        for (index, info) in windows.enumerated() {
            frames[info.window] = Rect(
                x: area.x + Double(index % columns) * width, y: area.y + Double(index / columns) * height, width: width, height: height)
        }
        return frames
    }

    /// The view's three windows: one per real app family where available (Electron first), then fixtures.
    func viewWindows(_ windows: [WindowInfo]) -> [WindowInfo] {
        var picked: [WindowInfo] = []
        for bundleID in ["com.microsoft.VSCode", "com.apple.Terminal", "com.apple.Safari", "com.apple.TextEdit"] {
            if let info = windows.first(where: { $0.window.bundleID == bundleID }), picked.count < 3 { picked.append(info) }
        }
        for info in windows where picked.count < 3 && !picked.contains(where: { $0.window == info.window }) { picked.append(info) }
        return picked
    }

    /// The view: its windows share the whole visibleFrame in columns; every other window is parked.
    func viewCommands(_ windows: [WindowInfo], view: [WindowInfo]) -> [WindowCommand] {
        let area = display.visibleFrame
        let width = area.width / Double(view.count)
        let parks = windows.filter { info in !view.contains { $0.window == info.window } }.map { WindowCommand.park($0.window, displayUUID: display.uuid) }
        let frames = view.enumerated().map { index, info in
            WindowCommand.setFrame(info.window, Rect(x: area.x + Double(index) * width, y: area.y, width: width, height: area.height))
        }
        return parks + frames
    }

    func homeCommands(_ windows: [WindowInfo], view: [WindowInfo]) -> [WindowCommand] {
        let home = homeFrames(windows)
        let parked = windows.filter { info in !view.contains { $0.window == info.window } }
        let shown = windows.filter { info in view.contains { $0.window == info.window } }
        return (parked + shown).compactMap { info in home[info.window].map { WindowCommand.setFrame(info.window, $0) } }
    }

    // MARK: One batch

    struct BatchResult {
        var ms: Double
        var perBundle: [String: Double]
        var missing: Int
        var captured: Int
        var budgetMissed: Int
        var images: [UInt32: CGImage]
    }

    /// Captures the windows visible at the start within the move budget, sends one perform and times every frameApplied.
    func batch(_ commands: [WindowCommand], visible: [WindowInfo], timeout: Duration = .seconds(3)) async -> BatchResult {
        var images: [UInt32: CGImage] = [:]
        if SnapshotCapture.isGranted() {
            let scale = NSScreen.main?.backingScaleFactor ?? 1
            let requests = visible.map { info in
                (info.visibleMemberID ?? info.window.windowID, CGSize(width: info.frame.width * scale, height: info.frame.height * scale))
            }
            images = await capture.captureAll(requests, deadline: SnapshotCapture.moveBudget)
        }
        let targets = Set(commands.map(\.window))
        applied = [:]
        let start = ContinuousClock.now
        await system.perform(commands)
        let deadline = start + timeout
        while ContinuousClock.now < deadline, !targets.isSubset(of: applied.keys) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        var perBundle: [String: Double] = [:]
        var last = Duration.zero
        for ref in targets {
            guard let arrival = applied[ref] else { continue }
            let elapsed = arrival.at - start
            last = max(last, elapsed)
            perBundle[ref.bundleID] = max(perBundle[ref.bundleID] ?? 0, ms(elapsed))
        }
        let missing = targets.subtracting(applied.keys).count
        return BatchResult(
            ms: missing > 0 ? ms(timeout) : ms(last), perBundle: perBundle, missing: missing, captured: images.count,
            budgetMissed: SnapshotCapture.isGranted() ? visible.count - images.count : 0, images: images)
    }

    /// Refreshes the tracked frames after a batch (the read-backs already updated them; this catches app-side changes).
    func current(_ windows: [WindowInfo]) async -> [WindowInfo] {
        var result: [WindowInfo] = []
        for info in windows { result.append(await system.windowInfo(info.window) ?? info) }
        return result
    }

    // MARK: settle (G1)

    func settle(runs: Int, windows initial: [WindowInfo]) async {
        var windows = initial
        let view = viewWindows(windows)
        Output.note("measuring \(windows.count) windows; view: \(view.map(\.window.bundleID))")
        _ = await batch(homeCommands(windows, view: view), visible: [])
        try? await Task.sleep(for: .seconds(1))
        for run in 0..<runs {
            for direction in ["in", "out"] {
                windows = await current(windows)
                let zoomIn = direction == "in"
                let commands = zoomIn ? viewCommands(windows, view: view) : homeCommands(windows, view: view)
                let visible = zoomIn ? windows : windows.filter { info in view.contains { $0.window == info.window } }
                let result = await batch(commands, visible: visible)
                Output.emit([
                    "gate": "G1", "dir": direction, "run": run, "ms": result.ms, "windows": windows.count, "perBundle": result.perBundle,
                    "missing": result.missing, "captured": result.captured, "budgetMissed": result.budgetMissed,
                ])
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}

// MARK: - Main

final class SpikeDelegate: NSObject, NSApplicationDelegate {
    let spike = Spike()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bounded run: the guest has no `timeout`, so the harness ends itself.
        let limit = intOption("--limit", 900)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(limit)) { [spike] in
            Output.note("time limit \(limit) s reached")
            spike.cleanup()
            exit(124)
        }
        Task {
            switch subcommand {
            case "settle":
                let apps = (options["--apps"] ?? "").split(separator: ",").map { name -> AppSpec in
                    guard let spec = appSpecs[String(name)] else { fail("unknown app \(name)", 64) }
                    return spec
                }
                let windows = await spike.prepare(fixtures: intOption("--fixtures", 8), apps: apps)
                await spike.settle(runs: intOption("--runs", 20), windows: windows)
            default:
                fail("unknown subcommand \(subcommand)\n\(usage)", 64)
            }
            spike.cleanup()
            exit(0)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = SpikeDelegate()
application.delegate = delegate
application.run()
