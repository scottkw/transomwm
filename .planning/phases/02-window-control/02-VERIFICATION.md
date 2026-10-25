---
phase: 02-window-control
verified: 2026-10-25T22:02:46Z
status: human_needed
score: 144/150 must-haves verified (5 backstops insufficient_spec, 1 present but behaviour-unverified; 5 via override)
covered_files:
  - ".github/workflows/ci.yml"
  - ".gitignore"
  - ".planning/phases/02-window-control/02-01-PLAN.md"
  - ".planning/phases/02-window-control/02-01-SUMMARY.md"
  - ".planning/phases/02-window-control/02-02-PLAN.md"
  - ".planning/phases/02-window-control/02-02-SUMMARY.md"
  - ".planning/phases/02-window-control/02-03-PLAN.md"
  - ".planning/phases/02-window-control/02-03-SUMMARY.md"
  - ".planning/phases/02-window-control/02-04-PLAN.md"
  - ".planning/phases/02-window-control/02-04-SUMMARY.md"
  - ".planning/phases/02-window-control/02-05-PLAN.md"
  - ".planning/phases/02-window-control/02-05-SUMMARY.md"
  - ".planning/phases/02-window-control/02-06-PLAN.md"
  - ".planning/phases/02-window-control/02-06-SUMMARY.md"
  - ".planning/phases/02-window-control/02-07-PLAN.md"
  - ".planning/phases/02-window-control/02-07-SUMMARY.md"
  - ".planning/phases/02-window-control/02-08-PLAN.md"
  - ".planning/phases/02-window-control/02-08-SUMMARY.md"
  - ".planning/phases/02-window-control/02-09-PLAN.md"
  - ".planning/phases/02-window-control/02-09-SUMMARY.md"
  - ".planning/phases/02-window-control/02-10-PLAN.md"
  - ".planning/phases/02-window-control/02-10-SUMMARY.md"
  - ".planning/phases/02-window-control/02-11-PLAN.md"
  - ".planning/phases/02-window-control/02-11-SUMMARY.md"
  - ".planning/phases/02-window-control/02-12-PLAN.md"
  - ".planning/phases/02-window-control/02-12-SUMMARY.md"
  - ".planning/phases/02-window-control/02-13-PLAN.md"
  - ".planning/phases/02-window-control/02-13-SUMMARY.md"
  - ".planning/phases/02-window-control/02-14-PLAN.md"
  - ".planning/phases/02-window-control/02-14-SUMMARY.md"
  - ".planning/phases/02-window-control/02-15-PLAN.md"
  - ".planning/phases/02-window-control/02-15-SUMMARY.md"
  - ".planning/phases/02-window-control/02-16-PLAN.md"
  - ".planning/phases/02-window-control/02-16-SUMMARY.md"
  - ".planning/phases/02-window-control/02-17-PLAN.md"
  - ".planning/phases/02-window-control/02-17-SUMMARY.md"
  - "Package.swift"
  - "Sources/PaneApp/main.swift"
  - "Sources/PaneEngine/Classifier.swift"
  - "Sources/PaneEngine/CloseRule.swift"
  - "Sources/PaneEngine/Coordinates.swift"
  - "Sources/PaneEngine/CorpusCase.swift"
  - "Sources/PaneEngine/ExclusionFilter.swift"
  - "Sources/PaneEngine/FallbackMatcher.swift"
  - "Sources/PaneEngine/LifecycleSync.swift"
  - "Sources/PaneEngine/MinimumSizeLearner.swift"
  - "Sources/PaneEngine/PermissionReducer.swift"
  - "Sources/PaneEngine/ResponsivenessTracker.swift"
  - "Sources/PaneEngine/SpaceSwitchMarks.swift"
  - "Sources/PaneEngine/TabGroupTracker.swift"
  - "Sources/PaneEngine/WindowSnapshot.swift"
  - "Sources/PaneEngine/WindowSystem.swift"
  - "Sources/PaneEngine/WindowTracker.swift"
  - "Sources/PaneFixtureApp/main.swift"
  - "Sources/PaneMac/AX/AXAppThread.swift"
  - "Sources/PaneMac/AX/AXSnapshotReader.swift"
  - "Sources/PaneMac/AX/AppRegistry.swift"
  - "Sources/PaneMac/AX/FrameWriter.swift"
  - "Sources/PaneMac/AX/SyntheticWindowIDs.swift"
  - "Sources/PaneMac/AX/WindowIDResolver.swift"
  - "Sources/PaneMac/AXWindowSystem.swift"
  - "Sources/PaneMac/CGWindowList.swift"
  - "Sources/PaneMac/Displays.swift"
  - "Sources/PaneMac/ExclusionStore.swift"
  - "Sources/PaneMac/MinimumHintsStore.swift"
  - "Sources/PaneMac/PaneMacApp.swift"
  - "Sources/PaneMac/Permission/PermissionController.swift"
  - "Sources/PaneMac/Permission/PermissionProbe.swift"
  - "Sources/PaneMac/Permission/SetupView.swift"
  - "Sources/PaneMac/Permission/SetupWindowController.swift"
  - "Sources/PaneMac/Permission/TCCReset.swift"
  - "Sources/PaneMac/RefreshScheduler.swift"
  - "Sources/PaneMac/SessionGate.swift"
  - "Sources/PaneMac/Shell/FreezeTest.swift"
  - "Sources/PaneMac/Shell/MenuCopy.swift"
  - "Sources/PaneMac/Shell/Nudge.swift"
  - "Sources/PaneMac/Shell/StatusItemController.swift"
  - "Sources/PaneMac/Shell/TrackedWindowsModel.swift"
  - "Sources/PaneMac/Shell/TrackedWindowsView.swift"
  - "Sources/PaneMac/Shell/TrackedWindowsWindowController.swift"
  - "Sources/PanePrivate/AXWindowID.swift"
  - "Sources/PanePrivate/Capabilities.swift"
  - "Sources/PanePrivate/SkyLightSpaces.swift"
  - "Sources/PaneTestSupport/FakeWindowSystem.swift"
  - "Sources/pane-dump/main.swift"
  - "Tests/PaneEngineTests/ClassifierCorpusTests.swift"
  - "Tests/PaneEngineTests/ClassifierTests.swift"
  - "Tests/PaneEngineTests/CloseRuleTests.swift"
  - "Tests/PaneEngineTests/CloseScenarioTests.swift"
  - "Tests/PaneEngineTests/CoordinatesTests.swift"
  - "Tests/PaneEngineTests/ExclusionScenarioTests.swift"
  - "Tests/PaneEngineTests/FakeWindowSystemTests.swift"
  - "Tests/PaneEngineTests/FallbackMatcherTests.swift"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/README.md"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/android_studio_welcome.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/finder_desktop.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/finder_main_window.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/finder_two_tabs.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/libreoffice_start_center.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/safari_browser_window.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/safari_settings.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/system_settings.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/terminal_settings.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/terminal_window.json"
  - "Tests/PaneEngineTests/Fixtures/AXDumps/vscode_main_window.json"
  - "Tests/PaneEngineTests/FrameScenarioTests.swift"
  - "Tests/PaneEngineTests/LifecycleSyncTests.swift"
  - "Tests/PaneEngineTests/MinimumSizeLearnerTests.swift"
  - "Tests/PaneEngineTests/PermissionReducerTests.swift"
  - "Tests/PaneEngineTests/ResponsivenessScenarioTests.swift"
  - "Tests/PaneEngineTests/ResponsivenessTrackerTests.swift"
  - "Tests/PaneEngineTests/SpaceSwitchMarksTests.swift"
  - "Tests/PaneEngineTests/TabGroupTrackerTests.swift"
  - "Tests/PaneEngineTests/TabScenarioTests.swift"
  - "Tests/PaneEngineTests/TrackerClassificationTests.swift"
  - "Tests/PaneEngineTests/TrackerDisplayTests.swift"
  - "Tests/PaneEngineTests/WindowTrackerTests.swift"
  - "Tests/PaneMacIntegrationTests/ClassificationIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/CloseIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/ExclusionIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/FallbackIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/FixtureShapesTests.swift"
  - "Tests/PaneMacIntegrationTests/FixtureTrackingTests.swift"
  - "Tests/PaneMacIntegrationTests/FrameWriteIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/FreezeIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/IntegrationSupport.swift"
  - "Tests/PaneMacIntegrationTests/LiveTrackingTests.swift"
  - "Tests/PaneMacIntegrationTests/NudgeIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/SpacesIntegrationTests.swift"
  - "Tests/PaneMacIntegrationTests/TabsIntegrationTests.swift"
  - "Tests/PaneMacTests/CapabilitiesTests.swift"
  - "Tests/PaneMacTests/ExclusionStoreTests.swift"
  - "Tests/PaneMacTests/FreezeTestTests.swift"
  - "Tests/PaneMacTests/MenuCopyTests.swift"
  - "Tests/PaneMacTests/MinimumHintsStoreTests.swift"
  - "Tests/PaneMacTests/NudgeTests.swift"
  - "Tests/PaneMacTests/SessionGateTests.swift"
  - "Tests/PaneMacTests/TCCResetTests.swift"
  - "Tests/PaneMacTests/TrackedWindowsModelTests.swift"
  - "Tests/PaneMacTests/WindowIDResolverTests.swift"
  - "Tests/PaneModelTests/NoAppKitTests.swift"
  - "scripts/build-debug.sh"
  - "scripts/generate.sh"
  - "scripts/run-debug.sh"
  - "xcode/Pane.entitlements"
  - "xcode/project.yml"
