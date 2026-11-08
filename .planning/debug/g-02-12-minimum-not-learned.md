---
status: diagnosed
trigger: "g-02-12-minimum-not-learned: A refused frame write should teach Transom the window's real minimum. Min Size should show it about a second later, and min-size-hints.json should store it per bundle."
created: 2026-10-27T20:00:00-05:00
updated: 2026-10-27T20:40:00-05:00
audit_acknowledged:
  milestone: v0.9.0
  at: 2026-11-08
  status: diagnosed
---

## Current Focus

bug_class: Bohrbug (deterministic: an at-minimum window's single refused write is never learned)
hypothesis: CONFIRMED - the UAT setup made Nudge's write an "unmoved" refusal (Notes already at 642x324 = its minimum, read-back == pre-write size). By design (WR-01 0c148fb / 7c97838 / G-03-6 c48e1b8 / CR-02 5a65a9a) MinimumSizeLearner learns nothing from one unmoved refusal, needs the same clamp repeated >= 1 s later (Nudge's next press restores instead, so it never repeats), and never persists an unmoved minimum. The learning pipeline itself works (live positive control).
next_action: none (diagnose only); return ROOT CAUSE FOUND

reasoning_checkpoint:
  hypothesis: "Nothing was learned because Notes sat exactly at its minimum, so Nudge's 578x260 request read back 642x324 == its pre-write size: MinimumSizeLearner.recordWrite treats that as an unmoved refusal, records only a clamp and makes no candidate, so no confirm refresh, no learnedMinimum, no windowChanged, no onLearnedMinimum and no hints file. Nudge's next press restores the old frame (a non-refusal that clears the clamp), so the >= 1 s repeat the unmoved path needs never comes; and an unmoved minimum is session-only by CR-02, so the hints file could never be written from this setup."
  confirming_evidence:
    - "MinimumSizeLearner.swift:68-74: actual within 2 pt of `before` returns (nil,false,Clamp) - no candidate; confirm (96) needs a candidate; persistable excludes *Unmoved axes (106-108)"
    - "Unit tests assert this as a known limit: FrameScenarioTests.aWindowThatOpensAtItsMinimumLearnsItOnceAWriteMovesIt ('known limit: the first refused write did not move it') and MinimumHintsStoreTests.aMinimumLearnedFromUnmovedRefusalsStaysWithItsWindow (persistableMinimum == nil)"
    - "Live differential in the VM, only change = Notes started 16 pt above its minimum (658x340): one Nudge read back 642x324 at 182,92, and within ~1.5 s ~/Library/Application Support/Transom/min-size-hints.json held com.apple.Notes 642x324 and Tracked Windows Min Size showed 642 x 324"
  falsification_test: "If the at-minimum case were a pipeline break rather than the learner rule, the min+16 Nudge would also have learned nothing (no Min Size, no file). It learned and saved within ~1.5 s, so the pipeline, the Phase 3 Arranger interaction and the renamed Transom data folder are all fine; only the pre-write size differs."
  fix_rationale: "The code does what its documented rule says; the UAT step and expectation (written in c6b6a23 before 7c97838 narrowed learning to refusals that move the window) set up a case the rule deliberately ignores. Fixing the test setup (start 2-32 pt above the minimum) addresses the cause; changing the learner would reopen WR-01/CR-02 (late appliers, fixed-size windows)."
  blind_spots: "Did not re-run the at-minimum Nudge myself (the UAT run is the observation; the learner logs nothing, so it is code reading + unit tests). Did not test Chrome/Electron, Terminal cell snap, second window or relaunch (not in scope, not installed). Did not instrument the build."
  candidate_causes:
    - "data/test setup: Notes placed at its exact minimum makes the refusal unmoved (CONFIRMED)"
    - "code (by design): MinimumSizeLearner ignores one unmoved refusal and never persists one (CONFIRMED, documented + tested)"
    - "code: NudgePlanner alternates shrink/restore, so the unmoved repeat never happens (CONFIRMED by reading)"
    - "code: Phase 3 Arranger write replaces the candidate before the confirm (ELIMINATED: Nudge echo is `own`, no write back before confirm; live control learned)"
    - "config/env: hints save path or onLearnedMinimum wiring broken after the Pane->Transom rename (ELIMINATED: live file written to Application Support/Transom)"
    - "environment: Notes on macOS 15.7.7 reports an unusable AX read-back (ELIMINATED: the read-back was learned in the control)"
  and_gate: "yes - the failure needs the window at its exact minimum (setup) AND the learner's unmoved-refusal rule (single refusal ignored, unmoved minimum never persisted) AND Nudge's alternation (no same-clamp repeat). Remove the first and one Nudge learns and saves (shown live)."

