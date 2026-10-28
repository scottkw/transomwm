---
phase: 02-window-control
verified: 2026-10-28T01:37:08Z
status: passed
score: 160/161 must-haves verified (1 deferred, the multi-display backstop for UAT 9; 5 pass via override)
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
  - ".planning/phases/02-window-control/02-18-PLAN.md"
  - ".planning/phases/02-window-control/02-18-SUMMARY.md"
  - ".planning/phases/02-window-control/02-19-PLAN.md"
  - ".planning/phases/02-window-control/02-19-SUMMARY.md"
  - "Package.swift"
  - "Sources/TransomApp/main.swift"
  - "Sources/TransomEngine/Classifier.swift"
  - "Sources/TransomEngine/CloseRule.swift"
  - "Sources/TransomEngine/Coordinates.swift"
  - "Sources/TransomEngine/CorpusCase.swift"
  - "Sources/TransomEngine/ExclusionFilter.swift"
  - "Sources/TransomEngine/FallbackMatcher.swift"
  - "Sources/TransomEngine/LifecycleSync.swift"
  - "Sources/TransomEngine/MinimumSizeLearner.swift"
  - "Sources/TransomEngine/PermissionReducer.swift"
  - "Sources/TransomEngine/ResponsivenessTracker.swift"
  - "Sources/TransomEngine/SpaceSwitchMarks.swift"
  - "Sources/TransomEngine/TabGroupTracker.swift"
  - "Sources/TransomEngine/WindowSnapshot.swift"
  - "Sources/TransomEngine/WindowSystem.swift"
  - "Sources/TransomEngine/WindowTracker.swift"
  - "Sources/TransomFixtureApp/main.swift"
  - "Sources/TransomMac/AX/AXAppThread.swift"
  - "Sources/TransomMac/AX/AXSnapshotReader.swift"
  - "Sources/TransomMac/AX/AppRegistry.swift"
  - "Sources/TransomMac/AX/FrameWriter.swift"
  - "Sources/TransomMac/AX/SyntheticWindowIDs.swift"
  - "Sources/TransomMac/AX/WindowIDResolver.swift"
  - "Sources/TransomMac/AXWindowSystem.swift"
  - "Sources/TransomMac/CGWindowList.swift"
  - "Sources/TransomMac/Displays.swift"
  - "Sources/TransomMac/ExclusionStore.swift"
  - "Sources/TransomMac/MinimumHintsStore.swift"
  - "Sources/TransomMac/Permission/PermissionController.swift"
  - "Sources/TransomMac/Permission/PermissionProbe.swift"
  - "Sources/TransomMac/Permission/SetupView.swift"
  - "Sources/TransomMac/Permission/SetupWindowController.swift"
  - "Sources/TransomMac/Permission/TCCReset.swift"
  - "Sources/TransomMac/RefreshScheduler.swift"
  - "Sources/TransomMac/SessionGate.swift"
  - "Sources/TransomMac/Shell/FreezeTest.swift"
  - "Sources/TransomMac/Shell/MenuCopy.swift"
  - "Sources/TransomMac/Shell/Nudge.swift"
  - "Sources/TransomMac/Shell/StatusItemController.swift"
  - "Sources/TransomMac/Shell/TrackedWindowsModel.swift"
  - "Sources/TransomMac/Shell/TrackedWindowsView.swift"
  - "Sources/TransomMac/Shell/TrackedWindowsWindowController.swift"
  - "Sources/TransomMac/TransomMacApp.swift"
  - "Sources/TransomPrivate/AXWindowID.swift"
  - "Sources/TransomPrivate/Capabilities.swift"
  - "Sources/TransomPrivate/SkyLightSpaces.swift"
  - "Sources/TransomTestSupport/FakeWindowSystem.swift"
  - "Sources/transom-dump/main.swift"
  - "Tests/TransomEngineTests/ClassifierCorpusTests.swift"
  - "Tests/TransomEngineTests/ClassifierTests.swift"
  - "Tests/TransomEngineTests/CloseRuleTests.swift"
  - "Tests/TransomEngineTests/CloseScenarioTests.swift"
  - "Tests/TransomEngineTests/CoordinatesTests.swift"
  - "Tests/TransomEngineTests/ExclusionScenarioTests.swift"
  - "Tests/TransomEngineTests/FakeWindowSystemTests.swift"
  - "Tests/TransomEngineTests/FallbackMatcherTests.swift"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/README.md"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/android_studio_welcome.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/finder_desktop.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/finder_main_window.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/finder_two_tabs.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/libreoffice_start_center.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/safari_browser_window.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/safari_pip.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/safari_settings.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/system_settings.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/terminal_settings.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/terminal_window.json"
  - "Tests/TransomEngineTests/Fixtures/AXDumps/vscode_main_window.json"
  - "Tests/TransomEngineTests/FrameScenarioTests.swift"
  - "Tests/TransomEngineTests/LifecycleSyncTests.swift"
  - "Tests/TransomEngineTests/MinimumSizeLearnerTests.swift"
  - "Tests/TransomEngineTests/PermissionReducerTests.swift"
  - "Tests/TransomEngineTests/ResponsivenessScenarioTests.swift"
  - "Tests/TransomEngineTests/ResponsivenessTrackerTests.swift"
  - "Tests/TransomEngineTests/SpaceSwitchMarksTests.swift"
  - "Tests/TransomEngineTests/TabGroupTrackerTests.swift"
  - "Tests/TransomEngineTests/TabScenarioTests.swift"
  - "Tests/TransomEngineTests/TrackerClassificationTests.swift"
  - "Tests/TransomEngineTests/TrackerDisplayTests.swift"
  - "Tests/TransomEngineTests/WindowTrackerTests.swift"
  - "Tests/TransomMacIntegrationTests/ClassificationIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/CloseIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/ExclusionIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/FallbackIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/FixtureShapesTests.swift"
  - "Tests/TransomMacIntegrationTests/FixtureTrackingTests.swift"
  - "Tests/TransomMacIntegrationTests/FrameWriteIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/FreezeIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/IntegrationSupport.swift"
  - "Tests/TransomMacIntegrationTests/LiveTrackingTests.swift"
  - "Tests/TransomMacIntegrationTests/NudgeIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/SpacesIntegrationTests.swift"
  - "Tests/TransomMacIntegrationTests/TabsIntegrationTests.swift"
  - "Tests/TransomMacTests/CapabilitiesTests.swift"
  - "Tests/TransomMacTests/ExclusionStoreTests.swift"
  - "Tests/TransomMacTests/FreezeTestTests.swift"
  - "Tests/TransomMacTests/MenuCopyTests.swift"
  - "Tests/TransomMacTests/MinimumHintsStoreTests.swift"
  - "Tests/TransomMacTests/NudgeTests.swift"
  - "Tests/TransomMacTests/SessionGateTests.swift"
  - "Tests/TransomMacTests/SetupWindowTests.swift"
  - "Tests/TransomMacTests/TCCResetTests.swift"
  - "Tests/TransomMacTests/TrackedWindowsModelTests.swift"
  - "Tests/TransomMacTests/WindowIDResolverTests.swift"
  - "Tests/TransomModelTests/NoAppKitTests.swift"
  - "scripts/build-debug.sh"
  - "scripts/generate.sh"
  - "scripts/run-debug.sh"
  - "xcode/Transom.entitlements"
  - "xcode/project.yml"
