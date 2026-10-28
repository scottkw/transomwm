---
status: diagnosed
trigger: "G-03-11 (UAT test 3 re-check, Pane 0.3.8, VM): dragging the gap between docked Finder 2399 (top) and the Desktop tile down shrank the floating windows; dragging it back up left them small (Finder 546/580/2252 460x252, TextEdit 132 tall, Terminal 127 tall, all at y 569) and some end below the screen's bottom edge"
created: 2026-10-27T09:00:00-05:00
updated: 2026-10-27T09:45:00-05:00
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (deterministic: reproduced exactly in the engine with the fake window system; no timing needed)
status_note: two independent causes confirmed in the engine; diagnose-only, no source changed (experiments ran on a scratch copy)
reasoning_checkpoint:
  hypothesis: "A (stay small): a floating window has one stored frame (DesktopLayer FloatingWindow.frame). It is both 'where the window is' and the only frame Pane can return to. Arranger.moved records every frame event of a floating window as that frame at Arranger.swift:639, BEFORE the 'Pane's own write' check at 642. So when a gap drag shrinks the Desktop, Planner clamps the floater (Planner.swift:55-57), Pane writes the clamp, the app's read-back echoes back as windowMoved/windowResized, and line 639 stores the clamped (or refused) frame. Each later step clamps from that, and when the Desktop grows back the stored small frame overlaps no tile, so nothing grows it. B (off screen): during a live drag the Desktop tile's minimum (per-axis max of floaters' learned minimums, Planner.swift:30) does not include the floaters' real minimum heights. The drag shrinks the Desktop below them, the app refuses the clamp height and the window hangs below the Desktop and the screen. Planner clamps only floaters that overlap a docked tile (Planner.swift:55), so this one is never clamped again, even once the Desktop has room for it."
  confirming_evidence:
    - "Probe (Harness + FakeWindowSystem, VM-like 1024x768, Desktop bottom 701): after the down drag and the up drag, all three floaters end at y 571 (VM: 569): Finder 460x252 bottom 823 (VM 821), Safari 574x224 bottom 795, TextEdit 729x130 (VM 132). After every live step the stored frame equals the read-back (recorded == screen). The up drag writes only the docked window"
    - "E1 (scratch copy, only change: line 639 skips the echo of Pane's own write): the same sequence ends with every floater back at its exact start frame (Finder 40,390 460x300 etc.). Restored also with minimums known (E3+E1)"
    - "E3 (real tree, the floaters' real minimums fed as learnedMinimum): the gap drag stops with the Desktop at 252 tall (docked tile bottom 437); nothing ends below the Desktop or the screen. The grow-back still leaves them shrunk (Finder 460x252, TextEdit 729x252), so A and B are independent"
    - "Learner probe (hand-speed: 400 ms per step, a refresh after each, plus a refresh 2 s after mouse-up): nothing is learned (mins=[] throughout). Every refusal past the first is an 'unmoved' repeat, which needs another write >= 1 s later (MinimumSizeLearner.swift:63-72). That write never comes, because the stored refused frame no longer overlaps a tile, so Pane never re-sends it"
  falsification_test: "A: if line 639 were not the overwrite, E1 (skip only that record for Pane's own echoes) would still leave the floaters small after the grow-back. It does not; they return exactly. B: if the off-screen overflow were caused by A or by the clamp math, E3 (minimums known, A unchanged) would still overflow. It does not; the Desktop stops at 252 and every floater stays inside."
  fix_rationale: "A: keep the frame the user wanted separate from the frame Pane shows, and derive the shown frame every plan as clamp(wanted, into: Desktop rect). Then shrink and grow are both views of one unchanged record. The echo stays a fact about the real frame (Arranger.windows already holds it) and is not stored as intent. B: make the Desktop tile's minimum cover a floater's real size (a refused floater clamp counts as its minimum right away, or the refusal retry docked windows get is extended to floaters so the learner confirms it), so the drag's cut (boundaryChange) stops there. Also re-clamp a floater whose shown frame leaves the Desktop rect, not only one that crosses a tile."
  blind_spots: "Not reproduced in the VM (the orchestrator holds it). The probe uses fake minimums (252/224/70) chosen to match the report. Whether Finder/Safari in the VM had learned or hinted minimum heights before the drag is unknown, but the 132 pt Desktop shows none above 132 was in effect. Other Desktop-shrinking paths (dock beside the Desktop, edge resize, display or gap change) go through the same planShown -> echo -> line 639 path by code reading, not probed. Did not design the wanted-frame storage (where it lives once a window docks, persistence, undo)."
  candidate_causes:
    - "code: Arranger.moved records Pane's own clamp echo as the floater's frame (A, confirmed by E1)"
    - "code: Planner clamps only floaters overlapping a docked tile, so an overflow below the Desktop/screen is never corrected (B, contributing, by probe + code)"
    - "data/learning: floaters' minimum heights are unknown during a live drag. The learner needs an unmoved repeat >= 1 s later, which the stored refused frame prevents (B, confirmed by learner probe + E3)"
    - "code (eliminated): recordFloatingFrame(clamped) at Arranger.swift:647 / 1244 / 415 (only off-plan user moves, drag misses, rescue; none runs in this sequence)"
    - "environment (eliminated): app-specific grid snap (Terminal 127 < 132 request is a smaller read-back; teaches nothing, not an overflow)"
  and_gate: "no for 'stays small' (A alone, E1). Yes for 'ends below the screen': it needs the Desktop shrunk below an app's real minimum (unknown minimum, B) AND the Planner never re-clamping a floater that overlaps no tile; A then keeps the overflowing frame stored after the grow-back"

