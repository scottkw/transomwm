---
phase: 09-polish-ship
plan: 25
subsystem: testing
status: complete
tags: [flaky-tests, live-tests, vm, macos-27, spaces, overview, tabs]
requires: [09-24]
provides:
  - "OverviewSpaceSwitchIntegrationTests green on macOS 27.2 and 15.7"
  - "TabStripSpaceIntegrationTests green on macOS 27.2 and 15.7"
  - "SpaceChangeRelay shared in IntegrationSupport.swift, logging its counts"
  - "Measured, recorded deviations for the Overview helper exit and the TabGroup close confirmation on 27.2"
affects: [09-26, 09-27, 09-28]
tech-stack:
  added: []
  patterns:
    - "SpaceChangeRelay (shared): a suite that switches Spaces while an AXWindowSystem runs starts one, so an SSH-run process on 27.2 still hears activeSpaceDidChange"
key-files:
  created: []
  modified:
    - Tests/TransomMacIntegrationTests/IntegrationSupport.swift
    - Tests/TransomMacIntegrationTests/ViewsIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/TabStripSpaceIntegrationTests.swift
    - .planning/phases/09-polish-ship/deferred-items.md
decisions:
  - "OverviewSpaceSwitch and TabStripSpace on 27.2: test setup, the 09-24 Views cause. The relay counted 0 system announcements for 10 Space changes on 27.2 and posted none on 15.7."
  - "Overview helper exit on 27.2: cause not proven. The exit was located after the Esc close; a pump-through-the-fade fix did not hold and was reverted. Recorded unfixed."
  - "TabGroup close on 27.2: product gap, not setup. A closed but retained window stays in the full CG list on 27.2, so the two-source close rule never confirms it. No test change; a CloseRule change is a product decision."
metrics:
  duration: "~2h"
  completed: 2026-11-07
estimate:
  tokens: 60000
  tasks: 3
actuals:
  tokens: 4200
  tasks: 3
  commits: 3
plan_head_before: 7df28f86d56534bfc1987f2332bacb4ded157811
plan_head_after: 4a5be15b19a7332cd03764c373c6c687f72a84ea
---

# Phase 9 Plan 25: Carried macOS 27.2 live failures (D-17) Summary

**Two of the four carried 27.2 failures are fixed in test setup: OverviewSpaceSwitch (3 tests) and TabStripSpace. Both had the 09-24 cause: an SSH-run test process on 27.2 never hears `activeSpaceDidChange`, and `SpaceChangeRelay`, now shared, fills that in. The other two are recorded as deviations with measured evidence. The Overview helper exit was located but its cause is not proven. The TabGroup close confirmation is a real product gap on macOS 27: a closed but retained window stays in the full CG window list, so Transom never confirms the close.**

## Tasks

| Task | Name | Commit | Result |
|------|------|--------|--------|
| 1 | OverviewSpaceSwitch on 27.2 (tracer) | cb3761b | 6/6 on 27.2, the first run with the fix; 6/6 on 15.7 |
| 2 | Overview helper exit, TabStripSpace strip | f3bdae1 | TabStripSpace passes on both; Overview **not fixed** (deviation 1) |
| 3 | TabGroup close confirmation, host gate | 4a5be15 | **Not fixed**: product gap (deviation 2); host gate green |

### Task 1: OverviewSpaceSwitch
- Baseline on 27.2 (`.build/09-25-oss-vm27-base.log`): L114 and L155 `cached` false, L195 Arranger never at the second Space, the same as 08.1.1-18.
- All three depend on `AXWindowSystem`'s `activeSpaceDidChange` observer. `SpaceChangeRelay` moved into `IntegrationSupport.swift` and prints its counts at `stop()`. Those counts are the evidence: on 27.2 the system announced 0 of 8 changes (relay posted them); on 15.7 it announced every one and the relay posted none.
- Note: the tracer gate passed (re-verified on 27.2 and 15.7) before the expansion tasks.

### Task 2: Overview and TabStripSpace
- TabStripSpace: baseline L61 on 27.2. With the relay, "2 Space changes, 0 announced, 2 posted" on 27.2 and "2 announced, 0 posted" on 15.7; it passed on both.
- Overview: see deviation 1.

