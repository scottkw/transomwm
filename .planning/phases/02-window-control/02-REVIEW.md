---
phase: 02-window-control
reviewed: 2026-10-25T17:31:41Z
depth: standard
files_reviewed: 92
files_reviewed_list:
  - Package.swift
  - Sources/PaneApp/main.swift
  - Sources/PaneEngine/Classifier.swift
  - Sources/PaneEngine/CloseRule.swift
  - Sources/PaneEngine/Coordinates.swift
  - Sources/PaneEngine/CorpusCase.swift
  - Sources/PaneEngine/ExclusionFilter.swift
  - Sources/PaneEngine/FallbackMatcher.swift
  - Sources/PaneEngine/LifecycleSync.swift
  - Sources/PaneEngine/MinimumSizeLearner.swift
  - Sources/PaneEngine/PermissionReducer.swift
  - Sources/PaneEngine/ResponsivenessTracker.swift
  - Sources/PaneEngine/TabGroupTracker.swift
  - Sources/PaneEngine/WindowSnapshot.swift
  - Sources/PaneEngine/WindowSystem.swift
  - Sources/PaneEngine/WindowTracker.swift
  - Sources/PaneFixtureApp/main.swift
  - Sources/PaneMac/AX/AXAppThread.swift
  - Sources/PaneMac/AX/AXSnapshotReader.swift
  - Sources/PaneMac/AX/AppRegistry.swift
  - Sources/PaneMac/AX/FrameWriter.swift
  - Sources/PaneMac/AX/SyntheticWindowIDs.swift
  - Sources/PaneMac/AXWindowSystem.swift
  - Sources/PaneMac/CGWindowList.swift
  - Sources/PaneMac/Displays.swift
  - Sources/PaneMac/ExclusionStore.swift
  - Sources/PaneMac/MinimumHintsStore.swift
  - Sources/PaneMac/PaneMacApp.swift
  - Sources/PaneMac/Permission/PermissionController.swift
  - Sources/PaneMac/Permission/PermissionProbe.swift
  - Sources/PaneMac/Permission/SetupView.swift
  - Sources/PaneMac/Permission/SetupWindowController.swift
  - Sources/PaneMac/Permission/TCCReset.swift
  - Sources/PaneMac/RefreshScheduler.swift
  - Sources/PaneMac/SessionGate.swift
  - Sources/PaneMac/Shell/FreezeTest.swift
  - Sources/PaneMac/Shell/MenuCopy.swift
  - Sources/PaneMac/Shell/Nudge.swift
  - Sources/PaneMac/Shell/StatusItemController.swift
  - Sources/PaneMac/Shell/TrackedWindowsModel.swift
  - Sources/PaneMac/Shell/TrackedWindowsView.swift
  - Sources/PaneMac/Shell/TrackedWindowsWindowController.swift
  - Sources/PanePrivate/AXWindowID.swift
  - Sources/PanePrivate/Capabilities.swift
  - Sources/PaneTestSupport/FakeWindowSystem.swift
  - Sources/pane-dump/main.swift
  - Tests/PaneEngineTests/ClassifierCorpusTests.swift
  - Tests/PaneEngineTests/ClassifierTests.swift
  - Tests/PaneEngineTests/CloseRuleTests.swift
  - Tests/PaneEngineTests/CloseScenarioTests.swift
  - Tests/PaneEngineTests/CoordinatesTests.swift
  - Tests/PaneEngineTests/ExclusionScenarioTests.swift
  - Tests/PaneEngineTests/FakeWindowSystemTests.swift
  - Tests/PaneEngineTests/FallbackMatcherTests.swift
  - Tests/PaneEngineTests/FrameScenarioTests.swift
  - Tests/PaneEngineTests/LifecycleSyncTests.swift
  - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
  - Tests/PaneEngineTests/PermissionReducerTests.swift
  - Tests/PaneEngineTests/ResponsivenessScenarioTests.swift
  - Tests/PaneEngineTests/ResponsivenessTrackerTests.swift
  - Tests/PaneEngineTests/TabGroupTrackerTests.swift
  - Tests/PaneEngineTests/TabScenarioTests.swift
  - Tests/PaneEngineTests/TrackerClassificationTests.swift
  - Tests/PaneEngineTests/TrackerDisplayTests.swift
  - Tests/PaneEngineTests/WindowTrackerTests.swift
  - Tests/PaneMacIntegrationTests/ClassificationIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/CloseIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/ExclusionIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/FixtureShapesTests.swift
  - Tests/PaneMacIntegrationTests/FixtureTrackingTests.swift
  - Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/FreezeIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/IntegrationSupport.swift
  - Tests/PaneMacIntegrationTests/LiveTrackingTests.swift
  - Tests/PaneMacIntegrationTests/NudgeIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/TabsIntegrationTests.swift
  - Tests/PaneMacTests/CapabilitiesTests.swift
  - Tests/PaneMacTests/ExclusionStoreTests.swift
  - Tests/PaneMacTests/FreezeTestTests.swift
  - Tests/PaneMacTests/MenuCopyTests.swift
  - Tests/PaneMacTests/MinimumHintsStoreTests.swift
  - Tests/PaneMacTests/NudgeTests.swift
  - Tests/PaneMacTests/SessionGateTests.swift
  - Tests/PaneMacTests/TCCResetTests.swift
  - Tests/PaneMacTests/TrackedWindowsModelTests.swift
  - Tests/PaneModelTests/NoAppKitTests.swift
  - scripts/build-debug.sh
  - scripts/generate.sh
  - scripts/run-debug.sh
  - xcode/Pane.entitlements
  - xcode/project.yml
