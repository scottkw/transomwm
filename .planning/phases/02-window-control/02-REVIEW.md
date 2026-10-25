---
phase: 02-window-control
reviewed: 2026-10-25T18:26:48Z
depth: standard
iteration: 3
diff_base: 3b02c4a
files_reviewed: 12
files_reviewed_list:
  - Sources/PaneEngine/MinimumSizeLearner.swift
  - Sources/PaneEngine/TabGroupTracker.swift
  - Sources/PaneEngine/WindowTracker.swift
  - Sources/PaneMac/AX/AXAppThread.swift
  - Sources/PaneMac/AX/AXSnapshotReader.swift
  - Tests/PaneEngineTests/FrameScenarioTests.swift
  - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
  - Tests/PaneEngineTests/TabGroupTrackerTests.swift
  - Tests/PaneEngineTests/TabScenarioTests.swift
  - Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift
  - Tests/PaneMacTests/MinimumHintsStoreTests.swift
findings:
  critical: 1
  warning: 4
  info: 12
  total: 17
status: issues_found
---

# Phase 2: Code Review Report (re-review, iteration 3)

**Reviewed:** 2026-10-25T18:26:48Z
**Depth:** standard
**Files Reviewed:** 12 (the fix diff `3b02c4a..0fb6481` and the files it touches; HEAD `72e9489` adds only planning docs on top)
**Status:** issues_found

## Summary

I read the full fix diff and every file it touches. I also read the code it calls: `Capabilities`/`CapabilitySession`, `FallbackMatcher`, and `AXWindowSystem.withSyntheticPresence`. `swift test --skip PaneMacIntegrationTests` passes: 382 tests (142 + 74 + 166). I did not run the live integration tests.

I re-ran the earlier harness (`/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe2/`) against the current code. I also wrote new scenarios that drive the real `WindowTracker` and `TabGroupTracker`: `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe3/Sources/Probe3/main.swift` (tabs) and `.../probe3/Sources/Probe3c/main.swift` (learner).

Status of the iteration-2 findings:

| Finding | Status |
|---|---|
| CR-01 Space switch folds a same-frame window into a group | **Partially resolved.** S4, S5 and S6 now give two stable windows at every step (probe2). Cmd-T with no twin, merge and the minimized twin still behave correctly (probe3 C1, C3, C4). But the tier order, "untracked before tracked standalone", picks a twin from another Space over the real hidden tab. With Cmd-T, that tracks one window twice and later reports a live window destroyed. It can also merge two tab groups from two Spaces for good. See the new CR-01. |
| WR-01 two stale read-backs teach a minimum | **Resolved for the stated case.** A read-back still at the pre-write size is skipped, and constant-speed or lag-2 back-and-forth sequences learn nothing (probe3c). The new semantics have two side effects: see WR-01 and WR-02 below. My iteration-2 fix suggestion caused part of WR-01. |
| WR-02 fallback ID flips to the real ID | **Resolved.** The cache is checked first, so a cached element keeps its ID. But the change has two side effects: see WR-03 and WR-04. |
| WR-03 per-window registrations unchecked, no cache without an observer | **Resolved** (checked by reading the code). `windows = current` always runs. Pending per-window notifications are retried on every observe and dropped on success, already-registered or unsupported. The new code still has no test: see IN-11. |
| IN-01..IN-10 | Carried forward, still open. Line references updated where the code moved. |

## Critical Issues

### CR-01: An untracked same-frame window on another Space wins the hidden-tab slot over the real tab. Cmd-T then tracks one window twice and later reports a live window destroyed, and two same-frame groups merge for good

**File:** `Sources/PaneEngine/TabGroupTracker.swift:87-98, 92, 69`, `Sources/PaneEngine/WindowTracker.swift:63-66`

**Issue:** `tier()` (lines 94-97) ranks the candidates as: own members 0, untracked windows 1, tracked standalone windows and other groups' members 2. Ties are broken by window ID. AX lists only the current Space, so every window on a Space not visited since Pane launched is untracked. It therefore beats the window that really just became a tab. These results come from the real tracker (probe3):

