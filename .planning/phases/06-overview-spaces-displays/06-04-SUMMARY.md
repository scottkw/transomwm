---
phase: 06-overview-spaces-displays
plan: 04
subsystem: engine
status: complete
tags: [displays, arrangements, layout-sets, settling, n12, fake-window-system]
requires:
  - phase: 06-02
    provides: "SpacesSnapshot / provider and per-display Space data the desks key on"
  - phase: 06-03
    provides: "ArrangementID, LayoutSet, LayoutFile schema 2 (maxLayoutSets = 16), SpaceRekey"
provides:
  - "ArrangerInput .displaysSettling and .displaysSettled(ArrangementID, names:, inventory:); .restore gains arrangement: and layoutSets: (defaulted)"
  - "Arranger.settling / arrangement / layoutSets, dormantDeskCount, awayDisplayCount; snapshot gains arrangement and layoutSets (pre-change World while settling)"
  - "LayoutSets (sorted, LRU cap 16, store/take/subscript) and ArrangementSwitch (same / known / new, decide, cascade)"
  - "Notice.displaysDisconnected(names:windows:) (N12, not a crash notice)"
  - "FakeWindowSystem.unplug(_:movingSpacesTo:) and plug(_:) modelling A6"
affects: [06-05, 06-06, 06-12]
actuals:
  tokens: 15100
  tasks: 2
  commits: 2
plan_head_before: 30a9ad2e0a2744b2905e15643db89f55a9bedcc1
plan_head_after: 9ac89c56b2bd51bccb8749648adfe2253d01b96c
tech-stack:
  added: []
  patterns:
    - "Settling flag: OS facts still update the World, but display-based rehome and every frame write wait for the settle"
    - "Claim on settle: a window held by a desk on a connected display is reported on that display, so the layout wins over where macOS left it"
    - "User-placed windows detected by diffing (desk, leaf NodeID) slots across an input that changed the undo history"
key-files:
  created:
    - Tests/TransomEngineTests/ArrangerDisplaySettleTests.swift
  modified:
    - Sources/TransomEngine/Arranger.swift
    - Sources/TransomEngine/Arrangements.swift
    - Sources/TransomEngine/Notice.swift
    - Sources/TransomTestSupport/FakeWindowSystem.swift
    - Sources/TransomMac/Shell/NoticeCopy.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Overlay/NoticeQueue.swift
    - Tests/TransomEngineTests/ArrangementsTests.swift
key-decisions:
  - "User action wins at desk level: each current desk holding a user-placed window is kept (less windows the stored set puts elsewhere), other desks come from the stored set, so a user-docked window stays docked rather than floating over a stored tile"
  - "Every settle claims windows by their desk's display (same, known and new), so a window macOS left on the wrong display goes back to its tile instead of being re-homed"
  - "A known switch merges with the larger IDSource of the stored and current Worlds, so no NodeID is minted twice across desks"
  - "A weight change (grow/shrink, gap drag) is not a placement: it stays with its arrangement's set"
  - "Undo history resets on a known arrangement switch (same as launch restore)"
  - "The current arrangement is initialised from the first inventory's displays when no restore set it"
requirements-completed: []  # OVER-04..06 hold in the Engine; not marked until 06-05 wires the shell inputs (as 06-03 did)
duration: ~45min
completed: 2026-10-31
---

# Phase 6 Plan 04: Display Settling and Arrangement Layout Sets Summary

The Engine now has a display "settling" state, so macOS moving windows off a vanishing display no longer destroys their tiles. It also keeps one layout set per display arrangement. Unplugging a display parks its desks (dormant) and cascades its windows onto the remaining display, with one N12 notice. Re-plugging, or docking into any arrangement seen before, applies that arrangement's stored layout through the launch re-attach path. A window the user placed in the meantime stays where they put it.

## What was built

- **Arrangements.swift:** `LayoutSets` keeps sets sorted by arrangement, at most 16, and drops the least recently used first (ties broken by arrangement). `ArrangementSwitch.decide` returns same, known or new. `ArrangementSwitch.cascade(frames:from:in:)` keeps each window's own size, steps 24 pt right and down from the Desktop tile's top-left, and clamps inside the visible frame.
- **Arranger.swift:**
  - `.displaysSettling` saves `preChangeWorld`, sets `settling` and hides the gap handles. While settling, `rehome` skips moves that change display (Space moves still apply). `planShown`, `floatLostRoom` and `moved()` answer nothing.
  - `.displaysSettled` stores the pre-change World under the old arrangement unless it is unknown, unchanged or the same. It then adopts the inventory and applies the decision:
    - **known:** merges the stored set with `userPlacedSinceSwitch` and runs `reattach`, the same path as the launch restore.
    - **new:** keeps the World, cascades the windows of absent displays and emits N12.
    - **same:** re-plans only.
  - Every settle then claims windows by their desk's display, feeds `place`, and emits `.save(.debounced)`.
  - Duplicate display UUIDs log an info line and force `.new`.
  - `reattach` now throws, and the launch caller keeps its `unattached` handling.
  - `adopt(_:)` is extracted from the inventory case.
