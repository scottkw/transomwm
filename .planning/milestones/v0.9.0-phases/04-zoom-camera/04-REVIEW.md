---
phase: 04-zoom-camera
reviewed: 2026-10-28T16:50:53Z
depth: standard
files_reviewed: 55
files_reviewed_list:
  - Package.swift
  - Sources/TransomEngine/Arranger+Camera.swift
  - Sources/TransomEngine/Arranger+Commands.swift
  - Sources/TransomEngine/Arranger.swift
  - Sources/TransomEngine/Command.swift
  - Sources/TransomEngine/DragSession.swift
  - Sources/TransomEngine/Navigator.swift
  - Sources/TransomEngine/Recovery.swift
  - Sources/TransomEngine/SettleTracker.swift
  - Sources/TransomEngine/TransomURL.swift
  - Sources/TransomEngine/ViewPlanner.swift
  - Sources/TransomMac/ArrangeController.swift
  - Sources/TransomMac/Displays.swift
  - Sources/TransomMac/Input/Hotkeys.swift
  - Sources/TransomMac/Input/InputTap.swift
  - Sources/TransomMac/Input/ZoomTapRules.swift
  - Sources/TransomMac/Overlay/PreviewPanel.swift
  - Sources/TransomMac/Overlay/PreviewStyle.swift
  - Sources/TransomMac/Overlay/Toast.swift
  - Sources/TransomMac/Shell/CommandMenu.swift
  - Sources/TransomMac/Shell/MenuCopy.swift
  - Sources/TransomMac/Shell/StatusItemController.swift
  - Sources/TransomMac/Shell/ZoomCopy.swift
  - Sources/TransomMac/TransomMacApp.swift
  - Sources/TransomMac/Zoom/AppColor.swift
  - Sources/TransomMac/Zoom/CollapsedPanels.swift
  - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
  - Sources/TransomMac/Zoom/SnapshotCapture.swift
  - Sources/TransomMac/Zoom/StagePanel.swift
  - Sources/TransomMac/Zoom/TileLayer.swift
  - Sources/TransomMac/Zoom/ZoomController.swift
  - Sources/TransomMac/Zoom/ZoomInput.swift
  - Sources/transom-zoom-spike/main.swift
  - Tests/TransomEngineTests/ArrangerCameraTests.swift
  - Tests/TransomEngineTests/ArrangerCollapseTests.swift
  - Tests/TransomEngineTests/NavigatorTests.swift
  - Tests/TransomEngineTests/RecoveryTests.swift
  - Tests/TransomEngineTests/SettleTrackerTests.swift
  - Tests/TransomEngineTests/TransomURLTests.swift
  - Tests/TransomEngineTests/ViewPlannerTests.swift
  - Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/RecoveryIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/SnapshotCaptureIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/ZoomSettleIntegrationTests.swift
  - Tests/TransomMacTests/AppColorTests.swift
  - Tests/TransomMacTests/CommandMenuTests.swift
  - Tests/TransomMacTests/HotkeyTableTests.swift
  - Tests/TransomMacTests/MenuCopyTests.swift
  - Tests/TransomMacTests/NoScreenCaptureTests.swift
  - Tests/TransomMacTests/PreviewStyleTests.swift
  - Tests/TransomMacTests/ShortcutsModelTests.swift
  - Tests/TransomMacTests/ZoomCopyTests.swift
  - Tests/TransomMacTests/ZoomOffTests.swift
  - Tests/TransomMacTests/ZoomTapRulesTests.swift
  - scripts/vm-spike.sh
findings:
  critical: 2
  warning: 6
  info: 9
  total: 17
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-10-28T16:50:53Z
**Depth:** standard
**Files Reviewed:** 55
**Status:** issues_found

## Summary

I reviewed the phase-4 diff (`6c6e542..HEAD`) for all 55 files, concentrating on the areas the orchestrator flagged. I traced the main paths through `Arranger+Camera`, `Navigator`, `ViewPlanner`, `Recovery`, `ArrangeController`, `ZoomController`, `ZoomInput`, `InputTap`/`ZoomTapRules`, `SnapshotCapture`, `StagePanel` and `CollapsedPanels`.

These checks came back clean:

