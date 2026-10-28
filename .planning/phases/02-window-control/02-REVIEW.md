---
phase: 02-window-control
reviewed: 2026-10-25T20:51:25Z
depth: standard
iteration: 4
diff_base: b63a0d4
head: 54278c8
files_reviewed: 31
files_reviewed_list:
  - Sources/PaneEngine/LifecycleSync.swift
  - Sources/PaneEngine/MinimumSizeLearner.swift
  - Sources/PaneEngine/SpaceSwitchMarks.swift
  - Sources/PaneEngine/TabGroupTracker.swift
  - Sources/PaneEngine/WindowSnapshot.swift
  - Sources/PaneEngine/WindowSystem.swift
  - Sources/PaneEngine/WindowTracker.swift
  - Sources/PaneMac/AX/AXAppThread.swift
  - Sources/PaneMac/AX/AXSnapshotReader.swift
  - Sources/PaneMac/AX/WindowIDResolver.swift
  - Sources/PaneMac/AXWindowSystem.swift
  - Sources/PaneMac/Shell/MenuCopy.swift
  - Sources/PaneMac/Shell/StatusItemController.swift
  - Sources/PanePrivate/Capabilities.swift
  - Sources/PanePrivate/SkyLightSpaces.swift
  - Sources/PaneTestSupport/FakeWindowSystem.swift
  - Tests/PaneEngineTests/FrameScenarioTests.swift
  - Tests/PaneEngineTests/LifecycleSyncTests.swift
  - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
  - Tests/PaneEngineTests/SpaceSwitchMarksTests.swift
  - Tests/PaneEngineTests/TabGroupTrackerTests.swift
  - Tests/PaneEngineTests/TabScenarioTests.swift
  - Tests/PaneEngineTests/TrackerDisplayTests.swift
  - Tests/PaneEngineTests/WindowTrackerTests.swift
  - Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift
  - Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift
  - Tests/PaneMacTests/CapabilitiesTests.swift
  - Tests/PaneMacTests/MenuCopyTests.swift
  - Tests/PaneMacTests/MinimumHintsStoreTests.swift
  - Tests/PaneMacTests/WindowIDResolverTests.swift
findings:
  critical: 1
  warning: 2
  info: 13
  total: 16
status: issues_found
---

# Phase 2: Code Review Report (gap-closure review, iteration 4)

**Reviewed:** 2026-10-25T20:51:25Z
**Depth:** standard
**Files Reviewed:** 31 (the gap-closure diff `b63a0d4..54278c8`, plans 02-14 to 02-17)
**Status:** issues_found

## Summary

I read every changed source file and the code it calls (`FallbackMatcher`, `CloseRule`, `RefreshScheduler`, `AXWindowID`, the AXAppThread cache loop). `swift test --skip PaneMacIntegrationTests` passes: 463 tests (142 + 96 + 225). I did not run the live integration tests.

Harnesses, all driving the real `WindowTracker` / `TabGroupTracker` from PaneEngine at HEAD:
- `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe3/Sources/Probe3/main.swift`: C1-C7 re-run.
- `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe3/Sources/Probe4/main.swift`: new scenarios R1, D1, D2, O1 and C3b. Run with an argument: `race`, `crash`, `dup`, `orphan` or `c3`.
- `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe3/Sources/Probe4c/main.swift`: the probe3c learner scenarios, ported to the 02-15 API.
- `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/probe3/Sources/Probe4d/main.swift`: a chained ID correction.

I accepted the known limits in the 02-14 to 02-17 SUMMARYs and do not raise them again here. These are: the single-Space fallback (C5), incomplete membership with Space data, the 32 pt margin and cells larger than 32 pt, the confirm refresh replacing a pending refresh, a late Space notification, a refused handoff being final, merges and rapid switching during a Space switch, a holder with no frame or no CG list, and `pendingFocus` on a re-keyed tab.

Status of the iteration-3 findings:

