---
phase: 03-tiling-mvp
reviewed: 2026-10-26T14:42:37Z
depth: standard
files_reviewed: 55
files_reviewed_list:
  - Sources/PaneEngine/Arranger+Commands.swift
  - Sources/PaneEngine/Arranger.swift
  - Sources/PaneEngine/Command.swift
  - Sources/PaneEngine/DragSession.swift
  - Sources/PaneEngine/GapHandles.swift
  - Sources/PaneEngine/LayoutFile.swift
  - Sources/PaneEngine/LayoutRestore.swift
  - Sources/PaneEngine/LifecycleSync.swift
  - Sources/PaneEngine/Notice.swift
  - Sources/PaneEngine/Planner.swift
  - Sources/PaneEngine/WindowSnapshot.swift
  - Sources/PaneEngine/WindowSystem.swift
  - Sources/PaneEngine/WindowTracker.swift
  - Sources/PaneFixtureApp/main.swift
  - Sources/PaneMac/AX/AXAppThread.swift
  - Sources/PaneMac/AX/AXSnapshotReader.swift
  - Sources/PaneMac/AX/MenuPress.swift
  - Sources/PaneMac/AXWindowSystem.swift
  - Sources/PaneMac/ArrangeController.swift
  - Sources/PaneMac/CGWindowList.swift
  - Sources/PaneMac/Displays.swift
  - Sources/PaneMac/GapPreference.swift
  - Sources/PaneMac/Input/DragFramePoller.swift
  - Sources/PaneMac/Input/GreenButton.swift
  - Sources/PaneMac/Input/Hotkeys.swift
  - Sources/PaneMac/Input/InputTap.swift
  - Sources/PaneMac/LayoutStore.swift
  - Sources/PaneMac/Overlay/GapHandlePanels.swift
  - Sources/PaneMac/Overlay/NoticeQueue.swift
  - Sources/PaneMac/Overlay/PreviewPanel.swift
  - Sources/PaneMac/Overlay/PreviewStyle.swift
  - Sources/PaneMac/Overlay/Toast.swift
  - Sources/PaneMac/PaneMacApp.swift
  - Sources/PaneMac/Shell/CommandMenu.swift
  - Sources/PaneMac/Shell/MenuCopy.swift
  - Sources/PaneMac/Shell/NoticeCopy.swift
  - Sources/PaneMac/Shell/StatusItemController.swift
  - Sources/PaneModel/DesktopLayer.swift
  - Sources/PaneModel/IDs.swift
  - Sources/PaneModel/LayoutTree.swift
  - Sources/PaneModel/Neighbours.swift
  - Sources/PaneModel/Resolve.swift
  - Sources/PaneModel/Snap.swift
  - Sources/PaneModel/TreeEdits.swift
  - Sources/PaneModel/Undo.swift
  - Sources/PaneModel/World.swift
  - Sources/PanePrivate/SkyLightSpaces.swift
  - Sources/PaneTestSupport/FakeWindowSystem.swift
  - Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift
  - scripts/release.sh
  - xcode/project.yml
  - Sources/PaneEngine/PaneURL.swift
  - Sources/PaneMac/AppDelegate.swift
  - Sources/PaneEngine/Recovery.swift
  - Sources/PaneEngine/PermissionReducer.swift
findings:
  critical: 2
  warning: 6
  info: 9
  total: 17
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-10-26T14:42:37Z
**Depth:** standard
**Files Reviewed:** 55
**Status:** issues_found

## Summary

This review covers the 51 files in the phase-3 list. It also read four files outside that list, because the focus areas depend on them: `PaneURL.swift`, `AppDelegate.swift` (the URL scheme and the quit restore), `Recovery.swift` (crash and quit rules) and the Phase 2 `PermissionReducer.swift` (the root cause of the Accessibility grant finding). Items already logged in `deferred-items.md` are not reported again.

The model layer is careful and holds up well: copy-then-commit edits, validated decoding, iterative walks and typed throws. `TreeEdits`, `Resolve`, `Neighbours` and `Snap` showed no correctness defects. The URL parser is a strict whitelist. The event tap re-enables itself on `tapDisabledBy*` and does no AX work in its callback. The quit restore is bounded and off main.

The defects are in how the Engine's state stays in sync with the OS:

- **Undo** can silently drop a window from every desk.
- **Parking** puts windows onto a neighbouring display. This happens on the user's own two-display setup.
- **Desk keys** depend on a Space lookup that can switch off or return 0 partway through a session. When it does, existing desks are stranded.

