---
phase: 03-tiling-mvp
plan: 14
subsystem: engine-recovery
status: complete
tags: [crash-recovery, safety, restore-all, hotkeys, notices]
requires:
  - 03-07 (layout.json, SessionRecord, LayoutRestore.reattach, writeCleanExit)
  - 03-08 (home frames, park)
  - 03-10 (pause reasons, crashLoop reason)
provides:
  - Recovery (stranded rule, destination rule, launch mode, survivedMinute due)
  - LaunchMode, ArrangerInput.launch
  - Command.restoreAll, hotkey restoreAll (control-option-command-0), Safety > Restore All Windows
  - Notice.crashRecovered (N2), Notice.crashLoop (N3), Notice.restored (N6)
affects:
  - 03-15 (pane://restore routes to Command.restoreAll; quit restore writes cleanExit)
tech-stack:
  added: []
  patterns:
    - "Pure decision rules in CloseRule style (Recovery), driven by the Arranger"
    - "Rescue moves go out as their own .perform before any layout work, bypassing the pause"
key-files:
  created:
    - Sources/PaneEngine/Recovery.swift
    - Tests/PaneEngineTests/RecoveryTests.swift
    - Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-14-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-14-task2-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-14-task3-red.json
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneEngine/Arranger+Commands.swift
    - Sources/PaneEngine/Command.swift
    - Sources/PaneEngine/Notice.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/Input/Hotkeys.swift
    - Sources/PaneMac/Shell/CommandMenu.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Sources/PaneMac/Shell/NoticeCopy.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Overlay/NoticeQueue.swift
    - Tests/PaneEngineTests/ArrangerRestoreTests.swift
    - Tests/PaneMacTests/CommandMenuTests.swift
    - Tests/PaneMacTests/HotkeyTableTests.swift
    - Tests/PaneMacTests/NoticeCopyTests.swift
    - Tests/PaneMacTests/NoticeQueueTests.swift
decisions:
  - "A recovery or crash-loop launch shows every hidden Desktop tile that holds windows (an OS fact, no undo step); otherwise the first plan parks the rescued windows again"
  - "A rescued window's display is its saved desk's display, else the display it is nearest, so the rescue never re-homes a docked window to a neighbouring display"
  - "Restore All shows hidden Desktop tiles holding windows as one undo step per desk; an empty hidden Desktop is left alone, so 'nothing stranded' sends no commands"
  - "survivedMinute is written 60 s after a recovery or crash-loop launch through WakeTimer; writeCleanExit cancels it so a clean quit is never recorded as unclean"
  - "The visible part for the 40 pt floor is the bounding box of the window's pieces on each display (shortcut: overestimates on vertically offset displays)"
metrics:
  duration: 13 min
  completed: 2026-10-26
  tasks: 3
  files: 22
estimate:
  tokens: 90000
  tasks: 3
actuals:
  tokens: 44000
  tasks: 3
  commits: 7
plan_head_before: f6c14b520655bad68ef18f4adca486aacb8feb18
plan_head_after: cead94248deffab9f97f1ae84483138428a5d196
---

# Phase 3 Plan 14: Crash Recovery and Restore All Windows Summary

After an unclean exit, the next launch moves stranded windows back on screen before it touches the layout. It then re-applies the saved layout by window ID and shows toast N2. A second crash within 60 s starts paused with the crashLoop reason and toast N3. Restore All Windows (Safety menu, ⌃⌥⌘0) brings every window back on screen on demand, even while paused, and shows toast N6.

## What was built

- **`Recovery` (PaneEngine, pure).** A window is stranded when less than 50% of its area is inside the union of the displays' visible frames, or when its visible part is under 40 pt wide or tall. The 40 pt floor is capped at the window's own size. A stranded window goes to its home frame clamped on screen. With no home frame it keeps its size, centred on its display and shrunk to fit. `launchMode` returns normal (no record, or a clean exit), recovery (an unclean exit), or crashLoop (an unclean exit from a recovery launch that did not reach `survivedMinute`). `survivedMinuteDue` gives the instant 60 s after a non-normal launch.
- **Arranger.**
  - `.launch(mode)` is fed before `.restore`. A crashLoop launch adds the `crashLoop` pause reason at once.
  - At the first complete inventory of a non-normal launch, `rescueStranded` sends one `.perform` with every stranded window's destination. It ignores the pause.
  - The re-attach then sees the rescued frames. Hidden Desktop tiles holding parked windows show again, and the quiet re-plan runs.
  - Last comes `.notice(.crashRecovered(unplaced:))`, or `.notice(.crashLoop)` on a crash-loop launch. `unplaced` counts the tracked windows the saved layout did not hold.
  - `Command.restoreAll` uses the same rescue, then shows hidden Desktops as one undo step per desk, then re-plans (only when not paused) and shows N6 with the count. It is available whenever access is ready, whatever the pause reasons.
- **ArrangeController.** `start` computes `Recovery.launchMode(previous: store.contents?.session)` and feeds `.launch`. Every write records `recoveryLaunch` and `survivedMinute`. A `WakeTimer` sets `survivedMinute` 60 s into a recovery launch, and `writeCleanExit` cancels it.
- **Shell.** N2, N3 and N6 copy with their glyphs (`lifepreserver`, `lifepreserver`, `checkmark.circle`). N2 and N3 are crash notices (10 s, never replaced). The `restoreAll` hotkey is ⌃⌥⌘0, the 33rd name. The Safety section gains Restore All Windows after Pause/Resume. The crashLoop pause line "Arranging paused after Pane quit unexpectedly" already existed (03-10) and is covered by MenuCopyTests.

## Tasks

1. **Task 1 (tracer): stranded windows come back after an unclean exit.** `f304885` (test, RED), `5468943` (feat, GREEN). Tracer gate: the automated `<verify>` passed end to end, including the live `RecoveryIntegrationTests` (trusted, not skipped). Expanding from there. The human check is end-of-phase UAT (`human_verify_mode: end-of-phase`).
2. **Task 2: a second crash within a minute starts paused.** `48e27c4` (test, RED), `32698bc` (feat, GREEN)
3. **Task 3: Restore All Windows from the menu and ⌃⌥⌘0.** `b3231fe` (test, RED), `13919aa` (feat, GREEN)
4. `cead942` (refactor): `LaunchMode.crashLoop` moved onto its own documented case. The plan's acceptance grep `case crashLoop` in Recovery.swift did not match the one-line `case normal, recovery, crashLoop`.

## TDD Gate Compliance

| Task | RED | Evidence | GREEN |
|------|-----|----------|-------|
| 1 | `f304885` | `tdd/03-14-task1-red.json` RED_EVIDENCE_OK (target `aRecoveryLaunchMovesTheStrandedWindowOnScreenBeforeReapplyingTheLayout()`). With the stubs compiled, every stranded, destination and unclean-launch row failed on its assertion, as did the rescue-before-layout, unplaced-count and unpark rows and the N2 copy and queue rows. Rows the stubs already met passed. The live test was also run once at RED: it failed on its planned assertion, with the docked window back in its tile and the floating one left at x 1430. | `5468943` |
| 2 | `48e27c4` | `tdd/03-14-task2-red.json` RED_EVIDENCE_OK (target `aCrashLoopLaunchStartsPausedButStillRescuesStrandedWindows()`). The crash-loop mode, survivedMinute due, N3 and Arranger crash-loop rows failed on their assertions. ArrangerPauseTests and the Task 1 rows passed. | `32698bc` |
| 3 | `b3231fe` | `tdd/03-14-task3-red.json` RED_EVIDENCE_OK (target `restoreAllShowsTheHiddenDesktopAndMovesAnOffScreenWindowEvenWhilePaused()`). Every Restore All row failed on its assertion while its preconditions passed (c parked, b stranded while paused). The hotkey, menu and N6 rows failed on their stubs. | `13919aa` |

## Verification

- `swift test --filter "RecoveryTests|ArrangerRestoreTests|NoticeCopyTests|NoticeQueueTests"`: 20 + 13 tests passed (RecoveryTests ran).
- `swift test --filter "RecoveryTests|ArrangerRestoreTests|NoticeCopyTests|ArrangerPauseTests"` (Task 2): 30 + 32 tests passed, the latter run with NoticeQueueTests and MenuCopyTests.
- `swift test --filter "ArrangerRestoreTests|NoticeCopyTests|HotkeyTableTests|CommandMenuTests"` (Task 3): 16 + 47 tests passed, the latter run with MenuCopyTests.
- `caffeinate -d -i swift test --filter RecoveryIntegrationTests`: passed in 1.1 s, not skipped.
- `scripts/check-no-appkit.sh` and `scripts/build-debug.sh` exit 0 (Pane Debug.app valid and signed).
- Full suite. The non-live suites passed: PaneModel 190, PaneEngine 164, PaneMac 415. The live suites ran caffeinated in three bounded batches with the Mac unlocked (11 + 14 + 14 tests passed). The known `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` was skipped (deferred). The opt-in fullscreen and title-bar-drag tests were skipped. No fixtures were left running after any batch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] A recovery launch shows hidden Desktop tiles that hold parked windows**
- **Found during:** Task 1
- **Issue:** After a crash with the Desktop hidden, the restored World still says "hidden". The fresh Arranger has no `parkRequested` record, so its first plan would park the rescued windows again. The plan's human check expects Notes back at its home frame.
- **Fix:** `showParkedDesktops(keeping:undoable:)`. After the re-attach on a non-normal launch it shows each hidden Desktop tile that holds windows, as an OS fact with no undo step, and keeps each rescued floating window at its rescue frame. Restore All reuses it, with an undo step.
- **Files:** Sources/PaneEngine/Arranger.swift
- **Commit:** `5468943`

