---
phase: 08-saved-views-urls-persistence
reviewed: 2026-11-04T02:01:47Z
depth: standard
files_reviewed: 46
files_reviewed_list:
  - Package.swift
  - Sources/TransomEngine/Arranger+Camera.swift
  - Sources/TransomEngine/Arranger+Placeholders.swift
  - Sources/TransomEngine/Arranger+Tabs.swift
  - Sources/TransomEngine/Arranger+Views.swift
  - Sources/TransomEngine/Arranger.swift
  - Sources/TransomEngine/CLICommandLine.swift
  - Sources/TransomEngine/CLICopy.swift
  - Sources/TransomEngine/CLIProtocol.swift
  - Sources/TransomEngine/Command.swift
  - Sources/TransomEngine/HintMatcher.swift
  - Sources/TransomEngine/LayoutFile.swift
  - Sources/TransomEngine/LayoutRestore.swift
  - Sources/TransomEngine/Navigator.swift
  - Sources/TransomEngine/Notice.swift
  - Sources/TransomEngine/OverviewLayout.swift
  - Sources/TransomEngine/SavedViews.swift
  - Sources/TransomEngine/SpaceRekey.swift
  - Sources/TransomEngine/TransomURL.swift
  - Sources/TransomFixtureApp/main.swift
  - Sources/TransomMac/AppDelegate.swift
  - Sources/TransomMac/ArrangeController.swift
  - Sources/TransomMac/BootSession.swift
  - Sources/TransomMac/CLIListener.swift
  - Sources/TransomMac/CommandGate.swift
  - Sources/TransomMac/Input/Hotkeys.swift
  - Sources/TransomMac/LayoutStore.swift
  - Sources/TransomMac/Overlay/NoticeQueue.swift
  - Sources/TransomMac/Overlay/PlaceholderPanels.swift
  - Sources/TransomMac/Overlay/Toast.swift
  - Sources/TransomMac/Overview/OverviewController.swift
  - Sources/TransomMac/Shell/MenuCopy.swift
  - Sources/TransomMac/Shell/NoticeCopy.swift
  - Sources/TransomMac/Shell/StatusItemController.swift
  - Sources/TransomMac/Shell/ViewCopy.swift
  - Sources/TransomMac/TransomMacApp.swift
  - Sources/TransomMac/Zoom/ShortcutsWindowController.swift
  - Sources/TransomMac/Zoom/StagePanel.swift
  - Sources/TransomMac/Zoom/TileLayer.swift
  - Sources/TransomMac/Zoom/ZoomController.swift
  - Sources/TransomModel/DesktopLayer.swift
  - Sources/TransomModel/World.swift
  - Sources/transom-cli/main.swift
  - scripts/release.sh
  - scripts/vm-cli-check.sh
  - xcode/project.yml
findings:
  critical: 3
  warning: 13
  info: 4
  total: 20
  necessity: 0
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-11-04T02:01:47Z
**Depth:** standard
**Files Reviewed:** 46
**Status:** issues_found

## Summary

Three findings should block shipping. A saved view is not written to disk when it is saved. After a reboot or an app relaunch, tiles on Spaces that aren't showing expire and are lost. Hint matching ignores Spaces, so a window on the wrong Space can consume a tile, and `rehome` then deletes that tile.

**How this was reviewed.** All findings come from reading the code. Nothing was built or run, and no app, CLI or URL was opened on this host, as instructed. New Phase 8 files were read in full. For the large existing files (`Arranger.swift`, `ArrangeController.swift`, `Arranger+Tabs.swift`, `OverviewController.swift`, `StagePanel.swift`, `ZoomController.swift`), I read the diff from `7b96181` and the code it calls, not every line.

**Limits on what is proven:**
- CR-02 and CR-03 rely on the codebase's own statement that AX does not list windows on hidden Spaces (`Arranger.swift:309-311`, `LayoutRestore.swift:7-8`). Neither was reproduced live. The real-reboot UAT is still open, and it should include a second Space.
- WR-06 depends on the order in which real apps close windows and terminate. The repo cannot settle that, and 08-04 records it as unverified.

