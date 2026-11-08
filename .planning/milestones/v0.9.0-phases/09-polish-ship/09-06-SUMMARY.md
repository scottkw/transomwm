---
phase: 09-polish-ship
plan: 06
subsystem: settings
status: complete
tags: [settings, gestures, trackpad, gesture-tap]
requires: [09-05]
provides:
  - "GesturePreference (gestures.option, gestures.wallpaper; Bool, default on)"
  - "GestureTapState.takesOptionGestures / takesWallpaperGestures and the gating in GestureTapRules.decide"
  - "GestureTapRules.PassReason.turnedOff"
  - "ArrangeController.wantsGestureTap(zoomEnabled:tapRunning:option:wallpaper:)"
  - "Settings ▸ Zoom & Gestures ▸ Trackpad section"
affects: [GestureController.publish, ArrangeController.updateGestureTap, StatusItemController.settingsTabs, transom-gesture-spike]
tech-stack:
  added: []
  patterns:
    - "Settings switches reach the tap only through the published GestureTapState, never read in the callback"
key-files:
  created:
    - Sources/TransomMac/GesturePreference.swift
  modified:
    - Sources/TransomMac/Input/GestureTapRules.swift
    - Sources/TransomMac/Zoom/GestureController.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Settings/ZoomGesturesTab.swift
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/transom-gesture-spike/main.swift
    - Tests/TransomMacTests/GestureTapRulesTests.swift
    - Tests/TransomMacTests/SettingsModelTests.swift
decisions:
  - "The Trackpad section has one footer: the ⌥ row's text with zoom on, ZoomCopy.doubleClickFooterZoomOff with zoom off (the wallpaper row has no footer in the UI-SPEC)"
  - "An ⌥ gesture over a window with the ⌥ switch off passes as windowUnderPointer, as the plan says; over bare wallpaper it is taken as a wallpaper gesture"
metrics:
  duration: "~20 min"
  completed: 2026-11-07
actuals:
  tokens: 5000
  tasks: 2
  commits: 3
plan_head_before: 6e10bebe1e8e608abcbfc7ac7e8601a8203a37fc
plan_head_after: a010b183fe88796a79f450a2fbf3b2f517ad194c
---

# Phase 9 Plan 06: Trackpad Gesture Switches Summary

Settings ▸ Zoom & Gestures has a new Trackpad section with two switches, both on by default (today's behaviour). "Pinch and pan with ⌥ held" is stored as `gestures.option` and "Pinch and pan on the wallpaper without ⌥" as `gestures.wallpaper`. The switches reach the gesture tap and the multitouch pinch path through the `GestureTapState` that `GestureController.publish()` already sends. With both off the gesture tap is not started.

## What was built

- `GesturePreference` (`@MainActor @Observable`, built like `GapPreference`). It reads each key as a Bool and treats a missing key as on. A stored value that is not a Bool is logged and removed (T-09-10). `setOption` and `setWallpaper` write the key and call `onChange`.
- `GestureTapState` has two new fields, `takesOptionGestures` and `takesWallpaperGestures`, both defaulting to true. `decide` takes an ⌥ gesture only while the ⌥ switch is on. With it off, an ⌥ gesture over bare wallpaper is still taken as a wallpaper gesture. A bare wallpaper gesture with the wallpaper switch off passes with the new `PassReason.turnedOff`.
- `ArrangeController` owns the one `GesturePreference`. When a switch changes, it republishes the tap state and calls `updateGestureTap(reason: "settings")`. That function now starts the tap only when `wantsGestureTap` is true: zoom on, mouse tap running and at least one switch on.
- `ZoomGesturesTab` has a Trackpad section with the two toggles bound through the preference. The toggles are disabled while zoom is off, and the footer then reads "Turn on zoom to use this."

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Tracer: switches reach the tap through the published state | 8b14539 |
| 2 (RED) | Failing tests for the toggles and the tap start rule | e2f23c8 |
| 2 (GREEN) | Trackpad toggles in Settings, no gesture tap with both off | a010b18 |

## Verification

- `.build/09-06-t1.log`: `GestureTapRulesTests|GestureControllerTests`, 33 tests passed, including the four named switch tests. Tracer gate: verify was re-run end to end and passed before Task 2.
- `.build/09-06-t2.log`: `SettingsModelTests`, 12 tests passed, including `bothTrackpadSwitchesOffMeansNoGestureTap` and `theOptionToggleWritesItsKeyAndFiresOnce`.
- `.build/09-06-full.log`: four passed "Test run with" lines (271, 501, 124 and 1303 tests), no ✘. `scripts/check-no-appkit.sh` printed no-appkit: OK (65 files).

## TDD Gate Compliance

- RED: e2f23c8 `test(09-06)`. The build failed with "type 'ArrangeController' has no member 'wantsGestureTap'".
- GREEN: a010b18 `feat(09-06)`. The tests pass.
- REFACTOR: none needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The spike's exhaustive switch over PassReason**
- **Found during:** Task 1
- **Issue:** `Sources/transom-gesture-spike/main.swift` `passText` switches over every `PassReason`, so adding `.turnedOff` would break the build.
- **Fix:** Added `case .turnedOff: "turned off in Settings"`.
- **Commit:** 8b14539

**2. [Rule 2 - Missing check] A test for the non-Bool stored value**
- Added `aStoredGestureSwitchThatIsNotABoolIsRemoved` to `SettingsModelTests`. It covers the T-09-10 mitigation.
- **Commit:** e2f23c8

## Known Stubs

None.

## Notes

- An ⌥ gesture over a window with the ⌥ switch off is logged at debug level as "passed … with ⌥: ⌥ pressed mid-gesture". This is because `optionPassText` maps `windowUnderPointer` to that text. Only the debug log is affected; behaviour is correct.
- None of this was checked on real hardware or in the VM. The plan allows host-only checks.

## Self-Check: PASSED
