import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Darwin
import Foundation
import KeyboardShortcuts
import TransomEngine
import TransomMac
import TransomPrivate
import os

// Phase 6 Spaces spike (06-01, RESEARCH "VM spike subcommands"). It runs only in the Tart VM through
// scripts/vm-spike.sh, except swipe-check which the user runs on the host. Every subcommand stops by itself after
// --seconds (default 30, max 120). stdout is for the person watching, JSON lines go to --out. It records readings and
// never a verdict: verdicts are made in 06-SPIKE.md. Spaces are read through the product's SpacesProvider, so the
// spike measures exactly what ships.

let usage = """
    usage: transom-spaces-spike <subcommand> [--seconds N] [--label text] [--out path]
      spaces-dump      private symbol table, raw managed-display Spaces, management mode, parsed snapshot   A5 A8
      hotkeys          symbolic hotkey table; disable 32/108, post F3 and ⌃↑, Carbon streams, CoreDock     A1 A3
      takeover-crash   a child disables 32/108 and aborts; does the disabled state outlive it              A2
      switch           posted ⌃→/⌃← latency to activeSpaceDidChange, AX after the switch                     A4
      ghost            closed Safari window: AX answer, CG presence and Space set every second              A7
      swipe-check      four-finger swipe consumption (user, host only: --i-am-on-the-host)                   D-05
    hotkeys, takeover-crash, switch and ghost refuse to run outside a VM.
    """

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("transom-spaces-spike: \(message)\n".utf8))
    exit(code)
}

let subcommands = ["spaces-dump", "hotkeys", "takeover-crash", "switch", "ghost", "swipe-check"]
var arguments = CommandLine.arguments.dropFirst()
let subcommand: String = {
    guard let first = arguments.popFirst() else { fail(usage, 64) }
    return first
}()
guard subcommands.contains(subcommand) else { fail("unknown subcommand \(subcommand)\n\(usage)", 64) }
var options: [String: String] = [:]
var flags: Set<String> = []
while let argument = arguments.popFirst() {
    switch argument {
    case "--seconds", "--label", "--out":
        guard let value = arguments.popFirst() else { fail("\(argument) needs a value\n\(usage)", 64) }
        options[argument] = value
    case "--i-am-on-the-host", "--child-apply-abort":
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
let label = options["--label"] ?? ""
let launchDate = Date()

func formatted(_ date: Date, _ format: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: date)
}

let outPath = options["--out"] ?? ".build/spike/spaces-\(subcommand)-\(formatted(launchDate, "yyyyMMdd-HHmmss"))/out.jsonl"

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

    /// Sorted keys, no whitespace, so gates can grep `"SLSCopyManagedDisplaySpaces":true`. A value JSON can't hold
    /// (a CFData in a SkyLight dictionary) is written as its description.
    static func record(_ fields: [String: Any]) {
        var fields = fields
        fields["label"] = label
        fields["t"] = formatted(Date(), "HH:mm:ss.SSS")
        let object: Any = JSONSerialization.isValidJSONObject(fields) ? fields : jsonSafe(fields)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        handle?.write(data + Data("\n".utf8))
    }

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }
}

func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]: dictionary.mapValues(jsonSafe)
    case let array as [Any]: array.map(jsonSafe)
    case let double as Double where !double.isFinite: 0.0
    case is String, is NSNumber: value
    default: String(describing: value)
    }
}

func osVersion() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (\(MultitouchCanary.currentOSBuild))"
}

// MARK: - spaces-dump

/// 06-RESEARCH F2: every private symbol the phase may use, by framework.
let skyLightSymbols = [
    "SLSMainConnectionID", "SLSCopyManagedDisplaySpaces", "SLSGetSpaceManagementMode", "SLSManagedDisplayGetCurrentSpace",
    "SLSCopySpacesForWindows", "SLSSpaceGetType", "SLSSpaceCopyName", "SLSGetActiveSpace", "SLSManagedDisplaySetCurrentSpace",
    "SLSShowSpaces", "SLSHideSpaces", "SLSCopyManagedDisplayForSpace", "SLSCopyWindowsWithOptionsAndTags",
    "SLSMoveWindowsToManagedSpace", "CGSSetSymbolicHotKeyEnabled", "CGSIsSymbolicHotKeyEnabled", "CGSGetSymbolicHotKeyValue",
    "CGSSetSymbolicHotKeyValue", "SLSSetSymbolicHotKeyEnabled", "SLSIsSymbolicHotKeyEnabled", "SLSGetSymbolicHotKeyValue",
    "_SLPSSetFrontProcessWithOptions", "SLPSPostEventRecordTo",
]
let hiServicesSymbols = ["CoreDockSendNotification", "_AXUIElementGetWindow"]

func symbolTable() -> [String: Bool] {
    var table: [String: Bool] = [:]
    let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    let hiServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
    for name in skyLightSymbols { table[name] = skyLight.map { dlsym($0, name) != nil } ?? false }
    for name in hiServicesSymbols { table[name] = hiServices.map { dlsym($0, name) != nil } ?? false }
    return table
}

func snapshotFields(_ snapshot: SpacesSnapshot?) -> Any {
    guard let snapshot else { return NSNull() }
    return [
        "separateSpaces": snapshot.separateSpaces,
        "skipped": snapshot.skipped,
        "displays": snapshot.displays.map { display in
            [
                "displayUUID": display.displayUUID,
                "current": display.current.map { NSNumber(value: $0) } ?? NSNull(),
                "spaces": display.spaces.map { ["id": NSNumber(value: $0.id), "uuid": $0.uuid, "kind": $0.kind.rawValue, "index": $0.index] },
            ] as [String: Any]
        },
    ] as [String: Any]
}

