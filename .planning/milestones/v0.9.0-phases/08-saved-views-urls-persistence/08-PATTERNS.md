# Phase 8: Saved Views, URLs & Persistence - Pattern Map

**Mapped:** 2026-11-03
**Files analyzed:** 24 (new + modified)
**Analogs found:** 22 / 24

All analog paths below are git-tracked source (verified with `git ls-files`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Sources/TransomEngine/TransomURL.swift` (mod) | utility (parser + limiter) | request-response | itself (lines 7-45) | exact |
| `Sources/TransomEngine/Command.swift` (mod: `ViewSlot`, `CameraCommand.view/.saveView`) | model | transform | `CameraCommand` (Command.swift:47-55) | exact |
| `Sources/TransomEngine/SavedViews.swift` (new) | model (Codable) | CRUD | `HomeFrame` / `SessionRecord` in `LayoutFile.swift:6-29` | role-match |
| `Sources/TransomEngine/Arranger+Views.swift` (new) | service (Arranger extension) | request-response | `Sources/TransomEngine/Arranger+Tabs.swift`, `Arranger+Camera.swift` | exact |
| `Sources/TransomEngine/HintMatcher.swift` (new) | utility (pure scorer) | transform | `Sources/TransomEngine/FallbackMatcher.swift` | exact |
| `Sources/TransomEngine/Arranger+Placeholders.swift` (new) | service | event-driven (deadlines on `tick`) | `Arranger.swift` dormant code 955-975 + `nextWake` 1099-1105 | role-match |
| `Sources/TransomEngine/LayoutFile.swift` (mod: schema 3, `views`) | model | file-I/O | itself 36-90; `DesktopLayer.swift:228` (`decodeIfPresent`) | exact |
| `Sources/TransomEngine/LayoutRestore.swift` (mod) | service (pure) | batch | itself 5-42 | exact |
| `Sources/TransomEngine/CLICommandLine.swift` (new) | utility (argv parser) | transform | `Sources/transom-dump/main.swift:20-34` (argv loop) + `TransomURL.parse` | role-match |
| `Sources/TransomEngine/CLICopy.swift` (new) | utility (copy) | transform | `Sources/TransomMac/Shell/NoticeCopy.swift` / `ZoomCopy.swift` (nonisolated copy enums) | role-match |
| `Sources/TransomEngine/CLIProtocol.swift` (new) | utility (wire format) | request-response | none (CFMessagePort new) | no analog |
| `Sources/TransomEngine/Notice.swift` (mod: N13-N19) | model | transform | itself (`enum Notice` lines 5-40) | exact |
| `Sources/TransomModel/World.swift` (mod: `adopt`, `refreshingTitles`, remove `withoutTitleHints` use) | model | transform | `World.withoutTitleHints()` 136-150, `World.rekey` 216-229 | exact |
| `Sources/TransomMac/LayoutStore.swift` (mod) | store | file-I/O | itself 54-130 | exact |
| `Sources/TransomMac/Input/Hotkeys.swift` (mod: 18 names) | config | event-driven | itself 7-128 | exact |
| `Sources/TransomMac/AppDelegate.swift` (mod: shared gate) | controller | request-response | itself 51-71 | exact |
| `Sources/TransomMac/CommandGate.swift` (new, shared URL/CLI gate) | service | request-response | `AppDelegate.application(_:open:)` 53-65 | role-match |
| `Sources/TransomMac/CLIListener.swift` (new) | controller (IPC server) | request-response | `AppDelegate.handleSIGTERM` 43-49 (C-source → main + `assumeIsolated`) | partial |
| `Sources/TransomMac/ArrangeController.swift` (mod: `CommandSource.cli`, sync decide) | controller | request-response | itself 560-600, 1162 | exact |
| `Sources/TransomMac/Overlay/PlaceholderPanels.swift` (new) | component (NSPanel pool) | event-driven | `Sources/TransomMac/Zoom/CollapsedPanels.swift` | exact (with property deltas) |
| `Sources/TransomMac/Overlay/NoticeQueue.swift` (mod: brief duration) | utility | event-driven | itself 13-40 | exact |
| `Sources/TransomMac/Shell/NoticeCopy.swift`, `ZoomCopy.swift` (mod), `Shell/ViewCopy.swift` (new) | utility (copy) | transform | `NoticeCopy.swift:6-64`, `ZoomCopy.shortcutTitle` 67, `TabCopy.swift` | exact |
| `Sources/transom-cli/main.swift` (new) + `Package.swift` (mod) | executable | request-response | `Sources/transom-dump/main.swift`; `Package.swift` executableTarget lines | role-match |
| `xcode/project.yml` (mod: `transom` tool target, copy to Contents/Helpers) | config | — | itself (targets.Transom) | role-match (no existing embedded tool) |
| Tests: `TransomURLTests`, `HintMatcherTests`, `SavedViewsTests`, `ArrangerViewsTests`, `ArrangerPlaceholderTests`, `CLICommandLineTests`, `CLICopyTests`, `LayoutStoreTests` (invert titles test) | test | — | `Tests/TransomEngineTests/TransomURLTests.swift`, `FallbackMatcherTests.swift`, `ArrangerRestoreTests.swift` | exact |

## Pattern Assignments

### `Sources/TransomEngine/TransomURL.swift` (parser, request-response)

**Analog:** itself. Current shape (lines 7-30):
```swift
public enum TransomURL {
    static let commands: [String: Command] = [
        "restore": .restoreAll, "toggle-desktop": .toggleDesktop, "split-finder": .finderSplit,
        "zoom-out": .camera(.zoomOutAll), ...
        "next-tab": .tabs(.next), "previous-tab": .tabs(.previous), "move-out-of-group": .tabs(.moveOut),
    ]
    public static func parse(_ url: URL, scheme: String) -> Command? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == scheme,
            parts.percentEncodedUser == nil, parts.percentEncodedPassword == nil, parts.port == nil,
            parts.percentEncodedQuery == nil, parts.percentEncodedFragment == nil,
            parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/", let host = parts.percentEncodedHost
        else { return nil }
        return commands[host]
    }
}
```
Changes: split the guard so `percentEncodedPath` is checked per branch. Empty/"/" path → `commands[host]` (do NOT add `view`/`save-view` there). Path of exactly 2 bytes `/` + `"1"..."9"` and host `view`/`save-view` → `.camera(.view(slot))` / `.camera(.saveView(slot))`. Compare `percentEncodedPath` so `/%33` fails. Put the help-line table beside `commands` (internal `static let`) for the coverage test.

**Rate limiter (lines 34-45)** is keyed by `Command`; with the slot inside the enum case, per-slot limiting is free. No change to `TransomURLRateLimiter`.

---

### `Sources/TransomEngine/Command.swift` (model)

**Analog:** `CameraCommand` (lines 47-55):
```swift
public enum CameraCommand: Hashable, Sendable {
    case zoomOutAll, stepOut, stepIn, back, forward
    case pan(Edge)
    case frameWindow, frameDesktop
    case overview
}
```
Add `case view(ViewSlot), saveView(ViewSlot)`; `ViewSlot` must be `Hashable, Sendable, Codable` with failable `init?(_:)` for 1...9 (RESEARCH Pattern 1 skeleton). Keeping them as `.camera` cases makes `Hotkeys.zoomNames` include them automatically (D-17).

---

### `Sources/TransomEngine/SavedViews.swift` (model, Codable)

**Analog:** `LayoutFile.swift:6-29` — small public Codable/Equatable/Sendable structs with explicit public init and doc comment citing the decision ID:
```swift
public struct HomeFrame: Codable, Equatable, Sendable {
    public var window: WindowIdentity
    public var frame: Rect
    public init(window: WindowIdentity, frame: Rect) { ... }
}
```
Sorting convention for byte-stable output (LayoutFile.swift:71-76): store `views` sorted by slot, `windows` sorted by identity.

---

### `Sources/TransomEngine/Arranger+Views.swift` and `Arranger+Placeholders.swift` (Arranger extensions)

**Analog:** `Sources/TransomEngine/Arranger+Tabs.swift` (file layout: `import TransomModel`, public effect/announcement enums at top, then `extension Arranger`) and `Arranger+Camera.swift` (`currentView(_:_:)` lines 99-103, `zoomTo` lines 232-257).

**Effect enum pattern** (Arranger+Tabs.swift:1-22):
```swift
import TransomModel

