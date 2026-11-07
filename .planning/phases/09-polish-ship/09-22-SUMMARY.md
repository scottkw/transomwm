---
phase: 09-polish-ship
plan: 22
subsystem: onboarding
status: complete
tags: [onboarding, install, app-translocation, quarantine, D-08, SHIP-02]
requires: [09-13 InstallLocation, 09-19..09-21 onboarding flow]
provides:
  - "InstallLocation.classify(bundlePath:home:) / needsMove"
  - "OnboardingFlow.steps(completed:conflictsActive:needsMove:) with .move first"
  - "AppMover: copy + trash + quarantine strip + relaunch after exit"
  - "Move to Applications step, Replace alert, failure callout"
affects: [SetupWindowController, OnboardingView, OnboardingCopy]
tech-stack:
  added: []
  patterns:
    - "Relaunch helper: fixed /bin/sh script, pid and path as $1/$2 argv (TCCReset analog)"
    - "Destructive NSAlert: confirmRestoreDefaults pattern (empty key equivalent, Cancel on Return, Esc monitor)"
key-files:
  created:
    - Sources/TransomMac/Onboarding/AppMover.swift
    - Tests/TransomEngineTests/InstallLocationTests.swift
    - Tests/TransomMacTests/AppMoverTests.swift
  modified:
    - Sources/TransomEngine/InstallLocation.swift
    - Sources/TransomEngine/OnboardingFlow.swift
    - Sources/TransomMac/Onboarding/OnboardingCopy.swift
    - Sources/TransomMac/Onboarding/OnboardingSteps.swift
    - Sources/TransomMac/Permission/SetupWindowController.swift
    - Tests/TransomEngineTests/OnboardingFlowTests.swift
    - Tests/TransomMacTests/OnboardingControllerTests.swift
decisions:
  - "A needed Move always comes first: OnboardingFlow.resume returns .move whenever steps start with it, so a stored later step can't skip it"
  - "The launch show rule is unchanged: a completed run with working access from a disk image doesn't pop the window; when it does open, Move is first"
  - "Destination is always /Applications/Transom.app (plan + UI-SPEC copy), not the running bundle's own name"
  - "If the relaunch helper can't start, the failure is logged and Transom still quits; the copy is already in Applications"
metrics:
  duration: ~25 min
  completed: 2026-11-07
estimate:
  tokens: 60000
  tasks: 2
actuals:
  tokens: 7300
  tasks: 2
  commits: 3
plan_head_before: 631e9fafaf3175387d85e833b85af257ae22a050
plan_head_after: 497af7deb280318772d6300c68f4c4042d1b74e3
---

# Phase 9 Plan 22: Move to Applications Summary

A Transom opened from a disk image, the Downloads folder or a translocated path now shows "Move Transom to Applications" before any permission step. Move copies the bundle to `/Applications/Transom.app` (the old copy goes to the Trash after a destructive confirm), strips quarantine from the fresh copy, starts a `/bin/sh` helper that waits for this pid to exit and then opens the copy, and quits. No SPI is used.

## What was built

- **`InstallLocation.classify(bundlePath:home:)`** returns `.translocated` (`/AppTranslocation/`), `.diskImage` (`/Volumes/`), `.downloads` (`home/Downloads/`), `.applications` or `.other`. **`needsMove`** is true for the first three.
- **`OnboardingFlow.steps(..., needsMove:)`** puts `.move` first, including after completion (`[.move, .accessibility]`). `resume` always returns `.move` when it is first. The parameter defaults to `false`, so existing callers didn't change.
- **`AppMover`** (`@MainActor enum`):
  - `copy(from:to:trash:)` sends an existing destination through `trash`, runs `copyItem`, then `removexattr("com.apple.quarantine", XATTR_NOFOLLOW)` on every item in the copied tree.
  - `moveToTrash` is the real `trash`, using `FileManager.trashItem`.
  - `relaunchArguments(pid:path:)` is the fixed script with `"$1"`/`"$2"`.
  - `relaunchAndQuit(path:)` runs the helper `Process`, logs a launch failure under category `onboarding`, then calls `NSApp.terminate`.
- **The Move step:**
  - Layout: `folder` hero at 48 pt in secondary, heading, `OnboardingCopy.moveBody(place)` naming the place, then **Quit** · **Move to Applications** (default).
  - A failed copy shows a callout-E-styled GroupBox (red `xmark.octagon.fill` plus "Couldn't move Transom. Drag it to the Applications folder yourself, then open it from there."). The step and its buttons stay.
