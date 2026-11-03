---
phase: 07-tab-groups
plan: 10
subsystem: tiling
tags: [swift, tab-groups, safety, quit-restore, restore-all, crash-recovery, persistence]

requires:
  - phase: 07-tab-groups
    plan: 09
    provides: tab commands, tabGroupCounts
  - phase: 07-tab-groups
    plan: 08
    provides: moveOutCascade, commitTearOff pattern
  - phase: 07-tab-groups
    plan: 05
    provides: minimised-selected participation rule (hidden member not recorded as parked)
provides:
  - Arranger.groupContentRects() (every member of every group, every desk, at its home-view content rect)
  - Arranger.selectedGroupMembers() (present selected members, raised last at quit)
  - Arranger.dissolveAllGroups() (Restore All: one undo step per desk, cascade 24 pt, faults per desk)
  - Arranger.regroupedLog(saved:) ("relaunch: group {node} re-formed with {n} of {m} members")
  - AXWindowSystem.restoreForTermination(_:raising:deadline:), AXAppThread.raiseForTermination
  - VM test quitPlacesEveryGroupMemberAtTheContentRect
affects: [07-11, 07-12]

estimate:
  tokens: 110000
actuals:
  tokens: 9600
  tasks: 3
  commits: 3
plan_head_before: ddb135f06ef34bb760f56b6790b32d6d09245d32
plan_head_after: c8b76beea35ab500c04a9a61876fb53f4e6c2745

tech-stack:
  added: []
  patterns:
    - "Quit plan: group members count as docked, with groupContentRects merged over homeTiles (group rects win), so a desk at home still gets targets for its hidden tabs"
    - "Restore All dissolves groups first and spares the dissolved members from rescueStranded, so neither the rescue nor the replan moves them off their cascade"

key-files:
  created:
    - .planning/phases/07-tab-groups/07-10-SUMMARY.md
  modified:
    - Sources/TransomEngine/Arranger+Tabs.swift
    - Sources/TransomEngine/Arranger+Commands.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/AXWindowSystem.swift
    - Sources/TransomMac/AX/AXAppThread.swift
    - Tests/TransomEngineTests/ArrangerTabsTests.swift
    - Tests/TransomMacTests/LayoutStoreTests.swift
    - Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift

key-decisions:
  - "groupContentRects plans every desk at home (not only desks away from home as homeTiles does); a docked group whose leaf has no planned rect (collapsed, or its selected member minimised, 07-05) gets none, so its parked hidden members fall to the stranded rule and come back centred on screen"
  - "The quit raise runs on each app's AX thread after that app's writes, within the same deadline, only for present selected members (a minimised one is never raised)"
  - "The VM quit test pauses arranging right after restoreForTermination (no await between them) in place of dropping the controller, which the shared SavedGroup helper keeps alive"
  - "Restore All: a docked group with no planned tile is left alone and not counted; a desk whose groups cannot be planned or edited logs a fault and Restore All still rescues (it is the way back, so one desk must not block it)"
  - "N2 carries only the unplaced count, so 'N2 counts the parked members' is met as: the parked member is in the rescue perform and is not counted as unplaced (crashRecovered(unplaced: 0)); no new copy"

patterns-established:
  - "Safety log lines name NodeIDs and counts only: 'quit: {w} group members placed at their content rects', 'restore all: dissolved {g} groups, {w} windows brought back', 'relaunch: group {node} re-formed with {n} of {m} members'"

requirements-completed: [TABS-02, TABS-05, TABS-01]

