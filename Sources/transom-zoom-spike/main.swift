import AVFoundation
import AppKit
import Foundation
import ImageIO
import TransomEngine
import TransomMac
import TransomModel
import UniformTypeIdentifiers

// Phase 4 feasibility spike (04-01, CONTEXT D). Runs only in the Tart VM through scripts/vm-spike.sh, never on the host.
// It measures the product's own AX write path (AXWindowSystem.perform -> AXAppThread -> FrameWriter, frameApplied
// read-backs) and its own SnapshotCapture. Every measurement is one JSON line with a "gate" key. Window titles and
// window snapshots are never written or logged (ZOOM-05); only screen recordings and stills of the VM test desktop are.

let usage = """
    usage: transom-zoom-spike <subcommand> [options] [--out path] [--limit secs]
      settle  --runs N [--fixtures K] [--apps vscode,safari,terminal,textedit] [--stage] [--record N]   G1, G2, G6
      capture [--fixtures K] [--apps ...]                                                            G8
      layers  [--tiles 120] [--runs 20] [--crossfade]                                                G4
      soak    [--minutes 60] [--interval 10] [--fixtures K] [--apps ...]                             G3
      menus                                                                                          G5
      minsize                                                                                        G7
      frames  <mov> <outdir> [--fps 60]
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
var flags: Set<String> = []
var positionals: [String] = []
while let argument = arguments.popFirst() {
    switch argument {
    case "--runs", "--fixtures", "--apps", "--out", "--limit", "--record", "--tiles", "--minutes", "--interval", "--fps":
        guard let value = arguments.popFirst() else { fail("\(argument) needs a value\n\(usage)", 64) }
        options[argument] = value
    case "--stage", "--crossfade":
        flags.insert(argument)
    default:
        guard !argument.hasPrefix("--") else { fail("unknown argument \(argument)\n\(usage)", 64) }
        positionals.append(argument)
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
                ( while [ ! -f stop ]; do stty size </dev/tty | cut -d' ' -f2 > cols\(index).txt; sleep 0.2; done ) &
                less long.txt
                exit 0
                """
            try? body.write(to: script, atomically: true, encoding: .utf8)
            chmod(script.path, 0o755)
            run("/usr/bin/open", ["-a", "Terminal", script.path])
        }
    case "textedit":
        let note = work.appendingPathComponent("note-\(getpid()).txt")  // a new document each run, never one already open
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


// MARK: - Helpers

func appKit(_ rect: Rect) -> CGRect {
    let r = Coordinates.appKit(fromTopLeft: rect, primaryHeight: Double(NSScreen.screens[0].frame.height))
    return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
}

/// A full-screen still of the VM test desktop into the output directory; returns its file name.
func still(_ name: String) -> String {
    let file = "\(name).png"
    run("/usr/sbin/screencapture", ["-x", Output.directory.appendingPathComponent(file).path])
    return file
}

func pgrep(_ name: String) -> Int32? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", name]
    process.standardOutput = pipe
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return text.split(separator: "\n").first.flatMap { Int32($0) }
}

func output(_ path: String, _ args: [String]) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// Physical footprint from `top` MEM (RESEARCH Pitfall 6: never ps RSS), in MB.
func topMB(_ pid: Int32) -> Double? {
    let text = output("/usr/bin/top", ["-l", "1", "-pid", String(pid), "-stats", "mem"])
    guard var value = text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).last(where: { !$0.isEmpty }) else { return nil }
    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
    guard let unit = value.last, let number = Double(value.dropLast()) else { return nil }
    switch unit {
    case "B": return number / 1_048_576
    case "K": return number / 1024
    case "M": return number
    case "G": return number * 1024
    default: return nil
    }
}

