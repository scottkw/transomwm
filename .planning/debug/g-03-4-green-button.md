---
status: diagnosed
trigger: "G-03-4: plain green-button click maximises (docked and floating) instead of toggling dock/float; Option-click green docks instead of zooming natively. User: 'Seems you might have them backwards'."
created: 2026-10-26T16:00:00-05:00
updated: 2026-10-27T14:40:00-05:00
reopened: 2026-10-27
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (deterministic: every plain green-button press, injected or real HID, in the VM)
hypothesis: CONFIRMED. Item 1/2: the tap's window-0 fallback CGWindowList.topmostWindow(at:) has no layer filter and returns the Dock's full-screen layer-20 window (CG 7) for every point, so rects[7] is nil, nothing is swallowed and macOS full-screens the window. Item 3: not inverted; the Option press passes, macOS zooms, then D-33 pulls the zoom back (docked -> its tile; floating across a tile -> clamped into the Desktop tile), which reads as "docked".
next_action: none (goal find_root_cause_only); hand to plan-phase --gaps
known_pattern_candidate: none (KB: safari-toolbar-drag-no-dock only; it did note windowUnderPointer is always 0)
reasoning_checkpoint:
  hypothesis: "Plain green presses are never swallowed because the window-0 fallback topmostWindow(at:) picks the Dock's full-screen layer-20 window (CG 7), not the app window, so rects[7] misses"
  confirming_evidence:
    - "VM: the topmost on-screen window at every green-button centre is Dock#7 layer 20 0,0 1024x768 (also with Dock autohide on: Dock#838)"
    - "VM: injected AND real VNC (HID) plain presses on 202's green logged 'start ... window 202 (CG 7 ...)', went through the pointer path, and 202 entered full screen"
    - "VM: the same press with mouseEventWindowUnderMousePointer preset to the real ID (fallback skipped) was swallowed: docked 722 floated, floating 578 docked, no drag-log press line"
  falsification_test: "if the preset-ID press had also passed through (press line logged, full screen), the fault would be in the rects (offset/frame) or shouldSwallow, not the window lookup"
  fix_rationale: "selecting the topmost NORMAL-layer (layer 0) window, as pressWindow already does, returns the app window under the button, so rects[id] hits and the press is swallowed"
  blind_spots: "host macOS 27 Dock window not confirmed (my host CG read listed no Dock window, possibly restricted); other non-zero-layer overlays (layer 3 utility panels of other apps) covering a button would be skipped by a layer-0 filter (T-03-34 trade-off)"
  candidate_causes:
    - "code: topmostWindow(at:) lacks the layer-0 filter pressWindow has (confirmed)"
    - "environment: session tap reports window 0 for every press, HID or injected (confirmed; makes the fallback the only path)"
    - "environment: Dock owns a full-screen layer-20 window on macOS 15 regardless of autohide (confirmed)"
    - "config/spec: D-33 snaps a docked window back / clamps a floating one after a native zoom (confirmed; explains item 3, works as specified)"
    - "code: Option condition inverted in shouldSwallow (eliminated)"
  and_gate: "yes for items 1/2: window field 0 at the session tap AND the fallback picking the Dock overlay; either alone would not fail (preset ID works; a layer-0 scan works). Item 3 is an independent spec effect (D-33), not a contributing condition"

## Symptoms

expected: A plain green-button click toggles dock/float; Option-click green zooms natively (TILE-06, TILE-19)
actual: (user, by hand in the VM) 1. plain click on a docked window: maximises natively. 2. plain click on a floating window: maximises natively. 3. Option-click green: docks, not maximises.
errors: none reported
reproduction: Tart VM pane-test (macOS 15.7.7), Pane 0.3.1 Developer ID build. Click the green traffic-light button of a docked / floating TextEdit window, then Option-click it.
started: phase 3 UAT (HEAD 5d83032 build), test 4
lead: an earlier Safari debug session saw the tap event's window-under-pointer field = 0 for every press in the VM.

## Eliminated

