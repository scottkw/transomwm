---
status: complete
phase: 06-overview-spaces-displays
source: 06-UI-SPEC.md "User hardware checklist" (items 1-7, verbatim) and backstop rows; 06-RESEARCH.md takeover host item; 06-06..06-11-SUMMARY.md items left to UAT
started: 2026-10-31
updated: 2026-11-01 (host checks + two fixes, user and agent)
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[complete 2026-11-01: VM run plus host checks; items 1-7 deferred (no external display)]

## Build under test

- Code: HEAD `a4141f1` (06-12 Task 1; the later 06-12 commits change planning files only).
- App: `/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, built by `scripts/build-debug.sh` on 2026-10-31. Developer ID signed, team S2K7P43927, bundle `com.eightabyte.transom.debug`. `codesign --verify --strict` and the designated-requirement check passed. The agent built it and never launched it.
- **Rebuild first (verifier, 2026-10-31):** this app was built at 16:38, before the ten review fixes (`20111d8`..`cd02991`, 17:00-17:15). Run `scripts/build-debug.sh` again before this pass, so the build under test includes them.
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
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

2. Plug the DELL back in. *Expected: those windows go back to their tiles on the DELL. No notice.*
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

3. Repeat 1 and 2, but dock one of the floated windows on the laptop before re-plugging. *Expected: that window stays where you docked it; the others go home.*
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

4. Arrange windows differently with the DELL connected, unplug (laptop-only layout), arrange the laptop differently, then plug back in and unplug again. *Expected: each time, each setup comes back exactly as you left it.* Then (review fixes WR-08/WR-09): unplug the DELL and plug it back in within about a second, before anything moves; and quit Transom with the DELL connected, unplug it, relaunch on the laptop alone. *Expected: each time, the layout for the displays you end up with comes back; no window lands in a tile from the other setup.*
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

5. Close the lid or sleep the Mac with the DELL connected, unplug it while asleep, wake. *Expected: nothing moves until you're logged in again; then the item 1 behaviour.*
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

6. In System Settings ▸ Desktop & Dock, turn off "Displays have separate Spaces", log out and back in, open the overview. *Expected: the Spaces strip shows on the laptop's main display only; tiling still works on both.* Turn it back on afterwards.
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

7. With two displays, press ⌃⌥⌘A. *Expected: both displays show their own windows with their own Spaces strip; Tab moves the highlight to the other display; Return goes to the highlighted window.* Then (review finding WR-06): with two desktops on the laptop and one or more on the DELL, pick one of the DELL's other desktops in the DELL's strip, once by click and once by Return. *Expected: the DELL switches to that desktop, not the laptop. Also write down the label the strip shows for it (macOS may number it Desktop 3).*
   result: deferred (user has no external display available on 2026-10-31; re-run when one is)

## 2. Mission Control takeover (host, macOS 27.2)

T1. Open the menu. *Expected: "Replace Mission Control" sits after "Frame Desktop" and before "Allow Window Previews…".* Choose it. *Expected: an alert with the app icon, "Replace Mission Control" as the default button and "Not Now"; Esc means Not Now.* Choose it again and confirm.
   result: pass (VM, synthetic events) — menu order "Frame Desktop" → "Replace Mission Control" → "Allow Window Previews…" (seen with Screen Recording reset in B7; with the grant the next item is "Turn Off Zoom"). The alert has the app icon (AXImage "Transom Debug alert"), "Use the Mission Control keys for Transom's overview?", AXDefaultButton "Replace Mission Control", AXCancelButton "Not Now" (`.build/0612-uat-vm-shots/t1-alert.png`). Esc closed it and the takeover stayed off (32/108/113 enabled, Debug "Mission Control takeover: off"). Chosen again and confirmed: log "takeover on: disabled 32, 108, 113", item checked, Debug "on, F3 and ⌃↑". **Check on the host:** after the menu was pressed through AX, `NSApp.activate()` left Finder frontmost, so the first Esc went to Finder and only an Esc after clicking the alert closed it. A real click on the menu bar icon may activate Transom normally; confirm that Esc closes the alert with no click first · **Host 2026-11-01:** pass (macOS 27.2): Esc closed the alert without clicking it first; the item stayed unchecked.

T2. Press F3, then F3 again; then ⌃↑ twice. *Expected: the overview opens and closes each time.* Quit Transom (menu ▸ Quit) and press F3. *Expected: macOS Mission Control opens, and no notice when you relaunch.* Relaunch Transom. *Expected: F3 opens the overview again.*
   result: pass (VM, synthetic events) — F3 → "open missionControlKey … 593 ms", F3 → "dismiss: toggle"; ⌃↑ → open (464 ms), ⌃↑ → dismiss; the Dock's on-screen window count stayed at 2 (no Mission Control). Menu ▸ Quit: "takeover off: restored originals", 32/108/113 read back enabled, and posted F3 opened Mission Control (Dock windows 2 → 4, `.build/0612-uat-vm-shots/t2-mc-after-quit.png`). Relaunch: "takeover on: disabled 32, 108, 113"; no notice panel in the first 8 s and no announcement; F3 opened the overview (474 ms) · **Host 2026-11-01:** pass (macOS 27.2): with the takeover on, F3 opened and closed the overview; turned off, F3 opened macOS Mission Control.

T3. With the takeover on, run `kill -9 $(pgrep -x "Transom Debug")` in Terminal, then press F3. *Expected: nothing happens.* Relaunch Transom and press F3. *Expected: macOS Mission Control opens at once; the notice "Transom quit unexpectedly, so Mission Control has its keys back. …" shows once; "Replace Mission Control" is unchecked.*
   result: pass (VM, synthetic events) — after `kill -9`, 32/108/113 stayed disabled and posted F3 did nothing (Dock windows stayed 2, `.build/0612-uat-vm-shots/t3-f3-after-kill.png`). Relaunch: "restored originals from last run (unclean exit)", hotkeys read back enabled, and F3 at once opened Mission Control (Dock windows 2 → 4). A notice panel (303,41 419×35) appeared and announced "Transom quit unexpectedly, so Mission Control has its keys back. Choose Replace Mission Control in the Transom menu to use them for the overview again." The item was unchecked, and Debug read "Mission Control takeover: off after a crash last launch". After a clean quit and relaunch there was no notice and no announcement, so it shows once. Side effect: the kill also tripped the G-01 multitouch canary ("Multitouch: off after a crash last launch"); Debug ▸ Turn Multitouch Back On restored it

## 3. Backstops and checks left to UAT

B1. First, with windows already on Desktop 2, relaunch Transom on Desktop 1 and press ⌃⌥⌘A without visiting Desktop 2. *Expected: Desktop 2's thumbnail shows its windows (app-icon tiles are fine). Write down if it shows only wallpaper.* Then visit Desktop 2, come back, press ⌃⌥⌘A. *Expected: Desktop 2's thumbnail shows real window previews, not app icons.* Click Desktop 2's thumbnail, then reopen and click a mini tile there. *Expected: both land on Desktop 2; the mini-tile window is focused. ⌃ doesn't feel stuck when you type afterwards. With two displays, the switch happens on the display you clicked.* Then (review fix WR-07): in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Mission Control, turn off "Move left a space" and "Move right a space", then click another desktop's thumbnail. *Expected: a beep and "Couldn't switch to Desktop {n}"; nothing is typed into the front app. Say whether this is the behaviour you want.* Turn both back on.
   result: partial (VM, synthetic events, one display) — **Cold:** with 2 docked fixture windows on Desktop 2 and Transom relaunched on Desktop 1, Desktop 2's thumbnail showed both windows as app-icon tiles, not wallpaper (`.build/0612-uat-vm-shots/b1-overview-cold.png`). **Visit: possible gap.** The first visit (~3 s, about 20 s after the relaunch) logged "space 3 captured 0 windows after visit", and the thumbnail still showed app icons (`b1-overview-warm.png`). A second visit (~9 s) logged "space 3 captured 2 windows after visit" and then showed real previews (`b1-overview-warm2.png`). Probable cause, not confirmed: right after a relaunch, the capture 1 s after arrival ran before that Space's windows were tracked. **Thumbnail click:** "pick space 3" → "switch to space 3 via keys 124"; the Space changed 1.23 s after the pick; no modifier keys held in the HID state. **Mini tile:** "pick window 1813 on space 3 (switch space)"; landed on Desktop 2 and the fixture answered "frontmost index=1". **WR-07:** with the Move left/right shortcuts off, a click on Desktop 2's thumbnail logged "switch to space 3 failed: the Move left/right a space shortcut is off" and announced "Couldn't switch to Desktop 2". The Space stayed 1, and the frontmost fixture stayed frontmost with `typed` empty. Expected beep: the code path is `.beep` + `.announce`, but the VM can't play audio. Note on IDs: "Move right a space" is hotkey **81**; 79 is left, and 80/82 are their variants. With only 79/80 off, the rightward switch still worked (correct, because 81 was on), so the run turned off 79-82, which matches both System Settings toggles. All four read back enabled afterwards. **Left for the user:** whether ⌃ feels stuck when typing on the real keyboard, the two-display "switch happens on the display you clicked", and whether the WR-07 beep-plus-message is the behaviour you want · **Host 2026-11-01:** ⌃ feel pass: typing in TextEdit right after an overview Space switch was plain text. First-visit capture gap fixed by d297b03 (a Space change now refreshes every app after 75 ms; debug session overview-first-visit-capture, VM test red 4/4 → green 3/3). Two-display switch and WR-07 preference deferred with items 1-7 (WR-07 refusal kept as built).

B2. With 30+ windows across both displays, press ⌃⌥⌘A. *Expected: it opens without a visible hitch, and Debug "Last overview" reads under 400 ms.*
   result: fail (VM, synthetic events, one display) — with 41 windows (30 fixture + 11) docked, three opens took 442, 451 and 423 ms (Debug "Last overview: 423 ms to open, 41 windows, 11 snapshots"; `.build/0612-uat-vm-shots/b2-overview-43.png`). The VM time does not grow with the window count: 10-11 windows took 399-593 ms, and without Screen Recording (B7) 11 windows took 314 ms. It includes the 250 ms open animation, so the overshoot is most likely the VM's rendering. A hitch can't be judged from screenshots. **Re-check on hardware** before treating this as a real failure · **Host 2026-11-01:** pass on hardware: Debug "Last overview" 326 ms (MacBook Air, macOS 27.2). The VM overshoot was VM rendering.

B3. In the overview, use the arrows and move the pointer over tiles. *Expected: a thin accent ring on the selected tile, a title capsule under it, a pointing-hand cursor over tiles. Esc pressed right after opening closes it. Text typed at once after Esc may be lost for ~0.4 s, but nothing typed later is.*
   result: pass (VM, synthetic events) — the screenshots show a thin blue accent ring on the selected tile and a title capsule at its bottom edge ("Notes", then "Fixture 0"), moving with → (`.build/0612-uat-vm-shots/b3-arrow1.png`, `b3-arrow2.png`). `NSCursor.currentSystem` was the pointing hand over a tile and the arrow over empty stage. Esc posted 80 ms after ⌃⌥⌘A closed the overview 5 times out of 5 ("dismiss: esc"; the open never completed). "hi" typed 0.6 s after Esc arrived complete in the front fixture. Seen in passing: the fixture tile showed a stretched, stale snapshot taken while the window was narrow during B2

B4. With the overview open, press ⌘-Tab; reopen and click the menu bar icon. *Expected: each closes the overview.*
   result: pass (VM, synthetic events) — ⌘-Tab with the overview open logged "interrupted: app switch" and Finder came forward. Reopened, a HID click on the menu bar icon logged "interrupted: menu" and the menu opened (`.build/0612-uat-vm-shots/b4-after-statusclick.png`)

B5. Turn on VoiceOver, open the overview, use the arrows and Tab. *Expected: each arrow reads the window; Tab reads the display name.* Turn VoiceOver off.
   result: partial (VM, synthetic events) — **VoiceOver speech not heard in the VM.** An AXObserver for AXAnnouncementRequested saw, at priority 90: "Overview, 11 windows" on open; ←, ↓, ↑ read "“TextEdit”, Untitled 4", "“TextEdit”, Untitled 2", "“TransomFixtureApp”, Fixture 0"; the strip selection read "Desktop 2, 2 windows"; Esc read "Overview closed". Tab announced nothing: with one display there is no other display to move to, so "Tab reads the display name" was not checked · **Host 2026-11-01:** VoiceOver takes ⌃⌥⌘A (its VO keys are ⌃⌥), so the overview must be opened from the menu or a rebound shortcut while VoiceOver is on (README note). The same session found the overview invisible until relaunch; cause was a macOS 27 screen lock stranding the reused panel on another Space, not VoiceOver. Fixed by 98f7d3d (debug session overview-stuck-after-voiceover); host lock re-check pass. Spoken arrows not re-heard on the host.

B6. Turn on Reduce Motion (System Settings ▸ Accessibility ▸ Display), open and close the overview. *Expected: it crossfades in and out with nothing moving.* Turn it off again.
   result: pass (VM, synthetic events, judged roughly) — Reduce Motion turned on with `defaults write com.apple.universalaccess reduceMotion` (`NSWorkspace.accessibilityDisplayShouldReduceMotion` read true). A 6-frame screenshot series during open and during close (`.build/0612-uat-vm-shots/b6-rm-open-*.png`, `b6-rm-close-*.png`, contact sheets `b6-rm-o-sheet.png` / `b6-rm-c-sheet.png`): mid-animation frames show the tiles already at their overview positions, half-transparent over the desktop, and no frame shows a tile between its window position and its overview position, so it crossfades with nothing moving. Turned off afterwards

B7. With Screen Recording not granted to "Transom Debug", open and close the overview once. *Expected: the Screen Recording explainer appears only after the overview has closed, not while it is open.*
   result: pass (VM, synthetic events) — after `tccutil reset ScreenCapture com.eightabyte.transom.debug` (guest only) and deleting `zoomPreviewExplainerShown`, Transom relaunched with "screen recording: not granted, using app-icon tiles". The overview opened (314 ms, 11 fallback tiles), and for 3 s Transom had no window besides its overlays (`.build/0612-uat-vm-shots/b7-open.png`). Esc at 23:22:43.214 logged "dismiss: esc", and "explainer shown" followed at 43.594, 380 ms later, after the stage had gone: "Show window previews while zooming?" with Allow Previews / Not Now (`b7-after-close.png`). Answered Not Now. **The guest's Screen Recording grant for Transom Debug is now reset.** It can't be re-granted without the GUI, so grant it again in System Settings ▸ Privacy & Security ▸ Screen Recording before the next VM run that needs previews

B8. (Review fix WR-10, the running-app half) Dock a Safari window that has three tabs, then close the whole window (⌘⇧W). *Expected: its tile closes and its neighbour fills within a few seconds, even if Safari keeps the closed window around in the background.*
   result: pass (VM, synthetic events) — a Safari window with three tabs (⌘T twice, `.build/0612-uat-vm-shots/b8-docked.png`) was docked with ⌃⌥⌘D above the Notes group (Safari 8,33 642×333, Notes 8,374). ⌘⇧W closed the window. By the first poll, 500 ms later, Safari's tile was gone and the Notes group was back at 8,33 642×334, its frame from before Safari was docked. It stayed there for 5 s while Safari kept running in the background (`b8-after.png`)

## VM UAT run (2026-10-31, agent)

Items T1-T3 and B1-B8 ran in the Tart `pane-test` guest (macOS 15.7.7, one 1024×768 display, two desktops) against the build under test (sha1 `f518458d…`, rebuilt with the review fixes), installed as `/Applications/Transom Debug.app`. The previous install is kept in `~/uat0612/` in the guest. The Accessibility and Screen Recording grants carried over ("permission probing -> ready", Debug "Zoom: on, window previews"). Transom was launched with `open --env TRANSOM_STAGE_CAPTURABLE=1` so screenshots include the stage panel.

Method, the same as Phase 5:
- **Windows:** TransomFixtureApp windows, docked with ⌃⌥⌘D or Arrange All.
- **Input:** synthetic CGEvents at the HID tap. Mission Control and Space chords carried the fn flag on key-down (F3 = key code 160 with 0x800000, ⌃↑ 0x840000, ⌃←/→ 0x840000) and no flags on key-up.
- **Mission Control opened:** detected when the Dock's on-screen window count went from 2 to 4.
- **Debug lines and menu state:** read through AX by pressing the status item while a posted ⌥ key-down was held.
- **Announcements:** an AXObserver for AXAnnouncementRequested on the app.
- **Symbolic hotkeys:** read with a read-only SkyLight probe (`~/uat0612/hkread2`, IDs 32/108/113/79-82). They were changed only for WR-07, with a guest-only `hkset`.
- **Logs:** the guest log is `.build/0612-uat-vm-transom.log`; screenshots and announcement captures are in `.build/0612-uat-vm-shots/`.

Caveats:
- The guest runs macOS 15.7.7 and the host 27.2. Hotkey IDs, chords and Dock behaviour were checked on 15 only.
- With one display, nothing in Tab-between-displays, per-display strips or the B1 switch on the clicked display could be checked, and hardware items 1-7 are deferred.
- Not checkable in the VM: audio (the WR-07 beep, VoiceOver speech), the feel of the real keyboard after a posted switch (the "⌃ doesn't feel stuck" part of B1 is left for the user), and smoothness at frame rate.
- Overview open times in the VM run 400-600 ms whatever the window count (B2).
- **Harness artifacts, not Transom:**
  - The driver's own ⌃⌥⌘A key-up carried the chord flags and left ⌘⌥⌃ marked down in the HID state. A flagless key-up cleared it, and later runs used flagless key-ups.
  - A posted Esc didn't close a status menu opened by a HID click (B4).
  - The task brief named hotkeys 79/80, but "Move right a space" is 81 (see B1).

Guest state afterwards:
- Symbolic hotkeys 32, 108, 113 and 79-82 read back enabled.
- Replace Mission Control is off. Debug still reads "off after a crash last launch" until it is next chosen, the designed canary behaviour from T3.
- Multitouch was turned back on.
- Reduce Motion is off. It was **on** when the run started, and the run left it off as instructed.
- The guest is on Desktop 1.
- Transom Debug quit, Safari quit, fixtures closed, and `layout.json` restored from the pre-run backup.
- TextEdit, Notes and Finder were untouched.
- Still to do by hand: the Screen Recording grant for `com.eightabyte.transom.debug` is reset (B7).

### VM results

| Item | Result |
|---|---|
| T1 | pass. Check on the host that Esc closes the alert without clicking it first |
| T2 | pass |
| T3 | pass: N10 shown once, item unchecked |
| B1 | partial: first visit after a relaunch captured 0 windows (gap); ⌃ feel, two displays and WR-07 preference left for the user |
| B2 | fail (VM): 423-451 ms at 41 windows, not growing with the window count; re-check on hardware |
| B3 | pass |
| B4 | pass |
| B5 | partial: announcements right, speech not heard, Tab not checkable with one display |
| B6 | pass (rough) |
| B7 | pass; guest grant now reset |
| B8 | pass |

## Known gaps

- macOS 14 not tested: evidence is the VM (macOS 15.7.7) and the host (macOS 27.2) (RESEARCH Open Question 4, resolved)
- N11 ("Couldn't take over Mission Control's keys…") is hard to cause on purpose; unit tests cover it.
- WR-05 (open, needs design): after a reboot that renumbers Spaces, a desk whose Space is gone can be taken over by a Space created later in the same session. No data is lost; it needs its own task.
- The VM Esc failure in `OverviewIntegrationTests` (two runs) has no known cause; Esc worked on hardware in every host check.
- Hardware items 1-7, WR-06 and Tab between displays: deferred until an external display is available (re-run this file's section 1 then).
- VoiceOver users: ⌃⌥⌘A collides with VoiceOver's ⌃⌥ keys; use the menu item or rebind Show Overview.
- Other reused panels (zoom stage, drag preview, gap handles, collapsed panels, toast) had the same lock stranding exposure; follow-up fix in progress at close.
