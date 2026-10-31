---
phase: 06-overview-spaces-displays
verified: 2026-10-31T23:05:00Z
status: human_needed
score: 5/5 roadmap success criteria verified (SC2 via accepted override) (10 hardware backstops left to the user in 06-UAT)
covered_files:
  - ".planning/phases/06-overview-spaces-displays/06-01-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-01-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-02-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-02-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-03-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-03-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-04-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-04-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-05-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-05-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-06-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-06-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-07-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-07-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-08-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-08-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-09-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-09-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-10-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-10-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-11-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-11-SUMMARY.md"
  - ".planning/phases/06-overview-spaces-displays/06-12-PLAN.md"
  - ".planning/phases/06-overview-spaces-displays/06-12-SUMMARY.md"
  - "Package.swift"
  - "Sources/TransomEngine/Arrangements.swift"
  - "Sources/TransomEngine/Arranger+Camera.swift"
  - "Sources/TransomEngine/Arranger.swift"
  - "Sources/TransomEngine/CloseRule.swift"
  - "Sources/TransomEngine/CoVisibilitySpaces.swift"
  - "Sources/TransomEngine/Command.swift"
  - "Sources/TransomEngine/LayoutFile.swift"
  - "Sources/TransomEngine/Navigator.swift"
  - "Sources/TransomEngine/Notice.swift"
  - "Sources/TransomEngine/OverviewLayout.swift"
  - "Sources/TransomEngine/OverviewSelection.swift"
  - "Sources/TransomEngine/SpaceRekey.swift"
  - "Sources/TransomEngine/SpaceSwitchPlan.swift"
  - "Sources/TransomEngine/SpacesSnapshot.swift"
  - "Sources/TransomEngine/TakeoverPolicy.swift"
  - "Sources/TransomEngine/TransomURL.swift"
  - "Sources/TransomEngine/WindowTracker.swift"
  - "Sources/TransomFixtureApp/main.swift"
  - "Sources/TransomMac/AXWindowSystem.swift"
  - "Sources/TransomMac/ArrangeController.swift"
  - "Sources/TransomMac/ConflictController.swift"
  - "Sources/TransomMac/DisplaySettler.swift"
  - "Sources/TransomMac/Displays.swift"
  - "Sources/TransomMac/Input/GestureTapRules.swift"
  - "Sources/TransomMac/Input/Hotkeys.swift"
  - "Sources/TransomMac/LayoutStore.swift"
  - "Sources/TransomMac/MissionControlTakeover.swift"
  - "Sources/TransomMac/Overlay/NoticeQueue.swift"
  - "Sources/TransomMac/Overview/OverviewController.swift"
  - "Sources/TransomMac/Shell/CommandMenu.swift"
  - "Sources/TransomMac/Shell/MenuCopy.swift"
  - "Sources/TransomMac/Shell/NoticeCopy.swift"
  - "Sources/TransomMac/Shell/OverviewCopy.swift"
  - "Sources/TransomMac/Shell/StatusItemController.swift"
  - "Sources/TransomMac/SpaceSwitcher.swift"
  - "Sources/TransomMac/SpacesProvider.swift"
  - "Sources/TransomMac/TakeoverAlert.swift"
  - "Sources/TransomMac/TransomMacApp.swift"
  - "Sources/TransomMac/Zoom/GestureController.swift"
  - "Sources/TransomMac/Zoom/ShortcutsWindowController.swift"
  - "Sources/TransomMac/Zoom/StagePanel.swift"
  - "Sources/TransomMac/Zoom/ZoomController.swift"
  - "Sources/TransomPrivate/Capabilities.swift"
  - "Sources/TransomPrivate/CoreDock.swift"
  - "Sources/TransomPrivate/SkyLightSpaces.swift"
  - "Sources/TransomPrivate/SymbolicHotKeys.swift"
  - "Sources/TransomTestSupport/FakeWindowSystem.swift"
  - "Sources/transom-gesture-spike/main.swift"
  - "Sources/transom-spaces-spike/main.swift"
  - "Tests/TransomEngineTests/ArrangementsTests.swift"
  - "Tests/TransomEngineTests/ArrangerCameraTests.swift"
  - "Tests/TransomEngineTests/ArrangerDisplaySettleTests.swift"
  - "Tests/TransomEngineTests/ArrangerSpacesTests.swift"
  - "Tests/TransomEngineTests/CloseRuleTests.swift"
  - "Tests/TransomEngineTests/CloseScenarioTests.swift"
  - "Tests/TransomEngineTests/CoVisibilitySpacesTests.swift"
  - "Tests/TransomEngineTests/Fixtures/Spaces/README.md"
  - "Tests/TransomEngineTests/Fixtures/Spaces/empty-uuid.json"
  - "Tests/TransomEngineTests/Fixtures/Spaces/fullscreen.json"
  - "Tests/TransomEngineTests/Fixtures/Spaces/separate-one-display.json"
  - "Tests/TransomEngineTests/Fixtures/Spaces/spans-main.json"
  - "Tests/TransomEngineTests/OverviewLayoutTests.swift"
  - "Tests/TransomEngineTests/OverviewSelectionTests.swift"
  - "Tests/TransomEngineTests/SpaceRekeyTests.swift"
  - "Tests/TransomEngineTests/SpaceSwitchPlanTests.swift"
  - "Tests/TransomEngineTests/SpacesSnapshotTests.swift"
  - "Tests/TransomEngineTests/TakeoverKeysTests.swift"
  - "Tests/TransomEngineTests/TakeoverPolicyTests.swift"
  - "Tests/TransomEngineTests/TransomURLTests.swift"
  - "Tests/TransomMacIntegrationTests/IntegrationSupport.swift"
  - "Tests/TransomMacIntegrationTests/OverviewIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/OverviewKeyboardIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/TakeoverIntegrationTests.swift"
  - "Tests/TransomMacTests/CapabilitiesTests.swift"
  - "Tests/TransomMacTests/CommandMenuTests.swift"
  - "Tests/TransomMacTests/DisplaySettlerTests.swift"
  - "Tests/TransomMacTests/GestureControllerTests.swift"
  - "Tests/TransomMacTests/HotkeyTableTests.swift"
  - "Tests/TransomMacTests/LayoutFileV1Fixture.swift"
  - "Tests/TransomMacTests/LayoutStoreTests.swift"
  - "Tests/TransomMacTests/MenuCopyTests.swift"
  - "Tests/TransomMacTests/NoticeCopyTests.swift"
  - "Tests/TransomMacTests/NoticeQueueTests.swift"
  - "Tests/TransomMacTests/OverviewCopyTests.swift"
  - "Tests/TransomMacTests/ShortcutsModelTests.swift"
  - "Tests/TransomMacTests/TakeoverMenuTests.swift"
