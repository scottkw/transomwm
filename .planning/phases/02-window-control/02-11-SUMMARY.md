---
phase: 02-window-control
plan: 11
subsystem: window-tracking
tags: [ax, cgwindowlist, private-api, fallback, os-allocated-unfair-lock, swift-testing]

requires:
  - phase: 02-window-control (02-09)
    provides: AXWindowSystem, AXAppThread element cache, CloseRule two-source close decisions
  - phase: 02-window-control (02-08)
    provides: Tracked Windows footer and Debug menu capability caption, "by frame" ID column
  - phase: 02-window-control (02-10)
    provides: TabGroupTracker with visibleMemberID on every window
provides:
  - FallbackMatcher (pid + frame + title match, synthetic CG presence) in PaneEngine
  - CapabilitySession call-time degradation (5 consecutive failures switch a capability off for the session)
  - Window identity without `_AXUIElementGetWindow` on each app thread (cgFrameMatch or synthetic IDs)
  - AXWindowSystem(appFilter:forceWindowIDFallback:) test seam
affects: [03 tiling (window identity in fallback mode), 08 VIEW-04 (synthetic IDs are session-only)]

actuals:
  tokens: 14551
  tasks: 2
  commits: 3
plan_head_before: df5879756abef6dc197ab199b5d22ed366a74768
plan_head_after: 7a267e6655cec4acb00e87e4d438eac5fb53019a

tech-stack:
  added: []
  patterns:
    - "Process-wide mutable state lives in a Sendable instance (CapabilitySession) behind OSAllocatedUnfairLock; tests build their own instance instead of touching the shared one"
    - "Synthetic IDs get CG presence one-to-one: each CG entry vouches for one synthetic window, windows AX lists now claim first"

key-files:
  created:
    - Sources/PaneEngine/FallbackMatcher.swift
    - Sources/PaneMac/AX/SyntheticWindowIDs.swift
    - Tests/PaneEngineTests/FallbackMatcherTests.swift
    - Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
  modified:
    - Sources/PanePrivate/Capabilities.swift
    - Sources/PaneMac/AX/AXSnapshotReader.swift
    - Sources/PaneMac/AX/AXAppThread.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/CGWindowList.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Shell/TrackedWindowsView.swift
    - Sources/PaneMac/Shell/TrackedWindowsWindowController.swift
    - Sources/PaneFixtureApp/main.swift
    - Tests/PaneMacTests/CapabilitiesTests.swift

key-decisions:
  - "Capability session state is a CapabilitySession instance (Capabilities.session is the shared one); a static global would let CapabilitiesTests switch the lookup off for the integration tests in the same test process"
  - "syntheticPresence is one-to-one: each same-bounds CG entry vouches for at most one synthetic window, never for an entry a tracked window owns, and windows AX lists this refresh claim first; otherwise closing one of two identical synthetic windows would never close"
  - "In fallback mode a cached AX element keeps its ID and source for its cache life; an element already given an axPrivate ID keeps it after the lookup is switched off mid-session"
  - "While the lookup is available a failed lookup still yields no ID for that refresh (as before); only the call that switches it off falls through to the frame fallback at once"
  - "The Tracked Windows footer takes a closure and reads the capability on every render, so a mid-session switch-off shows there as well as in the Debug menu"

patterns-established:
  - "Fallback identity is decided on the app thread from one CG snapshot per observation; CG names are fetched only when the first match is ambiguous and are never logged or stored"

requirements-completed: [SAFE-05]

