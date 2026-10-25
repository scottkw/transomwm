---
phase: 02-window-control
verified: 2026-10-25T18:34:53Z
status: gaps_found
score: 108/121 must-haves verified (8 failed, 5 backstops insufficient_spec)
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
  - "Tests/PaneModelTests/NoAppKitTests.swift"
  - "scripts/build-debug.sh"
  - "scripts/generate.sh"
  - "scripts/run-debug.sh"
  - "xcode/Pane.entitlements"
  - "xcode/project.yml"
covered_digest: "v3:sha256:ba1b84fafb0c3ccea883469ca226e7008e7e80aea566b11abf2fdc9b4d76b33a"
behavior_unverified: 0
overrides_applied: 0
gaps:
  - truth: "A natively tabbed window counts as one tracked window, and a same-frame window of the same app on another Space is never taken as its hidden tab (ROADMAP SC2; 02-10 truth 1; REVIEW CR-01)"
    status: failed
    requirement: WIN-06
    reason: "TabGroupTracker.update ranks hidden-tab candidates as own members (0), untracked windows (1), then tracked standalone windows and other groups' members (2), with ties broken by window ID. AX lists only the current Space, so a same-frame twin on a Space Pane has not visited yet is untracked and wins the slot over the window that really just became a tab. S4 (fixed in iteration 2) and C2 give update() the same inputs and need different answers, so reordering the tiers cannot fix both. I re-ran the reviewer's harness (scratchpad/probe3, Probe3) against HEAD and reproduced every case. C2, Cmd-T with an untracked twin: `[(10,10,1),(40,40,2)]`, so one real window is tracked twice. After a visit to Space 2 and a return, `DESTROYED 5` (or `DESTROYED 50`) is reported for a live window. C5, two same-frame groups on two Spaces: G1's visibleMemberID alternates 30 -> 10 -> 30 across Space switches, and G2 is never tracked. C7: Cmd-T joins a group from the other Space, and A stays tracked as a phantom."
    artifacts:
      - path: "Sources/PaneEngine/TabGroupTracker.swift"
        issue: "lines 87-98: tier() prefers untracked candidates over a tracked standalone window that was listed last refresh, even for a brand-new shown tab (Cmd-T). Line 91 binds a listed tabCount>=2 window to an existing group by membership alone, so G1 swallows G2 permanently. The shortcut comment at lines 31-33 claims the error 'corrects itself once the twin is listed'. That holds only for a twin without a tab bar"
      - path: "Sources/PaneEngine/WindowTracker.swift"
        issue: "lines 63-66: every TabResolution.folded identity is removed and reported windowDestroyed on CG bounds alone. This bypasses CloseRule, so a wrong fold destroys a live window"
      - path: "Sources/PanePrivate"
        issue: "has no Spaces lookup (only AXWindowID.swift and Capabilities.swift), so per-window Space membership cannot be used to rule out cross-Space twins"
      - path: "Tests/PaneEngineTests/TabScenarioTests.swift"
        issue: "no scenario presses Cmd-T while a same-frame twin is untracked (C2), and none has a twin that is itself a tab group (C5, C7). All three existing Space tests use standalone twins only"
    missing:
      - "Project-lead decision: pull forward from Phase 6 a READ-ONLY SkyLight Spaces lookup in its own PanePrivate file (e.g. Sources/PanePrivate/SkyLightSpaces.swift). It uses dlopen of /System/Library/PrivateFrameworks/SkyLight.framework/SkyLight plus dlsym into optional @convention(c) pointers: SLSMainConnectionID, SLSCopySpacesForWindows, and SLSGetActiveSpace or SLSManagedDisplayGetCurrentSpace as needed. Never link it at link time"
      - "Register it as a new Capability (e.g. `.spaces`) in Capabilities.swift: reported once in the launch capability log and in the Debug menu, forceable off with `--disable-private=Spaces`, with call-time degradation through CapabilitySession. SAFE-05: when it is missing or off, Pane falls back to single-Space behaviour and nothing else is disabled"
      - "Carry per-window Space IDs into PaneEngine without AppKit (e.g. an optional `spaceIDs: [UInt32: UInt64]` or a `spaceID` on CGWindowEntry in ObservationContext, filled on the app thread or once per refresh in AXWindowSystem). TabGroupTracker must exclude hidden-tab candidates whose Space differs from the shown tab's. With no Space data, it keeps today's behaviour plus the CG-history rule below"
      - "Pure single-Space fallback rule (REVIEW CR-01 fix 1): keep the previous refresh's CG ID set per pid. When a shown tab was not in the CG list before (a brand-new window: Cmd-T or New Tab), prefer a tracked standalone window that was listed last refresh over untracked candidates"
      - "Limit the damage of a wrong fold (REVIEW CR-01 fix 3). Only destroy a `folded` window once it has stayed a member across two refreshes in which it was not listed and the group's shown tab did not change. A listed tabCount>=2 window that matches an existing group only through line 91 rebinds only if the counts agree or that group's previous shown tab is no longer present offscreen"
      - "Add C2, C5 and C7 as TabScenarioTests driven through `showSpace`, both with Space data (the fake supplies Space IDs) and without it (fallback). Each test asserts the right tracked-window count, visibleMemberID and tabCount, no duplicate tracking, and no windowDestroyed for a window that is still alive. Keep S4/S5/S6, Cmd-T, merge and minimised-twin passing. Write the tests first and confirm they fail on the current code"
      - "Fake support: FakeWindowSystem models per-window Space membership and the Spaces capability being on or off"
  - truth: "A window is removed (windowDestroyed) only when two sources agree; a window alive on another Space is never reported destroyed (02-09 truth 2; WIN-09 core rule)"
    status: failed
    requirement: WIN-09
    reason: "Same root cause as the gap above. The folded path in WindowTracker.ingest (lines 63-66) emits windowDestroyed for a window that is alive and unchanged on another Space (probe3 C2: `DESTROYED 5`). Neither AX nor NSWorkspace said it was gone. Phase 3 would remove its tile from the user's layout"
    artifacts:
      - path: "Sources/PaneEngine/WindowTracker.swift"
        issue: "folded identities are destroyed without CloseRule"
    missing:
      - "This gap closes with the CR-01 fix above: the Space-aware candidate filter plus the two-refresh guard before a fold is destroyed. Add one assertion that a cross-Space twin is never destroyed while its CG entry exists"
  - truth: "When an app refuses a size, Pane learns its real minimum, including the common case of a window left clamped in a too-small tile and a window that is already at its minimum; a deterministic snap is never learned as a minimum (ROADMAP SC3; 02-12 truths 4 and 5; REVIEW WR-01, WR-02)"
    status: failed
    requirement: WIN-04
    reason: "Re-running the reviewer's learner harness (scratchpad/probe3, Probe3c) against HEAD gives: 'at-min static: learned nil' and 'one shrink then static: learned nil', so a window asked five times for a size it refuses never learns anything. WindowTracker.applyFrameResult (lines 211-215) skips every read-back that equals the pre-write frame, and that is exactly the read-back that confirms a clamp. 'snap req h 510 -> 518, 790 -> 790, 510 -> 518: learned (0, 518)', so a 16-pt row snap that rounds up is learned and then persisted per bundle by MinimumHintsStore (max only, no decay), which blocks splits below 518 pt for that app for good. A single refused write teaches nothing at all, which contradicts 02-12 truth 4 (a refusal of more than 2 pt learns max(old, actual)) and truth 5 (fixture minSize 250x150 asked for 100x80 learns 250x150). The live test was rewritten to a refuse, honour, refuse sequence to pass"
    artifacts:
      - path: "Sources/PaneEngine/WindowTracker.swift"
        issue: "lines 211-215: the `unchanged` pre-write-frame skip throws away the confirming read-back of a clamped window"
      - path: "Sources/PaneEngine/MinimumSizeLearner.swift"
        issue: "lines 34-41: confirmation needs two agreeing refusals but not two different requests, so a deterministic snap confirms itself. 'An honoured write at or above keeps it' lets an honoured write sit between the two snaps. The doc comments at lines 5-12 and 17 are stale"
      - path: "Sources/PaneMac/PaneMacApp.swift"
        issue: "IN-04: learned hints reach the tracker only at launch (setBundleHints once), and onLearnedMinimum does not push them back"
    missing:
      - "Project-lead decision: simplify the learner. Separate a stale read-back from a clamped one by TIME, not by the pre-write frame. Keep a refused read-back pending, and confirm it when a later AX refresh at least `settleDelay` after the write still reads the window at that size (e.g. `WindowTracker.ingest` calls `learner.confirmPending(identity, observed:, at:)`). Remove the pre-write `unchanged` skip"
      - "Treat a refusal as a minimum only when it holds against requests that differ by at least 2 * tolerance, with the read-back above both. Or cap any persisted hint at (smallest honoured size for that window - tolerance). Either way a round-up snap must not be learned"
      - "Rewrite the 02-12 truths 4 and 5 contract to the new rule (or record an override), so the plan text matches the code"
      - "Tests (write first, see them fail): a window that stays clamped through three identical writes and one later refresh learns; a window that opens already at its minimum learns after one refused write plus one refresh; the 16-pt snap grid (510->518, 790->790, 510->518) learns nothing; a lag-2 slow app learns nothing; the fixture minSize 250x150 asked once for 100x80 learns 250x150 in FrameWriteIntegrationTests"
      - "After the learner fix, push learned hints to the tracker within the session (IN-04: call system.setBundleHints(hints.hints) after hints.record)"
  - truth: "Call-time degradation switches `_AXUIElementGetWindow` off only after 5 consecutive failures across real windows, not because one unplaceable element fails repeatedly while cached windows record no successes (02-11 truth 4; SAFE-05; REVIEW WR-03)"
    status: failed
    requirement: SAFE-05
    reason: "AXSnapshotReader.windowID(of:) (line 81) returns a cached element's ID before the private lookup runs, so in steady state Capabilities.recordSuccess is never called. CapabilitySession.recordFailure (Capabilities.swift:95-114) resets only on recordSuccess. An AXWindow element whose lookup fails and that Fallback.identify cannot place is not cached: its frame is unreadable (line 111) or the CG list is nil (line 113). It therefore fails again on every refresh, and after 5 sweeps (about 25 s) the lookup is switched off process-wide for the rest of the session. 'In a row' no longer means anything. This was confirmed by reading the code. The WR-02 fix's own report records the side effect. No test covers it"
    artifacts:
      - path: "Sources/PaneMac/AX/AXSnapshotReader.swift"
        issue: "lines 81-92: cache-first return means no recordSuccess; failures are counted per lookup attempt, not per distinct element"
      - path: "Sources/PanePrivate/Capabilities.swift"
        issue: "lines 95-114: the consecutive-failure counter resets only on recordSuccess"
    missing:
      - "Count at most one failure per element: keep a per-app-thread negative cache of elements that already failed, matched with CFEqual. Or record one success per refresh whenever a cached `.axPrivate` element exists. Or switch off only when failures outnumber successes over a window of distinct elements"
      - "Add a CapabilitySession / reader-level test: one element fails 5+ times while other elements stay cached under `.axPrivate`, and the capability must stay on. Five distinct failing elements must still switch it off exactly once"
  - truth: "A window identified while the private lookup failed transiently is re-identified once the lookup works; no element keeps a synthetic or wrong frame-matched ID for life, and two elements never share one CGWindowID (02-11 truth 2 stickiness clause; WIN-02, SAFE-05; REVIEW WR-04)"
    status: failed
    requirement: SAFE-05
    reason: "The WR-02 fix makes the cache authoritative: an element keeps whatever ID it was first given for as long as it is cached, and its source is never re-checked. A synthetic ID then keeps only bounds-based presence for life, and Phase 4 can never map it to an SCWindow. Worse, a new window E whose lookup fails before E appears in the CG snapshot can frame-match a same-frame, offscreen, untracked twin (on another Space, or a hidden tab). E then carries the twin's real CGWindowID permanently. Once the twin is listed, two elements share one ID in byID, E takes on the twin's frame and title, and E's own window is later tracked a second time. This was confirmed by reading AXSnapshotReader.swift:79-81 and 115-123 and FallbackMatcher.swift:17-30. No test covers it"
    artifacts:
      - path: "Sources/PaneMac/AX/AXSnapshotReader.swift"
        issue: "lines 79-81: the cache-first check never re-checks `.synthetic` or `.cgFrameMatch` elements while the lookup is available; lines 115-123: a frame match accepted on the first pass may be an offscreen-only twin"
      - path: "Sources/PaneEngine/WindowTracker.swift"
        issue: "no re-key API exists to move a WindowInfo, its learner state and its tab membership to a corrected ID without emitting created/destroyed"
    missing:
      - "For cached elements whose source is not `.axPrivate`, keep calling the lookup while the capability is available. If it returns R and R differs from the cached ID, re-key explicitly with a new tracker API (e.g. `WindowTracker.rekey(from:to:)`) that moves WindowInfo, learner state, tab membership and close bookkeeping and emits no windowCreated or windowDestroyed"
      - "When the lookup is available but failed for a NEW element, do not accept an offscreen-only frame match on that pass. Wait one refresh, which the 250 ms settle hold already allows"
      - "Tests: a synthetic-ID element re-keys to its real ID when the lookup recovers (one window, no create/destroy); a wrong `.cgFrameMatch` to a cross-Space twin re-keys and the twin is tracked separately; no two cached elements ever share one ID"
      - "Note: the orchestrator brief grouped WR-03/WR-04 with WIN-04. In the code they belong to window identity (SAFE-05 fallback, WIN-02 tracking), not to move/resize"
