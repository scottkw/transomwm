---
status: diagnosed
trigger: "G-03-6 (major), UAT test 15: Reminders' fixed-size Welcome window (768x692, not resizable) docked beside Notes on Space 2 stays 768 wide at (12,25), overlapping Notes at x 370, and sits 12pt into the top gap"
created: 2026-10-26T15:00:00-05:00
updated: 2026-10-26T16:05:00-05:00
goal: find_root_cause_only
audit_acknowledged:
  milestone: v0.9.0
  at: 2026-11-08
  status: diagnosed
---

## Current Focus

bug_class: Bohrbug (deterministic: any window already at its minimum when Pane first shrinks it)
hypothesis: CONFIRMED - Pane's only "can't fit" signal is a learned minimum, and MinimumSizeLearner never learns one for a window whose first write it refuses entirely (read-back == pre-write size). Reminders sits at its 768x692 minimum, so every write reads back unmoved, nothing is learned, resolve() never marks it unfit, and it keeps 768pt in a 167pt tile over Notes. Its 692pt height is also inside the 32pt refusalMargin of the 664pt tile and taller than the 688pt visible frame, which is why AppKit pins it at y=25.
next_action: none (goal find_root_cause_only); hand to plan-phase --gaps
known_pattern_candidate: none (KB holds only safari-toolbar-drag-no-dock, unrelated)
reasoning_checkpoint:
  hypothesis: "A docked window bigger than its tile overlaps its neighbour because MinimumSizeLearner.recordWrite rejects a refusal whose read-back did not move from the pre-write size (actual < before - 2 fails), so no minimum is ever learned, Planner/resolve get no minimum for it, and nothing else compares the read-back with the tile"
  confirming_evidence:
    - "VM, Space 2: docked Notes then Reminders -> tree [Desktop | Reminders | Notes], Reminders' tile (191,37 167x664); read-back (191,25 768x692) overlapping Notes at x 370; min-size-hints.json gains no Reminders entry after > 3 s (confirmDelay is 1 s)"
    - "VM axprobe: the same size,position,size sequence returns success for every call and reads back 768x692 whatever smaller size is asked; 900 wide is honoured, so the window is resizable with min 768x692 and starts AT that minimum"
    - "The rule and its known limit are written down: MinimumSizeLearner doc comment, commit 7c97838, 02-REVIEW-FIX.md:147 ('a window that opens already larger than its tile, where Pane's first write is a shrink the app refuses entirely, now learns nothing from that write')"
  falsification_test: "if a Reminders hint had appeared in min-size-hints.json (or learnedMinimum set) after the dock and the window still overlapped, the cause would be downstream (resolve/planFloatingLostRoom), not the learner"
  fix_rationale: "the planner can only float what it knows is too big; giving it the window's real size (learning from an unmoved but repeated/confirmed refusal, or checking the read-back against the tile) addresses the missing signal, not the symptom"
  blind_spots: "did not instrument Pane to log applyFrameResult (no rebuild); the learner's behaviour on these numbers is from code reading plus the absent hint. Did not test a truly non-resizable window (AXSize unsettable); Reminders turned out to be resizable with a large minimum"
  candidate_causes:
    - "code: MinimumSizeLearner move gate (actual < before - 2) - confirmed primary"
    - "code: refusalMargin 32 pt - the 28 pt height refusal (692 vs 664) is never a candidate - confirmed secondary"
    - "code: no safety net comparing a docked window's read-back to its tile rect - confirmed contributing"
    - "environment: 1024x768 VM with visible Dock (visible frame 688 tall) - explains y=25 only; ruled out as the cause of the overlap (width 768 overflows a 167 tile on any display)"
    - "code: FrameWriter aborting on an AXSize error (H2) - eliminated"
  and_gate: "yes, partly: the overlap needs (1) a tile smaller than the window's real minimum (normal) AND (2) no learned minimum (the learner gate) AND (3) no read-back check. Fixing (2) alone is enough for the width here; the height would still slip through the 32 pt margin"

## Symptoms

