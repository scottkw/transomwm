---
phase: 03-tiling-mvp
plan: 01
subsystem: layout-model
status: complete
tags: [swift, paneModel, layout-tree, desktop-tile, persistence]

requires:
  - phase: 01-layout-model
    provides: LayoutTree, resolve, DropZones/applyDrop, World/Desk, undo, versioned JSON
provides:
  - "Node.desktop(hidden:) under the reserved NodeID.desktop (raw 0)"
  - "LayoutTree.withDesktop(), isDesktopHidden, setDesktopHidden(_:)"
  - "LayoutError.nothingDocked, LayoutError.desktopTile(_:)"
  - "resolve(..., desktopMinimum:) and Resolution.desktopRect"
  - "Every Desk starts as the Desktop tile alone; Desk.validate requires it; World requires ids.next >= 1"
affects: [03-02, 03-04, 03-07, arranger, persistence, snap, neighbours]

actuals:
  tokens: 12218
  tasks: 2
  commits: 4
plan_head_before: 172bfb260d023fd6e96c063eb855187bedc6ddf3
plan_head_after: f1267b3cc02ffb6891f89ac761b1e3a8773d4510

tech-stack:
  added: []
  patterns:
    - "Tree-level rule allows a tree without a Desktop tile (raw trees in tests); desk-level rule requires exactly one"
    - "The Desktop is an ordinary non-split leaf to remove, normalize and DropZones; only group refuses it"

key-files:
  created:
    - Tests/PaneModelTests/DesktopLeafTests.swift
  modified:
    - Sources/PaneModel/IDs.swift
    - Sources/PaneModel/LayoutTree.swift
    - Sources/PaneModel/TreeEdits.swift
    - Sources/PaneModel/Resolve.swift
    - Sources/PaneModel/World.swift
    - Tests/PaneModelTests/PersistenceTests.swift
    - Tests/PaneModelTests/UndoTests.swift
    - Tests/PaneModelTests/ScenarioTests.swift
    - Tests/PaneModelTests/DesktopLayerTests.swift
    - Tests/PaneModelTests/LifecycleTests.swift
    - Tests/PaneModelTests/SkeletonTests.swift
    - Tests/PaneModelTests/TabsTests.swift
    - Tests/PaneModelTests/ResolveTests.swift
    - Tests/PaneModelTests/TreeEditTests.swift
    - Tests/PaneModelTests/ResolveFuzzTests.swift
    - Tests/PaneEngineTests/LifecycleSyncTests.swift

key-decisions:
  - "The Desktop tile has the reserved ID NodeID.desktop (raw 0); IDSource starts at 1 and World requires ids.next >= 1, so it is never minted and a desk holds at most one Desktop tile by construction"
  - "When desktopMinimum alone exceeds the area, resolve does not throw: every docked window is unfit and the Desktop gets the whole inner area"
  - "A hidden Desktop keeps its stored weight, so showing it restores the exact previous rects"
  - "Schema stays at version 1 with the Desktop node in the fixtures; no World file has been written by the app, so no migration"

patterns-established:
  - "Desk fixtures dock their first window with insert(w, at: .left, of: .desktop, ids:) instead of insertRoot"

requirements-completed: [TILE-07, TILE-15]