**2. [Rule 1 - Bug] The rescue uses the saved desk's display**
- **Found during:** Task 1
- **Issue:** The tracker files a window that is off every display under the nearest display. Rescuing it to that display would re-home a docked window there and break the restored layout.
- **Fix:** The display is the one the window's desk is on in the saved World (or the current World for Restore All). The window's own display is the fallback, then the first display. The rescued `WindowInfo` gets that display's UUID.
- **Commit:** `5468943`

**3. [Rule 3 - Blocking] Live test: macOS never moves a window fully off screen**
- **Found during:** Task 1, first RED live run
- **Issue:** `move 0 <maxX + 2000>` left the fixture window at x 1430, a 40 pt sliver, so the "x ≥ farX" wait failed (1 of 3 allowed live failures). A docked window would also return to its tile through the re-applied layout with no rescue at all, so the test could not tell the difference.
- **Fix:** The test treats "less than half visible" as off screen. It also adds a floating second fixture window, which only the recovery rule brings back. The second RED run failed on the planned assertion (floating window still at x 1430), and GREEN passed.
- **Files:** Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift
- **Commit:** `f304885`

### Plan items not needed

- **LayoutStore.swift:** unchanged. `contents` is set only by `load` and never by `save`, so `store.contents?.session` already is the previous session's record, even after this launch's first write.
- **PaneMacApp.swift:** unchanged. `Hotkeys.register` registers every table entry, so the new hotkey needed no wiring.
- **StatusItemController.swift:** unchanged in Task 2, because the crashLoop pause line already existed. Task 3 added the Restore All item there.

## Requirements

- **SAFE-02 complete:** recovery works end to end, including the live crash-recovery test of off-screen fixture windows.
- **SAFE-03 stays Pending:** the menu item and hotkey are done, but the requirement also needs `pane://restore`, which is plan 15.

## Known Stubs

None.

## Threat Flags

None. The session record decides recovery and the crash loop (T-03-38). Its decode and validation are the 03-07 ones, and every destination is clamped inside a display's visible frame.

## Deferred Issues

None new. `aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop` (deferred-items.md, 03-08) was skipped, not re-run.

## Self-Check: PASSED

- FOUND: Sources/PaneEngine/Recovery.swift, Tests/PaneEngineTests/RecoveryTests.swift, Tests/PaneMacIntegrationTests/RecoveryIntegrationTests.swift, tdd/03-14-task{1,2,3}-red.json
- FOUND commits: f304885, 5468943, 48e27c4, 32698bc, b3231fe, 13919aa, cead942
