import AppKit
import ApplicationServices
import Foundation
import TransomEngine
import TransomMac

// Records one window of a running app as a redacted, labelled corpus case (D-07, T-02-08).
// The label always comes from --label, never from the classifier (Pitfall 6).

let usage = """
    usage: transom-dump --app <bundleID> --list
           transom-dump --app <bundleID> --window <index> --label <dockable|neverDock[:<reason>]|notAWindow>
                     --family <native|electron|java|office> --case <name> [--out <dir>]
    """

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("transom-dump: \(message)\n".utf8))
    exit(code)
}

var options: [String: String] = [:]
var list = false
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--list":
        list = true
    case "--app", "--window", "--label", "--family", "--case", "--out":
        guard let value = arguments.popFirst() else { fail("\(argument) needs a value\n\(usage)", 64) }
        options[argument] = value
    default:
        fail("unknown argument \(argument)\n\(usage)", 64)
    }
}
guard let bundleID = options["--app"] else { fail(usage, 64) }

/// The parsed label, checked before any AX call so a bad command line never reads a window.
struct Capture {
    let index: Int
    let expected: CorpusCase.Expected
    let family: String
    let caseName: String
}

func parseCapture() -> Capture {
    guard let label = options["--label"] else { fail("--label is required: the label is never inferred\n\(usage)", 64) }
    guard let index = options["--window"].flatMap({ Int($0) }), index >= 0 else { fail("--window <index> is required\n\(usage)", 64) }
    guard let family = options["--family"], ["native", "electron", "java", "office"].contains(family) else {
        fail("--family must be native, electron, java or office", 64)
    }
    // The case name becomes a file name, so it is restricted to a safe alphabet.
    guard let caseName = options["--case"], !caseName.isEmpty,
          caseName.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") })
    else { fail("--case must be lower-case letters, digits and _", 64) }
    let parts = label.split(separator: ":", maxSplits: 1).map(String.init)
    let kind = parts[0]
    let reason = parts.count == 2 ? parts[1] : nil
    guard ["dockable", "neverDock", "notAWindow"].contains(kind), reason == nil || kind == "neverDock" else {
        fail("--label must be dockable, neverDock[:<reason>] or notAWindow", 64)
    }
    if let reason, NeverDockReason(rawValue: reason) == nil {
        fail("unknown reason \(reason); one of \(NeverDockReason.allCases.map(\.rawValue).joined(separator: ", "))", 64)
    }
    return Capture(index: index, expected: .init(kind: kind, reason: reason, confirmedBy: "executor-proposed"), family: family, caseName: caseName)
}

let capture = list ? nil : parseCapture()

guard AXIsProcessTrusted() else { fail("this process has no Accessibility grant; run it from a trusted terminal", 3) }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    fail("\(bundleID) is not running", 66)
}
let observation = AXSnapshotReader.observeApp(pid: app.processIdentifier, bundleID: bundleID)
if let failure = observation.listFailure { fail("AXWindows failed: \(failure)", 69) }
guard let cgList = CGWindowList.snapshot() else { fail("the CG window list could not be read", 69) }
let cgWindows = Dictionary(cgList.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

/// The snapshot with its CG fact merged by window ID, exactly as WindowTracker sees it.
func snapshot(_ window: WindowObservation) -> WindowSnapshot? {
    guard case .success(var snapshot) = window.read else { return nil }
    if let id = window.windowID, let cg = cgWindows[id] {
        snapshot.cg = CGWindowFact(layer: cg.layer, onScreen: cg.onScreen, alpha: cg.alpha)
    }
    return snapshot
}

guard let capture else {
    // Titles are never printed.
    for (index, window) in observation.windows.enumerated() {
        guard let s = snapshot(window) else {
            print("\(index) read failed: \(window.read)")
            continue
        }
        let frame = s.frame.map { "\(Int($0.x)),\(Int($0.y)),\(Int($0.width)),\(Int($0.height))" } ?? "-"
        print("\(index) role=\(s.role ?? "-") subrole=\(s.subrole ?? "-") frame=\(frame) layer=\(s.cg.map { String($0.layer) } ?? "-")")
    }
    exit(0)
}

guard observation.windows.indices.contains(capture.index), var window = snapshot(observation.windows[capture.index]) else {
    fail("window \(capture.index) does not exist or could not be read; see --list", 65)
}
// Keep AXIdentifier only for the known developer identifiers; anything else may name a document.
if let identifier = window.identifier, !ClassifierOverrides.standard.neverDockIdentifiers.contains(identifier) {
    window.identifier = nil
}
let version = ProcessInfo.processInfo.operatingSystemVersion
let policy: String =
    switch app.activationPolicy {
    case .regular: "regular"
    case .accessory: "accessory"
    case .prohibited: "prohibited"
    @unknown default: "unknown"
    }
let corpusCase = CorpusCase(
    caseName: capture.caseName,
    capturedOn: .init(
        macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
        appVersion: app.bundleURL.flatMap { Bundle(url: $0) }?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        date: Date.now.formatted(.iso8601.year().month().day())
    ),
    app: .init(bundleID: bundleID, family: capture.family, activationPolicy: policy, hidden: observation.appHidden),
    window: window,
    title: .init(redacted: true, length: observation.windows[capture.index].title.count),
    expected: capture.expected
)

/// Sources/transom-dump/main.swift -> repo root.
let defaultOut = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/TransomEngineTests/Fixtures/AXDumps")
let directory = options["--out"].map { URL(fileURLWithPath: $0) } ?? defaultOut
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
do {
    let url = directory.appendingPathComponent("\(capture.caseName).json")
    try (encoder.encode(corpusCase) + Data("\n".utf8)).write(to: url)
    print(url.path)
} catch {
    fail("could not write the case: \(error)", 73)
}
