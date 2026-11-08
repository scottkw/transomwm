---
phase: 03-tiling-mvp
plan: 04
subsystem: arranger
status: complete
tags: [swift, paneEngine, paneMac, arranger, planner, keyboardshortcuts, tdd, tracer]

requires:
  - phase: 02-window-control
    provides: "WindowSystem events/inventory/perform, ExclusionFilter in perform (02-13), focusedWindow(of:)"
  - phase: 03-tiling-mvp
    provides: "Desktop tile (03-01), World.reflow / recordFloatingFrame / rekey and LifecycleSync rekey (03-03)"
provides:
  - "PaneEngine Command { dock, float, undo }"
  - "PaneEngine Planner.plan / clamp / dockTarget and FramePlan"
  - "PaneEngine Arranger, ArrangerInput, ArrangerEffect (pure layout owner)"
  - "PaneMac ArrangeController: the only reader of system.events, dispatch, effect runner"
  - "PaneMac Hotkeys + KeyboardShortcuts.Name dock/float/undo (⌃⌥⌘D/F/Z)"
  - "StatusItemController.update(_:) in place of its own events loop"
  - "FakeWindowSystem.setFullscreen(_:_:); PaneFixtureApp fullscreen / exit-fullscreen"
affects: [03-05, 03-06, 03-07, 03-08, 03-10, commands, menu, persistence, spaces]

actuals:
  tokens: 14150
  tasks: 3
  commits: 6
plan_head_before: d412503ebeeda9614e84ed8352e27e7e4d58f340
plan_head_after: 38e6781e28734449784525244113f4fd4c334b5c

tech-stack:
  added: ["KeyboardShortcuts 3.1.0 (exact, revision 772133d9dbe800fdac0473226822994c5c162c58)"]
  patterns:
    - "Pure Arranger + thin MainActor shell: inputs in, effects out, shell runs effects in order"
    - "One events reader (ArrangeController) fans the inventory out to the menu and Tracked Windows"
    - "Every write is a .perform effect that goes through system.perform (ExclusionFilter.admit)"
    - "lastRequested holds only windows still planned, so a window that leaves the plan is rewritten when it returns"

key-files:
  created:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Planner.swift
    - Sources/PaneEngine/Command.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/Input/Hotkeys.swift
    - Package.resolved
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift
    - Tests/PaneEngineTests/PlannerTests.swift
    - Tests/PaneMacTests/HotkeyTableTests.swift
    - Tests/PaneMacTests/NoScreenCaptureTests.swift
    - Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift
  modified:
    - Package.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneFixtureApp/main.swift

key-decisions:
  - "Dock uses the window's planned frame when Pane has just clamped it (it is about to be there), else its floating frame"
  - "A floating window whose model frame differs from its real frame (after Float or Undo) is moved to the model frame"
  - "lastRequested is pruned to windows still in the plan, so a minimised/fullscreen window gets its tile rect again on return"
  - "Undo with no focused window, or one on no desk, acts on the main display's visible desk"
  - "The live fullscreen test is opt-in (PANE_LIVE_FULLSCREEN=1): native fullscreen switches Spaces, which the live-test rules forbid"

patterns-established:
  - "ArrangerInput/ArrangerEffect is the contract later plans extend (add cases, never rename)"
  - "Live arrange tests place fixture windows before docking, since Dock acts where a drop at the centre lands (D-12)"

requirements-completed: [TILE-03, TILE-07, TILE-20]

