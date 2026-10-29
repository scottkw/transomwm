import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import TransomMac
import TransomPrivate
import os

// Phase 5 gesture spike (05-01, CONTEXT D-09, E-01). It runs on the host only when the user runs it; agents run only
// `synth` and `mt-devices`, in the VM through scripts/vm-spike.sh (D-08). It opens no window, makes no layout change
// and moves no window (the VM-only `synth` launches one TransomFixtureApp window as its target). Every subcommand stops
// by itself after --seconds (default 30, max 120) or Control-C, and the taps go with the process.
// stdout is for the person watching, JSON lines go to --out. It prints readings next to their gate thresholds and never
// PASS or FAIL: verdicts are made in 05-SPIKE.md (UI-SPEC Surface 6). The consume decision is the product's own
// `GestureTapRules.decide`, so the spike measures exactly what ships.

let usage = """
    usage: transom-gesture-spike <subcommand> [--seconds N] [--label text] [--out path]
      tap-listen                  listen-only tap (scroll, gesture, Dock control), one line per gesture   T1 T4 T6
      tap-consume [--require-alt] active tap with the product's GestureTapRules                          T2 T3 T5
      mt-devices                  multitouch devices and the dlsym table                                 M1
      mt-stream                   raw multitouch frames, one line per second                             M1 M2
      compare                     multitouch and tap together, first-frame lead per gesture              M4
      rescan                      device add/remove and wake, first frame after re-add                   M3
      synth --scenario <name|all> synthetic events through the consumer tap, downstream count (VM only)
    """

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("transom-gesture-spike: \(message)\n".utf8))
    exit(code)
}

var arguments = CommandLine.arguments.dropFirst()
guard let subcommand = arguments.popFirst() else { fail(usage, 64) }
guard ["tap-listen", "tap-consume", "mt-devices", "mt-stream", "compare", "rescan", "synth"].contains(subcommand) else {
    fail("unknown subcommand \(subcommand)\n\(usage)", 64)
}
var options: [String: String] = [:]
var flags: Set<String> = []
while let argument = arguments.popFirst() {
    switch argument {
    case "--seconds", "--label", "--out", "--scenario":
        guard let value = arguments.popFirst() else { fail("\(argument) needs a value\n\(usage)", 64) }
        options[argument] = value
    case "--require-alt":
        flags.insert(argument)
    default:
        fail("unknown argument \(argument)\n\(usage)", 64)
    }
}
let seconds: Int = {
    guard let text = options["--seconds"] else { return 30 }
    guard let value = Int(text), value > 0 else { fail("--seconds must be a positive integer", 64) }
    return min(value, 120)
}()
let scenarioName = options["--scenario"] ?? "all"
let label = options["--label"] ?? (subcommand == "synth" ? "synth \(scenarioName)" : "")
let requireAlt = flags.contains("--require-alt")

// MARK: - Clock and formatting

/// Seconds on the uptime clock: the one timebase of every tap and multitouch callback here.
nonisolated func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }

let launchDate = Date()
let launchUptime = uptime()

func formatted(_ date: Date, _ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: date)
}

/// Local `HH:mm:ss.SSS` of an uptime-clock time.
func clockTime(_ t: Double) -> String { formatted(launchDate.addingTimeInterval(t - launchUptime), "HH:mm:ss.SSS") }

let outPath = options["--out"] ?? ".build/spike/gesture-\(subcommand)-\(formatted(launchDate, "yyyyMMdd-HHmmss"))/out.jsonl"

func micros(_ value: Double) -> String { value < 1000 ? "\(Int(value.rounded())) µs" : String(format: "%.2f ms", value / 1000) }

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
}

func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

/// ⌥ ⌃ ⌘ ⇧ in that order, or – for none (UI-SPEC Surface 6).
func modifiers(_ flags: CGEventFlags) -> String {
    let glyphs = [(CGEventFlags.maskAlternate, "⌥"), (.maskControl, "⌃"), (.maskCommand, "⌘"), (.maskShift, "⇧")]
    let text = glyphs.filter { flags.contains($0.0) }.map(\.1).joined()
    return text.isEmpty ? "–" : text
}

// MARK: - Output

/// JSON lines to --out (always written), human lines to stdout.
enum Output {
    static var handle: FileHandle?

