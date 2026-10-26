---
status: partial
phase: 03-tiling-mvp
source: 03-VERIFICATION.md human_verification (from 03-01..03-17 SUMMARYs)
started: 2026-10-26T16:50:00-05:00
updated: 2026-10-26T14:34:30-05:00
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing paused - 3 items blocked on the host's second display]

## Tests

Build under test: HEAD 5d83032, Developer ID Release build, Tart VM pane-test (macOS 15.7.7). Already done before this session: Safari/TextEdit drag-docking (verification item 1); grant kept over a same-version binary swap.

### 1. Accessibility grant noticed without a relaunch
expected: Turning Pane on directly in System Settings while it runs starts tracking within a few seconds, no relaunch (WR-02)
result: pass
evidence: same pid 1449 logged notTrusted -> probing -> ready at 16:49:23 after the grant

### 2. Drag behaviours
expected: Holding at an edge shows a preview that matches the final frame; Shift-drag never docks; Cmd-release over another tile swaps; dropping on a docked window's edge nests a split, 3+ levels deep
result: pass

### 3. Close reflow, gap drag, Gaps menu
expected: Closing a docked window reflows its neighbours; dragging the gap between two tiles resizes both; changing Gaps in the menu applies at once and is kept after relaunch
result: issue
reported: "Pass, but the gap drag is a little janky.  It sometimes goes back to the way it was.  Sometimes one of the windows won't let you drag in a particulat direction."
severity: minor
note: close reflow, Gaps menu and relaunch persistence passed; only the gap-handle drag is affected

### 4. Green button, minimise, fullscreen
expected: Green button toggles dock/float; Option-click green zooms natively; a minimised or fullscreened docked window lends its tile and returns to it (WIN-07, TILE-20)
result: issue
reported: "1. Green button still maximizes. 2. Green button still maximizes. 3. Option-green button docks, not maximizes.  Seems you might have them backwards if that is what you intended. 4. Yep. 5. Yep."
severity: major
note: minimise and fullscreen return passed. Lead from the Safari debug session: in the VM the tap event's window-under-pointer field was 0 for every press; GreenButton.shouldSwallow looks up rects[windowID], so with 0 it never swallows and macOS handles the plain click. Why Option-click docks is unknown.

### 5. Keyboard pass
expected: Ctrl-Opt-Cmd arrows, Shift-arrows, S, =, -, B, R, X on docked windows and 1/2/3, U/I/J/K, Return, C, Shift-arrows on a floating window do what the UI-SPEC table says
result: pass
note: docked-window half (arrows, Shift-arrows, S, =, -, B, R, X) passed (user, by hand). Floating half driven by Claude via an in-VM CGEvent injector: F floats; 1/2/3 give 196pt thirds at x 388/596/804; U/I/J/K give 300x314 quarters; Return fills the Desktop tile (388,49 612x640); C centres a 300x314 window at (544,212). All exact for the Desktop tile with 12pt gaps. Shift-arrows (once the injector ran from SSH with Accessibility) give left/right halves 300x640 at x 388/700 and top/bottom halves 612x314 at y 49/375. The earlier Terminal-hosted injector dropped arrow chords; Pane was fine

### 6. Menu pass
expected: Hide/Show Desktop Tile, Arrange All, Float All, Split with New Finder Window, Don't Arrange, Pause/Resume and Undo act on the frontmost window's desk; Pause moves nothing; dock A, open B, Undo leaves B floating and dockable (CR-01)
result: issue
reported: "Claude-driven in the VM: Arrange All, Float All, Hide/Show Desktop Tile, Split with New Finder Window (Finder docks beside TextEdit, its 460pt min width respected, no overlap), Don't Arrange (Finder leaves the tiling, tick shown, untick works), Pause (menu says Arranging paused, commands greyed, injected Ctrl-Opt-Cmd-F and Shift-Ctrl-Opt-Cmd-F move nothing) and Resume all pass. Dock A, open B, Undo: Undo floats A and B stays floating, but B can't be docked: Ctrl-Opt-Cmd-D with B focused (AX focused window = Untitled 3) does nothing, and the menu shows Dock greyed / Float enabled as if the docked A were frontmost. A fresh window C (no Undo involved) can't be docked either."
severity: major
note: Not Undo-specific. With one TextEdit window docked, Pane resolves TextEdit's frontmost window to the docked one. Lead: every TextEdit window may share axIdentifier _NS:34 in layout.json, so identity matching could collapse them

### 7. pane:// URLs
expected: pane://toggle-desktop, pane://split-finder and pane://restore each run once; pane://restore?x=1 does nothing
result: issue
reported: "Claude-driven: pane://toggle-desktop hides and shows the Desktop tile; pane://restore brings parked windows back and re-shows the Desktop; pane://restore?x=1 is rejected (url log: rejected a URL). pane://split-finder opened a new Finder window (580) but did not dock it, and it never entered layout.json (menu still counted it)."
severity: major
note: split-finder worked from the menu earlier (test 6) when Finder had no other window; this run had Finder 546 already open, so it looks like the G-03-5 window-identity problem. Hide Desktop also left floating Finder 546 on screen while parking TextEdit 567/578: same suspect

### 8. Quit restore
expected: Hide the Desktop (floating windows park), quit Pane from the menu: every parked window comes back on screen (SAFE-01)
result: pass
note: Claude-driven: Desktop hidden (TextEdit 567/578 parked at 1023,685), Quit Pane from the menu, both back at (12,37); session cleanExit true

