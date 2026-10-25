---
phase: 02-window-control
reviewed: 2026-10-25T18:01:22Z
depth: standard
iteration: 2
diff_base: f1411f6
files_reviewed: 22
files_reviewed_list:
  - Sources/PaneEngine/MinimumSizeLearner.swift
  - Sources/PaneEngine/ResponsivenessTracker.swift
  - Sources/PaneEngine/TabGroupTracker.swift
  - Sources/PaneEngine/WindowTracker.swift
  - Sources/PaneMac/AX/AXAppThread.swift
  - Sources/PaneMac/AX/AXSnapshotReader.swift
  - Sources/PaneMac/AXWindowSystem.swift
  - Sources/PaneMac/CGWindowList.swift
  - Sources/PaneTestSupport/FakeWindowSystem.swift
  - Sources/pane-dump/main.swift
  - Tests/PaneEngineTests/CloseScenarioTests.swift
  - Tests/PaneEngineTests/ExclusionScenarioTests.swift
  - Tests/PaneEngineTests/FrameScenarioTests.swift
  - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
  - Tests/PaneEngineTests/ResponsivenessTrackerTests.swift
  - Tests/PaneEngineTests/TabGroupTrackerTests.swift
  - Tests/PaneEngineTests/TabScenarioTests.swift
  - Tests/PaneEngineTests/TrackerDisplayTests.swift
  - Tests/PaneEngineTests/WindowTrackerTests.swift
  - Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift
  - Tests/PaneMacTests/MinimumHintsStoreTests.swift
findings:
  critical: 1
  warning: 3
  info: 10
  total: 14
status: issues_found
---

# Phase 2: Code Review Report (re-review, iteration 2)

**Reviewed:** 2026-10-25T18:01:22Z
**Depth:** standard
**Files Reviewed:** 22 (the fix diff `f1411f6..f846161` and the files it touches)
**Status:** issues_found

## Summary

I re-read every file the fix diff touches in full, plus the code it calls (`CloseRule`, `AppRegistry`, `FallbackMatcher`, `FrameWriter`). `swift test --skip PaneMacIntegrationTests` passes: 376 tests (142 + 74 + 160). I did not run the live integration tests. I checked the tab-group interaction with a scratch harness that drives the real `WindowTracker` with hand-built observations: `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe2/Sources/Probe2/main.swift`.

Status of the iteration-1 findings:

| Finding | Status |
|---|---|
| CR-01 probe loop exits early | **Resolved.** `probeStep` returns `.wait` and the loop continues. The loop only stops when the app is no longer degraded, the thread is gone, or the task is cancelled. Test gap carried as IN-10. |
| CR-02 Cmd-T tracks one window twice | **Resolved** for the Cmd-T and switch-back flows (`aStandaloneWindowThatGainsATabStaysOneWindowLedByItself`). But its new `folded` path is half of the new blocker CR-01. |
| CR-03 same-frame twins taken as hidden tabs | **Not resolved for real flows.** The "not listed at the last refresh" rule fails on the first refresh after a Space switch, and that is exactly when a twin ends up on another Space. Combined with CR-02's `folded`, this now reports a live window destroyed. See CR-01. |
| CR-04 a single read-back is learned and persisted | **Partially resolved.** Now downgraded to a warning: a single stale read-back is no longer learned, but two back-to-back stale ones still are. See WR-01. |
| WR-01 a failed CG list is read as "no windows" | **Resolved.** Every caller handles `nil`. `appStopped(terminated:)` passes an inactive context, so nothing closes. |
| WR-02 a non-regular app keeps its windows | **Resolved.** `tracker.appStopped` clears windows, pending windows, rechecks, the terminated mark and tab groups. Later results from the old thread are dropped by the `threads[pid] === thread` guards. |
| WR-03 AX registration errors ignored | **Partially resolved.** App-level registration is retried. Per-window registration is still unchecked, and while there is no observer the element cache never fills. See WR-03. |
| WR-04 queued frames written after exclusion | **Resolved.** The `excluded` flag is held under the frame lock and checked in enqueue, claim, drain and requeue. |
| WR-05 failed `_AXUIElementGetWindow` means never tracked | **Resolved, but the fix adds a new bug:** a window's ID can flip from the fallback ID to the real one. See WR-02. |
| WR-06 `displayUUID` stale after a write | **Resolved.** |
| WR-07 lock and hang tests cannot fail | **Resolved.** The -25202 lock mode and the hung app's ingest now match the live system. |
| WR-08 burst test cannot fail | **Resolved.** The drain is held, then released, and the test expects exactly one write with the last frame. |
| IN-01..IN-09 | Carried forward unchanged (still open). |

