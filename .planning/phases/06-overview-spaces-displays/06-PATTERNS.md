# Phase 6: Overview, Spaces & Displays - Pattern Map

**Mapped:** 2026-10-31
**Files analyzed:** 28 (17 new, 11 modified)
**Analogs found:** 27 / 28

All analog paths are git-tracked (checked with `git ls-files Sources Tests`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `Sources/TransomPrivate/SkyLightSpaces.swift` (MOD: `managedDisplaySpaces`, `managementMode`) | private-API shim | request-response | itself (`currentSpace`, L21-32, L58-64) | exact |
| `Sources/TransomPrivate/SymbolicHotKeys.swift` (NEW) | private-API shim | request-response | `Sources/TransomPrivate/SkyLightSpaces.swift` | exact |
| `Sources/TransomPrivate/CoreDock.swift` (NEW) | private-API shim | fire-and-forget | `Sources/TransomPrivate/AXWindowID.swift` / `SkyLightSpaces.swift` | exact |
| `Sources/TransomPrivate/Capabilities.swift` (MOD: `.symbolicHotKeys`, `.coreDock`, takeover canary) | config/registry | — | itself (L5-17, L53-60, `MultitouchCanary` L127-193) | exact |
| `Sources/TransomEngine/SpacesSnapshot.swift` (NEW) | model + pure parser | transform | `SkyLightSpaces.spaceIDs(in:)` (L66-75) + `Sources/TransomEngine/WindowSnapshot.swift` | role-match |
| `Sources/TransomEngine/SpaceRekey.swift` (NEW) | pure utility | transform | `Sources/TransomEngine/LayoutRestore.swift` | role-match |
| `Sources/TransomEngine/Arrangements.swift` (NEW) | model + policy | transform | `Sources/TransomEngine/LayoutFile.swift` (Codable value types) | role-match |
| `Sources/TransomEngine/CoVisibilitySpaces.swift` (NEW) | pure state struct | event-driven | `Sources/TransomEngine/SpaceSwitchMarks.swift` | exact |
| `Sources/TransomEngine/OverviewLayout.swift` (NEW) | pure geometry | transform | `Sources/TransomEngine/ViewPlanner.swift` | role-match |
| `Sources/TransomEngine/OverviewSelection.swift` (NEW) | pure state machine | event-driven | `Sources/TransomEngine/Navigator.swift` | role-match |
| `Sources/TransomEngine/TakeoverPolicy.swift` (NEW) | pure decision table | request-response | `Sources/TransomEngine/CloseRule.swift` | exact |
| `Sources/TransomEngine/LayoutFile.swift` (MOD: schema 2, `spaces`, layout sets) | model | file-I/O | itself (L31-50) | exact |
| `Sources/TransomEngine/CloseRule.swift` (MOD: G-03-9) | decision table | request-response | itself (L42-56) | exact |
| `Sources/TransomEngine/Arranger.swift` (MOD: `.displaysChanged`, dormant desks, dirty hidden desks) | service | event-driven | itself (L619-620, `rescueStranded`) | exact |
| `Sources/TransomEngine/Notice.swift` + `Sources/TransomMac/Shell/NoticeCopy.swift` (MOD: N10-N12) | copy/enum | — | themselves | exact |
| `Sources/TransomMac/SpacesProvider.swift` (NEW) | adapter | request-response | `Sources/TransomMac/Displays.swift` | exact |
| `Sources/TransomMac/DisplaySettler.swift` (NEW) | debouncer | event-driven | `Sources/TransomMac/RefreshScheduler.swift` + `SessionGate.swift` | exact |
| `Sources/TransomMac/SpaceSwitcher.swift` (NEW) | service | request-response | `Sources/TransomMac/AX/MenuPress.swift` (posting input) | partial |
| `Sources/TransomMac/MissionControlTakeover.swift` (NEW) | controller | event-driven | `Sources/TransomMac/Zoom/GestureController.swift` (canary + start/stop) + `MultitouchCanary` | role-match |
| `Sources/TransomMac/Overview/OverviewController.swift` (NEW) | controller | event-driven | `Sources/TransomMac/Zoom/ZoomController.swift` | exact |
| `Sources/TransomMac/Shell/OverviewCopy.swift` (NEW) | copy | — | `Sources/TransomMac/Shell/ZoomCopy.swift` | exact |
| `Sources/TransomMac/Input/Hotkeys.swift` (MOD: `Name.showOverview`) | config | — | itself (L7-26) | exact |
| `Sources/TransomMac/AXWindowSystem.swift` (MOD: displaysDidChange -> settler) | adapter | event-driven | itself (L590-595, observers L112-117) | exact |
| `Sources/TransomMac/LayoutStore.swift` (MOD: accept v1, migrate) | store | file-I/O | itself (L93-97) | exact |
| `Sources/TransomMac/Shell/CommandMenu.swift` / `StatusItemController.swift` (MOD: Show Overview, Replace Mission Control, Debug line) | component | — | themselves | exact |
| `Sources/transom-spaces-spike/main.swift` + `Package.swift` target (NEW) | spike CLI | batch | `Sources/transom-gesture-spike/main.swift`, `Package.swift` L35 | exact |
| `Tests/TransomEngineTests/*` (NEW: SpacesSnapshot, SpaceRekey, Arrangements, CoVisibility, OverviewLayout/Selection, TakeoverPolicy, LayoutFile migration, CloseRule rows) | test | — | `Tests/TransomEngineTests/CloseRuleTests.swift` | exact |
| `Tests/TransomEngineTests/Fixtures/Spaces/*.json` (NEW) | fixture | — | `Tests/TransomEngineTests/Fixtures/AXDumps/` (+ README.md) | role-match |

## Pattern Assignments

### Private shims: `SkyLightSpaces.swift` (extend), `SymbolicHotKeys.swift`, `CoreDock.swift`

**Analog:** `Sources/TransomPrivate/SkyLightSpaces.swift`

Typealias + optional symbol in one `functions` closure, gated by `isForcedOff` (L21-32):
```swift
typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64

/// `currentSpace` is optional on its own, so a missing symbol never turns off the per-window lookup.
private static let functions: (connection: Int32, copySpaces: CopySpacesForWindows, currentSpace: CurrentSpace?)? = {
    guard !Capabilities.isForcedOff(.spaces),
          let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let main = dlsym(handle, "SLSMainConnectionID"),
          let copy = dlsym(handle, "SLSCopySpacesForWindows")
    else { return nil }
    let current = dlsym(handle, "SLSManagedDisplayGetCurrentSpace").map { unsafeBitCast($0, to: CurrentSpace.self) }
    return (unsafeBitCast(main, to: MainConnectionID.self)(), unsafeBitCast(copy, to: CopySpacesForWindows.self), current)
}()
public static var isLoaded: Bool { functions != nil }
```
Session-gated call with nil degradation (L58-64):
```swift
public static func currentSpace(displayUUID: String, session: CapabilitySession = Capabilities.session) -> UInt64? {
    guard session.isAvailable(.spaces), let functions, let currentSpace = functions.currentSpace else { return nil }
    ...
}
```
Failure accounting: `Capabilities.recordFailure(.spaces)` / `recordSuccess` (L50-55). `+1` CF returns use `takeRetainedValue()`. Add `CopyManagedDisplaySpaces`/`GetSpaceManagementMode` as extra optionals in the same tuple (RESEARCH Pattern 1). New files get their own `dlopen` + capability, never link-time symbols.

### `Capabilities.swift` (MOD)

Add cases with `fallback` text (L5-17) and a `loaded:` branch in `Capabilities.session` (L53-60). The takeover canary copies `MultitouchCanary` (L127-193) wholesale: `key`, `init(defaults:osBuild:appVersion:)` for injection, `arm()` / `clear()` / `isTripped()` comparing `osBuild` and `appVersion`, static `turnBackOn`. Reuse `currentOSBuild` / `currentAppVersion` rather than duplicating them (consider a key parameter, but 2 examples is not enough to abstract: copying is acceptable).

### `TakeoverPolicy.swift` (pure decision table)

**Analog:** `Sources/TransomEngine/CloseRule.swift` L42-56: a `public enum` with one `static func decide(...) -> Decision` switching over a tuple of facts, documented as a markdown table in the doc comment. Inject the store as a protocol/value (no UserDefaults in Engine).

### `CloseRule.swift` (MOD, G-03-9)

Narrow new input (e.g. `cgSpacesKnownEmpty: Bool`) and one tuple row; guard minimised/hidden/tab-member first (RESEARCH Pattern 9, Pitfall 10). Existing row to sit next to: `case (.alive, .valid(false, _, _, _), true): return .noChange`. Add rows to `CloseRuleTests.swift` `rows` array.

### `SpacesSnapshot.swift`

Parse `[[String: Any]]` defensively, type-checking each element like `SkyLightSpaces.spaceIDs(in:)` (L66-75: only CFNumber, drop 0, cap count). Value types `Codable, Equatable, Sendable`, Engine imports only Foundation/TransomModel. Empty uuid -> `"default:<displayUUID>"`; `"Main"` -> main display UUID passed in as a parameter.

### `CoVisibilitySpaces.swift`

**Analog:** `Sources/TransomEngine/SpaceSwitchMarks.swift` (whole file, 28 lines): `public struct ...: Equatable, Sendable` with `private var` storage, `mutating func spaceDidChange(...)`, `forget(pid:)`.

### `SpaceRekey.swift`, `Arrangements.swift`

Pure static funcs over `World` like `LayoutRestore.reattach` / `isAlive` (`Sources/TransomEngine/LayoutRestore.swift`, 42 lines). Keep `DeskKey` unchanged (`Sources/TransomModel/IDs.swift:119-121`). Return unmatched keys rather than dropping them (dormant desks, D-10).

### `LayoutFile.swift` + `LayoutStore.swift` (schema 2)

LayoutFile L31-50: `public static let schemaVersion = 1` plus sorted arrays for byte-stable output (`Self.sorted(...)`). New fields (`spaces: [SavedSpace]`, layout sets) follow the sorted-array convention and need `decodeIfPresent` defaults so a v1 file decodes. LayoutStore L93-97 is the gate to change (Pitfall 1: today a v1 file would be set aside once version becomes 2):
```swift
guard version <= LayoutFile.schemaVersion else { throw .newerVersion(version) }
guard version == LayoutFile.schemaVersion else { throw .corrupt("unknown schemaVersion \(version)") }
```
Keep the per-entry validation loop that follows (L104+) for new arrays.

### `OverviewLayout.swift`, `OverviewSelection.swift`

Pure, in Engine, `Rect`/`Point` from TransomModel, like `ViewPlanner.swift` (value struct per desk, throwing validated inits) and `Navigator.swift` (direction selection). No AppKit; convert in the controller (`tiles(for:images:)` in ZoomController L476-490 shows the `appKit(_ rect:)` conversion).

### `SpacesProvider.swift`

**Analog:** `Sources/TransomMac/Displays.swift`: `public enum` of static funcs, `Logger(subsystem: "com.eightabyte.transom", category: ...)`, compactMap with logged skips, calls `SkyLightSpaces.*` and returns Engine types. `Displays.screen(uuid:)` and the private `uuid(_:)` helper are the display-UUID source; reuse, don't reimplement. Read `NSScreen.screensHaveSeparateSpaces` here (app process only, Pitfall 5).

### `DisplaySettler.swift`

Debounce shape from `RefreshScheduler.scheduleAll(after:)`:
```swift
func scheduleAll(after delay: Duration) {
    pendingAll?.cancel()
    pendingAll = Task { [weak self, refreshAll] in
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        self?.pendingAll = nil
        await refreshAll()
```
`@MainActor final class`, injected closures in `init`, `isolated deinit` cancelling tasks. Hold while `SessionGate.isPaused` (SessionGate.swift L48), and fire on `onResume`. Hook from `AXWindowSystem.displaysDidChange()` (L590-595), which today yields `.displaysChanged` and `scheduler?.scheduleAll(after: .milliseconds(500))`. C reconfig callbacks bridge via `Unmanaged` refcon + `MainActor.assumeIsolated` (SessionGate L64-68 uses `assumeIsolated` for observers).

### `OverviewController.swift`

**Analog:** `Sources/TransomMac/Zoom/ZoomController.swift`
- per-display panel cache (L287-295):
```swift
private func stage(for uuid: String) -> StagePanel? {
    if let stage = stages[uuid] { return stage }
    guard let nsScreen = Displays.screen(uuid: uuid) else { return nil }
    let panel = StagePanel(screen: nsScreen)
    panel.onTileClick = { [weak self] id in self?.onTileClick?(uuid, id) }
    stages[uuid] = panel
    return panel
}
```
- teardown on display change (L274-283 `displaysChanged()`), captures via `capture.captureAll(..., deadline:)` (L298-302), AppColor fallback tile (`fallback(_:)` L498), permission check (L403). Overview keys: pick-mode Esc via KeyboardShortcuts events in `Sources/TransomMac/Zoom/ZoomInput.swift:179-181`.

### Takeover explanation alert

Copy `ExplainerAlert` (ZoomController.swift L527-566): NSAlert, first button default, Esc assigned via `keyEquivalent = "\u{1b}"`, `done` guard, `windowWillClose` = decline. Also see `Sources/TransomMac/ConflictController.swift` (Phase 3 conflict-alert style named by D-06).

### `OverviewCopy.swift`

**Analog:** `Sources/TransomMac/Shell/ZoomCopy.swift`: `nonisolated public enum`, imports only TransomEngine/TransomModel, `// MARK:` per UI-SPEC surface, `static let` strings and `static func` for counted phrases, curly quotes as `\u{201C}`/`\u{201D}`, `MenuCopy.truncatedAppName`.

### `Hotkeys.swift` (MOD)

```swift
static let toggleDesktop = Self("toggleDesktop", initial: .init(.h, modifiers: [.control, .option, .command]))
```
Pick an unused ⌃⌥⌘ letter (used: d f z h n p e s b o, arrows, = -).

### `transom-spaces-spike` + `Package.swift`

Copy `transom-gesture-spike/main.swift` header (L1-40): usage string with subcommands mapped to spike IDs, `fail(_:_:) -> Never` exit codes, `--seconds` cap, JSON lines to `--out`, never prints PASS/FAIL. Package target line (Package.swift L35):
```swift
.executableTarget(name: "transom-gesture-spike", dependencies: ["TransomMac", "TransomPrivate", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
```

### Tests

`CloseRuleTests.swift`: `import Testing`, row structs conforming to `CustomTestStringConvertible` with defaulted fields, a `private let rows` table driving a parameterised `@Test(arguments:)`. Fixtures go under `Tests/TransomEngineTests/Fixtures/Spaces/` with a README like `Fixtures/AXDumps/README.md`.

## Shared Patterns

- **Private API:** dlopen/dlsym into optionals, `Capabilities.isForcedOff` at load, `session.isAvailable` at call, `recordFailure/Success`; log category `private`.
- **Crash canary:** `MultitouchCanary` (Capabilities.swift L127-193), arm before risky call, clear only on clean stop.
- **Isolation:** Engine pure + `Sendable`; Mac `@MainActor final class` with closure injection and `isolated deinit`.
- **Logging:** `Logger(subsystem: "com.eightabyte.transom", category: "<area>")`.
- **Copy:** AppKit-free `*Copy` enums, unit tested.
- **Debounce:** cancel-latest `Task.sleep` (RefreshScheduler).

## No Analog Found

| File | Role | Reason |
|---|---|---|
| `SpaceSwitcher.swift` | CGEvent chord posting with explicit flags + verification | Nothing posts keyboard chords today; use RESEARCH "Posting a Space-switch chord with explicit flags" (Pitfall 7). `MenuPress.swift` is only a loose analog for "act then verify". |

## Metadata

**Search scope:** Sources/TransomPrivate, TransomEngine, TransomMac (Zoom, Input, Shell, root), Tests/TransomEngineTests, Package.swift
**Files scanned:** ~20 read
**Date:** 2026-10-31
