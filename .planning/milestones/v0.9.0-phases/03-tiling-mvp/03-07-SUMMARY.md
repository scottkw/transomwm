---
phase: 03-tiling-mvp
plan: 07
subsystem: persistence
status: complete
tags: [swift, paneModel, paneEngine, paneMac, persistence, layout-restore, tdd, tracer]

requires:
  - phase: 02-window-control
    provides: "WindowIDSource.synthetic is session-only (02-11); MinimumHintsStore's validated, atomic store shape (02-13)"
  - phase: 03-tiling-mvp
    provides: "Arranger, ArrangeController, World.reflow/recordFloatingFrame, Desktop tile (03-01..03-06)"
provides:
  - "PaneEngine LayoutFile, HomeFrame, SessionRecord (layout.json contents)"
  - "PaneEngine LayoutRestore.reattach (pure re-attach by identity; synthetic IDs never match)"
  - "Arranger: ArrangerInput.restore, ArrangerEffect.save(SaveUrgency), homeFrames, snapshot"
  - "PaneMac LayoutStore / LayoutStoreError: validated load with set-aside, newer schema kept and saving disabled, atomic 0600 save without titles"
  - "PaneModel World.withoutTitleHints()"
  - "ArrangeController(system:store:): load + restore at start, 0.5 s debounced writes, writeCleanExit()"
  - "PaneMacApp creates the store at ~/Library/Application Support/Pane and writes cleanExit true on willTerminate"
affects: [03-08, 03-14, 03-15, persistence, recovery, quit-restore]

estimate:
  tokens: 80000
  tasks: 2
actuals:
  tokens: 31400
  tasks: 2
  commits: 4
plan_head_before: d484175e97f0588916a946291a5742a9cb70e09b
plan_head_after: 77c5d029299b12a89df3e3cff1e581a92dd2d60d

tech-stack:
  added: []
  patterns:
    - "Arranger.handle diffs the World before and after each input and appends .save(.debounced) on any change, so no mutation path can forget to save"
    - "A pending restore is what snapshot returns, so a write before re-attach never replaces the saved layout with an empty one"

key-files:
  created:
    - Sources/PaneEngine/LayoutFile.swift
    - Sources/PaneEngine/LayoutRestore.swift
    - Sources/PaneMac/LayoutStore.swift
    - Tests/PaneEngineTests/ArrangerRestoreTests.swift
    - Tests/PaneMacTests/LayoutStoreTests.swift
    - .planning/phases/03-tiling-mvp/tdd/03-07-task1-red.json
    - .planning/phases/03-tiling-mvp/tdd/03-07-task2-red.json
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneModel/World.swift
    - Sources/PaneModel/DesktopLayer.swift
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift
    - Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift
    - Tests/PaneModelTests/PersistenceTests.swift

key-decisions:
  - "Every input that changes the World emits .save(.debounced), found by diffing the World, so OS facts recorded while the session is paused are saved too"
  - "Until a restore re-attaches, events are ignored and incomplete inventories change nothing; the first complete inventory re-attaches, and snapshot returns the saved layout meanwhile"
  - "On re-attach, each docked window's current frame counts as already requested and a present floating window's real frame is recorded, so only tiles more than 0.5 pt off are written and floating windows never move"
  - "Home frames are restored only for windows tracked under a real (non-synthetic) ID"
  - "LayoutRestore.reattach throws if closing a saved window leaves an invalid World; the Arranger then logs a fault and starts empty"
  - "The session record is written at launch with the loaded layout still in it (cleanExit false); writeCleanExit does nothing if tracking never started"
  - "SessionRecord.launchedAt uses JSONEncoder's default Date encoding (seconds since 2001, exact round trip), not ISO 8601"

patterns-established:
  - "layout.json tests build their bad files by editing one place in a real saved file, so each row differs from a good file in exactly one way"

requirements-completed: [SAFE-06]