## Critical Issues

### CR-01: A Space switch folds an unrelated same-frame window into a tab group: it is reported destroyed, or it takes over the group's identity (CR-03 not fixed; CR-02's `folded` makes it worse)

**File:** `Sources/PaneEngine/TabGroupTracker.swift:65-71, 81-82, 88, 101`, `Sources/PaneEngine/WindowTracker.swift:60-66`

**Issue:** `canBeHiddenTab` accepts any same-frame, offscreen, layer-0 CG window as a hidden tab if it was listed at the last refresh (`wasListed.contains(id)`). That is how the CR-02 fix spots the Cmd-T case. But AX lists only the current Space's windows, which the code itself assumes (CloseRule: "valid, unlisted, present: hidden tab, other Space"). So at the first refresh after the user changes Space, every window from the Space they just left was listed at the last refresh and is now offscreen. The rule cannot tell it apart from a window that just became a hidden tab.

Same-frame windows of one app on different Spaces are normal in a tiling window manager. A maximized or single-tile layout gives every window on a display the same frame. When one of those windows is a native tab group:

- **A live window is reported destroyed** (from harness S6). Tab group T (30 visible, 31 hidden) is tracked on Space 2. The user goes to Space 1 and opens window A (10) in the same slot. When they switch back to Space 2, A matches T's frame and was listed last refresh, so it becomes a member of T. A is a tracked standalone window that is not the leader, so `TabResolution.folded` returns it and `WindowTracker.ingest` emits `windowDestroyed(A)`:
  ```
  S6 ->sp1 (A opened): [(10, 10, 1, present), (30, 30, 2, present)]
  S6 ->sp2:            [(30, 30, 2, present)]      windowDestroyed(window 10)
  S6 ->sp1:            [(30, 10, 1, present)]      // T's identity now shows A
  ```
  When the user returns to Space 1, A is listed with `tabCount 1`. `list.firstIndex { $0.members.contains(v.id) }` (line 81) still binds it to T, because only the hidden-member filter checks `tabCount`, not the visible-member match. So A is never tracked as itself again, and T's identity flips between A and 30 on every Space switch.
- **A tracked window becomes the leader of another Space's group** (S4). If A is tracked first and T is first seen after the switch, line 88 picks A as T's leader (`standalone.first { members.contains($0.windowID) }`). The two windows on two Spaces then collapse into one tracked window that flips `visibleMemberID` between 10 and 30:
  ```
  S4 ->sp2: [(10, 30, 2, present)]   S4 ->sp1: [(10, 10, 1, present)]   S4 ->sp2: [(10, 30, 2, present)]
  ```

The new test `aTrackedWindowOnAnotherSpaceWithTheSameFrameIsNeverAHiddenTab` (TabGroupTrackerTests.swift:134-144) only passes because it calls `update` with no prior update, so `lastListed` is empty. A real twin always reaches the other Space through a refresh where it was listed. The "untracked twin" shortcut in the doc comment (TabGroupTracker.swift:27-28) understates the effect. That twin does not just inflate `tabCount`: it takes over the group's visible member and is never tracked separately.

