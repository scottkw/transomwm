---
phase: 03-tiling-mvp
plan: 16
subsystem: conflicts
status: complete
tags: [safe-04, stage-manager, cfpreferences, alerts, menu]
requires:
  - "03-10: PauseReason.stageManager, the pause line, CommandMenu and the Safety section"
  - "03-11: Arranger.isDragging"
  - "03-13/03-14: NoticeQueue, NoticeCopy, ToastPresenter"
provides:
  - "ConflictPolicy (PaneEngine): key table, active features, turn-off and restore plans, alert episodes"
  - "PreferencesStore / CFPreferencesStore (PaneMac)"
  - "ConflictController: 2 s poll and on activation, Stage Manager pause, Turn Off with read-back, Restore, modeless alerts"
  - "Status menu conflict lines and Safety > Restore macOS Window Settings"
  - "Notice.turnOffFailed (N7) and Notice.settingsRestored (N8)"
affects:
  - "03-17 (phase wrap-up / UAT): the human check below"
tech-stack:
  added: []
  patterns:
    - "Injected PreferencesStore: an in-memory store in unit tests, a test-only CFPreferences domain for the real I/O"
    - "Modeless NSAlert: layout(), button target/action on the controller, makeKeyAndOrderFront; no runModal"
key-files:
  created:
    - Sources/PaneEngine/ConflictPolicy.swift
    - Sources/PaneMac/WindowManagerSettings.swift
    - Sources/PaneMac/ConflictController.swift
    - Sources/PaneMac/Shell/ConflictCopy.swift
    - Tests/PaneEngineTests/ConflictPolicyTests.swift
    - Tests/PaneMacTests/WindowManagerSettingsTests.swift
    - Tests/PaneMacTests/ConflictControllerTests.swift
    - Tests/PaneMacTests/ConflictCopyTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-16-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-16-task2-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-16-task3-red.json
  modified:
    - Sources/PaneEngine/Notice.swift
    - Sources/PaneMac/Shell/NoticeCopy.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/Overlay/NoticeQueue.swift
    - Sources/PaneMac/Overlay/Toast.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Tests/PaneMacTests/NoticeCopyTests.swift
key-decisions:
  - "Recorded originals are JSON-encoded [String: PrefValue] under windowManagerOriginals; on load only allow-listed keys holding a boolean or absent survive (T-03-45)"
  - "A key holding a non-boolean is never written: Turn Off skips it and records no original for it"
  - "Restore marks every feature with a recorded key as restoredByPane; the set is pruned to the active features on each poll, so only a feature Restore turned back on skips its alert"
  - "presentAlert nil means no alert UI (unit tests); PaneMacApp sets it to showModelessAlert"
  - "Restore macOS Window Settings is a plain status-menu item, not a Command: it has no hotkey and no Arranger availability rule"
  - "N7's orange glyph comes from NoticeCopy.isWarning, passed to ToastPresenter.show(warning:)"
requirements-completed: [SAFE-04]
duration: 11 min
completed: 2026-10-26
actuals:
  tokens: 15000
  tasks: 3
  commits: 6
plan_head_before: 16d069219a875b36b6bb24e28b182d54e1d8c4d3
plan_head_after: e3253c08215566979cb5575232809a8e87cebdad
---

# Phase 3 Plan 16: macOS Conflict Settings (SAFE-04) Summary

Pane now reads Stage Manager, macOS edge tiling and click-wallpaper from com.apple.WindowManager through CFPreferences every 2 s and on activation. Arranging pauses while Stage Manager is on. Each active conflict gets a menu line that turns the feature off. Each turn-off records the original values once and reads the write back about 1 s later; if the write didn't take, Pane opens Desktop & Dock and shows N7. Restore macOS Window Settings puts every original back and shows N8. Each feature raises one modeless alert per on-episode.

## What was built

