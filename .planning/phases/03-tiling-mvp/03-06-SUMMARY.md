---
phase: 03-tiling-mvp
plan: 06
subsystem: arranger
status: complete
tags: [swift, paneEngine, paneMac, arranger, toast, notices, echo-rule, tdd, tracer]

requires:
  - phase: 02-window-control
    provides: "MinimumSizeLearner and windowChanged with a grown learnedMinimum (02-15); frameApplied read-backs"
  - phase: 03-tiling-mvp
    provides: "Arranger, Planner (unfit, Desktop-tile minimum), ArrangeController, lastRequested (03-04); World.reflow and recordFloatingFrame (03-03); per-Space desks (03-05)"
provides:
  - "PaneEngine Notice (.lostRoom, isCrashNotice) and ArrangerEffect.notice"
  - "Arranger floats docked windows that lose their room (World.reflow, no undo step) and emits one lostRoom notice per re-plan"
  - "Echo rule: lastApplied from frameApplied; a move or resize within 2 pt of it is never answered"
  - "Docked windows moved by their app go back to their tile at most once per second (ArrangerEffect.wake(at:), ArrangerInput.tick)"
  - "Floating moves recorded with recordFloatingFrame; clamped into the Desktop only when on a docked tile, the clamp recorded"
  - "PaneMac NoticeQueue<Item: QueueableNotice>, NoticeCopy (N1), ToastPresenter, WakeTimer, postAnnouncement"
  - "FakeWindowSystem.userMove(_:to:); Harness.now in the engine tests"
affects: [03-07, 03-08, 03-10, 03-13, drag, persistence, notices]

estimate:
  tokens: 80000
  tasks: 2
actuals:
  tokens: 13400
  tasks: 2
  commits: 4
plan_head_before: a93f807d06181d8b651fe7d95d4320b533a085c2
plan_head_after: 8b09dd8bcc340d72a08064dd25cd4281a072d27c

tech-stack:
  added: []
  patterns:
    - "Time-based Arranger rules return .wake(at:) and act on .tick; the shell keeps one replaceable WakeTimer"
    - "Toast queue rules are a pure value type generic over a two-requirement protocol, so kinds later plans add are testable now"

key-files:
  created:
    - Sources/PaneEngine/Notice.swift
    - Sources/PaneMac/Overlay/NoticeQueue.swift
    - Sources/PaneMac/Overlay/Toast.swift
    - Sources/PaneMac/Shell/NoticeCopy.swift
    - Tests/PaneEngineTests/ArrangerReflowTests.swift
    - Tests/PaneMacTests/NoticeQueueTests.swift
    - Tests/PaneMacTests/NoticeCopyTests.swift
    - Tests/PaneMacTests/WakeTimerTests.swift
  modified:
    - Sources/PaneEngine/Arranger.swift
    - Sources/PaneMac/ArrangeController.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Tests/PaneEngineTests/ArrangerLifecycleTests.swift
    - Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift

key-decisions:
  - "Lost-room floating repeats until every docked window fits: a floated window's minimum sizes the Desktop tile, which can crowd out a neighbour in turn. All windows floated in one re-plan share one notice"
  - "A floated window goes to its current frame clamped into the Desktop rect computed with every window of that pass already floating"
  - "The echo of a floating window still records its frame as a fact (no undo step) but is never answered"
  - "A docked window already within 2 pt of its tile is not corrected, and a tick corrects only windows still off their tile"
  - "NoticeQueue is generic over QueueableNotice (isCrashNotice, merged(with:)) and used as NoticeQueue<Notice>"

patterns-established:
  - "Live tests wait for the Arranger to see a fixture window's whole frame, not just x, before acting on it"

requirements-completed: []