covered_digest: "v4:sha256:20999420f23eb39d98f64b521b2293e02009b64a1324181d3402e344d959b117"
behavior_unverified: 0
overrides_applied: 5
overrides:
  # Carried forward unchanged from the 2026-10-25 verification.
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
  # Carried forward from the 2026-10-25 verification (lead decisions of 2026-10-25), plus the 02-19 and review-fix residuals.
  # None of them makes a must-have truth fail. Listed so they are not re-raised as gaps.
  - limit: "Single-Space fallback: without Space data, C5 may track two same-frame tab groups as one window (the override above)"
    source: "02-14-SUMMARY Known limits 1"
  - limit: "With Space data, a hidden tab of unknown Space is left out of its group while a window known to be on another Space shares the frame slot, until a tab switch shows it (visibleMemberID and tabCount unaffected)"
    source: "02-14-SUMMARY Known limits 2"
  - limit: "Late Space notification: a notification that reaches main only after the update that already saw the new Space protects nothing"
    source: "02-17-SUMMARY Known limits; upgrade path is the Phase 6 window-to-Space map"
  - limit: "A window already at its minimum learns nothing from a write that does not move it, and learns once a write moves it"
    source: "Lead decision 2026-10-25, commit 7c97838; UAT 12 and debug g-02-12 confirm it is the designed behaviour (G-02-12 closed with no code change)"
  - limit: "32 pt learner margin; the 1 s confirm refresh can replace a pending refresh of the same pid"
    source: "02-15-SUMMARY Known limits"
  - limit: "02-16 identity residuals: a holder with no frame or no CG list loses its window to the owner; a tab re-keyed inside a group does not re-point pendingFocus"
    source: "02-16-SUMMARY Known limits"
  - limit: "02-19 timing links: a Cmd-T or tab switch in the same update as a blind Space switch links only through the slot; a same-app window leaving the Space in the same refresh as a new tab can be taken as its opener or group (identity misattributed, never a window lost)"
    source: "02-19-SUMMARY Known limits; pinned by knownLimitAWindowLeavingTheSpaceWithACmdTCanBeTakenAsItsOpener"
  - limit: "Review-fix residuals: a Cmd-W in the refresh right after a group was not rebound can miss the handoff (destroy plus create, no window lost); without Space data and without the switch notification, a window on another Space with fewer tabs can take a closing group's identity"
    source: "02-REVIEW-GAPS2-FIX.md Residual limits"
