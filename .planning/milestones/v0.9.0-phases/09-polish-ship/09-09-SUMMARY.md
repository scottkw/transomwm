---
phase: 09-polish-ship
plan: 09
subsystem: settings
status: complete
tags: [settings, appearance, highlight, ship-01]
requires: [09-08]
provides:
  - "HighlightColor: the one highlight resolver (appearance.highlight \"#RRGGBB\" override, else NSColor.controlAccentColor), parse/hex/override/current/set, didChange notification"
  - "Settings ▸ General tab (GeneralTab) with the Appearance section: Match system accent color / Custom + colour well"
  - "SettingsCopy: appearanceSection, highlightColor, matchSystemAccent, customHighlight, customHighlightWell, highlightFooter"
affects: [StatusItemController.settingsTabs, PreviewPanel.color(_:), StagePanel.buildMark, CollapsedBlockView.updateLayer, CollapsedPanels observers, HandleView.updateLayer, GapHandlePanels observers]
tech-stack:
  added: []
  patterns:
    - "Validated UserDefaults string preference (GapPreference rule): invalid value logged without the value and removed"
    - "Overlay owners redraw shown panels on a list of notifications (system colours + HighlightColor.didChange)"
key-files:
  created:
    - Sources/TransomMac/HighlightColor.swift
    - Sources/TransomMac/Settings/GeneralTab.swift
    - Tests/TransomMacTests/HighlightColorTests.swift
  modified:
    - Sources/TransomMac/Settings/SettingsCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Overlay/PreviewPanel.swift
    - Sources/TransomMac/Zoom/StagePanel.swift
    - Sources/TransomMac/Zoom/CollapsedPanels.swift
    - Sources/TransomMac/Overlay/GapHandlePanels.swift
decisions:
  - "Choosing Custom stores the seed (current override, else the system accent at that moment) at once, so reopening Settings still shows Custom"
  - "Live redraw observers live on the panel owners (CollapsedPanels, GapHandlePanels), next to their existing systemColorsDidChange observers, rather than on each view; same effect, no per-view deinit"
  - "everyAccentSiteGoesThroughTheResolver test not added: it can't be expressed without reading source files, so the controlAccentColor grep is the invariant check"
metrics:
  duration: "~12 min"
  completed: 2026-11-07
actuals:
  tokens: 3800
  tasks: 2
  commits: 2
plan_head_before: 3e3002096a0d6103ced87dc23d11e52f6b6e56d9
plan_head_after: 962f5d587aca6d7149946c18b99dc5f7a9a77d7e
---

# Phase 9 Plan 09: Highlight Color Summary

The highlight colour now follows the macOS accent by default, with one custom override in Settings ▸ General ▸ Appearance (D-03). A single resolver, `HighlightColor.current`, replaces the four places that read `controlAccentColor` directly. Overlays already on screen redraw as soon as the setting changes.

## What was built

- **HighlightColor** (`Sources/TransomMac/HighlightColor.swift`, `@MainActor enum`): `key = "appearance.highlight"`.
  - `parse` accepts exactly "#RRGGBB", hex digits in either case.
  - `hex` writes sRGB, rounded and uppercase.
  - `override(in:)` returns the stored colour. A non-string value, or a string that doesn't parse, is logged under `preferences` (without the value) and removed.
  - `current(in:)` and `current` return the override or the system accent.
  - `set(_:in:)` stores or removes the value and posts `HighlightColor.didChange`.
- **GeneralTab** (`Sources/TransomMac/Settings/GeneralTab.swift`): an Appearance section with a `.radioGroup` picker ("Match system accent color" / "Custom") and, beside it, a `ColorPicker` without opacity. The picker is enabled only while Custom is chosen. The section footer reads "Used for docking previews, rings and gap handles." It is wired into `StatusItemController.settingsTabs()` as `.general`.
- **Accent sites**: `PreviewPanel.color(.accent)` (every drop and result preview), the `StagePanel.buildMark` ring (overview selection and pick rings), the hover ring in `CollapsedBlockView.updateLayer` and the fill in `HandleView.updateLayer` all read `HighlightColor.current`. Their Increase Contrast alpha rules are unchanged.
- **Live redraw**: `CollapsedPanels` and `GapHandlePanels` mark their shown panels for redraw on `HighlightColor.didChange`, as they already did for `systemColorsDidChangeNotification`. Stage rings and previews are rebuilt every time they are shown, so they need no observer.

## Verification

- Task 1: `.build/09-09-t1.log` shows 22 tests in 4 suites passed, including all four named HighlightColor tests.
- Task 2: `.build/09-09-t2.log` shows 9 tests passed plus 5 tests passed. `grep -rl controlAccentColor Sources` finds only `HighlightColor.swift`.
- Full host suite: `.build/09-09-full.log` has four passed "Test run with" lines (271, 513, 124 and 1303 tests) and no ✘. `scripts/check-no-appkit.sh` printed `no-appkit: OK (65 files)`.
- Tracer gate (Task 1): re-ran the automated verify end-to-end and it passed before Task 2 began.

## Deviations from Plan

Two small deviations; nothing else differs from the plan.

- **[Rule 1 - Placement] The redraw observers sit on the panel owners, not on each view.** The plan put the observer on `CollapsedBlockView` and the gap handle view, each removed in its own `deinit`. `CollapsedPanels` and `GapHandlePanels` already redraw every shown panel on system colour changes, so `HighlightColor.didChange` was added to those same lists. The effect is the same and the acceptance grep (`HighlightColor.didChange` in `GapHandlePanels.swift`) is met. The fix is in commit 962f5d5.
- **Extra tests**: added `aNonStringStoredValueIsRemoved` and more invalid inputs (`#+12345`, `FF8000`, `#FF80001`) to the parameterised invalid-value test. These cover the T-09-14 trust boundary.

## Known Stubs

None.

## Commits

- 41eb2ac feat(09-09): custom highlight in Settings ▸ General colours drop previews
- 962f5d5 feat(09-09): rings and gap handles use the highlight and redraw on change

## Self-Check: PASSED

- All three created files exist, and commits 41eb2ac and 962f5d5 are ancestors of HEAD.
