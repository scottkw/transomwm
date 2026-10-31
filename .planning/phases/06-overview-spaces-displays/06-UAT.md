---
status: testing
phase: 06-overview-spaces-displays
source: 06-UI-SPEC.md "User hardware checklist" (items 1-7, verbatim) and backstop rows; 06-RESEARCH.md takeover host item; 06-06..06-11-SUMMARY.md items left to UAT
started: 2026-10-31
updated: 2026-10-31
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[not started: waiting for the user's pass on the MacBook Air plus the DELL]

## Build under test

- Code: HEAD `a4141f1` (06-12 Task 1; the later 06-12 commits change planning files only).
- App: `/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, built by `scripts/build-debug.sh` on 2026-10-31. Developer ID signed, team S2K7P43927, bundle `com.eightabyte.transom.debug`. `codesign --verify --strict` and the designated-requirement check passed. The agent built it and never launched it.
- Swipe: **kept** (06-SPIKE verdict "skip → kept"). The four-finger swipe stays with macOS, so there is no swipe item.

## Automated results (2026-10-31)

| Run | Result |
|---|---|
| `scripts/check-no-appkit.sh` | OK (53 files) |
| Host `swift test` (full, `.build/0612-full.log`) | 193 + 363 + 83 + 809 = 1,448 tests. The only failure was FreezeTestTests.itResumesByItself (known load flake). Its re-run passed 8 of 8 (`.build/0612-freeze-rerun.log`) |
| VM `OverviewIntegrationTests` | 3 tests passed. The first two runs failed the Esc check ("Esc did not close the overview"); the next three runs passed with the test unchanged. Cause unknown, see `deferred-items.md` |
| VM `OverviewSpaceSwitchIntegrationTests` | 2 tests passed |
| VM `OverviewKeyboardIntegrationTests` | 1 test passed |
| VM `TakeoverIntegrationTests` | 2 tests passed |
| VM `SpacesIntegrationTests` (Phase 5 regression) | 2 tests passed |
| VM `ZoomSettleIntegrationTests` (Phase 5 regression) | 2 tests passed |

VM: Tart `pane-test`, macOS 15.7.7. One suite per `scripts/vm-live-test.sh` run, fixtures only. Logs are in `.build/0612-vm-*.log`. Afterwards the guest's symbolic hotkeys 32, 108 and 113 read back enabled (`/tmp/transom-hkread`), and the guest is on Desktop 1.

## Before you start

1. Quit every other Transom build (menu bar icon ▸ Quit), then check `pgrep -fl "Transom"` prints nothing.
2. Launch `open "/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app"`. Give "Transom Debug" Accessibility if asked. Screen Recording is needed for the preview items (B1, B2).
3. Zoom on (menu ▸ Turn On Zoom). Use the MacBook Air plus the DELL. The Debug submenu appears when you hold ⌥ while clicking the menu bar icon.
4. Answer each item with "pass" or what you saw instead.

## 1. Hardware checklist (UI-SPEC, verbatim)

1. With the DELL connected and windows docked on both displays, unplug the DELL. *Expected: after a second or two, the DELL's windows appear floating on the laptop screen and a notice says "“DELL …” was disconnected, so {n} windows from it are floating here until you reconnect it."*
   result: pending

2. Plug the DELL back in. *Expected: those windows go back to their tiles on the DELL. No notice.*
   result: pending

3. Repeat 1 and 2, but dock one of the floated windows on the laptop before re-plugging. *Expected: that window stays where you docked it; the others go home.*
   result: pending

4. Arrange windows differently with the DELL connected, unplug (laptop-only layout), arrange the laptop differently, then plug back in and unplug again. *Expected: each time, each setup comes back exactly as you left it.*
   result: pending

5. Close the lid or sleep the Mac with the DELL connected, unplug it while asleep, wake. *Expected: nothing moves until you're logged in again; then the item 1 behaviour.*
   result: pending

6. In System Settings ▸ Desktop & Dock, turn off "Displays have separate Spaces", log out and back in, open the overview. *Expected: the Spaces strip shows on the laptop's main display only; tiling still works on both.* Turn it back on afterwards.
   result: pending

7. With two displays, press ⌃⌥⌘A. *Expected: both displays show their own windows with their own Spaces strip; Tab moves the highlight to the other display; Return goes to the highlighted window.*
   result: pending

## 2. Mission Control takeover (host, macOS 27.2)

T1. Open the menu. *Expected: "Replace Mission Control" sits after "Frame Desktop" and before "Allow Window Previews…".* Choose it. *Expected: an alert with the app icon, "Replace Mission Control" as the default button and "Not Now"; Esc means Not Now.* Choose it again and confirm.
   result: pending

T2. Press F3, then F3 again; then ⌃↑ twice. *Expected: the overview opens and closes each time.* Quit Transom (menu ▸ Quit) and press F3. *Expected: macOS Mission Control opens, and no notice when you relaunch.* Relaunch Transom. *Expected: F3 opens the overview again.*
   result: pending

T3. With the takeover on, run `kill -9 $(pgrep -x "Transom Debug")` in Terminal, then press F3. *Expected: nothing happens.* Relaunch Transom and press F3. *Expected: macOS Mission Control opens at once; the notice "Transom quit unexpectedly, so Mission Control has its keys back. …" shows once; "Replace Mission Control" is unchecked.*
   result: pending

## 3. Backstops and checks left to UAT

B1. Visit Desktop 2, come back, press ⌃⌥⌘A. *Expected: Desktop 2's thumbnail shows real window previews, not app icons.* Click Desktop 2's thumbnail, then reopen and click a mini tile there. *Expected: both land on Desktop 2; the mini-tile window is focused. ⌃ doesn't feel stuck when you type afterwards. With two displays, the switch happens on the display you clicked.*
   result: pending

B2. With 30+ windows across both displays, press ⌃⌥⌘A. *Expected: it opens without a visible hitch, and Debug "Last overview" reads under 400 ms.*
   result: pending

B3. In the overview, use the arrows and move the pointer over tiles. *Expected: a thin accent ring on the selected tile, a title capsule under it, a pointing-hand cursor over tiles. Esc pressed right after opening closes it. Text typed at once after Esc may be lost for ~0.4 s, but nothing typed later is.*
   result: pending

B4. With the overview open, press ⌘-Tab; reopen and click the menu bar icon. *Expected: each closes the overview.*
   result: pending

B5. Turn on VoiceOver, open the overview, use the arrows and Tab. *Expected: each arrow reads the window; Tab reads the display name.* Turn VoiceOver off.
   result: pending

B6. Turn on Reduce Motion (System Settings ▸ Accessibility ▸ Display), open and close the overview. *Expected: it crossfades in and out with nothing moving.* Turn it off again.
   result: pending

B7. With Screen Recording not granted to "Transom Debug", open and close the overview once. *Expected: the Screen Recording explainer appears only after the overview has closed, not while it is open.*
   result: pending

## Known gaps

- macOS 14 not tested: evidence is the VM (macOS 15.7.7) and the host (macOS 27.2) (RESEARCH Open Question 4, resolved)
- N11 ("Couldn't take over Mission Control's keys…") is hard to cause on purpose; unit tests cover it.
- The VM Esc failure in `OverviewIntegrationTests` (two runs) has no known cause; B3 checks Esc on hardware.