- **C2: Cmd-T with an untracked twin.** A (10) is tracked, and Z (5 or 50) sits in the same slot on Space 2 and has never been listed. Cmd-T in A creates N (40), and A becomes the hidden tab. The candidates are A (tier 2) and Z (tier 1), and `prefix(1)` takes Z. So A is not a member. A stays tracked as a separate window, and N is created as a second window. That is the iteration-1 CR-02 bug again. Next the user visits Space 2: Z is listed, tracked, and removed from the group by the listed-single rule. When the user comes back, A fails `canBeHiddenTab`: A is tracked but was not listed at the last refresh. Z was listed at the last refresh, so it qualifies, gets picked, lands in `folded` and is reported destroyed:
  ```
  C2 cmdT:     [(10, 10, 1), (40, 40, 2)]      created 40         // one window tracked twice
  C2 ->sp2:    [(5, 5, 1), (10, 10, 1), (40, 40, 2)]   created 5
  C2 ->sp1:    [(10, 10, 1), (40, 40, 2)]      DESTROYED 5         // Z is alive on Space 2
  ```
  The same happens with Z = 50, so it does not depend on ID order.
- **C5: two same-frame tab groups on two Spaces.** G1 is 30 (shown) + 31 and is seen first. G2 is 10 + 11 on the other Space. G1's candidates are 31, 10 and 11, all tier 1, and the lowest ID wins, so G1 = {30, 10}. Switching to Space 2 lists 10 with `tabCount 2`. Line 91 (`members.contains(v.id)`) binds 10 to G1 before the room check is reached, and the listed-single strip does not apply because `tabCount` is 2. G2 is never tracked. G1's identity alternates between 30 and 10 on every Space switch, permanently:
  ```
  C5 ->sp2: [(30, 10, 2)]   C5 ->sp1: [(30, 30, 2)]   C5 sp1 again: [(30, 30, 2)]
  ```
  The shortcut comment (lines 31-33) says an untracked twin "can fill a free slot until it is first listed on its own Space". That holds only for a twin without a tab bar. A twin that is itself a group never corrects itself. Roughly half of all such pairs hit this, whenever the older group (lower IDs) is on the other Space.
- **C7: Cmd-T joins a group on another Space.** Group T (30 + 31) is first seen on Space 2 while A (10) waits untracked in the same slot on Space 1. T picks 10 instead of 31 (lowest ID). On Space 1, A is listed as a single, so the strip (line 69) removes it, and T drops to {30} with `tabCount 1`. 31 is never a member. Cmd-T in A then lists N (40, `tabCount 2`). T now seems to have room (`members.count 1 < 2`, line 92), and T's shown tab 30 is an offscreen candidate, so N joins T. T's identity now shows a tab on Space 1, while A stays tracked as a separate phantom window:
  ```
  C7 init sp2: [(30, 30, 2)]   ...   C7 cmdT: [(10, 10, 1), (30, 40, 2)]   C7 ->sp2: [(10, 10, 1), (30, 30, 2)]
  ```

Same-frame windows of one app on different Spaces are the normal case in a tiling manager: every single-tile or maximized layout shares a frame. This is the same class of failure the previous CR-01 was a blocker for: a live window reported destroyed, or one tracked window standing for two real ones. The new tests do not cover it. `aTrackedWindowNeverLeadsAGroupOnAnotherSpaceWithTheSameFrame`, `aWindowOnAnotherSpaceWithTheSameFrameIsNeverFoldedIntoAGroup` and `anUntrackedTwinOnAnotherSpaceLeavesTheGroupOnceItIsListed` use only standalone twins and never press Cmd-T while a twin is untracked.

S4 and C2 give `update()` the same inputs: one tracked standalone window that was listed last refresh, plus one untracked offscreen same-frame window. Only the right answer differs: 31 in S4, A in C2. So no reordering of the tiers can fix both. Two facts can tell them apart.

**Fix:**
1. **CG history (pure, no private API).** Keep the previous refresh's CG ID set per pid. A shown tab that was not in the CG list before is a brand-new window (Cmd-T, or New Tab). For it, prefer a tracked standalone window that was listed last refresh over untracked windows. A shown tab that was already in the CG list (offscreen) is a Space switch or a tab switch. For it, keep the current order:
   ```swift
   let isNewWindow = !(lastCG[pid] ?? []).contains(v.id)
   func tier(_ id: UInt32) -> Int {
       if own.contains(id) { return 0 }
       let isStandalone = standalone.contains { $0.windowID == id }
       if isNewWindow, isStandalone, wasListed.contains(id) { return 1 }   // Cmd-T: the window that just became a tab
       return isStandalone || list.contains { $0.members.contains(id) } ? 3 : 2
   }
   ```
