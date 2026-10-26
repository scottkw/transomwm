---
status: diagnosed
trigger: "G-03-3 (UAT test 3): Dragging the gap between two tiles resizes both tiles smoothly and the new split sticks -- user: 'Pass, but the gap drag is a little janky. It sometimes goes back to the way it was. Sometimes one of the windows won't let you drag in a particular direction.'"
created: 2026-10-26T15:00:00-05:00
updated: 2026-10-26T16:30:00-05:00
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (H1: deterministic geometry) + Bohrbug with a timing-dependent trigger (H2: deterministic once any window event or off-plan frame event lands mid-drag; whether one lands depends on the app and refresh timing)
status_note: both root causes confirmed in the engine and in the VM; diagnose-only, no code changed
reasoning_checkpoint:
  hypothesis: "Two independent causes. H1: Arranger.boundaryChange turns the drag delta into weight and cuts it to what the shrinking side loses on screen. When the growing side is already held at a minimum above its weight share, the weight shift is absorbed by that pin, so the dragged gap does not move (2 children) or a different boundary moves (3+ children). H2: the live gap drag exists only inside Arranger.replan(with:on:) for one gapDrag call. Any other replan() during the drag (a window event, a title change, an off-plan frame -> correct, a tick) lays out the committed World and writes the pre-drag tiles and handles. They stay on screen until the next mouse-dragged event or mouse-up."
  confirming_evidence:
    - "Engine diag: a pinned at 700 (share 469). Gap +20..+300: a stays 700, b shrinks 354 -> 267, Desktop grows, one undo step each. Unpinned control moves as expected."
    - "VM: root gap H[column pinned 729 / weight share 494, Terminal 259 / min 165]. Injected drag +50: no frame changes. Control drag on the unpinned vertical gap moves both TextEdits by exactly 50."
    - "Engine diag: mid-drag windowResized(stale frame) or windowChanged(new title) re-sends the pre-drag tiles (469/469) and the pre-drag handle x. Mouse-up then writes the drag result again."
    - "VM sampler (5 ms) during a hand-speed root-gap drag with Terminal: twice the whole desk went back to its exact pre-drag frames (TextEdit 494, Terminal 518/494). The second time the pointer was held still: the frames stayed reverted for about 1.4 s and came back only at mouse-up."
  falsification_test: "H1: if the weights were re-based to the laid-out sizes before the delta is applied, the +50 VM drag would move Terminal to 209 wide. If it still did not move, H1 would be wrong. H2: if pre-drag frames show up mid-drag even when replan() during a drag includes the live change, H2 would be wrong."
  fix_rationale: "H1: re-base the split's weights to its resolved child sizes (or apply the delta in points to the resolved sizes) before cutting, so the stored weights match the screen in both directions. H2: keep the live gap-drag change in Arranger state (e.g. a pending boundary move applied by every replan until mouse-up, as edge resizes keep `drag`), so a mid-drag replan plans the live layout, not the committed one."
  blind_spots: "Did not instrument which exact event fired each VM snap-back (Terminal's title 'cols x rows' changing on resize, or a stale refresh frame vs frame result ordering). Both are shown to snap back in the engine. Did not reproduce the user's own layout from test 3. Did not test the tap-path contributor (a docked window spilling into a gap becomes the press window)."
  candidate_causes:
    - "code: boundaryChange cut logic ignores pin offset (H1, confirmed)"
    - "code: live gap-drag state not held by Arranger, so replan() reverts (H2, confirmed)"
    - "data/environment: Desktop tile minimum = max learned minimum of floating windows (Safari 574, Finder 460) on a 1024-pt VM, which pins columns above their weight share and makes H1 common (contributing condition)"
    - "environment: app behaviour that emits events during resizes, e.g. Terminal's title change and grid snap (triggers H2)"
    - "code (lower confidence, not reproduced): pressWindow CG fallback picks a docked window that spills into the gap, starting a DragSession. Pane then never writes that window mid-drag, and a resize-classified session blocks gapDrag"
  and_gate: "no for the gap as a whole: H1 and H2 are independent and each explains a different reported symptom. Each needs a contributing condition: H1 needs a min-pinned growing side; H2 needs some event mid-drag."

