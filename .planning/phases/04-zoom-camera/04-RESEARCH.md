# Phase 4: Zoom Camera - Research

**Researched:** 2026-10-27
**Domain:** Snapshot-overlay zoom camera for an AX-driven macOS tiling WM (Swift 6, AppKit/Core Animation, ScreenCaptureKit, CGEventTap)
**Confidence:** MEDIUM. The code integration findings are HIGH (read this session). The external API shapes are HIGH (typechecked locally at a macOS 14 target). Performance and memory behaviour is LOW until the spike measures it.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### A. Camera model
- Camera targets are `NodeID`s (ROADMAP scope note). Zooming in to node X resolves X's subtree at full display size. Windows outside the view are parked by moving them to a screen corner at their own size, never shrunk. The home view ("everything") is exactly the Phase 3 layout.
- With zoom on, a drop that doesn't fit at the home view is accepted: the window shows as a collapsed app-colour block (ZOOM-13) until you zoom in. With zoom off, Phase 3's blocked-preview refusal stays.
- The full-screen overlay is shown only while the camera moves and until settle. Collapsed tiles get small persistent click-through panels (the gap-handle pattern) so ZOOM-13's double-click works at rest.
- Animation: about 250 ms ease-out, overlay only. At settle, one AX write per changed, visible window. Reduce Motion: crossfade instead of a zoom.

#### B. Snapshots and Screen Recording
- One-shot `SCScreenshotManager` captures of on-screen windows at zoom start, before parking, at on-stage pixel size. Cached per window ID and refreshed after settle. No `SCStream`, so the system "sharing" indicator never shows.
- Screen Recording is never requested at onboarding. It is asked the first time the user zooms, with a one-line explainer. The fallback is used until it's granted, and there is no re-prompt loop. Revoking it mid-session falls back silently.
- Fallback tile: the app's dominant icon colour fill, the app icon centred, the window title below.
- ScreenCaptureKit is confined to one file, `Sources/TransomMac/Zoom/SnapshotCapture.swift`. `NoScreenCaptureTests` is narrowed to allow only that file, so TILE-10 (tiling never needs Screen Recording) still holds.

#### C. Input and hotkeys
- The ⌃⌥⌘ base stays, using keys free in the Phase 3 table: O = zoom out to everything, `,` / `.` = step out / in, `[` / `]` = back / forward, M = frame focused window, G = frame Desktop. Pan keys for ZOOM-09 are fixed in the UI-SPEC from the remaining free keys. (`=` and `-` are already grow/shrink.)
- ZOOM-08: a minimal "Shortcuts" window with KeyboardShortcuts `Recorder` rows for every hotkey, Phase 3's included. The Phase 9 Settings window absorbs it later.
- ⌘⇧-drag rectangle zoom goes through the existing `InputTap`. The rubber band is drawn in the overlay. Mouse events are consumed only when ⌘⇧ is held at mouse-down. Esc cancels (ZOOM-12).
- With zoom on, double-clicking a window's title bar frames it and toggles back (ZOOM-10), intercepted in the tap. A preference hands double-click back to macOS's own action. Double-clicking the Desktop frames the Desktop (ZOOM-11).
- Clicking a window in a zoomed view zooms in to it and focuses it (ZOOM-6).
- Every navigation action also has a `transom://` URL (ZOOM-09/10/11), through `TransomURL` and the existing `Command` bus.

#### D. Spike, scope and safety (Mode: mvp)
- Plan 1 is a feasibility spike with go/no-go gates, run before anything else is built:
  - settle ≤500 ms for 15 real windows including Electron
  - no visible stale-layout flash
  - a 1-hour soak with WindowServer RSS growth under 200 MB
  - Core Animation holding 100+ snapshot layers smoothly
  - terminal re-wrap, and the overlay's window level versus open menus, checked and reported
- Parking safety: the layout is saved immediately before any window is parked (Phase 3 rule). Parked windows return on quit, after a crash and via Restore All Windows. `kill -9` while zoomed is a UAT item.
- Zoom off: a menu toggle plus a preference. When off, the overlay is never created and ScreenCaptureKit is never touched, giving exactly Phase 3 behaviour (success criterion 5).
- One camera and one back/forward stack per display: 50 entries of `NodeID`s, skipping entries whose node no longer exists. Zoom acts on the display under the pointer.

### Claude's Discretion
- Camera/Navigator internals in TransomEngine (must stay AppKit-free and headless-testable).
- Parking corner and offsets, snapshot cache size and refresh policy, capture concurrency limit (STACK.md suggests 4–6).
- Exact overlay window level, and pan key choice within the UI-SPEC.

### Deferred Ideas (OUT OF SCOPE)
- Remote control of Transom from a phone (Bonjour + command bus). Tabled by the user on 2026-10-27 and recorded in memory; a candidate phase after Phase 8.

**Also binding: the approved `04-UI-SPEC.md`** (status `approved`, 2026-10-27). It fixes hotkeys, URLs, timings (120 ms capture budget, 250 ms move, +50 ms redraw, 1500 ms cap, 120 ms reveal fade), panel properties, copy, log lines and announcements. The planner copies values from it rather than re-deciding them.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ZOOM-01 | Zoom out to see every window on the display at once | `ViewTarget.home` = the Phase 3 plan unchanged (Pattern 1). Stage move protocol (Pattern 4) |
| ZOOM-02 | Step in or out one level of the layout tree | Navigator `stepIn`/`stepOut` over `LayoutTree.parent(of:)` and child rects (Pattern 2) |
| ZOOM-03 | ⌘⇧-drag a rectangle to zoom to the windows it frames | `ZoomTapRules` consume rule plus LCA-of-leaf-centres target (Patterns 2 and 7) |
| ZOOM-04 | Back and forward through previous views | Per-display `CameraHistory`, 50 entries of `(DeskKey, ViewTarget, ancestor path)`, skipping dead nodes (Pattern 2) |
| ZOOM-05 | Live snapshots, or app colour and icon without Screen Recording | `SnapshotCapture.swift` (the only SCK file) plus the fallback tile layer (Patterns 5 and 6) |
| ZOOM-06 | Clicking a window in a zoomed view zooms in and focuses it | Pick-mode click consume rule plus a stage tile click. Focus via the existing `.focus` command after settle |
| ZOOM-07 | Settle ≤500 ms for 15 windows with no stale flash | Two-step move protocol, `SettleTracker` on `frameApplied`, only changed and visible writes, position-only parks (Patterns 4 and 8). Spike gates G1 and G2 |
| ZOOM-08 | Zoom hotkeys are rebindable | 11 new `KeyboardShortcuts.Name`s plus a Shortcuts window with `Recorder` rows and `.shortcutValidation` (verified in the 3.1.0 checkout) |
| ZOOM-09 | Move the view left, right, up or down by hotkey and URL | Navigator `pan(edge)` over home-view node rects at the same depth. 4 new URL hosts |
| ZOOM-10 | Frame the focused window and toggle back, by hotkey, URL or title-bar double-click | `frameWindow` = the leaf of the focused window, toggling through history. Title-bar double-click consumed in the tap from cached frames and `mouseEventClickState` |
| ZOOM-11 | Frame the Desktop and toggle back, by hotkey, URL or double-clicking the Desktop | `ViewTarget.node(.desktop)` (the reserved `NodeID.desktop`). Desktop double-click is not consumed, and the icon check runs async off the tap |
| ZOOM-12 | Esc cancels a ⌘⇧-drag rectangle zoom | Temporary `KeyboardShortcuts.events(for: Shortcut(.escape, …))` streams, live only during the band |
| ZOOM-13 | A tile too small shows as a collapsed app-colour block, and double-click zooms in | Two-pass collapsed resolve (Pattern 3), collapsed windows parked, block panels from a pool (`GapHandlePanels` pattern) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

From `/Users/ken/dev/transomwm/.claude/CLAUDE.md` and `/Users/ken/dev/CLAUDE.md`. Treat these like locked decisions.

- **Platform:** macOS 14+, Apple Silicon and Intel.
- **Stack:** Swift + SwiftPM, `swift-tools-version: 6.2`, Swift 6 language mode. Don't use Swift 6.4-only syntax (`anyAppleOS`, async `defer`). AppKit for overlays. SwiftUI only inside `NSHostingController` (allowed here for the Shortcuts window).
- **Testability:** `TransomModel` and `TransomEngine` must not import AppKit (`scripts/check-no-appkit.sh`, run inside `swift test` by `NoAppKitTests`). The camera/navigator logic belongs in TransomEngine.
- **Private APIs:** each in one file with a fallback, via `dlopen`/`dlsym`. Phase 4 needs **no new private API**. ScreenCaptureKit is public, but by decision it is confined to one file.
- **Only runtime dependency:** KeyboardShortcuts 3.1.0 (pinned `exact`). No new packages.
- **What NOT to use:** `CGWindowListCreateImage`, `SCStream` (decision B), link-time private symbols, App Sandbox, ad-hoc signing, SwiftUI `App`/`Settings`/`MenuBarExtra` shell, AX calls inside the event-tap callback.
- **Logging:** `os.Logger`, never window titles in `.public` (UI-SPEC: titles `.private`). New categories `camera`, `capture`, `zoomInput`.
- **Clean room:** never consult the TrellisWM binary. Loop is GPL-3.0: read for patterns, never copy. AeroSpace is MIT: read only.
- **Core principles:** Chesterton's Fence before removing code. Three real examples before abstracting. No silent fallbacks (`or {}`). For catastrophic or unknown failures, stop (RULE 0).
- **Testing:** 80%+ coverage in critical components. Swift Testing. A `swift test --filter` gate only counts if at least one test ran (SwiftPM exits 0 on an empty match).
- **Live tests:** only in the Tart VM through `scripts/vm-live-test.sh <filter>` with `TRANSOM_LIVE=1`, never on the host. Bounded batches, `caffeinate`, fixture windows only, clean up leftover fixtures.
- **GSD:** file changes go through GSD commands. Never stage `.planning/config.json` or `.planning/state.json`.
- **Ponytail** curbs over-build when code is written. Prefer the smallest change that solves the requirement.