/// A tab-group change to speak (UI-SPEC Accessibility); the shell words it (`TabCopy`).
public enum TabAnnouncement: Equatable, Sendable {
    case grouped(tabs: Int)
    ...
    case refused(TabRefusal)
}
```
Copy for a `ViewAnnouncement`/view outcome enum (saved, replaced, went, emptySlot, allGone, displayGone, emptyView) that the shell words via `ViewCopy`/`NoticeCopy`.

**Dormant / close path to copy for placeholder expiry** (Arranger.swift:957-975):
```swift
private var dormantWindows: [WindowRef] {
    world.desks.values.flatMap { $0.tree.windows + $0.desktop.windows.map(\.window) }
        .filter { windows[$0.identity] == nil }.sorted { $0.identity < $1.identity }
}
private mutating func closeDormant(where predicate: (WindowRef) -> Bool) -> [ArrangerEffect] {
    var faults: [ArrangerEffect] = []
    for window in dormantWindows where predicate(window) {
        forget(window)
        do throws(LayoutError) {
            _ = try LifecycleSync.handle(.windowDestroyed(window), world: &world, history: &history)
        } catch {
            faults.append(.fault("could not prune the closed window \(window): \(error)"))
        }
    }
    return faults
}
```
Placeholders must be excluded from `dormantWindows` (or the predicate) at the three delete sites: Arranger.swift:285-286 (inventory), 890-892 (`.appTerminated`), and `LayoutRestore.reattach`.

**Wake clock** (Arranger.swift:1100-1105) — append placeholder deadlines to the `compactMap` list:
```swift
var nextWake: ContinuousClock.Instant? {
    ...
    return (pendingCorrections.compactMap { ... }
        + [finderExpectation?.deadline, dwell, groupDwell, tabs.pendingReveal?.deadline, tabs.closeQueue?.deadline].compactMap { $0 }).min()
}
```

**App-terminated hook site** (Arranger.swift:890-892):
```swift
case .appTerminated(let pid):
    // Its tracked windows are still in `windows` here and close on their own windowDestroyed.
    faults += closeDormant { $0.pid == pid }
