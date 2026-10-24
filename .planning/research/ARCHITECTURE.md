# Architecture Research

**Domain:** macOS zoomable, nested-tiling window manager (no SIP, Accessibility-driven, private SkyLight/MultitouchSupport reads)
**Researched:** 2026-10-23
**Confidence:** MEDIUM overall. Facts about prior art are HIGH where marked "(src)": they come from reading the public MIT source of AeroSpace (`main`), yabai (`master`) and Amethyst (`development`) directly through the GitHub API. Pane-specific designs (camera, min-size solver, desk keying) are my recommendations. No prior art implements them, so they are MEDIUM/LOW and flagged.

> Clean-room note: everything below comes from `PLAN.md`/`PROJECT.md` and public MIT prior art. Type names here are Pane's own. Don't copy the reference app's internal type names into code.

---

## Standard Architecture

### How the prior art is structured (what Pane should learn from)

| WM | Tree / layout model | Threading | Window hiding | Spaces |
|----|--------------------|-----------|---------------|--------|
| **AeroSpace** (Swift) (src) | Mutable **reference** `TreeNode` classes: weak `parent`, `children` array, an MRU stack per node. `Workspace` → root `TilingContainer(orientation, layout: tiles/accordion)` → `Window` leaves. Separate containers per workspace hold floating, native-fullscreen, minimized, hidden-app and popup windows. Weights are **absolute points** per orientation, rebalanced every layout pass (`delta = (length − Σweights)/n`). It normalises after each refresh: single-child containers get flattened and nested containers alternate orientation. | **One dedicated `Thread` + `CFRunLoop` per app (pid).** All `AXUIElement` objects and `AXObserver`s live on that thread (`ThreadGuardedValue`). The main actor sends it cancellable `RunLoopJob`s. Each window's `setFrame` job is cancelled and replaced when a new one arrives, so the latest frame wins. A "refresh session" is a cancellable `Task`, and every new AX/NSWorkspace event cancels the one in flight. | Moves inactive windows to the bottom-left or bottom-right monitor corner, whichever doesn't touch another monitor. macOS still shows about a 1 px sliver. | Ignores native Spaces and emulates workspaces. Recommends turning off "Displays have separate Spaces". |
| **yabai** (C) (src) | One `view` per **Space id**. Each view holds a binary BSP `window_node` tree with a float `ratio` (clamped 0.1–0.9 on resize). `view->uuid` comes from `SLSSpaceCopyName`. A view on a hidden Space is marked **dirty** and only re-laid out when that Space becomes visible. | **A single serial event-loop thread** with a typed event queue (`WINDOW_RESIZED`, `SPACE_CHANGED`, `DISPLAY_*`, `MOUSE_*`, `SYSTEM_WOKE`, …). `AXUIElementSetMessagingTimeout(systemWide, 1.0)`. | Uses native Spaces. Animation captures proxy windows with `SLSHWCaptureWindowList` and transforms them; swapping a proxy in for the real window needs the scripting addition (SIP off). | Reads Spaces through SkyLight (`SLSCopyManagedDisplaySpaces`, `SLSCopyWindowsWithOptionsAndTags`, `SLSWindowQueryWindows`). |
| **Amethyst** (Swift) (src) | Layouts are stateless algorithms over an ordered window list, not a tree. Generic `WindowType`/`ScreenType` protocols with associated types let tests swap in fakes. A `Change` enum carries add/remove/focus/swap/spaceChange/tabChange. | Main thread plus the Silica AX wrapper. | n/a | **`layoutsBySpaceUUID`**, Codable and persisted, keyed by SkyLight Space UUID. Has a heuristic for detecting native tabs. |

**Lessons that carry over:**
1. AeroSpace's per-app AX thread is the proven fix for slow or hung apps blocking the WM. Copy the pattern. Write your own code: check the licence, and keep the clean-room rule in mind.
2. Every prior-art WM compares observed frames against the last frame it applied, within a tolerance (yabai 1.5 pt, AeroSpace 5 px on mouse resize). That is how they tell their own echo, a user drag and an app refusal apart.
3. yabai's dirty-view approach (don't lay out what can't be seen) maps directly onto Pane's rule of only applying AX frames to windows in view.
4. yabai's animation (snapshot proxy, transform, swap) is the closest prior art to Pane's zoom. Without SIP, Pane can't hide the real window under a proxy. **So the overlay has to be opaque, full-screen and above every app window**, rather than per-window proxies.
5. AeroSpace's `FrozenWorld` (a value snapshot of the trees, taken when a window dies) guards against the lock screen making every AX window look closed (src). Pane needs the same guard.

