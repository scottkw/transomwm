---
phase: 09-polish-ship
plan: 19
subsystem: onboarding
status: complete
tags: [onboarding, setup-window, permissions, ship-02]
requires: [09-18]
provides:
  - OnboardingStep (move…done, UI-SPEC order) and OnboardingFlow.steps(completed:) / caption(for:in:) / next(after:in:)
  - OnboardingCopy (Welcome, Done, Step n of total, Continue / Quit Transom / Done)
  - OnboardingModel + OnboardingView (step container; Welcome and Done pages; Accessibility = SetupView with a caption)
  - SetupWindowController.completedKey "onboarding.completed", launchDecision(completed:phase:), advance(), finish()
affects: [09-20, 09-21, 09-22]
tech-stack:
  added: []
  patterns:
    - onboarding steps are a pure Engine list; later plans add a case to OnboardingFlow.steps and a page in OnboardingView
    - the controller's permission-state sink moves past a ready Accessibility step in the same turn, so no ready stop renders mid-flow
key-files:
  created:
    - Sources/TransomEngine/OnboardingFlow.swift
    - Sources/TransomMac/Onboarding/OnboardingCopy.swift
    - Sources/TransomMac/Onboarding/OnboardingSteps.swift
    - Tests/TransomEngineTests/OnboardingFlowTests.swift
    - Tests/TransomMacTests/OnboardingControllerTests.swift
  modified:
    - Sources/TransomMac/Permission/SetupWindowController.swift
    - Sources/TransomMac/Permission/SetupView.swift
    - Tests/TransomMacTests/SetupWindowTests.swift
decisions:
  - "Captions count only numbered steps: the first run is Welcome 'Step 1 of 2', Accessibility 'Step 2 of 2'; any single-step list has no caption"
  - "Continue from Welcome skips the Accessibility step when access is already ready, so existing users see Welcome then Done"
  - "The ready move-on lives in SetupWindowController's permission.$state sink, not a SetupView onReady hook: the sink fires before SwiftUI renders, so the Phase 2 ready stop never shows mid-flow, and it is testable without waiting on SwiftUI"
  - "show() rebuilds the step list from onboarding.completed, so after Done the menu's Grant/Fix item opens the lone Accessibility step"
metrics:
  duration: ~10 min
  completed: 2026-11-07
actuals:
  tokens: 5600
  tasks: 2
  commits: 3
plan_head_before: f084021fa31e0498d8f88bb0de069c6e3d6db4e6
plan_head_after: 1cdde926fc825a39d511102e0e1b154318a98bc4
---

# Phase 9 Plan 19: First-run onboarding (Welcome, Accessibility, Done) Summary

Set Up Transom now opens at launch at Welcome on the first run (even when Accessibility is already granted), walks Welcome → Accessibility (Phase 2's step with a "Step 2 of 2" caption) → Done, and Done writes `onboarding.completed`; after that the Phase 2 rule returns: open only when access isn't ready, with the lone Accessibility step.

## What was built

- **Engine** `OnboardingFlow`: pure step list (`[.welcome, .accessibility, .done]` first run, `[.accessibility]` after), captions counting only Welcome…Launch at login present in the list, and `next`.
- **Mac** `OnboardingView`: Welcome (app icon 64 pt, Quit Transom · Continue) and Done (`checkmark.circle.fill` 48 pt green, Done) with Phase 2 metrics; every other step renders `SetupView`, which gained an optional `caption`. Headings carry `.isHeader` and take VoiceOver focus on appear (each step change swaps the view).
- **Controller**: `launchDecision(completed:phase:)` is used by `decideAtLaunch()` (still waits out `.probing`, still respects a user close) and by `show()`. Logs `step {name}` and `completed` under category `onboarding`. No new permission request anywhere: Accessibility is still asked only by Open System Settings (D-06).

## Verification

- `.build/09-19-t1.log`: OnboardingFlowTests (4) and SetupWindowTests (2) passed; `check-no-appkit.sh` OK.
- `.build/09-19-t2.log`: OnboardingControllerTests (4) and SetupWindowTests passed (6 tests, 2 suites).
- `.build/09-19-full.log`: four passed "Test run with" lines (271, 576, 124, 1323), no ✘; `no-appkit: OK (69 files)`.

## TDD Gate Compliance (Task 2)

- RED: `db5c168` (OnboardingControllerTests failed to compile: no `launchDecision`).
- GREEN: `1cdde92`.
- REFACTOR: none needed.

## Deviations from Plan

**1. [Rule 1 - Bug] SetupWindowTests read the test process's standard defaults**
- **Found during:** Task 1
- **Issue:** With no `onboarding.completed` the window opened at Welcome, so `theSetupWindowHeightFollowsAPermissionStateChange` saw no height change on ready.
- **Fix:** Both tests pass a throwaway defaults suite with `onboarding.completed = true`, so they keep testing Phase 2's single step (and no longer touch standard defaults).
- **Files modified:** Tests/TransomMacTests/SetupWindowTests.swift
- **Commit:** 4b95de5

**2. SetupView caption in Task 1, no `onReady` hook in Task 2**
- SetupView took the `caption` parameter in Task 1 (the tracer needs it on the Accessibility step). The plan's `onReady` hook was not added: the controller's state sink already moves on before SwiftUI renders, which meets the same truth with less code. `SetupView` still shows its Phase 2 ready state for the single-step list.

## Known Stubs

None. Steps move, screenRecording, features and launchAtLogin exist only as enum cases; `OnboardingFlow.steps` never returns them until 09-20…09-22 add them with their pages.

## Self-Check: PASSED

- Files: OnboardingFlow.swift, OnboardingCopy.swift, OnboardingSteps.swift, OnboardingFlowTests.swift, OnboardingControllerTests.swift present.
- Commits: 4b95de5, db5c168, 1cdde92 are ancestors of HEAD.
