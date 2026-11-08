---
phase: 07-tab-groups
reviewed: 2026-11-01T00:00:00Z
depth: standard
files_reviewed: 38
files_reviewed_list:
  - Sources/TransomEngine/Arranger+Camera.swift
  - Sources/TransomEngine/Arranger+Commands.swift
  - Sources/TransomEngine/Arranger+Tabs.swift
  - Sources/TransomEngine/Arranger.swift
  - Sources/TransomEngine/Command.swift
  - Sources/TransomEngine/DragSession.swift
  - Sources/TransomEngine/ExclusionFilter.swift
  - Sources/TransomEngine/Planner.swift
  - Sources/TransomEngine/TransomURL.swift
  - Sources/TransomEngine/ViewPlanner.swift
  - Sources/TransomEngine/WindowSystem.swift
  - Sources/TransomMac/AX/AXAppThread.swift
  - Sources/TransomMac/AXWindowSystem.swift
  - Sources/TransomMac/ArrangeController.swift
  - Sources/TransomMac/Input/Hotkeys.swift
  - Sources/TransomMac/Overlay/PreviewStyle.swift
  - Sources/TransomMac/Overlay/TabStripLayout.swift
  - Sources/TransomMac/Overlay/TabStripPanels.swift
  - Sources/TransomMac/Overlay/TearOffGhost.swift
  - Sources/TransomMac/Overview/OverviewController.swift
  - Sources/TransomMac/Shell/CommandMenu.swift
  - Sources/TransomMac/Shell/MenuCopy.swift
  - Sources/TransomMac/Shell/StatusItemController.swift
  - Sources/TransomMac/Shell/TabCopy.swift
  - Sources/TransomMac/Zoom/CollapsedPanels.swift
  - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
  - Sources/TransomMac/Zoom/StagePanel.swift
  - Sources/TransomMac/Zoom/TileLayer.swift
  - Sources/TransomMac/Zoom/ZoomController.swift
  - Sources/TransomMac/Zoom/ZoomInput.swift
  - Sources/TransomModel/DesktopLayer.swift
  - Sources/TransomModel/DropZones.swift
  - Sources/TransomModel/Resolve.swift
  - Sources/TransomModel/TabBand.swift
  - Sources/TransomModel/TreeEdits.swift
  - Sources/TransomModel/World.swift
  - Sources/TransomTestSupport/FakeWindowSystem.swift
  - Tests/TransomEngineTests/ArrangerTabsTests.swift
findings:
  critical: 1
  warning: 4
  info: 7
  total: 12
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-11-01
**Depth:** standard
**Files Reviewed:** 38 (all 37 Phase 7 source files, plus `ArrangerTabsTests.swift`, checked for coverage of the findings)
**Status:** issues_found

## Summary

I reviewed the Phase 7 diff (`git diff 9698f23 HEAD`) for every Sources/ file in scope. I traced these paths: the model (`DesktopLayer` groups, `TreeEdits` whole-leaf edits, `Resolve` hidden tabs, `World.validate`/`undo`), the engine (`Arranger+Tabs`, the drag, hover and drop changes, Planner parks and sizes, replan, rehome, exclusion release, quit and Restore All), and the shell (strip panels, event-tap strip detection, AX close/minimise/raise, quit restore).

The model layer is solid:
- A hostile or old layout.json is handled. `groups` decodes only if present, and `DesktopLayer.validate` / `World.validate` check member counts, selections, duplicates, ID ranges and ID collisions with tree nodes.
- Every edit is checked before it mutates.
- Every whole-group move goes through one `World.edit`.

The main risk is window stranding. Hidden tabs sit permanently at the 1 pt `parkedFrame` sliver, so any path that stops Transom from managing a parked window strands it. Excluding an app does exactly that, and nothing recovers the window, not even quit. Two other paths, an absent selected member and a failed reveal, leave windows parked, or keyboard focus on a parked window, with nothing on screen to recover from.

Concurrency and MainActor isolation are fine. Strip panels, timers and AX notifications all hop to main or use `assumeIsolated` on main-queue callbacks. AX write ordering is also correct: Close Group waits for the reveal read-back before it presses close, and quit raises run after each app's writes.

## Critical Issues

### CR-01: Excluding an app strands its hidden tabs off screen for good (quit restore included)