covered_digest: "v3:sha256:85132e9a1ec592f9b1edeabc580810ddb700818496e880cb0108f2f7abc9ed8e"
behavior_unverified: 1
overrides_applied: 5
overrides:
  - must_have: "Without Space data (Spaces capability off or missing), two same-frame native tab groups of one app on two Spaces (scenario C5) are tracked as two separate windows"
    reason: "Project-lead decision 2026-10-25: when the read-only SkyLight Spaces lookup is unavailable, Pane falls back to single-Space behaviour. Without per-window Space data no rule can tell the two groups' hidden tabs apart (REVIEW iteration 3 CR-01: 'No ordering rule can choose between 31 and 10'), so in that mode the two groups may be tracked as one window. With Space data the case is handled and tested (02-14). In fallback, Pane still never reports a live window destroyed and never tracks one window ID under two identities, and 02-14's tests assert both."
    accepted_by: "project lead (Ken Scott), decision 2026-10-25"
    accepted_at: "2026-10-25T19:07:21Z"
  - must_have: "A window already at its minimum learns: it opens at 500 wide, is asked for 300 once, reads back 500, and one refresh 1 s later teaches 500; a window shrunk once from 800 and then asked for 300 three more times teaches 500 after the next refresh (02-15 truth 2)"
    reason: "Lead decision 2026-10-25 (commit 7c97838, after re-verification warning 1): a refusal candidate also needs the read-back to be more than 2 pt below the window's size before the write, so an app that applies a resize over 1 s late teaches nothing. A window first written while already at its minimum reads back unmoved, which cannot be told apart from a late applier, so it learns only once a later write moves it. The second clause still holds (Probe4c: 500). The first is replaced by aWindowThatOpensAtItsMinimumLearnsItOnceAWriteMovesIt."
    accepted_by: "project lead (Ken Scott), decision 2026-10-25 (relayed by the orchestrator; recorded in commit 7c97838)"
    accepted_at: "2026-10-25T21:58:59Z"
  - must_have: "One rule, per axis: a frame write whose read-back is more than refusalMargin (32 pt) above the request is a refusal candidate; it becomes the learned minimum when an AX refresh at least confirmDelay (1 s) after that write, with no newer write in between, still sees the present window within 2 pt; anything else drops the candidate (02-15 truth 1)"
    reason: "Lead decision 2026-10-25 (commit 7c97838, after re-verification warning 1): a refusal candidate also needs the read-back to be more than 2 pt below the window's size before the write, so an app that applies a resize over 1 s late teaches nothing. A window first written while already at its minimum reads back unmoved, which cannot be told apart from a late applier, so it learns only once a later write moves it. The rule gained the moved-below-before condition, and a later write read back at the same clamp keeps the candidate. The plan text was not revised."
    accepted_by: "project lead (Ken Scott), decision 2026-10-25 (relayed by the orchestrator; recorded in commit 7c97838)"
    accepted_at: "2026-10-25T21:58:59Z"
  - must_have: "MinimumSizeLearner learns per axis: a read-back more than 32 pt above the request is a candidate, learned as max(old, read-back) once an AX refresh at least 1 s after that write still sees the present window within 2 pt of it (02-12 truth 4, revised by 02-15)"
    reason: "Lead decision 2026-10-25 (commit 7c97838, after re-verification warning 1): a refusal candidate also needs the read-back to be more than 2 pt below the window's size before the write, so an app that applies a resize over 1 s late teaches nothing. A window first written while already at its minimum reads back unmoved, which cannot be told apart from a late applier, so it learns only once a later write moves it. Same rule change as 02-15 truth 1. The plan text was not revised."
    accepted_by: "project lead (Ken Scott), decision 2026-10-25 (relayed by the orchestrator; recorded in commit 7c97838)"
    accepted_at: "2026-10-25T21:58:59Z"
  - must_have: "02-12-PLAN.md truths 4 and 5 state this rule (marked revised by 02-15), so the plan text matches the code (02-15 truth 7)"
    reason: "Lead decision 2026-10-25 (commit 7c97838, after re-verification warning 1): a refusal candidate also needs the read-back to be more than 2 pt below the window's size before the write, so an app that applies a resize over 1 s late teaches nothing. A window first written while already at its minimum reads back unmoved, which cannot be told apart from a late applier, so it learns only once a later write moves it. 02-12 truth 4 no longer matches the code until its text gains the moved-below-before condition (see warnings)."
    accepted_by: "project lead (Ken Scott), decision 2026-10-25 (relayed by the orchestrator; recorded in commit 7c97838)"
    accepted_at: "2026-10-25T21:58:59Z"
