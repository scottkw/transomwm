---
phase: 03-tiling-mvp
fixed_at: 2026-10-27T04:10:00Z
review_path: .planning/phases/03-tiling-mvp/03-REVIEW-03-23.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report (plan 03-23 review)

**Fixed at:** 2026-10-27T04:10:00Z
**Source review:** .planning/phases/03-tiling-mvp/03-REVIEW-03-23.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (CR-01..03, WR-01..04; IN-01/IN-02 are out of scope for `critical_warning`)
- Fixed: 7, each with a headless test that failed before its fix
- Skipped: 0

All fixes change logic, so each is marked "fixed: requires human verification". The headless tests pin the behaviour, but the live checks under "Needs VM" were not run.

## Fixed Issues

### CR-01: A docked tab group shown under a non-leader tab is duplicated at relaunch

**Files modified:** `Sources/PaneEngine/WindowSnapshot.swift`, `Sources/PaneTestSupport/FakeWindowSystem.swift`, `Sources/PaneMac/AXWindowSystem.swift`, `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** d9c9b39
**Status:** fixed: requires human verification
**Applied fix:** This is the review's "smallest change".
- `CGWindowEntry` gained an optional `spaces` field.
- `AXWindowSystem` fills it from `SkyLightSpaces.spaces(of:)` for each `liveWindows` entry. The fake fills it from its observation Spaces.
- At the restore, an untracked saved window is kept dormant only when its Space set is unknown, or known, non-empty and on no shown Space.
**Test:** `aTabGroupShownUnderAnotherTabAtRelaunchIsNotKeptTwice(hiddenTabsReportSpace: false/true)`. The tab group is docked, tab 11 is selected, and Pane relaunches. Result: no dormant windows, leader 10 on no desk, the group (now tracked as 11) floating once.
**Not done:**
- The review's "complete fix" (`WindowInfo.memberIDs` plus re-keying the saved leader onto the tracked group) was not done. Such a group comes back floating: its tile is lost, as before 03-23, but it is no longer duplicated.
- With Spaces unavailable (SkyLight missing or forced off), Space sets are unknown and the duplicate can still happen. That keeps your rule "keep today's behaviour when Spaces are unavailable". The re-key fix would close it.

### CR-02: A parked dormant floater stays offscreen after a recovery launch

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** 340b1f6
**Status:** fixed: requires human verification
**Applied fix:** `wakeDormant` records the actual frame of a floating window only when its desk's Desktop is shown and the frame is not stranded (`Recovery.isStranded`). The re-plan then moves the window back to the desk frame. `lastRequested` was never seeded for floaters.
**Test:** `aParkedDormantFloaterComesBackOnScreenAfterACrash`. Before the fix, window 3 stayed at its parked frame.

### CR-03: A locked or blank first inventory wipes saved windows, and that is saved

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Sources/PaneEngine/LayoutRestore.swift`, `Sources/PaneMac/ArrangeController.swift`, `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** 08d5f30
**Status:** fixed: requires human verification
**Applied fix:** The review's two-sided fix, with one change so Pane cannot get stuck.
- **Arranger:** the restore waits while `sessionPaused` or while `liveWindows == []`. The new `awaitsRestore` reports this.
- **ArrangeController:** feeds every complete inventory while `awaitsRestore`: `feed = (awaitsRestore || !fedCompleteInventory) && initialRefreshComplete`.
- **The change:** a nil (unknown) list never waits, because it might never arrive (for example, the CG list keeps failing). It decides nothing instead. `LayoutRestore.reattach(live: nil)` keeps every saved window, and the existing prune removes the closed ones once a usable list arrives.
- **Why waiting cannot get stuck:**
  - A paused session ends with `.sessionPaused(false)`, which `AXWindowSystem` emits after its post-resume refresh.
  - An empty list means no layer-0 window of any tracked app exists. There is then nothing to arrange, and the first window that opens yields an event, which triggers a feed.
- **Default kept:** `reattach` keeps its `live: = []` default, now typed `[CGWindowEntry]?`. The review asked to remove it, but the existing test `reattachKeepsAnUntrackedWindowTheCGListStillHasUnderItsIDAndPid` pins that default (`today == empty`), and removing it would mean rewriting that test.
**Tests:**
- `aRestoreWaitsForAnUnlockedSessionAndANonEmptyCGList(locked: true/false)`: nothing is re-attached, the snapshot is still the saved layout, `awaitsRestore` is true, and the next good inventory restores the layout.
- `aRestoreWithAnUnknownCGListKeepsEverySavedWindow`: the restore runs at once with every saved window kept, and a later usable list prunes the window that closed.

### WR-01: An inventory that tracks a dormant window first skips `wakeDormant`

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** ebde51a
**Status:** fixed: requires human verification
**Applied fix:** After the restore, the `.inventory` branch notes which windows were dormant before it replaced `windows`. It then calls `wakeDormant` for each one the inventory now tracks. A failure is reported as a `.fault`, before the prune.
**Test:** `anInventoryThatTracksADormantWindowFirstAppliesItsRealState`. A minimized dormant window is fed by an inventory before its `windowCreated`. Before the fix, the desk kept `.present`.

### WR-02: A dormant window excluded while dormant stays docked when it wakes

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** a790df2
**Status:** fixed: requires human verification
**Applied fix:** `wakeDormant` calls `release(info)` before `rehome(info)`.
**Test:** `aDormantWindowOfAnAppExcludedMeanwhileFloatsWhenItWakes`. Result: docked `[4]`, and the excluded window floats.

### WR-03: A G-03-9 ghost keeps its saved window's empty tile across relaunches

**Files modified:** `Sources/PaneEngine/LayoutRestore.swift`, `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerRestoreTests.swift`, `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift`
**Commit:** 55d6f0f
**Status:** fixed: requires human verification
**Applied fix:** The change is in `isAlive` only, as you asked. An entry whose Spaces are known and empty is not alive. Unknown Spaces keep today's rule. CloseRule is untouched.
- **Relaunch side:** CR-01's restore filter already dropped entries on no Space. That check now lives in `isAlive`, and the filter keeps only the shown-Space check.
- **Prune side:** a dormant window whose entry turns Space-less is now pruned.
**Tests:**
- `aCGEntryOnNoKnownSpaceIsNotAlive`: empty means not alive; nil means alive; `[2]` means alive.
- `aDormantWindowWhoseCGEntryIsOnNoSpaceIsPruned`.

### WR-04: An inventory re-homes the window being dragged

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/ArrangerDragTests.swift`
**Commit:** d272b85
**Status:** fixed: requires human verification
**Applied fix:** The review's minimum. `place()` skips `rehome` for `drag?.window`, as the `windowChanged` path already does. The separate `.liveWindows` input was not added.
**Not done:** the inventory still overwrites `windows[id].frame` mid-drag. The next 60 Hz `.dragFrame` replaces it.
**Test:** `anInventoryMidDragNeverRehomesThePressedWindow`. The window is dragged toward a second display and the inventory reports it there; it stays on its desk.

