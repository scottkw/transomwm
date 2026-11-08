---
phase: 03-tiling-mvp
plan: 08
subsystem: window-commands
status: complete
tags: [swift, paneEngine, paneMac, accessibility, park, focus, desktop-tile, hotkeys, tdd, tracer]

requires:
  - phase: 02-window-control
    provides: "WindowCommand park/focus/raise/setHidden logged and dropped; ExclusionFilter.admit; AXAppThread latest-wins frame slots and element cache"
  - phase: 03-tiling-mvp
    provides: "Desktop tile and setDesktopHidden (03-01), Neighbours.neighbour (03-02), Arranger (03-04), .save(.now) and homeFrames (03-07)"
provides:
  - "park in AXWindowSystem and FakeWindowSystem: size kept, moved to DisplayInfo.parkedFrame (visibleFrame bottom-right minus 1 pt) through the frame slot"
  - "focus and raise: AXAppThread.focusWindow / raiseWindow / setFrontmost; AXWindowSystem activates with an AXFrontmost fallback; the fake yields windowFocused and records raised"
  - "FramePlan.parks; Arranger toggleDesktop (hide/show, one undo step each), home frames, save-before-park, D-31"
  - "Arranger.focusOrder (MRU) and Command.focus(Edge) through Neighbours.neighbour"
  - "Command.toggleDesktop, Command.focus(Edge); hotkeys toggleDesktop (⌃⌥⌘H), focusLeft/Right/Up/Down (⌃⌥⌘ arrows)"
  - "Fixture stdin command frontmost"
affects: [03-10, 03-14, 03-15, menu, url-scheme, quit-restore, crash-restore]

estimate:
  tokens: 95000
  tasks: 2
actuals:
  tokens: 12600
  tasks: 2
  commits: 4
plan_head_before: a21697580395552cfa49f589d0827125661e3614
plan_head_after: 1d666f31115d3b0c4ba4dec16b13484e8de0e199

tech-stack:
  added: []
  patterns:
    - "replan is the one place parks are sent: each window once (parkRequested), with its home frame recorded and .save(.now) emitted ahead of the perform that parks it"
    - "A floating window can't exist on a hidden Desktop: admitting, re-homing or floating a window onto that desk shows it first"
    - "Shared park geometry lives in PaneEngine (DisplayInfo.parkedFrame), so both window systems park to the same rect"

key-files:
  created:
    - Tests/PaneEngineTests/ArrangerDesktopTests.swift
    - Tests/PaneEngineTests/ArrangerFocusTests.swift
    - Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-08-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-08-task2-red.json
    - .planning/phases/03-tiling-mvp/deferred-items.md
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Planner.swift
    - Sources/PaneEngine/Command.swift
    - Sources/PaneEngine/WindowSystem.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/Input/Hotkeys.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneFixtureApp/main.swift
    - Tests/PaneMacTests/HotkeyTableTests.swift

key-decisions:
  - "Parks are emitted by replan (not only by the hide command), so every park, including a deminimised or restored floating window on a hidden desk, gets a home frame and an immediate save first"
  - "A parked window's moves are not recorded as floating frames, so showing the Desktop, undo and D-31 all bring it back to its Desktop frame; home frames cover the restore-from-file case"
  - "Home frames are dropped for floating windows on a shown Desktop, and when a window closes; frames for docked windows restored from layout.json are left alone"
  - "Float while the Desktop is hidden, and a window re-homed onto such a desk, also show the Desktop (UI-SPEC: a floating window can't exist in that state)"
  - "focus and raise run as Tasks so a hung app never holds up ArrangeController's effect loop; AX work stays on the app thread"
  - "A Desktop neighbour with floating windows none of which was ever focused focuses the first in Desktop order"

patterns-established:
  - "Thread jobs that act on one cached window element return Bool and fall back to false when the element is unknown"

requirements-completed: []

coverage:
  - id: D1
    description: "park in both window systems behind ExclusionFilter.admit: size kept, sliver left at the visibleFrame's bottom-right"
    requirement: TILE-15
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerDesktopTests.swift#hidingSavesHomeFramesAtOnceThenParksTheFloatingWindowsAndTheTilesFillTheArea"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerDesktopTests.swift#anExcludedFloatingWindowIsNeverParked"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift#parkLeavesOnlyASliverOnScreenAtTheSameSizeAndSetFrameBringsItBack"
        status: pass
    human_judgment: false
  - id: D2
    description: "⌃⌥⌘H hides the Desktop tile (save before park, tiles take its space) and shows it with every window at its home frame; refused with nothing docked; undo; D-31"
    requirement: TILE-15
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerDesktopTests.swift (6 tests)"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/HotkeyTableTests.swift#entriesMapStableNamesToCommands"
        status: pass
    human_judgment: true
    rationale: "The parked sliver's look and real apps' behaviour when parked need the plan's human check"
  - id: D3
    description: "focus and raise in both window systems; ⌃⌥⌘ arrows focus the nearest tile with MRU ties, Desktop neighbour, floating frame"
    requirement: TILE-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerFocusTests.swift (6 tests)"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FocusParkIntegrationTests.swift#focusMakesTheFixtureFrontmostWithThatWindowKeyAndRaiseSucceeds"
        status: pass
    human_judgment: true
    rationale: "Activating real apps under cooperative activation is the plan's human check (Safari, Terminal, TextEdit, Notes)"

