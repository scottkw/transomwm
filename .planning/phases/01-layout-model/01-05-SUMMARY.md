---
phase: 01-layout-model
plan: 05
subsystem: layout-model
tags: [swift, swift-testing, tabs, lifecycle, drop-zones, undo, persistence]

requires:
  - phase: 01-02
    provides: "remove(_:) with tab handling and normalisation, edit fuzz suite"
  - phase: 01-03
    provides: "resolve excluding non-present windows, tabs as one rect, DropZones.target hit testing"
  - phase: 01-04
    provides: "Desk, DesktopLayer, World.edit/undo funnel, hardened JSON persistence"
  - phase: 01-06
    provides: "no-AppKit check script"
provides:
  - "LayoutTree.group(_:into:): a panel becomes tabs [existing, new] under the same NodeID; tabs append and select (MODEL-06)"
  - "LayoutTree.selectTab(_:) with notATabGroup / windowNotFound"
  - "LayoutTree.setState(_:for:): absent/fullscreen change states only; closed delegates to remove (MODEL-08, D-17)"
  - "Desk.setState(_:for:) for docked and floating windows; DesktopLayer.setState(_:for:) keeps the frame and refuses .closed"
  - "LayoutTree.applyDrop(_:window:ids:): the DropTarget-to-edit mapping (D-20)"
  - "TabsTests (7), LifecycleTests (10 incl. 2 parameterised cases), ScenarioTests (7 incl. 4 parameterised cases)"
  - "TreeFuzzTests now groups into leaves and switches tabs"
affects: [phase-2-window-control, phase-3-drag-docking]

actuals:
  tokens: 6931
  tasks: 3
  commits: 7
plan_head_before: dcf1fa0d9ebbb1dcdcea0fe0cca920fbe6736bea
plan_head_after: 194f488e1db535c0fc3a7ce1fe33284ca6db92b6

tech-stack:
  added: []
  patterns:
    - "Lifecycle transitions touch `states` only; `nodes` stays bit-identical, so the slot is reserved and resolve restores the same Resolution"
    - "applyDrop is a pure mapping onto existing transactional edits; it adds no validation of its own"
    - "Cross-layer duplicates (a floating window dropped into the tree) are caught by World.edit's whole-World validate, not by the tree edit"

key-files:
  created:
    - Tests/PaneModelTests/TabsTests.swift
    - Tests/PaneModelTests/LifecycleTests.swift
    - Tests/PaneModelTests/ScenarioTests.swift
  modified:
    - Sources/PaneModel/TreeEdits.swift
    - Sources/PaneModel/World.swift
    - Sources/PaneModel/DesktopLayer.swift
    - Sources/PaneModel/DropZones.swift
    - Tests/PaneModelTests/TreeFuzzTests.swift

key-decisions:
  - "group(_:into:) checks duplicate identity first, then target existence, then leaf-ness, so a docked window always reports duplicateWindow"
  - "Desk.setState delegates closing a floating window to DesktopLayer.remove and other states to DesktopLayer.setState; both throw windowNotFound for an unknown window, so Desk needs no extra lookup"
  - "DesktopLayer.setState(.closed) throws invariantViolated: .closed is a transition, never a stored state"
  - ".layoutEdge on an empty tree falls back to insertRoot, as the plan specified"

patterns-established:
  - "Two-source close contract documented on every setState: .closed only after an AX invalid-element error AND the window missing from the CG list; lock, sleep and AX timeouts are .absent"

requirements-completed: [MODEL-02, MODEL-06, MODEL-08]