- **AppKit imports:** none in TransomModel or TransomEngine.
- **ScreenCaptureKit:** used only in `SnapshotCapture.swift`. The spike only calls its API.
- **Event tap:** the callback makes no AX calls and does no I/O. The CG list read happens only under `needsWindow`, the same pattern as Phase 3's green button. Re-enabling after a timeout still works.
- **C-callback bridges:** they use `MainActor.assumeIsolated` only from main-queue callbacks. `ResumeOnce` is lock-guarded.
- **Timers:** the 04-08 `default:` timer bug is not repeated anywhere. The only other `default:` call sites mutate value types.
- **Zoom off, engine side:** it is equivalent to Phase 3. `planShown`, `moved`, `rehome`, `correct` and `commit` all reduce to their old behaviour when `camera.enabled == false` and `collapsible` is empty.

The defects are on the exit paths and in the collapse bookkeeping.

- **Blockers.** The 04-08 plan says no exit path may leave a window parked or off screen. Two paths break that rule:
  - Restore All Windows parks collapsed windows again in the same perform.
  - Turn Off Zoom while arranging is paused leaves every camera-parked and collapsed window parked.
- **Warnings:**
  - Once a window is collapsible it stays collapsible, which quietly removes the "keep refusing" guarantees for it.
  - A pick-mode Esc hotkey takes Esc from every app until the user next clicks.
  - The first move after launch never has snapshots.
  - A post-reveal capture refresh keeps calling ScreenCaptureKit after zoom is turned off.
  - A move dropped when its display is unplugged leaves engine state stuck.

## Critical Issues

### CR-01: Restore All Windows parks collapsed windows again, so they never come back and N6 overcounts

**File:** `Sources/TransomEngine/Arranger+Commands.swift:31-36` (with `Sources/TransomEngine/Arranger.swift:441-458`, `1596-1605`; `Sources/TransomEngine/ViewPlanner.swift:86-93`)

**Issue:** `restoreAll()` calls `goHome()`, then `rescueStranded`, then `replan()`.

1. A collapsed window is a parked sliver, so `rescueStranded` counts it as stranded. It moves the window on screen and removes it from `parkRequested` (line 454).
2. `goHome()` leaves `camera.collapsible` alone. So `replan() -> planShown()` runs `ViewPlanner.plan(.home, collapsible: camera.collapsible)`, which puts the window back in `plan.parks` (ViewPlanner line 92).
3. `parkRequested.insert` now succeeds again, so a fresh `.park` goes out.

The window flashes to its rescue frame and is parked again in the same perform. `.notice(.restored(count: moves.count))` still counts it as restored. This breaks the 04-08 rule ("MUST NOT leave any window parked, shrunk or off screen after ... Restore All Windows") and the UI-SPEC line "Parked windows return ... via Restore All Windows". `restoreAllReturnsEveryCameraHome` misses it because its fixture has no collapsed window.

**Fix:** Pick one rule and apply it everywhere. The simplest consistent one: Restore All treats collapsed windows the way Turn Off Zoom does. They float with N1 and `collapsible` is cleared before the replan:

```swift
mutating func restoreAll() throws(LayoutError) -> [ArrangerEffect] {
    goHome()
    camera.collapsible = []          // collapsed windows come back on screen (they float, as with zoom off)
    let moves = rescueStranded(desks: world)
    try showParkedDesktops(keeping: moves, undoable: true)
    return (moves.isEmpty ? [] : [.perform(moves)]) + replan() + showBlocks([:]) + [.notice(.restored(count: moves.count))]
}
```

If collapsed windows are meant to stay collapsed, leave them out of `rescueStranded` and the N6 count instead, and change the plan or UI-SPEC wording to say so. Add an `ArrangerCameraTests` case with a collapsed window either way.

### CR-02: Turn Off Zoom while arranging is paused leaves camera-parked and collapsed windows off screen

**File:** `Sources/TransomMac/ArrangeController.swift:581-626`; `Sources/TransomEngine/Arranger+Camera.swift:141-151`, `195`

**Issue:** `setZoomEnabled(false)` first sends `.zoomTo(.home)` to each display. While paused (`.user`, `.stageManager`, `.crashLoop` or `sessionPaused`), `zoomTo` returns `refused("paused")` with no `.cameraMove`. `awaitingHome` stays empty, so `finishZoomOff()` runs straight away.

`Arranger.setZoomEnabled(false)` then clears `views` and `collapsible` and returns `replan() + showBlocks([:])`. While paused, `planShown()` returns `[]` (Arranger.swift:1567). The result:

- Every window parked by the node view stays parked, and so does every collapsed window.
- The blocks that were their only on-screen cue are hidden.
- Zoom reports "Zoom off" and the hotkeys go.

The windows come back only on Resume or Restore All. The 04-08 rule lists Turn Off Zoom among the exits that must not leave a window off screen, and UI-SPEC Z11 says "The camera first moves home (un-parking every window), then zoom turns off." No test covers Turn Off Zoom while paused.

