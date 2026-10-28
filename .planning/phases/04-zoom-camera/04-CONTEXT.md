# Phase 4: Zoom Camera - Context

**Gathered:** 2026-10-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Zoom out to see every window on a display, zoom in to any node, ⌘⇧-drag a rectangle to zoom to it, back/forward through past views, pan to a neighbouring area, and frame the focused window or the Desktop on their own. Only a snapshot overlay animates; real windows get one AX write when the camera settles. Screen Recording is optional (app colour + icon fallback). Turning zoom off leaves Phase 3 tiling exactly as it is. Gestures are Phase 5; the all-displays overview and Spaces bar are Phase 6; saved views are Phase 8.

</domain>

<decisions>
## Implementation Decisions

### A. Camera model
- Camera targets are `NodeID`s (ROADMAP scope note). Zooming in to node X resolves X's subtree at full display size. Windows outside the view are parked by moving them to a screen corner at their own size, never shrunk. The home view ("everything") is exactly the Phase 3 layout.
- With zoom on, a drop that doesn't fit at the home view is accepted: the window shows as a collapsed app-colour block (ZOOM-13) until you zoom in. With zoom off, Phase 3's blocked-preview refusal stays.
- The full-screen overlay is shown only while the camera moves and until settle. Collapsed tiles get small persistent click-through panels (the gap-handle pattern) so ZOOM-13's double-click works at rest.
- Animation: about 250 ms ease-out, overlay only. At settle, one AX write per changed, visible window. Reduce Motion: crossfade instead of a zoom.

### B. Snapshots and Screen Recording
- One-shot `SCScreenshotManager` captures of on-screen windows at zoom start, before parking, at on-stage pixel size. Cached per window ID and refreshed after settle. No `SCStream`, so the system "sharing" indicator never shows.
- Screen Recording is never requested at onboarding. It is asked the first time the user zooms, with a one-line explainer. The fallback is used until it's granted, and there is no re-prompt loop. Revoking it mid-session falls back silently.
- Fallback tile: the app's dominant icon colour fill, the app icon centred, the window title below.
- ScreenCaptureKit is confined to one file, `Sources/TransomMac/Zoom/SnapshotCapture.swift`. `NoScreenCaptureTests` is narrowed to allow only that file, so TILE-10 (tiling never needs Screen Recording) still holds.

### C. Input and hotkeys
- The ⌃⌥⌘ base stays, using keys free in the Phase 3 table: O = zoom out to everything, `,` / `.` = step out / in, `[` / `]` = back / forward, M = frame focused window, G = frame Desktop. Pan keys for ZOOM-09 are fixed in the UI-SPEC from the remaining free keys. (`=` and `-` are already grow/shrink.)
- ZOOM-08: a minimal "Shortcuts" window with KeyboardShortcuts `Recorder` rows for every hotkey, Phase 3's included. The Phase 9 Settings window absorbs it later.
- ⌘⇧-drag rectangle zoom goes through the existing `InputTap`. The rubber band is drawn in the overlay. Mouse events are consumed only when ⌘⇧ is held at mouse-down. Esc cancels (ZOOM-12).
- With zoom on, double-clicking a window's title bar frames it and toggles back (ZOOM-10), intercepted in the tap. A preference hands double-click back to macOS's own action. Double-clicking the Desktop frames the Desktop (ZOOM-11).
- Clicking a window in a zoomed view zooms in to it and focuses it (ZOOM-6).
- Every navigation action also has a `transom://` URL (ZOOM-09/10/11), through `TransomURL` and the existing `Command` bus.

### D. Spike, scope and safety (Mode: mvp)
- Plan 1 is a feasibility spike with go/no-go gates, run before anything else is built:
  - settle ≤500 ms for 15 real windows including Electron
  - no visible stale-layout flash
  - a 1-hour soak with WindowServer RSS growth under 200 MB
  - Core Animation holding 100+ snapshot layers smoothly
  - terminal re-wrap, and the overlay's window level versus open menus, checked and reported