## Verification

- **Where it ran:** the main checkout, `/Users/ken/dev/panewm`. The orchestrator asked for the main tree, so no worktree was created and the numbers can be reproduced from this tree.
- **Per fix:** each test was first run alone with `swift test --filter <name>` and failed for the reason in the review (1–2 tests ran, none skipped). After the fix, the `PaneEngineTests` filter passed every time: 506 tests after CR-03, then 507, 508, 510 and 511.
- **Full headless `swift test` at HEAD d272b85:** 193 + 196 + 42 + 511 tests passed, with no failures. That is 502 → 511 engine tests: 9 new test functions, some taking arguments. `FreezeTestTests/itResumesByItself` did not flake in this run.
- **AppKit check:** `scripts/check-no-appkit.sh` reported `no-appkit: OK (40 files)`.
- **Existing tests:** no `#expect` or other line was removed or changed. The diff of `Tests/` since 8f8fda5 adds lines only.
- **Live runs:** no `PANE_LIVE` run, no Pane or fixture launch, and no Tart VM use.

## Needs VM (live checks not run)

1. **G-03-9 / WR-03 (verifier human item 5):** dock Safari, press Cmd-W, and relaunch Pane while the ghost entry lingers. The tile should no longer be reserved after the relaunch.
2. **Blind spot for WR-03 and CR-01:** check which Spaces SkyLight reports for windows on a hidden Space that are minimized or belong to a Cmd-H hidden app. An empty set now removes such a saved window at restore, and prunes it if it is dormant.
3. **CR-01:** in a Finder or Terminal tab group, select a tab other than the oldest, then relaunch. The group should float once, with no empty docked tile. Also check whether hidden tabs report a Space on this macOS.
4. **CR-02:** with a floater parked on a hidden Space's desk (Desktop hidden), `kill -9` Pane, relaunch, and show that Space. The window should come back on screen.
5. **CR-03:** start Pane while the screen is locked, with a saved hidden-Space desk, then unlock. The desk should be intact, which exercises the new ArrangeController feed rule live.
6. **Cost:** `liveWindows` now makes one SkyLight Space lookup per live window each sweep. Check that this adds no faults and no noticeable sweep time.
7. **WR-04:** drag a window across displays while a window is dormant.

---

_Fixed: 2026-10-27T04:10:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