re_verification:
  previous_status: human_needed
  previous_score: 144/150
  gaps_closed:
    - "G-02-1 (UAT 1): with no Accessibility grant the Set Up Transom window opens at its SwiftUI content size, centred, and follows each permission state (02-18)"
    - "G-02-10 (UAT 10): a native tab group stays one row through Cmd-T with a taller new tab, Cmd-T after a resize, Cmd-W and frame writes, even though hidden tabs keep stale CG bounds (02-19, review fixes 7dc33a8, cec2ec8, 47f11e4, eae0286)"
    - "G-02-12 (UAT 12): closed with no code change; the test setup started Notes exactly at its minimum, and the corrected step passes"
    - "Previous human_verification items: 17 of 18 passed in the Tart VM (02-UAT.md); UAT 9 (multi-display) is deferred by the user"
    - "Previous behaviour-unverified item (02-17 truth 2, live Space-switch notification): accepted by the developer through UAT 11 (pass); see warnings for the sub-step not run"
  gaps_remaining: []
  regressions: []
gaps: []
deferred:
  - truth: "UAT 9 / 02-13 multi-display backstop: Nudge on the built-in display and on an external display above, left and below; Display column follows; one displaysChanged then one refresh about 500 ms after a hot-plug (ROADMAP SC3 'including secondary displays in any arrangement')"
    addressed_in: "Re-check on the first Transom build (STATE.md Pending Todos), on the DELL second display. User decision 2026-10-27, the same deferral as Phase 3's second-display checks"
    evidence: "Headless coverage is green: CoordinatesTests, TrackerDisplayTests and NudgeTests (arrangements above, left and below; exact restore). The live second-display NudgeIntegrationTests case needs two displays. The Tart VM has one virtual display (02-UAT.md test 9, blocked: physical-device)"
advisory:
  - finding: "WR-02 residual, not built by the fixer: a group that still knows a hidden member outside the new shown tab's slot (resized after the sweep), then Cmd-W onto a stale non-member tab, gets no orphan handoff; the identity is destroyed and recreated (the window stays tracked, under a new row)"
    category: other
    reason: "Documented in 02-REVIEW-GAPS2-FIX.md Residual limits. No window is lost, but Phase 3 would see a close and an open. Resolve with a tracker test that builds this case"
    evidence_status: "none provided (not reproduced by a test or probe)"
  - finding: "IN-04 not fixed: with Space data on, a Space switch refuses no timing link when either Space set is empty (a hidden tab may report no Space)"
    category: other
    reason: "Design change left out of scope by the fixer. Could misattribute an identity after a Space switch; never destroys. Resolve by requiring confirmed Spaces for timing links when spaceChanged is true"
    evidence_status: "none provided"
  - finding: "IN-05 not fixed: knownLimitAWindowLeavingTheSpaceWithACmdTCanBeTakenAsItsOpener pins a 3-row result (one stale row) as its expected value without withKnownIssue"
    category: other
    reason: "A later fix would show up as a test failure rather than a pass; the type doc does not mention the leftover row"
    evidence_status: "test passes as written; the 3-row value is the documented limit"
  - finding: "IN-03 not fixed: SetupWindowTests.waitFor keeps looping after success and has a 2 s budget that may be tight on a loaded CI runner"
    category: other
    reason: "Possible future flake, not a defect today (both tests passed in this run)"
    evidence_status: "none provided"
