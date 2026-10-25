---
phase: 02-window-control
plan: 13
subsystem: window-control
tags: [swift, accessibility, exclusions, persistence, json, appkit, nsmenu, debug-menu]

requires:
  - phase: 02-window-control
    provides: "ExclusionStore and the status menu (02-08), visibleMemberID (02-10), FrameWriter and AXWindowSystem.perform with read-back and MinimumSizeLearner (02-12), windowFocused events (02-06)"
provides:
  - "ExclusionFilter (PaneEngine): case-insensitive exact bundle-ID match and an order-preserving admit/dropped split, run first in both window systems' perform"
  - "WindowTracker.setExcluded / FakeWindowSystem.setExcluded / AXWindowSystem.setExcludedBundleIDs: isExcluded flips with windowChanged; new windows start marked"
  - "MinimumHintsStore: validated, atomic ~/Library/Application Support/Pane/min-size-hints.json; whole-file rejection moved aside as .corrupt"
  - "WindowTracker.setBundleHints + MinimumSizeLearner.seed; AXWindowSystem.setBundleHints and onLearnedMinimum"
  - "NudgePlanner, AXWindowSystem.focusedWindow(of:), Debug ▸ Nudge Focused Window with its two disabled titles"
affects: [03-tiling-engine, 09-settings, phase-2-uat]

actuals:
  tokens: 96500    # chars/4 over the realized diff: ~13000 source and tests, the rest the three RED evidence records
  tasks: 3
  commits: 6
plan_head_before: 4f7fc11d37612c700589703bcece82dfc53b10ed
plan_head_after: 10cfe5266d19a340d2b4d68212b610614ff52da6

tech-stack:
  added: []
  patterns:
    - "Pure command filter in PaneEngine applied at the top of every WindowSystem.perform (defence in depth: the store validates, the system enforces)"
    - "User-writable JSON loaded as Persistence.swift does (size cap, version probe, full decode, per-entry validation) and rejected whole, logged and moved aside"
    - "Value-type planners in PaneMac marked nonisolated so they test headless despite MainActor default isolation"

key-files:
  created:
    - Sources/PaneEngine/ExclusionFilter.swift
    - Sources/PaneMac/MinimumHintsStore.swift
    - Sources/PaneMac/Shell/Nudge.swift
    - Tests/PaneEngineTests/ExclusionScenarioTests.swift
    - Tests/PaneMacTests/MinimumHintsStoreTests.swift
    - Tests/PaneMacTests/NudgeTests.swift
    - Tests/PaneMacIntegrationTests/ExclusionIntegrationTests.swift
    - Tests/PaneMacIntegrationTests/NudgeIntegrationTests.swift
  modified:
    - Sources/PaneEngine/WindowTracker.swift
    - Sources/PaneEngine/MinimumSizeLearner.swift
    - Sources/PaneTestSupport/FakeWindowSystem.swift
    - Sources/PaneMac/AXWindowSystem.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Tests/PaneMacTests/MenuCopyTests.swift

key-decisions:
  - "Excluded windows stay tracked and visible (isExcluded true); every command for them is dropped before routing, and AXWindowSystem logs each dropped bundle ID once (re-logged if re-excluded later)"
  - "FakeWindowSystem.performed still records every command it receives; the ones kept from excluded apps also go to dropped"
  - "Hints are keyed by the exact bundle ID the app reports (case-sensitive); duplicates are exact matches; unbundled: keys are never stored"
  - "A hints file from a newer schema is also moved aside (as the plan says for every rejection), so it survives as .corrupt and is never overwritten in place"
  - "Hints seed only windows first reported after setBundleHints; PaneMacApp loads them before tracking starts, and learning only ever raises a seeded value"
  - "MinimumHintsStore.loadError exposes why the last load rejected the file, so the rejection is testable and never silent"
  - "Nudge is disabled as excluded when either the store lists the frontmost bundle ID or the focused window is marked isExcluded"

patterns-established:
  - "Exclusion is enforced in the window system, not the UI: any future command path (Phase 3 Planner) is covered by ExclusionFilter.admit in perform"
  - "Per-bundle persisted facts live in Application Support as small, validated, sorted JSON with a schemaVersion"

requirements-completed: [WIN-08, WIN-04]

