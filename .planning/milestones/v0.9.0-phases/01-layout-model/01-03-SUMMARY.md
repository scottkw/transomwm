---
phase: 01-layout-model
plan: 03
subsystem: layout-model
tags: [swift, swift-testing, geometry, water-filling, property-testing, hit-testing]

requires:
  - phase: 01-layout-model
    provides: "01-01 Geometry, LayoutTree, weight-only resolve(_:in:mins:gap:), Resolution, LayoutError"
provides:
  - "resolve(_:in:mins:gap:) with input validation, lifecycle exclusion (D-17), aggregate minimums, unfit selection with maximality (D-11) and water-filling (D-10)"
  - "DropZone, DropTarget, DropZones.target(at:in:tree:resolution:), edgeBandFraction = 0.25, displayEdgeBand = 24 (D-20)"
  - "ResolveTests (18), ResolveFuzzTests (30 seeds x 20 cases, P1-P8), DropZoneTests (8)"
affects: [01-04, 01-06, phase-3, phase-4]

actuals:
  tokens: 8405
  tasks: 3
  commits: 5
plan_head_before: 9573fc7a9fe998b3e368f1a394e6eaa441621174
plan_head_after: 7711f3a4ad09267b85c5ac52bb4f873cafdce2ec

tech-stack:
  added: []
  patterns:
    - "resolve never changes stored weights; minimums change geometry only"
    - "Greedy unfit removal, then re-admission in removal order, so no window that fits is left out"
    - "Property tests check against an independent aggregate-minimum checker in the test file, not the solver's internals"

key-files:
  created:
    - Sources/PaneModel/DropZones.swift
    - Tests/PaneModelTests/ResolveTests.swift
    - Tests/PaneModelTests/ResolveFuzzTests.swift
    - Tests/PaneModelTests/DropZoneTests.swift
  modified:
    - Sources/PaneModel/Resolve.swift

key-decisions:
  - "invalidMinimum reports the smallest bad WindowIdentity, so the error does not depend on dictionary order"
  - "Layout-edge band is strict (< 24 pt from the area edge); its left/right vs top/bottom choice uses the area midpoint, mirroring the tile rule"
  - "A tile's centre is the closed range [0.25, 0.75] on both axes, so exactly 0.25 and 0.75 count as centre"

patterns-established:
  - "Recursive Solver.aggregate/place over validated trees (depth <= 64); edits and validation stay iterative"
  - "RED commits for new public API carry a compiling stub so tests fail on assertions, not build errors"

requirements-completed: [MODEL-04, MODEL-08]

coverage:
  - id: D1
    description: "resolve honours minimum sizes by water-filling and leaves stored weights unchanged"
    requirement: MODEL-04
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#waterFillingPinsAChildBelowItsMinimumAndKeepsTheWeights()"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#exactFitPlacesBothAtTheirMinimum()"
        status: pass
    human_judgment: false
  - id: D2
    description: "Windows that cannot fit are reported unfit (NodeID tie-break, binding axis, maximality); never overlapped"
    requirement: MODEL-04
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#onePointShortUnfitsTheLargerNodeIDAndTheOtherFills()"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#readmitsAWindowThatFitsOnceALaterVictimLeaves()"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveFuzzTests.swift#resolvedLayoutsNeverOverlapAndHonourMinimums(seed:)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Absent and fullscreen windows keep their slot without taking space; present again restores identical rects"
    requirement: MODEL-08
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#absentWindowKeepsItsSlotAndPresentAgainRestoresTheSameRects()"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#tabGroupStaysPlacedWhileOneTabIsPresent()"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#fullscreenBehavesLikeAbsent()"
        status: pass
    human_judgment: false
  - id: D4
    description: "Invalid area, gap and minimum throw typed errors before any arithmetic (T-01-06)"
    requirement: MODEL-04
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#invalidAreaThrows(area:)"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#invalidGapThrows(gap:)"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveTests.swift#invalidMinimumThrows(min:)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Seeded property suite: no overlap, whole points inside the inset area, minimums, nothing lost, deterministic, split lengths add up, maximality"
    requirement: MODEL-04
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/ResolveFuzzTests.swift#resolvedLayoutsNeverOverlapAndHonourMinimums(seed:)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Drop-zone hit testing: tile centre/edge bands, layout edge, gaps and outside nil, empty layout"
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/DropZoneTests.swift (8 tests)"
        status: pass
    human_judgment: false
  - id: D7
    description: "Drop-zone band sizes (25% tile edge, 24 pt layout edge) feel right when dragging"
    verification: []
    human_judgment: true
    rationale: "The constants are starting values; whether they feel right can only be judged with drag previews in Phase 3 UAT"

duration: 7min
completed: 2026-10-24
status: complete
---

# Phase 1 Plan 03: Resolve Minimums, Unfit and Drop Zones Summary

**resolve now water-fills minimum sizes, reports windows that cannot fit as unfit (greedy removal plus re-admission), skips absent/fullscreen windows while keeping their slots, and rejects NaN/negative/out-of-range input. DropZones hit-tests resolved leaf rects for tile edge/centre, layout edge and empty-layout targets.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-10-24T05:06:48Z
- **Completed:** 2026-10-24T05:13:51Z
- **Tasks:** 3
- **Files modified:** 5 (1 modified, 4 created)

