# Phase 3: Tiling MVP - Pattern Map

**Mapped:** 2026-10-25
**Files analyzed:** 38 (new + modified, from 03-CONTEXT.md, 03-RESEARCH.md "Recommended Project Structure", 03-UI-SPEC.md)
**Analogs found:** 27 / 38. The event tap, overlay panels, toast, KeyboardShortcuts table, CFPreferences I/O and release script have no in-repo analog. Use the RESEARCH.md skeletons for those.

All analog paths below are git-tracked (`git ls-files Sources Tests scripts`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Package.swift` (modify: add KeyboardShortcuts 3.1.0 to PaneMac) | config | n/a | itself (lines 1-36) | exact |
| `Sources/PaneModel/LayoutTree.swift` (modify: `Node.desktop(hidden:)`, at most one desktop leaf in `validate`) | model | transform | itself (lines 5-28, 62-110) | exact |
| `Sources/PaneModel/TreeEdits.swift` (modify: swap, balance, rotate, flip, resizeChild, setDesktopHidden) | model (edits) | transform | itself, `insert` (lines 25-66) | exact |
| `Sources/PaneModel/Neighbours.swift` (new) | utility (pure) | transform | `Sources/PaneModel/DropZones.swift` (hit-test over resolved rects) | role-match |
| `Sources/PaneModel/Snap.swift` (new) | utility (pure) | transform | `Sources/PaneModel/DropZones.swift` / `Geometry.swift` | role-match |
| `Sources/PaneModel/Resolve.swift` (modify: desktop minimum) | utility | transform | itself | exact |
| `Sources/PaneModel/World.swift` + `Undo.swift` (modify: Desk invariant, `rekey`, floating frames) | model | CRUD | itself (`edit` / `apply`) | exact |
| `Sources/PaneEngine/Arranger.swift` (new, the layout owner) | store/reducer | event-driven | `Sources/PaneEngine/PermissionReducer.swift` | role-match |
| `Sources/PaneEngine/Planner.swift` (new) | utility | transform | `Sources/PaneModel/Resolve.swift` | role-match |
| `Sources/PaneEngine/DragSession.swift` (new, drag detector) | state machine | event-driven | `PermissionReducer.swift` (state + event enum + effects, `Duration` time) | role-match |
| `Sources/PaneEngine/Command.swift` (new) | model (enum + enablement) | request-response | `Sources/PaneEngine/WindowSystem.swift` `WindowCommand` (lines 120-126) | partial |
| `Sources/PaneEngine/PaneURL.swift` (new, strict `pane://` parser) | utility (validation) | transform | `ExclusionStore.isValid` (`Sources/PaneMac/ExclusionStore.swift` 34-38) | partial |
| `Sources/PaneEngine/Recovery.swift` (new: stranded rule, crash-loop rule) | utility (decision table) | transform | `Sources/PaneEngine/CloseRule.swift` | role-match |
| `Sources/PaneEngine/ConflictPolicy.swift` (new) | reducer | event-driven | `PermissionReducer.swift` | role-match |
| `Sources/PaneEngine/LifecycleSync.swift` (modify: `windowRekeyed`) | service | event-driven | itself (lines 22-39) | exact |
| `Sources/PaneEngine/ExclusionFilter.swift` (unchanged; every new command goes through it) | utility | transform | itself | exact |
| `Sources/PaneMac/ArrangeController.swift` (new: MainActor shell, events reader, fan-out) | controller | event-driven | `Sources/PaneMac/Shell/StatusItemController.swift` 46-51 (the `for await system.events` loop) + `PaneMacApp.swift` wiring | partial |
| `Sources/PaneMac/Input/InputTap.swift` (new: event tap thread + watchdog + button-rect cache) | service (thread) | event-driven | `Sources/PaneMac/AX/AXAppThread.swift` 88-130 (own thread + CFRunLoop + `Unmanaged` refcon C callback) | partial |
| `Sources/PaneMac/Input/Hotkeys.swift` (new: KeyboardShortcuts.Name table → Command) | config/registry | event-driven | none | none |
| `Sources/PaneMac/Overlay/PreviewPanel.swift`, `GapHandles.swift`, `Toast.swift` (new) | component | event-driven | none (Setup window is a titled NSWindow, not a panel) | none |
| `Sources/PaneMac/LayoutStore.swift` (new) | store | file-I/O | `Sources/PaneMac/MinimumHintsStore.swift` | exact |
| `Sources/PaneMac/WindowManagerSettings.swift` (new: CFPreferences for com.apple.WindowManager) | store | CRUD | `Sources/PaneMac/ExclusionStore.swift` (defaults read + validate + log) | partial |
| `Sources/PaneMac/AppDelegate.swift` (new: `terminateLater`, `application(_:open:)`) | entry point | request-response | `Sources/PaneMac/PaneMacApp.swift` 17-50 | partial |
| `Sources/PaneMac/AXWindowSystem.swift` (modify: park, focus, raise, setHidden in `perform`) | service | request-response | itself, `perform` (lines 174-194) | exact |
| `Sources/PaneMac/AX/*` Finder split by AX menu press, green-button frames | adapter | request-response | `Sources/PaneMac/AX/AXSnapshotReader.swift` 41, 148, 166 (`AXUIElementCopyAttributeValue` helpers) | partial |
| `Sources/PanePrivate/SkyLightSpaces.swift` (modify: `currentSpace(displayUUID:)`) | private-API shim | request-response | itself (lines 18-28) | exact |
| `Sources/PaneMac/Shell/StatusItemController.swift` + `MenuCopy.swift` (modify: Arrange / Safety / Gaps / conflict line, ⌥-only Debug) | component | event-driven | itself (`menuNeedsUpdate` 59-75, `addExclusionItems` 107-135) | exact |
| `Sources/PaneTestSupport/FakeWindowSystem.swift` (modify: park, focus, raise, setHidden) | test support | event-driven | itself, `perform` (lines 362-374) | exact |
| `scripts/release.sh` (new) | script | n/a | `scripts/build-debug.sh` | role-match |
| `Tests/PaneModelTests/TreeEditTests.swift`, `NeighboursTests`, `SnapTests`, `DesktopLeafTests` | test | n/a | `Tests/PaneModelTests/TreeEditTests.swift` 1-30 | exact |
| `Tests/PaneEngineTests/ArrangerTests`, `PlannerTests`, `DragSessionTests`, `PaneURLTests`, `RecoveryTests`, `ConflictPolicyTests`, `LifecycleSyncTests` (rekey) | test | n/a | `Tests/PaneEngineTests/LifecycleSyncTests.swift`, `PermissionReducerTests.swift` | exact |
| `Tests/PaneMacTests/LayoutStoreTests.swift` | test | file-I/O | `Tests/PaneMacTests/MinimumHintsStoreTests.swift` | exact |
| `Tests/PaneMacTests/WindowManagerSettingsTests.swift` | test | CRUD | `Tests/PaneMacTests/MinimumHintsStoreTests.swift` (temp-dir fixture style); use a suite-named `UserDefaults` | partial |
| `Tests/PaneMacIntegrationTests/*` (park/focus/raise against the fixture app) | integration test | n/a | `Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift` + `IntegrationSupport.swift` | exact |

## Pattern Assignments

### `Sources/PaneMac/LayoutStore.swift` (store, file-I/O)

**Analog:** `Sources/PaneMac/MinimumHintsStore.swift` (140 lines). Copy the whole shape: error enum, constants, `load` that rejects and sets aside, atomic `save`, staged `decode`.

Error enum and constants (lines 5-27):
```swift
public enum HintsError: Error, Equatable {
    case tooLarge(Int), newerVersion(Int), corrupt(String), invalidEntry(String), writeFailed(String)
}
@MainActor public final class MinimumHintsStore {
    nonisolated public static let fileName = "min-size-hints.json"
    nonisolated public static let maxBytes = 65_536
    nonisolated public static let schemaVersion = 1
    nonisolated public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Pane", directoryHint: .isDirectory)
    }
    private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "hints")
```
Load with set-aside (lines 47-58):
```swift
guard FileManager.default.fileExists(atPath: file.path) else { return }
do { hints = try Self.decode(file) } catch {
    loadError = error
    Self.logger.error("rejected \(Self.fileName, privacy: .public): ...")
    setAside()
}
```
Atomic save (lines 71-84):
```swift
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(contents).write(to: file, options: .atomic)
} catch { throw .writeFailed(String(describing: error)) }
```
Decode order (lines 87-124): size cap, `VersionProbe` decode, `newerVersion` / unknown version, full decode, per-entry validation with indexed messages. For layout.json, the per-entry step is `World`'s own validated decode (`Sources/PaneModel/Persistence.swift`) plus home-frame `isValidGeometry` checks. Keep `.corrupt` set-aside (lines 131-139). The clean-exit flag goes in the same `Contents`. Raise `maxBytes` to suit many desks.

---

### `Sources/PaneModel/TreeEdits.swift` (modify: new edits)

**Analog:** `insert` in the same file (lines 25-66). Every edit works on `var next = self` (and `nextIDs`), then `normalize()`, `try next.validate()`, and commits only at the end:
```swift
// Every edit works on copies of the tree and the ID source and commits both only on success,
// so a throwing edit leaves no trace.
guard let targetNode = nodes[target] else { throw .nodeNotFound(target) }
var next = self
...
next.normalize()
try next.validate()
self = next
ids = nextIDs
```
Use typed throws `throws(LayoutError)` and reuse the existing cases (`nodeNotFound`, `windowNotFound`, `notASplit`, `notALeaf`, `invariantViolated`; `LayoutTree.swift` 11-28). Add new cases only when none fits. The switch on `.split / .panel / .tabs` (lines 38-47, and `LayoutTree.swift` 82-110) gains a `.desktop` arm everywhere, so the compiler will list every site.

**Tests:** `Tests/PaneModelTests/TreeEditTests.swift` 1-30 helpers `tree(root:_:)`, `h(...)`, `v(...)`, `n(_:)`, `makeWindow`. Extend `tree(...)`'s switch with `.desktop`.

---

### `Sources/PaneEngine/LifecycleSync.swift` (modify: `windowRekeyed`)

**Analog:** itself, lines 22-39. Move `.windowRekeyed` out of the ignored list (line 35) into its own case that calls the new `World.rekey`. Keep the rule from the doc comment: changes go through `World.apply`-style paths, never `World.edit`, so OS facts never land on the undo stack.
```swift
case .windowStateChanged(let window, let state):
    guard let key = world.desks.keys.sorted().first(where: { world.desks[$0]?.contains(window) == true }) else {
        return false
    }
    try world.apply(state, for: window, on: key, history: &history)
    return true
```
**Tests:** `Tests/PaneEngineTests/LifecycleSyncTests.swift` 1-30 (`ref(_:)`, `world(_:history:)` built through `world.edit` + `insertRoot`/`insert`).

---

### `Sources/PaneEngine/Arranger.swift`, `DragSession.swift`, `ConflictPolicy.swift` (reducers, event-driven)

**Analog:** `Sources/PaneEngine/PermissionReducer.swift` (lines 1-50+). Pure state machine. The caller passes time as `Duration`, so tests need no clock. The shell runs the returned effects in order.
```swift
// ... The controller in PaneMac feeds it UI clicks, 1 s poll ticks and probe/reset results,
// then runs the returned effects in order. Times are `Duration`s since app launch, measured by the caller.
public enum PermissionPhase: Equatable, Sendable { case notTrusted, waitingForGrant, probing, ready, ... }
public struct PermissionState: Equatable, Sendable { public var phase: PermissionPhase = .notTrusted ... }
public enum PermissionEvent: Equatable, Sendable {
    case launched(trusted: Bool)
    case pollTick(trusted: Bool, at: Duration)
```
Arranger inputs are `WindowEvent`, `PointerEvent`, `Command`, `Tick(at:)`, `Conflicts` and `Displays`. Its outputs are `[WindowCommand]` plus `[Effect]` (preview, toast, save-debounced / save-now, beep). The 150 ms dwell and the 0.5 s save debounce are `Duration` comparisons inside the reducer. PaneEngine must stay AppKit-free (`scripts/check-no-appkit.sh`).

**Tests:** `Tests/PaneEngineTests/PermissionReducerTests.swift` style (event, then state and effects `#expect`). Use `LifecycleSyncTests.swift` helpers for World fixtures.

---

### `Sources/PaneEngine/Planner.swift` (utility, transform)

**Analog:** `Sources/PaneModel/Resolve.swift`, a pure function over values with typed throws that returns frames plus the windows that don't fit. Planner wraps `resolve`, adding gap, Desktop rect, parks for hidden-Desktop windows, and `unfit`, and emits `[WindowCommand]` (`WindowSystem.swift` 120-126):
```swift
public enum WindowCommand: Equatable, Sendable {
    case setFrame(WindowRef, Rect)
    case park(WindowRef, displayUUID: String)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
}
```

---

### `Sources/PaneEngine/Recovery.swift`, `PaneURL.swift` (decision table / strict parser)

**Analog:** `Sources/PaneEngine/CloseRule.swift` (pure decision table, 1 file + `CloseRuleTests.swift`). For the URL whitelist validation style, copy `ExclusionStore.isValid` (`ExclusionStore.swift` 34-38):
```swift
public static func isValid(_ bundleID: String) -> Bool {
    (1...255).contains(bundleID.utf8.count)
        && bundleID.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-") }
}
```
Reject anything outside the three commands. Return nil, never a best guess.

---

### `Sources/PaneMac/AXWindowSystem.swift` (modify `perform`)

**Analog:** itself, lines 174-194. Replace the `guard case .setFrame ... else { logger.info("dropping ...") }` with a `switch command`. Keep the existing order: `ExclusionFilter.admit` first, then validity, then tracked lookup, then route to `threads[ref.pid]` (all AX work on the app thread, never on main).
```swift
let split = ExclusionFilter.admit(commands, excluded: excluded)
for command in split.admitted {
    guard case .setFrame(let ref, let rect) = command else {
        logger.info("dropping a command other than setFrame: not implemented before Phase 3")
        continue
    }
    guard rect.isValidGeometry else { ... }
    guard let info = tracker.info(for: ref.identity), let thread = threads[ref.pid] else { ... }
    thread.enqueueFrame(windowID: info.visibleMemberID ?? ref.windowID, rect: rect, ref: info.window)
}
```
Also update the doc comment at line 172.

### `Sources/PaneTestSupport/FakeWindowSystem.swift` (modify `perform`)

**Analog:** itself, lines 362-374. Keep `performed += commands` and `dropped += split.dropped`, and add arms for park, focus, raise and setHidden that mutate the fake's per-window state and `yield` the events a real system would emit (`yield(_:)` at 334-336). Respect `app.hung` the way `setFrame` holds frames.
```swift
performed += commands
let split = ExclusionFilter.admit(commands, excluded: excluded)
dropped += split.dropped
for case .setFrame(let ref, let rect) in split.admitted where rect.isValidGeometry {
    guard let app = apps[ref.pid], !app.terminated else { continue }
    if app.hung || !responsiveness.shouldRefresh(pid: ref.pid) { heldFrames[ref.identity] = (ref, rect) } else { write(rect, to: ref) }
}
```

---

### `Sources/PaneMac/Input/InputTap.swift` (thread + C callback)

**Analog:** `Sources/PaneMac/AX/AXAppThread.swift`. Copy the dedicated `Thread` that owns a `CFRunLoop` (lines 88-108) and the `Unmanaged` refcon bridge in a C callback (lines 113-125):
```swift
let thread = Thread { [self] in
    runLoop = CFRunLoopGetCurrent()
    ...
    CFRunLoopRun()
}
thread.name = "AXAppThread \(pid)"
...
let callback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let me = Unmanaged<AXAppThread>.fromOpaque(refcon).takeUnretainedValue()
    me.hints.yield(AXEventHint(...))   // copy facts out, yield to an AsyncStream; no AX in the callback
}
let refcon = Unmanaged.passUnretained(self).toOpaque()
```
The class is `nonisolated final class ...: @unchecked Sendable`, as at line 18. The tap source replaces the keep-alive source. Handle `.tapDisabledByTimeout` / `.tapDisabledByUserInput` and the watchdog using the RESEARCH skeleton.

---

### `Sources/PanePrivate/SkyLightSpaces.swift` (modify: current Space per display)

**Analog:** itself, lines 18-28. Add `SLSManagedDisplayGetCurrentSpace` to the same lazily resolved optional tuple, gated by `Capabilities.isForcedOff(.spaces)`:
```swift
private static let functions: (connection: Int32, copySpaces: CopySpacesForWindows)? = {
    guard !Capabilities.isForcedOff(.spaces),
          let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let main = dlsym(handle, "SLSMainConnectionID"),
          let copy = dlsym(handle, "SLSCopySpacesForWindows")
    else { return nil }
    return (unsafeBitCast(main, to: MainConnectionID.self)(), unsafeBitCast(copy, to: CopySpacesForWindows.self))
}()
```

---

### `Sources/PaneMac/WindowManagerSettings.swift` (CFPreferences)

**Analog:** `Sources/PaneMac/ExclusionStore.swift` 11-31: `@MainActor public final class`, inject the backing store in `init` for tests, treat stored values as user-writable, and log and drop bad values:
```swift
private let defaults: UserDefaults
private static let logger = Logger(subsystem: "com.eightabyte.pane", category: "exclusions")
public init(defaults: UserDefaults = .standard) { ... }
```
Use `CFPreferencesCopyAppValue` / `CFPreferencesSetAppValue` + `CFPreferencesAppSynchronize` on `"com.apple.WindowManager"` behind a small protocol, so tests use a fake. Key names come from RESEARCH and are low confidence (Pitfall 15). Read back after each write. Store originals in Pane's own `UserDefaults`.

---

### `Sources/PaneMac/AppDelegate.swift` / wiring in `PaneMacApp.swift`

**Analog:** `Sources/PaneMac/PaneMacApp.swift` 17-50. Create stores, call `load()`, hand values to the system and wire `on…` callbacks with logged save failures:
```swift
let hints = MinimumHintsStore(directory: MinimumHintsStore.defaultDirectory)
hints.load()
system.setBundleHints(hints.hints)
system.onLearnedMinimum = { bundleID, minimum in
    guard hints.record(bundleID: bundleID, minimum: minimum) else { return }
    do { try hints.save() } catch { logger.error("could not save ...") }
}
```
Use a static strong reference for the delegate and the ArrangeController, like `statusItem` at line 10. Note that line 15's logger category is `"hints"`. New files should use their own category.

---

### `Sources/PaneMac/ArrangeController.swift` (MainActor shell)

**Analog:** the events loop in `StatusItemController.swift` 46-51:
```swift
Task { [weak self, system] in
    for await _ in system.events {
        self?.latest = await system.inventory()
    }
}
```
Per RESEARCH, ArrangeController becomes THE single reader of `system.events` and fans out to the StatusItemController. The existing loop above must move behind it, because two readers would split one AsyncStream.

---

### `Sources/PaneMac/Shell/StatusItemController.swift` + `MenuCopy.swift` (menu)

**Analog:** itself. `menuNeedsUpdate` (59-75) rebuilds the menu from `add…Items(to:)` sections separated by `.separator()`. Copy strings live in `MenuCopy`. A submenu follows `addExclusionItems` (122-134):
```swift
let submenu = NSMenu(title: "Never Arrange")
for entry in ... {
    let item = NSMenuItem(title: entry.title, action: #selector(removeExclusion), keyEquivalent: "")
    item.target = self
    item.representedObject = entry.bundleID
    item.state = .on
    submenu.addItem(item)
}
let item = NSMenuItem(title: "Never Arrange", action: nil, keyEquivalent: "")
item.submenu = submenu
menu.addItem(item)
```
Add `addArrangeItems`, `addSafetyItems`, a Gaps submenu (checkmark via `.state`) and the conflict line. Gate `debugMenuItem()` (line 70) on `NSEvent.modifierFlags.contains(.option)`. Menu items dispatch the same `Command` as hotkeys.

---

### Finder split by AX menu press (in `Sources/PaneMac/AX/`)

**Analog:** `Sources/PaneMac/AX/AXSnapshotReader.swift` lines 148 and 166 (attribute reads with `== .success` guards). Walk `kAXMenuBarAttribute`, find the item, then `AXUIElementPerformAction(item, kAXPressAction)`. Do it on the Finder `AXAppThread`, not on main. The repo has no `AXUIElementPerformAction` call yet.

---

### `scripts/release.sh`

**Analog:** `scripts/build-debug.sh`. Copy the header comment (purpose, usage, exit codes), `set -euo pipefail`, the repo-root `cd`, the `fail()` helper, and the codesign verification. Call `scripts/build-debug.sh --release` and take its last stdout line as the app path. Then run `notarytool submit --keychain-profile pane-notary --wait`, `stapler staple`, create-dmg, and staple the DMG.
```bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
fail() { echo "build-debug: $1" >&2; exit 1; }
codesign --verify --strict --verbose=2 "$app" >&2 || fail "codesign --verify failed for $app"
```
Version 0.2.0 is set in `xcode/project.yml`. Bump it to 0.3.0 there.

---

### `Package.swift`

**Analog:** itself. Add `dependencies: [.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0")]` and add `.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")` to the PaneMac target (line 22) only. PaneModel and PaneEngine stay dependency-free.

### `Tests/PaneMacTests/LayoutStoreTests.swift`

**Analog:** `Tests/PaneMacTests/MinimumHintsStoreTests.swift` 1-40. It has a `@MainActor @Suite` and a per-test `Directory` class with temp URL, `file`, `corrupt` and `write(_:)`, plus round-trip, sorted-output, reject-and-set-aside, and newer-version tests:
```swift
final class Directory {
    let url = FileManager.default.temporaryDirectory.appending(path: "pane-hints-\(UUID().uuidString)", directoryHint: .isDirectory)
    var file: URL { url.appending(path: MinimumHintsStore.fileName) }
    var corrupt: URL { url.appending(path: MinimumHintsStore.fileName + ".corrupt") }
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
}
```

## Shared Patterns

- **Typed throws + copy-then-commit** (`TreeEdits.swift` 3-4, 25-66): every model edit.
- **Exclusion gate** (`ExclusionFilter.admit`, `ExclusionFilter.swift` 13-21): every `[WindowCommand]` from Arranger, menu, hotkey and URL goes through `perform`, which runs `admit` first. Never bypass it.
- **Logging:** `Logger(subsystem: "com.eightabyte.pane", category: "<area>")` with `privacy: .public` only on non-personal values. No window titles (T-02-36).
- **User-writable input is validated whole** (MinimumHintsStore decode, ExclusionStore init). Apply this to layout.json, the `pane://` URL and the WindowManager prefs.
- **Pure engine, impure shell:** reducers in PaneEngine take `Duration` time and return effects. PaneMac runs them. `scripts/check-no-appkit.sh` must keep passing.
- **Undo flow:** `LifecycleSync.undo`, then `requery`, then `applyRequeried` (`LifecycleSync.swift` 45-68).
- **Tests:** Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`), private file-level fixtures (`ref(_:)`, `makeWindow`). Test-first: a RED commit comes before each behaviour change.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `Sources/PaneMac/Input/Hotkeys.swift` | registry | event-driven | No KeyboardShortcuts use yet. Use the RESEARCH table with stable `KeyboardShortcuts.Name`s. |
| `Sources/PaneMac/Overlay/PreviewPanel.swift` | component | event-driven | No NSPanel / CAShapeLayer code. Use the UI-SPEC and the RESEARCH panel skeleton (non-activating, `ignoresMouseEvents`). |
| `Sources/PaneMac/Overlay/GapHandles.swift` | component | event-driven | Same as above. |
| `Sources/PaneMac/Overlay/Toast.swift` | component | event-driven | Same as above. The only SwiftUI hosting is `SetupView` / `TrackedWindowsView`, which can be borrowed for `NSHostingView` setup. |
| `Sources/PaneMac/Input/InputTap.swift` (tap-specific parts) | service | event-driven | No CGEventTap. Thread shape only, from AXAppThread. |
| `Sources/PaneMac/WindowManagerSettings.swift` (CFPreferences calls) | store | CRUD | No CFPreferences use. Store shape only, from ExclusionStore. |
| `scripts/release.sh` (notarytool / stapler / create-dmg steps) | script | n/a | No notarisation exists yet. |

## Metadata

**Analog search scope:** `Sources/` (PaneModel, PaneEngine, PaneMac, PanePrivate, PaneTestSupport), `Tests/`, `scripts/`
**Files scanned:** ~60 tracked sources and tests (13 read directly)
**Pattern extraction date:** 2026-10-25
