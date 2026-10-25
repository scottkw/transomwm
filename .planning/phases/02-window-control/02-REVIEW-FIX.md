---
phase: 02-window-control
fixed_at: 2026-10-25T17:53:19Z
review_path: .planning/phases/02-window-control/02-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 12
skipped: 0
status: all_fixed
---

# Phase 2: Code Review Fix Report

**Fixed at:** 2026-10-25T17:53:19Z
**Source review:** .planning/phases/02-window-control/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 12 (CR-01..04, WR-01..08; fix scope critical_warning)
- Fixed: 12
- Skipped: 0

**Where the fixes and the checks ran:** in the main checkout (`/Users/ken/dev/panewm`, branch `gsd/phase-01-layout-model`), not in an isolated worktree. The orchestrator's root-pin guard (`rootpin.sh`) has to pass before every commit, and it requires `git rev-parse --show-toplevel` to equal the pinned main checkout, which a worktree cannot satisfy. Every number below can be reproduced from that tree.

**Verification (main checkout, after the last fix):**
- `swift build`: complete.
- `swift test --skip PaneMacIntegrationTests`: 376 tests pass (142 + 74 + 160 across the three runs).
- `scripts/check-no-appkit.sh`: OK (24 files).
- `caffeinate -d -i swift test --filter PaneMacIntegrationTests`: 21 tests in 11 suites pass. One is skipped: `aWindowMovedOntoTheSecondDisplayReportsThatDisplay` needs two displays. The lockstate check said `locked: nil`. Afterwards no `PaneFixtureApp` process was left running.
- The new tests were run against the unfixed code. Where a unit test was feasible (CR-02, CR-03, CR-04, WR-04, WR-06), it failed there and passes with the fix. For CR-01 and WR-02 the test calls a new API, so it cannot compile against the old code (see those sections). WR-07 and WR-08 were checked by deliberately breaking the code under test (mutation checks, below).

## Fixed Issues

### CR-01: The probe loop exits on its first "not due yet" check

**Files modified:** `Sources/PaneEngine/ResponsivenessTracker.swift`, `Sources/PaneMac/AXWindowSystem.swift`, `Tests/PaneEngineTests/ResponsivenessTrackerTests.swift`
**Commit:** 37f4e40
**Status:** fixed: requires human verification (logic)
**Applied fix:** Added `ResponsivenessTracker.probeStep(pid:at:)`, which returns `.stop`, `.wait` or `.probe`. The probe loop in `startProbing` now stops only when the app is no longer degraded, and continues when a probe is not due yet. Test: `aLateResultAfterTheDegradeMakesTheProbeLoopWaitNotStop`. The loop itself is live-only code, so the test checks the decision it now uses. Because `probeStep` is new, the test cannot run against the old code.

### CR-02: An existing window that gains a native tab is tracked twice

**Files modified:** `Sources/PaneEngine/TabGroupTracker.swift`, `Sources/PaneEngine/WindowTracker.swift`, `Tests/PaneEngineTests/TabScenarioTests.swift`
**Commit:** d648966
**Status:** fixed: requires human verification (logic)
**Applied fix:** `TabGroupTracker.update` now takes the app's tracked identities, oldest first, through a new `tracked:` parameter. A new group adopts its oldest tracked standalone member as leader, so after Cmd-T the original window stays the group's identity: one window, `tabCount 2`, no create/destroy. A tracked standalone window that becomes a member of a group led by another identity (Merge All Windows, or dragging a window into an existing group) is returned in the new `TabResolution.folded`. `WindowTracker` then removes it and emits `windowDestroyed`. I chose a destroy event over a silent drop so that Phase 3 layout never keeps a tile for a window that no longer exists on its own. Please confirm this is the event you want. The window-removal code is now one shared `remove(_:at:)` helper. Tests: `aStandaloneWindowThatGainsATabStaysOneWindowLedByItself` (Cmd-T, then switching back to the original tab) and `mergingTwoTrackedWindowsLeavesOneGroupAndReportsTheOtherGone`.

### CR-03: Tab membership by bounds alone absorbs same-app twins

**Files modified:** `Sources/PaneEngine/TabGroupTracker.swift`, `Tests/PaneEngineTests/TabGroupTrackerTests.swift`
**Commit:** 5acd0e6
**Status:** fixed: requires human verification (logic)
**Applied fix:** A same-frame CG window can no longer become a hidden tab in two cases:
- It is listed in AXWindows without its own tab bar (`tabCount < 2`). This is the minimized twin.
- It is a tracked standalone window that was not listed in the previous update. This is the twin on another Space. The tracker now remembers each app's listed IDs from its last update (`lastListed`).