### System Overview (Pane)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Pane.app  (AppKit; MainActor UI + I/O adapters)                              │
│ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────┐ │
│ │ AXBackend  │ │ Spaces     │ │ InputHub   │ │ Snapshot   │ │ Overlays     │ │
│ │ per-app AX │ │ Provider   │ │ CGEventTap │ │ Service    │ │ StageOverlay │ │
│ │ threads,   │ │ (SkyLight  │ │ Multitouch │ │ (SCK +     │ │ DropPreview  │ │
│ │ observers  │ │ dlsym, RO) │ │ hotkeys    │ │ fallback)  │ │ GapHandles   │ │
│ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ │ TabStrip     │ │
│       │ WindowEvent  │ SpaceEvent   │ InputEvent   │ images └──────▲───────┘ │
│ ┌─────┴──────────────┴──────────────┴──────────────┴────────┐       │ Scene   │
│ │ AXWindowSystem  (implements WindowSystem; owns ID mapping)│───────┘         │
│ └────────────────────────────┬──────────────────────────────┘                 │
├──────────────────────────────┼───────────────────────────────────────────────┤
│ PaneEngine  (no AppKit; @MainActor; injected Clock)                           │
│   events in ──▶ ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│                 │ Reconciler   │  │ Sessions     │  │ Camera / Navigator    │ │
│                 │ desired vs   │  │ Drag, Resize │  │ curve, history,       │ │
│                 │ observed     │  │ MarqueeZoom,    │  │ saved views 1–9       │ │
│                 └──────┬───────┘  │ Gesture      │  └──────────┬────────────┘ │
│                        │          └──────┬───────┘             │              │
│                 ┌──────▼─────────────────▼─────────────────────▼────────────┐ │
│                 │ Planner: layout + camera + learned constraints → FramePlan │ │
│                 └──────────────────────────────┬────────────────────────────┘ │
│   commands out ◀── setFrame / park / focus / raise / showScene / hideScene    │
├───────────────────────────────────────────────────────────────────────────────┤
│ PaneModel  (pure Swift values; Codable; Sendable; no Foundation UI types)     │
│   World ─▶ Desk(key) ─▶ LayoutTree (flat NodeID store) + DesktopLayer         │
│   Node = split(axis, children, weights) | panel(WindowRef) | tabs([WindowRef])│
│   resolve(tree, rect, minSizes, gaps) -> [NodeID: Rect]   (pure function)     │
└───────────────────────────────────────────────────────────────────────────────┘
               ▲ persistence: JSON of World + views, written by App, debounced
