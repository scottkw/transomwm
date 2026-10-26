# Phase 3: Tiling MVP - Research

**Researched:** 2026-10-25
**Domain:** Drag-to-dock tiling on macOS: global input (CGEventTap), click-through overlay panels, a layout reconciler over the Phase 2 window system, crash-safe persistence, macOS window-feature conflicts (`com.apple.WindowManager`), hotkeys (KeyboardShortcuts 3.1.0), Developer ID notarisation
**Confidence:** HIGH for the model and engine design, the codebase facts, KeyboardShortcuts 3.1.0 (source read and compiled), SkyLight loading under hardened runtime (probed), the secure-timestamp gap (probed and cited) and the WindowManager key names (read on this Mac). MEDIUM for live-apply of WindowManager writes, event-tap visibility of native title-bar drags, and focus under cooperative activation (prior art and community sources only). LOW for the gap-handle resize cursor while Pane is inactive.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### A. Drag, drop and resize
- Drop zones keep the existing geometry in `DropZones.swift`: edge bands 25% of the tile, the centre 50%, and a 24 pt band at the screen edge. The drop preview and drop acceptance wait for about 150 ms of hover. The preview is the exact frame the window will get, computed as a dry run of `applyDrop` plus `resolve`. It is drawn in a click-through, non-activating panel.
- Releasing over a tile's centre does nothing before Phase 7: no preview, and the drop is a plain move. Tab grouping from the centre arrives in Phase 7.
- Modifiers:
  - Holding ⇧ while dragging places the window freely without docking (TILE-02).
  - Holding ⌘ when releasing over a docked tile swaps the two windows (TILE-11).
  - Modifiers are read during the drag, not at mouse-down.
  - ⌥-drag is left alone because it is Sequoia's tiling modifier. ⌃-click is left alone because it is a right-click.
- A docked window dropped outside every zone snaps back to its tile. You undock by bypass-dragging, with the green button, or with the Float command.
- Docked windows resize two ways: dragging a window's own edge moves its split boundary (`resizeBoundary`), and click-through gap handles appear when the gap is at least 4 pt (TILE-05).

#### B. Hotkeys and commands
- The base modifier is ⌃⌥⌘ for every layout command.
  - This avoids TrellisWM's ⌃⌥ set (clean-room rule) and clashes with Rectangle and Magnet.
  - It also avoids ⌥ typing characters on non-US layouts (Pitfall 16).
  - The STATE.md note "ship a ⌃⌥ fallback" applies to the ⌥1–9 saved views in Phase 8, not to Phase 3.
- Every command gets a default key, because success criteria 6 and 7 say "by hotkey":
  - Arrows move focus to the neighbouring tile.
  - ⇧-arrows move the focused window into the neighbour's tile. On a floating window, ⇧-arrows snap it to that half instead.
  - Letters cover the rest: ⏎ maximise, C centre, Z undo, B balance, R rotate, and so on.
  - The full table is defined in the UI-SPEC.
- No rebinding in Phase 3. Keys are registered through KeyboardShortcuts 3.1.0 with fixed defaults and stable names, so the Phase 4 recorder can reuse them.
- What commands act on:
  - **Direction commands:** the nearest tile across that edge, with ties going to the most recently focused window. Move docks the window on the near edge of that neighbour.
  - **Dock, or the green button, on a floating window:** docks it where a drop at its centre would land.
  - **Arrange All:** splits the largest tile along its longer side, taking windows in screen order.
  - **Finder split (TILE-17):** splits the current tile along its longer side.

#### C. Recovery and conflicts
- **Quit (SAFE-01):** docked windows stay where they are, since they are already on-screen. Parked, hidden and off-screen windows go back to their home frames, clamped on-screen. This runs before the app terminates, with a time limit per app (Pitfall 3).
- **Crash and relaunch (SAFE-02/06):**
  - One JSON file holds the layout, the home frames and a clean-exit flag. It is written atomically and validated, using the `MinimumHintsStore` pattern.
  - It is saved about 0.5 s after each change, and immediately before any window is parked.
  - After a crash, stranded windows are brought on-screen first. Then the layout is re-applied quietly, matching windows by window ID. Windows that can't be matched go to the Desktop.
  - A second crash within about 60 s makes the next launch start paused.
- **Conflict prompt (SAFE-04):**
  - Pane checks for conflicts at launch and whenever the relevant settings change.
  - Each new conflict gets one non-blocking alert with "Turn Off" and "Not Now". A menu line stays visible while any conflict remains.
  - Pane records the original values once and checks that each change took effect. If a change doesn't take, it opens System Settings instead.
  - Originals come back only through a "Restore macOS Window Settings" menu item.
- **While a conflict remains, and while paused:**
  - With Stage Manager on, arranging pauses automatically and the menu says why.
  - Edge tiling and click-wallpaper-to-reveal only show a warning.
  - Pause (TILE-08) keeps tracking but moves nothing and ignores drags. Resume re-applies the layout.

#### D. Desktop tile, layout space and release
- **The Desktop is a real tile in the layout tree.** This is a model change: a Desktop leaf.
  - With nothing docked, it fills the display. Docking beside it shrinks it.
  - Floating windows live inside its bounds, so nothing overlaps (the core promise).
  - Hiding the Desktop parks its windows and gives its space to the docked tiles.
  - It must land before SAFE-06 starts saving layouts, so the saved format includes it from the start.
- **Layouts per display and Space:** there is one layout per display and Space, keyed by the Phase 2 Spaces lookup (02-14). When the lookup is unavailable, there is no Space key. Only the visible Space is arranged, because the tracker keeps windows on other Spaces as `present`.
- **Windows that don't fit (no zoom yet):**
  - A drop that would leave any window without room shows a blocked preview and is refused.
  - A window that loses its room later, for example from a larger learned minimum or a smaller display, floats to the Desktop with a notice.
- **Gaps and menu:**
  - The default gap is 8 pt. A Gaps ▸ submenu offers 0/4/8/12/16/24 and the choice is saved in preferences.
  - The menu is grouped into Arrange, Safety (Pause, Restore All Windows) and Exclusions. The Debug submenu shows only while ⌥ is held.
  - There are no default exclusions, as Phase 2 decided. This overrides the Phase 3 scope note.
- **Release:** a local `scripts/release.sh` does a Release build, `notarytool` submission, stapling and a DMG.
  - It ships 0.3.0 as a GitHub pre-release, uploaded by hand.
  - Its first run proves that a hardened-runtime build that loads SkyLight at runtime can be notarised.
  - CI and the Homebrew cask come in Phase 9.

### Claude's Discretion
- How to recognise Pane's own frame writes (`frameApplied`) so they are never mistaken for user drags.
- Internal structure of the Reconciler or Planner that owns the layout model.
- Exact preview styling, within the UI-SPEC.

### Deferred Ideas (OUT OF SCOPE)
- Tab grouping from the centre zone (Phase 7)
- Collapsed tiles for windows that don't fit (Phase 4, ZOOM-13)
- A hotkey recorder and defaults that suit the keyboard layout (Phase 4/9, Pitfall 16)
- A Secure Input indicator
- Re-opening new windows in a remembered slot, and per-app auto-dock rules (V2-02)
- CI notarisation and the Homebrew cask (Phase 9)
- Multi-display hardening (Phase 6)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TILE-01 | Dragging a window by its title bar to a screen edge or another window's edge shows a drop preview and docks it there on release | Pattern 4 (drag sessions from tap pointer + frame deltas), Pattern 7 (preview panel), Pattern 2 (`applyDrop` dry run over a tree with a Desktop leaf) |
| TILE-02 | Holding a bypass modifier while dragging moves the window freely without docking | Pattern 4: flags read from every `leftMouseDragged` / `flagsChanged` event in the tap; release frame clamped into the Desktop rect |
| TILE-03 | When a docked window closes, its neighbours reflow to fill the space | Existing `LifecycleSync` close path + Pattern 1 Planner re-plan |
| TILE-04 | User can set the gap between windows | `resolve(_:in:mins:gap:)` already takes `gap`; UserDefaults preference with an allow-list |
| TILE-05 | Dragging the gap between two windows resizes both | Pattern 8 (gap handles) + `resizeBoundary`; Pitfall 9 (absent sibling between two taking-part children) |
| TILE-06 | The green button toggles a window between docked and floating on the Desktop | Pattern 5 (green-button hit test inside the tap from cached button rects, no AX) |
| TILE-07 | New windows open floating on the Desktop tile, never auto-split into the layout | Pattern 1: `windowCreated` → `DesktopLayer.add` with the frame clamped into the Desktop rect |
| TILE-08 | User can pause and resume arranging from the menu bar without quitting | Pattern 1 pause-reason set; no `perform` while paused; Resume re-plans |
| TILE-09 | Core commands available as hotkeys and menu items through one command dispatcher | Pattern 9 (one `Command` enum; KeyboardShortcuts names, menu items and `pane://` all call `dispatch`) |
| TILE-10 | Tiling works fully with zoom and Screen Recording turned off | Phase 3 uses no ScreenCaptureKit; overlays use `sharingType = .none`, which needs no permission; UAT with Screen Recording denied |
| TILE-11 | Swap two docked windows' tiles by hotkey or modifier-drag | New `swap` edit (Pattern 2); ⌘ read live in the drag; MRU focus list for `swapPrevious` |
| TILE-12 | Balance, rotate and flip a split | New edits `balance`, `rotate` (subtree transpose), `flip` (Pattern 2) |
| TILE-13 | Move the focused window into a neighbouring tile; grow/shrink its tile | Geometric neighbour lookup over `Resolution.nodeRects` + remove/insert in one edit; `resizeChild` edit (Pattern 2) |
| TILE-14 | Snap floating windows to halves, thirds, quarters, maximise, centre | Pure snap geometry relative to the Desktop leaf's rect (Pattern 2) |
| TILE-15 | Hide and show the Desktop tile by hotkey, menu and URL | `Node.desktop(hidden:)` (Pattern 2); `park` command implemented (Pattern 15); `pane://toggle-desktop` (Pattern 16) |
| TILE-16 | Arrange all / float all | Arrange All loop with a dry run per window; Float All as one edit (Pattern 2) |
| TILE-17 | Split the current tile with a new Finder window by hotkey and URL | Pattern 14: AX press of Finder's ⌘N menu item (no Apple Events, no Automation prompt) + a 2 s expectation for its `windowCreated` |
| TILE-18 | "Don't Arrange" for the frontmost app in one click | Existing `ExclusionStore.toggle` + float that app's docked windows; ⌃⌥⌘E hotkey |
| TILE-19 | ⌥-clicking the green button performs the normal macOS zoom | Pattern 5: the tap passes any mouse-down with ⌥ held straight through |
| TILE-20 | A minimised docked window lets neighbours take its space and returns to the same tile | Already modelled: minimised → `.absent`, slot kept (`Resolve.swift:22-24`); Planner re-plans on state change |
| WIN-07 | A fullscreen window keeps its tile reserved and returns to it | `.fullscreen` keeps the slot (`Resolve.swift:22-24`); no desk is created for a fullscreen Space (Pattern 12) |
| SAFE-01 | On quit, every window Pane moved returns to a sensible on-screen frame | Pattern 11: `applicationShouldTerminate` → `.terminateLater`; bounded synchronous termination writes per app thread; SIGTERM handler |
| SAFE-02 | After a crash or force-quit, the next launch restores stranded windows on-screen | Pattern 10: `layout.json` clean-exit flag, stranded-window rule, crash-loop rule |
| SAFE-03 | "Restore all windows" from the menu and by URL | Pattern 10 restore routine + `pane://restore` (Pattern 16); runs even while paused |
| SAFE-04 | Detect edge tiling, Stage Manager, click-wallpaper; explain; offer to turn off; restore originals | Pattern 13: CFPreferences on `com.apple.WindowManager` (keys read on this Mac), poll, originals incl. "absent", read-back, deep link |
| SAFE-06 | Quit and relaunch while apps keep running restores each display's layout | Pattern 10: persisted `World` + re-attach by unchanged `WindowIdentity`; synthetic IDs never matched (02-11) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

From `/Users/ken/dev/panewm/.claude/CLAUDE.md` and `/Users/ken/dev/CLAUDE.md`. Treat these like locked decisions.