## Symptoms

expected: Transom Debug writes a smaller frame to a window, and the app refuses the size. Transom should then learn the real minimum: the Tracked Windows "Min Size" column fills in about a second later, `system.onLearnedMinimum` fires, and MinimumHintsStore saves `~/Library/Application Support/Transom/min-size-hints.json` holding that bundle's size (Sources/TransomMac/TransomMacApp.swift lines 40-50).
actual: In the VM the hints file was absent (only an old Pane one). Notes #234 was shrunk with AX (/tmp/axset Notes 234 100 60 300 250) and settled at 642x324, its real minimum. With Notes frontmost, Debug > Nudge Focused Window ran (NudgePlanner targets +32,+32 and -64,-64, so 578x260). Notes moved to 132,73 but stayed 642x324. Min Size stayed blank, no Transom hints file appeared, nothing related was logged.
errors: none logged
reproduction: Tart VM pane-test (macOS 15.7.7), Transom Debug running. Notes frontmost, Option-click status item > Debug > Nudge Focused Window. Check Tracked Windows Min Size column and the hints file.
started: First live run of Phase 2 UAT test 12 (2026-10-27). Phase 3 added engine-side MinimumSizeLearner and Arranger frame handling. Notes floats on the Desktop tile, managed by the Arranger.

## Evidence

- timestamp: 2026-10-27T20:00:00-05:00
  checked: knowledge-base.md and open sessions g-03-6-fixed-size-window-overlap, g-03-11-floaters-stay-shrunk
  found: no KB entry matches; g-03-6 root cause says MinimumSizeLearner never learns from a first write the app refuses entirely (read-back == pre-write size); g-03-11 says an unmoved refusal needs a repeat write >= 1 s later (MinimumSizeLearner.swift:63-72)
  implication: known_pattern_candidate "g-03-6 — unmoved refusal not learned"; test first

- timestamp: 2026-10-27T20:05:00-05:00
  checked: Sources/TransomEngine/MinimumSizeLearner.swift:59-85 (recordWrite) and :89-113 (confirm)
  found: per axis a write is a refusal only if actual > requested + 32 (refusalMargin). If also actual < before - 2 it is a "moved" candidate (learned AND persistable after a refresh >= 1 s later). If actual is within 2 pt of `before` (unmoved), it only records a Clamp; it becomes a candidate only when a later write reads back the same clamp >= 1 s after, and then it is learned with widthUnmoved/heightUnmoved = true, so `persistable` never gets it (CR-02, 5a65a9a)
  implication: Notes at 642x324 asked for 578x260 and read back 642x324 == before: an unmoved refusal on both axes. No candidate, awaitsMinimumConfirmation false, no confirm refresh scheduled, nothing learned. Even a confirmed unmoved minimum would never reach onLearnedMinimum / the hints file

- timestamp: 2026-10-27T20:06:00-05:00
  checked: Sources/TransomMac/Shell/Nudge.swift (NudgePlanner.target) and StatusItemController.nudge (line 288)
  found: Nudge alternates: the first press writes +32,+32 / -64,-64 and stores the old frame; the next press writes that stored frame back. A restore write is not a refusal, so recordWrite returns (nil,false,nil) per axis and clears the unmoved record
  implication: Nudge can never produce the "same clamp repeated >= 1 s later" that an at-minimum window needs: shrink (record) -> restore (record cleared) -> shrink (new record) ...

