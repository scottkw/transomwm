---
status: diagnosed
phase: 04-zoom-camera
source: 04-VERIFICATION.md human_verification + behavior_unverified_items; 04-REVIEW-FIX.md (WR-02/03/04/06); 04-UI-SPEC.md; 04-08-SUMMARY.md
started: 2026-10-28T18:45:00Z
updated: 2026-10-28T19:30:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete - Claude-driven in the Tart VM; 3 items blocked on things the guest can't do from SSH (Screen Recording grant, Reduce Motion toggle)]

## Tests

Build under test: HEAD 9ccd9d6 (IN-01 fix) and then 2f0823c (dark-mode title fix), `Transom Debug.app` (Developer ID, `scripts/build-debug.sh`), installed in Tart VM `pane-test` (macOS 15.7.7) and launched with `open --env TRANSOM_STAGE_CAPTURABLE=1`. Input came from a guest-side CGEvent helper run over SSH (HID tap), plus `osascript`, a listen-only tap and `log stream --level debug`. Testing ran on Space 3 with Claude's own fixtures only: TransomFixtureApp windows, one new TextEdit document, Safari (launched for the test) and a localhost page. Evidence is under `.build/uat-04/` (git-ignored). For evidence runs only, an uncommitted local change made the preview, toast and collapsed-block panels capturable too. The final installed build is clean HEAD.

Environment note: the guest's display had gone to sleep, which leaves `CGMainDisplayID() == 0`. While it is asleep, every process's `NSScreen.screens[0].frame` sits at y = -768, so Transom's visibleFrame was 768 pt too low: pointer features missed their targets, and a real TextEdit window was tiled to y = 686. A `pmset displaysleepnow` / `caffeinate -u` wake restored the main display. All results below come from after that wake, with `caffeinate -dimsu` running in the guest (see Deferred Follow-Ups).

### 1. ⌘⇧-drag rectangle zoom (ZOOM-03) and Esc cancel (ZOOM-12)
expected: Band (8% fill) and accent target preview after 4 pt; the drag reaches no app; camera moves to the LCA of tiles whose centres are inside; a band over nothing does nothing. Esc (also with ⌘⇧ held) cancels: no move, the release reaches no app, the Esc hotkeys are gone afterwards, ⌥⌘Esc still opens Force Quit
result: pass
evidence: 13-band.png (band over TextEdit and Fixture 0, with the target preview over the bottom row); log `rect zoom → n12` then `home → node(n12)`; 15-esc.png (after cancel: no band, no move, no TextEdit selection); log `rect zoom canceled (Esc)` twice, once with ⌘⇧ held as the Esc modifiers and once with plain Esc. Afterwards, Esc closed Spotlight (window 5526 gone), so no Esc hotkey stayed registered. ⌥⌘Esc opened `loginwindow` "Force Quit Applications" (16-forcequit.png) while Transom was armed. A band missing every tile centre logged `rect zoom: no target` and made no move.
note: ⌥⌘Esc sent as a synthetic HID event never reaches loginwindow (a tool limit, unrelated to Transom); the System Events key code path opened it

### 2. Click-to-zoom after zoom-out (ZOOM-06), tile click mid-move, no stray focus exit (WR-02)
expected: After a Zoom Out reveal, pick mode starts; hover ring on the tile under the pointer; a plain click is consumed, zooms to that window's leaf and focuses it; a stage-tile click mid-move retargets; no stray windowFocused ends pick mode right after the reveal
result: pass
evidence: log `pick mode on` → `pick mode off: picked` → `pick → window 5500` → `home → node(n11)`; Fixture 0 framed at 8,33 1008x673, fixture `frontmost index=0`. 10-hover.png: 2pt accent ring on the Fixture 1 tile. Mid-move: `keyclick` 60 ms into a step-in gave `retarget node(n14) → node(n13) during moving`, Fixture 1 framed and focused (`frontmost index=1`). WR-02 (stray focus): pick mode stayed on for 4 s with no input (log 19:03:29, no `focus changed` exit). Esc ends pick mode (`pick mode off: Esc`).

