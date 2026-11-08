---
phase: 01-layout-model
plan: 04
subsystem: layout-model
tags: [swift, swift-testing, codable, undo, persistence, migration]

requires:
  - phase: 01-layout-model (01-01)
    provides: "Desk, World(ids:desks:), LayoutTree validate/insert, World.encoded()/decode(from:), PersistenceError"
provides:
  - "FloatingWindow and DesktopLayer (add/remove/setFrame/frame(of:)/contains/validate), back-to-front order"
  - "Desk.desktop, Desk.init(tree:desktop:), Desk.contains(_:), Desk.validate(); World.validate() counts floating windows across desks"
  - "World.addDesk(_:), transactional World.edit(_:history:_:), World.undo(_:history:)"
  - "UndoHistory: per-desk Desk snapshots capped at 50, session-only (not Codable)"
  - "World.maxEncodedBytes = 16 MiB, MigrationChain (standard has no steps), World.decode(from:migrations:)"
  - "DesktopLayerTests (11), UndoTests (9), PersistenceTests (13 incl. 17-item corrupt corpus)"
affects: [01-05, 01-06, phase-3, phase-8]

actuals:
  tokens: 10783
  tasks: 3
  commits: 6
plan_head_before: 9a2a4794935aa60d61771dd8cb42939daef5d96c
plan_head_after: f3b04c600e56da78be2b462a855a7562f96e333d

tech-stack:
  added: []
  patterns:
    - "Every desk change goes through World.edit: run on copies, validate the whole World, then push the snapshot and commit"
    - "Undo pops on a copy of the history and validates before committing; IDSource is never rewound"
    - "Version-1 files decode the original bytes; only older files go through JSONSerialization and the migration chain"

key-files:
  created:
    - Sources/PaneModel/DesktopLayer.swift
    - Sources/PaneModel/Undo.swift
    - Tests/PaneModelTests/DesktopLayerTests.swift
    - Tests/PaneModelTests/UndoTests.swift
    - Tests/PaneModelTests/PersistenceTests.swift
  modified:
    - Sources/PaneModel/World.swift
    - Sources/PaneModel/Persistence.swift

key-decisions:
  - "Desk encodes as synthesised keys tree and desktop; DesktopLayer decoding does not self-validate, World validates every desk it is built from"
  - "A stored .closed floating state throws invariantViolated; a bad floating frame throws invalidGeometry"
  - "Every successful edit pushes a snapshot, including one that changes nothing"
  - "MigrationChain.migrate commits to the object only if every step succeeds; a throwing step maps to .corrupt"

patterns-established:
  - "Transactional World edit funnel: closure over (inout Desk, inout IDSource), validate, then commit"
  - "Corrupt-file corpus as a parameterised @Test(arguments:) over hand-built JSON fixtures checked against a valid baseline"

requirements-completed: [MODEL-05, MODEL-07, MODEL-09, MODEL-10]

