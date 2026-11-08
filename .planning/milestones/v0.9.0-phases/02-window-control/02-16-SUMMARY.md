---
phase: 02-window-control
plan: 16
subsystem: window-identity
tags: [swift, accessibility, ax-private, fallback, window-id, rekey, tab-groups, capability-session]

requires:
  - phase: 02-window-control
    provides: "02-11 FallbackMatcher, synthetic IDs and CapabilitySession; 02-14 TabGroupTracker Spaces rules and fold guard; 02-15 learner candidates"
provides:
  - "WindowEvent.windowRekeyed(from:to:): the same window under a corrected ID, never a destroy and create pair"
  - "WindowTracker.rekey(from:to:): moves or merges a window's info, creation order, facts, rechecks, fold state, learner state and tab membership"
  - "TabGroupTracker.rekey(pid:from:to:newLeader:) and MinimumSizeLearner.rekey(from:to:)"
  - "WindowIDResolver (PaneMac, thread-confined): per-element failure counting, re-check of fallback IDs, the lookup's element owns its ID, first-failure wait"
  - "WindowObservation.replacesWindowID, AppObservation.identityPending, public Capabilities.session"
  - "AXWindowSystem.setForceWindowIDFallback(_:) test seam"
affects: [phase-03-tiling, phase-04-zoom, phase-06-spaces, SAFE-06]

actuals:
  tokens: 16900
  tasks: 3
  commits: 6
plan_head_before: 3908b5c52918fb76579a4466fcb32ba1026e20c9
plan_head_after: f4b06a9acfc0ffc9d1dbfa9afdeb751f0f9985e6

tech-stack:
  added: []
  patterns:
    - "Identity changes are explicit events: an observation carries replacesWindowID and the tracker re-keys before anything else"
    - "Two-pass ID resolution per refresh: lookups first (claims), then cached fallback IDs nobody claimed, then the frame fallback excluding every bound ID"

key-files:
  created:
    - Sources/PaneMac/AX/WindowIDResolver.swift
    - Tests/PaneMacTests/WindowIDResolverTests.swift
  modified:
    - Sources/PaneEngine/WindowSnapshot.swift
    - Sources/PaneEngine/WindowSystem.swift
    - Sources/PaneEngine/LifecycleSync.swift
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneEngine/TabGroupTracker.swift
    - Sources/PaneEngine/MinimumSizeLearner.swift
    - Sources/PanePrivate/Capabilities.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Tests/PaneEngineTests/WindowTrackerTests.swift
    - Tests/PaneEngineTests/TabGroupTrackerTests.swift
    - Tests/PaneEngineTests/LifecycleSyncTests.swift
    - Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift

key-decisions:
  - "02-16: A lookup success is counted only for real lookups (new elements and re-checks of fallback IDs); a cached axPrivate element is never looked up again and counts nothing, so a lookup that really broke mid-session still switches off"
  - "02-16: A lookup failure counts towards switching AXWindowID off at most once per element while it stays listed (CFEqual set pruned to the listed elements each refresh)"
  - "02-16: The element _AXUIElementGetWindow names owns that ID; a holder that had it by frame match is re-identified by frame or synthetic ID and re-keyed, so no two elements share an ID"
  - "02-16: Phase 3 obligation: windowRekeyed(from:to:) is not applied by LifecycleSync; Phase 3 must re-point any desk WindowRef from `from` to `to.window`"
  - "02-16: A first lookup failure of a new element never takes an offscreen-only frame match; the app is refreshed after the settle delay (identityPending)"
  - "02-16: A window tracked under both IDs merges into the existing entry with the older creation order and the larger learned minimum per axis, never added to the closed IDs"

patterns-established:
  - "Re-key, never destroy and create: any ID correction goes through WindowTracker.rekey and one windowRekeyed"

requirements-completed: [SAFE-05, WIN-02]