    static func open() {
        let url = URL(fileURLWithPath: outPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        if handle == nil { fail("can't write \(outPath)", 73) }
    }

    /// Sorted keys, no whitespace, so gates can grep `"downstream":0,`. Non-finite doubles become 0 (JSONSerialization
    /// would throw on them).
    static func record(_ fields: [String: Any]) {
        var fields = fields.mapValues { value -> Any in
            if let double = value as? Double, !double.isFinite { return 0.0 }
            return value
        }
        fields["label"] = label
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        handle?.write(data + Data("\n".utf8))
    }

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }
}

// MARK: - Permissions and header

let accessibility = AXIsProcessTrusted()
let inputMonitoring = CGPreflightListenEventAccess()
let postEvents = CGPreflightPostEventAccess()

/// Exit 2 with the fixed Surface 6 wording, before anything is recorded.
func requirePermissions() {
    let (name, granted): (String, Bool) =
        switch subcommand {
        case "tap-consume", "compare", "synth": ("Accessibility", accessibility)
        // An Accessibility grant also allows listen-only taps.
        case "tap-listen", "mt-stream", "rescan": ("Input Monitoring", inputMonitoring || accessibility)
        default: ("", true)
        }
    guard !granted else { return }
    FileHandle.standardError.write(Data("""
        \(subcommand) needs \(name) for your terminal app.
        Turn it on in System Settings ▸ Privacy & Security ▸ \(name), run this again, and turn it off when you're done.

        """.utf8))
    exit(2)
}

func osVersion() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    var size = 0
    sysctlbyname("kern.osversion", nil, &size, nil, 0)
    var build = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname("kern.osversion", &build, &size, nil, 0)
    let version = v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    return "\(version) (\(String(decoding: build.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)))"
}

func printHeader() {
    func state(_ granted: Bool) -> String { granted ? "granted" : "not granted" }
    Output.say("transom-gesture-spike \(subcommand) · macOS \(osVersion()) · \(formatted(launchDate, "yyyy-MM-dd HH:mm:ss"))")
    Output.say("Label: \(label.isEmpty ? "–" : label)")
    Output.say("Accessibility: \(state(accessibility)) · Input Monitoring: \(state(inputMonitoring)) · Post events: \(state(postEvents))")
    Output.say("Recording \(seconds) s to \(outPath)")
    Output.say("Press Control-C to stop early.")
}

// MARK: - Taps

/// One event as the tap saw it, handed to main. `sequence` is the latch slot the event belongs to.
nonisolated struct TapRecord: @unchecked Sendable {
    var input: GestureTapRules.Input
    var field55: Int64
    var window91: Int64
    var window92: Int64
    var consumed = false
    var micros: Double = 0
    var cgRead = false
    var sequence: GestureTapRules.Sequence?
    var ended = false
    /// tap-listen only: a copy for the `NSEvent(cgEvent:)` oracle, decoded on main.
    var event: CGEvent?
}

/// What a tap callback reaches through its refcon. `latch` is touched on the tap thread only.
nonisolated final class TapBox: @unchecked Sendable {
    enum Mode { case listen, consume, downstream }
    let mode: Mode
    let state: GestureTapState
    let requireAlt: Bool
    var latch = GestureTapRules.Latch.none
    var port: CFMachPort?
    var runLoop: CFRunLoop?
    let pending = OSAllocatedUnfairLock(initialState: [TapRecord]())
    let disabled = OSAllocatedUnfairLock(initialState: 0)
    let downstream = OSAllocatedUnfairLock(initialState: 0)

    init(mode: Mode, state: GestureTapState = GestureTapState(), requireAlt: Bool = false) {
        self.mode = mode
        self.state = state
        self.requireAlt = requireAlt
    }

    func take() -> [TapRecord] { pending.withLock { records in defer { records = [] }; return records } }
}