### 9. Crash recovery and crash loop
expected: Hide Desktop, kill -9, relaunch: stranded windows return and the layout re-applies with a crash notice. kill -9 again within 60 s: next launch starts paused with the crash-loop notice (SAFE-02)
result: pass
note: Claude-driven: kill -9 with 567/578 parked; relaunch returned them to (12,37), re-applied the docked layout, recoveryLaunch true (toast not visible: sharingType none hides it from VNC). Second kill -9 within 60 s: next launch menu reads "Arranging paused after Pane quit unexpectedly"

### 10. Layout survives relaunch
expected: Dock three windows, quit Pane (apps keep running), relaunch: same windows in the same tiles (SAFE-06)
result: pass
note: Claude-driven: quit and relaunch kept Terminal 160 and TextEdit 202 docked in the same tiles; the hidden Desktop state also came back

### 11. macOS conflict settings
expected: Stage Manager on pauses arranging with the reason in the menu; Turn Off works; click-wallpaper Turn Off works; Restore macOS Window Settings puts the original values back (SAFE-04)
result: pass
note: Claude-driven: Stage Manager on (defaults write) -> "Turn off Stage Manager?" alert; Not Now -> menu reads "Arranging paused: Stage Manager is on" with a Turn Off Stage Manager item; it sets GloballyEnabled 0 and arranging resumes. Click-wallpaper on -> its alert; Turn Off sets it 0. Restore macOS Window Settings put Stage Manager back to 1 (its value when Pane turned it off) and removed the edge-tiling and click-wallpaper keys (absent in this VM originally). VM settings put back afterwards

### 12. No Screen Recording
expected: A full dock/float session never prompts for Screen Recording and Pane is not listed under it; tiling works (TILE-10)
result: pass
note: Claude-driven: TCC holds only kTCCServiceAccessibility for com.eightabyte.pane; tccd logged no ScreenCapture request from Pane in 90 min of tiling

### 13. Update keeps the grant (bumped version)
expected: Installing a build with a bumped version over the current one keeps the Accessibility grant
result: pass
note: Claude-driven: copy of the HEAD Release app with CFBundleShortVersionString 0.3.1 / CFBundleVersion 999, re-signed with the same Developer ID and entitlements, installed over 0.3.0: permission notTrusted -> probing -> ready in 0.2 s, layout restored

### 14. New window placement
expected: With TextEdit docked, a new Safari window floats on the Desktop tile and does not auto-split (TILE-07)
result: pass
note: Claude-driven: with TextEdit 202 docked, a new Safari window (669) floats inside the Desktop tile at (12,139) and nothing splits. Side effect: the Desktop/TextEdit column widened 494 -> 574pt (Safari's width), Terminal narrowed 494 -> 417

### 15. Separate layouts per Space
expected: Dock windows on Space 1, switch to Space 2 and dock others, switch back: each Space keeps its own layout and switching moves nothing on the other Space
result: pass
note: Claude-driven: added Desktop 2 in Mission Control, docked Reminders and Notes there; layout.json holds a second desk. Ctrl-arrow round trips: Space 1 frames identical before and after, Space 2 frames unchanged

### 16. Second display: Hide Desktop parks safely
expected: Hiding the Desktop tile on one display never parks windows onto the other display or over its tiles (CR-02)
result: blocked
blocked_by: physical-device
reason: "Needs the host Mac with the DELL second display; user is away from home"

### 17. Second display: multi-desk relaunch
expected: Windows docked on both displays (and two Spaces) come back to their own layouts after quitting and relaunching Pane
result: blocked
blocked_by: physical-device
reason: "Needs the host Mac with the DELL second display; user is away from home"

### 18. Second display: live too-big test
expected: Live ArrangeIntegrationTests aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop passes, or its failure is shown to be the test sizing from the main display only
result: blocked
blocked_by: physical-device
reason: "Live test on the host with the DELL attached; user is away from home"

## Summary

total: 18
passed: 11
issues: 4
pending: 0
skipped: 0
blocked: 3

## Gaps

- gap_id: G-03-3
  truth: "Dragging the gap between two tiles resizes both tiles smoothly and the new split sticks"
  status: failed
  reason: "User reported: Pass, but the gap drag is a little janky.  It sometimes goes back to the way it was.  Sometimes one of the windows won't let you drag in a particulat direction."
  severity: minor
  test: 3
  artifacts: []
  missing: []

- gap_id: G-03-5
  truth: "Keyboard and menu commands act on the app's focused window, so a second window of an app with a docked window can be docked (CR-01)"
  status: failed
  reason: "Claude-driven UAT: with TextEdit A docked, focused TextEdit windows B and C can't be docked by Ctrl-Opt-Cmd-D; the menu treats docked A as frontmost"
  severity: major
  test: 6
  artifacts: []
  missing: []

- gap_id: G-03-6
  truth: "A docked window that can't fit its tile floats to the Desktop instead of overlapping a neighbour (core value: windows never overlap)"
  status: failed
  reason: "Claude-driven UAT on Space 2: Reminders' fixed-size Welcome window (768x692) was docked beside Notes; it stays 768 wide at (12,25), overlapping Notes at x 370, and sits 12pt into the top gap"
  severity: major
  test: 15
  artifacts: []
  missing: []

- gap_id: G-03-4
  truth: "A plain green-button click toggles dock/float; Option-click zooms natively (TILE-06, TILE-19)"
  status: failed
  reason: "User reported: 1. Green button still maximizes. 2. Green button still maximizes. 3. Option-green button docks, not maximizes.  Seems you might have them backwards if that is what you intended."
  severity: major
  test: 4
  artifacts: []
  missing: []