coverage:
  - id: D1
    description: "A window tracked under a fallback ID is re-keyed to its real ID as one windowRekeyed, keeping creation order, title and learned minimum; a pending one moves silently; LifecycleSync applies nothing for it"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/WindowTrackerTests.swift#RekeyTests"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/LifecycleSyncTests.swift#nonLifecycleEventsLeaveTheWorldUnchanged(event:)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Live: two identical fixture windows tracked under synthetic IDs are re-keyed to their real CGWindowIDs once the lookup works (two windowRekeyed, no create or destroy); the reader reports a cached synthetic element under its real ID with replacesWindowID"
    requirement: WIN-02
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift#syntheticIDsAreRekeyedToTheRealIDsOnceTheLookupWorks()"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift#anElementCachedUnderAFallbackIDIsReportedUnderItsRealIDOnceTheLookupWorks()"
        status: pass
    human_judgment: false
  - id: D3
    description: "Gap 4: one element that keeps failing never switches _AXUIElementGetWindow off; five distinct failing elements switch it off once; a success in between keeps it on"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/WindowIDResolverTests.swift#oneElementThatKeepsFailingNeverSwitchesTheLookupOff()"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/WindowIDResolverTests.swift#fiveDistinctFailingElementsSwitchTheLookupOffOnce()"
        status: pass
    human_judgment: false
  - id: D4
    description: "Gap 5: fallback IDs are re-checked and replaced, the lookup's element owns its ID, a frame-matched holder is re-identified, a first failure waits for its own CG entry, and no two elements ever share an ID"
    requirement: WIN-02
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/WindowIDResolverTests.swift#WindowIDResolverTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "Re-keys keep tab groups (leader and shown member), merge duplicates, and correct a wrong frame match to a cross-Space twin with the twin tracked on its own"
    requirement: WIN-02
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/WindowTrackerTests.swift#RekeyGroupTests"
        status: pass
      - kind: unit
        ref: "Tests/PaneEngineTests/TabGroupTrackerTests.swift#aRekeyedLeaderRenamesTheIDAndHandsTheGroupToTheNewLeader()"
        status: pass
    human_judgment: false
  - id: D6
    description: "Real apps: no 'AXWindowID failed 5 times' line in 10 minutes of normal use, and with --disable-private=AXWindowID rows show 'by frame', appear and disappear normally and never duplicate"
    requirement: SAFE-05
    verification: []
    human_judgment: true
    rationale: "Real-app lookup failures cannot be provoked from the fixture (VERIFICATION human item 'Signed app with the private API forced off'); the Task 3 human-check"

duration: 19min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 16: Window-ID Re-keying and Per-Element Failure Counting Summary

**A window first identified by frame or by a synthetic ID is looked up again on every refresh and re-keyed to its real CGWindowID as one `windowRekeyed`, never closed and reopened. A new thread-confined `WindowIDResolver` counts each failing element once, so one stubborn window can no longer switch `_AXUIElementGetWindow` off for every app. It also makes sure the element the lookup names owns that ID.**

## Performance

- **Duration:** 19 min
- **Started:** 2026-10-25T19:51:54Z
- **Completed:** 2026-10-25T20:10:35Z
- **Tasks:** 3
- **Files modified:** 16 (plus 4 TDD evidence records)

## Accomplishments

- `WindowEvent.windowRekeyed(from:to:)` and `WindowTracker.rekey(from:to:)`. A rekey moves the window's info (same creation order, title and AX identifier), `visibleMemberID`, classification facts, rechecks, fold state and learner state (minimum and candidate). It never adds anything to the closed IDs. A pending window keeps its settle start under the new ID. `ingest` re-keys every observation that carries `replacesWindowID` before it does anything else.
- Through tab groups: a group whose identity is re-keyed keeps its tabs under the new leader. A re-keyed tab that is not the group's identity is renamed in the group, and the group window showing it reports one `windowChanged`. A window tracked under both IDs (the old duplicate bug) merges into one entry, keeping the older creation order and the larger minimum per axis.
- `WindowIDResolver` replaces the reader's cache-first `windowID(of:)` and its `Fallback` struct. It lives beside the element cache on each `AXAppThread` and resolves in two passes:
  - **Pass 1:** cached `.axPrivate` elements keep their IDs with no lookup. Every other element is looked up once while the lookup is available.
  - **Pass 2:** a cached fallback ID that no element claimed in pass 1 is kept. Everything else goes through the frame fallback, excluding every ID already bound.
- Failure counting: a failure counts at most once per listed element, and every successful real lookup resets the count. A first failure never takes an offscreen-only frame match. The element stays unidentified, and `identityPending` makes AXWindowSystem refresh the app after the settle delay.
- AXWindowSystem re-points `focusedIdentities`, `mainWindowIDs`, `pendingFocus` and the last reported minimum on every `windowRekeyed`. `setForceWindowIDFallback(_:)` flips the lock-guarded flag on every app thread live.
- Live: two identical fixture windows tracked under synthetic IDs became their real IDs within 2 s of the flip. That produced two `windowRekeyed` events and no create or destroy.

## Task Commits

1. **Task 1: Tracer, synthetic ID re-keyed to the real ID, live**: `c50242c` (test, RED), `f150c9c` (feat, GREEN)
2. **Task 2: WindowIDResolver**: `d710947` (test, RED), `efdc81a` (feat, GREEN)
3. **Task 3: Re-key through tab groups and duplicates**: `09177c1` (test, RED), `f4b06a9` (feat, GREEN)

