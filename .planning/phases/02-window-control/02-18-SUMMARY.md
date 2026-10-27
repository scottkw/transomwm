---
phase: 02-window-control
plan: 18
subsystem: permission-onboarding
tags: [swift, appkit, swiftui, nshostingcontroller, setup-window, gap-closure, G-02-1]

requires:
  - phase: 02-window-control
    provides: "02-01 PermissionReducer / PermissionController (D-02), SetupWindowController and SetupView"
provides:
  - "SetupWindowController.makeWindow() sizes the window from its SwiftUI content before centring and keeps following each permission state"
  - "SetupWindowController.makeWindow() is internal (testable)"
  - "PermissionController.overrideStateForTesting(_:) internal test seam: sets state with no reducer and no effect"
  - "Tests/TransomMacTests/SetupWindowTests.swift: headless regression tests for G-02-1"
affects: [phase-02-uat]

actuals:
  tokens: 1400
  tasks: 1
  commits: 2
plan_head_before: 553f2b284c18a8664632d125b300d1deab531915
plan_head_after: 03787554a7bf3a18f98a58a8d74e8623bbb5eb77

tech-stack:
  added: []
  patterns:
    - "NSHostingController windows that follow SwiftUI content: sizingOptions [.preferredContentSize] plus one setContentSize(fittingSize) before reading window.frame"

key-files:
  created:
    - Tests/TransomMacTests/SetupWindowTests.swift
    - .planning/phases/02-window-control/tdd/02-18-task1-red.json
  modified:
    - Sources/TransomMac/Permission/SetupWindowController.swift
    - Sources/TransomMac/Permission/PermissionController.swift

key-decisions:
  - "02-18: the setup window uses sizingOptions [.preferredContentSize] and one setContentSize(fittingSize) before centring; preferredContentSize alone sizes the window only after a run-loop turn on macOS 27, too late for the centring code"

patterns-established:
  - "A window test builds the NSWindow with makeWindow() and never orders it on screen, so it runs headless under plain swift test"

requirements-completed: [WIN-01]

coverage:
  - id: D1
    description: "With no Accessibility grant, makeWindow() returns a window whose content size equals the SwiftUI fittingSize (non-zero), centred on the first screen's visible frame, before it is ever shown"
    requirement: WIN-01
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/SetupWindowTests.swift#theSetupWindowHasItsContentSizeBeforeItIsShown()"
        status: pass
    human_judgment: false
  - id: D2
    description: "A permission state change (notTrusted to ready) resizes the window to the new content height with no further setContentSize call"
    requirement: WIN-01
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/SetupWindowTests.swift#theSetupWindowHeightFollowsAPermissionStateChange()"
        status: pass
    human_judgment: false
  - id: D3
    description: "Live: a fresh Debug build with no grant opens a readable, centred Set Up Transom window with the default Open System Settings button, whose height follows the grant (UAT 1, 2, 3, 17)"
    requirement: WIN-01
    verification:
      - kind: manual
        ref: "Tart VM (macOS 15.7.7) re-check of 02-UAT tests 1, 2, 3 and 17, run by the orchestrator"
        status: pending
    human_judgment: true
    rationale: "Live runs are not allowed on the host; the orchestrator re-checks in the VM after execution"

duration: 6min
completed: 2026-10-27
status: complete
---

# Phase 2 Plan 18: Set Up Transom Window Sized From Its Content Summary

**The Set Up Transom window now opens at its SwiftUI content size, centred, instead of as a 1x28 title bar: the hosting controller publishes preferredContentSize, and makeWindow() sizes the window once from fittingSize before centring it (G-02-1).**

## Performance

- **Duration:** about 6 min
- **Completed:** 2026-10-27T20:58Z
- **Tasks:** 1 (tracer, TDD)
- **Files modified:** 2 source, 1 test created, 1 TDD evidence record

## Accomplishments

- `makeWindow()` sets `hosting.sizingOptions = [.preferredContentSize]`, so the window takes SwiftUI's size and follows each permission state's content height.
- After `layoutIfNeeded()` and before the centring block, `window.setContentSize(hosting.view.fittingSize)` sizes the window at once, so the centring reads a real `window.frame`.
- `makeWindow()` is internal, and `PermissionController.overrideStateForTesting(_:)` is an internal test seam that sets the state with no reducer and no effect.
- `SetupWindowTests` (2 tests) proves both behaviours headless. The window is created in the test process and never shown; `send(_:)` is never called, because its effects are live.

## Task Commits

1. **Task 1: Tracer, setup window sized and centred, follows state**: `87cae45` (test, RED), `0378755` (fix, GREEN)

## TDD Gate Compliance