**Fix:** Bound a group's hidden members by its `AXTabs` count, and prefer known members over tracked standalone windows. Only adopt a standalone window when the count cannot be filled otherwise (the Cmd-T case). Also stop a listed `tabCount < 2` window from binding an existing group unless it is that group's leader or last visible member, or the group's other members have all left the CG list:
```swift
// in update(), per visible v:
let needed = max(v.tabCount - 1, 0)
let known = candidates.filter { id in list.contains { $0.members.contains(id) } }
let fresh = candidates.filter { id in !known.contains(id) && !standalone.contains { $0.windowID == id } }
let adoptable = candidates.filter { id in standalone.contains { $0.windowID == id } }
let hidden = Array((known + fresh + adoptable).prefix(needed))
```
This handles S4, S6 and Cmd-T (tabCount 2 with only A as candidate, so A is adopted). For the untracked twin (S5), the Spaces API (`SLSCopySpacesForWindows`, already planned in `PanePrivate` with a fallback) is the real discriminator: exclude candidates that are not on the visible tab's Space. Add scenario tests that run the actual sequence (listed on Space 1, then a refresh on Space 2), not a fresh `TabGroupTracker`, and assert no `windowDestroyed` and two tracked windows.

## Warnings

### WR-01: Two back-to-back stale read-backs still teach a permanent per-bundle minimum (CR-04 partially fixed)

**File:** `Sources/PaneEngine/MinimumSizeLearner.swift:32-41`, `Sources/PaneMac/AX/FrameWriter.swift:35-44`, `Sources/PaneMac/AXWindowSystem.swift:181-185`

**Issue:** The fix requires two refused read-backs that agree within 2 pt. But `FrameWriter` still reads back right after the third write, with no settle. An app that applies size asynchronously, or is briefly busy, returns the same old size to every write until it catches up. Two drains in that window both read the old frame back, the values agree, and the old frame is learned. During a drag (Phase 3 sends a frame per drag step, and each drain writes the latest), a 200 ms stall in an Electron or Java app is enough. `onLearnedMinimum` then persists it through `MinimumHintsStore.record`, which still only takes the per-axis max. One stall still raises the bundle's minimum permanently, with no decay or cap.

None of the other review suggestions were applied: there is no settle re-read, and no check that the request was below the window's previous frame on that axis. A read-back equal to the pre-write frame is the signature of a stale or no-op write, and the learner counts it as a refusal.

**Fix:** In `applyFrameResult`, don't count an axis as refused when the read-back equals the window's pre-write frame on that axis (`old.frame.size`, within tolerance). Or require the two agreeing read-backs to be at least `probeInterval` apart. And cap the persisted hint below the window's display size, so a bad hint cannot block tiling:
```swift
// WindowTracker.applyFrameResult, before learning
let stale = abs(actual.width - old.frame.width) <= MinimumSizeLearner.tolerance
    && abs(actual.height - old.frame.height) <= MinimumSizeLearner.tolerance
if info.state == .present, !stale { _ = learner.learn(window: identity, requested: result.requested, actual: actual) }
```
Add a learner test where two consecutive writes read back the unchanged previous frame, and assert that nothing is learned.

### WR-02: A window first identified by the fallback changes identity when the private lookup next succeeds, leaving a permanent duplicate (introduced by the WR-05 fix)

**File:** `Sources/PaneMac/AX/AXSnapshotReader.swift:79-90, 107-125`, `Sources/PaneMac/AX/AXAppThread.swift:179-187`

**Issue:** `windowID(of:)` tries `_AXUIElementGetWindow` before it looks at the cache. Only `Fallback.identify` checks the cache (line 109). Suppose the lookup fails for element E and the frame match finds nothing, for example because the window is mid-animation or not yet in the CG snapshot. E then gets a synthetic ID S, and is tracked as S if this happens in the initial sweep or lasts past the settle delay. On a later refresh the lookup succeeds and returns the real ID R. Then:

- E is observed as R, a new window, and after the settle delay `windowCreated(R)` is emitted for a window that is already tracked as S.
- S is still in `knownWindowIDs`. `observe()` probes it through the old cache entry (AXAppThread.swift:179-185), which is the same element E, gets `.valid(listed: false)` back, and puts S back into the cache next to R.
- Once R is tracked, `syntheticPresence` no longer lets S claim R's CG entry. CloseRule gives `.valid, absent` → `.recheck` on every refresh, forever, because E never answers -25202.