coverage:
  - id: D1
    description: "Commands for excluded apps are dropped before routing in both window systems; their windows stay tracked with isExcluded true and flip immediately on list changes"
    requirement: WIN-08
    verification:
      - kind: unit
        ref: "Tests/PaneEngineTests/ExclusionScenarioTests.swift#ExclusionScenarioTests"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/ExclusionIntegrationTests.swift#anExcludedAppIsNeverMovedAndIsMovedOnceUnexcluded()"
        status: pass
    human_judgment: false
  - id: D2
    description: "Learned minimums persist per bundle in min-size-hints.json, load validated at launch, seed new windows, and a bad file is rejected whole and moved aside"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MinimumHintsStoreTests.swift#MinimumHintsStoreTests"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/MinimumHintsStoreTests.swift#BundleHintTrackerTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Nudge planner: +32/+32 and -64x-64 (min 1 pt), next press restores, per window; menu copy for the item and its disabled titles"
    requirement: WIN-04
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/NudgeTests.swift#NudgeTests"
        status: pass
      - kind: unit
        ref: "Tests/PaneMacTests/MenuCopyTests.swift#NudgeMenuCopyTests"
        status: pass
      - kind: integration
        ref: "Tests/PaneMacIntegrationTests/NudgeIntegrationTests.swift#theFocusedFixtureWindowIsNudgedAndRestored()"
        status: pass
    human_judgment: false
  - id: D4
    description: "Debug ▸ Nudge Focused Window on real apps and on each display of a multi-display setup (external above, then left of the built-in), the disabled titles for an excluded app and a never-dock window, and a learned minimum surviving relaunch"
    requirement: WIN-04
    verification: []
    human_judgment: true
    rationale: "Needs real third-party apps, physical display arrangements and a relaunch of the signed app (D-14 manual UAT); automation may only drive fixture windows"

duration: 11min
completed: 2026-10-25
status: complete
---

# Phase 2 Plan 13: Exclusions, Minimum Hints and Nudge Summary

**Pane now drops every command for an app on the exclusion list before routing it (the windows stay tracked and marked "Excluded"), remembers each app's learned minimum size across relaunches in a validated `min-size-hints.json`, and offers Debug ▸ Nudge Focused Window to move and shrink the focused window by 32/64 pt and put it back.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-10-25T16:53:42Z
- **Completed:** 2026-10-25T17:05:31Z
- **Tasks:** 3
- **Files modified:** 16 source/test files (+3 RED evidence records)

## Accomplishments
- `ExclusionFilter` (PaneEngine, no Foundation) matches bundle IDs case-insensitively and exactly, and splits commands into admitted and dropped, keeping order. `FakeWindowSystem.perform` and `AXWindowSystem.perform` both run it first, so no setFrame, focus, raise, park or hide can reach an excluded app.
- `WindowTracker.setExcluded` flips `isExcluded` on the affected windows with one `windowChanged` each, and new windows of an excluded app start marked. `PaneMacApp` pushes `ExclusionStore.bundleIDs` into the system at launch and on every change.
- Live: with the fixture excluded, a setFrame produced no `frameApplied` and the fixture kept its frame. After un-excluding, the same setFrame was applied within 1 s.
- `MinimumHintsStore` writes `{schemaVersion: 1, hints: [{bundleID, width, height}]}` sorted by bundle ID, pretty-printed, atomically, under `~/Library/Application Support/Pane/`. It keeps the per-axis maximum per bundle. It rejects the whole file if it is over 64 KiB, has a newer schema, is malformed JSON, or has a duplicate or invalid bundle ID or a size that is non-finite, negative or above `Geometry.maxCoordinate`. A rejected file is logged at error level, moved to `.corrupt` (replacing an older one), and Pane starts empty.
- New windows of a bundle with a hint start from it (`MinimumSizeLearner.seed`), and learning only raises it. `AXWindowSystem.onLearnedMinimum` reports growth, and `PaneMacApp` records it and saves, logging any save error.
- `NudgePlanner` plus `AXWindowSystem.focusedWindow(of:)`, which uses the latest `windowFocused`, else the AXMain visible window. The Debug submenu shows "Nudge Focused Window" in every build. It is disabled as "(app excluded)" or "(no window)" as UI-SPEC specifies.

## Task Commits

1. **Task 1: Excluded apps are never touched** - `5e1ea0e` (test, RED), `6d9b1cf` (feat, GREEN)
2. **Task 2: Per-bundle minimum hints persisted in Application Support** - `0d34e7b` (test, RED), `d291b26` (feat, GREEN)
3. **Task 3: Nudge Focused Window in the Debug menu** - `3f0fea0` (test, RED), `10cfe52` (feat, GREEN)

No refactor commits were needed.

