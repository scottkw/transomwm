---
status: testing
phase: 07-tab-groups
source: 07-UI-SPEC.md "User host checklist" (items 1-5, verbatim) and backstop rows; RESEARCH Assumption A3; 07-01..07-11-SUMMARY.md items left to UAT
started: 2026-11-02
updated: 2026-11-02 (VM run, agent; fixes after VM UAT)
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing: VM run done 2026-11-02 (V1-V16, see "VM UAT run"); host items 1-5 and backstops B1-B3 wait for the user]

## Build under test

- Code: HEAD `1267086`, which includes the review fixes CR-01 and WR-01 to WR-04 (`1267086` itself changes planning files only).
- App: `/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, rebuilt by `scripts/build-debug.sh` on 2026-11-01 at 22:19 CST (binary sha1 `52c7fc84…`). Developer ID signed, team S2K7P43927, bundle `com.eightabyte.transom.debug`; `codesign --verify --strict` and the designated-requirement check passed. The agent built it and never launched it.

## Automated results (2026-11-02)

| Run | Result |
|---|---|
| `scripts/check-no-appkit.sh` | OK (55 files) |
| Host `swift test` (full, `.build/0712-full.log`) | 219 + 390 + 93 + 952 = 1,654 tests, 0 failures (no FreezeTestTests re-run needed) |
| VM `TabGroupIntegrationTests` | 5 tests passed |
| VM `TabStripSpaceIntegrationTests` | 1 test passed |
| VM `QuitRestoreIntegrationTests` (regression) | 3 tests passed |
| VM `FocusParkIntegrationTests` (regression) | 2 tests passed |
| VM `TabsIntegrationTests` (Phase 2 regression) | 1 test passed |

VM: Tart `pane-test`, macOS 15.7.7. One suite per `scripts/vm-live-test.sh` run, fixtures only. Logs are in `.build/0712-vm-*.log`.

Re-run on the rebuilt HEAD `1267086` (2026-11-01):

| Run | Result |
|---|---|
| VM `TabGroupIntegrationTests` | "Test run with 5 tests in 1 suite passed after 8.230 seconds" (`.build/0713-vm-TabGroupIntegrationTests.log`) |
| VM `TabStripSpaceIntegrationTests` | "Test run with 1 test in 1 suite passed after 2.506 seconds" (`.build/0713-vm-TabStripSpaceIntegrationTests.log`) |

## Before you start

1. Quit every other Transom build (menu bar icon ▸ Quit), then check `pgrep -fl "Transom"` prints nothing.
2. Launch `open "/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app"`. Give "Transom Debug" Accessibility if asked. Screen Recording is needed only for the zoom-stage item (V12).
3. Answer each item with "pass" or what you saw instead.

## 1. Host checklist (UI-SPEC, verbatim)

1. Drag a Finder window by its title bar onto the middle of a docked TextEdit window and hold still for about half a second. *Expected: the preview changes to an outline with a band along the top, labelled "Group as tabs". Release: both windows share the tile under one tab strip, Finder's tab selected.*
   result: pending

2. Click the TextEdit tab, then the Finder tab. *Expected: the windows swap in place with no flash of the desktop picture.*
   result: pending

3. Drag the Finder tab out of the strip onto empty Desktop and release. *Expected: Finder floats where the dashed outline showed; TextEdit goes back to being a plain tile with no strip.*
   result: pending

4. Group a Safari window that has several tabs with another window, then switch Safari tabs. *Expected: one Safari tab in the strip whose title follows the Safari tab you're on.*
   result: pending

5. Type in TextEdit without saving, then click Close Group. *Expected: TextEdit asks whether to save, in view in the group's place; nothing else closes until you answer.*
   result: pending

## 2. VM checks (Tart VM pane-test, fixture windows, one at a time)

Run by the verifier in the VM, never on the host. Leave the guest on Desktop 1 and quit only what you launched.

V1. Float a group of two fixture windows, then raise another floating window over it. *Expected: that window covers the group's strip too. Clicking the group's window brings window and strip back in front together.*
   result: partial (VM, synthetic events) — **Bug 1.** Float Group (a HID click on the strip button) floated the group ("group n30: floated"), and the front app stayed the fixture. A floating window of another app raised over the group covered the strip (CG order: covering window, strip, group window). **Clicking the group's window did not bring the strip back.** After the click the order was group window, covering window, strip, and it was the same 2 s later (`.build/0713-uat-vm-shots/v1-crossapp-after-click.png`). A third fixture app gave the same result. When the covering window came from the **same** app as the group's window, the click did raise the strip (order: strip, group window, covering window). So the strip comes front only when the click changes the app's focused window. It does not when the click only activates an app whose focused window was already the group's window. Cause: Bug 1 below
   **Fixes after VM UAT:** fixed by `5a48451` (an app activation now reports the activated app's AXMain window as focused, so `raisedStrip` runs). VM proof with the rebuilt Debug app (2026-11-02): fixture C raised over a floating group's strip (CG order C, group window, strip); a click on the group window's uncovered part gave CG order **strip, group window, C** (`.build/0714-vm-check/`)

V2. With another app frontmost, click a hidden tab once. *Expected: it switches at once; the frontmost app becomes the tab's app, never Transom.*
   result: pass (VM, synthetic events) — with another fixture app frontmost, one HID click on the hidden tab switched at once ("group n32: select window 4094 … via click, 11 ms"). At 150, 300 and 600 ms the frontmost app was the tab's app (pid 23059), never Transom

V3. ⌘Tab to the app of a hidden member. *Expected: that tab becomes selected and its window fills the content rect.*
   result: fail (VM, synthetic events) — **Bug 1.** ⌘Tab (⌘ held, Tab pressed twice) to the hidden member's app made that app frontmost, but there was no tab switch. Its hidden window stayed parked at the 1 pt sliver (1023,689) as the app's focused, main window, so it was an invisible key window. It was the same 3 s later (`v3-after-cmdtab.png`). A stock app reproduced it during the V14 setup: `open -a "Font Book"`, while Font Book's only window was a hidden tab, left the window parked and Font Book frontmost. In both cases the app's focused window was already the hidden member, so macOS sent no focused-window change
   **Fixes after VM UAT:** fixed by `5a48451`. VM proof: the new `TabGroupIntegrationTests.activatingTheAppOfAHiddenMemberSelectsIt` (two fixture apps; the hidden member's app activated by AXFrontmost, its parked window key) failed with the hook disabled (window stayed at 1023,687, selected tab unchanged, `.build/0714-vm-red.log`) and passes with it: "Test run with 6 tests in 1 suite passed after 14.044 seconds" (`.build/0714-vm-TabGroupIntegrationTests.log`). With the rebuilt Debug app, a synthetic ⌘Tab to the hidden member's app logged "group n30: select window 4335 … via activation, 6 ms" and the window filled the content rect (40,112 320×200) while the other member parked. `open -a` and a Dock click take the same activation path; they were not re-run

V4. Tear a tab off to a screen edge and release. *Expected: it docks there, with the normal drop preview while dragging.*
   result: pass (VM, synthetic events) — a tab dragged to the left screen edge and released logged "moved out via tear-off, landed docked". It docked at 8,33 246×676, and the other member kept the tile. Mid-drag, the CG list showed the tear-off ghost (layer 4, 54×24 beside the pointer) and the full-screen drop preview panel (layer 3). Both panels are `sharingType = .none`, so screenshots don't show them. **Harness note:** the synthetic events had to carry the strip's window number in `kCGMouseEventWindowUnderMousePointer`. With the field at 0 (plain synthetic events), Transom logged "press … on CG window 0: no tracked window" and no tear-off began. Real hardware events most likely fill the field, so this looks like a harness limit; host item 3 is the real check

V5. Tear a tab off onto empty Desktop and release. *Expected: it floats at the dashed outline (clamp ghost); a two-tab group dissolves into a plain tile.*
   result: pass (VM, synthetic events) — a tab torn off onto empty Desktop (the Desktop tile) and released logged "landed floating". It landed at 516,65 246×644, clamped inside the Desktop tile. The log then read "group n35: dissolved, … keeps the tile", and the survivor became a plain tile again (770,33 246×676, no strip). The dashed outline is drawn in the uncapturable preview panel, so whether the window landed exactly at the outline was not seen

V6. Tear a tab off and press Esc mid-drag. *Expected: nothing changes; the tab stays in the group.*
   result: pass (VM, synthetic events) — Esc mid tear-off logged "Tab move canceled" / "group n35: tear-off canceled (esc)". The ghost and the preview went at once, the group kept both tabs, and both members stayed where they were

V7. With groups formed, quit Transom. *Expected: every member is on screen, in its group's content rect.* Relaunch, then `kill -9` Transom and relaunch again. *Expected: the N2 notice counts the parked members, and the groups re-form with the same selected tabs.*
   result: partial (VM, synthetic events) — Quit with a docked 4-tab group and a floating 2-tab group logged "quit: 4 group members placed at their content rects", and every member was on screen at its group's content rect. On relaunch both groups re-formed with the same selected tabs (C3, B1), and the hidden members parked again. After `kill -9` and a relaunch, the N2 panel read "Transom quit unexpectedly. Your windows are back on screen and your layout is restored." (log `notice crashRecovered(unplaced: 0)`, `v7-notice.png`), and the groups re-formed with the same selected tabs. **Mismatch:** N2 does not count the parked members. The UI-SPEC says "N2 counts them", but `NoticeCopy` counts only windows that couldn't be placed. The user should decide whether to change the copy or the spec

V8. Choose Restore All Windows. *Expected: every member is shown (N6 counts them) and the groups are gone.* Then Undo Layout Change. *Expected: the groups come back.*
   result: pass (VM, synthetic events) — Restore All Windows logged "restore all: dissolved 2 groups, 4 windows brought back" and showed N6 "Moved 4 windows back on screen.". Every member was on screen and there were no strips. Undo Layout Change brought both groups back with the same selected tabs and parked the hidden members again

V9. Switch Spaces away from a group and back, then lock and unlock the screen. *Expected: the strip shows only on its group's Space, and is still there and in place after unlock.*
   result: pass (VM, synthetic events) — after ⌃← to Desktop 1, no Transom strip was on screen there; after ⌃→ back, both strips were in place (`TabStripSpaceIntegrationTests` also passed). ⌃⌘Q, posted directly and through System Events, did not lock the guest. The lock was done with `pmset displaysleepnow` (CGSession locked=1) and then a wake. The log read "session paused: locked or asleep" / "session resumed after a full refresh", and both strips were still there and in place. A lock that needs a password to unlock was not tested

V10. Right-click a tab. *Expected: the context menu opens and tracks (Transom stays inactive); Close Tab closes that member (revealing it first if hidden) and Move Out of Group floats it beside the group.* If the menu does not track, the fix route is `NSMenu.popUpContextMenu` (RESEARCH A3).
   result: pass (VM, synthetic events) — a right-click on a hidden tab opened the menu at the pointer with Close Tab and Move Out of Group (`v10-menu.png`); the front app stayed the fixture. The menu tracked: a HID click on Close Tab chose it. Close Tab on the hidden member revealed it first ("select … via close") and then closed it. The log read "Tab group ended", and the other member kept the tile. Move Out of Group logged "moved out via menu, landed floating" at 516,57. That is inside the Desktop tile; the group was two columns away, so this is as near "beside" as the Desktop tile allows

V11. Strip details: icon and middle-truncated titles, neutral selected tab, hover and pressed fades, tooltips, the overflow menu with many tabs, the Close / Minimize / Float Group buttons (Minimize Group minimises the selected member; Float or Dock Group moves the whole group), and a title-bar drag of the selected window moving the whole group. Also with Increase Contrast on. *Expected: as UI-SPEC Surfaces 2-4; nothing activates Transom.*
   result: partial (VM, synthetic events) — **Works:**
   - Tooltip strings and labels are set: AXHelp "Tab n of m", "Closes all 5 windows in this tab group", "2 more tabs".
   - With 5 tabs, the More Tabs button opened a menu listing the 2 hidden tabs; picking one selected it ("via overflow, 2 ms").
   - Float Group, Dock Group and Minimize Group acted on the group. Minimize Group minimised only the selected member and the hidden members stayed parked. When macOS focused a parked member, Transom handed focus to an on-screen window.
   - A title-bar drag of the selected window moved the whole group, and the strip followed (32 pt above the window at the end, as at rest).
   - Nothing activated Transom.
   **Not judged:** the strip panel is `sharingType = .none`, so no screenshot shows the icons, middle truncation, the neutral selected tab, hover and pressed fades, or Increase Contrast. Tooltips did not appear on synthetic hover. **Seen in passing:** after Minimize Group the strip stayed on screen over the empty tile for about 2 s. After the restore it took about 2 s to come back. Both times it waited for the "display change seen; debouncing" that the Dock's change set off; UI-SPEC says 120 ms. Mid-drag, the strip trailed the window by about 10 pt (hardware item B1 judges this)

V12. Zoom on, with a group: zoom out and open the overview (⌃⌥⌘A). *Expected: the stage draws the group as its selected tile plus an icon-only strip above it; the real strip hides during the move and fades back (120 ms) at rest; the overview shows one tile per group (hidden tabs not listed) with its strip; a collapsed group shows its label.*
   result: partial (VM, synthetic events) — the overview (⌃⌥⌘A) showed 6 tiles: one per group, with the hidden tabs not listed, and each group drawn as its selected tile with an icon-only strip above it (`v12-overview.png`). The real strip was ordered out while the overview was open and came back as soon as Esc closed it. Then Frame Focused Window on a group member, followed by Zoom Out to All Windows: mid-move, the stage drew the group's selected tile with its icon-only strip (`v12-out-mid.png`). The real strip was gone during the move and back 0.1-0.2 s after "settle". Not checked: the length of the 120 ms fade, and the collapsed-group label (the run never got a collapsed group in the one-display VM). Tiles were app icons only, because the guest has no Screen Recording grant

V13. Press ⌃⌥⌘T, ⇧⌃⌥⌘T and ⌃⌥⌘L with a group focused, then open `transom://next-tab` with no group focused. *Expected: next, previous (both wrap) and Move Out of Group work; Arrange ▸ Tabs sits after Snap Floating Window; the URL refusal only logs (no beep).*
   result: partial (VM, synthetic events) — **Bug 2.**
   - ⌃⌥⌘T from tab 3 of 5 went to 4, 5, then 1 (wraps). ⇧⌃⌥⌘T from 1 went to 5, 4, 3, then 2 (wraps). ⌃⌥⌘L moved the selected member out ("moved out via hotkey, landed floating").
   - Arrange ▸ Tabs (Next Tab, Previous Tab, Move Out of Group) sits right after Snap Floating Window.
   - With no group focused, the URL only logged "refused next tab: not in a tab group". URLs have no announcement path, and the beep can't be heard in the VM.
   - **With a group focused, `open "transom-debug://next-tab"` was refused the same way.** `open -g` (background) worked ("select … via url"). A plain `open` makes Transom Debug the frontmost app, and the tab command reads the frontmost app's focused window.
   - Note: the Debug build's scheme is `transom-debug://`. `transom://` went to the older release Transom.app in the guest (see the run notes)
   **Fixes after VM UAT:** fixed by `bdd2d22` (a URL that arrives with Transom frontmost acts on the focused window of the app frontmost before Transom; every URL command that needs the focused window, i.e. the tab commands and `frame-window`). Unit test `AppDelegateTests.aURLActsOnTheAppFrontmostBeforeTransom`. VM proof with the rebuilt Debug app: with a group member focused, `open "transom-debug://next-tab"` (no -g) logged "group n30: select window 4335 … via url, 4 ms"; a second run, with an activation watcher, showed Transom Debug activated, then "select window 4340 … via url, 5 ms" and the tab's app activated 25 ms later