```

**Dependency direction is strictly downward:** App → Engine → Model. The Model knows nothing about windows, AX or time. The Engine knows nothing about AppKit, AX handles or threads. It only sees `WindowSystem`, `Clock` and value types.

### Component Responsibilities

| Component | Owns | Typical implementation |
|-----------|------|------------------------|
| **PaneModel.LayoutTree** | Nested split/panel/tab structure, weights, invariants | `struct` with `[NodeID: Node]` dictionary + `root`. All mutations are pure functions returning a new tree or throwing a typed error. |
| **PaneModel.Geometry** | Rect resolution with gaps and minimum sizes, hit-testing drop zones | Pure functions over the tree plus a `[WindowRef: Size]` constraints map |
| **PaneModel.World** | All desks, keyed by `DeskKey`; floating Desktop layer per desk; saved views | `struct World: Codable` |
| **PaneEngine.Reconciler** | Diffs desired frames against observed windows. Classifies each AX event as an echo of Pane's write, a user drag, a user resize, or an app refusal. Learns minimum sizes. | State machine on MainActor |
| **PaneEngine.Sessions** | Drag-to-dock, gap resize, rectangle zoom, gesture camera | One active session at a time; `begin/update/end/cancel` |
| **PaneEngine.Camera** | Viewport in desk coordinates, the zoom/pan curve, back/forward history | Value `Camera`, a `CameraTween` sampled by Clock |
| **PaneEngine.Planner** | Turns (tree, camera, constraints) into a `FramePlan`: which windows are *live* (real AX frame), *parked*, or *represented* (snapshot only) | Pure function, fully unit-tested |
| **WindowSystem (protocol)** | The seam. Async queries and fire-and-forget commands; an event stream | `AXWindowSystem` in the app, `FakeWindowSystem` in tests |
| **AXBackend** | `AXUIElement` lifetime, observers, `_AXUIElementGetWindow` ID lookup, messaging timeouts, coalesced setFrame | Per-app thread with CFRunLoop (AeroSpace pattern) |
| **SpacesProvider** | Read-only list of displays → Spaces → window IDs; current Space per display | SkyLight via `dlsym` in **one file**, with a fallback that reports a single Space per display |
| **InputHub** | Mouse (drag, mouse up), hotkeys, ⌥-pinch/pan, Mission Control interception | CGEventTap on its own thread; MultitouchSupport callback thread; everything marshalled to MainActor |
| **SnapshotService** | Latest good image per window; colour + icon placeholder when Screen Recording is denied | `SCScreenshotManager` (macOS 14+), LRU cache keyed by window ID |
| **StageOverlay** | One borderless non-activating panel per display, drawing a CALayer per window under a camera transform | Core Animation `sublayerTransform`; `CADisplayLink` (macOS 14) for custom curves |
| **Small overlays** | Drop preview, gap handles, tab strip | Small `NSPanel`s, positioned from engine `Scene` output |
| **Persistence** | Load/save World and saved views; migrate across display changes | JSON file in Application Support, debounced writes, schema version |

---

## Recommended Project Structure

```
Package.swift                 # SwiftPM: PaneModel, PaneEngine, PaneMac libs + tests
Sources/
├── PaneModel/                # import Foundation only (CGRect via CoreGraphics is fine)
│   ├── IDs.swift             # NodeID, DeskKey, WindowRef
│   ├── Node.swift            # enum Node { split, panel, tabs }
│   ├── LayoutTree.swift      # flat store + invariant checks
│   ├── TreeEdits.swift       # insert(at edge), remove, move, group, reweigh, normalise
│   ├── Resolve.swift         # tree + rect + mins + gaps -> [NodeID: Rect]
│   ├── DropZones.swift       # point -> DropTarget (edge/centre of node or desk)
│   ├── World.swift           # desks, desktop layer, saved views
│   └── Codable+Migration.swift
├── PaneEngine/               # imports PaneModel; no AppKit
│   ├── WindowSystem.swift    # protocol + event/command enums
│   ├── Engine.swift          # @MainActor facade: handle(event)
│   ├── Reconciler.swift
│   ├── Planner.swift         # FramePlan: live / parked / represented
│   ├── Camera/               # Camera, ZoomCurve, Navigator, History
│   ├── Sessions/             # DragSession, ResizeSession, RectZoomSession, GestureSession
│   └── Scene.swift           # value description of what overlays must draw
├── PaneMac/                  # AppKit glue as a library (so parts are testable)
│   ├── AX/                   # AXAppThread, AXWindowHandle, AXObserverBridge
│   ├── Private/              # ONE FILE PER PRIVATE API, each behind a protocol
│   │   ├── AXPrivateWindowID.swift   # _AXUIElementGetWindow
│   │   ├── SkyLight.swift            # SLS* via dlsym
│   │   ├── MultitouchSupport.swift
│   │   └── CoreDock.swift            # symbolic hotkeys / Dock notifications
│   ├── AXWindowSystem.swift
│   ├── Input/                # EventTapThread, HotkeyCenter, TrackpadSource
│   ├── Snapshots/            # SnapshotService, PlaceholderRenderer
│   ├── Overlays/             # StageOverlay, DropPreviewPanel, GapHandlePanel, TabBarOverlay
│   └── Persistence/
├── PaneApp/                  # thin app target: AppDelegate, menu bar, Settings (SwiftUI), URL handler
Tests/
├── PaneModelTests/           # property tests on invariants, golden rect tests
├── PaneEngineTests/          # FakeWindowSystem + TestClock scenario tests
└── PaneTestSupport/          # FakeWindowSystem (refusing windows, slow apps, ID churn)
```

### Structure Rationale

- **The PaneModel/PaneEngine split matches the "no AppKit" constraint** and keeps around 70% of the logic headless-testable. `swift test` runs without TCC permissions.
- **`PaneMac` is a library, separate from the app target**, so private-API adapters and AX code can get integration tests that run under a granted-permission test host, while the app target stays thin. Signing, entitlements, `Info.plist`, Sparkle and `SMAppService` all need a real `.app` bundle, so you need an Xcode project or a generated one (xcodegen, tuist) around the package.
- **`Private/` with one file per API** is a hard constraint from PROJECT.md. Each file exports a protocol plus a `static let isAvailable` checked at startup.

---

## Architectural Patterns

### Pattern 1: Flat, value-typed layout tree (not AeroSpace's reference classes)

**What:** `LayoutTree` is a `struct` holding `nodes: [NodeID: Node]`, `root: NodeID`, and a derived `parent` index rebuilt on mutation or kept in sync by the edit functions. `Node` is an enum. Children are ordered `[NodeID]`. Leaves hold a `WindowRef`, never a live AX handle.

**Why not AeroSpace's design:** AeroSpace's mutable classes work for a WM whose only time dimension is "now". Pane also needs:
- **Tweens and camera targets** that compare *before* and *after* layouts, which means two trees existing at once.
- **Saved views, history and undo** as cheap snapshots.
- **Persistence**: Codable falls out naturally. AeroSpace had to add a separate `FrozenTreeNode` mirror for exactly this (src).
- **Headless tests** that assert on whole-tree equality.
Swift dictionaries and arrays are copy-on-write, so snapshots cost almost nothing until something is edited.

**Trade-offs:** No parent pointers, so parent lookup goes through an index. Edits have to keep invariants by hand. Centralise them in `TreeEdits.swift` and run `validate()` in debug builds after every edit.

**IDs:**
- `NodeID`: a monotonic `UInt64` from the World's counter. It's stable across persistence and readable in logs. Don't use `UUID`: it's 16 bytes, unreadable, and buys nothing here.
- `WindowRef`: a Pane-level identity. In memory it's `{ cgWindowID, pid, bundleID }`. When persisted it also stores `{ bundleID, titleHint, axIdentifier?, creationOrder }` for re-matching after a restart, because CGWindowIDs don't survive app relaunches.
- Camera targets, history entries and saved views refer to a **`NodeID`, with a rect as fallback**, so they survive edits to the layout.

**Weights:** Store **normalised fractions per split, summing to 1**. Don't use AeroSpace-style absolute points or yabai-style binary ratios.
- Fractions don't depend on resolution, which matters because the same tree is drawn at many zoom scales and on displays of different sizes.
- N-ary splits avoid the BSP "ratio of a ratio" problem, and they match docking at an edge, which inserts a sibling rather than nesting a binary node.
- Rules: inserting gives the new child `1/(n+1)` and scales the others by `n/(n+1)`. Removing redistributes the removed share proportionally (i3-style, the most predictable). Gap drags move weight only between the two children on either side of the boundary. Renormalise and clamp to ≥ ε after every edit.
- Normalisation (borrowed from AeroSpace, src): collapse single-child splits into their parent, and merge a child split that has the same axis as its parent. With a fixed axis per split, this second rule plays the role of AeroSpace's "opposite orientation" rule.

**Example:**
```swift
public struct NodeID: Hashable, Codable, Sendable { public let raw: UInt64 }