- Parking safety: the layout is saved immediately before any window is parked (Phase 3 rule). Parked windows return on quit, after a crash and via Restore All Windows. `kill -9` while zoomed is a UAT item.
- Zoom off: a menu toggle plus a preference. When off, the overlay is never created and ScreenCaptureKit is never touched, giving exactly Phase 3 behaviour (success criterion 5).
- One camera and one back/forward stack per display: 50 entries of `NodeID`s, skipping entries whose node no longer exists. Zoom acts on the display under the pointer.

### E. Post-research decisions (2026-10-27)
- When a window outside the current view gets focus (Cmd-Tab, Dock click) or a new window opens, the camera widens to the smallest view containing both the current view and that window (RESEARCH open question 1).
- Spike environment: install VS Code in the Tart VM for the spike's Electron settle gate. All spike runs stay in the VM; no host live runs. Core Animation numbers come from a virtual GPU and are treated as pessimistic (RESEARCH open question 4).
- Literal UI-SPEC defaults accepted for RESEARCH open questions 2, 3 and 5:
  - only drops and keyboard Dock/Move collapse a window
  - an OS-caused loss of room still floats the window, as in Phase 3
  - grow/shrink/rotate/flip/balance keep refusing when a window wouldn't fit
  - the parking corner stays at the live-verified `visibleFrame` bottom corners

### Claude's Discretion
- Camera/Navigator internals in TransomEngine (must stay AppKit-free and headless-testable).
- Parking corner and offsets, snapshot cache size and refresh policy, capture concurrency limit (STACK.md suggests 4–6).
- Exact overlay window level, and pan key choice within the UI-SPEC.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Planner` (`Sources/TransomEngine/Planner.swift`) already produces `FramePlan { frames, parks, unfit, desktopRect }`. Parking for a hidden Desktop exists, and the camera extends it.
- `Hotkeys.swift` registers KeyboardShortcuts names with stable IDs, ready for a `Recorder` UI.
- `InputTap`, `DragFramePoller`, `GreenButton` (TransomMac/Input) handle global mouse and modifier input.
- Overlay panels: `PreviewPanel`, `GapHandlePanels`, `Toast`, `NoticeQueue` (TransomMac/Overlay): click-through non-activating NSPanel patterns.
- `TransomURL` + `Command` / `Arranger+Commands` form the command bus for hotkeys, URLs and the menu.
- `Recovery`, `LayoutRestore`, `LayoutStore`: crash-safe home frames and restore-on-quit (SAFE-01/02/06).
- `Capabilities` (TransomPrivate): capability registry to log ScreenCaptureKit availability and permission.

### Established Patterns
- Model/Engine are AppKit-free (`scripts/check-no-appkit.sh` runs inside `swift test`).
- Swift Testing with `FakeWindowSystem` for headless engine tests, and live tests gated by `TRANSOM_LIVE` in the Tart VM.
- Every refusal and notice is logged (VNC can't show toasts).
- A plan's `swift test --filter` gate must show a non-zero executed count.

### Integration Points
- `ArrangeController` / `Arranger`: settle writes go through the same frame-write path, tagged so they aren't mistaken for user drags.
- `NoScreenCaptureTests` must be narrowed to the single SnapshotCapture file.
- Menu (`Shell/StatusItemController`, `CommandMenu`): Zoom toggle, Shortcuts window entry.

</code_context>

<specifics>
## Specific Ideas

- Research scope for the spike comes from ROADMAP: settle latency with Electron-heavy windows, terminal re-wrap, represented-state UX, ScreenCaptureKit memory growth (soak), overlay level versus menus, Core Animation with 100+ layers.
- PITFALLS 3 and 9 apply directly: stranded parked windows, and resize-storm/capture cost. Resize only changed, visible targets; move rather than shrink off-view windows.

</specifics>

<deferred>
## Deferred Ideas

- Remote control of Transom from a phone (Bonjour + command bus). Tabled by the user on 2026-10-27 and recorded in memory; a candidate phase after Phase 8.

</deferred>