Two of today's live findings have causes in this code:

- **Accessibility grant not picked up (WR-02):** the cause is confirmed. The reducer never polls on the plain launch path.
- **Safari not docking (WR-03):** the cause is a probable one that still needs one live log line to confirm. It points at the drag classifier.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Undo silently drops every window that joined the desk after the undone edit

**File:** `Sources/PaneModel/World.swift:236-255`, `Sources/PaneEngine/Arranger.swift:582-590`, `Sources/PaneEngine/Arranger.swift:685-690`
**Issue:** Undo restores the snapshot desk as it was, so any window that came onto the desk later disappears. Several routes add a window to a desk without an undo step, through `World.reflow`:

- `admit` (a new window floats on the Desktop)
- `rehome` (a window that moved to this display or Space)
- `release` (an app that was just excluded)
- `planFloatingLostRoom`

None of these push a snapshot. `World.undo` replaces the whole desk with the snapshot (`candidate.desks[key] = snapshot`). It reconciles the states of windows present in both, but a window that is in the current desk and not in the snapshot is simply gone. `Arranger.undo` then calls only `replan()`, and nothing re-admits the window.

Example: dock A, open a new window B (admitted floating), press ⌃⌥⌘Z. B is now on no desk. As a result:

- the Planner does not size the Desktop tile for B's minimum;
- Dock and Move on B beep (`availability(.dock)` needs a desk);
- moving B by hand does nothing, because `moved()` returns early when `deskKey` is nil;
- B is only picked up again by an unrelated `windowChanged` or `windowCreated` event, or by a display-change inventory.

The reverse case is just as bad. A window whose app was excluded after the snapshot is docked again by the undo, which breaks D-29 until the next `windowChanged` event.

No test covers "undo after a window was admitted".
**Fix:** After an undo, reconcile the tracked windows against the World. For example, at the end of `Arranger.undo`:
```swift
guard let key = targetKey(focused), let revived = try LifecycleSync.undo(key, world: &world, history: &history) else { return [.beep] }
for info in windows.values.sorted(by: { $0.window.identity < $1.window.identity }) {
    try release(info)   // an app excluded since the snapshot floats again
    try admit(info)     // a window the snapshot did not hold floats on its Desktop
}
return revived.windows.isEmpty ? replan() : [.requery(revived)]
```
Alternatively, have `World.undo` carry each current-only window onto the snapshot's Desktop layer at its current frame. Add a regression test for "dock A, open B, undo: B is still floating on the desk".

### CR-02: Parked windows land on the neighbouring display, visible and overlapping its tiles

**File:** `Sources/PaneEngine/WindowSystem.swift:21-23`, `Sources/PaneMac/AXWindowSystem.swift:196-201`, `Sources/PaneEngine/Recovery.swift:67`
**Issue:** `parkedFrame` always puts a window's top-left corner at `visibleFrame.maxX - 1, visibleFrame.maxY - 1` of its own display. With a second display to the right of it, or below it, the parked window ends up almost entirely on that other display. This is the user's own setup: the built-in display plus a DELL S3425DW beside it.

Hide Desktop on the left display, and its floating windows appear on the right display on top of that display's docked tiles. That breaks the core "never overlap" promise.

`Recovery.swift:67` already notes "A park corner can show on a neighbouring display", but only the quit path works around it. The same blind spot also affects `rescueStranded` / Restore All (`Arranger+Commands.swift:31`). A window parked onto the other display has most of its area visible, so `Recovery.isStranded` returns false and Restore All does not bring it back while paused.
**Fix:** Pick the park corner that has no neighbouring display, as AeroSpace does, and fall back to an off-screen point outside the union of all display frames:
```swift
public func parkedFrame(size: Size, among displays: [DisplayInfo]) -> Rect {
    let corners = [(visibleFrame.maxX - 1, visibleFrame.maxY - 1), (visibleFrame.minX - size.width + 1, visibleFrame.maxY - 1),
                   (visibleFrame.maxX - 1, visibleFrame.minY - size.height + 1), (visibleFrame.minX - size.width + 1, visibleFrame.minY - size.height + 1)]
    for (x, y) in corners {
        let r = Rect(x: x, y: y, width: size.width, height: size.height)
        if !displays.contains(where: { $0.uuid != uuid && $0.frame.overlaps(r) }) { return r }
    }
    return Rect(x: visibleFrame.maxX - 1, y: visibleFrame.maxY - 1, width: size.width, height: size.height)
}
```
Pass `displays` from `AXWindowSystem.perform`. Add a two-display fake test where display B sits to the right of A.