accepted_limits:
  # Documented Known limits of 02-14..02-17, accepted as lead decisions of 2026-10-25 (relayed in the re-verification brief).
  # None of them makes a must-have truth fail, so none needs an override. Listed so they are not re-raised as gaps.
  - limit: "Single-Space fallback: without Space data, C5 may track two same-frame tab groups as one window (the override above)"
    source: "02-14-SUMMARY Known limits 1; Probe3 C5 at HEAD: G2 never tracked, no destroy"
  - limit: "With Space data, a hidden tab of unknown Space is left out of its group while a window known to be on another Space shares the frame slot, until a tab switch shows it (visibleMemberID and tabCount unaffected)"
    source: "02-14-SUMMARY Known limits 2"
  - limit: "Late Space notification: a notification that reaches main only after the update that already saw the new Space protects nothing; pinned by knownLimitWithoutTheSpaceNotificationTheShownTwinTakesTheClosedGroup"
    source: "02-17-SUMMARY Known limits (residual 1), plus residuals 2-4 (refused handoff is final, merge during a switch, rapid switching)"
  - limit: "A window already at its minimum learns nothing from a write that does not move it, and learns once a write moves it: an unmoved read-back cannot be told apart from an app that applies the resize more than 1 s late"
    source: "Lead decision 2026-10-25, commit 7c97838; test aWindowThatOpensAtItsMinimumLearnsItOnceAWriteMovesIt; Probe4c 'opens at its minimum: nil'. Also covered by the four learner overrides above, because 02-12 truth 4 and 02-15 truths 1, 2 and 7 state the old rule"
  - limit: "32 pt learner margin: a real minimum within 32 pt of the request is not learned from that write; cells larger than 32 pt can be learned; the 1 s confirm refresh can replace a pending refresh of the same pid"
    source: "02-15-SUMMARY Known limits"
  - limit: "02-16 identity residuals: a holder with no frame or no CG list loses its window to the owner; a tab re-keyed inside a group does not re-point pendingFocus"
    source: "02-16-SUMMARY Known limits"
re_verification:
  previous_status: gaps_found
  previous_score: 108/121
  gaps_closed:
    - "A natively tabbed window counts as one tracked window, and a same-frame window of the same app on another Space is never taken as its hidden tab (ROADMAP SC2; 02-10 truth 1; REVIEW CR-01)"
    - "A window is removed (windowDestroyed) only when two sources agree; a window alive on another Space is never reported destroyed (02-09 truth 2; WIN-09 core rule)"
    - "When an app refuses a size, Pane learns its real minimum, including the common case of a window left clamped in a too-small tile and a window that is already at its minimum; a deterministic snap is never learned as a minimum (ROADMAP SC3; 02-12 truths 4 and 5; REVIEW WR-01, WR-02)"
    - "Call-time degradation switches `_AXUIElementGetWindow` off only after 5 consecutive failures across real windows, not because one unplaceable element fails repeatedly while cached windows record no successes (02-11 truth 4; SAFE-05; REVIEW WR-03)"
    - "A window identified while the private lookup failed transiently is re-identified once the lookup works; no element keeps a synthetic or wrong frame-matched ID for life, and two elements never share one CGWindowID (02-11 truth 2 stickiness clause; WIN-02, SAFE-05; REVIEW WR-04)"
  gaps_remaining: []
  regressions: []
resolved_warnings:
  - finding: "Warning 1 (late applier more than 1 s learned its stale pre-write size as a minimum)"
    resolved_by: "commits 1a5f2b1 (RED test aWindowStillAtItsPreWriteSizeAfterASecondLearnsNothing) and 7c97838 (candidate needs a read-back more than 2 pt below the pre-write size, MinimumSizeLearner.swift:35-51; WindowTracker.swift:297 passes before: info.frame.size)"
    evidence: "Probe4c rebuilt at HEAD: 'late applier (>1 s): nil' (was 800.0x0.0). The suite (473 tests) is green"
  - finding: "Warning 2 (02-SECURITY.md audited only T-02-01..37)"
    resolved_by: "commit 3d8e390: 02-SECURITY.md now covers T-02-38..48 (49/49 closed, threats_open: 0)"
  - finding: "Warning 3 (stale key-link patterns in 02-11 and 02-12)"
    resolved_by: "commit dd7e231: 02-11 link now from WindowIDResolver.swift; 02-12 pattern learner\\.(recordWrite|confirm). verify.key-links exits 0 for both plans"
warnings:
  - finding: "Learner plan text is stale after 7c97838: 02-12 truth 4 and 02-15 truths 1 and 2 still state the old rule (no moved-below-before condition; an at-minimum window learning from one unmoved write)"
    category: other
    evidence: "02-12-PLAN.md:31, 02-15-PLAN.md truths 1-2 unchanged since dd7e231; the code and tests follow the new rule"
    reason: "Covered by overrides for now. Revise the four truths (mark them 'revised by 7c97838'), as 02-15 did for 02-12, so a later regression check needs no override"
  - finding: "Live evidence for the one-write fixture truth (02-12 truth 5, 02-15 truth 5) predates 7c97838"
    category: other
    evidence: "aRefusedSizeIsReadBackAndLearned last passed in the fixer's live gate at 5a0894a. By code trace it still holds: the fixture opens at 320x232 (PaneFixtureApp/main.swift:63) with minSize 250x150, so the 100x80 write moves both axes more than 2 pt; the fake equivalent theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsItFromOneWrite passes at HEAD"
    reason: "Run 'caffeinate -d -i swift test --filter FrameWriteIntegrationTests' once (not run here, as instructed)"
behavior_unverified_items:
  - truth: "AXWindowSystem observes `NSWorkspace.activeSpaceDidChangeNotification` and marks every tracked app through `SpaceSwitchMarks`; every update with a full AXWindows answer for a marked app carries `ObservationContext.spaceChanged == true` (02-17 truth 2)"
    test: "Launch `scripts/run-debug.sh --no-build --disable-private=Spaces`. Put a two-tab Safari window on Space 1 and a single same-frame Safari window on Space 2 (Window > Fill on each). On Space 1 close the whole tab group, then switch to Space 2 at once (Ctrl-Right). Open Tracked Windows. Repeat without the flag"
    expected: "The group's row is gone, and the Space 2 window has its own row with a new creation order. It is never shown under the closed group's entry"
    why_human: "SpaceSwitchMarks and the engine rule are unit-tested, and FakeWindowSystem mimics the wiring. But no test posts a real activeSpaceDidChangeNotification to AXWindowSystem (lines 110-114, 223, 244, 335), and real Spaces cannot be switched from automation"