## TDD Gate Compliance

Each task has a `test(02-16)` commit before its `feat(02-16)` commit. All four RED records returned `RED_EVIDENCE_OK`, and each failed on its planned assertions against compiling stubs.
- `tdd/02-16-task1-red.json`, target `aSyntheticWindowIsRekeyedToItsRealIDAndStaysOneWindow()`: two windows and no `windowRekeyed` against a `rekey` stub. The pending-move row failed as planned. The unknown-rekey row and the LifecycleSync row passed by design.
- `tdd/02-16-task1-live-red.json`, target `syntheticIDsAreRekeyedToTheRealIDsOnceTheLookupWorks()`: both windows stayed synthetic after the flip. The inverted WR-02 reader row failed on all four assertions. The first RED run exposed a test race (see Deviations), and this record is from the re-run.
- `tdd/02-16-task2-red.json`, target `oneElementThatKeepsFailingNeverSwitchesTheLookupOff()`: every behaviour row failed against an all-nil resolver stub. GREEN was then mutation-checked: removing the "claimed" check in pass 2 makes both collision tests fail.
- `tdd/02-16-task3-red.json`, target `aTabGroupLedByASyntheticIDKeepsItsTabsUnderTheRealID()`: with the Task 1 rekey alone, R joined the old group by the room rule, and the refresh reported a new window under X. The cross-Space twin row already passed on the Task 1 code and stays as a guard for the end-to-end case.

## Tracer gate

The mode is end-of-phase and the tracer's verify is automated only. After GREEN, both verify commands passed: the tracker and LifecycleSync suites, and the live FallbackIntegrationTests (4 run, none skipped). The tracer is verified end to end, so Task 2 went ahead.

## Verification

- `swift test --skip PaneMacIntegrationTests`: all pass (142 + 96 + 208 across the three test products).
- `caffeinate -d -i swift test --filter PaneMacIntegrationTests`: 24 pass. FallbackIntegrationTests ran (4 tests), and the only skip is the existing two-display test. Afterwards `pgrep -fl PaneFixtureApp` printed nothing.
- `scripts/check-no-appkit.sh`: OK (24 files). `scripts/build-debug.sh`: exits 0 (valid on disk, satisfies its designated requirement).
- Acceptance greps: `func rekey(from` 1, `windowRekeyed` in WindowSystem 1 and in LifecycleSync 2, `replacesWindowID` 3, `func setForceWindowIDFallback` 1, `struct WindowIDResolver` 1, `WindowIDResolver` in the reader 4, `public static let session` 1, `identityPending` in AXWindowSystem 1, `func rekey(pid` 1.
- Live runs: 5 in total (two Task 1 REDs, Task 1 GREEN, the Task 2 suites, the full integration suite). Each ran under `caffeinate -d -i` after a lock check (`locked: nil`). Only fixture windows were touched.

## Decisions Made

- **Discretion choice (as planned): successes come only from real lookups.** That means new elements and re-checks of fallback-identified elements. A cached `.axPrivate` element is never looked up again and records nothing. Crediting cached windows would keep a lookup that really broke mid-session switched on for as long as any old window exists.
- **Event contract change, a Phase 3 obligation.** `WindowEvent.windowRekeyed(from: WindowRef, to: WindowInfo)` is new. LifecycleSync applies nothing for it today. Phase 3 must re-point any desk's `WindowRef` from `from` to `to.window`. `WindowRef` equality is by identity, so a ref held under the old ID no longer matches.
- `ingest` gives the `from` entry the observation's `idSource` before re-keying, so the `windowRekeyed` event carries the window's final info (`.axPrivate`).
- The first-failure rule rejects only an offscreen `.cg` match, as planned. If a new element's first failure finds no candidate, or an ambiguous one, it still gets a synthetic ID at once. That ID is looked up again on every refresh and re-keyed once the lookup works.
- The CapabilitySession log line ("failed 5 times in a row") was left as it is. It is still accurate: five counted failures, now from distinct elements, with no success between them.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TabGroupTracker.rekey leaves `lastCG` alone**
- **Found during:** Task 3
- **Issue:** The plan renames the ID in `lastCG` too. But `lastCG` holds real CG entries. For a wrong `.cgFrameMatch` T, the T entry there is the twin's own window. Renaming it to R_E would make the twin look brand new (Cmd-T rule) at its next refresh, and would give R_E the twin's offscreen slot history (orphan handoff evidence). For a synthetic ID, the entry is a presence copy, and R's real entry is already there.
- **Fix:** Members, shown tab, leader and `lastListed` are renamed. `lastCG` is not, and a doc comment says why.
- **Files modified:** Sources/PaneEngine/TabGroupTracker.swift
- **Committed in:** f4b06a9