- **ConflictPolicy** (PaneEngine, pure). The key table from RESEARCH Pattern 13:
  - Stage Manager is `GloballyEnabled`, off when absent.
  - Edge tiling is `EnableTilingByEdgeDrag` / `EnableTopTilingByEdgeDrag`, checked only when osMajor ≥ 15, on when absent.
  - Click wallpaper is `EnableStandardClickToShowDesktop`, on when absent.
  - A non-boolean counts as off and is reported through `badKeys`. `EnableTilingOptionAccelerator` is named only in a doc comment and is in no plan (tested).
  - Also here: `restoreWrites` (a boolean goes back, an absent key is deleted, nothing outside the allow-list) and `alertsDue`.
- **CFPreferencesStore**. `CFPreferencesCopyAppValue` gives nil → absent, a CFBoolean → bool (a CFNumber 1 is *not* a bool), anything else → other. `SetAppValue` writes kCFBooleanTrue/False, or nil to delete, then `AppSynchronize`. PaneMacApp makes the only instance on `ConflictPolicy.domain`. Nothing restarts or signals WindowManager.
- **ConflictController**:
  - Sends `.setPaused(.stageManager, on)` when the state is first known and on every change.
  - Turn Off records each original once, writes, and reads back. On a mismatch it opens `x-apple.systempreferences:com.apple.Desktop-Settings.extension` and posts N7.
  - Restore is enabled only while originals are recorded. It writes them back, clears them and posts N8.
  - Alerts: the queue shows one at a time in the fixed order. A due alert waits while `isDragging` (it retries every 250 ms) and is withdrawn if its feature turns off. Not Now is kept in `conflictNotNow` and pruned when the feature goes off. A modeless `NSAlert` has "Turn Off" as the default (Return) and "Not Now" (Esc). Closing it counts as Not Now.
- **Menu**:
  - One line per active conflict, after the degraded line: a template `exclamationmark.triangle` with accessibilityDescription "Conflict" and the UI-SPEC tooltip.
  - Safety ▸ "Restore macOS Window Settings" after Restore All Windows. It has no shortcut and is greyed out while nothing is recorded.
  - The Stage Manager pause line and the disabled Resume come from 03-10, unchanged.

## Tasks

1. **Task 1 (tracer): Stage Manager pauses and its menu line turns it off.** `4472d58` (test, RED), `e42a811` (feat, GREEN). Tracer gate: the automated `<verify>` was re-run end to end after GREEN and passed (13 tests across both products, WindowManagerSettingsTests present). No blocking-human gate, `human_verify_mode: end-of-phase`, so execution continued.
2. **Task 2: edge tiling, click wallpaper, N7 and Restore.** `30e54cc` (test, RED), `b71e27f` (feat, GREEN).
3. **Task 3: one modeless alert per on-episode.** `d4a2910` (test, RED), `e3253c0` (feat, GREEN).

## TDD Gate Compliance

| Task | RED | Evidence | GREEN |
|------|-----|----------|-------|
| 1 | `4472d58` | `tdd/03-16-task1-red.json` RED_EVIDENCE_OK (target `stageManagerIsOnOnlyWhenGloballyEnabledIsTrue()`). Against the empty stub, the true row failed and the three off rows passed. Store round trips, controller pause/Turn Off and every copy string failed on their assertions | `e42a811` |
| 2 | `30e54cc` | `tdd/03-16-task2-red.json` RED_EVIDENCE_OK (target `restoreWritesTheBooleanBackAndDeletesAKeyThatWasAbsent()`). The N7 read-back, Restore and N7/N8 copy rows failed. Some rows passed already at RED: edge-tiling, click-wallpaper, record-once and crafted-plist, because Task 1's action required the full key table and the validated originals | `b71e27f` |
| 3 | `d4a2910` | `tdd/03-16-task3-red.json` RED_EVIDENCE_OK (target `anAlertIsDueOnlyWhenAFeatureTurnsOn()`). The first-launch row and the fixed-order row failed. All five controller alert rows failed on their presented lists or `shownAlert` | `e3253c0` |