public enum Axis: String, Codable, Sendable { case horizontal, vertical }

public enum Node: Codable, Sendable, Equatable {
    case split(axis: Axis, children: [NodeID], weights: [Double]) // weights.count == children.count, Σ == 1
    case panel(WindowRef)
    case tabs(windows: [WindowRef], selected: Int)
}

public struct LayoutTree: Codable, Sendable, Equatable {
    public private(set) var root: NodeID?
    public private(set) var nodes: [NodeID: Node]
    // Pure edit API; every function returns a new tree or throws LayoutError
    public func inserting(_ w: WindowRef, at edge: Edge, of target: NodeID, ids: inout IDSource) throws -> LayoutTree
    public func removing(_ w: WindowRef) -> LayoutTree
}
```

### Pattern 2: Min-size-aware resolve (water-filling), solved in points at plan time

**What:** `resolve(tree, in rect: Rect, mins: [WindowRef: Size], gaps:) -> [NodeID: Rect]`. Minimum sizes aggregate bottom-up: along a split's axis, `min = Σ child mins + gaps`; across the axis, `min = max child mins`. Top-down, each split gets length L. Every child starts at `wᵢ·L`. Any child below its minimum is pinned to the minimum, and the remainder is shared among the unpinned children in proportion to their weights. Repeat until stable (at most n passes).

**Why in points at plan time:** A window's minimum is in **screen points**, but at a given zoom a tile's size is `deskRect × cameraScale`. So the Planner resolves the subtree that is in view **in the concrete screen rect**, and the minimums only bind when the camera settles. Stored weights never change. The minimum adjusts geometry, not intent, so zooming out and back in comes back to the same layout.

**Overflow (Σmin > L):** A tiler normally lets windows overlap or squash in this case. **Recommendation for Pane:** put any window whose resolved tile is smaller than its learned minimum into the **represented** state. It stays drawn as a snapshot in the overlay, the real window is parked, and clicking it zooms in until it fits. This keeps the "never overlap" promise in zoomed-out views. (Pane design, MEDIUM. Validate in the camera phase.)

**Learned minimums:** Apps don't reliably expose their minimum size through AX. The Reconciler learns it: after `setFrame(r)`, a read-back or `kAXResized` frame that comes back larger than requested on an axis (beyond 2 pt) records `learnedMin[w] = max(old, observed)`. These are persisted per `bundleID` as a hint, and per window ID while the session runs.

### Pattern 3: Desired-state reconciliation with echo suppression

**What:** The Model plus Planner is the **desired state** for docked windows. AX is the **observed state**. Every observed frame event is classified:

| Classification | Test | Action |
|---|---|---|
| Echo of Pane's own write | `observed ≈ lastApplied[w]` within 2 pt | ignore |
| User drag | left mouse down, window position changed, size unchanged | start or update a `DragSession` (drop preview) |
| User edge resize | mouse down, size changed | `ResizeSession` → convert to a weight change on the nearest split boundary (AeroSpace's `resizeWithMouse` does this, src) |
| App refusal or self-resize | no mouse down, `observed ≠ lastApplied` | learn the minimum (Pattern 2), re-plan once. **Don't loop**: limit re-plans per window to 1 per second |
| Window gone | destroyed notification **or** missing from a full refresh | GC, reflow. Use AeroSpace's lock-screen guard (snapshot the World before GC; restore if the IDs come back) |

Back this up with a **full refresh** (enumerate apps and windows, diff the IDs) triggered by NSWorkspace notifications, mouse-up, Space change, display change and wake. Make it cancellable and latest-wins, as AeroSpace does (src). AeroSpace's source says explicitly that `kAXUIElementDestroyedNotification` is unreliable and runs a refresh on every mouse-up because of it (src).

**setFrame mechanics (src, AeroSpace and yabai):** Coalesce per window, so a new frame cancels the queued one. Write `size → position → size`, because a window moved to a place where its old size doesn't fit gets clamped. Wrap the writes in turning `AXEnhancedUserInterface` off and back on, or some apps animate or ignore the change.

### Pattern 4: Per-app AX threads with timeouts

**What:** One `AXAppThread` per pid. It creates `AXUIElementCreateApplication(pid)`, sets `AXUIElementSetMessagingTimeout(appElement, ~0.5–1.0 s)` (yabai uses 1.0 s on the system-wide element, src), adds `AXObserver` sources to **its own** run loop, and runs `CFRunLoopRun()`. The MainActor talks to it only through async jobs that can be cancelled. Observer callbacks hop to MainActor with `(pid, cgWindowID, notification)` and never pass an `AXUIElement` across threads.

**Why:** AX calls are synchronous IPC. A hung Electron or Java app would otherwise freeze the main thread, and with it the overlay and the event tap. Per-app threads contain the damage to that one app.

**Add on top of AeroSpace:** an **unresponsiveness tracker**. After N timeouts within a window of time, mark the app degraded. The Planner then stops relaying it out and shows a placeholder, until it responds again or the user excludes it.

**Swift 6 note:** AeroSpace's source mentions custom actor executors (SE-0392, macOS 14+) as a possible replacement. Recommendation: start with the plain Thread + RunLoop job queue, which is proven and debuggable, and wrap it in an `actor`-shaped API so the implementation can be swapped later.

### Pattern 5: Snapshot-overlay camera ("the stage")

macOS gives a non-SIP app no way to scale another app's window. So **zoom is an illusion**:

```
 idle (real windows live)
   │ zoom/pan/gesture begins
   ▼
 1. FREEZE   capture/refresh snapshots for windows in the from-view and to-view
             (use cached image if fresher than T; otherwise SCScreenshotManager)
 2. COVER    show StageOverlay on each affected display, drawn at the CURRENT camera
             so frame 0 is pixel-aligned with the real windows (no visible jump)
 3. ANIMATE  drive camera with ZoomCurve on CADisplayLink; only the CALayer
             root transform changes (GPU, 120 Hz-safe). Gestures feed the same camera.
 4. SETTLE   Planner(tree, finalCamera, mins) → FramePlan
             live windows: AX setFrame (coalesced, parallel across app threads)
             off-view windows: park (small, in a corner, ~1 px sliver)
             too-small windows: represented (stay as snapshot)
 5. WAIT     until each live window reports kAXResized AND a fresh snapshot differs,
             or a per-app redraw timeout (start 300–500 ms, adaptive per bundleID)
 6. REVEAL   cross-fade overlay out (≈100–150 ms); live windows now match
