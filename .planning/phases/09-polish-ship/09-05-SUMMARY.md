---
phase: 09-polish-ship
plan: 05
subsystem: settings
status: complete
tags: [settings, swiftui, zoom, gestures]
requires: [09-01, 09-04]
provides:
  - "Settings ▸ Zoom & Gestures tab (Zoom and Mouse sections)"
  - "ZoomGesturesTab.zoomBinding / mouseFooter static helpers"
affects: [StatusItemController.settingsTabs, ShortcutsView]
tech-stack:
  added: []
  patterns:
    - "Show the stored key via @AppStorage, write only through the menu's closure (zoomBinding)"
key-files:
  created:
    - Sources/TransomMac/Settings/ZoomGesturesTab.swift
  modified:
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Settings/ShortcutsTab.swift
    - Tests/TransomMacTests/SettingsModelTests.swift
decisions:
  - "The Zoom & Gestures tab is hosted with no fixed height; it has two short sections today (09-06/09-07 add more)"
metrics:
  duration: "~15 min"
  completed: 2026-11-07
actuals:
  tokens: 1700
  tasks: 2
  commits: 2
plan_head_before: 4d709d39f32c1120c68adbaaf2babc2d4943026e
plan_head_after: 1feb0d14cf802df5572dd0c304dad26eea753a96
---

# Phase 9 Plan 05: Settings Zoom & Gestures Tab Summary

Settings ▸ Zoom & Gestures now has "Use zoom", which goes through `ArrangeController.setZoomEnabled`, the same call the menu's Turn On/Off Zoom makes. The title-bar double-click toggle moved here from the Shortcuts tab into a Mouse section, and that section is disabled while zoom is off.

## Tasks

| Task | Name | Commit |
|------|------|--------|
| 1 | Tracer: "Use zoom" runs the menu's Turn On/Off Zoom path | 2cd373c |
| 2 | Double-click toggle moves from Shortcuts to Zoom & Gestures ▸ Mouse | 1feb0d1 |

## What changed

- **ZoomGesturesTab:** The toggle reads the stored `zoomEnabled` through `@AppStorage`, which defaults to true. Writes go through `zoomBinding(isOn:setZoomEnabled:)` to the closure, so the view never writes the key itself (T-09-08). The Mouse section is bound to `@AppStorage(ShortcutsModel.doubleClickKey)` and disabled while zoom is off. Its footer comes from `mouseFooter(zoomOn:)`.
- **StatusItemController.settingsTabs():** `.zoom` is wired to `Task { await self.arrange.setZoomEnabled(on) }` and has an explicit `(Bool) -> Void` type for Swift 6.3.
- **SettingsCopy:** new strings "Zoom", "Use zoom" and the UI-SPEC footer.
- **ShortcutsView:** the Mouse section and its two `@AppStorage` properties are removed. The Recorder sections, their footers and Restore Defaults are unchanged.

## Verification

- `.build/09-05-t1.log`: 8 tests passed (SettingsModelTests), including `theZoomToggleCallsTheMenuPathAndWritesNoKeyItself`.
- `.build/09-05-t2.log`: 18 tests passed (SettingsModelTests and ShortcutsModelTests), including `theMouseFooterFollowsZoom`.
- `.build/09-05-full.log`: four "Test run with" lines passed (271, 494, 124 and 1303 tests), with no ✘. `scripts/check-no-appkit.sh` printed `no-appkit: OK (65 files)`.
- Acceptance greps: `setZoomEnabled` appears 5 times in ZoomGesturesTab, `.zoom:` once in StatusItemController, `Toggle(` 0 times in ShortcutsTab and `doubleClickToggle` once in ZoomGesturesTab.
- Tracer gate: the run used the default end-of-phase mode and the verify step is automated only. The verify re-ran green, so no checkpoint was needed.

## Deviations from Plan

None. The plan was executed as written.

## Known Stubs

None. The Trackpad section (09-06) and the Mission Control section (09-07) are planned for later and are not stubs.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Settings/ZoomGesturesTab.swift
- FOUND: 2cd373c, 1feb0d1 (both ancestors of HEAD)
