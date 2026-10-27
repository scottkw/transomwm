---
status: partial
phase: 03-tiling-mvp
source: 03-VERIFICATION.md human_verification (from 03-01..03-17 SUMMARYs)
started: 2026-10-26T16:50:00-05:00
updated: 2026-10-27T13:55:00-05:00
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing paused - 03-23 review fixes VM-checked on 0.3.8: 4 pass, locked start fails (G-03-10); pending: G-03-10 fix, green button and gap drag by hand, tests 16-17 display half on the host's second display]

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
note: minimise and fullscreen return passed. Diagnosed (G-03-4): plain click is a real bug; Option-click docking is D-33 working as specified. User decision 2026-10-26: keep D-33 (Option-zoom is undone when it would overlap a tile), so the expectation for Option-click is "zooms, then returns to its tile / the Desktop tile". Original lead: in the VM the tap event's window-under-pointer field was 0 for every press; GreenButton.shouldSwallow looks up rects[windowID], so with 0 it never swallows and macOS handles the plain click. Why Option-click docks is unknown.

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
note: split-finder worked from the menu earlier (test 6) when Finder had no other window; this run had Finder 546 already open, so it looks like the G-03-5 window-identity problem. Hide Desktop also left floating Finder 546 on screen while parking TextEdit 567/578: same suspect. Diagnosed: not G-03-5 and not a bug: com.apple.finder was on the Never Arrange list (excludedBundleIDs) in the VM, so D-29 behaviour excluded it. With the exclusion cleared, Finder was admitted and Hide Desktop parked 546/580/731. Re-run test 7 with no exclusions after the gap fixes

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
result: issue
reported: "Claude-driven in the Tart VM (single display, via scripts/vm-live-test.sh): the test failed the same way before and after the gap fixes, so it is not display-related"
severity: minor
note: G-03-7. The bug was in the test, not Pane: window 1 was docked from the Desktop tile's exact middle (fx = 0.5), a tie that a 1 pt area change resolved as a column split, so nothing lost room. Fixed in the test (centre in the right edge band); the suite then passed 3 runs in a row in the VM. The "main-display sizing" explanation is dropped

## Re-run after gap closure (Pane 0.3.7 / 1005, HEAD 8653fcc, Tart VM, Claude-driven)

- 3 gap drag / close reflow / Gaps: pass (pinned-side drag moves; hold mid-drag shows no snap-back over 122 and 274 sampled changes; Undo exact)
- 4 green button: pass (real VNC plain click floats/docks, never fullscreen; Option-click zooms then D-33 returns; minimise/fullscreen return; CR-01: a Finder menu item over the green button got the click 3/3, window stayed docked)
- 6 menu / focus: pass (new window B docks by Ctrl-Opt-Cmd-D; Undo case; menu enablement follows B)
- 7 pane:// URLs: pass (toggle-desktop, split-finder with other Finder windows open, restore, restore?x=1 rejected)
- 14 new window placement: pass
- 15 Space 2 Reminders: pass (floats ~2 s after docking, Notes keeps its tile, no com.apple.reminders hint saved; ~410 pt overlap is accepted T-03-58)
- 17 Space half: pass (clean quit and kill -9 both restore both desks; Notes re-tiles and is tracked)
- New: a closed Safari window (2174) stays in layout.json as present; Safari keeps its CG entry (no Space) after close, and 03-23's dormant rule then keeps it across relaunch (G-03-9)
- Evidence: scratchpad uat-rerun.md (session-local)

## VM checks after the 03-23 review fixes (Pane 0.3.8 / 1006, HEAD 9c6727d, Tart VM, Claude-driven, 2026-10-27)

