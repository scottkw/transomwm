---
phase: 09-polish-ship
plan: 03
subsystem: cli
status: complete
tags: [cli, settings, help, ship-08]
requires: [09-02 transom://settings?pane= route]
provides: ["transom settings [pane]", "CLICopy.settingsTooManyArguments", "help section App"]
affects: [transom-cli, transom help]
tech-stack:
  added: []
  patterns: ["CLI argument mapped to a known enum raw value before it enters the URL"]
key-files:
  created: []
  modified:
    - Sources/TransomEngine/CLICommandLine.swift
    - Sources/TransomEngine/CLICopy.swift
    - Sources/TransomEngine/TransomURL.swift
    - Tests/TransomEngineTests/CLICommandLineTests.swift
    - Tests/TransomEngineTests/CLICopyTests.swift
decisions:
  - "transom settings <pane> sends only a SettingsPane raw value; unknown text becomes general (exit 0), so no argument text reaches the URL (T-09-05)"
requirements: [SHIP-08]
duration: 15m
completed: 2026-11-07
actuals:
  tokens: 2500
  tasks: 2
  commits: 2
plan_head_before: 009d4a5a21ab885ad76f945bf3fb063a894b8f65
plan_head_after: 409d07d
---

# Phase 9 Plan 03: transom settings CLI command Summary

`transom settings [pane]` sends `settings` or `settings?pane=<known raw value>`, which the tool and the app both parse with `TransomURL.parse`. `transom help` now has an "App" section that lists the command.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 (tracer) | `transom settings updates` sends a path that parses to `.settings(.updates)` | 68833c4 | CLICommandLine.swift, CLICopy.swift, CLICommandLineTests.swift |
| 2 | App section in `transom help`, pinned by the contract test | 409d07d | TransomURL.swift, CLICopyTests.swift |

## Behaviour

- `transom settings` sends `.send("settings")`, which opens Settings on its last tab.
- `transom settings updates` sends `.send("settings?pane=updates")`. A test checks the round trip to `.settings(.updates)`.
- `transom settings Foo&x=1` sends `.send("settings?pane=general")` and exits 0.
- `transom settings a b` returns `.usage("transom: settings takes at most one argument.")` and exits 64.
- Help line: `  settings [pane]      Open Settings, at a pane if one is named` (63 columns, ASCII).

## Verification

- `.build/09-03-t1.log`: CLICommandLineTests, 12 tests passed, including all four new settings tests.
- `.build/09-03-t2.log`: CLICopyTests, 6 tests passed (contract block, fits terminal, exact settings line, one help line per command).
- `.build/09-03-full.log`: full host suite passed on four "Test run with" lines (271, 485, 124, 1303), and `scripts/check-no-appkit.sh` printed `no-appkit: OK (65 files)`.

## Deviations from Plan

**1. [Rule 3 - Blocking] Added `import Foundation` to CLICommandLineTests.swift.** The new round-trip test builds a `URL`, and that file imported only TransomEngine and Testing. Commit 68833c4.

## Threat Flags

None. T-09-05 is handled as planned: only a `SettingsPane` raw value enters the URL.

## Known Stubs

None.

## Self-Check: PASSED

- All 5 modified files exist; commits 68833c4 and 409d07d are on HEAD.
- No STATE.md or ROADMAP.md changes (the orchestrator owns those).