warnings:
  - finding: "Two UAT sub-steps were accepted by the developer without being run: (a) UAT 11's whole-group close followed by an immediate Space switch, which is the only live check of 02-17 truth 2 (AXWindowSystem's activeSpaceDidChangeNotification observer marking spaceChanged); (b) UAT 17's long-CFBundleName wrap at 480 pt (02-05 backstop)"
    category: other
    evidence: "02-UAT.md test 11 note 'Not run: ... the whole-group close plus immediate switch'; test 17 note 'Not checked: a long CFBundleName wrap at 480 pt'. No headless test posts a real notification: the observer is registered in AXWindowSystem.start() (AXWindowSystem.swift:116-124), which starts live AX. SpaceSwitchMarks' consume rule and the engine hold are unit-tested"
    reason: "Both test results are 'pass' by the developer, so they count as verified here. Recommend adding the close-then-switch step to the STATE.md re-check on the first Transom build"
  - finding: "Live FrameWriteIntegrationTests.aRefusedSizeIsReadBackAndLearned has no recorded green run after 7c97838; 03-20-SUMMARY records it failing its 2 s learning wait in a host run"
    category: other
    evidence: "03-20-SUMMARY.md:128. The same mechanism passed live on a real app afterwards: UAT 12 in the VM learned Notes' 642x324 minimum about 1.5 s after a Nudge and kept it across a relaunch. The headless equivalent theFakeClampsToItsHiddenMinimumAndTheTrackerLearnsItFromOneWrite passes"
    reason: "Run 'scripts/vm-live-test.sh' with FrameWriteIntegrationTests once on the next VM session; a 2 s wait may be tight against the 1 s confirm delay plus the refresh"
  - finding: "Plans 02-01..02-17 still name Pane paths (Sources/PaneEngine/...), so verify.artifacts reports 0/N for them at HEAD; the learner plan text (02-12 truth 4, 02-15 truths 1, 2, 7) still states the pre-7c97838 rule"
    category: other
    evidence: "With the paths mapped Pane to Transom, all 17 plans pass verify.artifacts (76/76) and 16 of 17 pass verify.key-links. 02-08's 'exclusions\\.toggle' pattern is stale since 03-10 moved the toggle to ArrangeController.swift:389 (store.toggle); UAT 13 passed live"
    reason: "Historical plan text only; code and tests are correct. Optional cleanup"
human_verification: []
---

# Phase 2: Window Control Verification Report

**Phase Goal:** As a Mac user, I want to grant Transom (formerly Pane) access and have it track and move every window, so that no slow app or lock screen can freeze or lose them.
**Mode:** mvp. The user-story format is valid. Outcome clause: *no slow app or lock screen can freeze or lose them*.
**Verified:** 2026-10-28T01:37:08Z at HEAD `43c88f5`. The code is unchanged since `f8932bb`; `299e887` and `43c88f5` touch docs only.
**Status:** passed
**Re-verification:** Yes. This follows the VM UAT (02-UAT.md, 17 passed, 0 issues, 1 blocked), gap closures 02-18 (G-02-1) and 02-19 (G-02-10), the gap-closure review (02-REVIEW-GAPS2.md), and its fixes 7dc33a8, cec2ec8, 47f11e4, eae0286, 7b9e8fe and f8932bb. The previous status was human_needed, 144/150, with no gaps.

## User Flow Coverage (MVP)