## Symptoms

expected: Dragging the gap between two tiles resizes both tiles smoothly and the new split sticks
actual: gap drag is a little janky; it sometimes goes back to the way it was; sometimes one of the windows won't let you drag in a particular direction
errors: none reported
reproduction: Tart VM pane-test, macOS 15.7.7, Pane 0.3.1; two docked windows (TextEdit/Terminal) on Space 1; drag the gap handle between them by hand
started: first seen in phase 3 UAT (build 5d83032)

## Eliminated

- hypothesis: the gap-handle hit test or drag start uses CGWindowList.topmostWindow(at:) / the tap's window-under-pointer field (G-03-4)
  evidence: the handle is an AppKit NSPanel (GapHandlePanels.HandleView mouseDown/Dragged/Up); no CG hit test is involved, and injected drags reach it in the VM (control drag moved exactly 50 pt)
  timestamp: 2026-10-26T15:10:00-05:00

- hypothesis: the snap-back is a lost mouse-up commit (ended never reaches Arranger.gapDrag)
  evidence: engine and VM both show that mouse-up writes the drag result after a mid-drag revert (VM: reverted at 4134 ms, restored at mouse-up at ~5582 ms); the revert itself comes from a mid-drag replan() on the committed World
  timestamp: 2026-10-26T16:20:00-05:00

- hypothesis: an over-learned minimum (late applier) clamps the drag
  evidence: min-size-hints.json unchanged by all drags; a drag into TextEdit's real 70 pt minimum learned nothing (32 pt refusal margin + 'not moved' rule). The VM's frozen root gap is explained by H1 with correct minimums (Terminal 165, TextEdit 143, Safari 574 hint)
  timestamp: 2026-10-26T16:10:00-05:00

## Evidence

- timestamp: 2026-10-26T15:05:00-05:00
  checked: knowledge-base.md
  found: one entry (safari-toolbar-drag-no-dock), unrelated to gap handles
  implication: no known-pattern candidate

- timestamp: 2026-10-26T15:10:00-05:00
  checked: gap-drag path: GapHandlePanels.HandleView (mouseDown/Dragged/Up -> onDrag(handle, delta since press, ended)) -> ArrangeController.init onDrag (one Task per event) -> Arranger.gapDrag (Arranger.swift:1347) -> boundaryChange (1194) -> replan(with:on:) (1161, transient World copy, defer restores committed) / on ended world.edit + replan()
  found: the gap handle is a pure AppKit panel path; it does not use the session tap, CGWindowList.topmostWindow or the window-under-pointer field. A press in the gap gives pressWindow nil (no layer-0 tracked window in the gap), so no DragSession starts and gapDrag's `drag?.kind == nil` guard passes
  implication: G-03-4's hit-test bug does not touch the gap handle

- timestamp: 2026-10-26T15:15:00-05:00
  checked: VM state: layout.json + /tmp/frames + min-size-hints.json
  found: Space 1 root H[73, Terminal 160] weights 0.5/0.5; 73 = V[83, TextEdit 202]; 83 = H[Desktop, TextEdit 578] 0.5/0.5. Frames: column 73 is 729 wide (12..741) although its weight share is 494; Desktop tile 574 (floating Safari 669 hint 574); TextEdit 578 143 (its hint min); Terminal 256 (tile 259, hint min 165). All weights 0.5 but geometry fully min-pinned
  implication: the stored weights do not describe the screen; any gap whose growing side is pinned hits the cut logic below