human_verification:
  - test: "Accessibility grant flow: `tccutil reset Accessibility com.eightabyte.pane.debug`, then `scripts/run-debug.sh --no-build`; follow the setup window"
    expected: "S1 with a default 'Open System Settings'; the macOS prompt appears exactly once; after enabling 'Pane Debug' the window shows 'Pane is ready' with no click; the glyph changes from exclamationmark.triangle to rectangle.split.2x1"
    why_human: "Real TCC prompts and System Settings cannot be driven from tests (Pitfall 9: launch through LaunchServices)"
  - test: "Stale grant form B: copy the app to the scratchpad, re-sign only the copy ad hoc, launch it and click Open System Settings; then Reset Permission"
    expected: "'Already turned on?' appears after 15 s, not before; 'Resetting permission…' with every button disabled, then 'Turn Pane on again'. Form A (probe -25211) has not been reproduced locally; note if seen"
    why_human: "Needs a real stale TCC grant"
  - test: "Close the setup window while not ready; reopen it from the menu; try Esc and Cmd-W"
    expected: "It never reopens by itself; 'Grant Accessibility Access…' / 'Fix Accessibility Access…' reopens it; Esc and Cmd-W close it except while resetting"
    why_human: "Window-lifecycle behaviour in a real session"
  - test: "TCC grant survives a rebuild: grant Pane Debug, rebuild with `scripts/build-debug.sh`, relaunch"
    expected: "No new prompt; tracking starts"
    why_human: "Designated-requirement stability needs a real signed build and TCC"
  - test: "Menu-bar glyph in light, dark and tinted menu bars; header 'Tracking N windows in M apps'; Debug shows 'Window ID lookup: available' and 'Spaces lookup: available' (and 'Spaces lookup: off, single Space' with `--disable-private=Spaces`)"
    expected: "Glyph legible in every appearance; plausible counts; both Debug lines correct (backstop 02-02, 02-14 D5)"
    why_human: "Visual rendering"
  - test: "Lock and sleep: with 10 windows in several apps and Tracked Windows open, lock (Ctrl-Cmd-Q) for 30 s and unlock; sleep for a minute from the Apple menu and wake; optionally switch users"
    expected: "All 10 rows remain after each cycle; footer briefly shows 'Refreshing after wake · '; nothing moved or forgotten"
    why_human: "Real lock and sleep cannot (and must not) be triggered from automation"
  - test: "Real kill -STOP: open TextEdit and Safari windows, `kill -STOP <TextEdit pid>`, open a new Safari window and open Pane's menu; then `kill -CONT`"
    expected: "Menu opens instantly; the new Safari window is counted within a second; '1 app not responding' appears within about 7 s; after CONT it clears within about 4 s and TextEdit's windows were never dropped"
    why_human: "ROADMAP SC4 names a real user app; automation drives only the fixture"
  - test: "Freeze test (Debug ▸ Freeze “TextEdit” for 10 Seconds…): Return and Esc cancel; Freeze stops it; rows show 'Not responding'; auto-resume after 10 s; Freeze then Quit Pane resumes TextEdit at once; Finder/Pane show 'Freeze Frontmost App (not allowed)'; Release build has no Freeze item"
    expected: "As described in 02-08 SUMMARY human checks 3-6"
    why_human: "Alert key handling and SIGSTOP of a user app"
  - test: "Multi-display Nudge: on the built-in display, Debug ▸ Nudge Focused Window twice on a TextEdit window; attach an external display (or Sidecar) above, then left (and below), and nudge a window on it; unplug and replug while Pane runs"
    expected: "+32/+32 and -64x-64, then an exact restore; the same on the external display in each arrangement; the Display column follows; one displaysChanged then one refresh about 500 ms later on hot-plug"
    why_human: "Needs physical display arrangements (backstop 02-13; the live second-display test is skipped with 1 display)"
  - test: "Real native tabs: Finder, Terminal and Safari windows with three tabs each (Cmd-T); click between tabs. Then, quickly, Cmd-T followed at once by Ctrl-Shift-Tab; and Cmd-T followed by a click on an older tab. Also Cmd-W on the shown tab"
    expected: "One row per app window; the tab count and shown title follow every action; tab clicks change Title but never add or remove rows; the quick Cmd-T sequences never add a second row or crash Pane (REVIEW-FIX CR-01, WR-01); note which apps report AXTabGroup (Safari may not)"
    why_human: "Real apps' tab implementations and timings differ (RESEARCH A1/A2; backstop 02-10). The engine cases are covered by D1/D2/R1 tests and Probe4/Probe5, but not against real apps"
  - test: "Real Space switches with tab groups, with and without `--disable-private=Spaces`: a Terminal tab group on Space 1 and a same-frame Terminal window (and, separately, a same-frame tab group) on Space 2; switch back and forth; press Cmd-T in the Space 1 window while the twin sits on Space 2, then switch again; also the whole-group close plus immediate switch in behavior_unverified_items. Check `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 5m`"
    expected: "With Space data: one row per real window throughout, and Space switches and Cmd-T never add, remove or duplicate rows. Without Space data: the same, except two same-frame tab groups may share one row (accepted single-Space limit), and no row is ever lost. Log shows 'Spaces: available' or 'Spaces: off'"
    why_human: "Real Spaces cannot be created or switched from automation (02-14 D6, 02-17 D4)"
  - test: "Frame writes and minimum-size hints on real apps via Nudge. First delete `~/Library/Application Support/Pane/min-size-hints.json`, which may hold snap hints learned under the old rule. Then try a Chrome or Electron window (AXEnhancedUserInterface toggled and restored), Terminal or iTerm2, and an app with a real minimum (Notes, Music) opened larger than its minimum; also one already sized to its minimum; open a second window of that app; quit and relaunch Pane"
    expected: "Enhanced UI restored; no terminal cell snap learned; a busy Chrome/Electron window never learns its pre-write size; Min Size shows the real minimum about a second after a refused write that moved the window; a window already at its minimum shows nothing until a later write moves it (accepted limit); the second window starts from the learned value; after relaunch the hint is back; the hints file holds only bundle IDs and sizes"
    why_human: "Real third-party app behaviour (02-15 D6)"
  - test: "Exclusions in the real UI: Don't Arrange “TextEdit”, then Never Arrange submenu, then Nudge with TextEdit frontmost, then Nudge with System Settings frontmost"
    expected: "Checkmark; 'Excluded' badge; submenu lists and removes it; 'No apps excluded' when empty; 'Nudge Focused Window (app excluded)' and '(no window)' are shown disabled"
    why_human: "Menu rendering and interaction"
  - test: "Signed app, private lookup: run Pane Debug for 10 minutes of normal use across several apps (open and close windows, switch tabs and Spaces), then `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 15m`. Then relaunch with `scripts/run-debug.sh --no-build --disable-private=AXWindowID` (and once with `--disable-private=AXWindowID,Bogus`), open and close windows, and watch Tracked Windows and the Debug menu"
    expected: "No 'AXWindowID failed 5 times' line in normal use, and Debug still shows 'Window ID lookup: available'. With the flag: 'Window ID lookup: off, matching by frame' in menu and footer; rows show 'by frame', appear and disappear normally and never duplicate; the log has the capability report and an error line for 'Bogus'"
    why_human: "ROADMAP SC5 in the signed app launched through LaunchServices; real-app lookup failures cannot be provoked from the fixture (02-16 D6)"
  - test: "Corpus review before pushing publicly (SECURITY T-02-08): read every JSON in Tests/PaneEngineTests/Fixtures/AXDumps (`git log -p -- Tests/PaneEngineTests/Fixtures/AXDumps`), especially libreoffice_start_center and android_studio_welcome; then set confirmedBy to 'developer'"
    expected: "No title, path, URL or account name; every label matches the window. All 11 cases currently read confirmedBy 'executor-proposed'"
    why_human: "Labels must come from a person (Pitfall 6); privacy review is a judgment call"
  - test: "Picture-in-picture capture (backstop 02-03): play a video in Safari or Chrome, enter PiP, `swift run pane-dump --app com.apple.Safari --list`, then capture with `--label neverDock --family native --case safari_pip`; run `swift test --filter ClassifierCorpusTests`"
    expected: "The PiP case is labelled neverDock and classifies neverDock"
    why_human: "Needs a playing video; there is no PiP case in the corpus yet"
  - test: "UI-REVIEW visual items: GroupBox callout inner padding (12 pt vs about 2x); Tracked Windows table background and alternating rows; long CFBundleName wraps at 480 pt in the setup window; the 'Looking for windows…' font; reset-failed state with duplicated 'Open System Settings' buttons and callouts B and E at once; menu header vs footer counts and missing loading state; table behaviour at 720 pt (horizontal scroll, pinned header, middle-truncated titles with tooltips)"
    expected: "Confirm or file each against 02-UI-REVIEW.md Top 3 fixes and needs_human_review items"
    why_human: "No screenshots were captured (native AppKit, no dev server); code-derived findings need a rendered check"
  - test: "Prohibition review (judgment tier, non-authoritative LLM verdicts in the report): confirm no TrellisWM material and no code copied from AeroSpace, Amethyst, yabai or Loop (Loop is GPL-3.0; the SkyLight shim must be an independent reimplementation)"
    expected: "Developer confirms clean-room status"
    why_human: "Provenance cannot be verified from the code"