V14. (CR-01) Choose Don't Arrange (⌃⌥⌘E or the menu) for an app whose window is a hidden tab, once in a docked group and once in a floating group. *Expected: the hidden window comes back on screen at the group's content rect, the group loses it (dissolves if one is left), nothing is stranded at the 1 pt parked sliver.* Remove the exclusion afterwards.
   result: pass (VM, synthetic events) — **Docked:** Font Book's only window was the hidden tab of a docked group (content rect 8,65 1008×532), with Font Book frontmost. ⌃⌥⌘E logged "exclusion releases window 4186 … back on screen". The window came back at 8,65 1008×532, the group was gone, and the fixture kept the tile. **Floating:** with the group's content rect at 8,206, Font Book came back at 8,206, the group dissolved, and the survivor took the group's frame. Nothing stayed at the parked sliver. The exclusion was removed both times (`excludedBundleIDs` empty)

V15. Make a cross-app floating group: drop a Finder window on a floating TextEdit window's centre with the 400 ms rest. *Expected: they group, the strip shows both, switching works.*
   result: pass (VM, synthetic events) — a new Finder window dropped on the centre of a new floating TextEdit document, with a 550 ms rest, logged "group n33: created from window 4209 … com.apple.finder + window 4208 … com.apple.TextEdit (floating)". The strip listed both. Clicking the TextEdit tab, then the Finder tab, swapped the windows in place (3 ms each) and made each app frontmost