Before the fix, E was not tracked at all, and the capability only switched off session-wide, so a window's ID never changed. The fix turned "missing" into "duplicated", which is worse for Phase 3 layout.

**Fix:** Keep the ID an element already has. Check the cache before the private lookup, and only use the lookup for elements that are not cached:
```swift
if let cached = fallback.cachedID(for: element) { return cached }   // CFEqual against the cache
if !forceFallback, Capabilities.isAvailable(.axWindowID), let function = AXWindowID.function { ... }
```
Or, when the lookup succeeds for an element cached under a non-`axPrivate` ID, report it under the cached ID and let a later migration re-key it explicitly. Add a `FallbackIntegrationTests` or reader-level case where an element cached as synthetic later resolves through the private API. It should still be one window.

### WR-03: Per-window AX registrations are still unchecked, and without an observer the element cache never fills (WR-03 partially fixed)

**File:** `Sources/PaneMac/AX/AXAppThread.swift:123-126, 294-303`

**Issue:** The original WR-03 cited `updateWindows` as well as `installObserver`. The fix only covers app-level notifications:
- `updateWindows` still discards each `AXObserverAddNotification` result (line 301) and never retries. An element that is not AX-ready when first cached (an Electron or Java window right after creation) never gets `kAXUIElementDestroyedNotification`, moved or resized. Its close and frame changes then depend on the 5 s sweep for its whole life. Once the element is in `windows`, line 300 never tries it again.
- `updateWindows` still begins with `guard let observer else { return }` (line 295), so while `AXObserverCreate` keeps failing, `windows = current` never runs. That has three effects. The new "created late" loop (lines 123-126) always iterates an empty cache, so it is dead code. Every frame write fails with `.invalidElement` (`drainFrames` finds no element). Known windows that leave AXWindows cannot be probed (`windows[id]` is nil), so they map to `.timedOut` and `.noChange`.

**Fix:** Always assign `windows = current`, and only skip the registration when there is no observer. Track per-element registration failures (for example `CachedWindow.unregistered: [String]`) and retry them in `observe()`, like the app-level list:
```swift
private func updateWindows(_ current: [UInt32: CachedWindow]) {
    defer { windows = current }
    guard let observer else { return }
    ...
}
```

## Info

### IN-01: `ClosedIDCache` is dead state, and its doc comments are swapped

**File:** `Sources/PaneEngine/CloseRule.swift:60-85`, `Sources/PaneEngine/WindowTracker.swift:18-19, 45, 123, 250`

**Issue:** The tracker writes the cache but nothing reads it: `contains` is only called from tests. The "reused ID is a new window" behaviour actually comes from removing closed windows from `windows`. The comments are also misplaced: "True while `now < closed + ttl`" sits above `remove`, and "The ID is a live window again." above `contains`.

**Fix:** Delete `ClosedIDCache` and its tests, or use it (for example, to delay re-creating a reused ID). Either way, fix the comments.

### IN-02: The menu header count and Tracked Windows use different window filters

**File:** `Sources/PaneMac/Shell/StatusItemController.swift:99-100` vs `Sources/PaneMac/Shell/TrackedWindowsModel.swift:37, 77`

**Issue:** The header counts every inventory window, while Tracked Windows filters out `.closed`. The tracker never stores `.closed` today, so the two match for now, but the rule lives in two places.

**Fix:** Count with the same filter (`latest.windows.filter { $0.state != .closed }`), or drop the dead `.closed` filter from `TrackedWindowsModel`.

### IN-03: The `where` clause in `PermissionReducer` guards only the second pattern (open deferred item)

**File:** `Sources/PaneEngine/PermissionReducer.swift:110`

**Issue:** Swift applies `where state.showStaleFormB` only to `(.waitingForGrant, .resetClicked)`. The behaviour looks intended, since stale form A always offers Reset, but the release build warns.

**Fix:** Split it into two `case` labels with the same body, or make the intent explicit with `case (.waitingForGrant, .resetClicked) where state.showStaleFormB, (.staleTrustedButFailing, .resetClicked):` and a comment.