findings:
  critical: 4
  warning: 8
  info: 9
  total: 21
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-10-25T17:31:41Z
**Depth:** standard
**Files Reviewed:** 92
**Status:** issues_found

## Summary

I read all 46 source files in scope, with the most time on the AX concurrency layer (`AXWindowSystem`, `AXAppThread`, `FrameWriter`, `AXSnapshotReader`, `SessionGate`) and the engine (`WindowTracker`, `CloseRule`, `TabGroupTracker`, `FallbackMatcher`, `MinimumSizeLearner`, `MinimumHintsStore`). I then went through the tests and scripts. `swift test --skip PaneMacIntegrationTests` passes: 363 tests. I did not run the live integration tests.

The thread confinement in `AXAppThread` holds up. Every AX call stays on the app's own thread, the stop/enqueue lock prevents lost continuations, and teardown order is correct. The serious defects are in the decision logic above that layer:

- The live probe loop can exit early and leave an app degraded for the rest of the session (CR-01).
- Native tab handling is wrong in two ways I reproduced against the real `WindowTracker`. A scratch harness (`/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe`) fed it hand-built observations. In the most common tab flow (Cmd-T in an existing window), one window becomes two tracked windows (CR-02). An unrelated same-app window with an identical frame, such as a minimized twin or a window on another Space, gets merged into a tab group (CR-03).
- The minimum-size learner turns any larger read-back into a permanent per-bundle hint that only ever grows (CR-04).

The scenario tests cannot catch any of these. `FakeWindowSystem` models probing and lock blanking differently from `AXWindowSystem`, and no tab test covers an existing window gaining a tab or a same-frame window of the same app.

Confirmed from the briefing:
- **`ClosedIDCache` is dead state.** `WindowTracker` calls `purge`, `insert` and `remove` (WindowTracker.swift:45, 123, 250), but nothing in `Sources/` calls `contains`. Only `CloseRuleTests` does. See IN-01.
- **The menu header count includes `.closed` windows** (StatusItemController.swift:99-100), while Tracked Windows filters them out. No `WindowInfo` with state `.closed` reaches the inventory today, because the tracker removes closed windows and `CloseRule` never returns `.state(.closed)`. So the mismatch is latent and not visible to users. See IN-02.

## Critical Issues

### CR-01: The probe loop exits on its first "not due yet" check, so a degraded app can stay degraded for the rest of the session

**File:** `Sources/PaneMac/AXWindowSystem.swift:268-280` (with `Sources/PaneEngine/ResponsivenessTracker.swift:45-48`)

**Issue:** `startProbing` runs `guard …, self.responsiveness.needsProbe(pid: pid, at: .now) else { return }`. `needsProbe` is false whenever `lastAttempt` is less than 2 s old, and every `record()` updates `lastAttempt`, including results from jobs that were already queued on the app thread when the app degraded. Two examples:
- A refresh observe queued behind a hung frame drain finishes after the degrading result.
- After a slow (>1.5 s) successful observe, the drain behind it starts before main sets `drainEnabled = false`, then times out.

If such a result lands within 2 s of the probe's wake, the probe task returns for good. Nothing restarts it: `record` only returns `.degraded` on the not-degraded to degraded edge, `refresh` skips degraded apps, and `drainEnabled` stays false. The app gets no refreshes, no frame writes and no recovery until it quits.

`FakeWindowSystem.refresh` (FakeWindowSystem.swift:183-187) probes inline instead, so `ResponsivenessScenarioTests` cannot catch this.