coverage:
  - id: D1
    description: "FallbackMatcher matches an AX window to its same-pid CG window by bounds (±1 pt), preferring layer 0, a single onscreen entry, then a matching CG name; ambiguous otherwise"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FallbackMatcherTests.swift#FallbackMatcherTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Synthetic IDs count as present in CG while an unclaimed same-pid same-bounds CG window exists"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/FallbackMatcherTests.swift#eachCGWindowVouchesForOneSyntheticWindowInListedOrder()"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift#identicalWindowsGetDistinctIdentitiesAndCloseOneAtATime()"
        status: pass
    human_judgment: false
  - id: D3
    description: "5 consecutive unexpected lookup failures switch the capability off for the session exactly once, safe under concurrency"
    requirement: SAFE-05
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/CapabilitiesTests.swift#CapabilitySessionTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "With window-ID lookup forced off, fixture windows and a tab group are tracked by CG frame match, identical twins get distinct synthetic IDs and close one at a time"
    requirement: SAFE-05
    verification:
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift#FallbackIntegrationTests"
        status: pass
    human_judgment: false
  - id: D5
    description: "`swift run PaneApp --print-inventory-summary --disable-private=AXWindowID` launches and prints the summary line (ROADMAP SC5)"
    requirement: SAFE-05
    verification:
      - kind: other
        ref: "swift run PaneApp --print-inventory-summary --disable-private=AXWindowID | grep -E '^pane: tracked windows=[0-9]+ apps=[0-9]+$'"
        status: pass
    human_judgment: false
  - id: D6
    description: "Signed Debug app with --disable-private=AXWindowID shows \"Window ID lookup: off, matching by frame\" in the Debug menu and footer, and windows come and go normally"
    requirement: SAFE-05
    verification: []
    human_judgment: true
    rationale: "Needs the signed app launched through LaunchServices and a person opening menus and windows; real-app behaviour is end-of-phase UAT"

duration: 10min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 11: Window-ID Fallback Summary

**Without `_AXUIElementGetWindow`, Pane matches each AX window to its same-pid CG window by frame (then CG title), gives stable synthetic `0xF000_0000 | n` IDs only when that is ambiguous, keeps two-source closes for them, and switches a misbehaving lookup off for the session after 5 consecutive failures.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-10-25T16:26:51Z
- **Completed:** 2026-10-25T16:36:58Z
- **Tasks:** 2
- **Files modified:** 14 (plus 2 RED evidence records)

## Accomplishments
- `FallbackMatcher.match` and `syntheticPresence` (PaneEngine, Foundation-free), with 11 unit tests covering every behaviour row.
- `CapabilitySession`: consecutive-failure count and session-disabled set behind `OSAllocatedUnfairLock`; `Capabilities.isAvailable/recordFailure/recordSuccess/failureLimit`; `report()` is now session-aware.
- The app thread identifies windows through the fallback when the lookup is unavailable or forced off. Cached elements keep their IDs. New ones are matched against one CG snapshot per observation, and CG names are read only when a match is ambiguous.
- AXWindowSystem appends synthetic CG presence before every close decision (ingest, app quit, quit rechecks). Live: of two identical windows, closing one destroys exactly that one.
- `swift run PaneApp --print-inventory-summary --disable-private=AXWindowID` printed `pane: tracked windows=6 apps=6`, the same count as with the lookup on.

## Task Commits

1. **Task 1 RED: failing matcher and capability-session tests** - `a156b73` (test)
2. **Task 1 GREEN: fallback matcher and session-level degradation** - `ea19b5d` (feat)
3. **Task 2: track windows through the fallback** - `7a267e6` (feat)

## TDD Gate Compliance

- RED `a156b73`: `swift test --filter FallbackMatcherTests` (target `oneSamePidWindowWithEqualBoundsIsTheMatch()`, 9 of 11 failing on assertions against the `.none` stub) and `swift test --filter CapabilitySessionTests` (target `fiveConsecutiveFailuresSwitchTheCapabilityOffOnce()`, failing on its flip sequence against a never-flipping stub). Both returned `RED_EVIDENCE_OK`. Semantic check: the targets ran and failed on the planned assertions, with no build, load or fixture faults. The rows that passed in RED ("no presence", "reset", "not loaded") pass trivially against an empty stub, which is expected. Records: `tdd/02-11-task1-red.json`, `tdd/02-11-task1b-red.json`.
- GREEN `ea19b5d`: all 11 matcher tests and the 7 capability tests pass.
- REFACTOR: none needed.
- Task 2 is `type="auto"` with no `tdd` flag. It is covered by the new integration suite.