V16. (WR-02) ⌘M the selected tab of a 3-tab group. *Expected: a neighbour is selected and the group keeps its tile and strip.* Then Minimize Group on a group of two windows of one app. *Expected: both stay minimised; no parked window is left key or frontmost.*
   result: pass (VM, synthetic events) — **⌘M:** in a 3-tab fixture group, the selected (rightmost) tab was minimised. Its left neighbour was selected and shown at the content rect, and the group kept its tile and strip (3 windows). When the minimised member came back, the selection stayed and the returning member was parked. Once along the way the log read "select … failed, no read-back after 1 s; kept …", but the end state was correct. The fixture has no Window menu, so its own `minimize` command stood in for ⌘M. **Minimize Group** on two windows of one app: the selected one minimised. macOS focused the parked sibling, and Transom handed focus to an on-screen Finder window ("focus … handed to window 4209"). The fixture reported "frontmost none", so no parked window was key or frontmost. Because an on-screen window could take focus, the sibling stayed parked rather than minimised. The case with no other window on screen (both minimised) is covered by `minimizeGroupWithTwoWindowsOfOneAppStaysMinimized`, which passed above

## 3. Backstops on hardware (MacBook Air)

B1. Drag a grouped window by its title bar quickly. *Expected: the strip stays attached with no visible gap.*
   result: pending

