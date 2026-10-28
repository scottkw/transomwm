---
status: diagnosed
trigger: "Live test ArrangeIntegrationTests.aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop fails in the Tart VM (1024x768, macOS 15.7.7): 'window 0 did not float clear of window 1 within 5 s (fixture frames [])'. Fails identically at 53d5faa and a38a405."
created: 2026-10-26T00:00:00Z
updated: 2026-10-26T00:00:00Z
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (deterministic given the VM geometry)
hypothesis: CONFIRMED - test bug. Dock puts window 1 ABOVE the Desktop tile (vertical split [1 / Desktop] in the right column), not in the row. [0 | [1 / Desktop]] fits (554 + 8 + 440 = 1002 <= 1008), so nothing loses room and window 0 correctly stays docked; the guard desk.desktop.contains(refs[0]) never passes. Window 1 is exactly as wide as the Desktop tile, so its centre fx = 0.5 and Planner.dockTarget's nearest-edge choice is a tie decided by a sub-point vertical offset. In the VM the Arranger's area is 689 tall (odd) while the test's `visible` is 688 (read at test start), so fy != 0.5 and the edge is top/bottom
next_action: none (goal find_root_cause_only); hand back. All temporary test edits reverted
known_pattern_candidate: none
reasoning_checkpoint:
  hypothesis: "The live test fails because its window 1 placement (x = Desktop.minX, width = Desktop width, centre at the test's mid-height) makes Dock's nearest-edge choice a fx = 0.5 tie; with the Arranger's 689 pt area fy = 0.49926, so Dock splits the Desktop vertically, the layout fits, and no window loses room"
  confirming_evidence:
    - "Run 1 (original test + prints): after Dock the tree is horizontal [win0 | vertical [win1 / Desktop]]; window 1 tile (570,33,446,332) accepted; min1 never learned; Desktop layer empty for 6 s"
    - "Run 2 (only change: window 1 centre at 0.8 of the Desktop width, the right edge band): tree [win0 | Desktop | win1], window 1 refused 219 -> 440, min1 learned, window 0 floated to (8,33,554,673), window 1 retiled (570,33,446,673), test PASSED in 11.9 s"
  falsification_test: "If Pane's D-26 path were broken, run 2 (row dock) would also fail; it passed"
  fix_rationale: "Make the test's Dock target unambiguous (and assert it) instead of relying on a tie; Pane needs no change"
  blind_spots: "Host failure (UAT 18, DELL attached) not re-run (forbidden on host); the 688 -> 689 change is most likely the VM Dock shrinking 1 pt after the fixture's icon appears, not verified"
  candidate_causes:
    - "code (test): window 1 placement leaves Dock's edge choice on a tie (confirmed)"
    - "environment: test reads the visible frame once at start; the Arranger later plans in a 1 pt taller area (confirmed, contributing)"
    - "code (Pane): planFloatingLostRoom / learner broken (eliminated by run 2)"
  and_gate: "no - the tie alone fails it whenever the area height is odd or differs from the test's; the stale visible frame is just what makes the VM odd-height"

## Symptoms

expected: After window 1 docks beside window 0, [0 | 1 | Desktop] doesn't fit (min0 + min1 + gaps > inner), so planFloatingLostRoom floats window 0 to the Desktop tile and 0/1 stop overlapping (D-26)
actual: waitUntil guard never passes: frames [] -> desk.desktop.contains(refs[0]) false, or tree.state(of: refs[1]) != .present, or desk key gone. All #require before pass (min learned, clamp, window 1 docked)
errors: "Expectation failed: floated — window 0 did not float clear of window 1 within 5 s (fixture frames [])"
reproduction: scripts/vm-live-test.sh ArrangeIntegrationTests/aDockedWindowThatTurnsOutTooBig (VM only, never host)
started: fails at 53d5faa (before 03-20..03-22) and at HEAD a38a405; UAT 18 assumed host failure was second-display sizing, VM shows it is not

## Eliminated

- hypothesis: Pane's D-26 path (min learning from the refused tile, planFloatingLostRoom, 03-21 Desktop-minimum rule) fails to float window 0 live
  evidence: run 2, with window 1 docked in the row, learned min1 = 440 and floated window 0 within ~2 s; the test passed
  timestamp: 2026-10-26T00:25:00Z
- hypothesis: window 1 was floated/undocked instead of window 0
  evidence: run 1 shows window 1 present in the tree in every poll and the Desktop layer empty
  timestamp: 2026-10-26T00:10:00Z
- hypothesis: second-display / main-display sizing (UAT 18 assumption)
  evidence: VM has one display and fails the same way; the decisive factor is the Dock edge tie
  timestamp: 2026-10-26T00:10:00Z

