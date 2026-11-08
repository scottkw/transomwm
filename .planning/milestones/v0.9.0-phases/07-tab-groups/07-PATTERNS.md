# Phase 7: Tab Groups - Pattern Map

**Mapped:** 2026-11-01
**Files analyzed:** 30 (6 new source, 4 new test, ~20 modified)
**Analogs found:** 30 / 30 (every new file has an in-repo analog; all paths git-tracked)

RESEARCH.md already cites exact seam lines (Resolve.swift:127-131/151-152, Arranger.swift:1110/1432, WindowSystem.swift:154-160, AXWindowSystem.swift:229-234, CollapsedPanels.swift:196-207, ArrangeController.swift:460-470, ZoomInput.swift:38-39). This map adds the copyable excerpts and the analog per file.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `Sources/TransomModel/TabBand.swift` (NEW) | utility (pure geometry) | transform | `Sources/TransomModel/Snap.swift` | exact |
| `Sources/TransomModel/Resolve.swift` | model | transform | itself (`aggregate`/`place` `.tabs` arms) | self |
| `Sources/TransomModel/DesktopLayer.swift` | model | CRUD + Codable | itself (`add`/`remove`/`validate`) | self |
| `Sources/TransomModel/TreeEdits.swift` | model | CRUD | itself (`insert`, `swap`, `group`, `remove`) | self |
| `Sources/TransomModel/World.swift` | model | validation | itself (`validate`, decoder version check) | self |
| `Sources/TransomEngine/WindowSystem.swift` | model (command enum) | request-response | itself L154-160 | self |
| `Sources/TransomEngine/DragSession.swift` | engine state | event-driven | itself (`dwell`, `hover`, `PreviewState`, `CollapseCopy`) | self |
| `Sources/TransomEngine/Arranger+Tabs.swift` (NEW) | engine extension | event-driven | `Sources/TransomEngine/Arranger+Commands.swift` | exact |
| `Sources/TransomEngine/Arranger.swift` | engine | event-driven | itself (`showBlocks` L1877, `nextWake` L1032, `planShown` L1780) | self |
| `Sources/TransomEngine/Planner.swift` | engine | transform | itself L62 (`parks`) | self |
| `Sources/TransomEngine/Command.swift` | config enum | — | `case camera(CameraCommand)` + `CameraCommand` | exact |
| `Sources/TransomEngine/TransomURL.swift` | config | request-response | `commands` dictionary L8-16 | exact |
| `Sources/TransomEngine/Recovery.swift`, `Arranger+Camera.swift` | engine | batch | `restoreAll()` in Arranger+Commands.swift | self |
| `Sources/TransomMac/Overlay/TabStripPanels.swift` (NEW) | component (AppKit panel pool) | event-driven | `Sources/TransomMac/Zoom/CollapsedPanels.swift` | exact |
| `Sources/TransomMac/Overlay/TearOffGhost.swift` (NEW, may live in TabStripPanels) | component (click-through panel) | event-driven | `Sources/TransomMac/Overlay/PreviewPanel.swift` + CollapsedPanels `makePanel` | role-match |
| `Sources/TransomMac/Shell/TabCopy.swift` (NEW) | utility (copy) | transform | `Sources/TransomMac/Shell/OverviewCopy.swift` | exact |
| `Sources/TransomMac/AX/AXAppThread.swift` | service (AX jobs) | request-response | `focusWindow`/`raiseWindow` L224-240 | exact |
| `Sources/TransomMac/AXWindowSystem.swift` | service | request-response | `perform` switch L215-245 | self |
| `Sources/TransomMac/ArrangeController.swift` | controller | event-driven | itself (`pressWindow` L460-470, effect handling for `.collapsedBlocks`) | self |
| `Sources/TransomMac/Input/Hotkeys.swift` | config | — | `static let dock = Self("dock", initial: …)` L8+ | exact |
| `Sources/TransomMac/Shell/CommandMenu.swift`, `Zoom/ShortcutsWindowController.swift`, `Zoom/StagePanel.swift`/`TileLayer.swift`, `Overview/OverviewController.swift` | component | — | Snap submenu / Snap Recorder section / collapsed-block drawing | self |
| `Sources/TransomTestSupport` `FakeWindowSystem` | test support | — | existing `.focus`/`.raise` handling | self |
| `Tests/TransomModelTests/TabGroupModelTests.swift` (NEW) | test | — | `Tests/TransomModelTests/TabsTests.swift` | exact |
| `Tests/TransomEngineTests/ArrangerTabsTests.swift` (NEW) | test | — | `Tests/TransomEngineTests/ArrangerCollapseTests.swift` | exact |
| `Tests/TransomMacTests/TabCopyTests.swift` (NEW) | test | — | `Tests/TransomMacTests/OverviewCopyTests.swift` | exact |
| `Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift` (NEW, VM only) | test | — | `Tests/TransomMacIntegrationTests/TabsIntegrationTests.swift` | exact |