func rssKB(_ pid: Int32) -> Int? {
    Int(output("/bin/ps", ["-o", "rss=", "-p", String(pid)]).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Draws `image` small and reports whether it carries no content: fully transparent or one flat colour.
func isBlank(_ image: CGImage) -> Bool {
    let side = 16
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    guard drawn else { return true }
    if stride(from: 3, to: pixels.count, by: 4).allSatisfy({ pixels[$0] == 0 }) { return true }
    let first = Array(pixels[0..<4])
    return stride(from: 0, to: pixels.count, by: 4).allSatisfy { index in
        zip(pixels[index..<index + 4], first).allSatisfy { abs(Int($0) - Int($1)) <= 4 }
    }
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// A synthetic 480x300 snapshot for the layer gate, a distinct hue per index.
func syntheticImage(_ index: Int, width: Int = 480, height: Int = 300) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let color = NSColor(hue: CGFloat(index % 24) / 24, saturation: 0.6, brightness: 0.9, alpha: 1)
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: height - 28, width: width, height: 28))
    for row in 0..<8 {
        context.setFillColor(NSColor(white: 0.2, alpha: 1).cgColor)
        context.fill(CGRect(x: 16, y: height - 60 - row * 28, width: 60 + (index * 37 + row * 53) % 380, height: 12))
    }
    return context.makeImage()
}

/// The marker's colour in a recorded frame: true when green (reveal started), false when red, nil when neither.
func markerIsGreen(_ image: CGImage, at point: CGPoint) -> Bool? {
    guard let crop = image.cropping(to: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)) else { return nil }
    var pixel = [UInt8](repeating: 0, count: 4)
    let ok = pixel.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    guard ok else { return nil }
    let red = Int(pixel[0]), green = Int(pixel[1])
    if green > 150 && red < 100 { return true }
    if red > 150 && green < 100 { return false }
    return nil
}

/// Where the reveal marker sits: inside the bottom-left corner of the main display's visible frame.
let markerSize: CGFloat = 24
func markerRect() -> NSRect {
    let visible = NSScreen.screens[0].visibleFrame
    return NSRect(x: visible.minX + 4, y: visible.minY + 4, width: markerSize, height: markerSize)
}

/// G2's visual half: decodes `mov` at `fps`, finds each red -> green marker change (reveal start) and writes the frame
/// before it plus every `every`th of the next `after` frames as PNGs (at most 960 px wide). Recordings show only VM test windows (T-04-05).
func extractRevealFrames(_ mov: URL, into directory: URL, prefix: String, fps: Int, after: Int = 24, every: Int = 4) async -> [String: Any] {
    let asset = AVURLAsset(url: mov)
    guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return ["mov": mov.lastPathComponent, "error": "unreadable"] }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = CGSize(width: 960, height: 960)
    let screen = NSScreen.screens[0].frame
    let marker = markerRect()
    var previous: (green: Bool?, image: CGImage?) = (nil, nil)
    var written: [String] = []
    var transitions: [Double] = []
    var remaining = 0
    var frame = 0
    let step = 1 / Double(fps)
    var t = 0.0
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    while t < duration {
        defer { t += step; frame += 1 }
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) else { continue }
        let sx = CGFloat(image.width) / screen.width, sy = CGFloat(image.height) / screen.height
        let point = CGPoint(x: marker.midX * sx, y: (screen.height - marker.midY) * sy)
        let green = markerIsGreen(image, at: point)
        if green == true, previous.green == false {
            transitions.append(t.rounded(toPlaces: 3))
            if let before = previous.image {
                let name = "\(prefix)-r\(transitions.count)-before.png"
                writePNG(before, to: directory.appendingPathComponent(name))
                written.append(name)
            }
            remaining = after
        }
        if remaining > 0 {
            let index = after - remaining + 1
            if index == 1 || index % every == 0 {
                let name = "\(prefix)-r\(transitions.count)-after\(index).png"
                writePNG(image, to: directory.appendingPathComponent(name))
                written.append(name)
            }
            remaining -= 1
        }
        if green != nil { previous = (green, image) } else { previous.image = image }
    }
    return ["mov": mov.lastPathComponent, "decodedFrames": frame, "revealStarts": transitions, "frames": written]
}