- **Notice.swift:** adds the `displaysDisconnected(names:windows:)` case.
- **FakeWindowSystem:** `unplug` removes the display, moves its windows onto the target at the same offset (clamped), keeps their Space IDs, refreshes and yields `.displaysChanged`. `plug` reverses it.

## Verification

- Task 1 gate `swift test --filter ArrangerDisplaySettleTests`: 1 test passed, no ✘. The tracer gate was re-run (the whole Engine suite, 720 tests, was green) before expanding.
- Task 2 gate `swift test --filter 'ArrangerDisplaySettleTests|ArrangementsTests|ArrangerSpacesTests|ArrangerMultiDeskRestoreTests|ArrangerRestoreTests|TrackerDisplayTests'`: 82 tests passed, no ✘. `scripts/check-no-appkit.sh` passed (49 files).
- Full unit suites `--filter 'TransomEngineTests|TransomModelTests|TransomMacTests'`: 193 / 319 / 734 passed. No live runs.
- Acceptance greps: `displaysSettl` ×8 in Arranger (at least 2 required). The raw `.displaysChanged` no-op line is present once. `displaysDisconnected` ×2 in Notice.swift, `userPlacedSinceSwitch` ×4, and 11 `@Test` in ArrangerDisplaySettleTests (at least 9 required).

## TDD Gate Compliance

- Task 1 RED: the tracer failed to compile because `displaysSettling`, `displaysSettled`, `unplug` and `plug` did not exist. GREEN came in 32ef837.
- Task 2 RED: the new tests failed to compile because `Notice.displaysDisconnected`, `dormantDeskCount` and `awayDisplayCount` did not exist. GREEN came in 9ac89c5. The first GREEN run had one failure, which was a wrong assertion in the rescale test (D's tree is `[2 | 3 | Desktop]`, so window 3 never reaches the right edge). The assertion now checks the new tile height.
- Tests and implementation were committed together for each task, one commit per task.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Adding `Notice.displaysDisconnected` broke three exhaustive shell switches**
- **Found during:** Task 2
- **Fix:** `NoticeCopy.text` got the N12 copy from UI-SPEC Surface 6 (32-character name truncation, curly quotes, 1 / n / several branches). `glyph` returns `display`. `ArrangeController.displayUUID(of:)` returns nil, so the toast goes to the default display. `NoticeQueue.merged` returns nil.
- **Left for 06-05:** the N12 merge, the copy tests, and showing the toast on the display that received the windows.
- **Files modified:** Sources/TransomMac/Shell/NoticeCopy.swift, Sources/TransomMac/ArrangeController.swift, Sources/TransomMac/Overlay/NoticeQueue.swift
- **Commit:** 9ac89c5

**2. [Rule 1 - Bug] The plan's literal merge would overlap tiles**
- **Found during:** Task 2 design
- **Issue:** The plan removes user-placed windows from the stored World before reattach. That would float a window the user docked on top of the stored layout's tiles, which breaks the core no-overlap value.
- **Fix:** `Arranger.merged` keeps each current desk that holds a user-placed window, minus other windows the stored set puts elsewhere. Every other desk comes from the stored set, minus the windows those kept desks hold. Windows are removed through the close path with a throwaway history.
- **Commit:** 9ac89c5

**3. [Rule 2 - Correctness] Claim windows by their desk's display at every settle**
- **Found during:** Task 1
- **Issue:** macOS does not reliably move windows back on re-plug. Without a claim, `rehome` would float a window macOS left on L instead of returning it to its D tile, and would undo a user's dock on L when the fake moved it back to D.
- **Fix:** `claim(_:)` reports each window on its desk's display when that display is connected.
- **Commit:** 32ef837

**4. [Minor] Cascade signature and commit placement**
- `cascade(frames:from:in:)` takes a start point as well as the clamp rect, because the plan's `cascade(frames:in:)` cannot express both.
- The pure `cascade` landed in the Task 1 commit. It is first used in Task 2.

## Risks for 06-05

- The shell still feeds an inventory on `.displaysChanged` and never sends the settling inputs. Until 06-05 wires them, behaviour is unchanged from Phase 3.
- `ArrangeController.write` still passes `store.contents?.layoutSets` through. 06-05 should write `arranger.snapshot.layoutSets` and `.arrangement`, and pass both into `.restore`.
- If the saved arrangement differs from the live displays at launch, the Arranger treats the saved one as current. 06-05 should send a settle after the restore when they differ.
- Stored sets carry no wanted frames. A window re-docked by a known switch keeps the wanted frame it had while floating on the other display.

## Known Stubs

None.

## Threat Flags

None. All new surface is covered by T-06-10..12: settling stashes the World, duplicate UUIDs force `.new`, and the cascade is clamped and tested.

## Self-Check: PASSED