**Fix:** Keep the loop alive while the app is degraded, and only skip an attempt that is not due yet:
```swift
probes[pid] = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: ResponsivenessTracker.probeInterval)
        guard !Task.isCancelled, let self, let thread = self.threads[pid],
              self.responsiveness.degraded.contains(pid) else { return }
        guard self.responsiveness.needsProbe(pid: pid, at: .now) else { continue }
        let (outcome, duration) = await thread.probe()
        guard !Task.isCancelled, self.threads[pid] === thread else { return }
        self.record(pid, outcome, duration)
    }
}
```
Add a live-system unit test, or make the fake use the same loop, in which a record lands between the degrade and the first probe.

### CR-02: An existing window that gains a native tab is tracked twice, permanently

**File:** `Sources/PaneEngine/TabGroupTracker.swift:56-66`, `Sources/PaneEngine/WindowTracker.swift:70, 139-149`, `Sources/PaneEngine/CloseRule.swift:53`

**Issue:** Take a tracked standalone window A. The user presses Cmd-T in TextEdit, Finder or Terminal, and AppKit creates tab window N. N becomes the only listed member with `tabCount 2`, and A becomes an offscreen hidden tab. `TabGroupTracker.update` finds no existing group for N, so it creates a new group led by `WindowIdentity(N)`. `WindowTracker` then reports N as a new window. A is still tracked: it is probed through its cached element, which returns `.valid(listed: false)`, and it is still in the CG list. `CloseRule` returns `.noChange` for that, so A stays a separate `.present` window with `tabCount 1`. When the user later switches back to tab A, A maps to group N, but A's own identity is still decided as `.present` through its own visible ID. The duplicate never goes away.

Reproduced against `WindowTracker`:
```
S1 tracked: [(10, 10, 1, present), (11, 11, 2, present)]   // expected: one window, tabCount 2
```
This is the most common way a tab group comes into being. `TabScenarioTests` and `TabsIntegrationTests` only build groups that already exist at the first sweep (`tabGroup(ids:)`, `tabs:3`), so neither exercises it.

**Fix:** When a group is created or gains members, adopt an already-tracked member as the leader, and fold any other tracked member identities into the group without reporting them destroyed. For example, `TabGroupTracker.update` can take the set of tracked identities for the pid and pick `leader = trackedMembers.min(by: creationOrder) ?? WindowIdentity(v.id)`. `WindowTracker.ingest` then removes the other tracked members, or emits `windowChanged` to merge them. Add a scenario test: standalone window, then Cmd-T, which must leave exactly one window with `tabCount == 2` and no create/destroy churn. Also test switching back to the original tab.

### CR-03: Tab membership by bounds alone absorbs unrelated same-app windows with an identical frame, and can bind the group to a minimized window

**File:** `Sources/PaneEngine/TabGroupTracker.swift:53-61`

**Issue:** Members are any same-pid, layer-0, offscreen CG windows whose bounds match the visible tab within 1 pt. Minimized windows and windows on other Spaces are also layer 0 and offscreen, and they keep their frames. In a tiling window manager, same-app windows sharing a tile slot on two Spaces, or a minimized window restored to the same slot, are common. Consequences:
- **A listed minimized twin gets merged into the group.** It is listed in AXWindows, so `list.firstIndex { $0.members.contains(v.id) }` matches it. It overwrites the group's `members`, sets `tabCount` to 1, and `groupFor[twin] = leader`. If AX lists the twin first, the group's `visibleMemberID` becomes the minimized window. Reproduced:
  ```
  S2  tracked: [(10, 20, 1, absent)]                        // group 10 now points at minimized window 20; window 20 vanished
  S2b tracked: [(10, 20, 1, absent), (20, 20, 1, absent)]   // already-tracked twin: duplicate
  ```
- **An other-Space twin inflates `tabCount`.** It also keeps `remaining` non-empty in `decide` (WindowTracker.swift:238). So when the group's real last tab closes, the group "lives on" with a closed `visibleMemberID` and is never destroyed.

**Fix:** Never treat a window that is listed in this refresh's `visible` set as a hidden tab of another visible window, unless it reports an `AXTabGroup` itself (the drag-out case). Also exclude IDs that the tracker already tracks as separate, non-group windows. For example, pass `listedIDs` and `trackedStandaloneIDs` into `update` and filter `members` with `!listedIDs.contains(id) && !trackedStandaloneIDs.contains(id)`. Add `TabGroupTrackerTests` cases for a minimized twin and an other-Space twin with an identical frame.

### CR-04: Any larger read-back is learned as a minimum and persisted per bundle, monotonically, with no way back

