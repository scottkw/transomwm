---
phase: 09-polish-ship
plan: 21
subsystem: onboarding
status: complete
tags: [onboarding, launch-at-login, conflicts, settings]
requires: [09-20, 09-10, 09-04]
provides:
  - Launch at login onboarding step (ticked by default, D-07, SHIP-03)
  - macOS window features onboarding step, shown only while a Conflict is active (D-05, SHIP-02)
  - OnboardingFlow.steps(completed:conflictsActive:)
  - SetupWindowController.loginItem / .conflicts / continueLaunchAtLogin()
affects: [SetupWindowController, OnboardingView, TransomMacApp, LoginItemTests]
tech-stack:
  added: []
  patterns:
    - Injected LoginItemService on the setup controller; nil on reaching the step is preconditionFailure
    - Features step decided once at launch from ConflictController.active, so it stays once shown
    - Feature rows reuse ArrangingTab.featureRows, the same source Settings ▸ Arranging uses
key-files:
  created: []
  modified:
    - Sources/TransomEngine/OnboardingFlow.swift
    - Sources/TransomMac/Onboarding/OnboardingCopy.swift
    - Sources/TransomMac/Onboarding/OnboardingSteps.swift
    - Sources/TransomMac/Permission/SetupWindowController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Tests/TransomEngineTests/OnboardingFlowTests.swift
    - Tests/TransomMacTests/OnboardingControllerTests.swift
    - Tests/TransomMacTests/LoginItemTests.swift
decisions:
  - "Launch at login Continue moves on only when the status reads .enabled; any other outcome (requiresApproval, a register error, or a silent non-enabled status) keeps the step with the General tab's message and Open Login Items Settings, and the next Continue moves on"
  - "The features step is decided once in decideAtLaunch (conflicts are polled before it); turning the last feature off keeps the step so its rows read Off instead of the list jumping"
  - "Back is rendered leftmost by the shared page() layout (optional back: parameter) on Screen Recording, features and Launch at login"
metrics:
  duration: ~25m
  completed: 2026-11-07
estimate:
  tokens: 55000
  tasks: 2
actuals:
  tokens: 7400
  tasks: 2
  commits: 3
plan_head_before: 72d6e1ae99dc976311e9622a7faee11a3b0f0552
plan_head_after: f1b161279b8207b5c1629640c2b890d919fd93ad
---

# Phase 9 Plan 21: Launch at login and macOS window features onboarding steps Summary

Setup now ends with "Open Transom when you log in" (toggle on by default, registers through `LoginItemToggle` on Continue) and, when Stage Manager, edge tiling or click-wallpaper is on, shows "Turn off macOS features that move windows" with the same Turn Off action as the menu and Settings.

## What was built

- **Engine:** `OnboardingFlow.steps(completed:conflictsActive:)`. First run: welcome, accessibility, screenRecording, [features], launchAtLogin, done. Captions count features only when shown.
- **Launch at login step:** `power` hero, heading, `Toggle` "Open Transom at login" (`SettingsCopy.openAtLogin`), body text, Back · Continue. `continueLaunchAtLogin()` registers only while ticked; `.enabled` moves on; otherwise `model.loginResult` shows `SettingsCopy.needsApproval` (with the orange triangle) or `SettingsCopy.loginItemFailed`, plus "Open Login Items Settings"; a second Continue moves on. `TransomMacApp` wires `SystemLoginItem()`.
- **Features step:** `macwindow.on.rectangle` hero, heading and body from UI-SPEC, one row per `Conflict.allCases` (headline name, `ConflictCopy.tooltip` secondary, "Turn Off" running `conflicts.turnOff` or a green check + "Off"), and a `.link` "Open Desktop & Dock Settings" under each active row through `ConflictController.openSettings(ConflictController.desktopAndDock)`. `TransomMacApp` wires `setupController.conflicts = conflictController` (before `conflictController.start()` and `decideAtLaunch()`).
- **Back leftmost:** `page()` takes an optional `back:` and renders it before the spacer.

## Verification

- `.build/09-21-t1.log`: OnboardingControllerTests 14 passed, OnboardingFlowTests 6 passed; the three named tests passed.
- `.build/09-21-t2.log`: 16 + 7 passed, `theFeaturesStepShowsOnlyWithAnActiveConflict` and `theFeaturesStepTurnsAFeatureOffLikeTheMenu` passed.
- `.build/09-21-full.log`: four passed "Test run with" lines (271, 588, 124, 1326), no ✘; `scripts/check-no-appkit.sh` → `no-appkit: OK (69 files)`.
- Acceptance greps: `SystemLoginItem()` 1, `continueRegistersWhenTicked` 1, `com.apple.Desktop-Settings.extension` in OnboardingSteps.swift 1, `setupController.conflicts` 1.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | 0930f91 | feat(09-21): Launch at login onboarding step registers Transom by default |
| 2 (RED) | 860d158 | test(09-21): add failing tests for the macOS window features onboarding step |
| 2 (GREEN) | f1b1612 | feat(09-21): macOS window features onboarding step, shown only when one is on |

## TDD Gate Compliance

Task 2: RED commit 860d158 (tests failed to compile against the missing `conflictsActive:` API on `launchDecision` and the missing `conflicts` property), GREEN commit f1b1612. No refactor commit needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Shared FakeLoginItem**
- **Found during:** Task 1
- **Issue:** `FakeLoginItem` was `private` to LoginItemTests.swift, so onboarding tests could not use it.
- **Fix:** Dropped `private` (same test module); no duplicate fake.
- **Files modified:** Tests/TransomMacTests/LoginItemTests.swift
- **Commit:** 0930f91

**2. [Rule 2 - Missing] Back leftmost on Screen Recording**
- **Found during:** Task 1
- **Issue:** The must-have "Back is leftmost on steps 3–5" did not hold for the 09-20 Screen Recording step (Back sat after the spacer).
- **Fix:** `page()` takes an optional `back:` drawn before the spacer; Screen Recording, features and Launch at login use it.
- **Commit:** 0930f91

**3. Extra tests:** `aRegisterErrorStaysThenMovesOn` (error path) and `noActiveConflictSkipsTheFeaturesStep` (controller-level skip) beyond the named ones.

**Notes:**
- The Desktop & Dock URL literal appears in OnboardingSteps.swift as a comment; the link reuses `ConflictController.desktopAndDock` and its injectable `openSettings` rather than duplicating the URL.
- `launchDecision(completed:phase:)` gained a `conflictsActive:` argument; its three test call sites were updated.
- The controller test reaches the features step with `permission(.probing)` so `decideAtLaunch()` never calls `show()`.

## Known Stubs

None.

## Threat Flags

None. T-09-45 handled by the existing `ConflictController.turnOff` (allow-list, originals, read-back, Restore); T-09-46 by the visible default-on toggle, nothing registering before Continue, and `untickedContinueRegistersNothing`.

## Self-Check: PASSED

- All modified files exist; commits 0930f91, 860d158, f1b1612 are ancestors of HEAD.
- Not checked: the steps' visual layout in a running app (no UAT run on the host per project rules; the Tart VM UAT covers it).