## Pattern Assignments

### `Sources/TransomModel/TabBand.swift` (utility, transform) — analog `Sources/TransomModel/Snap.swift` L1-25

Pure `public enum` namespace of static functions over `Rect`, `import Foundation` only (no AppKit; `scripts/check-no-appkit.sh` + `NoAppKitTests`):
```swift
import Foundation

public enum Snap {
    /// The frame for `target` inside `desktop` inset by `gap` ... Whole points like `resolve`
    public static func frame(_ target: SnapTarget, window: Rect, desktop: Rect, gap: Double) -> Rect {
        ...
        let inset = Rect(
            x: minX, y: minY,
            width: max(0, desktop.maxX.rounded(.down) - gap - minX),
            height: max(0, desktop.maxY.rounded(.down) - gap - minY))
```
Body: RESEARCH.md Pattern 1 example (`height = 32`, `stripHeight = 28`, `content(of:)`, `frame(ofContent:)`, `strip(of:)`). Note the `// shortcut:` comment convention for accepted edge cases.

### `Sources/TransomModel/Resolve.swift` (model) — edit in place, L121-152

The two `.tabs` arms to change:
```swift
case let .tabs(windows, _):
    // Tabs share one rect, so it must fit the largest of them on each axis.
    let sizes = windows.filter(active.contains).compactMap { minimum[$0] }
    guard !sizes.isEmpty else { return nil }
    return Size(width: sizes.map(\.width).max()!, height: sizes.map(\.height).max()!)
...
case let .tabs(windows, _):
    for window in windows where active.contains(window) { result.windowRects[window] = rect }
```
Change: participation iff `windows[selected]` is active; aggregate + `(0, TabBand.height)`; `place` writes only `windowRects[selected] = TabBand.content(of: rect)` and the rest into new `Resolution.hiddenTabs`. Keep `nodeRects[id] = rect` (group frame).

### `Sources/TransomModel/DesktopLayer.swift` (model, CRUD) — edit in place

Mutator style to copy for `group`/`addTab`/`selectTab`/`setGroupFrame`/`removeFromGroup` (guard-then-mutate, typed throws):
```swift
public mutating func setFrame(_ frame: Rect, for window: WindowRef) throws(LayoutError) {
    guard let index = index(of: window) else { throw .windowNotFound(window) }
    guard frame.isValidGeometry else { throw .invalidGeometry("floating frame of \(window) is not finite or out of range") }
    windows[index].frame = frame
}
```
Validation style (L67-78) to extend for groups:
```swift
public func validate() throws(LayoutError) {
    var seen: Set<WindowIdentity> = []
    for floating in windows {
        guard seen.insert(floating.window.identity).inserted else { throw .duplicateWindow(floating.window) }
        ...
```
New: `public private(set) var groups: [FloatingTabGroup]`, custom `init(from:)` with `decodeIfPresent(..., forKey: .groups) ?? []` (the one sanctioned `??`: absent key in older files). `remove(_:)` must also dissolve a group (L27-30). `mapWindows`/`rekey` (L48-57) must also rewrite group members.

### `Sources/TransomModel/TreeEdits.swift` (model) — edit in place
`insert` builds `.panel(window)` at L34; `swap` guards at L161-162; `remove` dissolve/neighbour rule L77-84 is reused unchanged. Add `removeLeaf`/`insertLeaf` by generalising `insert`; relax `swap` to allow one `.tabs` side.

### `Sources/TransomEngine/WindowSystem.swift` — L154-160
```swift
public enum WindowCommand: Equatable, Sendable {
    case setFrame(WindowRef, Rect)
    case park(WindowRef, displayUUID: String)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
}
```
Add `size: Size? = nil` to `.park`, plus `.close(WindowRef)`, `.minimize(WindowRef)`. Update `ExclusionFilter.admit` and `FakeWindowSystem`.

