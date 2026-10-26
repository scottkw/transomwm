---
phase: 03-tiling-mvp
plan: 12
subsystem: engine
tags: [swift, arranger, hotkeys, keyboardshortcuts, nsmenu, layout-commands]

requires:
  - phase: 03-tiling-mvp
    provides: "03-02 tree edits (swap, balance, rotate, flip, resizeChild), Neighbours, Snap; 03-08 MRU focus list; 03-10 Command / CommandMenu / availability rule; 03-11 flashBlocked"
provides:
  - "Command cases moveOrSnap(Edge), swapPrevious, growTile, shrinkTile, balanceSplit, rotateSplit, flipSplit, snap(SnapTarget), arrangeAll, floatAll"
  - "Arranger+Commands.swift: the layout command handlers and a shared dry-run commit (refuses on unfit, optionally on no change)"
  - "Notice.floatedAll(count:) (N4) and Notice.arrangeLeftovers(count:) (N5) with NoticeCopy"
  - "21 new KeyboardShortcuts names (moveLeft..floatAll) on the UI-SPEC Surface 6 defaults"
  - "Menu rows: Swap with Previous Window, Move Window ▸, Split ▸ (grow/shrink/balance/rotate/flip), Snap Floating Window ▸, Arrange All Windows, Float All Windows"
  - "Arranger.isFloating(_:) for the halves alias, CommandMenu.update(focusedFloats:availability:)"
affects: [03-13, 03-14, 03-15, 03-16, phase-04-settings-recorder]

actuals:
  tokens: 18300
  tasks: 3
  commits: 6
plan_head_before: 8038b4b3a3665e806b6e7cf07b7e7893d7d94141
plan_head_after: 7574955c6d55cdeefee897c9cb30904c1216e39a

tech-stack:
  added: []
  patterns:
    - "Layout commands live in an Arranger extension file; Arranger.swift only gains dispatch and availability arms"
    - "commit(key, flashing:, refusingNoChange:) dry-runs a World.edit on a copy and refuses with beep + announce + flashBlocked when a window would lose its room"
    - "One command, two menu items (halves alias): the second item reuses the first's tag and shortcut; update(focusedFloats:) enables only the matching one"

key-files:
  created:
    - Sources/PaneEngine/Arranger+Commands.swift
    - Tests/PaneEngineTests/ArrangerCommandTests.swift
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Command.swift
    - Sources/PaneEngine/Notice.swift
    - Sources/PaneMac/Input/Hotkeys.swift
    - Sources/PaneMac/Shell/CommandMenu.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Sources/PaneMac/Shell/NoticeCopy.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Overlay/NoticeQueue.swift
    - Sources/PaneMac/ArrangeController.swift
    - Tests/PaneMacTests/HotkeyTableTests.swift
    - Tests/PaneMacTests/CommandMenuTests.swift
    - Tests/PaneMacTests/NoticeCopyTests.swift
    - Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift

key-decisions:
  - "Move to neighbour docks on the neighbour's near edge, except next to a sibling in the same split: there the near edge is the window's own slot (a no-op), so it goes past the sibling and takes its place"
  - "Grow/Shrink refuse (beep, no undo step) when the resolved rects would not change or resizeChild throws atSizeLimit"
  - "Every tree command (move, swap, grow/shrink, balance, rotate, flip) is refused up front with the blocked flash if it would leave a window without room, like Dock (D-26)"
  - "Arrange All and Float All target the focused window's desk, or the main display's visible desk with none focused, and stay enabled with no focused window"
  - "A newer N4 or N5 replaces the visible one instead of merging counts, since each count is already the current total"

patterns-established:
  - "Arranger+Commands.swift: new keyboard commands go here as extension methods"

requirements-completed: [TILE-11, TILE-12, TILE-13, TILE-14, TILE-16, TILE-09]