- timestamp: 2026-10-26T15:25:00-05:00
  checked: temporary engine test Tests/PaneEngineTests/ZZDiagGapDragTests.swift (H[a,b,Desktop], a min 700 > its 469 share; deleted after)
  found: dragging the a|b gap right by 20/50/100/150/200/300: a stays 700 (handle does not move), b shrinks 354 -> 350/346/337/326/313/267 and the Desktop grows, i.e. the b|Desktop boundary moves instead; each commit adds an undo step. Delta -50: nothing (a at its min, correct). Unpinned control: +50 gives a 519/b 419 as expected
  implication: H1 confirmed in the engine. With 2 children (VM root split) water-filling gives the loser the remainder regardless of weight, so `after == before`, room 0, cut 0, boundaryChange returns nil: the gap is frozen in that direction even though Terminal has 94 pt above its minimum

- timestamp: 2026-10-26T15:25:00-05:00
  checked: same temporary test, echo case: live gapDrag +30 then +60, then .windowResized(a, the +30 frame) (a refresh that read write 1 after write 2's request)
  found: Arranger wrote a = 469 and b = 469 (the pre-drag tiles) and re-sent the handles at the pre-drag x (477). The ended event then wrote the +60 frames again
  implication: H2 confirmed in the engine: any off-plan frame event mid-drag snaps the whole desk back to the committed layout until the next drag event; later off-plan events inside 1 s are deferred to a tick that does the same

- timestamp: 2026-10-26T15:30:00-05:00
  checked: AXWindowSystem event plumbing (frameWritten via per-thread frameResults Task; refresh via scheduler -> thread.observe -> ingest; both hop to MainActor separately)
  found: a refresh observation and a frame write result for the same window reach the tracker in no guaranteed order. A refresh that read frame N, ingested after result N+1, makes WindowTracker emit windowResized/windowMoved(N) (tracker frame N+1 != N), with lastApplied = N+1 and lastRequested = N+k
  implication: the stale event H2 needs is produced by ordinary refresh/write interleaving during a live drag (every write fires AX moved/resized notifications -> hints -> refreshes)

- timestamp: 2026-10-26T16:00:00-05:00
  checked: VM, injected drag of the root gap (x 747) right by 50 (Space 1 layout as found: column 73 pinned at 729 by Desktop 574 + 12 + TextEdit 578 143; Terminal 256/259, hint min 165)
  found: /tmp/frames identical before and after. Control: the same injector on the unpinned vertical gap (y 369 -> 419) moved TextEdit 202 to y 425 h 276 and TextEdit 578 to h 376, i.e. exactly 50
  implication: H1 reproduced in the real app. The root gap cannot move right although Terminal has 94 pt above its minimum, and it cannot move left either (column at its aggregate minimum), so it is frozen both ways

- timestamp: 2026-10-26T16:05:00-05:00
  checked: VM, hand-speed (3 pt per 16 ms) drag of the TextEdit-only vertical gap down 100, up 150, down 100, hold 1.5 s, with a 5 ms CGWindowList sampler (/tmp/sampler, /tmp/pathdrag)
  found: both TextEdit windows followed smoothly and stayed in lockstep; no reversion; final layout committed
  implication: H2 needs a trigger; TextEdit alone does not provide one in this run

- timestamp: 2026-10-26T16:10:00-05:00
  checked: VM, drag into TextEdit 202's real minimum height (gap to y 660) and hold 3 s
  found: TextEdit stops at h 70 while the gap keeps going (requested 35); it then extends 35 pt past the visible frame bottom. No minimum learned (each step refused by < 32 pt, then 'not moved'); hints file unchanged
  implication: the learner path (G-03-6 known limit) does not trigger H2 here. The overlap it leaves is G-03-6's, not this gap's. Layout dragged back afterwards

- timestamp: 2026-10-26T16:20:00-05:00
  checked: VM, Desktop tile hidden (pane://toggle-desktop) so the root gap is unpinned; hand-speed drag of the root gap (TextEdit column vs Terminal) right 138, left 250, right 160, hold 1.5 s, sampled at 5 ms
  found: Terminal follows in 7 pt column steps with x in 3 pt steps, so its right edge jitters 1006..1025 against the 1012 tile edge (cosmetic jank). At sampler 3420 ms both windows jumped to the exact pre-drag frames (TextEdit 202 w 494; Terminal 518/494) and recovered at 3434 with the next drag event. At 4134-4149 ms, with the pointer held still at the end, both went back to the pre-drag frames again and stayed there until mouse-up at about 5582 ms, when the drag result (TextEdit 542, Terminal 566/445) was written
  implication: H2 reproduced in the real app: 'it sometimes goes back to the way it was' is the whole desk reverting to the committed layout mid-drag, most visibly while the user holds still before releasing

- timestamp: 2026-10-26T16:22:00-05:00
  checked: temporary engine test, windowChanged(new titleHint) for a docked window mid-drag (Terminal's title carries 'cols x rows' and changes on every column change; WindowTracker emits windowChanged when titleHint changes, WindowTracker.swift:186)
  found: Arranger re-sent the pre-drag tiles (a 529 -> 469, b x 545 -> 485)
  implication: every window event that reaches Arranger.handle(_ event:) ends in `hidden + replan()` (Arranger.swift:515) on the committed World. Terminal's title is a realistic trigger, alongside stale or off-plan frame events (moved -> correct -> replan) and correction ticks

- timestamp: 2026-10-26T16:25:00-05:00
  checked: Arranger.release(now:) and pressWindow fallback (ArrangeController.pressWindow, layer-0 CG window containing the point, Rect.contains half-open)
  found: a press in the gap starts a DragSession only if a tracked layer-0 window's bounds contain the press point (a window spilling into the gap). If that happens, replan skips writing that window until mouse-up (`if window == drag?.window { continue }`), and if its frame changes by > 1 pt it is classified .resize, after which gapDrag's `drag?.kind == nil` guard drops every gap event including mouse-up
  implication: a third, layout-dependent contributor (not reproduced): a window at its minimum or a grid-snapped window that spills into the gap would freeze one side and could lose the commit

- timestamp: 2026-10-26T16:30:00-05:00
  checked: cleanup
  found: temporary test deleted (git status shows only the pre-existing planning changes plus this file); VM root gap dragged back and the Desktop shown again: frames identical to the start, all Space 1 weights 0.5, min-size-hints.json byte-identical to the copy taken before (/tmp/hints-before-g033.json in the VM). /tmp/sampler and /tmp/pathdrag left in the VM as helpers
  implication: no lasting change to the repo or the VM layout

## Resolution

root_cause: "H1 (won't drag one way): Arranger.boundaryChange (Sources/PaneEngine/Arranger.swift:1194) converts the drag's points into weight against the split's laid-out length, then cuts the move to what the shrinking side actually loses on screen. When the growing side is held at a minimum above its weight share (common: the Desktop tile's minimum is the largest learned minimum of its floating windows, e.g. Safari 574 / Finder 460 on a 1024-pt display), the weight shift first has to make up the gap between weight share and pinned size before anything moves. The cut then shrinks the move to the loser's (zero or small) on-screen change. With 2 children the gap is frozen; with 3+ the wrong boundary moves (the loser shrinks from its far side and a third child grows), and an undo step is still recorded; H2 (goes back / janky): the live gap drag is never Arranger state. It exists only inside replan(with:on:) (Arranger.swift:1161) for one gapDrag call, with `defer { world = committed }`. Any other replan() before mouse-up lays out the committed World and writes the pre-drag tiles and handles for the whole desk: every window event (Arranger.handle(_ event:) ends in `hidden + replan()`, e.g. Terminal's 'cols x rows' title change), an off-plan frame event (moved -> correct -> replan, Arranger.swift:569), or a correction tick. The revert stays until the next mouse-dragged event or mouse-up."
fix: ""
verification: ""
files_changed: []