**File:** `Sources/TransomEngine/Arranger.swift:1114-1121`, `Sources/TransomEngine/Arranger.swift:2016`, `Sources/TransomMac/AXWindowSystem.swift:185-190`, `Sources/TransomMac/AXWindowSystem.swift:263-270`

**Issue:** A hidden tab is parked at `DisplayInfo.parkedFrame` (a 1 pt sliver past the bottom-right corner). When its app becomes excluded ("Don't Arrange" on the frontmost app, or an exclusions list edit), these steps follow:

1. `AXWindowSystem.setExcludedBundleIDs` sets `thread.excluded = true` first, which drops every pending frame, and only then emits `windowChanged`. From that point no command for the app ever reaches AX.
2. If the member is docked, `release(_:)` takes it out of its group (`desk.tree.remove`). It then adds it to the Desktop layer at `info.frame`, which is the parked off-screen frame (`desk.desktop.add(info.window, frame: info.frame)`).
3. If the member is floating, nothing removes it from its `FloatingTabGroup`. The parks loop skips excluded windows (`windows[window.identity]?.isExcluded == false`), so `parkRequested` drops it, and it stays a hidden member at the sliver. Its tab still shows in the strip, but selecting it can never read back (the `setFrame` is dropped), so the select reverts after 1 s.
4. Restore All skips it (`rescueStranded` filters `!info.isExcluded`). The quit restore also skips it (`ExclusionFilter.isExcluded` in `restoreForTermination`).

The window is effectively lost until the user un-excludes the app. Even then, a floater at the sliver is "clear of every tile", so the Planner leaves it there. Phase 4 camera parks have the same latent problem, but Phase 7 makes parking permanent for every hidden tab. Grouping a second window of an app you use elsewhere and then excluding that app is a normal sequence. The tests cover an excluded member's *close* (`anExcludedMembersCloseNeverReachesTheSystem`), but not its exclusion while hidden.

**Fix:** Unpark before the exclusion takes effect, and take the window out of its group in both layers.

```swift
// AXWindowSystem.setExcludedBundleIDs: let the engine release first, then flip the threads.
public func setExcludedBundleIDs(_ bundleIDs: Set<String>, releasing: [WindowRef: Rect] = [:]) {
    for (ref, rect) in releasing { threads[ref.pid]?.enqueueFrame(windowID: ..., rect: rect, ref: ref) } // before the flip
    excluded = bundleIDs
    ...
}
// Arranger: a query the shell calls before the change.
public func releaseFrames(forExcluding bundleIDs: Set<String>) -> [WindowRef: Rect] {
    // every parked window (hidden tab or camera-parked) of those bundles -> its group content rect / homeFrame
}
// release(_:) and a new floating-group branch: remove the window from its group, and add it to the Desktop at
// the group's content rect (not info.frame) when it was a hidden member.
```

Add an engine test that excludes a hidden member, both docked and floating. It should assert that the window's last command is a `setFrame` on screen and that it is no longer in any group.

## Warnings

### WR-01: The reveal read-back needs every edge within 2 pt; apps that snap size (Terminal, iTerm) can never be selected, and a failed reveal leaves focus on a parked window

**File:** `Sources/TransomEngine/Arranger+Tabs.swift:480-488`, `Sources/TransomEngine/Arranger+Tabs.swift:492-509`, `Sources/TransomEngine/Arranger.swift:2046`

**Issue:** `revealed(_:actual:now:)` ends a selection only when `Planner.near(actual, planned, within: 2)` holds. That checks x, y, width and height all within 2 pt. Docked windows elsewhere may overshoot their tile by up to `MinimumSizeLearner.refusalMargin` (32 pt). Terminal-style apps round their size to whole character cells, and a window with an unlearned minimum above the content rect refuses to shrink. In both cases width or height misses by more than 2 pt, so every selection of that member times out after 1 s and reverts with a beep and "Couldn't show". Close Tab and Close Group of such a hidden member stop the same way (`revealTimedOut` clears `closeQueue`).

On top of that, replan sent `.focus(revealed)` with the reveal's `setFrame`. `revealTimedOut` re-selects `previous` but never focuses it back. Keyboard focus therefore stays on the revealed window, which the same replan then parks, so the user types into an invisible window.