## Accomplishments
- `resolve` validates area, gap and every minimum first, then builds the active set from `.present` windows only. It computes aggregate minimums (a tabs leaf takes the max over its tabs; a split sums along its axis plus gaps and takes the max across), removes victims until the root fits, and re-admits them in removal order wherever they still fit. Each split is water-filled by its stored weights, renormalised among the children that take part.
- Rounding contract kept from Plan 01: the area snaps inward, the gap is rounded, each child but the last gets floor(share), and the last gets the remainder. Every rect is in whole points, and each split's lengths plus gaps add up exactly.
- ROADMAP criterion 2 is shown by `ResolveFuzzTests`: 600 random layouts (negative and fractional origins, gaps 0-40, minimums 0-600, about 20% absent or fullscreen) pass P1-P8.
- `DropZones.target(at:in:tree:resolution:)` covers every D-20 zone.

## Task Commits

1. **Task 1: minimums, unfit, lifecycle, validation**: `fd31883` (test, RED), `5996d41` (feat, GREEN)
2. **Task 2: seeded property suite**: `7b97110` (test)
3. **Task 3: drop-zone hit testing**: `d6e53d8` (test, RED), `7711f3a` (feat, GREEN)

## TDD Evidence
- **Task 1 RED** (`fd31883`): `NO_COLOR=1 swift test --filter ResolveTests` exited 1, with 11 of 18 tests failing. The classifier (swift-testing) returned `RED_EVIDENCE_OK` / `target_test_failed` for `waterFillingPinsAChildBelowItsMinimumAndKeepsTheWeights()`. Semantic assessment: the target failed on its planned rect assertions, because the weight-only layout gave A and B 500 each instead of 700/300. Every other failure is a planned `#expect`: validation throws nothing, and unfit/absent rects are wrong. The build succeeded and nothing crashed. The 7 tests that already passed (empty tree, single window, exact fit, gap-0 touching, fractional snap, determinism, mins outside the tree) describe behaviour the Plan 01 weight-only layout already had.
- **Task 1 GREEN** (`5996d41`): 18/18 pass, and so does the full suite.
- **Task 2:** this task only adds tests: a property suite over the Task 1 solver. It passed on its first run, which is expected because there is no new production code to drive. To show it has teeth, I ran two temporary mutations of Resolve.swift and reverted both (no diff). Skipping re-admission made P8 fail 74 times. Disabling pinning made several seeds fail.
- **Task 3 RED** (`d6e53d8`): `NO_COLOR=1 swift test --filter DropZoneTests` exited 1, with 7 of 8 failing. `RED_EVIDENCE_OK` / `target_test_failed` for `centreAndEdgeBandsOfATile()`. Semantic assessment: the stub `target(at:)` returned nil where `.tile(n1, .center)` was expected. The one passing test checks the constants, which the stub already declares.
- **Task 3 GREEN** (`7711f3a`): 8/8 pass. Full suite: 64 tests in 7 suites pass.

## Files Created/Modified
- `Sources/PaneModel/Resolve.swift`: validation, the active set, `Solver.aggregate`, unfit selection with re-admission, `Solver.place` water-filling
- `Sources/PaneModel/DropZones.swift`: `DropZone`, `DropTarget`, `DropZones` (constants and `target`)
- `Tests/PaneModelTests/ResolveTests.swift`: 18 example tests from the plan's behaviour list, plus a maximality re-admission case
- `Tests/PaneModelTests/ResolveFuzzTests.swift`: its own SplitMix64, an independent aggregate checker, P1-P8, and failures that record the seed, case, area, gap and tree
- `Tests/PaneModelTests/DropZoneTests.swift`: 8 tests covering the D-20 zones and boundaries

## Decisions Made
- `invalidMinimum` names the smallest bad identity, so the result is deterministic.
- Layout edge: a point counts when it is strictly less than 24 pt from the area edge. Horizontal wins ties against vertical, and the side is chosen by the area midpoint.
- Tile centre is the closed range [0.25, 0.75].

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The Task 3 RED commit carries a compiling stub**
- **Found during:** Task 3 (RED)
- **Issue:** DropZoneTests cannot compile without the new types, and a build failure counts as INVALID_RED.
- **Fix:** the RED commit declares `DropZone`, `DropTarget` and `DropZones` with a `target` that returns nil. The GREEN commit replaces the body. This is the same approach Plan 01-02 used.
- **Committed in:** d6e53d8

**2. [TDD note] Task 2 has no failing RED step**
- **Found during:** Task 2
- **Issue:** the task only adds tests, as a property suite over code that already exists, so it cannot fail first unless the solver has a bug.
- **Fix:** I committed it as `test(01-03)` and showed it has teeth with two reverted mutations (see TDD Evidence).

---

**Total deviations:** 2 (1 blocking, 1 TDD ordering note)
**Impact on plan:** none on the public API. All names and signatures match `<interfaces>`.

## Issues Encountered
None.

## Known Stubs
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 3 can turn `windowRects` into frames and `DropZones.target` into drag previews. Phase 4 can read `unfit` for the represented state.
- The drop-band constants still need tuning in UAT (D7).

## Self-Check: PASSED
- FOUND: Sources/PaneModel/DropZones.swift, Tests/PaneModelTests/ResolveTests.swift, Tests/PaneModelTests/ResolveFuzzTests.swift, Tests/PaneModelTests/DropZoneTests.swift
- FOUND commits: fd31883, 5996d41, 7b97110, d6e53d8, 7711f3a

---
*Phase: 01-layout-model*
*Completed: 2026-10-24*