coverage:
  - id: D1
    description: "Tab-group tiles: group windows into one tile, switch the selected tab, resolve the group as one rect sized for its largest minimum"
    requirement: MODEL-06
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/TabsTests.swift (7 tests)"
        status: pass
      - kind: unit
        ref: "Tests/PaneModelTests/TreeFuzzTests.swift#randomEditsKeepEveryInvariant(seed:)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Absent and fullscreen windows keep their reserved slot and return to identical rects; only .closed removes the slot, for docked and floating windows"
    requirement: MODEL-08
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/LifecycleTests.swift (10 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "applyDrop maps every DropTarget onto insertRoot/insert/group; stale NodeIDs throw nodeNotFound and change nothing"
    requirement: MODEL-02
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/ScenarioTests.swift (applyDrop tests)"
        status: pass
    human_judgment: false
  - id: D4
    description: "End-to-end scenario: hit test -> edit -> resolve -> lifecycle -> undo -> byte-identical JSON round-trip through World.edit"
    verification:
      - kind: integration
        ref: "Tests/PaneModelTests/ScenarioTests.swift#dropTabAbsentPresentUndoAndPersist()"
        status: pass
      - kind: other
        ref: "swift test (125 tests in 14 suites) and scripts/check-no-appkit.sh"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-10-24
status: complete
---

# Phase 1 Plan 05: Tabs, Lifecycle Slots and Drop Application Summary

**Tab-group tiles (`group`/`selectTab`), lifecycle `setState` that keeps absent and fullscreen windows in their reserved slot until `.closed`, and `applyDrop`, proven end-to-end by a hit test → edit → resolve → undo → JSON scenario through `World.edit`.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-10-24T05:58:32Z
- **Completed:** 2026-10-24T06:03:34Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- `group(_:into:)` turns a panel into a tab group under the same NodeID, or appends to an existing group, always selecting the new tab. `selectTab(_:)` switches tabs (MODEL-06).
- `setState(_:for:)` on LayoutTree, Desk and DesktopLayer. Absent and fullscreen change `states` only, so `nodes` stays identical and `.present` restores the exact earlier Resolution. `.closed` is the only state that removes a slot (D-17, MODEL-08).
- `applyDrop(_:window:ids:)` turns each `DropTarget` into an existing edit, so stale targets roll back through the edits' transactional behaviour (D-20, T-01-12).
- The scenario test drops A, B and C (C onto B's centre, making tabs), marks A absent and then present, checks the JSON round-trip is byte-identical after every step, and undoes five times back to an empty desk.
- The edit fuzz suite now covers tab groups (grouping, switching tabs, removing tabs), which closes the gap 01-02 noted.

## Task Commits

1. **Task 1: Tab-group tiles**: RED `89c1bd0` (test), GREEN `2f0e60a` (feat)
   - Fuzz extension: `2e5e89f` (test)
2. **Task 2: Lifecycle transitions**: RED `328b25d` (test), GREEN `3502972` (feat)
3. **Task 3: applyDrop + scenario**: RED `2a906dc` (test), GREEN `194f488` (feat)

**Plan metadata:** see the final docs commit

### RED evidence

As in Plans 01-02 to 01-04, each RED commit includes compiling stubs, so the tests fail on assertions and not on build errors.

- **Task 1 RED:** `NO_COLOR=1 swift test --filter TabsTests` exited 1, with 7 of 7 tests failing. The classifier returned `RED_EVIDENCE_OK` / `target_test_failed` for `groupingIntoAPanelMakesATabGroupUnderTheSameNodeID()`. Semantic check: node 1 stayed `.panel(a)` where `.tabs([a, b], selected: 1)` was expected. The build was clean.
- **Task 2 RED:** 10 of 10 failed. The classifier returned `RED_EVIDENCE_OK` for `closedRemovesTheSlotExactlyLikeRemove()`. Semantic check: it failed on `tree == removed` and on `state(of: b) == nil` (still `.present`), because the stub did nothing.
- **Task 3 RED:** 7 of 7 failed. The classifier returned `RED_EVIDENCE_OK` for `tileCentreDropIsGroup()`. Semantic check: it failed on `dropped == grouped` because the stub left the tree unchanged. There were no build errors.

## Files Created/Modified
- `Sources/PaneModel/TreeEdits.swift`: `group(_:into:)`, `selectTab(_:)`, `setState(_:for:)`
- `Sources/PaneModel/World.swift`: `Desk.setState(_:for:)`
- `Sources/PaneModel/DesktopLayer.swift`: `DesktopLayer.setState(_:for:)`
- `Sources/PaneModel/DropZones.swift`: `LayoutTree.applyDrop(_:window:ids:)`
- `Tests/PaneModelTests/TabsTests.swift`: grouping, rejections, selection, one-rect resolve, JSON round-trip
- `Tests/PaneModelTests/LifecycleTests.swift`: reserved slots, close equals remove, Desk routing, floating frames, persisted states
- `Tests/PaneModelTests/ScenarioTests.swift`: applyDrop mapping, stale targets, the end-to-end phase scenario, a cross-layer duplicate rejected by the funnel
- `Tests/PaneModelTests/TreeFuzzTests.swift`: group and selectTab steps

## Decisions Made
- `group` checks for a duplicate identity before it checks the target, so a window that is already docked always reports `duplicateWindow`. That matches `insert`.
- `Desk.setState` relies on `DesktopLayer.remove` and `setState` to throw `windowNotFound`, so it does no lookup of its own.
- `group` checks only the tree for duplicates. If a floating window is dropped into the tree, `World.edit`'s whole-World validation rejects it. A scenario test pins this.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] RED commits carry compiling stubs**
- **Found during:** Tasks 1-3 (RED)
- **Issue:** without the new methods the tests do not compile, and a build failure counts as INVALID_RED.
- **Fix:** each RED commit declares the public signatures with empty bodies, and GREEN fills them in. This is the same practice as Plans 01-02 to 01-04.
- **Committed in:** 89c1bd0, 328b25d, 2a906dc

**2. [Scope extension, orchestrator-approved] Tab operations in TreeFuzzTests**
- **Found during:** Task 1
- **Issue:** 01-02 noted that its fuzz suite never builds tab groups.
- **Fix:** a third of the random drops onto a leaf now group into it, and a selectTab step takes half of the resize slots. TreeFuzzTests.swift is outside the plan's `files_modified`, but the orchestrator prompt allowed this file.
- **Committed in:** 2e5e89f

**3. [Rule 1 - Bug] Acceptance grep missed wrapped hit-test calls**
- **Found during:** Task 3 verification
- **Issue:** `grep -c "DropZones.target(at:"` counted only 1 of the 3 hit tests, because two of the calls wrapped after the opening parenthesis.
- **Fix:** each point is now bound to a local first, so every call fits on one line (count is now 3). Behaviour is unchanged.
- **Committed in:** 194f488

---

**Total deviations:** 3 (1 blocking convention, 1 approved scope extension, 1 formatting fix for the criterion)
**Impact on plan:** No scope creep beyond the fuzz extension the orchestrator approved.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 1 is complete. `swift test` passes 125 tests in 14 suites, and `scripts/check-no-appkit.sh` passes.
- Phase 2 (Window Control) has to honour the two-source close contract written on every `setState`: send `.closed` only after an AX invalid-element error and the window is also missing from the CG window list. Lock, sleep and AX timeouts map to `.absent`.
- Phase 3 (drag docking) can pass the result of `DropZones.target` straight to `applyDrop` inside `World.edit`.

---
*Phase: 01-layout-model*
*Completed: 2026-10-24*

## Self-Check: PASSED
