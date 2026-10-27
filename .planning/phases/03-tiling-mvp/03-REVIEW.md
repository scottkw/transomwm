---
phase: 03-tiling-mvp
reviewed: 2026-10-27T00:50:29Z
depth: standard
scope: "gap-closure diff since 53d5faa (plans 03-18..03-22, PANE_LIVE opt-in gate, scripts/vm-live-test.sh); replaces the earlier full phase-3 review"
diff_base: 53d5faa
files_reviewed: 9
files_reviewed_list:
  - Sources/PaneEngine/Arranger.swift
  - Sources/PaneEngine/MinimumSizeLearner.swift
  - Sources/PaneEngine/PendingFocus.swift
  - Sources/PaneEngine/Planner.swift
  - Sources/PaneMac/AXWindowSystem.swift
  - Sources/PaneMac/CGWindowList.swift
  - Sources/PaneModel/TreeEdits.swift
  - scripts/vm-live-test.sh
  - Tests/PaneMacIntegrationTests/IntegrationSupport.swift
findings:
  critical: 2
  warning: 5
  info: 3
  total: 10
status: issues_found
---

# Phase 3: Code Review Report (gap-closure diff since 53d5faa)

**Reviewed:** 2026-10-27T00:50:29Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

This review covers only the changes made since `53d5faa` (`git diff 53d5faa HEAD`): plans 03-18 to 03-22 (G-03-3, G-03-4, G-03-5, G-03-6), the `PANE_LIVE=1` opt-in gate for the live AX suites, and `scripts/vm-live-test.sh`. It replaces the earlier full phase-3 review that was in this file. I also read the code these changes call (`InputTap`, `GreenButton`, `WindowTracker`'s learner and bundle-hint path, `MinimumHintsStore`, `planShown` / `planFloatingLostRoom`, `TreeEdits.commit` / `normalize`).

The four fixes do what their summaries say on the paths they were tested on. Two of them have side effects that will cause real harm:

- **G-03-4 (CR-01).** The layer-0 filter skips every window that is not at layer 0, not only the Dock's full-screen overlay. A click on a menu item, a context-menu item, or a Dock icon that sits over a green button is now eaten, and Pane docks or floats the window underneath.
- **G-03-6 part 2 (CR-02).** For the first time, a fixed-size window can now be learned. Its size is merged into the per-bundle hint, which only ever grows and is saved to disk. One Welcome or About window then sets the minimum for every window of that app, permanently. The 03-22 VM run already wrote `com.apple.reminders width 768` this way.

The other findings: the live gap move silently reverts lost-room floats, so the notice repeats on every drag event (WR-01). The Planner's greedy floater drop removes more floaters than it needs to and is biased against width-only hints (WR-02). The retry state has a gap when a window is docked again into the same tile (WR-03). The VM script has robustness problems (WR-04, WR-05).

The `PANE_LIVE` gate itself is correct. All 21 integration suites go through `IntegrationEnv.trusted`, and nothing else in Sources, Tests, scripts or CI still reads `PANE_SKIP_AX_INTEGRATION`.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: The green-button fallback now eats clicks meant for menus, context menus and the Dock

**File:** `Sources/PaneMac/CGWindowList.swift:27-29` (called from `Sources/PaneMac/Input/InputTap.swift:134-140`)

**Issue:** `topmost(at:in:excludingPID:)` returns the first entry that is at layer 0 and contains the point. It skips every non-zero layer, not just the Dock's full-screen layer-20 overlay that G-03-4 was about. Before this change, any window in front of the green button blocked the swallow. The session tap's window field is always 0 (03-11), so every press inside a green-button rect now resolves to the app window underneath. That includes presses on:

- menu-bar dropdowns and context menus (layer 101). The first items of the app menu or File menu ("About …", "Settings…") lie right over the green button of a window docked at the top-left: window at (12, 37), button rect about x 58–74, y 43–59.
- Dock icons (layer 20) when the Dock is on the left or auto-hidden.
- popovers, Notification Center banners, and Control Center or status-item menus over a right-side tile.

`GreenButton.shouldSwallow` then returns true. The menu or Dock never gets the click, and Pane toggles dock/float on an unrelated window. T-03-52 accepted this for "another app's panel". Menus and the Dock are much more common than panels, and that acceptance did not consider them. This is a regression introduced by this diff.

**Fix:** Skip only see-through overlays that cover a whole display. Any other window above layer 0 that contains the point owns the click. `CGDisplayBounds` is safe to call on the tap thread.
```swift
static func topmost(at point: Point, in list: [CGWindowEntry], excludingPID own: Int32, displays: [Rect]) -> UInt32? {
    for entry in list where entry.pid != own && entry.alpha > 0 && entry.bounds.contains(point) {
        if entry.layer == 0 { return entry.windowID }
        // The Dock's full-screen layer-20 window (macOS 15, G-03-4) covers a whole display: look through it.
        if displays.contains(where: { $0 == entry.bounds }) { continue }
        return nil  // a menu, Dock tile, popover or banner is on top: never swallow
    }
    return nil
}
```
Add `TopmostWindowTests` cases for a layer-101 menu entry and a small layer-20 Dock-tile entry listed before the layer-0 window. Both should give nil. Also consider not skipping Pane's own layer-101 status-menu window. That is an older version of the same problem.

### CR-02: A fixed-size window now writes a permanent, grow-only minimum for its whole app

**File:** `Sources/PaneEngine/MinimumSizeLearner.swift:59-73` (the new unmoved-promotion path), together with `Sources/PaneEngine/Arranger.swift:584-598` (`retryRefusal`). The minimum spreads through `Sources/PaneEngine/WindowTracker.swift:165-172`, `Sources/PaneMac/AXWindowSystem.swift:436-440` and `Sources/PaneMac/MinimumHintsStore.swift:61-68`.

**Issue:** Before 03-22, a window that never moves when written to was never learned. 03-22 adds two pieces: (a) an unmoved refusal that repeats at least 1 s later is promoted to a candidate, and (b) the Arranger itself sends that repeat write. A fixed-size window (Welcome, About, onboarding, a fixed settings window) therefore now always confirms its own size as a "minimum". From there the value:

1. is merged into `bundleHints[bundleID]` for the rest of the session (WindowTracker 170-171);
2. is reported through `onLearnedMinimum` and saved to `min-size-hints.json` per bundle (AXWindowSystem 439, PaneMacApp 44-50);
3. only ever grows (`record` and `seed` take the max), and nothing in the code resets it.

As a result, every later window of that app, including resizable main windows whose real minimum is much smaller, starts with the fixed window's size. D-26 then refuses to dock them, or floats them, whenever the tile is narrower. The 03-22 VM run shows this happening: `min-size-hints.json` gained `{'bundleID': 'com.apple.reminders', 'width': 768}` from the Welcome window. The run only got rid of it by copying the old file back. On a user's Mac it would stay. The same path also learns any window of an app that stays unresponsive for more than about 2 s, which the doc comment admits as a "Known limit". Pane's own retry makes that case easy to hit, and this per-bundle spread turns it into permanent damage.

**Fix:** Keep minimums learned from unmoved refusals per window and for the current session only. Never merge them into bundle hints or persist them. Only refusals where the window moved toward the request should feed D-13. For example:
```swift
private struct Candidate { var width: Double?; var height: Double?; var writtenAt: ContinuousClock.Instant; var unmoved: Bool }
// confirm(...) -> (minimum: Size, persistable: Bool)?
// WindowTracker: update bundleHints and set info.learnedMinimumIsPersistable only when persistable;
// AXWindowSystem.emit: call onLearnedMinimum only for persistable minimums.
```
Alternatively, before promoting an unmoved refusal, check that the window is resizable at all (`AXUIElementIsAttributeSettable(kAXSizeAttribute)` or a grow area). Also give users a way to reset a bundle's hint, because learned values can never shrink.

## Warnings

### WR-01: During a live gap drag, lost-room floats are undone and the notice repeats on every drag event

**File:** `Sources/PaneEngine/Arranger.swift:1301-1315` and `1189-1194`

**Issue:** After G-03-3 H2, every `replan()` call made during a gap drag goes through `replan(with:on:)`. That function runs `planShown()` on a temporary World and restores it with `defer { world = committed }`. `planShown` calls `planFloatingLostRoom`, which floats unfit docked windows by changing `world` (`World.reflow`). Those floats are now thrown away, for every shown display, not just the dragged desk. The `.notice(.lostRoom)` and the `setFrame` commands for the post-float layout are still emitted.

The next drag event, at pointer rate, finds the same window unfit again, floats it again on a fresh temporary World, and emits the notice again. Mouse-up then floats it for real. This can happen whenever a docked window becomes unfit mid-drag: a minimum confirmed by the learner or by the new `retryRefusal`, an un-minimise, or a display change on another screen. The comment at 1192 ("weights never make a window unfit, so replan floats nothing here") was true only for the original edge-resize use. It no longer holds now that every event's replan goes through this path.

**Fix:** In the live path, do the lost-room float on the committed World first, then apply the gap move. For example, run `planFloatingLostRoom` (or a pass that only floats) on `world` before taking the `committed` snapshot. Or have `replan(with:on:)` keep any tree changes `planFloatingLostRoom` made and revert only the weight change. Add a test: during a gap drag, a learned minimum that leaves a window unfit floats it once, gives one notice, and later drag events give no notice.

### WR-02: The Planner's greedy floater drop removes more floaters than needed, and drops width-only hints last

**File:** `Sources/PaneEngine/Planner.swift:23-40`

**Issue:** Floaters are dropped in descending order of `min.width * min.height`, and a dropped floater is never added back. Two consequences:

1. **Over-dropping.** Suppose floaters A (300×600) and B (768×200) sit beside docked W (642 wide) on 1024 pt. B's width is the problem, but A has the larger area, so A goes first. W is still unfit, so B goes next. Now A no longer sizes the Desktop, even though it would fit next to W. A is then clamped below its own minimum and overlaps a tile (T-03-58), without any need.
2. **Single-axis hints sort last.** A learned minimum with one axis still at 0 has area 0. The under-32 pt rule in 03-22 produces these, for example Reminders' `768×0`. Such a floater is always dropped last, after every two-axis floater, even when it is the only one causing the problem.

**Fix:** After the loop, try to add back each dropped floater, in reverse drop order. Keep it if `unfit` is still a subset of `baselineUnfit`:
```swift
var dropped: [(window: WindowRef, min: Size)] = []
while !resolution.unfit.isSubset(of: baselineUnfit) { dropped.append(sizing.removeFirst()); resolution = try resolved(sizing) }
for floater in dropped.reversed() {
    let trial = try resolved(sizing + [floater])
    if trial.unfit.isSubset(of: baselineUnfit) { sizing.append(floater); resolution = trial }
}
```
Or order the drops by how far each floater's minimum goes past the room the Desktop can have on the axis that overflows, not by area. Add a PlannerTests case for each of the two consequences.

### WR-03: `refusalRetried` is never cleared, so a window docked again into the same tile is never retried or learned

**File:** `Sources/PaneEngine/Arranger.swift:587-598` (state at 123; cleared only in `forget` at 540)

**Issue:** The entry is keyed by the exact tile `Rect`, and it is removed only when the window is forgotten. Take a refused window whose minimum was not learned the first time: the app was late at the confirm, or the refresh fell through `dropDue`. It stays docked and overlapping. If the user floats it and docks it again into the same layout, the deterministic Planner produces the identical rect. `refusalRetried[id] == requested`, so there is no retry. With no repeat write, the learner's unmoved record is never promoted. That window can then never be learned at that tile, which is exactly the G-03-6 overlap this plan was meant to remove.

**Fix:** Clear the entry when the window leaves the tree, and when a write fits its tile:
```swift
// in retryRefusal, before the guard's overflow test:
if actual.width <= requested.width + margin, actual.height <= requested.height + margin { refusalRetried[id] = nil }
// and wherever a window is undocked/floated (float, commitUndock, planFloatingLostRoom): refusalRetried[id] = nil
```

### WR-04: `vm-live-test.sh` says "VM busy" on a fresh checkout

**File:** `scripts/vm-live-test.sh:21-22`

**Issue:** `mkdir .build/pane-vm.lock` fails when `.build/` does not exist yet, for example on a fresh clone or after `swift package clean`. The script then prints "VM busy (.build/pane-vm.lock exists)" and exits, which points the user at the wrong problem. `.build` is only created later, at line 25.

**Fix:**
```bash
mkdir -p .build
mkdir .build/pane-vm.lock 2>/dev/null || { echo "vm-live-test: VM busy (.build/pane-vm.lock exists)" >&2; exit 1; }
```

### WR-05: An interrupted VM run leaves Pane quit and fixture apps running in the guest

**File:** `scripts/vm-live-test.sh:36-47`

**Issue:** The remote cleanup (`pkill -x PaneFixtureApp`, relaunching Pane) runs only if the test helper returns normally. A Ctrl-C, an SSH drop, or the helper hanging and being killed all skip it. The guest is then left with Pane not running and PaneFixtureApp windows open, and the next UAT or live run on that guest starts from a dirty desk. The local `trap` releases only the local lock. Also, `osascript … quit` followed by a fixed `sleep 2` does not check that Pane actually quit. If Pane quits slowly, it is still tiling while the fixture suites run.

**Fix:** Put a `trap` in the remote script and wait for Pane to exit:
```bash
ssh ... "
  cleanup() { pkill -x PaneFixtureApp || true; [ -n \"\$was_running\" ] && open -a /Applications/Pane.app; }
  trap cleanup EXIT HUP INT TERM
  ...
  [ -n \"\$was_running\" ] && osascript -e 'quit app \"Pane\"' && for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Pane >/dev/null || break; sleep 0.5; done
"
```
Consider `ssh -t` so a Ctrl-C reaches the remote process group.

## Info

### IN-01: Comments no longer describe the code after 03-20 and 03-21

**File:** `Sources/PaneEngine/Arranger.swift:1192`, `Sources/PaneEngine/Arranger.swift:1426-1429`

**Issue:** "weights never make a window unfit, so replan floats nothing here" stopped being true once every replan goes through this function during a gap drag (see WR-01). `planFloatingLostRoom`'s doc still says "A floated window's minimum sizes the Desktop tile, which can leave a neighbour without room in turn, so this repeats". Since 03-21, the Planner drops a floater that would push a docked window out, so that cascade no longer happens.

**Fix:** Update both comments, or remove them, along with the WR-01 fix.

### IN-02: `setWeights` says it normalises to sum 1, but `commit` also clamps to `minWeight`

**File:** `Sources/PaneModel/TreeEdits.swift:241-250`

**Issue:** `commit` calls `normalize()`, which clamps every weight to at least `minWeight` (0.01). A re-based share below 1 % therefore does not come out as the caller passed it, and the caller cannot tell. In `boundaryChange`, the `resizeBetween` delta that follows is then computed against weights that were not actually stored. The effect is tiny today.

**Fix:** Either reject weights below `minWeight` in the guard, or say in the doc comment that they are clamped.

### IN-03: `vm-live-test.sh` relies on word splitting and string interpolation for its SSH options and arguments

**File:** `scripts/vm-live-test.sh:18, 35, 42-43`

**Issue:** `-e "ssh ${ssh_opts[*]}"` breaks when the key path contains a space. Extra `VAR=value` arguments (`$*`) and the filter (`'$filter'`) are pasted into the remote shell string unquoted or single-quoted, so a value containing a space or a `'` breaks the remote command. These values come from the operator, not from outside, so this is about robustness, not security. Host-key checking is off (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`). That is acceptable for a local Tart VM, but it should be stated in the script's header.

**Fix:** Escape the remote arguments with `printf '%q '`, for example `remote_env=$(printf '%q ' "$@")` and `filter_q=$(printf '%q' "$filter")`, and pass `-e "ssh $(printf '%q ' "${ssh_opts[@]}")"` to rsync.

---

_Reviewed: 2026-10-27T00:50:29Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