func spacesDump() -> Int32 {
    let table = symbolTable()
    let snapshot = SpacesProvider.snapshot()
    Output.record([
        "kind": "spaces-dump",
        "os": osVersion(),
        "symbols": table,
        "raw": SkyLightSpaces.managedDisplaySpaces() ?? NSNull(),
        "managementMode": SkyLightSpaces.managementMode().map { NSNumber(value: $0) } ?? NSNull(),
        "screensHaveSeparateSpaces": NSScreen.screensHaveSeparateSpaces,
        "snapshot": snapshotFields(snapshot),
    ])
    let missing = table.filter { !$0.value }.keys.sorted()
    Output.say("symbols: \(table.count - missing.count)/\(table.count) resolved" + (missing.isEmpty ? "" : "; missing \(missing.joined(separator: ", "))"))
    for display in snapshot?.displays ?? [] {
        Output.say("display \(display.displayUUID) current \(display.current.map(String.init) ?? "–"): "
            + display.spaces.map { "\($0.id) \($0.kind.rawValue) #\($0.index) \($0.uuid)" }.joined(separator: " · "))
    }
    if snapshot == nil { Output.say("Spaces lookup off: no snapshot") }
    return 0
}


// MARK: - Run lifecycle, clock, VM guard

final class Flag {
    var value = false
}

/// Seconds on the uptime clock.
nonisolated func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }

func pause(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

enum Run {
    /// Run once, newest first, on a normal finish, the --seconds timeout and SIGINT/SIGHUP/SIGTERM.
    static var cleanups: [(name: String, action: () -> Void)] = []
    static var finished = false

    static func onFinish(_ name: String, _ action: @escaping () -> Void) { cleanups.append((name, action)) }

    static func finish(_ code: Int32, reason: String = "done") -> Never {
        if !finished {
            finished = true
            for cleanup in cleanups.reversed() { cleanup.action() }
            cleanups = []
            if reason != "done" { Output.record(["kind": "stopped", "reason": reason]) }
            try? Output.handle?.close()
        }
        exit(code)
    }
}

/// The state-changing subcommands never run on a real Mac (CONTEXT E, D-08).
func requireVM() {
    var vmm: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("kern.hv_vmm_present", &vmm, &size, nil, 0) == 0, vmm == 1 else {
        fail("\(subcommand) runs only inside the Tart VM (scripts/vm-spike.sh)", 64)
    }
}

// MARK: - Events and Mission Control detection

/// Posts one key chord (down and up) with explicit flags, never the held modifiers (06-RESEARCH Pitfall 7).
func post(keyCode: CGKeyCode, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

func windowList(_ options: CGWindowListOption) -> [[String: Any]] {
    CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
}

/// On-screen windows the Dock owns: Mission Control adds several above the desktop.
func dockWindows() -> [Int] {
    windowList([.optionOnScreenOnly]).filter { $0[kCGWindowOwnerName as String] as? String == "Dock" }
        .compactMap { $0[kCGWindowLayer as String] as? Int }
}

/// The Dock's on-screen window count before and 600 ms after `action`.
func missionControlCheck(_ action: () -> Void) async -> (opened: Bool, before: Int, after: Int, layers: [Int]) {
    let before = dockWindows().count
    action()
    await pause(600)
    let after = dockWindows()
    return (after.count > before, before, after.count, after.sorted())
}

/// Leaves Mission Control with Escape (a control key, not text) if it is still showing.
func closeMissionControl(baseline: Int) async {
    guard dockWindows().count > baseline else { return }
    post(keyCode: CGKeyCode(kVK_Escape), flags: [])
    await pause(800)
}

let fnFlag: UInt32 = 0x800000

/// Posts the hotkey's chord from its own value (NX flags are CGEventFlags bits), first without the fn bit, then with
/// it if nothing opened. Records one line per attempt.
func postHotkeyChord(_ id: Int32, value: SymbolicHotKeys.Value, step: String) async -> Bool {
    for withFn in [false, true] {
        let raw = withFn ? value.modifiers | fnFlag : value.modifiers & ~fnFlag
        let check = await missionControlCheck { post(keyCode: value.keyCode, flags: CGEventFlags(rawValue: UInt64(raw))) }
        Output.record([
            "kind": "post", "step": step, "hotkey": id, "keyCode": value.keyCode, "flags": String(raw, radix: 16),
            "missionControl": check.opened, "dockBefore": check.before, "dockAfter": check.after, "dockLayers": check.layers,
        ])
        Output.say("\(step): hotkey \(id) chord vk \(value.keyCode) flags 0x\(String(raw, radix: 16)) → Mission Control \(check.opened ? "opened" : "not opened") (Dock windows \(check.before) → \(check.after))")
        if check.opened {
            await closeMissionControl(baseline: check.before)
            return true
        }
    }
    return false
}

// MARK: - Symbolic hotkey restore (T-06-01)

/// Every ID this process disabled, with the enabled state it had before. Restored by `restoreHotkeys` from a `defer`,
/// the timeout and the signal handlers.
var hotkeyOriginals: [Int32: Bool] = [:]

func disable(_ ids: [Int32]) {
    for id in ids {
        if hotkeyOriginals[id] == nil, let enabled = SymbolicHotKeys.isEnabled(id) { hotkeyOriginals[id] = enabled }
        SymbolicHotKeys.setEnabled(id, false)
    }
}

/// Restores every stored original and reads it back; the stored set is cleared only for IDs that read back right.
@discardableResult
func restoreHotkeys() -> [String: Any] {
    var readBack: [String: Any] = [:]
    for (id, enabled) in hotkeyOriginals.sorted(by: { $0.key < $1.key }) {
        let rc = SymbolicHotKeys.setEnabled(id, enabled)
        let now = SymbolicHotKeys.isEnabled(id)
        readBack[String(id)] = ["original": enabled, "readBack": now.map { $0 as Any } ?? NSNull(), "setOK": rc] as [String: Any]
        if now == enabled { hotkeyOriginals[id] = nil }
    }
    return readBack
}

func hotkeyState(_ ids: [Int32]) -> [String: Any] {
    Dictionary(uniqueKeysWithValues: ids.map { id -> (String, Any) in
        (String(id), [
            "enabled": SymbolicHotKeys.isEnabled(id).map { $0 as Any } ?? NSNull(),
            "keyCode": SymbolicHotKeys.value(id).map { Int($0.keyCode) as Any } ?? NSNull(),
            "modifiers": SymbolicHotKeys.value(id).map { String($0.modifiers, radix: 16) as Any } ?? NSNull(),
        ] as [String: Any])
    })
}

/// NX device-independent flags → Carbon modifiers (06-RESEARCH Pattern 4); the fn bit is dropped.
func carbonModifiers(_ nx: UInt32) -> Int {
    var carbon = 0
    if nx & 0x20000 != 0 { carbon |= shiftKey }
    if nx & 0x40000 != 0 { carbon |= controlKey }
    if nx & 0x80000 != 0 { carbon |= optionKey }
    if nx & 0x100000 != 0 { carbon |= cmdKey }
    return carbon
}

// MARK: - hotkeys (VM only)

func hotkeys() async -> Int32 {
    requireVM()
    defer { if !hotkeyOriginals.isEmpty { Output.record(["kind": "restore", "step": "defer", "readBack": restoreHotkeys()]) } }
    guard SymbolicHotKeys.isLoaded else {
        Output.record(["kind": "summary", "loaded": false])
        return 1
    }
    var valid = 0
    for id in Int32(0)..<400 {
        guard let value = SymbolicHotKeys.value(id) else { continue }
        valid += 1
        Output.record([
            "kind": "hotkey", "id": id, "enabled": SymbolicHotKeys.isEnabled(id) ?? false, "keyCode": value.keyCode,
            "modifiers": String(value.modifiers, radix: 16),
        ])
    }
    let watched: [Int32] = [32, 34, 108, 113]
    let originals = hotkeyState(watched)
    Output.record(["kind": "originals", "hotkeys": originals])
    Output.say("\(valid) hotkeys with a value; originals of 32/34/108/113: \(originals)")
    let values = Dictionary(uniqueKeysWithValues: watched.compactMap { id in SymbolicHotKeys.value(id).map { (id, $0) } })
    guard let mc = values[32], let mcKey = values[108] else {
        Output.record(["kind": "summary", "error": "hotkey 32 or 108 has no value"])
        return 1
    }

    // Baseline: does a posted chord open Mission Control while macOS owns it?
    var baseline: [String: Bool] = [:]
    for id: Int32 in [108, 32] { baseline[String(id)] = await postHotkeyChord(id, value: values[id]!, step: "baseline") }

    disable([SymbolicHotKeys.missionControl, SymbolicHotKeys.missionControlKey])
    let disabledState = hotkeyState([32, 108])
    Output.record(["kind": "disabled", "readBack": disabledState])
    var whileDisabled: [String: Bool] = [:]
    for id: Int32 in [108, 32] { whileDisabled[String(id)] = await postHotkeyChord(id, value: values[id]!, step: "disabled") }

    // Carbon hotkeys on the freed chords.
    var carbon: [String: Bool] = [:]
    for (id, value) in [(Int32(32), mc), (Int32(108), mcKey)] {
        let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: Int(value.keyCode), carbonModifiers: carbonModifiers(value.modifiers))
        let fired = Flag()
        let listener = Task { for await event in KeyboardShortcuts.events(for: shortcut) where event == .keyDown { fired.value = true } }
        await pause(200)
        post(keyCode: value.keyCode, flags: CGEventFlags(rawValue: UInt64(value.modifiers & ~fnFlag)))
        await pause(500)
        if !fired.value {
            post(keyCode: value.keyCode, flags: CGEventFlags(rawValue: UInt64(value.modifiers | fnFlag)))
            await pause(500)
        }
        listener.cancel()
        carbon[String(id)] = fired.value
        Output.record(["kind": "carbon", "hotkey": id, "carbonKeyCode": Int(value.keyCode), "carbonModifiers": carbonModifiers(value.modifiers), "fired": fired.value])
        Output.say("Carbon hotkey on hotkey \(id)'s chord: \(fired.value ? "fired" : "did not fire")")
    }

    // CoreDock with 32/108 disabled: open, then toggle closed.
    var coreDock: [String: Any] = ["loaded": CoreDock.isLoaded]
    if CoreDock.isLoaded {
        let open = await missionControlCheck { CoreDock.send(CoreDock.missionControl) }
        let close = await missionControlCheck { CoreDock.send(CoreDock.missionControl) }
        coreDock["opened"] = open.opened
        coreDock["closedBySecondSend"] = close.after <= open.before
        coreDock["dock"] = [open.before, open.after, close.after]
        Output.say("CoreDock: Mission Control \(open.opened ? "opened" : "not opened"); second send \(close.after <= open.before ? "closed it" : "did not close it") (Dock windows \(open.before) → \(open.after) → \(close.after))")
        await closeMissionControl(baseline: open.before)
    }
    var coreDockLine = coreDock
    coreDockLine["kind"] = "coredock"
    Output.record(coreDockLine)

    // 34 and 113 with only 32/108 disabled.
    var variants: [String: Any] = [:]
    for id: Int32 in [34, 113] {
        guard let value = values[id], SymbolicHotKeys.isEnabled(id) == true else {
            variants[String(id)] = NSNull()
            continue
        }
        variants[String(id)] = await postHotkeyChord(id, value: value, step: "variant")
    }

    let restored = restoreHotkeys()
    Output.record([
        "kind": "summary", "validHotkeys": valid, "baseline": baseline, "whileDisabled": whileDisabled, "disabledReadBack": disabledState,
        "carbonFired": carbon, "coreDock": coreDock, "variantsOpenMissionControl": variants, "restored": restored,
        "final": hotkeyState([32, 108]),
    ])
    return hotkeyOriginals.isEmpty ? 0 : 1
}

// MARK: - takeover-crash (VM only)

/// The hidden child: disable 32/108 and abort, so nothing restores them.
func childApplyAbort() -> Never {
    SymbolicHotKeys.setEnabled(SymbolicHotKeys.missionControl, false)
    SymbolicHotKeys.setEnabled(SymbolicHotKeys.missionControlKey, false)
    abort()
}

func takeoverCrash() async -> Int32 {
    requireVM()
    let ids: [Int32] = [32, 108]
    var originals: [String: Bool] = [:]
    for id in ids { originals[String(id)] = SymbolicHotKeys.isEnabled(id) }
    let originalsURL = URL(fileURLWithPath: outPath).deletingLastPathComponent().appendingPathComponent("originals.json")
    do {
        try JSONSerialization.data(withJSONObject: originals, options: [.sortedKeys]).write(to: originalsURL)
    } catch { fail("can't write \(originalsURL.path)", 73) }
    Output.record(["kind": "originals", "hotkeys": originals, "file": originalsURL.lastPathComponent])
    // From here a crash of this process too must not leave them disabled.
    for id in ids { hotkeyOriginals[id] = originals[String(id)] }
    defer { if !hotkeyOriginals.isEmpty { Output.record(["kind": "restore", "step": "defer", "readBack": restoreHotkeys()]) } }

    let child = Process()
    child.executableURL = Bundle.main.executableURL
    child.arguments = ["takeover-crash", "--child-apply-abort"]
    do { try child.run() } catch { fail("can't spawn the child: \(error)", 70) }
    child.waitUntilExit()
    let afterAbort = hotkeyState(ids)
    Output.record([
        "kind": "child", "status": child.terminationStatus, "reason": child.terminationReason == .uncaughtSignal ? "signal" : "exit",
        "afterAbort": afterAbort,
    ])
    Output.say("child ended by \(child.terminationReason == .uncaughtSignal ? "signal" : "exit") \(child.terminationStatus); 32/108 now \(afterAbort)")
    await pause(1000)
    let afterOneSecond = hotkeyState(ids)
    let mcKey = SymbolicHotKeys.value(108)
    let opensWhileLeftDisabled = if let mcKey { await postHotkeyChord(108, value: mcKey, step: "after-abort") } else { false }

    // Restore from the file, as a relaunched Transom would.
    let stored = (try? JSONSerialization.jsonObject(with: Data(contentsOf: originalsURL))) as? [String: Bool] ?? [:]
    var restoreOK = true
    for id in ids {
        guard let enabled = stored[String(id)] else {
            restoreOK = false
            continue
        }
        SymbolicHotKeys.setEnabled(id, enabled)
        if SymbolicHotKeys.isEnabled(id) == enabled { hotkeyOriginals[id] = nil } else { restoreOK = false }
    }
    let opensAfterRestore = if let mcKey { await postHotkeyChord(108, value: mcKey, step: "after-restore") } else { false }
    Output.record([
        "kind": "summary", "originals": originals, "afterAbort": afterAbort, "afterOneSecond": afterOneSecond,
        "missionControlKeyOpensWhileLeftDisabled": opensWhileLeftDisabled, "restoredFromFile": restoreOK,
        "missionControlKeyOpensAfterRestore": opensAfterRestore, "final": hotkeyState(ids),
    ])
    return restoreOK ? 0 : 1
}

// MARK: - Fixture driver

/// TransomFixtureApp next to this binary, driven over stdin/stdout; closing stdin quits it.
final class Fixture {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = ""
    private(set) var windows: [Int: UInt32] = [:]
    var pid: Int32 { process.processIdentifier }

    init(_ specs: [String]) throws {
        process.executableURL = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("TransomFixtureApp")
        process.arguments = specs.flatMap { ["--window", $0] }
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    /// Lines until one starts with `prefix` (or the timeout); window lines are kept as index → window ID.
    func read(until prefix: String, timeout: Double = 10) async -> Bool {
        let deadline = uptime() + timeout
        var bytes = [UInt8](repeating: 0, count: 4096)
        while uptime() < deadline {
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
            if count > 0 { buffer += String(decoding: bytes.prefix(count), as: UTF8.self) }
            while let newline = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<newline])
                buffer.removeSubrange(...newline)
                let fields = Dictionary(line.split(separator: " ").compactMap { part -> (String, String)? in
                    let pair = part.split(separator: "=", maxSplits: 1)
                    return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
                }, uniquingKeysWith: { a, _ in a })
                if line.hasPrefix("window "), let index = fields["index"].flatMap(Int.init), let id = fields["id"].flatMap(UInt32.init) {
                    windows[index] = id
                }
                if line.hasPrefix(prefix) { return true }
                if line.hasPrefix("error") { return false }
            }
            await pause(50)
        }
        return false
    }

    func command(_ text: String) async -> Bool {
        input.fileHandleForWriting.write(Data((text + "\n").utf8))
        return await read(until: "ok")
    }

    func quit() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