## Symptoms

expected: Floating windows keep the size the user gave them; a Desktop tile that shrinks and grows back returns them to that size, and none ends off screen
actual: after a gap drag down (Desktop shrinks) and back up (Desktop grows), the floaters stay small and low: all at y 569 (Finder 546/580/2252 460x252, TextEdit 202 729x132, TextEdit 578/722/567 143x132, Terminal 256x127, Safari 574x224); several end below the visible bottom (display 1024x768 pt; 569+252=821)
errors: none
reproduction: Tart VM, Pane 0.3.8, Space 1 desk: Finder 2399 docked at the top, Desktop tile below holding ~9 floaters (Safari, Terminal, TextEdit, Finder). Drag the Finder|Desktop gap down, then back up
started: seen in the 2026-10-27 UAT re-check of test 3 (after the G-03-3 fixes made the gap drag smooth)

## Eliminated

- hypothesis: the overwrite is recordFloatingFrame(clamped) at Arranger.swift:647 (moved), 1244 (missed) or 415 (showParkedDesktops) (the lead's call sites)
  evidence: 647 runs only when the frame is NOT within 2 pt of Pane's last read-back (line 642 returns first), i.e. a user move; 1244 is a floating drag released off a target; 415 is Restore All / crash rescue. None runs in a gap drag. E1 changed only the record at 639 and fully restored the frames
  timestamp: 2026-10-27T09:30:00-05:00

- hypothesis: Planner.clamp computes a wrong origin (windows pushed below the screen by Pane itself)
  evidence: every clamp Pane wrote ends at the Desktop's bottom (701): Finder requested (40,571 460x130). The window ends at 823 only because the app keeps 252 of height (fake hiddenMinimum, like the VM's Finder). Pane never asked for a frame below the Desktop
  timestamp: 2026-10-27T09:20:00-05:00

- hypothesis: an over-learned minimum shrinks or pins the floaters
  evidence: mins=[] in every probe dump; nothing was learned (see learner probe). Terminal's 127 (< 132 request) is a smaller read-back, which teaches nothing
  timestamp: 2026-10-27T09:25:00-05:00

## Evidence

- timestamp: 2026-10-27T09:05:00-05:00
  checked: knowledge-base.md and sibling sessions (g-03-3-gap-drag, g-03-6-fixed-size-window-overlap)
  found: no entry about floating frames; G-03-3 notes the Desktop tile minimum is the per-axis max of learned floater minimums (Planner.swift:30) and that floater minimums are learned only after a 1 s confirming refresh
  implication: no known-pattern candidate; the learner's delay is relevant to why a live drag can shrink the Desktop under a floater's real minimum

