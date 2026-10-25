---
phase: 02-window-control
plan: 15
subsystem: window-control
tags: [minimum-size, learner, frame-writes, bundle-hints, gap-closure, accessibility]

requires:
  - phase: 02-window-control
    provides: the frame write pipeline with read-back (02-12), MinimumHintsStore and per-bundle hints (02-13), the WindowTracker and FakeWindowSystem of 02-14
provides:
  - MinimumSizeLearner margin plus time rule (refusalMargin 32 pt, confirmDelay 1 s, tolerance 2 pt)
  - WindowTracker.applyFrameResult(_:at:) records candidates; ingest confirms them through learner.confirm
  - WindowTracker.awaitsMinimumConfirmation(pid:) and the confirming refresh scheduled by AXWindowSystem
  - onLearnedMinimum reported from emit for every learned growth (also during a refresh)
  - In-session bundle hints, raised inside the tracker when a minimum is learned
  - The reviewer's probe3c scenarios as committed tests
affects: [phase-03-tiling]

actuals:
  tokens: 16000    # chars/4 over the realized diff (63839 chars, TDD evidence excluded)
  tasks: 2
  commits: 5       # measured; includes 0b2af44 (a ROADMAP Phase 6 note committed by someone else during this plan), so 4 are this plan's
plan_head_before: 5a92e6d36023b8d6f18e38d11ee8c4b46617514a
plan_head_after: 855b42296df64ceef583a8ef0866049e76dab792

tech-stack:
  added: []
  patterns:
    - "Record at write time, confirm at refresh time: a learned value needs a later independent observation, not agreement between writes"
    - "Report-on-growth in emit: a per-identity last-reported value, seeded by windowCreated, so a hint is never echoed back to the store"

key-files:
  created:
    - .planning/phases/02-window-control/tdd/02-15-task1-red.json
    - .planning/phases/02-window-control/tdd/02-15-task1-live-red.json
    - .planning/phases/02-window-control/tdd/02-15-task2-red.json
  modified:
    - Sources/PaneEngine/MinimumSizeLearner.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
    - Tests/PaneEngineTests/FrameScenarioTests.swift
    - Tests/PaneEngineTests/TrackerDisplayTests.swift
    - Tests/PaneMacTests/MinimumHintsStoreTests.swift
    - Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift
    - .planning/phases/02-window-control/02-12-PLAN.md

key-decisions:
  - "02-15: refusalMargin = 32 pt. A text-grid app rounds a size up by less than one cell; a real minimum within 32 pt of a tile is not learned from that write"
  - "02-15: confirmDelay = 1 s (4 x the 250 ms settle delay). Late-applying apps have caught up by then, a clamped window has not moved"
  - "02-15: In-session hints live in the tracker (per-axis max into bundleHints when a minimum is learned); PaneMacApp keeps persisting through onLearnedMinimum"
  - "02-15: A candidate whose confirmation is due but which no refresh decided (window not listed, not present, or frame unknown) is dropped at that pid's next refresh, so no window waits forever and no 1 s refresh loop runs"

patterns-established:
  - "Learned facts from untrusted apps need an observation separated in time from the write that suggested them"

requirements-completed: [WIN-04]