| Step | Expected | Evidence | Status |
|---|---|---|---|
| Grant access | A readable guided grant; stale grant detected and explained | 02-18: `SetupWindowController.makeWindow()` uses `sizingOptions = [.preferredContentSize]` plus one `setContentSize(fittingSize)` before centring (lines 47-60). SetupWindowTests (2) pass headless. UAT 1, 2, 3 and 17 pass in the VM (480x345, centred, and shrinks to 480x253 on ready) | ✓ VERIFIED (G-02-1 closed) |
| Track every window | Every standard window; a tab group is one window | 02-19 timing links plus the review fixes. E1, E4, Cmd-W and frame-write scenarios pass in all 3 Space modes. UAT 10 and 11 were re-checked on the review-fix build: one row per real window, Finder 5 for 5, Terminal 7 for 7 | ✓ VERIFIED (G-02-10 closed) |
| Move every window | setFrame on any display; learn the real minimum; exclusions respected | FrameScenarioTests, learner tests, ExclusionScenarioTests. UAT 12: Notes learned 642x324 live and kept it after a relaunch. UAT 13: exclusions work in the real UI | ✓ VERIFIED. The secondary-display live check (UAT 9) is deferred |
| No slow app freezes it | A hung app is isolated per thread | Responsiveness scenario tests. UAT 7 (`kill -STOP` TextEdit) and UAT 8 (Freeze test) pass live | ✓ VERIFIED |
| No lock screen loses them | Lock, sleep and timeouts never close a window | CloseRule, SessionGate, fold guard. UAT 6: lock and unlock kept all 16 windows | ✓ VERIFIED (sleep/wake not run live; headless SessionGate and blanking tests cover it) |

The outcome clause holds in code, in the headless tests, and live in the VM.

## Goal Achievement

### Gap closures since the last report

