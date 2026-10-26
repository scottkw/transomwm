---
status: resolved
trigger: "Phase 3 gap: Safari windows do not dock when dragged by their unified toolbar title area; TextEdit docks fine (03-REVIEW.md WR-03, 03-VERIFICATION.md)."
created: 2026-10-26
updated: 2026-10-26
---

## Current Focus

bug_class: was assumed Bohrbug (deterministic per app); the live log shows it does not reproduce at all
hypothesis: none open. (a), (b) and (c) are all eliminated by the live log
next_action: none. Closed as not reproducible at bb67b5d; the new-window auto-dock observation went to 03-VERIFICATION.md as UAT item 19

## Symptoms

expected: dragging a Safari window by its unified toolbar onto an edge or tile shows the dock preview after the 150 ms dwell and docks it on release, as TextEdit does
actual: Safari stays floating, with no preview and no refusal; TextEdit docks correctly
errors: none logged
reproduction: Pane 0.3.0 in the pane-test Tart VM; drag a Safari window by its toolbar title area onto the TextEdit tile or a screen edge, hold, release
started: observed live on the 0.3.0 build (deferred-items 03-17); drag-to-dock is new in Phase 3

## Eliminated

- hypothesis: (a) no leftMouseDragged reaches the tap during a Safari toolbar drag, so the press never travels
  evidence: Safari toolbar drags logged dragged 23, 32 and 421 events, travel 169-370 pt, polling true (16:09:47, 16:09:49, 16:10:24)
  timestamp: 2026-10-26
- hypothesis: (b) Safari's CG bounds differ in size from its AX frame, so the first sample classifies the press as resize
  evidence: every Safari press logged AX start == CG start exactly (e.g. 8,33 574x517 both); first CG samples keep the start size; the two resize classifications started at Safari's bottom-right corner (574,357 for a window ending at 582,364; 1013,354 for one ending at 1016,364) and the size really changed (574x331 -> 753x520), so they are real resizes
  timestamp: 2026-10-26
- hypothesis: (c) a Safari press starts no session (press not mapped to a tracked window, or canDrag refuses it)
  evidence: every Safari press on its window logged a "start" line (windows 54, 114, 115); the "no tracked window" lines were presses off any tracked window (y 726-734 is below the 703-pt visible frame, so the Dock; the others hit no tracked window)
  timestamp: 2026-10-26

## Evidence

- timestamp: 2026-10-26
  checked: Sources/PaneEngine/Arranger.swift pointer(_:now:), release(now:); Sources/PaneEngine/DragSession.swift observe
  found: a session is classified only after `travelled` (pointer from .dragged/.flagsChanged only); the poll starts only after travel; `observe` compares CG/AX sample sizes against the AX startFrame within 1 pt; release with kind nil takes the app's-own-move path, kind .resize on a floating window takes the miss path
  implication: (a) and (b) both produce "stays floating, no preview"; a third branch (c), no session at all, does too
- timestamp: 2026-10-26
  checked: Sources/PaneMac/ArrangeController.swift handle(_ TapEvent), pressWindow(underPointer:at:)
  found: the press window is resolved by CG window number under the pointer mapped through `visibleMemberID ?? windowID`, with a front-to-back bounds fallback; a nil press or canDrag false starts no session silently
  implication: the start log must record whether a session started, not only its frames
- timestamp: 2026-10-26
  checked: instrumentation commit bb67b5d (ArrangeController category "drag" logger; DragSession.decisionSummary); check-no-appkit OK; swift test PaneModelTests|PaneEngineTests|PaneMacTests
  found: "Test run with 448 tests in 49 suites passed"; Release build signed, DR identifier com.eightabyte.pane + team S2K7P43927 unchanged
  implication: instrumentation is safe to deploy
- timestamp: 2026-10-26
  checked: pane-test VM (macOS 15.7.7) after replacing /Applications/Pane.app (zip sha256 c16d78e0...) and relaunching (pid 1175)
  found: log shows "permission notTrusted -> probing" then "probing -> ready" within 0.11 s, the same path as the previous launch (pid 1007); no error-level lines; Safari (911) and TextEdit (933) running
  implication: the Accessibility grant survived the binary swap (same designated requirement); the drag log is ready to capture
- timestamp: 2026-10-26
  checked: live drag log, 16:09:18-16:11:51, scratchpad drag-stream.log (user dragged Safari by its toolbar and TextEdit in the VM)
  found: Safari 114 at 16:09:47 "kind move travel 169.6 dragged 23 polls 18 ... decision dock(DeskKey(...), tile(n0, edge(top))) shown dock(8,33 574x331)"; Safari 115 at 16:10:24 "kind move ... dragged 421 polls 319 dry runs 7 decision dock(..., tile(n14, edge(left))) shown dock(224,33 574x670)"; Safari 114 at 16:09:49 "decision miss shown snapBack" (docked window released over its own tile: snap-back by design); TextEdit 111/119 docked on a tile edge, the layout edge and a nested tile edge; clicks (kind nil, travel 0) did nothing
  implication: Safari docks by drag at bb67b5d; the reported gap does not reproduce
- timestamp: 2026-10-26
  checked: the "CG <n>" field of every press line
  found: windowUnderPointer is 0 for every press in the VM, so pressWindow always resolved through the CGWindowList front-to-back fallback (which matched every time)
  implication: not a bug, but the fast path is never used in the VM; worth knowing if press resolution is ever suspected again
- timestamp: 2026-10-26
  checked: user report and VM layout.json after the drags
  found: layout H[Desktop, V[TextEdit, Safari]], nothing floating; user: "Once TextEdit is docked Safari automatically docks to another position and doesn't remain floating. Dragging it to the edge of TextEdit just changes its dock position." The log shows Safari docked only by user drags (16:09:47, 16:10:24); window 114 was replaced by 115 at the identical frame 8,33 1008x331 between 16:09:54 and 16:09:58
  implication: a separate question, not this gap: possibly a re-key keeping the slot, or a new window put into a tile (would contradict TILE-07). Recorded as UAT item 19 in 03-VERIFICATION.md

## Resolution

root_cause: unknown; not reproducible at bb67b5d. The 0.3.0 observation came from the same 03-17 run that hit WR-02 (tracking and the tap did not start until a relaunch), so the most likely explanations are drags made before the tap was running, or drops outside every drop zone (a miss leaves a floating window floating with no preview after the dwell). A side effect of the review fixes (CR-01 undo re-admit, WR-01 Space lookup) is possible but unproven
fix: none needed. Drag logging kept at debug level (category "drag") for the next report
verification: live VM drag log: Safari toolbar drags classify move and dock with the preview shown; 448 headless tests pass; check-no-appkit OK
files_changed: [Sources/PaneEngine/DragSession.swift, Sources/PaneMac/ArrangeController.swift] (diagnostics only: bb67b5d, 936da6c)
oracle_type: specified (the drop preview and the docked layout from UI-SPEC Surface 2)