- timestamp: 2026-10-27T09:10:00-05:00
  checked: Planner.plan (Planner.swift:51-58), Planner.clamp (63-69), Arranger.moved (Arranger.swift:629-658), WindowTracker.applyFrameResult (WindowTracker.swift:312-326), replan(with:on:) (Arranger.swift:1265-1270), planShown floating loop (1446-1454)
  found: (1) the model keeps one frame per floater (DesktopLayer FloatingWindow.frame). Planner clamps a floater only when that frame overlaps a docked tile, and clamps FROM it. (2) Pane's own write comes back as frameApplied (sets lastApplied, Arranger.swift:523) then windowMoved/windowResized (WindowTracker.swift:321-323). moved() records the frame as the floater's frame at line 639 BEFORE the own-write check at 642, so every clamp Pane writes is stored. That includes live drag steps, though the live plan runs on a transient World copy (the echo lands on the committed World). (3) Once stored, the clamped frame overlaps no tile, so no later plan touches it. planShown's 'not where the model has it' loop only moves a floater to its stored frame, which is now the small one
  implication: lead mechanism plausible, at line 639 rather than 647/1244/415

- timestamp: 2026-10-27T09:20:00-05:00
  checked: temporary probe Tests/PaneEngineTests/ZZDiagG311Tests.swift (now at scratchpad g311/ZZDiagG311Tests.swift), test shrinkThenGrowTheDesktopByAGapDrag. Harness + FakeWindowSystem (real WindowTracker, echoes as live). Display 1024x768, visible (0,37 1024x676), gap 12. Window 10 docked at the top (V[10, Desktop]); floaters Finder-like (min 460x252) at 40,390 460x300, Safari-like (min 574x224) at 420,400 574x290, TextEdit-like (min 143x70) at 270,420 729x260. Gap dragged down +50/+100/+150/+190 live, released, then a new handle dragged -50..-190, released. `swift test --filter ZZDiagG311Tests/shrinkThenGrowTheDesktopByAGapDrag`: 1 test ran, passed. Output in scratchpad g311/g311-run.txt
  found: live +50: Pane writes Finder 40,431 460x270; stored = 40,431 460x270. +100: request 220 tall, Finder reads back 252 -> stored 40,481 460x252. +190: requests 40,571 x130 for all, read-backs Finder 460x252 (bottom 823), Safari 574x224 (bottom 795), TextEdit 729x130. Up drag -50..-190: setFrames only for the docked window 10. Final, with the Desktop back at 12,381 1000x320: Finder 40,571 460x252 bottom 823, Safari 420,571 574x224 bottom 795, TextEdit 270,571 729x130; stored == screen for all. VERDICT: none back to start; Finder and Safari off screen
  implication: the user's shape reproduced headlessly (all at one y = the shrunken Desktop's top; the apps' minimum heights hang below the screen; nothing grows back)

- timestamp: 2026-10-27T09:25:00-05:00
  checked: probe learnedMinimumsAfterTheShrink: the same drag at hand speed (fake and Arranger clocks +400 ms per step, a refresh after each step, then +2 s and a refresh after mouse-up, then the up drag)
  found: mins=[] at every dump; refreshes caused no writes. Finder: +100 request 220, read-back 252 is not > 220+32 (no refusal). +150 and later are 'unmoved' refusals (before = 252 = actual), so only a Clamp record is kept. It becomes a candidate only when a write >= 1 s after the first record reads back the same, and none follows, because the stored frame 40,571 460x252 overlaps no tile and Pane never re-sends it. Final frames are the same as the first probe
  implication: the Desktop tile's minimum never learns Finder's/Safari's heights from this drag, so nothing stops the next drag either. The record at 639 also starves the learner of the repeat it needs