- timestamp: 2026-10-27T20:07:00-05:00
  checked: arithmetic of one Nudge against a window of size W with real minimum m (app clamps to m)
  found: request R = W - 64. Learned (moved refusal) needs m > R + 32 and m < W - 2, i.e. m + 2 < W < m + 32 on that axis. W >= m + 64: honoured. m + 32 <= W < m + 64: clamp within the margin, tolerated, not learned. W <= m + 2: unmoved, not learned
  implication: a single Nudge teaches a minimum only when the window sits 2-32 pt above its minimum on an axis; UAT 12 does not set that up and the VM run put Notes exactly at its minimum

- timestamp: 2026-10-27T20:08:00-05:00
  checked: Arranger.handle .frameApplied / moved (Sources/TransomEngine/Arranger.swift:551-563, 683-726)
  found: frameApplied sets lastApplied = actual; the windowMoved that follows is within 2 pt of it, so `own` is true and moved() returns [] (no write back). frameApplied also raises floaterFloors (Arranger-only). retryRefusal needs a docked present window, so a floater gets no retry
  implication: Phase 3 sends no follow-up write that could replace or clear the learner's candidate after a Nudge; it is not part of this failure (and matches Notes staying at 132,73)

- timestamp: 2026-10-27T20:09:00-05:00
  checked: Tests/TransomEngineTests/FrameScenarioTests.swift:121-133 and Tests/TransomMacTests/MinimumHintsStoreTests.swift:184-199; git dates
  found: aWindowThatOpensAtItsMinimumLearnsItOnceAWriteMovesIt asserts `learned == nil, "known limit: the first refused write did not move it"` (lead decision 2026-10-25); aMinimumLearnedFromUnmovedRefusalsStaysWithItsWindow asserts persistableMinimum == nil. UAT 12 text was written in c6b6a23 (2026-10-25 16:20); the moved-only rule landed after it in 7c97838 (16:58) after WR-01 0c148fb (13:13); CR-02 5a65a9a (10-26) made unmoved minimums session-only
  implication: the observed behaviour is the documented, tested design; UAT 12's expectation predates it and its procedure cannot satisfy it

- timestamp: 2026-10-27T20:35:00-05:00
  checked: VM state before the live test (/tmp/cglist, Application Support)
  found: Transom Debug pid 2077 running; Application Support/Transom has only layout.json (no min-size-hints.json); old Pane/min-size-hints.json still there; Notes#234 at 100,41 642x324
  implication: clean baseline for the Transom hints file

- timestamp: 2026-10-27T20:35:59-05:00
  checked: live differential in the VM. /tmp/axset Notes 234 150 60 658 340 (16 pt above the 642x324 minimum on both axes), Notes frontmost, Option-click status item > Debug > Nudge Focused Window (enabled), then polled /tmp/cglist and the hints file every 0.5 s
  found: t+0.5 s Notes#234 at 182,92 642x324 (request 594x276 refused, window moved to its minimum). t+1.5 s ~/Library/Application Support/Transom/min-size-hints.json exists: {"hints":[{"bundleID":"com.apple.Notes","height":324,"width":642}],"schemaVersion":1}. Tracked Windows (scrolled right) shows Min Size 642 x 324 on the Notes row. No log lines (the learner and Arranger log nothing here)
  implication: H1 confirmed. One moved refusal is learned, confirmed ~1 s later, reported through onLearnedMinimum and saved by MinimumHintsStore in the renamed Transom folder. The only difference from the UAT run is the pre-write size

- timestamp: 2026-10-27T20:36:01-05:00
  checked: why Notes went back to 150,60 658x340 at t+1.5 s (side finding); Arranger.swift:602, Planner.swift:64-68
  found: every event other than windowMoved/windowResized/frameApplied/windowCreated ends in replan(). The learned-minimum windowChanged re-planned the desk; Planner.plan sends each floater to wantedFrames[id] when it is not there. The Nudge was an `own` write (lastApplied echo), so wantedFrames stayed at the pre-Nudge frame (set when axset moved it), and the replan wrote it back
  implication: Phase 3 side effect, after learning, not part of G-02-12: on a floating window the Arranger undoes a Debug Nudge at the next replan (any focus/state event). It explains why Notes was found back at 100,41 at session start, and it can confuse UAT 9 (Nudge then exact restore) on a floater: the second press may "restore" a frame the Arranger already restored

