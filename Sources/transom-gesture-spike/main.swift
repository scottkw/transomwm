import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import TransomMac
import TransomModel
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
      tap-consume [--require-alt] [--no-sender-filter]
                                  active tap with the product's GestureTapRules                          T2 T3 T5
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
// A global, not a guard binding: functions and types below capture it.
let subcommand: String = {
    guard let first = arguments.popFirst() else { fail(usage, 64) }
    return first
}()
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
    case "--require-alt", "--no-sender-filter":
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
/// Fallback only: if tap-consume lines say "passed: not a trackpad", field 87 doesn't match the multitouch registry IDs.
let senderFilter = !flags.contains("--no-sender-filter")

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
    if !granted { permissionFailure(name) }
}

/// The fixed two-line Surface 6 message, exit 2. Also used when macOS refuses a tap despite the preflight; the empty
/// --out file is removed so nothing is recorded.
func permissionFailure(_ name: String) -> Never {
    try? Output.handle?.close()
    if Output.handle != nil { try? FileManager.default.removeItem(atPath: outPath) }
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
    let pads = deviceList.infos.filter(\.isTrackpad).map { "\($0.name) (family \($0.family), registry \(hex($0.registryID)))" }
    Output.say("Trackpads: " + (pads.isEmpty ? "none found" : pads.joined(separator: " · ")))
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
            guard consume else { return .wallpaper }
            if requireAlt { return .window }
            cgRead = true
            return GestureTapRules.liveSurface(at: point)
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
    static var onFinish: [@MainActor () -> Void] = []
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

func gestureStep(_ hid: Int64, _ phase: Int64, _ flags: CGEventFlags, survives: Bool) -> Step {
    .post(SynthEvent(kind: .gesture(hid: hid, phase: phase, value: 0.01), flags: flags, survives: survives))
}

let scenarios: [Scenario] = {
    let wheel = Step.post(SynthEvent(kind: .wheel, flags: option, survives: true))
    let stuck: [Step] =
        [.post(SynthEvent(kind: .scroll(phase: 1, momentum: 0), flags: option, survives: false))]
        + Array(repeating: .post(SynthEvent(kind: .scroll(phase: 2, momentum: 0), flags: option, survives: false)), count: 3)
        // No end, then more than the 2 s fingers-down limit. The next scroll arrives as `changed` with no start: only an
        // expired latch lets it through (a fresh began would re-decide anyway).
        + [.pause(2.1)]
        + Array(repeating: .post(SynthEvent(kind: .scroll(phase: 2, momentum: 0), flags: [], survives: true)), count: 5)
        + [.post(SynthEvent(kind: .scroll(phase: 4, momentum: 0), flags: [], survives: true))]
    let envelopes: [Step] =
        [gestureStep(GestureEventFields.hidGestureStarted, 0, option, survives: true)]
        + Array(pinchSteps(option, survives: false, changes: 3).dropLast())
        + [gestureStep(0, 2, option, survives: false), gestureStep(GestureEventFields.hidZoom, 4, option, survives: false)]
        + [gestureStep(GestureEventFields.hidGestureEnded, 0, option, survives: true)]
    // C1: the sub-type 4 events that leaked inside taken pinches on the host.
    let subTypeFour = Array(pinchSteps(option, survives: false, changes: 3).dropLast())
        + Array(repeating: gestureStep(4, 2, option, survives: false), count: 4)
        + [gestureStep(GestureEventFields.hidZoom, 4, option, survives: false)]
    let rotate = [gestureStep(GestureEventFields.hidRotate, 1, option, survives: true)]
        + Array(repeating: gestureStep(GestureEventFields.hidRotate, 2, option, survives: true), count: 5)
        + [gestureStep(GestureEventFields.hidRotate, 4, option, survives: true)]
    let midSequence =
        [Step.post(SynthEvent(kind: .scroll(phase: 1, momentum: 0), flags: [], survives: true))]
        + Array(repeating: .post(SynthEvent(kind: .scroll(phase: 2, momentum: 0), flags: option, survives: true)), count: 8)
        + [.post(SynthEvent(kind: .scroll(phase: 4, momentum: 0), flags: option, survives: true))]
    return [
        Scenario(name: "alt-pinch-over-window", onWallpaper: false, steps: pinchSteps(option, survives: false)),
        Scenario(name: "alt-pan-with-momentum", onWallpaper: false, steps: panSteps(option, survives: false, momentum: true)),
        Scenario(name: "plain-pinch-over-window", onWallpaper: false, steps: pinchSteps([], survives: true)),
        Scenario(name: "plain-scroll-over-window", onWallpaper: false, steps: panSteps([], survives: true)),
        Scenario(name: "plain-pinch-on-wallpaper", onWallpaper: true, steps: pinchSteps([], survives: false)),
        Scenario(name: "plain-scroll-on-wallpaper", onWallpaper: true, steps: panSteps([], survives: false, momentum: true)),
        Scenario(name: "alt-mid-sequence", onWallpaper: false, steps: midSequence),
        Scenario(name: "alt-discrete-wheel", onWallpaper: false, steps: Array(repeating: wheel, count: 5)),
        Scenario(name: "alt-control-pinch", onWallpaper: false, steps: pinchSteps([.maskAlternate, .maskControl], survives: true)),
        Scenario(name: "alt-command-scroll", onWallpaper: false, steps: panSteps([.maskAlternate, .maskCommand], survives: true)),
        Scenario(name: "stuck-latch-then-plain-scroll", onWallpaper: false, steps: stuck),
        Scenario(name: "alt-pinch-envelopes", onWallpaper: false, steps: envelopes),
        Scenario(name: "rotate-only", onWallpaper: false, steps: rotate),
        Scenario(name: "alt-pinch-subtype-4", onWallpaper: false, steps: subTypeFour),
    ]
}()

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

/// A bare-wallpaper point on the main display as far from `avoid` as possible, or nil. One window list read, then an
/// 8 pt grid: the VM desk can be nearly covered by windows other runs left open, which this tool never closes.
func wallpaperPoint(avoiding avoid: CGRect) -> CGPoint? {
    let display = CGDisplayBounds(CGMainDisplayID())
    guard let list = CGWindowList.onScreenFrontToBack() else { return nil }
    var best: (CGPoint, Double)?
    for x in stride(from: display.minX + 4, to: display.maxX, by: 8) {
        for y in stride(from: display.minY + 4, to: display.maxY, by: 8) {
            let p = CGPoint(x: x, y: y)
            guard !avoid.insetBy(dx: -40, dy: -40).contains(p),
                GestureTapRules.surface(at: p, in: list, excludingPID: getpid(), display: display) == .wallpaper
            else { continue }
            let distance = hypot(p.x - avoid.midX, p.y - avoid.midY)
            if distance > (best?.1 ?? -1) { best = (p, distance) }
        }
    }
    return best?.0
}

func runSynth() async {
    // IN-02: synth posts ⌥ scroll and gesture events into the session, so it refuses to run outside a VM.
    var vmm: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("kern.hv_vmm_present", &vmm, &size, nil, 0) == 0, vmm == 1 else { fail("synth runs only inside the VM", 64) }
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
        permissionFailure("Accessibility")
    }
    Output.record([
        "type": "setup", "overWindow": [overWindow.x, overWindow.y], "wallpaper": wallpaper.map { [$0.x, $0.y] } ?? NSNull(),
        "fixtureFrame": [frame.minX, frame.minY, frame.width, frame.height], "displays": state.deskDisplays.map { [$0.minX, $0.minY, $0.width, $0.height] },
        "finderPID": state.finderPID,
        // What owns the screen, for a run that found no bare wallpaper (pids, apps, layers and bounds; never titles).
        "onScreen": (CGWindowList.onScreenFrontToBack() ?? []).map { entry -> [String: Any] in
            [
                "pid": entry.pid, "app": NSRunningApplication(processIdentifier: entry.pid)?.localizedName ?? "?", "layer": entry.layer,
                "alpha": entry.alpha, "bounds": [entry.bounds.x, entry.bounds.y, entry.bounds.width, entry.bounds.height],
            ]
        },
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
            "pointerOwner": Int(ownerPID(at: point)), "frontmost": Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0),
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

// MARK: - Gestures (tap-listen, tap-consume, compare)

/// `1→2…→4`: runs collapsed, a repeated value marked with `…`.
func chain(_ values: [Int64]) -> String {
    var parts: [String] = []
    var last: Int64?
    var repeated = false
    for value in values {
        if value == last {
            repeated = true
            continue
        }
        if repeated { parts[parts.count - 1] += "…" }
        repeated = false
        parts.append(String(value))
        last = value
    }
    if repeated { parts[parts.count - 1] += "…" }
    return parts.isEmpty ? "–" : parts.joined(separator: "→")
}

/// The pid owning the point (the first visible entry front to back, looking through full-display overlays), 0 for bare
/// wallpaper: T6 compares it, and the frontmost app's pid, with field 40.
func ownerPID(at point: CGPoint) -> Int32 {
    guard let list = CGWindowList.onScreenFrontToBack() else { return -1 }
    var id: CGDirectDisplayID = 0
    var count: UInt32 = 0
    let display = CGGetDisplaysWithPoint(point, 1, &id, &count) == .success && count > 0 ? CGDisplayBounds(id) : .null
    let p = Point(x: point.x, y: point.y)
    for entry in list where entry.pid != getpid() && entry.alpha > 0 && entry.bounds.contains(p) {
        let b = entry.bounds
        if entry.layer != 0, b.minX <= display.minX, b.minY <= display.minY, b.maxX >= display.maxX, b.maxY >= display.maxY { continue }
        return entry.pid
    }
    return 0
}

func appName(_ pid: Int32) -> String { NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid" }

func surfaceName(_ surface: PointerSurface) -> String {
    switch surface {
    case .wallpaper: "wallpaper"
    case .window: "window"
    case .overlay: "menu or popover"
    }
}

/// The `NSEvent(cgEvent:)` oracle, on main inside an autorelease pool, never in the callback. Phase and magnification
/// are read only on event types that have them (AppKit throws otherwise).
func oracle(_ event: CGEvent) -> String {
    autoreleasepool {
        guard let ns = NSEvent(cgEvent: event) else { return "none" }
        var text = "type \(ns.type.rawValue)"
        if ns.type == .scrollWheel || ns.type == .magnify || ns.type == .rotate { text += " phase \(ns.phase.rawValue)" }
        if ns.type == .magnify { text += String(format: " magnification %.4f", ns.magnification) }
        return text
    }
}

/// Groups tap records into gestures: one stdout line and one JSON record per gesture, one sample record per event.
final class Gestures {
    enum Mode { case listen, consume, compare }

    final class Open {
        let kind: GestureSample.Kind
        let started: Double
        let pid: Int32
        let sender: UInt64
        let flags: CGEventFlags
        let who: String
        let oracle: String?
        let pointerOwner: Int32
        let frontmost: Int32
        var sequence: GestureTapRules.Sequence
        var last: Double
        var events = 0, consumed = 0, passed = 0, envelopesPassed = 0, cgReads = 0
        var micros: [Double] = []
        var phases: [Int64] = []
        var momentum: [Int64] = []
        var hids: Set<Int64> = []
        var scale = 1.0, dx = 0.0, dy = 0.0
        var pidSet = 0

        init(_ record: TapRecord, sequence: GestureTapRules.Sequence, who: String, oracle: String?) {
            kind = sequence.kind
            started = sequence.started
            pid = record.input.targetPID
            sender = record.input.senderID
            flags = record.input.flags
            self.who = who
            self.oracle = oracle
            pointerOwner = ownerPID(at: record.input.location)
            frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            self.sequence = sequence
            last = record.input.timestamp
        }
    }

    let mode: Mode
    var open: [GestureSample.Kind: Open] = [:]
    /// compare: the text after the gesture kind, from the gesture's start time.
    var compareText: ((GestureSample.Kind, Double) -> (String, Double?))?
    var gestures: [GestureSample.Kind: Int] = [:]
    var taken = 0, passedSequences = 0, timeouts = 0
    var eventsConsumed = 0, eventsPassed = 0
    var allMicros: [Double] = [], passedMicros: [Double] = []
    var scrollEvents = 0, gestureEvents = 0, dockEvents = 0, discrete = 0, pidSetScroll = 0, pidSetGesture = 0
    var senders: Set<UInt64> = []
    var completePinches = 0, pansWithStart = 0
    var leads: [GestureSample.Kind: [Double]] = [:]
    /// T6: sequences whose field 40 matched the app under the pointer, the frontmost app, or was 0.
    var pidMatchesPointer = 0, pidMatchesFrontmost = 0, pidZero = 0

    init(_ mode: Mode) { self.mode = mode }

    func feed(_ records: [TapRecord]) {
        for record in records { feed(record) }
    }

    private func feed(_ record: TapRecord) {
        let input = record.input
        let ns = record.event.map(oracle)
        switch input.type {
        case CGEventType.scrollWheel.rawValue:
            scrollEvents += 1
            if input.targetPID != 0 { pidSetScroll += 1 }
            if !input.isContinuous || (input.scrollPhase == 0 && input.momentumPhase == 0) { discrete += 1 }
        case GestureEventFields.gestureType:
            gestureEvents += 1
            if input.targetPID != 0 { pidSetGesture += 1 }
        default:
            dockEvents += 1
        }
        if input.senderID != 0 { senders.insert(input.senderID) }
        if mode == .consume {
            allMicros.append(record.micros)
            if record.consumed { eventsConsumed += 1 } else { eventsPassed += 1; passedMicros.append(record.micros) }
        }
        let pinch = input.type == GestureEventFields.gestureType
        var sample: [String: Any] = [
            "type": "sample", "t": input.timestamp, "kind": pinch ? "pinch" : input.type == CGEventType.scrollWheel.rawValue ? "pan" : "other",
            "cgType": Int(input.type), "field55": record.field55, "phase": pinch ? input.gesturePhase : input.scrollPhase,
            "momentum": input.momentumPhase, "continuous": input.isContinuous, "m": input.zoom, "dx": input.dx, "dy": input.dy,
            "hid": input.hidType, "pid": Int(input.targetPID), "sender": hex(input.senderID), "alt": input.flags.contains(.maskAlternate),
            "mods": modifiers(input.flags), "w91": record.window91, "w92": record.window92, "x": input.location.x, "y": input.location.y,
        ]
        if mode == .consume {
            sample["consumed"] = record.consumed
            sample["us"] = record.micros
            sample["cgRead"] = record.cgRead
        }
        if let ns { sample["ns"] = ns }
        if let sequence = record.sequence { sample["seq"] = sequence.started }
        Output.record(sample)

        guard let sequence = record.sequence else { return }
        if let current = open[sequence.kind], current.started != sequence.started { close(current, endedBy: "replaced") }
        let gesture: Open
        if let current = open[sequence.kind] {
            gesture = current
        } else {
            let pid = input.targetPID
            let who = pid != 0 ? "\(appName(pid)) (pid \(pid))" : "\(surfaceName(GestureTapRules.liveSurface(at: input.location))) (pid 0)"
            gesture = Open(record, sequence: sequence, who: who, oracle: ns)
            open[sequence.kind] = gesture
        }
        gesture.sequence = sequence
        gesture.last = input.timestamp
        gesture.events += 1
        if input.targetPID != 0 { gesture.pidSet += 1 }
        if record.consumed {
            gesture.consumed += 1
        } else {
            gesture.passed += 1
            if pinch && (input.hidType == GestureEventFields.hidGestureStarted || input.hidType == GestureEventFields.hidGestureEnded) {
                gesture.envelopesPassed += 1
            }
        }
        if record.cgRead { gesture.cgReads += 1 }
        gesture.micros.append(record.micros)
        if pinch {
            gesture.hids.insert(input.hidType)
            if input.hidType == GestureEventFields.hidZoom {
                gesture.phases.append(input.gesturePhase)
                if input.zoom.isFinite { gesture.scale += input.zoom }
            }
        } else {
            if input.scrollPhase != 0 { gesture.phases.append(input.scrollPhase) }
            if input.momentumPhase != 0 { gesture.momentum.append(input.momentumPhase) }
            gesture.dx += input.dx
            gesture.dy += input.dy
        }
        if record.ended { close(gesture, endedBy: "end") }
    }

    /// Closes gestures the rules have let go of by quiet (after lift) or timeout (fingers down).
    func expire(now: Double) {
        for gesture in open.values {
            let up = gesture.sequence.fingersUp
            if now - gesture.last > (up ? GestureTapRules.quietTimeout : GestureTapRules.fingersDownTimeout) + 0.05 {
                close(gesture, endedBy: up ? "quiet" : "timeout")
            }
        }
    }

    func closeAll() {
        for gesture in open.values { close(gesture, endedBy: "stop") }
    }

    private func close(_ gesture: Open, endedBy: String) {
        open[gesture.kind] = nil
        gestures[gesture.kind, default: 0] += 1
        if gesture.pid == 0 { pidZero += 1 }
        if gesture.pid != 0 && gesture.pid == gesture.pointerOwner { pidMatchesPointer += 1 }
        if gesture.pid != 0 && gesture.pid == gesture.frontmost { pidMatchesFrontmost += 1 }
        if endedBy == "timeout" { timeouts += 1 }
        let sequence = gesture.sequence
        if sequence.consuming { taken += 1 } else { passedSequences += 1 }
        let fullPinch = gesture.phases.first == 1 && gesture.phases.contains(2) && gesture.phases.last == 4
        if gesture.kind == .pinch && fullPinch { completePinches += 1 }
        if gesture.kind == .pan && (gesture.phases.contains(1) || gesture.phases.contains(128)) { pansWithStart += 1 }
        let kindText = gesture.kind == .pinch ? "pinch" : "pan  "
        let head = "\(clockTime(gesture.started))  \(kindText)  \(modifiers(gesture.flags))"
        let callback = "callback p50 \(micros(percentile(gesture.micros, 0.5))) · p99 \(micros(percentile(gesture.micros, 0.99)))"
        let pidField = gesture.pidSet == gesture.events ? "set" : gesture.pidSet == 0 ? "unset" : "set on \(gesture.pidSet) of \(gesture.events)"
        var lead: Double?
        let line: String
        switch mode {
        case .listen where gesture.kind == .pinch:
            line = "\(head)  \(gesture.who)  \(gesture.events) events  hid \(gesture.hids.sorted().map(String.init).joined(separator: ","))  phases \(chain(gesture.phases))  "
                + String(format: "scale %.2f", gesture.scale) + "  pid field: \(pidField)  sender \(hex(gesture.sender))"
        case .listen:
            let momentum = gesture.momentum.isEmpty ? "" : "  momentum \(chain(gesture.momentum))"
            line = "\(head)  \(gesture.who)  \(gesture.events) events  phases \(chain(gesture.phases))\(momentum)  Δ \(Int(gesture.dx.rounded())), \(Int(gesture.dy.rounded())) pt"
        case .consume where sequence.consuming:
            let envelope = gesture.passed > 0 && gesture.passed == gesture.envelopesPassed ? " (envelope)" : ""
            line = "\(head)  \(gesture.who)  taken: \(reasonText(sequence.reason))  consumed \(gesture.consumed) · passed \(gesture.passed)\(envelope)  \(callback)"
        case .consume:
            line = "\(head)  \(gesture.who)  passed: \(passText(sequence.passReason))  \(callback)"
        case .compare:
            let (text, value) = compareText?(gesture.kind, gesture.started) ?? ("no multitouch data", nil)
            lead = value
            if let value { leads[gesture.kind, default: []].append(value) }
            line = "\(clockTime(gesture.started))  \(kindText.trimmingCharacters(in: .whitespaces))  \(text)"
        }
        Output.say(line)
        var fields: [String: Any] = [
            "type": "sequence", "kind": gesture.kind == .pinch ? "pinch" : "pan", "t0": clockTime(gesture.started), "start": gesture.started,
            "ms": ((gesture.last - gesture.started) * 1000).rounded(), "events": gesture.events, "consumed": gesture.consumed,
            "passed": gesture.passed, "envelopesPassed": gesture.envelopesPassed, "pid": Int(gesture.pid), "who": gesture.who,
            "pidField": pidField, "sender": hex(gesture.sender), "mods": modifiers(gesture.flags), "optionAtStart": sequence.optionHeld,
            "phases": chain(gesture.phases), "momentum": chain(gesture.momentum), "hids": gesture.hids.sorted().map { Int($0) },
            "scale": gesture.scale, "dx": gesture.dx, "dy": gesture.dy, "cgReads": gesture.cgReads, "endedBy": endedBy, "line": line,
            "pointerOwner": Int(gesture.pointerOwner), "frontmost": Int(gesture.frontmost),
        ]
        if mode == .consume {
            fields["decision"] = sequence.consuming ? "taken" : "passed"
            fields["reason"] = sequence.consuming ? reasonText(sequence.reason) : passText(sequence.passReason)
            fields["p50us"] = percentile(gesture.micros, 0.5)
            fields["p99us"] = percentile(gesture.micros, 0.99)
            fields["maxus"] = gesture.micros.max() ?? 0
        }
        if let oracle = gesture.oracle { fields["oracleFirst"] = oracle }
        if let lead { fields["leadMs"] = lead }
        Output.record(fields)
    }

    func gestureCounts() -> String {
        let total = gestures.values.reduce(0, +)
        return "\(total) (pinch \(gestures[.pinch] ?? 0), pan \(gestures[.pan] ?? 0))"
    }
}

func summaryHead() -> String {
    "Summary · \(subcommand) · \(Int((uptime() - launchUptime).rounded())) s · label \"\(label)\""
}

func row(_ name: String, _ value: String) -> String { "  " + name.padding(toLength: 16, withPad: " ", startingAt: 0) + value }

func countText(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? String(n)
}

/// Prints the summary block and writes it as one JSON record.
func printSummary(_ rows: [String], gates: [String], record: [String: Any]) {
    Output.say(summaryHead())
    rows.forEach(Output.say)
    if !gates.isEmpty {
        Output.say("Gate readings (judged in 05-SPIKE.md, not here):")
        gates.forEach { Output.say("  " + $0) }
    }
    var fields = record
    fields["type"] = "summary"
    fields["rows"] = rows
    fields["gates"] = gates
    Output.record(fields)
    Output.say("Wrote \(outPath)")
}

func pad(_ text: String, _ width: Int = 28) -> String { text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0) }

func tapState() -> GestureTapState {
    let senders = Set(deviceList.infos.filter(\.isTrackpad).map(\.registryID).filter { $0 != 0 })
    return GestureTapState(
        armed: true, deskDisplays: displayFrames(), finderPID: finderPID(), trackpadSenders: senders, filtersBySender: senderFilter)
}

/// A permissive state for listen-only segmentation: every display a desk, no sender filter.
let listenState = GestureTapState(
    armed: true, deskDisplays: [CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)], filtersBySender: false)

/// Runs `work` on main every `seconds` until the process exits.
func every(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        while true {
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}

func startDrain(_ box: TapBox, into gestures: Gestures, before: (@MainActor () -> Void)? = nil) {
    every(0.1) {
        before?()
        gestures.feed(box.take())
        gestures.expire(now: uptime())
    }
}

func runTapListen() {
    let box = TapBox(mode: .listen, state: listenState)
    guard Tap.start(box, mask: Tap.listenMask, place: .tailAppendEventTap, options: .listenOnly) else {
        permissionFailure("Input Monitoring")
    }
    Run.boxes = [box]
    let gestures = Gestures(.listen)
    startDrain(box, into: gestures)
    Run.onFinish.append {
        gestures.feed(box.take())
        gestures.closeAll()
        let disabled = box.disabled.withLock { $0 }
        let pads = deviceList.infos.filter(\.isTrackpad).map { hex($0.registryID) }
        printSummary(
            [
                row("gestures", gestures.gestureCounts()),
                row("events", "\(countText(gestures.scrollEvents + gestures.gestureEvents + gestures.dockEvents)) (scroll \(countText(gestures.scrollEvents)), gesture \(countText(gestures.gestureEvents)), dock control \(countText(gestures.dockEvents)))"),
                row("discrete wheel", "\(countText(gestures.discrete)) events"),
                row("tap disabled", "\(disabled) times"),
            ],
            gates: [
                pad("T1  pinches 1→2…→4 \(gestures.completePinches) of \(gestures.gestures[.pinch] ?? 0)") + "(gate: 9 of 10 per surface, both trackpads)",
                pad("T1  pans with a start \(gestures.pansWithStart) of \(gestures.gestures[.pan] ?? 0)") + "(gate: 9 of 10 per surface)",
                pad("T4  dock control events \(gestures.dockEvents)") + "(observed here only; never in the product mask)",
                pad("T6  pid field set: scroll \(gestures.pidSetScroll) of \(gestures.scrollEvents) · gesture \(gestures.pidSetGesture) of \(gestures.gestureEvents)") + "  (gate: recorded)",
                "T6  pid field = app under pointer in \(gestures.pidMatchesPointer) of \(gestures.gestures.values.reduce(0, +)) gestures · = frontmost app in \(gestures.pidMatchesFrontmost) · 0 in \(gestures.pidZero)  (gate: recorded; decides trustsTargetPID)",
                "T6  senders seen \(gestures.senders.sorted().map(hex).joined(separator: ", ")) · trackpads \(pads.joined(separator: ", "))  (E-04 filter works only if they match)",
            ],
            record: [
                "gestures": gestures.gestures.values.reduce(0, +), "pinches": gestures.gestures[.pinch] ?? 0, "pans": gestures.gestures[.pan] ?? 0,
                "completePinches": gestures.completePinches, "pansWithStart": gestures.pansWithStart, "dockEvents": gestures.dockEvents,
                "pidSetScroll": gestures.pidSetScroll, "scrollEvents": gestures.scrollEvents, "pidSetGesture": gestures.pidSetGesture,
                "gestureEvents": gestures.gestureEvents, "pidMatchesPointer": gestures.pidMatchesPointer,
                "pidMatchesFrontmost": gestures.pidMatchesFrontmost, "pidZero": gestures.pidZero, "senders": gestures.senders.sorted().map(hex), "trackpads": pads, "tapDisabled": disabled,
            ])
    }
}

func runTapConsume() {
    let box = TapBox(mode: .consume, state: tapState(), requireAlt: requireAlt)
    guard Tap.start(box, mask: GestureTapRules.mask, place: .headInsertEventTap, options: .defaultTap) else {
        permissionFailure("Accessibility")
    }
    Run.boxes = [box]
    let gestures = Gestures(.consume)
    startDrain(box, into: gestures)
    Run.onFinish.append {
        gestures.feed(box.take())
        gestures.closeAll()
        let disabled = box.disabled.withLock { $0 }
        let p50 = percentile(gestures.allMicros, 0.5)
        let p99 = percentile(gestures.allMicros, 0.99)
        let max = gestures.allMicros.max() ?? 0
        let passedP50 = percentile(gestures.passedMicros, 0.5)
        printSummary(
            [
                row("gestures", gestures.gestureCounts()),
                row("taken", "\(gestures.taken) · passed \(gestures.passedSequences)"),
                row("events", "\(countText(gestures.eventsConsumed)) consumed · \(countText(gestures.eventsPassed)) passed"),
                row("callback", "p50 \(micros(p50)) · p99 \(micros(p99)) · max \(micros(max))"),
                row("tap disabled", "\(disabled) times"),
                row("timeouts", "\(gestures.timeouts) sequences ended by timeout"),
            ],
            gates: [
                pad("T5  callback p99 \(micros(p99))") + "(gate: under 1 ms)",
                pad("T5  passed-event p50 \(micros(passedP50))") + "(gate: under 50 µs)",
                pad("T5  tap disabled \(disabled)") + "(gate: 0 in 30 s)",
            ],
            record: [
                "gestures": gestures.gestures.values.reduce(0, +), "taken": gestures.taken, "passedSequences": gestures.passedSequences,
                "eventsConsumed": gestures.eventsConsumed, "eventsPassed": gestures.eventsPassed, "p50us": p50, "p99us": p99, "maxus": max,
                "passedP50us": passedP50, "tapDisabled": disabled, "timeouts": gestures.timeouts, "requireAlt": requireAlt,
                "trackpadSenders": box.state.trackpadSenders.sorted().map(hex),
            ])
    }
}

// MARK: - Multitouch (mt-devices, mt-stream, compare, rescan)

/// Frames from the product shim (TransomPrivate), queued for the main-thread drains below.
nonisolated let pendingFrames = OSAllocatedUnfairLock(initialState: [MultitouchSupport.Frame]())
nonisolated func takeFrames() -> [MultitouchSupport.Frame] { pendingFrames.withLock { pending in defer { pending = [] }; return pending } }

let deviceList = MultitouchSupport.DeviceList()

func deviceLine(_ info: MultitouchSupport.Info) -> String {
    "\(info.name) · family \(info.family) · device id \(hex(info.deviceID)) · registry \(hex(info.registryID)) · "
        + String(format: "surface %.1f × %.1f mm", info.widthMM, info.heightMM) + " · driver type \(info.driverType)"
}

func deviceRecord(_ info: MultitouchSupport.Info) -> [String: Any] {
    [
        "type": "device", "name": info.name, "builtIn": info.builtIn, "family": Int(info.family), "deviceID": hex(info.deviceID),
        "registry": hex(info.registryID), "widthMM": info.widthMM, "heightMM": info.heightMM, "driverType": Int(info.driverType),
        "trackpad": info.isTrackpad,
    ]
}

func runDevices() {
    for info in deviceList.infos {
        Output.say(deviceLine(info))
        Output.record(deviceRecord(info))
    }
    if deviceList.infos.isEmpty { Output.say("No multitouch devices.") }
    let table = MultitouchSupport.symbolTable()
    for (name, found) in table { Output.say("\(name.padding(toLength: 42, withPad: " ", startingAt: 0))\(found ? "found" : "missing")") }
    Output.record(["type": "symbols", "table": Dictionary(uniqueKeysWithValues: table.map { ($0.0, $0.1) })])
    let builtIn = deviceList.infos.filter(\.builtIn).count
    printSummary(
        [row("devices", "\(deviceList.infos.count) (trackpads \(deviceList.infos.filter(\.isTrackpad).count), built-in \(builtIn))"),
         row("symbols", "\(table.filter(\.1).count) of \(table.count) found")],
        gates: [pad("M1  devices \(deviceList.infos.count), built-in \(builtIn)") + "(gate: both trackpads, correct built-in)"],
        record: ["devices": deviceList.infos.count, "builtIn": builtIn, "symbolsFound": table.filter(\.1).count])
    Run.finish()
}

/// Multitouch frames on main: JSON per frame, one line per device per second, layout sanity counts for M1.
final class Stream {
    var infos: [Int: MultitouchSupport.Info] = [:]
    var frames = 0, touchFrames = 0, touches = 0, outOfRange = 0, badStates = 0, backwards = 0
    var maxSpeed: Float = 0
    var mainThreadFrames = 0
    var transitions: Set<String> = []
    var idFrames: [Int: [Int32: Int]] = [:]
    var lastState: [Int: [Int32: Int32]] = [:]
    var lastDeviceTime: [Int: Double] = [:]
    var lastCount: [Int: Int] = [:]
    var secondFrames: [Int: [MultitouchSupport.Frame]] = [:]
    /// Uptime of each 0 → touching transition, for compare.
    var touchDowns: [Double] = []
    var firstFrame: ((Int, MultitouchSupport.Frame) -> Void)?
    var seen: Set<Int> = []

    func name(_ device: Int) -> String { infos[device]?.name ?? "device \(device)" }

    func feed(_ batch: [MultitouchSupport.Frame]) {
        for frame in batch {
            frames += 1
            if frame.mainThread { mainThreadFrames += 1 }
            if !seen.contains(frame.device) {
                seen.insert(frame.device)
                firstFrame?(frame.device, frame)
            }
            if let previous = lastDeviceTime[frame.device], frame.deviceTime < previous { backwards += 1 }
            lastDeviceTime[frame.device] = frame.deviceTime
            if !frame.touches.isEmpty { touchFrames += 1 }
            if (lastCount[frame.device] ?? 0) == 0 && !frame.touches.isEmpty { touchDowns.append(frame.t) }
            lastCount[frame.device] = frame.touches.count
            var states = lastState[frame.device] ?? [:]
            for touch in frame.touches {
                touches += 1
                if !(0...1).contains(touch.x) || !(0...1).contains(touch.y) { outOfRange += 1 }
                if !(0...7).contains(touch.state) { badStates += 1 }
                maxSpeed = max(maxSpeed, (touch.vx * touch.vx + touch.vy * touch.vy).squareRoot())
                if let previous = states[touch.id], previous != touch.state { transitions.insert("\(previous)→\(touch.state)") }
                states[touch.id] = touch.state
                idFrames[frame.device, default: [:]][touch.id, default: 0] += 1
            }
            for id in states.keys where !frame.touches.contains(where: { $0.id == id }) { states[id] = nil }
            lastState[frame.device] = states
            secondFrames[frame.device, default: []].append(frame)
            Output.record([
                "type": "frame", "device": frame.device, "name": name(frame.device), "t": frame.t, "deviceTime": frame.deviceTime,
                "frame": Int(frame.frame), "count": Int(frame.rawCount), "main": frame.mainThread,
                "touches": frame.touches.map { ["id": Int($0.id), "state": Int($0.state), "x": Double($0.x), "y": Double($0.y), "vx": Double($0.vx), "vy": Double($0.vy)] },
            ])
        }
    }

    /// One line per device that sent frames since the last call.
    func printSecond() {
        for (device, batch) in secondFrames.sorted(by: { $0.key < $1.key }) {
            guard let last = batch.last else { continue }
            let deltas = zip(batch.dropFirst(), batch).map { $0.t - $1.t }
            let dt = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count) * 1000
            let ids = last.touches.map { String($0.id) }.joined(separator: ",")
            let states = last.touches.map { String($0.state) }.joined(separator: ",")
            Output.say(
                "\(clockTime(last.t))  \(name(device))  \(last.touches.count) touches  ids \(ids.isEmpty ? "–" : ids)  states \(states.isEmpty ? "–" : states)  "
                    + String(format: "frame Δt %.1f ms", dt) + "  callback thread: \(last.mainThread ? "main" : "background")")
        }
        secondFrames = [:]
    }

    func summaryRows() -> [String] {
        [
            row("devices", "\(infos.count) streamed (\(infos.values.sorted { $0.index < $1.index }.map(\.name).joined(separator: ", ")))"),
            row("frames", "\(countText(frames)) (with touches \(countText(touchFrames)))"),
            row("touches", "\(countText(touches)) read"),
            row("callback", frames == 0 ? "no frames" : mainThreadFrames == 0 ? "background thread" : "main thread on \(mainThreadFrames) frames"),
        ]
    }

    func gateRows() -> [String] {
        let ids = idFrames.values.flatMap(\.values)
        return [
            pad("M1  x,y outside [0,1] \(outOfRange) of \(countText(touches))") + "(gate: 0)",
            pad("M1  states outside 0-7 \(badStates)") + "(gate: 0)",
            pad("M1  state transitions \(transitions.sorted().joined(separator: ", "))") + "  (gate: 3→4…→5→(6/7))",
            pad("M1  ids in one frame only \(ids.filter { $0 == 1 }.count) of \(ids.count)") + "(gate: stable ids)",
            pad("M1  timestamps going back \(backwards)") + "(gate: 0)",
            pad(String(format: "M1  max speed %.2f", maxSpeed)) + "(gate: plausible velocities)",
        ]
    }

    func summaryRecord() -> [String: Any] {
        [
            "frames": frames, "touchFrames": touchFrames, "touches": touches, "outOfRange": outOfRange, "badStates": badStates,
            "transitions": transitions.sorted(), "backwards": backwards, "maxSpeed": Double(maxSpeed), "mainThreadFrames": mainThreadFrames,
            "singleFrameIDs": idFrames.values.flatMap(\.values).filter { $0 == 1 }.count, "ids": idFrames.values.flatMap(\.values).count,
        ]
    }
}

let worker: MultitouchSupport.Worker = {
    MultitouchSupport.setHandler { frame in pendingFrames.withLock { $0.append(frame) } }
    return MultitouchSupport.Worker()
}()

/// Starts streaming the trackpads of `list` into `stream`; false when there is nothing to stream.
func stream(_ list: MultitouchSupport.DeviceList, into stream: Stream, tagBase: Int = 0) -> Bool {
    for info in list.infos where info.isTrackpad { stream.infos[tagBase + info.index] = info }
    guard !stream.infos.isEmpty else { return false }
    return MultitouchSupport.startStreaming(list, on: worker, tagBase: tagBase)
}

func runMTStream() {
    let frames = Stream()
    guard stream(deviceList, into: frames) else {
        Output.say("No trackpad to stream, or the multitouch symbols are missing.")
        printSummary([], gates: [], record: ["frames": 0])
        Run.finish()
        return
    }
    Run.onFinish.append { MultitouchSupport.stopStreaming(deviceList, on: worker) }
    every(1) {
        frames.feed(takeFrames())
        frames.printSecond()
    }
    Run.onFinish.append {
        frames.feed(takeFrames())
        printSummary(
            frames.summaryRows(), gates: frames.gateRows() + ["M2  system gestures while streaming: your checklist item 4 answer  (gate: 10 of 10)"],
            record: frames.summaryRecord())
    }
}

func runCompare() {
    let frames = Stream()
    guard stream(deviceList, into: frames) else {
        Output.say("No trackpad to stream, or the multitouch symbols are missing.")
        printSummary([], gates: [], record: ["frames": 0])
        Run.finish()
        return
    }
    Run.onFinish.append { MultitouchSupport.stopStreaming(deviceList, on: worker) }
    let box = TapBox(mode: .listen, state: listenState)
    guard Tap.start(box, mask: GestureTapRules.mask, place: .tailAppendEventTap, options: .listenOnly) else {
        permissionFailure("Accessibility")
    }
    Run.boxes = [box]
    let gestures = Gestures(.compare)
    gestures.compareText = { _, started in
        // The latest touch-down at most 1 s before the gesture's first tap event.
        guard let down = frames.touchDowns.last(where: { $0 <= started && started - $0 <= 1 }) else {
            return ("no multitouch touch-down within 1 s before the first tap event", nil)
        }
        let lead = ((started - down) * 1000).rounded()
        return ("first MT frame leads first tap event by \(Int(lead)) ms", lead)
    }
    // Frames first, so a gesture closing in this tick already has its touch-down.
    startDrain(box, into: gestures) { frames.feed(takeFrames()) }
    Run.onFinish.append {
        frames.feed(takeFrames())
        gestures.feed(box.take())
        gestures.closeAll()
        var medians: [String] = []
        for kind in [GestureSample.Kind.pinch, .pan] {
            let values = gestures.leads[kind] ?? []
            medians.append(values.isEmpty ? "no data" : "\(Int(percentile(values, 0.5))) ms (n \(values.count))")
        }
        printSummary(
            [row("gestures", gestures.gestureCounts()), row("frames", countText(frames.frames))],
            gates: [
                pad("M4  median lead pinch \(medians[0])") + "(gate: reported; decision matrix row 1 needs under 30 ms)",
                pad("M4  median lead pan \(medians[1])") + "(gate: reported)",
            ],
            record: ["leadsPinch": gestures.leads[.pinch] ?? [], "leadsPan": gestures.leads[.pan] ?? [], "frames": frames.frames])
    }
}

/// IOKit add/remove and wake for M3. Every add or remove re-creates the device list: the old devices are stopped and
/// unregistered, then the old list (which owns them) is dropped. No device is released on its own (Pitfall 7).
enum Rescan {
    static var list = deviceList
    static var generation = 0
    static let frames = Stream()
    static var pendingFirstFrame: [UInt64: (Double, String)] = [:]
    static var wakeTime: Double?
    static var firstAfterWake: Double?
    static var reAddLatency: [Double] = []
    static var notifyPort: IONotificationPortRef?
    static var iterators: [io_iterator_t] = []

    static func registryIDs(_ iterator: io_iterator_t) -> [UInt64] {
        var ids: [UInt64] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            ids.append(id)
            IOObjectRelease(service)
        }
        return ids
    }

    static func describe(_ list: MultitouchSupport.DeviceList) -> String {
        let pads = list.infos.filter(\.isTrackpad)
        return pads.isEmpty ? "none" : pads.map { "\($0.name) (registry \(hex($0.registryID)))" }.joined(separator: " · ")
    }

    static func restart(reason: String) {
        let before = describe(list)
        MultitouchSupport.stopStreaming(list, on: worker)
        frames.infos = [:]
        generation += 1
        list = MultitouchSupport.DeviceList()
        _ = stream(list, into: frames, tagBase: generation << 8)
        Output.record(["type": "rescan", "event": "restart", "reason": reason, "devicesBefore": before, "devicesAfter": describe(list)])
    }

    static func added(_ ids: [UInt64]) {
        let now = uptime()
        restart(reason: "added")
        for id in ids {
            let name = list.infos.first { $0.registryID == id }?.name ?? "device"
            pendingFirstFrame[id] = (now, name)
            Output.record(["type": "rescan", "event": "added", "registry": hex(id), "name": name, "t": now])
        }
    }

    static func removed(_ ids: [UInt64]) {
        for id in ids {
            let name = list.infos.first { $0.registryID == id }?.name ?? "device"
            Output.say("\(clockTime(uptime()))  removed \(name) (registry \(hex(id)))")
            Output.record(["type": "rescan", "event": "removed", "registry": hex(id), "name": name, "t": uptime()])
        }
        restart(reason: "removed")
    }

    static let matchedCallback: IOServiceMatchingCallback = { _, iterator in
        let ids = Rescan.registryIDs(iterator)
        MainActor.assumeIsolated { Rescan.added(ids) }
    }
    static let terminatedCallback: IOServiceMatchingCallback = { _, iterator in
        let ids = Rescan.registryIDs(iterator)
        MainActor.assumeIsolated { Rescan.removed(ids) }
    }

    static func didSleep() {
        Output.say("\(clockTime(uptime()))  sleep")
        Output.record(["type": "rescan", "event": "sleep", "t": uptime()])
    }

    static func didWake() {
        wakeTime = uptime()
        firstAfterWake = nil
        // A device that came back is reached again only through a fresh list; its frames count as first frames again.
        frames.seen = []
        Output.say("\(clockTime(uptime()))  wake")
        Output.record(["type": "rescan", "event": "wake", "t": uptime()])
        restart(reason: "wake")
    }

    static func run() {
        Output.say("Devices before: \(describe(list))")
        frames.firstFrame = { device, frame in
            let info = frames.infos[device]
            if let wake = wakeTime, firstAfterWake == nil, frame.t > wake {
                firstAfterWake = (frame.t - wake) * 1000
                Output.say("\(clockTime(frame.t))  first frame after wake \(Int(firstAfterWake!)) ms")
                Output.record(["type": "rescan", "event": "first-frame-after-wake", "ms": firstAfterWake!])
            }
            if let info, let (t, name) = pendingFirstFrame.removeValue(forKey: info.registryID) {
                let ms = (frame.t - t) * 1000
                reAddLatency.append(ms)
                Output.say("\(clockTime(frame.t))  added \(name) · first frame after \(Int(ms)) ms")
                Output.record(["type": "rescan", "event": "first-frame-after-add", "registry": hex(info.registryID), "ms": ms])
            }
        }
        _ = stream(list, into: frames)
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { fail("IOKit notifications unavailable", 70) }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        for (type, callback) in [(kIOFirstMatchNotification, matchedCallback), (kIOTerminatedNotification, terminatedCallback)] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), callback, nil, &iterator)
            _ = registryIDs(iterator)  // drains the devices already present, which arms the notification
            iterators.append(iterator)
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Rescan.didSleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Rescan.didWake() }
        }
        every(1) {
            frames.feed(takeFrames())
            frames.printSecond()
        }
        Run.onFinish.append {
            MultitouchSupport.stopStreaming(list, on: worker)
            frames.feed(takeFrames())
            for (id, (_, name)) in pendingFirstFrame { Output.say("added \(name) (registry \(hex(id))) · no frame before the end") }
            let wake = firstAfterWake.map { "\(Int($0)) ms" } ?? (wakeTime == nil ? "no wake seen" : "no frame after wake")
            let reAdd = reAddLatency.isEmpty ? "no re-add seen" : reAddLatency.map { "\(Int($0)) ms" }.joined(separator: ", ")
            printSummary(
                [row("devices before", describe(deviceList)), row("devices after", describe(list))] + frames.summaryRows(),
                gates: [
                    pad("M3  first frame after wake \(wake)") + "(gate: under 2 s)",
                    pad("M3  first frame after re-add \(reAdd)") + "(gate: under 2 s)",
                    pad("M3  crash: none (this summary printed)") + "(gate: no crash)",
                ],
                record: ["firstAfterWakeMs": firstAfterWake ?? NSNull(), "reAddMs": reAddLatency, "devicesAfter": describe(list)])
        }
    }
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
        case "tap-listen": runTapListen()
        case "tap-consume": runTapConsume()
        case "mt-devices": runDevices()
        case "mt-stream": runMTStream()
        case "compare": runCompare()
        default: Rescan.run()
        }
    }
}
application.run()
