---
phase: 06-overview-spaces-displays
plan: 05
subsystem: shell
status: complete
tags: [displays, settling, debounce, session-gate, layout-sets, n12, debug-menu]
requires:
  - phase: 06-04
    provides: "Arranger .displaysSettling / .displaysSettled, snapshot.arrangement / layoutSets, dormantDeskCount, awayDisplayCount, Notice.displaysDisconnected"
provides:
  - "DisplaySettler: CG begin callback or screen-parameters change starts settling, 1.5 s cancel-latest quiet, held while SessionGate is paused"
  - "AXWindowSystem.onDisplaysSettling / onDisplaysSettled, displayNames (merged, keeps a gone display's name), settlerState"
  - "ArrangeController: settling/settled as Arranger inputs, no inventory fed while settling, layout.json saves arrangement + layout sets, .restore passes them, one settle after launch re-attach when the saved arrangement differs"
  - "N12 merge and toast on the main display; OverviewCopy S2-S4 in the Debug submenu; displays log lines"
affects: [06-06, 06-12]
actuals:
  tokens: 8100
  tasks: 2
  commits: 2
plan_head_before: 3215a1303d6e1549d3a018a7ca7c985f162a9304
plan_head_after: 70d4476ea299b7ff0e254f273a0274669063f9ef
tech-stack:
  added: []
  patterns:
    - "Injected sleep for timer tests: a manual sleeper the test fires, so no test waits the real 1.5 s"
    - "Settling input applied synchronously in the callback (effects run in a Task), so no inventory from the change is fed first"
key-files:
  created:
    - Sources/TransomMac/DisplaySettler.swift
    - Tests/TransomMacTests/DisplaySettlerTests.swift
  modified:
    - Sources/TransomMac/AXWindowSystem.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overlay/NoticeQueue.swift
    - Sources/TransomMac/Shell/NoticeCopy.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Tests/TransomMacTests/NoticeCopyTests.swift
    - Tests/TransomMacTests/NoticeQueueTests.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
key-decisions:
  - "The settler's resume restart hangs off AXWindowSystem's post-resume full refresh, not the raw SessionGate onResume, so a held change settles a full 1.5 s later against a fresh, unpaused inventory"
  - "The launch settle runs once the saved layout is re-attached (not straight after .restore): with a restore pending the Arranger would only relabel the arrangement, never store the saved World under its own arrangement or apply the live one's set"
  - "Display names are merged, never replaced, so a display that has already left NSScreen.screens keeps the name N12 needs"
  - "S2-S4 read arranger.displays / arrangement / layoutSets / dormantDeskCount / awayDisplayCount directly from the already-public `arranger`; no new ArrangeController accessors"
requirements-completed: [OVER-05, OVER-06]
duration: ~20min
completed: 2026-10-31
---

# Phase 6 Plan 05: Display Settling Shell, N12 and Debug S2-S4 Summary

Display changes now reach the Arranger the way 06-04 expects. The first CG reconfiguration callback or screen-parameters change puts it into settling at once. Every further change restarts a 1.5 s quiet period, and settled fires once with a fresh inventory, the new `ArrangementID` and the display names captured before any display left. Nothing settles while the Mac is asleep or locked. layout.json now saves the current arrangement and every layout set, and restores them at launch.

## What was built