// MARK: - AX helpers

func axWindows(pid: Int32) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success
    else { return [] }
    return value as? [AXUIElement] ?? []
}

func windowID(_ element: AXUIElement) -> UInt32? {
    var id: CGWindowID = 0
    guard let function = AXWindowID.function, function(element, &id) == .success, id != 0 else { return nil }
    return id
}

/// The AX answer for a cached window element: "invalidElement" (-25202), "valid-listed", "valid-unlisted" or "error <n>".
func axAnswer(_ element: AXUIElement, pid: Int32) -> String {
    var role: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    switch error {
    case .success: return axWindows(pid: pid).contains { CFEqual($0, element) } ? "valid-listed" : "valid-unlisted"
    case .invalidUIElement: return "invalidElement"
    default: return "error \(error.rawValue)"
    }
}

func cgEntry(_ windowID: UInt32) -> [String: Any]? {
    windowList([.optionAll]).first { ($0[kCGWindowNumber as String] as? Int).map(UInt32.init) == windowID }
}

func cgFields(_ windowID: UInt32) -> [String: Any] {
    guard let entry = cgEntry(windowID) else { return ["inCG": false] }
    return ["inCG": true, "layer": entry[kCGWindowLayer as String] as? Int ?? -1, "onScreen": entry[kCGWindowIsOnscreen as String] as? Bool ?? false]
}