**Checked, no defect found:**
- `TransomURL.parse` rejects the UI-SPEC's listed bad forms, and slots are compared byte by byte.
- `CommandGate` is shared by URL opens and CLI requests. Each slot has its own rate limit.
- `CLIListener` caps request size and checks the message ID before parsing. Any local process can send requests, but only allow-listed commands get through, as with a URL (T-08-15).
- `CLICopy.ascii` strips terminal escapes from replies, and an unrecognised reply is never printed.
- A newer-schema file disables saving and is left untouched. Schema 1 and 2 files migrate.
- Titles stay out of logs, because `WindowRef.description` and `debugDescription` omit them (`IDs.swift`).
- Restore rekeys go through throwaway identities, so reused IDs cannot chain.
- `World.adopt` keeps undo snapshots consistent.
- The helper's entitlement, timestamp, hardened-runtime and architecture checks in `release.sh` are sound.

**Necessity:** the rubric was applied and produced no findings. The redundant-looking guards in this phase sit on trust boundaries (layout.json, the message port, the environment) or are test seams, which the rubric excludes.

## Critical Issues

### CR-01: Saving a view never schedules a write, so the view can be lost after "Saved view N"

**File:** `Sources/TransomEngine/Arranger+Views.swift:22-27`, `Sources/TransomEngine/Arranger.swift:263`
**Issue:** `saveView` changes only `camera.savedViews` and returns a notice and an info line. `Arranger.handle` adds `.save(.debounced)` only after `guard world != before`, and saving a view doesn't change the World. The only `.save` effects in the engine are at `Arranger.swift:278`, `:544` and `:2190`, and `Navigator.camera` adds none.

The view therefore reaches layout.json only with the next World change or a clean quit. If Transom crashes, is killed or loses power first, the view is gone, even though the toast said "Saved view 3" and `transom save-view 3` exited 0. UI-SPEC Surface 1 says views are written "with the next debounced save (Phase 3: 0.5 s)". `ViewsIntegrationTests` does not catch this because its test splits and moves windows after saving, and those edits trigger a save.
**Fix:** Schedule the save where the view changes, and add a test that asserts the effect:
```swift
return [
    .notice(.viewSaved(slot, replaced: replaced, displayUUID: uuid)),
    .info("save view \(slot) on display \(uuid) space \(space): ..."),
    .save(.debounced),
]
```

### CR-02: Tiles on Spaces that aren't showing expire after a reboot or app relaunch, and the layout is lost

**File:** `Sources/TransomEngine/LayoutRestore.swift:26-32`, `Sources/TransomEngine/Arranger+Placeholders.swift:163-168`, `:181-198`, `Sources/TransomEngine/Arranger.swift:987`
**Issue:** With `skipIdentity`, every saved window is unattached. After a reboot, `isAlive` cannot help either, because the IDs and pids have changed. AX lists only the current Space's windows, so windows on other Spaces have no candidate, land in `waiting` and get a placeholder deadline. That deadline is 10 s if the app has any tracked window on the shown Space, otherwise 5 min, and `.appLaunched` shortens it to 10 s.

`expirePlaceholders` has no Space check, so it closes those tiles through the close path. When the user later visits that Space, the windows arrive after expiry and only float. Saved views on that desk are pruned at the next save. An app relaunched while Transom runs takes the same path, because the new pid also fails `isAlive`.

This contradicts UI-SPEC Surface 2, "Not a placeholder: a window on a Space not shown at launch", and the phase goal that layouts come back after reboots. It affects anyone with docked windows on more than one Space. No test in `ArrangerPlaceholderTests` covers a placeholder on a hidden Space.
**Fix:** Don't run a placeholder's deadline while its desk is on a Space that isn't showing:
- Make `deadline` optional, or add a `.spaceHidden` wait.
- Leave it nil when `key.spaceID` is non-nil and isn't any display's `currentSpaceID`.
- On `.spaceChanged`, start `launchWait` for placeholders on the Space now showing.
- Have `earliestDeadline` and `restartLaunchWait` skip placeholders on hidden Spaces.
- Add table tests for reboot, quit and relaunch with a second Space.