| Finding | Status |
|---|---|
| CR-01 untracked twin wins the hidden-tab slot (C2, C5, C7) | **Resolved for C2 and C7 in both modes; C5 is the accepted single-Space limit.** Probe3 at HEAD: C2 (Z = 5 and Z = 50) and C7 keep one row per real window, and nothing is destroyed. C1, C3 and C4 are unchanged. C3b: the merged window is destroyed on the third refresh, as the fold guard intends. However, the new rebind gate added a crash path and a permanent duplicate (new CR-01). The new Cmd-T rule fails when the CG snapshot predates the AX read (new WR-01). |
| WR-01 refused size never learned while the layout stays put | **Resolved.** Probe4c: "one shrink then static" and "opens at its minimum" both learn 500 after a refresh 1 s later. An early refresh waits, then the 1.05 s refresh learns it. |
| WR-02 deterministic snap learned | **Resolved for cells of 32 pt or less** (larger cells are an accepted limit). Probe4c: the 16-pt row snap, a lag-2 slow drag and a lag-2 back-and-forth drag learn nothing. |
| WR-03 one failing element switches `_AXUIElementGetWindow` off | **Partially resolved.** It holds while the element stays listed. A shown tab or a window on another Space leaves AXWindows and counts again each time it comes back (new WR-02). |
| WR-04 fallback ID lasts for the window's life | **Resolved.** Fallback IDs are looked up again on every pass and re-keyed through `windowRekeyed`. A chained correction in one refresh still hands one window's entry to another (IN-13). |
| IN-04 learned hints seed only after relaunch | **Resolved** (in-tracker session hints, 02-15). |
| IN-05 CG/AX ordering comment | **Superseded by WR-01.** The ordering now changes behaviour. |
| IN-12 stale doc comments | **Partially resolved.** The learner comment was rewritten. The AXAppThread `windows` comment is still stale. |
| IN-01..03, IN-06..11 | Carried forward, still open. |

## Critical Issues

### CR-01: A tab-count change during a tab switch crashes Pane, or leaves one tab group tracked as two windows for good

**File:** `Sources/PaneEngine/TabGroupTracker.swift:119-122, 135-138, 160-171, 179-186, 196`

**Issue:** The 02-14 rebind gate refuses a listed member `v` (not the shown tab) when the old shown tab is still offscreen in the CG list and `v.tabCount != boundTabCount`. A refused `v` is removed from its group (line 136) and then goes down the new-group path:
- `candidates` still holds the refused group's other members. They rank tier 4 but still fill `tabCount - 1` slots.
- The new group's leader is `standalone.first { members.contains(...) } ?? WindowIdentity(v.id)` (line 180). `standalone` leaves out every group leader, so when `v` is the group's own leader, the new group gets the **same leader identity** as the old one.
- Line 196 then builds `Dictionary(uniqueKeysWithValues:)` keyed by leader and traps.

These results come from the real tracker (Probe4):

- **D1, crash.** A (10) is tracked. Cmd-T opens N (40), so the group is {10, 40}, shown 40, bound with 2 tabs. Before the next refresh the user presses Cmd-T again (50) and goes back to tab A. The refresh lists 10 with `AXTabs 3`, and 40 and 50 are offscreen:
  ```
  Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: 'WindowIdentity(windowID: 10, pid: 7, ...)'
  exit=133
  ```
  In production this runs inside `AXWindowSystem.ingest` on MainActor, so the whole app dies. With Space data it is the same, because the count check refuses before Spaces matter.
- **D2, permanent duplicate.** The tabs are 10 (leader), 40 and 50, with 50 shown. Cmd-T opens 60, and the user clicks 40 in the same refresh interval. 40 founds a new group that takes 60, 10 and 50, the old group's own tabs. `created 40` is reported, and both rows survive every later refresh, including a click on 50:
  ```
  D2 cmdT+click: [(10, 50, 3), (40, 40, 4)]   created 40
  D2 click 50:   [(10, 50, 4), (40, 40, 4)]
  ```
  Neither identity is ever folded, because `folded` covers only standalone windows, never group leaders. One real window stays tracked as two. That is the CR-02 class from iteration 1, and it now has no way to correct itself.

