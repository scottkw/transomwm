---
status: resolved
trigger: "SIGTERM (`pkill -TERM`) leaves Transom alive for over five minutes with AppDelegate.handleSIGTERM in a nested run loop on the main thread; ⌘Q and menu Quit restore windows and exit cleanly."
created: 2026-11-04
updated: 2026-11-04
---

## Current Focus

hypothesis: "CONFIRMED. The hang needs two conditions at once: the SIGTERM source calls -terminate: from inside a main-queue drain, and applicationShouldTerminate leaves its restore, clean-exit write and reply to a later main-queue block. AppKit's terminateLater wait does not service the main queue while it is itself inside a main-queue block, so that block never runs."
test: done. Unit test and OutsideQuitIntegrationTests green on both guests; every quit route observed on both.
expecting: met.
next_action: none. Session archived.
bug_class: bohrbug (reproduced on every attempt, both guests)
reasoning_checkpoint:
  hypothesis: "NSApp.terminate(nil) called from the SIGTERM source runs AppKit's terminateLater wait inside _dispatch_main_queue_drain, so the block applicationShouldTerminate queued on the main queue is never run and the reply never arrives."
  confirming_evidence:
    - "Guest sample on 27.2 and 15.7.7: all samples in __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__ > handleSIGTERM closure > -[NSApplication terminate:] > _shouldTerminate > mach_msg."
    - "AppKit-only program on both guests: the same nextEvent(inMode: .modalPanel) wait runs a main-queue block from a run-loop block and does not from inside a main-queue block."
    - "On both guests the unfixed build quits cleanly by Apple Event, menu Quit, ⌘Q and logout, none of which call -terminate: from the main queue."
  falsification_test: "After the fix a real SIGTERM still leaves the app alive or with cleanExit false; or terminate from inside the drain with .terminateNow deadlocks or skips the willTerminate observer (checked: it does not on 15.7.7, repeat on 27.2)."
  fix_rationale: "Takes away the wait for every caller of -terminate:, not only the signal handler. The restore is already bounded and synchronous (2 s, DispatchGroup.wait on main), so terminateLater buys nothing: the queued block held the main thread for the same time. This is what Pattern 11 and Pitfall 14 asked for, not to rely on main-queue servicing during the quit. A hop in the signal handler would leave a later Task or main.async caller open to the same hang."
  blind_spots: "SIGTERM while the status menu is open or while a window is mid-drag. A quit started during restore. launchd's grace period on a command-line restart with a hung app: the 2 s limit applies, the grace period is not measured."
  candidate_causes:
    - "code: terminate called inside the main-queue drain + reply queued on the main queue (CONFIRMED, both needed)"
    - "code: modal-panel mode does not service the main queue (eliminated)"
    - "environment: macOS 27-only AppKit or CF behaviour (eliminated)"
    - "config: sudden termination or Info.plist keys (eliminated)"
    - "data: layout.json contents block the quit (eliminated)"
  and_gate: "yes: called from the main queue AND reply queued on the main queue. Either alone is harmless: Apple Event, menu and ⌘Q have the second only, and the terminateNow check has the first only. The fix removes the second, since that one is in the code every quit shares."

## Symptoms

expected: `pkill -TERM` on Transom restores windows, writes a clean exit to layout.json and exits promptly, bounded by the quit-restore timeout. ⌘Q and menu Quit already do this.
actual: on VM pane-test-27 (macOS 27.2, Transom Debug) `pkill -TERM` left the app alive for over five minutes, with `AppDelegate.handleSIGTERM` in a nested run loop on the main thread.
errors: none logged.
reproduction: launch the bundled app in the guest, send SIGTERM, watch with pgrep and `sample`.
started: unknown. Suspected from reading only: the DispatchSource handler at Sources/TransomMac/AppDelegate.swift:41-47 calls NSApp.terminate(nil) on the main queue; applicationShouldTerminate returns terminateLater and its reply block waits on the same main queue, so quit restore and writeCleanExit never run. killall may be affected; logout and restart are untested. scripts/vm-cli-check.sh comments rely on "the app answers SIGTERM with a clean-exit write". Unknown whether pane-test (15.7.7) does the same.

## Eliminated

- hypothesis: modal-panel run-loop mode does not service the main queue, so the reply block starves on any terminateLater
  evidence: the same delegate code exits in 0.22 s by Apple Event on both guests, and the AppKit-only program runs a main-queue block in that same modal-panel wait when not already inside a main-queue block.
  timestamp: 2026-11-04T19:20Z