- **Platform:** macOS 14+, Apple Silicon and Intel. The existing Release build is already universal (`lipo -archs` → `x86_64 arm64`, checked this session).
- **Stack:** Swift + SwiftPM, `swift-tools-version: 6.2`, Swift 6 language mode. Don't use Swift 6.4-only syntax. AppKit for overlays. SwiftUI only inside `NSHostingView`/`NSHostingController` (the UI-SPEC allows it for toast content).
- **Testability:** `PaneModel` and `PaneEngine` must not import AppKit. `scripts/check-no-appkit.sh` and `NoAppKitTests` enforce this.
- **Private APIs:** each one isolated in one file with a fallback, reached through `dlopen` + `dlsym`, never linked. The new `SLSManagedDisplayGetCurrentSpace` belongs in `Sources/PanePrivate/SkyLightSpaces.swift` behind `Capability.spaces`.
- **Legal:** clean room. Work from specs and public prior art only. Loop is GPL-3.0: read it for patterns, never copy it.
- **Only runtime dependency:** KeyboardShortcuts 3.1.0. No Sparkle. swift-collections only if a real need appears.
- **What NOT to use:** `CGWindowListCreateImage`, link-time private symbols, App Sandbox, ad-hoc signing, SwiftUI `App`/`Settings`/`MenuBarExtra` shell, AX calls inside the event-tap callback, CocoaPods/Carthage.
- **Logging:** `os.Logger` with per-subsystem categories (`tap`, `arrange`, `persist`, `conflicts`). Never log window titles.
- **Persistence:** `Codable` + JSON under `~/Library/Application Support/Pane/`. Preferences in `UserDefaults`.
- **Formatting:** `swift format lint --strict -r Sources Tests`.
- **Process:** test-first (a RED commit before each behaviour change, CONTEXT "Established Patterns"). 80%+ coverage in critical components. Start work through a GSD command.
- **Principles:** Chesterton's Fence before deleting anything. No silent fallbacks (`?? {}` turning a hard failure into silent corruption): log and set aside, as `MinimumHintsStore` does. Ponytail mode applies to the executor: the smallest change that fully solves each task.
- **Safety:** RULE 0. On a catastrophic or unknown failure, stop and report. Never `kill node`.

## Summary

Phase 3 turns Phase 2's window system into a tiling manager. Most of the needed parts already exist and are tested: the layout tree, `resolve` with minimum sizes and an `unfit` set, drop-zone hit-testing and `applyDrop`, 50-level undo, a latest-wins frame-write pipeline with read-back, two-source close detection, Spaces lookup, and exclusion enforcement in `perform`. What's missing is **an owner for the layout** and **the inputs that drive it**: an event tap for the pointer, hotkeys, overlay panels, persistence, and the conflict checker. The cleanest structure is the one Phase 2 already uses. A pure, AppKit-free `Arranger` state machine in PaneEngine takes events, pointer samples and commands, and returns `WindowCommand`s plus UI effects. A thin MainActor shell in PaneMac connects it to `AXWindowSystem`, the tap, panels, menu and store. That makes almost every requirement testable headless against `FakeWindowSystem`.

Three findings change the plan. **First**, the current Release build has no secure timestamp. `codesign -dvv` prints `Signed Time=`, and Apple documents that as "the binary doesn't have a secure timestamp", which notarisation rejects. `release.sh` must sign with `--timestamp`. Library validation is *not* a problem: a Developer ID, hardened-runtime binary built this session `dlopen`ed SkyLight and resolved every Space symbol without `disable-library-validation`. **Second**, the UI-SPEC's gap-handle tracking options combine `.cursorUpdate` with `.activeAlways`, and the SDK header says `NSTrackingActiveAlways` is "Not supported for NSTrackingCursorUpdate". The resize cursor while Pane is inactive is unproven. **Third**, `system.events` has exactly one reader today (`StatusItemController`). The Arranger must become that one reader and fan out, or events will be split between two consumers.

For drag detection, use one **active** session event tap (`.defaultTap`) on its own thread, masked to left mouse down/dragged/up and `flagsChanged`. It needs only the Accessibility grant Pane already has, while a listen-only tap would prompt for Input Monitoring. The callback copies the location, flags and `mouseEventWindowUnderMousePointer` (a public CGEvent field since 10.7) into an `AsyncStream` and returns. It swallows a mouse-down only when the point is inside a cached green-button rect and ⌥ is not held. A drag session starts only when the window under the mouse-down moves while the button is held, the pointer has travelled at least 3 pt, and the move is not an echo of Pane's own write. A cheap CG-bounds poll of that one window makes this fast, with no AX involved.

**Primary recommendation:** build the Desktop leaf and the new tree edits first (PaneModel, test-first), then the pure `Arranger` against `FakeWindowSystem`, then the AppKit shell (tap, panels, hotkeys, menu, store, conflicts), and finish with `release.sh` using `--timestamp`.

## Architectural Responsibility Map

