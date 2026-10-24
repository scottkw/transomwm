---
phase: 01-layout-model
plan: 02
subsystem: layout-model
tags: [swift, swift-testing, value-types, fuzzing]

requires:
  - phase: 01-01
    provides: "LayoutTree flat store, validate()/assertValid(), insertRoot/insert, LayoutError, IDSource"
provides:
  - "LayoutTree.remove(_:): proportional redistribution of a panel's share (D-05); tabs shrink, a two-tab group becomes a panel under the same NodeID"
  - "LayoutTree.normalize() (internal, throws): collapse single-child splits, merge same-axis child splits, renormalise and clamp weights to minWeight (D-06)"
  - "LayoutTree.resizeBoundary(in:after:by:): reweighs only the two neighbours of a boundary (D-07)"
  - "insert(_:at:of:ids:) now normalises, so the n/(n+1) scaling is clamped"
  - "TreeEditTests (16 tests) and TreeFuzzTests (20 seeds x 100 random edits)"
affects: [01-03, 01-04, 01-05, phase-3]

actuals:
  tokens: 5252
  tasks: 2
  commits: 4
plan_head_before: d265142ad04c5b0d7bd1fcd76e510617583aa54a
plan_head_after: 1ff76469fa7379d4dc40adef6242e1ef6c59e14e

tech-stack:
  added: []
  patterns:
    - "normalize() runs on the working copy of every edit (insert, remove, resizeBoundary) before commit"
    - "Weights already normalised (sum within 1e-12, each >= minWeight - 1e-12) are left bit-identical"
    - "Seeded SplitMix64 fuzz with sorted node IDs so a seed replays exactly across processes"

key-files:
  created:
    - Tests/PaneModelTests/TreeEditTests.swift
    - Tests/PaneModelTests/TreeFuzzTests.swift
  modified:
    - Sources/PaneModel/TreeEdits.swift

key-decisions:
  - "normalize() is `throws(LayoutError)`: a same-axis merge that would exceed maxChildren throws splitFull and the edit is rolled back, rather than leaving an invalid tree"
  - "remove() lets normalize() renormalise the remaining weights; dividing by their sum is the proportional redistribution"
  - "normalize() skips the weight pass for splits that are already normalised, so resizeBoundary can call it and still keep the other weights bit-identical"

patterns-established:
  - "Structural rules (collapse, merge) repeat until stable; weights are renormalised once afterwards, so floating-point drift cannot loop the structural pass"

requirements-completed: [MODEL-01, MODEL-02, MODEL-03, MODEL-06]

coverage:
  - id: D1
    description: "Removing a window gives its share back to its siblings proportionally; unknown windows throw windowNotFound and change nothing; removing the last window empties the tree"
    requirement: MODEL-03
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/TreeEditTests.swift#removeRedistributesShareProportionally, removingAnUnknownWindowThrowsAndChangesNothing, removingTheLastWindowEmptiesTheTree"
        status: pass
    human_judgment: false
  - id: D2
    description: "Single-child splits collapse into their slot; same-axis child splits merge with weights multiplied by the slot weight; weights below minWeight are clamped"
    requirement: MODEL-01
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/TreeEditTests.swift#removingOneOfTwoCollapsesTheSplit, innerSplitTakesTheRootSlot, collapseMergesSameAxisChildIntoParent, mergedWeightsBelowMinimumAreClamped, insertBesideANearMinimumSiblingClampsIt, mergePastMaxChildrenThrowsAndChangesNothing"
        status: pass
    human_judgment: false
  - id: D3
    description: "Removing from a tab group keeps selection in range; a group of two becomes a panel with the same NodeID"
    requirement: MODEL-06
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/TreeEditTests.swift#removingFromThreeTabsKeepsATabGroup, removingFromTwoTabsLeavesAPanelWithTheSameID"
        status: pass
    human_judgment: false
  - id: D4
    description: "resizeBoundary moves weight between the two neighbours only, clamps both, and rejects bad input with typed errors without changing the tree"
    requirement: MODEL-02
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/TreeEditTests.swift#resizeMovesWeightBetweenTheTwoNeighboursOnly, resizeClampsBothNeighboursToTheMinimum, resizeRejectsUnknownNodesAndNonSplits, resizeRejectsBoundariesOutsideTheSplit, resizeRejectsNonFiniteDeltas"
        status: pass
    human_judgment: false
  - id: D5
    description: "Random insert/remove/resize/must-throw sequences over 20 seeds keep validate() passing and the window set as expected after every operation"
    requirement: MODEL-01
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/TreeFuzzTests.swift#randomEditsKeepEveryInvariant(seed:)"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-10-24
status: complete
---