coverage:
  - id: D1
    description: "Re-attach keeps a saved window only for a tracked window with the same identity and a non-synthetic ID; others are removed through the close path; unknown tracked windows are unplaced and float"
    requirement: SAFE-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerRestoreTests.swift#reattachKeepsOnlyWindowsTrackedUnderTheSameRealID, reattachAppliesRealStatesAndFloatsWindowsTheLayoutDoesNotKnow"
        status: pass
    human_judgment: false
  - id: D2
    description: "A restore waits for the first complete inventory, then moves nothing that is already in its tile, and every World change asks for a debounced save"
    requirement: SAFE-06
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerRestoreTests.swift#aRestoreWaitsForTheFirstCompleteInventoryAndThenMovesNothing, everyWorldChangeAsksForADebouncedSave, aLayoutRoundTripsThroughLayoutFileIntoAFreshArranger"
        status: pass
    human_judgment: false
  - id: D3
    description: "A fresh window system and controller on the same layout.json re-attach docked fixture windows with the same World and unchanged frames"
    requirement: SAFE-06
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift#aFreshControllerOnTheSameStoreReattachesDockedWindowsWithoutMovingThem"
        status: pass
    human_judgment: true
    rationale: "The plan's human-check (quit and relaunch the signed Pane Debug with real apps) is deferred to end-of-phase UAT"
  - id: D4
    description: "layout.json is rejected whole on any doubt and set aside; a newer schema is kept and never overwritten; titles are never written; the file is 0600"
    requirement: SAFE-06
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/LayoutStoreTests.swift; Tests/PaneModelTests/PersistenceTests.swift#withoutTitleHintsEmptiesEveryTitleAndKeepsEverythingElse"
        status: pass
    human_judgment: false

duration: 11min
completed: 2026-10-26
---

# Phase 3 Plan 07: layout.json and re-attach by window ID Summary

**Pane now keeps the layout in `~/Library/Application Support/Pane/layout.json`: the World, the home frames and a session record. The file is written 0.5 s after each change, validated as a whole on load, and never holds window titles. After a relaunch with the apps still running, each window goes back to its tile by identity. Nothing moves that is already in place, and synthetic IDs never match.**

## Performance

- **Duration:** about 11 min
- **Started:** 2026-10-26T03:21:43Z
- **Completed:** 2026-10-26T03:32:20Z
- **Tasks:** 2 (4 commits)
- **Files:** 7 created, 8 modified

## Accomplishments

- **File shape (D-16).**
  - `LayoutFile { schemaVersion: 1, world, homeFrames: [HomeFrame], session: SessionRecord }`.
  - Home frames are sorted by identity.
  - `homeFrameMap` gives them back as a dictionary.
- **Re-attach (SAFE-06, D-17).** `LayoutRestore.reattach` is pure.
  - It keeps a saved window only when a tracked window has the same `WindowIdentity` and `idSource != .synthetic`.
  - Every other saved window is removed through `World.apply(.closed, …)` with a throwaway history.
  - Tracked dockable, present, non-excluded windows that no desk holds are returned as `unplaced`.
- **Arranger.**
  - `.restore(world, homeFrames:)` is held as pending.
  - While it is pending, events are ignored and an incomplete inventory changes nothing. `snapshot` returns the saved layout during that time.
  - The first complete inventory re-attaches the layout:
    - The World is replaced and history starts empty.
    - Each window's real state is applied with `World.apply`.
    - A present floating window's real frame is recorded.
    - Each docked window's current frame is seeded as already requested.
  - It then places unplaced windows on their Desktop, through the 03-04 path, and re-plans quietly with notices filtered out. Only tiles more than 0.5 pt off are written, so an unchanged layout sends nothing.
  - `handle` diffs the World around every input and appends `.save(.debounced)` when it changed.
