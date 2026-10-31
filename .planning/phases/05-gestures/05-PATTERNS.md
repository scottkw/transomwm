# Phase 5: Gestures - Pattern Map

**Mapped:** 2026-10-28
**Files analyzed:** 17 (new + modified)
**Analogs found:** 16 / 17

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Sources/TransomMac/Input/GestureTap.swift` (new) | input tap | event-driven (C callback -> AsyncStream) | `Sources/TransomMac/Input/InputTap.swift` | exact |
| `Sources/TransomMac/Input/GestureTapRules.swift` (new) | pure rules | transform (event -> consume/pass) | `Sources/TransomMac/Input/ZoomTapRules.swift` | exact |
| `Sources/TransomEngine/GestureRecognizer.swift` (new) | engine state machine | transform (samples -> SnapDecision) | `Sources/TransomEngine/Navigator.swift` (pure static target picking) | role-match |
| `Sources/TransomEngine/Arranger+Camera.swift` (modify: split `zoomTo` into non-mutating preview + commit) | engine | request-response | itself, `zoomTo` lines 204-255 | exact |
| `Sources/TransomMac/Zoom/GestureController.swift` (new) | main-actor glue | event-driven | `Sources/TransomMac/Zoom/ZoomInput.swift` + `ZoomController.run` | role-match |
| `Sources/TransomMac/Zoom/ZoomController.swift` (modify: `.following` phase, begin/follow/endFollow) | controller | event-driven | itself, `Phase` enum line 16, `run` line 71 | exact |
| `Sources/TransomMac/Zoom/StagePanel.swift` (modify: `follow(progress:)`, `springBack`) | AppKit view | animation | itself, `show`/`retarget`/`fadeOut` lines 108-186 | exact |
| `Sources/TransomMac/ArrangeController.swift` (modify: own GestureTap, watchdog ticks both) | controller | lifecycle | itself, `startWatchdog`/`watchdogTick` lines 216-252 | exact |
| `Sources/TransomPrivate/MultitouchSupport.swift` (new) | private-API shim | dlsym + C callback | `Sources/TransomPrivate/SkyLightSpaces.swift`, `AXWindowID.swift` | exact |
| `Sources/TransomPrivate/Capabilities.swift` (modify: `case multitouch`, only if MT ships) | config/registry | — | itself lines 1-60 | exact |
| `Sources/TransomMac/Input/MultitouchDevices.swift` (conditional) | device lifecycle | event-driven | `Sources/TransomMac/SessionGate.swift` (wake observers 32-35) | partial |
| `Sources/TransomMac/Shell/GestureCopy.swift` (new) | copy strings | pure | `Sources/TransomMac/Shell/ZoomCopy.swift` | exact |
| `Sources/transom-gesture-spike/main.swift` (new) + `Package.swift` target | CLI | batch / JSON lines | `Sources/transom-zoom-spike/main.swift`, `Package.swift:34` | exact |
| `scripts/vm-spike.sh` (generalize product) or sibling | script | batch | `scripts/vm-spike.sh` | exact |
| `Tests/TransomMacTests/GestureTapRulesTests.swift` | test | — | `Tests/TransomMacTests/ZoomTapRulesTests.swift` | exact |
| `Tests/TransomEngineTests/GestureRecognizerTests.swift` + `Fixtures/Gestures/*.jsonl` | test | fixture-driven | `Tests/TransomEngineTests/NavigatorTests.swift`, `Fixtures/AXDumps` | role-match |
| `Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift` | VM live test | event-driven | `Tests/TransomMacIntegrationTests/ArrangeIntegrationTests.swift` (TRANSOM_LIVE gating) | role-match (no existing synthetic-event + tail-tap helper) |

## Pattern Assignments

### `GestureTap.swift` — copy `InputTap.swift` whole

Structure to clone (InputTap.swift):
- lines 26-48: `nonisolated private final class TapBox: @unchecked Sendable` holding the continuation, `OSAllocatedUnfairLock<State>` for state published from main, tap-thread-only latch vars, `port`, `runLoop`.
- line 67: mask. Gesture version (RESEARCH Pattern 1): `(1 << CGEventType.scrollWheel.rawValue) | (1 << 29)`; never `1 << 30` (DockControl).
- lines 70-73: bounded stream `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))`.
- lines 82-85: `setZoomState` -> `setGestureState(_:)` whole-swap under lock.
- lines 88-123: `start()` (semaphore-synchronised own `Thread`, `CFRunLoopAddSource(.commonModes)`, `qualityOfService = .userInteractive`, thread name) and `stop()`.
- lines 128-136: `watchdogTick()` with trial port (refused trial -> `stop()`).
- lines 140-190: the single `makePort(_ box: TapBox?)`; callback re-enables on `.tapDisabledByTimeout/.tapDisabledByUserInput` (144-147), honours `ZoomTapRules.repostTag` in `eventSourceUserData` (148-150), reads state via `withLock { $0 }`, calls the pure rules, `return nil` to consume, else `Unmanaged.passUnretained(event)`. No AX, logging or file I/O in the callback.

```swift
return CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
    callback: callback, userInfo: box.map { Unmanaged.passUnretained($0).toOpaque() })
```

### `GestureTapRules.swift` — copy `ZoomTapRules.swift` (lines 1-82)

- `nonisolated struct ZoomTapState: Equatable, Sendable` (lines 3-16) with `armed`, `deskDisplays: [CGRect]` -> `GestureTapState` (armed, desk displays, wallpaper/latch inputs).
- `nonisolated enum ZoomTapRules` with nested `Swallow` (latch), `Kind`, `Decision { case pass; case consume(Kind?) }` (lines 19-31).
- `decide(...)` (lines 48-81): latch decided at gesture *begin* only, every begin decides afresh (mirror the "every mouse-down decides afresh, so a lost mouse-up can never trap the next click" rule), `defer { swallow = .none }` on end.
- Reuse `chordMask` style (line 36) for the ⌥ check.

### `GestureRecognizer.swift` (TransomEngine, AppKit-free, `Double` only)

Analog: `Navigator.swift` — `public enum Navigator` of pure `static func`s returning optional targets (`stepIn` line 82, `stepOut` 74, `pan` 97) and a `public enum Refusal: Error, Equatable, Sendable` (line 7). Recognizer feeds those for snap targets; refusal copy in GestureCopy derives from `Refusal`, never retyped (UI-SPEC). Must pass `scripts/check-no-appkit.sh`.

### `Arranger+Camera.swift` split

Current `mutating func zoomTo` (lines 204-255): guards (`camera.enabled`, paused, display/desk, node exists, `target != current`), two `ViewPlanner.plan` calls, tile list, then mutation only at the end:
```swift
camera.nextMoveID += 1
camera.pending[uuid] = PendingMove(id: camera.nextMoveID, key: key, target: target, kind: kind, focus: focus)
let move = CameraMove(id: camera.nextMoveID, displayUUID: uuid, from: current, to: target, tiles: ...)
return notes + [.cameraMove(move)]
```
Split: everything above `camera.nextMoveID += 1` becomes non-mutating `previewMove(to:displayUUID:)` returning tiles/refusal (note: `effectiveView(for:notes:)` is `mutating` — use `currentView`/`resolvedView` for the preview); `zoomTo` keeps the tail. Settle/history path untouched. Tests go in `Tests/TransomEngineTests/ArrangerCameraTests.swift`.

### `StagePanel.swift` follow/springBack

Copy from `show(tiles:)` (108-118, `CATransaction.setDisableActions(true)` for instant placement) for `follow(progress:)` (interpolate start->end per tile, no implicit animation), and from `retarget` (147-171, `layer.move(from: layer.currentRect, to: ..., timing: Self.moveTiming)`) for `springBack` (to `tile.start`, 250 ms) followed by `fadeOut` (174-186). Respect the `crossfade` (Reduce Motion) branch the same way.

### `ZoomController.swift` follow phase

Extend `enum Phase: String { case capturing, moving, settling, revealing }` (line 16) with `following`; `run(_ move:settle:)` (line 71) is the commit path; capture via `captureStart` (165) and `show` (180) at follow begin.

### `ArrangeController.swift` lifecycle

`startWatchdog` (216-238) 2 s `Task` loop plus `didActivateApplicationNotification`; `watchdogTick` (240-252) restarts/refuses the tap and logs. Add `gestureTap.watchdogTick()` here; create the gesture tap only when zoom on + ready; stop it in `stopTap()` (~line 210) next to `tap.stop()`.

### `MultitouchSupport.swift` — copy `SkyLightSpaces.swift`

```swift
typealias MainConnectionID = @convention(c) () -> Int32
private static let functions: (...)? = {
    guard !Capabilities.isForcedOff(.spaces),
          let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let main = dlsym(handle, "SLSMainConnectionID"), ...
    else { return nil }
    let current = dlsym(handle, "...").map { unsafeBitCast($0, to: CurrentSpace.self) }   // optional symbol
    return (...)
}()
public static var isLoaded: Bool { functions != nil }
```
Plus `Capabilities.recordFailure/recordSuccess` use (SkyLightSpaces lines ~45-55). Doc-comment the signature provenance (OpenMultitouchSupport header, MIT) as SkyLightSpaces does for yabai. `AXWindowID.swift` is the minimal single-symbol form. Never link-time.

### `Capabilities.swift`

Add `case multitouch = "Multitouch"` to `enum Capability` (lines 4-16), its `fallback` string ("hotkeys and overlay pinch"), and `case .multitouch: MultitouchSupport.isLoaded` in `session` (lines 54-59). Update `Tests/TransomMacTests/CapabilitiesTests.swift`.

### `GestureCopy.swift` — copy `ZoomCopy.swift`

`import TransomEngine; import TransomModel; nonisolated public enum ZoomCopy { // MARK: ... public static let ... ; public static func ...(...) -> String }`, reusing `MenuCopy.truncatedAppName`. Tests mirror `Tests/TransomMacTests/MenuCopyTests.swift` (ZoomCopy tests alongside).

### `transom-gesture-spike/main.swift` — copy `transom-zoom-spike/main.swift` lines 1-50

Header comment stating where it runs; `let usage = """..."""`; `fail(_:_:) -> Never` writing to stderr with exit code 64; hand-rolled `options`/`flags`/`positionals` parse loop; one JSON line per measurement with a `"gate"` key, `--out path`. Package.swift line 34 pattern:
```swift
.executableTarget(name: "transom-zoom-spike", dependencies: ["TransomMac", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
```
Host half (user-run) prints `AXIsProcessTrusted()` / `CGPreflightListenEventAccess()` / `CGPreflightPostEventAccess()` first.

### `scripts/vm-spike.sh`

Product is hard-wired at lines 25, 29 and 49 (`transom-zoom-spike`). Generalize with e.g. `SPIKE_PRODUCT="${SPIKE_PRODUCT:-transom-zoom-spike}"`; keep the `.build/transom-vm.lock` mutex (lines 20-22), caffeinate on both sides, Transom quit/relaunch, results to `.build/spike/<sub>-<ts>/`.

### Tests

`ZoomTapRulesTests.swift` (lines 1-30): `@testable import TransomMac`, `import Testing`, file-private fixtures (`armed` state), a private `decide(...)` helper with defaults, `@Suite struct`, `@Test func` sentences, `#expect(... == .consume(...))` sequences including the "next press is the app's again" check. Copy for GestureTapRulesTests. GestureRecognizer traces: JSONL under `Tests/TransomEngineTests/Fixtures/Gestures/`, sibling of `Fixtures/AXDumps`.

## Shared Patterns

- **Tap callback discipline** (InputTap 50-55 doc + 140-190): copy fields, pure rule lookup, consume or pass; never AX/log/IO. Apply to GestureTap and any MT contact callback (bridge to main via `Unmanaged` refcon + hop).
- **State publish from main** via `OSAllocatedUnfairLock` whole-value swap (InputTap 63-65, 78-85). Apply to GestureTap and MT shim.
- **Private API**: dlopen/dlsym into optional `static let`, `Capabilities.isForcedOff` guard, `--disable-private=` name. Apply to MultitouchSupport.
- **Logging**: `Logger(subsystem: "com.eightabyte.transom", category: ...)` (Capabilities line 20); category `private` for capability loss.
- **AppKit-free engine**: GestureRecognizer + Arranger changes must pass `scripts/check-no-appkit.sh`.
- **Live tests VM-only** through `scripts/vm-live-test.sh` / `vm-spike.sh`; never on host.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| Synthetic-event poster + downstream listen-only tail tap helper (in GestureTapIntegrationTests) | test helper | event-driven | No existing test posts CGEvents and observes downstream; use RESEARCH.md Code Examples |

## Metadata

**Analog search scope:** Sources/TransomMac/{Input,Zoom,Shell}, Sources/TransomEngine, Sources/TransomPrivate, Sources/transom-zoom-spike, scripts, Tests/*
**Files scanned:** ~20
**Pattern extraction date:** 2026-10-28