## Summary

Phase 4 is mostly **integration work inside code that already exists**. Phase 3's `Planner` already returns `FramePlan { frames, parks, unfit, desktopRect }`. The `Arranger.planShown()` path already parks windows once each, writes `.save(.now)` before any park, writes only frames that changed by more than 0.5 pt, and suppresses echoes of its own writes. The AX layer already writes per app, on one thread per app, with latest-wins slots and a read-back `frameApplied` per write. The camera therefore reduces to four things:

1. A pure **view planner**: resolve a subtree at display size, park everything outside it, and give collapsed windows a tile rect.
2. A pure **navigator**: step, pan, rect and frame targets, plus a per-display history.
3. A **two-step move protocol**: the engine emits a `cameraMove` with tile start and end rects, the shell animates, then the shell feeds `cameraSettle`. Only then does the engine commit the view and emit writes.
4. A TransomMac **stage** (a Core Animation panel), a **SnapshotCapture** file and **input rules** in the existing tap.

The work is not risky. The risk is **feasibility**: Electron settle latency, stale-flash-free reveal, ScreenCaptureKit and WindowServer memory over hours, and CA throughput with many textured layers. None of these can be settled from documentation; the forum evidence is all anecdotal (LOW). The spike (Plan 1) must measure them with the real AX write path, in the VM, against numeric gates. Two measurement traps found this session matter for how the gates are written:

- **`ps` RSS badly under-reports WindowServer.** Locally, `ps` gave 73,840 KB while `top`'s MEM (physical footprint) gave 1007M. The soak gate must use `top -l 1 -pid <pid> -stats mem`, not RSS.
- **Overlays with `sharingType = .none` are invisible to VNC and `screencapture`.** Phase 3 UAT already saw this with toasts. Claude-driven UAT cannot see the stage unless a Debug-only switch makes it capturable.

Three code facts the planner must act on:

- `Recovery.terminationPlan` and `ArrangeController.restoreForTermination` deliberately leave docked windows alone ("docked windows stay where they are"). With the camera, a docked window can be parked or zoomed, so quit and crash rescue need the **home-view tile** of every docked window.
- `Arranger.rehome` is exempt only for floaters parked by a hidden Desktop. Camera-parked docked windows need the same exemption, or a park can look like a display change.
- `NoScreenCaptureTests` only forbids `import ScreenCaptureKit`, `SCShareableContent` and `CGWindowListCreateImage`. Narrowing it must also add `SCScreenshotManager` and `CGPreflightScreenCaptureAccess`/`CGRequestScreenCaptureAccess`, so the permission calls stay in the one file too.

**Primary recommendation:** Build the spike first as an executable that reuses `AXWindowSystem`'s real write path and the final `SnapshotCapture.swift`. Then add `ViewTarget`, `ViewPlanner` and `Navigator` to TransomEngine with `Arranger.zoomEnabled` defaulting to **false**, so all 999 existing tests keep pinning Phase 3 behaviour. Last, the stage, input and menu shell in `Sources/TransomMac/Zoom/`.

## Architectural Responsibility Map

The tiers are those of a native macOS app, not a web stack.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| View resolution (subtree at display size, parks, collapsed rects) | TransomModel (subtree helper) + TransomEngine (`ViewPlanner`) | — | Pure geometry over `LayoutTree`/`resolve`. Must be headless-testable |
| Navigation targets (step, pan, rect, frame, history) | TransomEngine (`Navigator`, `CameraHistory`) | — | Pure functions of tree + resolution + focus. AppKit-free |
| Move protocol and settle bookkeeping (which writes, when committed) | TransomEngine (`Arranger` camera state, `SettleTracker`) | TransomMac (`ZoomController` timing) | The engine decides what to write. The shell decides when, from animation completion |
| AX writes and parks | TransomMac (`AXAppThread`/`FrameWriter`, existing) | — | Existing per-app threads. Add only a position-only write variant |
| Stage animation (tiles, backdrop, crossfade) | TransomMac (`Zoom/Stage*.swift`, Core Animation) | — | AppKit/QuartzCore only. The render server interpolates |
| Snapshots and the Screen Recording permission | TransomMac (`Zoom/SnapshotCapture.swift` only) | — | Decision B: one SCK file, enforced by a test |
| Fallback tile and app colour | TransomMac (icon sampling) + TransomEngine (pure colour bucketing, testable) | — | `NSRunningApplication.icon` is AppKit. The hue-bucket maths can be pure |
| Input consumption (⌘⇧-drag, pick clicks, title-bar double-click) | TransomMac (`InputTap` callback, published state) | TransomEngine (pure decision rules, LCA target) | The callback must stay at a few µs with no AX. Rules are pure and unit-tested |
| Hotkeys, URLs, menu, Shortcuts window | TransomMac (`Hotkeys`, `CommandMenu`, new `ShortcutsWindowController`) + TransomEngine (`Command`, `TransomURL`) | — | Existing command bus |
| Crash/quit safety for parked windows | TransomEngine (`Recovery`, home-view tiles) | TransomMac (`restoreForTermination`) | Existing SAFE-01/02 paths, extended |

## Standard Stack