final class LinkCounter: NSObject {
    var times: [CFTimeInterval] = []
    @objc func tick(_ link: CADisplayLink) { times.append(CACurrentMediaTime()) }
}

// MARK: - Spike

@MainActor final class Spike {
    let system = AXWindowSystem()
    let capture = SnapshotCapture()
    var fixture: Fixture?
    var launchedPIDs: [Int32] = []
    /// frameApplied arrivals since the batch began.
    var applied: [TransomModel.WindowRef: (at: ContinuousClock.Instant, actual: Rect)] = [:]
    var displays: [DisplayInfo] = []
    var display: DisplayInfo!
    lazy var stage = StagePanel(screen: NSScreen.screens[0])
    /// A small capturable square: red while the camera moves, green from reveal start, so a recording can be aligned.
    lazy var marker: NSPanel = {
        let panel = NSPanel(contentRect: markerRect(), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.backgroundColor = .red
        return panel
    }()

    /// Starts the fixture and apps, the window system and its event reader; returns the measured windows.
    func prepare(specs: [String], apps: [AppSpec]) async -> [WindowInfo] {
        let preRunning = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        var wanted: [(pid: Int32?, bundleID: String?, count: Int)] = []
        if !specs.isEmpty {
            guard let fixture = try? Fixture(windows: specs) else { fail("could not start TransomFixtureApp", 69) }
            self.fixture = fixture
            guard let pid = await fixture.ready() else { fail("TransomFixtureApp did not report ready", 69) }
            wanted.append((pid, nil, specs.count))
        }
        guard AXIsProcessTrusted() else { fail("no Accessibility grant in this session", 3) }
        await system.start()
        Task { [weak self] in
            guard let events = self?.system.events else { return }
            for await event in events {
                if case .frameApplied(let ref, _, let actual) = event { self?.applied[ref] = (.now, actual) }
            }
        }
        // Apps already running keep their windows (quitting them can prompt); only windows opened from here on are measured.
        let existing = Set(await system.inventory().windows.map(\.window))
        for spec in apps {
            launch(spec)
            wanted.append((nil, spec.bundleID, spec.windows))
        }
        // Wait until every group shows its windows; Safari's second window comes from its own ⌘N item.
        let deadline = ContinuousClock.now + .seconds(90)
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
                            && (group.pid.map { info.window.pid == $0 } ?? (info.window.bundleID == group.bundleID && !existing.contains(info.window)))
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
        let total = wanted.reduce(0) { $0 + $1.count }
        if chosen.count < total { Output.note("only \(chosen.count) of \(total) windows appeared; measuring those") }
        if SnapshotCapture.isGranted() { try? await capture.refreshShareable() }
        Output.emit([
            "gate": "env", "windows": chosen.count, "wanted": total, "screenRecording": SnapshotCapture.isGranted(),
            "bundles": Dictionary(chosen.map { ($0.window.bundleID, 1) }, uniquingKeysWith: +),
            "display": [display.frame.width, display.frame.height], "scale": NSScreen.screens[0].backingScaleFactor,
            "maxFPS": NSScreen.screens[0].maximumFramesPerSecond,
        ])
        return chosen
    }

    func cleanup() {
        FileManager.default.createFile(atPath: work.appendingPathComponent("stop").path, contents: nil)
        run("/usr/bin/pkill", ["-x", "less"])
        // Let the column probes see `stop` and the scripts exit, or Terminal asks before quitting.
        Thread.sleep(forTimeInterval: 1)
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

    /// Where a command sends its window, as the shell computes it (`AXWindowSystem.perform`).
    func target(_ command: WindowCommand, _ info: WindowInfo) -> Rect? {
        switch command {
        case .setFrame(_, let rect): rect
        case .park: display.parkedFrame(size: info.frame.size, among: displays)
        default: nil
        }
    }

    // MARK: One batch

    struct Timing {
        var ms: Double
        var perBundle: [String: Double]
        var missing: Int
    }

    /// One-shot captures of the windows visible at the start, within the 120 ms move budget (UI-SPEC step 3).
    func captureVisible(_ visible: [WindowInfo]) async -> [UInt32: CGImage] {
        guard SnapshotCapture.isGranted() else { return [:] }
        let scale = NSScreen.screens[0].backingScaleFactor
        let requests = visible.map { info in
            (info.visibleMemberID ?? info.window.windowID, CGSize(width: info.frame.width * scale, height: info.frame.height * scale))
        }
        return await capture.captureAll(requests, deadline: SnapshotCapture.moveBudget)
    }

    /// One perform, timed from just before it to the last frameApplied of its windows. `reveal` runs once every write
    /// returned, plus 50 ms, or at the 1500 ms cap (UI-SPEC step 7); timing continues to `timeout`.
    func write(_ commands: [WindowCommand], timeout: Duration = .seconds(3), reveal: (() async -> Void)? = nil) async -> Timing {
        let targets = Set(commands.map(\.window))
        applied = [:]
        let start = ContinuousClock.now
        await system.perform(commands)
        if let reveal {
            while ContinuousClock.now < start + .milliseconds(1500), !targets.isSubset(of: applied.keys) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            try? await Task.sleep(for: .milliseconds(50))
            await reveal()
        }
        while ContinuousClock.now < start + timeout, !targets.isSubset(of: applied.keys) {
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
        return Timing(ms: missing > 0 ? ms(timeout) : ms(last), perBundle: perBundle, missing: missing)
    }

    /// G2's geometric half at reveal start: every written window's CG bounds within 2 pt of its read-back, and every
    /// parked window stranded. A window with no read-back yet counts as a mismatch.
    func revealCheck(_ commands: [WindowCommand], windows: [WindowInfo]) -> (mismatches: Int, notStranded: Int, detail: [String]) {
        let cg = Dictionary((CGWindowList.snapshot() ?? []).map { ($0.windowID, $0.bounds) }, uniquingKeysWith: { a, _ in a })
        var mismatches = 0, notStranded = 0
        var detail: [String] = []
        for command in commands {
            guard let info = windows.first(where: { $0.window == command.window }) else { continue }
            let bounds = cg[info.visibleMemberID ?? info.window.windowID]
            guard let actual = applied[command.window]?.actual, let bounds else {
                mismatches += 1
                detail.append("\(info.window.bundleID): \(bounds == nil ? "no CG bounds" : "no read-back yet")")
                continue
            }
            let off = max(abs(bounds.x - actual.x), abs(bounds.y - actual.y), abs(bounds.width - actual.width), abs(bounds.height - actual.height))
            if off > 2 {
                mismatches += 1
                detail.append("\(info.window.bundleID): CG \(bounds) vs read-back \(actual)")
            }
            if case .park = command, !Recovery.isStranded(bounds, displays: displays) {
                notStranded += 1
                detail.append("\(info.window.bundleID): park not stranded at \(bounds)")
            }
        }
        return (mismatches, notStranded, detail)
    }

    func current(_ windows: [WindowInfo]) async -> [WindowInfo] {
        var result: [WindowInfo] = []
        for info in windows { result.append(await system.windowInfo(info.window) ?? info) }
        return result
    }

    func terminalCols() -> [String: Any] {
        var cols: [String: Any] = [:]
        for index in 1...2 {
            let text = (try? String(contentsOf: work.appendingPathComponent("cols\(index).txt"), encoding: .utf8)) ?? ""
            cols[String(index)] = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? NSNull()
        }
        return cols
    }

    // MARK: settle (G1, G2, G6)

    func settle(runs: Int, staged: Bool, record: Int, windows initial: [WindowInfo]) async {
        var windows = initial
        let view = viewWindows(windows)
        let terminal = windows.contains { $0.window.bundleID == "com.apple.Terminal" }
        Output.note("measuring \(windows.count) windows; view: \(view.map(\.window.bundleID))")
        _ = await write(homeCommands(windows, view: view))
        try? await Task.sleep(for: .seconds(1))
        if staged { marker.orderFrontRegardless() }
        var recordings: [URL] = []
        for run in 0..<runs {
            for direction in ["in", "out"] {
                windows = await current(windows)
                let zoomIn = direction == "in"
                if terminal, run == 0, zoomIn {
                    try? await Task.sleep(for: .milliseconds(600))
                    Output.emit(["gate": "G6", "phase": "before", "cols": terminalCols(), "still": still("g6-before")])
                }
                let commands = zoomIn ? viewCommands(windows, view: view) : homeCommands(windows, view: view)
                let visible = zoomIn ? windows : windows.filter { info in view.contains { $0.window == info.window } }
                let images = await captureVisible(visible)
                var recorder: Process?
                if staged, recordings.count < record {
                    let mov = Output.directory.appendingPathComponent("g2-\(recordings.count + 1).mov")
                    recordings.append(mov)
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-v", "-V", "5", "-x", mov.path]
                    try? process.run()
                    recorder = process
                    try? await Task.sleep(for: .milliseconds(1500))
                }
                var g2: (mismatches: Int, notStranded: Int, detail: [String])?
                let timing: Timing
                if staged {
                    marker.backgroundColor = .red
                    let tiles = visible.compactMap { info -> StageTile? in
                        guard let command = commands.first(where: { $0.window == info.window }), let end = target(command, info) else { return nil }
                        let id = info.visibleMemberID ?? info.window.windowID
                        return StageTile(id: id, start: appKit(info.frame), end: appKit(end), image: images[id], fill: NSColor.gray.cgColor)
                    }
                    stage.show(tiles: tiles)
                    marker.orderFrontRegardless()
                    await withCheckedContinuation { continuation in stage.animate(crossfade: false) { continuation.resume() } }
                    timing = await write(commands) { [self] in
                        g2 = revealCheck(commands, windows: windows)
                        marker.backgroundColor = .green
                        stage.fadeOut()
                    }
                } else {
                    timing = await write(commands)
                }
                Output.emit([
                    "gate": "G1", "dir": direction, "run": run, "ms": timing.ms, "windows": windows.count, "perBundle": timing.perBundle,
                    "missing": timing.missing, "captured": images.count,
                    "budgetMissed": SnapshotCapture.isGranted() ? visible.count - images.count : 0,
                ])
                if let g2 {
                    Output.emit(["gate": "G2", "dir": direction, "run": run, "mismatches": g2.mismatches, "notStranded": g2.notStranded, "detail": g2.detail, "recorded": recorder != nil])
                }
                if let recorder {
                    while recorder.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                }
                if terminal, run == 0 {
                    try? await Task.sleep(for: .milliseconds(600))
                    Output.emit(["gate": "G6", "phase": zoomIn ? "zoomedIn" : "zoomedOut", "cols": terminalCols(), "still": still(zoomIn ? "g6-in" : "g6-out")])
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
        marker.orderOut(nil)
        for mov in recordings {
            var record = await extractRevealFrames(mov, into: Output.directory, prefix: mov.deletingPathExtension().lastPathComponent, fps: intOption("--fps", 60))
            record["gate"] = "G2frames"
            Output.emit(record)
        }
    }

    // MARK: capture (G8)

    func captureCosts(windows: [WindowInfo]) async {
        guard SnapshotCapture.isGranted() else {
            Output.emit(["gate": "G8", "kind": "noPermission"])
            return
        }
        var fetches: [Double] = []
        for _ in 0..<10 {
            let start = ContinuousClock.now
            try? await capture.refreshShareable()
            fetches.append(ms(ContinuousClock.now - start))
        }
        Output.emit(["gate": "G8", "kind": "shareable", "samplesMs": fetches])
        let scale = NSScreen.screens[0].backingScaleFactor
        for info in windows {
            for percent in [25, 50, 100] {
                let factor = scale * CGFloat(percent) / 100
                let start = ContinuousClock.now
                let image = await capture.capture(info.visibleMemberID ?? info.window.windowID, pixelSize: CGSize(width: info.frame.width * factor, height: info.frame.height * factor))
                Output.emit([
                    "gate": "G8", "kind": "capture", "bundle": info.window.bundleID, "percent": percent,
                    "ms": ms(ContinuousClock.now - start), "ok": image != nil,
                ])
            }
        }
        // A parked window: does ignoreGlobalClipSingleWindow capture it whole (A3)?
        guard let info = viewWindows(windows).first else { return }
        let home = info.frame
        _ = await write([.park(info.window, displayUUID: display.uuid)])
        try? await Task.sleep(for: .milliseconds(500))
        try? await capture.refreshShareable()
        let size = CGSize(width: home.width * scale, height: home.height * scale)
        let image = await capture.capture(info.visibleMemberID ?? info.window.windowID, pixelSize: size)
        let parked = applied[info.window]?.actual
        Output.emit([
            "gate": "G8", "kind": "parked", "bundle": info.window.bundleID, "captured": image != nil,
            "blank": image.map(isBlank) ?? NSNull(), "size": image.map { [$0.width, $0.height] } ?? NSNull(),
            "expected": [Int(size.width), Int(size.height)],
            "stranded": parked.map { Recovery.isStranded($0, displays: displays) } ?? NSNull(),
        ])
        _ = await write([.setFrame(info.window, home)])
    }

    // MARK: layers (G4)

    func layers(count: Int, runs: Int, crossfade: Bool) async {
        let screen = NSScreen.screens[0]
        let frame = screen.frame
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + columns - 1) / columns
        let width = frame.width / CGFloat(columns), height = frame.height / CGFloat(rows)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var tiles: [StageTile] = []
        for index in 0..<count {
            let start = CGRect(x: frame.minX + CGFloat(index % columns) * width, y: frame.minY + CGFloat(index / columns) * height, width: width, height: height)
                .insetBy(dx: 4, dy: 4)
            let end = CGRect(x: center.x + (start.minX - center.x) * 2, y: center.y + (start.minY - center.y) * 2, width: start.width * 2, height: start.height * 2)
            tiles.append(StageTile(id: UInt32(index), start: start, end: end, image: syntheticImage(index), fill: NSColor.gray.cgColor))
        }
        let refresh = Double(screen.maximumFramesPerSecond)
        for run in 0..<runs {
            let forward = run % 2 == 0
            stage.show(tiles: tiles.map { tile in forward ? tile : StageTile(id: tile.id, start: tile.end, end: tile.start, image: tile.image, fill: tile.fill) })
            try? await Task.sleep(for: .milliseconds(200))
            let counter = LinkCounter()
            guard let view = stage.contentView else { return }
            let link = view.displayLink(target: counter, selector: #selector(LinkCounter.tick(_:)))
            link.add(to: .main, forMode: .common)
            let start = CACurrentMediaTime()
            await withCheckedContinuation { continuation in stage.animate(crossfade: crossfade) { continuation.resume() } }
            let end = CACurrentMediaTime()
            link.invalidate()
            let times = [start] + counter.times.filter { $0 <= end } + [end]
            let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
            let maxGap = gaps.max() ?? 0
            Output.emit([
                "gate": "G4", "run": run, "frames": counter.times.filter { $0 <= end }.count, "expected": (StagePanel.moveDuration * refresh).rounded(),
                "maxGapMs": (maxGap * 1000).rounded(toPlaces: 1), "maxGapAt": gaps.firstIndex(of: maxGap) ?? -1, "animationMs": ((end - start) * 1000).rounded(toPlaces: 1),
                "crossfade": crossfade, "refreshHz": refresh, "tiles": count,
            ])
        }
        stage.orderOut(nil)
    }

    // MARK: soak (G3)

    func soak(minutes: Int, interval: Int, windows initial: [WindowInfo]) async {
        var windows = initial
        let view = viewWindows(windows)
        _ = await write(homeCommands(windows, view: view))
        let start = ContinuousClock.now
        var nextSample = start
        var minute = 0
        var moves = 0
        var zoomIn = true
        func sample() {
            let server = pgrep("WindowServer"), replayd = pgrep("replayd")
            Output.emit([
                "gate": "G3", "minute": minute, "moves": moves,
                "windowServerMB": server.flatMap(topMB) ?? NSNull(), "replaydMB": replayd.flatMap(topMB) ?? NSNull(),
                "rssKB": server.flatMap(rssKB) ?? NSNull(),
            ])
            minute += 1
        }
        while ContinuousClock.now - start < .seconds(minutes * 60) {
            if ContinuousClock.now >= nextSample {
                sample()
                nextSample += .seconds(60)
            }
            let tick = ContinuousClock.now
            windows = await current(windows)
            let visibleStart = zoomIn ? windows : windows.filter { info in view.contains { $0.window == info.window } }
            _ = await captureVisible(visibleStart)
            _ = await write(zoomIn ? viewCommands(windows, view: view) : homeCommands(windows, view: view))
            // The refresh after settle: the windows visible at the end, at their new size, with a longer deadline.
            windows = await current(windows)
            let visibleEnd = zoomIn ? windows.filter { info in view.contains { $0.window == info.window } } : windows
            if SnapshotCapture.isGranted() {
                let scale = NSScreen.screens[0].backingScaleFactor
                _ = await capture.captureAll(
                    visibleEnd.map { ($0.visibleMemberID ?? $0.window.windowID, CGSize(width: $0.frame.width * scale, height: $0.frame.height * scale)) },
                    deadline: .seconds(2))
            }
            moves += 1
            zoomIn.toggle()
            try? await Task.sleep(until: tick + .seconds(interval))
        }
        sample()
    }

    // MARK: menus (G5)

    func menus() async {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Spike"
        let menu = NSMenu()
        for title in ["Zoom Out to All Windows", "Arrange All Windows", "Restore All Windows", "Quit"] { menu.addItem(withTitle: title, action: nil, keyEquivalent: "") }
        item.menu = menu
        // A toast-style probe panel, as ToastPresenter configures it but capturable so the still shows it.
        let visible = NSScreen.screens[0].visibleFrame
        let toast = NSPanel(
            contentRect: NSRect(x: visible.midX - 150, y: visible.maxY - 16 - 44, width: 300, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.level = .floating
        toast.ignoresMouseEvents = true
        toast.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        toast.backgroundColor = .systemOrange
        let label = NSTextField(labelWithString: "Toast probe (G5)")
        label.frame = NSRect(x: 16, y: 12, width: 268, height: 20)
        toast.contentView?.addSubview(label)
        toast.orderFrontRegardless()
        let tiles = (0..<12).map { index -> StageTile in
            let rect = CGRect(x: visible.minX + CGFloat(index % 4) * visible.width / 4, y: visible.minY + CGFloat(index / 4) * visible.height / 3, width: visible.width / 4, height: visible.height / 3).insetBy(dx: 8, dy: 8)
            return StageTile(id: UInt32(index), start: rect, end: rect.insetBy(dx: -20, dy: -20), image: syntheticImage(index), fill: NSColor.gray.cgColor)
        }
        let pid = getpid()
        var order: [[String: Any]] = []
        var stillName = ""
        // Timers in .common modes fire while the menu's tracking loop runs.
        func schedule(_ delay: Double, _ block: @escaping @MainActor () -> Void) {
            let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { block() } }
            RunLoop.main.add(timer, forMode: .common)
        }
        schedule(1.0) { [self] in
            stage.show(tiles: tiles)
            toast.orderFrontRegardless()  // UI-SPEC: a visible toast is re-ordered front when the stage orders in
            stage.animate(crossfade: false) {}
            schedule(0.5) {
                order = (CGWindowList.onScreenFrontToBack() ?? []).filter { $0.pid == pid }.map { entry in
                    ["layer": entry.layer, "w": Int(entry.bounds.width), "h": Int(entry.bounds.height)]
                }
                stillName = "g5-menu-stage.png"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", Output.directory.appendingPathComponent(stillName).path]
                try? process.run()
                schedule(2.0) { menu.cancelTracking() }
            }
        }
        item.button?.performClick(nil)
        try? await Task.sleep(for: .milliseconds(500))
        Output.emit([
            "gate": "G5", "order": order, "menuOpened": order.contains { ($0["layer"] as? Int) == Int(NSWindow.Level.popUpMenu.rawValue) },
            "stageLevel": stage.level.rawValue, "toastLevel": toast.level.rawValue, "popUpMenuLevel": NSWindow.Level.popUpMenu.rawValue,
            "still": stillName, "capturable": ProcessInfo.processInfo.environment["TRANSOM_STAGE_CAPTURABLE"] == "1",
        ])
        stage.orderOut(nil)
        toast.orderOut(nil)
        NSStatusBar.system.removeStatusItem(item)
    }

    // MARK: minsize (G7)

    func minsize(windows: [WindowInfo]) async {
        // The minsize window is the fixture's last; three columns at half height make its tile smaller than 900x700.
        guard windows.count == 3, let big = windows.max(by: { $0.window.windowID < $1.window.windowID }) else {
            Output.emit(["gate": "G7", "error": "expected 3 fixture windows, got \(windows.count)"])
            return
        }
        let area = display.visibleFrame
        let width = area.width / 3, height = area.height / 2
        let commands = windows.enumerated().map { index, info in
            WindowCommand.setFrame(info.window, Rect(x: area.x + Double(index) * width, y: area.y, width: width, height: height))
        }
        let timing = await write(commands)
        let requested = target(commands.first { $0.window == big.window }!, big)!
        let actual = applied[big.window]?.actual
        Output.emit([
            "gate": "G7", "requested": [requested.width, requested.height], "actual": actual.map { [$0.width, $0.height] } ?? NSNull(),
            "ms": timing.perBundle[big.window.bundleID] ?? NSNull(), "batchMs": timing.ms,
            "refused": actual.map { abs($0.width - requested.width) > 2 || abs($0.height - requested.height) > 2 } ?? NSNull(),
        ])
    }
}

// MARK: - Main

func appList() -> [AppSpec] {
    (options["--apps"] ?? "").split(separator: ",").map { name -> AppSpec in
        guard let spec = appSpecs[String(name)] else { fail("unknown app \(name)", 64) }
        return spec
    }
}

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
            let fixtures = Array(repeating: "standard", count: intOption("--fixtures", 8))
            switch subcommand {
            case "settle":
                let windows = await spike.prepare(specs: fixtures, apps: appList())
                await spike.settle(runs: intOption("--runs", 20), staged: flags.contains("--stage"), record: intOption("--record", 0), windows: windows)
            case "capture":
                await spike.captureCosts(windows: await spike.prepare(specs: fixtures, apps: appList()))
            case "layers":
                await spike.layers(count: intOption("--tiles", 120), runs: intOption("--runs", 20), crossfade: flags.contains("--crossfade"))
            case "soak":
                let windows = await spike.prepare(specs: fixtures, apps: appList())
                await spike.soak(minutes: intOption("--minutes", 60), interval: max(1, intOption("--interval", 10)), windows: windows)
            case "menus":
                await spike.menus()
            case "minsize":
                await spike.minsize(windows: await spike.prepare(specs: ["standard", "standard", "minsize:900x700"], apps: []))
            case "frames":
                guard positionals.count == 2 else { fail(usage, 64) }
                let directory = URL(fileURLWithPath: positionals[1])
                var record = await extractRevealFrames(URL(fileURLWithPath: positionals[0]), into: directory, prefix: "frame", fps: intOption("--fps", 60))
                record["gate"] = "G2frames"
                Output.emit(record)
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