expected: A docked window that can't fit its tile floats to the Desktop tile instead of overlapping a neighbour (core value: windows never overlap)
actual: Claude-driven UAT in the Tart VM on Space 2: Reminders' fixed-size Welcome window (768x692, not resizable) was docked beside Notes. It stays 768 wide at (12,25), overlapping Notes at x 370, and sits 12pt into the top gap (top of the tile area should be ~37 or 49 on a 1024x768-point screen with a menu bar)
errors: none reported
reproduction: VM pane-test, Space 2, Notes and Reminders docked side by side; Reminders shows its fixed-size Welcome window
started: first seen in phase 3 UAT (Pane 0.3.1 build of HEAD 5d83032)
related: test 14 side effect - a new floating Safari window on the Desktop tile widened the Desktop/TextEdit column 494 -> 574pt

## Eliminated

- hypothesis: H2 - FrameWriter's AXSize set errors on a non-resizable window and aborts before AXPosition, so the window is never moved
  evidence: VM /tmp/axprobe on Reminders 693 - AXSize and AXPosition are settable, zoom and fullscreen buttons enabled, and all three sets of FrameWriter's size,position,size sequence return 0 (success). The window is not non-resizable; it has a large minimum
  timestamp: 2026-10-26T15:58

## Evidence

- timestamp: 2026-10-26T15:50
  checked: Sources/PaneEngine/MinimumSizeLearner.swift recordWrite, WindowTracker.applyFrameResult
  found: a write is a refusal candidate only when actual > requested + 32 AND actual < before - 2 (the window moved toward the request), or the same clamp was seen on a previous write that moved. `before` is the tracked frame size. The doc comment states the known limit - "a window first written while already at its minimum does not move, so it is learned only after a later write moves it". A fixed-size window is always at its minimum and never moves
  implication: a non-resizable window can never get a learnedMinimum
- timestamp: 2026-10-26T15:51
  checked: Sources/PaneModel/Resolve.swift, Sources/PaneEngine/Planner.swift, Arranger unfit paths (Arranger.swift ~1367-1390)
  found: unfit (and so float-to-Desktop) is decided only from `mins`, which are the learned minimums (Arranger.swift:1400 builds them from info.learnedMinimum). No other input (read-back size, AXSize settable, buttons) feeds it
  implication: without a learned minimum the 768pt window is planned into its ~346pt tile and nothing ever notices the read-back is wider
- timestamp: 2026-10-26T15:52
  checked: Sources/PaneEngine/Classifier.swift, grep for settable/resizable/AXGrowArea
  found: nothing in Sources checks AXSize settability, AXGrowArea or resizability. The classifier only uses layer, subrole, modal, close button and fullscreen button; and while a sheet is attached (reliable=false) it returns dockable without checking anything
  implication: a non-resizable window is not recognised as fixed-size anywhere
- timestamp: 2026-10-26T15:53
  checked: Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop
  found: the live test resizes both fixture windows 40pt above their minimum first "so a refused tile write moves them toward it: that is how a minimum is learned (02-15)". The fixture windows are .resizable with a minSize
  implication: the only covered case is a resizable window with a minimum; a fixed-size window is untested
- timestamp: 2026-10-26T15:54
  checked: Sources/PaneMac/AX/FrameWriter.swift
  found: writes AXSize, AXPosition, AXSize; the first AX error stops the sequence and returns failure with no read-back; WindowTracker.applyFrameResult ignores a failed write entirely
  implication: if AXSize set errors on a non-resizable window, the position is never written either (would explain y=25 staying put)
- timestamp: 2026-10-26T15:55
  checked: VM state now - layout.json, /tmp/allapps, min-size-hints.json, Pane log
  found: Pane relaunched at 20:42 UTC (pid 3696); the Space 2 desk in layout.json is now empty; Reminders 693 at (12,25 768x692) and Notes 150 at (370,37 642x664), both on Space 2. min-size-hints.json has Notes width 642 and Safari width 574 but no Reminders entry. Pane logs no frame writes at info level
  implication: Notes' minimum was learned (resizable), Reminders' never was
