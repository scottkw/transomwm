---
phase: 01-layout-model
fixed_at: 2026-10-24T06:29:48Z
review_path: .planning/phases/01-layout-model/01-REVIEW.md
iteration: 1
findings_in_scope: 10
fixed: 10
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Fixed at:** 2026-10-24T06:29:48Z
**Source review:** .planning/phases/01-layout-model/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 10 (3 critical, 7 warning; fix_scope = critical_warning, so IN-01..IN-07 were not attempted)
- Fixed: 10
- Skipped: 0

**Where verification ran:** in the main checkout, on branch `gsd/phase-01-layout-model`. No worktree was created, because the orchestrator said not to create or switch branches. These results can be reproduced from this tree.

**Final gate results (all run after the last commit):**
- `scripts/check-no-appkit.sh`: OK (11 files)
- `swift build`: complete
- `swift test`: 135 tests in 14 suites passed (baseline was 125)
- `swift build -c release`: complete
- `swift test -c release -Xswiftc -enable-testing`: 135 tests passed

**How "fails before the fix" was shown:** every regression test was run against the unfixed code before the fix was written:
- Behaviour fixes: the test failed, or crashed the test process where the bug is a trap or NSException.
- WR-03: the new tests did not compile before the fix, because the API did not exist yet.
- Test-gap fixes (WR-06): a mutation run. The reviewer's equal-share mutation now fails the new tests.

## Fixed Issues

### CR-01: Hostile `ids.next` near `UInt64.max` passes validation, then crashes the process on the first edit

**Files modified:** `Sources/PaneModel/IDs.swift`, `Sources/PaneModel/TreeEdits.swift`, `Sources/PaneModel/World.swift`, `Tests/PaneModelTests/InvariantTests.swift`, `Tests/PaneModelTests/PersistenceTests.swift`
**Commit:** dc69ec2
**Applied fix:**
- `IDSource.make()` now `throws(LayoutError)` (`invariantViolated("ID source exhausted")`) instead of calling `preconditionFailure`. Its 3 call sites in `insertRoot`/`insert` use `try`.
- `World.validate()` rejects `ids.next > UInt64.max - 2 * maxNodes`, so such a file fails at load with `.invalidLayout`.

**Regression:**
- 2 new corpus entries (`ids.next = UInt64.max` and `.max - 100`). Both decoded without error before the fix.
- `anExhaustedIDSourceThrowsInsteadOfTrapping`. Before the fix it trapped the test process (`IDs.swift:49: Fatal error: IDSource exhausted`, signal 5).
- `worldJSON(next:)` changed from `Int` to `UInt64` so the corpus can express the value.

### CR-02: `insert`'s depth guard measures the new leaf, not the subtree that rule 3 pushes one level deeper

**Files modified:** `Sources/PaneModel/TreeEdits.swift`, `Sources/PaneModel/LayoutTree.swift`, `Tests/PaneModelTests/InvariantTests.swift`
**Commit:** e856741
**Applied fix:**
- `insert` now runs `try next.validate()` on the whole candidate before it commits, in every build. This replaces the `nodes.count` and `depth(of: leaf)` guards and the trailing `assertValid()`.
- `depth(of:)` had no callers left and was deleted.

**Regression:** `layoutEdgeDropThatWrapsAFullDepthRootThrowsAndLeavesTreeUnchanged`: a 64-deep chain with a horizontal root, then `applyDrop(.layoutEdge(.top))`. Before the fix:
- release: no throw, the tree changed, and IDs were consumed (3 failed expectations);
- debug: trapped (`LayoutTree.swift:169: Fatal error ... tooDeep(limit: 64)`).

After the fix it passes in both configurations.

### CR-03: A lagging `IDSource` makes `insert` overwrite existing nodes; in release a window is silently dropped from the tree

**Files modified:** `Sources/PaneModel/TreeEdits.swift`, `Sources/PaneModel/LayoutTree.swift`, `Tests/PaneModelTests/TreeEditTests.swift`
**Commit:** 475d7d2
**Applied fix:**
- `insert` refuses a freshly made leaf or split ID that is already in the tree: `invariantViolated("ID source issued nX, which is already in the tree")`.
- The `LayoutTree` doc comment claimed every edit ends in `validate()`. It now says what is true: `init`, decoding and `insert` validate in every build, and the other edits add no nodes and check with `assertValid` in debug builds.