coverage:
  - id: D1
    description: "⌃⌥⌘⇧ arrows move a docked window into the neighbouring tile, or snap a floating one to that half; no neighbour or no room beeps"
    requirement: TILE-13
    verification:
      - kind: unit
        ref: "swift test --filter ArrangerCommandTests (moving*, aDesktopNeighbour*, withNoNeighbour*, aMoveThatLeaves*, aFloatingWindowSnaps*)"
        status: pass
      - kind: integration
        ref: "caffeinate -d -i swift test --filter ArrangeIntegrationTests/moveLeftPutsTheRightWindowWhereTheLeftOneWas"
        status: pass
    human_judgment: false
  - id: D2
    description: "Swap with previous, grow/shrink, balance, Rotate Layout (from the root, twice restores) and flip, each one undo step"
    requirement: TILE-12
    verification:
      - kind: unit
        ref: "swift test --filter ArrangerCommandTests (swapPrevious*, grow*, balance*, rotate*, treeCommandsBeep*)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Thirds, quarters, maximize and centre snap a floating window inside the Desktop tile; a docked one beeps"
    requirement: TILE-14
    verification:
      - kind: unit
        ref: "swift test --filter ArrangerCommandTests/snapPutsAFloatingWindowAtItsTargetAndADockedOneBeeps"
        status: pass
    human_judgment: false
  - id: D4
    description: "Arrange All (screen order, largest tile, leftovers N5) and Float All (tile rects, shows a hidden Desktop, N4), each one undo step"
    requirement: TILE-16
    verification:
      - kind: unit
        ref: "swift test --filter ArrangerCommandTests (arrangeAll*, aWindowThatDoesNotFit*, whenNothingFits*, excludedNeverDock*, floatAll*)"
        status: pass
      - kind: unit
        ref: "swift test --filter NoticeCopyTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "21 hotkeys on the UI-SPEC defaults with no shared chord, and their menu rows in UI-SPEC order, through the one dispatcher"
    requirement: TILE-09
    verification:
      - kind: unit
        ref: "swift test --filter \"HotkeyTableTests|CommandMenuTests\""
        status: pass
    human_judgment: false
  - id: D6
    description: "The feel of the commands on real app windows and the menu's chord display (the plan's human-check)"
    verification: []
    human_judgment: true
    rationale: "Real app windows, command feel and NSMenu chord rendering; deferred to end-of-phase UAT (human_verify_mode end-of-phase)"

duration: 13min
completed: 2026-10-26
status: complete
---

# Phase 3 Plan 12: Keyboard Layout Commands Summary

**Move-to-neighbour, swap, grow/shrink, balance, Rotate Layout, flip, 13 floating snaps and Arrange All / Float All, each on its UI-SPEC chord and menu row through the one dispatcher, with dry-run refusals that beep and flash the blocked preview.**

## Performance

- **Duration:** about 13 min
- **Started:** 2026-10-26T05:06:13Z
- **Completed:** 2026-10-26T05:19Z
- **Tasks:** 3
- **Files modified:** 16 (2 created)

## Accomplishments

- **Move Window / snap half (⌃⌥⌘⇧ arrows).** A docked window moves into the tile across that edge as one undo step. A floating one snaps to that half of the Desktop tile, recorded as a frame fact with no undo step. Move Window ▸ and Snap Floating Window ▸ both run `moveOrSnap`, and only the item matching the focused window is enabled.
- **Tile commands.** Swap with Previous Window (⌃⌥⌘S) uses the MRU list. Grow and Shrink (⌃⌥⌘= / -) move a tenth of the split and beep at a size limit. Balance (B), Rotate Layout (R, from the root, so rotating twice restores the tree exactly) and Flip (X) act on the parent split. Each is one `World.edit`, and each is refused up front with the blocked flash if a window would lose its room.
- **Snaps.** ⌃⌥⌘1/2/3, U/I/J/K, ↩ and C snap a floating window to the thirds, quarters, maximise and centre of the Desktop tile. A docked window beeps.
- **All windows.** Arrange All (⌃⌥⌘⇧D) dry-runs every eligible floating window in screen order inside one edit. Each window goes on the longer side of the largest tile. Windows that don't fit stay floating, counted by N5, and when none fits it beeps with the blocked flash. Float All (⌃⌥⌘⇧F) floats every docked window at its tile, shows a hidden Desktop in the same step, and toasts N4.
- **Live:** from a trusted terminal, `moveOrSnap(.left)` on the right window of a docked fixture pair moves it into the left window's x-range with no overlap.

## Task Commits

1. **Task 1 (tracer): move to neighbour / snap half.** `48df792` (test, RED), `55d76fe` (feat, GREEN). Tracer gate: the automated `<verify>` passed again end to end, live included. Tracer verified end to end, expanding.
2. **Task 2: swap, grow/shrink, balance, rotate, flip, snap targets.** `55f0f96` (test, RED), `a1db581` (feat, GREEN)
3. **Task 3: Arrange All and Float All.** `9241f03` (test, RED), `7574955` (feat, GREEN)

## Files Created/Modified

- `Sources/PaneEngine/Arranger+Commands.swift`: every handler, plus the shared dry-run `commit` and the `largestTile` / `previousDocked` / `parentSplit` lookups
- `Sources/PaneEngine/Arranger.swift`: dispatch and availability arms, `isFloating`, a `recency(on:)` helper shared with focus; `world`/`history` setters and a few helpers widened from private to internal for the extension file
- `Sources/PaneEngine/Command.swift`, `Notice.swift`: the new cases
- `Sources/PaneMac/Input/Hotkeys.swift`: 21 names on the Surface 6 defaults
- `Sources/PaneMac/Shell/CommandMenu.swift`, `MenuCopy.swift`, `StatusItemController.swift`: Move Window, Split and Snap Floating Window submenus, the halves alias, Swap, Arrange All and Float All rows
- `Sources/PaneMac/Shell/NoticeCopy.swift`, `Overlay/NoticeQueue.swift`, `ArrangeController.swift`: N4/N5 copy, glyph, merge rule and toast display
- Tests: `ArrangerCommandTests` (22 tests), plus additions to `HotkeyTableTests` (including a new no-shared-chord check), `CommandMenuTests`, `NoticeCopyTests` and the live `ArrangeIntegrationTests`