coverage:
  - id: D1
    description: "Two docked windows tile without overlap inside the visible frame; closing one gives its space to the other"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerLifecycleTests.swift#dockingTwoWindowsTilesThemWithoutOverlap, closingADockedWindowGivesItsSpaceToItsNeighbour"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift#twoDockedWindowsTileWithoutOverlapAndReflowOnClose"
        status: pass
    human_judgment: false
  - id: D2
    description: "New windows float on the Desktop tile and are never docked; they move only when they overlap a docked tile"
    requirement: TILE-07
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerLifecycleTests.swift#newWindowsFloatOnTheDesktopAndAreNotMoved; Tests/PaneEngineTests/PlannerTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dock, Float and Undo by ⌃⌥⌘D/F/Z through one dispatcher; refusals beep"
    requirement: TILE-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerLifecycleTests.swift (float/undo rows); Tests/PaneMacTests/HotkeyTableTests.swift"
        status: pass
    human_judgment: true
    rationale: "Global hotkeys need a real key press in a real session (plan human-check)"
  - id: D4
    description: "No source file uses ScreenCaptureKit or CGWindowListCreateImage"
    requirement: TILE-10
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/NoScreenCaptureTests.swift#noSourceFileUsesScreenCapture"
        status: pass
    human_judgment: false
  - id: D5
    description: "A minimised docked window lends its tile and returns to it"
    requirement: TILE-20
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerLifecycleTests.swift#aMinimisedDockedWindowLendsItsTileAndReturnsToIt"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift#aMinimisedDockedWindowLendsItsTileAndComesBack"
        status: pass
    human_judgment: false
  - id: D6
    description: "A fullscreen docked window keeps its leaf, its neighbours take its space, and it returns to its tile"
    requirement: WIN-07
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerLifecycleTests.swift#aFullscreenDockedWindowKeepsItsLeafAndReturnsToItsTile"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift#aFullscreenDockedWindowKeepsItsTileAndComesBack (opt-in, not run)"
        status: unknown
    human_judgment: true
    rationale: "The live fullscreen test switches Spaces and was not run under the live-test rules; real fullscreen needs the plan's human-check"

duration: 27min
completed: 2026-10-26
---

# Phase 3 Plan 04: Arranger tracer, Dock/Float/Undo hotkeys, minimise and fullscreen reflow Summary

**Windows can now be docked. A pure `Arranger` in PaneEngine owns the World. `ArrangeController` is the only reader of `system.events` and sends every write through `system.perform`. ⌃⌥⌘D, ⌃⌥⌘F and ⌃⌥⌘Z (KeyboardShortcuts 3.1.0) dock, float and undo the focused window. When a docked window closes, minimises or goes fullscreen, its neighbours reflow, and it returns to its tile when it comes back.**

## Performance

- **Duration:** about 27 min
- **Started:** 2026-10-26T02:06:50Z
- **Completed:** 2026-10-26T02:33:37Z
- **Tasks:** 3 (6 commits)
- **Files:** 11 created, 5 modified

## Accomplishments

- **Planner** (pure). It turns a desk, its area and the gap into tile frames, the Desktop rect and the `unfit` set, all through `resolve`. The Desktop tile's minimum is the per-axis maximum of its present floating windows' minimums. A floating window moves only when it overlaps a docked tile, and then it is clamped into the Desktop rect (D-24). `dockTarget` maps a tile's centre zone to the nearest edge band of that tile, so `applyDrop` never sees a `.center` target.
- **Arranger** (pure, `Sendable`, no AppKit).
  - It keeps per-window info and the displays, and creates a desk the first time it sees a dockable, present, non-excluded window on a display.
  - New windows go onto the Desktop layer through `World.reflow`, never by docking.
  - Lifecycle events go through `LifecycleSync`. Floating moves are recorded with `recordFloatingFrame`.
  - It plans only the desks shown on a display. A `setFrame` is emitted only when a frame moved more than 0.5 pt from the last one requested.
  - While the session is paused it writes nothing, and it re-plans when the session resumes.
  - A thrown `LayoutError` becomes `fault` for an event, or `beep` + `fault` for a command.
- **Commands.**
  - Dock dry-runs the edit on copies and refuses with a beep plus "Not enough room to dock here" if the result leaves a window unfit.
  - Float undocks the window to its tile rect, clamped into the new Desktop rect.
  - Undo uses `LifecycleSync.undo`. It returns `.requery` when it revived windows; otherwise it re-plans directly.
  - Each command is one undo step. `isAvailable` holds the enablement rule.