### 3. Shortcuts window (ZOOM-08)
expected: Rebind a hotkey and use it; a duplicate chord is refused with the in-Transom message; Restore Defaults confirms and resets
result: pass
evidence: 19-shortcuts.png (Zoom section, 11 rows plus Arrange rows, Restore Defaults). Zoom Out to All Windows rebound to ⌃⌥⌘9: defaults `{"carbonKeyCode":25}`; ⌃⌥⌘O then did nothing and ⌃⌥⌘9 zoomed out (log 19:10:13). ⌃⌥⌘Z gave the alert "This shortcut is already used by “Undo Layout Change” in Transom." (21-duplicate.png) and the binding stayed 25. Restore Defaults showed the confirmation copy from UI-SPEC (22-restore-confirm.png); confirming reset it to keyCode 31 (O).
note: the 44-row count wasn't counted through AX (System Events can't walk the SwiftUI list). ShortcutsModelTests covers it

### 4. Title-bar double-click (ZOOM-10) and Desktop double-click vs icon (ZOOM-11)
expected: Title-bar double-click frames the window, a second one toggles back; wallpaper double-click frames the Desktop and toggles back; a desktop-icon double-click only opens the icon (RESEARCH A4 roles)
result: pass
evidence: log `title bar double-click → frame window 5482` → `home → node(n9)`, TextEdit at 8,33 1008x673 (24-titlebar-frame.png); a second double-click gave `node(n9) → home`. macOS's own title-bar action did not run. Wallpaper: `desktop double-click hit AXGroup / -` → `frame desktop` → `home → node(n0)` (25-desktop-frame.png), then back to home. Icon `uat-icon.txt` (AX `AXImage`, parent `AXGroup` desc "desktop"): `desktop double-click hit AXImage / -`, no camera move, and the file opened in TextEdit (26-icon-dblclick.png).
note: RESEARCH A4 confirmed on macOS 15.7: the wallpaper is `AXGroup` (desc "desktop") and an icon is `AXImage`. The Mouse toggle in Shortcuts (IN-05) was not exercised

### 5. Collapsed blocks (ZOOM-13)
expected: An oversized drop with zoom on shows "Collapsed until you zoom in" and then an app-colour block with icon; hover ring; double-click zooms to the leaf and focuses it; VoiceOver label '“App”, collapsed: title'
result: pass
evidence: 32-collapse-preview2.png (drop preview with the "Collapsed until you zoom in" capsule); log `Docked. Zoom in to see it.`; 33-collapsed-block2.png (dark app-colour block, app icon, hover ring). Double-click: `home → node(n17)`, Fixture 3 framed and focused (`frontmost index=3`, 34-block-zoomed.png). AX: `AXButton desc=“TransomFixtureApp”, collapsed: Fixture 3 help=Double-click to zoom in`; AXPress gave the same zoom. After zooming back home, the settle reported `1 collapsed`.
note: The first drop of a window whose minimum Transom hasn't learned yet does not collapse. The preview is a plain dock, the write is refused, and the window floats with "…no longer fits its tile, so it's floating on the Desktop" (31-collapsed-block.png, `notice lostRoom`). The second drop, with the minimum learned, collapses. This follows CONTEXT E (an OS-caused loss of room floats), but a user may read it as "collapse didn't work the first time". The user should judge. The pointing-hand cursor can't be seen in screenshots

### 6. kill -9 while zoomed, relaunch
expected: No window parked; N2 shows
result: pass
evidence: zoomed into `node(n14)` with 3 windows parked at 1023,686, then `pkill -9`. On relaunch every window was back on screen (list in the log), with `notice crashRecovered(unplaced: 0)`. 35-after-crash.png shows "Transom quit unexpectedly. Your windows are back on screen and your layout is restored."
note: the window that had been collapsed came back floating (`notice lostRoom`), because the collapsible set isn't persisted. It was on screen, never parked

### 7. ⌘⇧-click on a Safari link opens a new tab
expected: The re-posted press reaches Safari
result: pass
evidence: log `⌘⇧-click re-posted`; Safari's tabs went from [link.html] to [link.html, b.html] with b.html in front (40-safari-newtab.png)
note: file:// links make Safari show a "Confirm the file to load" panel, so the page was served from a guest-local `python3 -m http.server`

