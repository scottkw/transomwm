# Phase 7: Tab Groups - Research

**Researched:** 2026-11-01
**Domain:** Swift/AppKit macOS window manager: layout model extension (tab groups docked and floating), pure engine state machines (dwell, tab switch, group close), AX window commands, non-activating overlay panels
**Confidence:** HIGH for the codebase seams (every claim below was read this session); MEDIUM for macOS panel/Space/focus behaviour (needs the VM tests listed in Validation Architecture)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Making a group
- **D-01:** A centre drop (`DropZone.center`, the middle 50% of a tile) groups only after the pointer has rested there about 0.4 s. Then the drop preview changes to a tab-group outline with a strip. Releasing in the centre before the dwell is refused as today: a drag that misses has no beep, and the window returns (clarified 2026-11-01: the drag-miss path has never beeped; only the keyboard Dock path beeps).
- **D-02:** Works on docked tiles and on floating windows on the Desktop tile. A group made on a floating window floats at that window's frame. Dropping on an existing group's centre adds a tab to it.
- **D-03:** The dropped window becomes the selected tab.

#### Tab strip
- **D-04:** A strip about 28 pt tall sits at the top of the group's frame, inside the tile: the member windows get the frame minus the strip, so nothing overlaps (Core Value). Drawn in a non-activating panel that follows the group (CG bounds polling of the selected window, per the scope note).
- **D-05:** Each tab shows app icon + window title; the selected tab is highlighted. Styling follows the existing 04-UI-SPEC / overlay tokens.
- **D-06:** The strip carries the group's own close, minimise and dock/float buttons; each acts on every window of the group. Close sends a normal AX close to each window, so apps still show their unsaved-changes prompts. Minimise minimises the group as one (restoring brings the group back with the same selected tab).

#### Hidden tabs
- **D-07:** Non-selected members are parked off screen at the group's content size using the Phase 4 parking mechanism, never minimised, and restored on quit / crash recovery / Restore All Windows like other parked windows.
- **D-08:** Clicking a tab unparks it into the group frame and parks the previous one. If a hidden member is activated another way (⌘-Tab, Dock click, app activation, AX focus), the group switches to that tab.
- **D-09:** A native macOS tab group (e.g. Safari tabs, detected by `TabGroupTracker`) joins a Transom group as a single member.

#### Leaving a group
- **D-10:** Dragging a tab out of the strip turns into a normal window drag: drop on an edge to dock, anywhere else to float (existing drop zones and preview).
- **D-11:** Right-clicking a tab offers **Close Tab** and **Move Out of Group**; Move Out floats the window beside the group.
- **D-12:** A group reduced to one window dissolves back into a plain tile/floating window. Closing the selected tab selects a neighbour.
- **D-13:** Groups persist in layout.json like tiles (Node.tabs already serialises) and come back on relaunch.

### Claude's Discretion
- Exact dwell time tuning, strip height/padding, tab truncation and overflow when many tabs, keyboard/hotkey for next/previous tab if cheap, how the overview and zoom stage draw a group (likely the selected window plus a tab indicator), VoiceOver labels for tabs, undo granularity for group/ungroup.

(All of these were resolved by the approved `07-UI-SPEC.md`: 400 ms / 16 pt dwell, 28 pt strip + 4 pt gap = 32 pt band, ⌃⌥⌘T / ⇧⌃⌥⌘T / ⌃⌥⌘L, icon-only stage strip, one undo step per group/ungroup. The planner treats the UI-SPEC as binding.)

### Deferred Ideas (OUT OF SCOPE)
- Reordering tabs by dragging within the strip (if not free).
- Tab-group-specific Settings (Phase 9).

Also out of scope per CONTEXT boundary: a Settings window (Phase 9), saved views and the `transom` CLI (Phase 8). Per UI-SPEC: merging two whole groups by dropping one onto another; a keyboard way to form a group (recorded known gap).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TABS-01 | Dropping a window on the middle of another and pausing groups them under one tab strip | Pattern 3 (group dwell in `DragSession`), Pattern 4 (`GroupTarget` hit test incl. floating windows), Pattern 1/2 (band in `resolve`, floating groups in `DesktopLayer`), Pattern 6 (strip panels + `.tabStrips` effect) |
| TABS-02 | Clicking a tab switches the visible window; other tabs stay hidden | Pattern 5 (reveal-then-park state machine gated on `frameApplied`), Pitfall 1 (park size), Pitfall 6 (D-08 focus fights), Pattern 6 (strip click via AppKit) |
| TABS-03 | A group's close, minimise and dock/float buttons act on the whole group | Pattern 8 (new `WindowCommand.close` / `.minimize`, close-group queue), Pattern 9 (whole-leaf moves: Float/Dock Group, title-bar drag of the selected member) |
| TABS-04 | A tab can be dragged out to become its own window | Pattern 7 (tear-off driven by the existing InputTap pointer stream, engine `DragSession` with a tear-off origin) |
| TABS-05 | Tab groups work for windows from different apps, docked or floating | Pattern 2 (floating groups as a sidecar on `DesktopLayer`), D-09 native tab member = one `WindowRef` via `visibleMemberID` |
| TABS-06 | Right-clicking a tab offers closing it and moving it out of the group | Pattern 6 (context menu from the strip view), Pattern 8 (Close Tab = select then AX close), Move Out landing rule (UI-SPEC Surface 4) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Swift + SPM, macOS 14+; package `swift-tools-version: 6.2`, Swift 6 language mode; no Swift 6.4-only syntax in shipped code. [VERIFIED: Package.swift:1, `.planning`-level CLAUDE.md]
- `TransomModel` and `TransomEngine` must not import AppKit (headless unit tests). `scripts/check-no-appkit.sh` exists to enforce it. [VERIFIED: ls scripts]
- Private APIs isolated in `TransomPrivate` with fallbacks. Phase 7 adds **no** private API (park, focus, AX close/minimise are public AX). [VERIFIED: UI-SPEC Registry Safety + this research]
- Clean room: never consult the TrellisWM binary; Loop is GPL-3, read only. Safari/Finder tab bars must not be copied (UI-SPEC clean-room rule).
- Engine is pure: events in, effects out; the shell (`ArrangeController`, `AXWindowSystem`) executes. Every refusal reachable by hotkey/menu beeps; drag releases never beep.
- Live tests only in the Tart VM with fixture windows (`scripts/vm-live-test.sh`); never run event taps, overlay panels or window-opening code on the host during research or planning.
- Navigation: use graft (`graft ask/grep/skeleton/callers`) or LSP rather than grep where possible.
- Testing: user prefers minimal testing (engine unit tests, a few VM live tests, a short host checklist). Global CLAUDE.md asks 80%+ coverage on critical components: the model and engine edits below are the critical ones.
- Ponytail is active for executors: smallest change that fully solves the task. "Silent fallbacks" (`?? []` hiding failures) are discouraged; let errors surface as `.fault`.
- Commits: never stage `.planning/config.json` or `.planning/state.json`.

## Summary

The model already has `Node.tabs(windows:selected:)` with validation, persistence, `group(window, into:)`, `selectTab`, and a `remove` that dissolves a two-member group into a panel under the same NodeID and selects the right neighbour (else left) when the selected tab closes. Everything else Phase 7 needs is missing, and three gaps are structural and must be planned first:

1. **The 32 pt band does not exist in layout.** `resolve` gives every present tab member the full tile rect and sizes the tab leaf by the largest member minimum. Phase 7 must make `resolve` give only the **selected** member a window rect (the content rect = tile minus 32 pt at the top), add 32 pt to the tab leaf's minimum height, and report the hidden members separately so the planner parks them. If hidden members stay in `windowRects`, Phase 3's planner will `setFrame` all of them into the tile and they will overlap — the exact failure the Core Value forbids.
2. **Floating groups have no model.** Floating windows live in `DesktopLayer.windows: [FloatingWindow]`, one window each, outside the tree. D-02 needs groups there too. The recommended shape (Pattern 2) is a sidecar `groups` list on `DesktopLayer` whose members **stay** in `windows`, so the ~80 existing call sites (`contains`, `state(of:)`, `remove`, `rekey`, `LayoutRestore.reattach`, `World.validate`) keep working unchanged and an older Transom reading the file degrades to stacked floating windows instead of failing.
3. **Parking cannot set a size.** `.park` parks at the window's *tracked* size (`info.frame.size`), and park and `setFrame` share one coalescing write slot per window, so "resize to the content rect, then park" collapses into a park at the old size. `WindowCommand.park` needs an explicit size, and `parkRequested` needs to remember it so a resized group re-parks its hidden members.