deferred: []
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
  - test: "Menu-bar glyph in light, dark and tinted menu bars; header 'Tracking N windows in M apps'; Debug shows 'Window ID lookup: available'"
    expected: "Glyph legible in every appearance; plausible counts (backstop 02-02)"
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
    why_human: "Needs physical display arrangements (backstop 02-13; the live second-display test was skipped on the last run with 1 display)"
  - test: "Real native tabs: Finder, Terminal and Safari windows with three tabs each (Cmd-T); click between tabs; then repeat with a same-frame window of the same app on a second Space and switch Spaces (after the CR-01 gap closes)"
    expected: "One row per app reading '3 tabs'; tab clicks change Title but never add or remove rows; Space switches never add or remove rows; note which apps report AXTabGroup (Safari may not)"
    why_human: "Real apps' tab implementations differ (RESEARCH A1/A2) (backstop 02-10)"
  - test: "Frame writes on real apps via Nudge: a Chrome or Electron window (AXEnhancedUserInterface toggled and restored), Terminal or iTerm2, and an app with a real minimum size; then quit and relaunch Pane"
    expected: "Enhanced UI restored; terminal cell snapping not learned as a minimum; Min Size shows the real minimum; after relaunch the hint is back and `~/Library/Application Support/Pane/min-size-hints.json` holds only bundle IDs and sizes"
    why_human: "Real third-party app behaviour (re-run after the learner gap closes)"
  - test: "Exclusions in the real UI: Don't Arrange “TextEdit”, then Never Arrange submenu, then Nudge with TextEdit frontmost, then Nudge with System Settings frontmost"
    expected: "Checkmark; 'Excluded' badge; submenu lists and removes it; 'No apps excluded' when empty; 'Nudge Focused Window (app excluded)' and '(no window)' are shown disabled"
    why_human: "Menu rendering and interaction"
  - test: "Signed app with the private API forced off: `scripts/run-debug.sh --no-build --disable-private=AXWindowID`; open Tracked Windows and the Debug menu; open and close windows; check `log show --predicate 'subsystem == \"com.eightabyte.pane\" AND category == \"private\"' --last 5m` (also with `--disable-private=AXWindowID,Bogus`)"
    expected: "'Window ID lookup: off, matching by frame' in menu and footer; windows appear and disappear normally; ambiguous matches show 'by frame'; the log shows the capability report and an error line for 'Bogus'"
    why_human: "ROADMAP SC5 in the signed app launched through LaunchServices; unified-log output is not asserted by any test"
  - test: "Corpus review before pushing publicly (SECURITY T-02-08): read every JSON in Tests/PaneEngineTests/Fixtures/AXDumps (`git log -p -- Tests/PaneEngineTests/Fixtures/AXDumps`), especially libreoffice_start_center and android_studio_welcome; then set confirmedBy to 'developer'"
    expected: "No title, path, URL or account name; every label matches the window. All 11 cases currently read confirmedBy 'executor-proposed'"
    why_human: "Labels must come from a person (Pitfall 6); privacy review is a judgment call"
  - test: "Picture-in-picture capture (backstop 02-03): play a video in Safari or Chrome, enter PiP, `swift run pane-dump --app com.apple.Safari --list`, then capture with `--label neverDock --family native --case safari_pip`; run `swift test --filter ClassifierCorpusTests`"
    expected: "The PiP case is labelled neverDock and classifies neverDock"
    why_human: "Needs a playing video; there is no PiP case in the corpus yet"
  - test: "UI-REVIEW visual items: GroupBox callout inner padding (12 pt vs about 2x); Tracked Windows table background and alternating rows; long CFBundleName wraps at 480 pt in the setup window; the 'Looking for windows…' font; reset-failed state with duplicated 'Open System Settings' buttons and callouts B and E at once; menu header vs footer counts and missing loading state; table behaviour at 720 pt (horizontal scroll, pinned header, middle-truncated titles with tooltips)"
    expected: "Confirm or file each against 02-UI-REVIEW.md Top 3 fixes and needs_human_review items"
    why_human: "No screenshots were captured (native AppKit, no dev server); code-derived findings need a rendered check"
  - test: "Prohibition review (judgment tier, non-authoritative LLM verdicts below): confirm no TrellisWM material and no code copied from AeroSpace, Amethyst, yabai or Loop"
    expected: "Developer confirms clean-room status"
    why_human: "Provenance cannot be verified from the code"