### Core (all system frameworks or already present; no new dependency)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ScreenCaptureKit (`SCScreenshotManager`, `SCContentFilter(desktopIndependentWindow:)`, `SCShareableContent`, `SCStreamConfiguration`) | system, macOS 14.0 floor for `SCScreenshotManager` | One-shot window snapshots | The only supported capture API at a 14+ target. `CGWindowListCreateImage` is unavailable at ≥15 [CITED: STACK.md]. All the calls below typecheck at `-target arm64-apple-macos14.0` [VERIFIED: local `swiftc -typecheck`, 2026-10-27] |
| Core Animation (QuartzCore) | system | Stage tiles, backdrop, 250 ms move and crossfade | Render-server interpolation: no per-frame main-thread work. `CALayer.presentation()` gives mid-flight state for retargeting |
| AppKit `NSPanel` | macOS 14 SDK floor | Stage panel per display, collapsed-block panels | The existing overlay pattern (`PreviewPanel`, `GapHandlePanels`, `Toast`) |
| CoreGraphics event tap (existing `InputTap`) | system | ⌘⇧-drag, pick-mode clicks, title-bar double-click | The only way to consume global mouse input. Already running |
| KeyboardShortcuts | **3.1.0** (pinned `exact`, already resolved) | 11 new names, `Recorder` rows, temporary Esc via `events(for: Shortcut)` | Already the hotkey engine. `Recorder`, `.shortcutValidation`, `reset(_:)`, `disable/enable` and `events(for shortcut:)` are in the checkout [VERIFIED: `.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/KeyboardShortcuts.swift:345-372,399-426,786` and `Recorder.swift:111,336`] |
| SwiftUI (inside `NSHostingController`) | system | Shortcuts window `Form` | Allowed by CLAUDE.md for Settings-type windows |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.Logger` | system | Categories `camera`, `capture`, `zoomInput` | Every refusal, settle and capture failure (VNC can't show toasts) |
| `NSWorkspace.shared.desktopImageURL(for:)` | system | Stage backdrop | Loaded once per display and on wallpaper change |
| `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` | system | Crossfade mode | Observe `accessibilityDisplayOptionsDidChangeNotification` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Per-tile `CABasicAnimation` on `position`/`bounds` | One `sublayerTransform` camera (ARCHITECTURE Pattern 5) | A single transform can't express the re-resolve: target rects are not a uniform scale of the home rects, because the aspect changes and minimums re-water-fill. The UI-SPEC already specifies per-tile start→end interpolation |
| CA implicit/explicit animation | `NSView.displayLink` driving frames on main | A display link is needed only for gesture-driven cameras (Phase 5). For a fixed 250 ms move, CA's render-server timing keeps running even if main stalls |
| van Wijk log-scale zoom path (ARCHITECTURE) | Linear rect interpolation with ease-out (UI-SPEC) | van Wijk matters for large scale ratios and gestures. Over 250 ms the difference is invisible. Revisit in Phase 5 |
| `captureSampleBuffer` (IOSurface-backed) | `captureImage` → `CGImage` | Sample buffers may avoid one copy into `layer.contents`. Start with `CGImage` (simplest) and let spike G3/G4 decide |
| Direct Carbon `RegisterEventHotKey` for temporary Esc | `KeyboardShortcuts.events(for: Shortcut(.escape))` | The KeyboardShortcuts stream registers and unregisters dynamically, never persists to UserDefaults, and needs no new Carbon code |

**Installation:** none. No package is added. `Package.swift` is unchanged except possibly a new executable target for the spike harness (see Spike Design).

**Version verification:** KeyboardShortcuts stays at `exact: "3.1.0"` [VERIFIED: `Package.swift`]. No registry lookups are needed.

## Package Legitimacy Audit

This phase installs **no external packages**. KeyboardShortcuts 3.1.0 was vetted and pinned in Phase 3 (`Package.resolved`, T-03-10). ScreenCaptureKit, QuartzCore and AppKit are system frameworks.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none new) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

The spike may install **test apps** inside the VM, such as VS Code for an Electron window. These are not project dependencies, but the planner should gate the download behind a `checkpoint:human-verify` (see Environment Availability).

## Architecture Patterns

### System Architecture Diagram

```
 Trigger (hotkey | menu | transom:// URL | ⌘⇧-drag | pick click | stage click | double-click | collapsed dbl-click)
      │  (InputTap callback: pure ZoomTapRules on published ZoomTapState; no AX)
      ▼
 ArrangeController.dispatch(Command) ──► Arranger.handle(.command)          [TransomEngine, pure]
      │                                     │ Navigator: target = f(view, tree, focus, pointer)
      │                                     │ refuse? ──► .beep / .announce / .info  (UI-SPEC Refusals)
      │                                     ▼
      │                               ViewPlanner.plan(start view) + plan(target view)
      │                                     │  → CameraMove{display, tiles[start,end,kind], from, to}
      ▼                                     ▼  (no window writes yet; pending target recorded)
 ZoomController (TransomMac) ◄── effect .cameraMove
      │ 1. SnapshotCapture.capture(visible ids, sizes, deadline 120 ms, concurrency 4)  [only SCK file]
      │      └─ preflight false / failures → fallback tiles (app colour + icon + title)
      │ 2. Stage panel orders in, tiles exactly over real frames
      │ 3. CA animates 250 ms ease-out (or crossfade) ── retarget? new .cameraMove from presentation()
      │ 4. animation completion ──► Arranger.handle(.cameraSettle(display))
      │                                     │ commit view; planShown(view-aware)
      │                                     │ → .save(.now) (if parks) → .perform([parks…, setFrame…])
      ▼                                     ▼
 AXWindowSystem.perform ──► per-app AXAppThread drain (parallel across apps, serial within)
      │                          └─ FrameWriter (setFrame: size→pos→size; park/unpark: position only)
      ▼
 frameApplied events ──► SettleTracker(pending set) ── all returned +50 ms, or 1500 ms cap
      ▼
 5. Reveal: stage fades out 120 ms; collapsed-block panels fade in; pick mode maybe on
 6. Background refresh capture at new sizes → LRU cache (≤128 MB)
```

### Recommended Project Structure

```
Sources/TransomModel/
└── LayoutTree+Subtree.swift      # subtree(at:) → LayoutTree, ancestors(of:), depth(of:) (pure, validated)
Sources/TransomEngine/
├── Camera.swift                  # ViewTarget, CameraHistory (50), ViewEntry, CameraMove, TileMove
├── ViewPlanner.swift             # plan(desk, view, area, gap, mins, wanted, zoomEnabled) → ViewPlan
├── Navigator.swift               # stepIn/stepOut/pan/rectTarget/frameWindow/frameDesktop + refusal reasons
├── SettleTracker.swift           # pending writes → reveal decision (pure, clock injected)
├── ZoomTapRules.swift            # pure consume/pass decisions for the tap (like GreenButton.shouldSwallow)
├── Arranger+Camera.swift         # camera state, cameraMove/cameraSettle inputs, zoom on/off
├── Command.swift                 # + 11 zoom cases (+ internal zoomTo(NodeID) for rect/pick/click)
└── TransomURL.swift              # + 11 hosts
Sources/TransomMac/Zoom/
├── SnapshotCapture.swift         # THE ONLY ScreenCaptureKit / CGPreflight / CGRequest file
├── ZoomController.swift          # move lifecycle: capture → show → animate → settle → reveal
├── StagePanel.swift              # NSPanel + backdrop + tile layers, retarget, crossfade
├── TileLayer.swift               # snapshot / fallback / collapsed contents
├── AppColor.swift                # icon → app colour (cached per bundle ID)
├── CollapsedPanels.swift         # pooled panels (GapHandlePanels pattern)
├── ZoomInput.swift               # publishes ZoomTapState, rubber band, pick mode, Esc streams
└── ShortcutsWindowController.swift # NSWindow + NSHostingController(Form of Recorder rows)
Sources/transom-zoom-spike/       # (Plan 1) spike harness executable, depends on TransomMac
Tests/TransomEngineTests/         # Camera/ViewPlanner/Navigator/SettleTracker/ZoomTapRules/Arranger+Camera tests
Tests/TransomMacTests/            # NoScreenCaptureTests (narrowed), AppColor, ZoomCopy, hotkey table
Tests/TransomMacIntegrationTests/ # live (VM): ZoomSettleIntegrationTests, ParkRestore while zoomed
```

### Pattern 1: View planning, i.e. resolving a subtree at display size

**What:** For display D showing desk K with view V, the plan is:
- **`V == .home`:** exactly today's `Planner.plan(desk:area:…)`. With zoom on, the collapse pass (Pattern 3) replaces the lost-room float.
- **`V == .node(X)`:** resolve the subtree rooted at X in `display.visibleFrame`. Every window **outside** X goes into `parks`: docked windows, and floaters when X doesn't contain `.desktop`. If X contains the Desktop tile, floaters are planned against X's Desktop rect exactly as `Planner` does today (clamped only when they overlap a tile, wanted frames preserved).

**How:** Add `LayoutTree.subtree(at: NodeID) -> LayoutTree` to TransomModel. It copies the reachable nodes and their windows' states, sets `root = X` and builds through the validating `init(root:nodes:states:)`. The existing `resolve` is then reused unchanged. This beats a `root:` parameter on `resolve`, because `resolve` gathers candidates from **all** `tree.nodes` [VERIFIED: `Sources/TransomModel/Resolve.swift:63-76`: `for (id, node) in tree.nodes {` … `candidates.append((id, window, effective))`], so a root parameter would also need filtering there.

Validation passes for a subtree: the root has `parentAxis nil`, panels and the Desktop may be roots (`LayoutTree.withDesktop()` already makes a Desktop root), and node IDs are unchanged. `Planner.plan` takes a `Desk` (tree + desktop layer), so build a temporary `Desk` with the subtree. When X excludes `.desktop`, the floating layer's windows all become parks.

**Parks reuse the existing path.** `planShown` already does the safe thing [VERIFIED: `Sources/TransomEngine/Arranger.swift:1529-1536,1566-1567`]:
```swift
for window in plan.parks where windows[window.identity]?.isExcluded == false {
    parkedNow.insert(window.identity)
    guard parkRequested.insert(window.identity).inserted else { continue }
    if homeFrames[window.identity] == nil, windows[window.identity]?.isExcluded != true {
        homeFrames[window.identity] = desk.desktop.frame(of: window)
    }
    parks.append(.park(window, displayUUID: display.uuid))
}
…
commands = parks + commands
return faults + (parks.isEmpty ? [] : [.save(.now)]) + (commands.isEmpty ? [] : [.perform(commands)])
```
So camera parks get "saved before parked" (Decision D) for free. Parked floaters get a `homeFrames` entry, because `desk.desktop.frame(of:)` returns their floating frame. Parked **docked** windows get none (the call returns nil); their home is their home-view tile, which can be derived from the tree. See Pattern 9.

**The park geometry already exists** and was live-verified in Phase 3 [VERIFIED: `Sources/TransomEngine/WindowSystem.swift:23-31`]:
```swift
public func parkedFrame(size: Size, among displays: [DisplayInfo]) -> Rect {
    let others = displays.filter { $0.uuid != uuid }.map(\.frame)
    for x in [visibleFrame.maxX - 1, visibleFrame.minX - size.width + 1] {
        let rect = Rect(x: x, y: visibleFrame.maxY - 1, width: size.width, height: size.height)
        if !others.contains(where: rect.overlaps) { return rect }
    }
    let all = others + [frame]
    return Rect(x: (all.map(\.maxX).max() ?? frame.maxX) - 1, y: (all.map(\.maxY).max() ?? frame.maxY) - 1, width: size.width, height: size.height)
}
```
VM UAT confirmed macOS accepted it: "Desktop hidden (TextEdit 567/578 parked at 1023,685)" [VERIFIED: `.planning/phases/03-tiling-mvp/03-UAT.md:63`]. AeroSpace documents the same technique: windows go "outside the visible area of the screen, in the bottom right or left corner", because "macOS doesn't allow to place windows outside the visible area entirely" and a "1 pixel vertical line" remains [CITED: nikitabobko.github.io/AeroSpace/guide]. AeroSpace also moved to hiding windows **on their own monitor**, after hiding on another monitor caused flash-resizes (#149, "Should be fixed since 0.14.0") [CITED: github.com/nikitabobko/AeroSpace/issues/149]. Transom's `parkedFrame` already parks on the window's own display.

**Mismatch to resolve:** the UI-SPEC says "first corner of the display's `frame` … bottom-right, bottom-left, top-right, top-left". The code uses `visibleFrame`, the bottom corners only, then the union's bottom-right. **Recommendation: keep the code** (Chesterton: it is live-verified and avoids neighbouring displays, CR-02). Treat the UI-SPEC row as intent, and note the deviation in the plan.

### Pattern 2: Navigator and history (pure, TransomEngine)

```swift
public enum ViewTarget: Hashable, Sendable { case home; case node(NodeID) }   // .node(.desktop) = Frame Desktop
public struct ViewEntry: Hashable, Sendable { var desk: DeskKey; var target: ViewTarget; var path: [NodeID] } // path = ancestors at entry time
public struct CameraHistory: Sendable { var back: [ViewEntry] = []; var forward: [ViewEntry] = []; static let limit = 50 }
```
- **Home is a case, not a NodeID.** The desk's root ID changes whenever a split is created or normalised away. `NodeID.desktop` is reserved and stable, so `.node(.desktop)` is safe.
- **Key the committed view by `DeskKey`** (display + Space): `views: [DeskKey: ViewTarget]`. Keep the **history per display** (Decision D). Entries carry their `DeskKey`, and Back/Forward skip entries whose desk isn't shown or whose node is gone.
- **Node vanished:** when a view's node is removed (a window closed and its split normalised away), fall back to the deepest still-existing node in `path`, else `.home`. Store `path` because `LayoutTree.parent(of:)` is a linear scan and can't recover a deleted node's parent [VERIFIED: `Sources/TransomModel/LayoutTree.swift:134-140`, "Linear scan; the tree keeps no parent index."].
- **Step Out:** `parent(of: X)`. If the parent is the root, go `.home`.
- **Step In:** the child toward the focused window if it's in view, else toward the tile under the pointer, else the largest child by rect area (UI-SPEC). A single leaf refuses.
- **Pan(edge):** across that edge of the view's rect in the **home-view resolution**, the node at the same depth with the longest shared edge, with ties to the most recently viewed. `Neighbours.neighbour` handles leaves only [VERIFIED: `Sources/TransomModel/Neighbours.swift:21-27`: `if case .split? = tree.node(id) { continue }`], so write a depth-filtered variant rather than reusing it.
- **Rect target:** the LCA of every leaf whose **on-screen** tile centre lies inside the band (collapsed and Desktop tiles included). Pure, using ancestor paths.
- **Frame window / Frame Desktop:** a toggle. If the view already equals the target, go Back; otherwise push and move.

### Pattern 3: Collapsed windows, a two-pass resolve when zoom is on

`resolve` gives unfit windows **no rect** [VERIFIED: `Sources/TransomModel/Resolve.swift:10-11`: `/// Windows that cannot fit without overlapping; they get no rect.` `public var unfit: Set<WindowRef>`]. A collapsed block needs one, because the UI-SPEC puts the block "in its tile". With zoom on:

1. `r1 = resolve(subtree, area, mins)` and `U = r1.unfit`.
2. `r2 = resolve(subtree, area, mins with U → 1×1)`. Each collapsed tile now takes its weighted share, and the others keep their real minimums.
3. Repeat while `r2.unfit` is non-empty, adding those windows to U. This terminates because each pass grows U, which is bounded by the window count. A window still unfit at 1×1 is a "hidden collapsed": parked, with no block.
4. `collapsed = U ∩ {w : rect(w) smaller than min(w) on some axis}`. These windows are **parked**, and their rect in `r2` is the block rect. Every other window uses its `r2` rect.

This changes geometry only when zoom is on: the collapsed tile keeps its share instead of giving it to its siblings, which is what the UI-SPEC means. With zoom off, `planFloatingLostRoom` keeps Phase 3's float [VERIFIED: `Arranger.swift:1617`]. **Arrange All** keeps floating leftovers (UI-SPEC Surface 7). See Open Question 2 for lost room caused by OS facts.

### Pattern 4: The two-step move protocol (engine ↔ shell)

New inputs and effects:
```swift
// ArrangerInput
case zoomEnabled(Bool)
case cameraSettle(displayUUID: String, moveID: UInt64)   // animation finished for that move
// ArrangerEffect
case cameraMove(CameraMove)                               // start/end rects per tile; no writes yet
case cameraRevealed(displayUUID: String)                  // optional: lets the engine start pick mode
```
- A zoom command computes the target, refuses or proceeds, records `pending[display] = (moveID, target)` and emits `.cameraMove`. It does **not** change `views`, so no writes are emitted.
- `.cameraSettle` with the current `moveID` commits `views[key] = target`, pushes history and returns `planShown()`. That yields `.save(.now)` before the parks, then one `.perform` holding the parks plus only the changed `setFrame`s, thanks to the existing `lastRequested` 0.5 pt rule.
- **Retarget:** a new command while a move is pending computes from the *pending* target and emits a new `.cameraMove` with a new `moveID`. The shell starts it from each tile's `presentation()` rect. A stale `.cameraSettle` (old `moveID`) is ignored. "Writes not yet sent are dropped" holds automatically, because no writes existed yet.
- **Tile rects:** the start rect is each window's current tracked frame (`Arranger.windows[id].frame`), and the end rect is the target `ViewPlan` rect. Windows entering or leaving the view use the camera map `S_V(R)`: the affine map taking the view's rect in the **home** resolution onto `display.visibleFrame`. A window leaving gets `end = S_target(homeRect)`, and a window entering gets `start = S_current(homeRect)`. That gives the UI-SPEC's "slide off" and "slide in" with one formula for zoom in, zoom out and pan.
- **Coordinates:** the engine stays in top-left global points (D-09). The stage converts to AppKit bottom-left per display (ARCHITECTURE Anti-Pattern 5).

### Pattern 5: SnapshotCapture (the only ScreenCaptureKit file)

```swift
// Sources/TransomMac/Zoom/SnapshotCapture.swift  (sketch; API names typechecked at macOS 14)
import ScreenCaptureKit
@MainActor final class SnapshotCapture {
    static func isGranted() -> Bool { CGPreflightScreenCaptureAccess() }
    static func request() -> Bool { CGRequestScreenCaptureAccess() }
    private var scWindows: [CGWindowID: SCWindow] = [:]          // refreshed off the critical path
    func refreshShareable() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        scWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
    }
    func capture(_ id: CGWindowID, pixelSize: CGSize) async throws -> CGImage? {
        guard let window = scWindows[id] else { return nil }
        let config = SCStreamConfiguration()
        config.width = Int(pixelSize.width); config.height = Int(pixelSize.height)
        config.scalesToFit = true
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true   // spike G8: does a parked window still capture whole?
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
    }
}
```
- **Critical path:** at move start, use the **cached** `scWindows`. Refresh it after each settle and on `windowCreated`/`windowDestroyed` (debounced). Never fetch `SCShareableContent` inside the 120 ms budget; spike G8 measures its cost.
- **Concurrency 4** with a hard **120 ms** deadline for starting the move (UI-SPEC). Captures that finish late still go into the cache for the next move. Every capture also needs its **own timeout** (about 1 s): reports describe `SCScreenshotManager` completion handlers that never fire, which leaks continuations and hangs callers [CITED: claudeissues.com/issue/45414, LOW]. Count timeouts and errors as failures, and after N failures in a row switch the Debug line to "capture failing".
- **Size:** `max(start, end on-stage size) × backingScaleFactor`, capped at native. Cache is an LRU by decoded bytes (`w·h·4`), 128 MB cap (UI-SPEC), entry dropped on `windowDestroyed`, everything purged when zoom is turned off.
- **Permission:** `CGPreflightScreenCaptureAccess()` at every move start (Surface 2). Preflight can be **stale**: it can stay false until relaunch after a grant, and it is tied to the code-signing identity [CITED: developer.apple.com/forums/thread/819406; github.com/CapSoftware/Cap/issues/1722, LOW]. `CGRequestScreenCaptureAccess()` may do nothing after the user has already answered [CITED: same thread cluster, LOW], which is why the UI-SPEC recovery item also deep-links to System Settings. Debug is already signed with a stable Developer ID (Phase 2 decision), so TCC grants survive rebuilds.
- **Monthly re-consent** on macOS 15+ applies to ScreenCaptureKit apps that don't use the system picker. Only an MDM key (`forceBypassScreenCaptureAlert`) suppresses it [CITED: 9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/; tidbits.com 2024-08-19, MEDIUM]. The silent fallback covers this. Onboarding copy is Phase 9.

### Pattern 6: The stage (Core Animation)

- **Panel** per the UI-SPEC (`.floating`, borderless non-activating, `sharingType = .none`, opaque backdrop). The level numbers, verified locally: `normal 0, floating 3, modalPanel 8, mainMenu 24, statusBar 25, popUpMenu 101, screenSaver 1000`, Dock level `20` [VERIFIED: local AppKit run, macOS 27.0.1, 2026-10-27]. At level 3 the stage sits above app windows and below the Dock (20), the menu bar (24) and open menus (101), which is what the UI-SPEC wants. Spike G5 confirms it on the VM.
- **Tiles:** one container layer per window (`masksToBounds`) with an image sublayer laid out aspect-fill and top-anchored. Animate both `position` and `bounds` with `CABasicAnimation` (`duration 0.25`, `CAMediaTimingFunction(name: .easeOut)`) inside one `CATransaction` whose completion block feeds `.cameraSettle`. Disable implicit actions everywhere else (`CATransaction.setDisableActions(true)`).
- **Retarget:**
```swift
// For each tile layer on a retarget:
let now = layer.presentation()?.frame ?? layer.frame
layer.removeAllAnimations()
CATransaction.begin(); CATransaction.setDisableActions(true); layer.frame = now; CATransaction.commit()
// then animate `now` → new end rect with the same duration/curve
```
- **Reduce Motion:** two tile sets. Start-set opacity goes 1→0 and end-set 0→1 over 250 ms `.easeInEaseOut`.
- **Desktop icons and widgets disappear while the stage is up.** The backdrop is only the wallpaper image, and it must be opaque so the real windows don't show through mid-move. Report this in the spike, and accept it (≤ 250 + settle ms).
- **UAT visibility:** `sharingType = .none` hides the stage from VNC and `screencapture`. Phase 3 found the same with toasts: "toast not visible: sharingType none hides it from VNC" [VERIFIED: `.planning/phases/03-tiling-mvp/03-UAT.md:68`]. Add a **Debug-only** switch (environment variable or Debug-menu item) that sets `.readOnly`, so Claude-driven UAT can screenshot the stage. Leave it compiled out of Release.

### Pattern 7: Input in the tap (published state + pure rules)

The tap callback must stay trivial: "copies four fields and returns the event unchanged: no AX, no file I/O, no logging" [VERIFIED: `Sources/TransomMac/Input/InputTap.swift:39-43`]. The mask is mouse-only [VERIFIED: `InputTap.swift:54-55`: `(1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.flagsChanged.rawValue)`]. Mirror the green-button design:

- **`ZoomTapState`** behind an `OSAllocatedUnfairLock`, swapped whole from main. It holds: `armed` (zoom on, ready, not paused, no settle in progress, not in a fullscreen Space), `bandActive`, `titleBars: [UInt32: CGRect]` (docked windows only, from tracked frames, each band from the window's top edge down to its green button's bottom, using `WindowInfo.greenButton`), `pickTiles: [UInt32: CGRect]?`, `stageUp` and per-display Desktop rects.
- **`ZoomTapRules.decide(type, location, flags, clickState, state, swallowing:) -> Bool`**: a pure function in TransomEngine (or TransomMac with no AppKit), unit-tested exhaustively the way `GreenButton.shouldSwallow` is.
- **⌘⇧ at mouse-down** (with neither ⌃ nor ⌥) and `armed` → consume the down, drags and up. A press under 4 pt of travel is **re-posted** as a down/up pair carrying a tag in `.eventSourceUserData`, and the callback passes any event carrying that tag. `CGEventField.eventSourceUserData`, `.mouseEventClickState`, `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` and `post(tap: .cgSessionEventTap)` typecheck at macOS 14 [VERIFIED: local typecheck].
- **Window under the pointer is 0 at the session tap** (Phase 3 decision 03-11, STATE.md). As the green-button path does, pay for one `CGWindowList.topmostWindow(at:)` read only when the point is inside a published rect and `clickState == 2`.
- **Desktop double-click is not consumed** (UI-SPEC), so the icon-versus-wallpaper check can be **async, off the tap**: an AX hit test at the point on the app thread after the event. If the element is a Finder desktop item, don't frame. That role is [ASSUMED] and must be checked in UAT.
- **Esc during the band:** run `KeyboardShortcuts.events(for: KeyboardShortcuts.Shortcut(.escape, modifiers: m))` for `m ∈ {[], .shift, .command, [.command, .shift]}` while the band is active, and cancel those tasks at mouse-up or cancel. The stream registers on creation and unregisters on termination [VERIFIED: `KeyboardShortcuts.swift:786-808`: `registerIfNeeded(for: shortcut)` … `continuation.onTermination = { … unregisterIfNeeded(for: shortcut) }`]. `Key.escape` exists [VERIFIED: `Key.swift:90` `public static let escape = Self(kVK_Escape)`]. Never register ⌥⌘Esc.

### Pattern 8: Settle latency, and what the existing write path costs

- **Per-app parallel, per-window serial:** one `AXAppThread` per pid, latest-wins slots, drained in window-ID order [VERIFIED: `Sources/TransomMac/AX/AXAppThread.swift:293-301`]. Settle time is roughly the maximum over apps of the sum of that app's per-window write costs.
- **Each `setFrame` costs 6–8 AX round trips:** one read of `AXEnhancedUserInterface` (plus two writes if it is on), then size → position → size, then a position and size read-back [VERIFIED: `Sources/TransomMac/AX/FrameWriter.swift:17-18,28,37-39`: `for (attribute, value) in [(kAXSizeAttribute, sizeValue), (kAXPositionAttribute, originValue), (kAXSizeAttribute, sizeValue)]`].
- **The global messaging timeout is 1 s** [VERIFIED: `Sources/TransomMac/AXWindowSystem.swift:97` `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)`], so one hung app reaches the 1500 ms reveal cap. That is acceptable, because the UI-SPEC reveals at the cap and retries at the next settle.

**Mitigation ladder** (apply in order only if spike G1 fails; each step is small and keeps the existing semantics):

1. **Position-only writes for parks and size-unchanged unparks**, through a new `FrameWriter.move`. This saves 4–5 round trips per parked window, and parks dominate a zoom-in. A park keeps the size by definition.
2. **Read `AXEnhancedUserInterface` once per drain**, not once per window.
3. **Visible-at-target first** within an app's drain (sort key), so the user-visible windows land earliest. Parks still have to finish before reveal, or a not-yet-parked window shows at its old place.
4. **Adaptive redraw delay per bundle ID** (Pitfall 9) if G2 shows content repainting after geometry settles.

### Pattern 9: Crash and quit safety while zoomed

- **Today's quit path skips docked windows** [VERIFIED: `Sources/TransomEngine/Recovery.swift:61-77`: "Docked windows on screen, excluded and never-dock windows, and windows not present are left out." `let home = docked.contains(id) ? nil : homeFrames[id]`; and `Sources/TransomMac/ArrangeController.swift:462-466`: "docked windows stay where they are."]. A camera-parked docked window is `isStranded`, so today it would be **centred** at its own size (`destination(home: nil)`) rather than put back in its tile. A zoomed-in visible window would stay at its zoomed size.
- **Fix:** add `homeTiles: [WindowIdentity: Rect]` to `terminationPlan`. It is computed by the pure `ViewPlanner.plan(view: .home)` for every shown desk, and every docked window not within 2 pt of its home tile goes there. Collapsed-at-home windows have no tile big enough, so they keep the stranded rule (centred).
- **Crash:** the camera always starts at `.home` on launch (UI-SPEC). The re-attach writes "only tiles more than 0.5 pt off" (STATE, 03-07), so parked docked windows come back on the first plan, and parked floaters come back through `homeFrames`. Nothing about the camera is persisted, so `layout.json` keeps schema 1.
- **Crash-loop launch:** it starts paused, and no window command is sent while paused (STATE, 03-10). The planner must check that the recovery rescue of stranded windows still runs for **docked parked** windows in that mode, and passes `homeTiles` too, or a zoomed crash loop could leave windows parked behind a paused Transom. Add a headless test for this.
- **Restore All** (`.restoreAll`, acts while paused) sets every view to `.home` before its existing work. **Turn Off Zoom:** move home first, wait for settle, then set `zoomEnabled = false`. Collapsed windows then float and N1 shows.
- **Rehome exemption:** extend the guard in `rehome` [VERIFIED: `Arranger.swift:817-820`: `!(desk.tree.isDesktopHidden == true && desk.desktop.contains(info.window)),  // parked: off its display on purpose`] to also skip `parkRequested.contains(info.window.identity)`. Apply the same exemption to the docked-move correction path (`lastRequested`/`correct`): a parked docked window's echo is already "own" through `lastApplied`, but a later OS move of the sliver must not be read as a user move.

### Pattern 10: Zoom off means exactly Phase 3

- Default `Arranger.zoomEnabled = false` in the engine, and have production set it from the `zoomEnabled` preference (default on). All 999 existing tests then still assert Phase 3 behaviour with no edits. That is the cheapest guard for success criterion 5.
- In the shell, with zoom off, `ZoomController`, the stage and `SnapshotCapture` are **never instantiated**, and the 11 hotkey names are disabled with `KeyboardShortcuts.disable(_:)`. URL zoom commands are ignored with a log line. An integration-level test can assert that `SnapshotCapture.isGranted` is never called with zoom off (a counter seam).

### Anti-Patterns to Avoid
- **Animating real windows** or writing frames during the 250 ms move (ARCHITECTURE Anti-Pattern 1). The engine must emit no `.perform` between `.cameraMove` and `.cameraSettle` for that display's camera change.
- **Shrinking to park.** It forces reflow, terminal re-wrap and can teach the minimum learner false minimums. Always park by moving at the window's own size.
- **Fetching `SCShareableContent` on the move's critical path.** Keep it cached.
- **Continuations around SCK completion handlers with no timeout.** One hung capture blocks every later move.
- **Calling `CGPreflightScreenCaptureAccess` outside `SnapshotCapture.swift`.** The narrowed test forbids it, so wrap it there.
- **Using `ps` RSS for WindowServer memory.** Use `top`'s MEM (footprint).
- **A per-frame display link** for a fixed-duration move. Let the render server interpolate.
- **Copying Loop's code** (GPL-3.0).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window images | `CGWindowList…Image`, `SCStream` frame grabbing | `SCScreenshotManager.captureImage` + `SCContentFilter(desktopIndependentWindow:)` | One-shot, no sharing indicator, captures occluded windows. Old API unavailable at ≥15 |
| Tween engine | A display-link interpolator on main | `CABasicAnimation` + `presentation()` | Render-server timing, ProMotion-correct, keeps running if main stalls |
| Temporary Esc hotkey | Carbon `RegisterEventHotKey` wrapper, or adding key events to the tap mask | `KeyboardShortcuts.events(for: Shortcut(.escape, …))` | Already a dependency. Dynamic register/unregister. The tap stays mouse-only (T-03-28) |
| Recorder UI | Custom key-capture field | `KeyboardShortcuts.Recorder` + `.shortcutValidation` | Conflict dialogs, pauses hotkeys while recording, persistence under the stable names |
| Parking geometry | New corner logic | Existing `DisplayInfo.parkedFrame(size:among:)` | Live-verified, multi-display safe (CR-02) |
| Change detection on settle | New diffing | Existing `lastRequested` 0.5 pt rule + `parkRequested` | Already prevents write storms (T-03-08) and repeat parks |
| Save-before-park | New persistence | Existing `.save(.now)` before `.perform` in `planShown` | Already the D-16 ordering |
| Quit/crash restore | New restore routine | `Recovery.terminationPlan` + re-attach, extended with `homeTiles` | Keeps one SAFE-01/02 path |

**Key insight:** almost every safety property the camera needs (park once, save first, write only changes, echo suppression, per-app isolation, crash rescue) already exists in the Phase 3 code. The camera fails only where it bypasses that path, so route every camera write through `planShown`.

## Runtime State Inventory

This is not a rename phase. The camera adds runtime state that must not strand windows. That state is covered in Pattern 9 and summarised here so it isn't missed:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `layout.json` (`World`, `homeFrames`, `wantedFrames`, session record): no camera state is persisted, and the camera starts home | None. Keep schema 1 |
| Live service config | None. Verified: no external service | None |
| OS-registered state | TCC Screen Recording grant for `com.eightabyte.transom(.debug)`. KeyboardShortcuts bindings in UserDefaults under `KeyboardShortcuts_<name>` | New names must never be renamed (Pitfall 13). The Restore Defaults button resets only Transom names |
| Secrets/env vars | None | None |
| Build artifacts | A spike executable target (if added) and the VM test bundle staging in `scripts/vm-live-test.sh` (it copies `TransomMacIntegrationTests.xctest` and `TransomFixtureApp`) | If the spike harness must run in the VM, extend the staging copy list or ship it separately |

## Common Pitfalls

### Pitfall 1: Parked docked windows treated as "moved to another display"
**What goes wrong:** the tracker re-assigns `displayUUID` from a park position (`Coordinates.displayUUID` uses the largest intersection, else the nearest display). `rehome` then floats the window onto another desk.
**How to avoid:** apply the `parkRequested` exemption in `rehome` and the move handlers (Pattern 9), and test it with two fake displays.
**Warning signs:** after a zoom-in on a two-display fake, a docked window appears in the other desk's Desktop layer.

### Pitfall 2: Focus moves to a parked window
**What goes wrong:** ⌘-Tab, a Dock click or a Phase 3 focus command activates a window that is parked in a corner. The user sees only a 1 pt sliver.
**How to avoid:** on `windowFocused` for a docked window outside the current view, start a camera move to a view that contains it. The recommendation is the LCA of the current view and that window's leaf; this needs confirmation (Open Question 1).
**Warning signs:** a focused window with a stranded frame.

### Pitfall 3: New windows open while zoomed in
**What goes wrong:** a new window is admitted to the Desktop layer (Phase 3, TILE-07). If the view excludes `.desktop`, the plan parks it at once and it seems to vanish.
**How to avoid:** a new present window outside the view triggers the same rule as Pitfall 2 (Open Question 1). Never park a window the user just created without a move.

### Pitfall 4: Stale-layout flash at reveal
**What goes wrong:** geometry has settled, but an app (Electron, Chrome) still shows its old-size content, or a park hasn't landed yet.
**How to avoid:** reveal only when every write in the batch has returned (parks included), plus 50 ms. Spike G2 measures this geometrically (CG bounds at reveal start) and visually (frame captures). Per-bundle adaptive delay is mitigation step 4.

### Pitfall 5: WindowServer and replayd growth from captures
**What goes wrong:** WindowServer or `replayd` memory grows over hours (AltTab #4255, Loop #745 in PITFALLS.md). More reports this session: orphaned SCK sessions in `replayd` and WindowServer growth over multi-day uptime [CITED: forum.figma.com report 55501, LOW]. None ties the growth to `captureImage` specifically.
**How to avoid:** one-shot captures only, capped concurrency, no refresh storms (refresh only after settle, and only for visible windows), and an LRU cap. Spike G3 measures `top` MEM for both processes over 60 minutes.
**Warning signs:** WindowServer MEM up by more than 200 MB in an hour, or `replayd` above 200 MB.

### Pitfall 6: The soak gate measures the wrong number
**What goes wrong:** `ps -o rss` reports a small number for WindowServer (73,840 KB locally) while the real footprint is far larger (`top` MEM 1007M) [VERIFIED: local run, macOS 27.0.1]. Leaks in IOSurface or GPU memory wouldn't show in RSS.
**How to avoid:** gate on `top -l 1 -pid $(pgrep -x WindowServer) -stats mem`, sampled every 60 s, and record RSS beside it for reference.

### Pitfall 7: The stage is invisible to Claude-driven UAT
**What goes wrong:** `sharingType = .none` hides the stage from VNC and `screencapture`, so UAT screenshots show only the real windows.
**How to avoid:** the Debug-only capturable switch (Pattern 6). Note that a screen recording **without** it shows exactly what the real windows do underneath, which is useful for G2.

### Pitfall 8: Terminal re-wrap and app state on resize
**What goes wrong:** zooming in widens a terminal, so scrollback re-wraps, and zooming out re-wraps again. Some apps lose their scroll position on resize; AeroSpace #149 users saw Microsoft Teams lose its scroll position [CITED: github.com/nikitabobko/AeroSpace/issues/149].
**How to avoid:** this can't be avoided for windows whose size really changes. Report it in the spike (G6). Keep writes to changed windows only, and never resize parked windows.

### Pitfall 9: The tap disables itself, or input lags
**What goes wrong:** heavy work in the callback, such as a CG list read on every event or AX calls.
**How to avoid:** only lock-copy plus pure rules in the callback, and a CG read only inside a published rect on `clickState == 2`. The 2 s watchdog already re-enables the tap.

### Pitfall 10: Lost re-posted ⌘⇧-clicks
**What goes wrong:** a consumed ⌘⇧ press that turns out to be a click (under 4 pt of travel) never reaches the app, which breaks "open link in new tab".
**How to avoid:** re-post a tagged down/up pair at the original point and flags. The tap passes events carrying the tag, so it can't consume its own re-post. UAT: ⌘⇧-click a Safari link.

### Pitfall 11: Collapsed windows and crash loops
**What goes wrong:** a recovery launch rescues collapsed (parked) windows, and the first plan with zoom on parks them again, while the crash-loop mode is paused.
**How to avoid:** on recovery and crash-loop launches, treat collapsed windows like Phase 3 lost room (float them) until the first clean minute. Or simply verify the rescue order with a headless test. This is the planner's choice: add a test either way.

### Pitfall 12: Parks refused by an app
**What goes wrong:** some apps constrain their own frame, so the read-back shows the window still mostly on screen. It then appears beside the zoomed view.
**How to avoid:** check each park's read-back with `Recovery.isStranded(actual)`. A refused park gets a log line ("park refused {bundleID}") and stays a visible overlap. Don't retry in a loop.

## Code Examples

### Subtree helper (TransomModel)
```swift
// Sketch [ASSUMED shape]; uses only LayoutTree members verified in LayoutTree.swift:46-49,62-67
extension LayoutTree {
    /// The subtree rooted at `id`, validated; nil if `id` is not in the tree.
    public func subtree(at id: NodeID) -> LayoutTree? {
        guard nodes[id] != nil else { return nil }
        var kept: [NodeID: Node] = [:], states: [WindowIdentity: WindowState] = [:]
        var stack = [id]
        while let next = stack.popLast(), let node = nodes[next] {
            kept[next] = node
            switch node {
            case let .split(_, children, _): stack.append(contentsOf: children)
            case let .panel(w): states[w.identity] = self.states[w.identity]
            case let .tabs(ws, _): for w in ws { states[w.identity] = self.states[w.identity] }
            case .desktop: break
            }
        }
        return try? LayoutTree(root: id, nodes: kept, states: states)  // validate() runs in init
    }
}
```
*(The `try?` here is deliberate: a subtree of a valid tree is valid. If validation ever fails, that is an invariant bug, so prefer `try` plus a `.fault` effect in the caller over silently returning nil, per the CLAUDE.md silent-fallback rule.)*

### Settle tracker (pure, TransomEngine)
```swift
public struct SettleTracker: Sendable {
    public static let redraw: Duration = .milliseconds(50), cap: Duration = .milliseconds(1500)
    var pending: Set<WindowIdentity>; let started: ContinuousClock.Instant; var lastReturn: ContinuousClock.Instant?
    public mutating func applied(_ id: WindowIdentity, at now: ContinuousClock.Instant) { if pending.remove(id) != nil { lastReturn = now } }
    public func revealAt() -> ContinuousClock.Instant {          // the shell schedules a wake for this
        pending.isEmpty ? min((lastReturn ?? started) + Self.redraw, started + Self.cap) : started + Self.cap
    }
}
```

### Narrowed NoScreenCaptureTests
```swift
// Current forbidden list [VERIFIED: Tests/TransomMacTests/NoScreenCaptureTests.swift:10]:
//   static let forbidden = ["import ScreenCaptureKit", "SCShareableContent", "CGWindowListCreateImage"]
static let forbidden = ["import ScreenCaptureKit", "SCShareableContent", "SCScreenshotManager", "CGWindowListCreateImage",
                        "CGPreflightScreenCaptureAccess", "CGRequestScreenCaptureAccess"]
static let allowed = "Sources/TransomMac/Zoom/SnapshotCapture.swift"
// Fail if any non-allowed file contains a forbidden literal. Assert the allowed file exists. Assert
// CGWindowListCreateImage appears nowhere at all, including the allowed file. Keep `files.count > 10`.
```

### New hotkey names (persistent contract, Pitfall 13)
```swift
// Pattern of existing names [VERIFIED: Sources/TransomMac/Input/Hotkeys.swift:7]:
//   static let dock = Self("dock", initial: .init(.d, modifiers: [.control, .option, .command]))
static let zoomOutAll = Self("zoomOutAll", initial: .init(.o, modifiers: [.control, .option, .command]))
static let panLeft = Self("panLeft", initial: .init(.home, modifiers: [.control, .option, .command]))
// … stepOut(.comma) stepIn(.period) zoomBack(.leftBracket) zoomForward(.rightBracket) panRight(.end)
//   panUp(.pageUp) panDown(.pageDown) frameWindow(.m) frameDesktop(.g): names and keys from UI-SPEC
```
The key names `.comma, .period, .leftBracket, .rightBracket, .pageUp, .pageDown, .home, .end` are verified in `Key.swift:71-85`.

## Spike Design (Plan 1, go/no-go)

**Harness:** a new executable target `transom-zoom-spike` depending on `TransomMac`, like `transom-dump`. Reasons:
1. It measures the **real** write path (`AXWindowSystem.perform` → `AXAppThread` → `FrameWriter`) and its `frameApplied` read-backs.
2. It uses the **final** `SnapshotCapture.swift`, so the spike plan also narrows `NoScreenCaptureTests`.
3. It hosts a prototype `StagePanel` with N synthetic or real tile layers.

Run it in the VM over SSH. The guest's `sshd-keygen-wrapper` already holds Accessibility **and** Screen Recording (memory note, 2026-10-28), so no new TCC click is needed. Output is JSON lines per measurement plus a summary table appended to `04-SPIKE.md`.

| Gate | Setup | Metric | Pass |
|------|-------|--------|------|
| **G1 settle** | 15 windows: about 8 `TransomFixtureApp` windows + 2 Electron (VS Code) + 2 Safari + 2 Terminal + 1 TextEdit. Alternate home ↔ a 3-window node, 20 times each way | t(first write enqueued) → t(last `frameApplied` of the batch), p50/p95/max overall and per bundle | **p95 ≤ 500 ms** both directions |
| **G2 no stale flash** | Same runs | At reveal start (all returned + 50 ms): every target's CG bounds within 2 pt of its read-back, and every parked window `isStranded`. Plus a display recording (screencapture video in the guest) of 10 reveals, inspected frame by frame | 0 geometric mismatches in 40 moves. No recorded frame after reveal start shows a window at its old rect or blank content |
| **G3 soak** | 60 min, one move every 10 s (about 360) with captures of all visible windows and a refresh after settle | WindowServer and `replayd` `top -stats mem` every 60 s. Growth = mean(last 10 min) − mean(first 10 min) | **WindowServer growth < 200 MB**. Report `replayd` (flag if > 200 MB) |
| **G4 CA layers** | Stage with 120 tiles, each a 480×300 px CGImage, animated 250 ms, 20 runs (+ Reduce Motion crossfade) | `NSView.displayLink` callback count and the largest gap during each animation | ≥ 90% of expected frames and no gap above 2 refresh periods. **VM result is indicative only**: confirm on the host if the user allows (Open Question 4) |
| **G5 level vs menus** (report) | Open the Transom status menu, then fire a move (via the harness timer). Also a visible toast | Screenshot with the Debug capturable switch on | Menu and toast stay above the stage |
| **G6 terminal re-wrap** (report) | Terminal.app with long lines and `less`. Zoom in (wider) and back | Screenshots, `tput cols` before and after | Report only |
| **G7 represented-state UX** (report) | One window with a learned minimum larger than its home tile | Collapsed block shown, double-click zooms, settle | Report only |
| **G8 capture costs** (report) | 15 windows | `SCShareableContent` fetch ms. Per-capture ms at 25/50/100% sizes. Whether a **parked** window captures whole content with `ignoreGlobalClipSingleWindow = true` | Report only. Decides whether entering tiles can use fresh captures |

**Go/no-go rules:**
- **G1 fails:** apply mitigation ladder steps 1–3 (Pattern 8) and re-measure. Still failing → stop and escalate to the user with per-bundle numbers. Options: an app-specific "move only, keep size" mode, a relaxed budget, or reveal at the cap.
- **G2 fails:** adaptive per-bundle redraw delay, then re-measure.
- **G3 fails:** drop the refresh-after-settle and capture only on zoom-out. Still failing → ship snapshots **off by default** (fallback tiles). Zoom still works and Screen Recording stays optional.
- **G4 fails:** draw only tiles intersecting the display during the move, downsample images, `shouldRasterize` off. Metal stays deferred.
- **Any gate impossible to measure in the VM** (for example no Electron app can be installed) → report "no observation", never "pass".

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `CGWindowListCreateImage` | `SCScreenshotManager.captureImage` (14.0) | Deprecated 14, unavailable at a ≥15 target | Must use SCK, behind Screen Recording |
| `captureImage(in:)` region capture | 15.2+ only | macOS 15.2 | Not usable at the 14 floor without `#available` (local typecheck error: "'captureImage(in:)' is only available in macOS 15.2 or newer") |
| One-time Screen Recording grant | Monthly re-consent on macOS 15+ for non-picker SCK apps | macOS 15 | Silent fallback required (already decided) |
| Hidden windows parked on a shared corner monitor (AeroSpace < 0.14) | Hidden on their own monitor | AeroSpace 0.14 | Transom already does this |

**Deprecated/outdated:** `CVDisplayLink` (use `NSView.displayLink`, macOS 14) — only relevant in Phase 5.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Focusing or creating a window outside the view should move the camera to the LCA of the view and that window's leaf | Pitfalls 2–3 | UX surprise. Alternatives: go home, or frame the window |
| A2 | With zoom on, lost room from OS facts (a learned minimum grows, the display shrinks) also collapses rather than floats | Pattern 3 | Inconsistent with Phase 3 notices. The UI-SPEC only names drops and keyboard Dock/Move |
| A3 | `ignoreGlobalClipSingleWindow = true` makes a parked (mostly off-display) window capture its whole content | Pattern 5, G8 | Entering tiles fall back to the cached image or the fallback tile (harmless) |
| A4 | Finder desktop icons are distinguishable from bare wallpaper by an AX hit test after the double-click | Pattern 7 | Desktop double-click might frame when opening an icon. UAT backstop exists |
| A5 | Per-AX-call costs are about 2–10 ms native and 10–50 ms Electron, so 15 windows fit in 500 ms after mitigations | Pattern 8 | G1 fails and escalates |
| A6 | Linear rect interpolation with ease-out looks right for 250 ms moves (no van Wijk path needed) | Alternatives | Cosmetic only |
| A7 | `CGImage` contents for about 120 layers stay within the CA budget in the VM | G4 | Mitigations in G4 rules |
| A8 | Keeping `parkedFrame` (visibleFrame bottom corners) over the UI-SPEC's four display-frame corners is acceptable | Pattern 1 | A corner case with displays below both bottom corners, which already falls back to the union corner |
| A9 | A spike executable run over SSH in the VM can show `NSPanel`s in the console session, as fixture apps already do | Spike Design | The harness may instead need to run as a Debug-menu command inside `Transom Debug.app` |

## Open Questions

1. **What does the camera do when a window outside the view gets focus or is created?** (A1)
   - What we know: the UI-SPEC is silent. A parked focused window is effectively invisible.
   - Recommendation: move to the LCA of the current view and the window's leaf (the smallest move that shows it). New floaters while the Desktop is out of view go home. Confirm with the user in plan review.
2. **With zoom on, does lost room from OS facts collapse or float?** (A2)
   - Recommendation: collapse, for consistency ("with zoom on, unfit means collapsed"), and keep Arrange All's float. Otherwise keep Phase 3 floats for OS facts and collapse only on drops and keyboard Dock/Move, as the UI-SPEC literally says. **Default to the literal UI-SPEC** unless the user says otherwise.
3. **Do grow/shrink/rotate/flip/balance still refuse with zoom on?** The UI-SPEC accepts only Dock/Move. Recommendation: keep refusing (literal UI-SPEC).
4. **Hardware-sensitive gates (G1, G4) on the host?** The VM is macOS 15.7.7 with 4 CPUs, 8 GB and a paravirtualized GPU, and it has no Electron app. Host runs violate the live-test rules unless the user allows them. Recommendation: run every gate in the VM. Ask the user for one bounded host run of G1 and G4 on macOS 27 as a confirmation checkpoint.
5. **Parking corner rule:** keep the code's `visibleFrame` bottom corners (A8). Update the UI-SPEC wording at plan time if needed.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / Swift toolchain | build, typecheck | ✓ | Xcode 27.1, Swift 6.4 | — |
| macOS host | dev | ✓ | 27.0.1 (26A434) | — |
| Tart VM `pane-test` | all live tests, spike | ✓ running | macOS 15.7.7 (24G720), 4 CPU, 8 GB | — |
| VM grants (`sshd-keygen-wrapper`: Accessibility + Screen Recording) | spike over SSH | ✓ (memory note 2026-10-28) | — | Grant over VNC (one click) |
| Electron app in the VM (VS Code / Obsidian) | G1 Electron windows | ✗ (guest `/Applications`: Safari, Transom Debug, Transom, Utilities) | — | Download VS Code into the guest. **Checkpoint: user confirms the download** |
| Terminal.app in the VM | G6 | ✓ (system) | — | — |
| `top`, `ps` | G3 memory | ✓ (non-root `top -stats mem` works on the host; assume the same in the guest) | — | — |
| macOS 27 host run for G1/G4 | hardware confirmation | ✓ hardware, but blocked by host rules | — | VM-only results, marked indicative |

**Missing dependencies with no fallback:** none block planning.
**Missing dependencies with fallback:** an Electron app in the VM (install with the user's OK). Without one, G1 is reported as "no Electron observation", not as a pass.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (999 `@Test`s today), live suites gated by `TRANSOM_LIVE=1` (`Tests/TransomMacIntegrationTests/IntegrationSupport.swift:9`) |
| Config file | `Package.swift` (test targets TransomModelTests, TransomEngineTests, TransomMacTests, TransomMacIntegrationTests) |
| Quick run command | `swift test --filter <Suite>` (must show at least one executed test) |
| Full suite command | `swift test` (host, headless). Live: `scripts/vm-live-test.sh <filter>` in the VM only |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ZOOM-01 | Home view equals the Phase 3 plan. Zoom Out from a node emits a `cameraMove`, then settle unparks everything | unit (engine) | `swift test --filter ArrangerCameraTests` | ❌ Wave 0 |
| ZOOM-02 | Step in/out targets, refusals at home and at a leaf | unit | `swift test --filter NavigatorTests` | ❌ Wave 0 |
| ZOOM-03 | LCA of leaf centres in the band; ⌘⇧ consume rule; under-4 pt re-post | unit | `swift test --filter "NavigatorTests\|ZoomTapRulesTests"` | ❌ Wave 0 |
| ZOOM-04 | 50-entry history, dead-node skip, per-display, retarget doesn't double-push | unit | `swift test --filter CameraHistoryTests` | ❌ Wave 0 |
| ZOOM-05 | SCK only in one file; fallback tile chosen when not granted; app-colour bucketing | unit + static | `swift test --filter "NoScreenCaptureTests\|AppColorTests"` | ✅ (narrow) / ❌ |
| ZOOM-05 | Captures work in the VM, and revoking falls back silently | live (VM) + UAT | `scripts/vm-live-test.sh SnapshotCaptureIntegrationTests` | ❌ Wave 0 |
| ZOOM-06 | Pick-mode click consumed only on docked/collapsed tiles; zoom target = that leaf; `.focus` after settle | unit | `swift test --filter "ZoomTapRulesTests\|ArrangerCameraTests"` | ❌ |
| ZOOM-07 | Only changed+visible writes at settle; parks first, after `.save(.now)`; no `.perform` between move and settle; `SettleTracker` reveal timing | unit | `swift test --filter "ArrangerCameraTests\|SettleTrackerTests"` | ❌ |
| ZOOM-07 | ≤500 ms p95 for 15 windows; no stale flash | spike + live (VM) | `transom-zoom-spike settle --runs 20` (G1/G2) and `scripts/vm-live-test.sh ZoomSettleIntegrationTests` | ❌ |
| ZOOM-08 | 44 Recorder rows map to 44 names, names unique and unchanged, duplicate validation | unit | `swift test --filter "HotkeyTableTests\|ShortcutsModelTests"` | ✅ extend / ❌ |
| ZOOM-09 | Pan targets (same depth, longest shared edge, recency tie); 4 URL hosts parse; others rejected | unit | `swift test --filter "NavigatorTests\|TransomURLTests"` | ✅ extend / ❌ |
| ZOOM-10 | Frame window toggles; title-bar double-click consumed only for docked windows with the preference on | unit | `swift test --filter "NavigatorTests\|ZoomTapRulesTests"` | ❌ |
| ZOOM-11 | `.node(.desktop)` view; refused while the Desktop is hidden; Desktop double-click not consumed | unit | same | ❌ |
| ZOOM-12 | Esc streams registered only while the band is active and unregistered after; cancel consumes the rest of the drag | unit (rules) + UAT | `swift test --filter ZoomTapRulesTests` | ❌ |
| ZOOM-13 | Two-pass collapse: rects, parked, hidden-collapsed at 1×1; drop accepted with zoom on and refused with zoom off | unit | `swift test --filter "ViewPlannerTests\|ArrangerCameraTests"` | ❌ |
| SC-4 safety | Quit while zoomed restores home tiles; crash relaunch unparks; crash loop doesn't strand; Restore All goes home | unit + live (VM) + UAT `kill -9` | `swift test --filter "RecoveryTests\|ArrangerCameraTests"`; `scripts/vm-live-test.sh "QuitRestoreIntegrationTests\|RecoveryIntegrationTests"` | ✅ extend |
| SC-5 zoom off | All Phase 3 tests unchanged with the default `zoomEnabled = false`; SCK never touched with zoom off | unit (whole suite) | `swift test` | ✅ |
| Rehome | A parked docked window is never re-homed across displays | unit | `swift test --filter ArrangerCameraTests` | ❌ |

### Sampling Rate
- **Per task commit:** the `swift test --filter` for the touched suite, with an executed count above 0.
- **Per wave merge:** `swift test` (full headless suite).
- **Phase gate:** full suite green. Spike gates G1–G4 recorded as pass with numbers in `04-SPIKE.md`. VM live suites green. UAT items (UI-SPEC backstops: `kill -9` while zoomed, Safari ⌘⇧-click re-post, fn-arrow pan, Desktop icon double-click, Reduce Motion, fallback tile legibility) driven by Claude in the VM with the Debug stage-capturable switch.

### Wave 0 Gaps
- [ ] `Tests/TransomModelTests/SubtreeTests.swift`: `subtree(at:)` validity, states and Desktop root
- [ ] `Tests/TransomEngineTests/ViewPlannerTests.swift`: subtree resolve, parks, two-pass collapse, floaters with and without the Desktop in view
- [ ] `Tests/TransomEngineTests/NavigatorTests.swift`, `CameraHistoryTests.swift`
- [ ] `Tests/TransomEngineTests/SettleTrackerTests.swift`
- [ ] `Tests/TransomEngineTests/ZoomTapRulesTests.swift`
- [ ] `Tests/TransomEngineTests/ArrangerCameraTests.swift`: the move/settle protocol on `FakeWindowSystem` (it already models `park` [VERIFIED: `Sources/TransomTestSupport/FakeWindowSystem.swift:89-90,432-436`])
- [ ] `Tests/TransomMacTests/NoScreenCaptureTests.swift`: narrowed allow-list
- [ ] `Tests/TransomMacTests/AppColorTests.swift`, `ZoomCopyTests.swift`
- [ ] `Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift`, `SnapshotCaptureIntegrationTests.swift` (VM only)
- [ ] `Sources/transom-zoom-spike/` harness and `04-SPIKE.md` results template

## Security Domain

`security_enforcement` is enabled, at ASVS level 1, blocking on high.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | partly | The event tap may consume input only under the narrow published conditions (⌘⇧ at mouse-down, pick mode, docked title-bar double-click). The temporary Esc hotkeys never include ⌥⌘Esc (Force Quit) |
| V5 Input Validation | yes | `TransomURL` strict whitelist extended with exactly 11 hosts. No query, path, port, user or fragment. Existing rate limiter (1/s per command). URL zoom commands while zoom is off are logged and ignored |
| V6 Cryptography | no | — |
| V8 Data Protection | yes | Window snapshots stay **in memory only**: never written to disk, never logged, purged on zoom off and on window close. Titles logged `.private`. The stage and collapsed panels use `sharingType = .none` (the Debug capturable switch is compiled out of Release) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| A malicious web page fires `transom://` zoom URLs to make windows jump around | Tampering / DoS | Whitelist plus 1/s rate limit (existing). No UI on refusal |
| Re-posted synthetic events abused to inject clicks | Spoofing | Re-post only the exact consumed ⌘⇧ press (same point and flags), tagged. Never synthesise from other input |
| Screen contents leaked through the snapshot cache | Information disclosure | Memory-only LRU, purged on zoom off and on window close, no persistence, no logging of image data |
| Swallowed input locks the user out (tap stuck consuming) | DoS | Consume only within one press–release sequence. The watchdog (existing) takes the tap down when access is revoked. Esc and mouse-up always end the band |
| Stranded windows after a crash (availability) | DoS | Save before park (existing), `homeTiles` in the quit/crash rescue, Restore All by menu and URL |

## Sources

### Primary (HIGH confidence)
- Repository code read this session: `Planner.swift`, `Resolve.swift`, `LayoutTree.swift`, `Neighbours.swift`, `WindowSystem.swift`, `Recovery.swift`, `Arranger.swift` (planShown, planFloatingLostRoom, rehome, move and correction handlers), `TransomURL.swift`, `Command.swift`, `AXWindowSystem.swift`, `AXAppThread.swift`, `FrameWriter.swift`, `ArrangeController.swift`, `InputTap.swift`, `Hotkeys.swift`, `NoScreenCaptureTests.swift`, `FakeWindowSystem.swift`, overlay panel files, `Package.swift`, `scripts/vm-live-test.sh`
- KeyboardShortcuts 3.1.0 checkout (`.build/checkouts/KeyboardShortcuts`): `KeyboardShortcuts.swift`, `Key.swift`, `Recorder.swift`, `Shortcut.swift`
- Local verification on macOS 27.0.1 / Xcode 27.1: SCK and event APIs typecheck at a macOS 14 target; `captureImage(in:)` errors (15.2); `NSWindow.Level` raw values; WindowServer `ps` RSS vs `top` MEM; VM `sw_vers` and `/Applications`
- Phase 3 artifacts: `03-RESEARCH.md` Pattern 15, `03-UAT.md` park evidence, `STATE.md` decisions

### Secondary (MEDIUM confidence)
- developer.apple.com doc JSON: `SCScreenshotManager`, `SCContentFilter.init(desktopIndependentWindow:)`, `SCStreamConfiguration`, `SCShareableContent`, `NSWindow.Level`
- AeroSpace guide (nikitabobko.github.io/AeroSpace/guide) and issue #149
- 9to5Mac / TidBITS on monthly Screen Recording re-consent and `forceBypassScreenCaptureAlert`

### Tertiary (LOW confidence; validate in the spike)
- Figma forum report 55501 (WindowServer/replayd growth from orphaned SCK sessions)
- Apple Developer Forums 819406 and Cap #1722 (preflight stale until relaunch or tied to signing identity)
- claudeissues.com 45414 / 41116 (SCScreenshotManager completion handler not firing)
- Apple Developer Forums 845559 (Electron resize stutter under AX)
- Forum reports that `sharingType = .none` is not always honoured by ScreenCaptureKit (irrelevant to single-window filters)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. No new dependency. APIs typechecked at the 14 floor.
- Architecture: HIGH for the integration points (read in code). MEDIUM for the new engine shapes (design recommendations, no prior art in this repo).
- Pitfalls: MEDIUM. Code-derived pitfalls (rehome, quit path, NoScreenCapture scope, `ps` vs `top`, `sharingType` and VNC) are HIGH. Performance and memory are LOW until the spike runs.

**Research date:** 2026-10-27
**Valid until:** 2026-11-26 (30 days. macOS 27.x point releases may change SCK/TCC behaviour, so re-check if one ships before the spike runs)
