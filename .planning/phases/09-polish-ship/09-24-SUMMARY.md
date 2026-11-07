---
phase: 09-polish-ship
plan: 24
subsystem: testing
status: complete
tags: [flaky-tests, live-tests, vm, macos-27, spaces, placeholders]
requires: [09-23]
provides:
  - "Deterministic FreezeTestTests.itResumesByItself (done ahead in 93c440c)"
  - "ViewsIntegrationTests green on macOS 27.2 and 15.7"
  - "RematchIntegrationTests green on macOS 27.2 and 15.7"
  - ".planning/phases/09-polish-ship/deferred-items.md with the measured cause of each"
affects: [09-25, 09-26, 09-27, 09-28]
tech-stack:
  added: []
  patterns:
    - "SpaceChangeRelay: posts activeSpaceDidChange for an SSH-run test process when the system has not within 150 ms"
key-files:
  created:
    - .planning/phases/09-polish-ship/deferred-items.md
  modified:
    - Tests/TransomMacIntegrationTests/ViewsIntegrationTests.swift
    - Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift
decisions:
  - "Views on 27.2: test setup. An SSH-run test process on 27.2 gets no activeSpaceDidChange, while the real app in the GUI session hears every switch. A test-side relay fills the gap only when the system stays silent."
  - "Rematch on 27.2: test setup. The closed fixture window was still on screen when its close replied, so the test now waits for it to leave the screen before clicking. The old 'NSWorkspace stale over SSH' theory was disproved."
metrics:
  duration: "~2h"
  completed: 2026-11-07
estimate:
  tokens: 55000
  tasks: 3
actuals:
  tokens: 2040
  tasks: 3
  commits: 2
plan_head_before: cd9aa6ffb9de1efa1fdfcd6a2aa1514f09bd3766
plan_head_after: d7cacfc2d37d78be055d536a7ea27cbca9f16cf9
---

# Phase 9 Plan 24: Carried flaky tests (D-17) Summary

**All three carried D-17 failures are fixed by changing only test setup. The Freeze test now awaits its resume task (done ahead in 93c440c). The macOS 27.2 Views failure was an SSH-session gap in Space-change notifications, now covered by a relay that posts only when the system stays silent. The 27.2 Rematch failure was a click racing a fixture window's close.**

## Tasks

| Task | Name | Commit | Result |
|------|------|--------|--------|
| 1 | itResumesByItself awaits the resume task | 93c440c (orchestrator, done ahead) | 20/20 runs (`.build/09-24-t1.log`), passed in the full suite (`.build/09-24-full.log`) |
| 2 | Views `aViewOnAnotherSpaceSwitchesFirst` on 27.2 | 048dccf | 27.2 pass on the first run with the fix, 15.7 pass |
| 3 | Rematch `aPlaceholderIsClickThroughAndBehindRealWindows` on 27.2 | d7cacfc | 27.2 pass (run 3 of 3, the first with the fix), 15.7 pass; host gate green |

### Task 1 (done ahead in 93c440c)
I checked the orchestrator's commit against this plan's criteria and changed nothing. `grep -c "ContinuousClock.now + .seconds(1)"` gives 0. `grep -c "private(set) var resumeTask"` gives 1 (the declaration is `public private(set) var resumeTask`). The test runs `let resume = try #require(freeze.resumeTask); await resume.value`. That is stricter than the plan's `await freeze.resumeTask?.value`, which would pass silently if the task were nil, so the key-link regex `resumeTask\?\.value` does not match the text. The behaviour is the same, and I kept the stricter form. It was re-verified here: 20 runs in a row and one full host run passed.

### Task 2: Views
- Baseline on 27.2: failed at L193, "the Arranger never saw Desktop 1" (`.build/09-24-views-vm27-base.log`).
- A temporary probe, not committed, measured the cause. SkyLight showed every switch, but the SSH-run process heard 0 `activeSpaceDidChange` notifications on 27.2, against 2 per round trip on 15.7. `sudo launchctl asuser`, `NSApp.finishLaunching()` and the `.accessory` policy each changed nothing. The guest's `Transom Debug.app`, launched in the GUI session, logged every switch (`space 1 → 4`). This is a harness gap, not a product bug.
- Fix: `SpaceChangeRelay`, private to the test file. It watches SkyLight's current Space and posts the notification on the process's own workspace center only when the system has not sent it within 150 ms. On 15.7 the counts balance and it posts nothing. The product's switch-first path, its 500 ms wait for the Arranger and the camera are unchanged and still under test.

### Task 3: Rematch
- Baseline on 27.2: "did not reach Finder: nil" (`.build/09-24-rematch-vm27-base.log`).
- First theory (stale NSWorkspace, as 08-UAT suspected) was wrong. Reading the frontmost app through AX also gave nil (`-diag.log`, reverted). A probe showed that a desktop click over SSH on 27.2 does make Finder frontmost (`probe4`).
- A diagnostic copy of the test (`probe5`) found the cause: when `close 1` replies on 27.2, the closed window is still on screen under the point and takes the click. Once that window had left the screen, the click went through the panel to Finder.
- Fix: after `close 1`, wait up to 3 s (required) until that window leaves the on-screen list, then click.

## Deviations from Plan

**1. [Rule 3 - Diagnosis] Temporary probe suites and a runner tweak**
- **Found during:** Tasks 2 and 3
- **Issue:** to tell setup from product, I needed evidence the suites don't log.
- **Fix:** I wrote temporary `ProbeD17Tests` suites and ran them in the VMs through `vm-session.sh`, one suite per session. I also added a temporary opt-in `TRANSOM_VM_ASUSER` wrapper to `scripts/vm-live-test.sh` and ran one session with it. Before any commit I removed the probes and restored the runner byte for byte, so none of them was committed. The logs are kept: `.build/09-24-probe*.log`. One probe session ran with the guest's own `Transom Debug.app` to read its `spaces` log.
- **Rule compliance:** live runs happened only in the VMs. On 27.2 Views ran 2 times and Rematch 3 times (base, the reverted AX attempt, the fix). On 15.7 each suite ran once. After each session no `tart` process or VM lock was left, and both VMs were stopped.

**2. [Plan text] Task 1 key-link regex**: described above. The stricter `#require` form was kept.

No product code changed, and no test was skipped, disabled or deleted.

## Verification

- `.build/09-24-t1.log`: 20 FreezeTestTests runs, 20 `itResumesByItself` passed, no ✘.
- `.build/09-24-views-vm27.log`, `.build/09-24-views-vm15.log`: 2/2 passed, including `aViewOnAnotherSpaceSwitchesFirst`.
- `.build/09-24-rematch-vm27.log`, `.build/09-24-rematch-vm15.log`: 3/3 passed, including `aPlaceholderIsClickThroughAndBehindRealWindows`.
- `.build/09-24-full.log`: 4 passed "Test run with" lines, no ✘, and `itResumesByItself` passed. `scripts/check-no-appkit.sh`: `no-appkit: OK (69 files)`.

## Follow-up for 09-25

`OverviewSpaceSwitchIntegrationTests` (including "the Arranger never sees the second Space") and `TabStripSpaceIntegrationTests` are probably the same SSH notification gap. `SpaceChangeRelay` is the likely fix, moved into `IntegrationSupport.swift` once a second suite uses it.

## Self-Check: PASSED

- FOUND: .planning/phases/09-polish-ship/deferred-items.md, Tests/TransomMacIntegrationTests/ViewsIntegrationTests.swift, Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift
- FOUND commits: 93c440c, 048dccf, d7cacfc (all ancestors of HEAD)