B2. Switch tabs between two windows of different apps 10 times. *Expected: no flash of the desktop picture in the content rect.*
   result: pending

B3. Turn on VoiceOver and move to the strip. *Expected: "Tab group, 2 windows"; each tab reads its app, title and position; Close Tab and Move Out of Group are in the actions rotor.*
   result: pending

## VM UAT run (2026-11-02, agent)

Items V1-V16 ran in the Tart `pane-test` guest (macOS 15.7.7, one 1024×768 display, two desktops) against the rebuilt build under test (sha1 `52c7fc84…`). It was installed as `/Applications/Transom Debug.app`; the previous install is kept as `~/uat0713/Transom Debug.app.old` in the guest. Transom was launched with `open --env TRANSOM_STAGE_CAPTURABLE=1`. The run used Desktop 2, which was empty, and left Desktop 1's windows alone.

Method (same as Phase 6):
- **Windows:** TransomFixtureApp windows from several fixture processes, so they count as different apps for activation. Stock apps the run launched or opened itself: a new TextEdit document, a new Finder window, and Font Book.
- **Input:** synthetic CGEvents at the HID tap, from a throwaway driver (`.build/0713-uat-vm-shots/uat07-driver.swift`): clicks, title-bar drags with a rest, right-clicks, ⌘Tab, and flagless key-ups.
- **Reading state:** strip state through AX (the strip is an AXTabGroup with tab radio buttons and group buttons); z-order and frames through `CGWindowListCopyWindowInfo`.
- **Evidence:** the guest log is `.build/0713-uat-vm-transom.log`, and screenshots and CG captures are in `.build/0713-uat-vm-shots/`.

