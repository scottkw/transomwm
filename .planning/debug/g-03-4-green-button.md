---
status: diagnosed
trigger: "G-03-4: plain green-button click maximises (docked and floating) instead of toggling dock/float; Option-click green docks instead of zooming natively. User: 'Seems you might have them backwards'."
created: 2026-10-26T16:00:00-05:00
updated: 2026-10-26T16:15:00-05:00
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