### CR-03: Matching ignores Spaces, so a window on the wrong Space consumes a tile and `rehome` then deletes it

**File:** `Sources/TransomEngine/LayoutRestore.swift:35-37`, `Sources/TransomEngine/Arranger+Placeholders.swift:205-212`, `Sources/TransomEngine/Arranger.swift:669`, `:1000`, `:1247-1268`
**Issue:** `HintMatcher.assign` and both of its callers filter by bundle only. Nothing compares a candidate's `info.spaces` or `displayUUID` with the saved window's desk.

Example:
1. A user on Desktop 1 quits Terminal, which has a tile on Desktop 2, and relaunches it within 30 s.
2. The new window opens on Desktop 1 and scores `solePair`, 40.
3. `World.adopt` moves it into the Desktop 2 tile and removes the placeholder entry.
4. At the next `.windowChanged` or inventory, `rehome` computes `leftSpace == true`, calls `desk.tree.remove`, and floats the window on Desktop 1.

The Desktop 2 tile disappears with no placeholder, no expiry and no undo step. Saved views have already been remapped to the window that moved away. The launch path does the same after a reboot whenever macOS restores a window to a different Space.
**Fix:** Offer a candidate only when it can actually be in that tile. Its known `spaces` must contain the desk's `spaceID`, and unknown Spaces keep today's behaviour. Otherwise leave the placeholder waiting. A window on another display can still match, because a frame write moves it, but `rehome` must not float it before that write lands. Skip `rehome` for a window with a pending fill, or until its first `frameApplied`.

## Warnings

### WR-01: layout.json is stamped with the new boot session while it still holds the old boot's window IDs

**File:** `Sources/TransomMac/ArrangeController.swift:222`, `:1175-1177`
**Issue:** `write()` always records `BootSession.current()`. The launch write at line 222 runs before the restore, with the old boot's identities still in the file. Later writes keep unmatched placeholders under old-boot identities for up to 5 min. If Transom crashes or is relaunched in that time, `BootSession.changed` returns false, so the next launch re-attaches by identity against stale IDs. That is the collision the guard exists to prevent (RESEARCH Pitfall 5).
**Fix:** Keep the loaded `bootSession` in the file until the restore has run and no placeholder from the earlier boot remains. Have the engine expose that state, for example `arranger.holdsPreviousBootIdentities`, and write the new value only after that.

### WR-02: The boot-session guard covers only the first re-attach

**File:** `Sources/TransomEngine/Arranger.swift:533`, `:290-291`, `:900-901`
**Issue:** There are two gaps:
- Applying a stored layout set calls `reattach` with `skipIdentity` false, and `LayoutSet` records no boot session. A set saved in an earlier boot, such as before a monitor was unplugged, is therefore re-attached by identity in every later boot.
- After a boot-changed launch, both "the very window came back" paths clear a placeholder on an identity match alone, with no hint check.

A reused window ID, pid and bundle takes another window's tile. This is rare, but it is the case the guard was built for.
**Fix:** Store `bootSession` on `LayoutSet`, nil for older files, and pass `skipIdentity` when it differs from the current boot. Mark placeholders held after a boot change so they fill only through `HintMatcher`.

### WR-03: The sole-pair bonus alone reaches the threshold, so a wrong window is taken and never given back