## Files Created/Modified
- `Sources/PaneEngine/FallbackMatcher.swift`: pure matching and synthetic presence.
- `Sources/PanePrivate/Capabilities.swift`: `CapabilitySession`, shared session, static wrappers.
- `Sources/PaneMac/AX/AXSnapshotReader.swift`: `CachedWindow`; private lookup with success/failure reporting; `Fallback` identification.
- `Sources/PaneMac/AX/AXAppThread.swift`: cache holds `CachedWindow`; probes keep the cached ID source; `forceWindowIDFallback`.
- `Sources/PaneMac/AX/SyntheticWindowIDs.swift`: locked counter in the reserved range, avoiding CG IDs.
- `Sources/PaneMac/CGWindowList.swift`: `names(pid:)` for ambiguous matches only.
- `Sources/PaneMac/AXWindowSystem.swift`: init seam, `withSyntheticPresence`, focus hint through `visibleMemberID`.
- `Sources/PaneMac/PaneMacApp.swift`, `Shell/TrackedWindowsView.swift`, `Shell/TrackedWindowsWindowController.swift`: footer caption read live.
- `Sources/PaneFixtureApp/main.swift`: `title <i> <text>` command.
- `Tests/PaneEngineTests/FallbackMatcherTests.swift`, `Tests/PaneMacTests/CapabilitiesTests.swift`, `Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift`.

## Decisions Made
See `key-decisions` in the frontmatter. The two that change the plan's literal wording:
- Synthetic presence is one-to-one. Without that, the plan's own integration case (close one of two identical windows) could never close.
- Capability state is an instance, so tests don't share process-global state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] One-to-one synthetic CG presence**
- **Found during:** Task 1 (design of `syntheticPresence`)
- **Issue:** As worded ("present while a same-pid CG window with its bounds exists"), two identical synthetic windows both stay present after one closes, because the survivor's CG entry vouches for both. The closed one would be rechecked forever and never destroyed, which contradicts the plan's integration case (b).
- **Fix:** Each CG entry vouches for at most one synthetic window, never for an entry a tracked window owns. AXWindowSystem lists the windows AX shows this refresh first, using their current frames.
- **Files modified:** Sources/PaneEngine/FallbackMatcher.swift, Sources/PaneMac/AXWindowSystem.swift
- **Verification:** `eachCGWindowVouchesForOneSyntheticWindowInListedOrder()`, `nonSyntheticWindowsGetNoPresenceAndKeepTheirOwnCGEntry()`, and live `identicalWindowsGetDistinctIdentitiesAndCloseOneAtATime()` with both twins synthetic
- **Committed in:** ea19b5d, 7a267e6

**2. [Rule 2 - Missing critical] Live footer caption**
- **Found during:** Task 2
- **Issue:** The Tracked Windows footer got the capability as a `Bool` at launch, so a mid-session switch-off would never show there. Must-have: "the menu and footer then read 'Window ID lookup: off, matching by frame'".
- **Fix:** The view takes `() -> Bool`, and PaneMacApp passes `{ system.capabilityReport[.axWindowID] == true }`.
- **Files modified:** Sources/PaneMac/PaneMacApp.swift, Sources/PaneMac/Shell/TrackedWindowsView.swift, Sources/PaneMac/Shell/TrackedWindowsWindowController.swift
- **Verification:** builds; MenuCopyTests and TrackedWindowsModelTests pass. On-screen check is in UAT (D6).
- **Committed in:** 7a267e6