`test(02-18)` (`87cae45`) comes before `fix(02-18)` (`0378755`). RED record: `tdd/02-18-task1-red.json`. Both tests built, ran and failed only on size expectations:
- `theSetupWindowHasItsContentSizeBeforeItIsShown`: content width off by 479 and height off by 321.5 from fittingSize 480x321.5 (window content about 1x0).
- `theSetupWindowHeightFollowsAPermissionStateChange`: height stayed about 0 for the whole 2 s poll, 230 pt off the ready content's fittingSize.

## Tracer gate

The mode is end-of-phase and the tracer verify is automated only. After GREEN, `swift test --filter SetupWindowTests` passed (2 tests) and the full suite passed, so there was nothing to hold. This plan has one task, so nothing expands after it.

## Verification

- `swift test --filter SetupWindowTests`: 2 tests pass.
- `swift build && env -u TRANSOM_LIVE swift test`: exit 0, no "✘". Swift Testing runs: 193, 200 (TransomMacTests, was 198), 42 and 534 tests, all passing. The four "Executed 0 tests" lines are the empty XCTest runners, as before. Integration suites stay gated off because TRANSOM_LIVE is unset.
- `scripts/check-no-appkit.sh`: `no-appkit: OK (40 files)`.
- Both fix lines are load-bearing, checked by swapping each out:
  - The old controller (`[.intrinsicContentSize]`, no setContentSize) fails both tests.
  - `setContentSize(fittingSize)` with `[.intrinsicContentSize]` passes the first-show test but fails the state-change test, as the debug file's variants F/G predicted.
- Acceptance greps: `sizingOptions = [.preferredContentSize]` 1; `setContentSize(hosting.view.fittingSize)` 1, at line 55, before `let size = window.frame.size` at line 58; `Test seam` in PermissionController 1; forbidden calls in non-comment test lines 0.

## Decisions Made

- The setup window is sized by the sizing option plus one setContentSize before centring. The debug file warned against a one-off setContentSize, but only as a *replacement* for the sizing option. Here it is added before centring, and preferredContentSize still handles every later state, which the second test proves.

## Deviations from Plan

**1. [Planned deviation] Two lines, not the brief's one-line fix**
- The brief and the debug file proposed changing only the sizingOptions line. Planner measurement on macOS 27 (2026-10-27, scratch copy of makeWindow, window never shown): with `[.preferredContentSize]` alone the window was still 1x32 when `layoutIfNeeded()` returned. It reached its size only after a run-loop turn and grew downward from its top edge, so it would open with its top-left corner at the screen centre: readable, but not centred.
- Adding `window.setContentSize(hosting.view.fittingSize)` sized it at once on macOS 27 (480x269 for the lookalike view). A later content change still resized it (269 to 157, top edge fixed).
- In the VM (macOS 15.7.7) `[.preferredContentSize]` alone sized it to 480x353 inside `layoutIfNeeded()`. The extra line is harmless there.
- This executor's headless test confirms it on this host: the fixed window matches fittingSize (480x321.5 for the real SetupView) and is centred right after makeWindow().

**2. [Rule 1 - Bug, test only] State-change poll passed vacuously before SwiftUI re-rendered**
- **Found during:** Task 1 GREEN.
- **Issue:** the first poll condition (window height equals the current fittingSize) was already true for the notTrusted content, so it returned before SwiftUI re-rendered for `.ready`. The `#require` that the heights differ then failed (difference 0).
- **Fix:** the poll waits until fittingSize differs from the notTrusted height by more than 1 pt AND the window height matches it. Re-checked: it still fails on the old controller, and with a setContentSize-only fix. The gate is stricter, not weaker.
- **Files modified:** Tests/TransomMacTests/SetupWindowTests.swift. **Commit:** `0378755`.
- The RED record was taken with the first poll. Both versions fail on the old code for the same reason (window height about 0).

**Total deviations:** 2 (one planned, one test fix). **Impact:** none on scope.

## Issues Encountered

- `swift format lint --strict` on the touched files reports indentation and import-order findings across the whole of SetupWindowController.swift, not just the new lines. It is not one of this plan's gates, and the style predates this plan, so I left it alone.

## Threat Flags

None. T-02-49 is mitigated by the fix and covered by SetupWindowTests. T-02-50 is accepted: the seam is internal and runs no effect.

## Live re-check hand-off (not run by the executor)

After execution the orchestrator re-runs 02-UAT tests 1, 2, 3 and 17 in the Tart VM (macOS 15.7.7) with a fresh Debug build. Expected: a readable, centred Set Up Transom window with the default Open System Settings button, whose height follows the grant. Nothing was launched on the host.

## User Setup Required

None.

## Next Phase Readiness

- G-02-1 is closed in code. It stays open in 02-UAT until the VM re-check passes.
- 02-19 (G-02-10) is independent of this plan.

## Self-Check: PASSED