```

**Key design points:**
- **Never animate real windows through AX** at frame rate. AX writes are slow, uneven across apps, and get coalesced. Only the overlay animates. The real windows get exactly one write each, at settle.
- **Snapshots of parked windows still work.** Apple's WWDC22 ScreenCaptureKit session says a single-window filter "always includes full window content even when the source window is off-screen or occluded". Output pauses only while the window is minimised. But a parked window is *small*. **Capture a full-size image before parking** and keep it as that window's representative image.
- `CGWindowListCreateImage` is unavailable in the macOS 15 SDK, so use `SCScreenshotManager.captureImage` (async). It's too slow to call per frame, so treat it as a cache filler, never part of the render loop.
- **Placeholder path:** without Screen Recording, draw each tile as the app's colour plus its icon and title. The same layer type should take either content, so the camera code never branches on permission.
- **Camera model:** `Camera { center: Point (desk coords), scale: Double }`, with the viewport derived from display size. Interpolate **log(scale)** linearly and the centre in screen space, i.e. van Wijk & Nuij, *Smooth and Efficient Zooming and Panning* (2003). That keeps both zoom-in and zoom-out perceptually constant-speed. Gestures drive the camera directly and use a critically damped spring on release.
- **Navigation levels come from the tree.** "Step out" sets the target to the parent node's rect, "step in" to the child under the cursor or focus, "everything" to the desk bounds. Rect zoom fits the dragged rect to the display's aspect. History stores `NodeID` targets.
- **Overlay window:** borderless `NSPanel`, `.nonactivatingPanel`, level above normal app windows (start at `.statusBar` and tune so menus still work), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. Use **one per display**, because with "Displays have separate Spaces" on (the default) a window can't span displays. Toggle `ignoresMouseEvents` according to whether the stage is interactive.

### Pattern 6: Engine as event → command core behind `WindowSystem`

**What:** `Engine.handle(_ event: EngineEvent)` updates state and issues `WindowCommand`s through the `WindowSystem` protocol and `Scene` updates through a `StageSink` protocol. Time comes from an injected `Clock`. This lets every phase-3 to phase-8 behaviour run as a scripted scenario test against `FakeWindowSystem`. The fake can simulate refusing windows, slow apps, ID churn and lock-screen blanking.

```swift
public protocol WindowSystem: AnyObject, Sendable {
    var events: AsyncStream<WindowEvent> { get }           // created, destroyed, moved, resized, focused, appLaunched/Terminated, spaceChanged, displaysChanged
    func snapshot() async -> WindowInventory                 // full refresh: displays, spaces, windows+frames
    func setFrame(_ w: WindowRef, _ r: Rect)                 // fire-and-forget, coalesced by impl
    func park(_ w: WindowRef, on display: DisplayID)
    func focus(_ w: WindowRef)
    func setHidden(_ w: WindowRef, _ hidden: Bool)           // tabs: non-selected windows
}
public protocol StageSink: AnyObject { func show(_ s: Scene); func update(camera: Camera); func hide(fade: Duration) }
```

**Trade-off:** It's more ceremony than AeroSpace's direct calls. But AeroSpace's tests only cover commands against an in-memory tree. They can't exercise the AX echo/refusal logic, which is where WMs actually break.

---

## Data Flow

### Event flow (observed → desired → applied)

```
AX observer (app thread) ─┐
NSWorkspace notifications ─┤
SkyLight space change ─────┼──▶ AXWindowSystem ──▶ WindowEvent ──▶ Engine (MainActor)
CGEventTap / Multitouch ───┘    (normalise IDs,                     │
                                 coords top-left)                   ▼
                                                     Reconciler ── classify ──▶ Sessions
                                                         │                         │
                                                         ▼                         ▼
                                                   World (Model edit)      Camera target
                                                         └──────────┬──────────────┘
                                                                    ▼
                                                    Planner → FramePlan + Scene
                                                     │                    │
                                     WindowCommand ◀─┘                    └─▶ StageSink (overlays)
                                          │
                       AXWindowSystem → AXAppThread job (coalesced) → app
                                          │
                               kAXResized echo ──▶ back into Reconciler (suppressed or learned)