Caveats:
- The tab strip, drop preview and tear-off ghost are `sharingType = .none`, so screenshots never show them. Only the stage and overview are capturable. Strip visuals (V11) are left for the user.
- To start a tear-off, synthetic drags must set the window-under-pointer field to the strip's window number (V4 harness note).
- Not checkable in the VM: feel, audio (beeps, VoiceOver), the hardware trackpad, macOS 27, password-protected lock, and multiple displays.
- The guest clock jumped during the run, so guest log timestamps are not wall-clock order across steps.

Run incidents, all guest-only:
- macOS asked whether `com.apple.sshd-session` may bypass the private window picker for screen capture. The run answered Allow, so `screencapture` over ssh works.
- `open transom://next-tab` launched the older release `/Applications/Transom.app`, which the run then quit. Before quitting it logged "layout.json was saved by a newer Transom (schema 2); leaving it untouched". On quit it moved three of Transom Debug's parked hidden tabs on screen. Transom Debug did not re-park them until each tab was selected once.
- A Font Book drag by the toolbar did not move the window, and Transom docked Font Book where the pointer was released. The run undid this and later reset the guest (quit Transom, restored `layout.json`) before V14.

Guest state afterwards (checked again with the VM lock held):
- No Transom, Transom Debug, fixture, Font Book, `caffeinate` or `log stream` process left by the run.
- `excludedBundleIDs` is empty; `layout.json`, `min-size-hints.json` and the `com.eightabyte.transom.debug` defaults are restored from the pre-run backups (cmp equal).
- The four TextEdit documents that were there at the start (Untitled 2-5, Untitled 2 unsaved) are untouched. The run's own document and Finder window are closed.
- The guest is on Desktop 1, and no modifier keys are held.