- hypothesis: Pane has the Option condition inverted (Option-click swallowed and toggled, plain click passed)
  evidence: GreenButton.shouldSwallow swallows only `!flags.contains(.maskAlternate)`; VM Option-clicks (injx oclick, maskAlternate on down/up) logged a pointer-path press (CG 7) and macOS zoomed the window (202 -> 1,64 975x648; 722 -> 2,27 950x629) before Pane pulled it back. A swallowed press logs no drag line and never reaches the app.
  timestamp: 2026-10-26T16:08:00-05:00

- hypothesis: the green-button rects are not published (greenButton offset nil / wrong) so nothing can match
  evidence: AX green buttons read fine (offset 46,6 16x16 for TextEdit/Terminal, 58,18 for Safari, inside the frame); a press with the field preset to the real window ID was swallowed and toggled (722 floated, 578 docked), so rects[id] contains the point.
  timestamp: 2026-10-26T16:07:00-05:00

## Evidence

- timestamp: 2026-10-26T16:05:00-05:00
  checked: Sources/PaneMac/Input/InputTap.swift:130-145, GreenButton.swift, CGWindowList.swift:18-23, ArrangeController.swift:212-242,308-318
  found: the callback reads mouseEventWindowUnderMousePointer; when it is 0 and the press is inside some published rect it calls CGWindowList.topmostWindow(at:) = first on-screen (excludeDesktopElements) entry with pid != Pane, alpha > 0, bounds containing the point. NO layer filter. shouldSwallow needs rects[thatID] to contain the point and no Option. The drag path's pressWindow(underPointer:at:) does the same scan but with `entry.layer == 0`.
  implication: a fallback-supported design exists; it fails if any non-zero-layer window of another process covers the point.

- timestamp: 2026-10-26T16:10:00-05:00
  checked: VM /tmp/gbprobe (AX AXZoomButton/AXFullScreenButton rects per window + topmost CG window at the button centre, same CG options as topmostWindow) and /tmp/cglist (on-screen front-to-back)
  found: every window's green button is readable (TextEdit/Terminal offset 46,6 16x16; Safari 58,18 16x16; inside the frame, so greenButton is published). The topmost on-screen window at EVERY button centre is `Dock#7 pid 362 layer 20 alpha 1 bounds 0,0 1024x768` (the Dock's full-screen window; VM Dock is not auto-hidden). Front-to-back list: menu-bar items (layer 25), Menubar (24), Dock#7 (20, full screen), Pane gap handles (3, own pid), then the layer-0 app windows.
  implication: topmostWindow(at:) returns 7 for any point below the menu bar, rects[7] is nil, so no plain press is ever swallowed. The drag fallback survives only because it filters layer 0.

- timestamp: 2026-10-26T16:12:00-05:00
  checked: Arranger.swift:271-276 (.greenButton), 1052-1066 (release with no travel), 541-570 (moved)
  found: .greenButton -> Dock on floating, Float on docked (intent matches TILE-06). With Option the press passes (TILE-19); the press still starts a drag session on the window (pressWindow uses the layer-0 scan). A no-travel release answers a frame change as the app's own (D-33): a floating window's new frame is clamped by the Planner into the Desktop tile; a docked window off its tile is corrected back into it (correct()).
  implication: Option is NOT inverted. An Option-click zoom is performed by macOS and then constrained by Pane: docked -> pulled back into its tile; floating -> zoomed frame clamped to the Desktop tile, which can look exactly like "it docked".

- timestamp: 2026-10-26T16:03:00-05:00
  checked: VM, /tmp/wclick (CGEvent down/up at the hid tap, optionally presetting mouseEventWindowUnderMousePointer + ...ThatCanHandleThisEvent), Pane drag debug log streamed around each press
  found: (a) preset 722 on docked TextEdit 722's green (652,51): no press line, 722 floated (layout: TextEdit#722 floating, neighbours reflowed). (b) preset 578 on floating 578 (later run): no press line, 578 docked (598,37 143x326). (c) no preset, plain press on docked 202's green (66,389): log `start com.apple.TextEdit window 202 (CG 7, member 202)`, 202 went full screen (0,0 1024x768 + toolbar window).
  implication: the swallow and toggle work whenever the tap has the right window ID; with field 0 the fallback yields 7 (the Dock) and the press passes to macOS.