coverage:
  - id: D1
    description: "A new desk is the Desktop tile alone and resolves to the rect a lone panel gets"
    requirement: TILE-07
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/DesktopLeafTests.swift#aNewDeskIsTheDesktopTileAlone, theLoneDesktopGetsTheRectALonePanelGets"
        status: pass
    human_judgment: false
  - id: D2
    description: "Docking beside the Desktop through World.edit shrinks it without overlap; its edge bands dock beside it; removing the last docked window collapses back to it"
    requirement: TILE-07
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/DesktopLeafTests.swift#dockingBesideTheDesktopShrinksItWithoutOverlap, removingTheLastDockedWindowLeavesTheVisibleDesktopAlone"
        status: pass
    human_judgment: false
  - id: D3
    description: "Hide/show the Desktop tile: refused with nothingDocked when nothing is docked, gives its space to docked tiles, restores rects on show, shown again when the last docked window goes"
    requirement: TILE-15
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/DesktopLeafTests.swift#hidingTheDesktopWhileNothingIsDockedIsRefused, hidingTheDesktopGivesItsSpaceToTheDockedTilesAndShowingRestoresThem"
        status: pass
    human_judgment: false
  - id: D4
    description: "Saved World JSON at schema 1 carries the Desktop node and round-trips; files missing it, holding it under another ID, or with ids.next 0 are rejected"
    requirement: TILE-15
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/PersistenceTests.swift#corruptFileThrowsPersistenceError, richWorldRoundTripsExactly; DesktopLeafTests#theSavedWorldCarriesTheDesktopTileAndRoundTrips"
        status: pass
    human_judgment: false
  - id: D5
    description: "resolve takes desktopMinimum; the Desktop is never the unfit tile"
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/DesktopLeafTests.swift#theDesktopIsNeverTheUnfitTile, aDesktopMinimumLargerThanTheAreaGetsTheWholeArea, anInvalidDesktopMinimumIsRefused"
        status: pass
    human_judgment: false

duration: 9 min
completed: 2026-10-26
---

# Phase 3 Plan 01: The Desktop Tile Summary

**The Desktop is now a real leaf (`Node.desktop(hidden:)` under reserved `NodeID.desktop`) that every desk starts as, windows dock beside, `resolve` sizes with `desktopMinimum`, `setDesktopHidden` hides and shows, and the version-1 JSON persists.**

## Performance

- **Duration:** about 9 min
- **Completed:** 2026-10-26T01:48Z
- **Tasks:** 2 (tracer + auto, both TDD)
- **Files modified:** 17 (1 created)

## Accomplishments
- Every desk starts as the Desktop tile alone. Docking a window beside it (for example `applyDrop(.tile(.desktop, .edge(.left)))`) shrinks it, and the two rects never overlap.
- Validation: `.desktop` is accepted only under `NodeID.desktop`, a desk must hold it, and `World` refuses `ids.next == 0`. Corrupt-corpus rows prove each rejection (T-03-01, T-03-02).
- `resolve` gives a visible Desktop `desktopMinimum`, leaves out a hidden one, never picks it as unfit, and exposes `Resolution.desktopRect`.
- `setDesktopHidden` hides and shows the tile. Removing the last docked window leaves the visible Desktop alone. `group` into the Desktop throws `desktopTile`.
- Every PaneModel and PaneEngine desk fixture now docks beside the Desktop. 159 + 234 tests pass and none were deleted (the `@Test` count went from 497 to 514).

## Task Commits

1. **Task 1 RED:** `0c6c60d` test(03-01): add failing tests for the Desktop tile
2. **Task 1 GREEN:** `7e8f0b6` feat(03-01): make the Desktop a real tile in every desk (D-24)
3. **Task 2 RED:** `8743fb7` test(03-01): add failing tests for hiding and keeping the Desktop tile
4. **Task 2 GREEN:** `f1267b3` feat(03-01): hide and show the Desktop tile and migrate desk fixtures

No REFACTOR commits were needed.

## TDD Gate Compliance

- **RED 1:** `swift test --filter "DesktopLeafTests|PersistenceTests"` exited 1 with 10 of 22 tests failing. Target `aNewDeskIsTheDesktopTileAlone()` failed on `desk.tree.root == .desktop`. Classifier result: `RED_EVIDENCE_OK` (target_test_failed). Assessment: the failures were the planned assertions, run against scaffolding in which validate and resolve ignore `.desktop`. There were no build or load faults.
- **RED 2:** `swift test --filter DesktopLeafTests` exited 1 with 6 failures. Target `hidingTheDesktopWhileNothingIsDockedIsRefused()` failed with "an error was expected but none was thrown" against an empty `setDesktopHidden` stub. Classifier result: `RED_EVIDENCE_OK`. Assessment: the failures were the planned assertions. `removingTheLastDockedWindow…(hiddenFirst: true)` passed in RED only because the stub never hid the tile.
- **GREEN:** both feat commits pass their verify filters, which reported 22 and then 31 tests run.
- **Tracer gate (Task 1):** re-ran the verify commands (22 tests passed, no-appkit OK), then went on to Task 2.

