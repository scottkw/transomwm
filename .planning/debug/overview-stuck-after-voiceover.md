---
status: awaiting_human_verify
trigger: "Phase 6 host check 4: after a VoiceOver session the overview never appears again (hotkey or menu) until Transom is relaunched"
created: 2026-11-01
updated: 2026-11-01
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
hypothesis: CONFIRMED (host log + guest probes): after the 15:28:36 screen lock, macOS 27.2 left Transom's .canJoinAllSpaces panels pinned to the Space current during the lock (Space 4); OverviewController.panel(for:) reuses its panel for the life of the process, so on Space 5 every open ordered the same stranded window in on Space 4.
next_action: HOST RE-CHECK PENDING (user): lock the screen, unlock, switch to another desktop, open the overview (3 steps under Resolution.host_recheck). Fix committed 98f7d3d, Debug app rebuilt 2026-11-01 16:46.

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
  same_root_cause_not_fixed_here: "The zoom stage (ZoomController.stage(for:)), PreviewPanel (drag preview), GapHandlePanels, CollapsedPanels and Toast were also off the active Space on the host after the lock and are reused the same way. After a lock on another desktop, camera moves may show no stage, drag previews and gap handles may be missing, and notices may not show. Each needs the same isOnActiveSpace check in its own lifecycle (follow-up)."