## Eliminated

- hypothesis: Phase 3 Arranger sends a write after the Nudge that replaces or clears the learner's candidate before the confirm refresh
  evidence: Arranger.moved treats the Nudge echo as `own` (within 2 pt of lastApplied) and returns []; retryRefusal only acts on docked windows; the live min+16 control learned and saved. Its later replan only runs after the confirm
  timestamp: 2026-10-27T20:36:30-05:00

- hypothesis: onLearnedMinimum / MinimumHintsStore wiring or the save path broke in the Pane->Transom rename
  evidence: the live control wrote ~/Library/Application Support/Transom/min-size-hints.json with com.apple.Notes 642x324 about 1.5 s after the Nudge
  timestamp: 2026-10-27T20:36:30-05:00

- hypothesis: Notes on macOS 15.7.7 gives an unusable AX read-back after a refused size
  evidence: the same read-back (642x324) was learned in the control
  timestamp: 2026-10-27T20:36:30-05:00

## Resolution

root_cause: "Test setup meets a deliberate learner rule; no code defect in the learning pipeline. Notes was placed exactly at its real minimum (642x324) before the Nudge, so the Nudge's 578x260 request read back 642x324, the same as the window's size before the write. MinimumSizeLearner.recordWrite (Sources/TransomEngine/MinimumSizeLearner.swift:68-74) classes that as an unmoved refusal: it records a clamp and makes no candidate. awaitsMinimumConfirmation stays false, no confirm refresh is scheduled, learnedMinimum stays nil, and no windowChanged reaches onLearnedMinimum (Sources/TransomMac/AXWindowSystem.swift:459-465), so nothing is saved. This is the documented, tested known limit (WR-01 0c148fb, 7c97838 'learn a minimum only from a read-back the window moved to'). An unmoved refusal is learned only when the same clamp repeats >= 1 s later (G-03-6), but NudgePlanner's next press restores the old frame (Sources/TransomMac/Shell/Nudge.swift:15-22), a non-refusal that clears the clamp, so Nudge can never produce the repeat. Even when one is learned, CR-02 (5a65a9a) keeps an unmoved minimum session-only, so it never reaches min-size-hints.json. UAT 12's expectation was written in c6b6a23 (2026-10-25 16:20), before 7c97838 (16:58) narrowed learning, and its steps do not say where to start the window. With one Nudge (shrink 64), a minimum is learned on an axis only when the window starts more than 2 pt and less than 32 pt above its minimum on that axis."
fix: "Diagnose only, no change made. Suggested: fix UAT 12, not the learner. (1) Rewrite the step: put the window 2-32 pt above its real minimum on each axis before Nudge (Notes: /tmp/axset Notes <id> x y 658 340), so the refusal moves it; then Min Size shows the minimum about 1 s later and the hints file holds the bundle's size. (2) State the limit in the expectation: a window already at its minimum (or 32-64 pt above it) learns nothing from one Nudge by design, and a minimum learned from unmoved refusals is session-only and never saved (CR-02). (3) Optional, only if the developer wants Nudge to be a better probe: a Debug-only 'Probe Minimum' that shrinks to a tiny size twice >= 1 s apart would exercise the unmoved path too. Side finding to log separately (Phase 3): on a floating window the Arranger undoes a Debug Nudge at the next replan, because Nudge writes do not update wantedFrames; if UAT 9 runs on a floater, use a docked window or expect the revert."
verification: "Live VM control 2026-10-27 20:35: Notes 658x340 (min + 16) -> one Nudge -> read-back 642x324 -> Min Size 642 x 324 and Application Support/Transom/min-size-hints.json {com.apple.Notes 642x324} within ~1.5 s. The UAT's at-minimum run learned nothing, matching the unit tests' known-limit assertions."
files_changed: []
specialist_hint: swift
