---
phase: quick-261027-gqo
plan: 01
subsystem: engine
tags: [dock, green-button, TILE-06, D-33]
requires: []
provides: [left-biased exact-centre tie in Planner.dockTarget]
affects: [Arranger.dock, green button, Dock command]
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - Sources/PaneEngine/Planner.swift
    - Tests/PaneEngineTests/ArrangerGreenButtonTests.swift
    - Tests/PaneEngineTests/PlannerTests.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "Dock at a tile's exact centre picks the tile's left edge (user decision 2026-10-27); drag-drop centre and D-26 unchanged"
metrics:
  duration: ~10 min
  completed: 2026-10-27
status: complete
requirements: [TILE-06]
actuals:
  tokens: 2000
  tasks: 2
  commits: 3
plan_head_before: e6be085
plan_head_after: 18d2d04
---

# Quick 261027-gqo: Green click on a full-Desktop floater docks left Summary

When Dock lands at the exact centre of a tile, it now picks the tile's left edge. The fix is one character in `Planner.dockTarget` (`fx < 0.5` became `fx <= 0.5`), and two new regression tests cover it.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 RED | e0733c7 | test(quick-261027-gqo): green click on a floater filling the Desktop tile docks, ties go left |
| 1 GREEN | 953cc28 | fix(quick-261027-gqo): Dock at a tile's exact centre docks on its left edge |
| 2 | 18d2d04 | docs(quick-261027-gqo): mark the 03-18 green-click deferred item resolved |

## RED failure mode (at HEAD e6be085)

This matched the planner's prediction, so it was not a D-26 beep and not a `.center` guard problem.
- `PlannerTests.dockTargetAtTheDesktopsExactCentreGoesLeft`: the result was `.tile(n0, .edge(.right))`.
- `ArrangerGreenButtonTests.aPlainClickOnAFloaterZoomedToTheWholeDesktopTileDocksIt`: the setup asserts held. The w2 frame equals the Desktop rect, there is no `.beep`, w2 gets a setFrame, it leaves the Desktop list, and the history depth grows by one. Only the left-of-Desktop expectation failed: w2 docked at `(962, 33, 470x859)`, to the RIGHT of the new Desktop at `(485, 33, 469x859)`.

Arranger.swift was not touched, because its `.tile(_, .center)` guard is still reachable only when a node rect is missing.

## Verification

- Filtered run (ArrangerGreenButtonTests, PlannerTests, ArrangerCommandTests, ArrangerDragTests): 73 tests in 5 suites passed, with no ✘. The plan's grep gate is OK.
- Full headless `swift test`: all passed (largest run: 534 tests in 53 suites), with no ✘. The FreezeTest flake did not occur.
- `scripts/check-no-appkit.sh`: OK (40 files).

## Deviations from Plan

None. The plan was executed exactly as written.

## Self-Check: PASSED

- All three commits are ancestors of HEAD, and every modified file exists.