### VM results

| Item | Result |
|---|---|
| V1 | partial: covered strip not raised by a cross-app click (Bug 1); fixed `5a48451`, VM re-check pass |
| V2 | pass |
| V3 | fail: ⌘Tab leaves the hidden member parked and key (Bug 1); fixed `5a48451`, VM re-check pass |
| V4 | pass (window-number field set by the harness) |
| V5 | pass |
| V6 | pass |
| V7 | partial: N2 doesn't count parked members (copy/spec mismatch) |
| V8 | pass |
| V9 | pass (display-sleep lock) |
| V10 | pass |
| V11 | partial: behaviour pass; visuals and tooltips not capturable; strip lingers ~2 s after Minimize Group |
| V12 | partial: stage and overview pass; collapsed label and fade length not checked |
| V13 | partial: hotkeys and menu pass; tab URL refused when `open` activates Transom (Bug 2); fixed `bdd2d22`, VM re-check pass |
| V14 | pass (docked and floating) |
| V15 | pass |
| V16 | pass |

### Bugs found

1. **Activating an app without changing its focused window sends Transom no focus event** (V1, V3, also seen in V14 setup).
   - **Evidence, V3:** after ⌘Tab, Font Book or the fixture app is frontmost, but its window stays parked at 1023,689 as AXMain. Nothing in the log, no select.
   - **Evidence, V1:** the CG order stays group window, covering window, strip after the click; a same-app focus change does raise the strip.
   - **Probable cause:** `AXWindowSystem.handle(_:)` records a focus hint only for `kAXFocusedWindowChanged` / `kAXMainWindowChanged`. The `didActivateApplication` observers (`ArrangeController`, `AppRegistry`) never hint focus for the activated pid. So `Arranger` never gets `.windowFocused`, and neither `activated` (D-08) nor `raisedStrip` runs.
   - **Impact:** an invisible key window after ⌘Tab or the Dock; the strip stays covered.
