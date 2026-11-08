---
phase: 09-polish-ship
plan: 23
subsystem: zoom
status: complete
tags: [collapsed-block, label, ui-spec-surface-7, d-16]
requires: [09-09 HighlightColor, 09-22]
provides:
  - CollapsedBlockView label card (title + "Collapsed" / "{n} windows, collapsed")
  - CollapsedBlockView.labelLines(title:appName:groupSize:), labelFit(block:icon:fullCard:lineCard:), LabelFit
  - TabCopy.collapsed, TabCopy.collapsedWindows(_:)
affects: [Sources/TransomMac/Zoom/CollapsedPanels.swift]
tech-stack:
  added: []
  patterns: [pure nonisolated static fit/copy functions tested headless, CATextLayer with tail truncation]
key-files:
  created:
    - Tests/TransomMacTests/CollapsedLabelTests.swift
  modified:
    - Sources/TransomMac/Zoom/CollapsedPanels.swift
    - Sources/TransomMac/Shell/TabCopy.swift
    - Tests/TransomMacTests/TabCopyTests.swift
decisions:
  - "The collapsed-label card is drawn with two CATextLayers (truncationMode .end) inside a CALayer card. TileLayer draws its capsule text as an image, but CATextLayer does tail truncation without extra code."
  - "The capped card width has a floor of 16 + 13 pt (one Body character), so the width test can still fail on a narrow block. Without the floor, capping at block width - 32 would make it always pass."
  - "The 8 pt icon-to-card gap applies only when the icon is shown, as in TileLayer.layoutFallback"
metrics:
  duration: ~15 min
  completed: 2026-11-07
estimate:
  tokens: 35000
  tasks: 2
actuals:
  tokens: 2723
  tasks: 2
  commits: 3
plan_head_before: 20144a3d2ad8feef3a4768bff27e5702835c9228
plan_head_after: 5302f54f23f84d68928e87536b15cebb27cdb4b1
---

# Phase 9 Plan 23: Collapsed-block label card Summary

A collapsed block at rest now shows a label card under its app icon. The card holds the window title (or the app name, truncated to 32 graphemes) and "Collapsed", or "{n} windows, collapsed" for a tab group. On smaller blocks it drops to a one-line capsule and then to the icon alone. With Increase Contrast the card border is `labelColor` (D-16, UI-SPEC Surface 7).

## What was built

- **TabCopy**: `collapsed = "Collapsed"` and `collapsedWindows(_:)`, which returns "{n} windows, collapsed".
- **CollapsedBlockView**:
  - `labelLines`: line 1 is the title, or `MenuCopy.truncatedAppName(appName)` when the title is empty. Line 2 is the collapsed copy.
  - `labelFit`: returns `.full`, `.lineOne` or `.iconOnly`. A card fits when the block is at least card width + 32 wide and at least icon + 8 + card height + 32 high. Both tests are inclusive.
  - `layoutCard(iconSide:contrast:)` is called from `updateLayer()`. It centres the icon and the card as one group. The card has a `windowBackgroundColor` fill and a 1 pt border (`separatorColor`, or `labelColor` with Increase Contrast). Its radius is 8, or height / 2 for the one-line capsule. Line 1 is Body in `labelColor` and line 2 is subheadline (11 pt) in `secondaryLabelColor`, both tail-truncated. The card width is the wider line + 16, capped at block width − 32.
- These are unchanged: the app-colour fill, the block radius, the 1 pt border, the hover ring, the pointing hand, double-click, help, the accessibility label, and the stage's drawing of blocks during a camera move.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | Tracer: a roomy collapsed block shows its title and "Collapsed" | 8cc5f21 |
| 2 | Fallbacks to line one, then icon only; Increase Contrast border (TDD) | e7086c9 (RED), 5302f54 (GREEN) |

## Verification

- `.build/09-23-t1.log`: the 4 CollapsedLabelTests passed.
- `.build/09-23-t2.log`: CollapsedLabelTests, TabCopyTests and TileLayerTests passed (19 tests, 5 suites).
- `.build/09-23-full.log`: four passed "Test run with" lines (271, 602, 124, 1331 tests) and no ✘. `scripts/check-no-appkit.sh` printed no-appkit: OK (69 files).
- Tracer gate: Task 1's automated verify passed, so execution continued to Task 2.

## TDD Gate Compliance

- RED (e7086c9): `aShortBlockShowsLineOneOnly` and `theThresholdIsInclusive` failed with 3 issues, because `labelFit` returned only `.full` or `.iconOnly`.
- GREEN (5302f54): `labelFit` falls back to `fits(lineCard)`, and all tests pass.
- REFACTOR: none needed.

## Deviations from Plan

**1. [Rule 1 - Bug] `LabelFit` marked `nonisolated`**
- **Found during:** Task 1. Under the module's MainActor default isolation, its `Equatable` conformance could not be used from the nonisolated test.
- **Fix:** `nonisolated enum LabelFit`.
- **Commit:** 8cc5f21

**2. Task ordering**
- The view's one-line capsule path (line 2 hidden, radius height / 2) and the Increase Contrast border went in with Task 1's card layout. Task 2's code change was only the `labelFit` fallback, which the tests exercise. Behaviour matches the plan.

## Known Stubs

None.

## Deferred

- The must-have truth with `verification: backstop` still needs checking at real block sizes in a VM: a quarter-width Safari block, a thin strip, and a group. The end-of-phase host check (UI-SPEC host checklist item 5) also needs a visual look. Neither was run here, per the host-only rules.

## Self-Check: PASSED

- FOUND: Tests/TransomMacTests/CollapsedLabelTests.swift
- FOUND: 8cc5f21, e7086c9, 5302f54 (ancestors of HEAD)