coverage:
  - id: D1
    description: "Quit places every member of every group (docked, floating, every desk, zoomed or at home) at its content rect, selected raised last"
    requirement: TABS-02
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabSafetyTests (groupContentRects x3, minimised-selected stranded rule)"
        status: pass
      - kind: integration
        ref: "Tests/TransomMacIntegrationTests/TabGroupIntegrationTests.swift#quitPlacesEveryGroupMemberAtTheContentRect (VM)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Restore All dissolves every group first (selected keeps the tile or whole frame, others cascade 24 pt clamped into the Desktop, hidden Desktop shown), one undo step per desk, N6 counts the members once, Undo re-forms the group"
    requirement: TABS-05
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabSafetyTests (5 restoreAll tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Crash relaunch rescues the parked member then re-forms and re-parks it; a missing member re-forms (right neighbour selected), dissolves or removes the group with the relaunch log; groups round-trip through layout.json"
    requirement: TABS-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerTabsTests.swift#ArrangerTabSafetyTests; Tests/TransomMacTests/LayoutStoreTests.swift#dockedAndFloatingTabGroupsRoundTripWithTheirSelections"
        status: pass
    human_judgment: false
  - id: D4
    description: "Live: kill -9 and relaunch with groups shows N2 and re-forms the groups with the same selected tabs"
    requirement: TABS-01
    verification:
      - kind: manual
        ref: "VM UAT backstop at phase close (07-11)"
        status: pending
    human_judgment: true
    rationale: "Crash simulation runs only in the VM; this plan's VM run covers the quit path only"

duration: 25min
completed: 2026-11-02
status: complete
---

# Phase 7 Plan 10: Tab Group Safety Paths Summary

**A hidden tab can no longer be left off screen. On quit, every member of every group goes to its group's content rect with the selected window raised last (proved in the VM). Restore All Windows first dissolves every group, reversibly with one undo step per desk. A crash relaunch rescues parked members and then re-forms the saved groups, and a relaunch with members missing re-forms or dissolves the group and logs it.**

## Performance

- **Duration:** about 25 min
- **Completed:** 2026-11-02T03:13Z
- **Tasks:** 3
- **Files modified:** 9 (423 insertions, 20 deletions)

## Accomplishments

- **Quit (D-07):** `groupContentRects()` plans every desk at home and maps each docked group member to its leaf rect minus the band, and each floating group member to its planned (or stored) frame minus the band. `restoreForTermination` adds every group member to `docked` and merges these rects over `homeTiles()`, so the hidden tabs on a desk at home now get a target. It then raises each present selected member on its app's AX thread inside the same deadline and logs "quit: {w} group members placed at their content rects".
- **Restore All (D-07, Pitfall 3):** `dissolveAllGroups()` makes one `World.edit` per desk that holds groups, in key order, showing a hidden Desktop first. A docked group's non-selected members leave the tree, so the selected one stays a plain panel under the same NodeID. A floating group is removed and its selected member re-added at the whole frame. The other members float at the content size, 24 pt apart from the group's top-left, clamped into the Desktop tile. `restoreAll` keeps those members out of `rescueStranded`, adds them to N6 and logs "restore all: dissolved {g} groups, {w} windows brought back".
- **Relaunch (D-13):** the close path already re-formed, dissolved or removed groups whose members are gone. The new `regroupedLog(saved:)` compares the saved groups with what was re-attached and logs one line per group that shrank.
- **Persistence:** docked and floating groups, with their selected tabs, round-trip through `LayoutStore` unchanged.

## Task Commits

1. **Task 1: Tracer, quit puts every group member at the content rect (VM)** - `1dbbe59` (feat)
2. **Task 2: Restore All dissolves groups first** - `ffc50bf` (feat)
3. **Task 3: Crash relaunch, missing members, round trip** - `c8b76be` (feat)

## Verification

- Task 1: `swift test --filter 'ArrangerTabsTests|RecoveryTests'` ran 147 tests and all passed, and `swift build --build-tests` succeeded. In the VM, `scripts/vm-live-test.sh TabGroupIntegrationTests` printed "Test run with 5 tests in 1 suite passed", including `quitPlacesEveryGroupMemberAtTheContentRect`. That passing `<verify>` run was also the tracer gate.
- Task 2: 198 tests passed (the tab suites, ArrangerTabSafetyTests, ArrangerRestoreTests, ArrangerCommandTests, ArrangerCameraTests).
- Task 3: the full `swift test` passed (219, 384, 93 and 948 tests across the runs, no "✘"), and `scripts/check-no-appkit.sh` passed (55 files).
- No live code ran on the host. The integration suites are skipped there because `TRANSOM_LIVE` is not set.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The 07-05 minimised-selected case had no quit target**
- **Found during:** Task 3 (the check the orchestrator asked for)
- **Issue:** When a docked group's selected member is minimised, the planner gives the leaf no rect, so `groupContentRects()` has nothing for the hidden member, which is still parked.
- **Fix:** No new target. The hidden member stays in `docked` with no home tile, so `terminationPlan`'s stranded rule brings it back centred on screen. A test pins this, and the doc comment now says so. Restore All also leaves such a group alone (the rescue brings the member back) and does not count it as dissolved.
- **Files modified:** Sources/TransomEngine/Arranger+Tabs.swift, Tests/TransomEngineTests/ArrangerTabsTests.swift
- **Commit:** c8b76be

**2. [Rule 2 - Missing critical functionality] Restore All could fail completely on one desk**
- **Found during:** Task 3
- **Issue:** `dissolveAllGroups` was first written as a throwing function. If any desk could not be planned or edited, the throw aborted all of Restore All, including the stranded rescue, and Restore All is the safety command.
- **Fix:** It no longer throws. A desk it cannot dissolve keeps its groups and adds a `.fault`, and the rest of Restore All still runs. Desks without groups are skipped before any planning.
- **Commit:** c8b76be

**3. [Interpretation] "N2's count includes it"**
- N2 (`crashRecovered(unplaced:)`) only counts windows that could not be placed, and its copy names no rescued count. The crash test therefore checks that the parked member is in the rescue perform and that N2 says `unplaced: 0`. Changing the copy was not in scope.

**4. [Test shape] The VM quit test pauses instead of dropping the controller**
- The shared `SavedGroup` helper keeps the controller alive. The test calls `setPaused(.user, true)` right after `restoreForTermination`, with no suspension in between, so nothing reacts to the restore's moves. `planShown` writes nothing while paused.

**5. [Process] The formatter rewrote the whole file**
- `swift format -i` on `Arranger+Tabs.swift` re-indented the whole file because the repo has no `.swift-format`. The file was restored from HEAD and only this plan's edits were re-applied before the commit. No formatting changes were committed.

## Known Stubs

None.

## Threat Flags

None. T-07-22 is mitigated: quit, crash relaunch and Restore All all bring hidden members on screen, and the VM quit test covers quit. T-07-23 is mitigated by the three log lines, which carry only NodeIDs and counts.

## Next

07-11 (VM UAT backstop): kill -9 and relaunch with groups, then check that N2 appears and the groups re-form with the same selected tabs.

## Self-Check: PASSED
