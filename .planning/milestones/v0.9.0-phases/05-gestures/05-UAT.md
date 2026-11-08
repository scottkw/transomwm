---
status: complete
phase: 05-gestures
source: 05-UI-SPEC.md Surface 7 (Phase UAT checklist, C5-edited); 05-SPIKE.md Verdict and conditions; 05-02/04/05/06/07-SUMMARY.md items left to UAT
started: 2026-10-30
updated: 2026-10-30
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete. The user ran items 1, 2, 3, 6, 17, 18 and 23 on the host (all pass), re-checked G-01 on the host (no crash), and stopped there ("Done. I think we're good."). Items 7, 8, 10, 11, 14, 20, 21 and 24 are skipped by user decision; item 15 is N/A]

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

## VM UAT run (2026-10-30, agent)

Items 4, 5, 9, 12, 13, 16, 19 and 22 ran in the Tart `pane-test` guest (macOS 15.7.7, 1024×768) against the build under test, installed as `/Applications/Transom Debug.app`. The Accessibility and Screen Recording grants carried over from the older Debug build ("permission probing -> ready", Debug "Zoom: on, window previews"). Four TransomFixtureApp windows were docked with ⌃⌥⌘D. Gestures were synthetic CGEvents: type 29 with field 110 = 8, phases in field 132 and magnification in field 113, plus phased pixel scrolls, all posted at the HID tap with ⌥ in the event flags. Debug lines were read through AX: the status item was pressed while a posted ⌥ key-down was held. VoiceOver announcements came from an AXObserver for AXAnnouncementRequested on the app. Screenshots used `TRANSOM_STAGE_CAPTURABLE=1` so that the stage panel shows up. The guest has no trackpad, so the sender filter wasn't exercised and multitouch reads "available, no trackpad found". The guest log is at `.build/0508-uat-vm-transom.log`.

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
   result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — ⌥-pinch in over Safari followed the fingers and settled; Safari's page did not zoom.

2. **(both)** Hold ⌥ and pinch your fingers together. *Expected: it zooms back out one level. Let go before halfway: it springs back and nothing changes.*
   result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — ⌥-pinch out zoomed out one level (user screenshots: a group of Terminal, text and Safari went to all 4 windows with Preview back in view); a short pinch sprang back.

3. **(both)** Zoomed in, hold ⌥ and two-finger scroll left across about half the screen. *Expected: the view slides with your fingers and settles on the area to the right. A short scroll springs back. Safari didn't scroll, even after your fingers left the trackpad.*
   result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — ⌥-pan moved to the neighbouring area, a short pan sprang back, and no scroll leaked into Safari.