```
D-12a: record `quitting[pid] = (bundleID from windows, now)` here; in `.windowDestroyed` for a docked window with a quitting pid, keep the ref (forget tracking, skip `LifecycleSync.handle`).

---

### `Sources/TransomEngine/HintMatcher.swift` (pure scorer)

**Analog:** `Sources/TransomEngine/FallbackMatcher.swift` (whole file, 56 lines). Copy:
- outcome enum style (lines 3-6): `public enum FallbackMatch: Equatable, Sendable { case cg(UInt32), ambiguous, none }`
- caseless `public enum` namespace with `public static let` tunables (line 11: `public static let boundsTolerance: Double = 1.0`) — use for weights and `threshold = 40`
- pure static `match(...)` with filter-then-narrow, explicit ambiguity result instead of a guess (lines 16-32) — this is the precedent for D-10's "tie → neither".
- private geometric helper (lines 52-55) — sibling for IoU.

---

### `Sources/TransomEngine/LayoutFile.swift` (schema 3)

**Analog:** itself, lines 36-73:
```swift
public struct LayoutFile: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let maxLayoutSets = 16
    ...
    public var spaces: [SavedSpace]
    public init(world: World, ..., spaces: [SavedSpace] = []) {
        schemaVersion = Self.schemaVersion
        ...
        self.spaces = spaces.sorted { $0.id < $1.id }
    }