Desks zoomed on a Space that is not shown are also never moved home by the per-display loop. They return only when that Space is next shown, which is a softer form of the same gap.

**Fix:** Do not drop the camera while windows are parked and the engine cannot write. Either:

- refuse Turn Off Zoom while paused, with the Surface 1 "Arranging is paused" announcement, and keep zoom on; or
- when paused, run the Restore All rescue for camera-parked and collapsed windows before disabling (the rescue already runs while paused), then disable:

```swift
// Arranger.setZoomEnabled(false)
let rescued = (pauseReasons.isEmpty && !sessionPaused) ? [] : rescueStranded(desks: world)
camera = CameraState()   // enabled = false, everything cleared
return (rescued.isEmpty ? [] : [.perform(rescued)]) + replan() + showBlocks([:])
```

Add a test: pause, Turn Off Zoom, and expect every formerly parked window to be on screen.

## Warnings

### WR-01: Membership of `camera.collapsible` is sticky, so later edits silently collapse a window instead of refusing

**File:** `Sources/TransomEngine/Arranger+Camera.swift:175-178`; `Sources/TransomEngine/Arranger.swift:703`, `1729-1733`

**Issue:** `accept()` grows `camera.collapsible`. The only removals are `forget` (the window is gone) and zoom off. A window stays collapsible after it fits again, after it floats, and after the edit that collapsed it is undone.

`minimums` gives every collapsible window a 1x1 floor in every Phase 3 plan and dry run: grow, shrink, rotate, flip, balance, gap drags, drop hit tests, keyboard Dock and `planFloatingLostRoom`. So later:

- A neighbour's grow or a gap drag can push the window below its real minimum. The edit is accepted with no refusal, and `planShown` (which uses `learnedMinimums`) then collapses the window with no announcement.
- Re-docking it by drag shows a plain `.dock` preview, not the `.collapsed` one, because `collapse()` only reports windows newly added to the set.
- An OS-caused loss of room collapses it instead of floating it.

Each of these goes against CONTEXT E ("an OS-caused loss of room still floats the window" and "grow/shrink/rotate/flip/balance keep refusing when a window wouldn't fit"), and they compound over a session.

**Fix:** After each replan, prune the set to the windows that are actually collapsed in their desk's home plan. Also remove a window when it floats or leaves the tree:

```swift
// end of planShown, zoom on
camera.collapsible = camera.collapsible.filter { id in homeCollapsed.contains(id) }  // homeCollapsed: union of ViewPlanner(.home).collapsed keys
```

### WR-02: Pick mode takes Esc from every app (and plain clicks on window tiles) until the next click or command

**File:** `Sources/TransomMac/Zoom/ZoomInput.swift:156-185`, `102-114`

**Issue:** `revealed(...)` registers a global Carbon hotkey for plain Esc (`KeyboardShortcuts.events(for: Shortcut(.escape))`) whenever a Zoom Out reveal shows more than one window. Pick mode ends only on:

- a mouse press,
- a Transom command,
- a Space change,
- a display change,
- Esc itself.

If the user zooms out and then goes back to the keyboard (⌘-Tab into an editor, or typing in the focused window), Esc is swallowed system-wide. Vim, dialogs and full-screen exit all lose it, and the first Esc after a zoom-out is spent ending pick mode. Focus changes do not end pick mode. Until the next click, the published `pickTiles` also make the tap consume the next plain click on any window tile.

**Fix:** End pick mode on `.windowFocused` / app activation, and after an idle timeout (for example 5 s without pointer movement). Alternatively, register the Esc hotkey only while the pointer is over the zoomed display's tiles. Call `endPick(reason: "focus changed")` from the `system.events` loop on `.windowFocused`.

### WR-03: The first camera move after launch, and every move after a window opens, never has snapshots

**File:** `Sources/TransomMac/Zoom/SnapshotCapture.swift:47-49`, `87-96`; `Sources/TransomMac/Zoom/ZoomController.swift:165-177`, `240`

**Issue:** `capture(_:pixelSize:)` returns nil when `scWindows[id]` is missing. In the product, `scWindows` is filled only by `refreshShareable()`, and only `refresh()` calls that, after a reveal while permission is granted.

The `ZoomController` is created lazily on the first move. It is also thrown away by Turn Off Zoom and made again on Turn On. Its first move's `captureStart` therefore always runs against an empty map, and every tile is the app-colour fallback even with Screen Recording granted. Any window opened since the last reveal is likewise never captured on the next move.

