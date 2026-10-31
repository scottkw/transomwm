---
phase: 06-overview-spaces-displays
reviewed: 2026-10-31T21:53:07Z
depth: standard
files_reviewed: 50
files_reviewed_list:
  - Package.swift
  - Sources/TransomEngine/Arrangements.swift
  - Sources/TransomEngine/Arranger+Camera.swift
  - Sources/TransomEngine/Arranger.swift
  - Sources/TransomEngine/CloseRule.swift
  - Sources/TransomEngine/CoVisibilitySpaces.swift
  - Sources/TransomEngine/Command.swift
  - Sources/TransomEngine/LayoutFile.swift
  - Sources/TransomEngine/Navigator.swift
  - Sources/TransomEngine/Notice.swift
  - Sources/TransomEngine/OverviewLayout.swift
  - Sources/TransomEngine/OverviewSelection.swift
  - Sources/TransomEngine/SpaceRekey.swift
  - Sources/TransomEngine/SpaceSwitchPlan.swift
  - Sources/TransomEngine/SpacesSnapshot.swift
  - Sources/TransomEngine/TakeoverPolicy.swift
  - Sources/TransomEngine/TransomURL.swift
  - Sources/TransomEngine/WindowTracker.swift
  - Sources/TransomFixtureApp/main.swift
  - Sources/TransomMac/AXWindowSystem.swift
  - Sources/TransomMac/ArrangeController.swift
  - Sources/TransomMac/ConflictController.swift
  - Sources/TransomMac/DisplaySettler.swift
  - Sources/TransomMac/Displays.swift
  - Sources/TransomMac/Input/GestureTapRules.swift
  - Sources/TransomMac/Input/Hotkeys.swift
  - Sources/TransomMac/LayoutStore.swift
  - Sources/TransomMac/MissionControlTakeover.swift
  - Sources/TransomMac/Overlay/NoticeQueue.swift
  - Sources/TransomMac/Overview/OverviewController.swift
  - Sources/TransomMac/Shell/CommandMenu.swift
  - Sources/TransomMac/Shell/MenuCopy.swift
  - Sources/TransomMac/Shell/NoticeCopy.swift
  - Sources/TransomMac/Shell/OverviewCopy.swift
  - Sources/TransomMac/Shell/StatusItemController.swift
  - Sources/TransomMac/SpaceSwitcher.swift
  - Sources/TransomMac/SpacesProvider.swift
  - Sources/TransomMac/TakeoverAlert.swift
  - Sources/TransomMac/TransomMacApp.swift
  - Sources/TransomMac/Zoom/GestureController.swift
  - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
  - Sources/TransomMac/Zoom/StagePanel.swift
  - Sources/TransomMac/Zoom/ZoomController.swift
  - Sources/TransomPrivate/Capabilities.swift
  - Sources/TransomPrivate/CoreDock.swift
  - Sources/TransomPrivate/SkyLightSpaces.swift
  - Sources/TransomPrivate/SymbolicHotKeys.swift
  - Sources/TransomTestSupport/FakeWindowSystem.swift
  - Sources/transom-spaces-spike/main.swift
  - Tests/TransomMacIntegrationTests/TakeoverIntegrationTests.swift
findings:
  critical: 2
  warning: 10
  info: 6
  total: 18
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-10-31T21:53:07Z
**Depth:** standard
**Files Reviewed:** 50 (all 49 `Sources/` files in scope plus Package.swift; the other tests were read only to check coverage and safety; the gesture spike diff is one line)
**Status:** issues_found

## Summary

I reviewed the phase 6 diff (`579c66d..HEAD`) at standard depth. I traced these areas across files: the takeover lifecycle (TransomMacApp → MissionControlTakeover → TakeoverPolicy → SymbolicHotKeys → ConflictController/StatusItemController), the display-settle path (AXWindowSystem → DisplaySettler → ArrangeController → Arranger), and persistence (LayoutStore → LayoutFile → SpaceRekey → `ArrangeController.write`).