- timestamp: 2026-10-26T16:04:00-05:00
  checked: real HID pointer through VNC ($S/vnc.py), log streamed: title-bar press on 202 at (300,389), then green press at (66,389)
  found: title-bar press `CG 0`; green press `CG 7`, 202 entered full screen
  implication: the field is 0 for real HID clicks too, so the user's hand clicks take the same broken fallback. Matches report items 1/2 (macOS 15 plain green click = full screen, read by the user as "maximises").

- timestamp: 2026-10-26T16:05:00-05:00
  checked: Option-click (injx oclick) on docked 202 and floating 722, frames at +0.3 s and +3 s
  found: 202: press logged (CG 7), +0.3 s 1,64 975x648 (native zoom), +3 s back at its tile 12,375 574x326. 722 (floating, Desktop tile 12,37 574x326): +0.3 s 2,27 950x629 (native zoom), +3 s clamped back to 12,37 574x326
  implication: item 3 is D-33 working as specified (03-01-PLAN D-33 / 03-13-PLAN truth: floating keeps the zoom, clamped into the Desktop rect if it crosses a docked tile; docked snaps back). With any docked tile on screen the zoom is visible for well under a second and the end state looks like a dock.

- timestamp: 2026-10-26T16:06:00-05:00
  checked: Dock autohide on (defaults write + killall Dock), CG list, then autohide key deleted again + killall Dock
  found: Dock#838 layer 20 0,0 1024x768 still topmost at every button with autohide on; Dock#843 after restore
  implication: not an autohide artefact; any macOS 15 session with the Dock has the overlay.

- timestamp: 2026-10-26T16:09:00-05:00
  checked: tests and history: Tests/PaneEngineTests/ArrangerGreenButtonTests.swift, GreenButton tests, Tests/PaneMacIntegrationTests/ButtonFrameIntegrationTests.swift; 03-13-SUMMARY deviation 1
  found: shouldSwallow is tested with the windowID passed in; topmostWindow(at:) has no test and is not a pure function; the live test checks only that the AX green rect lies in the title bar. 03-13 added the fallback after 03-11 found field 0, and left the end-to-end check to end-of-phase UAT.
  implication: why not caught: no gate exercised the tap's window lookup against a real on-screen list.

- timestamp: 2026-10-26T16:12:00-05:00
  checked: side observation after my `killall Dock` (confounded, not part of this gap)
  found: a preset-ID press on floating 722 left it at macOS Fill (0,25 1024x688), and Pane then stopped answering 722's frame changes (AX moves to 100,100 800x500 and 150,150 700x400 not clamped) while 578 and 202 were still clamped/corrected. Not investigated further; log for that press was not captured. 722 was put back inside the Desktop tile by AX.
  implication: possible separate bug in per-window frame answering (maybe lastApplied/lastRequested dedupe or a lost per-window AX observation, cf. G-03-5); worth a look only if it reproduces without a Dock restart.

## Resolution

root_cause: "Items 1/2: CGWindowList.topmostWindow(at:) (Sources/PaneMac/CGWindowList.swift:20-23), the tap's fallback when the session tap reports window 0 (always, HID or injected), takes the first on-screen window of another process containing the point with no layer filter. On macOS 15 that is the Dock's full-screen layer-20 window (CG 7), so InputTap passes id 7, GreenButton.shouldSwallow finds no rects[7], and the plain click reaches macOS (full screen). Item 3: not an inversion; Option passes through as designed, macOS zooms, and D-33 snaps a docked window back into its tile / clamps a floating one crossing a tile into the Desktop rect, which reads as docking."
fix:
verification:
files_changed: []

## Reopened 2026-10-27

<!-- The sections above are the 2026-10-26 session (fixed by 03-18 + CR-01). Everything below is the reopened investigation. -->