**3. [Rule 2 - Missing critical] Fixture `title` command so the synthetic path is really exercised**
- **Found during:** Task 2 verification
- **Issue:** This terminal can read CG window names, so the fixture's distinct titles ("Fixture 0/1") narrowed the identical-frame case to `.cgFrameMatch`. The synthetic ID and synthetic close path ran nowhere live.
- **Fix:** Added `title <i> <text>` to PaneFixtureApp. Test (b) gives both twins the same title and now asserts both are `.synthetic`, at least `0xF000_0000`, and not any fixture ID.
- **Files modified:** Sources/PaneFixtureApp/main.swift, Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
- **Verification:** FallbackIntegrationTests 2/2 pass with the synthetic assertions
- **Committed in:** 7a267e6

**4. [Rule 1 - Bug, deferred item from 02-10] Focus hint on a non-leader tab**
- **Found during:** Task 2 (AXWindowSystem is this plan's file)
- **Issue:** `pendingFocus` was looked up by identity window ID, so a focus hint on a non-leader tab emitted no `windowFocused`.
- **Fix:** Look the window up by `visibleMemberID`. The deferred item is marked resolved.
- **Files modified:** Sources/PaneMac/AXWindowSystem.swift, .planning/phases/02-window-control/deferred-items.md
- **Verification:** TabsIntegrationTests pass. No dedicated test: the tracker already emits `windowFocused` on a tab switch, so a live test cannot tell the two paths apart.
- **Committed in:** 7a267e6

---

**Total deviations:** 4 auto-fixed (2 bugs, 2 missing critical)
**Impact on plan:** All needed for the must-have truths or for a test that actually exercises them. No scope creep. The interface names are as planned; `Capabilities.failureLimit` is a computed static forwarding `CapabilitySession.failureLimit`.

## Issues Encountered
- No `.swift-format` config or CI lint step exists, and the toolchain default (2-space indentation) does not match the repo's 4-space code, so `swift format lint` was not applied.
- The intermittent `CloseIntegrationTests` unhide flake did not recur (2 runs: the targeted regression run and the full suite).

## Verification Run
- `swift test --filter "FallbackMatcherTests|CapabilitiesTests"`: pass (11 + 7, plus CapabilitySessionTests)
- `swift test --filter FallbackIntegrationTests`: 2 tests pass, not skipped
- `swift run PaneApp --print-inventory-summary --disable-private=AXWindowID`: `pane: tracked windows=6 apps=6`, grep matches
- `swift test --filter "FixtureTrackingTests|CloseIntegrationTests|TabsIntegrationTests"`: 3 tests pass
- Full `swift test`: exit 0 (125 + 14 + 142 + 58 tests)
- `scripts/check-no-appkit.sh`: OK (22 files)

## End-of-Phase UAT (human-check)
- Run `scripts/run-debug.sh --no-build --disable-private=AXWindowID`, then open Tracked Windows and the Debug submenu, and open and close a few windows. Expected: the Debug menu shows "Window ID lookup: off, matching by frame", the footer shows the same caption, windows appear and disappear normally, and any ambiguous match shows "by frame" in the ID column. This confirms ROADMAP SC5 in the signed app launched through LaunchServices.
- Not checked live: call-time degradation (a present but failing lookup) cannot be triggered on this Mac. It is covered only by CapabilitySessionTests.

## User Setup Required
None. No external service configuration required.

## Next Phase Readiness
- SAFE-05 / ROADMAP SC5 are met in code and in tests. Phase 3 must treat synthetic IDs as session-only (they are never valid across launches), which matters for SAFE-06 layout restore.
- Ready for 02-12.

---
*Phase: 02-window-control*
*Completed: 2026-10-25*

## Self-Check: PASSED
- FOUND: Sources/PaneEngine/FallbackMatcher.swift, Sources/PaneMac/AX/SyntheticWindowIDs.swift, Tests/PaneEngineTests/FallbackMatcherTests.swift, Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift
- FOUND commits: a156b73, ea19b5d, 7a267e6 (evaluation-scope resolved 3 commits on this branch)
