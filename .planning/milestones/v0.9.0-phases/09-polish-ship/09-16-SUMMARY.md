---
phase: 09-polish-ship
plan: 16
subsystem: app-bundle
status: complete
tags: [app-icon, asset-catalog, menu-bar, xcodegen]
requires: [09-15]
provides:
  - xcode/Assets.xcassets with AppIcon, TransomTemplate and TransomZoomedTemplate
  - CFBundleIconName AppIcon in the built app (ASSETCATALOG_COMPILER_APPICON_NAME)
  - StatusItemController.glyphName(ready:paused:zoomed:) and the template glyph swap in updateGlyph()
affects: [09-17]
tech-stack:
  added: []
  patterns:
    - asset catalog lives in xcode/ and is a Transom-target source; swift run has no catalog and falls back to SF Symbols
key-files:
  created:
    - xcode/Assets.xcassets/Contents.json
    - xcode/Assets.xcassets/AppIcon.appiconset/ (Contents.json + 10 PNGs)
    - xcode/Assets.xcassets/TransomTemplate.imageset/ (Contents.json + SVG)
    - xcode/Assets.xcassets/TransomZoomedTemplate.imageset/ (Contents.json + SVG)
    - Tests/TransomMacTests/StatusGlyphTests.swift
  modified:
    - xcode/project.yml
    - Sources/TransomMac/Shell/StatusItemController.swift
decisions:
  - "updateGlyph copies the NSImage(named:) result before setting size and accessibilityDescription, because NSImage(named:) returns one shared instance and paused/normal share TransomTemplate with different descriptions"
  - "ASSETCATALOG_COMPILER_APPICON_NAME sits in the Transom target's base settings, so Debug and Release both get the icon"
metrics:
  duration: ~15 min
  completed: 2026-11-07
actuals:
  tokens: 6400
  tasks: 2
  commits: 3
plan_head_before: daaf140cbc69434f7fbb7c762bd90ce230cb9005
plan_head_after: 05485deb8b9f268e65dd782691ff37dded4e7adb
---

# Phase 9 Plan 16: App icon and menu-bar glyphs Summary

The signed Release `Transom.app` now has the Transom app icon from an asset catalog (`CFBundleIconName` AppIcon, `Assets.car` with AppIcon). The menu bar shows the `TransomTemplate` glyph, or `TransomZoomedTemplate` while zoomed in. Both are 18 × 18 pt template images, all copied byte for byte from `design-template/icons`. Not ready keeps `exclamationmark.triangle`. Under `swift run` there is no catalog, so the glyph falls back to `rectangle.split.2x1`.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Tracer: Release app built with the Transom icon | 96002f7 | xcode/Assets.xcassets/Contents.json, xcode/Assets.xcassets/AppIcon.appiconset/*, xcode/project.yml |
| 2 (RED) | Failing StatusGlyphTests | 20095c3 | Tests/TransomMacTests/StatusGlyphTests.swift |
| 2 (GREEN) | Template glyphs, zoomed variant when zoomed in | 05485de | xcode/Assets.xcassets/Transom*Template.imageset/*, Sources/TransomMac/Shell/StatusItemController.swift |

## Verification

- Task 1 (`.build/09-16-t1.log`): `scripts/release.sh --build-only` succeeded. `CFBundleIconName` is AppIcon, `Assets.car` exists, and `assetutil` lists AppIcon. The tracer gate re-ran this verify, and it passed.
- Task 2 (`.build/09-16-t2.log`): `StatusGlyphTests` ran 3 tests in 1 suite, and all passed. The rebuilt Release catalog lists both TransomTemplate and TransomZoomedTemplate, with "Template Mode": "template".
- Full host gate (`.build/09-16-full.log`): four passed "Test run with" lines (271, 547, 124 and 1317 tests). No ✘ or crash lines. `scripts/check-no-appkit.sh` printed `no-appkit: OK (68 files)`.
- Acceptance: the appiconset has 10 PNGs, the `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` count is 1, `TransomZoomedTemplate` appears once in StatusItemController, and `TransomTemplate.svg` exists.

## TDD Gate Compliance

- RED: 20095c3. The new test failed to compile because `StatusItemController` has no member `glyphName`.
- GREEN: 05485de. The tests passed.
- REFACTOR: none needed.

## Deviations from Plan

None. The plan was executed as written. One addition inside the plan's scope: `updateGlyph` copies the named image before mutating it (see decisions).

## Pending human check (end of phase)

On the host, check the Transom glyph on light, dark and tinted menu bars and on the 1x DELL display. It should be crisp and not clipped (quick 261106-bru's rule). This was not checked here: the user's running Transom Debug app was left untouched.

## Self-Check: PASSED

- All created files exist, and the AppIcon and imagesets match `design-template` (`diff -r` shows no differences).
- Commits 96002f7, 20095c3 and 05485de are on HEAD.