### Symptoms (reopened, immutable)

expected: a plain green-button click with the real mouse floats docked Notes / docks floating Notes (TILE-06)
actual: Pane 0.3.8 (HEAD code), Tart VM macOS 15.7.7, user's real mouse in the Tart window: plain click on docked Notes' green button (Space 41, Notes window 150), twice: only the macOS 15 "Move & Resize / Fill & Arrange / Full Screen" hover popup appears; Notes neither floats nor docks. Option-click works (zoom, D-33 return). A menu over the green button gets the click. Notes is floating on Space 41 now (cause unknown).
errors: none
reproduction: hover the green button like a human (popup shows), then click
started: after 03-18 + CR-01 (ae5560e); Claude-driven instant injected / VNC clicks passed

### Current Focus (reopened)

bug_class: Bohrbug (deterministic: every toggle on a desk whose only docked window is the clicked one)
hypothesis: CONFIRMED (H2). The tap takes the human-pattern click and Pane toggles Notes, but in the user's layout neither toggle changes anything on screen. Notes was the only docked window on Space 41: float keeps it at its tile rect (the Desktop rect the undock leaves is the whole area, so the clamp is a no-op) and dock-at-centre puts it back on the same right tile at the same frame. The only window that changes is the gap handle, which is drawn at opacity 0. The macOS hover popup stays up because the swallowed press never reaches it, so "only the popup appears" is all the user can see.
next_action: none (goal find_root_cause_only); hand to plan-phase --gaps
reasoning_checkpoint:
  hypothesis: "The user's plain clicks were taken and toggled float/dock, but in that layout (Notes the lone docked window, floaters only beside it) Arranger.float and Arranger.dock leave every window frame unchanged, so a working toggle is invisible"
  confirming_evidence:
    - "VM, exact screenshot layout (Notes docked 370,37 642x664, Reminders 12,25 768x692, Calculator floating): human-pattern hover 1.5 s + click -> layout.json Notes floating, all frames byte-identical; second click -> docked, frames identical; only Pane#2459 (gap handle, opacity 0) appears/disappears"
    - "VM, Pane paused (no rects published), same hover + click with the popup up -> Notes enters full screen (new Space 116): a click Pane does NOT take is visible. The user saw no full screen, so Pane took both presses"
    - "The user's next check (Option-click zoom, D-33 returns it to its tile) needs Notes DOCKED, which matches float + dock (two invisible toggles)"
  falsification_test: "a press that Pane passes through would full-screen Notes (shown above); a press Pane takes but does not toggle would leave layout.json unchanged. Either observation in the exact layout would refute H2; neither occurred"
  fix_rationale: "the fault is the missing observable, not the tap: give the toggle a visible result (or a cue) even when no sibling tile reflows, and make the UAT check read a state that changes"
  blind_spots: "no real HID click was observed by a probe (Tart pointer events not reproducible from inside the guest); the user's history is reconstructed, and why Notes ended floating after the hand session is unknown (odd number of taken presses, e.g. a third click, or a host first-click swallowed by Tart, or a later command)"
  candidate_causes:
    - "code/spec: Arranger.float keeps the tile rect, Arranger.dock of a lone floater restores the same tile, no feedback effect (confirmed)"
    - "code: CR-01 topmost() returns nil when the hover popup owns the point (eliminated: popup 57,59 / 396,71 never contains the button centre; injected human-pattern clicks are taken)"
    - "environment: Tart real-pointer events differ from CGEvent posts (not refuted directly; refuted indirectly: a pass-through is visible as full screen, the user saw none)"
    - "code: press taken but toggle refused (eliminated: rects and the .greenButton guards use the same conditions; layout.json toggled every time)"
  and_gate: "yes: (1) the clicked window is the only docked window on its desk, so no sibling reflows; (2) float/dock keep the frame by spec (TILE-09 float at the tile rect; D-12 dock at the centre drop); (3) Pane has no other float/dock cue (gap handle invisible until hovered). Remove any one and the toggle is visible (cf. 2026-10-26: 722 floated and its neighbours reflowed)"