coverage:
  - id: D1
    description: "A docked window that loses its room floats to the Desktop with no undo step and one N1 notice; a cascade in one re-plan gives one notice"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerReflowTests.swift#aDockedWindowThatLosesItsRoomFloatsToTheDesktopWithANotice, windowsLosingRoomInOneReplanGiveOneNotice, minimumsLearnedFromRefusedWritesFloatTheWiderWindowClearOfItsNeighbour, aNarrowerDisplayThatLeavesADockedWindowNoRoomFloatsItWithOneNotice"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/ArrangeIntegrationTests.swift#aDockedWindowThatTurnsOutTooBigFloatsToTheDesktop"
        status: pass
    human_judgment: false
  - id: D2
    description: "Pane's own writes are not moves (within 2 pt of the last frameApplied, including a refused write's read-back)"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerReflowTests.swift#panesOwnWriteComingBackWithin2PointsIsNotAMove, aRefusedWriteReadBackIsAnEchoNotAMoveToUndo"
        status: pass
    human_judgment: false
  - id: D3
    description: "A docked window moved by its app goes back at most once per second through wake and tick; the controller keeps only the latest wake"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerReflowTests.swift#aDockedWindowItsAppMovedIsPutBackAtMostOncePerSecond; Tests/PaneMacTests/WakeTimerTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "Floating windows are recorded where they are left, and clamped into the Desktop only when moved onto a docked tile"
    requirement: TILE-07
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ArrangerReflowTests.swift#aFloatingWindowMovedInsideTheDesktopIsRecordedWhereItWasLeft, aFloatingWindowMovedOntoADockedTileIsClampedIntoTheDesktop"
        status: pass
    human_judgment: false
  - id: D5
    description: "Toast queue and N1 copy (UI-SPEC Surface 4)"
    requirement: TILE-03
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/NoticeQueueTests.swift; Tests/PaneMacTests/NoticeCopyTests.swift"
        status: pass
    human_judgment: true
    rationale: "Toast styling in light and dark, focus, click-through and the VoiceOver reading are the plan's human-check"

duration: 20min
completed: 2026-10-26
---

# Phase 3 Plan 06: Lost-room floats, the echo rule and the toast surface Summary

**A docked window that stops fitting (a larger learned minimum, a narrower display) now floats to the Desktop tile through `World.reflow`, and a click-through toast says so (N1). Pane ignores its own writes when they come back (within 2 pt of the last `frameApplied`), puts a docked window back in its tile at most once per second when its app moves it, and records floating windows where they are left.**

## Performance

- **Duration:** about 20 min
- **Started:** 2026-10-26T02:55:14Z
- **Completed:** 2026-10-26T03:15:21Z
- **Tasks:** 2 (4 commits)
- **Files:** 8 created, 5 modified

## Accomplishments

- **Lost room (D-26).** After every plan, each shown desk's `unfit` docked windows are floated through `World.reflow`:
  - The window leaves the tree and goes onto the Desktop layer at its current frame, clamped into the Desktop rect computed with every window of that pass already floating. No undo step is added.
  - The desk is planned again. A floated window's minimum sizes the Desktop tile, so a neighbour can lose its room in turn. The loop repeats until every docked window fits; each pass removes at least one window from the tree, so it ends.
  - Every window floated in one re-plan (across displays) is named in one `.notice(.lostRoom([…]))`, sorted by identity.
  - Dock and drops still dry-run and refuse up front, so this path only runs for changes after a window docked.
- **Echo rule.** `frameApplied` stores the read-back in `lastApplied`. A `windowMoved`/`windowResized` within 2 pt of it is Pane's own write: nothing is answered. For a floating window the frame is still recorded as a fact. A refused write's read-back is therefore an echo too.
- **App moves of docked windows.** A non-echo move of a present docked window clears that window's `lastRequested` and re-plans, which writes the tile again. Inside one second of the last correction it waits instead: the Arranger returns `.wake(at: last + 1 s)` (the earliest due window), and `.tick` corrects only windows still off their tile. A window already within 2 pt of its tile is left alone. There is no pointer state yet, so every move counts as finished. Plan 10 adds drag sessions.
- **Floating moves (TILE-07).** The new frame is recorded with `World.recordFloatingFrame`. If it now overlaps a docked tile, the planner's clamp into the Desktop rect is recorded too and written.
- **Toast surface (UI-SPEC Surface 4).**
  - `NoticeQueue<Item: QueueableNotice>` is a pure value type. It shows one notice at a time. A newer notice replaces the visible one, or merges into it when they are the same kind. A crash notice is never replaced: later notices queue behind it (up to 3, the oldest dropped). Notices stay up 6 s, crash notices 10 s.
  - `NoticeCopy` gives the N1 singular and plural copy with curly quotes, app names through `MenuCopy.truncatedAppName`, and glyph `macwindow`.
  - `ToastPresenter` owns one `[.borderless, .nonactivatingPanel]` panel subclass that can never become key or main. It sets `ignoresMouseEvents`, `.floating`, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, `sharingType = .none` and a shadow. Content is a HUD `NSVisualEffectView` (radius 12) holding the SwiftUI HStack, text styles only. The toast is centred 16 pt below the top of the affected display's visible frame, placed through `Coordinates`. It fades in over 160 ms and out over 240 ms, and every shown toast posts the same text as a VoiceOver announcement.
  - `ArrangeController` runs `.notice` through the queue and the presenter. Expiry is scheduled on a `WakeTimer`. App names come from `NSRunningApplication.localizedName`, falling back to the bundle ID. The toast goes on the display of the first named window.