## Evidence

- timestamp: 2026-10-26T00:00:00Z
  checked: knowledge-base.md
  found: only entry is safari-toolbar-drag-no-dock; no keyword match (too big, float, lost room, minimum)
  implication: no known pattern

- timestamp: 2026-10-26T00:10:00Z
  checked: VM run with temporary DIAG prints (world JSON, tracked frames, learned minimums, fixture frames) at learned0, clamp, before/after dock 1 and every 500 ms for 6 s
  found: test visible = (0,25,1024,688), inner 1008, min0 554, min1 440. Arranger's display visibleFrame = (0,25,1024,689) (1 pt taller). Window 0 tile (8,33,554,673), min0 learned 554. Window 1 clamped to (570,120,446,300), then moved to (570,219,446,300). After Dock: tree root 2 = horizontal [panel1(win0) | split4], split4 = VERTICAL [panel3(win1) / desktop]. Window 1 tile (570,33,446,332), accepted (446 >= 440), so min1 never learned (nil in every poll). Desktop layer empty for all 6 s; frames stable
  implication: guard failing is desk.desktop.contains(refs[0]); window 1 docked in a column above the Desktop, not in the row, so [0 | [1 / Desktop]] needs 554 + 8 + 440 = 1002 <= 1008 and fits. No lost room exists; Pane is right not to float window 0

- timestamp: 2026-10-26T00:12:00Z
  checked: Planner.dockTarget + DropZones.target arithmetic with the observed numbers
  found: Window 1 centre (793, 369). Arranger Desktop rect (570,33,446,673): fx = 223/446 = 0.5 exactly (window as wide as the Desktop tile), fy = 336/673 = 0.49926. Centre zone -> nearest edge: min(fx,1-fx)=0.5 <= min(fy,1-fy)=0.49926 is false -> vertical, fy < 0.5 -> .top -> insert above the Desktop. With the test's own 688-tall area the Desktop centre is 369, fy = 0.5, the tie goes horizontal (<=) -> .right -> row. With any odd-height area, (midY - 150).rounded() moves the centre 0.5 pt off and the dock is vertical too
  implication: the test's "centre at mid-height -> same row" assumption is a knife-edge tie; it holds only if the test's area equals the Arranger's and its height is even. Test bug, not a Pane bug

- timestamp: 2026-10-26T00:13:00Z
  checked: git log of DropZones.swift (last change 01-05) and Planner.dockTarget (03-04)
  found: neither changed in 03-20..03-22
  implication: explains the identical failure at 53d5faa and a38a405; the 03-21/03-22 changes are downstream of the dock decision and never run in this scenario

- timestamp: 2026-10-26T00:25:00Z
  checked: VM run 2, temporary edit only to start1.x (window 1 centre at Desktop.minX + 0.8 * Desktop.width, right edge band) plus visible-frame prints
  found: mainVisibleFrame() = 688 tall at test start, after FixtureProcess.launch and right after arranging() (Arranger also 688 then); by learned0 the Arranger's display is 689 tall and stays so. Dock -> horizontal [win0 | Desktop | win1] (weights 1/3). Window 1 tile refused, read back (797,33,440,673); ~2 s later min1 = 440 learned, win0 floated to the Desktop at (8,33,554,673), tree [Desktop | win1], win1 (570,33,446,673). Test passed in 11.866 s
  implication: Pane's D-26 path works live; the only failing piece is the test's ambiguous Dock placement. The test's `visible` goes stale by 1 pt during the test (cause most likely the VM Dock resizing after the fixture's icon appears; unverified)

## Resolution

root_cause: Test bug, not a Pane bug. aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop places window 1 at x = Desktop.minX with the Desktop tile's full width (Pane clamped it to 446 pt), so its centre is exactly at the Desktop's horizontal middle (fx = 0.5). Planner.dockTarget turns a centre-zone point into the nearest edge with min(fx,1-fx) <= min(fy,1-fy); with fx = 0.5 the row (left/right) wins only if fy is exactly 0.5. The test computes mid-height from a visible frame read at test start (688 pt), but Pane plans in 689 pt by then, so fy = 0.49926 and Dock inserts window 1 above the Desktop (vertical split). [0 | [1 / Desktop]] fits (554 + 8 + 440 = 1002 <= 1008), window 1's tile (446 wide) is accepted, min1 is never learned, nothing loses room, and window 0 correctly stays docked, so the guard desk.desktop.contains(refs[0]) never passes. Independent of 03-20..03-22.
fix: (diagnose only) Make the Dock target in the row unambiguous in the test and assert it; no Pane change
verification: VM run 2 with only window 1's placement changed (centre in the Desktop's right edge band) passed
files_changed: []