The rest is engine state machines in the existing style (group dwell, reveal-then-park tab switch, close-group queue, tear-off session) plus one shell component (a pooled strip panel per group, modelled on `CollapsedPanels`), two new AX commands (close press, minimise), and the menu/hotkey/URL/copy plumbing the UI-SPEC lists.

**Primary recommendation:** Build bottom-up in four waves: (1) model: band in `resolve`, floating-group sidecar, leaf-move/swap edits; (2) engine: hidden-member parking with size, the tab-switch and close state machines, group dwell and drops, strip effect; (3) engine actions: tear-off, move out, group buttons, commands, safety paths (quit, crash, Restore All); (4) shell: strip panels, AX close/minimise, tap routing, preview state, menus, stage/overview layer. Gate everything on headless unit tests; prove the macOS-behaviour assumptions with 4–5 VM live tests.

## Architectural Responsibility Map

Transom's tiers are Model (pure value types), Engine (pure Arranger: inputs → effects), Shell (AppKit/AX execution), OS (WindowServer, apps).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tab group membership, selection, order | Model (`Node.tabs`, `DesktopLayer` groups) | — | Persisted, undoable, validated; must be headless-testable |
| Content rect (band subtraction), group minimum size | Model (`resolve`) | Engine (`Planner`) | Fit/unfit decisions and WYSIWYG previews come from `resolve`; doing it later would make dry runs lie |
| Which members are parked and at what size | Engine (`Planner`/`planShown`) | Shell (`AXWindowSystem.perform`) | Engine decides; shell computes the corner rect from `DisplayInfo.parkedFrame` |
| Group dwell (400 ms / 16 pt) | Engine (`DragSession`) | — | Time comes in as `now`, wake via `nextWake`; fully testable |
| Tab switch ordering (reveal, read-back, park, 1 s failure) | Engine | Shell (frame read-back events) | Pure state machine on `frameApplied` and `.tick` |
| D-08 activation switch | Engine (`.windowFocused`) | Shell (AX focus observation, already exists) | Focus events already reach the Arranger |
| Close Group / Close Tab / Minimize Group | Engine (queue, deadlines) | Shell (AX `AXPress` on close button, `AXMinimized`) | New `WindowCommand` cases; AX jobs on the app's thread |
| Strip geometry and contents | Engine (emits `TabStrip` values) | Shell (`TabStripPanels` draws, tracks hover, pops menus) | Same split as `CollapsedBlock` / `CollapsedPanels` |
| Strip following during a drag | Shell (`DragFramePoller` callback) | Engine helper for the rect formula | 60 Hz geometry offset; no layout decision involved |
| Tear-off drag | Engine (`DragSession` tear-off origin) | Shell (InputTap routes strip presses, ghost panel, Esc hotkeys) | Reuses the drop-zone/preview pipeline unchanged |
| Context menu, overflow menu, accessibility | Shell | Engine (commands they dispatch) | AppKit-only concerns |
| Stage / overview strip layer | Shell (`StagePanel`/`TileLayer`, overview) | Engine (`CameraMove` gains strip moves) | Drawing only; hidden members already excluded by the model change |
| Persistence | Model (Codable) | Shell (`LayoutStore`) | `Node.tabs` already serialises; floating groups need a backward-compatible decode |

## Standard Stack

No new dependency. Everything is system frameworks plus the existing KeyboardShortcuts 3.1.0. [VERIFIED: Package.swift dependencies list holds only KeyboardShortcuts `exact: "3.1.0"`]

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit `NSPanel` (`.borderless, .nonactivatingPanel`) | macOS 14 SDK | Strip panel, tear-off ghost panel | Same recipe as `CollapsedPanels` (proven non-activating, click-taking panel in this app) |
| ApplicationServices AX (`kAXCloseButtonAttribute` + `kAXPressAction`, `kAXMinimizedAttribute`, `kAXMainAttribute`/`kAXRaiseAction`) | system | Close/minimise group members, focus revealed tab | Only public way to act on other apps' windows; typechecked this session against the macOS 14 target |
| Core Animation (`CALayer`, `CATextLayer`) | system | Strip drawing, stage strip layer | Existing overlay convention (UI-SPEC platform rule) |
| KeyboardShortcuts | 3.1.0 (pinned) | 3 new `Name`s + `Recorder` rows; temporary Esc hotkeys during tear-off | Already used for every hotkey and for the Phase 4 rubber-band Esc (`ZoomInput.escapeModifiers`) |
| `os.Logger` | system | New `tabs` category | Project logging convention |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `NSMenu.popUp(positioning:at:in:)` | system | Tab context menu and overflow menu | Right-click / ⌃-click on a tab; overflow chevron |
| `NSAccessibilityCustomAction(name:handler:)` | system (10.13+) | "Close Tab" / "Move Out of Group" on each tab element | VoiceOver actions rotor |
| `NSAccessibility.Subrole.tabButtonSubrole` | system (10.13+) | Tab element subrole | See Pitfall 11: the UI-SPEC's `.tabButton` does not compile |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Sidecar `groups` on `DesktopLayer`, members kept in `windows` | Separate `FloatingGroup` list with members removed from `windows` | Cleaner type, but every one of ~80 `desktop.*` call sites (Arranger ×56, World ×11, Commands ×7, …) must be audited and `LayoutRestore`/`World.validate` duplicate checks extended. Higher regression risk to the Core Value path |
| Tear-off driven by the global InputTap stream | AppKit `mouseDragged` in the strip view | AppKit delivery outside the view's bounds was not confirmed this session (LOW), and modifier changes (⇧) would need a second path; the tap already feeds `flagsChanged` to the engine |
| Strip follows drags in the shell | Engine emits a strip effect per `.dragFrame` | Both work; shell-side keeps 60 Hz work out of the effect pipeline. Keep the formula in an engine helper so it is unit-tested |
| `.normal` level strip ordered with its group | `.floating` level like other overlays | `.floating` would float a floating group's strip over unrelated floating windows; UI-SPEC chose `.normal` |

**Installation:** none.

**Version verification:** Swift 6.4.2 toolchain, macOS 27.2 host, Tart VM `pane-test` (local, running). [VERIFIED: `swift --version`, `sw_vers`, `tart list` this session]

## Package Legitimacy Audit

This phase installs no external packages. No registry checks needed.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 User drag / click / key                           Apps (AX, WindowServer)
        |                                                   ^      |
        v                                                   |      | AX notifications, CG list
 InputTap (CGEventTap) --pointer(down/drag/up/flags)-->     |      v
   |  press on a strip panel? -> pressTab(member)      AXWindowSystem / WindowTracker
   |                                                    |  events: windowFocused, windowMoved,
 TabStripPanels (AppKit) --click/menu/button-->        |  frameApplied, windowDestroyed,
   |   (select tab, close tab, move out,               |  windowStateChanged(absent)
   |    close/min/float/dock group)                     v
   +------------------ ArrangerInput --------------> Arranger (pure engine)
                                                     |
               +-------------------------------------+----------------------------------+
               | DragSession: Phase 3 dwell 150 ms -> group dwell 400 ms/16 pt          |
               |   (window drag, whole-group drag, tear-off origin)                      |
               | TabGroups state: pendingReveal(new, old, 1 s), closeQueue(group, 1 s), |
               |   focusSuppress(until), parkedSize[identity]                           |
               | World.edit / reflow  ->  Model: LayoutTree(.tabs) + DesktopLayer.groups |
               | planShown(): Planner -> resolve(band=32) -> frames (selected -> content |
               |   rect), parks(hidden, size), strips                                    |
               +-------------------------------------+----------------------------------+
                                                     | effects
        +-------------------+--------------------+---+-------------+--------------------+
        v                   v                    v                 v                    v
  .perform([setFrame,   .preview(.group)   .tabStrips(...)   .announce/.beep      .save(.now)
   park(size), focus,    PreviewPanel       TabStripPanels    VoiceOver/log       layout.json
   close, minimize])                        (pool, Space-aware)
        |
        v
  AXAppThread per app: frame slot (setFrame/park coalesce), AXPress close, AXMinimized, AXMain+AXRaise