- timestamp: 2026-10-26T15:58
  checked: VM Space 2, /tmp/axprobe Reminders with FrameWriter's exact sequence and read-back (Pane tracks both windows as floating on the Space 2 desk, no tiles, so it does not answer)
  found: request (12,37 346x664) -> read-back (12,25 768x692); (100,60 900x600) -> (100,25 900x692); (100,60 500x500) -> (100,25 768x692). Every AX call returned success. So Reminders' Welcome window is resizable with minimum 768x692 (width can grow, height cannot go below 692). The visible frame is y 25..713 (menu bar + Dock), the tile area 37..701 = 664 tall. A 692pt window cannot sit at y >= 37 inside it, so AppKit pushes it up to y=25 (the menu bar edge), whatever y Pane writes
  implication: y=25 is AppKit constraining a window taller than the tile area, not a failed or skipped write. The window's real minimum (768 wide, 692 tall) does not fit a 346x664 tile on either axis
- timestamp: 2026-10-26T15:59
  checked: MinimumSizeLearner.recordWrite against those numbers
  found: width: actual 768 > requested 346 + 32, but `before` (tracked size) is already 768, so actual < before - 2 fails and there is no candidate. Height: actual 692 is NOT > requested 664 + 32 = 696, so the 28pt height refusal is inside refusalMargin and is never a candidate even for a window that moved
  implication: two independent gates in the learner reject this refusal; nothing is learned, so resolve() never sees a minimum and never marks Reminders unfit
- timestamp: 2026-10-26T16:01
  checked: VM reproduction with Pane 0.3.1 (pid 3696) on Space 2 - click Notes, Ctrl-Opt-Cmd-D; click Reminders, Ctrl-Opt-Cmd-D; frames, layout.json and min-size-hints.json 3 s later
  found: both docked; tree horizontal [Desktop, Reminders 693, Notes 150], equal weights; Notes takes its learned 642 min, Desktop and Reminders share the rest -> Reminders' tile (191,37 167x664). Reminders reads (191,25 768x692), overlapping Notes (370,37 642x664). min-size-hints.json still has no Reminders entry. Dock's D-26 pre-check (Arranger.swift:812) passed because `minimums` has no Reminders entry
  implication: reproduced the gap exactly; the minimum is never learned, so neither the dock refusal nor planFloatingLostRoom can fire
- timestamp: 2026-10-26T16:02
  checked: NSScreen in the VM
  found: frame 1024x768, visibleFrame y 55..743 (top-left 25..713), 688 tall. Reminders' minimum height 692 > 688
  implication: the window is taller than the whole visible frame; AppKit pins its top at the menu bar (y=25) whatever Pane writes. Not Space-2 specific
- timestamp: 2026-10-26T16:03
  checked: Planner.plan desktopMinimum, Resolve tests aDesktopMinimumLargerThanTheAreaGetsTheWholeArea, Arranger.planFloatingLostRoom
  found: the Desktop tile's minimum is the max of its floating windows' learned minimums; a Desktop minimum larger than the area makes every docked window unfit, and planFloatingLostRoom repeats until all fit
  implication: test 14's 494 -> 574 widening is this same, designed rule working (Safari's learned 574 width, in min-size-hints.json). It is not the G-03-6 cause. But once Reminders' 768x692 is learned and it floats, its 692 height exceeds the 664 inner height, so Notes (and any docked window on that desk) would float too - the fix must decide that case

## Resolution

root_cause: MinimumSizeLearner.recordWrite only takes a refusal when the read-back moved toward the request (actual < before - 2, added in 7c97838 against late appliers). Reminders' Welcome window opens at its 768x692 minimum, so Pane's tile write (167x664) reads back unmoved, no candidate is made, no minimum is ever learned, and resolve()/Planner (which judge fit only from learned minimums) never mark it unfit; the Dock pre-check and planFloatingLostRoom therefore never float it, and nothing compares the read-back to the tile. Secondary: its height refusal (692 vs 664 asked) is under the 32 pt refusalMargin, so it would not be learned even after a move; and 692 exceeds the 688 pt visible frame, so AppKit pins the window at y=25.
fix:
verification:
files_changed: []
