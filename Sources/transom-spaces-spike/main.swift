import AppKit
import Darwin
import Foundation
import TransomEngine
import TransomMac
import TransomPrivate

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

// MARK: - Main

// NSScreen.screensHaveSeparateSpaces reads false until NSApplication exists (06-RESEARCH Pitfall 5).
_ = NSApplication.shared
Output.open()
Output.say("transom-spaces-spike \(subcommand) · macOS \(osVersion()) · \(formatted(launchDate, "yyyy-MM-dd HH:mm:ss")) · up to \(seconds) s")
Output.say("Label: \(label.isEmpty ? "–" : label) · recording to \(outPath)")

let status: Int32
switch subcommand {
case "spaces-dump": status = spacesDump()
default:
    Output.say("\(subcommand): not built yet")
    status = 64
}
try? Output.handle?.close()
exit(status)