## Warnings

### WR-01: A Space lookup that turns off or returns 0 mid-session strands every existing desk

**File:** `Sources/PaneMac/Displays.swift:33`, `Sources/PanePrivate/SkyLightSpaces.swift:59-63`, `Sources/PaneEngine/Arranger.swift:605-622`, `Sources/PaneEngine/Arranger.swift:1239-1241`, `Sources/PaneEngine/Arranger.swift:1371-1373`
**Issue:** A desk's key is `(displayUUID, currentSpaceID)`. The Space ID becomes nil in two ways:

- `SLSManagedDisplayGetCurrentSpace` answers 0, which can happen transiently during a display reconfiguration.
- The capability switches off for the session after `failureLimit` (5) consecutive failed `spaces(of:)` batches (`Capabilities.swift:85`).

Once that happens, every display's key becomes `(uuid, nil)`, and the consequences follow:

- **Never planned again:** existing desks `(uuid, X)` no longer match any shown key, so `replan` skips them and they are never planned again.
- **No migration:** `rehome` does not move their windows, because the display is the same and `leftSpace` is false with `spaces == nil`.
- **Commands beep:** commands on those windows beep, because `display(for:)` is nil.
- **Phantom desk:** windows admitted during a transient nil go to a `(uuid, nil)` desk. Once the lookup recovers, that desk is never shown again either.

The layout looks frozen, and the state is persisted to layout.json.
**Fix:** In `Displays.current()`, keep the last known non-nil Space ID when SkyLight answers 0. When the capability turns off for the session, merge each display's desks into one `(uuid, nil)` desk, through `World.reflow`, once. At minimum, have `home(of:)` / `rehome` treat a nil shown Space as matching any desk on the same display.

### WR-02: Root cause: an Accessibility grant made while Pane runs is never noticed (live finding)

**File:** `Sources/PaneEngine/PermissionReducer.swift:74-75`, `Sources/PaneEngine/PermissionReducer.swift:93`, `Sources/PaneMac/Permission/PermissionController.swift:46-54`, `Sources/PaneMac/ArrangeController.swift:171-189`
**Issue:**

- **The reducer never starts polling:** at launch without trust, `(.notTrusted, .launched(false))` returns `[]`, so no polling starts. Polling begins only from `.openSettingsClicked`, the "Open System Settings" button in Set Up Pane.
- **A poll could not move the state anyway:** `.pollTick` is handled only in `.waitingForGrant`.

So if the user grants access directly in System Settings, through the system prompt, or after closing the Set Up window, `phase` stays `.notTrusted` forever. Then `.startTracking` never fires, and `onTrackingStarted` / `startTap` never run.

The tap watchdog cannot recover from this either. It is created only inside `startTap()`, so on this path it does not exist. This matches the log: no transition on the first launch, and notTrusted → probing → ready after a relaunch.
**Fix:**
```swift
case (.notTrusted, .launched(let trusted)):
    if !trusted { return [.startPolling] }
    ...
case (.notTrusted, .pollTick(let trusted, _)):
    guard trusted else { return [] }
    state.phase = .probing
    return [.stopPolling, .runProbe]
```
Add a reducer test for "launched untrusted, a later poll tick says trusted, so the state goes to probing".

### WR-03: Probable root cause of Safari not docking: drag classification depends on mouse-dragged events and on AX and CG sizes matching (live finding)

**File:** `Sources/PaneEngine/Arranger.swift:826-844`, `Sources/PaneEngine/DragSession.swift:124-139`, `Sources/PaneEngine/Arranger.swift:1024-1034`, `Sources/PaneMac/ArrangeController.swift:283-290`
**Issue:** A drag becomes a `.move`, the only kind that can dock, only when both of these hold:

1. **Travel.** `travelled` is computed only from `session.pointer`, which only `.leftMouseDragged` and `.flagsChanged` tap events update (`Arranger.swift:829`). The frame poll starts only after travel (`:832-835`). If a window drag is driven so that no `leftMouseDragged` reaches the session tap, for example a toolbar drag handed to the WindowServer, the session never travels. It is never classified and never polled.
2. **Equal sizes.** `observe` compares every sample's size with `startFrame` within 1 pt. `startFrame` is the AX frame, while the samples are CG bounds from `DragFramePoller`. If an app's CG bounds differ in size from its AX frame (unified toolbar, glass chrome), the first poll sample classifies the press as `.resize`.