func spaceSet(_ windowID: UInt32) -> Any {
    guard let sets = SkyLightSpaces.spaces(of: [windowID]) else { return "lookup off" }
    guard let set = sets[windowID] else { return "call failed" }
    return set.sorted().map { NSNumber(value: $0) }
}

// MARK: - switch (VM only)

/// activeSpaceDidChange times on the uptime clock.
var spaceChanges: [Double] = []

func waitForSpaceChange(after start: Double, timeout: Double = 2) async -> Double? {
    while uptime() < start + timeout {
        if let t = spaceChanges.first(where: { $0 > start }) { return (t - start) * 1000 }
        await pause(5)
    }
    return nil
}

/// Posts ⌃→ or ⌃← (explicit flags, no fn first) and returns the latency in ms to activeSpaceDidChange, nil if none.
func switchSpace(right: Bool, step: String) async -> Double? {
    let keyCode = CGKeyCode(right ? kVK_RightArrow : kVK_LeftArrow)
    for flags: CGEventFlags in [.maskControl, [.maskControl, .maskSecondaryFn]] {
        let start = uptime()
        post(keyCode: keyCode, flags: flags)
        let latency = await waitForSpaceChange(after: start)
        Output.record([
            "kind": "switch", "step": step, "direction": right ? "right" : "left", "flags": String(flags.rawValue, radix: 16),
            "latencyMs": latency.map { $0 as Any } ?? NSNull(), "current": currentSpace().map { NSNumber(value: $0) } ?? NSNull(),
        ])
        Output.say("\(step): ⌃\(right ? "→" : "←") flags 0x\(String(flags.rawValue, radix: 16)) → \(latency.map { String(format: "%.0f ms", $0) } ?? "no Space change in 2 s")")
        if latency != nil {
            await pause(700)  // let the slide animation finish before the next chord
            return latency
        }
    }
    return nil
}

func currentSpace() -> UInt64? { SpacesProvider.snapshot()?.displays.first?.current }

func desktops() -> [UInt64] { SpacesProvider.snapshot()?.displays.first?.spaces.filter { $0.kind == .desktop }.map(\.id) ?? [] }

func focus(pid: Int32, window: AXUIElement) async -> Double? {
    let start = uptime()
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    NSRunningApplication(processIdentifier: pid)?.activate()
    while uptime() < start + 2 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return (uptime() - start) * 1000 }
        await pause(5)
    }
    return nil
}

let switchOnActivateKey = "AppleSpacesSwitchOnActivate" as CFString