covered_digest: "v4:sha256:97386d8c17ea0b8226ad622add979e6d7c3182fad1217f08db2ef3d6d1ce3909"
behavior_unverified: 1
overrides_applied: 1
overrides:
  - must_have: "User can opt in to Mission Control's swipe and shortcut opening Transom's overview"
    reason: "D-05 made the four-finger swipe spike-gated; the user skipped the host swipe-check on 2026-10-31 (06-SPIKE 'skip → kept'), choosing to leave the swipe with macOS. v1 takes only the Mission Control shortcuts (F3, ⌃↑, ⇧F3). Copy says so."
    accepted_by: "Ken Scott"
    accepted_at: "2026-10-31T23:20:00Z"
gaps:
  - truth: "SC2 / OVER-02: User can opt in to Mission Control's swipe AND shortcut opening Transom's overview"
    status: partial
    reason: "The shortcut half is built and tested (F3, ⌃↑ and ⇧F3 open the overview, opt-out restores, crash restore at launch). The four-finger swipe is not taken: by user decision D-05 plus the 06-SPIKE swipe verdict ('skip → kept'), it stays with macOS. ROADMAP SC2 and REQUIREMENTS OVER-02 still promise the swipe, and REQUIREMENTS marks OVER-02 [x] Complete. This is a contract mismatch, not missing code."
    artifacts:
      - path: ".planning/ROADMAP.md"
        issue: "SC2 still says 'Mission Control's swipe and shortcut'"
      - path: ".planning/REQUIREMENTS.md"
        issue: "OVER-02 still says 'swipe and shortcut' and is checked Complete"
      - path: "Sources/TransomMac/Input/SwipeTakeoverTap.swift"
        issue: "Absent on purpose (06-11 swipe verdict: kept)"
    missing:
      - "A user decision, with no code change: either add the suggested override to this file's frontmatter, or reword SC2 and OVER-02 to 'the Mission Control shortcut (F3 / ⌃↑); the four-finger swipe stays with macOS' and track the swipe as a later item"