What holds up:
- The takeover's crash-safety order is correct. Originals are written and `synchronize()`d before the first disable. A second apply never overwrites a stored original (T-06-27). Originals are cleared only after a read-back matches. The launch restore runs before `AXWindowSystem` exists.
- The private APIs are dlopen/dlsym only and gated by capability. No link-time symbols were found.
- TransomEngine and TransomModel still import no AppKit.
- The spike's state-changing subcommands, including the `--child-apply-abort` child, refuse to run outside a VM.

What does not hold up:
- **Arrangement layout sets are corrupted or lost in two ways.** A failed launch re-attach (`unattached`) combined with any arrangement change writes the wrong layout under the wrong arrangement and drops the stored set (CR-01). Layout sets are also never re-keyed and are missing from the Space table, so after a reboot they point at stale Space IDs (CR-02).
- **No in-session way to recover the shortcuts.** Several takeover paths leave the user's Mission Control shortcuts disabled for the whole session with no way to recover them from inside the app (WR-02). One path makes the preference impossible to turn off (WR-03).
- **SpaceSwitcher on multiple displays.** Its per-display "Desktop n" index likely does not match macOS's numbering, which runs across all displays (WR-06).
- **Live takeover tests have no VM gate.** They change the host's real symbolic hotkeys behind only `TRANSOM_LIVE=1`. A crash in them leaves the hotkeys disabled where the app can never restore them (WR-11).

## Critical Issues

### CR-01: A failed launch re-attach plus any arrangement settle saves the wrong layout under the wrong arrangement and drops a stored layout set

**File:** `Sources/TransomEngine/Arranger.swift:270-275, 396-399, 420-470`; `Sources/TransomMac/ArrangeController.swift:184, 998-1003`
**Issue:** When `reattach` throws, `unattached = restore` is set and never cleared, and `world` stays empty. After that:
1. `settleIfLaunchArrangementChanged()` (or any later dock or undock) sends `.displaysSettling`, which sets `preChangeWorld = world` (the empty World).
2. `displaysSettled` runs `layoutSets.store(before, for: old, ...)`. That stores an **empty World as arrangement A's set**, replacing any good one.
3. For `.known(B)`, `layoutSets.take(B)` removes B's stored set, and the merge goes into `world`.
4. `snapshot` returns `pendingRestore ?? unattached ?? ...`. It therefore writes **A's saved World as `world`, labelled with `arrangement = B`**, and the layout-set list now lacks B and holds an empty A.

Result: B's stored layout is gone from disk, A's layout is relabelled as B, and returning to A applies an empty set. This is exactly the risk the executors flagged. No test covers it: `ArrangerDisplaySettleTests` has no failed-restore case.
**Fix:** Do not settle while the saved layout is unattached, and keep the label consistent with what `snapshot` writes:
```swift
case .displaysSettling:
    guard !settling, unattached == nil else { return [] }   // nothing real to store as the old set
...
private mutating func displaysSettled(...) -> [ArrangerEffect] {
    ...
    guard pendingRestore == nil else { return process(.inventory(inventory), now: now) }
    guard unattached == nil else {           // the file still holds the saved layout: keep its arrangement too
        arrangement = old
        return [.info("display settle skipped: saved layout not attached")]
    }
```
Also have `snapshot` return the arrangement the unattached World was saved under, rather than the live `arrangement`. Add a test that runs a failed reattach, then a settle, then a write.

### CR-02: Layout sets are never re-keyed by Space UUID and are missing from the Space table, so after a reboot their per-Space desks point at stale IDs

**File:** `Sources/TransomMac/ArrangeController.swift:918-939, 941-951`; `Sources/TransomEngine/Arranger.swift:439, 454-462`
**Issue:**
- `rekeyed(_:)` re-keys only `saved.world`. `saved.layoutSets` goes into `.restore` unchanged.
- `write()` builds the table with `SpaceRekey.table(for: snapshot.world, ...)`, so only Space IDs used by the current World get a UUID.