```

### Recommended Project Structure (new and touched files)

```
Sources/TransomModel/
├── TabBand.swift            # NEW: `TabBand.height = 32`, contentRect(of:), groupFrame(ofContent:) — pure geometry
├── Resolve.swift            # band: selected-only windowRects, +32 to tabs minimum, Resolution.hiddenTabs
├── DesktopLayer.swift       # floating group sidecar (+ backward-compatible decode)
├── TreeEdits.swift          # removeLeaf/insertLeaf (whole-group move), swap allows a tabs leaf
└── World.swift              # validate floating group NodeIDs < ids.next and disjoint from tree nodes
Sources/TransomEngine/
├── WindowSystem.swift       # WindowCommand: park(size:), close, minimize
├── DragSession.swift        # group dwell, tear-off origin, PreviewState.group
├── Planner.swift            # floating group placement, hidden members -> parks with sizes
├── Arranger+Tabs.swift      # NEW: select/reveal, close queue, move out, group buttons, tear-off commit
├── Arranger.swift           # hover/decide/release branches, planShown strips + sized parks, nextWake
├── Command.swift            # case tabs(TabCommand)  (.next, .previous, .moveOut)
├── TransomURL.swift         # next-tab, previous-tab, move-out-of-group
└── Recovery.swift / Arranger+Camera.swift  # quit plan includes hidden members at content rects
Sources/TransomMac/
├── Overlay/TabStripPanels.swift  # NEW: pool, TabStripView, a11y, context + overflow menus
├── Overlay/TearOffGhost.swift    # NEW (or inside TabStripPanels): click-through ghost panel
├── AX/AXAppThread.swift          # closeWindow(windowID:), minimizeWindow(windowID:)
├── AXWindowSystem.swift          # perform: .close, .minimize, .park(size:)
├── ArrangeController.swift       # strip press routing, .tabStrips effect, strip follow, 500 ms backstop
├── Shell/TabCopy.swift           # NEW: all strings, unit-tested
└── Input/Hotkeys.swift, Shell/*, Zoom/ShortcutsWindowController.swift, Zoom/StagePanel.swift
Tests/TransomModelTests/TabGroupModelTests.swift      # NEW
Tests/TransomEngineTests/ArrangerTabsTests.swift      # NEW
Tests/TransomMacTests/TabCopyTests.swift              # NEW
Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift  # NEW (VM only)
```

### Pattern 1: The band lives in `resolve` (model), not in the shell

**What:** A `.tabs` leaf keeps its tile rect in `nodeRects`; only its **selected** member gets `windowRects[selected] = content rect` (tile minus 32 pt at the top). Hidden members get no window rect; they are reported in a new `Resolution.hiddenTabs: [WindowRef: Rect]` (the content rect, for parking size and quit restore). The leaf's aggregate minimum is `max(member minimums) + (0, 32)`.

**Why here:** The current code sizes and places every present tab member identically: [VERIFIED: Sources/TransomModel/Resolve.swift:127-131, 151-152]

```swift
case let .tabs(windows, _):
    // Tabs share one rect, so it must fit the largest of them on each axis.
    let sizes = windows.filter(active.contains).compactMap { minimum[$0] }
    ...
case let .tabs(windows, _):
    for window in windows where active.contains(window) { result.windowRects[window] = rect }
```

Left as is, Phase 3's `planShown` writes every member into the tile (they overlap), the drop dry run ignores the band (WYSIWYG breaks), and the unfit pass never sees the extra 32 pt.

**Participation rule (recommend):** a tab leaf takes part iff its **selected** member is `.present`. Hidden members never make the leaf take part. This makes Minimize Group (selected → `.absent`) and native fullscreen of the selected member behave like Phase 3's absent panel: the slot is reserved, neighbours take the space, the strip hides. [VERIFIED: WindowState cases at Sources/TransomModel/IDs.swift:114-116: `case present, absent, fullscreen, closed`]

**Example:**
```swift
// Sources/TransomModel/TabBand.swift (new, pure)
public enum TabBand {
    /// Strip 28 pt + 4 pt gap (07-UI-SPEC Spacing exceptions).
    public static let height: Double = 32
    public static let stripHeight: Double = 28
    public static func content(of frame: Rect) -> Rect {
        Rect(x: frame.x, y: frame.y + height, width: frame.width, height: max(0, frame.height - height))
    }
    public static func frame(ofContent content: Rect) -> Rect {
        Rect(x: content.x, y: content.y - height, width: content.width, height: content.height + height)
    }
    public static func strip(of frame: Rect) -> Rect {
        Rect(x: frame.x, y: frame.y, width: frame.width, height: stripHeight)
    }
}
```
(`Rect(x:y:width:height:)` and top-left global coordinates: [VERIFIED: used verbatim in Sources/TransomModel/Resolve.swift:54-57 and Planner.swift:95-98].)

### Pattern 2: Floating groups as a sidecar on `DesktopLayer`

**What:** Add to `DesktopLayer`:
```swift
public struct FloatingTabGroup: Codable, Equatable, Sendable {
    public let id: NodeID            // minted from IDSource inside World.edit; never a tree node ID
    public var members: [WindowIdentity]   // tab order (insertion order, D-03 appends)
    public var selected: Int
    public var frame: Rect           // the GROUP frame, strip included
}
public private(set) var groups: [FloatingTabGroup]
```
Every member **stays** a `FloatingWindow` in `windows`, its `frame` kept equal to the group's content rect. New mutators: `group(_ window:, with target:, id:)`, `addTab`, `selectTab`, `setGroupFrame` (moves every member's stored frame), `removeFromGroup` (dissolve at one member: the survivor's frame becomes the full group frame, UI-SPEC "the 32pt band returns to it"). `remove(_:)` must also drop the window from its group (dissolve rule) so the close path (`World.apply(.closed)`) needs no change.

**Why:** Today the layer holds single windows only: [VERIFIED: Sources/TransomModel/DesktopLayer.swift:5-9, 13-14]
```swift
public struct FloatingWindow: Codable, Equatable, Sendable {
    public let window: WindowRef
    public var frame: Rect
    public var state: WindowState
}
...
public struct DesktopLayer: Codable, Equatable, Sendable {
    public private(set) var windows: [FloatingWindow]
```
Keeping members in `windows` means `Desk.contains`, `Desk.state(of:)`, `Desk.close`, `rekey`, `withoutTitleHints`, `World.validate`'s cross-desk duplicate check and `LayoutRestore.reattach` (which iterates `desk.tree.windows + desk.desktop.windows.map(\.window)`) all keep working. [VERIFIED: Sources/TransomEngine/LayoutRestore.swift:21, 27]

**Persistence:** `DesktopLayer` uses synthesized `Codable`; adding a non-optional stored property makes every existing layout.json fail with `keyNotFound`. Write a custom `init(from:)` that uses `decodeIfPresent(..., forKey: .groups) ?? []` and keep `LayoutFile.schemaVersion` at 2. [VERIFIED: `public static let schemaVersion = 2` at Sources/TransomEngine/LayoutFile.swift:41; `public static let currentSchemaVersion = 1` at Sources/TransomModel/World.swift:87 and its decoder rejects any other version at World.swift:270-273]. An older build reading a new file ignores the unknown `groups` key and sees members as plain floating windows at the content rect, which its planner moves on screen: a safe downgrade.

**Validation (add to `DesktopLayer.validate` and `World.validate`):** each group has ≥ 2 members, all present in `windows`, no window in two groups, `selected` in range, valid `frame`, group IDs unique, `id.raw < ids.next`, and no group ID equal to a tree node ID on the same desk. Bound the group count by `LayoutTree.maxNodes` so a hostile file cannot make validation quadratic-expensive.

**Rules every engine path must honour (audit list for the planner):**
- Only the **selected** member's own moves update the group frame (`recordFloatingFrame` → `setGroupFrame(TabBand.frame(ofContent:))`). A hidden member's moves are ignored (it is parked or about to be). [VERIFIED: the parked guard pattern already exists at Sources/TransomEngine/Arranger.swift:946-947: `guard !parkRequested.contains(window.identity) else { return [] }`]
- `Planner` places the selected member at `TabBand.content(of: group.frame)` (clamped like any floater) and puts hidden members in `parks` with the content size.
- `arrangeAll` docks a floating group as one `.tabs` leaf; `floatAll` floats a docked group as one floating group; `rehome` of one member breaks it out of its group (an OS fact; acceptable) or moves the whole group (recommend: whole group, keyed on the selected member).
- Desktop focus target (Arranger.swift:1217-1219 picks a floating window by focus order) must skip hidden members.
- Overview floating list (OverviewController.swift:657) must skip hidden members.

### Pattern 3: Group dwell inside `DragSession`

**What:** Keep the Phase 3 150 ms dwell and add a second deadline for centre targets. Today a centre hover is turned into "no target": [VERIFIED: Sources/TransomEngine/Arranger.swift:1432 `case .tile(_, .center)?: target = nil  // tab groups from a centre drop are Phase 7 (D-02)`] and the keyboard Dock path beeps on a centre: [VERIFIED: Arranger.swift:1110 `if case .tile(_, .center) = target { return [.beep] }  // tab groups from a centre drop are Phase 7`]. The keyboard path stays as is (UI-SPEC: keyboard commands never create groups).

Add to `Hover` a `groupTarget: GroupTarget?` (engine enum, not a new `DropTarget` case, so `LayoutTree.applyDrop` and `Planner.dockTarget` stay untouched):
```swift
enum GroupTarget: Equatable, Sendable {
    case tile(DeskKey, NodeID)        // docked panel or docked group centre
    case floating(DeskKey, WindowRef) // a plain floating window's middle 50%
    case floatingGroup(DeskKey, NodeID)
}
```
Add to `DragSession`: `groupAnchor: Point?`, `groupSince: ContinuousClock.Instant?`, `static let groupDwell: Duration = .milliseconds(400)`, `static let groupRest = 16.0`. On each pointer sample with an unchanged hover: if the pointer is more than 16 pt from the anchor **and the group preview is not yet shown**, reset anchor and `groupSince`. `nextWake` must include the group deadline. [VERIFIED: nextWake aggregates deadlines at Sources/TransomEngine/Arranger.swift:1032-1035; `public static let dwell: Duration = .milliseconds(150)` at DragSession.swift:105]

Before 400 ms the decision is exactly today's miss (snap-back ghost for docked, nothing/clamp ghost for floating). At 400 ms run a group dry run (Pattern 4) and show `PreviewState.group(frame:strip:label:)` or Blocked / Collapsed. Modifier change already restarts via `Hover.modifiers`. Exclusions (UI-SPEC Surface 1): ⇧, ⌘ over a plain docked panel (swap wins), own tile, Desktop tile, collapsed block, excluded/never-dock target, whole-group drag.

**Floating centre hit test:** topmost floating window under the pointer, excluding the dragged window. `desktop.windows` is back to front [VERIFIED: DesktopLayer.swift:11 "The floating windows of one desk, back to front"], so search it reversed; for a group, use its content rect's middle 50%.

### Pattern 4: Drops are desk-level edits (one undo step)

- Docked target: existing `dropping(window, on:, at: .tile(id, .center))` already removes the window from wherever it is and calls `applyDrop` → `group(window, into:)`, which makes the dropped window selected. [VERIFIED: Sources/TransomModel/DropZones.swift:59 `case let .tile(node, .center): try group(window, into: node)`; TreeEdits.swift:110-111 sets `selected: 1` / `selected: windows.count`]
- Floating target: a new `droppingIntoFloating(window, on: key, target:)` running inside one `World.edit`: remove the dragged window from tree or layer, then `desktop.group(...)` at the target window's current frame (D-02) or `addTab` to the floating group.
- Dry run: plan the candidate desk; unfit with zoom off → Blocked "Not enough room"; zoom on → Collapsed (reuse `collapse(_:area:)` as `decide` does today).

### Pattern 5: Tab switch = reveal, read back, then park (engine state machine)

**Engine state:**
```swift
struct PendingReveal: Equatable, Sendable {
    var group: GroupKey          // tree NodeID or floating group id, with its DeskKey
    var revealed: WindowRef
    var previous: WindowRef
    var deadline: ContinuousClock.Instant   // now + 1 s
}
```
Flow on select (click, overflow, Next/Previous, D-08):
1. `World.reflow` (no undo step: UI-SPEC "Selecting a tab is not an undo step") → `selectTab`.
2. `planShown()` emits `setFrame(new, content)` and `.focus(new)`; the strip effect shows the new selection at once. **`previous` is excluded from parks while a reveal is pending** (keep it where it is, covering the content rect).
3. On `.frameApplied(new, requested, actual)` with `actual` within 2 pt of the content rect: clear the pending reveal, replan → park `previous` (with size).
4. On `.tick` past the deadline: reflow `selectTab(previous)`, replan, `[.beep, .announce("Couldn't show “{App}”")]`, log.

Read-backs already arrive as `case frameApplied(WindowRef, requested: Rect, actual: Rect)` [VERIFIED: Sources/TransomEngine/WindowSystem.swift:141]. A parked window has no `lastRequested` entry once it leaves `planned` (Arranger.swift: `lastRequested = lastRequested.filter { planned.contains($0.key) || hidden.contains($0.key) }`), so the reveal `setFrame` is always sent and always gets a read-back.

### Pattern 6: Strip panels (shell) fed by a pure `TabStrip` effect

**Engine value:**
```swift
public struct TabStrip: Equatable, Sendable {
    public var group: GroupKey
    public var frame: Rect             // TabBand.strip(of: groupFrame), global top-left
    public var members: [WindowRef]
    public var titles: [String]        // explicit: WindowRef equality ignores titleHint (Pitfall 7)
    public var selected: Int
    public var floating: Bool          // Float Group vs Dock Group button
}
case tabStrips([TabStrip], displayUUID: String)   // ArrangerEffect; empty hides
```
Emitted from `planShown()` for the **shown** desk of each display, sent only on change (the `showBlocks` pattern at Arranger.swift `showBlocks(_:)`). Strips are absent for groups whose selected member is not present, that are parked/collapsed by the camera, or whose desk is not shown.

**Shell (`TabStripPanels`)** copies `CollapsedPanels`' pool, appearance observers and `leftOnAnotherSpace` replacement, with the UI-SPEC's differences: `level = .normal`, `collectionBehavior = [.stationary, .ignoresCycle]` (no `.canJoinAllSpaces`), `allowsToolTipsWhenApplicationIsInactive = true`, a tracking area with `.activeAlways`, and the view returns `acceptsFirstMouse = true`. [VERIFIED: CollapsedPanels makePanel at Sources/TransomMac/Zoom/CollapsedPanels.swift:196-207: `styleMask: [.borderless, .nonactivatingPanel]`, `panel.level = .floating`, `panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`, `panel.sharingType = .none`, `panel.hidesOnDeactivate = false`; subclass with `canBecomeKey`/`canBecomeMain` false at lines 7-10]

Clicks, hover, buttons, right-click and the overflow menu are handled by the view with AppKit events (select on **mouse-up** with < 4 pt travel). Each action calls back into `ArrangeController`, which feeds a new `ArrangerInput.tab(TabAction)` (`select(member)`, `closeTab(member)`, `moveOut(member)`, `closeGroup`, `minimizeGroup`, `toggleGroupFloat`). Paused/not-ready refusals are the engine's (`.beep` + announcement), so the shell has no policy.

**Ordering:** call `orderFrontRegardless()` for a group's strip when one of its members is focused/raised or moved into the content rect (engine can add `raised: Bool`/a separate `.raiseStrip(GroupKey)` effect on `windowFocused` of a member). Do **not** order every strip front on every replan: that would lift a floating group's strip above an unrelated floating window raised over it (UI-SPEC row "level .normal").

**Following:** during a title-bar drag of the selected member, `ArrangeController.pollDragFrame`'s callback already receives the window's CG bounds at ~60 Hz [VERIFIED: Sources/TransomMac/Input/DragFramePoller.swift:11-23 polls every 16 ms while the left button is down]; move that group's strip to `TabBand.strip(of: TabBand.frame(ofContent: bounds))` inside `CATransaction.setDisableActions(true)`. Backstop: a 500 ms main-actor timer while any strip is shown reads `DragFramePoller.bounds(of:)` for each selected member and re-places a strip whose window drifted more than 2 pt from its planned content rect (the engine's existing correction path moves the window back; the strip follows).

### Pattern 7: Tear-off through the existing pointer pipeline

**What:** The press on a strip is resolved in the tap pipeline, not in AppKit, so the engine sees down/drag/up in order with modifiers:
1. `ArrangeController.handle(_ event:)` on `leftMouseDown`: if `event.windowUnderPointer` is one of the strip panels' window numbers, ask `TabStripPanels` (synchronously, main actor) which tab is under the point, and send `PointerEvent(kind: .down, ..., pressWindow: nil)` plus a new `pressTab: (GroupKey, WindowRef)?` field (or a separate `ArrangerInput.tabPress`). Never resolve `pressWindow` for a strip press (Pitfall 4).
2. The engine keeps a *candidate* tear session; on `.dragged` outside the strip rect it becomes a `DragSession` with `origin: .tearOff(GroupKey)`, `kind = .move`, the member as `window`, and a synthetic landing frame (pre-group wanted frame size, else content size; centred on the pointer, top 12 pt above it).
3. `hover`/`decide` use that synthetic frame instead of `windows[window].frame`; ⌘ swap is never offered; the "own tile" exclusion is replaced by "pointer back in the source strip → no preview".
4. Release: `.dock` → `dropping` (removes the member from its group via `tree.remove`/`desktop.remove`, which dissolves at one); group target → Pattern 4; elsewhere → float at the landing frame (show a hidden Desktop first, Phase 3 D-31); strip → cancel. Esc → cancel via temporary hotkeys registered only during the tear-off. [VERIFIED: the pattern exists at Sources/TransomMac/Zoom/ZoomInput.swift:38-39 `/// Esc with no modifier, ⇧, ⌘ and ⌘⇧ ... Never with ⌥: ⌥⌘Esc is Force Quit.` `private static let escapeModifiers: [NSEvent.ModifierFlags] = [[], [.shift], [.command], [.command, .shift]]`]
5. The ghost panel follows the pointer in the shell (it needs the pointer only; feed it from the same tap events).

The click path (press + release inside the strip with < 4 pt travel) stays entirely AppKit; the engine's candidate session ends on `.up` with no tear.

### Pattern 8: AX close and minimise as `WindowCommand`s, sequenced by the engine

**New commands:**
```swift
public enum WindowCommand: Equatable, Sendable {
    case setFrame(WindowRef, Rect)
    case park(WindowRef, displayUUID: String, size: Size? = nil)   // nil = tracked size (today)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
    case close(WindowRef)      // NEW: AXPress on the window's kAXCloseButtonAttribute element
    case minimize(WindowRef)   // NEW: set kAXMinimizedAttribute = true
}
```
[VERIFIED: current cases at Sources/TransomEngine/WindowSystem.swift:154-160: `case setFrame(WindowRef, Rect)`, `case park(WindowRef, displayUUID: String)`, `case focus(WindowRef)`, `case raise(WindowRef)`, `case setHidden(WindowRef, Bool)`]. Enum cases may carry default argument values (Swift 5.1+), so existing `.park(w, displayUUID: u)` call sites compile unchanged. `FakeWindowSystem` (TransomTestSupport) and `ExclusionFilter.admit` need the new cases; excluded apps' commands are still dropped first.

**AX side (AXAppThread):** add `closeWindow(windowID:)` (copy `kAXCloseButtonAttribute`, `AXUIElementPerformAction(button, kAXPressAction)`) and `minimizeWindow(windowID:)` (`AXUIElementSetAttributeValue(element, kAXMinimizedAttribute, kCFBooleanTrue)`) as jobs next to `focusWindow`/`raiseWindow` [VERIFIED: those jobs exist at Sources/TransomMac/AX/AXAppThread.swift:225-240 using `kAXMainAttribute` and `kAXRaiseAction`]. All three constants typecheck against `-target arm64-apple-macos14` (verified this session).

**Close Group queue (engine):** `closeQueue = (group, remaining: [WindowRef], current: WindowRef, deadline)`. Step: if `current` is hidden, run Pattern 5 to reveal it first and wait for the read-back; then emit `.close(current)` and set a 1 s deadline. On `.windowDestroyed`/`.windowStateChanged(.closed)` for `current` → next (the model's `remove` already selected a neighbour). On deadline → stop, keep it selected, announce "“{App}” didn't close". A second Close Group click resumes from the remaining list. Close Tab = the same queue with one entry.

**Minimize Group:** `.minimize(selected)`. The tracker turns a minimised window into `.absent` [VERIFIED: Sources/TransomEngine/WindowTracker.swift:143 `?? (snapshot.minimized == true || app.appHidden ? .absent : snapshot.fullScreen == true ? .fullscreen : .present)`], which with Pattern 1's participation rule hides the strip and reserves the slot; restoring from the Dock brings it back with the same selection.

### Pattern 9: Whole-group moves need leaf-level edits

`LayoutTree.insert` always creates `.panel(window)` and `swap` refuses anything but two panels: [VERIFIED: Sources/TransomModel/TreeEdits.swift:34 `next.nodes[leaf] = .panel(window)`; lines 161-162 `guard case .panel? = nodes[leafA] else { throw .notALeaf(leafA) }` / `guard case .panel? = nodes[leafB] ...`]. The current drop/float paths remove the **window**, which would tear one member out of a group instead of moving the group: [VERIFIED: Arranger.swift `dropping`: `} else if desk.tree.state(of: window) != nil { try desk.tree.remove(window) }` then `applyDrop(target, window:)`; `float(_:)` does `try desk.tree.remove(window)`]

Add model edits:
- `removeLeaf(_ id: NodeID) -> (node: Node, states)` and `insertLeaf(_ node: Node, states:, at edge:, of target:, ids:)` (generalise `insert` to take a leaf node; reuse rules 1–3 and `normalize`/`validate`).
- `swap` allowing one side to be a `.tabs` leaf (UI-SPEC: ⌘ swap of a whole group with a plain panel).
- `DesktopLayer`: `removeGroup(id) -> FloatingTabGroup + members`, `addGroup(...)`.

Engine branches (when `window` is the **selected** member of a group): title-bar drag drop/undock/swap, green button, Dock Window / Float Window, Float Group / Dock Group buttons, Arrange All / Float All. Each stays one `World.edit` (one undo step).

### Anti-Patterns to Avoid
- **Subtracting the band in the shell or in `planShown`:** the dry run and the unfit pass would disagree with what gets written. Do it in `resolve`.
- **Minimising or ⌘H-hiding hidden tabs:** forbidden by D-07; also makes them `.absent`, which changes layout.
- **Ordering every strip front on every replan:** breaks the floating-window z-order rule.
- **Reusing `widen(toShow:)` for a hidden member before selecting it:** focus of a hidden member must select it first; the camera widen should then see the group's leaf, not try to show a parked sliver. [VERIFIED: widen runs on every `windowFocused` at Arranger.swift:854 `let widened = if case .windowFocused(let window) = event { widen(toShow: window, new: false) } ...`]
- **Adding a `DropTarget.floating` case to the model enum:** forces edits to `applyDrop`, `dockTarget` and every exhaustive switch for an engine-only concept.
- **Logging titles:** titles stay `.private`; `.fault` strings name identities only (project rule).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Hiding inactive tabs | New hide mechanism, ⌘H, minimise | Phase 4 park (`WindowCommand.park` + `DisplayInfo.parkedFrame`) with a size | Proven; quit/crash restore already understand parked slivers |
| Hotkeys and recorder rows | Carbon code | KeyboardShortcuts `Name` + `Recorder` | Existing convention; `isTakenBySystem` log already runs |
| Esc during tear-off | NSEvent monitors | Temporary `KeyboardShortcuts.events(for: Shortcut(.escape, modifiers:))` (ZoomInput pattern) | Works while Transom is never active |
| Panel pooling / Space stranding | New panel lifecycle | `CollapsedPanels` pool + `NSWindow.leftOnAnotherSpace(_:)` | Encodes the macOS 27 lock-stranding fix |
| Dissolve on last member | Custom ungroup | `LayoutTree.remove` (already turns a 1-member tabs node into `.panel` under the same NodeID) | [VERIFIED: TreeEdits.swift:77-84] |
| Neighbour selection on close | Custom picker | `LayoutTree.remove`'s rule (index-taker, clamped to last) = right neighbour else left | [VERIFIED: TreeEdits.swift:81-84 "Removing the selected tab selects the one that took its index, clamped to the last."] |
| Native tab title (D-09) | Reading Safari tabs | `WindowInfo` of the native group's leader (`visibleMemberID`, live `titleHint`) | `TabGroupTracker` already folds native tabs into one window |
| URL parsing | New parser | `TransomURL.commands` whitelist + existing rate limit | Security posture already reviewed |
| Strings | Inline literals | `TabCopy` (AppKit-free, unit-tested like `MenuCopy`) | UI-SPEC copy contract |

**Key insight:** almost every hard part (parking, drop zones, previews, focus path, close confirmation, Space-stranding fix) already exists. Phase 7's risk is in **wiring the group concept through every path that today assumes one window per leaf or per floater**, not in new mechanisms.

## Runtime State Inventory

Not a rename/refactor phase. One persistence-shape change only:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | layout.json (`~/Library/Application Support/Transom/`): `Node.tabs` already encoded; `DesktopLayer` gains `groups` | Code edit only: backward-compatible decode (`decodeIfPresent ?? []`). No data migration: existing files have no groups |
| Live service config | None — Transom has no external services | None |
| OS-registered state | None new (no new login item, URL scheme host additions are code) | None |
| Secrets/env vars | None | None |
| Build artifacts | None (no target or bundle ID change) | None |

## Common Pitfalls

### Pitfall 1: Park writes the old size
**What goes wrong:** A window that just joined a group is parked at its full-tile size; when selected later it shows at the wrong size until the next correction, and the 1 pt sliver may land differently.
**Why it happens:** [VERIFIED: Sources/TransomMac/AXWindowSystem.swift:229-234] `.park` → `display.parkedFrame(size: info.frame.size, among: displays)`, and the doc comment says "`.park` is a frame write through the same slot". A `setFrame(content)` followed by `park` in one perform coalesces to the park.
**How to avoid:** `park(_, displayUUID:, size:)`; the engine passes the content size for hidden members. Track `parkedSize[identity]` next to `parkRequested` (today a `Set<WindowIdentity>` [VERIFIED: Arranger.swift:170-171]) and re-park when the content size changes by > 0.5 pt (group resized, docked, floated, display change).
**Warning signs:** after a tile resize, selecting a hidden tab shows it at the old size for ~1 s.

### Pitfall 2: Hidden members are written into the tile
**What goes wrong:** All members stack in the tile; the Core Value breaks.
**Why:** current `resolve` (see Pattern 1).
**How to avoid:** selected-only `windowRects`; hidden in `Resolution.hiddenTabs`; `Planner` → `parks`. Unit test: a two-member group plans exactly one frame.

### Pitfall 3: Quit and Restore All leave hidden members off screen or re-park them
**What goes wrong:** Quit: `homeTiles()` only covers desks whose camera is not at home, so on a desk at home a docked hidden member falls to the "stranded" rule and lands centred on the display, not in the content rect. [VERIFIED: Sources/TransomEngine/Arranger+Camera.swift:121-123 `for (key, desk) in world.desks where resolvedView(for: key) != .home {`; Recovery.swift:73-78 uses `homeTiles[id]` for docked windows, else `isStranded` + `destination(for:home:display:)`.] Restore All: `restoreAll()` rescues stranded windows and then calls `replan()` in the same effect list, which would re-park hidden members immediately. [VERIFIED: Arranger+Commands.swift:31-37: `let moves = rescueStranded(desks: world)` ... `return (moves.isEmpty ? [] : [.perform(moves)]) + replan() + ...`]
**How to avoid:** Quit: pass every hidden member's content rect (docked and floating groups, every desk) into `terminationPlan` (treat them as docked with a home tile). Restore All: dissolve every group on the affected desks **first** (one undoable `World.edit` per desk, cascade 24 pt, clamp into the Desktop, show a hidden Desktop), then rescue and replan.
**Warning signs:** QuitRestore VM test shows a fixture window centred instead of at the content rect.

### Pitfall 4: A press on the strip starts a drag on the window behind it
**What goes wrong:** ⌘⇧ rubber band or a stray drag session on an unrelated window.
**Why:** `pressWindow` falls back to the front-most tracked layer-0 CG window containing the point when the window under the pointer is not tracked. The strip is Transom's own untracked window, so the fallback walks past it. [VERIFIED: Sources/TransomMac/ArrangeController.swift:460-470: `for entry in list where entry.layer == 0 && entry.bounds.contains(point) {` ... `if let found = trackedWindow(cgID: entry.windowID) ?? synthetic?.window { return found }`]
**How to avoid:** in `handle(_:)` (and `zoomInput.pointerDown`), check `event.windowUnderPointer` against the strip pool's window numbers before anything else; route to the tab-press path (Pattern 7).

### Pitfall 5: Floating group frame moved by a hidden member's echo
**What goes wrong:** A hidden member's late frame report (before or during parking) moves the whole floating group.
**How to avoid:** only the selected member's moves update `group.frame`; hidden members' moves are dropped (they are parked or pending park).

### Pitfall 6: D-08 fights Minimize Group and closes
**What goes wrong:** After the selected member is minimised or closed, macOS makes another window of the same app key. If that window is a hidden member, D-08 selects it and the group pops back (defeating Minimize Group) or picks a different tab than D-12's right neighbour.
**Why:** Same-app members are common (two Finder windows). This is macOS key-window behaviour on minimise/close. [ASSUMED]
**How to avoid:** a short suppression window per group (recommend 1 s) after Transom-initiated or observed selection changes, minimise, or member close, during which a `windowFocused` of a hidden member does not switch tabs. Also ignore focus echoes of the window Transom itself just revealed. Test both in the VM with two fixture windows of one app.
**Warning signs:** Minimize Group with two fixture windows of one app leaves a visible group.

### Pitfall 7: Strip never updates titles
**What goes wrong:** A tab keeps an old title (or a native Safari tab title never follows).
**Why:** `WindowRef` equality ignores `titleHint`: [VERIFIED: Sources/TransomModel/IDs.swift:101 `public static func == (lhs: WindowRef, rhs: WindowRef) -> Bool { lhs.identity == rhs.identity }`]. A `next != shown` change check on `[WindowRef]` misses title changes. Also, `World` stores refs whose titles are emptied for layout.json.
**How to avoid:** `TabStrip.titles: [String]` taken from the live `windows[identity].window.titleHint`.

### Pitfall 8: Strips on the wrong Space, or replaced on every Space switch
**What goes wrong:** A strip shows on a Space where its group is not, or `leftOnAnotherSpace` reports true for a correctly placed strip and churns panels (and logs "was off the shown Space; made a new one") every switch.
**Why:** The strip deliberately lacks `.canJoinAllSpaces`, so it belongs to the Space it was ordered in. `leftOnAnotherSpace` returns true for any window with a number that is not on the active Space: [VERIFIED: Sources/TransomMac/Displays.swift:69-73 `guard windowNumber > 0, !isOnActiveSpace else { return false }` ... `return true`]. An ordered-out panel may also report `isOnActiveSpace == false`. [ASSUMED]
**How to avoid:** order strips in only for the shown desk, and only after the engine's `spaceChanged` (macOS has switched by then); order out strips of desks no longer shown; run the `leftOnAnotherSpace` check only for a strip that is visible and belongs to the shown desk. VM test with two Spaces plus a lock/unlock.

### Pitfall 9: Whole-group drag tears out the selected member
**What goes wrong:** Dragging a group by the selected window's title bar moves only that window out of the group.
**Why:** `dropping`/`float`/`commitUndock` remove the window, not the leaf (Pattern 9).
**How to avoid:** branch on "selected member of a group" in every drag/float/dock path; unit-test each.

### Pitfall 10: Close confirmation slower than the 1 s rule
**What goes wrong:** Close Group stops after the first member even though it closed, because Transom's close needs two sources (AX invalid + gone from the CG list) and may take longer than 1 s under load.
**How to avoid:** start the 1 s deadline at the AX press, but treat "AX element invalid" (an early `windowStateChanged`/destroyed signal from the tracker) as success for the queue, or make the deadline a named constant the VM test can measure and tune. [ASSUMED: confirmation latency not measured this session]

### Pitfall 11: UI-SPEC accessibility subrole name does not compile
**What goes wrong:** `NSAccessibility.Subrole.tabButton` is a compile error.
**Fact:** the Swift name is `.tabButtonSubrole` (header `NSAccessibilityTabButtonSubrole`, macOS 10.13). [VERIFIED: local `swiftc -typecheck -target arm64-apple-macos14`: `.tabButton` → "type 'NSAccessibility.Subrole' has no member 'tabButton'"; `.tabButtonSubrole` typechecks; header line `APPKIT_EXTERN NSAccessibilitySubrole const NSAccessibilityTabButtonSubrole API_AVAILABLE(macos(10.13));`]

### Pitfall 12: Camera parking and hidden-tab parking collide
**What goes wrong:** With zoom on, a view that excludes the group parks members "at its own size"; when the view returns, hidden members must stay parked and only the selected one comes back.
**How to avoid:** `ViewPlanner` keeps hidden members in `parks` in every view (they are never in `frames`); `parkRequested`/`parkedSize` dedupe prevents double parks. Stage `TileMove`s come from plan frames, so hidden members are automatically never drawn or captured. [VERIFIED: ViewPlanner.swift `.node` view: `let outside = desk.tree.windows.filter { tree.states[$0.identity] == nil && desk.tree.state(of: $0) == .present }` + `plan.parks = (plan.parks + outside)`]

### Pitfall 13: Hotkey names are a persistent contract
`nextTab`, `previousTab`, `moveOutOfGroup` must never be renamed once shipped (UI-SPEC, Phase 3 Pitfall 13). Adding `Command.tabs(...)` touches every exhaustive switch over `Command` (`MenuCopy`, `CommandMenu`, `Hotkeys.entries`, `Arranger.availability`, `ShortcutsWindowController`); the compiler finds them all.

## Code Examples

### Hidden members to parks with size (Planner)
```swift
// In Planner.plan, after resolution (sketch; names per Pattern 1/2)
var parks = desk.tree.isDesktopHidden == true ? floating.map(\.window) : []
var parkSizes: [WindowRef: Size] = [:]
for (window, content) in resolution.hiddenTabs {          // docked groups
    parks.append(window); parkSizes[window] = Size(width: content.width, height: content.height)
}
for group in desk.desktop.groups {                        // floating groups
    let content = TabBand.content(of: group.frame)
    for (i, id) in group.members.enumerated() where i != group.selected { /* parks + parkSizes */ }
}
```
(`parks` today: [VERIFIED: Sources/TransomEngine/Planner.swift:62 `let parks = desk.tree.isDesktopHidden == true ? floating.map(\.window) : []`].)

### Sized park in the shell
```swift
case .park(_, let uuid, let size):
    guard let display = displays.first(where: { $0.uuid == uuid }) else { /* log, continue */ continue }
    thread.enqueueFrame(windowID: windowID, rect: display.parkedFrame(size: size ?? info.frame.size, among: displays), ref: info.window)
