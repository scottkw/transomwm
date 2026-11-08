---
phase: 09-polish-ship
plan: 01
subsystem: settings
status: complete
tags: [settings, appkit, nstabviewcontroller, shortcuts, menu]
requires: []
provides:
  - "SettingsPane (Engine): the seven panes in toolbar order"
  - "SettingsWindowController: one toolbar-tab Settings window, show(_:from:), settings.lastPane"
  - "StatusItemController.showSettings(_:from:) and settingsTabs(), the table later plans extend"
  - "SettingsCopy: menu item, tab labels, tab symbols"
affects: [09-02, 09-04, 09-05, 09-08, 09-09, 09-11, 09-18]
tech-stack:
  added: []
  patterns:
    - "Settings tab = SettingsWindowController.hosting(view, height:) entry in StatusItemController.settingsTabs()"
key-files:
  created:
    - Sources/TransomEngine/SettingsPane.swift
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Settings/SettingsWindowController.swift
    - Tests/TransomMacTests/SettingsWindowTests.swift
  modified:
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Settings/ShortcutsTab.swift (moved from Zoom/ShortcutsWindowController.swift)
    - Sources/TransomMac/Shell/ZoomCopy.swift
    - Tests/TransomMacTests/ZoomCopyTests.swift
decisions:
  - "The stored-pane write is armed only after all tabs are added (panes set last), so adding the first tab never overwrites settings.lastPane"
  - "select() calls selectionChanged() explicitly, since NSTabView does not fire didSelect when the tab is already selected"
  - "Each tab's view controller title is the tab label, so NSTabViewController's own title propagation agrees with the explicit window title"
metrics:
  duration: ~15 min
  completed: 2026-11-07
actuals:
  tokens: 4100
  tasks: 2
  commits: 2
plan_head_before: 6122c149a5536e59a556421909905b487bc6ec27
plan_head_after: bc32f4e9ba990131f61c8972d2d4cc26d29912f6
---

# Phase 9 Plan 01: Settings Window Shell Summary

One AppKit Settings window (KeyClosableWindow + NSTabViewController in `.toolbar` style) opened by "Settings…" (⌘,) from the status menu, remembering its last tab in `settings.lastPane`; the old Shortcuts window is now its Shortcuts tab at 560 × 560.

## Tasks

| # | Task | Commit |
|---|------|--------|
| 1 | Tracer: Settings… (⌘,) opens one toolbar-tab Settings window on its Shortcuts tab | 7ff62ea |
| 2 | Shortcuts lives only in Settings: window class and "Shortcuts…" string removed | bc32f4e |

## Verification

- `SettingsWindowTests` 4/4 passed (`.build/09-01-t1.log`); tracer gate re-run passed.
- `SettingsWindowTests|ZoomCopyTests|ShortcutsModelTests`: 23 tests passed (`.build/09-01-t2.log`).
- Full host suite: four passed "Test run with" lines (271, 483, 124, 1292), no ✘; `scripts/check-no-appkit.sh` OK (`.build/09-01-full.log`).
- Acceptance greps: `tabStyle = .toolbar` 1; `SettingsCopy.menuItem` in StatusItemController 1; `ZoomCopy.shortcutsItem` 0; no `class ShortcutsWindowController`; `shortcutsItem` in ZoomCopy 0.

## Deviations from Plan

None - plan executed as written. (Task 2's first commit attempt named the already-renamed old path and git refused it; re-run without it. No content change.)

## Not verified here

- The must-have marked `verification: backstop` (the `.toolbar` look and title-follows-tab on macOS 15 and 27) and the window height animating per tab were not checked on screen: host tests never show windows. Needs the phase UAT in the VM.

## Known Stubs

None. Only the Shortcuts tab exists by design; later plans add the other six entries to `settingsTabs()`.

## Self-Check: PASSED

- All four created files and the moved ShortcutsTab.swift exist; commits 7ff62ea and bc32f4e are ancestors of HEAD.
