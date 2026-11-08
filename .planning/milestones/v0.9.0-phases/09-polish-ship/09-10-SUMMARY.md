---
phase: 09-polish-ship
plan: 10
subsystem: settings
status: complete
tags: [settings, general, login-item, permissions, cli, ship-03, ship-01]
requires: [09-09]
provides:
  - "LoginItemStatus / LoginItemService protocol / SystemLoginItem (SMAppService.mainApp, category login, \"login item {status}\") / LoginItemToggle (pure status → toggle, isOn, needsApproval, footer, toggled(_:service:))"
  - "Settings ▸ General ▸ Startup: Open Transom at login, approval row with Open Login Items Settings, register-error footer; status re-read on appear"
  - "Settings ▸ General ▸ Permissions: Accessibility (GeneralTab.accessibilityRow) and Screen Recording (GeneralTab.screenRecordingRow) over injected closures, re-read once a second while shown"
  - "Settings ▸ General ▸ Command-line tool: GeneralTab.installedCLIPath(exists:), Copy Install Command"
  - "SettingsCopy.loginItemDebugLine(_:) and the Debug submenu line"
affects: [StatusItemController.settingsTabs, StatusItemController.debugMenuItem, 09-21 onboarding launch-at-login step (reuses LoginItemService / LoginItemToggle)]
tech-stack:
  added: [ServiceManagement (system)]
  patterns:
    - "System seam as a small protocol with one production class; tests inject a fake (no host login item ever registered)"
    - "Permission-touching calls (SnapshotCapture) reach the tab only as closures, so tests never count a touch"
key-files:
  created:
    - Sources/TransomMac/LoginItem.swift
    - Tests/TransomMacTests/LoginItemTests.swift
  modified:
    - Sources/TransomMac/Settings/GeneralTab.swift
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Tests/TransomMacTests/SettingsModelTests.swift
decisions:
  - "With requiresApproval the error footer is hidden even if register() threw: the approval row is the next step, and macOS can throw while leaving the item awaiting approval"
  - "Accessibility .probing (trusted, still checking) shows Off + Set Up…; the spec named no row for it and tracking isn't running yet"
  - "Permission rows reuse SettingsCopy.featureOn / featureOff (\"On\" / \"Off\") rather than adding duplicate strings"
  - "Command-line tool path is read on appear only (not polled); reopening the tab picks up a new install"
metrics:
  duration: "~10 min"
  completed: 2026-11-07
actuals:
  tokens: 5230
  tasks: 3
  commits: 3
plan_head_before: 885d7c59021b54d6149ceccd23d97d581017a3f6
plan_head_after: 76a9f13
---

# Phase 9 Plan 10: General tab Startup, Permissions and Command-line tool Summary

Launch at login through `SMAppService.mainApp` behind a `LoginItemService` protocol (tests use a fake), plus Accessibility / Screen Recording status rows, the `transom` CLI install row and the Debug "Login item:" line. The General tab is now complete.

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | Tracer: Open Transom at login through the login item service | 7075f42 |
| 2 | General ▸ Permissions: Accessibility and Screen Recording rows | 11ac761 |
| 3 | General ▸ Command-line tool row and the Debug "Login item" line | 76a9f13 |

## Verification

- `.build/09-10-t1.log`: LoginItemTests, 4 tests passed (tracer gate re-run passed before expanding).
- `.build/09-10-t2.log`: SettingsModelTests + ZoomOffTests, 22 tests passed (no SnapshotCapture touch from tests).
- `.build/09-10-t3.log`: LoginItemTests, 6 tests passed.
- `.build/09-10-full.log`: four passed "Test run with" lines (271, 521, 124, 1303), no ✘; `scripts/check-no-appkit.sh` → no-appkit: OK (65 files).
- Acceptance greps: `SMAppService.mainApp` in LoginItem.swift (4), `SMAppService` in LoginItemTests.swift (0), `screenRecordingGranted` / `accessibilityRow` in GeneralTab.swift (2 / 2), `loginItemDebugLine` in StatusItemController.swift (1), install command in SettingsCopy.swift (1).

## TDD Gate Compliance

Tasks 2 and 3: tests written first and confirmed failing at compile (`no member 'accessibilityRow'` / `'loginItemDebugLine'`), then implemented to green. RED was not committed separately (each task is one commit, matching prior 09 plans).

## Deviations from Plan

None in behaviour. Notes:
- `swift format lint --strict` reports indentation errors on the new files, but the repo has no `.swift-format` and existing files (e.g. ArrangingTab.swift) fail the same way, so it is not a gate here.
- Not run on the host by design: a real register / unregister, the tab's live appearance, starting at next login (09-28 VM UAT).

## Known Stubs

None.

## Threat Flags

None beyond the plan's register (T-09-15 accepted: fixed install string, never run; T-09-16 mitigated: only `SMAppService.mainApp`, only on a toggle click, tests use `FakeLoginItem`).

## Self-Check: PASSED

- FOUND: Sources/TransomMac/LoginItem.swift, Tests/TransomMacTests/LoginItemTests.swift
- FOUND commits: 7075f42, 11ac761, 76a9f13