2. **The Spaces API for C5 and C7.** No ordering rule can choose between 31 and 10 the first time a group is seen. Exclude candidates whose Space differs from the shown tab's: `SLSCopySpacesForWindows` behind a `PanePrivate` shim, falling back to today's behaviour.
3. **Limit the damage until then.** Only destroy a `folded` window if it stayed a member across two refreshes where it was not listed and the group's shown tab was unchanged. Also, a listed `tabCount >= 2` window that binds an existing group through line 91 should rebind only if that group's previous shown tab is no longer offscreen-but-present, or if the counts agree.

Add C2, C5 and C7 as `TabScenarioTests` using `showSpace`.

## Warnings

### WR-01: A refused size is never learned while the layout stays put, and a window already at its minimum never learns at all (side effect of the WR-01 fix)

**File:** `Sources/PaneEngine/WindowTracker.swift:211-215`, `Sources/PaneEngine/MinimumSizeLearner.swift:34-41`

**Issue:** The `unchanged` skip throws away exactly the read-back that confirms a real minimum: a second write to a window that is already clamped. Results from the real tracker (probe3c):
- The window is at 800, and the layout asks for 300 five times. Only the first read-back (500) is recorded as unconfirmed. The other four read back 500, which equals the pre-write frame, so they are skipped. `learnedMinimum` stays nil.
- The window opens at its 500 minimum, and the layout asks for 300. Every read-back is "unchanged", so not even an unconfirmed refusal is stored.

A refusal is learned only if the tile shrinks, grows to a size the app honours, then shrinks again. So the most common case never teaches anything: Pane puts a window into a too-small tile and leaves it there. For Phase 3, the window then overlaps its neighbour (the Core Value) until the user rearranges twice. Under iteration 1, the second identical write confirmed it.

In iteration 2 I suggested comparing against the pre-write frame without seeing this consequence. The fixer's "honoured at or above keeps it" rule only rescues the oscillating case.

**Fix:** Separate a stale read-back from a clamped one by time, not by the frame before the write. Keep an "unchanged" read-back as pending, and confirm it when a later AX refresh, at least `settleDelay` after the write, still reads the window at that size. A late-applying app will have caught up by then. A clamped window has not. For example, `WindowTracker.ingest` calls `learner.confirmPending(identity, observed: frame.size, at: now)`. Add a test where the window stays clamped for three writes and one refresh, and expect it to learn.

### WR-02: A deterministic snap that rounds up by more than 2 pt is still learned and persisted per bundle, now even across honoured writes

**File:** `Sources/PaneEngine/MinimumSizeLearner.swift:5-12, 34-41`

**Issue:** The doc comment says confirmation protects against "a snap", but a deterministic snap gives two agreeing read-backs by construction. With "an honoured write at or above it keeps it", any honoured write can sit between the two refusals. Take an app that snaps height to the nearest 16-pt row (probe3c, `snapH`). It is asked for 510 and reads back 518, asked for 790 and reads back 790 (honoured, so 518 is kept), asked for 510 again and reads back 518. Result: `learnedMinimum == (0, 518)`. That is a tiling layout switching a tile between two heights, which happens all the time. The value then goes to `MinimumHintsStore` (max only, no decay) and seeds every window of the bundle, which blocks any split below 518 pt for that app permanently. The "terminals snap down" assumption (line 11) covers only round-down grids.

**Fix:** Treat a refusal as a minimum only when it holds against requests that differ. Require the two agreeing refusals to come from requests at least `2 * tolerance` apart, with the read-back above both. A snap follows the request, so it reads back differently; a real minimum does not. Or cap a persisted hint at the smallest frame ever honoured for that window minus `tolerance`.
```swift
// in axis(): confirm only if this request is clearly different from the one that produced `last`
if let last, abs(actual - last.value) <= Self.tolerance, abs(requested - last.requested) > 2 * Self.tolerance { learned = max(learned, actual) }
```

### WR-03: Cached elements no longer report successes, so a single failing element can switch `_AXUIElementGetWindow` off for the whole session (side effect of the WR-02 fix)

**File:** `Sources/PaneMac/AX/AXSnapshotReader.swift:81-92, 110-113`, `Sources/PanePrivate/Capabilities.swift:95-114`