**2. [Rule 2 - Missing critical] `pendingFocus` follows a re-key**
- **Found during:** Task 1
- **Issue:** A focus hint names the thread's cached (old) ID. After a re-key in the same refresh, it would match no window, and the `windowFocused` would be lost.
- **Fix:** `emit` re-points `pendingFocus` along with `focusedIdentities` and `mainWindowIDs`.
- **Files modified:** Sources/PaneMac/AXWindowSystem.swift
- **Committed in:** f150c9c

**3. [Rule 1 - Bug, test] Live flip test race**
- **Found during:** Task 1 RED
- **Issue:** EventLog reads the event stream asynchronously. The flip index was taken before the second `windowCreated` arrived, so that event counted as "after the flip".
- **Fix:** The test waits for both creates in the log before it flips. RED was re-run, and the record is from the re-run.
- **Files modified:** Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
- **Committed in:** c50242c

**4. [Rule 2 - Defensive] Synthetic IDs also avoid every bound and cached ID**
- **Found during:** Task 2
- **Issue:** The allocator avoided only the IDs in the CG list.
- **Fix:** It now also avoids the IDs bound this pass and the cache keys.
- **Files modified:** Sources/PaneMac/AX/WindowIDResolver.swift
- **Committed in:** efdc81a

---

**Total deviations:** 4 auto-fixed (2 bugs, 2 missing critical or defensive). **Impact:** all are inside the plan's files. No scope creep.

## Known limits

- **A holder with no frame or no CG list loses its window to the owner.** When another element's lookup claims a holder's frame-matched ID, and the holder cannot be re-identified this pass (no readable frame, or no CG list), the holder stays unidentified. The owner then takes over the tracked entry, and the holder appears as a new window at a later refresh. This needs a lookup failure, a collision and a failed read in the same refresh.
- **A tab re-keyed inside a group does not re-point `pendingFocus`.** That path emits `windowChanged`, which carries no old ID, so one focus hint can be lost.
- **One lookup per fallback-identified element per refresh** while the lookup works. Elements identified through the lookup cost nothing extra.
- **Not done here (02-17):** in fallback mode, refuse a handoff or merge in the same refresh as an `NSWorkspace.activeSpaceDidChangeNotification`.

## Issues Encountered

None.

## Threat Flags

None. There is no new endpoint, file access or trust-boundary surface. T-02-42 is mitigated: the lookup's element owns its ID, holders are re-identified, unique byID keys are enforced on insert and asserted in every resolver test, and a first failure never takes an offscreen-only match. T-02-43 is mitigated: one counted failure per listed element, and five distinct failures still switch the lookup off once. T-02-44 is mitigated: every ID change is an explicit `windowRekeyed` carrying both refs.

## Human UAT (end of phase, Task 3 human-check)

Run Pane Debug for 10 minutes of normal use across several apps: open and close windows, switch tabs and Spaces. Then run `log show --predicate 'subsystem == "com.eightabyte.pane" AND category == "private"' --last 15m`. Relaunch with `scripts/run-debug.sh --no-build --disable-private=AXWindowID`, open and close windows, and watch Tracked Windows.

Expected: no "AXWindowID failed 5 times" line in normal use, and Debug still shows "Window ID lookup: available". With the flag, rows show "by frame", appear and disappear normally, and never duplicate.

## User Setup Required

None.

## Next Phase Readiness

- VERIFICATION gaps 4 and 5 (SAFE-05, WIN-02) are closed in code and in tests.
- 02-17 (refusing a fallback handoff or merge in a refresh with a Space change) is next, then Phase 2 re-verification.
- Phase 3 must handle `windowRekeyed` (see Decisions) and must treat synthetic IDs as session-only, as before.

## Self-Check: PASSED

- FOUND: Sources/PaneMac/AX/WindowIDResolver.swift, Tests/PaneMacTests/WindowIDResolverTests.swift, and the four tdd/02-16-*.json records
- FOUND commits: c50242c, f150c9c, d710947, efdc81a, 09177c1, f4b06a9 (all ancestors of HEAD; `evaluation-scope` resolved them on this branch)
- No "RED stub", TODO, FIXME or placeholder left in the changed sources
- Every task's acceptance criteria and the plan-level verification commands were re-run and pass, as listed above

---
*Phase: 02-window-control*
*Completed: 2026-10-25*
