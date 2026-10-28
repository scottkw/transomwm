# Phase 2: Window Control - Pattern Map

**Mapped:** 2026-10-24
**Files analyzed:** 40 (new + modified, from 02-CONTEXT.md, 02-RESEARCH.md "Recommended Project Structure" / Wave 0, 02-UI-SPEC.md)
**Analogs found:** 17 / 40 have an in-repo analog (mostly convention-level). Every PanePrivate / PaneMac / PaneApp / fixture / XcodeGen file is new ground. Use the RESEARCH.md verified skeletons for those.

All analog paths below are git-tracked (checked with `git ls-files`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Package.swift` (modify) | config | n/a | itself (lines 1-17) | exact |
| `Sources/PaneEngine/WindowSystem.swift` (modify) | protocol + value types | event-driven / request-response | itself | exact |
| `Sources/PaneEngine/WindowSnapshot.swift` | model (Codable value) | transform | `Sources/PaneModel/Geometry.swift`, `IDs.swift` (Codable/Sendable structs) | role-match |
| `Sources/PaneEngine/Classifier.swift` | utility (pure fn) | transform | `Sources/PaneModel/Resolve.swift` (pure fn over values, typed throws) | role-match |
| `Sources/PaneEngine/TabGroupTracker.swift` | service (pure state) | transform | `Sources/PaneModel/DesktopLayer.swift` (mutating value with validated edits) | role-match |
| `Sources/PaneEngine/CloseRule.swift` | utility (decision table) | transform | `Resolve.swift` | partial |
| `Sources/PaneEngine/MinimumSizeLearner.swift` | utility | transform | `Resolve.swift` lines 33-34 (finite/range validation) | partial |
| `Sources/PaneEngine/Coordinates.swift` | utility (math) | transform | `Sources/PaneModel/Geometry.swift` (`Rect`, `maxCoordinate`) | partial |
| `Sources/PaneEngine/PermissionReducer.swift` | store/reducer | event-driven | none (enum state machines don't exist yet) | none |
| `Sources/PaneEngine/LifecycleSync.swift` | service | event-driven | consumer of `World.apply` / `World.undo` (`World.swift` 121-160) | partial |
| `Sources/PanePrivate/AXWindowID.swift` | private-API shim | request-response | none | none (RESEARCH Pattern 8) |
| `Sources/PanePrivate/Capabilities.swift` | config/registry | n/a | none | none (RESEARCH Pattern 8) |
| `Sources/PaneMac/AX/AXAppThread.swift` | service (thread) | event-driven | none | none (RESEARCH Pattern 1) |
| `Sources/PaneMac/AX/AXSnapshotReader.swift` | adapter | transform | none | none |
| `Sources/PaneMac/AX/AppRegistry.swift` | service | event-driven | none | none |
| `Sources/PaneMac/AXWindowSystem.swift` | service (protocol impl) | event-driven | `WindowSystem.swift` protocol + RESEARCH "WindowSystem conformances" | role-match (protocol only) |
| `Sources/PaneMac/CGWindowList.swift` | adapter | request-response | none | none |
| `Sources/PaneMac/Displays.swift` | adapter | request-response | `DisplayInfo` in `WindowSystem.swift` 4-16 | partial |
| `Sources/PaneMac/FallbackMatcher.swift` | utility | transform | none | none |
| `Sources/PaneMac/SessionGate.swift` | service | event-driven | none | none |
| `Sources/PaneMac/Permission/*` (probe, tccutil runner, SetupView) | service + component | request-response | `Tests/PaneModelTests/NoAppKitTests.swift` 11-21 (`Process` run + exit status) for the tccutil runner only | partial |
| `Sources/PaneMac/Exclusions.swift` | store | CRUD (UserDefaults) | none | none |
| `Sources/PaneMac/MinimumHintsStore.swift` | store | file-I/O | `Sources/PaneModel/Persistence.swift` 1-70 | role-match |
| `Sources/PaneMac/Shell/*` (StatusItem, menu, TrackedWindowsView) | component | event-driven | none | none (UI-SPEC is the contract) |
| `Sources/PaneApp/main.swift` | entry point | n/a | none | none |
| `Sources/pane-dump/main.swift` | CLI tool | file-I/O | `Persistence.swift` (sorted-key JSON encode) | partial |
| `Sources/PaneFixtureApp/main.swift` | test fixture app | n/a | none | none |
| `Sources/PaneTestSupport/FakeWindowSystem.swift` | test support (actor) | event-driven | `Tests/PaneModelTests/SkeletonTests.swift` 5-8 (shared `makeWindow` helper) + RESEARCH skeleton | partial |
| `Tests/PaneEngineTests/*Tests.swift` (Classifier corpus, CloseRule, TabGroup, Learner, Coordinates, PermissionReducer, LifecycleSync, Fake scenarios) | test | n/a | `Tests/PaneModelTests/LifecycleTests.swift`, `SkeletonTests.swift` | exact (style) |
| `Tests/PaneEngineTests/Fixtures/AXDumps/*.json` | test fixture | file-I/O | located like `NoAppKitTests.swift` 7-9 (`#filePath`) | partial |
| `Tests/PaneMacIntegrationTests/*` | integration test | n/a | `NoAppKitTests.swift` (Process launch, repo root) | partial |
| `Tests/PaneModelTests/NoAppKitTests.swift` (possibly extend) | test | n/a | itself | exact |
| `scripts/check-no-appkit.sh` (unchanged default dirs; must keep passing) | script | n/a | itself | exact |
| `scripts/generate.sh`, `scripts/run-debug.sh` | script | n/a | `scripts/check-no-appkit.sh` 1-8 (header + `set -euo pipefail` + repo root) | role-match |
| `xcode/project.yml` | config | n/a | none | none (RESEARCH "XcodeGen project.yml") |
| entitlements / Info.plist keys (via project.yml) | config | n/a | none | none |
| `.gitignore` (modify) | config | n/a | itself | exact |
| `.github/workflows/ci.yml` (modify, if adding steps) | config | n/a | itself | exact |

## Pattern Assignments

### `Package.swift` (config)

**Analog:** `Package.swift` (whole file, 17 lines)
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pane",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaneModel", targets: ["PaneModel"]),
        .library(name: "PaneEngine", targets: ["PaneEngine"]),
    ],
    targets: [
        .target(name: "PaneModel"),
        .target(name: "PaneEngine", dependencies: ["PaneModel"]),
        .testTarget(name: "PaneModelTests", dependencies: ["PaneModel"]),
    ],
    swiftLanguageModes: [.v6]
)
```
Notes for the planner:
- The current targets have **no** `swiftSettings`. CLAUDE.md asks for `NonisolatedNonsendingByDefault` + `ExistentialAny` on Model/Engine. RESEARCH says PaneEngine must **not** get `.defaultIsolation(MainActor.self)` (Anti-Patterns). Adding upcoming features to existing targets is optional, so don't change PaneModel settings casually.
- New: `.target(name: "PanePrivate")` (nonisolated, no defaultIsolation); `.target(name: "PaneMac", dependencies: ["PaneEngine", "PanePrivate"], swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")])` plus a `.library(name: "PaneMac")` product for XcodeGen; `.executableTarget` for `PaneApp`, `pane-dump`, `PaneFixtureApp`; `.target(name: "PaneTestSupport")` under `Sources/`; `.testTarget` for `PaneEngineTests` and `PaneMacIntegrationTests`.
- Keep `swiftLanguageModes: [.v6]` and tools-version 6.2.

### `Sources/PaneEngine/WindowSystem.swift` (modify)

**Analog:** itself. Keep the conventions:
- `import PaneModel` only (no Foundation needed today, never AppKit).
- Every public value type is `public struct X: Equatable, Sendable` with an explicit memberwise `public init` (lines 4-16, 19-31).
- Doc comment `///` on every type; coordinate rule stated once (lines 67-71).
- Protocol shape (lines 72-76): `public protocol WindowSystem: AnyObject, Sendable { var events: AsyncStream<WindowEvent> { get }; func inventory() async -> WindowInventory; func perform(_ commands: [WindowCommand]) async }`.
Revisions from RESEARCH: `WindowInfo` gains `visibleMemberID`, `isExcluded`, classification, tab count; `WindowEvent` gains `.appResponsiveness(pid:degraded:)` and `.frameApplied(ref, requested:, actual:)`. Add cases to the existing enums; don't make a parallel enum.

### PaneEngine pure types (`WindowSnapshot`, `Classifier`, `TabGroupTracker`, `CloseRule`, `MinimumSizeLearner`, `Coordinates`, `PermissionReducer`, `LifecycleSync`)

**Analogs:** `Sources/PaneModel/Geometry.swift`, `IDs.swift`, `Resolve.swift`, `LayoutTree.swift`, `World.swift`

**Value-type declaration** (`Geometry.swift` 7, 17, 27; `IDs.swift` 57-71):
```swift
public struct Rect: Codable, Equatable, Hashable, Sendable {
...
public struct WindowIdentity: Hashable, Comparable, Codable, Sendable {
    public var windowID: UInt32
    public var pid: Int32
    public var bundleID: String

    public init(windowID: UInt32, pid: Int32, bundleID: String) { ... }
```
`WindowSnapshot` follows this: `Codable, Equatable, Sendable`, explicit `public init`, `schemaVersion` field like the corpus format.

**Raw-value enums** (`Geometry.swift` 70-74, `IDs.swift` WindowState): `public enum Edge: String, Codable, Sendable, CaseIterable`. Use for `NeverDockReason`, `Capability`, permission states.

**Pure function with validation + typed throws** (`Resolve.swift` 31-34):
```swift
public func resolve(_ tree: LayoutTree, in area: Rect, mins: [WindowRef: Size], gap: Double) throws(LayoutError) -> Resolution {
    guard gap.isFinite, gap >= 0, gap <= Geometry.maxCoordinate else { throw .invalidGap }
    let isValid = { (s: Size) in [s.width, s.height].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= Geometry.maxCoordinate } }
```
Copy this finite/range check for `MinimumSizeLearner` and the hints loader. `Geometry.maxCoordinate = 1_000_000` (Geometry.swift 66).

**Error enums** (`LayoutTree.swift` 10-29): `public enum LayoutError: Error, Equatable, Sendable` with associated values, and a doc line "Messages name ... identities only, never window titles". New engine errors follow the same shape and the same no-titles rule.

**Lifecycle contract** (`World.swift` 121, 147). `LifecycleSync` must call exactly these:
```swift
public mutating func apply(_ state: WindowState, for window: WindowRef, on key: DeskKey, history: inout UndoHistory) throws(LayoutError)
@discardableResult
public mutating func undo(_ key: DeskKey, history: inout UndoHistory) throws(LayoutError) -> [WindowRef]?
```
`.closed` ignores `key`. The `undo` return list must be re-queried and re-reported through `apply` (doc comment lines 138-146).

**Logging-safe identity:** `WindowRef.description` = `"window \(windowID) pid \(pid) \(bundleID)"` (IDs.swift ~100). Log refs with that, never `titleHint`.

### `Sources/PaneMac/MinimumHintsStore.swift` (store, file-I/O)

**Analog:** `Sources/PaneModel/Persistence.swift` lines 1-70

**Error type** (lines 3-10):
```swift
public enum PersistenceError: Error, Equatable, Sendable {
    case corrupt(String)
    case newerVersion(found: Int, supported: Int)
    ...
    case tooLarge(bytes: Int, limit: Int)
    case encodingFailed(String)
}
```
**Deterministic encode** (lines 14-22): `JSONEncoder` with `outputFormatting = [.sortedKeys]`, typed `throws(PersistenceError)`.
**Validated decode** (lines 25-47): size cap first (`maxEncodedBytes`), `VersionProbe: Decodable { let schemaVersion: Int }`, reject newer versions, then full decode. Copy this order for `min-size-hints.json`, sized much smaller (RESEARCH V5: schema version, finite, 0...maxCoordinate, size cap). The same decode shape fits the pane-dump corpus loader in tests.

### `Sources/PaneMac/Permission/` tccutil runner (+ integration tests launching PaneFixtureApp)

**Analog:** `Tests/PaneModelTests/NoAppKitTests.swift` lines 11-21
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["scripts/check-no-appkit.sh"] + arguments
process.currentDirectoryURL = Self.repoRoot
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
try process.run()
process.waitUntilExit()
return process.terminationStatus
```
For tccutil: `executableURL = /usr/bin/tccutil`, fixed argv `["reset", "Accessibility", bundleID]`, surface `terminationStatus` (64 = unknown bundle ID) to the reducer and callout E. Don't block main on `waitUntilExit`. Run it off main or use `terminationHandler`.

### `Sources/PaneTestSupport/FakeWindowSystem.swift`

**Analog:** shared helper convention in `Tests/PaneModelTests/SkeletonTests.swift` 5-8:
```swift
/// Shared test helper: a window of one fake app, identified by `id`.
func makeWindow(_ id: UInt32, title: String = "") -> WindowRef {
    WindowRef(identity: WindowIdentity(windowID: id, pid: 100, bundleID: "com.example.app"), titleHint: title)
}
```
Its body comes from RESEARCH "WindowSystem conformances": a `public actor FakeWindowSystem: WindowSystem` with `public nonisolated let events`, `AsyncStream.makeStream(bufferingPolicy: .unbounded)`, a `performed` log, and inventory sorted by `identity` for deterministic tests. It is a library target, so helpers need to be `public` (the current `makeWindow` is internal to its test target). Add scenario hooks: hang, slow, ID churn, refusing sizes, lock blanking.

### `Tests/PaneEngineTests/*` (test)

**Analogs:** `Tests/PaneModelTests/LifecycleTests.swift` 1-50, `SkeletonTests.swift`
- Header: `import Foundation`, `import Testing`, `@testable import PaneEngine` (+ `import PaneModel`).
- File-private fixtures as `private let` / `private func` at the top (LifecycleTests 5-27).
- `@Suite struct XTests { ... }` with sentence-style test names (`aHiddenWindowKeepsItsSlotAndComesBackToTheSameRects`).
- Parameterised tests: `@Test(arguments: [WindowState.absent, .fullscreen])`. Use this for CloseRule table rows, Coordinates vectors and corpus files.
- `#expect(...)` and `try #require(...)` for optionals.
- Test functions `throws`. No XCTest.

**Corpus fixture location** (`NoAppKitTests.swift` 7-9):
```swift
static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
```
Locate `Tests/PaneEngineTests/Fixtures/AXDumps/*.json` this way rather than with SwiftPM resources or `Bundle` (RESEARCH: `Bundle.allBundles` has no `.xctest`).

**Trusted-only suites (PaneMacIntegrationTests):** no analog. Use `@Suite(.enabled(if: AXIsProcessTrusted()))` per RESEARCH.

### Scripts (`scripts/generate.sh`, `scripts/run-debug.sh`)

**Analog:** `scripts/check-no-appkit.sh` lines 1-8
```bash
#!/usr/bin/env bash
# Fails if PaneModel or PaneEngine imports a UI framework (D-23), so they stay headless-testable.
# Usage: scripts/check-no-appkit.sh [dir ...]   (default: Sources/PaneModel Sources/PaneEngine)
# Exit: 0 clean, 1 violation found, 2 a directory is missing or has no .swift files.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
```
Keep the same three-line header (purpose / Usage / Exit codes), `set -euo pipefail`, and the cd to repo root. Errors go to stderr with a `name:` prefix (line 18).

`check-no-appkit.sh` defaults to `Sources/PaneModel Sources/PaneEngine` (line 9). Leave it alone: PaneMac and PaneApp are allowed AppKit. PanePrivate and PaneTestSupport could optionally be added as extra args in CI, but PanePrivate imports ApplicationServices (not in the banned list), so it would pass.

### `.github/workflows/ci.yml` and `.gitignore` (modify)

**ci.yml** (lines 13-19): steps `check-no-appkit.sh`, `swift build`, `swift test`, `swift build -c release`, `swift test -c release -Xswiftc -enable-testing`. `NoAppKitTests.ciBuildsAndTestsInReleaseToo` (lines 65-69) asserts the last two lines exist. **Do not reword them.** The integration suite must skip on CI, since the runner isn't AX-trusted. XcodeGen/xcodebuild should not be added to CI in Phase 2 unless the plan installs xcodegen there.

**.gitignore**: append `xcode/*.xcodeproj/` and `xcode/.xcode-build/` (RESEARCH). The existing `*.app/` line (line 3) already covers built bundles.

## Shared Patterns

### Module isolation flags
**Source:** CLAUDE.md "Package Layout" + RESEARCH Pattern 1 / Anti-Patterns
**Apply to:** all new targets
- PaneEngine: stays nonisolated. Mark the few engine classes `@MainActor` explicitly.
- PaneMac: `.defaultIsolation(MainActor.self)`. Thread classes must be `nonisolated final class ...: @unchecked Sendable`. A class conforming to `WindowSystem` needs an explicit `@MainActor` and `public nonisolated let events`.
- PanePrivate: nonisolated, `static let` optional `@convention(c)` pointers.
- Locks: `OSAllocatedUnfairLock`, not `Mutex`, because of the macOS 14 floor.

### Error handling
**Source:** `LayoutTree.swift` 10-29, `Persistence.swift` 3-10
**Apply to:** all engine/store errors. `public enum XError: Error, Equatable, Sendable`, typed `throws(XError)`, payloads carry IDs and never titles. No `?? default` / `or {}` fallbacks (CLAUDE.md). The AX reader returns `Result<Value, AXError>` per attribute so that -25202 and -25204 stay distinct.

### Validation of untrusted input
**Source:** `Resolve.swift` 33-34, `Persistence.swift` 35-47
**Apply to:** hints JSON, corpus loader, `--disable-private` parsing (known `Capability` raw values only), AX-provided numbers.

### Logging
**Source:** no in-repo logger yet (Phase 1 has none). Use `Logger(subsystem: "com.eightabyte.pane", category: "ax" | "private" | "permission" | ...)`, and log windows via `WindowRef.description` only.

### Tests
**Source:** `Tests/PaneModelTests/*`. Swift Testing, `@Suite struct`, `@Test(arguments:)`, `#expect` / `#require`, `#filePath`-relative repo paths, RED then GREEN commits.

## No Analog Found

The planner should use the RESEARCH.md / UI-SPEC skeletons for these:

| File | Role | Data Flow | Reason / use instead |
|---|---|---|---|
| `Sources/PanePrivate/AXWindowID.swift`, `Capabilities.swift` | private-API shim | request-response | No private APIs yet. RESEARCH Pattern 8 (verified `dlopen` of the ApplicationServices path, `--disable-private`) |
| `Sources/PaneMac/AX/AXAppThread.swift` | thread service | event-driven | No threads or CF run loops yet. RESEARCH Pattern 1 verified skeleton + latest-wins slots (Pattern 5) |
| `Sources/PaneMac/AX/AXSnapshotReader.swift`, `AppRegistry.swift` | adapter/service | event-driven | No AX code. RESEARCH Patterns 1-2 |
| `Sources/PaneMac/AXWindowSystem.swift` | protocol impl | event-driven | Only the protocol exists. RESEARCH "WindowSystem conformances" |
| `Sources/PaneMac/CGWindowList.swift`, `Displays.swift`, `FallbackMatcher.swift`, `SessionGate.swift` | adapters | request-response / event-driven | RESEARCH Patterns 4, 6, 8 |
| `Sources/PaneMac/Exclusions.swift` | store | CRUD (UserDefaults) | No UserDefaults use yet |
| `Sources/PaneMac/Permission/*` (probe, onboarding SetupView) | service/component | request-response | RESEARCH Pattern 7 + UI-SPEC Surface 2 (the tccutil runner borrows the `Process` shape above) |
| `Sources/PaneMac/Shell/*` (status item, menu, Tracked Windows, Freeze alert) | component | event-driven | No UI code. UI-SPEC Surfaces 1, 3, 4. AppKit `NSStatusItem` + `NSHostingController`, no SwiftUI App lifecycle |
| `Sources/PaneApp/main.swift` | entry point | n/a | No executables yet. AeroSpace-style `main.swift` calling into PaneMac |
| `Sources/PaneFixtureApp/main.swift` | fixture app | n/a | RESEARCH Wave 0 list (tabs, sheet, panel, borderless floating, fullScreenNone, minSize, argv/stdin command channel) |
| `Sources/pane-dump/main.swift` | CLI | file-I/O | Shares `AXSnapshotReader`. Redaction rules in RESEARCH Pattern 2. The JSON encode convention comes from Persistence.swift |
| `Sources/PaneEngine/PermissionReducer.swift` | reducer | event-driven | No state machines yet. RESEARCH Pattern 7 states |
| `xcode/project.yml`, entitlements, Info.plist keys | config | n/a | RESEARCH "XcodeGen project.yml" (Developer ID, team S2K7P43927, hardened runtime, LSUIElement, bundle IDs `com.eightabyte.pane[.debug]`) |

## Metadata

**Analog search scope:** all git-tracked files (`Sources/PaneModel`, `Sources/PaneEngine`, `Tests/PaneModelTests`, `scripts/`, `.github/`, `Package.swift`, `.gitignore`)
**Files scanned:** 31 tracked source/config files
**Pattern extraction date:** 2026-10-24
