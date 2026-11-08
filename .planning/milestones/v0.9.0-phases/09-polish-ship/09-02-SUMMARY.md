---
phase: 09-polish-ship
plan: 02
subsystem: shell-routing
status: complete
tags: [url-scheme, settings, rate-limit, SHIP-08]
requires: [09-01 SettingsPane, StatusItemController.showSettings(_:from:)]
provides: [Command.settings(SettingsPane?), transom://settings URL branch, ArrangeController.openSettings]
affects: [onboarding Done button, Raycast/Alfred/scripts, transom CLI]
tech-stack:
  added: []
  patterns: [shell-handled Command case like toggleExcludeFrontmost]
key-files:
  created:
    - Tests/TransomMacTests/SettingsRouteTests.swift
  modified:
    - Sources/TransomEngine/Command.swift
    - Sources/TransomEngine/TransomURL.swift
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Tests/TransomEngineTests/TransomURLTests.swift
decisions:
  - "Only host settings may carry a URL query: exactly one item named pane; any SettingsPane raw value opens that tab, any other value opens General (D-04)"
  - "Every .settings command shares one rate-limit key (.settings(nil)) on both the URL and CLI routes"
metrics:
  duration: 23min
  completed: 2026-11-07
actuals:
  tokens: 3300
  tasks: 2
  commits: 3
plan_head_before: 9b35480634835ea982c66be38667cc04db742fb7
plan_head_after: cf74c84270ae1f272af6e772d846076911a152b7
---

# Phase 9 Plan 02: transom://settings?pane= Summary

`transom://settings?pane=updates` now passes CommandGate as `.settings(.updates)`. ArrangeController intercepts it before the Arranger and before the overview interrupt, and StatusItemController's `openSettings` closure sends it to `showSettings(_:from:)` with the source word (`url`, `cli`, `menu` or `hotkey`). The CLI gets `ok`.

## Tasks

| Task | Name | Commits | Files |
| ---- | ---- | ------- | ----- |
| 1 | Tracer: URL → gate → controller → showSettings | 9927e3e | Command, TransomURL, Arranger, MenuCopy, ArrangeController, StatusItemController, SettingsRouteTests |
| 2 | Strict parse and shared rate limit (TDD) | 645b727 (RED), cf74c84 (GREEN) | TransomURL, TransomURLTests |

## Behaviour

- `transom://settings` and `transom://settings/` open the last tab (`.settings(nil)`).
- `?pane=` followed by any of the seven raw values opens that tab. `?pane=UPDATES`, `?pane=foo`, `?pane=`, a bare `?pane` and `?pane=%75pdates` open General.
- These are rejected (nil): `?tab=`, a second `pane` item, an extra item, a path (`/updates`), a fragment, the wrong scheme and an uppercase host. Every other host still refuses any query, including `?` alone.
- `TransomURLRateLimiter.admit` keys every `.settings` command as `.settings(nil)`. `admitOpenedURL` goes through `admit`, so both routes share one second.

## TDD Gate Compliance

- RED: 645b727. `everySettingsURLSharesOneRateLimitSecond` failed with 2 issues, and the other 28 TransomURLTests passed (the Task 1 parse already met every row).
- GREEN: cf74c84. All 30 TransomURLTests pass.
- No refactor step was needed.

## Verification

- `.build/09-02-t1.log`: SettingsRouteTests ran 2 tests and both passed. `scripts/check-no-appkit.sh` printed `no-appkit: OK (65 files)`.
- `.build/09-02-t2.log`: TransomURLTests ran 30 tests and all passed. The four named tests passed.
- `.build/09-02-full.log`: four passed "Test run with" lines (271, 485, 124 and 1298 tests). There was no ✘ and no-appkit printed OK.
- All acceptance grep counts were met: Command case 1, `openSettings` in ArrangeController 2, `arrange.openSettings` 1, `settingsWithEachPaneOpensThatPane` 1, `settings` in TransomURL 6.

## Deviations from Plan

None. The plan executed as written. Task 2's parse needed no change after Task 1.

## Known Stubs

None.

## Threat Flags

None. The new surface (the settings query) is T-09-03 and T-09-04, and both are mitigated and tested.

## Self-Check: PASSED

- Tests/TransomMacTests/SettingsRouteTests.swift exists.
- Commits 9927e3e, 645b727 and cf74c84 are ancestors of HEAD.
