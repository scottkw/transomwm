---
phase: 02-window-control
plan: 04
subsystem: engine
tags: [swift, swift-testing, lifecycle, undo, world-apply]

requires:
  - phase: 01-layout-model
    provides: World.apply / World.undo contracts (undo returns revived windows, .closed ignores the desk key)
  - phase: 02-window-control (02-01, 02-03)
    provides: WindowEvent, WindowSystem.windowInfo, FakeWindowSystem with the initial sweep
provides:
  - LifecycleSync.handle mapping OS lifecycle events to World.apply only (D-10)
  - LifecycleSync.undo / requery / applyRequeried meeting the Phase 1 undo re-query obligation (D-11)
  - RevivedWindows value type making the re-query obligation explicit in the API
affects: [03-tiling, engine actor that owns the World]

actuals:
  tokens: 3500
  tasks: 2
  commits: 4
plan_head_before: 1804ce56ef1384b6c6fc7d204fd4d46700c7a873
plan_head_after: 61e4aa7accdde41ab1b5fd6d7551d10ef15c2d81

tech-stack:
  added: []
  patterns:
    - "Undo split sync -> async -> sync (undo, requery, applyRequeried) so an actor-held World never crosses an await inout"
    - "Exhaustive WindowEvent switch (no default) so a new event case forces a lifecycle decision"

key-files:
  created:
    - Sources/PaneEngine/LifecycleSync.swift
    - Tests/PaneEngineTests/LifecycleSyncTests.swift
    - .planning/phases/02-window-control/tdd/02-04-red-task1.json
    - .planning/phases/02-window-control/tdd/02-04-red-task2.json
  modified: []

key-decisions:
  - "LifecycleSync always passes a placeholder DeskKey for .closed: World.apply ignores the key for .closed, so the plan's holder/smallest-key fallback chain was dropped as dead code"
  - "windowCreated returns false: a new window is on no desk, so placing it is Phase 3 tiling's job, not a lifecycle fact"
  - "requery maps windowInfo nil to .closed (nil only means never seen or two-source confirmed closed)"

patterns-established:
  - "OS facts reach the model through LifecycleSync, never World.edit"

requirements-completed: [WIN-09]

coverage:
  - id: D1
    description: "OS lifecycle events change window states or close windows through World.apply only, never touching undo depth"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#stateChangedOnADockedWindowAppliesItWithoutTouchingUndo"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#fullscreenThenPresentEndsPresentWithUndoUnchanged"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#stateChangedToClosedIsTheSameAsDestroyed"
        status: pass
    human_judgment: false
  - id: D2
    description: "A destroyed window is removed and purged from every undo snapshot, including one on no desk and in a World with no desks"
    requirement: WIN-09
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#destroyingADockedWindowRemovesItAndNoUndoBringsItBack"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#destroyingAWindowOnNoDeskStillPurgesItFromUndo"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#destroyingAWindowInAWorldWithNoDesksDoesNotThrow"
        status: pass
    human_judgment: false
  - id: D3
    description: "Non-lifecycle events and state changes for windows on no desk leave World and history unchanged"
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#nonLifecycleEventsLeaveTheWorldUnchanged(event:)"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#stateChangedForAWindowOnNoDeskChangesNothing"
        status: pass
    human_judgment: false
  - id: D4
    description: "Undo re-queries each revived window from the WindowSystem: minimised ends .absent, unknown ends closed and purged, order preserved"
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#undoReviveOfAMinimisedWindowEndsAbsent"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#undoReviveOfAWindowTheSystemNoLongerKnowsClosesIt"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#requeryPreservesTheRevivedOrder"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#undoWithNothingToUndoReturnsNil"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#undoThatRevivesNothingReturnsAnEmptyListAndApplyingItChangesNothing"
        status: pass
    human_judgment: false

duration: 4min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 04: LifecycleSync Summary

**`LifecycleSync` sends OS lifecycle events into the model only through `World.apply`, and re-queries every window an undo brings back through `WindowSystem.windowInfo`, closing the Phase 1 obligation from c403f45.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-10-24T15:52:57Z
- **Completed:** 2026-10-24T15:56:59Z
- **Tasks:** 2
- **Files modified:** 4 (2 source/test, 2 RED evidence records)

## Accomplishments
- `LifecycleSync.handle`: `windowStateChanged` applies on the desk that holds the window (desks scanned in sorted key order). `windowDestroyed` and `windowStateChanged(_, .closed)` apply `.closed`, which purges the window from every undo snapshot. Every other event returns false. `World.edit` is never called, so undo depth never changes (D-10).
- `LifecycleSync.undo` → `requery` → `applyRequeried`: the undo path runs as sync, async, sync steps. `requery` maps a nil `windowInfo` to `.closed`. A revived window the fake reports minimised ends `.absent`. One the fake does not know ends removed and purged (D-11).
- `RevivedWindows` puts the re-query obligation in the type signature. The doc comment on `undo` states it.