---

# Phase 2: Window Control Verification Report

**Phase Goal:** As a Mac user, I want to grant Pane access and have it track and move every window, so that no slow app or lock screen can freeze or lose them.
**Mode:** mvp. The user-story format is valid. Outcome clause: *no slow app or lock screen can freeze or lose them*.
**Verified:** 2026-10-25T18:34:53Z
**Status:** gaps_found
**Re-verification:** No. This is the initial verification (no earlier 02-VERIFICATION.md existed).

## User Flow Coverage (MVP)

| Step | Expected | Evidence in codebase | Status |
|---|---|---|---|
| Grant access | Guided grant; stale grant detected and explained | PermissionReducer (prompt only on the first click of a cycle, `PermissionReducer.swift:82,88`), PermissionProbe, TCCReset with fixed argv `/usr/bin/tccutil`, SetupView/Controller; PermissionReducerTests green | VERIFIED (automated); real TCC needs a human |
| Track every window | Inventory of every standard window, live open and close | WindowTracker/AXWindowSystem/RefreshScheduler/AppRegistry; the classifier corpus passes | VERIFIED, except tab groups (gap 1) and fallback identity (gap 5) |
| Move every window | setFrame on any display; learn minimum; exclusions respected | FrameWriter size→pos→size, latest-wins slot, ExclusionFilter.admit in both `perform` paths | Move: VERIFIED. Learn minimum: FAILED (gap 3) |
| No slow app freezes it | Hung app isolated per thread; degraded probing | ResponsivenessTracker, per-app AXAppThread, 1 s system-wide messaging timeout (`AXWindowSystem.swift:80`), scenario tests green | VERIFIED (automated); a real `kill -STOP` needs a human |
| No lock screen loses them | Lock/sleep/timeout never close; two-source close | CloseRule table, SessionGate, lock-blanking scenario tests green | Lock/sleep/timeout: VERIFIED. The "never lose" outcome FAILED for cross-Space twins (gap 2: folded path destroys a live window) |