**File:** `Sources/TransomEngine/HintMatcher.swift:25-27`, `:92`, `:127`, `Sources/TransomEngine/Arranger+Placeholders.swift:202`
**Issue:** `solePair` is 40 and `threshold` is 40, so one saved window and one candidate match with no other evidence, even when both titles are known and differ. In the fill path, `sole` counts only waiting and fresh windows. An app whose first window is a Welcome, Preferences or sign-in window (if classified dockable) therefore fills the tile. The doc comment says "a committed match is never undone", so the real window then floats beside it. A window created with an empty title also matches at creation, before there is a title to compare. The type's own header claims a window "is never put in another window's tile on a guess".
**Fix:** Don't let the sole-pair bonus decide against evidence. Withhold it when both titles are non-empty and their normalised forms differ. While a candidate's title is empty, wait for the title or a short grace period before using it. Add table rows for both cases.

### WR-04: The sliding 10 s deadline has no cap, so a placeholder can wait indefinitely

**File:** `Sources/TransomEngine/Arranger+Placeholders.swift:54-59`, `:146-152`
**Issue:** Every new dockable window of the bundle resets all its placeholders to `now + 10 s`, whether or not that window could match them. An app that opens a window at least every 10 s keeps an empty tile indefinitely. The doc comment at lines 3-4 says a placeholder "can never become a permanent hole". `aLaunchSwitchesToTenSecondsAndEachNewWindowRestartsThem` confirms the slide but sets no limit.
**Fix:** Record the first restart time and cap the slide, for example `min(now + launchWait, firstLaunch + 60 s)`, with a test.

### WR-05: `prune` removes a window created before its old window's destroy event, so that fill path doesn't work

**File:** `Sources/TransomEngine/Arranger+Placeholders.swift:62-68`, `:146-152`, `Sources/TransomEngine/Arranger.swift:264`
**Issue:** `noteCreated` marks a new window fresh when its bundle is in `quitting`, and 08-04 lists this as handled. But `admit` then floats the window, which changes the World, and `handle` calls `prune`. If no placeholder of the bundle exists yet, `waits(for:)` is false, so `prune` removes the window from `fresh`. When `.windowDestroyed` arrives, `holdForQuit` finds no candidates. Nothing retries, because only `.windowCreated` adds to `fresh`, so the tile expires with its window open beside it. This happens when an app relaunches during `recheckTerminatedSoon`'s lag, which can last up to 5 s. No test in the suite covers this order.
**Fix:** Keep a window fresh while its bundle is quitting, and add the missing test:
```swift
let quittingBundles = Set(quitting.values.map(\.bundleID))
return (waits(for: id.bundleID) || quittingBundles.contains(id.bundleID)) && !docked
```

### WR-06: The quit hold depends on `.appTerminated` arriving first, and that is unverified for real apps

**File:** `Sources/TransomEngine/Arranger+Placeholders.swift:134-136`, `Sources/TransomEngine/CloseRule.swift:56`
**Issue:** `holdForQuit` only holds a window whose pid is already in `quitting`. If an app closes its windows while its process is still alive, `CloseRule` returns `.closed` from `(.alive, .invalidElement, false)`, and the tile closes before `.appTerminated` arrives. D-12a then fails with no recovery. 08-04 verified the order only with the fixture's `exit(0)`, and it skipped the Pitfall 1 rollback for that reason.
**Fix:** Test ⌘Q on real apps in UAT, including an Electron app and a document app with a save prompt. Unless that order is shown to be safe, add the rollback: keep recently closed docked refs for about 1.5 s, and convert them to placeholders if `.appTerminated` follows for that pid.

### WR-07: Title hints go stale, and an empty title can overwrite a good one

**File:** `Sources/TransomEngine/Arranger.swift:263`, `Sources/TransomModel/World.swift:137-142`, `Sources/TransomEngine/Arranger+Placeholders.swift:137-138`
**Issue:** There are two defects:
- `WindowRef` equality ignores titles, so `world != before` is false for a title change and no save is scheduled. After a crash or power loss, layout.json holds the title from the last World change. Titles are worth the most points in matching.
- `refreshingTitles` applies any title it is given, including `""`. A window that momentarily reports no title, for example during teardown or while loading, erases its saved hint in the snapshot and in `holdForQuit`. `HintMatcher` scores nothing for an empty title.