## TDD Gate Compliance
- Each task has a `test(02-13)` commit before its `feat(02-13)` commit.
- **RED Task 1** (`tdd/02-13-task1-red.json`): `swift test --filter ExclusionScenarioTests`, target `anExcludedAppsWindowIsNeverMovedButStaysTrackedAndMarked()`, returned `RED_EVIDENCE_OK`. Semantic check: 6 of 7 tests failed on `#expect` against compiling no-op stubs. `anEmptyListAdmitsEverything` passed only because the stub admits everything. No build, load or fixture faults.
- **RED Task 2** (`tdd/02-13-task2-red.json`): `swift test --filter "MinimumHintsStoreTests|BundleHintTrackerTests"`, target `aBadFileIsRejectedWholeAndMovedAside(name:text:)` (all 7 cases), returned `RED_EVIDENCE_OK`. Semantic check: every case failed on its planned assertions against the no-op stub. Two "nothing stored" rows passed only because the stub stores nothing. The first attempt did not compile (MainActor-isolated static constants), so it was not recorded as RED.
- **RED Task 3** (`tdd/02-13-task3-red.json`): `swift test --filter "NudgeTests|MenuCopyTests"`, target `pressesAlternateBetweenNudgedAndRestored()`, returned `RED_EVIDENCE_OK`. Semantic check: the target failed on all three press assertions against a stub that returns the current frame. `theStepsAreThoseOfTheSpec` passed because the constants are part of the declared interface. The first attempt did not compile (MainActor-isolated struct), so it was not recorded as RED.

## Files Created/Modified
- `Sources/PaneEngine/ExclusionFilter.swift`: `ExclusionFilter.isExcluded/admit`, `WindowCommand.window`
- `Sources/PaneEngine/WindowTracker.swift`: `setExcluded`, `setBundleHints`, exclusion marking and hint seeding in `ingest`
- `Sources/PaneEngine/MinimumSizeLearner.swift`: `seed(_:minimum:)` (validated, raises only)
- `Sources/PaneTestSupport/FakeWindowSystem.swift`: `setExcluded`, `dropped`, admit before writing
- `Sources/PaneMac/AXWindowSystem.swift`: `setExcludedBundleIDs`, admit and log once per bundle, `setBundleHints`, `onLearnedMinimum`, `focusedWindow(of:)`
- `Sources/PaneMac/MinimumHintsStore.swift`: `MinimumHintsStore`, `HintsError`
- `Sources/PaneMac/PaneMacApp.swift`: pushes exclusions; loads, records and saves hints
- `Sources/PaneMac/Shell/Nudge.swift`: `NudgePlanner`
- `Sources/PaneMac/Shell/StatusItemController.swift`: Nudge item at the top of the Debug submenu
- `Sources/PaneMac/Shell/MenuCopy.swift`: `nudgeItem`, `nudgeExcluded`, `nudgeNoWindow`
- Tests: `ExclusionScenarioTests`, `MinimumHintsStoreTests` (+ `BundleHintTrackerTests`), `NudgeTests`, `NudgeMenuCopyTests`, `ExclusionIntegrationTests`, `NudgeIntegrationTests`

## Decisions Made
See `key-decisions` in the frontmatter. The one to carry forward: exclusion is enforced in the window system's `perform`. Phase 3's planner gets it for free and must not route commands around `perform`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `nonisolated` constants and planner in PaneMac**
- **Found during:** Tasks 2 and 3 (RED)
- **Issue:** PaneMac uses MainActor default isolation. The tests could not read `MinimumHintsStore.fileName` or call `NudgePlanner` from a nonisolated context.
- **Fix:** marked the store's static constants and `NudgePlanner` `nonisolated`, the same way `MenuCopy` is.
- **Files modified:** Sources/PaneMac/MinimumHintsStore.swift, Sources/PaneMac/Shell/Nudge.swift
- **Committed in:** 0d34e7b, 3f0fea0

**2. [Rule 3 - Blocking] `WindowCommand.window` accessor**
- **Found during:** Task 1
- **Issue:** `admit` needs the bundle ID of any command's window, and the enum had no accessor.
- **Fix:** a public `window` property in `ExclusionFilter.swift`.
- **Committed in:** 6d9b1cf

**3. [Rule 2 - Missing critical] `MinimumHintsStore.loadError`**
- **Found during:** Task 2
- **Issue:** `load()` returns nothing. Without a readable reason, the "explicit, logged decision" could only be checked through os_log.
- **Fix:** `loadError: HintsError?` holds why the last load rejected the file, and the tests assert it.
- **Committed in:** d291b26