- **Wake-up.** `WakeTimer` is one replaceable `Task` sleeping until an instant. `ArrangeController` feeds `.tick` when the Arranger's wake fires.
- **Fake.** `FakeWindowSystem.userMove(_:to:)` changes the frame and refreshes the app, so the tracker reports the move with no `frameApplied`. The engine test `Harness` feeds inputs at a settable `now`.

## Task Commits

1. **Task 1 (tracer): a docked window that turns out too big floats with a notice**: `a452ba4` (test, RED), `a73c704` (feat, GREEN)
2. **Task 2: echo rule, app moves of docked windows, floating-window facts**: `2d4248b` (test, RED), `8b09dd8` (feat, GREEN)

## TDD Gate Compliance

- Every task starts with a `test(03-06)` commit, and a `feat(03-06)` commit follows it.
- **Task 1 RED:** `RED_EVIDENCE_OK`, target `aDockedWindowThatLosesItsRoomFloatsToTheDesktopWithANotice()`. Record: `.planning/phases/03-tiling-mvp/tdd/03-06-task1-red.json`.
  - All 10 unit tests failed on their planned assertions, against stubs that compile: `ArrangerEffect.notice` was never emitted, and `NoticeQueue` and `NoticeCopy` had empty bodies.
  - The precondition rows passed: b fits at 610 pt, and three windows dock.
  - The live test was not run at RED, to keep live runs down.
- **Task 2 RED:** `RED_EVIDENCE_OK`, target `aDockedWindowItsAppMovedIsPutBackAtMostOncePerSecond()`. Record: `.planning/phases/03-tiling-mvp/tdd/03-06-task2-red.json`.
  - The target failed with no correction and no wake. `.tick` was a stub that does nothing.
  - These rows passed at RED by design, as guards for behaviour that already holds and must keep holding once moves are corrected:
    - echo
    - refusal echo
    - floating inside the Desktop
    - floating onto a tile
    - narrower display
    - WakeTimer
- **Tracer gate after Task 1:** the automated verify was re-run end to end (unit, live, no-AppKit) and passed before Task 2 started. The plan's human-check is deferred to end-of-phase UAT (`human_verify_mode: end-of-phase`), the same as in 03-05.
- No refactor commits.

## Verification

- `swift test --filter "ArrangerReflowTests|NoticeQueueTests|NoticeCopyTests"`: 3 + 8 tests ran and passed. NoticeQueueTests appear in the output.
- `caffeinate -d -i swift test --filter ArrangeIntegrationTests`, from a trusted terminal, with the lock checked first:
  - Run after Task 1 and again after Task 2: 3 passed both times.
  - The fullscreen test is skipped by its `PANE_LIVE_FULLSCREEN` opt-in, because the live-test rules forbid Space switches.
  - No fixtures were left over.
- `swift test --filter "ArrangerReflowTests|ArrangerLifecycleTests|ArrangerSpacesTests"`: 37 tests passed.
- `swift test --skip PaneMacIntegrationTests`: 189 + 112 + 284 tests passed.
- `scripts/check-no-appkit.sh`: OK (31 files).
- Acceptance greps:
  - `case lostRoom` in Notice.swift: 1.
  - `nonactivatingPanel` in Toast.swift: 1.
  - `sharingType = .none` in Toast.swift: 1.
  - `system(size` in Toast.swift: 0.
  - `func userMove` in FakeWindowSystem.swift: 1.
  - `case wake` in Arranger.swift: 1.
  - `lastApplied` in Arranger.swift: 5.

## Deviations from Plan

**1. [Rule 1 - Correctness] Lost-room floating loops until everything fits**
- **Found during:** Task 1 design
- **Issue:** The plan says to re-plan "once more". The 03-04 Planner sizes the Desktop tile to the largest minimum among the present floating windows. A floated window can therefore leave a neighbour unfit. A single re-plan would leave that neighbour with no rect, overlapping its neighbours.
- **Fix:** The float-then-plan loop repeats, bounded by the number of docked windows, and everything floated shares one notice. Pinned by `windowsLosingRoomInOneReplanGiveOneNotice`.
- **Commit:** a73c704