Either way, `release` takes the `.miss` path, or the unclassified "app's own frame change" path (`:1024-1034`). For a floating window, that only records its frame. The result is exactly "Safari stays floating", with no preview and no refusal, while TextEdit, whose AX frame and CG bounds agree, docks fine.

Also, `.up` does not update `session.pointer` (`:841-844`).
**Fix:**

- Log `session.kind`, `travelled` and the first sample against `startFrame` at release, and run one Safari drag to confirm which of the two conditions fails.
- Take `startFrame` from `DragFramePoller.bounds(of:)` at mouse-down, so CG bounds are compared with CG bounds.
- Count travel from the window's origin displacement as well as from pointer samples, for example `travelled || abs(frame.x - startFrame.x) + abs(frame.y - startFrame.y) >= minimumTravel`.
- Set `session.pointer = event.location` on `.up`.

### WR-04: If re-attaching the saved layout fails, the next save erases layout.json

**File:** `Sources/PaneEngine/Arranger.swift:321-323`, `Sources/PaneEngine/Arranger.swift:272-275`, `Sources/PaneMac/ArrangeController.swift:360-363`, `Sources/PaneMac/ArrangeController.swift:434-445`
**Issue:** When `reattach` throws, the World stays empty and `pendingRestore` is already nil. Possible causes include `recordFloatingFrame` rejecting a live frame as out of range (`isValidGeometry`), or `apply` failing validation. `place(inventory)` then admits windows, which changes the World and emits `.save(.debounced)`. Half a second later, `write()` saves the empty-plus-floating World over the user's layout.json. The saved layout is lost with only a log line. This is not the `.corrupt` path, which LayoutStore sets aside safely; this file was valid.
**Fix:** On a re-attach failure, keep the saved layout:

- either keep `snapshot` returning the saved World for the rest of the session (as `pendingRestore` does),
- or have the shell copy layout.json to `layout.json.unattached` before the first write.

Also make the failure isolated per window. Skip a window whose frame or state cannot be applied instead of failing the whole re-attach.

### WR-05: A rejected or newer-schema layout.json skips crash rescue at launch

**File:** `Sources/PaneMac/ArrangeController.swift:98-100`, `Sources/PaneMac/LayoutStore.swift:36-52`, `Sources/PaneEngine/Arranger.swift:177`
**Issue:** `launchMode` comes from `store.contents?.session`. When the file was rejected (`.corrupt`, set aside) or comes from a newer schema, `contents` is nil, so the launch counts as `.normal`. That holds even if the previous session crashed with its Desktop hidden. `rescueStranded` runs only in non-normal modes, so windows parked at a display corner stay stranded until the user finds Restore All. "Stranded windows come on screen first" (D-17) is exactly the guarantee this case needs.
**Fix:** If `store.loadError != nil`, treat the launch as `.recovery` for rescue purposes only, since there is no layout to re-apply. Alternatively, always run `rescueStranded` at the first complete inventory: it only moves windows that are less than half on screen.

### WR-06: Home frames are cleared only by `replan`, which does not run while paused, so a quit sends windows back to stale homes

**File:** `Sources/PaneEngine/Arranger.swift:1230`, `Sources/PaneEngine/Arranger.swift:1265`, `Sources/PaneEngine/Arranger+Commands.swift:30-34`, `Sources/PaneEngine/Recovery.swift:66-71`
**Issue:**

1. Restore All runs while paused (by design). It shows hidden Desktops through `showParkedDesktops`.
2. `replan()` returns at once while paused or while the session is paused, so the line that spends home frames on a shown Desktop (`:1265`) never runs.
3. If the user then moves those floating windows (`moved()` still records the frames) and quits while still paused, `Recovery.terminationPlan` sees a home frame for each one and writes it back to its old home.

The same happens to any floating window left with a home frame whenever `replan` has been skipped.
**Fix:** Clear the home frames of a desk's floating windows inside `showingDesktop()`'s commit path, or in `showParkedDesktops` / `toggleDesktop`, rather than in `replan`. Or have `terminationPlan` use a home frame only while the window's desk still has its Desktop hidden.

## Info