- **`SetupWindowController`**:
  - Takes `place:` (default `InstallLocation.classify(bundlePath: Bundle.main.bundlePath, home: NSHomeDirectory())`) and threads `needsMove` through `init`, `decideAtLaunch`, `launchDecision` and `show`.
  - `moveToApplications()` shows the Replace alert when `/Applications/Transom.app` exists. The alert has "Replace" (`hasDestructiveAction`, empty key equivalent) and "Cancel" (Return and Esc). Cancel keeps the step. Otherwise the controller copies, then relaunches and quits.
- **`OnboardingModel.copyForMove(_:)`** is the model-level helper: it logs a thrown copy, sets `moveFailure`, and returns `false`.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Tracer: classify, steps with Move first, AppMover copy and relaunch | 24d3c9c |
| 2 (RED) | Failing tests for the Move step | f38ddb0 |
| 2 (GREEN) | Move step, Replace alert, failure callout | 497af7d |

Tracer gate: the Task 1 `<verify>` chain was re-run end-to-end after the final Task 1 edit and passed before Task 2 started.

## Verification

- `.build/09-22-t1.log`: InstallLocationTests (4), OnboardingFlowTests (8, incl. `moveComesFirstWhenNeeded`), AppMoverTests (3). All passed, and `check-no-appkit.sh` passed.
- `.build/09-22-t2.log`: AppMoverTests and OnboardingControllerTests, 22 tests, all passed, including `theMoveBodyNamesThePlace`, `aFailedCopyKeepsTheStepWithTheFailureText` and `aDiskImageLaunchStartsAtMoveEvenAfterCompletion`.
- `.build/09-22-full.log`: four passed "Test run with" lines (271, 594, 124, 1331), no ✘. `no-appkit: OK (69 files)`.
- Acceptance greps: `SecTranslocate` in AppMover.swift = 0; `trashItem` = 1; "Replace the Transom in Applications?" in OnboardingCopy.swift = 1; `InstallLocation.classify` in SetupWindowController.swift = 1.

## TDD Gate Compliance

RED `f38ddb0`: the tests failed to compile (`OnboardingCopy` had no `moveBody`, and `OnboardingModel` had no `copyForMove` or `place`). GREEN `497af7d`: the tests pass. No refactor commit was needed.

## Deviations from Plan

**1. [Rule 2 - Correctness] `resume` returns `.move` whenever Move is first**
- **Found during:** Task 1
- **Issue:** A first run interrupted at Accessibility and relaunched from a DMG would resume at the stored step and skip Move. That breaks D-08's "before any permission".
- **Fix:** One line in `OnboardingFlow.resume`, covered in `moveComesFirstWhenNeeded`.
- **Commit:** 24d3c9c

**2. [Rule 3 - Blocking] `AppMover.moveToTrash` wrapper**
- **Found during:** Task 1 (acceptance grep `trashItem` ≥ 1 in AppMover.swift)
- **Issue:** `FileManager.default.trashItem` is `(URL, AutoreleasingUnsafeMutablePointer?)`, so it can't be passed directly as `(URL) throws -> Void`, and the plan's acceptance requires `trashItem` in AppMover.swift.
- **Fix:** A one-line static that the controller passes as `trash`.
- **Commit:** 24d3c9c

**3. [Addition] Controller-level test `aDiskImageLaunchStartsAtMoveEvenAfterCompletion`** in OnboardingControllerTests. It covers the `SetupWindowController` wiring (Move first on the first run despite a stored later step, and `[.move, .accessibility]` after completion). It uses a probing permission so the window never shows.
- **Commit:** f38ddb0

## Known Stubs

None.

## Backstop (not run on host, by rule)

"A quarantined download launched from the DMG in a VM shows the Move step, relaunches from /Applications, and the permissions then persist" is a VM UAT backstop (UI-SPEC). This assumes RESEARCH A1–A3: copying through a translocated path works, a programmatic copy keeps quarantine, and LaunchServices reuses a running instance.

## Self-Check: PASSED

- Files exist: AppMover.swift, InstallLocationTests.swift, AppMoverTests.swift.
- Commits 24d3c9c, f38ddb0 and 497af7d are ancestors of HEAD. 3 commits were measured from the ledger.
