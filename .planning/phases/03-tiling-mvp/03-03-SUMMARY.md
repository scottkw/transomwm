---
phase: 03-tiling-mvp
plan: 03
subsystem: layout-model
status: complete
tags: [swift, paneModel, paneEngine, rekey, undo, floating, tdd]

requires:
  - phase: 02-window-control
    provides: "WindowEvent.windowRekeyed(from:to:) contract (02-16)"
  - phase: 03-tiling-mvp
    provides: "Desktop tile and DesktopLayer (03-01)"
provides:
  - "World.rekey(from:to:history:), UndoHistory.rekey(from:to:) (internal), DesktopLayer.rekey(from:to:)"
  - "World.recordFloatingFrame(_:for:), World.reflow(_:_:)"
  - "World.undo keeps the current frame of windows floating now and in the snapshot"
  - "LifecycleSync applies windowRekeyed through World.rekey"
affects: [03-04, 03-08, 03-10, arranger, commands, persistence]

actuals:
  tokens: 6300
  tasks: 2
  commits: 4
plan_head_before: ca09d1b007c8ba855acd9da33b9c632003f27af4
plan_head_after: 952db3e8e4adaa06666335db27551119b21251f2

tech-stack:
  added: []
  patterns:
    - "OS facts change the World through non-undo paths (apply, rekey, reflow, recordFloatingFrame); user commands through edit"
    - "edit = reflow + history push, so both share one copy-validate-commit body"

key-files:
  created:
    - Tests/PaneModelTests/WorldRekeyTests.swift
  modified:
    - Sources/PaneModel/World.swift
    - Sources/PaneModel/Undo.swift
    - Sources/PaneModel/DesktopLayer.swift
    - Sources/PaneEngine/LifecycleSync.swift
    - Tests/PaneModelTests/UndoTests.swift
    - Tests/PaneEngineTests/LifecycleSyncTests.swift

key-decisions:
  - "A rekey onto an ID a desk already holds closes the old ID through apply(.closed), purging it from history"
  - "A rekey from an ID to itself is a no-op (it would otherwise hit the merge rule and close a live window)"
  - "World.edit now delegates to World.reflow, then pushes the pre-edit desk"

requirements-completed: []

duration: 5min
completed: 2026-10-25
---

# Phase 3 Plan 03: Rekey, non-undo reflow and floating frames Summary

**When macOS corrects a window's ID, `World.rekey` renames it in its panel, tab group or Desktop layer and in every undo snapshot, with no undo step. `reflow` and `recordFloatingFrame` let OS facts change a desk without touching undo, and Undo now leaves floating windows where they are.**

## Performance

- **Duration:** about 5 min
- **Tasks:** 2 (4 commits)
- **Files:** 1 created, 6 modified

## Accomplishments

- `World.rekey(from:to:history:)` meets the Phase 2 obligation from 02-16. It keeps the window's state, frame, NodeID, tab order and selection. If a desk already holds `to`, it closes `from` instead. A window that no desk holds gets renamed in the snapshots only.
- `UndoHistory.rekey` rewrites every snapshot. A snapshot that already holds `to` drops `from`, the same way `forget` does. After a rekey, an undo brings the window back under its new ID, so `requery` finds it and doesn't report it closed (Pitfall 3).
- `LifecycleSync.handle` has its own `windowRekeyed` arm, which returns true. The old "Phase 3 re-points desk refs" note is gone.
- `World.reflow(_:_:)` has the same contract as `edit` without the history push. `World.recordFloatingFrame(_:for:)` is built on it and rejects bad frames (T-03-06) and windows that don't float.
- `World.undo` copies the current frame of every window that floats both now and in the snapshot (Pitfall 10). A window that is docked now but floated in the snapshot gets the snapshot's frame back.

## Task Commits

1. **Task 1 (tracer): rekey through LifecycleSync and Undo**: `0694342` (test, RED), `e9e9d8c` (feat, GREEN)
2. **Task 2: reflow, recordFloatingFrame, undo floating frames**: `d24a3ec` (test, RED), `952db3e` (feat, GREEN)

## TDD Gate Compliance

Each task starts with a `test(...)` commit. The model tests in each one failed to compile against HEAD because the symbols didn't exist yet (`World.rekey`, then `World.recordFloatingFrame`/`World.reflow`). That follows 03-02's convention. A `feat(...)` commit then makes the suites pass. No refactor commits were needed.

## Verification

- `swift test --filter "WorldRekeyTests|LifecycleSyncTests"`: 7 + 15 tests ran and passed (12 parameterised non-lifecycle cases).
- `swift test --filter 'PaneModelTests|PaneEngineTests'`: 189 tests in 19 suites and 236 tests in 26 suites ran and passed.
- `scripts/check-no-appkit.sh`: OK (27 files).
- Acceptance greps: `func rekey` appears 3 times in World.swift and once in Undo.swift. `world.rekey` appears once in LifecycleSync.swift and "re-points desk refs" 0 times. `func recordFloatingFrame` and `func reflow` appear once each.
- Tracer gate after task 1: the verify step passed end to end before Task 2 started.

## Deviations from Plan

**1. [Rule 1 - Consistency] World.edit delegates to World.reflow**
- **Found during:** Task 2
- **Issue:** `reflow` is `edit` without the push, so keeping two copies of the copy-validate-commit body would duplicate it.
- **Fix:** `edit` checks the desk exists, calls `reflow` and then pushes the pre-edit desk. The throw behaviour hasn't changed, and every existing UndoTests row passes.
- **Files modified:** Sources/PaneModel/World.swift
- **Commit:** 952db3e

**2. [Rule 2 - Correctness] A rekey to the same ID is a no-op**
- **Found during:** Task 1
- **Issue:** `WindowRef` equality is identity. Without a guard, `rekey(from: x, to: x)` would find that "a desk already holds `to`" and close a live window.
- **Fix:** `guard from != to else { return }`, covered by `aRekeyToTheSameIDChangesNothing()`.
- **Files modified:** Sources/PaneModel/World.swift
- **Commit:** e9e9d8c

## Requirements

SAFE-06, TILE-07 and TILE-09 stay **Pending**. This plan only adds their model and engine layer: rekeying the identity for relaunch matching, non-undo floating frames, and an Undo that leaves floating windows alone. The user-visible parts (relaunch restore, opening new windows floating, and the undo command and dispatcher) come in later Phase 3 plans.

## Known Stubs

None.

## Threat Flags

None. T-03-05 is mitigated: the merge rule closes the old ID, and the candidate World is validated before it is committed. T-03-06 is mitigated: `setFrame` checks `isValidGeometry`, and a NaN frame is rejected with no change.

## Notes for later plans

- Use `World.reflow` for automatic floats (D-26) and `World.recordFloatingFrame` for user moves of floating windows that the event stream observes. User commands still go through `World.edit`.
- `World.undo` still restores snapshot frames for windows that are docked now. An undo that floats a window again puts it back where it was.

## Self-Check: PASSED

WorldRekeyTests.swift exists, and commits 0694342, e9e9d8c, d24a3ec and 952db3e are ancestors of HEAD.
