---
status: resolved
trigger: "Phase 6 host check 4: after a VoiceOver session the overview never appears again (hotkey or menu) until Transom is relaunched"
created: 2026-11-01
updated: 2026-11-01 (follow-up: other reused panels)
---

## Symptoms

- **Expected:** ⌃⌥⌘A or menu Show Overview opens the overview (it did, on the same build, minutes earlier: check 3, 326 ms).
- **Actual:** after the steps below, nothing appears on screen from either trigger, even with VoiceOver off. Quit + relaunch fixes it.
- **Errors:** none. Log (subsystem com.eightabyte.transom, category overview) keeps reporting normal opens and closes:
  `open hotkey: 1 displays, 1 tiles, 1 snapshots, 0 fallback, 352 ms` then `dismiss: toggle` on the next press;
  later `dismiss: toggle` (first press, so isOpen was still true) then `open hotkey: … 382 ms`.
  While isOpen was true, CGWindowListCopyWindowInfo showed Transom's three 1710x1112 layer-3 (NSWindow.Level.floating)
  windows with kCGWindowIsOnscreen absent (none on screen); one 96x21 layer-103 window at the menu bar.
- **Timeline:** worked through host checks 1–3 (Space switch from the strip, timing). Broke during check 4.
- **Repro (host, macOS 27.2, MacBook Air, one display, Debug build):**
  1. ⌘F5 VoiceOver on.
  2. ⌃⌥⌘A (VoiceOver consumes it: VO keys are ⌃⌥).
  3. Menu bar icon → Show Overview: nothing visible.
  4. → twice, Esc, ⌘F5 VoiceOver off.
  5. From now on ⌃⌥⌘A / Show Overview show nothing although the log says opened.
  Menu items dispatch via the same closure as hotkeys with source .hotkey (TransomMacApp.swift:71), so log lines say "open hotkey" for both.

## Relevant code

- Sources/TransomMac/Overview/OverviewController.swift (open/show/dismiss/close, takeKeys, postAnnouncement)
- Sources/TransomMac/Zoom/StagePanel.swift (show(tiles:) + animate orderFrontRegardless, takesKeys/canBecomeKey, freezeAtPresentation, fade-out order-out, collectionBehavior [.canJoinAllSpaces, .stationary, .ignoresCycle], level .floating, setAccessibilityElement(false))
- Sources/TransomMac/Zoom/ZoomController.swift

## Hypotheses to test

1. A close/fade-out completion orders the panel out after a reopen already ordered it in (stale completion; generation not checked), leaving the overview "open" but off screen; later toggles keep alternating on an invisible panel.
2. The key-panel handoff (takesKeys/makeKey) while VoiceOver's cursor sits on the panel leaves AppKit window state (e.g. ordered out by VoiceOver focus change / occlusion) that orderFrontRegardless no longer clears.
3. alphaValue stuck at 0 is ruled out-ish: CG reports alpha 1 but not on screen.

## Constraints