nonisolated enum Tap {
    /// tap-listen sees Dock control (30) too, to observe T4. The product mask never has bit 30.
    static let listenMask = GestureTapRules.mask | (1 << GestureEventFields.dockControlType)

    /// listen: segmentation only (decide on a permissive state, nothing taken). consume: the product rules. downstream:
    /// counts what survives.
    static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let box = Unmanaged<TapBox>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
            box.latch = .none
            box.disabled.withLock { $0 += 1 }
            return Unmanaged.passUnretained(event)
        }
        if box.mode == .downstream {
            box.downstream.withLock { $0 += 1 }
            return Unmanaged.passUnretained(event)
        }
        let input = GestureTapRules.Input(event: event, type: type)
        let pinch = type.rawValue == GestureEventFields.gestureType
        let slotBefore = pinch ? box.latch.pinch : type == .scrollWheel ? box.latch.pan : nil
        // The slot as decide will see it after expiry, so "this event ended it" is told apart from "it timed out".
        let before = slotBefore.flatMap { sequence -> GestureTapRules.Sequence? in
            let limit = sequence.fingersUp ? GestureTapRules.quietTimeout : GestureTapRules.fingersDownTimeout
            return input.timestamp - sequence.lastEvent > limit ? nil : sequence
        }
        let consume = box.mode == .consume
        let requireAlt = box.requireAlt
        var cgRead = false
        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let decision = GestureTapRules.decide(input, state: box.state, latch: &box.latch) { point in
            cgRead = true
            guard consume else { return .wallpaper }
            return requireAlt ? .window : GestureTapRules.liveSurface(at: point)
        }
        let elapsed = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1000
        let after = pinch ? box.latch.pinch : type == .scrollWheel ? box.latch.pan : nil
        var record = TapRecord(
            input: input, field55: event.getIntegerValueField(GestureEventFields.realType),
            window91: event.getIntegerValueField(.mouseEventWindowUnderMousePointer),
            window92: event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent), micros: elapsed, cgRead: cgRead)
        if let after, after.lastEvent == input.timestamp {
            record.sequence = after
        } else if after == nil, let before {
            record.sequence = before
            record.ended = true
        }
        if case .consume = decision, consume { record.consumed = true }
        if box.mode == .listen { record.event = event.copy() }
        let done = record
        box.pending.withLock { $0.append(done) }
        return done.consumed ? nil : Unmanaged.passUnretained(event)
    }

    /// A session tap on its own thread with its own CFRunLoop (InputTap shape). False when macOS refuses it.
    static func start(_ box: TapBox, mask: CGEventMask, place: CGEventTapPlacement, options: CGEventTapOptions) -> Bool {
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: place, options: options, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(box).toOpaque())
        else { return false }
        box.port = port
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [box] in
            let runLoop = CFRunLoopGetCurrent()
            box.runLoop = runLoop
            if let port = box.port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) {
                CFRunLoopAddSource(runLoop, source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "GestureSpikeTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    static func stop(_ box: TapBox) {
        guard let port = box.port, CFMachPortIsValid(port) else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop = box.runLoop { CFRunLoopStop(runLoop) }
    }
}

/// Every display, as desk displays for the spike's state.
func displayFrames() -> [CGRect] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
}

func finderPID() -> Int32 {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier ?? 0
}

func reasonText(_ reason: GestureSample.Reason?) -> String {
    switch reason {
    case .optionHeld: "⌥ held"
    case .wallpaper: "wallpaper"
    case nil: "–"
    }
}

func passText(_ reason: GestureTapRules.PassReason?) -> String {
    switch reason {
    case .disarmed(.zoomPaused): "zoom paused"
    case .disarmed(.notReady): "not ready"
    case .disarmed(.rectZoomOrDrag): "rect zoom or drag in progress"
    case .disarmed(nil): "not armed"
    case .fullScreen: "full screen"
    case .notDeskDisplay: "not a desk display"
    case .chord: "⌃ or ⌘ also held"
    case .notTrackpad: "not a trackpad"
    case .midSequence: "mid-gesture (start not seen)"
    case .windowUnderPointer: requireAlt ? "no ⌥ (--require-alt)" : "window under pointer"
    case .overlayUnderPointer: "menu or popover under pointer"
    case .shortCircuit: "app under pointer"
    case nil: "–"
    }
}

// MARK: - Stopping

/// Stops every tap and device, prints the summary and exits. Runs once, at --seconds or Control-C.
enum Run {
    static var boxes: [TapBox] = []
    static var onFinish: [() -> Void] = []
    static var finished = false

    static func finish(_ code: Int32 = 0) {
        guard !finished else { return }
        finished = true
        boxes.forEach(Tap.stop)
        onFinish.forEach { $0() }
        try? Output.handle?.close()
        exit(code)
    }
}

// MARK: - synth (VM only)

/// One synthetic event and whether it should reach the downstream tap.
struct SynthEvent {
    enum Kind {
        case scroll(phase: Int64, momentum: Int64)
        case wheel
        case gesture(hid: Int64, phase: Int64, value: Double)
    }
    let kind: Kind
    let flags: CGEventFlags
    let survives: Bool
}

enum Step {
    case post(SynthEvent)
    case pause(Double)
}

