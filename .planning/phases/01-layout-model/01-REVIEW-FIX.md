---
phase: 01-layout-model
fixed_at: 2026-10-24T07:23:53Z
review_path: .planning/phases/01-layout-model/01-REVIEW.md
iteration: 3
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Fixed at:** 2026-10-24T07:23:53Z
**Source review:** .planning/phases/01-layout-model/01-REVIEW.md (iteration 3)
**Iteration:** 3 (covers iterations 1 and 2 as well; see the sections below)

## Iteration 3

**Summary (iteration 3):**
- Findings in scope: 2 (WR-01, WR-02). fix_scope = critical_warning, so IN-01..IN-10 were not attempted.
- Fixed: 2
- Skipped: 0

**Where verification ran:** in the main checkout, on branch `gsd/phase-01-layout-model`. No worktree was created, because the orchestrator said not to. These results can be reproduced from this tree.

**Final gate results (all run after the last commit, b2c7489):**
- `swift test`: 141 tests in 14 suites passed (baseline 139)
- `swift test -c release -Xswiftc -enable-testing`: 141 tests passed
- `scripts/check-no-appkit.sh`: OK (11 files)

### Fixed Issues (iteration 3)

#### WR-01: Undo restores a window that is on no desk with whatever lifecycle state its snapshot held

**Files modified:** `Sources/PaneModel/World.swift`, `Tests/PaneModelTests/UndoTests.swift`, `Tests/PaneModelTests/ScenarioTests.swift`
**Commit:** c403f45
**Status:** fixed: requires human verification (this changes the public `undo` signature and adds a caller obligation)

**Applied fix:**
- `World.undo` now returns `[WindowRef]?` instead of `Bool`. `nil` means there was nothing to undo, as `false` did before. Otherwise it returns the windows the restored snapshot holds that no desk held before the undo, in snapshot order. Usually the list is empty. On success these are exactly the windows the old carry-over loop skipped. A skipped window that is on another desk makes `validate()` throw instead, so it is never returned.
- The doc comment states the contract: these windows keep their snapshot state, which may be stale, and the caller must re-report each one's real state through `apply`. The model cannot know that state itself, so it does not guess.
- I used an optional array instead of the reviewer's `UndoResult` struct. It carries the same two facts with no new type.
- No Phase 2 engine plan exists yet, so nothing could be updated there. When the Phase 2 engine is planned, it must query the OS for every window `undo` returns and call `apply` with the result.

**Regression test:** `UndoTests.undoReportsAWindowItBroughtBackFromNoDeskSoItsRealStateCanBeReapplied` runs the reviewer's sequence (1): move w from k1 to k2, `apply(.absent)` on k2, undo k2 (returns `[]`, and `apply` on k1 throws `windowNotFound`), then undo k1 returns `[w]` with the stale `.present`, and re-applying `.absent` sets it right. Before the fix, `undo` returned `Bool` and reported nothing, so this test does not compile against the old code. That is a compile-time failure, not a runtime one.

**Call sites updated:** every `world.undo` in `UndoTests` and `ScenarioTests` (`#expect(x)` became `x != nil`, `== false` became `== nil`). `undoWithEmptyHistoryReturnsFalseAndChangesNothing` was renamed to `...ReturnsNilAndChangesNothing`. Nothing in `Sources/` calls `undo`.

#### WR-02: `apply(.closed)` requires an existing desk key it otherwise ignores

**Files modified:** `Sources/PaneModel/World.swift`, `Tests/PaneModelTests/UndoTests.swift`
**Commit:** b2c7489
**Applied fix:** I took the smaller of the two options the reviewer offered. The `deskNotFound` guard moved into the non-`.closed` branch of `apply`, so `.closed` no longer looks at `key`, and the doc comment says so. `.absent`, `.present` and `.fullscreen` with an unknown key still throw `deskNotFound`. The existing `applyToAnUnknownDeskOrWindowThrowsAndChangesNothing` test still covers that. No new API was added.

**Regression test:** `UndoTests.closingAWindowNoDeskHoldsNeedsNoExistingDeskKey` runs the reviewer's reproduction: dock a and w on k1, remove w, `apply(.closed, w, on: k2)` where k2 has no desk, then undo k1. Before the fix it failed with `Caught error: .deskNotFound(D2)` (I ran it against the unfixed code first). After the fix, undo k1 returns `[]` and restores `[a]` without w.