The "tiers" for a native agent app are its targets.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Desktop leaf, swap/balance/rotate/flip/move/grow edits, neighbour lookup, snap geometry | PaneModel | — | Pure value edits with all-or-nothing commit and validation; headless tests |
| Non-undo World paths (rekey, floating frame facts, auto-float of unfit) | PaneModel | PaneEngine (caller) | Must keep `World` and `UndoHistory` consistent; only PaneModel can touch `history` internals |
| Layout ownership: event → plan → commands, drag/resize sessions, pause, MRU, echo suppression | PaneEngine (`Arranger`, pure struct) | PaneMac shell | Same pattern as `WindowTracker`: pure core, shared by fake and live |
| Command dispatcher (`Command` enum, enablement rules) | PaneEngine | PaneMac (menu/hotkey/URL adapters) | One route for menu, hotkey and URL (TILE-09) |
| Crash-loop and recovery decisions, conflict policy (what to change, what to restore) | PaneEngine (pure) | PaneMac (I/O) | Decision logic is testable without files or defaults |
| Event tap, CG bounds poll, green-button rect cache | PaneMac (`InputTap`, own thread) | PanePrivate — none | Public CoreGraphics API; must never block |
| Overlay panels (preview, gap handles, toast), status menu, alerts | PaneMac (AppKit, MainActor) | — | AppKit-only surfaces |
| Hotkeys | PaneMac (KeyboardShortcuts) | PaneEngine (names → `Command`) | Carbon registration is AppKit-side |
| `park` / `focus` / `raise` / Finder menu press / termination writes | PaneMac (`AXAppThread`) | — | All AX IPC stays on the app's thread |
| Current Space per display | PanePrivate (`SkyLightSpaces`) | PaneMac (`Displays`) | Private API, one file, nil fallback |
| `layout.json` store, `com.apple.WindowManager` prefs I/O | PaneMac | PaneEngine (validated values) | File and CFPreferences I/O |
| Release build, notarise, staple, DMG | `scripts/release.sh` + `xcode/project.yml` | — | Local tooling (CI is Phase 9) |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| KeyboardShortcuts (sindresorhus, MIT) | 3.1.0 (tag commit `772133d9dbe8`, released 2026-09-11) | Global hotkeys with stable `Name`s and fixed defaults; `NSMenuItem.setShortcut(for:)` | The only runtime dependency allowed by STACK.md. Its `Package.swift` declares `swift-tools-version:6.2` and `.defaultIsolation(MainActor.self)`. A scratch package with PaneMac's exact settings compiled and ran it this session [VERIFIED: GitHub source + local build] |
| CoreGraphics event taps (`CGEvent.tapCreate`) | system | Pointer down/drag/up, live modifiers, green-button swallow | The only way to observe *and consume* global input [CITED: STACK.md; VERIFIED: compile + `tapIsEnabled` true in scratch run] |
| AppKit `NSPanel` / Core Animation `CAShapeLayer` | macOS 14 SDK floor | Preview, gap handles, toast | UI-SPEC platform rule |
| CFPreferences (`CFPreferencesCopyAppValue` / `SetAppValue` / `AppSynchronize`) | system | Read and write `com.apple.WindowManager` | Public API. Reads, and a same-value write with read-back, worked from a Developer ID + hardened-runtime binary this session [VERIFIED: local probe] |
| ApplicationServices AX | system | `park`, `focus`, `raise`, Finder menu press, button frames | Already the Phase 2 control path |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `os.Logger` | system | Categories `tap`, `arrange`, `persist`, `conflicts` | Always |
| `NSAccessibility.post(element:notification:userInfo:)` | system | Toast and refusal announcements (UI-SPEC) | Every toast and refusal |
| `xcrun notarytool` 1.1.3 / `xcrun stapler` | Xcode 27.1 | Notarise and staple | `release.sh` [VERIFIED: local `--version`] |
| create-dmg | 1.3.0 (2026-07-02, MIT) | DMG with `--codesign`, `--notarize <profile>`, `--skip-jenkins` | `release.sh`. Not installed: `brew install create-dmg` (bottle 1.3.0). Fallback is `hdiutil create` [VERIFIED: GitHub README v1.3.0; `brew info`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| One active tap (`.defaultTap`) | Listen-only tap or `NSEvent.addGlobalMonitorForEvents` for drags + an active tap for the green button | A listen-only tap prompts for Input Monitoring (forum reports). A global monitor works (Rectangle uses one) but can't swallow the green-button click, so an active tap is needed anyway. One tap is simpler [CITED: Rectangle `EventMonitor.swift`; MEDIUM forum] |
| AX menu press for Finder ⌘N | AppleScript `make new Finder window` | Apple Events need `com.apple.security.automation.apple-events` under hardened runtime, plus `NSAppleEventsUsageDescription` and an Automation consent prompt. AX is already granted [ASSUMED for the entitlement requirement] |
| AX menu press | `NSWorkspace.shared.open(homeURL)` | Finder may bring an existing window for that folder forward instead of opening a new one. Keep it as the fallback only when Finder has no windows [ASSUMED] |
| CG bounds poll during a press | AX `kAXWindowMovedNotification` only | AX moved hints go through refresh scheduling and arrive late or coalesced (Pitfall 19). The CG poll is WindowServer IPC, safe on main, one window only |
| `runModal()` conflict alert | Modeless `alert.window` | The UI-SPEC allows either with a UAT backstop. The modeless form has no run-loop-mode risk |

**Installation:**
```swift
// Package.swift: add to `dependencies:` and to the PaneMac target only
.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
// PaneMac: dependencies: ["PaneEngine", "PanePrivate", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")]
```
```bash
brew install create-dmg   # release.sh only; checkpoint (local tool install)
```

**Version verification:** `gh api repos/sindresorhus/KeyboardShortcuts/releases/latest` → `3.1.0 2026-09-11T23:42:00Z`. `Package.resolved` in the scratch build pinned revision `772133d9dbe800fdac0473226822994c5c162c58`, which equals the tag's commit. `gh api repos/create-dmg/create-dmg/releases/latest` → `v1.3.0 2026-07-02`.

## Package Legitimacy Audit

The `gsd-tools package-legitimacy` seam supports only `npm|pypi|crates` (it returned a usage error for `swiftpm`). The SwiftPM dependency was checked against its GitHub source instead.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| KeyboardShortcuts | SwiftPM (GitHub) | 6.5 yrs (repo created 2020-05-07) | n/a (2,724 stars; used by Amethyst per STACK.md) | github.com/sindresorhus/KeyboardShortcuts (MIT, not archived) | OK (manual: source-only target, no `binaryTarget`, no plugins; tag commit = resolved revision) | Approved. Pin `exact: "3.1.0"` |
| create-dmg | Homebrew (dev tool, not shipped) | repo active, v1.3.0 2026-07-02 | n/a (2,659 stars) | github.com/create-dmg/create-dmg (MIT) | OK (manual) | Approved as a local tool. Install is a checkpoint |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
             ┌──────────────── PaneMac (MainActor shell) ─────────────────────────────────────┐
 mouse ─────▶│ InputTap thread (CFRunLoop)                                                     │
 (session    │  callback: copy {type, location, flags, windowUnderPointer} ─▶ AsyncStream      │
  tap)       │  green-button rect cache (lock) ─▶ swallow down/up unless ⌥                    │
             │  disabledByTimeout ─▶ tapEnable(true); watchdog 2 s: tapIsEnabled + trial create│
             └───────────────┬─────────────────────────────────────────────────────────────────┘
 hotkeys (Carbon) ─▶ KeyboardShortcuts.onKeyDown(name) ─┐   │ PointerEvent
 status menu items ──────────────────────────────────────┼──▶│                     
 pane:// URL (strict parse) ─────────────────────────────┘   ▼ Command
 AXWindowSystem.events (THE single reader) ──WindowEvent──▶ ┌─────────────────────────────────┐
 CG bounds poll (pressed window, 60 Hz) ──DragFrame──────▶ │ Arranger (PaneEngine, pure)      │
 Displays + current Space per display ──Displays────────▶  │  World + UndoHistory             │
 conflict poll (CFPreferences, 2 s) ──Conflicts─────────▶  │  sessions: drag | edgeResize |   │
 clock ticks (dwell 150 ms, debounce) ──Tick────────────▶  │            gapDrag | none        │
                                                            │  pause reasons, MRU focus,       │
                                                            │  lastRequested / lastApplied     │
                                                            │  Planner: resolve → frames       │
                                                            └──────┬──────────────┬────────────┘
                                      [WindowCommand] (setFrame/park/focus/raise) │ [Effect]
                                                   ▼                              ▼
                       AXWindowSystem.perform ─▶ ExclusionFilter.admit ─▶ AXAppThread   preview panel / gap
                       (latest-wins slot, size→pos→size, read-back) ─▶ frameApplied ─┐   handles / toast /
                                                                                     │   beep / announce /
                       echo: frameApplied + windowMoved ≈ lastApplied ◀──────────────┘   save(debounced|now)
                                                                                         ▼
                                                                  LayoutStore (layout.json, atomic)
```

### Recommended Project Structure

```
Sources/PaneModel/
├── LayoutTree.swift        # + Node.desktop(hidden:), validate: ≤1 desktop leaf
├── TreeEdits.swift         # + swap, balance, rotate, flip, resizeChild, setDesktopHidden
├── Neighbours.swift        # NEW: neighbour(of:toward:in:recency:), boundary(for:edge:)
├── Snap.swift              # NEW: SnapTarget → Rect inside the Desktop rect
├── Resolve.swift           # + desktopMinimum parameter (default 1×1)
├── World.swift             # + Desk invariant (exactly one desktop leaf), rekey, recordFloatingFrame, reflow
└── Undo.swift              # + internal rekey(from:to:)
Sources/PaneEngine/
├── Arranger.swift          # NEW: pure state machine (inputs → commands + effects)
├── Planner.swift           # NEW: desk + display + gap + mins → FramePlan (frames, parks, unfit)
├── DragSession.swift       # NEW: classification + dwell + target/modifier rules (UI-SPEC state matrix)
├── Command.swift           # NEW: Command enum + enablement (menu/hotkey/URL share it)
├── PaneURL.swift           # NEW: strict pane:// parser (3 commands)
├── Recovery.swift          # NEW: stranded rule, crash-loop rule, home frames
├── ConflictPolicy.swift    # NEW: detected values → conflicts, originals, restore plan
└── LifecycleSync.swift     # + windowRekeyed handling via World.rekey
Sources/PaneMac/
├── Input/InputTap.swift        # NEW: tap thread, callback, watchdog, button-rect cache
├── Input/Hotkeys.swift         # NEW: KeyboardShortcuts.Name table → Command
├── Overlay/PreviewPanel.swift  # NEW: per-display click-through panel + CAShapeLayers
├── Overlay/GapHandles.swift    # NEW: pooled handle panels
├── Overlay/Toast.swift         # NEW: NSVisualEffectView + NSHostingView
├── ArrangeController.swift     # NEW: MainActor shell owning Arranger, the events reader, fan-out
├── LayoutStore.swift           # NEW: layout.json (MinimumHintsStore pattern)
├── WindowManagerSettings.swift # NEW: CFPreferences I/O for com.apple.WindowManager
├── AppDelegate.swift           # NEW: terminateLater, application(_:open:) for pane://
└── AX/…                        # + park/focus/raise, Finder menu press, button frames, termination write
Sources/PanePrivate/SkyLightSpaces.swift  # + currentSpace(displayUUID:) via SLSManagedDisplayGetCurrentSpace
scripts/release.sh                       # NEW
```

### Current code Phase 3 builds on (verbatim)

These are the exact discrete values the plans touch. Each was read this session.

`Sources/PaneEngine/WindowSystem.swift:120-126` [VERIFIED]:
```swift
public enum WindowCommand: Equatable, Sendable {
    case setFrame(WindowRef, Rect)
    case park(WindowRef, displayUUID: String)
    case focus(WindowRef)
    case raise(WindowRef)
    case setHidden(WindowRef, Bool)
}
```

`Sources/PaneEngine/WindowSystem.swift:97-117` [VERIFIED]:
```swift
public enum WindowEvent: Equatable, Sendable {
    case windowCreated(WindowInfo)
    case windowDestroyed(WindowRef)
    case windowMoved(WindowRef, Rect)
    case windowResized(WindowRef, Rect)
    case windowFocused(WindowRef)
    case windowStateChanged(WindowRef, WindowState)
    /// Title, kind, tab or exclusion changed. Titles are never logged.
    case windowChanged(WindowInfo)
    /// The same window, only its ID changed (a fallback ID corrected, D-15): never a close and a reopen. Consumers
    /// re-point every reference to `from` at `to.window`.
    case windowRekeyed(from: WindowRef, to: WindowInfo)
    /// A frame write finished; `actual` is the read-back frame.
    case frameApplied(WindowRef, requested: Rect, actual: Rect)
    case appResponsiveness(pid: Int32, degraded: Bool)
    case sessionPaused(Bool)
    case appLaunched(pid: Int32, bundleID: String)
    case appTerminated(pid: Int32)
    case displaysChanged
    case spaceChanged(displayUUID: String, spaceID: UInt64?)
}
```
`spaceChanged` is declared but **never emitted**: `grep` finds no producer in `Sources/`. Phase 3 must emit it.

`Sources/PaneModel/LayoutTree.swift:3-8` and `:42-45` [VERIFIED]:
```swift
public enum Node: Codable, Equatable, Sendable {
    /// `weights.count == children.count`, each weight >= `LayoutTree.minWeight`, sum 1.
    case split(axis: Axis, children: [NodeID], weights: [Double])
    case panel(WindowRef)
    case tabs(windows: [WindowRef], selected: Int)
}
    public static let minWeight = 0.01
    public static let maxDepth = 64
    public static let maxNodes = 4096
    public static let maxChildren = 100
```

`Sources/PaneModel/IDs.swift:108-110` [VERIFIED]: `case present, absent, fullscreen, closed`

`Sources/PaneModel/DropZones.swift:4-15, 20, 22` [VERIFIED]:
```swift
public enum DropZone: Equatable, Sendable {
    case edge(Edge)
    case center
}
public enum DropTarget: Equatable, Sendable {
    case tile(NodeID, DropZone)
    /// Dock along the whole layout's edge.
    case layoutEdge(Edge)
    /// The tree is empty: the drop becomes the root.
    case emptyLayout
}
    public static let edgeBandFraction: Double = 0.25
    public static let displayEdgeBand: Double = 24
```
`applyDrop` maps `.tile(node, .center)` to `group(window, into: node)` (`DropZones.swift:59`). **Phase 3 must never pass a `.center` target to `applyDrop`**, because CONTEXT A makes the centre a plain move.

`Sources/PaneModel/World.swift:57` `public static let currentSchemaVersion = 1`. `Sources/PaneModel/Undo.swift:8` `public static let limit = 50`. `Undo.swift:17,24,27`: `push`, `pop` and `forget` are `internal` [VERIFIED].

`Sources/PaneModel/Resolve.swift:22-24` [VERIFIED]: "Only `.present` windows take part (D-17). Absent and fullscreen windows keep their node but get no rect and are not unfit". Signature (`:31`): `public func resolve(_ tree: LayoutTree, in area: Rect, mins: [WindowRef: Size], gap: Double) throws(LayoutError) -> Resolution`.

`Sources/PaneModel/Persistence.swift:25` `public static let maxEncodedBytes = 16 * 1024 * 1024`. `World.encoded()` has **no production caller** (`grep` matches only `Persistence.swift:14`), so no `World` file has ever been written by the app [VERIFIED].

`Sources/PaneMac/MinimumHintsStore.swift:15-21` [VERIFIED]: `fileName = "min-size-hints.json"`, `maxBytes = 65_536`, `schemaVersion = 1`, `defaultDirectory` = `URL.applicationSupportDirectory.appending(path: "Pane", directoryHint: .isDirectory)`.

`Sources/PaneEngine/LifecycleSync.swift:34-37` [VERIFIED]:
```swift
        // windowRekeyed is not a lifecycle fact: Phase 3 re-points desk refs from `from` to `to.window`.
        case .windowCreated, .windowMoved, .windowResized, .windowFocused, .windowChanged, .windowRekeyed, .frameApplied,
             .appResponsiveness, .sessionPaused, .appLaunched, .appTerminated, .displaysChanged, .spaceChanged:
            return false
```

`Sources/PaneMac/AXWindowSystem.swift:179-183` [VERIFIED]:
```swift
        for command in split.admitted {
            guard case .setFrame(let ref, let rect) = command else {
                logger.info("dropping a command other than setFrame: not implemented before Phase 3")
                continue
            }
```

`Sources/PaneMac/Shell/StatusItemController.swift:46-51` [VERIFIED] is the only reader of `system.events`:
```swift
        // inventory() serves the cache immediately, so re-reading it after each event is cheap.
        Task { [weak self, system] in
            for await _ in system.events {
                self?.latest = await system.inventory()
            }
        }
```

`Sources/PaneMac/Displays.swift:31` [VERIFIED]: `currentSpaceID: nil`, with the comment at `:11-12` "`currentSpaceID` waits for SkyLight (Phase 6)". Phase 3 fills it in (CONTEXT D).

`Sources/PanePrivate/SkyLightSpaces.swift:20-22` [VERIFIED]: `dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)`, `dlsym(handle, "SLSMainConnectionID")`, `dlsym(handle, "SLSCopySpacesForWindows")`.

`Sources/PaneMac/AX/AXSnapshotReader.swift:17-21` [VERIFIED]: the batched read already includes `kAXZoomButtonAttribute, kAXFullScreenButtonAttribute`, but only their presence and enabled state are kept (`ButtonFact`, `WindowSnapshot.swift:8-18`). No button *frame* is read yet.

`xcode/project.yml` [VERIFIED]: `:11` `GENERATE_INFOPLIST_FILE: YES`, `:13` `MARKETING_VERSION: "0.2.0"`, `:17` `DEVELOPMENT_TEAM: S2K7P43927`, `:18` `ENABLE_HARDENED_RUNTIME: YES`, `:42` `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.pane`, `:43` `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES`, `:45` `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`.

### Pattern 1: `Arranger`, a pure core with a thin MainActor shell

**What:** one `struct Arranger: Sendable` in PaneEngine owns `World`, `UndoHistory`, sessions, pause reasons, the MRU focus list, `lastRequested[WindowIdentity]`, `lastApplied[WindowIdentity]` and the current displays. `mutating func handle(_ input: ArrangerInput, now: ContinuousClock.Instant) -> [ArrangerEffect]`. It never sleeps. Deadlines (dwell, save debounce, Finder expectation) are values it returns, and the shell schedules a `.tick` for them. This is the `WindowTracker` pattern (pure, takes `now`, shared by fake and live).

**Inputs:** `.event(WindowEvent)`, `.inventory(WindowInventory)` (launch), `.pointer(PointerEvent)` (from the tap), `.dragFrame(WindowIdentity, Rect)` (CG poll), `.command(Command)`, `.displays([DisplayInfo])`, `.conflicts(ConflictState)`, `.gap(Double)`, `.tick`.
**Effects:** `.perform([WindowCommand])`, `.preview(PreviewState?)`, `.gapHandles([GapHandle])`, `.notice(Notice)`, `.beep`, `.announce(String)`, `.save(.debounced | .now)`, `.openFinderWindow`, `.alert(Conflict)`.

**The shell (`ArrangeController`, PaneMac)** becomes the single `for await` reader of `system.events`. After each event it calls `system.inventory()` and forwards the result to `StatusItemController` (today's `latest`/`onInventory` fan-out) instead of `StatusItemController` reading the stream itself. Every `WindowCommand` goes through `system.perform`, never around it (02-13: exclusion is enforced there).

**Planner** (pure function): `plan(desk:display:gap:mins:desktopMinimum:) -> FramePlan { frames: [WindowRef: Rect], parks: [WindowRef], unfit: Set<WindowRef>, desktopRect: Rect? }`. The area is the display's `visibleFrame` (top-left), so the 24 pt layout-edge band never reaches the menu bar. That keeps the top edge clear of Mission Control (ROADMAP scope note). The Arranger diffs planned frames against `lastRequested` and emits `setFrame` only for changes larger than 0.5 pt. It plans only the desks whose `DeskKey` equals a display's `(uuid, currentSpaceID)`.

**Echo recognition (Claude's discretion; recommended rule):**

| Observation | Condition | Classification | Action |
|---|---|---|---|
| `frameApplied(w, requested, actual)` | always | Pane's write finished | `lastApplied[w] = actual`; clear `lastRequested[w]` once `actual` ≈ `requested` (±2 pt) or the read-back differs (refusal) |
| `windowMoved/Resized(w, f)` | `f` ≈ `lastApplied[w]` (±2 pt) | echo | ignore |
| same | left button down (tap), `w` is the press window, pointer travelled ≥ 3 pt, origin changed, size unchanged | user move | start or continue a **drag session** |
| same | left button down, press window, travelled ≥ 3 pt, size changed | user edge resize | **edge-resize session** (docked) or floating-frame fact (floating) |
| same | button up, docked `w`, `f` ≠ planned | app-initiated move or refusal | re-plan `w` at most once per second (ARCHITECTURE Pattern 3). Learned minimums arrive separately through `windowChanged.learnedMinimum` |
| same | button up, floating `w` | app moved its own floating window | record the floating frame (non-undo); clamp into the Desktop rect if it crosses docked tiles |

The ≥ 3 pt travel rule prevents a double-click on the title bar (a native zoom with no pointer travel) from being read as an edge resize.

### Pattern 2: the Desktop leaf and the new edits (PaneModel)

**Recommended shape** (proposed new code, not yet in the repo):
```swift
public enum Node: Codable, Equatable, Sendable {
    case split(axis: Axis, children: [NodeID], weights: [Double])
    case panel(WindowRef)
    case tabs(windows: [WindowRef], selected: Int)
    /// The Desktop tile (CONTEXT D): floating windows live inside its rect. Hidden: no rect, its space
    /// goes to the docked tiles, its windows are parked.
    case desktop(hidden: Bool)
}
```

Invariants and rules:
- `LayoutTree.validate()` allows **at most one** `.desktop` node. `Desk.validate()` requires **exactly one**, and `Desk.init()` creates a tree whose root is the Desktop leaf. Splitting the rule this way keeps the existing tree-level tests (empty trees, trees without a Desktop) valid, while every desk, which is what gets saved, has one.
- `windows` and `leaf(containing:)` skip `.desktop`. `group(_:into:)` on the Desktop throws, because it can't be a tab group. `remove` and `normalize` treat it like a panel, so the last docked window closing collapses the tree back to the Desktop root.
- `resolve` gains `desktopMinimum: Size = Size(width: 1, height: 1)`. A visible Desktop aggregates to that minimum. A hidden one returns `nil` (it doesn't take part, like an absent window). The Desktop is never chosen as an `unfit` victim. The Planner passes the per-axis maximum of the present floating windows' minimums, so floating windows always fit inside the Desktop at their minimum.
- `DropZones.target` needs no change: the Desktop leaf is a non-split rect in `nodeRects`, so its edge bands dock beside it and its centre is a plain move. `.emptyLayout` becomes unreachable for desks (the root is never nil) but stays for raw trees.
- **Schema:** keep `currentSchemaVersion = 1` and update the hand-built JSON fixtures in `PersistenceTests.swift` (for example `validPair`, `deskJSON`) to include a `{"desktop":{"hidden":false}}` node. No v1 `World` file can exist outside tests, because `World.encoded()` has no production caller (verified above). That satisfies "the saved format includes it from the start" without a migration nobody needs.

New edits. Each follows the existing all-or-nothing pattern of working on copies and committing on success, and each is one `World.edit`, so one undo step:

| Edit | Semantics | Notes |
|---|---|---|
| `swap(_ a: WindowRef, _ b: WindowRef)` | Exchange the contents of two `.panel` leaves. NodeIDs stay in place | Tabs and Desktop: throw. Phase 7 extends this |
| `balance(split:)` | All weights `1/n` | `normalize` keeps them bit-identical (`isNormalised`) |
| `rotate(split:)` | **Transpose the subtree**: toggle the axis of that split and of every split below it, keeping child order | Rotating twice is the identity, unless the new axis equals the parent's, in which case `normalize` merges it into the parent (expected; Undo reverts). Toggling only the one split would merge same-axis children and lose the nested shape [ASSUMED: A3] |
| `flip(split:)` | Reverse children and weights | — |
| `resizeChild(in split:, index:, by delta:)` | Child `index` grows by `delta` (fraction of the split's length), taken from its siblings in proportion, each clamped at `minWeight` | Grow/Shrink (TILE-13), 10% steps. Commit only if the **resolved** rects change, otherwise beep (at a size limit; UI-SPEC) |
| `setDesktopHidden(_:)` | Flip `.desktop(hidden:)` | Hide is refused while nothing is docked (UI-SPEC) |
| move-to-neighbour (Desk level) | `tree.remove(w)` then `tree.insert(w, at: nearEdge, of: neighbourLeaf)` in one closure | The neighbour leaf's NodeID survives `remove` (only splits collapse) |
| float (Desk level) | `tree.remove(w)` then `desktop.add(w, frame:)` | Frame = current tile rect, clamped into the new Desktop rect |
| dock (Desk level) | `desktop.remove(w)` then `applyDrop(target)` | `target` from `DropZones.target` at the window's centre (CONTEXT B) |

**Neighbour lookup** (new pure function in `Neighbours.swift`): `neighbour(of leaf: NodeID, toward edge: Edge, in resolution: Resolution, recency: [NodeID]) -> NodeID?`. A candidate is any non-split leaf, Desktop included, whose near side lies across `edge`. For `.right` that means `candidate.minX >= rect.maxX` minus a tolerance of gap + 1, with positive perpendicular overlap. The nearest edge distance wins. Ties go to the earliest entry in `recency` (the MRU list), then the smaller NodeID, so the result is deterministic. A floating window uses its frame as `rect`.

**Boundary lookup** for edge resize: `boundary(for leaf: NodeID, edge: Edge) -> (split: NodeID, index: Int)?`. Walk up the ancestors to the first split on `edge.axis` where the ancestor-or-self child has a sibling on that side. Return `nil` for an outer edge, in which case the window snaps back.

**Snap targets** (TILE-14, `Snap.swift`): halves, thirds, quarters, maximise and centre, computed inside the Desktop leaf's resolved rect inset by the gap. Centre keeps the window's size, clamped inside the rect [ASSUMED: A9 for the gap inset].

### Pattern 3: non-undo World paths that keep persistence and undo consistent

| Need | New PaneModel API (proposed) | Why not `World.edit` / `apply` |
|---|---|---|
| `windowRekeyed(from:to:)` (Phase 2 obligation) | `World.rekey(from: WindowRef, to: WindowRef, history: inout UndoHistory)`: re-point the ref in every desk's tree nodes, `states` and Desktop layer, **and** in every undo snapshot (new internal `UndoHistory.rekey`). If `to` is already on a desk (the tracker merged two entries, 02-16), close `from` instead | An undo snapshot still holding the old ID would revive a window no desk holds. `requery` returns nil for it, so it is reported `.closed` and the slot is lost |
| A floating window the user moved | `World.recordFloatingFrame(_:for:on:)`, no history | A user moving a floating window is an OS fact, not a layout edit |
| A window that lost its room (CONTEXT D) | `World.reflow(_ key:, _ change:)`, the same as `edit` but pushes no history | Undoing it would re-dock an unfit window, which would immediately float again |
| Undo after floating moves | Extend `World.undo` to keep the **current frame** of every window that floats in both the current desk and the snapshot, as it already keeps states | Otherwise an undo of an unrelated edit throws floating windows back to old positions |

Route `windowRekeyed` through `LifecycleSync` by replacing the `.windowRekeyed` arm at `LifecycleSync.swift:35` with a call to `World.rekey`. That keeps "the one path from OS facts into the model" true.

### Pattern 4: drag detection from the tap plus frame deltas

1. **Mouse-down** (tap → main): record the point, flags and `windowUnderPointer` (`event.getIntegerValueField(.mouseEventWindowUnderMousePointer)`, a public CGEvent field: `CGEventTypes.h:377` `kCGMouseEventWindowUnderMousePointer = 91` [VERIFIED: SDK header]). Map it to a tracked window through `visibleMemberID ?? windowID`. If it's unknown (a synthetic ID, or the field is 0), use the topmost tracked window whose frame contains the point, ranked by the latest CG list order. That is pure geometry, not an AX hit test.
2. Start a **60 Hz CG-bounds poll** of that one window (`CGWindowListCreateDescriptionFromArray`, as `CGWindowList.swift` already uses CG) once the pointer has travelled 3 pt. Stop it on mouse-up. Feed `.dragFrame` to the Arranger.
3. **Session start:** the classification table in Pattern 1. Excluded apps, never-dock windows and any drag while paused start no session and get no overlay (UI-SPEC).
4. **During the drag:** on every pointer sample, `DropZones.target(at: pointer, in: visibleFrame, tree:, resolution:)` (cheap). The target or the modifier set changing restarts the 150 ms dwell. The dry run (`applyDrop` + `resolve`) runs once per change, never per move. Modifiers come from each event's `flags` (`.maskShift` bypass, `.maskCommand` swap). ⌥ and ⌃ are ignored (CONTEXT A).
5. **Mouse-up:** apply exactly the preview on screen (WYSIWYG). If no preview is visible, the miss rules apply: a docked window snaps back, a floating one gets a plain move or a clamp. Read the final frame from the poll's last sample. A dock or swap is one `World.edit`, then the Planner runs.

Rectangle shows this flow working during native title-bar drags. It watches `.leftMouseDown, .leftMouseUp, .leftMouseDragged` with a global monitor (or an active `CGEvent.tapCreate(... options: .defaultTap ...)`) and reads `.mouseEventWindowUnderMousePointerThatCanHandleThisEvent` at mouse-down [CITED: github.com/rxhanson/Rectangle `Rectangle/Snapping/SnappingManager.swift`, `Rectangle/Utilities/EventMonitor.swift`, main @ 2026-10-25]. Pane avoids Rectangle's main-thread AX lookup by using the CG field plus the poll.

### Pattern 5: green button without AX in the callback (TILE-06, TILE-19)

- On each refresh, the `AXAppThread` reads the green button's frame: `kAXFullScreenButtonAttribute`, falling back to `kAXZoomButtonAttribute` when that is absent, with one `AXUIElementCopyMultipleAttributeValues` for position and size. Store it as an **offset from the window's top-left**, so the cache follows frame changes (from `frameApplied` and the poll) without new AX reads.
- The shell publishes `[CGWindowID: CGRect]` (global rects) into an `OSAllocatedUnfairLock` the tap reads. Writers swap in a whole dictionary, so the callback's critical section is one dictionary lookup.
- Callback rule: `leftMouseDown` and not `flags.contains(.maskAlternate)` and `zoomRects[windowUnderPointer]` contains `location` → set `swallowing = true`, yield `.greenButton(windowID)`, return `nil`. Swallow the matching `leftMouseUp` too (and any `leftMouseDragged` in between). With ⌥ held, everything passes through, so macOS performs its normal zoom (TILE-19). Pane also skips swallowing when the window is excluded, never-dock or the app is paused. Those flags are in the same published dictionary (drop the entry).
- After a native ⌥-zoom, the frame change is app-initiated (Pattern 1 table): a floating window keeps the zoom, clamped into the Desktop rect; a docked window is re-planned back into its tile [ASSUMED: A4].

### Pattern 6: event-tap wrapper with watchdog

- A dedicated `Thread` with its own `CFRunLoop`, the same shape as `AXAppThread`. **Not the main run loop:** while the status menu is open, main runs in event-tracking mode, a default-mode source wouldn't be serviced, and the system would disable the tap by timeout (Pitfall 5).
- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: leftMouseDown|leftMouseUp|leftMouseDragged|flagsChanged, …)`. **No `keyDown` in the mask**, so Pane never sees typed characters (privacy).
- In the callback: on `.tapDisabledByTimeout` or `.tapDisabledByUserInput`, call `CGEvent.tapEnable(tap: port, enable: true)` and return the event. Otherwise copy the fields and `continuation.yield(...)`. No AX, file I/O, logging or allocation-heavy work.
- Watchdog (main, every 2 s): check `CGEvent.tapIsEnabled(tap:)`, and re-enable it if needed. **Also try a throwaway `tapCreate(.defaultTap)`**. If that returns nil, Accessibility was revoked: invalidate Pane's tap immediately (`CFMachPortInvalidate`). An active tap left running after revocation has been reported to block clicks until restart, and `AXIsProcessTrusted()` can keep returning true [CITED: developer.apple.com/forums/thread/735204]. The state drives the Debug line "Event tap: running" / "Event tap: off, drags not detected".

### Pattern 7: click-through overlay panels

The UI-SPEC property table (Surface 2) is right as written. Additional findings:
- Pass `.nonactivatingPanel` **in the initializer's `styleMask`**. Setting it later is widely reported not to take effect [ASSUMED: community reports; JUCE forum, Electron #35815].
- Subclass `NSPanel` with `canBecomeKey`/`canBecomeMain` returning false. The scratch build compiled exactly this configuration [VERIFIED: local compile].
- Position layers through `Coordinates.appKit(fromTopLeft:primaryHeight:)`, then subtract the panel origin.
- Re-resolve `CGColor`s inside `effectiveAppearance.performAsCurrentDrawingAppearance` (UI-SPEC Color).

### Pattern 8: gap handles

- Geometry comes from the Planner's `Resolution`. For each split, the strip between consecutive **taking-part** children.
- **Correction to the UI-SPEC:** `NSTrackingArea` options `[.mouseEnteredAndExited, .cursorUpdate, .activeAlways]` won't deliver `cursorUpdate`. `NSTrackingArea.h:29` says `NSTrackingActiveAlways` is "Not supported for NSTrackingCursorUpdate" [VERIFIED: macOS 27 SDK header]. Use `[.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]` and call `NSCursor.set()` in `mouseEntered`/`mouseMoved`/`mouseDragged`. Reports say an inactive app's cursor changes can be ignored over another app [CITED: developer.apple.com/forums/thread/738051]. If UAT shows the arrow cursor, the accent highlight still works and resize still works. Accept that for Phase 3 (A5).
- `acceptsFirstMouse(for:) -> true` on the handle view, so the first click in an inactive window starts the drag.
- During a handle drag, apply weights to a **transient copy** for live `setFrame`s (latest-wins coalesces them), and commit one `World.edit(resizeBoundary)` on mouse-up, so it is one undo step.
- `NSCursor.resizeLeftRight` and the other resize cursors are `API_TO_BE_DEPRECATED` in the macOS 27 SDK. They compile cleanly with `-warnings-as-errors` at a macOS 14 target [VERIFIED: local compile]. On 15+, `NSCursor.columnResize`/`rowResize` are the replacements (`NSCursor.h:93,102`).

### Pattern 9: one command dispatcher and the hotkey table

- `enum Command` in PaneEngine has one case per UI-SPEC row. Menu items, `KeyboardShortcuts.onKeyDown(for:)` handlers and `pane://` all call `ArrangeController.dispatch(_:)` → `arranger.handle(.command(c))`. Enablement (`func availability(_ c: Command, context:) -> Availability`) is one pure function, used both to grey menu items and to beep on refused hotkeys.
- Names and defaults come verbatim from `03-UI-SPEC.md:343-366` [VERIFIED: read this session]. There are 33 names: `focusLeft focusRight focusUp focusDown moveLeft moveRight moveUp moveDown dock float swapPrevious undo growTile shrinkTile balanceSplit rotateSplit flipSplit finderSplit snapLeftThird snapCenterThird snapRightThird snapTopLeft snapTopRight snapBottomLeft snapBottomRight snapMaximize snapCenter arrangeAll floatAll toggleDesktop togglePause restoreAll toggleExcludeFrontmost`. The halves alias is `moveLeft…moveDown` and dispatches `moveOrSnap(edge)`.
- `Name(_:initial:)` writes the default into `UserDefaults` under `KeyboardShortcuts_<name>` the first time, only if no value is stored (`KeyboardShortcuts.swift:589-605`) [VERIFIED: source]. These raw names are therefore a **persistent contract** for the Phase 4 recorder. Renaming one later orphans the user's binding.
- Menu: UI-SPEC says to call `KeyboardShortcuts.disable(names)` in `menuWillOpen` and `enable` in `menuDidClose`, which is what the library documents (`NSMenuItem++.swift:101`). 3.1.0 also switches to raw-key local monitors while a menu is tracking (`HotKey.swift:77-79`), which consume matching keys, so both routes fire the command once. Keep the UI-SPEC approach, since it guarantees the menu item path.
- **`setShortcut(for:)` registers a `NotificationCenter` block observer per item** that is only removed by `setShortcut(for: nil)` or a re-set (`NSMenuItem++.swift:127-151`) [VERIFIED: source]. `menuNeedsUpdate` rebuilds items on every open (`StatusItemController.swift:59-60`), so one observer would leak per item per open. Build the command items **once** and update only `isEnabled`, `title` and `state` on open. Alternatively, call `setShortcut(for: nil)` on old items before `removeAllItems()`.

### Pattern 10: persistence and recovery

**File:** `~/Library/Application Support/Pane/layout.json`, following the `MinimumHintsStore` pattern: size cap (`World.maxEncodedBytes`), version probe, full decode, validation, set-aside to `.corrupt`. A **newer** schema version is never overwritten (`Persistence.swift:31-33`): log it, keep the file, and run this session without saving layouts.
```json
{ "schemaVersion": 1,
  "world": { …World.encoded()… },
  "homeFrames": [ { "window": {WindowIdentity}, "frame": {Rect} } ],
  "session": { "cleanExit": false, "launchedAt": "<ISO8601>", "recoveryLaunch": true, "survivedMinute": false } }
```
(Proposed shape. `World` and `WindowIdentity` are existing `Codable` types.)

- **Writes:** debounced 0.5 s after any World change. **Synchronous** immediately before any `park` is sent (CONTEXT C). `cleanExit` is written `false` at launch and `true` as the last step of a clean quit.
- **Crash loop** (CONTEXT C): at launch, `crashLoop = !cleanExit && previous.recoveryLaunch && !previous.survivedMinute`. A recovery launch writes `recoveryLaunch = true`, and 60 s later writes `survivedMinute = true`. Pure function in `Recovery.swift`, tested with an injected clock.
- **Stranded rule** (SAFE-02/03): a tracked window is stranded when less than 50% of its area, or less than 40×40 pt, lies inside the union of the displays' `visibleFrame`s. Destination: its home frame if one is recorded for its identity, otherwise the same size centred on its display's `visibleFrame`, shrunk to fit. Do this **before** re-applying the layout [ASSUMED: A6 for the thresholds].
- **Re-attach (SAFE-06):** after the initial sweep, keep each saved `WindowRef` whose `WindowIdentity` (windowID, pid, bundleID) equals a tracked window's identity **and** whose `idSource != .synthetic`. Synthetic IDs are session-only (02-11). Unmatched saved slots are removed through the close path. Tracked windows not in the saved layout float on their desk's Desktop. Then re-plan quietly: no toasts except N2/N3.
- **Home frames:** a floating window's home is its Desktop-layer frame. A parked window's home is its pre-park frame (written before parking). Docked windows need none, since they stay put on quit.

### Pattern 11: quit restore (SAFE-01)

`PaneMacApp.run` installs no `NSApplicationDelegate` today (it calls `app.run()` directly, `PaneMacApp.swift:65`). Add one:
- `applicationShouldTerminate(_:)` → `.terminateLater`. Run the restore, then `NSApp.reply(toApplicationShouldTerminate: true)`.
- Restore with **bounded synchronous writes**, the AeroSpace pattern (`setAxFrameForTermination` with a `DispatchSemaphore`) [CITED: github.com/nikitabobko/AeroSpace `Sources/AppBundle/tree/MacApp.swift:159-166`]. Add `AXAppThread.writeForTermination(windowID:rect:deadline:) -> Bool`, which performs a block on the thread and waits on a semaphore up to its deadline. Fan out across apps with a `DispatchGroup` and wait at most about 2 s in total. A hung app is abandoned when its deadline passes. Don't depend on `async` MainActor work during `.terminateLater`. The run loop is then in modal-panel mode, and it is simpler not to rely on main-queue servicing there.
- Save `cleanExit = true` last.
- Install `DispatchSource.makeSignalSource(signal: SIGTERM)` (after `signal(SIGTERM, SIG_IGN)`) → `NSApp.terminate(nil)`, so `killall Pane` and logout restore too. `kill -9` is the crash path.

### Pattern 12: desks per display and Space (CONTEXT D, WIN-07)

- Add `SkyLightSpaces.currentSpace(displayUUID: String) -> UInt64?` through `dlsym(handle, "SLSManagedDisplayGetCurrentSpace")` with signature `@convention(c) (Int32, CFString) -> UInt64`, behind `Capability.spaces`. A Developer ID + hardened-runtime probe resolved it and returned `6` for the main display, matching `SLSCopyManagedDisplaySpaces`' "Current Space" `id64` 6 [VERIFIED: local probe, macOS 27.0.1]. The signature's provenance is yabai's `SLSManagedDisplayGetCurrentSpace(int cid, CFStringRef uuid)` [ASSUMED: prior-art header, cross-checked only by the probe returning a plausible ID].
- `Displays.current()` fills `currentSpaceID`. On `NSWorkspace.activeSpaceDidChangeNotification` (already observed, `AXWindowSystem.swift:110`), re-read the displays and emit `.spaceChanged(displayUUID:spaceID:)` per display that changed.
- Add `spaces: Set<UInt64>?` to `WindowInfo`, filled from `ObservationContext.windowSpaces` in `WindowTracker.ingest`. The Arranger puts a new window on `DeskKey(displayUUID, its Space ∩ the display's current Space)`.
- **Fullscreen Spaces get no desk.** A desk is created lazily, only when a dockable, present, non-fullscreen window is first seen on that Space. A window that goes fullscreen keeps its slot on its original desk (`.fullscreen`, `Resolve.swift:22-24`), and its neighbours take the space until it returns (WIN-07).
- **UI-SPEC inconsistency, resolved:** the UI-SPEC says a fullscreen window's reserved tile "is an ordinary drop target and shows the wallpaper". Under the locked model (D-17), a fullscreen window's leaf has **no rect**, so it isn't in `nodeRects` and can't be a drop target. Follow D-17. That UI-SPEC sentence describes nothing visible.
- **Spaces lookup off:** `spaceID = nil`, one desk per display. Accept degraded behaviour: windows on other Spaces may be planned. Log once. This is the Phase 2 fallback contract [ASSUMED: A7].

### Pattern 13: conflict settings (SAFE-04)

Keys present in `com.apple.WindowManager` on this Mac (macOS 27.0.1), all `CFBoolean` [VERIFIED: `defaults read` + `CFPreferencesCopyAppValue` probe]:

| Feature (System Settings label on macOS 27, read from `DesktopSettings.appex` `Localizable.loctable`) | Key | "On" means | Turn Off writes | Absent key means |
|---|---|---|---|---|
| Stage Manager | `GloballyEnabled` | true | false | off [ASSUMED] |
| "Drag windows to left or right edge of screen to tile" (macOS 15+) | `EnableTilingByEdgeDrag` | true | false | **on** (system default) [CITED: pkdone/.dotfiles-mac PR #15, 2026-10-18; MEDIUM] |
| "Drag windows to menu bar to fill screen" (macOS 15+) | `EnableTopTilingByEdgeDrag` | true | false | on [ASSUMED, same family] |
| "Hold ⌥ key while dragging windows to tile" | `EnableTilingOptionAccelerator` | — | **left alone** (CONTEXT A, UI-SPEC) | — |
| "Click wallpaper to show desktop" | `EnableStandardClickToShowDesktop` | true = "Always" | false = "Only in Stage Manager" | true (Always) [CITED: nix-darwin `system.defaults.WindowManager.EnableStandardClickToShowDesktop`; MEDIUM] |

- **I/O:** `CFPreferencesAppSynchronize(domain)`, then `CFPreferencesCopyAppValue(key, domain)` (nil = absent). Write with `CFPreferencesSetAppValue(key, kCFBooleanFalse, domain)` + `CFPreferencesAppSynchronize`. A same-value write and read-back succeeded with no prompt from a hardened-runtime Developer ID binary [VERIFIED: probe].
- **Originals:** record `{key: .absent | .bool(Bool)}` once, before the first write, in UserDefaults. Restore writes the bool back, or **deletes the key** (`CFPreferencesSetAppValue(key, nil, domain)`) when it was absent, so the system default applies again.
- **Gate edge tiling on the OS version** (`ProcessInfo.processInfo.isOperatingSystemAtLeast(15.0)`), not on key presence. On 14 the keys don't exist, and on 15+ an absent key means "on".
- **Live apply:** community sources say WindowManager applies this domain live, with no `killall` [CITED: pkdone PR #15; qiita.com/P-man_Brown/items/509c432f4a56160eaa7d; MEDIUM]. System Settings itself goes through the private `WindowManager.framework` (`otool -L` on `DesktopSettings.appex`), so a raw write may not always be adopted. **Read-back:** about 1 s after the write, synchronize and read again. If the value isn't the written one, open `x-apple.systempreferences:com.apple.Desktop-Settings.extension` and show N7. Never `killall WindowManager` (Pitfall 15).
- **Change detection:** CFPreferences has no public cross-process change notification. Poll every 2 s on main (cheap: cfprefsd) and also on app activation.
- **Copy note:** macOS 27 labels the setting "Click wallpaper to show desktop" (Sonoma said "reveal"). The approved UI-SPEC copy "Click Wallpaper to Reveal Desktop" stays. Flag it in UAT only.

### Pattern 14: Finder split (TILE-17), with no Apple Events

1. The Arranger records `FinderExpectation { target leaf, edge (longer side: width ≥ height → .right, else .bottom), existing Finder window IDs, deadline now + 2 s }` and emits `.openFinderWindow`.
2. The shell, on Finder's `AXAppThread`, gets the app's `kAXMenuBarAttribute`, walks the menu items (bounded depth 3), and finds the first item with `kAXMenuItemCmdCharAttribute == "N"` and `kAXMenuItemCmdModifiersAttribute == 0` (`kAXMenuItemModifierNone`: ⌘ only). That is File ▸ New Finder Window, which matches in any localisation. It then calls `AXUIElementPerformAction(item, kAXPressAction)` [VERIFIED: constants in `AXAttributeConstants.h:984-1005`; ASSUMED: that pressing works while Finder is inactive].
3. The first `windowCreated` for Finder's pid that isn't in the existing set, before the deadline, docks through `applyDrop(.tile(target, .edge(edge)))`. The tracker's 250 ms settle delay (`WindowTracker.swift:46`) is inside the 2 s window. At the deadline, show N9.
4. If Finder isn't running (a user can quit it): `NSWorkspace.shared.openApplication` first, then press. If the menu item isn't found, fall back to `NSWorkspace.shared.open(home)`.
5. No `com.apple.security.automation.apple-events` entitlement and no Automation prompt.

### Pattern 15: `park`, `focus` and `raise` in `perform`

- `park(ref, displayUUID)`: keep the size, set the position to the display's `visibleFrame` bottom-right corner minus 1 pt, through the same latest-wins slot. macOS keeps a sliver visible, which AeroSpace documents [CITED: PITFALLS.md Pitfall 3]. Save `layout.json` synchronously first (Pattern 10).
- `focus(ref)`: on the app thread, set `kAXMainAttribute` true, then `AXUIElementPerformAction(window, kAXRaiseAction)`. Then on main, `NSRunningApplication(processIdentifier:)?.activate()`. If the frontmost pid hasn't changed after about 200 ms, fall back to setting the app element's `kAXFrontmostAttribute` true. `activateIgnoringOtherApps` "is deprecated in macOS 14 and will have no effect" [CITED: developer.apple.com doc JSON `activateignoringotherapps`]. AeroSpace still uses AXMain + AXRaise + `activate` [CITED: AeroSpace `MacApp.swift:130-148`].
- `raise(ref)`: `kAXRaiseAction` only.
- `setHidden`: keep it logged and dropped (not needed in Phase 3). Chesterton: it stays in the protocol for later phases.
- `FakeWindowSystem.perform` must model `park` (frame move plus a recorded "parked" flag), `focus` (emit `windowFocused`) and `raise`.

### Pattern 16: the `pane://` URL scheme

- Register `CFBundleURLTypes` through XcodeGen's target `info:` (`path:` + `properties:`). Xcode merges it with the generated plist, since `GENERATE_INFOPLIST_FILE: YES` is set (`project.yml:11`) [ASSUMED: XcodeGen ProjectSpec "info" merge behaviour; verify by `plutil -p` on the built app].
- Handle it in `NSApplicationDelegate.application(_:open:)`.
- Strict parser (pure, PaneEngine): scheme `pane`, host one of `restore | toggle-desktop | split-finder`, and **no** user, password, port, path (other than empty or `/`), query or fragment. Anything else: log and do nothing (UI-SPEC, Pitfall 21). Rate-limit to 1 per second per command.
- Debug and Release both registering `pane` makes LaunchServices pick one at random on a dev Mac. Register `pane-debug` in the Debug config [ASSUMED: A8].

### Pattern 17: `scripts/release.sh` (local, Phase 3)

```bash
# 1. Build: Release, universal, with a SECURE TIMESTAMP (the current Release build has none; see Pitfall 1)
scripts/generate.sh
xcodebuild -project xcode/Pane.xcodeproj -scheme Pane -configuration Release \
  -derivedDataPath xcode/.xcode-build OTHER_CODE_SIGN_FLAGS="--timestamp" build
APP="xcode/.xcode-build/Build/Products/Release/Pane.app"
codesign -dvv "$APP" 2>&1 | grep -q '^Timestamp=' || { echo "no secure timestamp"; exit 1; }
codesign --verify --strict --deep --verbose=2 "$APP"
codesign -d --entitlements - "$APP" | grep -q get-task-allow && { echo "get-task-allow present"; exit 1; }
# 2. Notarise and staple the app (so a copy dragged out of the DMG passes Gatekeeper offline)
ditto -c -k --keepParent "$APP" build/Pane.zip
xcrun notarytool submit build/Pane.zip --keychain-profile pane-notary --wait
xcrun stapler staple "$APP"
# 3. DMG, signed, notarised, stapled (create-dmg --notarize waits and staples)
create-dmg --volname "Pane 0.3.0" --app-drop-link 400 120 --skip-jenkins \
  --codesign "Developer ID Application: Ken Scott (S2K7P43927)" --notarize pane-notary \
  "build/Pane-0.3.0.dmg" build/dmg-staging/
# 4. Verify
spctl -a -vvv -t exec "$APP"            # expect: source=Notarized Developer ID
xcrun stapler validate "build/Pane-0.3.0.dmg"
shasum -a 256 "build/Pane-0.3.0.dmg"   # publish beside the GitHub pre-release
```
Also: bump `MARKETING_VERSION` to `0.3.0` (`project.yml:13`). Store notary credentials once, by hand: `xcrun notarytool store-credentials pane-notary` (a human-action checkpoint). `--skip-jenkins` avoids the Finder AppleScript, and with it an Automation prompt for Terminal. Phase 9 can prettify the DMG.

### Anti-Patterns to Avoid

- **A second `for await` on `system.events`.** AsyncStream delivers each element to one iterator, so two readers split the events.
- **Writing frames while a session is active for that window,** or writing the dragged window at all before mouse-up.
- **`World.edit` for OS facts.** Floating moves, auto-float and rekey must not land on the undo stack.
- **Passing `.center` drop targets to `applyDrop`** before Phase 7.
- **Taking a lock that is held across IPC inside the tap callback.** Readers must only copy a dictionary.
- **Rebuilding `setShortcut` menu items on every open.** Observers leak (Pattern 9).
- **Calling `killall WindowManager`** or writing any WindowManager key not in the table above.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Global hotkeys + menu key equivalents | Carbon `RegisterEventHotKey` wrapper, keycode tables | KeyboardShortcuts 3.1.0 | Menu-tracking mode, key-code registration, Phase 4 recorder compatibility |
| Notarisation upload, polling, stapling | `curl` against the notary REST API | `xcrun notarytool submit --wait`, `stapler` | Official, handles auth and logs |
| DMG layout | Hand `hdiutil` + AppleScript | create-dmg 1.3.0 (`--codesign`, `--notarize`) | Retries "Resource busy", signs and notarises |
| Space ID per display | Inferring the Space from on-screen windows | `SLSManagedDisplayGetCurrentSpace` (dlsym) | Works on empty Spaces; verified |
| Opening a Finder window | AppleScript / Apple Events | AX press of Finder's ⌘N menu item | No entitlement, no Automation prompt |
| Layout geometry, min sizes | New layout math in the Arranger | `resolve` (water-filling, `unfit`) + `DropZones` | Already fuzz-tested in Phase 1 |
| Atomic, validated JSON store | New file format code | `MinimumHintsStore` pattern + `World.decode` | Size cap, version probe, set-aside |

**Key insight:** almost every hard problem in this phase is already solved and tested in Phases 1–2. The risk is in wiring: one events reader, one command route, one edit path. Don't add new geometry or AX plumbing alongside the existing ones.

## Common Pitfalls

### Pitfall 1: Release build has no secure timestamp, so notarisation fails
**What goes wrong:** `notarytool` rejects the app. **Why:** a plain `xcodebuild build` with manual Developer ID signing produced `Signed Time=Oct 24, 2026 at 11:52:53 AM` on `Pane.app`. Apple: "the presence of `Signed Time` in the output indicates the binary doesn't have a secure timestamp" [VERIFIED: local `codesign -dvv`; CITED: developer.apple.com "Resolving common notarization issues"]. **How to avoid:** `OTHER_CODE_SIGN_FLAGS="--timestamp"` for Release (in `project.yml` or on the command line), with a `Timestamp=` check in `release.sh`. **Warning sign:** the notary log says "The signature does not include a secure timestamp".

### Pitfall 2: Two consumers of `system.events`
**What goes wrong:** the Arranger misses closes or moves at random. **Why:** `StatusItemController` already iterates the stream (`StatusItemController.swift:47-51`). **How to avoid:** the Arranger shell is the only reader and fans out the inventory. **Warning sign:** a menu header count that disagrees with the layout.

### Pitfall 3: Rekey not applied to undo snapshots
**What goes wrong:** after a fallback ID is corrected, Undo makes the window vanish from its tile. **Why:** the snapshot revives the old identity, `requery` returns nil, and the window is applied as `.closed`. **How to avoid:** `World.rekey` rewrites the desks *and* `UndoHistory` (Pattern 3). **Test:** a fake scenario with `forceWindowIDFallback`, docking, a rekey, then undo.

### Pitfall 4: Active tap after Accessibility is revoked blocks clicks
**What goes wrong:** the user's mouse clicks stop working system-wide. **How to avoid:** the watchdog's trial `tapCreate` and immediate invalidation (Pattern 6), and also tear down the tap when `PermissionController` leaves `.ready` [CITED: Apple forum 735204].

### Pitfall 5: Tap source on the main run loop
**What goes wrong:** opening the status menu freezes drags and the system disables the tap. **How to avoid:** a dedicated tap thread (Pattern 6).

### Pitfall 6: Echo or double-click mistaken for a user resize
**What goes wrong:** a docked window's split jumps after Pane writes it, or after a title-bar double-click. **How to avoid:** the ±2 pt `lastApplied` echo rule, sessions only for the press window, and at least 3 pt of pointer travel (Pattern 1).

### Pitfall 7: `setShortcut(for:)` observer leak
See Pattern 9. **Warning sign:** memory or `NotificationCenter` observer count growing with each menu open.

### Pitfall 8: Gap-handle cursor via `.cursorUpdate` + `.activeAlways`
Unsupported per the SDK header (Pattern 8). Use `mouseEntered`/`mouseMoved` + `NSCursor.set()` and accept the arrow if the system ignores it.

### Pitfall 9: Gap handle across an absent child
**What goes wrong:** dragging the handle between children 0 and 2, while child 1 is minimised, moves weight into the invisible child. **Why:** `resizeBoundary(in:after:by:)` only moves weight between adjacent indices (`TreeEdits.swift:144-157`). **How to avoid:** add `resizeBetween(split, a, b, delta)` (moves weight only between `a` and `b`), or show no handle next to a non-taking-part child. Prefer the former.

### Pitfall 10: Undo moving floating windows back
See Pattern 3. `World.undo` keeps states but restores snapshot frames.

### Pitfall 11: Hide Desktop with a new window arriving
**What goes wrong:** there's nowhere to float a new window without overlapping docked tiles. **Resolution:** a new window while the Desktop is hidden shows the Desktop again and floats there [ASSUMED: A2].

### Pitfall 12: Edge-tiling conflict detected by key presence
**What goes wrong:** on macOS 15+, a missing key means "on", so the conflict is missed. On 14, a conflict alert would describe a feature that doesn't exist. **How to avoid:** gate on the OS version and treat absent as the documented default (Pattern 13).

### Pitfall 13: KeyboardShortcuts names are persistent
Default values are stored under `KeyboardShortcuts_<name>` in UserDefaults on first launch. Renaming a `Name` later orphans the stored value. Freeze the 33 names now.

### Pitfall 14: `terminateLater` waiting on async MainActor work
Use the bounded semaphore writes on the app threads (Pattern 11), not `await`s, during termination.

## Code Examples

### Event tap callback (compiled this session under PaneMac's Swift settings)
```swift
// Source: scratchpad apicheck/Sources/APICheck/main.swift, built with swift-tools 6.2, Swift 6 mode,
// .defaultIsolation(MainActor.self), NonisolatedNonsendingByDefault, InferIsolatedConformances: Build complete.
nonisolated final class TapBox: @unchecked Sendable {
    let zoomRects = OSAllocatedUnfairLock(initialState: [UInt32: CGRect]())
    let swallowing = OSAllocatedUnfairLock(initialState: false)
    var port: CFMachPort?
    let continuation: AsyncStream<(CGEventType, CGPoint, CGEventFlags, Int64)>.Continuation
    init(_ c: AsyncStream<(CGEventType, CGPoint, CGEventFlags, Int64)>.Continuation) { continuation = c }
}
let callback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<TapBox>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let windowID = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
    let point = event.location            // global top-left points, Pane's model space
    let flags = event.flags
    box.continuation.yield((type, point, flags, windowID))
    if type == .leftMouseDown, !flags.contains(.maskAlternate),
       let rect = box.zoomRects.withLock({ $0[UInt32(truncatingIfNeeded: windowID)] }), rect.contains(point) {
        box.swallowing.withLock { $0 = true }
        return nil                         // TILE-06: Pane toggles; ⌥ passes through (TILE-19)
    }
    if type == .leftMouseUp, box.swallowing.withLock({ let s = $0; $0 = false; return s }) { return nil }
    return Unmanaged.passUnretained(event)
}
let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
    | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                             eventsOfInterest: CGEventMask(mask), callback: callback,
                             userInfo: Unmanaged.passUnretained(box).toOpaque())
```
In production, the box must outlive the tap: retain it from the tap thread object, the same way `AXAppThread` keeps its refcon alive. That `event.location` is in global top-left coordinates is [ASSUMED]; verify it in the live spike against a fixture window frame.

### Hotkey names with fixed defaults (compiled this session)
```swift
// Key constants verified in KeyboardShortcuts 3.1.0 Key.swift: d(15) leftArrow(89) return(68) equal(72) zero(42)
extension KeyboardShortcuts.Name {
    static let dock = Self("dock", initial: .init(.d, modifiers: [.control, .option, .command]))
    static let moveLeft = Self("moveLeft", initial: .init(.leftArrow, modifiers: [.control, .option, .command, .shift]))
    static let snapMaximize = Self("snapMaximize", initial: .init(.return, modifiers: [.control, .option, .command]))
    static let growTile = Self("growTile", initial: .init(.equal, modifiers: [.control, .option, .command]))
    static let restoreAll = Self("restoreAll", initial: .init(.zero, modifiers: [.control, .option, .command]))
}
let item = NSMenuItem(title: "Dock Window", action: nil, keyEquivalent: "")
item.setShortcut(for: .dock)   // run output: keyEquivalent "d", modifierMask 0x1C0000 (⌃⌥⌘)
KeyboardShortcuts.onKeyDown(for: .dock) { /* dispatch(.dock) */ }
```
The other key constants in the UI-SPEC table also exist in `Key.swift`: `b c e f h i j k n p r s u x z one two three minus rightArrow upArrow downArrow` (lines 13-89) [VERIFIED: source].

### Current Space for a display (probed this session)
```swift
typealias CurrentSpace = @convention(c) (Int32, CFString) -> UInt64
// dlopen SkyLight (same path as SkyLightSpaces.swift:20), dlsym "SLSManagedDisplayGetCurrentSpace"
let uuid = CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())!.takeRetainedValue())!
let space = unsafeBitCast(dlsym(handle, "SLSManagedDisplayGetCurrentSpace")!, to: CurrentSpace.self)(connection, uuid)
// probe output on macOS 27.0.1: 6 (SLSCopyManagedDisplaySpaces "Current Space" id64 = 6, type 0)
```
Production code must nil-check `dlsym` (no `!`) and stay inside `SkyLightSpaces.swift` behind `Capabilities.isAvailable(.spaces)`.

### WindowManager preference read, and the write shape
```swift
let domain = "com.apple.WindowManager" as CFString
_ = CFPreferencesAppSynchronize(domain)
let value = CFPreferencesCopyAppValue("EnableTilingByEdgeDrag" as CFString, domain)   // nil = absent
// Turn Off:
CFPreferencesSetAppValue("EnableTilingByEdgeDrag" as CFString, kCFBooleanFalse, domain)
_ = CFPreferencesAppSynchronize(domain)
// Restore an originally absent key:
CFPreferencesSetAppValue("EnableTilingByEdgeDrag" as CFString, nil, domain)
```
For tests, make the domain injectable (for example `com.eightabyte.pane.tests.windowmanager`), so unit tests never touch the real domain.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `activate(options: .activateIgnoringOtherApps)` steals focus | Deprecated with no effect; cooperative activation | macOS 14 | Focus needs AXMain + AXRaise + `activate`, with an AX `kAXFrontmost` fallback (Pattern 15) |
| `NSCursor.resizeLeftRight` etc. | `NSCursor.columnResize` / `rowResize` / `frameResize(position:directions:)` | macOS 15 SDK (old ones `API_TO_BE_DEPRECATED`) | Use `#available(macOS 15, *)` if desired; old ones still compile at a 14 target |
| Sonoma "Click wallpaper to reveal desktop" | macOS 27 label "Click wallpaper to show desktop" | macOS 26/27 | UI copy note only |
| Edge tiling did not exist | `EnableTilingByEdgeDrag` / `EnableTopTilingByEdgeDrag`; macOS 27 label "Drag windows to left or right edge of screen to tile" | macOS 15 | Conflict detection is OS-gated |
| KeyboardShortcuts menus buffer hotkeys | 3.1.0 handles menu tracking with raw-key local monitors | 3.x | Disabling in `menuWillOpen` is still recommended by its docs |

**Deprecated/outdated:** `altool` notarisation (replaced by `notarytool`). `CGWindowListCreateImage` (STACK.md). `kCGEventTapOptionListenOnly` for this use, since it prompts for Input Monitoring.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | An active session tap sees `leftMouseDragged`/`leftMouseUp` during native title-bar drags, and `mouseEventWindowUnderMousePointer` is populated at mouse-down | Pattern 4 | Drag docking doesn't start. Mitigation: a Wave-1 live spike. Fallbacks: CG z-order hit test; AX moved hints |
| A2 | A new window while the Desktop is hidden re-shows the Desktop and floats there | Pitfall 11 | Behaviour differs from the user's expectation. **Needs user confirmation** |
| A3 | Rotate = transpose the split's subtree (toggle every axis below it) | Pattern 2 | Rotate feels different from the user's expectation. **Needs user confirmation** |
| A4 | After a native ⌥-zoom, a floating window keeps it (clamped into the Desktop); a docked window snaps back into its tile | Pattern 5 | TILE-19 on docked windows has no lasting effect. **Needs user confirmation** |
| A5 | The gap-handle resize cursor may not show while another app is active; the arrow cursor is acceptable for Phase 3 | Pattern 8 | A UI-SPEC row is unmet. UAT decides. A later private `SetsCursorInBackground` shim is out of scope |
| A6 | Stranded = under 50% of area or under 40×40 pt visible | Pattern 10 | Too strict or too lax recovery; tune in UAT |
| A7 | With Spaces lookup off, one desk per display; windows on other Spaces may be planned | Pattern 12 | Odd moves of other-Space windows in the fallback only |
| A8 | The Debug build registers `pane-debug://`, Release `pane://` | Pattern 16 | Dev-machine URL routing confusion only |
| A9 | Snap targets are inset by the gap inside the Desktop rect | Pattern 2 | Cosmetic |
| A10 | Absent `GloballyEnabled` = Stage Manager off; absent `EnableTopTilingByEdgeDrag` = on (macOS 15+) | Pattern 13 | A missed or false conflict line; read-back still guards writes |
| A11 | WindowManager adopts direct CFPreferences writes live | Pattern 13 | Turn Off falls back to System Settings + N7 (designed path) |
| A12 | Pressing Finder's ⌘N menu item through AX works while Finder is inactive | Pattern 14 | Finder split falls back to `NSWorkspace.open`; live UAT |
| A13 | Space IDs (`id64`) are stable for the login session, so a Pane relaunch re-keys desks correctly | Pattern 12 | SAFE-06 desks don't match after relaunch. Phase 8 handles reboot |
| A14 | The user Pause reason is not persisted across relaunch | Pattern 1 | Minor |
| A15 | The Desktop has no minimum beyond its floating windows' minimums (1×1 when empty) | Pattern 2 | The Desktop can shrink to a sliver when many windows dock |
| A16 | `CGEvent.location` is in global top-left points (no flip) | Code Examples | Preview offset bugs; one fixture spike catches it |
| A17 | XcodeGen `info:` properties merge with `GENERATE_INFOPLIST_FILE` | Pattern 16 | URL scheme not registered; check with `plutil -p` |
| A18 | Apple Events from a hardened-runtime app need `com.apple.security.automation.apple-events` | Alternatives | Only affects the rejected alternative |

## Open Questions (RESOLVED)

1. **How does Pane tell its own writes from user drags and app moves?** RESOLVED: the `lastApplied` ±2 pt echo rule plus press-window, travel and button-state gating (Pattern 1 table).
2. **Green-button detection without AX in the callback?** RESOLVED: cached button rects (offset from the window origin) in a lock, keyed by `mouseEventWindowUnderMousePointer`. Swallow the down/up pair unless ⌥ (Pattern 5). Residual uncertainty is carried as A1.
3. **Does notarisation need `disable-library-validation` for SkyLight?** RESOLVED: no. Library validation allows Apple-signed libraries [CITED: Apple entitlement doc], and a Developer ID + runtime probe loaded SkyLight. The real blocker is the missing secure timestamp (Pitfall 1). The first `release.sh` run is still the final proof (CONTEXT D).
4. **Do WindowManager writes apply live?** RESOLVED as a design: write, read back after 1 s, deep link + N7 on mismatch, never `killall`. Live adoption carried as A11.
5. **Exact WindowManager keys?** RESOLVED: read on this Mac (Pattern 13 table). Absent-key defaults partly carried as A10.
6. **Gap-handle cursor while inactive?** RESOLVED as a design: no `.cursorUpdate`; use `mouseEntered`/`mouseMoved` + `NSCursor.set()`. Outcome carried as A5 (UAT).
7. **Fullscreen reserved tile as a drop target (UI-SPEC) vs D-17?** RESOLVED: follow D-17. The leaf has no rect while fullscreen (Pattern 12).
8. **Schema version for the Desktop leaf?** RESOLVED: keep 1 and update the test fixtures. No production v1 file exists (verified).
9. **Finder split mechanism and permission prompts?** RESOLVED: AX menu press, no Apple Events, no prompt (Pattern 14). Inactive-press behaviour carried as A12.
10. **Current Space per display?** RESOLVED: `SLSManagedDisplayGetCurrentSpace`, probed (Pattern 12).
11. **Hotkeys while the menu is open?** RESOLVED: `disable` in `menuWillOpen`, `enable` in `menuDidClose` (UI-SPEC), consistent with the 3.1.0 source.
12. **New window while the Desktop is hidden; rotate semantics; ⌥-zoom on docked windows?** Carried as A2, A3, A4 (user confirmation).
13. **Notary credentials present on this Mac?** Not probed, to avoid using credentials. Carried as a `checkpoint:human-action` in the release plan (`xcrun notarytool store-credentials pane-notary`).
14. **Event-tap visibility during native drags?** Carried as A1, with a Wave-1 live spike (manual, minutes).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| macOS | everything | ✓ | 27.0.1 (26A434) | — |
| Xcode / Swift | build | ✓ | Xcode 27.1 (27A9275), Swift 6.4 | — |
| XcodeGen | `generate.sh`, `release.sh` | ✓ | 2.46.0 | — |
| Developer ID Application identity | signing | ✓ | "Developer ID Application: Ken Scott (S2K7P43927)" | — |
| `notarytool` / `stapler` | release | ✓ | 1.1.3 (42) | — |
| Notary keychain profile `pane-notary` | release | unknown (not probed) | — | Human-action checkpoint: `xcrun notarytool store-credentials` |
| create-dmg | release DMG | ✗ | — (brew bottle 1.3.0) | `brew install create-dmg`, or `hdiutil create -srcfolder … -format UDZO` + `codesign` + `notarytool` + `stapler` |
| xcbeautify | build logs | ✗ | — | `build-debug.sh` already falls back to raw output |
| `gh` | manual pre-release upload | ✓ | present | Upload via github.com |
| GitHub network for SwiftPM | KeyboardShortcuts resolve | ✓ | resolved 3.1.0 this session | — |
| SkyLight symbols | current Space | ✓ | all resolve on 27.0.1 | `spaceID = nil` |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** create-dmg (hdiutil), xcbeautify (raw logs). Notary credentials need a human-action checkpoint.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (toolchain-bundled), as in Phases 1–2 |
| Config file | none (SwiftPM) |
| Quick run command | `swift test --filter 'PaneModelTests|PaneEngineTests'` (measured 4.2 s incremental, 234 tests) |
| Full suite command | `swift test && swift test -c release -Xswiftc -enable-testing` |
| Trusted integration | `swift test --filter PaneMacIntegrationTests` (auto-skips without AX trust, `IntegrationSupport.swift:8`) |
| Guardrail | `scripts/check-no-appkit.sh` |

Test types: **unit** = pure PaneModel/PaneEngine functions. **fake** = `Arranger` + `FakeWindowSystem` scenarios with synthetic pointer events and an injected clock. **live-fixture** = `PaneMacIntegrationTests` against `PaneFixtureApp` with real AX. **manual** = human UAT (marked **HUMAN**).

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TILE-01 | Drop target → dry-run preview frame = committed frame; nesting; WYSIWYG release; dwell 150 ms | unit + fake | `swift test --filter "DesktopLeafTests|ArrangerDragTests"` | ❌ Wave 0 |
| TILE-01 | Real title-bar drag docks with preview | manual **HUMAN** | — | n/a |
| TILE-02 | ⇧ pressed mid-drag → no preview, floats at release frame clamped into Desktop | fake | `swift test --filter ArrangerDragTests` | ❌ |
| TILE-03 | Close of docked window reflows neighbours (setFrames emitted) | fake + live-fixture | `swift test --filter "ArrangerLifecycleTests|ArrangeIntegrationTests"` | ❌ |
| TILE-04 | Gap change re-resolves; allow-list 0/4/8/12/16/24 | unit + fake | `swift test --filter "GapPreferenceTests|ArrangerCommandTests"` | ❌ |
| TILE-05 | Handle geometry incl. T-junction and absent sibling; one undo step per drag | unit + fake | `swift test --filter "GapHandleGeometryTests|ArrangerGapDragTests"` | ❌ |
| TILE-05 | Handle hover/cursor while another app is frontmost | manual **HUMAN** | — | n/a |
| TILE-06 | Green-button input toggles dock/float; tap hit-test pure function | unit + fake | `swift test --filter "GreenButtonHitTests|ArrangerCommandTests"` | ❌ |
| TILE-06/19 | Real green click toggles; ⌥-click zooms natively | manual **HUMAN** | — | n/a |
| TILE-07 | `windowCreated` → floating, clamped into Desktop rect; never docked | fake | `swift test --filter ArrangerLifecycleTests` | ❌ |
| TILE-08 | Paused: no `perform`, drags ignored, lifecycle still applied; Resume re-plans | fake | `swift test --filter ArrangerPauseTests` | ❌ |
| TILE-09 | Every `Command` reachable; availability rules; menu/hotkey/URL share dispatch; 33 unique names, no reserved chords (⌃⌥⌘8 , .) | unit | `swift test --filter "CommandTests|HotkeyTableTests"` | ❌ |
| TILE-10 | No ScreenCaptureKit import in Sources | unit (grep guard) | `swift test --filter NoScreenCaptureTests` | ❌ |
| TILE-10 | Full tiling with Screen Recording denied | manual **HUMAN** | — | n/a |
| TILE-11 | `swap` edit; ⌘-release over tile swaps; `swapPrevious` uses MRU | unit + fake | `swift test --filter "LayoutEditTests|ArrangerDragTests"` | ❌ |
| TILE-12 | balance/rotate/flip invariants + rotate twice = identity (no parent merge) | unit | `swift test --filter LayoutEditTests` | ❌ |
| TILE-13 | Neighbour lookup ties → MRU; move docks at near edge; grow/shrink beeps at limit | unit + fake | `swift test --filter "NeighbourTests|ArrangerCommandTests"` | ❌ |
| TILE-14 | Snap rects inside Desktop rect for 13 targets | unit | `swift test --filter SnapTests` | ❌ |
| TILE-15 | Hide parks Desktop windows (save `.now` before park), docked tiles take space; Show un-parks; URL | fake | `swift test --filter "ArrangerDesktopTests|PaneURLTests"` | ❌ |
| TILE-15 | `park` real move keeps size, sliver visible | live-fixture | `swift test --filter FocusParkIntegrationTests` | ❌ |
| TILE-16 | Arrange All in screen order, leftovers → N5; Float All one undo step → N4 | fake | `swift test --filter ArrangerCommandTests` | ❌ |
| TILE-17 | Expectation docks the next Finder `windowCreated`; deadline → N9 | fake | `swift test --filter ArrangerFinderTests` | ❌ |
| TILE-17 | Real Finder window opens and docks | manual **HUMAN** | — | n/a |
| TILE-18 | Exclusion toggle floats that app's docked windows; commands dropped | fake | `swift test --filter "ArrangerExclusionTests|ExclusionScenarioTests"` | ❌ / ✅ |
| TILE-20 | Minimise → neighbours take space; deminimise → same rect | fake + live-fixture | `swift test --filter "ArrangerLifecycleTests|ArrangeIntegrationTests"` | ❌ |
| WIN-07 | Fullscreen → slot kept, no desk for fullscreen Space; exit → same rect | fake (+ manual **HUMAN** real fullscreen) | `swift test --filter ArrangerSpacesTests` | ❌ |
| SAFE-01 | Termination plan: parked/off-screen → home clamped; docked untouched; per-app deadline | unit + live-fixture | `swift test --filter "RecoveryTests|QuitRestoreIntegrationTests"` | ❌ |
| SAFE-01 | Real ⌘Q / `killall Pane` restore | manual **HUMAN** | — | n/a |
| SAFE-02 | Stranded rule; crash-loop rule with injected clock; dirty flag | unit + PaneMac store | `swift test --filter "RecoveryTests|LayoutStoreTests"` | ❌ |
| SAFE-02 | Real `kill -9` then relaunch → windows back, N2; twice in 60 s → paused, N3 | manual **HUMAN** | — | n/a |
| SAFE-03 | Restore all (even paused) → N6 counts; `pane://restore` strict parse | unit + fake | `swift test --filter "PaneURLTests|ArrangerRestoreTests"` | ❌ |
| SAFE-04 | Conflict policy: detection per OS version, originals incl. absent, restore deletes absent keys, read-back mismatch → N7 | unit (injected prefs store, test domain) | `swift test --filter "ConflictPolicyTests|WindowManagerSettingsTests"` | ❌ |
| SAFE-04 | Real Turn Off / Restore of Stage Manager, edge tiling, click wallpaper | manual **HUMAN** | — | n/a |
| SAFE-06 | Save → decode → re-attach by identity; synthetic IDs never matched; unmatched → Desktop; corrupt → `.corrupt` | unit + PaneMac store + fake | `swift test --filter "PersistenceTests|LayoutStoreTests|ArrangerRestoreTests"` | ✅ (update) / ❌ |
| SAFE-06 | Real quit + relaunch with apps running restores tiles | manual **HUMAN** | — | n/a |
| (obligation) | `windowRekeyed` re-points desks and undo history | unit + fake | `swift test --filter "RekeyTests|LifecycleSyncTests"` | ❌ / ✅ (extend) |
| (release) | Notarised, stapled, `spctl` "Notarized Developer ID"; secure timestamp present | manual script **HUMAN** (credentials) | `scripts/release.sh` | ❌ |
| (spike) | Tap sees drags; window field populated; `event.location` space (A1, A16) | manual **HUMAN** (5 min) | Debug build + log category `tap` | n/a |

### Sampling Rate
- **Per task commit:** `swift test --filter 'PaneModelTests|PaneEngineTests'` (about 5 s) + `scripts/check-no-appkit.sh`
- **Per wave merge:** `swift test` and `swift test -c release -Xswiftc -enable-testing`, plus `swift test --filter PaneMacIntegrationTests` from a trusted terminal
- **Phase gate:** full suite green, signed Debug build verified with `scripts/build-debug.sh`, `release.sh` run once successfully, and the HUMAN UAT rows signed off before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `Package.swift`: KeyboardShortcuts 3.1.0 (`exact:`) on PaneMac; `Package.resolved` committed
- [ ] `FakeWindowSystem`: `userMove(_:to:)` / `userResize` (frame change emitted as `windowMoved/Resized` with **no** `frameApplied`), `perform` for `park`/`focus`/`raise`, `setFullscreen(_:)`, a current Space per display
- [ ] `PaneFixtureApp`: stdin commands `fullscreen <i>`, `exit-fullscreen <i>`, `zoom <i>`; report the frontmost window after `focus`
- [ ] `PersistenceTests.swift` fixture helpers emit a Desktop node
- [ ] Test-only CFPreferences domain + an injectable `PreferencesStore` protocol for `WindowManagerSettings`
- [ ] Temp-directory helper for `LayoutStoreTests` (reuse the `MinimumHintsStoreTests` pattern)
- [ ] `brew install create-dmg` (checkpoint) and `notarytool store-credentials pane-notary` (human action)

## Security Domain

`security_enforcement: true`, ASVS level 1, block on high.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Local app, no accounts |
| V3 Session Management | no | — |
| V4 Access Control | yes (OS) | Hardened runtime; no new entitlements (no `disable-library-validation`, no `automation.apple-events`); TCC Accessibility only; Release without `get-task-allow` |
| V5 Input Validation | yes | `layout.json` (size cap, version probe, `World.decode` validation, finite in-range home frames, set-aside); strict `pane://` parser; gap allow-list; WindowManager values type-checked as `CFBoolean`; AX strings untrusted |
| V6 Cryptography | no | Code signing and notarisation only; publish the DMG sha256 |
| V7 Error Handling & Logging | yes | `os.Logger`; never log titles; the tap never logs events; no `keyDown` in the tap mask |
| V12 Files & Resources | yes | Only `~/Library/Application Support/Pane/`; atomic writes; never overwrite a newer-schema file |
| V14 Configuration | yes | Secure timestamp check, `codesign --verify --strict`, `spctl` in `release.sh`; fixed bundle IDs |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Web page or app spamming `pane://toggle-desktop` / `split-finder` | DoS / Tampering | Three parameterless commands only, strict parse, 1/s rate limit, no URL data passed anywhere (Pitfall 21) |
| Tampered `layout.json` moving windows off-screen or huge | Tampering / DoS | `World.decode` validation, `maxEncodedBytes`, home frames clamped on-screen before use, set-aside on any doubt |
| Active tap left running after Accessibility revocation blocks input | DoS | Watchdog trial `tapCreate`, invalidate at once, teardown on permission loss |
| Slow tap callback lagging system input | DoS | Copy-and-return callback, dedicated thread, re-enable on timeout |
| Writing other apps' preferences | Tampering | Fixed key allow-list in one domain, typed values, originals recorded once, restore deletes absent keys, no `killall` |
| Crash loop repeatedly moving windows | DoS | Second crash within 60 s → start paused (N3) |
| Supply chain (dependency, release artifact) | Tampering | `exact: "3.1.0"` + committed `Package.resolved` (revision `772133d…`); notarised + stapled DMG; published sha256 |
| Keystroke capture concerns | Information disclosure | Tap mask excludes keyboard events; hotkeys via Carbon registration only |

## Sources

### Primary (HIGH confidence)
- Codebase, read this session: `Sources/PaneModel/{LayoutTree,TreeEdits,DropZones,DesktopLayer,World,Resolve,Undo,Persistence,IDs,Geometry}.swift`, `Sources/PaneEngine/{WindowSystem,WindowTracker,LifecycleSync,ExclusionFilter,Coordinates,WindowSnapshot}.swift`, `Sources/PaneMac/{AXWindowSystem,MinimumHintsStore,PaneMacApp,Displays}.swift`, `Sources/PaneMac/AX/{AXAppThread,FrameWriter,AXSnapshotReader}.swift`, `Sources/PaneMac/Shell/StatusItemController.swift`, `Sources/PanePrivate/*`, `Sources/PaneTestSupport/FakeWindowSystem.swift`, `xcode/project.yml`, `scripts/*.sh`, `Tests/PaneModelTests/PersistenceTests.swift`
- Local probes (scratchpad): `defaults read com.apple.WindowManager`; CFPreferences read and same-value write; Developer ID + hardened-runtime `dlopen` of SkyLight and `SLSManagedDisplayGetCurrentSpace`/`SLSCopyManagedDisplaySpaces`; `codesign -dvv` of the existing Release/Debug apps; `lipo -archs`; KeyboardShortcuts 3.1.0 + tap + NSPanel compile/run; NSCursor at a 14 target with `-warnings-as-errors`; `DesktopSettings.appex` `Localizable.loctable` labels; `otool -L` of `DesktopSettings`
- macOS 27 SDK headers: `CGEventTypes.h` (fields 91/92, tap options), `NSTrackingArea.h:29`, `NSCursor.h`, `AXAttributeConstants.h`, `AXActionConstants.h`
- KeyboardShortcuts 3.1.0 source via `gh api` (`Package.swift`, `Name.swift`, `KeyboardShortcuts.swift`, `HotKey.swift`, `NSMenuItem++.swift`, `Key.swift`)
- Apple developer documentation JSON: `security/resolving-common-notarization-issues` (secure timestamp, Signed Time); `bundleresources/entitlements/com.apple.security.cs.disable-library-validation` (library validation scope); `appkit/nsapplication/activationoptions/activateignoringotherapps` (deprecated macOS 14, no effect)
- Rectangle source (MIT) via `gh api`: `Rectangle/Snapping/SnappingManager.swift`, `Rectangle/Utilities/EventMonitor.swift`
- AeroSpace source (MIT) via `gh api`: `Sources/AppBundle/tree/MacApp.swift` (`nativeFocus`, `setAxFrameForTermination`)
- create-dmg README v1.3.0 via `gh api`

### Secondary (MEDIUM confidence)
- [pkdone/.dotfiles-mac PR #15](https://github.com/pkdone/.dotfiles-mac/pull/15): WindowManager applies the domain live; `EnableTilingByEdgeDrag` unset = On
- [nix-darwin option EnableStandardClickToShowDesktop](https://mynixos.com/nix-darwin/option/system.defaults.WindowManager.EnableStandardClickToShowDesktop): false = Only in Stage Manager, default true
- [qiita P-man_Brown](https://qiita.com/P-man_Brown/items/509c432f4a56160eaa7d) and [Hexnode](https://www.hexnode.com/mobile-device-management/help/script-to-enable-disable-stage-manager-on-mac/): `GloballyEnabled` toggles Stage Manager, applied immediately
- [Apple Developer Forums 735204](https://developer.apple.com/forums/thread/735204): active tap + revoked Accessibility; trial `tapCreate` detection
- [Apple Developer Forums 738051](https://developer.apple.com/forums/thread/738051): inactive app cursor changes ignored
- [Apple Developer Forums 122492](https://developer.apple.com/forums/thread/122492) (via search): listen-only tap → Input Monitoring prompt

### Tertiary (LOW confidence)
- [JUCE forum](https://forum.juce.com/t/making-a-floating-window-that-doesnt-bring-the-application-to-the-front/36963), [Electron #35815](https://github.com/electron/electron/issues/35815): `.nonactivatingPanel` must be set at creation
- [DEV Community](https://dev.to/appish/mac-window-tiling-shortcuts-not-working-whats-actually-going-on-and-how-to-fix-it-4ckc): `killall WindowManager` as a user fix (not used)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. KeyboardShortcuts compiled under PaneMac settings; tools verified locally; create-dmg not installed.
- Architecture: HIGH for the model and engine patterns, which extend tested Phase 1–2 contracts. MEDIUM for tap visibility during native drags (A1) and focus under cooperative activation.
- Pitfalls: HIGH for Pitfalls 1, 2, 3, 7, 8, 9 (verified in code, SDK or probe). MEDIUM for 4, 5 (forum and prior art).
- Conflicts (SAFE-04): HIGH for key names on macOS 27; MEDIUM for live adoption and absent defaults.

**Research date:** 2026-10-25
**Valid until:** 2026-11-24 (30 days). Re-check the WindowManager keys and SkyLight symbols on any macOS point release.