## Decisions Made
- The Desktop tile takes the reserved ID `NodeID.desktop` (raw 0). This was the plan's discretion choice and is applied as written.
- If `desktopMinimum` alone cannot fit the area, `resolve` stops picking victims (it used to force-unwrap) and gives the Desktop the whole inner area. Every docked window is then unfit. The alternative was a crash or an error.
- In `PersistenceTests`, `deskJSON` adds node `"0"` by default. Each fixture places that node in its tree as an extra root-split child or as the root, and `desktopTile: false` builds the corrupt rows. `chainDesk` ends in the Desktop rather than panel 2000, so the depth-limit fixture keeps its depth.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `.desktop` arms to test-side Node switches**
- **Found during:** Task 1 RED
- **Issue:** after the new enum case, the tree helpers in `ResolveTests` and `TreeEditTests` and the `need` oracle in `ResolveFuzzTests` were no longer exhaustive.
- **Fix:** added `case .split, .desktop: break` to the helpers. The fuzz oracle returns nil for `.desktop`, because fuzzed trees are raw trees and never hold one.
- **Files modified:** Tests/PaneModelTests/ResolveTests.swift, TreeEditTests.swift, ResolveFuzzTests.swift
- **Commit:** 0c6c60d

**2. [Rule 1 - Bug] Guarded the unfit-victim loop when only the Desktop is too big**
- **Found during:** Task 1 GREEN
- **Issue:** with the Desktop never a candidate, a `desktopMinimum` larger than the area would make the victim loop force-unwrap nil and crash.
- **Fix:** the loop now stops when no window is left to take out. Covered by `aDesktopMinimumLargerThanTheAreaGetsTheWholeArea`.
- **Files modified:** Sources/PaneModel/Resolve.swift
- **Commit:** 7e8f0b6

**3. [Rule 1 - Fixture] UndoTests headroom test needed one fewer ID**
- **Found during:** Task 2 migration
- **Issue:** docking b beside `[a, Desktop]` now joins the existing split (1 ID, not 2), so `next: .max - 2` no longer exhausted the source.
- **Fix:** changed it to `next: .max - 1`. The test still checks that edits stop exactly where `make()` throws.
- **Commit:** f1267b3

Also updated with the migration: `ScenarioTests.dropTabAbsentPresentUndoAndPersist` now starts with a drop on the Desktop's left band. Its step 5 expects the tab group and the Desktop to share A's space. The test's intent is unchanged.

**Total deviations:** 3 auto-fixed (1 blocking, 1 bug, 1 fixture). **Impact:** no change to scope or API.

## Issues Encountered
- `swift format lint --strict` reports thousands of indentation errors across the existing code because the repo has no `.swift-format` config. This was there before the plan and is out of scope; it is not logged as a regression.

## User Setup Required
None.

## Next Phase Readiness
- Plans 02, 04 and 07 can build on `NodeID.desktop`, `Resolution.desktopRect`, `setDesktopHidden` and the Desktop-carrying v1 JSON.
- `selectTab` needs no Desktop arm: `leaf(containing:)` never returns the Desktop.

## Self-Check: PASSED
- FOUND: Tests/PaneModelTests/DesktopLeafTests.swift
- FOUND commits: 0c6c60d, 7e8f0b6, 8743fb7, f1267b3
- `swift test --filter 'PaneModelTests|PaneEngineTests'`: 159 and 234 tests passed, 0 failed
- `scripts/check-no-appkit.sh`: OK (25 files)
- All acceptance greps pass (each count >= 1)