func setSwitchOnActivate(_ value: CFPropertyList?) {
    CFPreferencesSetValue(switchOnActivateKey, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
}

func spaceSwitch() async -> Int32 {
    requireVM()
    let observer = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            let now = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
            MainActor.assumeIsolated { spaceChanges.append(now) }
        }
    Run.onFinish("observer") { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    let order = desktops()
    guard order.count >= 2 else {
        Output.record(["kind": "summary", "error": "needs two desktops", "desktops": order.map { NSNumber(value: $0) }])
        return 1
    }
    // Start on the first desktop.
    while let current = currentSpace(), current != order[0], await switchSpace(right: false, step: "to-first") != nil {}
    Run.onFinish("back to the first desktop") {
        // A blocking best effort: one ⌃← per desktop. The fn bit is needed: without it a posted arrow chord switches nothing (06-SPIKE).
        for _ in 1..<order.count { post(keyCode: CGKeyCode(kVK_LeftArrow), flags: [.maskControl, .maskSecondaryFn]); usleep(800_000) }
    }

    let right = await switchSpace(right: true, step: "chord")
    let left = await switchSpace(right: false, step: "chord")

    // A fixture window on the second desktop, then AX before/after switching to it.
    _ = await switchSpace(right: true, step: "place-fixture")
    let fixture: Fixture
    do { fixture = try Fixture(["standard"]) } catch { fail("can't launch TransomFixtureApp: \(error)", 70) }
    Run.onFinish("fixture") { fixture.quit() }
    guard await fixture.read(until: "window index=0"), let fixtureWindow = fixture.windows[0] else {
        Output.record(["kind": "summary", "error": "fixture reported no window"])
        return 1
    }
    await pause(500)
    let fixtureSpaces = spaceSet(fixtureWindow)
    _ = await switchSpace(right: false, step: "leave-fixture")
    let listedBefore = axWindows(pid: fixture.pid).compactMap(windowID).contains(fixtureWindow)
    let toFixture = await switchSpace(right: true, step: "to-fixture")
    let listedAfter = axWindows(pid: fixture.pid).compactMap(windowID).contains(fixtureWindow)
    var focusMs: Double?
    if let element = axWindows(pid: fixture.pid).first(where: { windowID($0) == fixtureWindow }) {
        focusMs = await focus(pid: fixture.pid, window: element)
    }
    Output.record([
        "kind": "ax-after-switch", "fixtureWindow": fixtureWindow, "fixtureSpaces": fixtureSpaces, "axListedBefore": listedBefore,
        "axListedAfter": listedAfter, "focusMs": focusMs.map { $0 as Any } ?? NSNull(),
    ])
    Output.say("fixture window \(fixtureWindow) on Space \(fixtureSpaces): AX lists it before switch \(listedBefore), after \(listedAfter); focus \(focusMs.map { String(format: "%.0f ms", $0) } ?? "not frontmost in 2 s")")

    // Activation-only run with AppleSpacesSwitchOnActivate = 1, restored afterwards.
    _ = await switchSpace(right: false, step: "leave-fixture-2")
    let original = CFPreferencesCopyValue(switchOnActivateKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    Run.onFinish("AppleSpacesSwitchOnActivate") { setSwitchOnActivate(original) }
    defer { setSwitchOnActivate(original) }
    var activation: [String: Any] = ["original": original.map { "\($0)" } ?? "absent"]
    for setting in [0, 1] {
        setSwitchOnActivate(NSNumber(value: setting))
        await pause(500)
        if currentSpace() != order[0] { _ = await switchSpace(right: false, step: "reset") }
        let start = uptime()
        NSRunningApplication(processIdentifier: fixture.pid)?.activate()
        let latency = await waitForSpaceChange(after: start)
        activation[String(setting)] = ["latencyMs": latency.map { $0 as Any } ?? NSNull(), "current": currentSpace().map { NSNumber(value: $0) } ?? NSNull()] as [String: Any]
        Output.say("AppleSpacesSwitchOnActivate \(setting): activating the fixture → \(latency.map { String(format: "Space change after %.0f ms", $0) } ?? "no Space change in 2 s")")
        await pause(700)
        // Hand activation back so the next run starts from the first desktop.
        NSRunningApplication.current.activate()
    }
    setSwitchOnActivate(original)
    Output.record([
        "kind": "summary", "desktops": order.map { NSNumber(value: $0) }, "chordRightMs": right.map { $0 as Any } ?? NSNull(),
        "chordLeftMs": left.map { $0 as Any } ?? NSNull(), "toFixtureMs": toFixture.map { $0 as Any } ?? NSNull(),
        "axListedBefore": listedBefore, "axListedAfter": listedAfter, "focusMs": focusMs.map { $0 as Any } ?? NSNull(),
        "activationOnly": activation,
        "switchOnActivateRestored": (CFPreferencesCopyValue(switchOnActivateKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)).map { "\($0)" } ?? "absent",
    ])
    return 0
}

// MARK: - ghost (VM only)

func pressMenuItem(pid: Int32, menu: String, item: String) -> Bool {
    func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }
    func title(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        return value as? String
    }
    var bar: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXMenuBarAttribute as CFString, &bar) == .success,
          let menuBar = bar, let top = children(menuBar as! AXUIElement).first(where: { title($0) == menu }),
          let list = children(top).first, let entry = children(list).first(where: { title($0) == item })
    else { return false }
    return AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success
}