**File:** `Sources/PaneEngine/MinimumSizeLearner.swift:18-27`, `Sources/PaneMac/AX/FrameWriter.swift:35-44`, `Sources/PaneMac/AXWindowSystem.swift:175-184`, `Sources/PaneMac/PaneMacApp.swift:37-44`, `Sources/PaneMac/MinimumHintsStore.swift:61-68`

**Issue:**
- `FrameWriter` reads the frame back immediately after the third write, with no settle.
- `learn` records the read-back as the minimum on any axis where it exceeds the request by more than 2 pt, however large the request was.
- `onLearnedMinimum` immediately raises and saves the per-bundle hint, and `record` only ever takes the per-axis max.

So one write whose read-back is larger than requested permanently raises that app's minimum for every future window in every future session. Examples: an app that applies size asynchronously and still reports the old, larger size; cell or increment snapping that rounds up by more than 2 pt; a write to a `.fullscreen` window (`perform` does not check `info.state`). Nothing decays, caps or ignores the hint, and Phase 3 will lay out using it. The only recovery is deleting `min-size-hints.json`.

The live test (`aRefusedSizeIsReadBackAndLearned`) uses a synchronous AppKit fixture, and the fake clamps synchronously (FakeWindowSystem.swift:206-208), so neither can show this.

**Fix:** Only learn when the request was actually below what came back, and confirm before persisting:
- Skip learning for windows that are not `.present`.
- Re-read the frame after a short settle, or on the next AX resize notification, and learn only if both reads agree.
- Only count an axis when the request was smaller than the window's previous frame on that axis, which is what a refused shrink looks like.
- Persist only after the same minimum is seen in at least two writes.

For example, in `AXWindowSystem.frameWritten`, call `onLearnedMinimum` only when the learned value has been confirmed by a second, independent write or refresh.

## Warnings

### WR-01: A failed CG window list silently becomes "no windows", which breaks the second source and duplicates tab groups

**File:** `Sources/PaneMac/CGWindowList.swift:13`

**Issue:** `guard let list = CGWindowListCopyWindowInfo(...) else { return [] }` turns a failed read into "every window has left the CG list". That is the `or {}` pattern CLAUDE.md warns about.
- `CloseRule` then closes every window of a terminated app (`(.terminated, _, false)`) and every AX-invalid window on one source.
- `TabGroupTracker.update` intersects every group with an empty set and drops the groups. The next refresh re-forms the group under the visible tab's ID, and the old leader identity stays as a permanent duplicate. Reproduced: `S3 tracked: [(10, 10, 2, present), (11, 11, 2, present)]`.

**Fix:** Return `nil` (`[CGWindowEntry]?`) on failure, log it, and skip the close decision and the tab update for that refresh. In `AXWindowSystem.refresh` and `sweep`, call `ingest` with only the AX-side updates, or defer the refresh.

### WR-02: An app that stops being `.regular` without quitting leaves its windows tracked for good

**File:** `Sources/PaneMac/AXWindowSystem.swift:367-378`, `Sources/PaneMac/AX/AppRegistry.swift:62-65`

**Issue:** `appStopped(pid, terminated: false)` tears down the thread and returns, so the tracker keeps that app's windows with no thread to refresh them. `recheckTerminated` only covers terminated PIDs, and `perform` logs "window not tracked", which is wrong. If the app becomes `.regular` again, the new thread starts with an empty element cache. Any window that closed in the meantime is "known but uncached", so it is left out of the observation (AXAppThread.swift:148-149), maps to `.timedOut` and gets `.noChange` forever. Apps that switch activation policy when their last window closes or when they move to the menu bar can trigger this.

**Fix:** On a non-terminated stop, drop the app's windows from the tracker silently, or emit `windowDestroyed` (for example with a new `tracker.appStopped(pid:)` that also clears `pending`, `rechecks` and the app's tab groups). Alternatively, keep the thread alive and stop only hint handling.

### WR-03: AX observer registration errors are ignored and never retried

**File:** `Sources/PaneMac/AX/AXAppThread.swift:105-112, 256-258`

**Issue:** `AXObserverCreate` failing returns silently, and each `AXObserverAddNotification` result is discarded. Apps that are not AX-ready right after `isFinishedLaunching` (Electron and Java apps commonly answer -25204 for a moment) never get app-level notifications such as window created, focus, or hide/show. That app then relies on the 5 s sweep for its whole lifetime, and focus hints never arrive.

**Fix:** Check the results. If `AXObserverCreate` or any app-level registration fails with `.cannotComplete` or `.notificationUnsupported`, mark the app as needing registration and retry at the start of each `observe()` until it succeeds. Log the first failure.