**Fix:** Ignore empty titles in `refreshingTitles`: `if let title = titles[window.identity], !title.isEmpty`. Schedule a debounced save when a docked or floating window's title changes, comparing `titleHint` in the `.windowChanged` branch.

### WR-08: If moving a rejected file aside fails, the next save overwrites it

**File:** `Sources/TransomMac/LayoutStore.swift:51`, `:148-156`, `Sources/TransomMac/ArrangeController.swift:222`
**Issue:** The doc comment says the move happens "so the next save cannot destroy it". When `moveItem` fails, `setAside` only logs, `savingDisabled` stays false, and the launch write replaces the file. A successful move also deletes any earlier `.corrupt` copy, so a second rejection destroys the first file, which may be the only copy of the user's views. `backUp` already uses timestamps to avoid this.
**Fix:** Set `savingDisabled = true` when the move fails. Name the copy `layout.json.corrupt-<unix seconds>`, as `backUp` does, so none is replaced.

### WR-09: Nothing caps titles or the saved file's size, so an oversized file is rejected whole at the next launch

**File:** `Sources/TransomMac/LayoutStore.swift:58-65`, `:94`, `Sources/TransomEngine/WindowTracker.swift:145`
**Issue:** `load` rejects anything over `World.maxEncodedBytes` (16 MB), but `save` never checks that limit. Since D-10, the file holds raw AX titles from other apps, with no length cap, across the World and up to 16 layout sets. Reaching 16 MB takes a misbehaving app or unusually long titles, so this is unlikely. If it happens, the save succeeds, and the next launch moves the file aside and starts empty, losing every layout and view.
**Fix:** Truncate titles when they are captured or saved, for example to 512 characters, and compare the same truncated form in `HintMatcher`. In `save`, refuse to write over the cap and keep the previous file: `guard data.count <= World.maxEncodedBytes else { throw .tooLarge(data.count) }`.

### WR-10: Re-matched windows lose their saved wanted and home frames, and a reused ID can inherit another window's

**File:** `Sources/TransomEngine/Arranger.swift:314`, `:707-709`, `Sources/TransomEngine/Arranger+Placeholders.swift:221-224`
**Issue:** Saved frames are keyed by the old identity and are not carried over on a match. `reattach` filters them to identities the World still holds, and `forget(match.saved)` drops them in the fill path, which substitutes the window's current frame. The `.windowRekeyed` path at lines 923-925 does carry them over. So the pre-dock frame that `LayoutFile.wantedFrames` exists to preserve is lost on exactly the windows VIEW-04 brings back. After a reboot, an entry whose old identity is reused by a different window is also kept and applied to that window.
**Fix:** Move `wantedFrames` and `homeFrames` through the same throwaway-identity pass used for `remapViews`. In the fill path, read the saved window's wanted frame before calling `forget`.

### WR-11: A placeholder's stage tile uses its dead window ID, which can match a live window after a reboot

**File:** `Sources/TransomMac/Zoom/StagePanel.swift:34-36`, `:378`, `Sources/TransomMac/Zoom/ZoomController.swift` (`StageTile.placeholders(of:) + windows`), `Sources/TransomMac/Overview/OverviewController.swift:563`
**Issue:** The comment at `StagePanel.swift` says these IDs "match no click", but after a reboot a dead ID can equal a live CG window ID, which is the premise of the boot guard. Layers are built with `uniquingKeysWith: { first, _ in first }`, and placeholders come first, so the placeholder wins and the live window loses its stage layer during that camera move. In the overview, removing a gone placeholder by ID also removes the live tile that shares it. A click on the placeholder could also resolve to that live window.
**Fix:** Give placeholders their own ID space, as `stripID` does for strips, and check that it can't collide with `stripID`, for example by deriving it from the identity with a reserved bit. Use it in both the stage and the overview.

### WR-12: `vm-cli-check.sh` can delete the guest's data, and can report success with checks skipped