The miss does not count as a failure, so nothing is logged and the Debug line still says "window previews". The spike and the integration tests call `refreshShareable()` themselves, which hides this.

**Fix:** Refresh the shareable list off the critical path once the controller exists, and again when windows are created:

```swift
// ZoomController.init or zoom(): if SnapshotCapture.isGranted() { Task { try? await capture.refreshShareable() } }
// ArrangeController events loop: if case .windowCreated = event { zoomController?.noteWindowCreated() }  // debounced refreshShareable
```

### WR-04: An in-flight post-reveal refresh keeps calling ScreenCaptureKit after Turn Off Zoom

**File:** `Sources/TransomMac/Zoom/ZoomController.swift:250-259`, `296-306`; `Sources/TransomMac/Zoom/SnapshotCapture.swift:87-125`

**Issue:** `refresh()` starts an untracked `Task` that does `guard let self` (a strong reference), then awaits `refreshShareable()` and `captureAll(..., deadline: .seconds(2))`. Each capture has its own 1 s timeout.

`purge()` clears the cache, and `finishZoomOff` sets `zoomController = nil`, but nothing cancels that task. For up to about 3 s after zoom is off, the old controller keeps:

- calling `SCShareableContent` and `SCScreenshotManager`,
- incrementing `SnapshotCapture.touches`,
- filling a fresh cache on an object that is otherwise dead.

D-D says that with zoom off ScreenCaptureKit is never touched. `startNext` also never checks for cancellation.

**Fix:** Store the refresh and capture tasks on the controller, cancel them in `purge()`, and check `Task.isCancelled` in `SnapshotCapture.startNext` and `refresh` before every ScreenCaptureKit call:

```swift
private var refreshTask: Task<Void, Never>?
// refresh(): refreshTask?.cancel(); refreshTask = Task { [weak self] in ... }
// purge():   refreshTask?.cancel(); refreshTask = nil
```

### WR-05: A move dropped by `displaysChanged` leaves `camera.pending` and `unparkedNew` stuck in the engine

**File:** `Sources/TransomMac/Zoom/ZoomController.swift:142-150`; `Sources/TransomEngine/Arranger+Camera.swift:85-87`, `113`, `244-250`

**Issue:** When a display disappears mid-move, `ZoomController.displaysChanged()` deletes `active[uuid]` without calling its `settle` closure. The engine is never told, and nothing else clears `camera.pending[uuid]`; only settle, `goHome` and zoom off do.

When that display comes back with the same UUID, `currentView` returns the stale pending target. If that target is `.home` and the committed view is a node, Zoom Out to All refuses with "Already showing all windows" while windows are still parked.

Any window put in `unparkedNew` by that widen move is never parked either. It stays on screen over the zoomed view until some later settle on its desk. `forget` does not remove closed windows from `unparkedNew`.

**Fix:** In the engine, drop `camera.pending` entries (and their `unparkedNew` members) for displays that are gone whenever displays change. Or have the shell feed `.cameraSettle` for every move it drops. Also remove the window in `forget`:

```swift
camera.pending = camera.pending.filter { uuid, _ in displays.contains { $0.uuid == uuid } }
camera.unparkedNew.remove(window.identity)   // in forget(_:)
```

### WR-06: Turn Off Zoom treats an older move's reveal as the home move's reveal

**File:** `Sources/TransomMac/ArrangeController.swift:572-577`, `587-591`; `Sources/TransomMac/Zoom/ZoomController.swift:73-78`, `242-244`

**Issue:** If display D is in `.revealing` when Turn Off Zoom runs, the `.zoomTo(.home)` move is queued behind the fade. D is added to `awaitingHome`. The earlier move's `onRevealed` then fires `revealed(D)`, which removes D, so `finishZoomOff()` runs while the home move is still only queued.

`purge()` then drops the queued move, and `.zoomEnabled(false)` makes the engine's replan write the windows home with no animation. The windows do end up correct. But the "move home first, then turn off" sequence the code promises does not happen, and the pending move's settle is thrown away.

**Fix:** Track the home move's ID per display (`awaitingHome: [String: UInt64]`) and finish only when `onRevealed` reports that ID.

## Info

### IN-01: `frameWindow` / `frameDesktop` can commit `.node(root)` instead of `.home`

**File:** `Sources/TransomEngine/Navigator.swift:260-262`, `287-294`

**Issue:** `toggle(.node(leaf))` and `toggle(.node(.desktop))` skip `Navigator.target`'s root normalisation. When the leaf or the Desktop is the tree root (one window with the Desktop hidden, or nothing docked), the camera commits a node view that looks identical to home. The status item then says "Transom: zoomed in", gap handles are suppressed, and `homeTiles()` plans that desk at quit.