| Gap / finding | Fix | Evidence I ran | Status |
|---|---|---|---|
| G-02-1: setup window opened at 1x28 | `0378755`: `[.preferredContentSize]` and `setContentSize(hosting.view.fittingSize)` before the centring reads `window.frame` | `theSetupWindowHasItsContentSizeBeforeItIsShown` (size equals fittingSize within 1 pt, centred, never shown) and `theSetupWindowHeightFollowsAPermissionStateChange` (a `#require` that the heights differ blocks a vacuous pass) both pass. UAT 1/2/3/17 pass live | ✓ CLOSED |
| G-02-10: stale extra tab-group rows | `859c77c`, `7f764ad`: timing opener (`wentHidden`), persistent own members, timing join, `nearest` tie-break; the fake keeps stale hidden-tab frames (`3514f43`) | `aCmdTWhoseNewTabIsTallerStaysOneWindowLedByItsOpener` (E1), `aCmdTAfterTheShownTabWasResizedStaysOneGroup` (E4), `cmdWInAResizedGroupFollowsTheNextTab`, `aFrameWriteToATabGroupThenCmdTStaysOneGroup`, each ×3 modes; `aBlindSpaceSwitchLinksNoOpenerByTiming`, `aBlindSpaceSwitchMakesNoTimingJoin`: all pass. UAT 10/11 pass live | ✓ CLOSED |
| CR-01: the timing opener preempted the slot join | `7dc33a8`: the room-rule join runs first, then the standalone openers and the joinable groups compete in one `nearest` call (TabGroupTracker.swift:170-193) | `aCmdTInAGroupIsNeverHandedToAStandaloneThatWentHidden` (P1, ×3) and `aCmdTInAGroupBesideAMinimizedWindowWhoseReadTimedOutStaysInTheGroup` (P6: rows `[[10,10,1],[20,50,3]]` over 5 refreshes, nothing destroyed) pass | ✓ FIXED |
| WR-01: a failed read looked unlisted | `cec2ec8`: `listed:` parameter; WindowTracker passes `listedInAXWindows` IDs (WindowTracker.swift:80). `leftAX`, `canBeHiddenTab` and `lastListed` use it | `aListedWindowWhoseReadFailedIsNeverTakenAsTheOpener`, `aListedWindowWhoseReadFailedIsNeverAHiddenTab` pass | ✓ FIXED |
| WR-02: orphan handoff needed a bounds match | `47f11e4`: handoff by evidence (untracked offscreen last refresh, fewer tabs than the group's last count, every member gone); bounds only break ties (195-206) | `cmdWOnAGroupFirstSeenWithStaleHiddenTabsKeepsItsIdentity`, `cmdWAfterARelaunchKeepsTheGroupsIdentity` (rows `[[219,216,2]]`, created `[219]`, nothing destroyed), `aFormerTabOutsideTheSlotStillTakesTheIdentity`, `aWindowWithAsManyTabsAsTheGroupNeverTakesTheIdentity` pass | ✓ FIXED |
| WR-03: stale sweep CG list with a taller Cmd-T | `eae0286`: the timing opener accepts `leftAX` when the CG list is stale (182-185) | `aTallerNewTabMissingFromAStaleCGListStillTakesItsOpener`, `aTallerCmdTSeenWithAStaleSweepCGListStaysOneWindow` (rows `[[10,40,2]]`) pass | ✓ FIXED |
| IN-01, IN-02 | `7b9e8fe`: `overrideStateForTesting` is under `#if DEBUG` (PermissionController.swift:25-31). `f8932bb`: `makeWindow()` returns the existing window (line 41) | Code read; SetupWindowTests pass | ✓ FIXED |
| G-02-12 | No code change: wrong test setup (debug g-02-12) | UAT 12 passes with the corrected step | ✓ CLOSED |

All 15 commit hashes named in the SUMMARYs and the fix report exist (`verify.commits`: 15/15).

### Roadmap Success Criteria (contract)

| # | Truth | Status | Evidence |
|---|---|---|---|
| SC1 | Guided grant; stale grant detected and explained, no looping prompts | ✓ VERIFIED | PermissionReducerTests and SetupWindowTests green; UAT 1-4 pass live |
| SC2 | Tracked list shows every standard window, updates live, counts a tabbed Finder/Terminal/Safari window as one, never includes dialogs, sheets, popovers or PiP (corpus passes) | ✓ VERIFIED (C5 fallback via override) | The 12-case corpus (now including `safari_pip`, confirmed by the developer) is green. Tab gap closed (above). UAT 10, 11, 15, 16 pass |
| SC3 | Move/resize any window on any display, including secondary displays in any arrangement; learn the real minimum; never touch excluded apps | ✓ VERIFIED (live secondary display deferred) | FrameScenarioTests, CoordinatesTests, TrackerDisplayTests, NudgeTests, learner tests and ExclusionScenarioTests are green. UAT 12 and 13 pass live. The live second-display check (UAT 9) is deferred |
| SC4 | `kill -STOP` neither stalls Transom nor delays others; lock, sleep or AX timeout never marks a window closed | ✓ VERIFIED | Responsiveness and close scenario tests green; UAT 6, 7 and 8 pass live |
| SC5 | With `_AXUIElementGetWindow` forced off, Transom launches and tracks through its fallback | ✓ VERIFIED | CapabilitiesTests and WindowIDResolverTests green; UAT 14 (`--disable-private=AXWindowID,Bogus`) passes live, with 6 rows for 6 windows |

### Plan must-have truths

| Plan | Truths | Verified | Deferred | Notes |
|---|---|---|---|---|
| 02-01..02-17 | 145 | 144 | 1 | Regression: all suites green. The four backstops routed to a human last time passed UAT: glyph (UAT 5), PiP (UAT 16), CFBundleName wrap (UAT 17, the sub-check was not performed, see warnings) and real-app tabs (UAT 10). 02-17 truth 2 was accepted through UAT 11 (see warnings). 02-13's multi-display backstop is deferred (UAT 9). 5 truths pass via the carried-forward overrides |
| 02-18 | 4 | 4 | 0 | Size before show, centring, the height follows state, and the test is headless (no `show`, `send` or activation calls; checked by reading) |
| 02-19 | 7 | 7 | 0 | E1, E4, Cmd-W, frame write, timing link with the blind-switch refusal, persistent members. Truth 7 held at 02-19's end (`062d605`: the Tests/ diff removed nothing). WR-02 later deliberately replaced one TabGroupTrackerTests case (`"outside the slot"`) that asserted the bounds premise G-02-10 disproved; positive and negative cases replace it (Info) |

**Score:** 160/161 truths verified (5 roadmap SCs + 156 plan truths). 0 failed. 1 deferred (UAT 9, multi-display). 0 behaviour-unverified. 5 pass via override (C5 single-Space fallback; four learner truths whose text predates 7c97838).

### Prohibitions

UAT 18 resolved the judgment-tier prohibition review: the developer confirmed clean-room status on 2026-10-27. 02-18 and 02-19 declare no prohibitions. The new code adds no link-time private symbol: `scripts/check-no-appkit.sh` passes, and the gap diff touches no `TransomPrivate` file.

### Required Artifacts

| Artifact | Status | Details |
|---|---|---|
| 02-18 (3) | ✓ VERIFIED | `verify.artifacts` 3/3, exit 0 |
| 02-19 (4) | ✓ VERIFIED | `verify.artifacts` 4/4, exit 0 |
| 02-01..02-17 (76) | ✓ VERIFIED after path mapping | They exit 1 at HEAD only because the plans name pre-rename `Pane*` paths. After mapping to `Transom*` (scratch copies), every plan passes |

### Key Link Verification

02-18: 2/2. 02-19: 2/2 (`wasListed`; `bounds: $0.frame` in the fake). With paths mapped, 02-01..02-17 pass except 02-08's `exclusions\.toggle`. Phase 3 (03-10) moved that call to `ArrangeController.swift:389` (`store.toggle(id)`), and UAT 13 confirms it live, so the link is WIRED. WindowTracker → TabGroupTracker `listed:` (WindowTracker.swift:78-80) is WIRED, and so is SetupWindowTests → `makeWindow()`.

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| Set Up Transom window size | `fittingSize` / `preferredContentSize` | SwiftUI SetupView for each PermissionState | yes (UAT 1: 480x345, then 480x253) | ✓ FLOWING |
| Tab-group rows | `TabResolution.groupFor`, `tabCount` | AX listed IDs + CG list + `lastListed`/`lastCG` → WindowTracker → inventory | yes (UAT 10/11 row counts match AX) | ✓ FLOWING |
| `listed` IDs | `Set<UInt32>` | `app.windows.filter(listedInAXWindows)` in WindowTracker | yes | ✓ FLOWING |
| Space-switch flag | `spaceChanged` | NSWorkspace notification → SpaceSwitchMarks → ObservationContext | wired; developer-accepted via UAT 11 | ✓ FLOWING (live sub-step not run, see warnings) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full headless suite | `env -u TRANSOM_LIVE swift test` (run once) | Exit 0. Four Swift Testing runs: 193 tests in 20 suites, 200 in 31, 42 in 20, 564 in 54 (999 total), 0 failures, no `✘`. The 4 XCTest lines "Executed 0 tests" are the empty XCTest harnesses. Live integration suites are skipped ("needs a process with the Accessibility grant") | ✓ PASS |
| Engine and Model AppKit-free | `bash scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | ✓ PASS |
| Named gap tests | `grep` of the saved run output | SetupWindowTests (2), E1/E4/Cmd-W/frame-write (×3 modes), CR-01 P1 (×3) and P6, WR-01 (2), WR-02 (4), WR-03 (2), blind-switch timing refusals (2): all `✔` | ✓ PASS |
| Commits exist | `gsd-tools verify.commits` (15 hashes) | all_valid | ✓ PASS |
| Debt markers in the gap-round files | `grep -nwE 'TBD\|FIXME\|XXX'` and `TODO\|HACK\|PLACEHOLDER` on the 9 changed files | none | ✓ PASS |
| Live integration and app | not run (headless only, as instructed) | Live evidence is the VM UAT | ? SKIP |

Saved run output: `/private/tmp/claude-501/-Users-ken-dev-transomwm/fb58eaa5-8cd9-4b77-941d-64fed871017b/scratchpad/verify02/swift-test.txt`.

### Probe Execution

No `scripts/*/tests/probe-*.sh` is declared or present, so Step 7c does not apply.

### Test Quality Audit (gap-round tests)

| Test file | Linked req | Skipped | Circular | Assertion level | Verdict |
|---|---|---|---|---|---|
| Tests/TransomMacTests/SetupWindowTests.swift | WIN-01 | 0 | no | Value (sizes within 1 pt, guarded against a vacuous pass) | OK |
| Tests/TransomEngineTests/TabScenarioTests.swift | WIN-06, WIN-09 | 0 | no | Behavioural (rows, created, destroyed across refreshes) | OK (IN-05 advisory) |
| Tests/TransomEngineTests/TabGroupTrackerTests.swift | WIN-06 | 0 | no | Value (`groupFor`, members) | OK |
| Tests/TransomEngineTests/FakeWindowSystemTests.swift | WIN-06 | 0 | no | Value (frames) | OK |

No `.disabled`, `withKnownIssue` or skip markers appear in these files. The expected values are hand-derived from the debug traces (E1, E4, P1-P6), not captured from the tracker.

### Requirements Coverage

| Requirement | Source plans | Status | Evidence |
|---|---|---|---|
| WIN-01 | 02, 05, 18 | ✓ SATISFIED | G-02-1 closed; UAT 1-4 |
| WIN-02 | 01, 02, 06, 08, 09, 16, 19 | ✓ SATISFIED | UAT 10, 11, 14 |
| WIN-03 | 07, 08, 12 | ✓ SATISFIED | UAT 7, 8 |
| WIN-04 | 06, 12, 13, 15 | ✓ SATISFIED | UAT 12; secondary display deferred (UAT 9) |
| WIN-05 | 03 | ✓ SATISFIED | 12-case corpus incl. PiP; UAT 15, 16 |
| WIN-06 | 10, 14, 17, 19 | ✓ SATISFIED | G-02-10 closed; UAT 10, 11 |
| WIN-08 | 08, 13 | ✓ SATISFIED | UAT 13 |
| WIN-09 | 04, 09, 14, 17, 19 | ✓ SATISFIED | UAT 6; no destroy in every gap scenario |
| SAFE-05 | 01, 02, 11, 14, 16 | ✓ SATISFIED | UAT 5, 14 |

REQUIREMENTS.md maps no other ID to Phase 2, so none is orphaned.

### Decision Coverage

The gate was skipped: there are no trackable decisions in 02-CONTEXT.md (`check.decision-coverage-verify`: total 0).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (9 files changed since 553f2b2) | — | TBD/FIXME/XXX, TODO/HACK/placeholder | none found | — |
| Sources/TransomEngine/TabGroupTracker.swift | 56-66 | `shortcut:` stating the single-Space, blind-switch and misattribution limits | ℹ️ Info | Accurate; matches accepted_limits |
| Sources/TransomEngine/TabGroupTracker.swift | 217-235 | `tier` recomputed in the sort comparator (IN-06) | ℹ️ Info | Harmless at real window counts |

### Advisory (New Scope, Unevidenced)

| # | Finding | Category | Why Advisory |
|---|---|---|---|
| 1 | WR-02 residual: a group with a hidden member outside the slot, then Cmd-W onto a stale non-member tab, is destroyed and recreated | other | No test or probe reproduces it; no window is lost |
| 2 | IN-04: Space-data-on switch with an unknown Space allows timing links | other | No deterministic evidence; misattribution only |
| 3 | IN-05: the known-limit test pins a 3-row value without `withKnownIssue` | other | Test hygiene |
| 4 | IN-03: SetupWindowTests `waitFor` budget may be tight on CI | other | Passed in this run |

### Human Verification Required

None outstanding. 02-UAT.md: 17 passed, 0 issues, 1 blocked. The blocked test, UAT 9, is deferred to the STATE.md re-check on the first Transom build, which needs the DELL second display. The warnings above name two sub-steps that the developer accepted without running them.

### Gaps Summary

There are no gaps. All three UAT gaps are closed: G-02-1 and G-02-10 in code, with headless tests and live VM re-checks, and G-02-12 as a corrected test step. CR-01 and WR-01 to WR-03 from the gap-closure review are fixed test-first. I read every fix in the code, and each named test passes in my own full run (999 Swift Testing tests, 0 failures). UAT 10 and 11 were re-checked live on the review-fix build.

**Deferred (Step 9b):** UAT 9, the multi-display Nudge, is deferred by the user to the re-check on the first Transom build (STATE.md Pending Todos), the same way Phase 3's second-display checks were. It does not affect the status.

---

_Verified: 2026-10-28T01:37:08Z_
_Verifier: Claude (gsd-verifier)_