4. At the view showing all windows, hold ⌥ and scroll in any direction. *Expected: the screen stretches a little, resists, and springs back. No beep.*
   result: pass (VM, synthetic events — ⌥-pans at home left/right/up/down were all taken (0 of 10 events reached a tail tap), logged "took pan #n: ⌥ held … no area right/left/bottom/top", and a mid-gesture screenshot showed the stage rubber-banded ~58 pt for 120 pt of travel, then back at home; no beep call on the gesture path, but the VM can't hear one; small pans (40 pt) posted no announcement, decisive ones posted "No area to the …")

5. Hold ⌥ and make one long pinch, fingers fully apart. *Expected: it goes in exactly one level, resisting past that. Pinch again to go one more level.*
   result: pass (VM, synthetic events — one 3.0-magnification ⌥-pinch went home → node(n29) only ("took pinch #2 … moved to node(n29)"), the mid-gesture screenshot showed the stage stretched past that level; a second identical pinch went n29 → node(n28), one more level)

6. Without ⌥, pinch and scroll over bare wallpaper. *Expected: zoom and pan work. Without ⌥ over a window: the app zooms and scrolls as usual, and Transom does nothing.*
   result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — without ⌥, pinch and pan over bare wallpaper worked. Without ⌥ over Safari, Transom took nothing (Debug "Gestures taken" stayed at 60). On the first try Safari did not visibly zoom; a retry with Safari's zoom on did zoom. Recorded as a pass, not a gap: Transom took nothing either time, so the first try was Safari, not a leak.

7. Hold ⌃ and scroll, and hold ⌘ and pinch, over Safari. *Expected: Transom does nothing; Safari or macOS behaves as it does without Transom.* If you use the Accessibility "scroll gesture with modifier keys to zoom", check it still works.
   result: skipped (user, not checked on hardware) — the user stopped after the core items ("Done. I think we're good."). E-05's ⌃-scroll Accessibility zoom was **not** confirmed on hardware. Partial cover: VM `GestureTapIntegrationTests.controlOrCommandChordsPass` and the headless `GestureTapRulesTests.controlOrCommandWithOptionPassesButShiftConsumes`.

8. Scroll with a mouse wheel or Magic Mouse while holding ⌥. *Expected: the app scrolls; Transom does nothing.* N/A if you have no USB or Bluetooth mouse.
   result: skipped (user, not checked on hardware) — not run; the user did not say whether a USB or Bluetooth mouse is present, so it is not marked N/A. Partial cover: VM `GestureTapIntegrationTests.aDiscreteWheelWithOptionPasses` (discrete ⌥-wheel passes); the trackpad sender filter itself was never exercised (no mouse on the host run, no trackpad in the VM).

9. Press ⌃⌥⌘-Comma (Zoom Out One Level) to zoom out and, while it is still moving, ⌥-pinch apart. *Expected: the motion carries on from where it was, without a jump.*
   result: pass (VM, synthetic events — ⌃⌥⌘-Comma from n28 logged "move … node(n28) → node(n29)", then the ⌥-pinch 100 ms later logged "retarget gesture pinch during moving" and "took pinch … moved to node(n28)" with one settle; a 6-screenshot series showed the follow continuing from the step-out position; smoothness at frame rate can't be judged from screenshots, worth a glance on the host)

10. Mid-scroll with ⌥, rest your fingers still for a second, then keep scrolling and lift. *Expected: no scroll reaches Safari at any point.*
   result: skipped (user, not checked on hardware) — partial cover: headless `GestureTapRulesTests.quietAfterFingersUpEndsTheLatchButFingersDownQuietKeepsIt` and `aStuckLatchIsReleasedByTimeoutOrANewStart`, plus VM `momentumTailNeverLeaks`; item 3 on the host saw no Safari scroll leak.

11. Turn on System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. Repeat items 1 and 2. *Expected: the screen still follows your fingers, but the finish is a fade, not a zoom.* Turn it off again.
   result: skipped (user, not checked on hardware) — not in the user's results and not run (the user ended UAT before it). Partial cover: headless `StageFollowTests.reduceMotionCrossfadesTheSnapAndFadesTheSpringBack`.

12. Turn on VoiceOver (⌘F5). Repeat item 1, then pinch apart fully on a single window. *Expected: you hear "Showing …" after the first, and "Nothing to zoom in to" after the second.* Turn VoiceOver off.
   result: pass (VM, synthetic events — VoiceOver speech not heard in the VM; an AXObserver on the app saw AXAnnouncementRequested "Nothing to zoom in to" after a full ⌥-pinch apart on leaf n28, and "Showing 11 windows" / "Showing all windows" after committed pinches, priority 90 (high))

13. Status menu ▸ Turn Off Zoom. ⌥-pinch and ⌥-scroll over Safari. *Expected: Safari zooms and scrolls as if Transom weren't running.* Turn zoom back on.
   result: pass (VM, synthetic events — after status menu ▸ Turn Off Zoom the log said "gesture tap stopped: zoom off"; an ⌥-pinch, an ⌥-scroll with momentum and a pinch over the Desktop tile all reached a tail tap whole (12/12, 15/15, 12/12) and Transom logged no took line; Turn On Zoom restarted the tap)

14. Sleep the Mac, wake it, then ⌥-pinch. *Expected: it works first time.*
   result: skipped (user, not checked on hardware) — partial cover: item 18 on the host (sleep/wake with "Zoom in or out" off, ⌥-pinch worked first time, no relaunch) and VM `GestureTapIntegrationTests.wakeRepublishesState`. Sleep/wake with the setting on (trackpad events only) was not run.

15. **N/A** (05-SPIKE C5): reconnecting an external trackpad can't be tested on a Mac with only the built-in trackpad.
   result: n/a (05-SPIKE C5, no Magic Trackpad)

16. Open the status menu ▸ Debug. *Expected: "Gestures: on, …", a "Gestures taken" count, and "Last gesture" matching your last gesture.*
   result: pass (VM, synthetic events — Debug read through AX with ⌥ posted: "Gestures: on, trackpad events and multitouch", "Gestures taken: 9", "Last gesture: pinch in, moved" right after a committed ⌥-pinch in). Host: Debug showed "Gestures taken: 60, 3 ended by timeout" and "Multitouch: available, 1 trackpad" during the G-01 re-check.

## Added checks (05-07 multitouch and items earlier plans left to UAT)

17. **Multitouch pinch with "Zoom in or out" off (05-07).** Turn off System Settings ▸ Trackpad ▸ Scroll & Zoom ▸ "Zoom in or out". In Terminal, run `defaults read com.apple.AppleMultitouchTrackpad TrackpadPinch`. *Expected: `0`* (see Risks: this value is the one thing 05-07 couldn't confirm). Then:
    a. Hold ⌥ over Safari and pinch your fingers apart past halfway, then let go. *Expected: the desk follows your fingers and zooms in one level; Safari's page doesn't zoom.*
    b. Hold ⌥ and pinch together. *Expected: it zooms back out one level.*
    c. Without ⌥, pinch apart over bare wallpaper. *Expected: Transom takes it and the desk zooms.*
    d. Hold ⌥ and two-finger scroll left and right while zoomed in. *Expected: the view still pans. It doesn't start a zoom.*
    e. Hold ⌥, click the menu bar icon ▸ Debug. *Expected: "Gestures: on, trackpad events and multitouch" and "Multitouch: available, 1 trackpad".* If the log stream is running, the pinches show as "took pinch #m…: multitouch, ⌥ held, …".
    Leave "Zoom in or out" **off** for item 18.
    result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — `defaults read com.apple.AppleMultitouchTrackpad TrackpadPinch` printed `0` with "Zoom in or out" off, which resolves the 05-07 risk. ⌥-pinch in and out drove the desk through multitouch and Safari did not zoom; ⌥-pans still panned and started no zoom. Debug read "Multitouch: available, 1 trackpad".

18. **Sleep/wake with "Zoom in or out" off (05-07).** Keep the log stream from step 6 running. Don't relaunch Transom. Choose Apple menu ▸ Sleep, wake the Mac, then hold ⌥ over Safari and pinch apart. *Expected: it works first time, and the log shows "multitouch: rescan after wake".* Then turn System Settings ▸ Trackpad ▸ Scroll & Zoom ▸ "Zoom in or out" back **on**.
    result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — with the setting off, Apple menu ▸ Sleep, wake, then ⌥-pinch worked first time, with no relaunch and no crash. The setting was turned back on afterwards.

19. **Multitouch disabled at launch (tap-only fallback, 05-07).** Quit Transom Debug (menu bar icon ▸ Quit). Then run:
    ```
    open "/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app" --args --disable-private=Multitouch
    ```
    Turn zoom on if it's off. Hold ⌥, click the menu bar icon ▸ Debug. *Expected: "Gestures: on, trackpad events" and "Multitouch: off, trackpad events only".* With "Zoom in or out" on, hold ⌥ over Safari and pinch apart. *Expected: it still zooms the desk (trackpad events alone).* Then quit and relaunch normally with the `open` command from step 2. *Expected: Debug shows "Multitouch: available, 1 trackpad" again.*
    result: pass (VM, synthetic events — launched with --args --disable-private=Multitouch: log "Multitouch: off", Debug "Gestures: on, trackpad events" and "Multitouch: off, trackpad events only"; an ⌥-pinch still zoomed ("took pinch #1 … moved to node(n29)", 0 of 12 downstream); a normal relaunch showed "Multitouch: available, no trackpad found" (VM has no trackpad; the host should show "1 trackpad")). Host: the normal launch read "Multitouch: available, 1 trackpad" (G-01 re-check); the --disable-private launch itself was not run on the host.

20. **Reduce Motion takeover mid-crossfade (05-05).** Turn on System Settings ▸ Accessibility ▸ Display ▸ Reduce motion. Press ⌃⌥⌘-Comma (Zoom Out One Level). While the fade is still running (about a quarter of a second), hold ⌥ and pinch apart. *Expected: the screen follows your fingers from where it was, with no jump in position. Half-faded tiles may turn fully opaque at once. That pop is known, so say if it bothers you.* Turn Reduce motion off again.
    result: skipped (user, not checked on hardware) — partial cover: VM item 9 (gesture takeover mid-move continues without a jump, no Reduce Motion); the known opacity pop under Reduce Motion (05-05) was not looked at.

21. **Pinch over the Desktop tile's wallpaper (05-04).** If the menu bar icon shows "Show Desktop Tile", choose it so the Desktop tile is on the desk, and keep part of it free of floating windows. At the view showing all windows, **without ⌥**, put your fingers over the empty part of the Desktop tile and pinch apart past halfway. *Expected: the desk zooms in toward the Desktop tile.* Without ⌥, two-finger scroll there while zoomed in. *Expected: the view pans.* Without ⌥, pinch over a floating window inside the Desktop tile. *Expected: the app gets it and Transom does nothing.*
    result: skipped (user, not checked on hardware) — partial cover: VM `GestureFollowIntegrationTests.aNoOptionPinchOnWallpaperZooms` and `GestureTapIntegrationTests.wallpaperWithoutOptionIsTaken` (bare wallpaper outside the Desktop tile, 05-04 deviation 4) and host item 6; the Desktop-tile-specific case is unverified.

22. **Debug lines G1-G4 (05-06, 05-07).** Hold ⌥ while clicking the menu bar icon to reach Debug. Check each line:
    a. Before any gesture (step 5 of Before you start): "Gestures taken: none yet" and "Last gesture: none yet".
    b. After an ⌥-pinch apart that zoomed in: "Gestures: on, trackpad events and multitouch", "Gestures taken: {n}" (it goes up by one per gesture Transom took), "Last gesture: pinch in, moved", and "Multitouch: available, 1 trackpad".
    c. After a short ⌥-pinch you let go before halfway: "Last gesture: pinch in, sprang back" (or "pinch out, sprang back").
    d. At the view showing all windows, ⌥-pinch together fully and let go: "Last gesture: pinch out, already showing all windows".
    e. A tiny ⌥ two-finger touch that barely moves: "Last gesture: pan, too small" or "pinch, too small".
    f. Menu bar icon ▸ Turn Off Zoom, then Debug: "Gestures: off (zoom off)", and the Multitouch line still reads "available, 1 trackpad". Turn zoom back on.
    result: pass (VM, synthetic events — a "none yet" ×2 before any gesture; b "Gestures: on, trackpad events and multitouch", count +1 per gesture, "pinch in, moved"; c "pinch in, sprang back" and "pinch out, sprang back"; d "pinch out, already showing all windows"; e "pan, too small" and "pinch, too small"; f "Gestures: off (zoom off)" with "Multitouch: available, no trackpad found"; the VM has no trackpad, so the host should re-check that b and f say "1 trackpad"). Host: b's "Multitouch: available, 1 trackpad" confirmed with zoom on (G-01 re-check); f (zoom off) was not re-checked on the host.

23. **Pinch-out and flick feel (05-02).** Zoomed in one level, hold ⌥ and pinch together slowly, noting how far your fingers travel before letting go would commit. Compare it with item 1's pinch apart. *Known: pinch-out reaches the halfway point with about half the finger travel that pinch-in needs.* Then, zoomed in, hold ⌥ and make a **short, quick** two-finger scroll (well under a third of the screen) and lift. *Known: most real pans are fast enough to commit as a flick, so it will probably move one area.* A short, **slow** scroll should spring back. Tell us if pinch-out feels too twitchy or quick short pans commit too easily. The constants are in `GestureTuning`.
    result: pass (host, MacBook Air built-in trackpad, macOS 27.2, Transom Debug rebuilt after `7357a32`, 2026-10-30) — user: "feels fine". Pinch-out travel and flick commit are OK; no `GestureTuning` change.

24. **Spaces with four fingers or ⌃← / ⌃→ (05-SPIKE C5).** You need at least two Spaces (Mission Control ▸ + adds one). With zoom on, swipe left and right between Spaces with **four** fingers 5 times, then use ⌃← / ⌃→ 5 times. Swipe up with four fingers (or press ⌃↑) for Mission Control. *Expected: every switch and Mission Control works; Transom takes none of them.* Back on the Space with your docked windows, hold ⌥ and pinch apart. *Expected: it works first time.*
    result: skipped (user, not checked on hardware) — partial cover: 05-SPIKE items 4 and T4 (four-finger and ⌃←/→ Spaces switching and Mission Control worked while the tap and `mt-stream` ran; 80 Dock-control events seen, none consumed; the product tap mask has no type-30 bit).

## Risks to watch

- **TrackpadPinch with the setting off is unconfirmed on hardware (05-07).** Transom reads `com.apple.AppleMultitouchTrackpad` `TrackpadPinch` and treats a missing key as on. It read `true` with "Zoom in or out" on. If the value doesn't read false once the setting is off (item 17's `defaults read`), multitouch never takes a pinch. Pinch is then lost while the setting is off, the same as tap-only. Item 17a would fail with nothing happening. **Resolved:** item 17 read `0` with the setting off, and multitouch pinch worked.
- With the setting off and ⌥ held, a pan whose finger spacing changes by 3% or more in its first ~63 ms could start a multitouch pinch (item 17d). **Not seen:** item 17d pans started no zoom.
- Under Reduce Motion, taking over mid-crossfade can make the tiles pop to full opacity (item 20). **Open, unlooked-at:** item 20 was skipped.
- Feel: pinch-out commits with less travel than pinch-in, and short pans mostly commit by flick (item 23). **Accepted:** user "feels fine", no tuning change.

## Summary

total: 24
passed: 15 (host, built-in trackpad: items 1, 2, 3, 6, 17, 18, 23; VM, synthetic events: items 4, 5, 9, 12, 13, 16, 19, 22)
issues: 0 open (G-01 fixed in `7357a32`, verified on the host)
pending: 0
skipped: 8 (user, not checked on hardware: items 7, 8, 10, 11, 14, 20, 21, 24)
n/a: 1 (item 15, 05-SPIKE C5)

## Gaps

### G-01: Crash in the multitouch frame path while zoom is on (fixed `7357a32`, verified on the host)

- **Seen:** Transom Debug 0.3.0 on macOS 27.2 (MacBook Air, built-in trackpad) crashed repeatedly with zoom on, 33 s and about 3 min after launch (`~/Library/Logs/DiagnosticReports/Transom Debug-2026-10-30-093943.ips` and `-094043.ips`). EXC_BAD_ACCESS / SIGBUS, KERN_PROTECTION_FAILURE in a stack guard page, on MultitouchSupport's own callback thread (`mt_ThreadedMTEntry`), under `MultitouchSupport.receive` → a chain of reabstraction thunks → `ShimMultitouchBackend.open` handler → `DispatchQueue.main.async`.
- **Root cause:** the frame handler was stored in `OSAllocatedUnfairLock<(@Sendable (Frame) -> Void)?>`. In Debug (-Onone), each `withLock { $0 }` read wrote the closure back through unspecialized generic `inout` state. That wrapped it in one more thunk pair per frame, so calling it recursed deeper every frame until the 512 KB thread stack ran out. The crash report shows only six of the thousands of pairs. The spike streamed about 1,400 frames, under the limit. The VM has no multitouch device. Reproduced headless: a no-op handler passes 1,000 frames and crashes at 6,000 on a normal thread.
- **Fix:** frames now go into a lock-protected buffer (`os_unfair_lock`) and wake main through a `DispatchSourceUserDataAdd`. The handler runs on main, in order, from a plain stored property, so no closure sits behind generic state and there is no per-frame `DispatchQueue.main.async`. The crash canary now stays armed while multitouch runs and clears only at a clean stop (zoom off, quit), so a crash minutes into streaming makes the next launch tap-only ("Multitouch: off after a crash last launch"). Trade-off: any crash while zoom is on now turns multitouch off for that OS build and app version.
- **Regression test:** `MultitouchDevicesTests.theShimFramePathSurvivesThousandsOfFramesOnASmallStack` sends 3,000 frames through the real callback path from a 64 KB thread. Run against the old code, it crashes with the same SIGBUS. `framesKeepTheCanaryArmedUntilACleanStop` covers the new canary rule. Full host `swift test`: 193 + 306 + 75 + 690 = 1,264 passed.
- **Re-check on the host:** rebuilt `Transom Debug.app` (same path as above, not launched). Run with zoom on and use the trackpad for several minutes (pinches, pans, two-finger scrolls). Expect no crash and Debug G4 reading "Multitouch: available, 1 trackpad".
- **Host re-check (user, 2026-10-30, macOS 27.2, rebuilt Debug app):** no crash across about 45 minutes of use with zoom on and multitouch running. Debug read "Multitouch: available, 1 trackpad" and "Gestures taken: 60, 3 ended by timeout". After the earlier crashes, Transom correctly started with "Arranging paused after Transom quit unexpectedly" until Resume Arranging was chosen.
- **Status:** verified.