### 8. fn⌃⌥⌘ arrows pan; macOS tiling doesn't act
expected: View pans; macOS window tiling doesn't also act
result: pass
evidence: from the framed Fixture 2: fn⌃⌥⌘← `node(n15) → node(n11)`, ↑ `→ node(n0)`, ↓ `→ node(n15)`, → refused `No area to the right`. After each pan, window frames match Transom's plan exactly, so macOS did no tiling.
note: sent as keycodes 115/116/121/119 with the fn flag, which is what an Apple keyboard sends for fn+arrow

### 9. Reduce Motion gives a crossfade
expected: Crossfade; no tile moves or scales
result: blocked
blocked_by: other
reason: "`defaults write com.apple.universalaccess reduceMotion -bool true` is written (reads back 1) but `NSWorkspace.accessibilityDisplayShouldReduceMotion` doesn't change without the System Settings toggle's notification. The mid-move frame still slid (43-reduce-mid.png vs 42-motion-mid.png). The key was deleted afterwards (it didn't exist before). Needs the Accessibility ▸ Display ▸ Reduce motion switch, flipped by the user"

### 10. Fallback tiles legible in light and dark with Screen Recording denied
expected: Icon + title capsule legible in both appearances; the explainer shows once after the first reveal and never again
result: pass
evidence: Transom Debug has no Screen Recording grant (`screen recording: not granted, using app-icon tiles`). Light: 42-motion-mid.png is legible. Dark, before the fix: the title capsule drew black text on the dark capsule (44-dark-capsule-crop.png), so it was not legible. Fixed in 2f0823c and re-verified: 45-dark-fixed.png / 45-dark-fixed-crop.png show white text. Light was re-checked after the fix (46-menu-over-stage.png). The explainer showed once ("explainer shown", then "explainer: not now") across 40 min, relaunches and a crash recovery.
note: issue found and fixed during UAT (see Gaps, G-04-10, resolved). Appearance restored to light

### 11. An open status menu stays above the stage
expected: Menu stays above the stage
result: pass
evidence: status menu open, then `transom-debug://step-in`: 46-menu-over-stage.png shows the menu (CG layer 101) over the moving stage

### 12. WR-02: pick mode ends on a focus change (⌘-Tab, Dock click)
expected: Bringing another app forward ends pick mode, so its Esc is not taken
result: issue
reported: "Claude-driven: after a Zoom Out reveal (pick mode on), `tell application \"TextEdit\" to activate` brought TextEdit forward, but pick mode stayed on; it only ended 1.7 s later on the next command (`pick mode off: command`). The `.windowFocused` hook never fires on app activation alone: AXWindowSystem emits windowFocused only from kAXFocusedWindowChanged/kAXMainWindowChanged hints, which don't fire when an app activates with its focused window unchanged. So the WR-02 fix doesn't cover its stated ⌘-Tab / Dock-click case, and the first Esc typed in that app is still taken by Transom"
severity: minor

### 13. WR-03: first move after launch gets snapshots on the second move at the latest
expected: With Screen Recording granted, the first move may show fallback tiles; the next shows snapshots
result: blocked
blocked_by: other
reason: "Needs Screen Recording granted to Transom Debug. Allow Window Previews… sent the request (tccd: `Notifying for access kTCCServiceScreenCapture … Transom Debug.app`) and opened the Screen & System Audio Recording pane, but Transom Debug isn't listed there and no prompt appeared, so granting needs the user's + in System Settings. Claude doesn't grant TCC by UI automation"

### 14. WR-04: Turn Off Zoom during a post-reveal refresh makes no more ScreenCaptureKit calls
expected: No SCK call after Turn Off Zoom
result: blocked
blocked_by: other
reason: "Same as test 13: the post-reveal refresh runs only when granted. With previews denied, zoom off logged no capture activity"

### 15. WR-06: Turn Off Zoom waits for the home move's own reveal
expected: Zoom ends only after the home move reveals, never on an older move's reveal; no window left parked
result: pass
evidence: step-in through a URL, then Turn Off Zoom from the open status menu. Log: `home → node(n12)` settle 17.537, home move `node(n12) → home` 17.710, settle 18.027, `zoom off (0 collapsed windows floated)` 18.127, after the home move's settle plus its 100 ms fade. Every window ended at its home tile. Turn On Zoom logged `zoom on`.
note: menu tracking adds about 0.5 s, so the turn-off landed during the step-in's reveal, not mid-animation