func ghost() async -> Int32 {
    requireVM()
    // Space sets of a minimised window, a ⌘H-hidden app's windows and a hidden native tab.
    var hidden: [String: Any] = [:]
    do {
        let fixture = try Fixture(["standard", "standard", "tabs:2"])
        Run.onFinish("fixture") { fixture.quit() }
        if await fixture.read(until: "ready") {
            // The window lines follow the ready line; drain them.
            _ = await fixture.read(until: "never", timeout: 1.5)
            let ids = fixture.windows.sorted { $0.key < $1.key }.map(\.value)
            func sets() -> [String: Any] { Dictionary(uniqueKeysWithValues: ids.map { (String($0), spaceSet($0)) }) }
            hidden["windows"] = ids
            hidden["shown"] = sets()
            _ = await fixture.command("minimize 0")
            await pause(800)
            hidden["minimised0"] = ["window": ids.first ?? 0, "spaces": ids.first.map(spaceSet) ?? NSNull(), "cg": ids.first.map(cgFields) ?? [:]] as [String: Any]
            _ = await fixture.command("deminimize 0")
            _ = await fixture.command("hide-app")
            await pause(800)
            hidden["hiddenApp"] = sets()
            _ = await fixture.command("unhide-app")
            var line = hidden
            line["kind"] = "hidden-sets"
            line["note"] = "the last two windows are one tab group; the unselected tab is the hidden tab"
            Output.record(line)
            Output.say("fixture Space sets: \(hidden)")
        }
        fixture.quit()
    } catch {
        Output.record(["kind": "hidden-sets", "error": "\(error)"])
    }

    // Safari: open a window through its own menu (AX), close it with its close button, then watch the ID for 30 s.
    let safariID = "com.apple.Safari"
    let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: safariID).isEmpty
    if !wasRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safariID) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        Run.onFinish("quit Safari (launched here)") {
            NSRunningApplication.runningApplications(withBundleIdentifier: safariID).forEach { $0.terminate() }
        }
    }
    await pause(3000)
    guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: safariID).first else {
        Output.record(["kind": "summary", "error": "Safari did not start"])
        return 1
    }
    let pid = safari.processIdentifier
    let before = Set(axWindows(pid: pid).compactMap(windowID))
    guard pressMenuItem(pid: pid, menu: "File", item: "New Window") else {
        Output.record(["kind": "summary", "error": "File ▸ New Window not pressable", "safariWasRunning": wasRunning])
        return 1
    }
    await pause(2000)
    guard let element = axWindows(pid: pid).first(where: { windowID($0).map { !before.contains($0) } ?? false }),
          let ghostID = windowID(element)
    else {
        Output.record(["kind": "summary", "error": "no new Safari window found"])
        return 1
    }
    Output.record(["kind": "ghost-open", "window": ghostID, "spaces": spaceSet(ghostID), "cg": cgFields(ghostID)])
    // The UAT ghost had been open a while; give the window time to load its start page before closing it.
    await pause(8000)
    var close: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &close)
    guard let closeButton = close, AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString) == .success else {
        Output.record(["kind": "summary", "error": "close button not pressable", "window": ghostID])
        return 1
    }
    let closedAt = uptime()
    var answers: [String: Int] = [:]
    var lastInCG: Double?
    for second in 0..<30 {
        let answer = axAnswer(element, pid: pid)
        let cg = cgFields(ghostID)
        let spaces = spaceSet(ghostID)
        answers[answer, default: 0] += 1
        if cg["inCG"] as? Bool == true { lastInCG = uptime() - closedAt }
        var line = cg
        line.merge(["kind": "ghost", "second": second, "window": ghostID, "ax": answer, "spaces": spaces]) { _, new in new }
        Output.record(line)
        Output.say("+\(second) s: AX \(answer) · CG \(cg) · Spaces \(spaces)")
        await pause(1000)
    }
    Output.record([
        "kind": "summary", "window": ghostID, "safariWasRunning": wasRunning, "axAnswers": answers,
        "lastSeenInCGSeconds": lastInCG.map { $0 as Any } ?? NSNull(), "hidden": hidden,
    ])
    return 0
}

// MARK: - swipe-check (user, host only)

/// One type-30 event, copied off the tap callback.
nonisolated struct SwipeEvent: @unchecked Sendable {
    let t: Double
    let integers: [Int: Int64]
    let doubles: [Int: Double]
    let consumed: Bool
}

nonisolated final class SwipeBox: @unchecked Sendable {
    let events = OSAllocatedUnfairLock(initialState: [SwipeEvent]())
    /// Phase 2: consume an event whose `field` value is in `values`.
    let rule = OSAllocatedUnfairLock<(field: Int, values: Set<Int64>)?>(initialState: nil)
    var port: CFMachPort?

    static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let box = Unmanaged<SwipeBox>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == GestureEventFields.dockControlType else { return Unmanaged.passUnretained(event) }
        var integers: [Int: Int64] = [:]
        var doubles: [Int: Double] = [:]
        for raw in UInt32(0)..<256 {
            guard let field = CGEventField(rawValue: raw) else { continue }
            let integer = event.getIntegerValueField(field)
            if integer != 0 { integers[Int(raw)] = integer }
            let double = event.getDoubleValueField(field)
            if double != 0, double != Double(integer) { doubles[Int(raw)] = double }
        }
        let rule = box.rule.withLock { $0 }
        let consume = rule.map { integers[$0.field].map($0.values.contains) ?? false } ?? false
        let record = SwipeEvent(t: Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9, integers: integers, doubles: doubles, consumed: consume)
        box.events.withLock { $0.append(record) }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}

/// The lowest field whose values on swipe-up events are few (≤ 3) and never seen on horizontal ones.
func separatingField(up: [SwipeEvent], horizontal: [SwipeEvent]) -> (field: Int, values: Set<Int64>)? {
    guard !up.isEmpty, !horizontal.isEmpty else { return nil }
    let fields = Set(up.flatMap(\.integers.keys)).union(horizontal.flatMap(\.integers.keys)).sorted()
    for field in fields {
        let upValues = Set(up.map { $0.integers[field] ?? 0 })
        let horizontalValues = Set(horizontal.map { $0.integers[field] ?? 0 })
        if upValues.count <= 3, upValues.isDisjoint(with: horizontalValues) { return (field, upValues) }
    }
    return nil
}

