---
phase: 03-tiling-mvp
plan: 02
subsystem: layout-model
status: complete
tags: [swift, paneModel, layout-tree, edits, neighbours, snap, tdd]

requires:
  - phase: 03-tiling-mvp
    provides: "Desktop tile (NodeID.desktop), Resolution.desktopRect (03-01)"
provides:
  - "LayoutTree.swap(_:_:), balance(split:), flip(split:), rotate(split:)"
  - "LayoutTree.resizeChild(in:index:by:), resizeBetween(in:_:_:by:); resizeBoundary now delegates to resizeBetween"
  - "LayoutError.atSizeLimit(NodeID)"
  - "Neighbours.neighbour(of:excluding:toward:tree:resolution:gap:recency:), Neighbours.boundary(for:edge:in:), TreeBoundary"
  - "SnapTarget (13 cases), Snap.frame(_:window:desktop:gap:)"
affects: [03-08, 03-10, 03-11, 03-12, arranger, commands]

actuals:
  tokens: 7900
  tasks: 3
  commits: 6
plan_head_before: ea9195422a19e2b0211f12c54b7c8229ff63460f
plan_head_after: 0a7ffa09f86a4b3b17c31b0ce68231e7a6b78549

tech-stack:
  added: []
  patterns:
    - "One-node edits go through a private commit(_:_:) helper: copy, set the node, normalize, validate, then self = next"
    - "clamped(_:total:) water-fills to any total, shared by normalize and resizeChild"

key-files:
  created:
    - Sources/PaneModel/Neighbours.swift
    - Sources/PaneModel/Snap.swift
    - Tests/PaneModelTests/LayoutEditTests.swift
    - Tests/PaneModelTests/NeighbourTests.swift
    - Tests/PaneModelTests/SnapTests.swift
  modified:
    - Sources/PaneModel/TreeEdits.swift
    - Sources/PaneModel/LayoutTree.swift

key-decisions:
  - "rotate on a nested split flips every axis from the root split, so no split merges and Rotate is its own inverse (D-32)"
  - "swap moves only the windows between two panel leaves; NodeIDs and weights stay, states follow by identity; a tab-group member throws notALeaf"
  - "resizeBoundary now calls resizeBetween(index, index + 1), and so validates (throws) in every build instead of assertValid"
  - "Snap.frame insets the Desktop rect the same way resolve insets the area (min edges rounded up, max down, gap rounded)"

patterns-established:
  - "Neighbour tie-break tuple: (edge distance, index in recency or Int.max, NodeID)"

requirements-completed: [TILE-11, TILE-12, TILE-13, TILE-14, TILE-05]

duration: 6min
completed: 2026-10-25
---

# Phase 3 Plan 02: Layout edits, neighbours and snap targets Summary

**Swap, balance, flip, rotate (self-inverse from the root), proportional grow/shrink and a two-child resize as one-undo-step tree edits, plus pure neighbour/boundary lookups and the 13 Desktop-tile snap frames.**

## Performance

- **Duration:** about 6 min
- **Started:** 2026-10-26T01:52:24Z
- **Tasks:** 3
- **Files:** 5 created, 2 modified

## Accomplishments

- `swap`, `balance`, `flip`, `rotate` in TreeEdits.swift, each copy-then-commit, so one `World.edit` is one undo step (tested through World with history depth 1 and undo).
- `resizeChild` takes from or gives to siblings in proportion, each clamped at `minWeight`, and throws `atSizeLimit` when nothing moves; `resizeBetween` touches only the two named children (Pitfall 9).
- `Neighbours.neighbour` (Desktop tile included, recency then NodeID tie-break) and `Neighbours.boundary` (nil on an outer edge).
- `Snap.frame` for all 13 `SnapTarget`s, whole points, inside the Desktop rect for gaps 0, 3.5, 8 and 20.

## Task Commits

1. **Task 1 (tracer): swap, balance, flip, rotate**: `e93d29e` (test, RED), `4fe01f9` (feat, GREEN)
2. **Task 2: resizeChild, resizeBetween, Neighbours**: `4312fd5` (test, RED), `168fc2b` (feat, GREEN)
3. **Task 3: snap targets**: `7852f7a` (test, RED), `0a7ffa0` (feat, GREEN)

## TDD Gate Compliance

Each task has a `test(...)` commit that failed to compile against HEAD (missing symbols: `swap`/`balance`/`flip`/`rotate`; `Neighbours`/`TreeBoundary`; `Snap`/`SnapTarget`), followed by a `feat(...)` commit that makes the suite pass. No refactor commits were needed.

## Verification

- `swift test --filter LayoutEditTests`: 9 tests ran, passed (6 after task 1).
- `swift test --filter "LayoutEditTests|NeighbourTests"`: 13 tests in 2 suites ran, passed.
- `swift test --filter SnapTests`: 4 tests ran (two parameterised over all 13 targets), passed.
- `swift test --filter PaneModelTests`: 176 tests in 18 suites, passed.
- `scripts/check-no-appkit.sh`: OK (27 files).
- Tracer gate after task 1: verify re-run end-to-end, passed, then expanded.

## Deviations from Plan

**1. [Rule 1 - Consistency] resizeBoundary delegates to resizeBetween**
- **Found during:** Task 2
- **Issue:** resizeBetween is resizeBoundary generalised to any two indices; keeping both bodies would duplicate the clamp logic.
- **Fix:** resizeBoundary(after: i) is now `resizeBetween(i, i + 1)`. Same errors in the same order; it now throws on an invalid result in release builds instead of only asserting in debug. All existing resizeBoundary tests still pass.
- **Files modified:** Sources/PaneModel/TreeEdits.swift
- **Commit:** 168fc2b

No other deviations.

## Known Stubs

None.

## Threat Flags

None. T-03-03 (weights clamped at minWeight and validated) and T-03-04 (rotate walks iteratively with an explicit stack) are implemented as planned.

## Notes for later plans

- `Neighbours.boundary` ignores whether the sibling across the boundary is placed (absent window, hidden Desktop); the Arranger should check `resolution.nodeRects` before offering a drag.
- `Snap.frame` on a Desktop narrower than two gaps returns an empty rect at the inset origin (marked `shortcut:` in Snap.swift).

## Self-Check: PASSED

All 5 created files exist; commits e93d29e, 4fe01f9, 4312fd5, 168fc2b, 7852f7a, 0a7ffa0 are ancestors of HEAD.