# Phase 1 Plan 02: Remove, Normalise and Resize Summary

**Window removal with i3-style proportional redistribution, a D-06 normaliser (collapse, same-axis merge, renormalise, minWeight clamp) run by every edit, two-neighbour boundary reweighing, and a 20-seed edit fuzz suite**

## Performance

- **Duration:** 5 min
- **Started:** 2026-10-24T04:58:11Z
- **Completed:** 2026-10-24T05:03:53Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- `remove(_:)`: a panel's share goes to its siblings in proportion. Tab groups shrink with the selection kept in range, and a group of two becomes a panel under the same NodeID. Removing the last window leaves an empty, valid tree.
- `normalize()`: collapses single-child splits (the child keeps the slot's weight), merges same-axis child splits (grandchild weights multiplied by the slot weight), then renormalises and clamps every split's weights. Explicit worklist, no recursion.
- `insert` now normalises too, which closes the unclamped n/(n+1) limit left by Plan 01 (WINDOWS.md entry 1 marked fixed).
- `resizeBoundary(in:after:by:)`: moves weight only between the two children either side of the boundary. Both are clamped to `minWeight`, every other weight stays bit-identical, and bad input throws a typed error with the tree unchanged.
- `swift test`: 37 tests in 4 suites pass, including 16 TreeEditTests and 20 fuzz seeds.

## Task Commits

1. **Task 1 RED: failing removal/normalisation tests** - `c0c288e` (test)
2. **Task 1 GREEN: remove + normalize, insert normalises** - `cab6a27` (feat)
3. **Task 2 RED: failing resizeBoundary tests + fuzz suite** - `197997b` (test)
4. **Task 2 GREEN: resizeBoundary** - `1ff7646` (feat)

## TDD Evidence

- **Task 1 RED** (`c0c288e`): `NO_COLOR=1 swift test --filter TreeEditTests` exited 1, with 9 of 9 tests failing on assertions. The classifier (`check tdd-red-evidence`, swift-testing) returned `RED_EVIDENCE_OK` / `target_test_failed` for `removingAnUnknownWindowThrowsAndChangesNothing()`. Semantic assessment: the target ran and failed its planned `#expect(throws: LayoutError.windowNotFound(d))` ("an error was expected but none was thrown"). Every other failure is an `#expect` on the planned tree shape. The build succeeded, and there were no crashes or load faults. `remove(_:)` was an empty stub so the suite could compile.
- **Task 1 GREEN** (`cab6a27`): 11 TreeEditTests pass, and `swift test` passes 31/31.
- **Task 2 RED** (`197997b`): `NO_COLOR=1 swift test --filter "TreeEditTests|TreeFuzzTests"` exited 1, with 5 of 17 failing, all of them the new resize tests. `RED_EVIDENCE_OK` / `target_test_failed` for `resizeMovesWeightBetweenTheTwoNeighboursOnly()`. Semantic assessment: the target failed its planned weight assertions because the weights were unchanged at [0.5, 0.3, 0.2]. The fuzz suite already passed at RED. That is expected: it is a property test over the real insert/remove from Task 1, and the resize stub was an empty body that cannot break an invariant.
- **Task 2 GREEN** (`1ff7646`): `swift test` passes 37/37 with no `✘`.

## Files Created/Modified
- `Sources/PaneModel/TreeEdits.swift` - remove, resizeBoundary, normalize, collapseOrMergeOnce, isNormalised, clamped. insert calls normalize. Plan 01's `shortcut:` comment is removed.
- `Tests/PaneModelTests/TreeEditTests.swift` - 16 example tests for removal, collapse, merge, clamp, tabs and resize
- `Tests/PaneModelTests/TreeFuzzTests.swift` - file-private `SplitMix64` and a 20-seed fuzz of 100 operations per seed

## Decisions Made
- `normalize()` throws instead of being non-throwing (see deviation 1).
- The weight pass only touches splits that are not already normalised (sum within 1e-12, each >= minWeight − 1e-12). Renormalising an already normalised array is the identity mathematically, so skipping it changes nothing except that the bits are kept. That lets `resizeBoundary` call `normalize()` (the plan's key link) and still meet D-07's bit-identical rule.
- Collapse and merge loop until stable, and the weights are renormalised once afterwards. If renormalisation were part of the "changed" loop, floating-point drift could keep it changing forever.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A same-axis merge could exceed maxChildren**
- **Found during:** Task 1
- **Issue:** H[50 panels, V[B, H[60 panels]]] minus B collapses V and merges the inner H into the root, giving 109 children. validate() rejects that, and assertValid() would trap in DEBUG. The plan specified a non-throwing normalize().
- **Fix:** `normalize()` is `throws(LayoutError)` and throws `.splitFull(split, limit: 100)` before such a merge. Every edit runs it on the working copy, so the tree stays unchanged. The acceptance grep `func normalize()` still matches.
- **Files modified:** Sources/PaneModel/TreeEdits.swift, Tests/PaneModelTests/TreeEditTests.swift (`mergePastMaxChildrenThrowsAndChangesNothing`)
- **Committed in:** cab6a27

**2. [Rule 3 - Blocking] RED commits carry empty stubs**
- **Found during:** Tasks 1 and 2 (RED)
- **Issue:** Tests that call `remove` or `resizeBoundary` cannot compile without those functions, and a build failure is INVALID_RED.
- **Fix:** each RED commit adds the public signature with an empty body, so the tests fail on assertions. The matching GREEN commit replaces it.
- **Committed in:** c0c288e, 197997b

**3. [TDD note] The insert-clamp regression test landed with GREEN, not RED**
- **Found during:** Task 1
- **Issue:** without normalize(), `insertBesideANearMinimumSiblingClampsIt` traps in `assertValid()` (precondition failure). That kills the whole test process, so it cannot produce assertion-level RED evidence.
- **Fix:** it was added in the GREEN commit `cab6a27` as the regression test for the Plan 01 limit (WINDOWS.md entry 1).

---

**Total deviations:** 3 (1 bug, 1 blocking, 1 TDD ordering note)
**Impact on plan:** public signatures match `<interfaces>`. The only contract change is that internal `normalize()` throws. No scope creep.

## Issues Encountered
- My first expected values for the insert-clamp test assumed n/(n+1) = 1/2 for two siblings. It is 2/3. I fixed the test's arithmetic, not the code.

## Known Stubs
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plans 01-03 to 01-05 can rely on insert, remove and resizeBoundary always leaving a normalised, valid tree.
- No API creates tab groups yet. The tabs removal paths are covered by example tests on trees built with the validating init, but not by the fuzz suite. Plan 01-05 (tabs) should add tab operations to the fuzz.
- Phase 3 must handle `splitFull` from `remove` (only reachable with more than 100 tiles across a merge). A closed window that cannot be removed stays in the tree.

## Self-Check: PASSED
- Files exist: Sources/PaneModel/TreeEdits.swift, Tests/PaneModelTests/TreeEditTests.swift, Tests/PaneModelTests/TreeFuzzTests.swift
- Commits c0c288e, cab6a27, 197997b, 1ff7646 are ancestors of HEAD (`git rev-list --count d265142..HEAD` = 4)
- Acceptance greps: remove signature 1, `func normalize()` 1, resizeBoundary signature 1, SplitMix64 2, `arguments: 0..<20` 1
- `swift test --filter TreeEditTests`: 16 passed. `swift test --filter TreeFuzzTests`: passed (1 test, 20 cases). `swift test`: exit 0, 37 tests in 4 suites, no `✘`
- `grep -rhE "^import " Sources/PaneModel | sort -u` prints only `import Foundation`

---
*Phase: 01-layout-model*
*Completed: 2026-10-24*