```

### State ownership

```
World (value)  ── owned by Engine, mutated only via Model edit functions
    │  (debounced, on change)
    ▼
Persistence (App) ── JSON world.json + views.json
Observed state ── owned by AXWindowSystem (inventory cache); Engine keeps lastApplied[w]
Snapshots ── owned by SnapshotService; Scene refers to window IDs, overlay pulls images
```

### Key Data Flows

1. **Drag-to-dock:** mouse down on a title bar, then `kAXMoved` while the button is held → `DragSession.begin`. Each mouse move goes to `DropZones.hitTest(world, point)` and returns a `DropTarget(node, edge|centre)`. A `Scene.dropPreview(rect)` goes to the preview panel. On mouse up, `World.inserting(...)` (or `grouping` for the centre) → Planner → setFrames, and the other windows reflow.
2. **Close/reflow:** destroyed event or refresh diff → `World.removing(w)` → normalise → Planner → setFrames for the affected subtree only.
3. **Zoom:** hotkey or gesture → `Camera` target → stage sequence (Pattern 5) → settle → FramePlan.
4. **Space switch:** SpacesProvider reports a new active Space for display D → Engine switches the active `Desk` for D → Planner. Desks for hidden Spaces are marked dirty and never laid out while hidden (the yabai pattern, src).
5. **Display change:** `displaysChanged` → match displays by **display UUID** (`CGDisplayCreateUUIDFromDisplayID`), not by `CGDirectDisplayID` or position. Desks for missing displays go **dormant**, not deleted. Their windows move to a "refugee" panel on the main display's desk and go back when the display returns.

---

## Per-display vs per-Space state (open question → recommendation)

**Recommendation: key desks by `DeskKey(displayUUID, spaceID?)`, decided in Phase 1, even though Spaces support arrives in Phase 6.**

- Without SIP, Pane can't reliably move windows between Spaces. yabai needs its scripting addition for that on recent macOS. Windows on other Spaces really are out of reach, so a single tree per display would contain windows Pane can't place. That points to per-Space trees.
- Amethyst (`layoutsBySpaceUUID`, src) and yabai (one view per Space, src) both key by Space. AeroSpace avoids the question by emulating workspaces, which conflicts with Pane's Spaces bar and Overview.
- Fallback: when SkyLight is unavailable or the user turns Spaces awareness off, `spaceID = nil`, meaning one desk per display.
- Persist **Space UUIDs**, not numeric Space IDs, and treat them as best-effort. If a stored UUID no longer exists, its desk becomes dormant. (MEDIUM: UUID stability across reboots and macOS updates is unverified. Test it in Phase 6.)
- Native-fullscreen Spaces are not desks. Treat fullscreen windows as temporarily unmanaged, like AeroSpace's `macosFullscreenWindowsContainer` (src).

---

## Threading summary

| Thread | Runs | Rule |
|---|---|---|
| Main (MainActor) | Engine, Model edits, overlays, CA, persistence scheduling | Never makes a blocking AX call |
| AXAppThread × N | All AX reads/writes/observers for one pid | Messaging timeout per app; jobs cancellable; latest-wins setFrame |
| EventTapThread | CGEventTap run loop | Callback returns in microseconds; re-enable on `kCGEventTapDisabledByTimeout`/`ByUserInput` |
| Multitouch callback | MultitouchSupport frames | Reduce to gesture deltas, hop to MainActor, drop frames if behind |
| SCK async | Snapshot capture | Results delivered to MainActor cache; never blocks rendering |

---

## Persistence

- **What:** `World` (desks, trees, Desktop floating layer frames in desk coordinates), saved views 1–9 (camera target `NodeID` + rect fallback + DeskKey), learned minimum-size hints per bundleID, and settings (settings go separately in `UserDefaults`).
- **Format:** JSON with `schemaVersion`. Write atomically, debounced by about 1 s, and also on quit and sleep.
- **Re-matching after a restart:** if Pane restarts while the apps keep running, CGWindowIDs are still valid, so match exactly. If apps relaunched, match by `bundleID + title + AXIdentifier + order`. Leaves that don't match become **placeholders** that expire after a grace period (e.g. 60 s after launch) and are then removed with normal reflow. This is MEDIUM confidence, since the heuristic hasn't been validated.
- **Lock screen and sleep:** AX goes blank on the lock screen and makes every window look closed (stated in AeroSpace's source). Before removing windows in bulk, keep a frozen World and restore it if the IDs reappear. Also skip GC while the frontmost app is `loginwindow`.

---

## Scaling Considerations

The scale that matters here is windows and displays, not users.

| Scale | Architecture adjustments |
|-------|--------------------------|
| 1–20 windows, 1 display | Everything above works naively; full refresh on every event is fine |
| 20–100 windows, 2–3 displays | Plan only the affected subtree. Snapshot only the windows in the from-view and to-view. Cap concurrent SCK captures (e.g. 4). Coalesce refreshes |
| 100+ windows / many Spaces | Dirty-desk laziness (don't plan hidden Spaces). Downsample snapshots for zoomed-out tiles. LRU-evict snapshot memory (budget e.g. 300 MB) |

### Scaling Priorities

1. **First bottleneck: AX latency at settle.** Many windows across slow apps make the WAIT step long. Fix: parallel writes across app threads, a per-app redraw timeout, and revealing each display independently.
2. **Second bottleneck: snapshot freshness and memory.** Fix: refresh on focus-out and before parking, use the cache everywhere else, downsample by tile size.

---

## Anti-Patterns

### Anti-Pattern 1: Animating real windows with AX during zoom
**What people do:** call `setFrame` at 60 fps to "tween" windows.
**Why it's wrong:** AX writes take milliseconds to hundreds of milliseconds, depend on the app, get coalesced, and some apps snap to grid sizes (terminals). The result is judder and fights with the app.
**Do this instead:** animate the overlay only, and write each real window once, at settle.

### Anti-Pattern 2: Synchronous AX on the main thread
**What people do:** call `AXUIElementCopyAttributeValue` from MainActor because it's simpler.
**Why it's wrong:** one hung app freezes the overlay, the event tap (macOS disables taps that block) and the menu bar.
**Do this instead:** per-app threads plus timeouts (Pattern 4).

### Anti-Pattern 3: Treating AX notifications as reliable
**What people do:** rely only on `kAXUIElementDestroyedNotification` and `kAXWindowCreatedNotification`.
**Why it's wrong:** they're lost or delayed, and AeroSpace's source says so. Apps that open new windows by dragging tabs out make it worse.
**Do this instead:** notifications are hints that schedule a cancellable full refresh diff. Delay registering new windows while the mouse is down (AeroSpace does this, src).

### Anti-Pattern 4: Storing absolute pixels in the model
**What people do:** AeroSpace-style point weights or saved frames.
**Why it's wrong:** Pane's tree is viewed at arbitrary zoom scales and on displays of different sizes, so pixels lose their meaning.
**Do this instead:** fractions in the model, points only in the Planner's output.

### Anti-Pattern 5: Mixing coordinate systems
**What people do:** pass `NSScreen` frames (bottom-left origin) straight into AX (top-left origin, primary display).
**Why it's wrong:** windows land on the wrong display or off by the menu-bar height, and it only shows up on multi-display setups.
**Do this instead:** Model and Engine use a single top-left global coordinate space. Convert only at the AppKit boundary, in one helper with tests.

### Anti-Pattern 6: Private API calls scattered through the code
**Why it's wrong:** one macOS update breaks a symbol and the crash is somewhere unrelated.
**Do this instead:** one file per API, `dlsym` with a nil check, a protocol, and a fallback that degrades features without crashing (e.g. no Spaces bar).

---

## Integration Points

### External services and system APIs

| Service | Integration pattern | Notes |
|---------|---------------------|-------|
| Accessibility (AX) | Per-app thread, observers, timeouts | Permission prompt via `AXIsProcessTrustedWithOptions`. A rebuilt or re-signed binary loses trust, so use a stable signing identity during development |
| `_AXUIElementGetWindow` | Private, single file | Maps an AX element to a CGWindowID. Without it, window identity breaks. Fallback: heuristic matching by frame and title against the CGWindowList |
| SkyLight (SLS*) | `dlsym`, read-only | Spaces per display, windows per Space. Used by yabai (src) |
| ScreenCaptureKit | `SCScreenshotManager` (macOS 14+) | Optional permission. Single-window filters capture off-screen content |
| MultitouchSupport | Private, callback thread | OpenMultitouchSupport (MIT) is the reference wrapper |
| CGEventTap + symbolic hotkeys + CoreDock | Event tap thread; private toggles | Mission Control takeover. Must restore system state on quit or crash, so keep a restore file and run it at the next launch |
| Sparkle 2 | App target only | EdDSA key, signed appcast |
| SMAppService | App target only | Launch at login |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Model ↔ Engine | Direct calls to pure functions on values | Engine is the only owner of `World` |
| Engine ↔ App | `WindowSystem` (commands + `AsyncStream` events), `StageSink` (Scene), `Clock` | Everything crossing is a value: `WindowRef`, `Rect`, `DisplayID` |
| AXWindowSystem ↔ AXAppThread | Cancellable jobs; callbacks carry IDs only | `AXUIElement` never leaves its thread |
| Overlay ↔ SnapshotService | Overlay pulls images by window ID | Scene stays image-free, so it's testable |

---

## Build Order Implications (for the roadmap)

```
Phase 1  PaneModel ───────────────┐ (no deps; decide DeskKey + WindowRef + Node.tabs NOW)
Phase 2  WindowSystem protocol ───┤──▶ FakeWindowSystem (tests)  +  AXWindowSystem/AXBackend
                                  ▼