- Minimised (Notes) and Cmd-H hidden (Calculator) windows on hidden Space 41: SkyLight reports Space 41 for both from Space 1 (also Space 1 on the shown Space); clean relaunch keeps both desks; Notes returns to its tile on unminimise: pass (WR-03 risk does not occur for these)
- Docked Safari closed with Cmd-W (twice, incl. a Cmd-N window): tile freed at once, still free after relaunch: pass; Safari's no-Space ghost entry did not recur, so that path is headless-only
- Finder tab group, newer tab (2399) selected over docked 731: hidden tab 731 reports no Space; after relaunch the group appears once, floating (CR-01); the tile is lost as before 03-23: pass as designed
- Parked floater (Reminders, Space 41 Desktop hidden by Ctrl-Opt-Cmd-H), kill -9 from Space 1, relaunch: back on screen at its home frame, Desktop shown: pass (CR-02)
- Locked start (Ctrl-Cmd-Q, launch, unlock): paused while locked and layout.json untouched; after unlock hidden Space 41 kept its desk but shown Space 1 lost every tile (Terminal, TextEdit 202/578 now floating, frames unmoved): fail (G-03-10)
- Calculator on Space 41 was not parked when its Desktop was hidden (observed, not yet a gap)

## Summary

total: 18
passed: 11
issues: 6
pending: 0
skipped: 0
blocked: 2

## Gaps

- gap_id: G-03-3
  truth: "Dragging the gap between two tiles resizes both tiles smoothly and the new split sticks"
  status: failed
  reason: "User reported: Pass, but the gap drag is a little janky.  It sometimes goes back to the way it was.  Sometimes one of the windows won't let you drag in a particulat direction."
  severity: minor
  test: 3
  root_cause: "Two independent bugs. (H1) Arranger.boundaryChange converts the drag delta to weight against the laid-out length, then caps it at the loser's on-screen loss; when the growing side is pinned at a minimum above its weight share (common for the Desktop tile, whose minimum is the largest learned minimum of its floating windows), the weight shift is absorbed and nothing moves (2 children) or the wrong boundary moves (3+), still recording an undo step. (H2) The live gap move only exists inside one replan(with:on:) call (defer restores the committed World), so any other replan() mid-drag (window event such as Terminal's title change, off-plan frame correction, correction tick) re-writes the pre-drag tiles until the next drag event or mouse-up."
  artifacts:
    - path: "Sources/PaneEngine/Arranger.swift"
      issue: "boundaryChange (~1194) ignores pinned-child offset; gapDrag (~1347)/replan(with:on:) (~1161) keep no live drag state; handle(_:) (~515) and moved/correct (~569) replan the committed World mid-drag"
    - path: "Sources/PaneEngine/Planner.swift"
      issue: "Desktop minimum = max learned min of floating windows makes H1 common"
  missing:
    - "Re-base split weights to resolved child sizes (or apply delta in points) before capping"
    - "Hold the pending gap move in Arranger state until mouse-up and apply it in every replan()"
    - "Tests: pinned growing side; mid-drag windowChanged / off-plan windowResized must not write pre-drag tiles"
  debug_session: ".planning/debug/g-03-3-gap-drag.md"

- gap_id: G-03-5
  truth: "Keyboard and menu commands act on the app's focused window, so a second window of an app with a docked window can be docked (CR-01)"
  status: failed
  reason: "Claude-driven UAT: with TextEdit A docked, focused TextEdit windows B and C can't be docked by Ctrl-Opt-Cmd-D; the menu treats docked A as frontmost"
  severity: major
  test: 6
  root_cause: "The focus hint for a newly created window is lost: AXAppThread's observer gives windowID nil for an element not yet cached, and AXWindowSystem.refresh() consumes pendingFocus even when the window is still in WindowTracker's 250 ms settle set; settling emits only windowCreated. focusedWindow(of:) then prefers the stale focusedIdentities[pid] (docked A) over the correct AXMain, so every hotkey, pane:// URL and menu validation acts on A. The _NS:34 axIdentifier lead is refuted (identity is windowID/pid/bundleID)."
  artifacts:
    - path: "Sources/PaneMac/AXWindowSystem.swift"
      issue: "focusedWindow(of:) (~278) prefers stale focusedIdentities; refresh() (~326) drops pendingFocus for not-yet-tracked windows; handle(_:) (~473) ignores focus hints without windowID"
    - path: "Sources/PaneMac/AX/AXAppThread.swift"
      issue: "observer callback (~119) yields windowID nil for uncached elements"
    - path: "Sources/PaneEngine/WindowTracker.swift"
      issue: "settle pending set (~118) and windowCreated carry no focus fact"
  missing:
    - "Keep an unresolved focus hint until the window is tracked (or refresh focus from AXMain when a created window is main), keeping focusedIdentities' tab-switch/panel behaviour"
    - "Test: second window of the same app created after a windowFocused becomes the command target"
  debug_session: ".planning/debug/g-03-5-focused-window-identity.md"