behavior_unverified_items:
  - truth: "WR-08: a display change that starts while a settle is still queued never ends settling mid-change (ArrangeController.displaysSettled returns unless the settler is idle, before and after the inventory await)"
    test: "Unplug the DELL and plug it back in within about a second (06-UAT item 4, second part)"
    expected: "One settle after the last change; the layout for the final set of displays comes back and no window is cascaded from a half-finished change"
    why_human: "ArrangeController needs a live AXWindowSystem, so there is no headless test, and the VM cannot hot-plug displays"
human_verification:
  - test: "06-UAT section 1, hardware items 1-7 on the MacBook Air plus the DELL. Now includes WR-08/WR-09 (item 4: fast re-plug; relaunch on other displays than the saved layout) and WR-06 (item 7: pick a DELL desktop in the DELL's strip by click and by Return, and note its label)"
    expected: "As written in each 06-UAT item"
    why_human: "Display hot-plug, sleep/wake with a display change, 'Displays have separate Spaces' off and two-display picks cannot run in the single-display VM"
  - test: "06-UAT section 2, takeover T1-T3 on the host (menu, F3/⌃↑, quit restore, kill -9 then relaunch)"
    expected: "As written; after kill -9, F3 opens macOS Mission Control at once and N10 shows once"
    why_human: "Agents may not change the host's symbolic hotkeys or kill the app; the VM half passed (TakeoverIntegrationTests, 2 tests)"
  - test: "06-UAT section 3, B1-B8. Now includes: B1 first part, the overview before visiting Desktop 2 after a launch; B1 last part, WR-07 with 'Move left/right a space' turned off (confirm the reversed rule); B8, WR-10 running-app half (close a docked three-tab Safari window)"
    expected: "As written in each 06-UAT item"
    why_human: "Visual, VoiceOver, Reduce Motion, timing with 30+ windows, and real Safari ghosts need real hardware. The first part of B1 checks a code-path limit: windows AX has never listed since launch are absent from other-Space thumbnails"
  - test: "Before the pass: rebuild the Debug app with scripts/build-debug.sh"
    expected: "The build under test includes the ten review fixes"
    why_human: "The signed app in 06-UAT was built at 16:38, before every review-fix commit (17:00-17:15)"
---

# Phase 6: Overview, Spaces & Displays Verification Report

**Phase Goal:** As a multi-display user, I want to see every window on every display and Space in one overview, so that I can jump anywhere and keep each layout.
**Mode:** mvp (the user story passed `user-story.validate`)
**Verified:** 2026-10-31T23:05:00Z
**Status:** gaps_found (one gap: a contract mismatch on the swipe that needs a user decision and no code change; everything else is waiting on the hardware UAT)
**Re-verification:** No, initial verification

## User Flow Coverage

| # | Step of the user story | Expected | Evidence in codebase | Status |
|---|---|---|---|---|
| 1 | Press Show Overview (⌃⌥⌘A, menu, `transom://overview`, or F3/⌃↑ with the takeover on) | One panel per display, current-Space windows in place, Spaces strip on top | `Hotkeys.swift:54,104` → `ArrangeController.dispatchCamera` (`:549`) → `toggleOverview` → `OverviewController.open/show`; `OverviewLayout` geometry. VM `OverviewIntegrationTests` (3 tests) passed in 06-12 | ✓ VERIFIED (1 display); two displays: UAT item 7 |
| 2 | See windows on other Spaces | Strip thumbnails with mini tiles (cached snapshot, else app tile) | `OverviewController.inputs` → `plannedWindows(desk)` from stored desks; `overlay()` mini tiles; visit capture `spaceDidSettle` → `captureVisit` | ✓ VERIFIED for windows Transom has seen. ⚠️ Windows AX never listed since launch are absent (06-UAT B1, first part) |
| 3 | Click a window or Space, or use the arrows and Return | Goes to it: switches Space if needed, focuses, closes | `click` → `pick` → `pickOnCurrentSpace` / `switchAway` → `SpaceSwitcher.switchTo` → `focusWindow` (refresh app + `.focus`). VM `OverviewSpaceSwitchIntegrationTests` **re-run by the verifier after the review fixes: "Test run with 2 tests in 1 suite passed"**; VM `OverviewKeyboardIntegrationTests` 1 test passed | ✓ VERIFIED (1 display); WR-06 two-display numbering: UAT item 7 |
| 4 | Keep each layout (per display, per Space, across unplug, sleep and docking) | Layouts survive Space switches, re-plug, sleep/wake and arrangement changes | `DeskKey(displayUUID, spaceID)`; `DisplaySettler` → `ArrangeController.displaysSettled` → `Arranger.displaysSettled` with `LayoutSets`; schema-2 `LayoutFile` + `SpaceRekey`. Engine tests listed below, all passed | ✓ VERIFIED in logic; hardware backstops in 06-UAT |