## Iteration 2

**Fixed at:** 2026-10-24T07:16:10Z
**Source review:** .planning/phases/01-layout-model/01-REVIEW.md (iteration 2)
**Iteration:** 2 (covers iteration 1 as well; see "Iteration 1" below)

**Summary (iteration 2):**
- Findings in scope: 2 (WR-01, WR-02). fix_scope = critical_warning, so IN-01..IN-09 were not attempted.
- Fixed: 2
- Skipped: 0

**Where verification ran:** in the main checkout, on branch `gsd/phase-01-layout-model`. No worktree was created, because the orchestrator said not to. These results can be reproduced from this tree.

**Final gate results (all run after the last commit, ac3dabc):**
- `swift test`: 139 tests in 14 suites passed (baseline 135)
- `swift test -c release -Xswiftc -enable-testing`: 139 tests passed
- `scripts/check-no-appkit.sh`: OK (11 files)

**How "fails before the fix" was shown:** each regression test was written and run against the unfixed code first. The failures are recorded per finding below.

### Fixed Issues (iteration 2)

#### WR-01: Undo can still bring back a closed window: `apply(.closed)` only purges history when some desk currently holds the window

**Files modified:** `Sources/PaneModel/World.swift`, `Sources/PaneModel/Undo.swift`, `Sources/PaneModel/TreeEdits.swift`, `Sources/PaneModel/DesktopLayer.swift`, `Tests/PaneModelTests/UndoTests.swift`, `Tests/PaneModelTests/LifecycleTests.swift`, `Tests/PaneModelTests/TreeEditTests.swift`
**Commit:** 971a691
**Status:** fixed: requires human verification (this changes the lifecycle API contract)

**Applied fix:**
- `World.apply(.closed, …)` now acts on the window, not on the desk. It removes the window from whichever desk holds it, if any. It always calls `history.forget(window)`, including when no desk holds the window, so it no longer throws `windowNotFound` for `.closed`. An unknown `key` still throws `deskNotFound`. Other states keep the old desk-scoped behaviour and still throw `windowNotFound`.
- To close the bypass through `edit`, the public `LayoutTree.setState` and `Desk.setState` now reject `.closed` with `invariantViolated(...)`, the same way `DesktopLayer.setState` already did. The new internal `Desk.close(_:)` does the actual removal. Only `World.apply` and `UndoHistory.forget` call it. So nothing outside the module can close a window except through `apply`. Inside `edit`, `tree.remove` still works, because it is a real user edit and undo should restore it.
- I used the reviewer's alternative ("have `apply` purge regardless of the desk") rather than adding a separate public `close` method. Doc comments were updated in all four source files.

**Regression tests (in `UndoTests`):**
- `closingAWindowThatUndoTookOffEveryDeskStillPurgesHistory`: the reviewer's exact sequence (dock a and w on k1, remove w, insertRoot w on k2, undo k2, apply `.closed` on k1 and on k2, undo k1). Before the fix it failed with `windowNotFound`. After the fix, k1 restores to `[a]` without w.
- `closingIsAboutTheWindowNotTheDeskKey`: `apply(.closed, w, on: k1)` while w floats on k2 removes it from k2. Before the fix it failed with `windowNotFound`.
- `closingInsideAnEditIsRejectedSoUndoCannotReviveIt`: `edit { desk.setState(.closed, …) }` for a docked and a floating window, plus `edit { desk.tree.setState(.closed, …) }`. Each throws, and the world and history stay unchanged. Before the fix, nothing was thrown and the world and history changed (4 issues).

**Tests changed to match the new contract:**
- `applyToAnUnknownDeskOrWindowThrowsAndChangesNothing`: the `windowNotFound` check now uses `.absent`. A `.closed` for a window that no desk holds now succeeds and changes nothing.
- `LifecycleTests.closedRemovesTheSlotExactlyLikeRemove` is now `closedIsNotAStoredStateSoTheTreeRejectsIt`. The two `Desk` lifecycle tests now use `desk.close` and `tree.remove`.
- `TreeEditTests.closingAWindowWhoseMergeWouldPassMaxChildrenKeepsTheChildSplitNested` now uses `t.remove(b)`. It tests the same removal path that `.closed` takes.