**Regression:** `anIDSourceThatLagsTheTreeThrowsInsteadOfOverwritingNodes` covers both collision paths: rule 1 reuses the leaf ID, rule 3 reuses the split ID. In each case the tree and the IDs stay unchanged. Before the guard, the CR-02 whole-tree validate already stopped the silent data loss, but only with the generic "reachable more than once" error. The test expects the specific collision error and failed against that code.

### WR-01: A confirmed-closed window can be impossible to remove (`setState(.closed)` throws `splitFull`)

**Files modified:** `Sources/PaneModel/LayoutTree.swift`, `Sources/PaneModel/TreeEdits.swift`, `Tests/PaneModelTests/TreeEditTests.swift`, `Tests/PaneModelTests/TreeFuzzTests.swift`
**Commit:** b4e0fe3
**Status:** fixed: requires human verification (this relaxes a tree invariant)

**Why not the reviewer's first suggestion:** relaxing the child cap does not work on its own. A flat split of more than 100 children cannot keep every weight at or above `minWeight` (0.01): 101 × 0.01 > 1, and `clamped` would return weights that sum to more than 1. Keeping the floor would mean changing `minWeight` everywhere.

**Applied fix (the reviewer's alternative, "keep the inner split"):**
- `normalize` skips any merge that would exceed `maxChildren` and leaves that same-axis child split nested. A later edit that makes room merges it as usual.
- `validate` accepts same-axis nesting only in exactly that overflow case.
- `normalize`/`collapseOrMergeOnce` no longer throw, so `remove` (and `.closed`) throws only `windowNotFound`.
- The layout does not move when B closes.

**Locked decision D-06 (merge same-axis children):** still applied wherever the merge can be represented. The one exception is a merge that could not produce a valid tree.

**Regression:**
- The old test `mergePastMaxChildrenThrowsAndChangesNothing` pinned the bug, and was replaced by `closingAWindowWhoseMergeWouldPassMaxChildrenKeepsTheChildSplitNested`. Before the fix it failed with `splitFull(n1, limit: 100)`. It also checks that removing 10 more outer windows triggers the delayed merge.
- `sameAxisNestingIsRejectedWhenTheMergeWouldFit` guards against loosening the axis rule too far.
- The fuzz invariant was updated to allow the same exception.

### WR-02: One un-restorable snapshot permanently blocks a desk's entire undo stack

**Files modified:** `Sources/PaneModel/World.swift`, `Tests/PaneModelTests/UndoTests.swift`
**Commit:** ad5ab19
**Applied fix:** `undo` now pops the snapshot before it validates. A snapshot that can no longer be restored still throws (for example `duplicateWindow`) and leaves the World unchanged, but it is consumed, so the next undo reaches the older entries. The doc comment was updated.

**Regression:** the old test (`...ThrowsAndChangesNothing`, which expected the depth to stay put) was rewritten as `undoThatWouldPutAWindowOnTwoDesksThrowsAndDiscardsOnlyThatSnapshot`. It checks that the depth drops by one and that the 2 older undos then succeed. It failed before the fix.

### WR-03: Observed lifecycle changes go on the user's undo stack, so undo brings back closed windows and overrides OS state

**Files modified:** `Sources/PaneModel/World.swift`, `Sources/PaneModel/Undo.swift`, `Tests/PaneModelTests/UndoTests.swift`, `Tests/PaneModelTests/ScenarioTests.swift`
**Commit:** 8c5a745
**Status:** fixed: requires human verification (this changes undo semantics)

**Decision:** undo covers user edits only. Lifecycle states reported by the OS (absent, fullscreen, present, closed) are facts, not user intent, so they never go on the undo stack and undo never overrides them. Locked decision "every edit pushes a snapshot" still holds for every user edit. OS reports are not treated as edits.

**Applied fix:**
- New `World.apply(_ state:, for:, on:, history:)`: routed through `Desk.setState`, validated like `edit`, all-or-nothing, and never pushes a snapshot.
- `.closed` also calls the new `UndoHistory.forget(window)`, which removes the window from every snapshot of every desk, so no undo can bring it back. Thanks to WR-01, removal from a valid snapshot cannot fail.
- `undo` copies each window's current lifecycle state (new `Desk.state(of:)`) into the restored snapshot, so a window that is currently absent or fullscreen stays that way.
- `edit` is documented as the way to make user edits.

**Regression:**
- `lifecycleChangesUseNoUndoLevelsAndUndoKeepsTheCurrentStates`
- `undoNeverBringsBackAClosedWindow`
- `applyToAnUnknownDeskOrWindowThrowsAndChangesNothing`

Before the fix these did not compile (no `apply`); the behaviour they cover is the one the reviewer's `resurrect` probe reproduced. Mutation checks: turning off the undo carry-over fails the first test, and turning off `forget` fails the second.

**Scenario test change:** `ScenarioTests.dropTabAbsentPresentUndoAndPersist` steps 5 and 6 now use `apply`. Its undo count went from 5 to 3, because only the 3 drops are user edits.

### WR-04: A migration step that produces a non-JSON value crashes the process with an uncaught NSException

**Files modified:** `Sources/PaneModel/Persistence.swift`, `Tests/PaneModelTests/PersistenceTests.swift`
**Commit:** 3bf9f1a
**Applied fix:** after migration, a `JSONSerialization.isValidJSONObject(object)` guard throws `.corrupt(...)` before `data(withJSONObject:)` can raise.

**Regression:** `migrationThatProducesANonJSONValueIsCorruptNotACrash` (a step that stores a `Date`). Before the fix it crashed the test process: `NSInvalidArgumentException ... Invalid type in JSON write (__NSTaggedDate)`, signal 6.

### WR-05: The no-AppKit gate (D-23) is easy to bypass

**Files modified:** `scripts/check-no-appkit.sh`, `Tests/PaneModelTests/NoAppKitTests.swift`
**Commit:** 88c6853
**Applied fix:** the regex now:
- matches an `import` at the line start or after `;`;
- accepts attributes with arguments (`@_spi(Private)`);
- ends the module name on any non-identifier character;
- also blocks the umbrella frameworks `WebKit`, `Quartz` and `Carbon`.

The robust check (`-emit-loaded-module-trace`, which also catches transitive imports) was not built. It is recorded as a `shortcut:` comment in the script.

**Regression:**
- 7 new violation lines: `import AppKit;`, `@_spi(Private) import AppKit`, `import Foundation; import AppKit`, `import AppKit.NSView`, `import WebKit`, `import Quartz`, `import Carbon`. Before the fix, 6 of them passed the check; `import AppKit.NSView` was already caught.
- 2 new clean lines, which still pass.

### WR-06: Test gap — `resolve` can ignore split weights entirely and all 125 tests still pass

**Files modified:** `Tests/PaneModelTests/ResolveTests.swift`, `Tests/PaneModelTests/ResolveFuzzTests.swift`
**Commit:** 5d8f831
**Applied fix:**
- New `unequalWeightsSplitTheLengthProportionally`: exact rects for H 0.3/0.7 with gap 0, and V 0.8/0.2 with gap 10.
- New fuzz property P9: in any placed split where no child's weighted share is below its minimum (so nothing is pinned), each non-last child's length is within 1 point of `available * w_i / Σw`.

**Regression:** a mutation run with the reviewer's equal-share mutation in `Resolve.swift:156`. It now fails the exact test and records 1613 fuzz issues. `Resolve.swift` was restored afterwards; the source is unchanged.

### WR-07: CI never builds or tests release, so all DEBUG-only invariant enforcement is untested where it matters

**Files modified:** `.github/workflows/ci.yml`, `Tests/PaneModelTests/NoAppKitTests.swift`
**Commit:** 9f6c2e5
**Applied fix:**
- Added the CI steps `swift build -c release` and `swift test -c release -Xswiftc -enable-testing`. The YAML parses (ruby) and every CI step was run locally and passes.
- CR-02 also removed the main debug/release difference: `insert` now validates in every build.

**Regression:**
- `ciBuildsAndTestsInReleaseToo` checks that the workflow keeps both release steps. It failed before the edit.
- The real release proof: the CR-02 test failed under `swift test -c release` before CR-02 and passes now.

---

_Fixed: 2026-10-24T06:29:48Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