- **ArrangeController.**
  - `start()` feeds the inventory and then runs the single `for await` loop over `system.events`. After each event it re-reads the inventory and calls `onInventory`.
  - It runs effects in order: perform, then requery and requeried, then `NSSound.beep`, then the accessibility announcement, then a `Logger(category: "arrange")` fault.
  - `StatusItemController` no longer has its own loop. It gets `update(_:)`, which still feeds Tracked Windows.
- **Hotkeys.** The names `dock`, `float` and `undo` have fixed ⌃⌥⌘D/F/Z defaults and are registered once in `PaneMacApp`. KeyboardShortcuts is pinned `exact: "3.1.0"` at revision 772133d9 (source only, no binary target or plugins). Only PaneMac and PaneMacTests depend on it.
- **Test plumbing.** `FakeWindowSystem.setFullscreen` was added. `PaneFixtureApp` gained `fullscreen <i>` and `exit-fullscreen <i>`, which reply once AppKit's did-enter/did-exit notification fires (5 s limit).

## Task Commits

1. **Task 1 (tracer): Planner, Arranger, ArrangeController, one events reader**: `5a49bd1` (test, RED), `9329d78` (feat, GREEN)
2. **Task 2: Float, Undo, ⌃⌥⌘D/F/Z**: `2b4bed8` (test, RED), `196296f` (feat, GREEN)
3. **Task 3: minimised and fullscreen docked windows**: `ac4883a` (test, RED), `38e6781` (feat, GREEN)

## TDD Gate Compliance

- Every task starts with a `test(03-04)` commit, and a `feat(03-04)` commit follows it.
- RED evidence was classified `RED_EVIDENCE_OK` for all three tasks: `dockingTwoWindowsTilesThemWithoutOverlap()`, `floatPutsADockedWindowOnTheDesktopAtItsClampedTileRect()` and `aFullscreenDockedWindowKeepsItsLeafAndReturnsToItsTile()`. Each failed on its planned assertion against stubs that compile.
- Some RED rows passed against the stubs, and that is expected:
  - The negative Planner rows ("left alone"). A stub that plans nothing trivially leaves windows alone.
  - The Task 2 rows for availability, beeps and requeried. Task 1's GREEN Arranger already contained `isAvailable` and the `.requeried` arm, because they are part of the Arranger contract.
  - The Task 3 rows for minimise, pause and floating-minimise. Task 1's lifecycle path already delivered them.
  - NoScreenCaptureTests. It is a guard on a property that already held.
- No refactor commits.

## Verification

- `swift test --filter "PlannerTests|ArrangerLifecycleTests"`: 21 tests ran and passed (8 planner, 13 arranger at Task 2). After Task 3, ArrangerLifecycleTests ran 17 tests and passed.
- `swift test --filter "ArrangerLifecycleTests|HotkeyTableTests|NoScreenCaptureTests"`: 13 + 5 tests ran and passed.
- `caffeinate -d -i swift test --filter ArrangeIntegrationTests`, trusted terminal, lock checked first: 2 tests ran and passed (close reflow, minimise round trip). The fullscreen test was skipped by its opt-in gate (see Deviations). No fixtures were left over.
- `PANE_SKIP_AX_INTEGRATION=1 swift test`, in debug and in `-c release -Xswiftc -enable-testing`: 189 + 102 + 27 + 261 tests passed.
- `scripts/check-no-appkit.sh`: OK (30 files). `scripts/build-debug.sh`: built and verified "Pane Debug.app".
- Acceptance greps:
  - `public struct Arranger` appears 1 time.
  - `for await` appears once in ArrangeController and 0 times in StatusItemController.
  - `in system.events` appears once under Sources/PaneMac.
  - `exact: "3.1.0"` appears 1 time.
  - The revision appears 1 time in Package.resolved.
  - `Self("dock"` appears 1 time.
  - KeyboardShortcuts appears in PaneEngine and PaneModel 0 times.
  - `func setFullscreen` appears 1 time.
  - `"fullscreen"` appears 2 times in the fixture.
- The tracer gate after Task 1 re-ran the verify step end to end and it passed before Task 2 started.

## Deviations from Plan