## Decisions Made

See `key-decisions` in the frontmatter. The move rule is the one deviation from the plan's wording (below).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A move next to a sibling on the move axis did nothing**
- **Found during:** Task 1
- **Issue:** The plan says to remove the window and insert it on the neighbour's near edge (`edge.opposite`). For `[a | b | Desktop]` with b moving left, that rebuilds exactly `[a | b | Desktop]`. The press would change nothing and still push an undo step, and the plan's own live truth ("moves it into the left window's tile area") could never pass.
- **Fix:** When the window and its neighbour share a parent split, the window is inserted on the neighbour's far edge, so it takes the sibling's place (`H[b,a,D]`, the i3/AeroSpace "move" behaviour). Across a split boundary the near-edge rule stands: `H[a,V[b,c],D]` with c moving left gives `H[a,c,b,D]`, and `V[H[a,b],D]` with b moving down gives `V[a,b,D]`. Moving toward a sibling Desktop tile likewise passes it.
- **Files modified:** Sources/PaneEngine/Arranger+Commands.swift
- **Verification:** ArrangerCommandTests (sibling, near-edge and Desktop cases) and the live move-left test
- **Committed in:** 55d76fe

**2. [Rule 3 - Blocking] Files outside `files_modified`**
- **Found during:** Tasks 1 and 3
- **Issue:** The new `Notice` cases make the exhaustive switches in `NoticeQueue.merged(with:)` and `ArrangeController.displayUUID(of:)` fail to compile. The extension file also cannot set `private(set)` properties or call `private` helpers.
- **Fix:** Added the two switch arms (N4/N5 replace rather than merge; they show on the menu-bar display). Widened `world`/`history` to `internal(set)` and `replan`, `minimums`, `display(for:)`, `targetKey`, `showingDesktop` to internal. All of these stay module-internal.
- **Files modified:** Sources/PaneMac/Overlay/NoticeQueue.swift, Sources/PaneMac/ArrangeController.swift, Sources/PaneEngine/Arranger.swift
- **Committed in:** 55d76fe, 7574955

**3. [Rule 1 - Bug] Tree commands refuse when a window would lose its room**
- **Found during:** Task 2
- **Issue:** The plan only specifies a no-room refusal for move. A swap, rotate or balance that leaves a window unfit would otherwise commit, and the next re-plan would float that window with an N1 toast. Dock and drops refuse up front (D-26).
- **Fix:** Every tree command goes through the same dry-run `commit`, which refuses with beep, the "Not enough room to dock here" announcement and `.flashBlocked`.
- **Committed in:** a1db581

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking). **Impact on plan:** the move rule changes the documented same-axis behaviour to the only one that does something visible. Nothing else in the contract changed.

## Issues Encountered

- The first leftover test for Arrange All used a floating window taller than the display. Its minimum sizes the Desktop tile, so every dock on that desk came out unfit and nothing docked. This is existing Planner behaviour, logged in `deferred-items.md`. The test now uses a realistic case, a window that fits on the Desktop but not beside the largest tile.
- **Verification scope:** `swift test` ran with `PANE_SKIP_AX_INTEGRATION=1` (368 + 190 + 38 tests, all passed). The live `ArrangeIntegrationTests` ran as one bounded, caffeinated batch of 4 (all passed, no leftover fixtures). That batch left out the known two-display failure `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` (deferred-items, not re-run under the project rules) and the opt-in fullscreen test. `scripts/build-debug.sh` and `scripts/check-no-appkit.sh` exit 0.
- **Human check pending (end of phase):** in Pane Debug with real app windows, try ⌃⌥⌘⇧D / ⇧F / Z and the tile and snap chords, and check that each menu item shows its chord (D6 above).

## Known Stubs

None.

## User Setup Required

None. No external service configuration is required.

## Next Phase Readiness

- Success criterion 6 and the all-window half of criterion 7 now work by hotkey and menu. The Phase 4 recorder can reuse the 21 new names, which are a persistent contract.
- TILE-13, TILE-14 and TILE-16 are delivered end to end. TILE-09, TILE-11 and TILE-12 were already marked complete, and this plan adds their remaining hotkey and menu routes.

## Self-Check: PASSED