```
Bump to 3, add `views: [SavedView]` (default `[]` in init, sorted). Decode absent `views` with the Phase 7 precedent (`Sources/TransomModel/DesktopLayer.swift:228`):
```swift
groups = try container.decodeIfPresent([FloatingTabGroup].self, forKey: .groups) ?? []
```
Do NOT bump `World.currentSchemaVersion` (World.swift:87, 280).

---

### `Sources/TransomEngine/LayoutRestore.swift`

**Analog:** itself (lines 13-32). Keep the signature style (`throws(LayoutError)`, tuple return, sorted desk iteration `saved.desks.sorted(by: { $0.key < $1.key })`). Change: after identity re-attach, run `HintMatcher` over `unplaced` vs unattached saved refs; matched → `world.rekey(from:to:history:)` (World.swift:216); unmatched docked → kept and returned as `placeholders`. Update the doc comment line 9-10 ("re-matching it is VIEW-04's").

---

### `Sources/TransomModel/World.swift`

**Analog for `refreshingTitles`:** `withoutTitleHints()` lines 136-150 (walks `desk.tree.nodes` `.panel`/`.tabs` plus Desktop layer, rebuilding `WindowRef(identity:axIdentifier:creationOrder:)`). Write the inverse taking `[WindowIdentity: String]`.
**Analog for `adopt(_:by:)`:** `rekey(from:to:history:)` lines 216-229 — candidate copy, `try candidate.validate()`, `self = candidate`, `history.rekey(...)`; "any throw leaves self unchanged".

---

### `Sources/TransomMac/LayoutStore.swift`

**Analog:** itself. Remove redaction (lines 59-61):
```swift
var redacted = contents
redacted.world = contents.world.withoutTitleHints()
for index in redacted.layoutSets.indices { redacted.layoutSets[index].world = ... .withoutTitleHints() }
```
Keep `.posixPermissions: 0o600` (line 67). Decode switch (lines 117-122) becomes:
```swift
case 1: contents = try decoder.decode(LayoutFileV1.self, from: data).migrated()
case 2, LayoutFile.schemaVersion: contents = try decoder.decode(LayoutFile.self, from: data)
```
Update the doc comment at line 54 ("with every window title removed").

---

### `Sources/TransomMac/Input/Hotkeys.swift`

**Analog:** itself. Name declaration (line 42) and table entry (line 97):
```swift
static let zoomOutAll = Self("zoomOutAll", initial: .init(.o, modifiers: [.control, .option, .command]))
...
(.zoomOutAll, .camera(.zoomOutAll)),
```
Add `view1…view9` / `saveView1…saveView9` with `initial` from a pure `ViewChords.modifiers(save:os:)` (RESEARCH Pattern 5). Keep the "persistent contract, never rename" comment (lines 5-6). `zoomNames` (line 115) and `setZoomHotkeys` (126-128) need no change.

---

### `Sources/TransomMac/AppDelegate.swift` + new `CommandGate.swift`

**Analog:** `application(_:open:)` lines 53-65:
```swift
for url in urls {
    guard let urlScheme, let command = TransomURL.parse(url, scheme: urlScheme) else {
        logger.notice("rejected a URL")
        continue
    }
    guard limiter.admit(command, at: .now) else {
        logger.info("rate-limited a URL command")
        continue
    }
    open(command)
}
```
Move `private var limiter = TransomURLRateLimiter()` (line 14) into the shared gate returning `rejected | rate | command`; AppDelegate and CLIListener both call it. Scheme from `registeredScheme(in:)` (lines 68-71). Logger pattern: `Logger(subsystem: "com.eightabyte.transom", category: "url")` (line 15) — new categories `views`, `match`, `cli`.

---

### `Sources/TransomMac/CLIListener.swift` (IPC server)

**Partial analog:** C-level source bridged to MainActor, `AppDelegate.handleSIGTERM` lines 43-49:
```swift
let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
source.resume()
sigterm = source
```
Same idea: `CFMessagePortSetDispatchQueue(port, .main)` + `MainActor.assumeIsolated` in the `@convention(c)` callback, `Unmanaged.passUnretained(self)` as `info`. Full skeleton is in RESEARCH Pattern 7 (no codebase analog for CFMessagePort).

---

### `Sources/TransomMac/ArrangeController.swift`

**Analog:** itself. `CommandSource` (line 1162): `public enum CommandSource { case hotkey, menu, url }` → add `.cli`. URL-route filtering in `dispatch` (lines 560-590):
```swift
let refuse = source == .url ? {} : beep
...
let via: TabLeaveSource = switch source { case .hotkey: .hotkey; case .menu: .menu; case .url: .url }
...
guard source == .url else { return await run(effects) }
return await run(effects.filter { if case .beep = $0 { false } else if case .tabAnnouncement(.refused) = $0 { false } else { true } })
```
`.cli` follows `.url` filtering but extracts the refusal text for the reply. `dispatchCamera` (592+) zoom-off branch is where "Zoom is off" CLI refusal goes. Split into sync `decide` + `Task { await run(effects) }` per RESEARCH Pattern 7.

---

### `Sources/TransomMac/Overlay/PlaceholderPanels.swift` (NSPanel pool)

**Analog:** `Sources/TransomMac/Zoom/CollapsedPanels.swift`.
- Panel subclass (lines 7-10): `private final class BlockPanel: NSPanel { override var canBecomeKey: Bool { false }; override var canBecomeMain: Bool { false } }`
- View with `wantsUpdateLayer` + `updateLayer()` re-resolving colours (lines 60-80), using `AppColor.color(forBundleID:icon:)`, `TileLayer.cornerRadius`, `TileLayer.minIcon`, `accessibilityDisplayShouldIncreaseContrast`.
- Pool class (lines 126-200): `shown: [String: [Panel]]`, `pool`, `hidden: Set<String>`, appearance observers (134-145), `show(_:on:)` reuse/recycle loop (148-173) with `Coordinates.appKit(fromTopLeft:primaryHeight:)`, `hide(on:)`, `fadeIn(on:)` 0.12 s (183-193), `onShownSpace` (Space-stranding replacement).
- **Deltas required by UI-SPEC:** `ignoresMouseEvents = true` (analog: false), `level = .normal` + `orderBack` (analog: `.floating` + `orderFrontRegardless`), `collectionBehavior = [.stationary, .ignoresCycle]` with NO `.canJoinAllSpaces`, `sharingType = .none`; view role `.staticText`, no hover ring/double-click; 40% fill + dashed `CAShapeLayer` border 8/4.

---

### `Sources/TransomMac/Overlay/NoticeQueue.swift`

**Analog:** itself lines 13-40. `public static var duration: Duration { .seconds(6) }` (line 20) → add a per-item duration via `QueueableNotice` (protocol lines 5-10 already carries `isCrashNotice`; add `isBrief`). `post` (33-40) gains "brief behind crash notice → dropped, not queued".

---

### Copy types: `NoticeCopy.swift`, `ZoomCopy.swift`, new `Shell/ViewCopy.swift`, new `TransomEngine/CLICopy.swift`

**Analog:** `Sources/TransomMac/Shell/NoticeCopy.swift` — `nonisolated public enum NoticeCopy { public static func text(for notice: Notice, appName: ...) -> String; glyph(for:); isWarning(_:) }` (lines 6-64). `ZoomCopy.shortcutTitle(_ command: Command)` (ZoomCopy.swift:67) gets view/saveView cases. `CollapsedBlockView.label(appName:title:)` (CollapsedPanels.swift:40-43) shows the `nonisolated static func` + `MenuCopy.truncatedAppName` pattern for the placeholder label. CLICopy lives in TransomEngine (no AppKit) but same caseless-enum shape.

---

### `Sources/transom-cli/main.swift` + `Package.swift`

**Analog:** `Sources/transom-dump/main.swift` lines 10-34:
```swift
let usage = """ ... """
func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("transom-dump: \(message)\n".utf8))
    exit(code)
}
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() { switch argument { ... default: fail("unknown argument ...", 64) } }
```
Keep main.swift thin: delegate parsing to `CLICommandLine` and messages to `CLICopy` (testable). Prefix `transom: `, exit 64 on usage.
Package.swift: copy the executableTarget line form, but depend only on TransomEngine and no MainActor isolation is needed:
```swift
.executableTarget(name: "transom-dump", dependencies: ["TransomMac", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
```
→ `.executableTarget(name: "transom-cli", dependencies: ["TransomEngine"]),`

---

### `xcode/project.yml`

**Analog:** existing `targets.Transom` block (dependencies `- package: Transom / product: TransomMac`, per-config settings, `OTHER_CODE_SIGN_FLAGS: "--timestamp"` in Release). Add a `transom` `type: tool` target and a dependency on the app with `embed: true, codeSign: true, copy: { destination: wrapper, subpath: Contents/Helpers }` per RESEARCH Pattern 8. Inherit global hardened-runtime/signing settings.

---

### Tests

**URL tests analog:** `Tests/TransomEngineTests/TransomURLTests.swift` lines 1-40 — private `parse` helper, `@Suite struct`, parameterized `@Test(arguments:)` for accepted hosts and a rejected-strings list. Add `view/1…9`, `save-view/1…9`, and the UI-SPEC rejected list (`view`, `view/`, `/0`, `/10`, `/3/`, `/03`, `/%33`, `/a`, `zoom-out/3`, `VIEW/3`), plus per-slot limiter cases.

**Matcher table analog:** `Tests/TransomEngineTests/FallbackMatcherTests.swift` lines 1-40 — file-private fixture constants (`pid`, `bundleID`, `frame`), private builder funcs (`cg(_:)`, `identity(_:)`), `@Test(arguments: [(input, expected)])` tables. Use for the D-10 required case table.

**Arranger tests:** `ArrangerRestoreTests.swift`, `ArrangerLifecycleTests.swift`, `ArrangerCameraTests.swift` for restore/placeholder/view-go flows.

## Shared Patterns

### AppKit-free engine
**Source:** Package.swift targets; `scripts/check-no-appkit.sh`. **Apply to:** SavedViews, HintMatcher, CLICommandLine, CLICopy, CLIProtocol, Arranger extensions. Only `import Foundation` / `import TransomModel`.

### Logging
**Source:** `AppDelegate.swift:15`, `Hotkeys.swift:117`: `Logger(subsystem: "com.eightabyte.transom", category: "...")`; `.public` for non-personal values. **Apply to:** new categories `views`, `match`, `cli`; titles `.private` only.

### Typed throws and fault effects
**Source:** `World.rekey` (`throws(LayoutError)`), `closeDormant` returning `[ArrangerEffect]` with `.fault(...)`. **Apply to:** adopt, placeholder expiry, restore matching.

### URL-route silence
**Source:** `ArrangeController.dispatch` 560-590. **Apply to:** `.cli` source (no beep/announce on screen; reason returned to CLI).

### Byte-stable persistence
**Source:** `LayoutFile.init` sorting (lines 65-76), encoder `[.sortedKeys, .prettyPrinted]` (LayoutStore.swift:63). **Apply to:** `views`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `Sources/TransomEngine/CLIProtocol.swift` | utility | request-response | No IPC exists yet; use RESEARCH Pattern 7 wire format |
| `Sources/TransomMac/CLIListener.swift` (CFMessagePort part) | controller | request-response | No CFMessagePort use; only the C-callback → MainActor bridge has an analog |

## Metadata

**Analog search scope:** Sources/TransomEngine, Sources/TransomModel, Sources/TransomMac (Input, Overlay, Zoom, Shell), Sources/transom-dump, Tests/TransomEngineTests, Package.swift, xcode/project.yml
**Files scanned:** ~25
**Pattern extraction date:** 2026-11-03