2. **Tab URLs are refused when opened normally** (V13).
   - **Evidence:** `open "transom-debug://next-tab"` with a group's window focused logs "refused next tab: not in a tab group", and Transom Debug becomes frontmost. The same URL with `open -g` logs "select … via url".
   - **Probable cause:** `ArrangeController.commandContext()` takes the focused window of `NSWorkspace.frontmostApplication`, which is Transom itself once LaunchServices activates it to deliver the URL. The Phase 3/4/6 URLs don't need a focused window, so this is new with the Phase 7 tab URLs.

Minor observations (not filed as bugs):
- N2 has no parked-member count (V7).
- After Minimize Group or a restore, the strip changes only after the ~2 s display-change debounce the Dock sets off (V11).
- A hidden tab moved on screen by another program stays there until it is selected once (run incidents).

### Fixes after VM UAT (2026-11-02)

| Bug | Commit | Root cause | Proof |
|---|---|---|---|
| 1 (V1, V3) | `5a48451` | Only `kAXFocusedWindowChanged` / `kAXMainWindowChanged` became focus hints; an app activation that keeps the app's focused window sent Transom nothing | 5 `PendingFocusTests`; VM `TabGroupIntegrationTests` red without the hook, 6/6 green with it; Debug app ⌘Tab and cross-app click re-checks |
| 2 (V13) | `bdd2d22` | `commandContext()` read Transom's own focused window once `open` activated Transom to deliver the URL | `AppDelegateTests.aURLActsOnTheAppFrontmostBeforeTransom`; Debug app `open` (no -g) re-check |

- Host `swift test` (full): 219 + 391 + 94 + 966 tests passed (`.build/0714-host-full-fix2.log`); `scripts/check-no-appkit.sh` OK (55 files).
- VM regressions: `TabStripSpaceIntegrationTests` 1 passed, `FocusParkIntegrationTests` 2 passed.
- Debug app rebuilt by `scripts/build-debug.sh` (main binary sha1 `ff9b4638…`); installed in the guest only for the re-check, then the previous build (`52c7fc84…`) was put back. Guest `layout.json`, `min-size-hints.json` and defaults were restored (cmp equal), and the guest was left on Desktop 1.
- Behaviour change to know: ⌘Tab or a Dock click to an app now counts as focusing its main window, so the focus order updates, a selected member's strip comes front, and (zoom on) a window outside the view widens the camera, as an AX focus change always did.
- Not changed: N2 still has no parked-member count (V7). `Notice.crashRecovered` only carries windows that couldn't be placed, so a count needs new N2 copy, which is a copy decision.

## Known gaps

- No keyboard or VoiceOver way to form a group in Phase 7 (UI-SPEC unresolved item, accepted; candidate for Phase 8's URL/CLI "group with" command).
- Multi-display tab checks deferred to hardware items, as in Phase 6.
- macOS 14 not tested: evidence is the VM (macOS 15.7.7) and the host (macOS 27.2).
- Stage strip IDs flip the top bit of the window ID (`StageTile.stripID`, `shortcut:` comment); a CG window ID of 0x7000_0000 or more could collide. CG IDs are small in practice (07-11).
- A reveal right after a Space change while the stage is up can briefly fade in the previous Space's strips until the replan replaces them (07-11).