coverage:
  - id: D1
    description: "One rule per axis: a read-back more than 32 pt above the request is a candidate, learned once a refresh at least 1 s later (no newer write) still sees it within 2 pt; anything else drops it"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/MinimumSizeLearnerTests.swift (margin boundary 32 / 32.01, 999 ms vs 1 s, observed elsewhere, newer write, per-axis, non-finite, only grows, forget)"
        status: pass
    human_judgment: false
  - id: D2
    description: "probe3c scenarios: a window that stays clamped and one that opens at its minimum learn; a 16-pt snap, lag-2 drags and a user resize learn nothing; a fullscreen window learns nothing"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FrameScenarioTests.swift#aWindowThatStaysClampedLearnsAfterTheNextRefresh, aWindowThatOpensAtItsMinimumLearnsIt, aGridSnapIsNeverLearnedButARealRefusalStillIs, aSlowAppDuringADragLearnsNothing, aSlowAppDraggedBackAndForthLearnsNothing, aWindowResizedByTheUserBeforeTheRefreshLearnsNothing, aFullscreenWindowLearnsNothing"
        status: pass
    human_judgment: false
  - id: D3
    description: "Fake and live fixture learn 250 x 150 from one refused write, with no second write"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FrameScenarioTests.swift#theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsItFromOneWrite, aClosedWindowsCandidateIsForgotten"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift#aRefusedSizeIsReadBackAndLearned()"
        status: pass
    human_judgment: false
  - id: D4
    description: "A minimum learned for one window seeds later windows of its bundle in the same session (REVIEW IN-04)"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MinimumHintsStoreTests.swift#BundleHintTrackerTests (aMinimumLearnedThisSessionSeedsTheNextWindowOfThatBundle, aLearnedMinimumRaisesAStoredHintPerAxisAndOnlyForItsBundle, aRefusalWithinTheMarginRaisesNoHint, aWindowAlreadyTrackedKeepsItsOwnValue, setBundleHintsReplacesTheSessionsHints)"
        status: pass
    human_judgment: false
  - id: D5
    description: "02-12 truths 4 and 5 state the new rule"
    verification:
      - kind: other
        ref: "grep -c 'revised by 02-15' .planning/phases/02-window-control/02-12-PLAN.md (2)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Real apps via Nudge: Terminal/iTerm2 learn no cell snap; an app with a real minimum (Notes, Music) shows it about a second after the refused write; its second window starts from it; the hint survives relaunch"
    requirement: WIN-04
    verification: []
    human_judgment: true
    rationale: "Real third-party apps' snapping and minimums cannot be driven from automation (end-of-phase human UAT, the human-check in Task 2; inspect or delete ~/Library/Application Support/Pane/min-size-hints.json first, since it may hold snap hints learned under the old rule)"

duration: 8min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 15: Margin Plus Time Minimum-Size Learning Summary

**One refused write teaches a window's minimum once a refresh a second later still sees the window at the read-back size. Only read-backs more than 32 pt above the request count, so a terminal's cell snap is never learned. A window already at its minimum learns too, and what one window teaches seeds the next window of that app in the same session.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-10-25T19:40:34Z
- **Completed:** 2026-10-25T19:48:41Z
- **Tasks:** 2
- **Files modified:** 10 (plus 3 TDD evidence records)

## Accomplishments

- `MinimumSizeLearner` has one rule. `recordWrite` keeps a per-axis candidate for any read-back more than `refusalMargin` (32 pt) above the request, and stores the write time. A newer write replaces it. `confirm` does nothing until `confirmDelay` (1 s) has passed. After that it learns each candidate axis observed within 2 pt, as max(old, value), and drops the candidate either way. The agreement fields, the old `learn` method and the pre-write size skip are gone.
- `WindowTracker.applyFrameResult(_:at:)` records a candidate only while the window is present. `ingest` confirms it for each present, listed window with a known frame, and `learnedMinimum` is now part of the windowChanged comparison. A due candidate that no refresh decided is dropped at that pid's next refresh (`dropDue`).
- `AXWindowSystem` schedules the pid's refresh `confirmDelay` after a write that left a candidate. It reschedules when a refresh came too early. `emit` now calls `onLearnedMinimum` for every windowChanged whose minimum grew, so a minimum learned during a refresh reaches MinimumHintsStore. A seeded minimum (windowCreated) counts as already reported, so a hint is never echoed back.
- The reviewer's probe3c cases (one shrink then static, at-min static, snap, lag-2 slow drag, lag-2 back and forth) are committed tracker tests, each with a doc comment naming its case. The snap test includes a positive control.
- The live fixture `minsize:250x150` learns 250 x 150 from one setFrame within 2 s (passed in 1.85 s), and the test asserts there was no second write.
- In-session hints: a learned minimum raises the tracker's `bundleHints` per axis. Later windows of the bundle start from it. A stored hint still seeds only first reports, and `setBundleHints` still replaces the map.
- 02-12-PLAN.md truths 4 and 5 now state this rule, marked "revised by 02-15".