- **Store (T-03-15..18).** `LayoutStore` follows `MinimumHintsStore`'s order:
  - Size cap at `World.maxEncodedBytes`.
  - Version probe.
  - Full decode, which runs World's own validation.
  - Each home frame must pass `isValidGeometry` and be unique.
  - Any failure logs at error level (category `persist`), moves the file to `layout.json.corrupt` (replacing an older one) and starts empty.
  - A newer schema is the exception. It is logged and left byte-identical, `savingDisabled` is set, and every later `save` returns false without writing.
  - `save` writes the World with titles removed, sorted and pretty-printed, atomically, then sets 0600.
- **Controller and app.**
  - `ArrangeController(system:store:)` loads the store at `start()`, feeds `.restore`, then writes this launch's session record (`cleanExit: false`) with the loaded layout still in it.
  - The first inventory that has `initialRefreshComplete` is fed again from the events loop.
  - `.save(.debounced)` is one replaceable `WakeTimer` 0.5 s after the latest request. `.save(.now)` writes at once.
  - `PaneMacApp` creates the store at `MinimumHintsStore.defaultDirectory`. Its willTerminate observer calls `writeCleanExit()`, which writes `cleanExit: true`. Plan 15 moves this after the quit restore.

## Task Commits

1. **Task 1 (tracer): docked fixture windows come back after a fresh controller loads layout.json**: `1bb2588` (test, RED), `5b0b8fb` (feat, GREEN)
2. **Task 2: a hostile or newer layout.json is rejected safely, and no titles are stored**: `964052c` (test, RED), `77c5d02` (feat, GREEN)

## TDD Gate Compliance

- Each task starts with a `test(03-07)` commit, and a `feat(03-07)` commit follows it. There are no refactor commits.
- **Task 1 RED:** `RED_EVIDENCE_OK`, target `aRestoreWaitsForTheFirstCompleteInventoryAndThenMovesNothing()`. The record is in `.planning/phases/03-tiling-mvp/tdd/03-07-task1-red.json`.
  - All 5 unit tests failed on their planned assertions, against stubs that compile:
    - `.restore` was ignored.
    - `reattach` returned the saved World unchanged.
    - `.save` was never emitted.
  - The live test was not run at RED, to keep live runs down.
- **Task 2 RED:** `RED_EVIDENCE_OK`, target `aNewerFileIsKeptUntouchedAndNeverOverwritten()`. The record is in `.planning/phases/03-tiling-mvp/tdd/03-07-task2-red.json`.
  - The target and the rejection, permission and title rows failed against the Task 1 store and a `withoutTitleHints` stub that returned `self`.
  - `noFileStartsEmptyWithoutAnError` and the existing PersistenceTests passed at RED by design.
- **Tracer gate after Task 1:** both automated verifies were re-run after GREEN and passed before Task 2 started: the unit suite, then the live suite from a trusted terminal. The plan's human-check is deferred to end-of-phase UAT (`human_verify_mode: end-of-phase`), as in 03-05 and 03-06.

## Verification

- `swift test --filter ArrangerRestoreTests`: 5 tests ran and passed.
- `swift test --filter Arranger`: 42 tests passed.
- `swift test --filter "LayoutStoreTests|PersistenceTests|TitleRedactionTests"`: 15 + 6 tests ran and passed, with LayoutStoreTests in the output.
- `caffeinate -d -i swift test --filter ArrangeIntegrationTests` was run twice, after Task 1 and after Task 2:
  - The Mac was checked as unlocked before each run.
  - 4 tests passed each time, including `aFreshControllerOnTheSameStoreReattachesDockedWindowsWithoutMovingThem`, which was not skipped.
  - The fullscreen test is skipped behind its `PANE_LIVE_FULLSCREEN` opt-in, because the live-test rules forbid Space switches. The plan's `fails_when` says "skipped", and only that existing opt-in test is skipped.
  - `pgrep` found no leftover fixtures.