duration: 17min
completed: 2026-10-26
---

# Phase 3 Plan 08: Park, Focus and Raise, Hide Desktop and Focus Neighbour Summary

**⌃⌥⌘H parks the Desktop tile's floating windows in the display's bottom-right corner. Their home frames are saved to layout.json first, and the docked tiles take the whole screen. Pressing ⌃⌥⌘H again brings each window back to its home frame. ⌃⌥⌘ plus an arrow focuses the nearest tile in that direction, and ties go to the most recently focused window. This works through real AXMain/AXRaise/activate calls with an AXFrontmost fallback.**

## Performance

- **Duration:** about 17 min
- **Started:** 2026-10-26T03:38:08Z
- **Completed:** 2026-10-26T03:55Z
- **Tasks:** 2 (each RED then GREEN)
- **Files modified:** 16

## Accomplishments

- Phase 2's dropped commands now work in both window systems behind `ExclusionFilter.admit`:
  - `park` keeps the window's size and writes `DisplayInfo.parkedFrame` through the latest-wins slot.
  - `focus` runs AXMain and AXRaise on the app thread, then `NSRunningApplication.activate()`. If the app is still not frontmost after about 200 ms, it sets AXFrontmost.
  - `raise` runs AXRaise only.
  - `setHidden` stays logged and dropped (Chesterton's Fence).
- Hide Desktop works as follows:
  - It records the home frames of the floating windows that are not excluded.
  - It is one `World.edit` step.
  - `replan` emits `.save(.now)` and then a single perform. That perform holds the parks first and the tiles' new frames after them.
  - Show is one undo step. It puts each floating window back at its home frame.
  - Undo of a hide, and a new window arriving (D-31), un-park the same way.
- Focus neighbour:
  - The MRU `focusOrder` is fed by `windowFocused`. It forgets closed windows and follows rekeys.
  - `Neighbours.neighbour` runs with recency mapped to leaf IDs. Floating windows map to the Desktop leaf.
  - A Desktop neighbour focuses its most recently focused present floating window.
  - When there is no neighbour, it beeps.
- Five new hotkeys use frozen names: `toggleDesktop`, `focusLeft`, `focusRight`, `focusUp`, `focusDown`.

## Task Commits

1. **Task 1 RED:** `5ac83fd` test(03-08): add failing tests for hiding and showing the Desktop tile
2. **Task 1 GREEN:** `fc178bc` feat(03-08): hide and show the Desktop tile, parking its floating windows
3. **Task 2 RED:** `42c3766` test(03-08): add failing tests for focusing the neighbouring tile
4. **Task 2 GREEN:** `1d666f3` feat(03-08): focus and raise windows, and focus the neighbouring tile by hotkey

There were no refactor commits.

## TDD Gate Compliance

- **Task 1 RED:** `swift test --filter ArrangerDesktopTests` exited 1. Five of six tests failed on their planned assertions against compiling stubs: `.toggleDesktop` was always refused and `parked` was never filled. The refusal test passed at RED because the stub refuses everything, and it pins the rule GREEN keeps. The classifier returned `RED_EVIDENCE_OK` (`tdd/03-08-task1-red.json`). The live park test was not run at RED.
- **Task 2 RED:** `swift test --filter ArrangerFocusTests` exited 1. All six tests failed on their assertions. The layout-shape precondition passed, so the failures came from missing behaviour and not from setup. The classifier returned `RED_EVIDENCE_OK` (`tdd/03-08-task2-red.json`).
- **GREEN:** both suites pass, and so do HotkeyTableTests and the live FocusParkIntegrationTests.

## Verification

- `swift test --filter "ArrangerDesktopTests|HotkeyTableTests"`: 6 + 4 tests ran and passed.
- `swift test --filter "ArrangerFocusTests|HotkeyTableTests|ArrangerDesktopTests"`: 12 + 4 tests ran and passed.
- `caffeinate -d -i swift test --filter FocusParkIntegrationTests`, from a trusted terminal with the lock checked first:
  - After Task 1: 1 test passed.
  - After Task 2: 2 tests passed. Neither run was skipped, and no fixtures were left over.
- `PANE_SKIP_AX_INTEGRATION=1 swift test`: 190 + 118 + 32 tests ran.
  - One known flake failed once: `FreezeTestTests/itResumesByItself`. It passed three times on its own (see deferred-items.md).
  - Before Task 2, the same run passed in full (190 + 118 + 31 + 295).
- Live regression batch `ArrangeIntegrationTests|FrameWriteIntegrationTests|ExclusionIntegrationTests` (11 tests):
  - The minimise round trip failed once and passed when re-run.
  - `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` failed. It fails the same way at the base commit a216975 in a scratch worktree, so this plan did not cause it. The Mac now has a second display. The test was not run again after its third failure.
- `scripts/check-no-appkit.sh`: OK (33 files).
- Acceptance greps:

  | Pattern | File | Count |
  |---|---|---|
  | `not implemented before Phase 3` | AXWindowSystem.swift | 0 |
  | `case .park` | AXWindowSystem.swift / FakeWindowSystem.swift | 1 / 1 |
  | `ExclusionFilter.admit` | AXWindowSystem.swift | 1 |
  | `Self("toggleDesktop"` | Hotkeys.swift | 1 |
  | `func focusWindow` | AXAppThread.swift | 1 |
  | `kAXRaiseAction` | AXAppThread.swift | 2 |
  | `activateIgnoringOtherApps` | AXWindowSystem.swift | 0 |
  | `"frontmost"` | PaneFixtureApp/main.swift | 1 |
  | `Self("focusLeft"` | Hotkeys.swift | 1 |

## Decisions Made

See `key-decisions` in the frontmatter. The main ones:
- `replan` is the only place that sends a park. This ensures every park has a saved home frame first (D-16, T-03-19).
- A parked window's moves are ignored. This means show, undo and D-31 all bring a window back to its Desktop frame.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Each window is parked once**
- **Found during:** Task 1 design
- **Issue:** `replan` runs on every event. Re-sending `park` each time would write the window on every echo of its own park. That is a write loop.
- **Fix:** `parkRequested` holds windows already parked. It is pruned to the ones still parked, and it is updated on close and rekey.
- **Commit:** fc178bc

**2. [Rule 1 - Bug] A parked window is never re-homed, and its moves are not recorded**
- **Found during:** Task 1 design
- **Issue:** A parked window can sit mostly on a neighbouring display, and `Coordinates.displayUUID` would then re-home it to that desk. Its park would also overwrite its Desktop frame as if the user had moved it.
- **Fix:** `rehome` skips parked windows. `moved` returns early for a floating window on a hidden desk.
- **Commit:** fc178bc

**3. [Rule 2 - Correctness] Floating or re-homing onto a hidden Desktop shows it**
- **Issue:** Without this, Float while the Desktop is hidden would park the window it just floated, so the window would vanish. The UI-SPEC says a floating window can't exist in that state.
- **Fix:** `float` and `rehome` show the Desktop first, as D-31 does for new windows.
- **Commit:** fc178bc

**4. [Plan file list] ArrangeController.swift was not changed**
- `dispatch(_:)` already routes any `Command`, and the new commands add no new effects. Nothing needed changing there.

**5. [Interface extension] Additions beyond the plan's interfaces**
- `DisplayInfo.parkedFrame(size:)`, the park geometry shared by both window systems.
- `AXAppThread.setFrontmost()`, the activation fallback job.
- `Arranger.focusOrder` is public read-only, for the MRU tests.
- **Effect on callers:** none.

**6. [Test design] The focus live test checks both windows and the job results**
- It focuses window 0 and then window 1. The fixture may already have window 1 key at launch, so focusing only window 1 would prove nothing.
- "Raise succeeds" is checked on a standalone `AXAppThread`, because `perform` returns nothing.

## Issues Encountered

- See deferred-items.md: one live D-26 test already fails at the base commit (probably because of the second display), and there are two timing flakes.

## Known Stubs

None.

## Threat Flags

None. park, focus and raise are the surfaces in the plan's threat model. Each one runs after `ExclusionFilter.admit`, as T-03-20 requires. All AX work stays on the app's thread, and main only calls `activate`, as T-03-21 requires. The save-before-park order is tested, as T-03-19 requires.

## Requirements

TILE-15, TILE-09 and TILE-13 stay **Pending**:
- TILE-15 has its hotkey now, but its menu item comes in plan 10 and its URL in plan 15.
- TILE-09 gets focus neighbour by hotkey here, but its menu items come in plan 10.
- TILE-13 (move to neighbour, grow/shrink) is delivered by other plans.

## Next Phase Readiness

- Plan 10 can add the "Hide Desktop Tile" / "Show Desktop Tile" menu item. It should grey it out with `isAvailable(.toggleDesktop, focused:)` and use the four Focus items.
- Plans 14 and 15 can rely on this: every parked window has a home frame in layout.json, written before it was parked.
- Human UAT (end of phase) is the plan's human-check:
  1. Dock Safari on the left, with Terminal and TextEdit stacked on the right.
  2. Use ⌃⌥⌘→ / ↓ / ← ← to move focus. The last press should beep.
  3. Press ⌃⌥⌘H twice with a floating Notes window. It should park in the corner and then come back to the same frame.

## Self-Check: PASSED