- gap_id: G-03-6
  truth: "A docked window that can't fit its tile floats to the Desktop instead of overlapping a neighbour (core value: windows never overlap)"
  status: failed
  reason: "Claude-driven UAT on Space 2: Reminders' fixed-size Welcome window (768x692) was docked beside Notes; it stays 768 wide at (12,25), overlapping Notes at x 370, and sits 12pt into the top gap"
  severity: major
  test: 15
  root_cause: "Fit is decided only from learned minimums, and MinimumSizeLearner.recordWrite counts a refusal only if the read-back moved toward the request (late-applier guard from 7c97838). Reminders' window opens at its minimum, so no write moves it, nothing is learned, and no path compares a docked window's read-back with its tile. Overflows under the 32 pt refusalMargin are also never learned. y=25 is AppKit pinning a window taller than the visible frame, not a failed write."
  artifacts:
    - path: "Sources/PaneEngine/MinimumSizeLearner.swift"
      issue: "moved-toward-request check (~43) rejects refusals from windows already at their minimum; 32 pt margin hides small overflows"
    - path: "Sources/PaneEngine/WindowTracker.swift"
      issue: "applyFrameResult (~304) only feeds the learner"
    - path: "Sources/PaneEngine/Arranger.swift"
      issue: "fit checks (Dock ~812, planFloatingLostRoom ~1368) rely solely on learned minimums"
    - path: "Sources/PaneEngine/Planner.swift"
      issue: "Desktop minimum = max learned min of floating windows; a too-big floater would then make every docked window on the desk unfit"
  missing:
    - "Treat a docked window whose read-back still exceeds its tile after confirmDelay as unfit (or learn that size), keeping the late-applier protection"
    - "Decide docked-tile overflow under 32 pt"
    - "Cap the Desktop minimum at the area / ignore floaters that can never fit, so floating one window doesn't float the whole desk"
    - "Tests: window that opens at its minimum; minimum height within 32 pt of the tile"
  debug_session: ".planning/debug/g-03-6-fixed-size-window-overlap.md"

- gap_id: G-03-4
  truth: "A plain green-button click toggles dock/float; Option-click zooms natively and D-33 returns the window to its tile (TILE-06, TILE-19)"
  status: failed
  reason: "User reported: 1. Green button still maximizes. 2. Green button still maximizes. 3. Option-green button docks, not maximizes.  Seems you might have them backwards if that is what you intended."
  severity: major
  test: 4
  root_cause: "The session tap's window-under-pointer field is 0 for every press (injected and HID), so InputTap falls back to CGWindowList.topmostWindow(at:), which has no layer filter and returns the Dock's full-screen layer-20 window (#7) on macOS 15. GreenButton.shouldSwallow finds no rect for it, the click passes through and macOS goes fullscreen. ArrangeController.pressWindow already filters layer 0, which is why drags work. Option-click 'docking' is D-33 as specified; user chose to keep it (2026-10-26)."
  artifacts:
    - path: "Sources/PaneMac/CGWindowList.swift"
      issue: "topmostWindow(at:) (~18) has no layer-0 filter"
    - path: "Sources/PaneMac/Input/InputTap.swift"
      issue: "press (~131) resolves to the Dock overlay window and is never swallowed"
  missing:
    - "topmostWindow(at:) picks the topmost layer-0 window, as pressWindow does, ideally as a pure function over [CGWindowEntry] with a unit test (Dock layer-20 full-screen entry first)"
    - "Re-test with real hand clicks"
  debug_session: ".planning/debug/g-03-4-green-button.md"

- gap_id: G-03-7
  truth: "Live test aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop passes (D-26 live)"
  status: resolved
  reason: "Fails in the single-display VM before and after the gap fixes"
  severity: minor
  test: 18
  root_cause: "Test bug: window 1's dock point was the Desktop tile's exact middle (fx = 0.5), a tie between the side bands and the top/bottom bands; the test's visible frame (688) went stale vs Pane's area (689), so Dock chose .top, the column layout fit and no window lost room. Pane's D-26 path works (passes once the point is in the right edge band)."
  artifacts:
    - path: "Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift"
      issue: "start1 at desktop.minX with the full Desktop width put the dock point on the tie"
  missing: []
  resolved_by: "test fix in the commit that adds this entry"
  debug_session: ".planning/debug/g-03-7-live-too-big-test.md"