The outcome clause does not hold yet. A same-frame window of the same app on another Space can be reported destroyed while it is alive (gap 2), or tracked twice (gap 1). That is a lost window, which the phase goal says must never happen.

## Goal Achievement

### Roadmap Success Criteria (contract)

| # | Truth | Status | Evidence |
|---|---|---|---|
| SC1 | Guided Accessibility grant; stale grant detected and explained, no looping prompts | ✓ VERIFIED | Reducer transitions, the 14.9 s / 15 s form-B boundary and the 20-sequence no-repeat-prompt property are covered by PermissionReducerTests (green in my run). Real TCC flow is in human_verification |
| SC2 | Tracked list shows every standard window, updates live, counts a natively tabbed window as one, and excludes dialogs, sheets, popovers and PiP (corpus passes) | ✗ FAILED | Tracking and classification hold: the 11-case corpus covers Finder, Safari, Terminal, System Settings, Electron (VS Code), Java (Android Studio) and office (LibreOffice), with 7 dockable, 3 neverDock and 1 notAWindow case, and ClassifierCorpusTests is green. **Tabs fail:** probe3 C2/C5/C7 reproduced against HEAD (gap 1) |
| SC3 | Move/resize any window on any display; learn the real minimum on refusal; excluded apps never touched | ✗ FAILED | Move/resize and exclusions hold: `ExclusionFilter.admit` is at `AXWindowSystem.swift:155` and `FakeWindowSystem.swift:296`, and FrameScenarioTests and ExclusionScenarioTests are green. **Learning fails:** probe3c 'at-min static: learned nil', snap learned 518 (gap 3). Multi-display needs a human |
| SC4 | kill -STOP neither stalls Pane nor delays others; lock, sleep or AX timeout never marks a window closed | ✓ VERIFIED | `aHungAppDoesNotDelayAnotherAppsNewWindow`, `aHungAppNeverLosesAWindowOverFiveRefreshes`, `blankingWithoutTheGateAlsoClosesNothingBecauseEveryReadTimesOut` and the CloseRule `.timedOut → noChange` case are green. FreezeIntegrationTests passed in the orchestrator's live gate (I did not re-run it). A real app and a real lock/sleep need a human |
| SC5 | With `_AXUIElementGetWindow` forced unavailable, Pane launches and tracks through its fallback | ✓ VERIFIED | dlopen/dlsym only (`AXWindowID.swift:15-16`); no link-time private symbol anywhere; FallbackMatcherTests and CapabilitiesTests green; FallbackIntegrationTests passed in the orchestrator's live gate. Call-time degradation and identity stickiness have their own gaps (4, 5) |