- `swift test --skip PaneMacIntegrationTests`: 190 + 118 + 289 tests passed.
- `scripts/check-no-appkit.sh`: OK (33 files).
- Acceptance greps (actual counts):

  | Pattern | File | Count |
  |---|---|---|
  | `public struct LayoutFile` | LayoutFile.swift | 1 |
  | `synthetic` | LayoutRestore.swift | 2 |
  | `"layout.json"` | LayoutStore.swift | 1 |
  | `LayoutStore` | PaneMacApp.swift | 1 |
  | `func withoutTitleHints` | World.swift | 1 |
  | `savingDisabled` | LayoutStore.swift | 3 |
  | `.corrupt` | LayoutStore.swift | 10 |
  | `0o600` | LayoutStore.swift | 2 |
  | `LayoutRestore.reattach` | Arranger.swift | 1 |
  | `store.(save\|load)` | ArrangeController.swift | 2 |

## Deviations from Plan

**1. [Rule 1 - Correctness] `LayoutRestore.reattach` throws**
- **Issue:** The interface declares `reattach` as non-throwing. Removing a saved window goes through `World.apply(.closed, …)`, which can throw on a crafted tree (for example, a same-axis merge past `maxChildren`). A non-throwing version would have to swallow that error silently.
- **Fix:** The signature is `throws(LayoutError)`. The Arranger catches the error, emits a fault and starts with an empty World, so every tracked window floats. It is the same "any doubt, start empty" rule the store uses.
- **Commit:** 5b0b8fb

**2. [Rule 2 - Correctness] A pending restore is what gets saved**
- **Issue:** The controller writes the session record at launch, before re-attach. With `snapshot` returning the live World, that write, or a quit before the first sweep, would replace the saved layout with an empty one.
- **Fix:** `snapshot` returns the pending restore. `writeCleanExit()` does nothing if tracking never started and cancels a pending debounced write.
- **Commit:** 5b0b8fb

**3. [Test update] The pause test now expects a save**
- **Issue:** `nothingIsWrittenWhileThePauseLastsAndTheDeskIsReplannedOnResume` expected no effects at all for a `windowDestroyed` while paused.
- **Fix:** The close still changes the World, so it now yields exactly `[.save(.debounced)]`. No frame is written, which is what the test protects.
- **Commit:** 5b0b8fb

**4. [Interface extension] `save` returns `Bool`**
- **What changed:** `save` is `@discardableResult … -> Bool`. It returns false when nothing was written, as the behaviour "a later save is a no-op that reports nothing written" requires.
- **Effect on callers:** none.

**5. [Interface extension] Two small helpers outside the listed files**
- `LayoutFile.homeFrameMap`, so callers do not rebuild the dictionary.
- `DesktopLayer.mapWindows`, internal, because `DesktopLayer.windows` is private(set) and `withoutTitleHints` must rewrite floating refs.
- **Effect on callers:** none.

**6. [Test design] There is no NaN row**
- **Issue:** JSON cannot carry NaN, and the default `JSONDecoder` refuses it.
- **Fix:** The "non-finite home frame" row uses the overflowing literal `1e400`. The `2e6`-wide row checks the `isValidGeometry` range rule and is pinned as `.invalidEntry`.

## Known Stubs

None.

## Threat Flags

None. The only new file surface is layout.json under ~/Library/Application Support/Pane, which the plan's threat model covers (T-03-15 to T-03-18).

## Next Phase Readiness

- Plan 08 can emit `.save(.now)` before a park and record `homeFrames`; the controller already writes at once for `.now`.
- Plan 14 reads `LayoutStore.contents?.session` before this launch's write. The controller writes at start right after `load()`, and `contents` keeps the previous record.
- Plan 15 moves `writeCleanExit()` from the willTerminate observer into the terminate sequence and keeps the freeze-test resume observer.
- Human UAT (end of phase): in Pane Debug, dock three app windows, quit from the menu, and relaunch with the apps still running. Each window should be back in its tile with no visible movement.

## Self-Check: PASSED