```
(`parkedFrame(size:among:)` signature: [VERIFIED: Sources/TransomEngine/WindowSystem.swift:23 `public func parkedFrame(size: Size, among displays: [DisplayInfo]) -> Rect {`].)

### Strip context menu from a never-active app
```swift
override func rightMouseDown(with event: NSEvent) {
    guard let tab = tabIndex(at: convert(event.locationInWindow, from: nil)) else { return }
    let menu = NSMenu()
    menu.addItem(withTitle: TabCopy.closeTab, action: #selector(closeTab(_:)), keyEquivalent: "").representedObject = tab
    menu.addItem(withTitle: TabCopy.moveOut, action: #selector(moveOut(_:)), keyEquivalent: "").representedObject = tab
    menu.items.forEach { $0.target = self }
    menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
}
```
`popUp(positioning:at:in:)` typechecks at the macOS 14 target (verified). Whether it tracks correctly from a non-activating panel of an app that never activates is [ASSUMED]; cover it in the VM test.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Centre drop refused / mapped to nearest edge | Centre drop after a 400 ms rest groups; keyboard Dock still maps to an edge | This phase | `Planner.dockTarget` comment ("centre drops make tab groups only from Phase 7") stays true for the keyboard path; update its wording only |
| Tab members share the full tile rect | Selected member gets tile minus 32 pt band; hidden members parked | This phase | `resolve` contract change; update `ResolveTests` |

**Deprecated/outdated:** nothing removed. The Arranger comments at L1110/L1432 marking Phase 7 should be replaced, not left stale.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | macOS makes another window of the same app key after a minimise/close, which can be a hidden (parked) member | Pitfall 6 | If false, the suppression window is harmless; if true and not handled, Minimize Group fails for same-app groups |
| A2 | An ordered-out non-`.canJoinAllSpaces` panel reports `isOnActiveSpace == false`, and `orderFrontRegardless()` after `spaceChanged` places it on the newly active Space of its display | Pitfall 8, Pattern 6 | Strips on wrong Space or log churn; VM test catches it |
| A3 | `NSMenu.popUp(positioning:at:in:)` tracks normally from a non-activating panel in an app that never activates | Code Examples | Context menu would not open; fallback `NSMenu.popUpContextMenu(_:with:for:)` in `rightMouseDown` |
| A4 | Two-source close confirmation usually completes within 1 s of the AX close press | Pitfall 10, Pattern 8 | Close Group stops early; tune the constant |
| A5 | AppKit would keep sending `mouseDragged` to the strip view outside its bounds (not relied upon: Pattern 7 uses the tap stream instead) | Alternatives | None if Pattern 7 is followed |
| A6 | Parking at the content size works for every app (no app refuses an off-screen frame of that size) | Pattern 5 | Same risk as Phase 4 parking, which passed UAT; the 1 s reveal failure rule covers refusals |
| A7 | `.stationary` collection behaviour leaves the strip in place during Mission Control while member windows shrink (cosmetic) | Pattern 6 | Cosmetic only; Transom's Mission Control takeover may make it moot |

## Open Questions (RESOLVED)

1. **Floating group model shape**
   - What we know: a sidecar on `DesktopLayer` keeps every existing path working and decodes old files; a separate list is cleaner but touches ~80 call sites.
   - Recommendation: sidecar (Pattern 2). Planner should make this the first model task and include a call-site audit task for the rules listed in Pattern 2.
   - RESOLVED: sidecar group list on `DesktopLayer`, schema stays 2 (07-04).
2. **Focus suppression length (A1)**
   - Recommendation: 1 s per group after minimise/close/selection change; constant in the engine; tune in the VM test.
   - RESOLVED: 1 s engine constant, tuned in the VM test (07-02, 07-05).
3. **Strip follow source during a drag**
   - Recommendation: shell-side via the existing `DragFramePoller` callback with an engine-tested geometry helper; no 60 Hz effects.
   - RESOLVED: shell-side `DragFramePoller` follow with an engine-tested geometry helper and a 500 ms backstop (07-03).
4. **Rehome of a floating group member to another display/Space**
   - Question: whether to move the whole group or break the member out.
   - Recommendation: move the whole group when the **selected** member is rehomed; ignore hidden members (they are parked, already guarded by `parkRequested` in `rehome`).
   - RESOLVED: whole-group rehome when the selected member is rehomed; hidden members ignored (07-06).
5. **UI-SPEC subrole spelling** — use `.tabButtonSubrole` (Pitfall 11); no product decision needed. RESOLVED: `.tabButtonSubrole` (07-03).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift toolchain | build/test | ✓ | Apple Swift 6.4.2 | — |
| macOS host | build only (no live runs) | ✓ | 27.2 (26B123) | — |
| Tart + VM `pane-test` | VM live tests | ✓ | local VM, running | — |
| graft | code navigation | ✓ | `~/.local/bin/graft` | grep/LSP |
| Xcode test runtime (for `vm-live-test.sh`) | VM live tests | ✓ (script copies from `xcode-select -p`) | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`, `@Test`, `#expect`) on SPM test targets; ~1460 existing tests |
| Config file | `Package.swift` test targets: `TransomModelTests`, `TransomEngineTests` (+ `TransomTestSupport`), `TransomMacTests`, `TransomMacIntegrationTests` (live, gated by `TRANSOM_LIVE=1`) |
| Quick run command | `swift test --filter 'TabGroupModelTests|ArrangerTabsTests|TabCopyTests'` |
| Full suite command | `swift test` (host-safe: integration tests skip without `TRANSOM_LIVE`) plus `scripts/check-no-appkit.sh` |
| VM live command | `scripts/vm-live-test.sh TabGroupIntegrationTests` (never on the host) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TABS-01 | `resolve` gives one frame per group (content rect), +32 pt minimum; floating group decode/validate/round-trip; v2 file without `groups` decodes | unit (model) | `swift test --filter TabGroupModelTests` | ❌ Wave 0 |
| TABS-01 | Dwell: no group before 400 ms, group after, restart on > 16 pt, ⇧/⌘/own-tile exclusions; drop on docked panel, docked group, floating window; dropped window selected; Blocked/Collapsed; one undo step | unit (engine) | `swift test --filter ArrangerTabsTests` | ❌ Wave 0 |
| TABS-02 | Select: setFrame+focus first, park(previous, content size) only after `frameApplied`; 1 s failure reverts + beep; D-08 focus selects; suppression after minimise/close | unit (engine) | `swift test --filter ArrangerTabsTests` | ❌ Wave 0 |
| TABS-02 | Real windows: park leaves a sliver at content size and a reveal brings it back; strip click does not activate Transom | live (VM) | `scripts/vm-live-test.sh TabGroupIntegrationTests` | ❌ Wave 0 |
| TABS-03 | Close Group queue order and 1 s stop; Minimize Group → `.minimize(selected)` and strip hidden; Float/Dock Group and title-bar drag move the whole leaf | unit (engine) | `swift test --filter ArrangerTabsTests` | ❌ Wave 0 |
| TABS-03 | AX close press closes a fixture window; AX minimise minimises it | live (VM) | `scripts/vm-live-test.sh TabGroupIntegrationTests` | ❌ Wave 0 |
| TABS-04 | Tear-off: dock on edge, float at landing frame, join another group, cancel on strip/Esc; dissolve at one | unit (engine) | `swift test --filter ArrangerTabsTests` | ❌ Wave 0 |
| TABS-05 | Floating group placement and parking; different-app members; native tab member keeps `visibleMemberID` addressing | unit (engine) | `swift test --filter ArrangerTabsTests` | ❌ Wave 0 |
| TABS-06 | Close Tab selects hidden member first; Move Out lands right/left/cascade, clamped; menu enabled rules; `TabCopy` strings and plurals | unit (engine + mac) | `swift test --filter 'ArrangerTabsTests|TabCopyTests'` | ❌ Wave 0 |
| Safety | Quit plan puts every member at its content rect; Restore All dissolves before rescue; relaunch with a missing member re-forms/dissolves | unit (engine) | `swift test --filter ArrangerTabsTests` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** quick run command (seconds; model/engine are headless).
- **Per wave merge:** `swift test` + `scripts/check-no-appkit.sh`.
- **Phase gate:** full suite green, then one VM batch (`TabGroupIntegrationTests`, plus `QuitRestoreIntegrationTests` and `FocusParkIntegrationTests` as regression), then the 5-item host checklist from 07-UI-SPEC ("User host checklist").

### VM live tests (keep to these five, fixture windows only)
1. Group two fixture windows (engine-driven via AXWindowSystem + Arranger, as existing integration tests do): one shown at the content rect, the other parked as a sliver at content size.
2. Select the hidden tab: it appears at the content rect before the other parks (read both frames).
3. AX `close` and `minimize` commands on fixture windows.
4. Two fixture windows of one app: minimise the selected member; the group stays minimised (Pitfall 6).
5. Quit-restore plan with a group: every member lands at the content rect.
(Strip panel Space/lock behaviour and context menu: one manual VM check during UAT, per UI-SPEC backstops; not automated.)

### Wave 0 Gaps
- [ ] `Tests/TransomModelTests/TabGroupModelTests.swift` — band in `resolve`, floating group edits/validation/decode, leaf move/swap
- [ ] `Tests/TransomEngineTests/ArrangerTabsTests.swift` — dwell, drops, reveal/park, D-08, close/minimise, tear-off, move out, safety
- [ ] `Tests/TransomMacTests/TabCopyTests.swift` — copy, plurals, Debug line
- [ ] `Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift` — five VM tests above
- [ ] `FakeWindowSystem` support for `.close`, `.minimize`, `.park(size:)` (TransomTestSupport)
- [ ] Update existing `ResolveTests` expectations for tab leaves (band + selected-only)

## Security Domain

`security_enforcement: true`, ASVS level 1. [VERIFIED: .planning/config.json `"security_enforcement": true`, `"security_asvs_level": 1`]

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (local) | Commands act only on tracked, non-excluded windows (`ExclusionFilter.admit` runs before every `WindowCommand`, including the new `.close`/`.minimize`) |
| V5 Input Validation | yes | `TransomURL` strict whitelist + rate limit for the 3 new hosts; layout.json: validated decode of floating groups (bounds, membership, NodeID ranges), iterative checks only |
| V6 Cryptography | no | — |
| V7 Errors & Logging | yes | Titles never logged (`.private`); `.fault` names identities only |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Hostile `transom://next-tab` etc. from a web page | Tampering / DoS | Whitelist, parameterless, once-per-second limit, no beep for URL refusals (existing) |
| Crafted layout.json with huge/cyclic groups | DoS / Tampering | Size cap (`World.maxEncodedBytes`), group count ≤ `maxNodes`, membership and duplicate checks in `validate()`, reject on failure (unreadable → rescue mode, existing) |
| Close Group closing unsaved work | Tampering (data loss) | Normal AX close press only (apps prompt), hidden member revealed first, stop at the first window still open after 1 s; no force close |
| Window titles leaking to logs | Information disclosure | `TabStrip.titles` stay in memory/UI; log lines use NodeID and identities |

## Sources

### Primary (HIGH confidence)
- Codebase, read this session: `Sources/TransomModel/{LayoutTree,TreeEdits,Resolve,DropZones,DesktopLayer,World,IDs}.swift`, `Sources/TransomEngine/{Arranger,Arranger+Commands,Arranger+Camera,Planner,ViewPlanner,DragSession,WindowSystem,TabGroupTracker,LayoutFile,LayoutRestore,Recovery,PendingFocus,Command,TransomURL}.swift`, `Sources/TransomMac/{AXWindowSystem,ArrangeController,Displays}.swift`, `Sources/TransomMac/Zoom/CollapsedPanels.swift`, `Sources/TransomMac/Input/{DragFramePoller,Hotkeys}.swift`, `Sources/TransomMac/Zoom/ZoomInput.swift`, `Sources/TransomFixtureApp/main.swift`, `scripts/vm-live-test.sh`, `Package.swift`
- Local SDK verification: `swiftc -typecheck -target arm64-apple-macos14` of `NSAccessibility.Role.tabGroup/.radioButton`, `NSAccessibility.Subrole.tabButtonSubrole`, `NSMenu.popUp(positioning:at:in:)`, `NSPanel` style/collection behaviour, `allowsToolTipsWhenApplicationIsInactive`, `NSAccessibilityCustomAction(name:handler:)`, `kAXCloseButtonAttribute`, `kAXMinimizedAttribute`, `kAXPressAction`; `NSAccessibilityConstants.h` line 595
- `.planning/phases/07-tab-groups/07-CONTEXT.md`, `07-UI-SPEC.md` (approved), `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/config.json`

### Secondary (MEDIUM confidence)
- none

### Tertiary (LOW confidence)
- [Handling Mouse Events (Apple, Cocoa Event Handling Guide)](https://developer.apple.com/library/prerelease/content/documentation/Cocoa/Conceptual/EventOverview/HandlingMouseEvents/HandlingMouseEvents.html) — search surfaced the page but not the passage on drags leaving a view; not relied upon (Pattern 7 avoids it)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependency; every API typechecked locally.
- Architecture: HIGH for seams and gaps (read in code); MEDIUM for the recommended floating-group shape (a design judgement, alternatives listed).
- Pitfalls: HIGH for 1–5, 7, 9, 11–13 (code-verified); MEDIUM/ASSUMED for 6, 8, 10 (macOS behaviour, VM tests listed).

**Research date:** 2026-11-01
**Valid until:** 2026-12-01 (stable codebase; re-check line numbers if Phase 7 plans start after other merges)