### Plan must-have truths (116 across 13 plans)

All key links (38/38) and artifacts (57/57) pass `verify.key-links` and `verify.artifacts`. Truths per plan:

| Plan | Truths | Verified | Failed | Backstop (insufficient_spec → human) | Notes |
|---|---|---|---|---|---|
| 02-01 tracer | 11 | 11 | 0 | 0 | dlopen path, 1.0 s timeout at `AXWindowSystem.swift:80`, own pid and loginwindow skipped (`AppRegistry.swift:58`), FakeWindowSystem over the shared tracker. FixtureTrackingTests comes from the orchestrator's live gate |
| 02-02 shell/signing | 9 | 8 | 0 | 1 (glyph legibility) | project.yml: manual Developer ID, team S2K7P43927; no Sparkle |
| 02-03 classifier/corpus | 10 | 9 | 0 | 1 (PiP capture) | Corpus labels are `executor-proposed`, so the developer-label confirmation is in human_verification |
| 02-04 LifecycleSync | 5 | 5 | 0 | 0 | LifecycleSyncTests green |
| 02-05 permission | 12 | 11 | 0 | 1 (long CFBundleName wrap) | |
| 02-06 live tracking/displays | 9 | 9 | 0 | 0 | CoordinatesTests and TrackerDisplayTests green; LiveTrackingTests from the gate |
| 02-07 hung apps | 7 | 7 | 0 | 0 | ResponsivenessTracker and scenario tests green |
| 02-08 Tracked Windows/exclusions/freeze | 12 | 12 | 0 | 0 | UI-REVIEW warnings are cosmetic (see human_verification) |
| 02-09 two-source close/session gate | 9 | 8 | **1** | 0 | Truth 2 fails: the folded path destroys a live cross-Space twin (gap 2). Truth 6 (reused ID is a new window) holds through removal (`aReusedIDIsANewWindow`), but ClosedIDCache is dead state (IN-01) |
| 02-10 native tabs | 8 | 6 | **1** | 1 (real-app tabs) | Truth 1 fails (gap 1) |
| 02-11 ID fallback | 7 | 5 | **2** | 0 | Truth 2's "keeps its ID for life" clause is the WR-04 defect (gap 5); truth 4 fails, because the consecutive-failure count is meaningless without successes (gap 4) |
| 02-12 frame writes/learning | 8 | 6 | **2** | 0 | Truths 4 and 5 fail: one refusal teaches nothing, and a clamped window never learns (gap 3) |
| 02-13 exclusions/hints/nudge | 9 | 8 | 0 | 1 (multi-display) | |

