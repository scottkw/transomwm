---
phase: 03-tiling-mvp
plan: 22
subsystem: layout-engine
status: complete
tags: [tile-01, win-04, g-03-6, minimum-size, gap-closure]
gap_closure: true
gap_ids: [G-03-6]
requires:
  - "03-21: Planner.plan drops a floater too big for the room from the Desktop minimum, so the floated window does not evict its neighbour"
  - "02 (7c97838): MinimumSizeLearner's late-applier guard (lead decision 2026-10-25)"
provides:
  - "MinimumSizeLearner: an unmoved over-margin refusal is recorded and promoted to a candidate by the same clamp read back unmoved at least confirmDelay later"
  - "Arranger.retryRefusal: one re-write of a refused docked tile per window and tile (refusalRetried), through the correction path"
affects:
  - "Every docked window whose read-back exceeds its tile by more than 32 pt gets one extra write about 1 s later"
  - "A window that opens at a minimum larger than its tile now learns it about 2 s after docking and floats with the lost-room notice"
tech-stack:
  added: []
  patterns:
    - "Retry rides the existing once-per-second correction (pendingCorrections + tick), no new timer"
key-files:
  created:
    - Tests/PaneEngineTests/TooBigDockedWindowTests.swift
  modified:
    - Sources/PaneEngine/MinimumSizeLearner.swift
    - Sources/PaneEngine/Arranger.swift
    - Tests/PaneEngineTests/FrameScenarioTests.swift
    - Tests/PaneEngineTests/MinimumSizeLearnerTests.swift
    - .planning/phases/03-tiling-mvp/deferred-items.md
decisions:
  - "Under-32 pt tolerance: a docked overflow of 32 pt or less (refusalMargin) is never retried or learned, on either axis, so a visible overlap of up to the margin minus the gap can remain (e.g. Reminders' 692 pt height in a 664 pt tile). Stated in MinimumSizeLearner's doc comment ('Overflow within refusalMargin is tolerated') and pinned by tests. Reversible: a later phase can shrink or replace the margin."
  - "Weakened late-applier bound: one unmoved refusal still teaches nothing, but an app lagging more than about 2 s on two writes in a row (unmoved at t, unmoved again at t+1 s, still unmoved at the t+2 s refresh) is misread as a minimum. The doc comment's 'Known limit' now says this."
  - "A refresh that sees the window off a recorded unmoved clamp drops that record (added beyond the plan's rule list), so an app that caught up late cannot be promoted by a much later unmoved write"
  - "A promoted unmoved candidate takes the latest read-back (within 2 pt of the record)"
metrics:
  duration: "~60 min (code ~25 min, VM ~35 min)"
  completed: 2026-10-27
estimate:
  tokens: 75000
  tasks: 3
actuals:
  tokens: 7800
  tasks: 3
  commits: 3
plan_head_before: e4bc11a8cad540a281e44c979e4108d6972c8f4b
plan_head_after: 3805e0ad397d0fe879be3744217706babc12af76
---

# Phase 3 Plan 22: Retry a refused docked tile once and learn an unmoved minimum from the repeat (G-03-6 part 2) Summary

**A docked window that opens already at a minimum larger than its tile now floats instead of overlapping. Its refused tile is written once more after 1 s, the same unmoved clamp is promoted to a candidate, and the 1 s confirm refresh learns it. A single slow write still teaches nothing. In the VM (Pane 0.3.6, build 1004), Reminders' Welcome window docked beside Notes floated about 2 s later, with a width-only 768 hint, and Notes kept its tile.**

## Tasks

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Tracer RED: repeat-rule tracker tests + Harness end-to-end | bf31d66 | FrameScenarioTests.swift, TooBigDockedWindowTests.swift |
| 1 | GREEN: learner `unmoved` record + Arranger `refusalRetried` retry | c48e1b8 | MinimumSizeLearner.swift, Arranger.swift |
| 2 | Late-applier, under-32 pt and retry-bound tests | 3805e0a | MinimumSizeLearnerTests.swift, FrameScenarioTests.swift, TooBigDockedWindowTests.swift |
| 3 | VM UAT re-check of test 15 (no source change) | this SUMMARY commit | 03-22-SUMMARY.md, deferred-items.md |

## The rule

**Learner, per axis in `recordWrite`.**
- A read-back more than 32 pt over the request is a refusal.
- If it moved more than 2 pt from `before`, it is a candidate, as today.
- If it did not move, the same clamp as the previous candidate keeps that candidate, as today.
- Otherwise it is checked against the `unmoved` record. A record within 2 pt that is at least `confirmDelay` old promotes the axis to a candidate at this write's time. A matching record that is younger is kept with its original time. No record, or a different clamp, stores a new record.
- A write that is not an over-margin refusal on an axis clears that axis's record. So does an invalid write.
- `confirm` drops a record axis when the refresh sees the window off it.
- `awaitsConfirmation` and `dropDue` ignore records. `rekey` moves them and `forget` drops them.