- hypothesis: the hang is specific to macOS 27
  evidence: pane-test (15.7.7) shows the same hang and the same main-thread stack.
  timestamp: 2026-11-04T19:22Z

- hypothesis: sudden termination or an Info.plist setting changes how the app handles the signal
  evidence: grep of xcode/project.yml, xcode/Transom-Info.plist and Sources finds no NSSupportsSuddenTermination, NSSupportsAutomaticTermination or disableSuddenTermination; the sample shows the handler running.
  timestamp: 2026-11-04T19:05Z

- hypothesis: something in the saved layout.json holds up the quit
  evidence: each probe starts with an empty Application Support/Transom; the hang precedes any quit write and the Apple Event route passes from the same state.
  timestamp: 2026-11-04T19:10Z

- hypothesis: a real logout or restart from loginwindow reaches the SIGTERM path, as the AppDelegate comment says
  evidence: on the unfixed build, which cannot write cleanExit from SIGTERM, logout (both guests) and restart (27.2) recorded cleanExit true.
  timestamp: 2026-11-04T19:16Z

## Evidence

- timestamp: 2026-11-04T19:00Z
  checked: read Sources/TransomMac/Shell/StatusItemController.swift:105 (Quit Transom, key equivalent q, action NSApplication.terminate(_:)), AppDelegate.swift, 03-RESEARCH Pattern 11, grep for terminate callers
  found: there is no main menu, so ⌘Q is the key equivalent of the status menu's Quit item. Menu Quit and ⌘Q call -terminate: from an AppKit menu action (run-loop event path). The only other callers are SetupView's Quit button and the SIGTERM DispatchSource handler on .main. applicationShouldTerminate is shared by all of them; it schedules restore, writeCleanExit and reply with DispatchQueue.main.async and returns .terminateLater. Pattern 11 itself says "don't depend on main-queue servicing" during terminateLater, yet the reply block does.
  implication: read only. The routes share applicationShouldTerminate and differ only in the context -terminate: is called from. Testable difference: inside a main-queue drain (SIGTERM) or not (menu, Apple Event).

- timestamp: 2026-11-04T19:08Z
  checked: OBSERVED on pane-test-27 (macOS 27.2), unfixed 867887a Debug build from scratch derived data, one fixture window stranded off-screen; `osascript quit app id` (kAEQuitApplication)
  found: pid gone after 0.23 s; layout.json session.cleanExit false before, true after; log "quit restore: 1 of 1 windows"; window back from 984,686 to 352,256.
  implication: baseline. The same terminateLater + main-queue reply works from the Apple Event path, in the same modal-panel nested loop. So modal-panel mode alone cannot be what starves the block.

- timestamp: 2026-11-04T19:10Z
  checked: OBSERVED on pane-test-27 (27.2), same build and setup; `pkill -TERM -x "Transom Debug"` in the guest, waited 75 s, sampled at 6 s
  found: REPRODUCED. Alive at 75 s, cleanExit still false, no "quit restore" log line, window still at 984,686. Main thread, 1300 of 1300 samples: NSApplication run > __CFRunLoopRun > __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__ > _dispatch_main_queue_drain > _dispatch_source_invoke > closure in AppDelegate.handleSIGTERM > -[NSApplication terminate:] > -[NSApplication _shouldTerminate] > nextEventMatchingMask > __CFRunLoopRun > __CFRunLoopServiceMachPort > mach_msg.
  implication: the nested run loop sits inside a main-queue drain. The block queued by applicationShouldTerminate is behind the source handler on the same serial queue, and it never runs.

- timestamp: 2026-11-04T19:11Z
  checked: OBSERVED on pane-test-27 (27.2), same build; `killall "Transom Debug"` in the guest, waited 30 s, sampled
  found: same hang and same stack as pkill -TERM (closure in AppDelegate.handleSIGTERM > -[NSApplication terminate:] > _shouldTerminate > mach_msg, 1351 of 1351 samples); cleanExit false; window not restored.
  implication: killall sends SIGTERM, so it reaches the same handler and hangs the same way.

- timestamp: 2026-11-04T19:12Z
  checked: OBSERVED on pane-test-27 (27.2), same build; status menu opened over AX then (a) AXPress on Quit Transom, (b) a real posted Command-Q
  found: both exit; cleanExit true; "quit restore: 1 of 1 windows"; window back at 352,256. Gone in 1.76 s and 2.20 s, which include the helper's AX timeout and pause before the press.
  implication: confirms the report that menu Quit and ⌘Q work on the unfixed build.