## Task Commits

1. **Task 1: Lifecycle events reach the model only through World.apply**
   - RED `3443d17` (test): 8 tests (one of them parameterised over 12 non-lifecycle events), plus a skeleton `handle` returning false
   - GREEN `56b6c56` (feat)
2. **Task 2: Undo re-queries every revived window and reports its real state**
   - RED `acd13b5` (test): 5 tests, plus skeleton `RevivedWindows`/`undo`/`requery`/`applyRequeried`
   - GREEN `61e4aa7` (feat)

No REFACTOR commit: nothing needed cleaning.

## TDD Gate Compliance

- **RED (Task 1):** `swift test --filter LifecycleSyncTests` exited 1 with 6 of 8 failing. Target `stateChangedOnADockedWindowAppliesItWithoutTouchingUndo()` failed on its planned assertions: `handle` returned false and A stayed `.present`. Classifier result: `RED_EVIDENCE_OK` (record `tdd/02-04-red-task1.json`). Semantic check: the build succeeded and the target ran. The two tests that passed (no-desk state change, non-lifecycle events) assert that nothing changes, so they pass against the skeleton by design.
- **RED (Task 2):** exited 1 with 4 of 13 failing. Target `undoReviveOfAMinimisedWindowEndsAbsent()` failed because the skeleton `undo` returned nil. Its setup assertion (the fake reports B `.absent`) passed, so the failure came from the planned behaviour and not from the fixture. Classifier result: `RED_EVIDENCE_OK` (record `tdd/02-04-red-task2.json`).
- **GREEN:** 13/13 LifecycleSyncTests pass; 43 tests in 6 suites under `--filter PaneEngineTests` pass.
- Both RED commits include a compile-only skeleton in `LifecycleSync.swift`. Swift cannot build a test target that references missing symbols, and a build failure is `INVALID_RED`.

## Files Created/Modified
- `Sources/PaneEngine/LifecycleSync.swift`: `RevivedWindows`, `LifecycleSync.handle/undo/requery/applyRequeried`
- `Tests/PaneEngineTests/LifecycleSyncTests.swift`: event-mapping and undo re-query tests against a real `World` and `FakeWindowSystem`
- `.planning/phases/02-window-control/tdd/02-04-red-task{1,2}.json`: RED evidence records

## Decisions Made
- `.closed` always goes to `World.apply` with a placeholder `DeskKey("", nil)`. The plan said: holder key, else smallest desk key, else placeholder. `World.apply` ignores the key for `.closed`, so that chain was dead code. The behaviour is the same, and the call site carries a comment saying so.
- `windowCreated` is a no-op here. A brand-new window is on no desk, so placing it belongs to Phase 3 tiling.
- The `handle` switch lists every `WindowEvent` case and has no `default`. Adding a new event case therefore fails to compile until someone decides whether it is a lifecycle fact.

## Deviations from Plan

**1. [Simplification] Dropped the holder/smallest-key fallback for `.closed`**
- **Found during:** Task 1
- **Issue:** The plan's three-step key choice has no observable effect, because `World.apply(.closed, …)` ignores the key.
- **Fix:** Pass a placeholder key and comment why.
- **Verification:** `destroyingAWindowOnNoDeskStillPurgesItFromUndo`, `destroyingAWindowInAWorldWithNoDesksDoesNotThrow` and `stateChangedToClosedIsTheSameAsDestroyed` pass.
- **Committed in:** `56b6c56`

**Total deviations:** 1 (simplification, no behaviour change). **Impact:** none on the contract.

## Issues Encountered
- `swift format lint --strict` reports 2-space indentation errors. The repo has no `.swift-format` file, so the tool uses its defaults, while the codebase uses 4 spaces throughout. This is pre-existing and not caused by this plan.

## Known limits
- `applyRequeried` is not atomic across pairs. Each `World.apply` is transactional, but if a later pair throws (for example, the desk was removed between `undo` and `applyRequeried`), the earlier pairs stay applied. Each applied pair is a true OS fact, so this is safe.

## User Setup Required
None.

## Next Phase Readiness
- The STATE.md obligations "Phase 2 obligation (from Phase 1 review fix c403f45)" and "OS lifecycle events go through World.apply" are met by `LifecycleSync` and can be closed.
- Phase 3 should drive its World through `LifecycleSync.handle` and the `undo` → `requery` → `applyRequeried` sequence.
- No human-check items for UAT: everything here is covered by unit tests.

## Self-Check: PASSED
- FOUND: Sources/PaneEngine/LifecycleSync.swift, Tests/PaneEngineTests/LifecycleSyncTests.swift, both RED records
- FOUND commits: 3443d17, 56b6c56, acd13b5, 61e4aa7
- `grep "\.edit(" Sources/PaneEngine/LifecycleSync.swift` prints nothing; `scripts/check-no-appkit.sh` exits 0

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
