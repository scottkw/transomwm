---
phase: 09-polish-ship
plan: 04
subsystem: settings
status: complete
tags: [settings, swiftui, observation, preferences, conflicts]
requires: [09-01, 09-03]
provides:
  - "Settings ▸ Arranging tab (Layout, Tab groups, macOS window features)"
  - "@Observable GapPreference, NewWindowsPreference, DragToDockPreference, ConflictController"
affects: [StatusItemController.settingsTabs]
tech-stack:
  added: []
  patterns:
    - "Settings binding = Binding(get: pref.value, set: pref.set) on the instance the menu holds; no @AppStorage for validated keys"
    - "@Observable with @ObservationIgnored on closures/helpers so only the shown state is tracked"
key-files:
  created:
    - Sources/TransomMac/Settings/ArrangingTab.swift
    - Tests/TransomMacTests/SettingsModelTests.swift
  modified:
    - Sources/TransomMac/GapPreference.swift
    - Sources/TransomMac/NewWindowsPreference.swift
    - Sources/TransomMac/DragToDockPreference.swift
    - Sources/TransomMac/ConflictController.swift
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
decisions:
  - "ConflictController takes the @Observable macro (it compiles on the NSObject subclass); the ObservableObject fallback was not needed"
  - "Arranging tab is hosted at the UI-SPEC's 640pt cap height; a grouped Form has no reliable ideal height and scrolls past that"
  - "Row names use a new sentence-case SettingsCopy.featureName; the menu and toasts keep ConflictCopy.featureName"
metrics:
  duration: "~35 min"
  completed: 2026-11-07
actuals:
  tokens: 5300
  tasks: 3
  commits: 5
plan_head_before: 513c60dcd53561d0a46740e142620c3c9d3746f9
plan_head_after: b001dcef26f1021a86c3d109796ed6580fdeed67
---

# Phase 9 Plan 04: Settings Arranging Tab Summary

Settings ▸ Arranging binds Gaps, New windows and Drag to dock to the menu's own preference objects, writing only through `set(_:)`. It also adds the Close Group question and the three macOS window features rows with Turn Off and Restore, driven by an `@Observable` ConflictController.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | Tracer: Gaps in Settings is the menu's GapPreference | fd7c466 |
| 2 | New windows, Drag to dock, Close Group question | c964282 (test, RED), 43cb548 (feat) |
| 3 | macOS window features rows and Restore | 5245c07 (test, RED), b001dce (feat) |

## What changed

- **Preferences:** `GapPreference`, `NewWindowsPreference` and `DragToDockPreference` are `@Observable`, with `onChange` and `defaults` ignored. `value` and `set(_:)` are unchanged, so `TransomMacApp`'s engine update and announcement run once for each change, whether it comes from the menu or from Settings (D-02, T-09-06).
- **ArrangingTab:** `gapBinding`, `newWindowsBinding` and `dragToDockBinding` are static so they can be tested. `footer(_:)` returns MenuCopy's tooltips verbatim. `featureRows(_:)` gives (conflict, name, detail, isOn) in `Conflict.allCases` order. The Close Group toggle uses `@AppStorage(CloseGroupConfirmation.key)` with a default of true. That is safe because the key is read lazily and has no onChange.
- **ConflictController:** `@Observable`. Only `active` and `originals` are tracked; every closure and helper var is `@ObservationIgnored`. Turn Off and Restore call the existing `turnOff` / `restore` unchanged (T-09-07).
- **StatusItemController.settingsTabs():** has a new `.arranging` entry that passes the four instances the menu reads.

## Verification

- `.build/09-04-t1.log`: 6 tests passed (SettingsModelTests and GapPreferenceTests).
- `.build/09-04-t2.log`: 15 tests passed (adds NewWindowsPreferenceTests and DragToDockPreferenceTests).
- `.build/09-04-t3.log`: 18 tests passed (SettingsModelTests and ConflictControllerTests).
- `.build/09-04-full.log`: four passing "Test run with" lines (271, 492, 124, 1303). `scripts/check-no-appkit.sh` printed `no-appkit: OK (65 files)`.
- The tracer gate ran in the default end-of-phase mode with an automated-only verify. The verify re-ran green, so there was no checkpoint.

## TDD Gate Compliance

Tasks 2 and 3 each have a RED `test(09-04)` commit (both failed to compile against the missing API: `newWindowsBinding`/`dragToDockBinding`/`footer`, and `featureRows`), followed by a GREEN `feat(09-04)` commit.

## Deviations from Plan

**1. [Rule 3 - Blocking] A counter box for `withObservationTracking`**
- **Found during:** Task 1
- **Issue:** Swift 6 rejects mutating a captured `var` inside the `@Sendable` onChange closure.
- **Fix:** Added a test-private `final class Count: @unchecked Sendable`. The change fires synchronously on the main actor.
- **Files:** Tests/TransomMacTests/SettingsModelTests.swift. **Commit:** fd7c466

**2. [Rule 2 - Missing] Arranging tab height**
- **Issue:** The plan's hosting call had no height. A grouped Form has no reliable ideal height, and the UI-SPEC caps tabs at 640pt.
- **Fix:** `hosting(..., height: 640)`. **Commit:** b001dce

## Known Limits / Not Checked

- I did not check the tab on screen: host tests never show windows. Phase UAT in the VM needs to cover row layout, radio footers, the 640pt height and the window-height animation.
- The Restore button's enabled state is computed from `canRestore`. Its `takeover` part (Mission Control takeover on, or stored originals) is not observed, so if only the takeover changes while the tab is open, the button can be stale until the tab re-renders. The menu builds fresh each time, so it is unaffected.

## Self-Check: PASSED

- All 8 key files exist; commits fd7c466, c964282, 43cb548, 5245c07 and b001dce are ancestors of HEAD.