**2. [Test design] NoticeQueue is generic**
- **Issue:** Phase 3 has only one `Notice` case so far. That makes "a notice of another kind replaces it" and the crash-notice rules untestable against `Notice` itself.
- **Fix:** `NoticeQueue<Item: QueueableNotice>` has two requirements, `isCrashNotice` and `merged(with:)`. The shell uses `NoticeQueue<Notice>`. The tests use a three-kind `TestNotice`, plus one merge row on the real `Notice`.
- **Commit:** a452ba4, a73c704

**3. [Rule 1 - Test bug] The live test docked before the tracker saw the window's size**
- **Found during:** Task 1 live verification
- **Issue:** The live test failed 3 times on "window 0's minimum was never learned". The third failure was an accidental rerun I started while trying to read the second run's message. I stopped after that and diagnosed instead of rerunning:
  - A fake reproduction showed the Arranger path learns correctly.
  - One instrumented live run, with temporary prints that were reverted, showed the cause: the wait checked only x. Window 0 already started at x = 40, so Dock wrote before the tracker had seen the resize. A write only teaches a minimum when the window moves toward the request from its tracked size (02-15).
  - The same wait bug made window 1 dock above the Desktop instead of beside it.
- **Fix:** The test waits for the whole frame. It also waits for Pane's clamp of window 1 into the Desktop tile before moving it. It passed on its next three live runs, two of them as part of the full suite. The fake reproduction became a test: `minimumsLearnedFromRefusedWritesFloatTheWiderWindowClearOfItsNeighbour`.
- **Commit:** a73c704

**4. [Scope] Files outside the plan's list**
- `Tests/PaneMacTests/WakeTimerTests.swift` covers the "only the latest wake" row.
- `ArrangerLifecycleTests.swift` gains `Harness.now`, so the once-per-second rule is tested with explicit instants.
- `postAnnouncement` moved into Toast.swift and is shared by `.announce` and toasts.
- **Commit:** 2d4248b, a73c704

**Total deviations:** 4 (1 correctness, 1 test design, 1 test bug, 1 scope). **Impact:** no product scope change.

## Known limits (not stubs)

- **Lost room usually floats the whole row.** A docked neighbour survives a lost-room float only in a band about 9 pt wide. The pair's minimums must exceed the row with the Desktop tile, yet fit beside a Desktop tile sized to the floated window. In nearly every real case the neighbours sharing that axis float too. This follows from the 03-04 rule that the Desktop tile holds its floating windows' minimums, which is what keeps floats from overlapping tiles. Worth a product look in UAT; Phase 4's "represented" windows are the planned answer.
- **Docked windows are pulled back during a user drag.** Every move counts as finished until plan 10 adds drag sessions. A user dragging a docked window is corrected once per second.
- **Learning needs a tracked size first** (02-15 limit, confirmed live). A window whose first write lands before the tracker has seen its current size teaches nothing until a later write moves it.
- **The toast goes on the first named window's display** when one notice names windows on several displays.

## Requirements

TILE-03 and TILE-07 were already marked Complete in REQUIREMENTS.md by earlier plans. This plan adds the lost-room, echo and app-move behaviour and leaves their status unchanged.

## Threat Flags

None new. The mitigations are in place:
- **T-03-13:** a docked window is corrected at most once per second, and the wake is a single replaceable timer.
- **T-03-14:** toasts show only app names (truncated to 32) and counts, never titles, and the panel is click-through and can never become key or main.

## Human checks pending (from the plan)

- In Pane Debug, dock three windows side by side, one of them an app with a large minimum width (System Information or Xcode). Do it in light and dark appearance, and once with VoiceOver on.
- Expected: the too-big window floats to the Desktop tile, and a toast appears at the top of that display: "A “…” window no longer fits its tile, so it's floating on the Desktop."
- Expected: the toast does not take focus or block clicks, fades after 6 s, and VoiceOver reads the same text.
- Given the known limit above, the other two windows may float as well.

## Self-Check: PASSED

The created files exist (Notice.swift, NoticeQueue.swift, Toast.swift, NoticeCopy.swift, ArrangerReflowTests.swift, NoticeQueueTests.swift, NoticeCopyTests.swift, WakeTimerTests.swift). Commits a452ba4, a73c704, 2d4248b and 8b09dd8 are ancestors of HEAD.