The review's suggested fix was to exclude every tracked standalone window. That would have undone CR-02, because the original window in the Cmd-T case is exactly that. The previous-refresh rule tells the two apart. Tests: `aListedMinimizedTwinWithTheSameFrameIsNeverAHiddenTab` (both AX orders), `aTrackedWindowOnAnotherSpaceWithTheSameFrameIsNeverAHiddenTab`, and `aTrackedWindowListedLastRefreshThatGainsATabLeadsTheGroup`. Known limit, recorded in a `Shortcut:` comment: a twin on another Space that was never tracked still passes as a hidden tab.

### CR-04: Any larger read-back is learned as a minimum and persisted per bundle

**Files modified:** `Sources/PaneEngine/MinimumSizeLearner.swift`, `Sources/PaneEngine/WindowTracker.swift`, `Tests/PaneEngineTests/MinimumSizeLearnerTests.swift`, `Tests/PaneEngineTests/FrameScenarioTests.swift`, `Tests/PaneMacTests/MinimumHintsStoreTests.swift`, `Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift`
**Commit:** 328d40d
**Status:** fixed: requires human verification (logic)
**Design choice:** a refusal is learned only once two consecutive read-backs agree.
- The learner keeps the last refused read-back for each window and axis, unconfirmed. A refused axis is one read back more than 2 pt above the request.
- That value is learned only if the next write's read-back is also refused on that axis and lands within 2 pt of it.
- Any other read-back on that axis clears the unconfirmed value.
- `applyFrameResult` skips learning entirely when the window is not `.present` (fullscreen or minimized).
- `onLearnedMinimum` fires only when the learned value changes, so the persisted per-bundle hint now needs two agreeing writes.

What this covers: a single stale read-back (an app that applies its size later), a snapped read-back that the next write contradicts, and writes to fullscreen windows. I did not add a cap at display bounds. Agreement is the simpler rule, and it also catches stale values smaller than the display. One limit remains: an app that snaps the same request to the same larger size every time still teaches that size after two identical writes.

**Tests:** `aRefusedSizeIsLearnedOnceASecondWriteAgreesAndAnHonouredOneChangesNothing`, `aStaleReadBackThatTheNextWriteContradictsTeachesNothing`, `twoRefusalsThatDisagreeTeachNothing`, `aFullscreenWindowLearnsNothing`. The tests that relied on single-write learning now write twice, including the live `aRefusedSizeIsReadBackAndLearned`, which now also checks that one read-back is not learned.

### WR-01: A failed CG window list silently becomes "no windows"

**Files modified:** `Sources/PaneMac/CGWindowList.swift`, `Sources/PaneMac/AXWindowSystem.swift`, `Sources/PaneMac/AX/AXSnapshotReader.swift`, `Sources/pane-dump/main.swift`, `Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift`
**Commit:** 69b3bb3
**Applied fix:** `CGWindowList.snapshot()` now returns `[CGWindowEntry]?` and logs when it returns nil. The callers handle nil as follows:
- `refresh` still records responsiveness, then skips the ingest (no close decision, no tab update) and reschedules the pid after the settle delay.
- A sweep whose snapshot failed lets each refresh read its own.
- `appStopped(terminated:)` marks the app terminated with an inactive context, so nothing closes, and leaves the decision to `recheckTerminatedSoon`, which skips any iteration with no list.
- The frame fallback leaves the element unidentified instead of giving it a synthetic ID.
- `pane-dump` exits with code 69.

There is no unit test: `CGWindowListCopyWindowInfo` cannot be made to fail from a test.

### WR-02: An app that stops being `.regular` without quitting leaves its windows tracked

**Files modified:** `Sources/PaneEngine/WindowTracker.swift`, `Sources/PaneEngine/TabGroupTracker.swift`, `Sources/PaneMac/AXWindowSystem.swift`, `Tests/PaneEngineTests/WindowTrackerTests.swift`
**Commit:** 8021d0a
**Status:** fixed: requires human verification (behaviour choice)
**Applied fix:** New `WindowTracker.appStopped(pid:)`. It drops the app's windows and emits `windowDestroyed` for each. It also clears the app's pending windows, rechecks, terminated mark and tab groups (new `TabGroupTracker.forget(pid:)`). `AXWindowSystem.appStopped` calls it on a non-terminated stop, so if the app becomes `.regular` again its windows come back as new ones. Test: `anAppThatStopsBeingTrackedLosesItsWindowsAndTheyComeBackAsNew`.

### WR-03: AX observer registration errors are ignored and never retried

**Files modified:** `Sources/PaneMac/AX/AXAppThread.swift`
**Commit:** ce05cb9
**Applied fix:** `installObserver` now checks every result. A failed `AXObserverCreate` leaves the observer nil, and app-level notifications that fail stay in an `unregistered` list. `.notificationAlreadyRegistered` counts as success. Both are retried at the start of every `observe()` until they succeed, and only the first failure is logged. An observer created late also registers the per-window notifications for windows already in the cache. Known limit, recorded in a `shortcut:` comment: a notification an app never supports is retried on every observe, at one IPC call each. There is no unit test because this needs a live app that is not AX-ready yet. The live suite exercised the normal registration path.

