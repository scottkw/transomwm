---
phase: 03-tiling-mvp
plan: 26
subsystem: engine-persistence
status: complete
tags: [g-03-4, g-03-11, safe-06, tile-06, wanted-frame, layout-json, gap-closure, tdd]
requires: [03-25]
provides:
  - "LayoutFile.wantedFrames ([HomeFrame], sorted by identity) and wantedFrameMap; a missing key decodes as empty"
  - "ArrangerInput.restore(_, homeFrames:, wantedFrames: = [:]); Arranger.snapshot.wantedFrames"
  - "reattach adopts saved wanted frames by identity, with the moved-while-off and stranded rules (T-03-74)"
  - "LayoutStore validates wanted frames like home frames (T-03-73)"
affects: [ArrangeController restore and write, Arranger.reattach, Arranger.wakeDormant, LayoutStore.decode]
tech-stack:
  added: []
  patterns: ["optional Codable key with a hand-written init(from:) instead of a schema bump"]
key-files:
  created:
    - .planning/phases/03-tiling-mvp/03-26-SUMMARY.md
  modified:
    - Sources/PaneEngine/LayoutFile.swift
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/LayoutStore.swift
    - Tests/PaneEngineTests/ArrangerRestoreTests.swift
    - Tests/PaneMacTests/LayoutStoreTests.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "No schema bump: wantedFrames is an optional key. An older Pane ignores it, and a newer Pane reads an older file with no wanted frames. schemaVersion stays 1."
  - "Moved-while-off rule: at the re-attach (and in wakeDormant), a present floater on a shown Desktop whose real frame is on screen and more than 2 pt off its saved floating frame takes the real frame as its wanted frame, so no setFrame moves it back."
  - "Stranded rule: a saved wanted frame that is stranded on the current displays is dropped, so Float falls back to the 90% centred frame."
  - "Saved wanted frames are kept only for windows the re-attached World holds; 03-25's seeding then fills floaters with none."
  - "Undo is unchanged: wanted frames are not part of desk snapshots (03-25)."
metrics:
  duration: "~5 min"
  completed: 2026-10-27
  tasks: 2
  files: 7
actuals:
  tokens: 5400
  tasks: 2
  commits: 4
plan_head_before: cf34184900234320b6bf8c0acee20caaeef514c8
plan_head_after: 7dcb43038a930e65315e585983b3018664538426
---

# Phase 3 Plan 26: Wanted frames saved in layout.json (G-03-4, G-03-11) Summary

layout.json now carries each window's wanted frame as an optional, validated key, so a docked window's pre-dock frame survives a quit and relaunch and Float still lands there. At the re-attach, a floater the user moved while Pane was not running keeps its real frame, and a saved frame that is stranded on the current displays is dropped. Files from before 03-26 load with no wanted frames, and the schema version stays 1.

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 (tracer) | A docked window's pre-dock frame survives a relaunch | 292d66c (RED), 0040dfe (GREEN) |
| 2 | layout.json validation and backward compatibility for wanted frames, deferred items | c00d6ad (RED), 7dcb430 (GREEN) |

## TDD

**Task 1 RED (292d66c):** a compile failure, as the plan expected. `swift build --build-tests` reported `extra argument 'wantedFrames' in call` (LayoutFile and `.restore`) and `value of tuple type '(world: World, homeFrames: ...)' has no member 'wantedFrames'` (`snapshot`).

**Task 1 GREEN (0040dfe):** the verify filter (`ArrangerRestoreTests|ArrangerMultiDeskRestoreTests|WantedFrameTests|ArrangerGreenButtonTests`) ran 57 tests in 5 suites, all passing, with no "✘". The three new tests ran and passed. A mutation check (the moved-while-off rule forced to false) made `aFloaterMovedWhilePaneWasNotRunningKeepsWhereTheUserPutIt` fail on both expectations: b's wanted frame stayed the saved one, and a setFrame moved b. The rule was then restored.

**Task 1 tracer gate:** the verify was re-run end to end after the GREEN commit and passed. No `gate="blocking-human"` on the task.

**Task 2 RED (c00d6ad):** `swift test --filter LayoutStoreTests` failed with 8 issues: the "huge wanted frame" and "duplicate wanted frame" rows were loaded instead of rejected. The "non-finite wanted frame" row already passed, because JSONDecoder rejects `1e400` at parse time, as for the existing "non-finite home frame" row. The two new tests passed at RED, since Task 1 already added `decodeIfPresent`. They guard that behaviour.

**Task 2 GREEN (7dcb430):** `LayoutStoreTests` ran 8 tests (10 badFiles cases), all passing. The full `swift test` passed every test binary, 527 + 198 + 193 + 42, with no "✘". `scripts/check-no-appkit.sh` printed `no-appkit: OK (40 files)`.

**Expectation guard:** `git diff 292d66c^ -- Tests/ | grep -c "^-.*#expect"` prints 0. No existing expectation was removed or rewritten.

## Acceptance checks

- `decodeIfPresent` in LayoutFile.swift: 1.
- `wantedFrames` in non-comment lines of ArrangeController.swift: 2.
- `static let schemaVersion = 1` in LayoutFile.swift: 1.
- `wantedFrames` in non-comment lines of LayoutStore.swift: 1.
- `Found in 03-25 and 03-26` in deferred-items.md: 1.

## Deviations from Plan

None. The plan was executed as written.

- The "non-finite wanted frame" row passed at RED: the JSON parser rejects it before validation runs, as with the existing home-frame row. The row still pins the rejection.
- `movedWhileOff(_:saved:)` is one private helper in Arranger, shared by `reattach` and `wakeDormant`, so the rule is written once. It reuses `Arranger.near` (`Planner.near`) at 2 pt.

## Known Stubs

None.

## Threat Flags

None. The new surface is the one in the plan's threat model: T-03-73 (validation) and T-03-74 (re-attach rules) are mitigated and tested, and T-03-75 is accepted. `titlesAreNeverWritten` still passes.

## Output note

The orchestrator re-checks these afterwards in the Tart VM:
- the green button on a desk's only docked window moves it visibly both ways;
- a gap drag down and back up returns the floaters, with none below the screen;
- a quit and relaunch keeps a docked window's pre-dock frame for Float.

This plan does not close G-03-4 or G-03-11 in 03-UAT.md. /gsd-verify-work does.

The run was headless only. PANE_LIVE was never set, and neither Pane nor PaneFixtureApp was launched.

## Self-Check: PASSED

- Files: LayoutFile.swift, LayoutStore.swift and 03-26-SUMMARY.md exist.
- Commits 292d66c, 0040dfe, c00d6ad and 7dcb430 are all ancestors of HEAD.