struct Scenario {
    let name: String
    let onWallpaper: Bool
    let steps: [Step]
    var posted: Int { steps.filter { if case .post = $0 { true } else { false } }.count }
    var expect: Int { steps.filter { if case .post(let e) = $0 { e.survives } else { false } }.count }
}

func pinchSteps(_ flags: CGEventFlags, survives: Bool, changes: Int = 10) -> [Step] {
    let began = SynthEvent(kind: .gesture(hid: GestureEventFields.hidZoom, phase: 1, value: 0.02), flags: flags, survives: survives)
    let changed = SynthEvent(kind: .gesture(hid: GestureEventFields.hidZoom, phase: 2, value: 0.03), flags: flags, survives: survives)
    let ended = SynthEvent(kind: .gesture(hid: GestureEventFields.hidZoom, phase: 4, value: 0), flags: flags, survives: survives)
    return [.post(began)] + Array(repeating: .post(changed), count: changes) + [.post(ended)]
}

func panSteps(_ flags: CGEventFlags, survives: Bool, changes: Int = 8, momentum: Bool = false) -> [Step] {
    func scroll(_ phase: Int64, _ momentum: Int64, _ f: CGEventFlags = flags) -> Step {
        .post(SynthEvent(kind: .scroll(phase: phase, momentum: momentum), flags: f, survives: survives))
    }
    var steps = [scroll(1, 0)] + Array(repeating: scroll(2, 0), count: changes) + [scroll(4, 0)]
    // Momentum arrives after the fingers lift; ⌥ is usually released by then.
    if momentum { steps += [scroll(0, 1, [])] + Array(repeating: scroll(0, 2, []), count: 6) + [scroll(0, 3, [])] }
    return steps
}

let option = CGEventFlags.maskAlternate

let scenarios: [Scenario] = [
    Scenario(name: "alt-pinch-over-window", onWallpaper: false, steps: pinchSteps(option, survives: false)),
    Scenario(name: "plain-scroll-over-window", onWallpaper: false, steps: panSteps([], survives: true)),
]

func makeEvent(_ synth: SynthEvent, at point: CGPoint) -> CGEvent? {
    let event: CGEvent?
    switch synth.kind {
    case .scroll(let phase, let momentum):
        event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: -6, wheel2: 0, wheel3: 0)
        event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    case .wheel:
        event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -1, wheel2: 0, wheel3: 0)
    case .gesture(let hid, let phase, let value):
        event = CGEvent(source: nil)
        if let type = CGEventType(rawValue: GestureEventFields.gestureType) { event?.type = type }
        event?.setIntegerValueField(GestureEventFields.hidType, value: hid)
        event?.setIntegerValueField(GestureEventFields.phase, value: phase)
        event?.setDoubleValueField(GestureEventFields.zoomValue, value: value)
    }
    event?.flags = synth.flags
    event?.location = point
    return event
}

/// The TransomFixtureApp next to this binary with one `standard` window; closing its stdin quits it.
final class FixtureWindow {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    init() throws {
        process.executableURL = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("TransomFixtureApp")
        process.arguments = ["--window", "standard"]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
    }