### IN-04: Learned bundle hints only seed windows after a relaunch

**File:** `Sources/PaneMac/PaneMacApp.swift:36-44`, `Sources/PaneEngine/WindowTracker.swift:114-117, 182-184`

**Issue:** `setBundleHints` is called once at launch, and `onLearnedMinimum` updates the store but not the tracker. A second window of the same bundle opened in the same session starts from 0.

**Fix:** After `hints.record(...)` succeeds, call `system.setBundleHints(hints.hints)`. Fix CR-04 first.

### IN-05: A comment contradicts how sweep refreshes order the AX and CG reads

**File:** `Sources/PaneMac/AXWindowSystem.swift:202, 225-226`

**Issue:** The comment says the CG list is read after AX answered, but `sweep` takes one CG snapshot before any AX job and passes it to every refresh. For sweep refreshes the order is reversed, so a close that happens during the sweep only becomes a `.recheck`, and a window created after the snapshot has no layer fact. Both correct themselves on a later refresh.

**Fix:** Correct the comment, or take the CG snapshot per pid after `observe` in sweeps too.

### IN-06: Starting while locked marks the initial refresh complete without one

**File:** `Sources/PaneMac/AXWindowSystem.swift:107-115, 400-414`

**Issue:** If `start()` runs while the gate is paused, every `refresh` returns early, but `initialRefreshComplete` is still set to true. The post-resume `refreshAll` uses `initial: false`, so every pre-existing window waits out the settle delay and is reported as newly created rather than part of the initial sweep.

**Fix:** Set `initialRefreshComplete` only after a sweep has actually run. Make the first post-resume sweep `initial: true` if none has.

### IN-07: `concurrentReadsAgree` cannot fail

**File:** `Tests/PaneMacTests/CapabilitiesTests.swift:53-60`

**Issue:** The test does 100 concurrent reads with no concurrent writer. The answer is always `[true]`.

**Fix:** Interleave `recordFailure` calls and assert that the result changes monotonically, or delete the test.

### IN-08: Revoking Accessibility while Pane runs is not detected

**File:** `Sources/PaneMac/Permission/PermissionController.swift:55-73`, `Sources/PaneMac/AXWindowSystem.swift:238-244`

**Issue:** Polling stops once Pane is `.ready`. After a revoke, every `AXWindows` read fails with -25211, which maps to `.otherFailure`. Windows freeze at their last state while the glyph still shows ready.

**Fix:** Treat `listFailure == .apiDisabled` from several apps as a permission event: send `.pollTick(trusted: AXIsProcessTrusted(), …)` or add a new `.accessLost` event.

### IN-09: `resumeRecordedPID` sends SIGCONT to a recorded PID that may have been reused

**File:** `Sources/PaneMac/Shell/FreezeTest.swift:63-71`

**Issue:** After a crash and a reboot, the stored PID can belong to an unrelated process, which may have been stopped on purpose (a `^Z` job or a debugger). SIGCONT would resume it.

**Fix:** Store the start time (`proc_pidinfo` `pbi_start_tvsec`) or the bundle ID with the PID, and only resume if they still match.

### IN-10: The live probe loop is still untested, and the fake still probes inline

**File:** `Sources/PaneMac/AXWindowSystem.swift:276-292`, `Sources/PaneTestSupport/FakeWindowSystem.swift:189-193`, `Tests/PaneEngineTests/ResponsivenessTrackerTests.swift:59-69`

**Issue:** The CR-01 fix is correct as written, but only `probeStep` is tested. The loop in `startProbing` is still live-only. `FakeWindowSystem.refresh` still probes inline through `needsProbe`, so `ResponsivenessScenarioTests` would not catch a regression in the loop, such as `.wait` returning, or a missed restart on a late record.

**Fix:** Move the loop body into a small testable driver (for example a `ProbeLoop` that takes a clock and a probe closure), or make the fake run the same `probeStep` loop on its simulated clock.

---

_Reviewed: 2026-10-25T18:01:22Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