**4. [Rule 2 - Missing critical] Live test of the Nudge path**
- **Found during:** Task 3
- **Issue:** The plan has no automated check of `focusedWindow(of:)` or a nudge reaching a real window. Both are new logic.
- **Fix:** `NudgeIntegrationTests` launches a fixture, finds it through `focusedWindow(of:)`, then nudges and restores it with `NudgePlanner` and `perform`. It touches only that fixture window.
- **Files modified:** Tests/PaneMacIntegrationTests/NudgeIntegrationTests.swift
- **Verification:** 3 of 3 live runs passed
- **Committed in:** 10cfe52

**5. [Rule 1 - Bug] Debug submenu separator in Release**
- **Found during:** Task 3
- **Issue:** The separator was inside `#if DEBUG`. With Nudge in every build, the Release menu would show Nudge directly above the capability line.
- **Fix:** the separator moved after the `#if DEBUG` block.
- **Committed in:** 10cfe52

**Smaller choices:** `defaultDirectory` uses `URL.applicationSupportDirectory` + `Pane` (it does not throw, and gives the same path for this non-sandboxed app) rather than `url(for:in:appropriateFor:create:)`, and `save()` creates the directory. The Nudge item is also disabled as excluded when the focused window itself is `isExcluded`.

---

**Total deviations:** 5 auto-fixed (2 blocking, 2 missing critical, 1 bug)
**Impact on plan:** All were needed for the plan's own contract or to test it. No scope creep.

## Issues Encountered
- The intermittent `CloseIntegrationTests` unhide flake (deferred-items.md) did not recur in the full run.
- Release build: only the known `PermissionReducer.swift:110` warning.

## Verification
- `swift test --filter ExclusionScenarioTests`: 7 passed
- `swift test --filter ExclusionIntegrationTests`: passed, not skipped (trusted terminal, `caffeinate`). It also passed in 3 more runs alongside `NudgeIntegrationTests`. No fixtures were left behind.
- `swift test --filter "MinimumHintsStoreTests|BundleHintTrackerTests"`: 10 passed. `swift test --filter "MinimumSizeLearnerTests|FrameScenarioTests"`: 15 passed
- `swift test --filter "NudgeTests|MenuCopyTests"`: 17 passed
- `scripts/build-debug.sh`: exit 0, signature valid. Full `swift test`: exit 0 (142 + 74 + 20 live + 147 tests, all six new suites included)
- `swift build -c release -Xswiftc -enable-testing --build-tests`: builds. `scripts/check-no-appkit.sh`: OK (24 files)
- Prohibitions: an excluded app's commands are dropped in `perform` before any routing, and the integration test proves the fixture is not moved. The hints file holds only bundle IDs and sizes, with no titles.

## Human UAT (end of phase)
1. Run Pane Debug. On the built-in display, focus a TextEdit window and choose Debug ▸ Nudge Focused Window twice. Expected: it moves 32 pt right and down and shrinks by 64 pt, then returns exactly. The Tracked Windows Frame column follows.
2. Attach an external display (or Sidecar), place it above the built-in display, and nudge a window on it. Then place it to the left and nudge again. Expected: the same movement, and the Display column names that display.
3. Exclude TextEdit (Don't Arrange “TextEdit”) and open the Debug menu with TextEdit frontmost. Expected: "Nudge Focused Window (app excluded)", disabled. Its rows show "Excluded".
4. Open the Debug menu with System Settings frontmost. Expected: "Nudge Focused Window (no window)", because it is never-dock.
5. Nudge an app with a real minimum size until the shrink is refused. Expected: Min Size shows the learned value. Quit and relaunch Pane: the value is back for that app's windows once it is re-learned or seeded, and `~/Library/Application Support/Pane/min-size-hints.json` lists only bundle IDs and sizes.
6. From 02-12: nudge a Chrome or Electron window (enhanced UI toggled and restored) and a Terminal or iTerm2 window. Expected: cell snapping is not learned as a minimum.

## User Setup Required
None. No external service configuration is required.

## Next Phase Readiness
- Phase 2's plans are all complete. ROADMAP SC3 holds in code and tests: Pane moves and resizes tracked windows on any display, learns real minimums and now keeps them, and never touches excluded apps. D-01's debug menu is complete (list, Nudge, Freeze, Don't Arrange).
- Phase 3: route every command through `WindowSystem.perform`, where `ExclusionFilter.admit` runs. Treat bundle hints as starting minimums for `resolve`.

---
*Phase: 02-window-control*
*Completed: 2026-10-25*