### 16. The 6 flagged prohibitions (judgement)
expected: Each MUST NOT holds
result: pass
evidence: |
  - 04-01 ZOOM-05 (no snapshots to disk or logs): holds. The only product disk writers are LayoutStore and MinimumHintsStore (JSON). Guest `~/Library/Application Support/Transom` holds only layout.json and min-size-hints.json, and nothing is under Caches. No log line carries image data.
  - 04-04 ZOOM-05 (asks for Screen Recording at most once on its own): holds. "explainer shown" appeared once in 40 min across two relaunches and a kill -9. Later requests came only from the menu (test 13).
  - 04-04 ZOOM-05 (no persisting or sharing of snapshots; purge on zoom off): holds by code inspection (memory LRU, close()). Not observable here, because previews were denied.
  - 04-06 ZOOM-12 (one press-release only, no lingering Esc, never ⌥⌘Esc): holds. Esc reached Spotlight after band cancels and after pick mode ended, and Force Quit opened. Exception: the Esc hotkey lingers in pick mode after an app switch (test 12), until the next click, command or Esc.
  - 04-06 ZOOM-03 (no input synthesised except the exact re-post): holds. `event.post(tap:)` appears once in Sources (ZoomInput.repost), outside the spike.
  - 04-08 ZOOM-07 (no window left parked after quit, crash, Restore All or Turn Off Zoom): holds for all four in this run. Quit while zoomed: `quit restore: 6 of 6 windows`, all on screen. Crash: test 6. Restore All while zoomed: `notice restored(count: 3)`, all home. Turn Off Zoom: test 15. Crash loop not exercised.

## Summary

total: 16
passed: 12
issues: 1
pending: 0
skipped: 0
blocked: 3

## Gaps

- gap_id: G-04-12
  truth: "Pick mode ends when the user brings another app forward (⌘-Tab, Dock click), so that app's Esc is never taken (WR-02)"
  status: failed
  reason: "Claude-driven VM UAT: TextEdit activated during pick mode; pick mode stayed on until the next command. windowFocused is emitted only on AX focused/main-window-changed hints, not on app activation"
  severity: minor
  test: 12
  root_cause: "ArrangeController ends pick mode on `.windowFocused` (ArrangeController.swift:156), but AXWindowSystem emits that event only from kAXFocusedWindowChanged / kAXMainWindowChanged (AXWindowSystem.swift:500). Activating an app whose focused window doesn't change emits neither"
  artifacts: ["Sources/TransomMac/ArrangeController.swift", "Sources/TransomMac/AXWindowSystem.swift"]
  missing: ["End pick mode on NSWorkspace.didActivateApplicationNotification (ArrangeController already observes it in startWatchdog); needs a shell-level test or VM re-check, as no headless test reaches ZoomInput"]
- gap_id: G-04-10
  truth: "Fallback tile titles are legible in dark mode"
  status: resolved
  reason: "Claude-driven VM UAT: black title text on the dark capsule in dark mode"
  severity: cosmetic
  test: 10
  root_cause: "TileLayer.text built an NSImage with a lazy drawing handler; labelColor resolved when CA drew it, outside the stage's drawing appearance"
  artifacts: ["Sources/TransomMac/Zoom/TileLayer.swift", "Tests/TransomMacTests/TileLayerTests.swift"]
  resolved_by: 2f0823c
  resolved_at: 2026-10-28T19:21:00Z

## Deferred Follow-Ups

- test: 0
  idea: "Guest display sleep leaves CGMainDisplayID() == 0 and NSScreen.screens[0].frame at y = -height in every process; Transom then plans visibleFrame 768 pt too low and tiles real windows off screen (TextEdit was written to y 686). Seen in the VM only. Worth checking whether a real Mac with its display asleep can hit it (Displays.current() trusts NSScreen while CGDisplayBounds was right), and whether VM harness scripts should wake the display (`caffeinate -u`) and hold `caffeinate -d` before live runs"
  deferred_at: 2026-10-28
- test: 5
  idea: "First oversized drop of a window with an unlearned minimum floats instead of collapsing (CONTEXT E). Consider treating a refused write right after a zoom-on drop as a collapse"
  deferred_at: 2026-10-28