The `[outcome]` clause, "jump anywhere and keep each layout", is true in code and covered by behavioural tests on one display. The two-display half of "multi-display user" can only be shown by the 06-UAT hardware pass.

## Goal Achievement

### Observable Truths (roadmap contract)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Opening the overview shows every window on every display with the Spaces along the top, and clicking a window goes to it | ✓ VERIFIED (single display) | Flow steps 1-3 above. Shown windows: tracked, present, on the current Space, on screen. Other Spaces: stored desks. Live VM suites passed. Caveats routed to UAT: two displays (item 7), WR-06 desktop numbering, windows on Spaces unseen since launch (B1) |
| 2 | Opt in to Mission Control's **swipe and** shortcut opening the overview; opt out restores; a crash restores at next launch | ✗ PARTIAL (gap) | **Shortcut half verified:** `MissionControlTakeover.apply` stores originals → disables 32/108 (+113 per spike) → reads back → registers Carbon chords; `lift` restores; `TransomMacApp.run` calls `launchRestore()` before `AXWindowSystem` exists; canary → `.offAfterCrash` + N10. Tests: `TakeoverPolicyTests` (13), `TakeoverMenuTests` (11), VM `TakeoverIntegrationTests.launchRestoresUnliftedState` (2 tests passed after the fixes). **Swipe half absent by decision** (D-05, swipe kept). See Gaps |
| 3 | Each display and each Space keeps its own layout, and switching Spaces leaves the other layouts untouched | ✓ VERIFIED | `ArrangerSpacesTests.aSpaceSwitchLeavesTheOtherSpacesLayoutAlone`, `aCloseOnAHiddenSpaceIsAppliedAndPlannedOnlyOnReturn` (D-14), `windowsAtLaunchGoToTheirOwnSpacesDesk…`; `SpaceRekeyTests` (10, D-13 UUID re-key incl. layout sets after CR-02). VM `SpacesIntegrationTests` **re-run by the verifier: 2 tests passed**. Known edge WR-05 open (see Anti-Patterns) |
| 4 | Unplug/re-plug or sleep/wake restores that display's layout, with "Displays have separate Spaces" on and off | ✓ VERIFIED (logic) | `ArrangerDisplaySettleTests.unplugThenReplugReturnsEveryWindowToItsTile`, `floatedWindowsCascade…`, `sharedSpacesKeepDesksKeyedPerDisplay` (D-12), `dormantDesksAreCounted…`; `DisplaySettlerTests.nothingSettlesWhilePausedAndResumeRestartsTheFullQuietPeriod` (D-11); `AXWindowSystem:617` `settler.sessionResumed()`. Real hot-plug/sleep: hardware backstops (UAT 1-3, 5, 6) |
| 5 | A layout set per display arrangement, switched automatically on dock/undock | ✓ VERIFIED (logic) | `Arrangements.swift` (sorted-UUID `ArrangementID`, LRU of 16); `ArrangerDisplaySettleTests.dockAndUndockCyclesBringEachArrangementsLayoutBack`, `aWindowTheUserDockedWhileAwayStaysWhereTheUserPutIt`, `duplicateDisplayUUIDsNeverApplyAStoredSet`, CR-01/WR-09 regression tests; `ArrangeController.write()` persists `arrangement` + `layoutSets` (schema 2). Real docking: UAT item 4 |

**Score:** 4/5 roadmap truths verified (1 present, behaviour-unverified: WR-08; 10 hardware backstops are `insufficient_spec` and sit in 06-UAT)

### Plan must-haves (checked by plan)