**Arranger.** `.frameApplied` sets `lastApplied` and then calls `retryRefusal`. It retries only when all of these hold:
- not paused or session-paused;
- not the dragged window, and not excluded;
- docked and present on a shown desk;
- `requested` is within 0.5 pt of `lastRequested`;
- the overflow is more than the margin on either axis;
- `refusalRetried[id] != requested`.

It then sets `refusalRetried[id] = requested` and `lastCorrection = now`, inserts the window into `pendingCorrections`, and returns the wake. The existing `tick` sees the window off its tile, and `correct()` re-sends the tile. `forget` clears the entry and `.windowRekeyed` moves it.

## Verification

- `swift test --filter "FrameScenarioTests|TooBigDockedWindowTests|MinimumSizeLearnerTests"` after Task 1: `✔ Test run with 34 tests in 3 suites passed`.
- `swift test --filter "MinimumSizeLearnerTests|FrameScenarioTests|TooBigDockedWindowTests|RefusalRetryBoundTests"` after Task 2: `✔ Test run with 48 tests in 4 suites passed`.
- Full `swift test`: `✔ Test run with 487 tests in 52 suites passed` (live AX suites skip on the host; PANE_LIVE never set). `scripts/check-no-appkit.sh`: `no-appkit: OK (40 files)`.
- Acceptance greps: `unmoved` 12 in MinimumSizeLearner.swift; `refusalRetried` 5 in Arranger.swift; `@Test` 8 in TooBigDockedWindowTests.swift; "Overflow within refusalMargin is tolerated" 1. Removed `#expect` lines in MinimumSizeLearnerTests/FrameScenarioTests since the parent of bf31d66: **0**. No existing learner expectation changed (the plan's guard did not trip). Only the comment of `aWindowThatOpensAtItsMinimumLearnsItOnceAWriteMovesIt` was updated.
- The plan's ArrangeIntegrationTests/FrameWriteIntegrationTests live suites were not run. The plan's verify blocks only list the unit suites. The VM check below covers the live path.

## TDD Gate Compliance

- RED bf31d66: `aWindowAtItsMinimumLearnsItWhenTheSameClampRepeatsASecondLater` failed (no candidate, nothing learned). The Harness test failed three ways: no re-write on tick, no learned width, no lost-room notice. `anUnmovedRepeatSoonerThanTheConfirmDelayLearnsNothing` passed at RED. It is a guard test that the old rule satisfies trivially.
- GREEN c48e1b8: all pass, and the full suite is green.
- Task 2 (3805e0a): the tests passed against c48e1b8, because Task 1's GREEN already contained the refresh-clears-record rule. There was no failing RED commit for Task 2. To show the tests are not vacuous, I removed the Arranger guards (pause, drag, excluded, shown desk, once-per-tile, margin) and the learner's refresh-clear, and ran the suites. Six tests failed: once-per-tile, under-margin, paused, dragged, the refresh-clear test, and the second-tick check. Then I restored the sources (`git diff` was clean). The floating and excluded bound tests did not fail under that mutation, because `lastRequested` (no tile for a floating window) also blocks them. Their protection is redundant, not missing.

## VM re-check G-03-6 (test 15)

**Setup.** The lock `.build/pane-vm.lock` was taken with `mkdir` and released with `rmdir`. `ls -d` fails afterwards. `scripts/build-debug.sh --release` exited 0. The app was copied with ditto and bumped to 0.3.6 / 1004 (installed: 0.3.5 / 1003). It was re-signed with `Developer ID Application: Ken Scott (S2K7P43927)`, `--options runtime --timestamp`, and the build's own entitlements (`app-sandbox false`). The DR is unchanged (`… leaf[subject.OU] = S2K7P43927`). Pane was quit, and the app was copied over with a tar pipe. `codesign --verify --strict` passed in the guest. Pane was relaunched with `open`, and the log showed `permission notTrusted -> probing` then `probing -> ready`. Guest: Tart pane-test 192.168.64.18. Saved first: /tmp/layout-before-0322.json and /tmp/hints-before-0322.json. Those hints have no Reminders entry: AddressBook 497x411, Notes 642, Safari 574, Terminal 165, TextEdit 143, Finder 460. The AddressBook entry is new since 03-21 and was not made by this plan.

**Test 15, Space 2.** After the relaunch the Space 2 desk was empty (known deferred item), so the layout was re-created. I clicked Notes (690,400) and pressed ⌃⌥⌘D: `docked ['Notes#150'] floating ['reminders#693']`, Notes `370 37 642 664`. Then I clicked Reminders (150,400), pressed ⌃⌥⌘D and sampled `/tmp/frames`:

| after dock (cumulative sleeps, plus SSH latency) | Reminders 693 | Notes 150 |
|---|---|---|
| +0.3 s | `191 25 768 692` (its tile, refused) | `370 37 642 664` |
| +1.0 s | `191 25 768 692` | `370 37 642 664` |
| +2.0 s | `12 25 768 692` (floated, clamped to the Desktop's left edge) | `370 37 642 664` |
| +3, +4, +6 s | `12 25 768 692` | `370 37 642 664` |

- layout.json, Space 2 desk: `docked ['Notes#150'] floating ['reminders#693:present']`, and Reminders' Desktop frame is `12 25 768 692`. The dock was accepted (the tile write at x 191). The window then left the tree with no command, and only `planFloatingLostRoom` does that. It emits `.notice(.lostRoom([reminders]))`.
- min-size-hints.json gained `{'bundleID': 'com.apple.reminders', 'height': 0, 'width': 768}`: width only, with no height entry, per the under-32 pt decision (692 vs 664).
- Notes kept its docked tile throughout (03-21). Only one docked tile remains on Space 2, so no docked tiles overlap.
- **No lost-room log line.** Pane does not log notices; they go only to the toast. The toast is not visible over VNC, and a debug-level log stream during the run showed only drag start/end lines. The notice is inferred from the docked-to-floating transition, not seen. This is logged in deferred-items.md (03-22).
- **Visible overlap remains (accepted T-03-58).** Reminders is 768 pt wide at its minimum, and Notes' tile is 642 pt, on a 1024 pt display. The floater is clamped to the Desktop's left edge but cannot shrink, so as the frontmost window it covers Notes' left part (screenshot scratchpad v22b.png). No layout can fit both side by side on this display. 03-21 recorded this as accepted until Phase 4's collapsed tiles (ZOOM-13). Test 15's "floats" branch is met; "not overlapping Notes" is not, for this reason.

**Regression, Space 1 (about 90 s).** Starting frames: TextEdit 578 `598 37 143 326`, Terminal 160 `753 37 256 659`, TextEdit 202 `12 375 729 326`.
- I dragged the TextEdit/Terminal gap right and back four times, stepping 747→813→777→747. Terminal went `819 37 193 659` → `783 37 228 659` → `753 37 256 659`, and TextEdit 578 went 209 → 173 → 143.
- I also dragged the vertical TextEdit 202 gap 369→300→369 three times (TextEdit 202 `12 306 729 395` and back).
- Left drags of the 747 gap do nothing, because TextEdit 578 is at its 143 minimum.
- The md5 of min-size-hints.json was the same before and after (`4a239a8b…`, with the new Reminders entry already in it). There is no new TextEdit or Terminal entry and no changed value, so grid snaps and slow appliers still teach nothing.

**Restore.**
- Quit Pane. Copied /tmp/hints-before-0322.json and /tmp/layout-before-0322.json back, so the Reminders hint is gone.
- The vertical gap drags had shrunk the Desktop tile, so the Space 1 floaters had been clamped: Finder 731/580/546 to 252 tall, TextEdit 722/567 to 214, and Safari 669 to y 37. I set them back with `/tmp/axset` to their saved frames (Finder `12 37 460 326`, Safari `12 139 574 224`, TextEdit `12 37 574 326`).
- My first attempt at this passed each frame as one quoted argument, so `axset` failed silently. The second, per-window attempt worked.
- Relaunched Pane (`probing -> ready`). Every Space 1 frame matches the start. `min-size-hints.json` is byte-identical (`cmp`), and layout.json's `world` compares equal to the saved copy.
- Reminders 693 was left on Space 2 at `12 25 768 692` (it was `191 25` when I found it). `axset` cannot reach it from Space 1, and it is floating in a desk Pane drops on relaunch anyway.
- The installed app is now 0.3.6 (1004) with this fix.
- The 03-21 Undo-off-screen issue was not reproduced: no Undo was used.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical] A refresh off a recorded unmoved clamp drops the record**
- **Found during:** Task 1, designing the rule
- **Issue:** The plan's rule list clears a record only on a non-refusal write. An app that applied the request late, as seen by a refresh, and was later widened again could have a much later unmoved write promoted against the old record. That would let a late applier be learned, which is against the lead decision.
- **Fix:** `confirm` drops each record axis whose refresh sees the window more than 2 pt off the clamp. Pinned by `aRefreshOffTheClampDropsTheUnmovedRecord`.
- **Files modified:** Sources/PaneEngine/MinimumSizeLearner.swift
- **Commit:** c48e1b8

**2. Task 2 had no failing RED commit.** The behaviour was already in Task 1's GREEN, so mutation evidence replaces the RED commit (see TDD Gate Compliance).

**3. Test 15 acceptance, partly met.** "Lost-room log line" cannot be met because Pane never logs notices (deferred). "Not overlapping Notes" is not met on a 1024 pt display (T-03-58, accepted in 03-21). Reminders floats and Notes stays docked, as required.

## Known Stubs

None.

## Threat Flags

None. There is no new surface. T-03-60 and T-03-61 are mitigated as planned: two unmoved refusals at least 1 s apart plus a confirm 1 s later, all over the 32 pt margin with `isValidGeometry`; and at most one retry per window and tile on the existing correction path.

## Self-Check: PASSED

- FOUND: Sources/PaneEngine/MinimumSizeLearner.swift, Sources/PaneEngine/Arranger.swift, Tests/PaneEngineTests/TooBigDockedWindowTests.swift
- FOUND: bf31d66, c48e1b8, 3805e0a (ancestors of HEAD)
- `.build/pane-vm.lock` absent; no STATE.md or ROADMAP.md edits