coverage:
  - id: D1
    description: "Each desk holds a tiled tree plus a floating Desktop layer; a window cannot be both docked and floating, or on two desks"
    requirement: MODEL-05
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/DesktopLayerTests.swift (11 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Transactional desk edits with 50-level per-desk undo that never rewinds IDs and refuses cross-desk duplicates"
    requirement: MODEL-10
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/UndoTests.swift (9 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "DeskKey with spaceID nil and 7 on one display are distinct desks through lookup and round-trip"
    requirement: MODEL-07
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/PersistenceTests.swift#nilAndNonNilSpaceOnOneDisplayAreDistinctDesks"
        status: pass
    human_judgment: false
  - id: D4
    description: "Exact byte round-trip, version gate, migration chain, corrupt corpus and 16 MiB cap"
    requirement: MODEL-09
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/PersistenceTests.swift (13 tests, corpus of 17)"
        status: pass
    human_judgment: false

duration: 7min
completed: 2026-10-24
status: complete
---

# Phase 1 Plan 04: Desktop Layer, Undo and Hardened Persistence Summary

**Every desk now has a floating Desktop layer next to its tile tree. All desk edits go through one transactional `World.edit` funnel that keeps 50 undo levels per desk. Loading is hardened: a 16 MiB cap, a refusal for newer schema versions, a step-by-step `MigrationChain` for older ones, and a 17-item corrupt-file corpus that throws instead of crashing.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-10-24T05:16:40Z
- **Completed:** 2026-10-24T05:23:26Z
- **Tasks:** 3
- **Files modified:** 7 (5 created, 2 modified)

## Accomplishments
- `DesktopLayer` keeps windows in back-to-front order through add, setFrame, remove and JSON. Duplicate, unknown and invalid-frame calls throw and leave the layer unchanged. Negative origins are accepted.
- `Desk.validate()` and `World.validate()` refuse any window that is both docked and floating, or that sits on two desks, whether docked or floating.
- `World.edit` runs the change on copies of the desk and the IDSource and validates the whole candidate World. Only then does it push the pre-edit snapshot and commit. A failed edit uses up no NodeIDs.
- `World.undo` is last-in first-out, per desk and capped at 50. It never rewinds IDSource. If restoring a snapshot would put a window on two desks, it throws `duplicateWindow` and leaves both the World and the history as they were.
- A rich World (nested splits, tabs, absent/fullscreen states, floating windows, nil and non-nil axIdentifier, weights 1/3, 2/3 and 0.1/0.9, IDSource 2^53+1) round-trips with `==` and byte-identical re-encoding.
- `swift test`: 97 tests in 10 suites pass, with no warnings.

## Task Commits

1. **Task 1: Floating Desktop layer**: RED `01c7784` (test), GREEN `d8fc5bf` (feat)
2. **Task 2: Transactional edits + per-desk undo**: RED `1fd56dd` (test), GREEN `e38841b` (feat)
3. **Task 3: Hardened persistence**: RED `4d88af6` (test), GREEN `f3b04c6` (feat)

No refactor commits were needed.

## TDD Gate Compliance

Each task has a `test(01-04)` commit followed by a `feat(01-04)` commit. As in Plans 01-02 and 01-03, each RED commit includes compiling stubs, so the tests fail on assertions and not on build errors.

- **Task 1 RED:** `NO_COLOR=1 swift test --filter DesktopLayerTests` exited 1 with 10 of 11 tests failing. The classifier returned `RED_EVIDENCE_OK` / `target_test_failed` for `duplicateAddThrowsAndChangesNothing()`. Semantic check: the target failed on its planned `#expect(throws: LayoutError.duplicateWindow(a))` ("an error was expected but none was thrown"). The build was clean and there were no load faults. The one test that passed checks that a new desk's layer is empty, which the stub already satisfies.
- **Task 2 RED:** 8 of 9 tests failed. The classifier returned `RED_EVIDENCE_OK` for `addDeskCreatesEmptyDeskAndUnknownKeysThrow()`. Semantic check: the target failed on the planned deskExists/deskNotFound expectations and on `world[k1] == Desk()`. The test that passed checks that undo with an empty history returns false, which the stub already does.
- **Task 3 RED:** 5 of 13 tests failed. The classifier returned `RED_EVIDENCE_OK` for `oversizedInputIsRejectedBeforeParsing()`. Semantic check: the target got `.corrupt` where it expected `.tooLarge(bytes:limit:)`, because the stub parsed the oversized data. The round-trip, version-gate and corpus tests already passed in RED, because Plan 01's validation and Task 1's desk validation cover them. Those tests pin behaviour in place. They are not new behaviour.
- GREEN: each target suite and the full suite passed after the matching `feat` commit.

## Files Created/Modified
- `Sources/PaneModel/DesktopLayer.swift`: FloatingWindow and DesktopLayer
- `Sources/PaneModel/Undo.swift`: UndoHistory with per-desk stacks capped at 50
- `Sources/PaneModel/World.swift`: Desk.desktop/contains/validate, floating windows in the cross-desk check, addDesk/edit/undo
- `Sources/PaneModel/Persistence.swift`: maxEncodedBytes, decode(from:migrations:), MigrationChain
- `Tests/PaneModelTests/DesktopLayerTests.swift`, `UndoTests.swift`, `PersistenceTests.swift`: the three new suites

## Decisions Made
- `undo` pops from a copy of the history rather than adding an internal `peek`, so the existing push/pop API was enough.
- Decoding a `DesktopLayer` does not validate it on its own. The validating path is `World.init(ids:desks:)`, which every decode goes through, so a negative width or a 1e300 coordinate surfaces as `.invalidLayout(.invalidGeometry)`.
- An unknown `Node` case maps to `.corrupt` and not `.invalidLayout`, because the file does not parse as the schema.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] RED commits carry compiling stubs**
- **Found during:** Tasks 1-3 (RED)
- **Issue:** the new tests cannot compile without the new types and methods, and a build failure counts as INVALID_RED.
- **Fix:** each RED commit declares the public signatures with empty bodies, and the GREEN commit fills them in. This matches Plans 01-02 and 01-03.
- **Committed in:** 01c7784, 1fd56dd, 4d88af6

**2. [Rule 2 - Coverage] Extra tests beyond `<behavior>`**
- **Found during:** Task 3
- **What:** added `handBuiltBaselineFixtureIsValid` (proves each corpus fixture is invalid for its intended reason only), `throwingMigrationStepIsCorrupt`, and `olderFileDecodesThroughTheChain` (an end-to-end schema-0 file decoded through a test chain).
- **Committed in:** 4d88af6

---

**Total deviations:** 2 (1 blocking, 1 coverage addition)
**Impact on plan:** all public names and signatures match `<interfaces>`. No scope creep.

## Issues Encountered
- The plan asked to stop if IDSource 2^53+1 did not round-trip exactly. It round-trips exactly through JSONEncoder/JSONDecoder, so no action was needed. The migration path goes through JSONSerialization, which may not keep integers that large exact. This is noted in a code comment, and `olderFileDecodesThroughTheChain` therefore compares desks, not `ids`.

## Known Limitations
- `World.validate()` runs over all desks on every edit and undo. That is O(total windows) and fine at current limits.
- `MigrationChain.standard` has no steps, because schema 1 is the first version.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 3 can use `World.edit` / `World.undo` as the single path for desk changes, and `decode` for saved layouts.
- The orchestrator should note that work is still on branch `gsd/phase-01-layout-model`.

## Self-Check: PASSED
- All 7 key files exist on disk
- Commits 01c7784, d8fc5bf, 1fd56dd, e38841b, 4d88af6, f3b04c6 are ancestors of HEAD. `check evaluation-scope --plan 01-04 --commits-only` resolved them.
- Plan verification: `swift test` exit 0, 97 tests in 10 suites, no `✘`. `grep -rhE "^import " Sources/PaneModel | sort -u` prints only `import Foundation`.
- All acceptance criteria for Tasks 1-3 were re-run and pass.

---
*Phase: 01-layout-model*
*Completed: 2026-10-24*