### WR-04: Frames already queued for an app are written after the app is excluded

**Files modified:** `Sources/PaneMac/AX/AXAppThread.swift`, `Sources/PaneMac/AXWindowSystem.swift`, `Sources/PaneTestSupport/FakeWindowSystem.swift`, `Tests/PaneEngineTests/ExclusionScenarioTests.swift`
**Commit:** fc1a8e1
**Applied fix:** `AXAppThread` now has an `excluded` flag, kept under the frame lock. Setting it:
- empties the slots, including frames held while the app was degraded;
- makes `enqueueFrame` refuse new frames, and `claimDrain` refuse to schedule a drain;
- makes `drainFrames` stop before its next write.

It also stops a write the app did not answer from being put back in its slot. `setExcludedBundleIDs` sets the flag on every thread, and new threads start with it. `FakeWindowSystem.setExcluded` drops held frames the same way. Test: `aFrameHeldForAHungAppIsNeverWrittenOnceTheAppIsExcluded`, which failed before the fake fix. The live half of the fix has no unit-level test.

### WR-05: Windows whose `_AXUIElementGetWindow` fails are silently never tracked

**Files modified:** `Sources/PaneMac/AX/AXSnapshotReader.swift`, `Sources/PaneEngine/WindowTracker.swift`
**Commit:** c6718a8
**Applied fix:** When the private lookup fails for an element and the capability is still on, the element now goes through the frame fallback: cache, then CG frame match, then a synthetic ID. Before, it got no ID. Non-windows still get nil from the fallback's role check, and the failure still counts towards switching the capability off. IDs the lookup does return are bound, so the fallback cannot reuse them. The stale "Plan 11" comment in `WindowTracker` is updated. Known limit, recorded in a `shortcut:` comment: only IDs bound before the failing element are excluded from its match. There is no unit test because the private API cannot be made to fail for one element from a test.

### WR-06: `applyFrameResult` updates the frame but not `displayUUID`

**Files modified:** `Sources/PaneEngine/WindowTracker.swift`, `Tests/PaneEngineTests/TrackerDisplayTests.swift`
**Commit:** 0138c57
**Applied fix:** The tracker keeps the displays from the latest `ingest` context. `applyFrameResult` recomputes `displayUUID` from the read-back and emits `windowChanged` when it changes. Test: `aWriteThatMovesTheWindowToBReportsBAtOnce`, which failed before the fix.

### WR-07: The lock and hang scenario tests cannot catch a broken gate or tracker path

**Files modified:** `Sources/PaneTestSupport/FakeWindowSystem.swift`, `Tests/PaneEngineTests/CloseScenarioTests.swift`
**Commit:** d410714
**Applied fix:**
- New fake mode `setLocked(_:gate:axInvalid:)`. The CG list is blank, AXWindows answers with no windows, and every known window answers -25202.
- `lockBlankingClosesNothing` now runs in both the timeout mode and the -25202 mode.
- New test `withoutTheGateABlankingThatAnswersInvalidClosesEverything`: with `gate: false`, all 10 windows are destroyed.
- The fake now ingests a hung app's failed observation, as `AXWindowSystem` does. Held frames are still flushed only once the app is responsive.

**Mutation check:** I broke the code under test twice. Each time the right tests failed, and the original code was restored afterwards.
- Removing `CloseRule`'s `guard sessionActive` makes `lockBlankingClosesNothing(axInvalid:)` fail.
- Making a timeout return `.closed` makes `aHungAppNeverLosesAWindowOverFiveRefreshes` fail. Before this fix, that test would still have passed under the same change.

### WR-08: The burst-coalescing integration test cannot fail on coalescing

**Files modified:** `Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift`
**Commit:** 95f1d91
**Applied fix:** `aBurstOfFramesEndsAtTheLatest` is replaced by `aBurstQueuedWhileTheDrainIsHeldWritesOnlyTheLatest`. It drives the fixture's `AXAppThread` directly through `@testable import PaneMac`, with no new production seam. The test:
1. observes, to fill the element cache;
2. sets `drainEnabled = false` and enqueues 10 frames;
3. re-enables the drain;
4. expects exactly one `FrameWriteResult`, whose `requested` is the last frame, and the fixture ending at x ≈ 190.

**Mutation check:** I gave every frame its own slot, which removes latest-wins, and ran the live test. It failed on `results.count == 1`, and the original code was restored afterwards.

---

_Fixed: 2026-10-25T17:53:19Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