Phase 3  Engine: Reconciler + Planner(identity camera) + Drag/Resize sessions + small overlays
         ── FIRST USABLE RELEASE; core-value gate: tiling must work with stage disabled ──
                                  ▼
Phase 4  Camera + StageOverlay + SnapshotService + park/represent states  (needs a solid Reconciler)
Phase 5  InputHub gestures → same Camera API (needs Phase 4's camera, not its overlay polish)
Phase 6  SpacesProvider + multi-display desks + Overview (model keying already exists)
Phase 7  Tab groups (Node.tabs exists since P1; adds setHidden + TabBarOverlay)
Phase 8  Saved views + URL commands + persistence hardening (needs NodeID-based camera targets)
Phase 9  Polish/ship
```

- **Model decisions that are expensive to change later and must be made in Phase 1:** flat value tree with `NodeID`, fractional weights, `Node.tabs` case, a `DesktopLayer` per desk, `DeskKey(displayUUID, spaceID?)`, `WindowRef` with persisted match hints, and a schema version. Adding any of these afterwards means a model rewrite and a migration.
- **The `WindowSystem` protocol should be drafted in Phase 1 or early Phase 2**, so engine scenario tests can begin before the AX code is finished.
- **Phase 3 must not depend on the stage.** Plan it with an identity camera (desk = screen, scale 1). That way the core value, "tiling works even if zoom fails", holds by construction.
- **Phase 4 is the riskiest** (redraw waits, snapshot freshness, the represented-state UX). Give it a research spike in planning.
- **Coordinate conversion and display UUID matching** belong in Phase 2, not Phase 6, because the gap handles and drop preview in Phase 3 already need correct multi-display coordinates.

---

## Sources

- AeroSpace source, read directly via the GitHub API (MIT): `Sources/AppBundle/tree/{TreeNode,TilingContainer,Window,MacWindow,MacApp,normalizeContainers}.swift`, `layout/{layoutRecursive,refresh}.swift`, `runLoop.swift`, `util/AxSubscription.swift`, `GlobalObserver.swift`, `mouse/{resizeWithMouse,moveWithMouse}.swift`, `tree/frozen/*`: https://github.com/nikitabobko/AeroSpace (HIGH for the behaviours described; checked against the code)
- AeroSpace guide: https://nikitabobko.github.io/AeroSpace/guide (workspace emulation, normalisation, the separate-Spaces recommendation)
- yabai source (MIT): `src/{view.h,event_loop.h,event_loop.c,window_manager.c,space.c,misc/extern.h}`: https://github.com/koekeishiya/yabai (HIGH; checked against the code)
- Amethyst source (MIT): `Amethyst/Model/{Change,Reliability,Space,Window}.swift`, `Managers/ScreenManager.swift`: https://github.com/ianyh/Amethyst (HIGH; checked against the code)
- WWDC22 "Take ScreenCaptureKit to the next level" (10155), transcript: https://nonstrict.eu/wwdcindex/wwdc2022/10155/ and https://developer.apple.com/videos/play/wwdc2022/10155 (MEDIUM)
- CGWindowListCreateImage → ScreenCaptureKit migration: https://developer.apple.com/forums/thread/740493, https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/ (MEDIUM)
- CADisplayLink on macOS 14: https://developer.apple.com/documentation/quartzcore/cadisplaylink (MEDIUM)
- van Wijk & Nuij, "Smooth and Efficient Zooming and Panning", IEEE InfoVis 2003 (camera-curve basis; from training knowledge, LOW until checked)
- Pane-specific designs (min-size water-filling, the represented state, DeskKey, re-matching heuristics) are original recommendations with no prior-art validation (MEDIUM/LOW)

---
*Architecture research for: macOS zoomable nested-tiling window manager (Pane)*
*Researched: 2026-10-23*