The window for this needs only two tab actions inside one refresh interval: Cmd-T or a background tab plus a tab switch. That interval is at least the 75 ms cancel-latest debounce, which each new hint extends. It is longer while a confirm refresh (up to 1 s, an accepted 02-15 limit) or an in-flight observe holds the pid. Typing Cmd-T then Ctrl-Shift-Tab fits. The tests check refusal only for a non-leader `v` whose new group takes untracked windows (`aMemberWhoseTabCountDiffersFromItsGroupsLeavesItWhileTheShownTabIsStillThere`).

**Fix:** Only proof that the windows are on different Spaces should refuse a rebind. A count change alone is Cmd-T, a background tab or a closed tab. Without Space data, the C5 variant this lets through is already the accepted single-Space limit. A refused member must also never found a group out of its old group's tabs or under its leader:
```swift
func mayRebind(_ group: Group, _ v: (id: UInt32, frame: Rect, tabCount: Int)) -> Bool {
    !Self.differ(space(v.id), group.spaces)
}
...
if let member = index, list[member].shown != v.id, v.tabCount >= 2, !mayRebind(list[member], v) {
    list[member].members.remove(v.id)
    (refused, index) = (member, nil)
}
// A refused member's new group never takes the refused group's tabs, and never reuses an existing leader.
let pool = refused.map { r in candidates.filter { !list[r].members.contains($0) } } ?? candidates
let leader = standalone.first { members.contains($0.windowID) }
    ?? (list.contains { $0.leader.windowID == v.id } ? nil : WindowIdentity(windowID: v.id, pid: pid, bundleID: bundleID))
```
(Use `pool` where `foldable` reads `candidates`, and skip the new group when `leader` is nil.) As a backstop, line 196 should tolerate duplicates: `Dictionary(list.map { ($0.leader, $0.tabCount) }, uniquingKeysWith: max)`. Dropping the count check inverts `aMemberWhoseTabCountDiffersFromItsGroupsLeavesItWhileTheShownTabIsStillThere`, which then needs a Space-data variant to keep the refusal covered. Add D1 and D2 as `TabScenarioTests` in all three modes, together with the invariant that no two groups share a leader or a member.

## Warnings

### WR-01: A sweep's CG snapshot taken before the AX read defeats the Cmd-T rule: the opener and the new tab are tracked as two windows, then the opener is reported destroyed

**File:** `Sources/PaneMac/AXWindowSystem.swift:220-230, 250-251`, `Sources/PaneEngine/TabGroupTracker.swift:115, 131-132, 190-191`

**Issue:** `sweep` takes one `CGWindowList.snapshot()` (line 224) before any app thread's AX read. If Cmd-T lands between that snapshot and the pid's `observe`, AX lists the new tab N, but the CG list still has the opener A onscreen and no N. In that update, A is not an offscreen candidate, so `opener` is nil. N founds a group under its own identity. `lastListed` becomes {N}. From then on A is never "listed last refresh", so the Cmd-T rule never fires for it again. Real tracker (Probe4 `race`):
```
R1 stale-CG: [(10, 10, 1), (40, 40, 2)]   created 40
R1 next3:    [(10, 10, 1), (40, 40, 2)]        // one tab group, two rows, for as long as tab 40 stays shown
R1 click10:  [(10, 10, 1), (40, 10, 2)]
R1 again:    [(40, 10, 2)]   DESTROYED 10      // the older identity, the one the layout had, is reported gone
```
This happens with or without Space data: N has no Space entry, because the Space lookup reads the same stale list (line 332). The hint refresh that follows does not repair it. FakeWindowSystem always builds the CG list and AX from one state, so no scenario test can see this. This is the behavioural consequence of the old IN-05: the comment at line 250 ("Read after AX answered") is still false for sweeps.