**Not done (out of the given scope):** the reviewer's related gap. When undo restores a window that is on no desk, it keeps that window's stale lifecycle state from the snapshot.

#### WR-02: A World whose `ids.next` is at the new headroom bound loads, then rejects every edit

**Files modified:** `Sources/PaneModel/World.swift`, `Tests/PaneModelTests/PersistenceTests.swift`, `Tests/PaneModelTests/UndoTests.swift`
**Commit:** ac3dabc
**Applied fix:**
- The headroom guard moved out of `World.validate()` and into `World(ids:desks:)`, which is the load path (`init(from:)` calls it). The bound is now generous: `ids.next <= UInt64.max / 2`.
- `edit`, `apply` and `undo` still run `validate()` on every candidate, but it no longer checks headroom. During edits, only `IDSource.make()` throwing at `UInt64.max` stops them.
- `ids` is `private(set)` and the only other initializer is `init()`, so there is no other way to load a World.

**Regression tests:**
- Corpus case `ids.next one past the load headroom bound` (`.max / 2 + 1`). Before the fix it decoded without error, so the test failed.
- `UndoTests.aWorldAtTheLoadHeadroomBoundStillEditsUntilTheIDSourceRunsOut`: builds a World at `.max / 2` and edits it. One edit moves the ID source to `.max - 2` and docks a window. The next edit then throws `ID source exhausted` and leaves the World unchanged. Before the fix it failed with `invariantViolated("ID source 18446744073709551615 is too close to exhaustion")`.
- The existing corpus cases `ids.next = .max` and `.max - 100` are still rejected at load.

## Iteration 1

The source was the iteration-1 review. The full report is preserved at `01-REVIEW-FIX.iter2.md`. 10 in scope, 10 fixed, 0 skipped. Gates after iteration 1: 135 tests passing in debug and release, and the no-AppKit gate OK.

| ID | Title | Commit | Status | Applied fix |
|----|-------|--------|--------|-------------|
| CR-01 | Hostile `ids.next` near `UInt64.max` passes validation, then crashes on the first edit | dc69ec2 | fixed (the headroom bound was moved to load only in iteration 2, WR-02) | `IDSource.make()` throws instead of trapping; added a headroom check in `World.validate()` |
| CR-02 | `insert`'s depth guard measures the new leaf, not the subtree pushed deeper | e856741 | fixed | `insert` validates the whole candidate in every build |
| CR-03 | A lagging `IDSource` makes `insert` overwrite existing nodes | 475d7d2 | fixed | `insert` refuses a fresh ID that is already in the tree |
| WR-01 | A confirmed-closed window can be impossible to remove (`splitFull`) | b4e0fe3 | fixed: requires human verification | `normalize` keeps an overflowing same-axis child nested; `remove` throws only `windowNotFound` |
| WR-02 | One un-restorable snapshot blocks a desk's whole undo stack | ad5ab19 | fixed | `undo` pops before validating, so a stale snapshot is consumed |
| WR-03 | Lifecycle changes go on the undo stack, so undo brings back closed windows | 8c5a745 | fixed: requires human verification (completed in iteration 2, WR-01) | New `World.apply`, which pushes no snapshot; `.closed` forgets the window from history; undo carries the current states over |
| WR-04 | A migration step that produces a non-JSON value crashes with an NSException | 3bf9f1a | fixed | `isValidJSONObject` guard before `data(withJSONObject:)` |
| WR-05 | The no-AppKit gate is easy to bypass | 88c6853 | fixed | Regex covers `;`, attribute arguments, submodules, and the WebKit/Quartz/Carbon umbrellas |
| WR-06 | Test gap: `resolve` can ignore split weights | 5d8f831 | fixed | Exact unequal-weight test and fuzz property P9 |
| WR-07 | CI never builds or tests release | 9f6c2e5 | fixed | CI has the release build and test steps, plus a test that keeps them there |

---

_Fixed: 2026-10-24T07:23:53Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 3_
