# Phase 4: Zoom Camera - Pattern Map

**Mapped:** 2026-10-27
**Files analyzed:** 30 (new + modified)
**Analogs found:** 28 / 30

All analog paths below are git-tracked sources in this repo.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Sources/TransomModel/LayoutTree+Subtree.swift` (new) | model | transform | `Sources/TransomModel/LayoutTree.swift` (`init(root:nodes:states:)` L62, `parent(of:)` L135, `withDesktop()` L170) | exact |
| `Sources/TransomEngine/Camera.swift` (new: ViewTarget, ViewEntry, CameraHistory, CameraMove, TileMove) | model (value types) | transform | `Sources/TransomEngine/GapHandles.swift` (`GapHandle` struct L1-20) | role-match |
| `Sources/TransomEngine/ViewPlanner.swift` (new) | service (pure planner) | transform | `Sources/TransomEngine/Planner.swift` | exact |
| `Sources/TransomEngine/Navigator.swift` (new) | service (pure) | transform | `Sources/TransomEngine/GapHandles.swift` `GapHandles.handles(...)`; `Sources/TransomModel/Neighbours.swift` | role-match |
| `Sources/TransomEngine/SettleTracker.swift` (new) | service (pure, clock injected) | event-driven | `Sources/TransomEngine/TransomURL.swift` `TransomURLRateLimiter` (L21-33) | role-match |
| `Sources/TransomEngine/ZoomTapRules.swift` (new) | utility (pure decision) | event-driven | `Sources/TransomMac/Input/GreenButton.swift` | exact |
| `Sources/TransomEngine/Arranger+Camera.swift` (new) | service (engine extension) | request-response | `Sources/TransomEngine/Arranger+Commands.swift` | exact |
| `Sources/TransomEngine/Arranger.swift` (modify: inputs/effects, `handle` switch, `rehome` exemption L817-820, `planShown` L1501) | service | event-driven | itself | exact |
| `Sources/TransomEngine/Command.swift` (modify: 11 cases + internal `zoomTo`) | model | — | itself | exact |
| `Sources/TransomEngine/TransomURL.swift` (modify: 11 hosts) | config | request-response | itself L7 | exact |
| `Sources/TransomEngine/Recovery.swift` (modify: `homeTiles` in `terminationPlan`) | service | batch | itself L64-78 | exact |
| `Sources/TransomMac/Zoom/SnapshotCapture.swift` (new, only SCK file) | service | file-I/O (async capture) | none in repo; RESEARCH Pattern 5 sketch. Logger/async shape from `Sources/TransomMac/CGWindowList.swift` | partial |
| `Sources/TransomMac/Zoom/ZoomController.swift` (new) | controller | event-driven | `Sources/TransomMac/ArrangeController.swift` (effect switch L425-430) | role-match |
| `Sources/TransomMac/Zoom/StagePanel.swift` (new) | component (NSPanel + CA) | streaming (animation) | `Sources/TransomMac/Overlay/PreviewPanel.swift` (per-display full-frame panel + CALayer root) | exact |
| `Sources/TransomMac/Zoom/TileLayer.swift` (new) | component (CALayer) | transform | `Sources/TransomMac/Overlay/PreviewPanel.swift` `PreviewLabelView` (capsule) | role-match |
| `Sources/TransomMac/Zoom/AppColor.swift` (new) | utility | transform | none (pure hue bucketing; spec in UI-SPEC Color) | none |
| `Sources/TransomMac/Zoom/CollapsedPanels.swift` (new) | component (pooled panels) | event-driven | `Sources/TransomMac/Overlay/GapHandlePanels.swift` | exact |
| `Sources/TransomMac/Zoom/ZoomInput.swift` (new) | middleware (tap state publisher) | event-driven | `Sources/TransomMac/Input/InputTap.swift` (`greenButtons` lock + `setGreenButtons`) | exact |
| `Sources/TransomMac/Input/InputTap.swift` (modify: ZoomTapState, consume rules, re-post tag) | middleware | event-driven | itself | exact |
| `Sources/TransomMac/Input/Hotkeys.swift` (modify: 11 names + entries) | config | — | itself | exact |
| `Sources/TransomMac/Zoom/ShortcutsWindowController.swift` (new) | controller (window) | request-response | `Sources/TransomMac/Shell/TrackedWindowsWindowController.swift` | exact |
| `Sources/TransomMac/Shell/ZoomCopy.swift` (new) | utility (copy) | — | `Sources/TransomMac/Shell/MenuCopy.swift` | exact |
| `Sources/TransomMac/Shell/CommandMenu.swift`, `StatusItemController.swift` (modify: Zoom section, Shortcuts…, Debug lines) | component | — | themselves | exact |
| `Sources/TransomMac/AX/FrameWriter.swift` (modify, ladder step 1: position-only `move`) | service | file-I/O (AX) | itself `write` L12 | exact |
| `Sources/TransomMac/ArrangeController.swift` (modify: `.cameraMove` effect, `restoreForTermination` L465 homeTiles) | controller | event-driven | itself | exact |
| `Sources/transom-zoom-spike/main.swift` (new, Plan 1) + `Package.swift` target | utility (executable) | batch | `Sources/transom-dump/main.swift` + `Package.swift` L33 | exact |
| `Tests/TransomEngineTests/{Camera,ViewPlanner,Navigator,SettleTracker,ZoomTapRules,ArrangerCamera}Tests.swift` | test | — | `Tests/TransomEngineTests/ArrangerDesktopTests.swift` + `Harness` in `ArrangerLifecycleTests.swift` L44 | exact |
| `Tests/TransomMacTests/NoScreenCaptureTests.swift` (modify: allow-list one file, add literals) | test | — | itself | exact |
| `Tests/TransomMacTests/{ZoomCopy,AppColor,HotkeyTable}Tests.swift` | test | — | `MenuCopyTests.swift`, `HotkeyTableTests.swift`, `GreenButtonHitTests.swift` | exact |
| `Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift` | test (live, VM) | — | `Tests/TransomMacIntegrationTests/FocusParkIntegrationTests.swift` / `QuitRestoreIntegrationTests.swift` (TRANSOM_LIVE gated) | role-match |

## Pattern Assignments

### `Sources/TransomEngine/ZoomTapRules.swift` (pure tap rule)

**Analog:** `Sources/TransomMac/Input/GreenButton.swift` (whole file, L1-24). Copy shape exactly: `nonisolated enum`, one static func taking `type, location, flags, ...state, swallowing: inout Bool`, swallow the whole click once the down is taken.
```swift
nonisolated enum GreenButton {
    static func shouldSwallow(
        type: CGEventType, location: CGPoint, flags: CGEventFlags, windowID: UInt32, rects: [UInt32: CGRect], swallowing: inout Bool
    ) -> Bool {
        switch type {
        case .leftMouseDown:
            swallowing = !flags.contains(.maskAlternate) && rects[windowID]?.contains(location) == true
            return swallowing
        case .leftMouseDragged:
            return swallowing
        case .leftMouseUp:
            defer { swallowing = false }
            return swallowing
        default:
            return false
        }
    }
}
```
Note: TransomEngine may not import AppKit; CoreGraphics `CGEventType` is fine but if kept in Engine, prefer Engine-native types or place next to GreenButton in TransomMac (RESEARCH allows either). Test analog: `Tests/TransomMacTests/GreenButtonHitTests.swift` L1-30 (private `swallow(...)` helper, `var swallowing`, sequences of down/drag/up).

### `Sources/TransomMac/Input/InputTap.swift` + `Zoom/ZoomInput.swift` (published state)

**Analog:** `InputTap.swift` itself.
- Lock-published state (L51-52, L64-67): `private let greenButtons = OSAllocatedUnfairLock(initialState: [UInt32: CGRect]())` and `func setGreenButtons(_ rects:) { greenButtons.withLock { $0 = rects } }` — add `ZoomTapState` the same way (swap whole value).
- `TapBox` (L25-37) holds the lock and `var swallowing` (tap-thread only) — add a second `zoomSwallowing` flag.
- Callback (L123-146): copy-lock, pay for `CGWindowList.topmostWindow(at:)` only when the point is inside a published rect (L134-136), decide, `yield` a `TapEvent` with a new `Kind` case, return `nil` to consume. Add `TapEvent.Kind` cases (L9-13) for rect-band / pick / title double-click.
- Mask (L54-55) stays mouse-only (T-03-28). Esc comes from `KeyboardShortcuts.events(for:)`, not the tap.
- Re-post tag: check `event.getIntegerValueField(.eventSourceUserData)` first in the callback and pass tagged events.

### `Sources/TransomEngine/ViewPlanner.swift`

**Analog:** `Sources/TransomEngine/Planner.swift`. Pure `public enum` with a static `throws(LayoutError)` function and an `Equatable, Sendable` result struct (L7-13, L16-28):
```swift
public struct FramePlan: Equatable, Sendable {
    public var frames: [WindowRef: Rect]
    public var parks: [WindowRef]
    public var unfit: Set<WindowRef>
    public var desktopRect: Rect?
    public var resolution: Resolution
}
public enum Planner {
    public static func plan(
        desk: Desk, area: Rect, gap: Double, mins: [WindowRef: Size], wanted: [WindowIdentity: Rect] = [:],
        floors: [WindowIdentity: Size] = [:]
    ) throws(LayoutError) -> FramePlan {
```
ViewPlanner wraps it: `.home` -> `Planner.plan` unchanged; `.node(X)` -> temporary `Desk` with `tree.subtree(at: X)`, everything outside -> `parks`; zoom-on two-pass collapse (RESEARCH Pattern 3). Doc-comment style: dense `///` citing requirement IDs.

### `Sources/TransomModel/LayoutTree+Subtree.swift`

**Analog:** `Sources/TransomModel/LayoutTree.swift`. Build through the validating `public init(root: NodeID?, nodes: [NodeID: Node], states: [WindowIdentity: WindowState]) throws(LayoutError)` (L62). `parent(of:)` (L135) is a linear scan — store ancestor paths in `ViewEntry`. Tests: `Tests/TransomModelTests/TreeEditTests.swift`, `InvariantTests.swift`.

### `Sources/TransomEngine/Navigator.swift`

**Analog:** `Arranger+Commands.swift` `moveOrSnap` L11-24 shows the resolve-then-neighbour flow:
```swift
let resolution = try Planner.plan(desk: desk, area: area, gap: gap, mins: minimums).resolution
guard let leaf = desk.tree.leaf(containing: window), let rect = resolution.nodeRects[leaf],
    let neighbour = Neighbours.neighbour(
        of: rect, excluding: leaf, toward: edge, tree: desk.tree, resolution: resolution, gap: gap, recency: recency(on: desk))
else { return [.beep] }
```
Pan needs a depth-filtered variant of `Neighbours.neighbour` (`Sources/TransomModel/Neighbours.swift` L21-27 skips splits). Keep Navigator a pure `public enum` like `GapHandles` (`GapHandles.swift` L22-30) returning a target or a refusal reason enum.

### `Sources/TransomEngine/Arranger+Camera.swift` and `Arranger.swift` changes

**Analog:** `Arranger+Commands.swift` (extension with `mutating func ... throws(LayoutError) -> [ArrangerEffect]`, guard-or-`[.beep]`).
- Inputs/effects enums: `Arranger.swift` L4-27 (`ArrangerInput`) and L58-82 (`ArrangerEffect`) — add `zoomEnabled(Bool)`, `cameraSettle(displayUUID:moveID:)`, `.cameraMove(CameraMove)`, `.collapsedBlocks(...)` alongside `.gapHandles([GapHandle], displayUUID:)` (L81).
- Command dispatch switch: L259-277 `case (.command, focused)` pattern `case (.stepIn, _): return try stepIn(...)`.
- Refusals: return `[.beep, .announce(ZoomCopy...)]` plus `.info(...)` log effect (L61-65).
- `rehome` exemption at L817-820: add `!parkRequested.contains(info.window.identity)`.
- `planShown()` L1501 (park/save-before-park L1529-1567, quoted in RESEARCH Pattern 1) — make view-aware; do not bypass it.
- Default `zoomEnabled = false` so existing tests are untouched.

### `Sources/TransomEngine/SettleTracker.swift`

**Analog:** `TransomURLRateLimiter` (`TransomURL.swift` L21-33): small `public struct ...: Sendable`, private state, `mutating` funcs taking `at now: ContinuousClock.Instant` (clock injected, testable):
```swift
public mutating func admit(_ command: Command, at now: ContinuousClock.Instant) -> Bool {
    if let last = lastAdmitted[command], now - last < Self.interval { return false }
    lastAdmitted[command] = now
    return true
}
```
Use `static let` constants for 50 ms / 1500 ms.

### `Sources/TransomEngine/Command.swift` / `TransomURL.swift`

Append cases to `Command` (L5-34) with a `///` line each, never rename. Add hosts to the dictionary at `TransomURL.swift` L7:
```swift
static let commands: [String: Command] = ["restore": .restoreAll, "toggle-desktop": .toggleDesktop, "split-finder": .finderSplit]
```
Tests: `Tests/TransomEngineTests/TransomURLTests.swift`, `CommandTests.swift`.

### `Sources/TransomMac/Input/Hotkeys.swift`

Add to the `KeyboardShortcuts.Name` extension (L6-40) e.g. `static let zoomOutAll = Self("zoomOutAll", initial: .init(.o, modifiers: [.control, .option, .command]))` and append `(name, command)` tuples to `Hotkeys.entries` (L44-78). `register` (L81-85) unchanged; add enable/disable for the 11 zoom names. Update `HotkeyTableTests.swift` L12-20 expected raw-name list.

### `Sources/TransomMac/Zoom/StagePanel.swift`

**Analog:** `Sources/TransomMac/Overlay/PreviewPanel.swift` — never-key panel subclass (L7-10), appearance-aware content view (L13-20), `PreviewPresenter` per-display `Overlay { panel, view, root: CALayer }` (L63-70). Panel config to copy (from `GapHandlePanels.makePanel`, `GapHandlePanels.swift` L169-184):
```swift
let panel = HandlePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
panel.ignoresMouseEvents = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
panel.sharingType = .none
panel.isOpaque = false          // stage: true (opaque backdrop)
panel.backgroundColor = .clear
panel.hasShadow = false
panel.animationBehavior = .none
panel.hidesOnDeactivate = false
panel.setAccessibilityElement(false)
```
Coordinates: `Coordinates.appKit(fromTopLeft:primaryHeight:)` with `NSScreen.screens.first?.frame.height` (GapHandlePanels L154-160). Animation with explicit `CABasicAnimation` from `presentation()` value (GapHandlePanels `fade` L120-128). Debug-only `sharingType = .readOnly` switch for UAT.

### `Sources/TransomMac/Zoom/CollapsedPanels.swift`

**Analog:** `Sources/TransomMac/Overlay/GapHandlePanels.swift` whole file: pooled `show(_:on displayUUID:)` (L151-167: reuse matching panel, else `pool.popLast()`, else make; order out leftovers into pool), `HandleView` tracking area `[.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]` (L43-47), hover fade 80/120 ms (L49-60), `updateLayer` colour re-resolve (L35-39), `systemColorsDidChangeNotification` observer with `MainActor.assumeIsolated` (L141-147). Replace drag with double-click (`event.clickCount == 2`) callback.

### `Sources/TransomMac/Zoom/TileLayer.swift`

**Analog:** `PreviewLabelView` in `PreviewPanel.swift` L24-60 for the title capsule (8/4 padding, `windowBackgroundColor` fill, 1pt `separatorColor`, radius h/2, `resolveColors()` inside `effectiveAppearance.performAsCurrentDrawingAppearance`). Use `.body` instead of `.headline`, middle truncation.

### `Sources/TransomMac/Zoom/ShortcutsWindowController.swift`

**Analog:** `Sources/TransomMac/Shell/TrackedWindowsWindowController.swift` L24-47:
```swift
func show() {
    let window = window ?? makeWindow()
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
}
private func makeWindow() -> NSWindow {
    let hosting = NSHostingController(rootView: view)
    hosting.sizingOptions = []
    let window = KeyClosableWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.title = "Tracked Windows"
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 960, height: 480))
    window.contentMinSize = NSSize(width: 720, height: 320)
    if !window.setFrameUsingName("TrackedWindows") { window.center() }
    window.setFrameAutosaveName("TrackedWindows")
```
Change to `[.titled, .closable, .resizable]`, 480x640, min 400, fixed width, autosave "Shortcuts". `KeyClosableWindow` lives in `Permission/SetupWindowController.swift` L79. Rows iterate `Hotkeys.entries` + ZoomCopy titles with `KeyboardShortcuts.Recorder`.

### `Sources/TransomMac/Shell/ZoomCopy.swift`

**Analog:** `Sources/TransomMac/Shell/MenuCopy.swift` L1-30: `nonisolated public enum`, `public static let` strings, plural branches via functions, no AppKit import. Tests copy `MenuCopyTests.swift` (parameterised `@Test(arguments:)`).

### `Sources/TransomMac/Zoom/SnapshotCapture.swift`

No in-repo SCK analog (by design). Use RESEARCH Pattern 5 sketch. Logger convention: `private static let logger = Logger(subsystem: "com.eightabyte.transom", category: "capture")` (as `CGWindowList.swift` L9, `LayoutStore.swift` L27). Titles `.private`.

### `Tests/TransomMacTests/NoScreenCaptureTests.swift`

Modify L10 forbidden list to add `"SCScreenshotManager"`, `"CGPreflightScreenCaptureAccess"`, `"CGRequestScreenCaptureAccess"`, and skip exactly `Sources/TransomMac/Zoom/SnapshotCapture.swift` in the L17-22 loop (add a test asserting that file exists so the allow-list can't silently rot).

### `Sources/TransomEngine/Recovery.swift`

Extend `terminationPlan` (L64-78) with `homeTiles: [WindowIdentity: Rect]`; current line `let home = docked.contains(id) ? nil : homeFrames[id]` becomes "docked -> homeTiles[id]". Mirror in `ArrangeController.restoreForTermination` (L465). Tests: `RecoveryTests.swift`.

### `Sources/transom-zoom-spike/main.swift`

**Analog:** `Sources/transom-dump/main.swift` (imports AppKit/TransomEngine/TransomMac, `usage` string, `fail(_:_:) -> Never` writing to stderr) and target line `Package.swift` L33:
```swift
.executableTarget(name: "transom-dump", dependencies: ["TransomMac", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
```

### Engine tests

**Analog:** `Tests/TransomEngineTests/ArrangerDesktopTests.swift` L1-30 (file-private `pid`, `visible`, `key`, `ref(_:)`, `parked(_:)` helper) and `Harness` in `ArrangerLifecycleTests.swift` L44-70 (`Harness.started(frames:)`, `send(_:)` runs `.perform` on `FakeWindowSystem` and feeds echoes). Camera tests send `.zoomEnabled(true)`, a zoom `.command`, assert `.cameraMove` and no `.perform`, then `.cameraSettle` and assert `.save(.now)` precedes `.perform`.

## Shared Patterns

### No AppKit in Model/Engine
`scripts/check-no-appkit.sh` via `Tests/TransomModelTests/NoAppKitTests.swift`. Camera, ViewPlanner, Navigator, SettleTracker (and ZoomTapRules if in Engine) import only `TransomModel`/Foundation.

### Overlay panel recipe
Source: `GapHandlePanels.swift` L169-184 (above). Apply to StagePanel and CollapsedPanels. Never-key subclass from `PreviewPanel.swift` L7-10.

### Colour re-resolution
Source: `PreviewLabelView.resolveColors()` (`PreviewPanel.swift` L52-59) and GapHandlePanels observer L141-147. Apply to tiles, collapsed blocks, rubber band.

### Logging
`Logger(subsystem: "com.eightabyte.transom", category: "<cat>")`, new categories `camera`, `capture`, `zoomInput`. Engine logs through `.info(String)` effects (`Arranger.swift` L65), not Logger directly.

### Command bus
Every trigger -> `ArrangeController.dispatch(_:from:)` (`ArrangeController.swift` L357) -> `Arranger.handle(.command(...))`. Hotkeys, menu, URL share one `Command` case.

### Copy in pure types
`MenuCopy`/`NoticeCopy` pattern; tested in `TransomMacTests`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `Sources/TransomMac/Zoom/SnapshotCapture.swift` | service | async capture | ScreenCaptureKit forbidden until now (TILE-10); use RESEARCH Pattern 5 |
| `Sources/TransomMac/Zoom/AppColor.swift` | utility | transform | No icon/pixel code exists; follow UI-SPEC Color recipe (pure bucketing can be split into a testable function) |

## Metadata

**Analog search scope:** `Sources/**`, `Tests/**`, `Package.swift`
**Files scanned:** ~25 read/grepped
**Pattern extraction date:** 2026-10-27