**Fix:** In `refresh`, when the sweep's `cgWindows` lacks any window ID that `observation` lists, read a fresh `CGWindowList.snapshot()` for that pid after AX answered (both the Space lookup and the tracker use it). As a defence in the engine, `TabGroupTracker.update` should not found or rebind a group for a `v` whose ID is not in `inCG`, and should not update `lastListed` or `lastCG` for that pid on such an update. Add R1 to the tracker tests.

### WR-02: A failing element still switches `_AXUIElementGetWindow` off for every app, through tab or Space switches

**File:** `Sources/PaneMac/AX/WindowIDResolver.swift:55, 71-76`, `Sources/PaneMac/AX/AXSnapshotReader.swift:41-61`

**Issue:** `failed` is pruned on every resolve to the elements in AXWindows (line 55). But AXWindows leaves out the same element for ordinary reasons: a hidden native tab, and every window on another Space. The element is still cached, and still tracked through the `known` loop in `AXAppThread.observe`. When it is listed again it is not in `failed`, so it records a new failure. Successes come only from new elements and re-checks, and cached `.axPrivate` windows record none (a deliberate 02-16 choice). So with one fallback-identified element whose lookup keeps failing, five tab switches back to it, or five Space round trips, switch the lookup off for the session. No new window has to open in between. This is the exact outcome the WR-03 fix was meant to prevent, and `aFailingElementCountsAgainOnlyAfterItLeftAXWindows` pins it as intended. The plan's premise (02-16-PLAN line 203) was that a reappearing element is a new element. For tabs and Spaces it is the same cached element.

**Fix:** Prune `failed` to the elements still in the cache (listed or carried as known), not to the listed elements:
```swift
failed.removeAll { element in !items.contains { CFEqual($0.element, element) } && !cache.values.contains { CFEqual($0.element, element) } }
```
Add a resolver test: one failing element is listed, unlisted while cached, then listed again, five times, and the capability stays on.

## Info

### IN-01: `ClosedIDCache` is dead state, and its doc comments are swapped (carried)

**File:** `Sources/PaneEngine/CloseRule.swift:60-85`, `Sources/PaneEngine/WindowTracker.swift:20, 51, 173, 247, 374`

**Issue:** The tracker writes the cache (insert, remove, purge, and now `rekey` too), but nothing reads `contains` outside the tests. "True while `now < closed + ttl`" still sits above `remove`.

**Fix:** Delete the cache or use it, and fix the comments.

### IN-02: The menu header count and Tracked Windows use different window filters (carried)

**File:** `Sources/PaneMac/Shell/StatusItemController.swift:99-100` vs `Sources/PaneMac/Shell/TrackedWindowsModel.swift:37, 77`

**Fix:** Use one filter in both places.

### IN-03: The `where` clause in `PermissionReducer` guards only the second pattern (carried)

**File:** `Sources/PaneEngine/PermissionReducer.swift:110`

**Fix:** Split it into two `case` labels.

### IN-06: Starting while locked marks the initial refresh complete without one (carried)

**File:** `Sources/PaneMac/AXWindowSystem.swift:126-127, 236-239`

**Fix:** Set `initialRefreshComplete` only after a sweep has actually run.

### IN-07: `concurrentReadsAgree` cannot fail (carried)

**File:** `Tests/PaneMacTests/CapabilitiesTests.swift:61-68`

**Fix:** Interleave `recordFailure` writers, or delete the test.

### IN-08: Revoking Accessibility while Pane runs is not detected (carried)

**File:** `Sources/PaneMac/Permission/PermissionController.swift:55-73`

**Fix:** Treat `.apiDisabled` from several apps as a permission event.

### IN-09: `resumeRecordedPID` sends SIGCONT to a recorded PID that may have been reused (carried)

**File:** `Sources/PaneMac/Shell/FreezeTest.swift:63-71`

**Fix:** Store the process start time or bundle ID with the PID, and check them before resuming.