### `Sources/TransomEngine/DragSession.swift` — dwell + preview + copy
Constants and state (L~95-130):
```swift
public static let dwell: Duration = .milliseconds(150)
...
var hover: Hover?
var hoverSince: ContinuousClock.Instant?
var decision: Decision?
```
Add `groupDwell = .milliseconds(400)`, `groupRest = 16.0`, `groupAnchor`, `groupSince`, `GroupTarget`, `PreviewState.group(frame:strip:label:)` next to `case collapsed(Rect, label: String)`. Preview labels "Group as tabs"/"Add as a tab" go in a sibling of:
```swift
public enum CollapseCopy {
    public static let draggedLabel = "Collapsed until you zoom in"
    public static func othersLabel(_ count: Int) -> String {
        count == 1 ? "1 window collapses" : "\(count) windows collapse"
    }
```
`DropAction` enum (same file) stays; a group release is a new action or engine branch, not a `DropTarget` case.

### `Sources/TransomEngine/Arranger+Tabs.swift` (NEW, engine extension) — analog `Sources/TransomEngine/Arranger+Commands.swift`
Header + mutating method shape (one `World.edit` per user edit, dry-run first, `[.beep]` on refusal):
```swift
import TransomModel

/// The keyboard layout commands (...). Each user edit is one `World.edit`, dry-run first, so a
/// refusal changes nothing (D-26)...
extension Arranger {
    mutating func moveOrSnap(_ window: WindowRef, toward edge: Edge) throws(LayoutError) -> [ArrangerEffect] {
        guard let key = deskKey(of: window), let desk = world[key], let area = display(for: key)?.visibleFrame else { return [.beep] }
        ...
        return try commit(key, flashing: window, collapsible: true) { desk, ids throws(LayoutError) in
            try desk.tree.remove(window)
            try desk.tree.insert(window, at: side, of: neighbour, ids: &ids)
        }
    }
```
Restore All (same file L30-37), which Pitfall 3 says must dissolve groups first:
```swift
mutating func restoreAll() throws(LayoutError) -> [ArrangerEffect] {
    goHome()
    camera.collapsible = []  // else the replan parks them again in the same perform
    let moves = rescueStranded(desks: world)
    try showParkedDesktops(keeping: moves, undoable: true)
    return (moves.isEmpty ? [] : [.perform(moves)]) + replan() + showBlocks([:]) + [.notice(.restored(count: moves.count))]
}
```
Frame-fact (no undo) path for tab select uses the `snap` shape: `world.recordFloatingFrame(...)` then `return replan()`; selection uses `World.reflow` (no undo step).

### `Sources/TransomEngine/Arranger.swift` — strip effect + wake
Copy `showBlocks` (L1877-1885) for `showStrips`, change-only emission per display:
```swift
mutating func showBlocks(_ blocks: [String: [CollapsedBlock]]) -> [ArrangerEffect] {
    let uuids = Set(blocks.keys).union(camera.shownBlocks.keys).sorted()
    return uuids.compactMap { uuid in
        let next = blocks[uuid] ?? []
        guard next != camera.shownBlocks[uuid] ?? [] else { return nil }
        camera.shownBlocks[uuid] = next.isEmpty ? nil : next
        return .collapsedBlocks(next, displayUUID: uuid)
    }
}
```
Append group dwell, pending-reveal and close-queue deadlines to `nextWake` (L1032-1035):
```swift
private var nextWake: ContinuousClock.Instant? {
    let dwell = drag?.kind == .move ? drag?.dwellEnds : nil
    return (pendingCorrections.compactMap { ... } + [finderExpectation?.deadline, dwell].compactMap { $0 }).min()
}
```
Centre refusals to replace: L1110 (keyboard, keep beep) and L1432 (`target = nil`). Parked-window move guard to mirror for hidden members: L946-947 `guard !parkRequested.contains(window.identity) else { return [] }`.

### `Sources/TransomEngine/Command.swift` + `TransomURL.swift`
Nested-command pattern:
```swift
case camera(CameraCommand)
}
public enum CameraCommand: Hashable, Sendable {
    case zoomOutAll, stepOut, stepIn, back, forward
```
→ `case tabs(TabCommand)` / `enum TabCommand { case next, previous, moveOut }`. URL whitelist entry style: `"frame-desktop": .camera(.frameDesktop),` → `"next-tab": .tabs(.next), "previous-tab": .tabs(.previous), "move-out-of-group": .tabs(.moveOut)`.

