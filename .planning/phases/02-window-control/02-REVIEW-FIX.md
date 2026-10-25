---
phase: 02-window-control
fixed_at: 2026-10-25T18:16:11Z
review_path: .planning/phases/02-window-control/02-REVIEW.md
iteration: 2
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 2: Code Review Fix Report

**Fixed at:** 2026-10-25T18:16:11Z
**Source review:** .planning/phases/02-window-control/02-REVIEW.md (re-review, iteration 2)
**Iteration:** 2

**Summary:**
- Findings in scope: 4 (CR-01, WR-01..03; fix scope critical_warning; IN-01..10 not in scope)
- Fixed: 4
- Skipped: 0

**Where the fixes and the checks ran:** in the main checkout (`/Users/ken/dev/panewm`, branch `gsd/phase-01-layout-model`), not in an isolated worktree. As in iteration 1, the root-pin guard (`rootpin.sh`) must pass before every commit, and it requires the main checkout as the git toplevel. Every number below can be reproduced from that tree.

**Verification (main checkout, after the last fix):**
- `swift build`: complete.
- `swift test --skip PaneMacIntegrationTests`: 382 tests pass (142 + 74 + 166). Iteration 1 ended at 376.
- `scripts/check-no-appkit.sh`: OK (24 files).
- `caffeinate -d -i swift test --filter PaneMacIntegrationTests`: 22 tests in 11 suites pass. One is skipped: `aWindowMovedOntoTheSecondDisplayReportsThatDisplay` needs two displays. The lockstate check said `locked: nil`. Afterwards `pgrep -fl PaneFixtureApp` found nothing.
- Every new test was run against the unfixed code first and failed there (CR-01, WR-01, WR-02). For two pieces of the CR-01 fix I also did mutation checks: each time I removed one rule, its test failed, and I restored the code afterwards. WR-03 has no test (see that section).

## Fixed Issues

### CR-01: A Space switch folds an unrelated same-frame window into a tab group

**Files modified:** `Sources/PaneEngine/TabGroupTracker.swift`, `Tests/PaneEngineTests/TabScenarioTests.swift`, `Tests/PaneEngineTests/TabGroupTrackerTests.swift`
**Commit:** dfc57d1
**Status:** fixed: requires human verification (logic)
**Applied fix:** `TabGroupTracker.update` changes in three ways:
- **Hidden tabs are capped by `AXTabs`.** A group takes at most `tabCount - 1` hidden tabs. They are picked in tiers:
  1. the group's own known members;
  2. untracked windows that belong to no group;
  3. tracked standalone windows and members of other groups, only to fill the count.

  This is why Cmd-T still adopts the original window: with tabCount 2 and no other candidate, it is the only way to fill the slot.
- **The binding check at line 81 now depends on `tabCount`.** Before binding, a window listed with `tabCount < 2` is removed from any group that still has other members, unless it is that group's leader or its last-shown tab. Each group now records its shown tab in a new `Group.shown` field. So a single listed window no longer takes over a group's identity.
- **A new tab joins an existing group only if that group has room** under the tab's `AXTabs` count. Two same-frame tab groups on different Spaces therefore stay two groups.

The "not listed at the last refresh" rule from iteration 1 is kept as an extra filter.

**Tests:** Review scenarios S4, S5 and S6 now run on the fake through real Space switches. A new `showSpace` helper lists, and shows onscreen, only the windows of the current Space. Each scenario runs several refreshes and settle delays:
- `aTrackedWindowNeverLeadsAGroupOnAnotherSpaceWithTheSameFrame` (S4)
- `aWindowOnAnotherSpaceWithTheSameFrameIsNeverFoldedIntoAGroup` (S6)
- `anUntrackedTwinOnAnotherSpaceLeavesTheGroupOnceItIsListed` (S5)

Each one asserts two tracked windows with the right `visibleMemberID` and `tabCount`, and no `windowDestroyed`. A new unit test, `aSameFrameGroupOnAnotherSpaceIsAGroupOfItsOwn`, covers the "room under the count" rule.

The CR-02 Cmd-T test, the merge test and the CR-03 minimized-twin test still pass unchanged. The reviewer's harness (`probe2`) now prints two stable windows at every step of S4, S5 and S6.

**Mutation checks:**
- Dropping the room check fails the new unit test.
- Dropping the strip of listed single windows fails S5.

**Residual limits** (recorded in a `shortcut:` comment):
- The Spaces API is not in PanePrivate (it contains only `AXWindowID` and `Capabilities`). So an untracked same-frame twin on another Space can still fill a free slot of a group seen first. This is S5's first step. It corrects itself the first time the twin is listed on its own Space.
- Suppose a 2-tab group has lost its leader, and the user closes the shown tab. The remaining tab rebinds only once WindowServer drops the closed tab from the CG list. If that takes longer than the 250 ms settle delay, the remaining tab is briefly reported as a window of its own.

### WR-01: Two back-to-back stale read-backs still teach a permanent per-bundle minimum

**Files modified:** `Sources/PaneEngine/WindowTracker.swift`, `Sources/PaneEngine/MinimumSizeLearner.swift`, `Tests/PaneEngineTests/FrameScenarioTests.swift`, `Tests/PaneEngineTests/MinimumSizeLearnerTests.swift`, `Tests/PaneMacTests/MinimumHintsStoreTests.swift`, `Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift`
**Commit:** 0c148fb
**Status:** fixed: requires human verification (logic, and a behaviour choice)
**Applied fix:** `applyFrameResult` no longer learns from a read-back whose size equals the window's size before the write (both axes, within 2 pt). That read-back comes from a busy or late-applying app.

