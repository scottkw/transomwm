# Phase 6: Overview, Spaces & Displays - Context

**Gathered:** 2026-10-31
**Status:** Ready for planning

<domain>
## Phase Boundary

An overview that shows every window on every display and Space, with a Spaces strip along the top, where clicking a window goes to it (OVER-01). An opt-in Mission Control takeover so F3 / ⌃↑ open the overview, with the system shortcuts restored after a crash (OVER-02, OVER-03). One layout per display and per Space that survives Space switches, unplug/re-plug and sleep/wake, with "Displays have separate Spaces" on or off (OVER-04, OVER-05). Layout sets remembered per display arrangement and switched automatically on dock/undock (OVER-06).

Also in scope (roadmap scope notes): build the `SpacesProvider` on the existing read-only `SkyLightSpaces` (02-14, capability `Spaces`) rather than re-adding it; a public-API co-visibility fallback map of window→Space; and closing deferred G-03-9 (a window whose only CG entry has no Space counts as closed), see `.planning/debug/g-03-9-closed-safari-lingers.md`.

Out of scope: creating/deleting Spaces, moving windows between Spaces, taking over ⌃←/→ Space switching, a Settings window (Phase 9).

</domain>

<decisions>
## Implementation Decisions

### Overview look and interaction
- D-01: The overview is a new command, **Show Overview**, on its own ⌃⌥⌘ hotkey (a free key, rebindable in the Shortcuts window). ⌃⌥⌘O keeps its Phase 4 meaning: per-display zoom out to all windows (pick mode).
- D-02: Each display shows its own windows in place on its own StagePanel, with a strip of that display's Spaces along its top. No combined cross-display panel.
- D-03: Windows on other Spaces show the last snapshot taken this session; otherwise the existing app-colour + icon + title tile (AppColor). Never try to capture non-composited windows.
- D-04: Clicking a window switches to its Space if needed, focuses it and closes the overview. Arrow keys move the selection, Return opens it, Esc closes the overview. Clicking a Space in the strip switches to that Space.

### Mission Control takeover
- D-05: v1 takeover triggers are the Mission Control keys (F3 / ⌃↑): disable the system symbolic hotkey and handle the keys ourselves. The 4-finger swipe up (CGEvent type 30, Dock control) is spike-gated: only take it if a VM spike plus a user host check prove it can be consumed safely; otherwise leave the swipe to macOS and say so.
- D-06: Opt-in is a menu toggle (e.g. "Replace Mission Control") that shows a one-time explanation alert, matching the Phase 3 conflict-alert style, plus a Debug submenu status line. Off by default.
- D-07: Crash safety: before disabling, store the original symbolic-hotkey state in UserDefaults; restore it on quit, on turning the toggle off and at the next launch. Also use the MultitouchCanary pattern: a crash while the takeover is on turns it off for that build/version until the user turns it back on.
- D-08: ⌃←/→ Space switching stays with macOS; not taken over.

### Display arrangements
- D-09: A display arrangement is identified by the sorted set of display UUIDs, ignoring positions and resolution.
- D-10: On unplug, the vanished display's desks become dormant (kept in the World, not planned). Its windows float on a remaining display and return to their tiles on re-plug, matched by display UUID.
- D-11: Debounce display reconfiguration ~1.5 s after the last screen-parameters change, and never act while the session is asleep or locked (SessionGate).
- D-12: "Displays have separate Spaces" off is detected (from SkyLight) and handled silently: one shared Space spanning displays, desks still keyed per display UUID. No prompt.

### Spaces handling
- D-13: Persist Space desks by the macOS Space UUID (from `SLSCopyManagedDisplaySpaces`); use the numeric ManagedSpaceID at runtime. Existing layout.json files with numeric IDs need a migration (research to confirm ID stability across reboots).
- D-14: A desk that changes while its Space is hidden is marked dirty and planned when its Space is next shown; no AX writes to hidden-Space windows.
- D-15: Without the Spaces lookup, build a window→Space co-visibility map from `activeSpaceDidChange` (Spaces visited since launch only) and hide the Spaces strip.
- D-16: The Spaces strip is read-only in v1: click to switch only. No create, delete or drag-window-to-Space.

### Claude's Discretion
- Which free ⌃⌥⌘ key Show Overview uses; exact strip styling (follow 04-UI-SPEC tokens); selection highlight; how Space switching is performed (public API or SkyLight); arrangement-set schema shape and migration mechanics.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/TransomPrivate/SkyLightSpaces.swift`: per-window Spaces and current Space per display (no Space list/UUIDs yet; add `SLSCopyManagedDisplaySpaces`).
- `Sources/TransomPrivate/Capabilities.swift`: capability registry, `--disable-private=<Name>`, `MultitouchCanary` (copy for the takeover).
- `Sources/TransomMac/Displays.swift`: `DisplayInfo` (uuid, frame, visibleFrame, currentSpaceID).
- `Sources/TransomMac/Zoom/StagePanel.swift`, `TileLayer.swift`, `SnapshotCapture.swift`, `AppColor.swift`, `ZoomController.swift` (pick mode): one panel per screen.
- `Sources/TransomEngine/LayoutRestore.swift` (`reattach`, `isAlive`), `LayoutFile.swift` (schema v1), `Sources/TransomMac/LayoutStore.swift`.
- `rescueStranded` and dormant-window handling in the Arranger (G-03-8).

### Established Patterns
- `DeskKey(displayUUID, spaceID?)`; World maps DeskKey → Desk; displays matched by UUID only.
- Only the visible Space is arranged; `.spaceChanged` re-plans only the shown desk.
- Private APIs via dlopen/dlsym into optionals, one file each, capability-gated, call-time degradation.
- ⌃⌥⌘ hotkeys via KeyboardShortcuts with Recorder rows; Debug submenu shown with ⌥.
- macOS defaults changed only after asking, restored via "Restore macOS Window Settings".

### Integration Points
- `Sources/TransomMac/AXWindowSystem.swift` ~L112-117: `didChangeScreenParameters` and `activeSpaceDidChange` observers.
- `Sources/TransomMac/SessionGate.swift`: sleep/wake gating.
- `Sources/TransomEngine/Arranger.swift`: `.displaysChanged` is a no-op today (~L619); `home(of:)`/`rehome` float windows that change display.
- `Sources/TransomMac/Input/InputTap.swift`: mask is mouse + flagsChanged; Mission Control keys need keyDown (or the symbolic-hotkey route).
- `Sources/TransomEngine/CloseRule.swift`: G-03-9 fix point.

</code_context>

<specifics>
## Specific Ideas

- The user has a MacBook Air with only the built-in trackpad and has used ⌃←/→ and a 4-finger swipe for Spaces. Multi-display checks need user hardware checklists; the Tart VM cannot emulate display hot-plug easily.
- Research must verify: SkyLight signatures for `SLSCopyManagedDisplaySpaces`, Space ID/UUID stability across reboots and OS updates, `CGSSetSymbolicHotKeyEnabled` behaviour on macOS 27 and its state after a deliberate crash (VM), whether focusing a window on another Space switches Space.
- G-03-9 caveat: minimised, ⌘H-hidden windows and hidden tabs may also report no Space; verify in the VM before treating "known and empty" as closed.

</specifics>

<deferred>
## Deferred Ideas

- 4-finger swipe takeover, if the spike fails.
- Dragging windows between Spaces; creating/deleting Spaces from the strip.
- Taking over ⌃←/→ Space switching.

</deferred>