| Plan | Result | Notes |
|---|---|---|
| 06-01 spike + shims | ✓ | `SymbolicHotKeys.swift`, `CoreDock.swift` are dlopen/dlsym and capability-gated (`CapabilitiesTests`). Backstops (reboot UUIDs, swipe) were met by observed spike evidence in 06-SPIKE (reboot diff; swipe "kept") |
| 06-02 Spaces runtime, G-03-9 | ✓ with caveat | `CloseRule` rows, `CloseScenarioTests`, `CoVisibilitySpaces` (debug only). WR-10 running-app tabbed ghost is still open → UAT B8 |
| 06-03 schema 2 | ✓ | `LayoutStoreTests` (v1 fixture migrates; >2 blocks save), `SpaceRekeyTests` |
| 06-04 / 06-05 settling, sets, N12, Debug S2-S4 | ✓ | Tests above; copy strings present in `NoticeCopy.swift:33`, `OverviewCopy.swift:42-53` |
| 06-06..06-09 overview | ✓ with accepted deviation | 06-08 truth "temporary Carbon hotkeys; other keys reach the frontmost app" was replaced by the user-approved Option A non-activating key panel (2026-10-31, noted in ROADMAP). Other keys are now ignored while the overview is open. The event-tap mask is unchanged (`InputTap.swift` not in the diff) |
| 06-07 switch rule | ⚠️ reversed by WR-07 | A disabled move hotkey now means "no route" (beep) rather than posting ⌃←/→. Spike evidence supports it; user confirmation is in UAT B1 |
| 06-10 / 06-11 takeover | ✓ (shortcut) | IDs 32/108/113 (`theSpikeSetIs113Only`), menu placement (`o2SitsAfterFrameDesktopBeforeAllowWindowPreviews`), N10/N11, Restore hook + retry (WR-02), WR-01/WR-03 fixes tested |
| 06-12 gate | ✓ | Host suite and VM suites (see spot-checks); signed build exists but predates the fixes (rebuild noted in UAT) |

### Required Artifacts