### Evidence (reopened, append only)

- timestamp: 2026-10-27T14:20:00-05:00
  checked: VM Space 41, Notes 150 floating at 31,25 642x664, AX zoom/full-screen button 89,43 16x16 (centre 97,51); injected `move` onto the centre with Notes NOT frontmost, 2 s, CG on-screen list
  found: no popup appears and no new window is listed when Notes is not the active app
  implication: the hover popup needs the window's app active (the user's screenshot shows Notes active)

- timestamp: 2026-10-27T14:22:00-05:00
  checked: same, after an injected click in Notes' sidebar (Notes frontmost), `move` onto 97,51, 2 s, CG list front-to-back
  found: the popup is `ThemeWidgetControlViewService#2494 pid 12242 layer 101 alpha 1 bounds 57,59 224x212` (a separate XPC service process, not Notes, not Dock), listed first. Its bounds start at y 59, i.e. at the button's bottom edge; they do NOT contain the button centre 97,51. Dock#843 layer 20 full-display is next, then Notes#150 layer 0.
  implication: at the button centre CR-01's topmost() still skips the Dock overlay and returns 150. H1 holds only for the bottom row of the button (y = 59, if the rect is half-open at 59). Need the press itself.

- timestamp: 2026-10-27T14:06:00-05:00
  checked: VM Space 41, Notes 150 FLOATING at 31,25 (active app), injected `move` to the button centre, ~2 s with the popup up, then an injected click at 97,51
  found: Notes DOCKED (12,37 642x664, Reminders reflowed to 666,25); popup stayed on screen and moved with the window (38,71)
  implication: a press arriving while the popup is up is still taken and toggled; the hover delay alone does not break the tap path for CGEvent posts

- timestamp: 2026-10-27T14:07:00-05:00
  checked: same, popup up, injected click on docked Notes' button (81,63 inside 70,55 16x16); log stream around it
  found: Notes became FLOATING in layout.json, frame unchanged 12,37 642x664; no drag-log press line (a swallowed press logs none)
  implication: docked -> float also works with the popup up

- timestamp: 2026-10-27T14:09:00-05:00
  checked: rebuilt the user's exact screenshot state (7.png measured: Notes at 370,37 642x664, Reminders 12,25 768x692 behind it): axset Notes to 370,37 642x664, instant green click -> layout `docked ['Notes#150'] floating [reminders, calculator]`, Desktop tile 12..358 (gap handle Pane#2459 358,37 12x664). Then human pattern: move away, move onto 436,63 in 3 steps, 1.5 s (popup up at 396,71), click; then again (1 s hover, click)
  found: click 1: layout -> Notes FLOATING; every frame byte-identical before/after (Notes 370,37 642x664, Reminders 12,25 768x692, Calculator 122,184 198x350); only change on screen: the 12-pt gap handle window 2459 disappears. Click 2: layout -> Notes DOCKED again; frames again identical; gap handle back. Popup stays up throughout (the swallowed press never reaches the popup service).
  implication: H1 ELIMINATED for this layout: the tap takes the human-pattern click and Pane toggles. NEW H2: both of the user's clicks may have worked: with Notes the only docked window on its desk, float keeps the window at its tile rect (Arranger.float, TILE-09 "at its tile rect, clamped into the Desktop rect the undock leaves" -> the whole area) and dock-at-centre (Arranger.dock, D-12) puts it back on the same right tile, so neither toggle moves anything; the still-visible macOS popup is the only thing the user sees

- timestamp: 2026-10-27T14:12:00-05:00
  checked: VM, Pane paused (ctrl-opt-cmd-P, no rects published), Notes docked at 370,37, human-pattern hover (popup 2494 up), plain click on 436,63; then unfs Notes and resume
  found: Notes entered full screen (Notes 150 0,0 1024x768 + toolbar window 2496, Space 116 created). After unfs + resume: back at 370,37 642x664, docked, Space 116 gone.
  implication: a plain click that Pane does not take is plainly visible even with the popup up. The user saw no full screen on either click, so Pane's tap took both of the user's presses; the real-HID-path difference cannot have made them pass through