**Issue:** `CapabilitySession` switches the capability off after `failureLimit = 5` *consecutive* failures, process-wide. Only `recordSuccess` resets the count. Before this fix, every refresh looked up every listed element, so the normal windows of the swept apps reset the count all the time. Now line 81 returns cached elements before the lookup runs, so in steady state no success is ever recorded:
- An `AXWindow` element whose lookup fails and that `Fallback.identify` cannot place is not cached. That happens when its frame is unreadable (line 111) or the CG list is nil (line 113). Its lookup then runs again on every refresh and records one failure each time, with no success in between. Five sweeps (about 25 s) switch the private lookup off for every app for the rest of the session, and every new window falls back to frame matching.
- The counter also builds up across the session from new windows whose lookup fails during creation (the WR-05 case). It is only reset when a new element somewhere succeeds.

**Fix:** Count at most one failure per element. Keep a per-thread negative cache of elements that have already failed, matched by CFEqual. Or have `observeApp` record one success per refresh when any cached `.axPrivate` element exists, since that ID came from a working lookup. Or switch off only when failures outnumber successes over a window of distinct elements. Add a `CapabilitySession` test: one element fails five times while other elements stay cached, and the capability must stay on.

### WR-04: A fallback ID chosen during a brief lookup failure now lasts for the window's life, including a wrong frame match to another window's CG ID (side effect of the WR-02 fix)

**File:** `Sources/PaneMac/AX/AXSnapshotReader.swift:79-81, 115-123`, `Sources/PaneEngine/FallbackMatcher.swift:17-30`

**Issue:** The cache-first check never re-checks an element whose cached source is `.synthetic` or `.cgFrameMatch`, even once the lookup works for it:
- **Synthetic.** The window keeps only the bounds-based presence of `withSyntheticPresence` for its whole life. Its close decision depends on whether a same-pid CG entry with its bounds still exists. Phase 4's windowID-to-`SCWindow` mapping can never capture it.
- **Wrong `.cgFrameMatch`.** A new window E whose lookup fails while it is not yet in the CG snapshot (the WR-05 case) can match a same-frame, offscreen, untracked window of the same app: a twin on another Space, or a hidden tab. `FallbackMatcher` returns the one offscreen candidate. E then carries the twin's real CG ID for good. Once the twin is listed, its own lookup returns the same ID, so two elements share one ID in `byID`, and E's identity takes the twin's frame and title. On E's Space, E's element has dropped out of the cache, so it gets its real ID as a second window. While the twin lives, a closed E keeps hitting `.recheck`, because its ID stays in the CG list.

Before iteration 2, the next successful lookup corrected this (at the cost of the duplicate in old WR-02).

**Fix:** For cached elements whose source is not `.axPrivate`, still call the lookup while it is available. If it returns R and R equals the cached ID, or the cached ID is synthetic and R is not tracked, re-key explicitly. That needs a tracker API such as `rekey(from:to:)` that moves `WindowInfo`, learner state and tab membership without emitting created or destroyed. If R differs from a cached `.cgFrameMatch` ID, the match was wrong: re-key to R. Separately, when the lookup is available but fails for a new element, don't accept an offscreen-only frame match on that pass. Wait one refresh, since the window is held for the settle delay anyway.

## Info

### IN-01: `ClosedIDCache` is dead state, and its doc comments are swapped

**File:** `Sources/PaneEngine/CloseRule.swift:60-85`, `Sources/PaneEngine/WindowTracker.swift:19, 47, 132, 292`

**Issue:** The tracker writes the cache but nothing reads it: `contains` is only called from tests. The comments are also swapped: "True while `now < closed + ttl`" sits above `remove`, and "The ID is a live window again." sits above `contains`.

**Fix:** Delete `ClosedIDCache` and its tests, or use it. Either way, fix the comments.

### IN-02: The menu header count and Tracked Windows use different window filters

**File:** `Sources/PaneMac/Shell/StatusItemController.swift:99-100` vs `Sources/PaneMac/Shell/TrackedWindowsModel.swift:37, 77`

**Issue:** The header counts every inventory window, while Tracked Windows filters out `.closed`. They match today only because the tracker never stores `.closed`.

**Fix:** Use one filter in both places.

### IN-03: The `where` clause in `PermissionReducer` guards only the second pattern

