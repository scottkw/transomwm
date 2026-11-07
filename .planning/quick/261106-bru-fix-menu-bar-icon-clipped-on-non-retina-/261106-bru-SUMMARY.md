---
phase: quick-261106-bru
plan: 01
subsystem: TransomMac/Shell (status item)
tags: [status-item, menu-bar, sf-symbols, ui-spec]
status: complete
requires: []
provides:
  - "Status item glyph drawn at the SF Symbol default size (fits the 22 pt square item on 1x and Retina menu bars)"
affects:
  - Sources/TransomMac/Shell/StatusItemController.swift
  - .planning/phases/02-window-control/02-UI-SPEC.md
tech-stack:
  added: []
  patterns: ["SF Symbol template at default configuration for the status item"]
key-files:
  created: []
  modified:
    - Sources/TransomMac/Shell/StatusItemController.swift
    - .planning/phases/02-window-control/02-UI-SPEC.md
decisions:
  - "Status item glyph uses the SF Symbol default configuration with no explicit point size; a forced 16 pt image (23 x 18 pt) overflowed the 22 pt square item and lost its bottom edge on 1x displays"
requirements: [TILE-08, WIN-01]
metrics:
  completed: 2026-11-06
  tasks: 2
  files: 2
actuals:
  tokens: 680
  tasks: 2
  commits: 2
plan_head_before: f5dc4bde98c9848900d6d3b92a73d9af816eee8d
plan_head_after: 6d6be69bfbbe39fa37fa690bb85e91ce704f2247
---

# Quick 261106-bru Plan 01: Menu bar icon clipped on non-Retina displays Summary

The status item glyph is now an SF Symbol template at its default size (18 x 14 pt for `rectangle.split.2x1`), not a forced 16 pt configuration that produced a 23 x 18 pt image and lost its bottom edge on the 1x Dell S3425DW.

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Draw the status glyph at the default symbol size (tracer) | 2d67345 | Sources/TransomMac/Shell/StatusItemController.swift |
| 2 | Amend the Phase 2 UI-SPEC status-item rule | 6d6be69 | .planning/phases/02-window-control/02-UI-SPEC.md |

## What changed

- `updateGlyph()`: `let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)`. The chained `.withSymbolConfiguration(...pointSize: 16...)` call is gone. Symbol choice, `isTemplate`, `appearsDisabled`, accessibility descriptions and tooltips are unchanged. The doc comment now says why there is no explicit size.
- 02-UI-SPEC Surface 1: the status-item sentence now prescribes the default symbol configuration and records the 2026-11-06 amendment (one changed line).

## Verification

- `swift build` succeeded; `swift test --filter TransomMacTests`: "Test run with 467 tests in 65 suites passed" (matches the HEAD baseline), no failures.
- Comment-filtered `SymbolConfiguration` and `pointSize` counts in StatusItemController.swift: 0 (were 1 and 1).
- Tracer gate: verify re-run passed end to end before Task 2.
- 02-UI-SPEC: `pointSize: 16` count 0, `quick 261106-bru` count 1, numstat diff total 2.
- `scripts/check-no-appkit.sh` exits 0.
- Each commit touches only its one file; nothing under `.planning/phases/08.1.1-*` was read, edited or staged.

## Pending host UAT (user)

Run `scripts/run-debug.sh` on the host, then check: (1) on the Dell S3425DW (1x) the icon shows all four edges, including the bottom; (2) on the Retina notch display the icon still reads clearly and is not too small; (3) after Pause, the dimmed glyph is unclipped on both displays. If (2) looks too small, report it as a follow-up rather than reintroducing a fixed size.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Shell/StatusItemController.swift
- FOUND: .planning/phases/02-window-control/02-UI-SPEC.md
- FOUND: 2d67345 (ancestor of HEAD)
- FOUND: 6d6be69 (ancestor of HEAD)

## Host UAT

2026-11-06: user confirmed the icon renders whole on the Dell S3425DW (1x) after rebuilding. Pass.