### `Sources/TransomMac/Overlay/TabStripPanels.swift` (NEW) — analog `Sources/TransomMac/Zoom/CollapsedPanels.swift` (whole file, 221 lines)
- Imports L1-4: `AppKit`, `QuartzCore`, `TransomEngine`, `TransomModel`.
- Non-key panel subclass L7-10 (`canBecomeKey`/`canBecomeMain` false).
- View: `wantsUpdateLayer` + `updateLayer()` inside `CATransaction.setDisableActions(true)` resolving semantic colours (L59-83); `acceptsFirstMouse` true (L85); tracking area `[.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect]` (L87-91; add `.mouseMoved`, drop cursor change — strip keeps arrow); hover fade via `CABasicAnimation` 0.08/0.12 (L93-118).
- Accessibility: `nonisolated static func label(...)` testable label + `accessibilityRole`/`accessibilityPerformPress` overrides (L35-57). Use role `.radioButton`, subrole `.tabButtonSubrole` (Pitfall 11, not `.tabButton`).
- Pool + per-display `show(_:on:)` reuse by identity (L146-173), `hide`/`fadeIn` 120 ms (L175-193), appearance observers (L133-144).
- `makePanel` (L195-208) — copy, then change `level = .normal`, `collectionBehavior = [.stationary, .ignoresCycle]` (no `.canJoinAllSpaces`), add `allowsToolTipsWhenApplicationIsInactive = true`:
```swift
let panel = BlockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
panel.ignoresMouseEvents = false
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
panel.sharingType = .none
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.animationBehavior = .none
panel.hidesOnDeactivate = false
```
- Space-stranding replacement (L210-218), mandatory per CONTEXT canonical ref:
```swift
private func onShownSpace(_ panel: BlockPanel, _ displayUUID: String) -> BlockPanel {
    guard let view = Self.view(panel), panel.leftOnAnotherSpace("display \(displayUUID): collapsed block panel") else { return panel }
    panel.orderOut(nil)
    let new = makePanel(view.block)
    ...
```
Only call it for visible strips of the shown desk (Pitfall 8). Coordinate conversion: `Coordinates.appKit(fromTopLeft:primaryHeight:)` (L158). Expose panel window numbers so `ArrangeController` can route strip presses (Pitfall 4).

### `TearOffGhost` (NEW) — analog `Sources/TransomMac/Overlay/PreviewPanel.swift` + CollapsedPanels `makePanel`
Same `makePanel` recipe with `ignoresMouseEvents = true`, `.floating`, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`; ordered above the preview panel. Temporary Esc hotkeys: copy `ZoomInput.escapeModifiers` (`Sources/TransomMac/Zoom/ZoomInput.swift` L38-39 per RESEARCH; never ⌥).

### `Sources/TransomMac/Shell/TabCopy.swift` (NEW) — analog `Sources/TransomMac/Shell/OverviewCopy.swift`
```swift
/// Phase 6 copy from the UI-SPEC (Surface 7, Copywriting Contract). Pure strings, no AppKit types.
nonisolated public enum OverviewCopy {
    public static func titleOrApp(title: String, app: String) -> String { title.isEmpty ? app : title }
    public static func savedArrangementsLine(_ count: Int) -> String {
        count == 0 ? "Saved arrangements: none yet" : "Saved arrangements: \(count)"
    }
```
Explicit plural branches, curly quotes `\u{201C}…\u{201D}`, app names via `MenuCopy.truncatedAppName`. Holds announcements, tooltips, a11y labels, menu items, Debug line "Tab groups: …".

### `Sources/TransomMac/AX/AXAppThread.swift` — L224-240
```swift
func raiseWindow(windowID: UInt32) async -> Bool {
    await perform { [self] _ -> Bool in
        guard let element = windows[windowID]?.element else { return false }
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    } ?? false
}
```
`closeWindow`: copy `kAXCloseButtonAttribute` then `AXUIElementPerformAction(button, kAXPressAction)`. `minimizeWindow`: `AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)`.

### `Sources/TransomMac/AXWindowSystem.swift` — `perform` switch L215-245
```swift
case .park(_, let uuid):
    guard let display = displays.first(where: { $0.uuid == uuid }) else {
        logger.error("dropping park for \(ref.description, privacy: .public): display \(uuid, privacy: .public) unknown")
        continue
    }
    thread.enqueueFrame(windowID: windowID, rect: display.parkedFrame(size: info.frame.size, among: displays), ref: info.window)
case .raise:
    Task {
        if !(await thread.raiseWindow(windowID: windowID)) {
            logger.info("raise of \(ref.description, privacy: .public) failed")
        }
    }
```
`.park` → `size ?? info.frame.size`; `.close`/`.minimize` copy the `.raise` Task+log shape. Note `windowID = info.visibleMemberID ?? ref.windowID` already handles D-09 native groups.

### `Sources/TransomMac/Input/Hotkeys.swift`
```swift
static let dock = Self("dock", initial: .init(.d, modifiers: [.control, .option, .command]))
```
→ `nextTab` (.t, ⌃⌥⌘), `previousTab` (.t, ⌃⌥⌘⇧), `moveOutOfGroup` (.l, ⌃⌥⌘). Raw names are a persistent contract. Exhaustive `Command` switches (MenuCopy, CommandMenu, Hotkeys.entries, Arranger.availability, ShortcutsWindowController) are found by the compiler.

## Test Patterns

### `Tests/TransomModelTests/TabGroupModelTests.swift` — analog `TabsTests.swift` L1-40
```swift
import Foundation
import Testing
@testable import TransomModel