### IN-10: The live probe loop is untested, and the fake probes inline (carried)

**File:** `Sources/PaneMac/AXWindowSystem.swift:297-313`

**Fix:** Pull the loop into a driver with an injectable clock.

### IN-11: Per-window registration retries cannot be cancelled and differ from the app-level rule (carried)

**File:** `Sources/PaneMac/AX/AXAppThread.swift:139-143, 315-326`

**Issue:** The retry loop does not check `isStopped`. The app level still retries `.notificationUnsupported` for ever (the `shortcut:` comment notes it). Nothing tests either.

**Fix:** Check `isStopped` between registrations, cap the retries per element, and drop `.notificationUnsupported` at app level too.

### IN-12: Stale doc comment on the AXAppThread cache (carried, partly resolved)

**File:** `Sources/PaneMac/AX/AXAppThread.swift:34`

**Issue:** `windows` is still described as "each registered for the per-window notifications", but registration can be pending in `unregisteredWindows`.

**Fix:** Update the comment.

### IN-13: An ID correction that chains within one refresh, or whose holder is not listed, gives one window's entry to another

**File:** `Sources/PaneEngine/WindowTracker.swift:55-60, 231-249`, `Sources/PaneMac/AX/AXAppThread.swift:186-197`

**Issue:** `ingest` applies `replacesWindowID` re-keys one at a time, in AX order. Probe4d: E2 is tracked as synthetic 900, and H holds 20 through a wrong frame match (20 is E2's real ID). The lookup returns E2 → 20 and H → 30. E2's re-key runs first and merges into H's entry, and the next re-key moves that entry to 30:
```
rekeyed 900 -> 20 / rekeyed 20 -> 30 / created 20
after: [(20, "E2", 3), (30, "H", 1)]   // E2 is a new window; H has E2's creation order and both refs
```
Also, if the holder is not listed when the owner's lookup claims its ID (the holder is on another Space), the holder is never re-identified. The `known` loop drops its element, because `cache[id]` is already the owner, and the owner's observation silently takes over the holder's tracked entry. Both need a wrong frame match, which now requires two lookup failures in a row on a new window. That is rare, so this is Info.

**Fix:** Apply every re-key of one refresh as a single permutation: remove all `from` entries first, then insert them under their `to` IDs. When a lookup claims an ID whose cached holder is not in `items`, drop the holder's tracked ID (emit a re-key to a fresh synthetic ID) rather than letting the owner inherit it.

### IN-14: The blind-switch protection depends on whether a Space batch answered, not on whether the shown window has a Space

**File:** `Sources/PaneEngine/TabGroupTracker.swift:88, 116, 148-154`, `Sources/PanePrivate/SkyLightSpaces.swift:37-47`

**Issue:** `blindSwitch` is `spaceChanged && spaces == nil`. Suppose the batch answered for some of the pid's windows but `SLSCopySpacesForWindows` returned NULL for the newly shown window, which is then left out of the map. Then `space(v.id)` is empty, `differ` can never refuse, and the blind-switch refusal is off. Probe4 `orphan` (scenario O1): with a non-nil map that has no entry for the shown twin 50, the closed group passes its identity to 50 (`[(30, 50, 1)]`). Without any Space data, or with 50 answered, it does not. A live onscreen window has always answered so far, so this is Info.

**Fix:** Treat a window missing from a non-nil map as "no Space data" for the rules that read it: `let blindSwitch = spaceChanged && (spaces == nil || spaces?[v.id] == nil)`, evaluated per `v`.

### IN-15: A doc comment sits on the wrong function in WindowTracker

**File:** `Sources/PaneEngine/WindowTracker.swift:396-405`

**Issue:** The `hasPendingWindows` comment ("True while a window of `pid` is withheld waiting for its settle delay") sits above `awaitsMinimumConfirmation`, and `hasPendingWindows` has none.

**Fix:** Move the first line down to `hasPendingWindows`.

---

_Reviewed: 2026-10-25T20:51:25Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
