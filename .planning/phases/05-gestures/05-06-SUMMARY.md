---
phase: 05-gestures
plan: 06
subsystem: shell
status: complete
tags: [gestures, debug-menu, copy]
requires:
  - "05-03: GestureController counters taken / timeouts; ArrangeController.isGestureTapRunning, gestureTapFailedToStart"
  - "05-04/05-05: GestureController.LastGesture (kind, direction, outcome)"
provides:
  - "GestureCopy (AppKit-free): G1 gesturesLine(Source), G2 takenLine(taken:timeouts:), G3 lastGestureLine(kind:direction:outcome:) / lastGestureNone, kindLabel, refusalText"
  - "StatusItemController Debug submenu: G1-G3 directly after 'Snapshot cache: …', rebuilt when the menu opens"
affects: [05-07, 05-08]
tech-stack:
  added: []
  patterns:
    - "Copy types take a local outcome enum so they stay independent of main-actor controllers; the menu maps the controller's enum"
key-files:
  created:
    - Sources/TransomMac/Shell/GestureCopy.swift
    - Tests/TransomMacTests/GestureCopyTests.swift
  modified:
    - Sources/TransomMac/Shell/StatusItemController.swift
key-decisions:
  - "pan-only value not shipped: spike item 3 = no pinch lines (pinch setting off) / E-01 = tap+multitouch (05-SPIKE.md 'User decision (E-01)'). Multitouch supplies pinch, so G1 never shows 'pan only'; Task 2 made no code change"
  - "A gesture with no direction (never left the dead zone or locked an axis, outcome too small) is named by its kind: 'Last gesture: pinch, too small' / 'pan, too small'"
requirements-completed: [GEST-04]
metrics:
  duration: "~15 min"
  completed: 2026-10-29
commits: 1
plan_head_before: d092bf9c843eef0c4b9afc4d48cf8827a248786e
plan_head_after: d4563486d68293ea9b406149c7e9dcc76e8b33e7
actuals:
  tokens: 2000
  tasks: 2
  commits: 1
---

# Phase 5 Plan 06: Gesture Debug Lines Summary

The status menu's Debug submenu now shows "Gestures: …", "Gestures taken: …" and "Last gesture: …" after the snapshot cache line. The values come from live ArrangeController and GestureController state, and the strings live in AppKit-free GestureCopy with every value unit-tested.

## What was built

- **GestureCopy.swift** (new, imports TransomEngine and TransomModel only):
  - G1: `Source { on, offZoom, offTapNotRunning, unavailable }`.
  - G2: "none yet", "{n}", or "{n}, {t} ended by timeout".
  - G3: "{kind}, moved / sprang back / {refusal} / too small". `{kind}` is the direction the view moved (pinch in/out, pan left/right/up/down), and `{refusal}` is `Navigator.Refusal.announcement` with its first letter lower-cased, never retyped.
- **StatusItemController.debugMenuItem**: G1 is chosen in this order. Zoom off gives `.offZoom`, a running tap gives `.on`, a tap that failed to start gives `.unavailable`, and anything else gives `.offTapNotRunning`. G2 reads `gestures.taken`/`timeouts`. G3 maps `gestures.lastGesture`, or shows "none yet" when there is no gesture yet.
- **Empty and error states**: before any gesture, the lines read "Gestures taken: none yet" and "Last gesture: none yet". With no gesture source, G1 reads "Gestures: unavailable (no gesture source)". Hotkeys, URLs and the menu still drive zoom, since nothing else depends on the tap.

## Task 2: pan-only value not shipped

pan-only value not shipped: spike item 3 = no pinch lines / E-01 = tap+multitouch. 05-SPIKE.md "User decision (E-01)" records that, with "Zoom in or out" off, the tap saw 0 pinches, and that the user chose tap+multitouch. The UI-SPEC drops the value when multitouch ships. Task 2 made no code change: StatusItemController is unchanged after Task 1's commit, and there is no `pinchSettingOff` and no Trackpad preference read. Plan 05-07 can add its G1 "trackpad events and multitouch" value as a new `Source` case, and the G4 "Multitouch: …" line after G3.

## Verification

- `swift test --filter GestureCopyTests`: **6 tests in 1 suite passed** (the parameterized G1 and G3 tests cover 4 and 7 cases). The earlier RED run failed to build with "cannot find 'GestureCopy' in scope".
- `scripts/check-no-appkit.sh`: OK (45 files). GestureCopy has no AppKit/Cocoa/SwiftUI import.
- The acceptance greps pass. StatusItemController has 6 `GestureCopy.` references, and they come after `snapshotCacheLine`. GestureCopy contains no retyped refusal text.
- No live VM run. The plan's checks are headless only. Reading the lines over VNC is UAT item 16 (05-08).

## Deviations from Plan

**1. [Scope] Dropped `Source.onPanOnly` from Task 1.** Task 1's behavior listed it, but the UI-SPEC drops the value when multitouch ships (E-01 = tap+multitouch), so it would have been a case that is never used. `pinchOffLog` was left out for the same reason.

**2. [Rule 1 - Bug] `lastGestureLine` takes the gesture's kind as well.** `LastGesture.direction` is nil for a gesture that never left the dead zone (outcome too small). Without a fallback, G3 would have had no `{kind}`, so the kind ("pinch"/"pan") stands in. StatusItemController converts `GestureSample.Kind` to `GestureRecognizer.Kind`, so GestureCopy doesn't depend on the CoreGraphics-backed sample type.

## Deferred

- The UI-SPEC Logging "debug" line, "gesture counters: {t} taken, {p} passed with ⌥, {s} short-circuited, {o} timeouts" every 60 s (handoff from 05-03), is not implemented. It is a log line, not a Debug menu line, and neither this plan's tasks nor any other 05-0x plan list it. The counters exist on GestureController and GestureTap.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Shell/GestureCopy.swift
- FOUND: Tests/TransomMacTests/GestureCopyTests.swift
- FOUND: d456348 (ancestor of HEAD)