- Reproduce only in the Tart VM `pane-test` (scripts/vm-live-test.sh, ssh admin@<vm> with ~/.ssh/pane_vm_ed25519, lock .build/transom-vm.lock, one VM job at a time). VoiceOver can be toggled in the guest. Never run live tests, event taps, key posting, overlay panels, VoiceOver or window-opening code on the host.
- A VM test run passes only if output has "Test run with N tests … passed".
- Never touch the user's real layout.json or defaults; never set TRANSOM_LIVE=1 on host; never stage .planning/config.json, .planning/state.json, milestone.lock; never kill node.
- Guest: never quit apps you didn't launch, leave guest on Desktop 1, restore anything changed (VoiceOver off at the end).
- Builds sequential. Commit trailers: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01HXttRxYZhy1TD5LBCzjqSJ`.
- Fix the root cause with a unit or VM test proving it; rebuild the Debug app (xcode build) at the end for a host re-check.
- RULE 0: stop on unknown/catastrophic failure.

## Current Focus

bug_class: Bohrbug (deterministic once the panel is stranded), trigger = macOS 27 screen lock, not VoiceOver
hypothesis: CONFIRMED for the overview (host re-check pass 2026-11-01) and, in the VM, for the zoom stage and toast panel (follow-up, commit db281d4).
next_action: HOST RE-CHECK PENDING for the follow-up (user): steps under Resolution.followup_host_recheck. Debug app rebuilt with db281d4, not launched.

reasoning_checkpoint:
  hypothesis: "The overview panel is invisible because it is no longer on every Space (isOnActiveSpace false after the macOS 27 lock transition) and panel(for:) keeps reusing it; orderFrontRegardless orders it in on the Space it was stranded on."
  confirming_evidence:
    - "Host AppKit 'defer invalidatation' lists both StagePanels, PreviewPanel, HandlePanel, Toast at 15:30-15:33 but not at 15:10; guest deferprobe shows that list == windows with isOnActiveSpace false, and a sticky ordered-out panel is not in it"
    - "Host Space timeline: lock on Space 4 at 15:28:36, Space 5 from 15:28:56; every invisible open was on Space 5; the same overview worked on Space 5 at 15:06-15:10"
    - "Host CG check while open: overview panel kCGWindowIsOnscreen absent, alpha 1 (on another Space); same StagePanel instances before and after the lock; relaunch (new windows) fixed it"
    - "Guest pinprobe: a panel left ordered in on Space 1 without all-Spaces membership reports isOnActiveSpace false and stays off screen after orderFrontRegardless on Space 2"
  falsification_test: "On the host after the fix: lock on one Space, unlock, switch Space, open the overview. Still invisible => wrong (or fresh windows are also stranded); the 'off the active Space' notice must be in the log."
  fix_rationale: "panel(for:) only reuses a panel that is still on the active Space; otherwise it orders it out and makes a new one, which is what a relaunch did. isOnActiveSpace is the exact signal AppKit reported false on the host."
  blind_spots: "Cannot reproduce the macOS 27 unpinning on the macOS 15 guest; the test simulates it by pinning the panel. Not proven that a panel made during the minutes right after an unlock is sticky (the relaunch came at 15:59). Zoom stage, PreviewPanel, gap HandlePanels, CollapsedPanels and Toast have the same exposure and are not changed here."
  candidate_causes:
    - "environment: macOS 27 lock/unlock transition (WindowManager ScaleScreenLockTransitionModifier) drops all-Spaces membership of existing windows"
    - "code: OverviewController reuses one StagePanel per display for the process lifetime and only rebuilds on a display change"
    - "code (eliminated): stale fadeOut completion ordering the panel out (guarded; completions fire on time offscreen in the guest)"
    - "environment (eliminated): app hidden by VoiceOver / Hide Others (accessory app cannot be hidden)"
  and_gate: "yes: needs (1) the OS stranding the panel on a Space at a lock AND (2) Transom reusing that panel AND (3) the user opening the overview on another Space. Removing (2) is the part Transom owns."

## Evidence

- timestamp: 2026-11-01
  checked: OverviewController.show / dismiss / close, StagePanel.show / fadeOut / freezeAtPresentation (code read)
  found: every open calls panel.show(tiles:) -> alphaValue = 1 + orderFrontRegardless, then takeKeys -> makeKey. The only orderOut of an overview panel is StagePanel.fadeOut's completion (guarded by the panel's generation, bumped by freezeAtPresentation when show() finds the panel still visible) and displaysChanged(). A dismiss's retarget completion is guarded by the controller generation.
  implication: H-1 (stale completion) can at most hide one open whose close was < 0.37 s earlier; it cannot explain invisibility that persists across several open/close cycles seconds apart. Something sticky outside the per-open path is needed: app hidden, or a panel stuck in some window-server state.
- timestamp: 2026-11-01
  checked: 06-UAT.md B5 (VM, VoiceOver on) and Known gaps
  found: in the VM run VoiceOver on + overview worked (announcements fired, no stuck panel), but that run opened via the hotkey only, never via the status menu while VO consumed the hotkey. Separately, OverviewIntegrationTests twice failed "Esc did not close the overview" in the VM, cause unknown.
  implication: the trigger is specific to the host sequence (VO consumes ⌃⌥⌘A, then menu Show Overview, arrows, Esc, VO off); the Esc flake may be the same "panel never became key" family.
- timestamp: 2026-11-01
  checked: VM repro (pane-test, macOS 15.7.7, installed /Applications/Transom Debug.app = review-fix build), driver ~/vo1101/vodrive (scratchpad vodrive/main.swift). Steps: ⌘F5 VO on (Quickstart "Use VoiceOver"), ⌃⌥⌘A, menu Show Overview (AXPress and HID click), → → Esc, ⌘F5 off, ⌃⌥⌘A. Both with TRANSOM_STAGE_CAPTURABLE=1 and without (sharingType .none, as on the host).
  found: never stuck. Every open showed the panel on screen (CG onscreen=1, screenshot s2.png shows the overview under the VO caption panel), Esc logged "dismiss: esc" with VO on, and opens after VO off worked. The posted ⌃⌥⌘A was NOT consumed by VO in the guest (it opened the overview).
  implication: not reproducible with synthetic input on macOS 15. Either 27.2-specific or depends on a step the VM did not mimic.
- timestamp: 2026-11-01
  checked: scratchpad overview-stream.log / overview-stream2.log (host log stream captured earlier in this session)
  found: 15:34:32 press at the menu bar (x≈560), 15:34:34.3 press at 591,454 (the Show Overview row of the status menu), 15:34:35.110 "open hotkey: 1 tiles, 1 snapshots, 352 ms", 15:34:36.728 "dismiss: toggle". Then no overview line until 15:36:15 (the later presses at x 1115-1317, y≈893-902 are clicks in Warp's window). Second stream: 15:58:03.974 dismiss: toggle, 15:58:10.725 open 382 ms, 15:59:07.896 "interrupted: menu" (isOpen still true), quit 15:59:10.
  implication: the open log line is written in the open animation's CATransaction completion, i.e. show() ran (panel.show -> orderFrontRegardless) for the invisible opens. The first VO-era open (step 3) was already invisible, so the state broke at or before step 3, not at step 4.
- timestamp: 2026-11-01
  checked: CG window count on the host report vs code
  found: the three 1710x1112 layer-3 windows are the overview panel, the zoom stage (ZoomController.stage) and the drag PreviewPanel overlay; all three are expected. No orphaned panel.
  implication: no leaked second overview panel.
- timestamp: 2026-11-01
  checked: H-A in the guest: NSRunningApplication.hide() and System Events "visible false" on Transom Debug
  found: hide() returns false and isHidden stays false; the overview keeps opening on screen.
  implication: an LSUIElement accessory app cannot be hidden from outside (Hide Others, option-click, VO). Transom never calls NSApp.hide itself. H-A is very unlikely.
- timestamp: 2026-11-01
  checked: host persisted unified log (read-only `/usr/bin/log show`, pid 55333 = the stuck Transom Debug, plus VoiceOver and loginwindow)
  found: (1) VoiceOver sessions: 15:10:11-15:12 (overview opened at 15:10:15 and 15:10:43 with VO on, captures normal), 15:30:09-15:30:58, 15:33:22-15:33:27. VO was OFF at 15:34:35 (the logged invisible open). (2) loginwindow: screensaver idle lock at 15:28:36, unlocked 15:28:46; Transom logged "session paused: locked or asleep" 15:28:36 / "session resumed" 15:28:48. (3) SCWindow lines from every overview capture: before the lock every captured window isOnScreen=1 (15:06-15:23); from 15:28:57 to 15:37:21 every captured window, including Warp 94 that the user was typing in, isOnScreen=0; 15:57:11 and 15:58:10 isOnScreen=1 again. (4) AppKit "defer invalidatation" (windows AppKit treats as ordered in but not visible) at 15:10:09 lists only ToastPanel; at 15:30:08, 15:30:55, 15:33:22, 15:33:24 it lists PreviewPanelWindow, BOTH StagePanels (0x772dea4000, 0x772dea7800), HandlePanel and ToastPanel, i.e. every Transom panel, while the overview was closed. Same two StagePanel instances throughout (no rebuild).
  implication: the break follows the 15:28:36 screensaver lock, not VoiceOver (VO + overview worked at 15:10; the 15:34:35 invisible open had VO off). After the unlock, every Transom panel, including the gap HandlePanel that is normally on screen, was ordered in per AppKit but not visible per the WindowServer, and stayed so on the same panel instances until the relaunch. The drag tap's "CG 0 / first CG nil" in the 15:34 stream fits an empty on-screen CG list in that period.
- timestamp: 2026-11-01
  checked: host WindowManager log (hotEdgeSpaceSwitch "Dock confirmed switch animation complete")
  found: Space 4 current from 15:13:18 (the 3-window overviews 15:19-15:23 worked there), screensaver lock 15:28:36 on Space 4, switch to Space 5 (Warp's Space) at 15:28:56, then 3 and back to 5 at 15:37 and 15:38. Every invisible open (15:30:20, 15:33:11, 15:34:35, 15:57:11-15:58) was on Space 5. The overview had worked on Space 5 at 15:06-15:10 (checks 1-3). WindowManager ran its macOS 27 ScaleScreenLockTransitionModifier (lock/unlock window transition) at 15:28:46-47.
  implication: the panels broke across the lock, and the user then worked on a different Space than the one current during the lock.
- timestamp: 2026-11-01
  checked: guest probe deferprobe (scratchpad deferprobe/main.swift): four panels (sticky ordered out, never shown, non-sticky left on Space 1, sticky shown), switch to Space 2, appearance toggle
  found: AppKit's "defer invalidatation" list is exactly the windows with isOnActiveSpace == false (NeverShown, PinnedOther). A sticky panel ordered out still reports isOnActiveSpace = true and is not listed.
  implication: on the host at 15:30-15:33 both StagePanels (overview + zoom stage), PreviewPanel, HandlePanel and Toast had isOnActiveSpace == false: they were no longer on all Spaces but pinned to another Space (Space 4), although their collectionBehavior still had .canJoinAllSpaces. At 15:10 the StagePanels were sticky (not listed). orderFrontRegardless on such a window orders it in on its old Space: kCGWindowIsOnscreen absent, nothing visible, Esc/arrows never reach it. A relaunch makes new, sticky windows. isOnActiveSpace is a host-proven detection signal.
- timestamp: 2026-11-01
  checked: guest repro of the trigger: screensaver with screen lock (sysadminctl -screenLock immediate), unlock by typed password, overview on Space 1, then lock on Space 1 -> unlock -> Space 2 -> overview; plain screensaver without lock
  found: overview on screen every time on macOS 15.7.7 (screen lock restored to off afterwards).
  implication: the unpinning is macOS 27 specific (its lock transition); macOS 15 cannot reproduce the OS half. The Transom half (reusing a panel that is not on the active Space) can be reproduced by pinning the panel to one Space and switching.

- timestamp: 2026-11-01 (follow-up)
  checked: every other reused .canJoinAllSpaces panel (code read): ZoomController.stage(for:) keeps one StagePanel per display for the process (rebuilt only on displaysChanged/purge); PreviewPresenter keeps one PreviewPanelWindow per display (rebuilt only on didChangeScreenParameters); GapHandlePanels and CollapsedPanels recycle panels through shown/pool; ToastPresenter has one `let` panel for life. All order in with orderFrontRegardless and never check the Space. The engine hides gap handles on a Space change, so the next show pops stranded pool panels; collapsed blocks are only re-sent when they change, so hide(on:)/fadeIn(on:) cycle the same stranded panels.
  found: run() and show() in ZoomController both call stage(for:), so a new stage is looked up again before it is ever ordered in; the deferprobe showed a never-ordered-in panel also reports isOnActiveSpace false, so a plain `!isOnActiveSpace` guard would replace every new stage once (and the toast panel, made at launch, at its first show) and log a false notice.
  implication: the guard must only replace a panel that was ordered in before: windowNumber > 0 (a deferred panel has no window device until first ordered in) and !isOnActiveSpace. Five sites need the same predicate + notice, so one helper (NSWindow.leftOnAnotherSpace) is justified; replacement stays per site.
- timestamp: 2026-11-01 (follow-up)
  checked: RED run, new VM tests aZoomStageStrandedOnAnotherSpaceDoesNotHideTheNextMove and aToastPanelStrandedOnAnotherSpaceDoesNotHideTheNextToast (strand the panel on desktop 1 as 98f7d3d's test does, show on desktop 2), code without the guard (.build/stranded-others-red.log)
  found: "✘ ... recorded an issue at OverviewSpaceSwitchIntegrationTests.swift:256:9: Expectation failed: next.onScreen" and ":280:9: Expectation failed: ... isOnScreen(panel)"; "✘ Test run with 2 tests in 1 suite failed after 7.171 seconds with 2 issues." The new-stage-kept and toast-first-show-kept checks passed.
  implication: both panels reproduce the overview's failure (reused while on another Space = off screen).
- timestamp: 2026-11-01 (follow-up)
  checked: GREEN run of the same two tests with the guard at every site (.build/stranded-others-green.log)
  found: "✔ Test run with 2 tests in 1 suite passed after 5.411 seconds."
  implication: a stranded zoom stage / toast panel is replaced and the new one is on screen on desktop 2; a panel on the shown Space is kept.
- timestamp: 2026-11-01 (follow-up)
  checked: mutant without the windowNumber gate (`guard !isOnActiveSpace`) (.build/stranded-others-mutant-nogate.log)
  found: "Expectation failed: started === stage" (moves 1 and 2: the stage made by run() was replaced by show()) and "Expectation failed: toast.panel === fresh" (first toast replaced its never-shown panel); then the test helper trapped on CGWindowID(-1) for that replaced, never-ordered-in panel ("Negative value is not representable").
  implication: confirms on the guest that a deferred panel never ordered in reports isOnActiveSpace false AND has a negative windowNumber, so the gate is needed and correct. isOnScreen now returns false for windowNumber <= 0 so such a regression fails instead of crashing.
- timestamp: 2026-11-01 (follow-up)
  checked: neighbour suites, one per vm-live-test run, with the final code
  found: OverviewSpaceSwitchIntegrationTests "✔ Test run with 6 tests in 1 suite passed after 22.672 seconds."; ZoomSettleIntegrationTests "✔ Test run with 2 tests in 1 suite passed after 26.230 seconds."; ArrangeIntegrationTests "✔ Test run with 6 tests in 1 suite passed after 16.865 seconds." (fullscreen test skipped, opt-in); GestureFollowIntegrationTests "✔ Test run with 13 tests in 1 suite passed after 61.344 seconds."; OverviewIntegrationTests "✔ Test run with 3 tests in 1 suite passed after 10.730 seconds." Host: swift build OK, scripts/check-no-appkit.sh OK (53 files), scripts/build-debug.sh exit 0 (codesign valid, DR satisfied).
  implication: no regression in camera moves, gestures (beginFollow uses stage(for:)), docking/gap handles, collapsed blocks or the overview.

## Eliminated

- hypothesis: H-A Transom gets hidden (NSApp hidden) by VoiceOver / Hide Others
  evidence: an accessory app refuses NSRunningApplication.hide() (returns false, isHidden stays false, overview still shows) in the guest; no Transom code hides itself
  timestamp: 2026-11-01
- hypothesis: a leaked or duplicate overview panel is the one being ordered front
  evidence: the three 1710x1112 layer-3 windows on the host are overview panel + zoom stage + PreviewPanel overlay
  timestamp: 2026-11-01

## Resolution

root_cause: "After a screen lock (screensaver idle lock 15:28:36), macOS 27.2 left Transom's existing .canJoinAllSpaces panels pinned to the Space shown during the lock (Space 4): AppKit reported isOnActiveSpace false for both StagePanels, PreviewPanel, HandlePanel and Toast afterwards. OverviewController.panel(for:) reused its one panel per display for the life of the process (rebuilding only on a display change), so on Space 5 every open ordered that window in on Space 4: off screen (kCGWindowIsOnscreen absent, alpha 1), never key, so Esc and arrows did nothing, until a relaunch made new windows. VoiceOver was a coincidence (on 15:30:09-15:30:58; the logged invisible open at 15:34:35 had it off; VO + overview worked at 15:10)."
fix: "OverviewController.panel(for:) reuses a panel only while panel.isOnActiveSpace; otherwise it logs the notice 'display <uuid>: overview panel was off the shown Space; made a new one', orders the old panel out and makes a new StagePanel (what the relaunch did). panels became private(set) for the test."
files_changed:
  - Sources/TransomMac/Overview/OverviewController.swift
  - Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift
commit: 98f7d3d
oracle_type: "specified (window server on-screen state of the panel the open used: kCGWindowIsOnscreen true on the shown desktop), plus boundary neighbours: the replaced panel is no longer ordered in on the old desktop; a panel already on the shown Space is kept (no new window per open)"
verification:
  target_test: { result: pass, test: "OverviewSpaceSwitchIntegrationTests/aPanelStrandedOnAnotherSpaceDoesNotHideTheNextOpen", log: .build/overview-stranded-green.log, line: "✔ Test run with 1 test in 1 suite passed after 4.048 seconds." }
  mutation_check: { result: pass, reason_if_skipped: "no Stryker for Swift; two manual mutants instead", mutant_killed: "no check at all (the pre-fix code): 'the overview is not on screen on the second desktop' (.build/overview-stranded-red.log); always replace (if false, ...): 'a panel on the shown Space was replaced' (.build/overview-stranded-mutant.log)" }
  no_op_deletion: { result: pass, deletion_justified_by_rca: n/a (adds a guard, deletes nothing) }
  adjacent_tests: { result: pass, suites_run: ["OverviewSpaceSwitchIntegrationTests (3 passed)", "OverviewIntegrationTests (3 passed)", "OverviewKeyboardIntegrationTests (1 passed)"], note: "one suite per vm-live-test run; a combined 'Overview' filter ran 4 suites in parallel and they interfered (Space switches, posted keys) - not a regression, discarded", other: "scripts/check-no-appkit.sh OK (53 files); swift format lint not applicable (no .swift-format config, default rules flag every pre-existing line)" }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, note: "RED run before the fix, GREEN after (same test)" }
  guardrail_verdict: accepted
  debug_app: "scripts/build-debug.sh exit 0 at 16:46, codesign valid, satisfies designated requirement; the new dylib contains the notice string. Built only, not launched."
host_recheck:
  status: pending (the macOS 27 half cannot be reproduced on the macOS 15 guest)
  steps:
    - "Quit the running Transom Debug (menu bar icon > Quit Transom), then open the rebuilt /Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app; zoom on; press ⌃⌥⌘A once to check the overview shows, then close it."
    - "Lock the screen (⌃⌘Q), wait about 10 s, unlock, then switch to a different desktop than the one you locked on (⌃→ or a swipe)."
    - "Press ⌃⌥⌘A (and try menu > Show Overview): expected the overview shows and Esc closes it. Then run: /usr/bin/log show --last 10m --predicate 'subsystem == \"com.eightabyte.transom\" AND category == \"overview\"' | grep 'off the shown Space'  - a line there means the lock stranded the panel and the fix replaced it; no line means this lock did not strand it (try again on another desktop)."
  status_note: "user re-check pass 2026-11-01 (orchestrator)"
followup:
  scope: "The zoom stage (ZoomController.stage(for:)), PreviewPanel (drag preview / marquee), gap HandlePanels, CollapsedPanels and the Toast panel, which the host also listed off the active Space after the lock and which are reused the same way."
  fix: "NSWindow.leftOnAnotherSpace(_:) in Displays.swift: true, with the notice '<name> was off the shown Space; made a new one' (subsystem com.eightabyte.transom, category spaces), for a panel ordered in before (windowNumber > 0) that is not isOnActiveSpace. Sites: ZoomController.stage(for:) orders the old stage out and makes a new one (as 98f7d3d); ToastPresenter builds its panel in makePanel() and replaces it in show(); PreviewPresenter's show/flashBlocked/showBand/showPickRing look the overlay up through overlay(_:), which calls rebuildPanels() when stranded; GapHandlePanels.show replaces a reused (old or pooled) panel; CollapsedPanels.show and fadeIn replace one keeping block, double-click handler and frame. OverviewController.panel(for:) left as committed in 98f7d3d (host-verified; it always shows a panel it makes)."
  why_windownumber_gate: "a deferred panel never ordered in also reports isOnActiveSpace false (deferprobe; mutant run), and ZoomController.run then show both call stage(for:) before the new stage is ever ordered in; the toast panel exists from launch and is first ordered in at the first notice."
  commit: db281d4
  files_changed:
    - Sources/TransomMac/Displays.swift
    - Sources/TransomMac/Zoom/ZoomController.swift
    - Sources/TransomMac/Overlay/Toast.swift
    - Sources/TransomMac/Overlay/PreviewPanel.swift
    - Sources/TransomMac/Overlay/GapHandlePanels.swift
    - Sources/TransomMac/Zoom/CollapsedPanels.swift
    - Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift
  oracle_type: "specified (kCGWindowIsOnscreen of the panel the move/toast used, on the shown desktop), plus boundary neighbours: the replaced panel is no longer ordered in; a panel on the shown Space is kept; a new panel never ordered in is kept (stage made by run() is the one show() uses; the toast's first show keeps its panel)"
  verification:
    target_tests: { result: pass, tests: ["aZoomStageStrandedOnAnotherSpaceDoesNotHideTheNextMove", "aToastPanelStrandedOnAnotherSpaceDoesNotHideTheNextToast"], red: ".build/stranded-others-red.log: ✘ Test run with 2 tests in 1 suite failed after 7.171 seconds with 2 issues (next.onScreen; isOnScreen(panel))", green: ".build/stranded-others-green.log: ✔ Test run with 2 tests in 1 suite passed after 5.411 seconds." }
    mutation_check: { result: pass, mutant_killed: "no windowNumber gate: started === stage and toast.panel === fresh failed (.build/stranded-others-mutant-nogate.log); no guard at all = the RED run" }
    adjacent_tests: { result: pass, suites_run: ["OverviewSpaceSwitchIntegrationTests (6 passed)", "ZoomSettleIntegrationTests (2 passed)", "ArrangeIntegrationTests (5 passed, 1 opt-in skipped)", "GestureFollowIntegrationTests (13 passed)", "OverviewIntegrationTests (3 passed)"] }
    host: "swift build OK; scripts/check-no-appkit.sh OK (53 files); scripts/build-debug.sh exit 0, codesign valid, DR satisfied; built only, not launched"
    not_covered: "no dedicated test for the PreviewPanel, gap handle or collapsed panel replacement (they share the tested predicate; their replacement code is exercised only on a stranded panel); the macOS 27 lock itself cannot be reproduced on the macOS 15 guest"
  followup_host_recheck:
    - "Quit the running Transom Debug, open the rebuilt xcode/.xcode-build/Build/Products/Debug/Transom Debug.app; zoom on; with two docked windows step in and out once (⌃⌥⌘. and ⌃⌥⌘,) and drag a window once, so the stage, preview and gap handles have been shown."
    - "Lock the screen (⌃⌘Q), wait about 10 s, unlock, switch to a different desktop with docked windows."
    - "Step in/out with ⌃⌥⌘. / ⌃⌥⌘, (the stage animation should show), drag a window (the drop preview should show), hover a gap (the handle should highlight). Then: /usr/bin/log show --last 10m --predicate 'subsystem == \"com.eightabyte.transom\"' | grep 'off the shown Space' lists which panels the lock stranded and were replaced."