**Fix:** Match the reveal on origin, with a size test no stricter than the docked correction's:

```swift
let t = 2.0, m = MinimumSizeLearner.refusalMargin
let landed = abs(actual.x - planned.x) <= t && abs(actual.y - planned.y) <= t
    && actual.width <= planned.width + m && actual.height <= planned.height + m
```

In `revealTimedOut`, also add `.perform([.focus(pending.previous)])` when `previous` is present. Add a test with a read-back that is 10 pt short in height.

### WR-02: When a group's selected member goes absent, its present hidden members stay parked with no strip, no tile, and focus may land on them

**File:** `Sources/TransomModel/Resolve.swift:139`, `Sources/TransomEngine/Planner.swift:93`, `Sources/TransomEngine/Arranger+Tabs.swift:611-617`, `Sources/TransomEngine/Arranger.swift:860`

**Issue:** A group takes part only while its selected member is present. Several things make the selected member absent: ⌘M or the yellow button on it, its app being hidden with ⌘H, native full screen, or the strip's Minimize Group (which minimises only the selected member). When that happens:
- The leaf gets no rect and no `hiddenTabs`, and the floating-group loop skips the group.
- The other members' park entries drop, but nothing moves them, so they stay at the 1 pt sliver. The strip goes, and the tile collapses into its neighbours.
- If the minimised window's app has another member in the group, macOS focuses that parked member at once. `suppressFocus` deliberately ignores that focus for 1 s, and no further `windowFocused` arrives because it is already focused. The user ends up with an invisible key window.

The 07-05 summary records the "stays parked" fact, but nothing on screen shows that the windows exist. Only ⌘-Tab to another member's app after the suppression window, a tab hotkey, or quit brings them back. D-06 asks only that Minimize Group restores with the same selected tab. It does not require hiding the other members for every other cause of absence.

**Fix:**
- For causes other than Minimize Group, i.e. a member absent without `minimizeGroup` having been sent, select a present neighbour the way `LayoutTree.remove` does for a close. That keeps the group on screen.
- Alternatively, keep the group participating with its hidden members' sizes, so a focused hidden member is still revealable.
- Either way, do not suppress `activated` when the focused hidden member is the only present member of its group.

### WR-03: Rehoming a group to another Space carries hidden members that physically stay on the old Space

**File:** `Sources/TransomEngine/Arranger.swift:1136-1170`

**Issue:** Suppose the user moves the selected member to another Space (Mission Control drag, Dock "Assign To", Move to Desktop N). `rehome` then takes the whole group (`takeGroup`) and adds it as a floating group on the new Space's desk. But the hidden members are windows on the *old* Space, and AX frame writes cannot move a window across Spaces. As a result:
- Each later `select` writes the member into the content rect on its own (old) Space. The read-back matches, so the previous member parks, and the strip on the new Space sits over an empty content rect.
- The old desk no longer holds the hidden members. `rehome` refuses to move them back (`!isHiddenTab(info.window)`), so they stay parked at the old Space's sliver.

The windows are not lost, since quit writes them on screen, but the group is broken until quit.

**Fix:** When the move crosses Spaces (`leftSpace`), carry only the selected member. Dissolve the group on the old desk, with the remaining members taking the leaf or frame there the way a close does, or move them out the way `dissolveAllGroups` does. Keep whole-group rehome for display moves within the same Space.

### WR-04: Switching tabs mid-drag parks the window under the pointer

**File:** `Sources/TransomEngine/Arranger.swift:2015-2027` (the parks loop), `Sources/TransomEngine/Arranger+Tabs.swift:442-473`