- **DisplaySettler.swift (new):** states `idle`, `settling`, `waitingForWake`.
  - `begin()` (from the CG callback's begin flag) and `touch()` (from a screen-parameters change) share one settling. `onSettling` fires only on the idle → settling edge, and either call restarts the quiet task (the RefreshScheduler shape).
  - When the quiet period ends: if the session is paused the state becomes `waitingForWake` and "deferred: session asleep or locked" is logged. Otherwise the state goes back to `idle` and `onSettled` fires.
  - `sessionResumed()` restarts the full quiet period while a change is pending.
  - The CG callback uses an unretained refcon and always hops to main. `isolated deinit` removes the callback and cancels the task. The callback is registered by `observeReconfiguration()`, so tests never register it.
- **AXWindowSystem:** owns the settler (lazy, `isPaused` reads the gate). `displaysDidChange` merges display names, calls `settler.touch()`, and still yields `.displaysChanged`, so pick mode and the overview still end on it. On the settling edge the names are merged again before `onDisplaysSettling`. The post-resume refresh calls `settler.sessionResumed()`. Exposes `displayNames` and `settlerState`.
- **ArrangeController:**
  - Settling applies `.displaysSettling` synchronously.
  - Settled reads the inventory, logs "arrangement {id}: {d} displays ({uuids}), {known | new}" and feeds `.displaysSettled`.
  - `.displaysChanged` no longer forces an inventory feed, and nothing is fed while `arranger.settling`.
  - `write` saves `snapshot.arrangement` and `snapshot.layoutSets` (replacing the 06-03 pass-through), and `.restore` passes the saved ones back in.
  - If the saved arrangement is not unknown and differs from the live displays, one settle runs as soon as the restore has re-attached.
  - Adds the log lines "display {uuid} gone / back" and "applied layout set for arrangement {id}: {w} windows placed".
- **N12:** names are truncated through `MenuCopy.truncatedAppName` and shown in curly quotes. Two N12s merge their names and window counts into the several-displays form. The toast shows on the main display (`arranger.displays.first`), where the Engine floats the windows.
- **Debug S2-S4:** `OverviewCopy.DisplaysLine`, `displaysLine`, `savedArrangementsLine` and `dormantDesksLine`, all with explicit plural branches. They are added after S1 in the Debug submenu.

## Verification

- Task 1 gate `swift test --filter 'DisplaySettlerTests|LayoutStoreTests|SessionGateTests'`: 25 tests passed, no ✘. `swift build` OK. The tracer gate re-ran the gate plus the full TransomMacTests suite (325 passed) before expanding.
- Task 2 gate `swift test --filter 'NoticeCopyTests|NoticeQueueTests|OverviewCopyTests'`: 26 tests passed, no ✘.
- Full unit suites: Model 193, Mac 333 and Engine 734 tests passed. `scripts/check-no-appkit.sh` OK (49 files).
- Acceptance greps all pass:
  - DisplaySettler.swift: `CGDisplayRegisterReconfigurationCallback` ×1, `CGDisplayRemoveReconfigurationCallback` ×1.
  - AXWindowSystem.swift: `settler.touch` ×1.
  - ArrangeController.swift: `displaysSettled` ×5 or more, `layoutSets` ×3.
  - NoticeCopy.swift: `until you reconnect` ×2, `"display"` ×1.
  - OverviewCopy.swift: `(s)` ×0.
- No live runs. Real hot-plug, clamshell and sleep-with-change can't be done in the VM and are covered by the 06-12 hardware checklist items 1-5.

## TDD Gate Compliance

- Task 1 RED: DisplaySettlerTests failed to compile (`cannot find type 'DisplaySettler'`). GREEN came in 61dc69c.
- Task 2 RED: OverviewCopyTests failed to compile (`OverviewCopy` had no `DisplaysLine`, `displaysLine` or `savedArrangementsLine`). GREEN came in 70d4476.
- Tests and implementation were committed together for each task, one commit per task (same as 06-04).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Correctness] The resume restart is moved to after the post-resume refresh**
- **Found during:** Task 1
- **Issue:** Calling `settler.sessionResumed()` from the raw SessionGate `onResume` would race AXWindowSystem's own 1.5 s resume refresh. Settled could then read an inventory that is still `sessionPaused` and stale.
- **Fix:** It is called where AXWindowSystem ends its pause, after the full refresh. The change still waits for wake/unlock plus a full 1.5 s, as D-11 requires.
- **Commit:** 61dc69c

**2. [Rule 1 - Correctness] The launch settle waits for the re-attach**
- **Found during:** Task 1
- **Issue:** The hand-off asked for a settle "right after restore". While a restore is pending, `Arranger.displaysSettled` only relabels the arrangement and processes the inventory. The saved World would never be stored under its own arrangement, and the live arrangement's known set would never be applied.
- **Fix:** `launchSettlePending` is checked after each inventory feed and fires once `!arranger.awaitsRestore`.
- **Commit:** 61dc69c

**3. [Minor] No new ArrangeController accessors for S2-S4**
- `arranger` is already public, so StatusItemController reads its values directly. The plan's `arrangementShortHash` and related accessors would only have repeated those values.

## Known Stubs

None.

## Risks

- Settled does not force a full AX sweep. It relies on the 500 ms `scheduleAll` that `displaysDidChange` already queues, which has run long before the 1.5 s quiet ends.
- If the launch restore fails (`unattached`), the launch settle still runs and stores the live World under the saved arrangement. This edge case is not covered by a test.
- The "gone" log line names the display of the first floated window as the target. When windows float onto several displays, only that first display is named.

## Threat Flags

None. The new surface (CG callback, session hold) is covered by T-06-13 and T-06-14 as planned.

## Self-Check: PASSED