**1. [Rule 1 - Test bug] The live dock test now places the fixture windows before docking**
- **Found during:** Task 1
- **Issue:** Dock acts where a drop at the window's centre lands (D-12). On this 1710-pt display, the second fixture window was clamped and its centre fell in the Desktop tile's *top* band. It therefore docked above the Desktop, and closing it gave the space back to the Desktop rather than to window 0. The engine reproduced the same result, so this was the test's geometry, not a product bug.
- **Fix:** The test `move`s window 0 to the left part of the screen and window 1 just right of the middle, both at mid-height, so they dock side by side on any display size. It also requires `a.maxX < b.minX`.
- **Commit:** 9329d78

**2. [Rule 1 - Test bug] The live tests keep the ArrangeController alive**
- **Found during:** Task 3
- **Issue:** A refactored helper discarded the controller (`let (_, _, a, _)`). Its events loop holds `self` weakly, so the loop ended and the reflows never ran.
- **Fix:** Bind the controller and `defer { withExtendedLifetime(arrange) {} }`. Production is unaffected, because `PaneMacApp` keeps a static strong reference.
- **Commit:** 38e6781

**3. [Project rule] The live fullscreen test is opt-in (`PANE_LIVE_FULLSCREEN=1`)**
- **Found during:** Task 3
- **Issue:** Native fullscreen moves the window to its own Space, so macOS switches Spaces. That conflicts with the live-test rule "never switch Spaces", which takes precedence over the plan's verify step.
- **Fix:** The test and the fixture commands exist. The test always leaves fullscreen on failure. It runs only when `PANE_LIVE_FULLSCREEN` is set, and it was not run here. The fullscreen behaviour is covered by the fake test, and the plan's human-check covers real apps. The plan's "not skipped" criterion for ArrangeIntegrationTests is therefore met for close and minimise only.
- **Commit:** ac4883a

---

**Total deviations:** 3 (2 test fixes, 1 rule-driven gate). **Impact:** no product scope change. WIN-07 stays unverified live.

## Issues Encountered

- Three live runs failed while diagnosing deviation 1 (two plain runs and one instrumented run). The geometry (843 pt = half of 1710 − 24) and an engine probe found the cause without opening more windows. After the fix, every live run passed.
- `swift format lint` with default settings rejects the repo's 4-space style everywhere, and CI runs no format gate, so it was not applied.

## Requirements

- **Complete:** TILE-03 (verified live), TILE-07 (new windows float and are never docked), TILE-20 (verified live).
- **Pending:**
  - TILE-09: focus neighbour and the menu items come in later plans.
  - TILE-10: the guard test is in place; the phase verifier confirms the whole phase works without Screen Recording.
  - WIN-07: the live fullscreen test was not run (Spaces rule), and plan 05 adds the Space rule for fullscreen Spaces.

## Known Stubs

None. Two items are known limits for later plans rather than stubs:
- `displaysChanged` and `spaceChanged` do not re-feed displays to the Arranger yet (plan 05 for Spaces, Phase 6 for displays).
- `unfit` windows after an event get no frame; auto-float with a notice (D-26) comes later.

## Threat Flags

None. All the mitigations were applied:
- T-03-07: every write is a `.perform` through `system.perform`, and excluded or never-dock windows are never put on a desk (tested).
- T-03-08: the 0.5 pt `lastRequested` diff.
- T-03-09: `fault` messages use `WindowRef.description`, which carries no title, and are logged with `privacy: .public`.
- T-03-10: exact pin plus the committed Package.resolved.

## Human checks pending (from the plan)

- In Pane Debug: press ⌃⌥⌘D on two TextEdit windows, ⌃⌥⌘F on the first, then ⌃⌥⌘Z twice, then ⌃⌥⌘Z once more on an empty history, which should beep.
- Dock Safari and TextEdit side by side. Minimise and restore Safari. Fullscreen TextEdit and leave fullscreen.

## Self-Check: PASSED

All 11 created files exist. Commits 5a49bd1, 9329d78, 2b4bed8, 196296f, ac4883a and 38e6781 are ancestors of HEAD.