### IN-01: The press-window fallback skips an untracked topmost window and picks a tracked window beneath it

**File:** `Sources/PaneMac/ArrangeController.swift:268-273`
**Issue:** The session tap always reports window 0, so every press goes through the CG front-to-back scan. If the topmost layer-0 window under the pointer is untracked, for example Pane's own Set Up or Tracked Windows window, or an app Pane does not track, the loop continues and returns a tracked window underneath. A drag session and a 60 Hz poll then start for a window the user did not press. They usually stay unclassified, but this is wrong.
**Fix:** Stop at the first layer-0 entry containing the point. Return its tracked window, or nil.

### IN-02: A rekey does not update the drag session or remove duplicates from `focusOrder`

**File:** `Sources/PaneEngine/Arranger.swift:440-450`
**Issue:** `drag.window` keeps the old identity, so the moves and `dragFrame` events of a window being dragged go unmatched, and the docked window gets corrected against the user. `focusOrder.map` can also leave the new identity in the list twice.
**Fix:** End or re-point `drag` when `drag?.window == from`, and remove duplicates after the map.

### IN-03: The tap callback can do WindowServer IPC and log

**File:** `Sources/PaneMac/Input/InputTap.swift:134-136`, `Sources/PaneMac/CGWindowList.swift:26-29`
**Issue:** A press inside any published green-button rect calls `CGWindowListCopyWindowInfo` inside the callback, and on failure it logs at error level. Both go against T-03-29 ("no logging"). Under WindowServer load this can push the callback toward `tapDisabledByTimeout`.
**Fix:** Use a log-free variant in the callback, and consider resolving "topmost window" from a snapshot cached on the tap thread.

### IN-04: A gap drag whose split disappears mid-drag leaves the in-progress frames until the next replan

**File:** `Sources/PaneEngine/Arranger.swift:1315-1320`
**Issue:** The guard returns `[]`, with no `replan()`, when the handle's split is gone, for example because a window closed during the drag. The `ended` call therefore never sets the neighbours back.
**Fix:** Return `replan()` from that guard when `ended` is true.

### IN-05: layout.json is briefly 0644 before the chmod

**File:** `Sources/PaneMac/LayoutStore.swift:65-66`
**Issue:** `Data.write(options: .atomic)` creates the file with the umask's default mode, and `setAttributes(0o600)` runs afterwards. ~/Library is normally 0700 and titles are removed, so the impact is minimal.
**Fix:** Write with `FileManager.createFile(atPath:contents:attributes: [.posixPermissions: 0o600])` to a temporary file, then `replaceItemAt`.

### IN-06: Any page or app can toggle the Desktop tile through `pane://toggle-desktop`

**File:** `Sources/PaneEngine/PaneURL.swift:7`, `Sources/PaneMac/AppDelegate.swift:53-65`
**Issue:** The parser is strict and the rate limit is per command, so this is safe from injection. But an unattended `toggle-desktop` parks every floating window, and a page can repeat it once a second. Browsers do prompt before opening a custom scheme.
**Fix:** Consider a shared limit across commands, or leaving `toggle-desktop` out of the URL surface until there is a user-visible need.

### IN-07: release.sh never runs a Gatekeeper assessment on the DMG itself

**File:** `scripts/release.sh:110-114`
**Issue:** `spctl` assesses only `$app`, so a DMG whose ticket or signature Gatekeeper rejects would still pass. The known hdiutil disappearance (deferred-items, 03-17) is also caught only at line 107, after `codesign` has already failed on line 99.
**Fix:** Add `spctl -a -t open --context context:primary-signature -v "$dmg"`, and run `[ -f "$dmg" ] || retry once` right after line 97.

### IN-08: Dead centre-zone check in `dock`

**File:** `Sources/PaneEngine/Arranger.swift:645`
**Issue:** `Planner.dockTarget` already maps `.center` to the nearest edge, so this branch cannot run.
**Fix:** Remove it, or turn it into an assertion.

### IN-09: The restore test redoes LayoutStore's encoding instead of calling it

**File:** `Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift:104-111`
**Issue:** The test copies the redaction and encoder settings by hand, so a change to `LayoutStore.save`/`decode`, such as encoder options or home-frame validation, would not be caught. The test also covers only a `.normal` launch.
**Fix:** Round-trip through `LayoutStore(directory: tempDir).save` / `load()`, and add a `.recovery` variant.

---

_Reviewed: 2026-10-26T14:42:37Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
