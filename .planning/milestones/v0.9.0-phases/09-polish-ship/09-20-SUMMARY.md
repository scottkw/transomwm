---
phase: 09-polish-ship
plan: 20
subsystem: onboarding
status: complete
tags: [onboarding, screen-recording, permissions, settings]
requires: [09-19]
provides:
  - Screen Recording onboarding step (request once per click, 1 s preflight poll)
  - OnboardingFlow.resume(stored:in:) and UserDefaults key onboarding.step
  - Completion on close from Screen Recording onward
  - Done's Open Settings
affects: [SetupWindowController, OnboardingView, TransomMacApp]
tech-stack:
  added: []
  patterns:
    - Injected closures for SnapshotCapture so tests never touch Screen Recording
    - Task-based 1 s poll owned by the controller, cancelled on step change and window close
key-files:
  created: []
  modified:
    - Sources/TransomEngine/OnboardingFlow.swift
    - Sources/TransomMac/Onboarding/OnboardingCopy.swift
    - Sources/TransomMac/Onboarding/OnboardingSteps.swift
    - Sources/TransomMac/Permission/SetupWindowController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Tests/TransomMacTests/OnboardingControllerTests.swift
    - Tests/TransomEngineTests/OnboardingFlowTests.swift
decisions:
  - "Screen Recording step reads and requests only through injected closures; a nil closure on reaching the step is a wiring bug (preconditionFailure), as is a nil openSettings on Done"
  - "Allow uses the request's return value as the first answer; the poll then runs every 1 s while the step shows and keeps the asked state across Back"
  - "The Accessibility step's ready-state Done advances when a later step exists (reachable via Back from Screen Recording), and closes otherwise"
requirements: [SHIP-02]
metrics:
  duration: ~20 min
  completed: 2026-11-07
actuals:
  tokens: 6500
  tasks: 2
  commits: 3
plan_head_before: 1d0fb88052ee70798878288c927441a95bf6b199
plan_head_after: 84475cd8e8ecbf396ce4863b759a8b2f0d22c0fe
---

# Phase 9 Plan 20: Screen Recording onboarding step, relaunch resume and Done's Open Settings Summary

The first run now walks Welcome, Accessibility, Screen Recording (optional) and Done. Allow Screen Recording calls the injected `SnapshotCapture.request` exactly once per click, then a 1 s `isGranted` preflight poll runs only while the step shows. `onboarding.step` lets macOS's Quit & Reopen resume past Screen Recording, closing from step 3 onward completes onboarding, and Done offers Open Settings.

## What was built

- **Engine** (`OnboardingFlow`): first run is `[.welcome, .accessibility, .screenRecording, .done]`. `resume(stored:in:)` returns the step after Screen Recording for a stored `screenRecording`, the stored step when it is in the list, and the first step otherwise. The stored value is parsed through `OnboardingStep(rawValue:)` (T-09-44).
- **Controller** (`SetupWindowController`): `screenRecordingGranted` / `requestScreenRecording` / `openSettings` closures; `allowScreenRecording()`, `pollScreenRecording()` (test seam), `back()`, `openSettingsFromDone()`. Entering the step writes `zoomPreviewExplainerShown = true`, checks once and starts the poll `Task`. Every step change writes `onboarding.step` and cancels the poll, and closing the window cancels it too. `decideAtLaunch()` resumes from `onboarding.step` on a first run. `windowWillClose` sets `onboarding.completed` from Screen Recording onward.
- **View** (`OnboardingView`): the Screen Recording page has the `rectangle.dashed.badge.record` hero, heading, body and the monthly line. Before Allow it shows Back · Skip · Allow Screen Recording. After Allow it shows a spinner, "Waiting for Screen Recording…", the System Settings path, and Back · Continue (never disabled). Once granted it shows a green check, "Screen Recording is on." and Back · Continue. Done shows Open Settings · Done. `page(...)` gained a `detail` slot. All strings are in `OnboardingCopy`.
- **Wiring** (`TransomMacApp.run`): the closures are set to `SnapshotCapture.isGranted()` / `.request()` right after the controller is built, before `decideAtLaunch()`. `openSettings` is set to `controller.showSettings($0, from: "onboarding")`.

## Verification

- `.build/09-20-t1.log`: OnboardingControllerTests, OnboardingFlowTests and ZoomOffTests pass, including `allowRequestsExactlyOncePerClick`, `theStepOnlyPollsAfterwards`, `continueIsNeverBlockedWhileWaiting` and `reachingTheStepMarksThePreviewsAlertAnswered`. ZoomOffTests shows no SnapshotCapture touches.
- `.build/09-20-t2.log`: `resumeSkipsPastScreenRecording`, `resumeFallsBackToTheFirstStep`, `closingFromScreenRecordingCompletes` and `openSettingsCompletesAndOpensSettings` pass.
- `.build/09-20-full.log`: four "Test run with … passed" lines (271, 582, 124, 1325 tests) and no ✘. `scripts/check-no-appkit.sh` printed `no-appkit: OK (69 files)`.
- Acceptance greps: `screenRecordingGranted` appears 2 times in SetupWindowController, `requestScreenRecording` appears 1 time in TransomMacApp, and `func resume` appears 1 time. `grep -c "onboarding.step"` prints 2 because the unescaped `.` also matches "onboarding steps" in an existing doc comment (the baseline was 1, not 0). `grep -cF` prints 1.
- Tracer gate: Task 1's verify was re-run on the committed code and passed before Task 2 expanded it.

## TDD Gate Compliance (Task 2)

- RED: `14df625`. The suite failed to compile because `OnboardingFlow` had no `resume`, and `stepKey`, `openSettings` and `openSettingsFromDone` were missing.
- GREEN: `84475cd`. The filtered and full suites pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The existing `readyDuringOnboardingMovesOnByItself` expected `.done` after Accessibility**
- **Found during:** Task 1
- **Issue:** With Screen Recording added, ready access now moves on to `.screenRecording`, which needs the closures to be wired.
- **Fix:** The test injects the counting fake, expects `.screenRecording`, and asserts zero requests.
- **Commit:** 87d64cd

**2. [Rule 1 - Bug] Back from Screen Recording could strand the user on Accessibility's "Done"**
- **Found during:** Task 1
- **Issue:** Back returns to Accessibility (UI-SPEC). With access ready, Phase 2's `SetupView` shows "Done", which closed the window mid-first-run and left onboarding pending.
- **Fix:** The `close` closure passed to `SetupView` now advances when a later step exists and closes otherwise. The lone post-completion step is unchanged.
- **Files modified:** Sources/TransomMac/Permission/SetupWindowController.swift
- **Commit:** 87d64cd

**3. [Rule 1 - Bug] Test fake released early**
- **Found during:** Task 1, first test run (a `Fatal error` on an unowned read)
- **Fix:** `FakeScreenRecording`'s closures capture the fake strongly. There is no cycle: the fake holds no reference to the controller.
- **Commit:** 87d64cd

## Known Stubs

None.

## Backstop (not verified on host)

- The truth "On macOS 15, granting Screen Recording and accepting Quit & Reopen resumes onboarding at the step after Screen Recording" (verification: backstop) needs a Tart VM run. Resume depends on `windowWillClose` not firing during app termination. If it did fire, onboarding would count as complete and the window would not reopen at Done.

## Self-Check: PASSED

- All seven modified files exist. Commits 87d64cd, 14df625 and 84475cd are ancestors of HEAD.