## Task Commits

1. **Task 1: Tracer, one refused write confirmed by a later refresh** - `9790e5c` (test, RED), `81903a2` (feat, GREEN)
2. **Task 2: In-session bundle hints and the 02-12 contract** - `42b7de3` (test, RED), `855b422` (feat, GREEN)

`0b2af44` (docs: Phase 6 co-visibility note in ROADMAP.md) landed between them. It was not made by this plan.

## TDD Gate Compliance

Each task has a `test(02-15)` commit before its `feat(02-15)` commit. All three RED records returned `RED_EVIDENCE_OK`.
- `tdd/02-15-task1-red.json`, target `aWindowThatStaysClampedLearnsAfterTheNextRefresh()`. Compiling stubs kept the 02-14 rule behind the new interface: `recordWrite` wrapped the old `learn`, and `confirm` returned nil. The planned rows failed on their assertions. Stays-clamped, opens-at-minimum and the single-write fake learned nothing, and the snap row learned 518. The lag-2, user-resize, fullscreen and margin-negative rows passed, as guards.
- `tdd/02-15-task1-live-red.json`. The live test got its 250 x 150 read-back, then failed only on the learned expectation (nil for 2 s).
- `tdd/02-15-task2-red.json`, target `aMinimumLearnedThisSessionSeedsTheNextWindowOfThatBundle()`. B started from nil, and C started from 300 x 200 instead of 350 x 200. The three guard rows passed by design.

## Tracer gate

The mode is end-of-phase and the tracer's verify is automated only. Both verify commands were re-run after GREEN and passed: the four unit suites, and FrameWriteIntegrationTests with aRefusedSizeIsReadBackAndLearned run. Tracer verified end to end, and Task 2 went ahead.

## Verification

- `swift test --skip PaneMacIntegrationTests`: all pass (142 + 81 + 199 across the three test products).
- `caffeinate -d -i swift test --filter FrameWriteIntegrationTests`: 4 pass, and the existing two-display test is skipped. aRefusedSizeIsReadBackAndLearned ran and passed.
- `caffeinate -d -i swift test --filter PaneMacIntegrationTests`: 23 pass, and the same two-display test is skipped. This checks that the new refresh scheduling breaks no other live test.
- `scripts/check-no-appkit.sh`: OK.
- Acceptance greps: `refusalMargin` 3, `confirmDelay` 5, `func confirm(window` 1, `func applyFrameResult(_ result: FrameWriteResult, at` 1, `learner.confirm` 1, `revised by 02-15` 2.
- Live runs: 4 in total (RED, Task 1 GREEN, Task 2 GREEN, full integration suite). Each was wrapped in `caffeinate -d -i` after a lock check (`locked: nil`). Fixture windows only. Afterwards `pgrep -fl PaneFixtureApp` printed nothing.
- The candidate-forget fake row was mutation-checked. With `forget` not dropping the candidate, it fails, and so does the learner's forget row.

## Known limits

- **A real minimum within 32 pt of the request is not learned from that write.** If a window's true minimum is 2 to 32 pt above the tile Pane asks for, the write is clamped but teaches nothing. The read-back frame still reaches Phase 3, so the layout sees the real size. A later, smaller request (more than 32 pt under the minimum) teaches it.
- **Cells larger than 32 pt are not protected.** A text-grid app whose cells are taller or wider than 32 pt (very large terminal fonts) can round a request up by more than the margin. That snap is then learned as its minimum and persisted for the bundle.
- **The 1 s confirm refresh replaces a pending refresh of the same pid.** `RefreshScheduler.schedule` keeps one pending refresh per pid. A write that leaves a candidate can therefore delay a pending settle or quick-recheck refresh of another window of that app by up to 750 ms. The refresh that follows reschedules the settle or recheck as usual.
- **A minimized, hidden or unlisted window at confirm time teaches nothing.** Its candidate is dropped at that pid's next due refresh.
- Real-app checks are end-of-phase human UAT (coverage D6): Terminal or iTerm2 cell snapping, Notes or Music real minimums, a second window in the same session, and relaunch persistence. Before running them, inspect or delete `~/Library/Application Support/Pane/min-size-hints.json`, which may hold snap hints learned under the old rule.