## Verification

- `swift test --filter "ConflictPolicyTests|WindowManagerSettingsTests|ConflictCopyTests"` (plus ConflictControllerTests): passed, and WindowManagerSettingsTests appears in the output.
- `swift test --filter "ConflictPolicyTests|NoticeCopyTests"`: passed.
- `scripts/build-debug.sh`: exit 0. `Pane Debug.app` is valid and satisfies its designated requirement.
- `swift test --skip PaneMacIntegrationTests`: PaneModel 190, PaneEngine 188, PaneMac 436, all passed.
- `scripts/check-no-appkit.sh`: OK (39 files).
- Acceptance greps:
  - `"com.apple.WindowManager"` appears once in ConflictPolicy.swift and 0 times in Tests.
  - `EnableTilingOptionAccelerator` appears once in ConflictPolicy.swift (the doc comment).
  - In ConflictController.swift: `isOperatingSystemAtLeast` 1, `Desktop-Settings.extension` 1, `runModal` 0, `conflictNotNow` 2.
  - `case settingsRestored` appears once in Notice.swift.
  - `killall` in Sources: 1, the existing 03-15 doc comment (see Deviations).
- The real com.apple.WindowManager domain was never written. Unit tests used `MemoryPreferences` or `com.eightabyte.pane.tests.windowmanager`, and no `defaults write` was run.

**Live suites not re-run.** The live PaneMacIntegrationTests were not run, because no path they exercise changed. ArrangeController only gained `post` and `setPaused`, and the toast gained a `warning` flag that defaults to false.

**Human check (end-of-phase UAT).** Still open: the real WindowManager adoption of the writes (A11), the System Settings toggles, Not Now after a relaunch, docking with an alert open, and VoiceOver.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Exhaustive switches over Notice**
- **Found during:** Task 2 RED
- **Issue:** Adding the N7/N8 cases broke `NoticeQueue.merged(with:)` and `ArrangeController.displayUUID(of:)`.
- **Fix:** Both new cases added (never merged; shown on the menu-bar display).
- **Files modified:** Sources/PaneMac/Overlay/NoticeQueue.swift, Sources/PaneMac/ArrangeController.swift
- **Commit:** 30e54cc

**2. [Rule 2 - Missing] N7's orange glyph**
- **Found during:** Task 2
- **Issue:** UI-SPEC wants N7's `exclamationmark.triangle.fill` in systemOrange, but the toast drew every glyph in secondaryLabelColor.
- **Fix:** Added `NoticeCopy.isWarning` and `ToastPresenter.show(warning:)`. Toast.swift was not in the plan's file list.
- **Commit:** b71e27f

### Other notes

- `ConflictControllerTests.swift` is a new test file (not listed in the plan). Task 1 named the controller behaviour but no file for it.
- `CommandMenu.swift` was not changed. Restore macOS Window Settings is not a Command (no hotkey, no Arranger rule), so StatusItemController adds it directly.
- The plan's `killall` baseline of 0 is stale. 03-15 added a doc comment that mentions `killall Pane`. 03-16 adds none. This is logged in deferred-items.md.
- The test UserDefaults suites leave empty plists in ~/Library/Preferences. This pattern was already there (GapPreferenceTests left 102). I deleted the ones these tests created and logged the issue in deferred-items.md.

## Known Stubs

None.

## Threat Flags

None. The only new trust-boundary surface is the planned com.apple.WindowManager write path (T-03-44 to T-03-47), mitigated as follows:
- Only allow-listed keys are written, and only booleans.
- Originals are validated on load.
- Alerts are modeless.
- Tests never use the real domain.

## Self-Check: PASSED

- All created files exist: ConflictPolicy.swift, WindowManagerSettings.swift, ConflictController.swift, ConflictCopy.swift, the four test files and the three RED records.
- Commits 4472d58, e42a811, 30e54cc, b71e27f, d4a2910 and e3253c0 are ancestors of HEAD.