### Task 3: TabGroup
- See deviation 2. Full host suite: four passed "Test run with" lines (271, 602, 124, 1331), no ✘, `no-appkit: OK (69 files)` (`.build/09-25-full.log`).

## Deviations from Plan

**1. [D-17 / RULE 0 - unexplained] OverviewIntegrationTests helper exit on 27.2 not fixed**
- **Found during:** Task 2
- **Evidence:** a temporary marker copy (`.build/09-25-overview-vm27-diag.log`) showed every step through the Esc close succeeded. `exit` then came from `swift_task_asyncMainDrainQueue`, which means the helper's top-level main run loop had been stopped during the final 400 ms wait or the `frames()` read.
- **Tried:** keeping the main thread in `dispatchAppKitEvents` for the whole fade, on the theory that the keyUp or the key panel's order-out caused the stop. It still exited (`.build/09-25-overview-vm27.log`). That was 27.2 run 3 of 3, so the change was reverted. Oops: the theory was wrong or incomplete.
- **15.7:** run 1 failed at L46 after a 16 s first test just after boot (`.build/09-25-overview-vm15.log`); run 2 passed 3/3 (`-vm15-2.log`). One attempt in between lost rsync before any test ran (`-vm15-2-rsyncdrop.log`).
- **Next:** a probe with a marker after every await and a main-loop exit observer, in a plan with its own run budget. No product cause is shown: the real app runs `NSApp.run`.

**2. [D-17 / product cause] TabGroup `closeAndMinimizeCommandsActOnFixtureWindows` on 27.2 not fixed**
- **Found during:** Task 3
- **Evidence:** two probe copies (`.build/09-25-tabgroup-vm27-diag.log`, `-diag2.log`). After the AX close press, window 43 left AX's list and the screen but stayed in the full CG list (layer 0, alpha 1, on Space 1) for at least 8.5 s. The tracker kept it `present`. On 15.7 the close confirmed in 0.109 s.
- **Why product:** the fixture retains closed windows, as many real apps do. On macOS 27 Transom would keep such windows tracked and tiled, and Close Group would stop at its 1 s confirmation. Releasing the fixture's windows would hide that. Fixing it means changing `CloseRule`, which is outside a test-only plan and needs care for minimised, hidden and other-Space windows.
- **Also seen:** on 15.7, `aTabDraggedOutWithNoWindowUnderPointerLeavesTheGroup` failed once at L46 (the fixture launch reported fewer than 2 windows). It passed on 27.2. Out of scope; recorded.

**3. [Plan text] acceptance `grep -c "D-17"` for OverviewIntegrationTests.swift and TabGroupIntegrationTests.swift is 0**
- Neither file changed, because no proven setup fix exists (deviations 1 and 2). Not adding a comment-only change just to meet the grep.

**4. [Rule 3 - Diagnosis] Temporary probe copies**
- Three diagnostic edits (Overview markers and `atexit`, two TabGroup samplers) ran in the VMs only and were reverted before any commit (`git diff` of Tests/Sources/scripts is clean). No product code changed. No test was skipped, disabled or deleted.

## Verification

- `.build/09-25-oss-vm27.log`, `.build/09-25-oss-vm15.log`: 6/6 passed each, including the three target tests.
- `.build/09-25-strip-vm27.log`, `.build/09-25-strip-vm15.log`: `theStripShowsOnlyOnItsGroupsSpace` passed.
- `.build/09-25-overview-vm27*.log`, `.build/09-25-tabgroup-vm27*.log`: failing, as recorded above.
- `.build/09-25-full.log`: 4 passed "Test run with" lines, `no-appkit: OK`.
- After every session: no `tart` process, no `.build/transom-vm.lock`, both VMs stopped, no host `TransomFixtureApp`.
- Not re-run: ViewsIntegrationTests after the relay move (the code is identical, plus a print; it compiles in the host gate).

## Self-Check: PASSED

- FOUND: Tests/TransomMacIntegrationTests/IntegrationSupport.swift, OverviewSpaceSwitchIntegrationTests.swift, TabStripSpaceIntegrationTests.swift, .planning/phases/09-polish-ship/deferred-items.md
- FOUND commits: cb3761b, f3bdae1, 4a5be15 (all ancestors of HEAD)