func swipeCheck() async -> Int32 {
    if ProcessInfo.processInfo.environment["SSH_CONNECTION"] != nil || !flags.contains("--i-am-on-the-host") {
        FileHandle.standardError.write(Data("swipe-check is run by you on your Mac: add --i-am-on-the-host, and not over SSH.\n".utf8))
        return 3
    }
    guard AXIsProcessTrusted() else {
        FileHandle.standardError.write(Data("""
            swipe-check needs Accessibility for your terminal app.
            Turn it on in System Settings ▸ Privacy & Security ▸ Accessibility, run this again, and turn it off when you're done.

            """.utf8))
        return 2
    }
    let box = SwipeBox()
    guard let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: CGEventMask(1) << CGEventMask(GestureEventFields.dockControlType), callback: SwipeBox.callback,
        userInfo: Unmanaged.passUnretained(box).toOpaque())
    else {
        Output.record(["kind": "summary", "error": "tap refused"])
        return 2
    }
    box.port = port
    let source = CFMachPortCreateRunLoopSource(nil, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    Run.onFinish("remove the tap") {
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(port)
    }

    // Phase 1: listen only (the rule is nil, nothing is consumed), prompted directions.
    var windows: [(direction: String, start: Double, end: Double)] = []
    for direction in ["up", "left", "right"] {
        Output.say("Phase 1: swipe \(direction) with four fingers now (3 s)")
        let start = uptime()
        await pause(3300)
        windows.append((direction, start, uptime()))
    }
    let phase1 = box.events.withLock { events in let copy = events; events.removeAll(); return copy }
    func events(_ direction: String) -> [SwipeEvent] {
        guard let window = windows.first(where: { $0.direction == direction }) else { return [] }
        return phase1.filter { $0.t >= window.start && $0.t < window.end }
    }
    for event in phase1 {
        let direction = windows.first { event.t >= $0.start && event.t < $0.end }?.direction ?? "none"
        Output.record([
            "kind": "swipe-event", "phase": 1, "direction": direction,
            "integers": Dictionary(uniqueKeysWithValues: event.integers.map { (String($0.key), $0.value) }),
            "doubles": Dictionary(uniqueKeysWithValues: event.doubles.map { (String($0.key), $0.value) }),
        ])
    }
    let rule = separatingField(up: events("up"), horizontal: events("left") + events("right"))
    Output.say("Phase 1: \(phase1.count) Dock-control events; separating field: \(rule.map { "\($0.field) = \($0.values.sorted())" } ?? "none")")
    guard let rule else {
        Output.record(["kind": "summary", "phase1Events": phase1.count, "separatingField": NSNull(), "phase2": "skipped: no field separates swipe-up from horizontal swipes"])
        return 0
    }

    // Phase 2: consume only events the rule calls swipe-up.
    box.rule.withLock { $0 = rule }
    var counts: [String: [String: Int]] = [:]
    for direction in ["up", "left", "right", "up"] {
        Output.say("Phase 2: swipe \(direction) with four fingers now (4 s); swipe-up should do nothing, left/right should switch Spaces")
        let start = uptime()
        await pause(4300)
        let seen = box.events.withLock { events in let copy = events; events.removeAll(); return copy }.filter { $0.t >= start }
        counts[direction, default: [:]]["consumed", default: 0] += seen.filter(\.consumed).count
        counts[direction, default: [:]]["passed", default: 0] += seen.filter { !$0.consumed }.count
        for event in seen {
            Output.record(["kind": "swipe-event", "phase": 2, "direction": direction, "consumed": event.consumed,
                           "field": event.integers[rule.field] ?? 0])
        }
    }
    box.rule.withLock { $0 = nil }
    Output.record([
        "kind": "summary", "phase1Events": phase1.count, "separatingField": rule.field, "upValues": rule.values.sorted(),
        "phase2Counts": counts, "note": "the verdict needs your report: did swipe-up do nothing while left/right switched Spaces?",
    ])
    Output.say("Phase 2 done. Tell the agent whether swipe-up did nothing and whether left/right still switched Spaces.")
    return 0
}

// MARK: - Main

if flags.contains("--child-apply-abort") {
    requireVM()
    childApplyAbort()
}

// NSScreen.screensHaveSeparateSpaces reads false until NSApplication exists (06-RESEARCH Pitfall 5).
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
Output.open()
Output.say("transom-spaces-spike \(subcommand) · macOS \(osVersion()) · \(formatted(launchDate, "yyyy-MM-dd HH:mm:ss")) · up to \(seconds) s")
Output.say("Label: \(label.isEmpty ? "–" : label) · recording to \(outPath)")

// Every stop path restores whatever this process changed (T-06-01).
Run.onFinish("restore hotkeys") {
    guard !hotkeyOriginals.isEmpty else { return }
    Output.record(["kind": "restore", "step": "finish", "readBack": restoreHotkeys()])
}
var signalSources: [any DispatchSourceSignal] = []
for number in [SIGINT, SIGHUP, SIGTERM] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { Run.finish(130, reason: "signal \(number)") } }
    source.resume()
    signalSources.append(source)
}
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
    MainActor.assumeIsolated { Run.finish(subcommand == "takeover-crash" ? 1 : 0, reason: "timeout after \(seconds) s") }
}

DispatchQueue.main.async {
    Task {
        let status: Int32
        switch subcommand {
        case "spaces-dump": status = spacesDump()
        case "hotkeys": status = await hotkeys()
        case "takeover-crash": status = await takeoverCrash()
        case "switch": status = await spaceSwitch()
        case "ghost": status = await ghost()
        default: status = await swipeCheck()
        }
        Run.finish(status)
    }
}
application.run()