- timestamp: 2026-11-04T19:13Z
  checked: OBSERVED on pane-test-27 (27.2), same build; a real GUI logout, `tell application "loginwindow" to «event aevtrlgo»` (session gone afterwards: `who` empty, new loginwindow)
  found: app gone after 1.59 s with cleanExit true, log "gesture tap stopped: quit". This build cannot write cleanExit from SIGTERM, so a clean write proves the logout came in as the quit Apple Event, not as SIGTERM. No "quit restore" line: the fixture had already quit, so the plan was empty.
  implication: the AppDelegate comment "logout sends SIGTERM" is wrong for a real logout. Logout was never affected by this hang.

- timestamp: 2026-11-04T19:16Z
  checked: OBSERVED on pane-test-27 (27.2), same build; real restart, `tell application "loginwindow" to «event aevtrest»`
  found: guest rebooted; after boot layout.json session.cleanExit true with launchedAt unchanged (815512563.58), so it was this run's write, and nothing relaunched.
  implication: a restart from loginwindow (Apple menu's route) also arrives as the quit Apple Event, not SIGTERM. Not affected by this hang.

- timestamp: 2026-11-04T19:17Z
  checked: OBSERVED on pane-test-27 (27.2), same build; `sudo shutdown -r now`
  found: guest rebooted; after boot cleanExit false with launchedAt unchanged (815512621.03), so the quit write never happened.
  implication: a command-line restart is the one that gets no Apple Event, and it loses the clean exit and the restore on this build. Whether its signal is SIGTERM is checked by re-running this on the fixed build.

- timestamp: 2026-11-04T19:20Z
  checked: OBSERVED on pane-test-27 (27.2), a small AppKit program with no Transom code: queue a main-queue block, then wait with nextEvent(inMode: .modalPanel) as _shouldTerminate does, once from a run-loop block and once from inside a main-queue block. Two earlier CF-only versions printed false for both cases: a bad control, since CFRunLoopRunInMode returns at once for a mode nothing is scheduled in. Discarded.
  found: "from a run-loop block (menu action, Apple Event): main-queue block ran = true"; "from inside a main-queue block (SIGTERM source): main-queue block ran = false".
  implication: confirms the mechanism apart from Transom. AppKit's modal-panel wait does service the main queue, except when the wait itself is inside a main-queue block.

- timestamp: 2026-11-04T19:22Z
  checked: OBSERVED on pane-test (macOS 15.7.7), the same unfixed build, the same probes
  found: SAME AS 27.2. pkill -TERM: alive at 60 s, cleanExit false, window not restored, same main-thread stack (1357 of 1357 samples). killall: alive at 20 s, cleanExit false, handleSIGTERM in the sample. osascript quit: gone in 0.22 s, cleanExit true, "quit restore: 1 of 1 windows". Status menu Quit and real ⌘Q: gone (1.77 s, 1.73 s), cleanExit true, window restored. Real logout: gone in 0.72 s, cleanExit true. AppKit mechanism program: true from a run-loop block, false inside a main-queue block.
  implication: the hang is not specific to macOS 27. Both guests agree on every route tried on both.

- timestamp: 2026-11-04T19:25Z
  checked: OBSERVED on pane-test (15.7.7), same build; `sudo shutdown -r now`, read layout.json after boot
  found: cleanExit false, launchedAt unchanged (815513081.41). Same as pane-test-27.
  implication: a command-line restart loses the clean exit and the restore on both guests.

- timestamp: 2026-11-04T19:24Z
  checked: OBSERVED on pane-test (15.7.7), small AppKit program: terminate(nil) from inside a main-queue block, delegate answers .terminateNow, willTerminate observer on OperationQueue.main (as TransomMacApp's freeze-test resume)
  found: prints applicationShouldTerminate, "willTerminate observer ran", "exit reached"; exit 0.
  implication: answering synchronously is safe from inside the drain: the observer runs and the process exits. No deadlock from posting inside the drain. Repeat on 27.2 before relying on it there.

- timestamp: 2026-11-04T19:30Z
  checked: RED. Host, `swift test --filter AppDelegateTests` (no signal, not live): new quittingRestoresThenWritesTheCleanExitBeforeAnswering. VM pane-test (15.7.7), `scripts/vm-quit-check.sh` with the unfixed app: new OutsideQuitIntegrationTests.
  found: unit test fails with reply rawValue 2 (terminateLater) and steps == []. VM: the sigterm case fails with 3 issues ("still running 10 s after sigterm", "no clean exit recorded", "the window is still stranded at 984,686"); the appleEvent case passes. "Test run with 1 test in 1 suite failed after 23.455 seconds with 3 issues."
  implication: both tests reproduce the bug and tell the routes apart.

- timestamp: 2026-11-04T19:29Z
  checked: GREEN on pane-test (15.7.7): `TRANSOM_VM=pane-test scripts/vm-quit-check.sh` with the fixed app; host `swift test --filter AppDelegateTests` and `--filter TransomMacTests` (no signal, not live)
  found: "✔ Test run with 1 test in 1 suite passed after 13.050 seconds." (sigterm and appleEvent cases). Host: "Test run with 5 tests in 1 suite passed", "Test run with 432 tests in 62 suites passed".
  implication: the same test and setup that failed against the unfixed app pass against the fixed one.

- timestamp: 2026-11-04T19:40Z
  checked: OBSERVED on pane-test (15.7.7), FIXED build, every route, one stranded fixture window each
  found: pkill -TERM gone 0.26 s; killall 0.25 s; osascript quit 0.24 s; status menu Quit 1.64 s (5 of 5 runs, same as the unfixed build's 1.63-1.64 s, which is the helper's AX pauses; one earlier run took 4.11 s, not repeated); real ⌘Q 1.73 s; SIGTERM with the status menu open 1.45 s; SIGTERM with the fixture stopped 2.17 s ("an app did not answer in time; abandoned", "quit restore: 0 of 1 windows"). All cleanExit true; all restore the window except the stopped app's, as intended. Real logout gone 0.51 s, cleanExit true. loginwindow restart: cleanExit true after boot, launchedAt unchanged. `sudo shutdown -r now`: cleanExit TRUE after boot, launchedAt unchanged, where the unfixed build recorded false.
  implication: the fix reaches every route, and a real signal stays within the 2 s restore limit with a hung app. The shutdown -r change shows a command-line restart does go through the SIGTERM handler.

- timestamp: 2026-11-04T19:41Z
  checked: pane-test (15.7.7), `TRANSOM_VM=pane-test TRANSOM_VM_APP=<fixed app> scripts/vm-live-test.sh 'QuitRestoreIntegrationTests|OutsideQuitIntegrationTests'`
  found: "✔ Test run with 4 tests in 2 suites passed after 15.254 seconds."
  implication: the quit-restore neighbours still pass.

- timestamp: 2026-11-04T19:45Z
  checked: OBSERVED on pane-test-27 (27.2), FIXED build, every route, one stranded fixture window each; and the terminateNow check program
  found: quitnow: applicationShouldTerminate, "willTerminate observer ran", "exit reached", exit 0. pkill -TERM gone 0.25 s, repeated 6 more times at 0.23-0.26 s; killall 0.24 s; osascript quit 0.22 s; status menu Quit 1.66 s; real ⌘Q 1.71 s; SIGTERM with the status menu open 1.41 s; SIGTERM with the fixture stopped 2.28 s ("abandoned", "quit restore: 0 of 1 windows"). All cleanExit true; all restore the window except the stopped app's. Real logout gone 0.91 s, cleanExit true. loginwindow restart: cleanExit true after boot. `sudo shutdown -r now`: cleanExit TRUE after boot, launchedAt unchanged.
  implication: same results as 15.7.7.

- timestamp: 2026-11-04T19:47Z
  checked: revert and reconfirm on pane-test-27 (27.2): `TRANSOM_VM=pane-test-27 scripts/vm-quit-check.sh <unfixed app>`, then `TRANSOM_VM=pane-test-27 scripts/vm-quit-check.sh` (fresh build into .build/vm-quit-app); then both quit suites through vm-live-test.sh; host `swift test`
  found: unfixed: "✘ Test run with 1 test in 1 suite failed after 24.885 seconds with 3 issues." Fixed: "✔ Test run with 1 test in 1 suite passed after 14.010 seconds." Both suites: "✔ Test run with 4 tests in 2 suites passed after 14.210 seconds." Host, not live, no signal: 226, 432, 101 and 1098 test runs all passed. xcode/.xcode-build Debug app mtime unchanged (Nov 3 21:29).
  implication: this change is what fixes it. The bug returns with the unfixed app and goes with the fixed one, on both guests.

## Resolution

root_cause: Two conditions together. The SIGTERM DispatchSource (queue .main) calls NSApp.terminate(nil) from inside _dispatch_main_queue_drain; and applicationShouldTerminate returned .terminateLater and left restore, writeCleanExit and the reply to a DispatchQueue.main.async block. AppKit's terminateLater wait (nextEventMatchingMask in modal-panel mode, under -[NSApplication _shouldTerminate]) does not service the main queue while it is itself inside a main-queue block, so that block never ran. Menu Quit, ⌘Q and the quit Apple Event call terminate from outside the queue, so they worked.
fix: applicationShouldTerminate runs restore() and writeCleanExit() itself and returns .terminateNow; the reply closure is gone. Corrected the comment that said logout sends SIGTERM, and the AXWindowSystem comment about terminateLater.
oracle_type: specified (SAFE-01: a quit restores, records the clean exit and exits, bounded by the restore limit). Neighbours checked by guest probe: a hung app at the 2 s deadline, SIGTERM with the status menu open.
verification:
  target_test: { result: pass, unit: "AppDelegateTests.quittingRestoresThenWritesTheCleanExitBeforeAnswering", vm: "OutsideQuitIntegrationTests on pane-test and pane-test-27" }
  mutation_check: { result: skipped, reason_if_skipped: "no Stryker for Swift. The revert below is the mutant at the fix site, and the driving tests catch it" }
  no_op_deletion: { result: flagged, deletion_justified_by_rca: true, note: "net deletion of the terminateLater wait and the reply closure. The work itself still runs, now before the answer. Removing the wait is the fix; every route was re-observed doing restore and clean exit" }
  adjacent_tests: { result: pass, suites_run: ["host swift test: all targets, not live", "VM QuitRestoreIntegrationTests on both guests"] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, note: "same test, unfixed app vs fixed app, on both guests" }
  guardrail_verdict: accepted
  human_verify: not requested. The session was unattended by instruction; VM runs stand in for it.
files_changed:
  - Sources/TransomMac/AppDelegate.swift
  - Sources/TransomMac/AXWindowSystem.swift
  - Tests/TransomMacTests/AppDelegateTests.swift
  - Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/IntegrationSupport.swift
  - scripts/vm-live-test.sh
  - scripts/vm-quit-check.sh
commits: 1c338be (RED tests), fe771b6 (fix)

## Answers to the session's questions

- pane-test (15.7.7) vs pane-test-27 (27.2): the same. OBSERVED: same hang, same main-thread stack, same results on every route, before and after the fix.
- killall: the same code path as pkill -TERM. OBSERVED: same stack on both guests.
- Logout and restart from loginwindow: a different path, the quit Apple Event, and never affected. OBSERVED: real logout on both guests and a real loginwindow restart on 27.2, on the unfixed build, recorded cleanExit true, which SIGTERM cannot do on that build. On the fixed build logout and restart were observed on both guests. Which event loginwindow sends is inferred from this result and from the exit path; it was not traced directly.
- Command-line restart (`sudo shutdown -r now`): reaches the SIGTERM path. OBSERVED on both guests: cleanExit false on the unfixed build, true on the fixed build. That it is SIGTERM is inferred from that difference; the signal itself was not traced.

## Prevention

why_chain:
  - code: "Why did the block not run? terminate was called inside the main-queue drain. Why was that possible? The handler uses a .main signal source, a natural choice, and nothing says terminate may not be called there. Why did the delegate depend on the queue? Plan 03-15 scheduled the sequence on the main queue, although Pattern 11 warned against relying on main-queue servicing in that wait; it was applied to the restore's internals, not to the block carrying them."
  - process: "Why did nobody see it? Plan 03-15 listed the real SIGTERM path as human verification, and no gate sent a real signal: the unit test called applicationShouldTerminate directly, in a context that does service the queue, and vm-cli-check's SIGTERM fallback only runs after osascript quit fails."
  - environment: "Eliminated: not specific to a macOS version."
why_not_caught: no gate existed for this class. The unit test called the delegate directly and passed, and live tests call restoreForTermination in-process; nothing quit the real app by signal.
recurrence_guard: OutsideQuitIntegrationTests.aQuitFromOutsideRestoresRecordsTheCleanExitAndExits (Tests/TransomMacIntegrationTests/QuitRestoreIntegrationTests.swift), run with scripts/vm-quit-check.sh; AppDelegateTests.quittingRestoresThenWritesTheCleanExitBeforeAnswering, which fails if the delegate defers its work again.
