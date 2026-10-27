---
phase: 03-tiling-mvp
fixed_at: 2026-10-27T16:31:45Z
review_path: .planning/phases/03-tiling-mvp/03-REVIEW-03-26.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report (plans 03-24 to 03-26 review)

**Fixed at:** 2026-10-27T16:31:45Z
**Source review:** .planning/phases/03-tiling-mvp/03-REVIEW-03-26.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (CR-01, WR-01, WR-02; IN-01..06 are out of scope for `critical_warning`)
- Fixed: 3, each with a headless test that failed before its fix
- Skipped: 0

All three fixes change logic, so each is marked "fixed: requires human verification". The headless tests pin the behaviour, but the live checks under "Needs VM" were not run.

## Fixed Issues

### CR-01: A floater moved back onto Pane's last write is treated as Pane's own, and the next re-plan moves it away again

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/WantedFrameTests.swift`
**Commit:** 7d2bef3
**Status:** fixed: requires human verification
**Applied fix:** The review's fix. In `moved`, a floater's first move that is not Pane's own records the wanted frame and also clears `lastApplied`. After the window has been anywhere else, a move back onto Pane's last read-back counts as the user's. The optional extra (clearing `lastApplied` once its echo is consumed) was not done.
**Tests:**
- `aFloaterMovedBackOntoPanesLastWriteIsNotMovedAway` (probe A): dock, green button, zoom, un-zoom back to the float frame, focus. No setFrame, the window stays un-zoomed, and its wanted frame is the un-zoomed frame.
- `aFloaterCentredAgainByTheUserStaysCentred` (Window > Center variant): with no pre-dock frame, Float centres the window. The user moves it, then centres it again, and Pane leaves it centred.
- `aClampTheAppAppliesLateIsStillPanesOwn` still passes, as the review predicted, because its late frame counts as own through `liveGap`.

### WR-01: Float stores its clamp of the pre-dock frame as the new wanted frame

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Tests/PaneEngineTests/WantedFrameTests.swift`
**Commit:** 75d2424
**Status:** fixed: requires human verification
**Applied fix:** `float()` decides inside the edit closure, where the Desktop rect is known. If the landing frame is `clamp(wanted, into: desktop)`, so Float used the pre-dock frame, the pre-dock frame stays the wanted frame. If Float used the centred 90% fallback, the landing frame is recorded as before. The re-plan already plans `clamp(W)` while W overlaps a tile, so the window lands where it did before the fix.
**Edge case:** if W overlaps no tile but sticks out of the Desktop rect (for example, it reaches into the gap band), the re-plan now moves the window to W itself rather than to its clamp. Every floater with a wanted frame is planned this way.
**Test:** `aFloatedWindowGrowsBackToItsPreDockFrameWhenTheDesktopDoes` (probe C). Two windows are docked. Float the one with the large pre-dock frame: it is clamped, and its wanted frame is still the pre-dock frame. Float the other: the first grows back to its pre-dock frame.

### WR-02: Float All, and any undock that is later undone, permanently replaces the pre-dock frames

**Files modified:** `Sources/PaneEngine/Arranger.swift`, `Sources/PaneEngine/Arranger+Commands.swift`, `Tests/PaneEngineTests/WantedFrameTests.swift`, `Tests/PaneEngineTests/ArrangerDragTests.swift`
**Commit:** 9cb65bd
**Status:** fixed: requires human verification
**Applied fix:** Neither of the review's options was used as written.
- **Why not option (a).** The review's option (a), and the orchestrator's suggestion, was that Float All and the ⇧-undock not overwrite the wanted frame. That does not keep TILE-16's tile-rect landing. The Planner moves every floater whose recorded frame is more than 0.5 pt from its wanted frame, so the re-plan right after Float All would send each window to its pre-dock frame. It would do the same to a ⇧-dropped window, which would jump away from where the user dropped it. I checked this headlessly: with option (a) applied to `floatAll`, the new test's `frame(w1) == tile` check failed.
- **What was done.** A per-window `undockedWanted` dictionary. Float All and `commitUndock` save the wanted frame they replace. `undo()` gives it back to each window that the undone desk docks again. `forget` drops the entry and `windowRekeyed` moves it, like the other per-window state.
- **Undo design is unchanged.** The snapshot type is untouched, and wanted frames are still not in snapshots.
- **Float is not covered.** After WR-01, Float no longer destroys a used pre-dock frame. When it falls back to the centred frame, the pre-dock frame was on the tile, so Float after an Undo falls back again either way.
- **Known limit.** The dictionary holds one level per window. An Undo across two undocks of the same window gives back the later undock's frame, not the earlier one. This is marked `shortcut:` in the code.
**Tests:**
- `undoingFloatAllGivesBackThePreDockFrames` (probe B). Dock w1, then Float All: w1 lands at its tile, which pins TILE-16. Undo docks it again, and Float then sends it to its pre-dock frame.
- `undoingAShiftUndockGivesBackThePreDockFrame`. ⇧-drag b out of `[a | b | Desktop]`: it lands at its release frame. Undo docks it again, and Float then sends it to `frameB`.

## Verification

- **Where it ran:** an isolated git worktree, `.claude/worktrees/rf-03-2841-1793118273`, on branch `gsd-reviewfix/03-2841`. `workflow.use_worktrees` is not set in config, so it defaults to true. The commits were fast-forwarded onto `gsd/phase-01-layout-model`. The worktree was then removed, so rerun the commands below in the main checkout to reproduce the numbers.
- **Per fix:** each new test was first run with `swift test --filter` and failed for the reason in the review (1–7 tests ran, none skipped). The WR-02 ⇧-undock test first failed in its setup because it was missing the `.tick` the existing ⇧-undock test sends. After the tick was added, it failed only on the Float-after-Undo frame. After each fix, the `PaneEngineTests` filter passed: 529, then 530, then 532 tests.
- **Full headless `swift test` at HEAD 9cb65bd:** 193 + 198 + 42 + 532 tests passed, with no failures (XCTest: 0 tests). Engine tests went from 527 to 532 (5 new test functions). `FreezeTestTests/itResumesByItself` did not flake in this run.
- **AppKit check:** `scripts/check-no-appkit.sh` reported `no-appkit: OK (40 files)`.
- **Existing tests:** no `#expect` or other line was removed or changed. The diff of `Tests/` since ef6d12e adds lines only.
- **Live runs:** no `PANE_LIVE` run, no Pane or fixture launch, and no Tart VM use.

## Needs VM (live checks not run)

1. **CR-01:** float a window with the green button, double-click its title bar to zoom, then double-click again to un-zoom. Pane should not re-zoom it on the next focus change. Repeat with Window > Center on a window Float centred.
2. **CR-01 side effect:** with an app that answers a write late or in two steps (outside a boundary drag), check that a floater is not pushed back and forth. Its late echo is still own through `lastRequested` while it is planned.
3. **WR-01:** dock a large window next to another, Float the large one (it is clamped), then Float the other. The first should grow back to its pre-dock frame.
4. **WR-02:** Float All, then Undo, then Float one window. It should go to its pre-dock frame. Do the same with a ⇧-drag undock followed by Undo.

---

_Fixed: 2026-10-27T16:31:45Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
