---
status: testing
phase: 07-tab-groups
source: 07-UI-SPEC.md "User host checklist" (items 1-5, verbatim) and backstop rows; RESEARCH Assumption A3; 07-01..07-11-SUMMARY.md items left to UAT
started: 2026-11-02
updated: 2026-11-02
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing: nothing run yet; host checklist and hardware backstops are the user's, VM checks are the verifier's]

## Build under test

- Code: HEAD `8a8973a` (07-11 complete; the 07-12 commits change planning files only).
- App: `/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, built by `scripts/build-debug.sh` on 2026-11-02. Developer ID signed, team S2K7P43927, bundle `com.eightabyte.transom.debug`; `codesign --verify --strict` and the designated-requirement check passed. The agent built it and never launched it.

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
   result: pending

V2. With another app frontmost, click a hidden tab once. *Expected: it switches at once; the frontmost app becomes the tab's app, never Transom.*
   result: pending

V3. ⌘Tab to the app of a hidden member. *Expected: that tab becomes selected and its window fills the content rect.*
   result: pending

V4. Tear a tab off to a screen edge and release. *Expected: it docks there, with the normal drop preview while dragging.*
   result: pending

V5. Tear a tab off onto empty Desktop and release. *Expected: it floats at the dashed outline (clamp ghost); a two-tab group dissolves into a plain tile.*
   result: pending

V6. Tear a tab off and press Esc mid-drag. *Expected: nothing changes; the tab stays in the group.*
   result: pending

V7. With groups formed, quit Transom. *Expected: every member is on screen, in its group's content rect.* Relaunch, then `kill -9` Transom and relaunch again. *Expected: the N2 notice counts the parked members, and the groups re-form with the same selected tabs.*
   result: pending

V8. Choose Restore All Windows. *Expected: every member is shown (N6 counts them) and the groups are gone.* Then Undo Layout Change. *Expected: the groups come back.*
   result: pending

V9. Switch Spaces away from a group and back, then lock and unlock the screen. *Expected: the strip shows only on its group's Space, and is still there and in place after unlock.*
   result: pending

V10. Right-click a tab. *Expected: the context menu opens and tracks (Transom stays inactive); Close Tab closes that member (revealing it first if hidden) and Move Out of Group floats it beside the group.* If the menu does not track, the fix route is `NSMenu.popUpContextMenu` (RESEARCH A3).
   result: pending

V11. Strip details: icon and middle-truncated titles, neutral selected tab, hover and pressed fades, tooltips, the overflow menu with many tabs, the Close / Minimize / Float Group buttons (Minimize Group minimises the selected member; Float or Dock Group moves the whole group), and a title-bar drag of the selected window moving the whole group. Also with Increase Contrast on. *Expected: as UI-SPEC Surfaces 2-4; nothing activates Transom.*
   result: pending

V12. Zoom on, with a group: zoom out and open the overview (⌃⌥⌘A). *Expected: the stage draws the group as its selected tile plus an icon-only strip above it; the real strip hides during the move and fades back (120 ms) at rest; the overview shows one tile per group (hidden tabs not listed) with its strip; a collapsed group shows its label.*
   result: pending

V13. Press ⌃⌥⌘T, ⇧⌃⌥⌘T and ⌃⌥⌘L with a group focused, then open `transom://next-tab` with no group focused. *Expected: next, previous (both wrap) and Move Out of Group work; Arrange ▸ Tabs sits after Snap Floating Window; the URL refusal only logs (no beep).*
   result: pending

## 3. Backstops on hardware (MacBook Air)

B1. Drag a grouped window by its title bar quickly. *Expected: the strip stays attached with no visible gap.*
   result: pending

B2. Switch tabs between two windows of different apps 10 times. *Expected: no flash of the desktop picture in the content rect.*
   result: pending

B3. Turn on VoiceOver and move to the strip. *Expected: "Tab group, 2 windows"; each tab reads its app, title and position; Close Tab and Move Out of Group are in the actions rotor.*
   result: pending

## Known gaps

- No keyboard or VoiceOver way to form a group in Phase 7 (UI-SPEC unresolved item, accepted; candidate for Phase 8's URL/CLI "group with" command).
- Multi-display tab checks deferred to hardware items, as in Phase 6.
- macOS 14 not tested: evidence is the VM (macOS 15.7.7) and the host (macOS 27.2).
- Stage strip IDs flip the top bit of the window ID (`StageTile.stripID`, `shortcut:` comment); a CG window ID of 0x7000_0000 or more could collide. CG IDs are small in practice (07-11).
- A reveal right after a Space change while the stage is up can briefly fade in the previous Space's strips until the replan replaces them (07-11).