A `.known` switch replaces the current World with the stored set plus the kept desks (`merged`). Desks that exist only in layout sets (for example a dormant display's desks after switching A+H → A+W) therefore never have a UUID on disk. After a reboot (D-13: IDs change), applying such a set gives desks keyed by previous-boot IDs:
- They stay dormant (layout lost), or
- with "Displays have separate Spaces" off, or when IDs are reused, they attach to an unrelated live Space.

`merged` also replaces the current desks on displays the set covers. So the current, correctly keyed per-Space layouts are dropped unless the user placed windows since the last switch. On the next launch, re-keying a stale desk onto an ID that a fresh desk now holds sends it to quarantine, which deletes it (see WR-04). This breaks D-13 for OVER-06.
**Fix:** Put every layout set's Space IDs in the table and re-key every set at load:
```swift
// write()
let allWorlds = [snapshot.world] + snapshot.layoutSets.map(\.world)
let ids = Set(allWorlds.flatMap { $0.desks.keys.compactMap(\.spaceID) })
let spaces = ids.sorted().compactMap { id in uuids[id].map { SavedSpace(id: id, uuid: $0) } }

// start(): re-key each set with the same table before .restore
let sets = saved.layoutSets.map { set in
    LayoutSet(arrangement: set.arrangement, world: (try? SpaceRekey.rekey(set.world, saved: table, current: live.idByUUID).world) ?? set.world, lastUsed: set.lastUsed)
}
```
Add a `SpaceRekeyTests` case and an `ArrangerDisplaySettleTests` case: save, change IDs, reload, switch to the known arrangement.

## Warnings

### WR-01: Takeover originals in UserDefaults can crash every launch

**File:** `Sources/TransomMac/MissionControlTakeover.swift:21-23`
**Issue:** `Dictionary(uniqueKeysWithValues:)` over keys parsed with `Int32(key)` traps on a duplicate. `"32"`, `"032"` and `"+32"` all parse to 32. The defaults domain is user-writable, and the comment itself calls this value a trust boundary. A malformed `takeover.originals` crashes `launchRestore()`, the first thing `TransomMacApp.run` does, on every launch.
**Fix:** `Dictionary(pairs, uniquingKeysWith: { first, _ in first })`, and log the anomaly. Better still, reject any key whose `String(Int32(key)!) != key`.

### WR-02: A failed restore, or a forced-off capability, leaves Mission Control shortcuts disabled for the whole session with no way back inside the app

**File:** `Sources/TransomMac/MissionControlTakeover.swift:102-119, 256-265, 274-282`; `Sources/TransomMac/ConflictController.swift:205-211`; `Sources/TransomPrivate/SymbolicHotKeys.swift:47-57`
**Issue:**
- When `restore` reads back a mismatch, the originals are kept "for the next launch", but nothing retries them during the session.
- "Restore macOS Window Settings" (`canRestore`) only considers `takeover?.isOn`, not `storedOriginals`, so it is disabled exactly when the shortcuts are stuck off.
- With `--disable-private=SymbolicHotKeys` (or a session-disabled capability), `launchRestore` hits a no-op `setEnabled` and reads back nil. It keeps the originals silently and logs only the generic "differs" error, while the user's ⌃↑ and F3 stay dead for the session.
**Fix:**
- Make `canRestore` true when `takeover?.storedOriginals?.isEmpty == false`, and have `restore()` call a `takeover.retryRestore()` that runs `restore(store.originals)`.
- When the launch restore fails, post a notice (or at least a Debug S5 line) saying the system shortcuts are still off.
- Consider letting the restore path ignore `isForcedOff`, since it only writes back values the user had.

### WR-03: After a failed apply the preference stays on and the menu can never turn it off; N11 repeats every launch

**File:** `Sources/TransomMac/MissionControlTakeover.swift:122-150, 245-251`; `Sources/TransomMac/ArrangeController.swift:96`; `Sources/TransomMac/Shell/StatusItemController.swift:165`
**Issue:**
- `setPreference(true)` writes `takeover.enabled = true` before `apply()`. On `.applyFailed` the state becomes `.offApplyFailed`, but the preference stays true.
- The menu item shows `isOn` (unchecked). Clicking it calls `choose`, which retries `turnOn()`, so the user cannot clear the preference.
- At every later launch the policy applies again, and the `takeover` didSet posts N11 again.
**Fix:** On `.applyFailed`, set `defaults.set(false, forKey: Self.enabledKey)`. Alternatively, have the menu reflect `preferenceOn` and let `choose` turn the preference off whenever it is on, even if not applied.

### WR-04: Quarantined desks are deleted from layout.json on the first launch write, with no backup

**File:** `Sources/TransomEngine/SpaceRekey.swift:40-57`; `Sources/TransomMac/ArrangeController.swift:175-189`
**Issue:**
- Quarantined desks are removed from the World passed to `.restore`. The launch `write()` then saves that pending World at once, so the desks are gone permanently.
- The second-collision branch (line 51) also quarantines a user's desk because of an ordering accident (`sorted` by key) rather than staleness.
- The `default:<displayUUID>` synthetic UUID depends on which screen is `NSScreen.screens.first` (spans mode) or on the display identifier. A changed main display can therefore turn a live desktop's desk into an "unmatched, ID live" case and delete it.

This conflicts with the "never discard a user's layout" goal.
**Fix:** Keep quarantined desks out of the live World but keep them in the file, for example as a `quarantined: [DeskKey: Desk]` field or a `.quarantine` side file. At minimum, copy layout.json to `layout.json.pre-rekey` before the first save that drops desks.

### WR-05: A dormant desk whose stale Space ID a newly created Space takes during the session silently inherits that Space

**File:** `Sources/TransomEngine/SpaceRekey.swift:40-48`; `Sources/TransomMac/ArrangeController.swift:947-951`
**Issue:** An unmatched desk keeps its previous-boot ID because "no live Space has it". After a reboot, IDs restart low, so a Space the user creates later in the session can receive that ID. The Arranger then treats the dormant desk as that new Space's layout, and `write()` records `id → new UUID` (live wins), which makes the mismatch permanent. The quarantine guard runs only once, at launch.
**Fix:** At each `refreshSpaces()` that adds a Space ID, compare it with the dormant desks' keys and their saved UUIDs (kept from `store.contents.spaceMap`). Quarantine or re-key the desk when the UUIDs differ. Alternatively, re-key dormant desks to a reserved synthetic ID range, such as `CoVisibilitySpaces.syntheticBase`, so a live ID can never collide with them.

### WR-06: SpaceSwitcher targets the wrong Space on multi-display setups

**File:** `Sources/TransomMac/SpaceSwitcher.swift:19-40`; `Sources/TransomEngine/SpaceSwitchPlan.swift:36-46`; `Sources/TransomEngine/SpacesSnapshot.swift:78-81`
**Issue:**
- `SpaceInfo.index` counts desktops **per display**. macOS numbers Mission Control desktops, and the "Switch to Desktop n" shortcuts (IDs 118+), consecutively across displays: a second display's first desktop is "Desktop 3" when the main display has two. The same index drives the "Desktop n" strip labels and announcements. This needs a hardware check, because the VM cannot run multiple displays.
- If so, a pick on a non-main display posts the main display's "Desktop n" shortcut. That switches the wrong display, waits 1 s and then beeps.
- The move-left/right fallback acts on the display macOS considers active (pointer or focus), not on `display`. A keyboard (Return) pick on another display's strip therefore moves the wrong display.
**Fix:**
- Compute a global desktop index: count desktops over `snapshot.displays` in order up to the target. Use it for the direct chord and the labels, or use the direct chord only for the main display.
- For move chords, first warp the pointer onto the target display (`CGWarpMouseCursorPosition`) or refuse.
- Add a multi-display item to 06-UAT.

### WR-07: SpaceSwitcher posts ⌃←/⌃→ into the frontmost app when the user has turned those hotkeys off, and the 1 s deadline ignores how many chords were posted

**File:** `Sources/TransomEngine/SpaceSwitchPlan.swift:20-23, 44`; `Sources/TransomMac/SpaceSwitcher.swift:32-39`
**Issue:**
- `chord(hotkeys(moveRightID)) ?? moveRight` falls back to ⌃→ even when the hotkey is present but **disabled** (`hotkey.enabled == false` returns nil). With the system shortcut off, the posted ⌃→ goes to the frontmost app (cursor-by-word, editor commands) `|Δ|` times, and the switch then fails.
- The deadline is a fixed 1 s even for 5+ queued move chords. Each one animates, so a switch that is still in progress is reported as failed: a beep and "Couldn't switch".
**Fix:** Use the default chords only when the getter is **unavailable** (`hotkeys(id) == nil`). When the hotkey is readable but disabled, return `[]` and refuse up front. Scale the timeout, for example `timeout + .milliseconds(400) * (chords.count - 1)`.

### WR-08: A new display change between "settled" and its Task can end settling mid-change

**File:** `Sources/TransomMac/ArrangeController.swift:192-202, 961-966`; `Sources/TransomMac/DisplaySettler.swift:58-85`
**Issue:**
- `onDisplaysSettled` wraps `displaysSettled()` in a `Task`, and that method also awaits `system.inventory()`.
- If another change arrives in that gap, the settler goes `idle → settling` and calls `onSettling`. The Arranger is still `settling`, so `.displaysSettling` returns early.
- The pending `displaysSettled` then runs against a mid-change inventory and clears `settling`. It may decide `.new` or `.known`, cascade windows and store sets while macOS is still moving windows (Pitfall 4).
- When the second settle arrives, `preChangeWorld` is nil and `before = world` is already modified.
**Fix:** At the top of `ArrangeController.displaysSettled()`, and again after the `await`, check `guard system.settlerState == .idle else { return }`. Alternatively, pass a settle generation number from the settler and drop stale ones.

### WR-09: A display settle while the launch restore is still pending relabels the saved layout and never stores or applies the right sets

**File:** `Sources/TransomEngine/Arranger.swift:424-430`; `Sources/TransomMac/ArrangeController.swift:184, 998-1003`
**Issue:**
- In `displaysSettled`, `arrangement = id` runs before `guard pendingRestore == nil`, so the saved arrangement A is overwritten by B before the re-attach. The restore then attaches A's World as B.
- The pending `launchSettlePending` later sees `id == arrangement` (`.same`): A's layout is never stored as its set, and B's known set is never applied.
- `launchSettlePending` stays armed until some later feed, which can trigger a spurious settle in the middle of the session.
**Fix:** In the `pendingRestore != nil` branch, leave `arrangement` as the saved one, process the inventory, and let `settleIfLaunchArrangementChanged` run straight after it, called from `ArrangeController.displaysSettled` too. Clear `launchSettlePending` once a settle has handled the launch.

### WR-10: The G-03-9 ghost rule does not close tabbed ghosts

**File:** `Sources/TransomEngine/CloseRule.swift:55-57`; `Sources/TransomEngine/WindowTracker.swift:357-375`
**Issue:**
- Alive app: `(.alive, .invalidElement, true)` checks `isKnownTabMember` **before** `cgSpacesKnownEmpty`. A Safari window with several tabs whose closed entries linger (the G-03-9 case) therefore becomes `.absent`, not closed, and keeps its tile.
- Terminated app: a ghost's shown member is "closed", but `remaining = members ∩ inCG` counts the other ghost members by CG presence alone, ignoring that they have no Space either. The group never closes, and each pass only rewrites `tabCount`.

So G-03-9 stays open for tabbed windows. This is moderate confidence and should be checked with the VM `ghost` spike on a multi-tab window.
**Fix:** For the terminated path, filter `remaining` by `context.windowSpaces?[member] != []`. For the alive path, decide whether a known tab member that is a no-Space ghost and whose other members are all no-Space ghosts should close the group. Add CloseScenario cases for both.

### WR-11: Live takeover tests change the host's real symbolic hotkeys with no VM gate, and a crash leaves them unrecoverable

**File:** `Tests/TransomMacIntegrationTests/TakeoverIntegrationTests.swift:11, 43-62`; `Tests/TransomMacIntegrationTests/IntegrationSupport.swift:10`
**Issue:**
- The suite says "VM only", but `IntegrationEnv.trusted` checks only `AXIsProcessTrusted() && TRANSOM_LIVE == 1`. Unlike the spike's `requireVM()`, it has no `kern.hv_vmm_present` check.
- The tests disable 32/108/113 for real and restore them through `defer`, which does not run on a crash, a `.timeLimit` kill or SIGKILL.
- The originals sit in a throwaway `UserDefaults` suite, so the real app's `launchRestore` can never find them. A host run that dies mid-test leaves the user's Mission Control shortcuts disabled until they re-enable them by hand in System Settings.

This also goes against the "VM only for live tests" project rule.
**Fix:** Gate the suite with `.enabled(if: IntegrationEnv.trusted && IntegrationEnv.inVM)`, where `inVM` reads `kern.hv_vmm_present`, as `requireVM()` does. Also gate `OverviewSpaceSwitchIntegrationTests`, which posts Space-switch chords.

## Info

### IN-01: A local `state` shadows the `state` property in `apply()`

**File:** `Sources/TransomMac/MissionControlTakeover.swift:246-249`
**Issue:** `let state = readBack(ids)`, followed by `self.state = .offApplyFailed`, is easy to misread or break in an edit.
**Fix:** Rename it `readBackState`.

### IN-02: `LiftReason.restoreSettings` is never used

**File:** `Sources/TransomMac/MissionControlTakeover.swift:62`; `Sources/TransomMac/ConflictController.swift:211`
**Issue:** ConflictController calls `setPreference(false)`, so the lift is logged as `.toggleOff`.
**Fix:** Use `.restoreSettings` there, or remove the case.

### IN-03: The Engine uses the wall clock for layout-set LRU

**File:** `Sources/TransomEngine/Arranger.swift:439`
**Issue:** `layoutSets.store(before, for: old, at: .now)` reads `Date.now` inside a pure reducer that is otherwise driven by `now: ContinuousClock.Instant`. Eviction order then depends on the wall clock and cannot be tested deterministically.
**Fix:** Carry a `Date` in `.displaysSettled` from the shell.

### IN-04: Merged N12 can name the same display twice

**File:** `Sources/TransomMac/Overlay/NoticeQueue.swift:68-69`
**Issue:** `names + more` is not de-duplicated: a display that flaps out twice inside the toast's lifetime is named twice.
**Fix:** `names + more.filter { !names.contains($0) }`.

### IN-05: The "Desktop 0" copy can surface

**File:** `Sources/TransomMac/Overview/OverviewController.swift:435, 442, 533`; `Sources/TransomMac/Shell/OverviewCopy.swift:84, 101`
**Issue:** `spaceInfo(space)?.index ?? 0` and full-screen Spaces (index 0) produce "Desktop 0" in announcements and in "Couldn't switch to Desktop 0".
**Fix:** Branch on `.fullScreen` or nil and use the app name or a generic "that Space".

### IN-06: The DisplaySettler callback may run after deinit

**File:** `Sources/TransomMac/DisplaySettler.swift:33-35, 89-97`
**Issue:** The refcon is unretained, and a block already queued on main by the CG callback can run after `deinit` removed the callback: a use-after-free. Risk is low today because the settler lives as long as `AXWindowSystem`.
**Fix:** Keep a static registry of live settlers keyed by address, or use `passRetained` and balance it in an explicit `stop()`.

---

_Reviewed: 2026-10-31T21:53:07Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