| Artifact | Status | Details |
|---|---|---|
| `Sources/TransomMac/Overview/OverviewController.swift` | ✓ VERIFIED | 656 lines, wired from `ArrangeController.overview()` |
| `Sources/TransomEngine/OverviewLayout.swift`, `OverviewSelection.swift` | ✓ VERIFIED | Used by the controller; 2 test suites |
| `Sources/TransomMac/MissionControlTakeover.swift`, `TransomEngine/TakeoverPolicy.swift` | ✓ VERIFIED | Wired in `TransomMacApp.run`, `ArrangeController.takeover`, `ConflictController`, `StatusItemController` |
| `Sources/TransomMac/DisplaySettler.swift` | ✓ VERIFIED | Owned by `AXWindowSystem` (`:31`), CG callback + screen-parameter touch |
| `Sources/TransomEngine/Arrangements.swift`, `SpaceRekey.swift`, `LayoutFile.swift` (schema 2) | ✓ VERIFIED | Used in `Arranger.displaysSettled`, `ArrangeController.rekeyed/write` |
| `Sources/TransomMac/SpaceSwitcher.swift`, `TransomEngine/SpaceSwitchPlan.swift` | ✓ VERIFIED | Wired into `OverviewController.switchAway` |
| `Sources/TransomPrivate/SymbolicHotKeys.swift`, `CoreDock.swift`, `SkyLightSpaces.swift` | ✓ VERIFIED | dlsym into optionals; `--disable-private` tested |
| `Sources/TransomMac/Input/SwipeTakeoverTap.swift` | absent on purpose | Swipe kept (gap 1 is the contract wording) |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| ⌃⌥⌘A / menu / URL | `OverviewController.toggle` | `Hotkeys` → dispatch → `dispatchCamera(.overview)` → `toggleOverview` | ✓ WIRED |
| Taken F3/⌃↑ Carbon chord | overview | `MissionControlTakeover.triggered` → `onTrigger` → `ArrangeController.missionControlKey` → `TakeoverPolicy.trigger` | ✓ WIRED |
| App launch | stored-originals restore | `TransomMacApp.run` → `takeover.launchRestore()` before `AXWindowSystem()` | ✓ WIRED |
| Quit / SIGTERM | lift | `AppDelegate(restore:)` → `takeover.lift(reason: .quit)`; `handleSIGTERM()` | ✓ WIRED |
| CG reconfiguration / screen params | Arranger | `DisplaySettler` → `onSettling` / `onDisplaysSettled` → `.displaysSettling` / `.displaysSettled` | ✓ WIRED |
| Strip / mini-tile pick | Space switch + focus | `pick` → `switchAway` → `SpaceSwitcher.switchTo` → `focusWindow` (`system.refresh(app:)` + `.focus`) | ✓ WIRED |
| Snapshot of World + sets | layout.json | `ArrangeController.write` → `LayoutFile(arrangement, layoutSets, spaces: SpaceRekey.table(…layoutSets…))` | ✓ WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| Overview main area | `OverviewDisplayInput.windows` | `arranger.windows` filtered by current Space + `CGWindowList.onScreenFrontToBack()` | Yes | ✓ FLOWING |
| Strip mini tiles | `hiddenSpaceWindows` | `arranger.world[DeskKey]` planned by `Planner.plan`; full-screen Spaces from `WindowInfo.spaces` | Yes, for windows Transom has tracked or restored | ✓ FLOWING (limit noted) |
| Strip thumbnails | `spaces` | `system.spacesSnapshot` ← `SkyLightSpaces.managedDisplaySpaces()` → `SpacesSnapshot.parse` | Yes (VM spaces-dump) | ✓ FLOWING |
| Layout sets | `arranger.layoutSets` | `Arranger.displaysSettled` store/take | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full host suite (run once) | `env -u TRANSOM_LIVE swift test` | 193 + 366 + 814 Swift Testing tests passed, 0 failures (83 live tests skipped on the host); exit 0 | ✓ PASS |
| Engine layer imports no AppKit | `scripts/check-no-appkit.sh` | `no-appkit: OK (53 files)` | ✓ PASS |
| Strip click / mini-tile pick lands on the Space, after the review fixes | `scripts/vm-live-test.sh OverviewSpaceSwitchIntegrationTests` | "Test run with 2 tests in 1 suite passed after 7.942 seconds" | ✓ PASS |
| Space switch leaves other layouts alone (Phase 5 regression, after the fixes) | `scripts/vm-live-test.sh SpacesIntegrationTests` | "Test run with 2 tests in 1 suite passed after 1.555 seconds" | ✓ PASS |
| Takeover apply/lift/launch restore (VM) | 06-REVIEW-FIX run of `TakeoverIntegrationTests` after the fixes | "Test run with 2 tests in 1 suite passed" (not re-run by the verifier; `.build/0612-vm-TakeoverIntegrationTests.log` holds the earlier pass) | ✓ PASS (reported) |
| Overview open/close per display (VM) | `.build/0612-vm-OverviewIntegrationTests-final.log` | 3 tests passed; 2 earlier runs failed the Esc check (WINDOWS #7) | ✓ PASS, flaky |
| Overview keys (VM) | `.build/0612-vm-OverviewKeyboardIntegrationTests.log` | 1 test passed | ✓ PASS |

No live test, tap, hotkey setter, CoreDock call, key post or window-opening code was run on the host by the verifier.

### Probe Execution

None declared for this phase (no `scripts/*/tests/probe-*.sh`). Step 7c: not applicable.

### Requirements Coverage

| Requirement | Source plans | Description | Status | Evidence |
|---|---|---|---|---|
| OVER-01 | 06-01, 02, 06, 07, 08, 09, 12 | Overview of every window on every display, Spaces on top, click goes to it | ✓ SATISFIED (1 display) / ? two displays in UAT | Truth 1 |
| OVER-02 | 06-01, 10, 11, 12 | Opt in to Mission Control's swipe and shortcut opening the overview | ✗ PARTIAL: shortcut yes, swipe kept with macOS | Gap 1 |
| OVER-03 | 06-01, 10, 11, 12 | Crash while replacing → shortcuts restored next launch | ✓ SATISFIED (VM) / ? host kill -9 in UAT T3 | Truth 2, shortcut half |
| OVER-04 | 06-01, 02, 03, 04, 12 | Each display and Space keeps its own layout | ✓ SATISFIED | Truth 3 |
| OVER-05 | 06-04, 05, 12 | Unplug/re-plug, sleep/wake restore | ✓ SATISFIED (logic) / ? hardware | Truth 4 |
| OVER-06 | 06-03, 04, 05, 12 | Layouts per display arrangement, auto-applied | ✓ SATISFIED (logic) / ? hardware | Truth 5 |

All six IDs are claimed by plans and none is orphaned (REQUIREMENTS maps exactly OVER-01..06 to Phase 6).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (all 88 phase files) | — | TBD / FIXME / XXX | none found | — |
| `Sources/TransomEngine/SpaceRekey.swift` | 40-48 | WR-05 open: a dormant desk's stale Space ID can be taken by a Space created later that session | ⚠️ Warning | Edge case after a reboot that renumbers Spaces (the spike saw no renumbering in one VM reboot). The desk is relabelled, not deleted. Needs its own design task; not in the WINDOWS ledger yet |
| `Sources/TransomMac/SpaceSwitcher.swift` | 19-40 | WR-06: per-display desktop index may not match macOS's numbering across displays | ⚠️ Warning | May switch the wrong display on two displays. Needs hardware evidence (UAT item 7) |
| `Sources/TransomEngine/CloseRule.swift` | 57 | WR-10 running-app half: a tabbed ghost becomes `.absent`, not closed | ⚠️ Warning | G-03-9 is still open for multi-tab Safari windows (UAT B8) |
| `Tests/TransomMacIntegrationTests/OverviewIntegrationTests.swift` | 66 | Flaky VM Esc check (WINDOWS #7, open) | ⚠️ Warning | Cause unknown; UAT B3 checks Esc on hardware |
| `Sources/TransomMac/Overview/OverviewController.swift` | 294 | `shortcut:` strip not rebuilt on live window changes | ℹ️ Info | Documented, deliberate |
| `Sources/TransomMac/DisplaySettler.swift` | 89-97 | IN-06 unretained refcon | ℹ️ Info | Low risk: the settler lives as long as the window system |

### Human Verification Required

Merged into 06-UAT.md rather than listed twice here. The verifier added the review checks to existing items, so the list stays four groups:

1. **06-UAT section 1, items 1-7** (MacBook Air + DELL). Item 4 now ends with a fast re-plug and a relaunch on other displays than the saved layout (WR-08/WR-09). Item 7 now ends with a DELL-desktop pick by click and by Return, noting its label (WR-06).
2. **06-UAT section 2, T1-T3** (host takeover, quit restore, kill -9 relaunch), unchanged.
3. **06-UAT section 3, B1-B8.** B1 now starts with the overview before visiting Desktop 2 after a launch, and ends with the WR-07 check (turn off "Move left/right a space"; confirm the beep-and-refuse rule you want). New B8 covers WR-10 (close a docked three-tab Safari window).
4. **Rebuild first:** the signed Debug app predates every review-fix commit. 06-UAT "Build under test" now says so.

### Gaps Summary

There is one gap, and no code is missing for it. ROADMAP SC2 and REQUIREMENTS OVER-02 promise that Mission Control's **swipe** and shortcut open the overview. The shortcut path is complete and tested, including crash-safe restore. The four-finger swipe was gated by D-05 on a host check that the user skipped, so it stays with macOS. The UI copy uses the "swipe kept" variant and there is no swipe tap. REQUIREMENTS nevertheless marks OVER-02 Complete. Resolve it one of two ways:

**This looks intentional.** To accept the deviation, add this to this file's frontmatter:

```yaml
overrides:
  - must_have: "User can opt in to Mission Control's swipe and shortcut opening Transom's overview"
    reason: "D-05 made the four-finger swipe spike-gated; the user skipped the host swipe-check on 2026-10-31 (06-SPIKE 'skip → kept'), so v1 takes only the Mission Control shortcuts (F3, ⌃↑, ⇧F3) and leaves the swipe to macOS. Copy says so."
    accepted_by: "Ken Scott"
    accepted_at: "<ISO timestamp when accepted>"
```

The other way is to reword SC2 and OVER-02 to the shortcut only and track the swipe separately. After either one, re-verifying should give `human_needed`, pending the 06-UAT hardware pass.

Known gaps, recorded and not blocking:
- macOS 14 is not tested. Evidence comes from the VM (15.7.7) and the host (27.2).
- WR-05 is open and needs design.
- The VM Esc check is flaky (WINDOWS #7).
- Windows on a Space that AX has not listed since launch are missing from that Space's thumbnail. This follows from the code path (other-Space data comes from stored desks; the spike showed AX lists other-Space windows only after a switch). 06-UAT B1 now checks how much it matters on real apps.

---

_Verified: 2026-10-31T23:05:00Z_
_Verifier: Claude (gsd-verifier)_
