---
phase: 03-tiling-mvp
plan: 24
subsystem: engine-restore
status: complete
tags: [safe-06, g-03-10, cr-03, restore, session-gate, gap-closure]
requires: [03-23]
provides:
  - "AXWindowSystem: a sweep is initial until one runs with no pause from start to end (pauseCount); start() no longer sets initialRefreshComplete unconditionally"
  - "FakeWindowSystem: initialSweepDone set only by an unpaused refreshAll; inventory().initialRefreshComplete reported from it"
  - "Locked-start regression aStartWhileLockedKeepsEveryDeskOnceUnlocked; relaunched(locked:)"
affects: [AXWindowSystem start/refreshAll/sweep/sessionDidPause, FakeWindowSystem inventory, menu "looking for windows" header while a locked start waits]
tech-stack:
  added: []
  patterns: ["initial sweep = first sweep with no pause from start to end, counted by an edge-triggered pause counter"]
key-files:
  created:
    - .planning/phases/03-tiling-mvp/03-24-SUMMARY.md
  modified:
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "Initial-sweep rule: a sweep is initial while initialRefreshComplete is false, and sets it only if the session is unpaused at its end and no pause began since it started (sessionDidPause bumps pauseCount on the gate's not-paused -> paused edge). After a locked start, sessionDidResume's refreshAll is the initial sweep: every listed window is tracked with no 250 ms settle hold before .sessionPaused(false)."
  - "The fake mirrors it with !(locked && lockGate): a lock with gate: false still counts, as AXWindowSystem is not paused without a lock signal."
  - "Arranger, LayoutRestore, WindowTracker and ArrangeController unchanged: their guards already wait on initialRefreshComplete."
  - "T-03-68 accepted as a non-goal (deferred-items, Found in 03-24): an app whose AX reads fail at the first unpaused sweep, and the in-flight hint refresh edge (plan-check W2)."
metrics:
  duration: "~15 min"
  completed: 2026-10-27
  tasks: 2
  files: 4
actuals:
  tokens: 3200
  tasks: 2
  commits: 3
plan_head_before: 95f6b7a346972a8f4e1b9d77837fb59d88bfc35e
plan_head_after: 3319d773ef9f3ff572556856bd76a720933ed366
---

# Phase 3 Plan 24: Locked start keeps every desk (G-03-10) Summary

A sweep made while the session is paused no longer counts as the initial one, so after a start while locked the post-resume sweep tracks every window before the restore runs, and both the shown and the hidden desk come back intact.

## What changed

- **AXWindowSystem**: `sweep()` (no `initial` parameter) reads `initial = !initialRefreshComplete` at its start and sets `initialRefreshComplete = true` only if `!paused` at its end and `pauseCount` is unchanged. `sessionDidPause` bumps `pauseCount` first, so a lock and unlock inside one sweep also leaves it uncounted (plan-check W1). `start()` and `refreshAll()` call the same `sweep()`; the unconditional `initialRefreshComplete = true` is gone. `sessionDidResume` is unchanged.
- **FakeWindowSystem**: `refreshAll()` marks the initial sweep done only when `!(locked && lockGate)`; `inventory()` reports `initialRefreshComplete: initialSweepDone` instead of a hard-coded `true`.
- **Tests**: `relaunched(..., locked: Bool = false)`; new `aStartWhileLockedKeepsEveryDeskOnceUnlocked`. The CR-03 test keeps every line of code and every `#expect`; only its doc comment and the `if locked` comment now say it models a pause that began after an unpaused initial sweep.
- **deferred-items.md**: `## Found in 03-24` with the T-03-68 / W2 non-goal.

## TDD

**RED** (89bde04, at HEAD behaviour): `swift test --filter ArrangerMultiDeskRestoreTests`, 18 tests, 1 failed with 6 issues, all in the new test:
- line 446 `fake.inventory().initialRefreshComplete == false` (the fake's old hard-coded true)
- line 460 `harness.arranger.world == first.saved` (the restore after unlock lost a desk)
- line 461 `world[deskA1]?.tree.windows == [ref(1)]`
- lines 467-469 after the settle refresh: world != saved, Space 1 docks nothing, window 1 floating

**GREEN** (d4f9bf3): `swift test --filter "ArrangerMultiDeskRestoreTests|ArrangerRestoreTests"`: 39 tests in 2 suites passed, no failures. Both cases of the CR-03 test pass unchanged.

## Verification

- `swift build`: clean.
- Full headless `swift test`: largest run 512 tests in 52 suites passed, no "✘" (other runs 193, 196, 42; live suites skip, PANE_LIVE never set). The plan's "513 + 1" estimate counted the 2-test probe file that was in the tree during the planning experiment; 511 + 1 new test = 512.
- `scripts/check-no-appkit.sh`: OK (40 files).
- Acceptance greps: `initialRefreshComplete: true` in the fake 0; `sweep(initial: true)` in AXWindowSystem 0; `setLocked(true)` in the test file 2; removed `#expect` lines in the 03-24 test diff 0; `Found in 03-24` 1.
- Only headless commands ran on the host. Neither Pane nor PaneFixtureApp was launched; the Tart VM was not touched.

## Expected side effect

While a locked start waits, `initialRefreshComplete` is false, so the menu header shows MenuCopy's "looking for windows" text and TrackedWindowsModel shows `.loading`. That is correct: nothing has been observed yet. Not changed.

## Non-goals (T-03-68, W2)

- An app whose AX reads fail (-25204, timeout) at the first unpaused sweep is still untracked when the restore runs; its saved shown-Space windows are removed and return as floaters. Same as at any ordinary launch; recorded in deferred-items.md.
- A hint refresh already in flight for a pid when the first unpaused sweep reaches it folds that pid's initial refresh into a non-initial follow-up, so its new windows can still be settling at `.sessionPaused(false)`. Recorded in the same entry.

## Coverage gap

The AXWindowSystem half (pause counter, `start()`/`sessionDidResume` path) has no headless test: PaneMac is exercised only by live suites. The fake mirrors the rule and the regression pins it there. The real locked start is pending a VM re-check.

## Output note

The VM re-check of the locked start (G-03-10 `missing` item 5: Ctrl-Cmd-Q, launch Pane while locked, unlock, read layout.json for both Spaces) is not part of this plan. The orchestrator runs it in the Tart VM pane-test afterwards, because it needs the user to unlock the screen. This plan does not mark G-03-10 closed in 03-UAT.md; /gsd-verify-work does that.

## Deviations from Plan

None in code. The full-suite count is 512, not the plan's estimated 514 (see Verification; the estimate included the probe file's tests).

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: Sources/PaneMac/AXWindowSystem.swift, Sources/PaneTestSupport/FakeWindowSystem.swift, Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift, .planning/phases/03-tiling-mvp/deferred-items.md
- FOUND commits: 89bde04, d4f9bf3, 3319d77