- timestamp: 2026-10-27T14:14:00-05:00
  checked: Sources/PaneEngine/Arranger.swift:302-307 (.greenButton -> .dock / .float), 765-790 (dock at the centre drop, D-12), 792-811 (float: tile rect clamped into the Desktop rect the undock leaves, TILE-09, line 807); Sources/PaneMac/Overlay/GapHandlePanels.swift:27 (handle layer opacity 0 until hovered); 03-CONTEXT B ("Dock, or the green button, on a floating window: docks it where a drop at its centre would land"); Tests/PaneEngineTests/ArrangerGreenButtonTests.swift (button == command world, no visibility check); 2026-10-26 evidence (722 floated, neighbours reflowed)
  found: by design a float moves nothing itself; the change is only visible through siblings reflowing into the freed tile. With no other docked window the undock leaves Desktop rect == area, clamp(tile) == tile; docking a lone floater gives it the side tile at its own frame. No announce, flash or border marks either state. The swallowed press also leaves the macOS hover popup up (it never sees the click), so the popup is the only thing on screen that reacts.
  implication: the reopened symptom is a missing observable, not a dropped click. The UAT step tested on a layout where success and failure look identical

- timestamp: 2026-10-27T14:15:00-05:00
  checked: why Notes was floating after the hand session; persisted Pane log (info level) 13:48-14:05
  found: no persisted lines after "session resumed" at 13:48 (Pane's drag/press lines are debug level, not kept). The Option-click check passing ("returns it to its tile") needs Notes docked at that point, i.e. an even number of taken presses before it.
  implication: unexplained, not needed for this gap: an odd number of taken presses (a third click, or a Tart host first-click that never reached the VM) or a later command floated it. My runs left Notes DOCKED at 370,37 642x664 on Space 41; VM back on Space 1; Pane 12113 still running.

### Eliminated (reopened, append only)

- hypothesis: H1, the macOS 15 hover popup (or its tracking window) owns the button point at a layer above 0, so CR-01's topmost() returns nil and the press passes
  evidence: the popup is one window, ThemeWidgetControlViewService (separate pid) layer 101, anchored BELOW the button (57,59 / 38,71 / 396,71 224x212), never containing the button centre; injected presses with the popup up were taken and toggled 4/4 (dock, float, float, dock)
  timestamp: 2026-10-27T14:09:00-05:00

- hypothesis: H3, the user's real Tart pointer clicks are not taken (window field / location differ from CGEvent posts) and pass to macOS
  evidence: a pass-through click with the popup up full-screens Notes (paused-Pane run); the user saw no full screen on either click
  timestamp: 2026-10-27T14:12:00-05:00

- hypothesis: H4, the press is taken but the toggle is refused (trackedWindow nil or the .greenButton guard)
  evidence: layout.json flipped on every taken press in the exact layout; the published rect and the guard share the conditions (dockable, not excluded, present, on a desk, not paused)
  timestamp: 2026-10-27T14:10:00-05:00

### Resolution (reopened)

root_cause: "Not a dropped click. Pane takes the plain press and toggles (layout.json flips every time, also with the hover popup up), but on the user's desk the toggle has no visible effect: Notes was the only docked window on Space 41, so Arranger.float (Sources/PaneEngine/Arranger.swift:792-811, frame = clamp(tile, into: Desktop rect) at 807, where the Desktop rect becomes the whole area) leaves it exactly where it was, and Arranger.dock (765-790, D-12 drop at its centre) puts the floater back on the same tile at the same frame. No sibling reflows, the gap handle that comes and goes is drawn at opacity 0 (Sources/PaneMac/Overlay/GapHandlePanels.swift:27), and Pane has no float/dock cue. Because the press is swallowed, the macOS 15 hover popup never sees it and stays up, so the popup is the only reaction the user sees. A press Pane does not take would full-screen Notes, which the user did not see."
fix:
verification:
files_changed: []
