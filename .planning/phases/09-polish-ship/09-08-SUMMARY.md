---
phase: 09-polish-ship
plan: 08
subsystem: settings
status: complete
tags: [settings, exclusions, ship-01]
requires: [09-07]
provides:
  - "Settings ▸ Exclusions tab (ExclusionsTab): sorted list with 16 pt icons, + via NSOpenPanel, − removes the selection"
  - "ExclusionsTab.rows(_:displayName:), ExclusionsTab.decide(bundleID:own:), ExclusionsTab.exclude(_:own:in:)"
  - "SettingsCopy: addApp, removeApp, exclusionsFooter, addAppMessage, addAppPrompt, cantExcludeSelf, noBundleID(_:)"
affects: [StatusItemController.settingsTabs, StatusItemController.displayName(of:) now internal]
tech-stack:
  added: []
  patterns:
    - "Pure static helpers on the SwiftUI tab (rows / decide / exclude) tested against a throwaway ExclusionStore; the view only wires NSOpenPanel and selection"
key-files:
  created:
    - Sources/TransomMac/Settings/ExclusionsTab.swift
  modified:
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Tests/TransomMacTests/SettingsModelTests.swift
decisions:
  - "rows takes the store, not a bundle-ID array, so the order is ExclusionStore.sortedEntries itself; an uninstalled app sorts by its bundle ID, as in the menu"
  - "decide is a MainActor static, not nonisolated, because ExclusionStore.isValid is MainActor-isolated; avoids touching ExclusionStore"
  - "Several refusals from one + click show one line each; the refusal text clears on the next + click"
metrics:
  duration: "~15 min"
  completed: 2026-11-07
actuals:
  tokens: 3300
  tasks: 2
  commits: 3
plan_head_before: 940e5c25c837500db5e7eca260ef514947e899fc
plan_head_after: 11be14eb5e54b2c3805c191fc7a9869fc0722c64
---

# Phase 9 Plan 08: Exclusions Settings Tab Summary

The Settings ▸ Exclusions tab lists the apps Transom never arranges, from the same `ExclusionStore` the menu's Never Arrange list uses. + adds apps through an Open panel (refusing Transom itself and apps with no bundle ID), and − removes the selected apps at once.

## What was built

- **ExclusionsTab** (`Sources/TransomMac/Settings/ExclusionsTab.swift`): a bordered `List` with multiple selection. Rows come in `sortedEntries` order, with a 16 pt icon from `NSWorkspace.icon(forFile:)` and the name truncated to 32 graphemes. An app that is no longer installed shows its bundle ID in the secondary colour next to a blank 16 pt frame. An empty list shows a centred secondary "No apps excluded". The +/− buttons are `.borderless` and carry the accessibility labels "Add App" and "Remove App"; − is disabled while nothing is selected. Under them sit the refusal line, if any, and the UI-SPEC footer.
- **+**: an `NSOpenPanel` at /Applications with `[.application]`, multiple selection, the UI-SPEC message and the prompt "Exclude". Each chosen app goes through `decide`: Transom's own ID (compared case-insensitively) gives "Transom can't exclude itself."; a missing or invalid ID gives "{App} has no bundle ID, so it can't be excluded."
- **Wiring**: `.exclusions` in `settingsTabs()` at a fixed 560 pt height. `displayName(of:)` was made internal so the tab shares the menu's name lookup.

## Verification

- `.build/09-08-t1.log`: 23 tests in 2 suites passed (`SettingsModelTests`, `ExclusionStoreTests`).
- `.build/09-08-t2.log`: 17 tests passed, including `addingTransomItselfIsRefused`, `anAppWithNoBundleIDIsRefused` and `anAppIsAddedOnce`.
- `.build/09-08-full.log`: four passing "Test run with" lines (271 / 508 / 124 / 1303), and `scripts/check-no-appkit.sh` printed `no-appkit: OK (65 files)`.
- Acceptance greps: `.exclusions:` 1, `exclusions.remove` 1, `NSOpenPanel` 1, `can't exclude itself` 1.
- The tracer gate re-ran Task 1's automated verify, which passed, so expansion went ahead.

## TDD Gate Compliance (Task 2)

- RED: `b846810`, test commit; the build failed with "type 'ExclusionsTab' has no member 'decide'".
- GREEN: `11be14e`, with all three named tests passing.
- REFACTOR: none needed.

## Commits

- `317b514` feat(09-08): Exclusions tab lists excluded apps and removes them
- `b846810` test(09-08): failing tests for adding exclusions from Settings
- `11be14e` feat(09-08): + adds excluded apps from an Open panel

## Deviations from Plan

1. **[Rule 1 - Test fix] Task 1 sort expectation.** The first version of `exclusionRowsSortByNameAndShowUninstalledAppsByBundleID` expected the uninstalled app last. `sortedEntries` titles an uninstalled app by its bundle ID and sorts it by that title, which the menu also does, so the test was corrected to match the menu.
2. **Signatures.** `rows` takes the `ExclusionStore` instead of `bundleIDs:` so it reuses `sortedEntries`. `decide` is not `nonisolated` because `ExclusionStore.isValid` is MainActor-isolated. `exclude(_:own:in:)` was added so the panel's add-and-refuse logic is testable without showing a panel.

## Not verified

- The panel and list rendering were not exercised on screen; the plan forbids showing an `NSOpenPanel` from a host test. Visual UAT belongs in the VM at phase end.
- `swift format lint --strict` flags these files, as it does every existing file. The repo has no `.swift-format` config and CI does not run the lint.

## Threat Flags

None. Bundle IDs go through `ExclusionStore.add` / `isValid` (T-09-12), and nothing new is logged (T-09-13).

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Settings/ExclusionsTab.swift
- FOUND: 317b514, b846810, 11be14e (ancestors of HEAD)