- gap_id: G-03-8
  truth: "Docked windows on every Space come back to their own layouts after quitting and relaunching Pane, apps still running (SAFE-06)"
  status: failed
  reason: "Verifier + VM: after a Pane relaunch (clean or crash-recovery) the hidden Space's desk comes back empty; reproduced 4/4"
  severity: major
  test: 17
  root_cause: "AX kAXWindowsAttribute lists only the shown Space's windows, so at launch WindowTracker never tracks hidden-Space windows; Arranger.process(.inventory) runs LayoutRestore.reattach once at the first complete inventory and it closes every saved window not tracked yet (World.apply(.closed)). The windows are alive: CGWindowList optionAll still has them at layer 0 with the same IDs and SkyLight reports their Space. ArrangerMultiDeskRestoreTests misses it because its relaunch reuses the first session's fake tracker."
  artifacts:
    - path: "Sources/PaneEngine/LayoutRestore.swift"
      issue: "reattach (18-23) treats not-yet-tracked as closed"
    - path: "Sources/PaneEngine/Arranger.swift"
      issue: "restore runs once at the first complete inventory (194-218)"
    - path: "Sources/PaneMac/AXWindowSystem.swift"
      issue: "has the optionAll CG list and SkyLight Spaces at the first sweep but never passes live-untracked windows to the engine"
    - path: "Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift"
      issue: "relaunch (120-123) keeps the same FakeWindowSystem"
  missing:
    - "Report saved windows still alive (layer-0 CG optionAll entry, same windowID+pid) to reattach and keep them dormant in their desk"
    - "Seed lastRequested for a dormant docked window when it is first created so the Space-switch plan is written"
    - "Close a dormant window when its ID leaves the CG list or its app terminates"
    - "Headless test with a fresh fake at relaunch (fails today); fix ArrangerMultiDeskRestoreTests the same way; VM re-check of UAT 17's Space half"
  debug_session: ".planning/debug/g-03-8-hidden-space-relaunch.md"

- gap_id: G-03-9
  truth: "Closing a window removes it from Pane's tracking and layout.json"
  status: deferred
  deferred_to: "Phase 6 (user decision 2026-10-26)"
  reason: "Claude-driven VM re-run: closed Safari window 2174 stays present; survives relaunch as dormant"
  severity: minor
  test: 14
  root_cause: "Safari keeps the closed window's CG optionAll entry (layer 0, offscreen, no Space) for minutes; CloseRule needs the CG entry gone, and 03-23's isAlive/liveWindows count any layer-0 entry as alive. Bookkeeping only, no overlap."
  artifacts:
    - path: "Sources/PaneEngine/CloseRule.swift"
      issue: "CG presence alone blocks every close"
    - path: "Sources/PaneEngine/LayoutRestore.swift"
      issue: "isAlive checks only layer, ID and pid"
  missing:
    - "Treat a layer-0 entry with a known-empty Space list as absent; measure minimised/hidden/tab windows' Spaces first"
  debug_session: ".planning/debug/g-03-9-closed-safari-lingers.md"

- gap_id: G-03-10
  truth: "Starting Pane while the screen is locked keeps every saved desk once the screen is unlocked (SAFE-06, CR-03)"
  status: failed
  reason: "Claude-driven VM check on 0.3.8: Pane launched while locked logged 'session paused: locked or asleep' and kept layout.json; after unlock ('session resumed after a full refresh') the shown Space 1 desk lost all 3 docked tiles (Terminal 160, TextEdit 202, TextEdit 578 became floating, frames unmoved); hidden Space 41 (Notes docked, Reminders/Calculator floating) was kept"
  severity: major
  test: 17
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

## Observed, not yet a gap

- (promoted to G-03-8) Space 2 desk emptied on relaunch.
- Calculator (Space 41) stays on screen when its desk's Desktop is hidden, while Reminders is parked.
- After a Dock restart, Pane stopped correcting one window's frame changes (seen by the G-03-4 debugger, possibly caused by the restart).