**File:** `scripts/vm-cli-check.sh:39`, `:48-49`, `:94-95`, `:129-140`
**Issue:** This affects only the test VM, but it contradicts the script's header:
- Line 94 doesn't check `ditto`, and the guest script has no `set -e`. Line 95 sets `support_saved=1` regardless, so a failed backup makes cleanup run `rm -rf "$support"` with nothing to restore.
- After `pkill` at line 48, cleanup restores the folder at once. The app handles SIGTERM with a clean-exit write, so it can overwrite the restored files.
- Line 39 exits before the trap is set, leaving `~/transomcli` in the guest, despite "Nothing stays in the guest".
- The check assumes slot 7 is empty, but the guest's real layout.json is kept, so a saved slot 7 gives a false failure.
- Any other refusal reason, such as no Accessibility permission, prints `SKIP` and still ends with "N checks passed".

**Fix:**
- Use `ditto ... || { echo "backup failed" >&2; exit 1; }` before setting `support_saved`.
- Wait for the process to exit after `pkill`.
- Set the trap before line 39.
- Start the app with an empty support folder after the backup, so slot 7 is known to be empty.
- Make the final line report skips, and exit non-zero if any occurred.

### WR-13: `release.sh` can ship a stale helper from an incremental build

**File:** `scripts/release.sh:36`, `:60-72`, `scripts/build-debug.sh:21-22`
**Issue:** 08-05 recorded that an incremental Release build kept an old signed copy in `Contents/Helpers` while `Products/Release/transom` was correct. `vm-cli-check.sh:24` deletes the bundle first for that reason, but `release.sh` doesn't, and neither does `build-debug.sh`. The release checks cover signing and architectures, not whether the helper came from the current build, so a correctly signed old tool would pass and be notarised.
**Fix:** Run `rm -rf "xcode/.xcode-build/Build/Products/Release/Transom.app"` before building in `release.sh`, or do a clean build for releases.

## Info

### IN-01: `exitCode(sendStatus:)` ignores its status

**File:** `Sources/TransomEngine/CLIProtocol.swift:33`
**Issue:** The parameter is unused. If the app quits between `CFMessagePortCreateRemote` and the send, `kCFMessagePortIsInvalid` is reported as "didn't answer" (exit 1), not "not running" (exit 2).
**Fix:** Map `kCFMessagePortIsInvalid` to `CLICopy.notRunning` and exit 2, or remove the parameter.

### IN-02: The 0600 mode is applied after the file is published

**File:** `Sources/TransomMac/LayoutStore.swift:64-65`
**Issue:** The atomic write puts the file at its final path before `setAttributes` runs, so a newly created file briefly has default permissions, or keeps them if `setAttributes` fails. The real exposure is small: `~/Library` is normally 0700, and the first write after a missing file usually holds no titles. I did not verify whether an atomic replace keeps an existing file's mode.
**Fix:** Write to a temporary file created with 0600 in the same directory, then replace `layout.json` with it.

### IN-03: `Placeholder.origin` is mostly unused, and launch placeholders don't log the "shown" line

**File:** `Sources/TransomEngine/Arranger+Placeholders.swift:16`, `:142`, `:163-168`, `:232`
**Issue:** Only `!= .tie` ever reads `origin`, so `.launch` and `.appQuit` are never told apart. UI-SPEC's logging table asks for "placeholder {node} for {bundle}: shown ({launch | app quit | tie})", but only the app-quit path logs it.
**Fix:** Log the line from `holdAtLaunch` using `origin`, which also gives the field its purpose.

### IN-04: The `TRANSOM_CLI_PORT` test hook ships in the release tool

**File:** `Sources/transom-cli/main.swift:28`, `Sources/TransomEngine/CLIProtocol.swift:15`
**Issue:** The notarised binary honours an environment variable that redirects it to any port. Setting it requires control of the caller's environment and replies are sanitised, so this grants no new access. It is still undocumented behaviour in a release build.
**Fix:** Either accept and document it, or compile it only into Debug builds if the tests allow that.

---

_Reviewed: 2026-11-04T02:01:47Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
