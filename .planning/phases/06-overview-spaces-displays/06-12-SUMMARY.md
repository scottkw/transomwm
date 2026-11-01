---
phase: 06-overview-spaces-displays
plan: 12
subsystem: phase-gate
status: complete
tags: [gate, uat, validation, vm, over-01, over-02, over-03, over-04, over-05, over-06]
requires:
  - phase: 06-11
    provides: "the finished Phase 6 code (overview, Spaces, displays, Mission Control takeover)"
provides:
  - "Green phase gate: full host suite, six VM suites one at a time, signed Debug build"
  - "06-UAT.md: 17 items result: pending for the user's MacBook Air + DELL pass"
  - "06-VALIDATION.md: per-task map 06-01-01 … 06-12-02, Wave 0 complete, manual-only rows"
affects: [verify-work, validate-phase]
actuals:
  tokens: 3800
  tasks: 2
  commits: 2
plan_head_before: 845bbf699239e3957c1865d57a0ecc181b503fae
plan_head_after: b1836a616fc5b3af833d64da162564468caf7a65
tech-stack:
  added: []
  patterns:
    - "VM gate: each suite's output captured to .build/0612-vm-<suite>.log and accepted only with a 'Test run with N tests … passed' line and no ✘"
key-files:
  created:
    - .planning/phases/06-overview-spaces-displays/06-UAT.md
    - .planning/phases/06-overview-spaces-displays/deferred-items.md
  modified:
    - .planning/phases/06-overview-spaces-displays/06-VALIDATION.md
key-decisions:
  - "The intermittent VM Esc failure in OverviewIntegrationTests was recorded, not patched: no change could be tied to a cause, and a fix without one would only hide it"
  - "The CoreDockSendNotification string in the spike's symbol-presence list was left in place; the only call site is TransomPrivate/CoreDock.swift"
requirements-completed: [OVER-01, OVER-02, OVER-03, OVER-04, OVER-05, OVER-06]
duration: 13min
completed: 2026-10-31
---

# Phase 6 Plan 12: Phase Gate Summary

**Every Phase 6 suite is green: 1,448 host tests and six VM suites, run one at a time with real count lines. The signed "Transom Debug.app" is built but not launched, and 06-UAT.md holds 17 pending items for one MacBook Air + DELL pass.**

## Results

| Run | Result |
|---|---|
| `scripts/check-no-appkit.sh` | OK (53 files) |
| Host `swift test` (`.build/0612-full.log`) | 193 + 363 + 83 + 809 = 1,448 tests. Only FreezeTestTests.itResumesByItself failed (known load flake). The re-run `swift test --filter FreezeTestTests` passed 8 of 8 (`.build/0612-freeze-rerun.log`) |
| VM OverviewIntegrationTests | 3 tests passed (`.build/0612-vm-OverviewIntegrationTests-final.log`, again in `…-after-idle.log`). The first two runs failed the Esc check, see Deviations |
| VM OverviewSpaceSwitchIntegrationTests | 2 tests passed |
| VM OverviewKeyboardIntegrationTests | 1 test passed |
| VM TakeoverIntegrationTests | 2 tests passed |
| VM SpacesIntegrationTests | 2 tests passed |
| VM ZoomSettleIntegrationTests | 2 tests passed |
| `scripts/build-debug.sh` | `/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`. Developer ID, team S2K7P43927, `com.eightabyte.transom.debug`. Signature and designated requirement verified. Not launched |

All VM runs used Tart `pane-test` (macOS 15.7.7), on 2026-10-31. Afterwards the guest's symbolic hotkeys 32, 108 and 113 read back enabled through `/tmp/transom-hkread`, and the guest is on Desktop 1 (per `com.apple.spaces`).

Acceptance greps:
- `SLSSetSymbolicHotKeyEnabled` appears only in `TransomPrivate/SymbolicHotKeys.swift` and the spike. As expected.
- `CoreDockSendNotification` appears in `TransomPrivate/CoreDock.swift`, and also in `Sources/transom-spaces-spike/main.swift:127`. The spike match is a string in its dlsym presence list, not a call.

## Task Commits

1. **Task 1: phase gate run and validation map**: `a4141f1` (test)
2. **Task 2: 06-UAT.md**: `b1836a6` (docs)

## 06-UAT.md contents

- Group 1, "Hardware checklist": UI-SPEC items 1-7, pasted verbatim (checked line by line against the spec).
- Group 2, "Mission Control takeover": three items.
  - T1: menu order and the alert.
  - T2: F3 / ⌃↑, a clean quit, then relaunch.
  - T3: `kill -9`, relaunch, then N10 with the shortcuts back.
- Group 3, "Backstops": seven items.
  - B1: other-Space previews, strip and mini-tile clicks, ⌃ not stuck, the switch on the right display.
  - B2: 30+ windows under 400 ms.
  - B3: ring, capsule and cursor; Esc right after opening; keys typed during the Esc fade.
  - B4: ⌘-Tab and the menu close the overview.
  - B5: VoiceOver.
  - B6: Reduce Motion.
  - B7: explainer timing.
- "Known gaps" lists macOS 14 not tested, N11 and the VM Esc flake.
- There is no swipe item: the 06-SPIKE verdict was "kept".

## Deviations from Plan

**1. [Rule 1 - Test reliability, not fixed] Intermittent VM Esc failure in OverviewIntegrationTests**
- **Found during:** Task 1, the VM loop.
- **Issue:** `overviewOpensPerDisplayAndCloses` failed "Esc did not close the overview" in two runs in a row.
  - The other two tests in the suite passed both times.
  - Three later runs passed with the test unchanged: once alone, and the whole suite twice, the second after the guest sat idle.
  - It last passed at 06-09, and no overview code changed after that.
- **Ruled out:**
  - Suite parallelism: the suite is `.serialized` and this test runs first.
  - Guest screen saver and display sleep: both are off.
  - Leftover guest processes: none.
  - A temporary diagnostic, since reverted, showed `holdsKeys` true straight after the reopen.
- **Fix:** None. The cause is unknown, and a pump-before-Esc change would not be tied to it. Logged in `deferred-items.md` with a next step: log the WindowServer key window when Esc is posted. Row 06-06-01 in 06-VALIDATION.md is marked ⚠️ flaky, and UAT B3 checks Esc on hardware.
- **Files modified:** `deferred-items.md`, `06-VALIDATION.md` (commit `a4141f1`).

**2. [Plan verify wording] Host flake rule**
- The plan's literal check, `grep "✘" | grep -vc itResumesByItself` ≤ 1, counts 2 here. Those two lines are FreezeTestTests' own suite and run summary lines.
- Checked by hand: no other test failed, and the filtered re-run passed.

## Known Stubs

None.

## Next Phase Readiness

- The user runs 06-UAT.md on the MacBook Air plus the DELL (`/gsd-verify-work 6`).
- `/gsd-validate-phase` sets `nyquist_compliant`.

## Self-Check: PASSED

- FOUND: .planning/phases/06-overview-spaces-displays/06-UAT.md, 06-VALIDATION.md, deferred-items.md
- FOUND commits: a4141f1, b1836a6
- FOUND: /Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app