- timestamp: 2026-10-27T09:30:00-05:00
  checked: E1 on a scratch copy (scratchpad g311/e1tree, patch g311/e1-moved-no-echo-record.patch): moved() computes `own = lastApplied near frame within 2` and skips recordFloatingFrame when own (Arranger.swift:639/642). Same probe, run there
  found: during the shrink the stored frames stay at the start frames while the screen shows the clamps (Finder screen 40,571 460x252, stored 40,390 460x300). After the up drag every floater is back exactly: Finder 40,390 460x300, Safari 420,400 574x290, TextEdit 270,420 729x260; VERDICT back to start=true, offScreen=false for all three. Finder still hung to 823 while the Desktop was shrunk (B unaffected)
  implication: A confirmed: the echo record at line 639 is what loses the size

- timestamp: 2026-10-27T09:32:00-05:00
  checked: probe knownMinimumsBoundTheDrag (E3, real tree): the floaters' real minimums fed as WindowInfo.learnedMinimum before the drag; then E3 in the E1 copy too
  found: real tree: the down drag is cut at +68 (Desktop 12,449 1000x252, docked bottom 437); every floater ends at y 449, bottom 701, inside the Desktop and the screen. After the up drag they stay 252 tall (Finder 460x252 instead of 460x300, TextEdit 729x252 instead of 260). E1 copy: the same cut, and the up drag restores the exact start frames
  implication: B confirmed independent of A: with the minimums known, boundaryChange's cut keeps the Desktop >= the floaters' heights and nothing overflows. A still loses the size

- timestamp: 2026-10-27T09:38:00-05:00
  checked: Chesterton's fence for line 639: PaneEngineTests + PaneModelTests on the E1 copy (512 tests); then a fence probe (ZZDiagG311FenceTests, in both trees) of TooBigDockedWindowTests' setup
  found: one regression, TooBigDockedWindowTests.aDockedWindowAlreadyAtAMinimumWiderThanItsTileIsRetriedOnceThenFloats (2 issues, 3/3 runs; passes on the real tree). Fence probe: after a docks, b's clamp is refused (b stays 783 wide). Baseline stores b at 724,312 783x300 (the read-back) and Dock b gives H[a, Desktop, b] (children n1, n0, n3). E1 stores 600,312 (the frame before the clamp), so dock (Arranger.swift:772) reads a planned clamp narrower than the real window. Its centre is elsewhere, and Dock b gives H[a, n4] (a new split under the old Desktop column) with b 783x425 at the top
  implication: line 639 is load-bearing: the stored frame is also 'where and how big the window really is' (dock's centre at 772, Planner's overlap test at Planner.swift:55, planShown at 1451). Dropping the echo record is not a fix. The intent (wanted frame) and the fact (real frame, already in Arranger.windows[id].frame) need separate records

- timestamp: 2026-10-27T09:42:00-05:00
  checked: cleanup
  found: both probe files moved out of the tree (ZZDiagG311Tests.swift to scratchpad g311/, ZZDiagG311FenceTests.swift copy kept there); e1tree/.build deleted; git status shows only the pre-existing .planning changes plus this file
  implication: no source or test change left in the repo

## Resolution

root_cause: "A (stay small): a floating window has one stored frame (DesktopLayer FloatingWindow.frame), and Arranger.moved (Sources/PaneEngine/Arranger.swift:639) overwrites it with every frame event, including the echo of Pane's own clamp write. It does this before the own-write check at 642. During a gap drag that shrinks the Desktop tile, Planner.plan clamps each floater that now overlaps the growing docked tile (Planner.swift:55-57). The read-back of that write, clamped or refused by the app, becomes the stored frame on the committed World, although the live plan itself runs on a transient copy. When the Desktop grows back, the stored small frame overlaps no tile, so no plan enlarges it. The frame the user gave the window is gone. B (ends off screen): during a live drag the Desktop tile's minimum (per-axis max of learned floater minimums, Planner.swift:30) does not know the floaters' real minimum heights, so the drag shrinks the Desktop below them (132 pt in the VM). The app refuses the clamp height (Finder 252, Safari 224), and the window hangs below the Desktop and the screen. Planner re-clamps only floaters that overlap a docked tile (Planner.swift:55), so it is never corrected. The learner cannot catch up: these are 'unmoved' refusals that need a repeat write >= 1 s later (MinimumSizeLearner.swift:63-72), and A stops Pane from ever re-sending it."
fix: ""
verification: ""
files_changed: []