### WR-04: Frames already queued for an app are written after the app is excluded

**File:** `Sources/PaneMac/AXWindowSystem.swift:133-137, 152-172`, `Sources/PaneMac/AX/AXAppThread.swift:186-243`

**Issue:** `ExclusionFilter` only runs in `perform`. Frames already in an `AXAppThread` slot are left alone when `setExcludedBundleIDs` adds the app. That includes frames held while the app is degraded (`drainEnabled == false`) and frames re-queued after a -25204. They are written on recovery or on the next drain, which breaks D-12 ("never touched"). `FakeWindowSystem.heldFrames` has the same gap (FakeWindowSystem.swift:186-189).

**Fix:** In `setExcludedBundleIDs`, clear the slots of every thread whose `bundleID` is now excluded. Add an `AXAppThread.clearFrames()` that empties `queue.slots` under the lock. Also check the exclusion in `drainFrames` before each write.

### WR-05: Windows whose `_AXUIElementGetWindow` fails are silently never tracked while the capability stays on

**File:** `Sources/PaneMac/AX/AXSnapshotReader.swift:78-87`, `Sources/PanePrivate/Capabilities.swift:95-114`, `Sources/PaneEngine/WindowTracker.swift:61-62`

**Issue:** When the private lookup fails for a readable `AXWindow` and the capability is still available, `windowID` returns `nil`, and the tracker skips windows with a `nil` ID. The capability only switches off after 5 *consecutive* failures process-wide, and any success from any other app resets the count (`recordSuccess`). So an app whose windows consistently fail the lookup while other apps succeed is never tracked, and nothing logs it. The comment at WindowTracker.swift:61 ("Fallback IDs (nil windowID) arrive in Plan 11") is out of date: Plan 11 did not fall back per window.

**Fix:** When the lookup fails for a real window, fall back for that element (`return fallback.identify(element, snapshot:title:)`) as well as recording the failure. Update the comment.

### WR-06: `applyFrameResult` updates the frame but not `displayUUID`

**File:** `Sources/PaneEngine/WindowTracker.swift:188-201`

**Issue:** After a write that moves a window to another display, `windowInfo` and the inventory report the new frame with the old `displayUUID` until an AX notification-driven refresh happens. A caller reading `windowInfo` right after `frameApplied` gets an inconsistent record. `aWindowMovedOntoTheSecondDisplayReportsThatDisplay` only passes because it polls for up to 2 s.

**Fix:** Recompute the display in the tracker, keeping the last `displays` from `ingest` or passing them in. Emit `windowChanged` when it changes:
```swift
info.displayUUID = Coordinates.displayUUID(for: actual, among: lastDisplays)
if old.displayUUID != info.displayUUID || old.learnedMinimum != info.learnedMinimum { events.append(.windowChanged(info)) }
```

### WR-07: The scenario tests for locks and hangs cannot catch a broken gate or a broken tracker path

**File:** `Tests/PaneEngineTests/CloseScenarioTests.swift:90-126`, `Sources/PaneTestSupport/FakeWindowSystem.swift:179-195, 225-232`

**Issue:**
- **The two lock tests don't test the gate.** The fake's lock makes every observation a `listFailure: .cannotComplete` (`.timedOut`), and `CloseRule` never closes on a timeout. So `lockBlankingClosesNothing` and `blankingWithoutTheGate…` pass whether or not `sessionActive` is honoured. The gate-dependent case is untested: AX answers -25202 and the CG list is empty during a lock.
- **`aHungAppNeverLosesAWindowOverFiveRefreshes` never reaches the tracker.** It passes because the fake returns before `ingest` for hung apps (`guard !app.hung else { return }`), while `AXWindowSystem` does ingest those observations.
- **Probing differs between the fake and the live system**, as covered in CR-01.

**Fix:** Add a fake mode where a lock blanks the CG list but AX still answers -25202, and assert that nothing closes with `gate: true` and something does with `gate: false`. Make the fake ingest the hung app's `listFailure` observation, as the live system does.

### WR-08: The burst-coalescing integration test cannot fail on coalescing

**File:** `Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift:88-92`

**Issue:** The test enqueues 10 frames and asserts `applied(...).count <= 10`. At most one `frameApplied` comes back per enqueued frame, so the assertion always holds, even if latest-wins coalescing (T-02-34) were removed.

**Fix:** Enqueue the burst while the drain is held, for example on a stopped fixture or with `drainEnabled = false` through a test seam, then release it and assert `count == 1` and `requested == last`.

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

---

_Reviewed: 2026-10-25T17:31:41Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
