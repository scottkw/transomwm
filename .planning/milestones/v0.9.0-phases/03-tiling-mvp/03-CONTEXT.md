# Phase 3: Tiling MVP - Context

**Gathered:** 2026-10-25
**Status:** Ready for planning

<domain>
## Phase Boundary

The first usable release. You dock windows by dragging them into nested, non-overlapping tiles, and the layout stays correct as windows open, close, minimise and resize. Layout commands are available from hotkeys and the menu. Recovery is crash-safe, and Pane detects the macOS window features that conflict with it. A notarised 0.3.0 pre-release ships. Everything must work with zoom absent and Screen Recording denied (TILE-10).

Requirements: TILE-01..20, WIN-07, SAFE-01, SAFE-02, SAFE-03, SAFE-04, SAFE-06.

Not in this phase:
- the zoom camera (Phase 4)
- tab groups from a centre drop (Phase 7)
- the hotkey recorder (Phase 4)
- CI notarisation and the Homebrew cask (Phase 9)
- multi-display hardening (Phase 6)

</domain>

<decisions>
## Implementation Decisions

### A. Drag, drop and resize
- Drop zones keep the existing geometry in `DropZones.swift`: edge bands 25% of the tile, the centre 50%, and a 24 pt band at the screen edge. The drop preview and drop acceptance wait for about 150 ms of hover. The preview is the exact frame the window will get, computed as a dry run of `applyDrop` plus `resolve`. It is drawn in a click-through, non-activating panel.
- Releasing over a tile's centre does nothing before Phase 7: no preview, and the drop is a plain move. Tab grouping from the centre arrives in Phase 7.
- Modifiers:
  - Holding ⇧ while dragging places the window freely without docking (TILE-02).
  - Holding ⌘ when releasing over a docked tile swaps the two windows (TILE-11).
  - Modifiers are read during the drag, not at mouse-down.
  - ⌥-drag is left alone because it is Sequoia's tiling modifier. ⌃-click is left alone because it is a right-click.
- A docked window dropped outside every zone snaps back to its tile. You undock by bypass-dragging, with the green button, or with the Float command.
- Docked windows resize two ways: dragging a window's own edge moves its split boundary (`resizeBoundary`), and click-through gap handles appear when the gap is at least 4 pt (TILE-05).

### B. Hotkeys and commands
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

### C. Recovery and conflicts
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

### D. Desktop tile, layout space and release
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
- `setHidden` stays logged and dropped in Phase 3 (RESEARCH line 602). Park, focus and raise are implemented. setHidden is deferred to the phase that first needs it, and must go through `ExclusionFilter.admit` when it lands. Lead-accepted on 2026-10-25 (plan check warning 1).
- **Verification rule for every plan:** a `swift test --filter …` gate passes only if at least one test actually ran. SwiftPM exits 0 when a filter matches nothing. Check that the output shows a non-zero executed or passed count for the named suites, and treat "0 tests" or "no matching tests" as a failure.
- How to recognise Pane's own frame writes (`frameApplied`) so they are never mistaken for user drags.
- Internal structure of the Reconciler or Planner that owns the layout model.
- Exact preview styling, within the UI-SPEC.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- PaneModel provides drop-zone hit-testing and `applyDrop` (`DropZones.swift`), `resolve` with minimum sizes and a list of windows that don't fit (`Resolve.swift`), and `World.edit` with 50-level undo and versioned JSON. `TreeEdits.swift` has no swap, balance, rotate, flip or move-to-neighbour edits yet; Phase 3 adds them.
- `MinimumHintsStore` is the template for persisting layouts and home frames: an atomic write with all-or-nothing validation. The `KeyClosableWindow` and Never Arrange submenu patterns can be reused.
- `ExclusionFilter.admit` already guards every command. Minimum sizes come from `WindowInfo.learnedMinimum` plus in-session bundle hints.

### Established Patterns
- `LifecycleSync` is the only route from OS events into the model. It ignores `windowRekeyed` today (`LifecycleSync.swift:34`). **Phase 3 must re-point the layout's window references on `windowRekeyed`** (Phase 2 obligation).
- Undo runs `undo`, then `requery`, then `applyRequeried`.
- `StatusItemController` builds its menu from `add…Items(to:)` sections, with copy held in `MenuCopy`.
- PaneModel and PaneEngine stay free of AppKit (`scripts/check-no-appkit.sh`). Development is test-first: a RED commit comes before each behaviour change.

### Integration Points
- Nothing owns the layout model yet, so Phase 3 adds a Reconciler or Planner.
- `perform` handles only `setFrame`. Park, focus, raise and setHidden are dropped today (`AXWindowSystem.swift:172-181`, `FakeWindowSystem.swift:361`).
- There is no event tap and no hotkey dependency in `Package.swift`. KeyboardShortcuts 3.1.0 is added here.
- Build: `xcode/project.yml` (Developer ID, hardened runtime, version 0.2.0) and `scripts/build-debug.sh --release`. There is no notarisation step yet.

</code_context>

<specifics>
## Specific Ideas

- "Windows never overlap" is the core promise, which is why the Desktop is a real tile and why a drop with no room is refused.
- The clean-room rule applies: Pane chooses its own default hotkeys.
- Research flags:
  - The `com.apple.WindowManager` setting names for edge tiling are low confidence (Pitfall 15), and it is unknown whether a change applies without restarting WindowManager.
  - Notarising a hardened build that dlopens SkyLight may or may not need `disable-library-validation`.
  - Green-button clicks have to be caught without making AX calls inside the event-tap callback, and ⌥-click must still give the normal zoom (TILE-19).

</specifics>

<deferred>
## Deferred Ideas

- Tab grouping from the centre zone (Phase 7)
- Collapsed tiles for windows that don't fit (Phase 4, ZOOM-13)
- A hotkey recorder and defaults that suit the keyboard layout (Phase 4/9, Pitfall 16)
- A Secure Input indicator
- Re-opening new windows in a remembered slot, and per-app auto-dock rules (V2-02)
- CI notarisation and the Homebrew cask (Phase 9)
- Multi-display hardening (Phase 6)

</deferred>