**Design choice: please confirm.** A read-back still at the pre-write size looks exactly like a window that is already at its minimum. So the confirming refusal now has to come from a larger frame. Under the iteration 1 rule, any honoured read-back dropped the unconfirmed refusal. With the new skip, Pane-driven layout would almost never learn: every refusal episode yields one usable read-back, and the honoured write between episodes erased it.

So the learner now drops an unconfirmed refusal only when a read-back contradicts it:
- a refusal at a different size, or
- an honoured size below it.

An honoured write at or above it keeps it. The sequence that teaches is now: refuse, honour a larger frame, refuse again at the same size.

I did not add the review's optional cap of the persisted hint at the display size.

**Tests:**
- New: `readBacksStillAtThePreWriteSizeTeachNothing` (failed before the fix) and `anHonouredWriteAtOrAboveARefusalKeepsItAndOneBelowDropsIt`.
- Changed to the refuse, honour, refuse sequence, because they confirmed with two identical back-to-back writes: `aReadBackFrameMovesAndResizesAndASecondAgreeingOneLearns`, `theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsIt`, `aClosedWindowsLearnedMinimumIsForgotten`, `aNewWindowStartsFromItsBundlesHintAndLearningOnlyRaisesIt`, and the live `aRefusedSizeIsReadBackAndLearned`.

The live test passes against the fixture.

### WR-02: A window first identified by the fallback changes identity when the private lookup next succeeds

**Files modified:** `Sources/PaneMac/AX/AXSnapshotReader.swift`, `Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift`
**Commit:** f43f5fd
**Applied fix:** `windowID(of:)` now checks the app thread's element cache (`CFEqual`) before it calls `_AXUIElementGetWindow`. An element keeps whatever ID it was first given (synthetic, CG match or private) for as long as it stays cached. So a fallback ID never turns into the real ID, which would add a second window. The cache check inside `Fallback.identify` was moved up into `windowID(of:)`.

**Side effect:** a cached element no longer calls the private lookup, so it no longer calls `Capabilities.recordSuccess` either. Failures are still counted for every new element.

**Test:** the fake cannot model AX elements or the private lookup, so the new test is a live, reader-level one: `anElementCachedUnderAFallbackIDKeepsItWhenTheLookupLaterSucceeds` in `FallbackIntegrationTests`, which now uses `@testable import PaneMac`. It works like this:
1. Seeds the cache with the fixture's real window element under a synthetic ID.
2. Calls `AXSnapshotReader.observeApp` with the private lookup available.
3. Asserts that the element is still reported, and cached, under the synthetic ID.

Before the fix, it returned the real ID.

### WR-03: Per-window AX registrations are unchecked, and without an observer the element cache never fills

**Files modified:** `Sources/PaneMac/AX/AXAppThread.swift`
**Commit:** 604f6f3
**Applied fix:** `updateWindows` now always stores the new cache. So frame writes, and probes of known windows that left AXWindows, work while `AXObserverCreate` keeps failing.

Each newly cached window starts with all six per-window notifications pending, in a new `unregisteredWindows` map. Once an observer exists, `updateWindows` registers the pending ones on every `observe()`. A notification leaves the list on `.success`, `.notificationAlreadyRegistered` or `.notificationUnsupported`; an unsupported one never will register. Any other error stays pending and is retried on the next observe. Only the first failure is logged, through the existing `logRegistrationFailure`. A window that leaves the cache drops its pending list.

This replaces the "observer created late" loop in `installObserver`. That loop only ever saw an empty cache, because the cache never filled without an observer.

**Test:** none. Making `AXObserverCreate` or a per-window registration fail needs a live app that is not AX-ready yet, so this fix is checked by reading the code only. The live suite exercised the normal registration path: close, move and tab tests all pass.

## Iteration 1 (summary)

The first pass fixed 12 findings: CR-01..04 and WR-01..08 of the original review. The commits were 37f4e40, d648966, 5acd0e6, 328d40d, 69b3bb3, 8021d0a, ce05cb9, fc1a8e1, c6718a8, 0138c57, d410714 and 95f1d91.

- **CR-01:** the probe loop no longer exits on its first "not due yet" check (`probeStep`).
- **CR-02:** Cmd-T keeps one window led by the original. A merged window is reported destroyed through `TabResolution.folded`.
- **CR-03:** a same-frame twin is rejected as a hidden tab if it is listed without a tab bar, or if it is tracked but was not listed at the last refresh. Iteration 2's CR-01 above completes this.
- **CR-04:** a refusal is learned only when two read-backs agree, and never for a non-present window. Iteration 2's WR-01 above tightens this.
- **WR-01:** a failed CG list is nil and never "no windows".
- **WR-02:** a stopped app's windows are dropped (`appStopped`).
- **WR-03:** app-level AX registrations are checked and retried. Iteration 2's WR-03 above completes this.
- **WR-04:** an `excluded` flag under the frame lock stops queued writes.
- **WR-05:** a failed private lookup falls back to the frame match. Iteration 2's WR-02 above fixes the identity flip this caused.
- **WR-06:** a frame write updates `displayUUID`.
- **WR-07:** the lock and hang tests can now fail: there is a -25202 lock mode, and the hung app's observation is ingested.
- **WR-08:** the burst test holds the drain and expects exactly one write.

---

_Fixed: 2026-10-25T18:16:11Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
