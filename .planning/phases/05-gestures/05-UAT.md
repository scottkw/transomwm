---
status: testing
phase: 05-gestures
source: 05-UI-SPEC.md Surface 7 (Phase UAT checklist, C5-edited); 05-SPIKE.md Verdict and conditions; 05-02/04/05/06/07-SUMMARY.md items left to UAT
started: 2026-10-30
updated: 2026-10-30
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[awaiting the user: run items 1-24 on the host with the built-in trackpad, one at a time]

## Build under test

- Code: HEAD `8b64792` (05-07 complete; 05-08 changes only planning files).
- App: `/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, built by `scripts/build-debug.sh` on 2026-10-30. Developer ID signed, team S2K7P43927, bundle `com.eightabyte.transom.debug`. `codesign --verify --strict` and the designated-requirement check passed. The agent built it and never launched it.
- Multitouch: **shipped** (E-01 "tap+multitouch", plan 05-07). The tap does all the consuming. Multitouch supplies pinch only while Trackpad ▸ "Zoom in or out" is off.
- Host: MacBook Air, built-in trackpad only (05-SPIKE C5). Magic Trackpad items are N/A. Spaces checks use a four-finger swipe or ⌃← / ⌃→.

## Automated results (2026-10-30)

| Run | Result |
|---|---|
| `scripts/check-no-appkit.sh` | OK (45 files) |
| `git grep -l 'import ScreenCaptureKit' -- Sources` | only `Sources/TransomMac/Zoom/SnapshotCapture.swift` |
| Host `swift test` (full, `.build/0508-full.log`) | 193 + 305 + 75 + 690 = 1,263 tests passed, 0 failed (the FreezeTestTests flake did not occur) |
| VM `GestureTapIntegrationTests` | 12 tests passed (20.3 s) |
| VM `GestureFollowIntegrationTests` | 13 tests passed (57.1 s) |
| VM `InputTapIntegrationTests` | 3 tests passed (1.1 s) |
| VM `ZoomSettleIntegrationTests` | 2 tests passed (19.4 s) |
| VM `MultitouchIntegrationTests` (05-07, no device in the guest) | 1 test passed |

VM: Tart `pane-test`, macOS 15.7.7. The guest display was woken and `caffeinate -dimsu` held by `scripts/vm-live-test.sh`. One suite ran per invocation, using fixtures only. Logs are in `.build/0508-vm-*.log`. The VM was stopped afterwards.

## Before you start

1. Quit every other Transom build: open its menu bar icon ▸ Quit. Then check in Terminal that nothing is left:
   ```
   pgrep -fl "Transom"
   ```
   *Expected: no output.*
2. Launch the Debug app:
   ```
   open "/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app"
   ```
   If macOS asks, give "Transom Debug" Accessibility (System Settings ▸ Privacy & Security ▸ Accessibility). Screen Recording is optional: without it the zoom shows app-icon tiles instead of window pictures.
3. Open the menu bar icon ▸ Turn On Zoom (skip this if it already says Turn Off Zoom).
4. Dock at least 4 windows, including a Safari page and a PDF in Preview. Keep "Zoom in or out" on (System Settings ▸ Trackpad ▸ Scroll & Zoom) until item 17.
5. **The Debug submenu only appears if you hold ⌥ while you click the menu bar icon.** Do that now, before any gesture, and open Debug. *Expected: "Gestures taken: none yet" and "Last gesture: none yet".* (This is the first part of item 22.)
6. Optional but useful for items 17, 18 and any failure: leave this running in a Terminal window. It shows every gesture Transom takes and the multitouch lines:
   ```
   log stream --level info --style compact --predicate 'subsystem == "com.eightabyte.transom" AND category == "gesture"'
   ```
7. For each item, reply "pass" or say what you saw instead. Items marked (both) run on the built-in trackpad. VoiceOver (item 12) is ⌘F5, or fn-⌘-F5 if F5 is a media key on your keyboard.

## Phase UAT checklist (Transom running, zoom on)

Items 1-16 are UI-SPEC Surface 7, pasted unchanged. It was edited on 2026-10-30 for 05-SPIKE C5: no Magic Trackpad, item 15 is N/A, and item 8 is N/A without a mouse.

Set up first: at least 4 windows docked, with a Safari page and a PDF in Preview among them. Items marked **(both)** run on the built-in trackpad, the only one on this Mac.

1. **(both)** Hold ⌥ over Safari and pinch your fingers apart slowly. *Expected: the screen follows your fingers toward the tile under them. Let go past halfway: it finishes zooming in and the real windows are in place. Safari's page did not zoom.*
   result: pending

2. **(both)** Hold ⌥ and pinch your fingers together. *Expected: it zooms back out one level. Let go before halfway: it springs back and nothing changes.*
   result: pending

3. **(both)** Zoomed in, hold ⌥ and two-finger scroll left across about half the screen. *Expected: the view slides with your fingers and settles on the area to the right. A short scroll springs back. Safari didn't scroll, even after your fingers left the trackpad.*
   result: pending

4. At the view showing all windows, hold ⌥ and scroll in any direction. *Expected: the screen stretches a little, resists, and springs back. No beep.*
   result: pending

5. Hold ⌥ and make one long pinch, fingers fully apart. *Expected: it goes in exactly one level, resisting past that. Pinch again to go one more level.*
   result: pending

6. Without ⌥, pinch and scroll over bare wallpaper. *Expected: zoom and pan work. Without ⌥ over a window: the app zooms and scrolls as usual, and Transom does nothing.*
   result: pending

7. Hold ⌃ and scroll, and hold ⌘ and pinch, over Safari. *Expected: Transom does nothing; Safari or macOS behaves as it does without Transom.* If you use the Accessibility "scroll gesture with modifier keys to zoom", check it still works.
   result: pending

8. Scroll with a mouse wheel or Magic Mouse while holding ⌥. *Expected: the app scrolls; Transom does nothing.* N/A if you have no USB or Bluetooth mouse.
   result: pending

9. Press ⌃⌥⌘-Comma (Zoom Out One Level) to zoom out and, while it is still moving, ⌥-pinch apart. *Expected: the motion carries on from where it was, without a jump.*
   result: pending

10. Mid-scroll with ⌥, rest your fingers still for a second, then keep scrolling and lift. *Expected: no scroll reaches Safari at any point.*
   result: pending

11. Turn on System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. Repeat items 1 and 2. *Expected: the screen still follows your fingers, but the finish is a fade, not a zoom.* Turn it off again.
   result: pending

12. Turn on VoiceOver (⌘F5). Repeat item 1, then pinch apart fully on a single window. *Expected: you hear "Showing …" after the first, and "Nothing to zoom in to" after the second.* Turn VoiceOver off.
   result: pending

13. Status menu ▸ Turn Off Zoom. ⌥-pinch and ⌥-scroll over Safari. *Expected: Safari zooms and scrolls as if Transom weren't running.* Turn zoom back on.
   result: pending

14. Sleep the Mac, wake it, then ⌥-pinch. *Expected: it works first time.*
   result: pending

15. **N/A** (05-SPIKE C5): reconnecting an external trackpad can't be tested on a Mac with only the built-in trackpad.
   result: n/a (05-SPIKE C5, no Magic Trackpad)

16. Open the status menu ▸ Debug. *Expected: "Gestures: on, …", a "Gestures taken" count, and "Last gesture" matching your last gesture.*
   result: pending

## Added checks (05-07 multitouch and items earlier plans left to UAT)

17. **Multitouch pinch with "Zoom in or out" off (05-07).** Turn off System Settings ▸ Trackpad ▸ Scroll & Zoom ▸ "Zoom in or out". In Terminal, run `defaults read com.apple.AppleMultitouchTrackpad TrackpadPinch`. *Expected: `0`* (see Risks: this value is the one thing 05-07 couldn't confirm). Then:
    a. Hold ⌥ over Safari and pinch your fingers apart past halfway, then let go. *Expected: the desk follows your fingers and zooms in one level; Safari's page doesn't zoom.*
    b. Hold ⌥ and pinch together. *Expected: it zooms back out one level.*
    c. Without ⌥, pinch apart over bare wallpaper. *Expected: Transom takes it and the desk zooms.*
    d. Hold ⌥ and two-finger scroll left and right while zoomed in. *Expected: the view still pans. It doesn't start a zoom.*
    e. Hold ⌥, click the menu bar icon ▸ Debug. *Expected: "Gestures: on, trackpad events and multitouch" and "Multitouch: available, 1 trackpad".* If the log stream is running, the pinches show as "took pinch #m…: multitouch, ⌥ held, …".
    Leave "Zoom in or out" **off** for item 18.
    result: pending

18. **Sleep/wake with "Zoom in or out" off (05-07).** Keep the log stream from step 6 running. Don't relaunch Transom. Choose Apple menu ▸ Sleep, wake the Mac, then hold ⌥ over Safari and pinch apart. *Expected: it works first time, and the log shows "multitouch: rescan after wake".* Then turn System Settings ▸ Trackpad ▸ Scroll & Zoom ▸ "Zoom in or out" back **on**.
    result: pending

19. **Multitouch disabled at launch (tap-only fallback, 05-07).** Quit Transom Debug (menu bar icon ▸ Quit). Then run:
    ```
    open "/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app" --args --disable-private=Multitouch
    ```
    Turn zoom on if it's off. Hold ⌥, click the menu bar icon ▸ Debug. *Expected: "Gestures: on, trackpad events" and "Multitouch: off, trackpad events only".* With "Zoom in or out" on, hold ⌥ over Safari and pinch apart. *Expected: it still zooms the desk (trackpad events alone).* Then quit and relaunch normally with the `open` command from step 2. *Expected: Debug shows "Multitouch: available, 1 trackpad" again.*
    result: pending

20. **Reduce Motion takeover mid-crossfade (05-05).** Turn on System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. Press ⌃⌥⌘-Comma (Zoom Out One Level). While the fade is still running (about a quarter of a second), hold ⌥ and pinch apart. *Expected: the screen follows your fingers from where it was, with no jump in position. Half-faded tiles may turn fully opaque at once. That pop is known, so say if it bothers you.* Turn Reduce motion off again.
    result: pending

21. **Pinch over the Desktop tile's wallpaper (05-04).** If the menu bar icon shows "Show Desktop Tile", choose it so the Desktop tile is on the desk, and keep part of it free of floating windows. At the view showing all windows, **without ⌥**, put your fingers over the empty part of the Desktop tile and pinch apart past halfway. *Expected: the desk zooms in toward the Desktop tile.* Without ⌥, two-finger scroll there while zoomed in. *Expected: the view pans.* Without ⌥, pinch over a floating window inside the Desktop tile. *Expected: the app gets it and Transom does nothing.*
    result: pending

22. **Debug lines G1-G4 (05-06, 05-07).** Hold ⌥ while clicking the menu bar icon to reach Debug. Check each line:
    a. Before any gesture (step 5 of Before you start): "Gestures taken: none yet" and "Last gesture: none yet".
    b. After an ⌥-pinch apart that zoomed in: "Gestures: on, trackpad events and multitouch", "Gestures taken: {n}" (it goes up by one per gesture Transom took), "Last gesture: pinch in, moved", and "Multitouch: available, 1 trackpad".
    c. After a short ⌥-pinch you let go before halfway: "Last gesture: pinch in, sprang back" (or "pinch out, sprang back").
    d. At the view showing all windows, ⌥-pinch together fully and let go: "Last gesture: pinch out, already showing all windows".
    e. A tiny ⌥ two-finger touch that barely moves: "Last gesture: pan, too small" or "pinch, too small".
    f. Menu bar icon ▸ Turn Off Zoom, then Debug: "Gestures: off (zoom off)", and the Multitouch line still reads "available, 1 trackpad". Turn zoom back on.
    result: pending

23. **Pinch-out and flick feel (05-02).** Zoomed in one level, hold ⌥ and pinch together slowly, noting how far your fingers travel before letting go would commit. Compare it with item 1's pinch apart. *Known: pinch-out reaches the halfway point with about half the finger travel that pinch-in needs.* Then, zoomed in, hold ⌥ and make a **short, quick** two-finger scroll (well under a third of the screen) and lift. *Known: most real pans are fast enough to commit as a flick, so it will probably move one area.* A short, **slow** scroll should spring back. Tell us if pinch-out feels too twitchy or quick short pans commit too easily. The constants are in `GestureTuning`.
    result: pending

24. **Spaces with four fingers or ⌃← / ⌃→ (05-SPIKE C5).** You need at least two Spaces (Mission Control ▸ + adds one). With zoom on, swipe left and right between Spaces with **four** fingers 5 times, then use ⌃← / ⌃→ 5 times. Swipe up with four fingers (or press ⌃↑) for Mission Control. *Expected: every switch and Mission Control works; Transom takes none of them.* Back on the Space with your docked windows, hold ⌥ and pinch apart. *Expected: it works first time.*
    result: pending

## Risks to watch

- **TrackpadPinch with the setting off is unconfirmed on hardware (05-07).** Transom reads `com.apple.AppleMultitouchTrackpad` `TrackpadPinch` and treats a missing key as on. It read `true` with "Zoom in or out" on. If the value doesn't read false once the setting is off (item 17's `defaults read`), multitouch never takes a pinch. Pinch is then lost while the setting is off, the same as tap-only. Item 17a would fail with nothing happening.
- With the setting off and ⌥ held, a pan whose finger spacing changes by 3% or more in its first ~63 ms could start a multitouch pinch (item 17d).
- Under Reduce Motion, taking over mid-crossfade can make the tiles pop to full opacity (item 20).
- Feel: pinch-out commits with less travel than pinch-in, and short pans mostly commit by flick (item 23).

## Summary

total: 24
passed: 0
issues: 0
pending: 23
skipped: 0
n/a: 1 (item 15); item 8 is N/A if there's no mouse

## Gaps

[none yet]
