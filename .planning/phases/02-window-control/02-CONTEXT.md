# Phase 2: Window Control - Context

**Gathered:** 2026-10-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Connect Pane to real macOS windows. A minimal signed menu-bar app (`Pane.app`) guides the user through the Accessibility permission, tracks every window of every running app through per-app non-blocking AX threads, classifies each window (dockable vs never-dock, native tabs as one window), moves and resizes windows on any display while learning real minimum sizes, honours a user exclusion list, and only treats a window as closed when two sources confirm it. Private APIs load through a `PanePrivate` dlsym layer with fallbacks. An `AXWindowSystem` implements Phase 1's draft `WindowSystem` protocol, and a `FakeWindowSystem` supports headless tests. No tiling, drop preview or zoom yet (Phase 3+).

</domain>

<decisions>
## Implementation Decisions

### App shell, permission & signing
- Phase 2 ships a minimal menu-bar `Pane.app` (LSUIElement) with a debug menu: live tracked-window list, "Nudge focused window" (move/resize test), "Freeze test" helper, and "Don't arrange <frontmost app>". No tiling.
- Permission flow: one onboarding window explains Accessibility; a button opens System Settings ▸ Privacy & Security ▸ Accessibility; Pane polls `AXIsProcessTrusted()` every 1 s and advances by itself. Stale grant (trusted but AX calls fail) is detected by a real AX probe and explained, with a "Reset permission" button that runs `tccutil reset Accessibility <bundle id>` and tells the user to re-grant.
- All builds (debug included) are signed with the developer's **Developer ID Application** identity (team `S2K7P43927`, hardened runtime) so TCC grants survive rebuilds. Never ad-hoc sign.
- Bundle IDs: release `com.eightabyte.pane`; debug `com.eightabyte.pane.debug` (separate TCC entries).
- App bundle produced by XcodeGen `project.yml` around the SwiftPM targets (per STACK.md); the `.xcodeproj` is generated, never committed.

### Window tracking & classification
- Track every window of every regular-activation-policy app. Each window is classified **dockable** (AXStandardWindow) or **never-dock** (dialog, sheet, popover, PiP, utility/floating panel, splash). Never-dock windows are tracked but never arranged. Minimised windows are tracked with lifecycle state `absent`.
- Classifier is tested against a committed corpus of recorded AX dumps: a `pane-dump` tool records AX attribute trees from real apps on this Mac into JSON fixtures with titles and other personal strings redacted. Initial corpus: Finder, Safari, Terminal, one Electron app, one Java app, System Settings, an Office app if installed.
- Native tabs: windows of the same app sharing a tab group (`AXTabGroup`, or same frame with tab siblings) count as one tracked window, represented by the visible tab.
- Close confirmation needs two sources: AX element invalid (`kAXErrorInvalidUIElement`) **and** the window id absent from the CG/SkyLight window list. A timeout never counts as closure. Reconciliation pauses during screen lock and sleep; a full refresh runs after unlock/wake. AX notifications are hints that trigger a cancellable refresh.
- OS lifecycle changes reach the model only through `World.apply` (never `World.edit`), per the Phase 1 contract; `.closed` needs no valid desk key.
- After `World.undo` returns restored windows, the engine re-queries the OS for each and reports its real state via `World.apply` (Phase 1 obligation, commit c403f45).

### Exclusions, minimums & testing
- Exclusion list: bundle IDs in UserDefaults; edited in Phase 2 via the menu item "Don't arrange <frontmost app>" (toggle). Full Settings UI is Phase 9. No hard-coded default exclusions.
- Learned minimums: per window in memory, plus per-bundle-ID hints persisted as JSON in `~/Library/Application Support/Pane/`.
- Testing: unit tests against `FakeWindowSystem` simulate hung apps, slow apps, window-id churn, refusing sizes and lock-screen blanking. A small integration-test target exercises real AX only when the process is trusted (skips otherwise). Real `kill -STOP`, lock-screen, sleep and multi-display checks are a manual UAT checklist the developer runs.
- Private APIs: `PanePrivate` target, one file per API, every symbol loaded via `dlopen`/`dlsym` into optional function pointers; a capability registry logged at launch. Debug launch flag `--disable-private=<name>` (e.g. `AXWindowID`) forces a capability off; without `_AXUIElementGetWindow` windows are matched by pid + frame + title.

### Architecture (from research, locked)
- Per-app AX thread with its own CFRunLoop and observers; `AXUIElementSetMessagingTimeout` ~1 s per app; an unresponsiveness tracker marks degraded apps; a newer setFrame replaces any queued one for the same window.
- Frame writes are size → position → size with `AXEnhancedUserInterface` temporarily off; every write is read back.
- One tested coordinate-conversion boundary (Pane model is top-left global points; AppKit is bottom-left) and displays matched by UUID.

### Claude's Discretion
- Exact file layout inside the new targets (`PanePrivate`, `PaneMac`, `PaneApp`, test support)
- Refresh debounce intervals, degraded-app thresholds, polling intervals other than the 1 s permission poll
- Debug menu wording and layout

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PaneModel`: `World`, `Desk`, `DeskKey(displayUUID:spaceID:)`, `WindowRef` (identity `{windowID, pid, bundleID}` + hints), lifecycle states, `World.apply`, `World.undo -> [WindowRef]?`, `Rect/Size/Point` (top-left points).
- `PaneEngine/WindowSystem.swift`: draft async `WindowSystem` protocol with `DisplayInfo`, `WindowInfo`, `WindowInventory`, `WindowEvent`, `WindowCommand`. Phase 2 implements and may revise it.
- `scripts/check-no-appkit.sh` + `NoAppKitTests`: must keep passing; AppKit is allowed only in the new Mac/App targets.

### Established Patterns
- Swift 6 language mode, tools-version 6.2, macOS 14; Swift Testing; TDD with RED/GREEN commits; validation after every edit in all builds.
- Phase 1 work lives on branch `gsd/phase-01-layout-model` (main is protected).

### Integration Points
- Phase 3 consumes `AXWindowSystem` + `FakeWindowSystem` for drag-to-dock, gaps and reflow.
- Phase 4 consumes window ids and frames for snapshots.

</code_context>

<specifics>
## Specific Ideas

- Clean-room rule: AeroSpace (MIT) is the closest prior art for per-app AX threads and AX dumps; read for ideas, write fresh code. Loop is GPL: read the dlsym loader pattern, do not copy.
- The developer has a Developer ID Application identity, so notarisation work in Phase 3/9 is unblocked.

</specifics>

<deferred>
## Deferred Ideas

- Settings window for the exclusion list (Phase 9)
- Multi-display layout persistence and Spaces keying (Phase 6); Phase 2 only matches displays by UUID and converts coordinates
- Fullscreen tile return (WIN-07, Phase 3)

</deferred>