**Score:** 108/121 truths verified (5 roadmap SCs + 116 plan truths). 8 failed (SC2, SC3, 02-09#2, 02-10#1, 02-11#2, 02-11#4, 02-12#4, 02-12#5). 5 are backstops routed to a human. 0 are present but behaviour-unverified.

### Prohibitions (judgment tier, mode-dependent soft gate)

All 23 prohibitions are judgment tier (no wired negative test). The verdicts below are **non-authoritative LLM-judge verdicts** and are flagged `unverified-prohibition: human review recommended`.

| Prohibition (plan) | LLM verdict | Evidence |
|---|---|---|
| No link-time private symbols (01) | holds | No `@_silgen_name`, C header or `-framework SkyLight`; dlopen/dlsym only |
| Titles never logged (01, 08) | holds | No logger call carries a title |
| No TrellisWM material or copied code (01) | cannot judge | Provenance needs a human (see human_verification) |
| No ad-hoc signing (02) | holds | `CODE_SIGN_IDENTITY: "Developer ID Application"`; no `codesign -s -` in scripts |
| No Sparkle (02) | holds | Not in Package.swift or project.yml |
| No TrellisWM text or icons in the menu (02) | holds (weak) | No 'trellis' string in Sources, xcode or scripts |
| Corpus has no personal data; labels never auto-filled (03) | holds | Leak test; titles redacted; pane-dump requires `--label`. Developer review pending |
| Lifecycle never through World.edit (04) | holds | LifecycleSync calls only apply/undo |
| No reset of foreign TCC entries; no looping prompt or reopen (05) | holds | Fixed argv with own bundle ID; prompt only on the first click |
| AX notification alone never closes (06) | holds | Hints only schedule refreshes |
| MainActor never blocks on one app (07) | holds | One in-flight job per pid; degraded apps are probed only |
| Freeze never stops critical processes or leaves an app stopped (08) | holds | Refuse list, Debug only, auto-resume, resume at launch (IN-09 PID-reuse risk noted) |
| No default exclusions (08) | holds | ExclusionStore has no defaults |
| **Never discard a tracked window on one source (09)** | **violated** | The folded path destroys on CG bounds alone (gap 2) |
| A tab switch never looks like close+open (10) | holds for a tab switch | Space-switch churn is covered by gap 1 |
| Private-API failure never stops launch (11) | holds | Optional pointers; session switch-off |
| CG names never logged or stored (11) | holds | Names read only for an ambiguous match, then dropped |
| Pane never arranges on its own in Phase 2 (12) | holds | The only `perform` caller is the Nudge item (`StatusItemController.swift:201`) |
| Never touch excluded apps' windows (13) | holds | ExclusionFilter first in both paths; WR-04 (iteration 1) excluded flag under the frame lock |
| Hints file stores only bundle IDs and sizes (13) | holds | MinimumHintsStore schema |

Status: complete with 23 flagged prohibitions, 1 judged violated (it is the same defect as gap 2).

### Key Link Verification

38/38 links verified by `verify.key-links`. Every plan's links pass, including `tracker.ingest`, `AXWindowID.function`, `Classifier.classify`, `CloseRule.decide`, `tabGroups.update`, `FallbackMatcher.match`, `recordFailure`, `enqueueFrame`, `FrameWriter.write`, `learner.learn`, `ExclusionFilter.admit`, `setExcludedBundleIDs`, `MinimumHintsStore` and `NudgePlanner`.

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| StatusItemController header | inventory counts | `await system.inventory()` ← WindowTracker ← AXAppThread observations | yes | ✓ FLOWING (IN-02: header and footer use different filters) |
| TrackedWindowsView rows | WindowInfo list | TrackedWindowsModel ← inventory + exclusions | yes | ✓ FLOWING |
| WindowInfo.learnedMinimum | learned size | MinimumSizeLearner ← applyFrameResult read-back | flows, but the learner rarely produces a value | ⚠️ semantics defect (gap 3) |
| Bundle hints | per-bundle minimums | MinimumHintsStore → setBundleHints at launch only | flows at launch only | ⚠️ IN-04 |
| Capability caption | AXWindowID state | CapabilitySession | yes | ✓ FLOWING (gap 4 affects when it flips) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Non-live suite green | `swift test --skip PaneMacIntegrationTests` (run once) | 142 + 74 + 166 = 382 tests passed, exit 0 | ✓ PASS |
| Engine and Model AppKit-free | `bash scripts/check-no-appkit.sh` | `no-appkit: OK (24 files)` | ✓ PASS |
| CR-01 still reproduces | `swift run Probe3` (scratchpad/probe3, real TabGroupTracker and WindowTracker at HEAD) | C2 `[(10,10,1),(40,40,2)]` … `DESTROYED 5` / `DESTROYED 50`; C5 visible member alternates 30/10; C7 phantom A | ✗ FAIL (gap 1, 2) |
| WR-01/WR-02 still reproduce | `swift run Probe3c` | 'at-min static: learned nil', 'one shrink then static: learned nil', snap → `learned (0, 518)` | ✗ FAIL (gap 3) |
| Live integration suite | not run (instructed) | Orchestrator gate: 22 passed, 1 skipped (needs 2 displays) | ? SKIP (gate evidence accepted, not re-run) |

### Probe Execution

No `scripts/*/tests/probe-*.sh` is declared or present. Step 7c: not applicable.

### Requirements Coverage

| Requirement | Source plans | Description | Status | Evidence |
|---|---|---|---|---|
| WIN-01 | 02, 05 | Guided grant; stale grant detected | ✓ SATISFIED (automated) | Reducer, probe, reset; human UAT pending |
| WIN-02 | 01, 02, 06, 08, 09 | Tracks every standard window | ⚠️ PARTIAL | Holds with the private lookup. Under fallback, gap 5 can merge or duplicate identities; gap 1 can track one window twice |
| WIN-03 | 07, 08, 12 | Hung app never freezes Pane | ✓ SATISFIED (automated) | ResponsivenessTracker and per-app threads; real kill -STOP needs a human |
| WIN-04 | 06, 12, 13 | Move/resize; learn minimum | ✗ BLOCKED | Gap 3 |
| WIN-05 | 03 | Dialogs, sheets, popovers, PiP never docked | ✓ SATISFIED | Corpus green; developer label review and PiP capture are human items |
| WIN-06 | 10 | Native tabs count as one window | ✗ BLOCKED | Gap 1 |
| WIN-08 | 08, 13 | Exclusion list | ✓ SATISFIED | ExclusionFilter in both perform paths; scenario and store tests green |
| WIN-09 | 04, 09 | Close only on two sources; lock, sleep, timeouts never close | ✗ BLOCKED | Lock, sleep and timeout hold, but the folded path closes a live window on one source (gap 2) |
| SAFE-05 | 01, 02, 11 | Broken private API disables only its feature | ⚠️ PARTIAL | Forced-off launch and fallback hold; call-time degradation miscounts (gap 4); fallback IDs stick (gap 5) |

All 9 phase requirement IDs appear in at least one plan's `requirements` field. REQUIREMENTS.md maps no other ID to Phase 2, so nothing is orphaned. **Traceability note:** REQUIREMENTS.md marks all nine `[x] Complete`. WIN-04, WIN-06, WIN-09 and SAFE-05 should not be considered complete until gaps 1-5 close.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (all phase files) | — | TBD/FIXME/XXX | none found | — |
| Sources/PaneEngine/TabGroupTracker.swift | 31-33 | `shortcut:` comment claims cross-Space twins self-correct | 🛑 Blocker (tied to gap 1) | The claim is false for twins with a tab bar (C5) and for Cmd-T (C2) |
| Sources/PaneEngine/WindowTracker.swift | 63-66 | Destroy without CloseRule | 🛑 Blocker (gap 2) | A live window is reported destroyed |
| Sources/PaneMac/AX/AXSnapshotReader.swift | 81 | Cache-first return skips recordSuccess | ⚠️ Warning (gap 4) | Session-wide switch-off |
| Sources/PaneEngine/CloseRule.swift | 60-85 | ClosedIDCache dead state, doc comments swapped (IN-01) | ℹ️ Info | — |
| Sources/PaneEngine/PermissionReducer.swift | 110 | `where` guards only the second pattern (IN-03, deferred-items) | ℹ️ Info | Release warning |
| Sources/PaneMac/AXWindowSystem.swift | 107-115 | Starting while locked marks the initial refresh complete (IN-06) | ℹ️ Info | Existing windows reported as new after unlock |
| Sources/PaneMac/Permission/PermissionController.swift | 55-73 | Accessibility revoke not detected (IN-08) | ℹ️ Info | Glyph still shows ready |
| Sources/PaneMac/AX/AXAppThread.swift | 128, 294-315 | Retry loop does not check isStopped; no cap; unsupported retried at app level (IN-11) | ℹ️ Info | Slow observes on a misbehaving app |
| Tests/PaneMacIntegrationTests/CloseIntegrationTests.swift | 58 | Rare unhide flake (deferred-items) | ℹ️ Info | 1 in ~37 runs |

IN-02, IN-05, IN-07, IN-09, IN-10 and IN-12 from 02-REVIEW.md are still open as Info. They are not blockers.

### Human Verification Required

17 items are listed in the `human_verification` frontmatter: the grant flows, lock/sleep, a real kill -STOP, the Freeze test, multi-display Nudge, real Finder/Terminal/Safari tabs, real-app frame writes, the exclusions UI, the menu glyph in light and dark, the signed app with `--disable-private=AXWindowID` and its unified log, the corpus label and privacy review before a public push (SECURITY T-02-08), the PiP capture, the UI-REVIEW visual items, and clean-room provenance. Run the tab and real-app frame-write items again after gaps 1 and 3 close.

### Gaps Summary

There are five gaps, from three root causes. Every one is a finding the code review left open after the loop cap, and I confirmed each one myself against HEAD: CR-01, WR-01 and WR-02 by re-running the reviewer's harness, WR-03 and WR-04 by reading the code.

1. **Tab group vs. same-frame twin on another Space (gaps 1 and 2, WIN-06 and WIN-09).** Without Space membership, S4 and C2 are the same input and need different answers. Per the project lead's decision, pull a **read-only SkyLight Spaces lookup** forward from Phase 6. It goes in its own PanePrivate file with dlopen/dlsym, registers as a new Capability that can be forced off, and falls back to a single Space. Add the pure CG-history rule for brand-new shown tabs, and add a two-refresh guard before a folded window is destroyed. Add C2, C5 and C7 scenario tests, both with and without Space data.
2. **Minimum-size learner semantics (gap 3, WIN-04).** Simplify the learner. Confirm a refusal by time (a later refresh at least settleDelay after the write still reads the clamped size) instead of skipping pre-write-size read-backs. Require refusals against requests that differ, so a deterministic snap is never learned. Align the 02-12 truth text, and push hints to the tracker within the session (IN-04).
3. **Window-ID cache and capability count (gaps 4 and 5, SAFE-05 and WIN-02).** Count failures per distinct element, or record a success for cached `.axPrivate` elements. Re-check the lookup for cached non-`.axPrivate` elements and re-key through a new `WindowTracker.rekey(from:to:)`. Don't accept an offscreen-only frame match on the first pass after a lookup failure.

**Deferral check (Step 9b):** Phase 6's scope note includes a "Read-only SkyLight `SpacesProvider` with a single-Space fallback". It could have absorbed part of gap 1, but the project lead has decided to pull it forward to close the gap in Phase 2, so nothing is deferred. Phase 6 can reuse the shim.

---

_Verified: 2026-10-25T18:34:53Z_
_Verifier: Claude (gsd-verifier)_