---

# Phase 2: Window Control Verification Report

**Phase Goal:** As a Mac user, I want to grant Pane access and have it track and move every window, so that no slow app or lock screen can freeze or lose them.
**Mode:** mvp. The user-story format is valid. Outcome clause: *no slow app or lock screen can freeze or lose them*.
**Verified:** 2026-10-25T22:02:46Z at HEAD `0605100` (code at `7c97838`). Refreshed after the slow-resize hardening (`1a5f2b1`, `7c97838`); first pass of this round at `29242da`
**Status:** human_needed
**Re-verification:** Yes. This follows gap-closure plans 02-14 to 02-17 and the review-fix round 7c3350f..5a0894a. Previous status: gaps_found, 108/121.

## User Flow Coverage (MVP)

| Step | Expected | Evidence in codebase | Status |
|---|---|---|---|
| Grant access | Guided grant; stale grant detected and explained | PermissionReducer, PermissionProbe, TCCReset, SetupView. PermissionReducerTests green | VERIFIED (automated); real TCC needs a human |
| Track every window | Every standard window, live open and close, a tab group as one window | WindowTracker, TabGroupTracker (Space-aware, Cmd-T rule, fold guard), WindowIDResolver (re-check and re-key). Classifier corpus, SpaceTabScenarioTests (3 modes) and RekeyTests green; Probe3/4/5 one row per real window | VERIFIED. C5 without Space data is the accepted single-Space limit (override) |
| Move every window | setFrame on any display; learn the real minimum; exclusions respected | FrameWriter size→pos→size; MinimumSizeLearner margin plus time rule; ExclusionFilter.admit in both paths | VERIFIED (4 learner truths via the lead's 7c97838 override); multi-display and real apps need a human. A late applier no longer learns a wrong minimum |
| No slow app freezes it | Hung app isolated per thread | ResponsivenessTracker, per-app AXAppThread, 1 s messaging timeout; scenario tests green | VERIFIED (automated); a real `kill -STOP` needs a human |
| No lock screen loses them | Lock/sleep/timeout never close; two-source close; no live cross-Space window destroyed | CloseRule, SessionGate, two-refresh fold guard, Space-switch hold. Invariant "no live window reported destroyed" checked after every refresh in SpaceTabScenarioTests | VERIFIED (automated); a real lock and sleep need a human |

The outcome clause now holds in code and tests. The two ways a window could be lost (gap 2: a fold destroying a live cross-Space twin; gap 1: a cross-Space twin tracked twice or taken as a hidden tab) are closed. With Space data that holds in every scenario; without it, in every scenario except the accepted C5 limit, where two groups may share one row but neither is ever destroyed.

## Goal Achievement

### Previous gaps (all closed)

| # | Gap (previous truth) | Fix in code | Behavioural evidence (run by me at HEAD) | Status |
|---|---|---|---|---|
| 1 | Tab group vs. same-frame twin on another Space (SC2, 02-10#1, WIN-06) | `SkyLightSpaces.swift` (dlopen/dlsym, `Capability.spaces`), `ObservationContext.windowSpaces` filled at `AXWindowSystem.swift:332-333`; `TabGroupTracker.swift`: Space exclusion and ambiguity rule (134, 162, 176), Cmd-T rule including a stale sweep CG list (127-136), rebind gate on Space proof only (119-121, 139-142), refused member never takes its old tabs or an existing leader (172, 188), orphan handoff needs former-tab evidence (152-159), blind-switch hold (89, 173-175) | Probe3 C2 (Z=5 and Z=50): `[(10,40,2),(Z,Z,1)]`, the twin created on its own, no DESTROYED. C7: `[(10,40,2),(30,30,2)]`, no phantom. Probe4 D1 (was exit 133): `[(10,10,3)]`, exit 0. D2: one row `[(10,50,4)]`. R1: one row, no `created 40`, no DESTROYED. Tests: `cmdTWithATwinOnAnotherSpaceTakesTheWindowItWasOpenedFrom` (6 cases), `twoSameFrameGroupsOnTwoSpacesStayTwoWindows`, `cmdTBesideAGroupOnAnotherSpaceLeadsItsOwnGroup`, D1/D2 in 3 modes, `cmdTSeenWithAStaleSweepCGListStaysOneWindow`: all pass | ✓ CLOSED. C5 in fallback: PASSED (override) |
| 2 | A live cross-Space window reported destroyed (02-09#2, WIN-09) | `WindowTracker.swift:78-98`: a fold is destroyed only on the second consecutive full refresh with the same shown tab, and is held (neither counted nor destroyed) in a Space-switch update without Space data | Every SpaceTabScenarioTests refresh asserts that no tracked window disappears while its shown tab is AX-valid and in the CG list, and that no window ID is tracked under two identities (`TabScenarioTests.swift:55-80`). All modes pass. Probe4 C3b: a real Merge All Windows is still destroyed on the third refresh, as designed | ✓ CLOSED |
| 3 | Minimum-size learning (SC3, 02-12#4/#5, WIN-04) | `MinimumSizeLearner.swift`: a candidate needs a read-back more than 32 pt above the request and, since `7c97838`, more than 2 pt below the pre-write size; a repeat write read back at the same clamp keeps it (35-51). It is confirmed by a refresh at least 1 s later within 2 pt (54-67); in-session bundle hints in `WindowTracker.swift:164-166`; confirm refresh scheduled at `AXWindowSystem.swift:203, 345-347`; persisted through `onLearnedMinimum` (`AXWindowSystem.swift:367-373`) | Probe4c (rebuilt after 7c97838): 16-pt snap → nil; one shrink then static → 500; opens at its minimum → nil (accepted limit; learns once a write moves it); lag-2 drag and back-and-forth → nil; early refresh waits, then 500 at 1.05 s; late applier → nil. Tests `aWindowThatStaysClampedLearnsAfterTheNextRefresh`, `aWindowStillAtItsPreWriteSizeAfterASecondLearnsNothing`, `aWindowThatOpensAtItsMinimumLearnsItOnceAWriteMovesIt`, `aGridSnapIsNeverLearnedButARealRefusalStillIs`, both slow-app tests, `theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsItFromOneWrite`, `aMinimumLearnedThisSessionSeedsTheNextWindowOfThatBundle`: all pass. 02-12 truths 4/5 carry "revised by 02-15" | ✓ CLOSED. The at-minimum clause passes via the 7c97838 override |
| 4 | One failing element switches `_AXUIElementGetWindow` off (02-11#4, SAFE-05) | `WindowIDResolver.swift:78-86`: one counted failure per element (`counted`, capped at 64, not pruned by listing); every real lookup success resets the count | `oneElementThatKeepsFailingNeverSwitchesTheLookupOff`, `roundTripsOfOneFailingElementNeverSwitchTheLookupOff(staysCached:)` (Space round trip and hidden tab), `aFailingElementCountsOnceEvenAfterItLeftAXWindows`, `fiveDistinctFailingElementsSwitchTheLookupOffOnce`, `aSuccessBetweenFailuresKeepsTheLookupOn`: all pass | ✓ CLOSED |
| 5 | Fallback ID kept for life; two elements sharing an ID (02-11#2, WIN-02) | `WindowIDResolver.swift:67-77` looks up every non-`.axPrivate` element again and reports `replaces`; 98-113: no offscreen-only match on a first failure (`identityPending`); 123-132: unique IDs; `WindowTracker.rekey(from:to:)` (215-250) moves info, creation order, facts, learner and tab state, and emits one `windowRekeyed` | `aSyntheticWindowIsRekeyedToItsRealIDAndStaysOneWindow`, RekeyTests, RekeyGroupTests (including the wrong cross-Space frame match), WindowIDResolverTests: all pass. Live FallbackIntegrationTests passed in the fixer's gate (24 pass, 1 skip); I did not re-run it, as instructed | ✓ CLOSED |

### Roadmap Success Criteria (contract)

| # | Truth | Status | Evidence |
|---|---|---|---|
| SC1 | Guided Accessibility grant; stale grant detected and explained, no looping prompts | ✓ VERIFIED | PermissionReducerTests (14.9 s / 15 s boundary, 20-sequence no-repeat-prompt property) green. Real TCC in human_verification |
| SC2 | Tracked list shows every standard window, updates live, counts a natively tabbed window as one, and excludes dialogs, sheets, popovers and PiP (corpus passes) | ✓ VERIFIED (C5 fallback via override) | The 11-case corpus is green. Tab groups: gap 1 evidence above. Without Space data, C5 is the accepted single-Space limit. Real-app tabs are a backstop for a human |
| SC3 | Move/resize any window on any display; learn the real minimum on refusal; excluded apps never touched | ✓ VERIFIED | FrameScenarioTests, ExclusionScenarioTests and the learner tests are green, and Probe4c agrees. The late applier is now refused; a window already at its minimum learns once a write moves it (override). Multi-display and real apps go to a human |
| SC4 | kill -STOP neither stalls Pane nor delays others; lock, sleep or AX timeout never marks a window closed | ✓ VERIFIED | `aHungAppDoesNotDelayAnotherAppsNewWindow`, `aHungAppNeverLosesAWindowOverFiveRefreshes`, `lockBlankingClosesNothing`, `blankingWithoutTheGateAlsoClosesNothingBecauseEveryReadTimesOut` green |
| SC5 | With `_AXUIElementGetWindow` forced unavailable, Pane launches and tracks through its fallback | ✓ VERIFIED | dlopen/dlsym only; CapabilitiesTests and WindowIDResolverTests green; FallbackIntegrationTests passed in the fixer's live gate |

### Plan must-have truths (145 across 17 plans)

Every artifact passes `verify.artifacts` (all 17 plans exit 0; 02-14 to 02-17: 19/19). Key links: plans 02-14 to 02-17 pass 13/13. 02-11 and 02-12 now each report one failing link, because the pattern went stale (warning 3). I checked the wiring by hand, and it holds.

| Plan | Truths | Verified | Failed | Backstop (→ human) | Behaviour-unverified | Notes |
|---|---|---|---|---|---|---|
| 02-01 | 11 | 11 | 0 | 0 | 0 | Regression: unchanged areas, suites green |
| 02-02 | 9 | 8 | 0 | 1 (glyph) | 0 | |
| 02-03 | 10 | 9 | 0 | 1 (PiP) | 0 | |
| 02-04 | 5 | 5 | 0 | 0 | 0 | LifecycleSync ignores `windowRekeyed` (Phase 3 obligation, 02-16) |
| 02-05 | 12 | 11 | 0 | 1 (CFBundleName wrap) | 0 | |
| 02-06 | 9 | 9 | 0 | 0 | 0 | |
| 02-07 | 7 | 7 | 0 | 0 | 0 | |
| 02-08 | 12 | 12 | 0 | 0 | 0 | |
| 02-09 | 9 | **9** | 0 | 0 | 0 | Truth 2 now holds (gap 2) |
| 02-10 | 8 | **7** | 0 | 1 (real-app tabs) | 0 | Truth 1 now holds (gap 1) |
| 02-11 | 7 | **7** | 0 | 0 | 0 | Truths 2 and 4 now hold (gaps 4, 5) |
| 02-12 | 8 | **8** | 0 | 0 | 0 | Truth 5 holds (gap 3). Truth 4 passes via the 7c97838 override (its rule text is stale) |
| 02-13 | 9 | 8 | 0 | 1 (multi-display) | 0 | |
| 02-14 | 10 | 10 | 0 | 0 | 0 | Truth 9 states the accepted C5 limit and its two safety invariants, which pass in fallback mode |
| 02-15 | 7 | 7 | 0 | 0 | 0 | Truths 1, 2 and 7 pass via the 7c97838 override (old rule text; the at-min clause is now an accepted limit). Truth 5's live test predates 7c97838 (warning) |
| 02-16 | 6 | 6 | 0 | 0 | 0 | Truth 5 is now stronger after the WR-02 fix (counted once per element for its lifetime, up to 64) |
| 02-17 | 6 | 5 | 0 | 0 | **1** | Truth 2 (live notification observer): wired at `AXWindowSystem.swift:110-114, 223, 244, 335`, but no test posts a real notification |

**Score:** 144/150 truths verified (5 roadmap SCs + 145 plan truths). 0 failed. 5 backstops routed to a human (insufficient_spec). 1 present and wired but behaviour-unverified. 5 truths pass via override: C5 (single-Space fallback) and the four learner truths whose text predates 7c97838.

### Prohibitions (judgment tier, mode-dependent soft gate)

There are 24 prohibitions: 23 from 02-01..13 and 1 new in 02-14. All are judgment tier with no wired negative test. The verdicts are **non-authoritative LLM-judge verdicts**, flagged `unverified-prohibition: human review recommended`.

| Prohibition (plan) | LLM verdict | Evidence |
|---|---|---|
| SkyLight never linked at link time (14, new) | holds | `grep SkyLight Package.swift xcode/project.yml` finds nothing; no `@_silgen_name` anywhere; `SkyLightSpaces.swift:19-25` uses dlopen/dlsym only |
| No link-time private symbols (01) | holds | dlopen/dlsym only |
| Titles never logged (01, 08) | holds | No logger call in the gap-closure diff carries a title |
| No TrellisWM material or copied code (01) | cannot judge | Provenance needs a human |
| **Never discard a tracked window on one source (09)** | **holds (was violated)** | A fold now needs two consecutive refreshes with the same shown tab (AX tab bar plus CG offscreen slot), and is held during a blind Space switch. The scenario invariant passes in all modes |
| A tab switch never looks like close+open (10) | holds | D1/D2/R1 and my Probe5 V2-V4 report no create or destroy |
| Private-API failure never stops launch (11) | holds | Optional pointers; Spaces degrades on its own |
| CG names never logged or stored (11) | holds | `WindowIDResolver.swift:104-107`: names used for one ambiguous match only |
| Hints file stores only bundle IDs and sizes (13) | holds | MinimumHintsStore schema unchanged |
| The other 15 (02, 03, 04, 05, 06, 07, 08, 12, 13) | hold | Unchanged since the previous verification; the code they cover was not touched by the gap closure, or was touched only additively |

The phase completes with 24 flagged prohibitions, none judged violated.

### Key Link Verification

02-14: 3/3, 02-15: 3/3, 02-16: 3/3, 02-17: 4/4. Plans 02-01..10 and 02-13 all exit 0. 02-11 (`FallbackMatcher\.match` in AXSnapshotReader) and 02-12 (`learner\.learn` in WindowTracker) fail on patterns the gap closure renamed. The manual trace: `AXSnapshotReader.swift:59` → `WindowIDResolver.resolve` → `FallbackMatcher.match` (`WindowIDResolver.swift:103, 106`); `WindowTracker.applyFrameResult` → `learner.recordWrite` (297) and `ingest` → `learner.confirm` (161). The links are WIRED.

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| StatusItemController header | inventory counts | `system.inventory()` ← WindowTracker ← AXAppThread | yes | ✓ FLOWING (IN-02 filter mismatch carried) |
| TrackedWindowsView rows | WindowInfo list | TrackedWindowsModel ← inventory + exclusions | yes | ✓ FLOWING |
| WindowInfo.learnedMinimum | learned size | MinimumSizeLearner.confirm ← ingest ← AX refresh ≥1 s after the write | yes | ✓ FLOWING |
| Bundle hints | per-bundle minimums | MinimumHintsStore → setBundleHints at launch; in-session raise in WindowTracker; `onLearnedMinimum` → `hints.record` / `save` | yes | ✓ FLOWING (IN-04 resolved) |
| Window Spaces | `[UInt32: Set<UInt64>]` | `SkyLightSpaces.spaces(of:)` ← this pid's layer-0 CG IDs → ObservationContext → TabGroupTracker | yes (live SpacesIntegrationTests, fixer's gate) | ✓ FLOWING |
| Space-switch flag | `spaceChanged` | NSWorkspace notification → SpaceSwitchMarks → ObservationContext | wired; real notification untested | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED (02-17#2) |
| Debug menu captions | AXWindowID and Spaces state | CapabilitySession | yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Non-live suite green | `swift test --skip PaneMacIntegrationTests` (run once per pass) | At HEAD 0605100: 142 + 97 + 234 = 473 tests passed, 0 failures, exit 0 (470 at 29242da) | ✓ PASS |
| Engine and Model AppKit-free | `bash scripts/check-no-appkit.sh` | `no-appkit: OK (25 files)` | ✓ PASS |
| CR-01 (iter. 3) cross-Space cases | `swift run Probe3` (scratchpad/probe3, real trackers at HEAD) | C1-C7 as in the gap table; output identical to `scratchpad/final/probe3.txt` apart from the build banner | ✓ PASS (C5 under override) |
| CR-01 (iter. 4) crash and duplicate | `.build/debug/Probe4 crash`, `dup` | D1 `[(10,10,3)]`, exit 0 (was 133); D2 one row throughout | ✓ PASS |
| WR-01 stale sweep CG | `.build/debug/Probe4 race` | One row at every step; no `created 40`, no DESTROYED | ✓ PASS |
| Merge fold guard | `.build/debug/Probe4 c3` | Merged 20 destroyed on the third refresh, by design | ✓ PASS |
| Orphan handoff | `.build/debug/Probe4 orphan` | No Space data, and twin answered: group destroyed, twin created. Partial Space map: `[(30,50,1)]` (IN-14, Info) | ✓ PASS (IN-14 Info) |
| Learner | `.build/debug/Probe4c` (rebuilt after 7c97838; binary newer than every PaneEngine source) | snap nil; clamped 500; at-min nil (accepted limit); lag-2 nil; early then 1.05 s → 500; late applier (>1 s) nil (was 800) | ✓ PASS |
| Chained re-key | `.build/debug/Probe4d` | `rekeyed 900 -> 20 / rekeyed 20 -> 30 / created 20` (IN-13, Info) | ? Info |
| My own adversarial cases | `scratchpad/reverify/probe5` (V1 two onscreen same-frame windows plus Cmd-T, stale and fresh CG; V2 Cmd-W on the shown tab; V3 Cmd-T plus Cmd-W in one refresh; V4 stale Cmd-T then Ctrl-Shift-Tab) | Every step keeps one row per real window, with no spurious create or destroy | ✓ PASS |
| Debt markers in the 31 changed files | `grep -nwE 'TBD\|FIXME\|XXX'` and `TODO\|HACK\|PLACEHOLDER\|RED stub` | none | ✓ PASS |
| Live integration suite | not run (instructed) | Fixer's gate at `5a0894a`: 24 passed, 1 skipped (needs 2 displays) | ? SKIP (gate evidence accepted) |

All probe outputs are in `/private/tmp/claude-501/-Users-ken-dev-panewm/fa534412-df62-4443-994d-8e3bd65099ce/scratchpad/reverify/`. At 29242da, every Probe4/4c/4d output was byte-identical to `scratchpad/final/`. After 7c97838, `probe4c-2.txt` differs from it in exactly two rows: at-min and late applier, both now nil. Probe3, Probe4 and Probe5 do not exercise frame writes, and 7c97838 changed only the learner and its `recordWrite` call, so their results stand. The probe binaries are newer than every PaneEngine source they link (TabGroupTracker.swift 16:02:31, binaries 16:02:50; the later 5a0894a touched only PaneMac).

### Probe Execution

No `scripts/*/tests/probe-*.sh` is declared or present, so Step 7c does not apply. The reviewer's Swift harnesses were run as behavioural spot-checks (above).

### Requirements Coverage

| Requirement | Source plans | Description | Status | Evidence |
|---|---|---|---|---|
| WIN-01 | 02, 05 | Guided grant; stale grant detected | ✓ SATISFIED (automated) | Real TCC needs a human |
| WIN-02 | 01, 02, 06, 08, 09, 16 | Tracks every standard window | ✓ SATISFIED | Gap 5 closed: re-check and re-key, unique IDs |
| WIN-03 | 07, 08, 12 | Hung app never freezes Pane | ✓ SATISFIED (automated) | Real kill -STOP needs a human |
| WIN-04 | 06, 12, 13, 15 | Move/resize; learn minimum | ✓ SATISFIED | Gap 3 closed; late applier refused (7c97838); at-minimum window learns once a write moves it (accepted limit, override) |
| WIN-05 | 03 | Dialogs, sheets, popovers, PiP never docked | ✓ SATISFIED | Corpus green; label review and PiP capture need a human |
| WIN-06 | 10, 14, 17 | Native tabs count as one window | ✓ SATISFIED | Gap 1 closed; C5 fallback under override |
| WIN-08 | 08, 13 | Exclusion list | ✓ SATISFIED | |
| WIN-09 | 04, 09, 14, 17 | Close only on two sources; lock, sleep, timeouts never close | ✓ SATISFIED | Gap 2 closed; fold guard and Space-switch hold |
| SAFE-05 | 01, 02, 11, 14, 16 | Broken private API disables only its feature | ✓ SATISFIED | Gap 4 closed; Spaces is its own capability with a single-Space fallback |

All 9 IDs are claimed by plans. REQUIREMENTS.md maps no other ID to Phase 2, so nothing is orphaned. REQUIREMENTS.md marks all nine complete. That is now consistent with the code, pending the human UAT.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (31 files changed since b63a0d4) | — | TBD/FIXME/XXX, TODO/HACK/placeholder | none found | — |
| Sources/PaneEngine/TabGroupTracker.swift | 46-50 | `shortcut:` documenting the accepted single-Space and late-notification limits | ℹ️ Info | Accurate; matches the override and accepted_limits |
| Sources/PaneEngine/MinimumSizeLearner.swift | 5-14 | Doc rewritten by 7c97838; it states the moved rule and the at-minimum limit | ℹ️ Info | Resolved warning 1 |
| Sources/PaneEngine/WindowTracker.swift | 396-398 | Misplaced doc comment (IN-15) | ℹ️ Info | — |
| Sources/PaneEngine/WindowTracker.swift | 55-60 | Re-keys applied one at a time (IN-13, Probe4d) | ℹ️ Info | A chained correction can swap two windows' entries; needs two lookup failures in a row |
| Sources/PaneEngine/TabGroupTracker.swift | 89 | Blind switch keyed on the batch, not on the window (IN-14, Probe4 orphan) | ℹ️ Info | A partial Space map can hand a closed group to a twin |
| Probe3 C3 / Probe4 C3b | — | Merge All Windows shows the merged window twice for one refresh before the fold guard destroys it | ℹ️ Info | The intended cost of the two-refresh guard |
| IN-01..03, IN-06..12 | — | Carried from 02-REVIEW.md | ℹ️ Info | Not gaps (lead instruction) |

### Human Verification Required

There are 18 items in the `human_verification` frontmatter, plus 1 `behavior_unverified_items` entry (a real Space switch reaching AXWindowSystem). The items:
- the grant flows (4)
- the menu glyph and Debug lines
- lock/sleep
- kill -STOP
- the Freeze test
- multi-display Nudge
- real Finder/Terminal/Safari tabs, including quick Cmd-T then Ctrl-Shift-Tab, and Cmd-T then clicking an older tab
- real Space switches with tab groups, with and without `--disable-private=Spaces`
- Chrome/Electron/Terminal frame writes and the minimum-size hints, after deleting `min-size-hints.json` first
- exclusions in the real UI
- the signed app over 10 minutes of normal use and with `--disable-private=AXWindowID`
- the corpus label review before the public push
- the PiP capture
- the UI-REVIEW visual items
- clean-room provenance

### Gaps Summary

There are no gaps. All five previous gaps are closed in code and in committed tests, and the reviewer's harnesses confirm each one against HEAD. So do four extra tab-timing scenarios I wrote myself. The iteration-4 review findings (CR-01 crash and duplicate, WR-01 stale sweep, WR-02 per-listing count) are fixed, and the probes that exposed them now pass.

All three warnings from the first pass of this round are resolved:
1. **Late applier:** hardened by `1a5f2b1` and `7c97838` (lead decision). Probe4c now returns nil.
2. **02-SECURITY.md:** audited by `3d8e390` (49/49 threats closed).
3. **Key-link patterns:** fixed by `dd7e231`. Both plans exit 0.

The hardening adds one accepted limit: a window already at its minimum learns only once a write moves it. Four learner truths still state the old rule, so they pass through overrides of that lead decision. Two small follow-ups remain:
- revise the text of 02-12 truth 4 and 02-15 truths 1, 2 and 7;
- run FrameWriteIntegrationTests once live, because its last live pass predates `7c97838`.

The documented Known limits of 02-14..02-17 are recorded under `accepted_limits` and the C5 override. IN-13 and IN-14 stay Info.

**Deferral check (Step 9b):** there are no gaps to defer. Phase 6's co-visibility window-to-Space map is the stated upgrade path for the late-notification and single-Space limits.

---

_Verified: 2026-10-25T22:02:46Z_
_Verifier: Claude (gsd-verifier)_