    /// The window's frame (global top-left points) from its `window index=0 … frame=x,y,w,h` line.
    func frame(timeout: Double = 15) async -> CGRect? {
        let handle = output.fileHandleForReading
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var text = ""
        let deadline = uptime() + timeout
        var bytes = [UInt8](repeating: 0, count: 4096)
        while uptime() < deadline {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 { text += String(decoding: bytes.prefix(count), as: UTF8.self) }
            if let line = text.split(separator: "\n").first(where: { $0.hasPrefix("window index=0 ") }),
                let field = line.split(separator: " ").first(where: { $0.hasPrefix("frame=") })
            {
                let n = field.dropFirst("frame=".count).split(separator: ",").compactMap { Double($0) }
                if n.count == 4 { return CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
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

/// A bare-wallpaper point on the main display as far from `avoid` as possible, or nil.
func wallpaperPoint(avoiding avoid: CGRect) -> CGPoint? {
    let display = CGDisplayBounds(CGMainDisplayID())
    var best: (CGPoint, Double)?
    for i in 1..<12 {
        for j in 1..<10 {
            let p = CGPoint(x: display.minX + display.width * Double(i) / 12, y: display.minY + display.height * Double(j) / 10)
            guard !avoid.insetBy(dx: -40, dy: -40).contains(p), GestureTapRules.liveSurface(at: p) == .wallpaper else { continue }
            let distance = hypot(p.x - avoid.midX, p.y - avoid.midY)
            if distance > (best?.1 ?? -1) { best = (p, distance) }
        }
    }
    return best?.0
}

func runSynth() async {
    let chosen = scenarioName == "all" ? scenarios : scenarios.filter { $0.name == scenarioName }
    guard !chosen.isEmpty else { fail("unknown scenario \(scenarioName); one of: all, \(scenarios.map(\.name).joined(separator: ", "))", 64) }
    let fixture: FixtureWindow
    do { fixture = try FixtureWindow() } catch { fail("can't launch TransomFixtureApp: \(error)", 70) }
    Run.onFinish.append { fixture.quit() }
    guard let frame = await fixture.frame() else { fail("TransomFixtureApp reported no window", 70) }
    try? await Task.sleep(for: .milliseconds(500))
    let overWindow = CGPoint(x: frame.midX, y: frame.midY)
    let wallpaper = wallpaperPoint(avoiding: frame)
    let state = GestureTapState(armed: true, deskDisplays: displayFrames(), finderPID: finderPID())
    let consumer = TapBox(mode: .consume, state: state)
    let counter = TapBox(mode: .downstream)
    Run.boxes = [consumer, counter]
    // The counter is an active pass-through tap at the tail, so it surely runs after the consumer.
    guard Tap.start(consumer, mask: GestureTapRules.mask, place: .headInsertEventTap, options: .defaultTap),
        Tap.start(counter, mask: GestureTapRules.mask, place: .tailAppendEventTap, options: .defaultTap)
    else {
        fixture.quit()
        fail("macOS refused the event taps (Accessibility)", 2)
    }
    Output.record([
        "type": "setup", "overWindow": [overWindow.x, overWindow.y], "wallpaper": wallpaper.map { [$0.x, $0.y] } ?? NSNull(),
        "fixtureFrame": [frame.minX, frame.minY, frame.width, frame.height], "displays": state.deskDisplays.map { [$0.minX, $0.minY, $0.width, $0.height] },
        "finderPID": state.finderPID,
    ])
    var results: [(String, Int, Int, Int)] = []
    for scenario in chosen {
        guard let point = scenario.onWallpaper ? wallpaper : overWindow else {
            Output.say("\(scenario.name)  skipped: no bare wallpaper point found")
            Output.record(["gate": "synth", "scenario": scenario.name, "skipped": "no wallpaper point", "pass": false])
            continue
        }
        CGWarpMouseCursorPosition(point)
        try? await Task.sleep(for: .milliseconds(300))
        _ = consumer.take()
        let startCount = counter.downstream.withLock { $0 }
        for step in scenario.steps {
            switch step {
            case .post(let synth):
                makeEvent(synth, at: point)?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(8))
            case .pause(let seconds):
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
        try? await Task.sleep(for: .milliseconds(400))
        let downstream = counter.downstream.withLock { $0 } - startCount
        let seen = consumer.take()
        let reasons = Set(seen.compactMap { record in
            record.sequence.map { $0.consuming ? "taken: \(reasonText($0.reason))" : "passed: \(passText($0.passReason))" }
        })
        Output.say("\(scenario.name)  posted \(scenario.posted) · downstream \(downstream)  (expect \(scenario.expect))")
        Output.record([
            "gate": "synth", "scenario": scenario.name, "posted": scenario.posted, "downstream": downstream, "expect": scenario.expect,
            "pass": downstream == scenario.expect, "seen": seen.count, "consumedByTap": seen.filter(\.consumed).count,
            "pidField": seen.map { Int($0.input.targetPID) }, "decisions": reasons.sorted(), "point": [point.x, point.y],
        ])
        results.append((scenario.name, scenario.posted, downstream, scenario.expect))
    }
    Output.say("Summary · synth · \(results.count) scenarios · label \"\(label)\"")
    for (name, _, got, expect) in results {
        Output.say("  \(name.padding(toLength: 30, withPad: " ", startingAt: 0))  expect \(expect) · got \(got)")
    }
    Output.say("Wrote \(outPath)")
    Run.finish()
}

// MARK: - Main

requirePermissions()
printHeader()
Output.open()
signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { Run.finish(130) }
interrupt.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { Run.finish() }

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
DispatchQueue.main.async {
    Task {
        switch subcommand {
        case "synth": await runSynth()
        default: fail("\(subcommand) is not built yet", 64)
        }
    }
}
application.run()