**Fix:** `toggle(Navigator.target(leaf, in: desk.tree))`, and the same for `.desktop`.

### IN-02: `SnapshotCapture` timeout tasks are never cancelled

**File:** `Sources/TransomMac/Zoom/SnapshotCapture.swift:64-67`, `108-111`

**Issue:** Every capture leaves a 1 s sleeping `Task`, and every `captureAll` leaves a deadline task, even when the work finished early. This is harmless but adds noise, and it blocks the cancellation fix in WR-04.

**Fix:** Keep the handles and cancel them once the continuation is resumed.

### IN-03: `AppColor` caches `systemGray` forever when the first lookup had no icon

**File:** `Sources/TransomMac/Zoom/AppColor.swift:35-40`

**Issue:** `color(forBundleID:icon:)` caches the nil-icon result. That happens, for example, when `NSRunningApplication(processIdentifier:)` returned nil for a pid that has gone. The app stays grey for the rest of the session.

**Fix:** Cache only results that were computed from an icon.

### IN-04: `windowClosed` evicts by `windowID`, but the cache is keyed by the visible tab's CG window

**File:** `Sources/TransomMac/Zoom/ZoomController.swift:369-377`

**Issue:** For native tab groups, `cgWindow` uses `visibleMemberID`, so `capture.remove(window.windowID)` misses the entry. The next `refresh` prunes it.

**Fix:** Remove `cgWindow(window)` as well, or every member ID.

### IN-05: The title-bar double-click preference is read only in `publish()`

**File:** `Sources/TransomMac/Zoom/ZoomInput.swift:69-70`

**Issue:** Turning the toggle off in the Shortcuts window has no effect until the next Arranger change republishes the tap state.

**Fix:** Observe `UserDefaults` for `ShortcutsModel.doubleClickKey` and call `publish()`.

### IN-06: "Allow Window Previews…" can show the system prompt and the Settings pane at once

**File:** `Sources/TransomMac/Shell/StatusItemController.swift:160-166`

**Issue:** `CGRequestScreenCaptureAccess()` returns false immediately while its first-time prompt is still up. So the first use also opens System Settings, contrary to the comment.

**Fix:** Open the pane only if the explainer or a previous request has already been answered (track it in a flag).

### IN-07: Observers and synchronous wallpaper decoding in `StagePanel`

**File:** `Sources/TransomMac/Zoom/StagePanel.swift:78-94`

**Issue:** `colorObserver` is never removed, so one observer token leaks each time `displaysChanged` drops a stage. The wallpaper is also decoded synchronously on main in `init`, which is on the first move's critical path and runs again after every display change. If `NSImage(contentsOf:)` fails (dynamic or aerial wallpapers), the backdrop becomes solid `windowBackgroundColor`, a visible flash on every move.

**Fix:** Remove the observer in `deinit` or `close()`. Decode the backdrop off the critical path when the controller is created, and log when it falls back.

### IN-08: Collapsed-block panels sit at `.floating`, above excluded and never-dock windows

**File:** `Sources/TransomMac/Zoom/CollapsedPanels.swift:121-124`, `196`

**Issue:** The comment says a block "steals no click from an app" because its rect is bare wallpaper. An excluded app's window, or a never-dock window over that rect, is drawn under the block and loses clicks there. Also, `isPointerBusy` (ZoomController:50-51) says it covers a rubber band, but `zoom.isPointerBusy` only checks `arranger.isDragging`.

**Fix:** Use a level just above normal windows, or document the trade-off. Fix the `isPointerBusy` comment or include `ZoomInput`'s band state.

### IN-09: `ZoomOffTests` does not exercise the zoom-off paths it claims to guard

**File:** `Tests/TransomMacTests/ZoomOffTests.swift:12-25`

**Issue:** The controller is never started (no displays, no desks), and `dispatchCamera` returns at `guard zoomEnabled` before anything runs. The test never builds the status menu either. `StatusItemController.addZoomItems` and the Debug `captureLine` are the shell paths that call `SnapshotCapture.isGranted()`, and neither is covered.

Separately, `SnapshotCapture.touches == 0` is a process-wide static. Any future TransomMacTests suite that zooms will make this test fail depending on run order.

**Fix:** Start the controller with a fake inventory and build the status menu with zoom off, then assert `touches` did not change. Drop the absolute `== 0` check.

---

_Reviewed: 2026-10-28T16:50:53Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