**File:** `Sources/PaneEngine/PermissionReducer.swift:110`

**Issue:** `where state.showStaleFormB` applies only to `(.waitingForGrant, .resetClicked)`, and the release build warns about it.

**Fix:** Split it into two `case` labels, or make the intent explicit.

### IN-04: Learned bundle hints only seed windows after a relaunch

**File:** `Sources/PaneMac/PaneMacApp.swift:36-44`, `Sources/PaneEngine/WindowTracker.swift:123-126, 201-203`

**Issue:** `setBundleHints` is called once at launch. `onLearnedMinimum` updates the store but not the tracker.

**Fix:** After `hints.record(...)`, call `system.setBundleHints(hints.hints)`. Fix WR-02 first, so a snap hint does not spread within the session.

### IN-05: A comment contradicts how sweep refreshes order the AX and CG reads

**File:** `Sources/PaneMac/AXWindowSystem.swift:202, 225-226`

**Issue:** The comment says the CG list is read after AX answered. A sweep takes one CG snapshot before any AX job.

**Fix:** Correct the comment, or take the CG snapshot per pid after `observe`.

### IN-06: Starting while locked marks the initial refresh complete without one

**File:** `Sources/PaneMac/AXWindowSystem.swift:107-115, 400-414`

**Issue:** `initialRefreshComplete` is set even when every `refresh` returned early because the gate was paused. Windows that already existed are then reported as newly created after the settle delay.

**Fix:** Set the flag only after a sweep has actually run.

### IN-07: `concurrentReadsAgree` cannot fail

**File:** `Tests/PaneMacTests/CapabilitiesTests.swift:53-60`

**Issue:** The test does concurrent reads with no concurrent writer.

**Fix:** Interleave `recordFailure` calls, or delete the test.

### IN-08: Revoking Accessibility while Pane runs is not detected

**File:** `Sources/PaneMac/Permission/PermissionController.swift:55-73`, `Sources/PaneMac/AXWindowSystem.swift:238-244`

**Issue:** Polling stops at `.ready`. After a revoke, every read fails with -25211, which maps to `.otherFailure`, and the glyph still shows ready.

**Fix:** Treat `.apiDisabled` from several apps as a permission event.

### IN-09: `resumeRecordedPID` sends SIGCONT to a recorded PID that may have been reused

**File:** `Sources/PaneMac/Shell/FreezeTest.swift:63-71`

**Issue:** After a crash and a reboot, the stored PID can belong to an unrelated process that was stopped on purpose.

**Fix:** Store the process start time or bundle ID with the PID, and only resume if they still match.

### IN-10: The live probe loop is still untested, and the fake still probes inline

**File:** `Sources/PaneMac/AXWindowSystem.swift:276-292`, `Sources/PaneTestSupport/FakeWindowSystem.swift:189-193`

**Issue:** Only `probeStep` is tested. A regression in the loop in `startProbing` would not be caught.

**Fix:** Pull the loop out into a driver with an injectable clock, or make the fake run the same loop.

### IN-11: The new per-window registration retry has no test, cannot be cancelled, and differs from the app-level rule

**File:** `Sources/PaneMac/AX/AXAppThread.swift:294-315, 128-134`

**Issue:** The WR-03 fix is checked only by reading the code; the fix report says so. The retry loop (lines 304-314) does not check `isStopped`. Each `.cannotComplete` costs up to the 1 s global messaging timeout, and that time counts in `observation.duration`. So an app that keeps timing out on one element's registrations makes every observe slow and can push it into the degraded state. Also, per-window registration drops `.notificationUnsupported`, but the app-level filter (line 131) retries it forever, as its `shortcut:` comment notes.

**Fix:** Check `isStopped` between registrations, cap the retries per element (for example 5), and drop `.notificationUnsupported` at app level too. A seam that injects the AddNotification result would make the bookkeeping unit-testable.

### IN-12: Stale doc comments after the fixes

**File:** `Sources/PaneEngine/MinimumSizeLearner.swift:17`, `Sources/PaneMac/AX/AXAppThread.swift:34`

**Issue:** `unconfirmed` still says "waiting for the next write to confirm it", but it now survives honoured writes at or above it. `windows` still says each element is "registered for the per-window notifications", but registration can now be pending in `unregisteredWindows`.

**Fix:** Update both comments.

---

_Reviewed: 2026-10-25T18:26:48Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