## Decisions Made

- `refusalMargin = 32`, `confirmDelay = 1 s` and in-tracker session hints, as the plan chose (see key-decisions).
- `dropDue(pid:at:)`, a small learner method the plan did not list. Without it, a candidate whose window is never confirmed would keep `awaitsMinimumConfirmation` true, and AXWindowSystem would refresh that app every second forever. Examples are a window that went to another Space or was minimized. It drops only that pid's due candidates, so another app's refresh never cancels a pending confirmation.
- A write with a non-finite or out-of-range requested or read-back value clears the window's candidate, since it counts as a newer write. A non-finite observed size at confirm time also drops the candidate.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] Due candidates that no refresh decided are dropped**
- **Found during:** Task 1
- **Issue:** The plan's confirm path runs only for present, listed windows with a known frame, and the follow-up reschedules while a candidate waits. A candidate for a window that never meets those conditions would never be removed, so that app would be refreshed every second for good.
- **Fix:** `MinimumSizeLearner.dropDue(pid:at:)`, called once per ingest after the per-window confirms.
- **Files modified:** Sources/PaneEngine/MinimumSizeLearner.swift, Sources/PaneEngine/WindowTracker.swift
- **Committed in:** 81903a2

**2. [Rule 1 - Bug] Two RED test rows had wrong data**
- **Found during:** Task 1 GREEN
- **Issue:** `aWindowSeenElsewhereAtConfirmTimeTeachesNothing` moved only the width, but the plan's per-axis rule correctly still learns the height. The closed-window row used a 120 x 90 clamp of a 100 x 80 request, which is within the 32 pt margin.
- **Fix:** Both axes are now observed elsewhere, and a new `eachAxisIsConfirmedOnItsOwn` row covers the per-axis case. The reused window's minimum is now 160 x 130.
- **Files modified:** Tests/PaneEngineTests/MinimumSizeLearnerTests.swift, Tests/PaneEngineTests/FrameScenarioTests.swift
- **Committed in:** 81903a2

**3. [Rule 1 - Bug] The closed-window fake row could not see a forgotten minimum once session hints exist**
- **Found during:** Task 2 GREEN
- **Issue:** After Task 2, a reused window ID of the same bundle starts from the bundle hint, which is the intended behaviour. So "the old minimum is forgotten" can no longer be observed through the fake.
- **Fix:** The row became `aClosedWindowsCandidateIsForgotten`: a candidate waits, the window closes, the reused ID reappears at the candidate's size and learns nothing. `forgetDropsTheMinimumAndTheCandidate` in the learner tests still covers the minimum. Both were mutation-checked.
- **Files modified:** Tests/PaneEngineTests/FrameScenarioTests.swift
- **Committed in:** 855b422

**Total deviations:** 3 auto-fixed (1 missing critical, 2 test bugs).
**Impact on plan:** No scope change. The rule, the interfaces and the call sites match the plan.

## Issues Encountered

None.

## Threat Flags

None. No new endpoint, file access or trust-boundary surface. T-02-41 is mitigated as planned: the margin and the 1 s confirmation apply, values are validated in `recordWrite`, `confirm` and `seed`, session hints take only the per-axis max of learned values, and MinimumHintsStore keeps its load-side validation.

## Next Phase Readiness

This was the last gap-closure plan in this batch. Phase 2 is ready for re-verification (gap 3, WIN-04 / ROADMAP SC3) and the end-of-phase human UAT, including the real-app Nudge checks in coverage D6.

## Self-Check: PASSED

- FOUND: 9790e5c, 81903a2, 42b7de3, 855b422 (all ancestors of HEAD)
- FOUND: Sources/PaneEngine/MinimumSizeLearner.swift, Tests/PaneEngineTests/FrameScenarioTests.swift, the three tdd/02-15-*.json records
- No stub, TODO or "RED stub" marker left in the changed sources