private let a = makeWindow(1)
private func n(_ raw: UInt64) -> NodeID { NodeID(raw: raw) }
private func single() throws -> (LayoutTree, IDSource) { ... try tree.insertRoot(a, ids: &ids) ... }

@Suite struct TabsTests {
    @Test func groupingIntoAPanelMakesATabGroupUnderTheSameNodeID() throws {
        var (tree, _) = try single()
        try tree.group(b, into: n(1))
        #expect(tree.node(n(1)) == .tabs(windows: [a, b], selected: 1))
```
Cover: two-member group resolves exactly one window rect (Pitfall 2), +32 minimum, floating-group validate/decode of old JSON without `groups`.

### `Tests/TransomEngineTests/ArrangerTabsTests.swift` — analog `ArrangerCollapseTests.swift` L1-30
```swift
@testable import TransomEngine
import TransomModel
import Testing

private let area = Rect(x: 0, y: 25, width: 1440, height: 875)
private let mainDisplay = DisplayInfo(uuid: "main", frame: Rect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: area, currentSpaceID: nil)
private func pointer(_ kind: PointerEvent.Kind, _ x: Double, _ y: Double, _ modifiers: Modifiers = [], press: WindowRef? = nil) -> ArrangerInput {
    .pointer(PointerEvent(kind: kind, location: Point(x: x, y: y), modifiers: modifiers, pressWindow: press))
}
private func bare(_ infos: [WindowInfo], world: World? = nil, zoom: Bool) -> Arranger {
    var arranger = Arranger()
    if let world { _ = arranger.handle(.restore(world, homeFrames: [:]), now: .now) }
    _ = arranger.handle(.inventory(WindowInventory(displays: [mainDisplay], windows: infos, initialRefreshComplete: true)), now: .now)
```
Drive dwell by passing `now` + 400 ms; assert on `[ArrangerEffect]`. `ArrangerDragTests.swift` is a second reference for drag sequences.

### `Tests/TransomMacTests/TabCopyTests.swift` — analog `OverviewCopyTests.swift`
Parameterised `@Test(arguments: [(input, expected)])` over each copy function, `import TransomMac`.

### `Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift` — analog `TabsIntegrationTests.swift`
`@Suite(.serialized, .enabled(if: IntegrationEnv.trusted, ...)) @MainActor`, `FixtureProcess.launch([...])` + `defer { fixture.terminate() }`, `AXWindowSystem(appFilter:)`, `waitUntil(timeout:)`. VM only (`scripts/vm-live-test.sh`). Quit restore check: `QuitRestoreIntegrationTests.swift`.

## Shared Patterns

- **Pure engine, effects out:** every tab action returns `[ArrangerEffect]`; shell has no policy. Refusals = `[.beep]` + announcement for hotkey/menu, never on drag release (Arranger+Commands `return [.beep]`).
- **One undo step per user edit:** `commit(key, …) { desk, ids throws(LayoutError) in … }` / `World.edit`; tab selection via `World.reflow` (no undo).
- **Change-only overlay effects:** `showBlocks` diff pattern → `.tabStrips`.
- **Panels:** CollapsedPanels pool + `leftOnAnotherSpace` + appearance observers; semantic colours re-resolved in `updateLayer`.
- **Copy in AppKit-free enums** with explicit plural branches and parameterised tests.
- **Typed throws** `throws(LayoutError)`, guard-then-mutate in the model; no silent `?? []` except the backward-compatible `groups` decode.
- **Logging:** `os.Logger` subsystem `com.eightabyte.transom`, new `tabs` category; titles `.private`, identities `.public` (AXWindowSystem `logger.info("... \(ref.description, privacy: .public) ...")`).

## No Analog Found

None. Closest weak spots: tear-off session (no prior cross-panel drag origin; build on `DragSession` per RESEARCH Pattern 7) and close-group queue (no existing multi-step AX queue; model on pending-reveal/`finderExpectation.deadline` + `nextWake`).

## Metadata

**Analog search scope:** Sources/TransomModel, Sources/TransomEngine, Sources/TransomMac (Overlay, Zoom, Shell, AX, Input), Tests/*
**Files scanned:** ~25 read/excerpted
**Pattern extraction date:** 2026-11-01