**Issue:** The `desired` loop never writes `drag?.window` (line 2042, D-23), but the parks loop has no such guard. Here is how it happens:
1. During a whole-group drag (the selected member's title bar is held), Next or Previous Tab is triggered from the hotkey, menu, URL or `activated` (D-08).
2. `select` makes the dragged window hidden.
3. The next replan sends `.park(dragged, size:)`, which moves the window out from under the user's pointer while the mouse button is still down.
4. Mouse-up then runs the drop with `movingGroup(window) == nil`, because the window is no longer the selected member. The single window is dropped, not the group.

**Fix:** Refuse `select`, `tabCommand` and `activated` for a group whose member is `drag?.window`, or skip `drag?.window` in the parks loop the same way the frames loop skips it.

## Info

### IN-01: A tear-off dropped into another group does not announce leaving, or dissolving, its own group

**File:** `Sources/TransomEngine/Arranger+Tabs.swift:816-817`
**Issue:** The `.group` branch of `releaseTearOff` returns `commitGroup`'s effects only. The `.dock` and float branches append `movedOut(...)`, which speaks "Moved out" and "Tab group ended" (D-12). A source group left with one window dissolves silently.
**Fix:** Append `movedOut(window, from: ref, landed: "grouped")` when `tabGroup(holding: window)?.key != ref.key` after the commit.

### IN-02: `CloseQueue`, `TearPress` and `tearing` are not rekeyed on `windowRekeyed`

**File:** `Sources/TransomEngine/Arranger.swift:833-842` (rekey branch)
**Issue:** `pendingReveal` is rekeyed, but `tabs.closeQueue.remaining` and `current`, `tabs.tearPress.member` and `tabs.tearing` are not. `WindowRef ==` compares identity, so a rekeyed member counts as closed (`windows[old.identity] == nil`). Close Group then skips it and reports one more closed window than it actually closed. This is safe (nothing is lost), but the count is wrong.
**Fix:** Map these fields through the rekey the same way `pendingReveal` is mapped.

### IN-03: The engine's `.command(.tabs)` path hard-codes `ready: true`

**File:** `Sources/TransomEngine/Arranger.swift:332`
**Issue:** The shell routes tab commands through `.tab(.command(...), ready:)`, but `.command(.tabs)` bypasses the readiness refusal. Any future caller of `handle(.command(.tabs(...)))` would act while Accessibility is not ready.
**Fix:** Fault or refuse with `.notReady` there, or have `ArrangerInput.command` carry readiness.

### IN-04: The `Resolve` unfit victim is ranked by the selected member's own minimum, not by the group's

**File:** `Sources/TransomModel/Resolve.swift:84`, `Sources/TransomModel/Resolve.swift:100-103`
**Issue:** `candidates` records the selected member's own `effective` minimum. `Solver.aggregate` uses the largest member's minimum plus `TabBand.height`. When a hidden member's minimum, or the band, is what fails to fit, other panels are tried as victims first. The maximality pass usually repairs the result, but the documented rule ("the window with the largest minimum on the violated axis becomes unfit") does not hold for groups.
**Fix:** For a tabs leaf, record the group's aggregate minimum in the candidate.

### IN-05: Floating group member frames are not checked against the group's content rect

**File:** `Sources/TransomModel/DesktopLayer.swift:177-197`
**Issue:** `validate()` checks `group.frame` but not that each member's stored frame equals `TabBand.content(of: group.frame)`. A hand-edited or corrupt layout.json can store them apart. The Planner places the selected member at its own frame, while `tabStrips` falls back to `group.frame`, so the strip can detach from its window until the first `setFrame`.
**Fix:** Either validate the equality, or normalise it in `World.init(from:)` (call `setMemberFrames` for every group after decoding).

### IN-06: Strip panels at `.normal` level are ordered front on every fade-in

**File:** `Sources/TransomMac/Overlay/TabStripPanels.swift:567-574`
**Issue:** `fadeIn` calls `orderFrontRegardless()`, which lifts the strip above every app window, including a floating window the user is using that overlaps a docked group's band. The engine rule ("strip comes front only on focus", `raisedStrip`) is weaker than what the panel actually does.
**Fix:** On a re-show, order the strip in at its previous position (`orderWindow(.above, relativeTo: selectedWindowNumber)`), and keep `orderFrontRegardless` for `raise(_:)`.

### IN-07: A layout.json written by Phase 7 opened by an older build drops floating groups and mis-reads docked tabs

**File:** `Sources/TransomModel/DesktopLayer.swift:215-231`
**Issue:** The schema stays at 2. An older build ignores `groups`, so the members become plain floaters stacked at one content rect. It also reads `.tabs` with Phase 1's "all tabs share one rect" meaning, so hidden members are written on top of each other. This is acceptable for an unreleased app, but worth recording before the first public release.
**Fix:** Bump the schema when groups are present, or document that downgrading is unsupported.

---

_Reviewed: 2026-11-01_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
