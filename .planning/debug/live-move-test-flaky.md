---
status: awaiting_human_verify
trigger: "LiveTrackingTests aMoveIsReportedWithin1s intermittently fails at LiveTrackingTests.swift:39 (window never tracked) after plan 02-09"
created: 2026-10-24T00:00:00Z
updated: 2026-10-25T00:00:00Z
---

## Current Focus

hypothesis: confirmed. SessionGate latched a momentary frontmost loginwindow, which macOS reports while unlocked when self-activating apps quit together, into a full pause
next_action: none in code; human confirms. Open item: CloseIntegrationTests unhide-step flake (see Evidence), separate from this fix
bug_class: Mandelbug (order/load dependent: needs fixtures quitting inside another live test's wait window)
reasoning_checkpoint:
  hypothesis: "a quit-time loginwindow activation pauses every live AXWindowSystem for >= 1.75 s (scheduler.stop drops pending refreshes; resume waits resumeQuiet 1.5 s + refreshAll + 250 ms settle)"
  confirming_evidence:
    - "int-2.log pre-fix: unlocked, loginwindow frontmost 12 ms at a fixture quit, live system logged PAUSE"
    - "A/B with the real SessionGate source on the real notification centres, pairs of fixtures quitting together, unlocked: HEAD gate 7 pauses in 16 rounds, fixed gate 0 in 16; CGSSessionScreenIsLocked absent at every loginwindow activation"
  falsification_test: "a pause while unlocked with the fix, or an aMove trackedWindow failure with no other cause"
  fix_rationale: "the lock flag is the authoritative poll and is never set during the transient; loginwindow frontmost is only used when the session dictionary cannot be read"
  blind_spots: "no instrumented failing aMove run was captured; the link from the transient to the 3 original failures rests on mechanism plus wave5 timing (Freeze and Close suites finished inside the wait)"
  candidate_causes:
    - "code: gate latches an ambiguous instantaneous signal (confirmed, fixed)"
    - "environment: parallel suites quitting self-activating fixtures together (trigger; also real use)"
    - "code: first AX read after launch fails with no follow-up (eliminated in logs: every no-known-window list failure was a quitting fixture)"
  and_gate: "yes: trigger (fixtures quitting together inside a wait) AND the gate's latching; removing the code condition is sufficient"

## Symptoms

expected: aMoveIsReportedWithin1s finds the freshly launched fixture window within 2 s, then sees windowMoved within 1 s
actual: intermittently "window 8539 of pid 79732 never tracked" at LiveTrackingTests.swift:39 (find() nil after 2 s); test failed after 4.86 s
errors: "Expectation failed: await find() ... window <id> of pid <pid> never tracked"
reproduction: full `swift test` or back-to-back suite runs; ~3 failures in 13 runs at ea7f401; move test alone 6/6 passes
started: after plan 02-09 (dcd2e7f passed 4/4)

## Eliminated

## Evidence

- timestamp: 2026-10-24T00:00:00Z
  checked: wave5-fail.log
  found: failure is at line 39, the #require in trackedWindow (initial tracking), not the move wait. Ran in parallel with FreezeIntegrationTests and CloseIntegrationTests, which launch/stop/hide/quit their own fixtures; LiveTracking's appFilter matches every fixture by bundle key.
  implication: the window-appearance path (launch refresh -> settle 250 ms -> created) was delayed > 2 s

- timestamp: 2026-10-24T00:00:00Z
  checked: AXWindowSystem.swift (02-09 diff)
  found: refresh() calls gate.evaluate() and returns early when paused; sessionDidPause() calls scheduler.stop() which cancels ALL pending per-pid refreshes; resume waits resumeQuiet 1.5 s then refreshAll (sweep initial:false, so a new window is pending again and needs a 250 ms settle follow-up). SessionGate.evaluate() pauses when NSWorkspace.frontmostApplication is com.apple.loginwindow.
  implication: any brief spurious pause costs > 1.75 s of blindness, enough to fail the 2 s / 1 s limits

- timestamp: 2026-10-24T13:06:27Z
  checked: instrumented integration loop, run 2 (int-2.log)
  found: while the session was unlocked, when quittingTheAppEmitsAppTerminatedWithin2s terminated its (frontmost) fixture, NSWorkspace.frontmostApplication read com.apple.loginwindow for 12 ms (1792864387.032 -> .044, then dev.warp.Warp-Stable). SessionGate.evaluate (didActivateApplication) set loginWindowFrontmost and the live AXWindowSystem logged PAUSE, then resumed on the next activation. The session lock flag was not set (resume happened as soon as loginwindow cleared).
  implication: a quit of the frontmost app makes every live AXWindowSystem pause; the pause drops pending refreshes (scheduler.stop) and blinds the system for resumeQuiet 1.5 s + a full refresh + a 250 ms settle

- timestamp: 2026-10-24T13:06:27Z
  checked: wave5-fail.log ordering
  found: aMoveIsReportedWithin1s started, then FreezeIntegrationTests and CloseIntegrationTests both finished (each terminates its fixture, and every fixture activates itself with NSApp.activate) during its 2 s trackedWindow wait; the window was never tracked
  implication: matches the transient-pause mechanism: two frontmost-fixture quits inside the wait window

- timestamp: 2026-10-24T13:06:27Z
  checked: first batch of 8 instrumented full runs (user active at the keyboard)
  found: 0 PAUSE, 0 failures
  implication: the transient only happens when the quitting fixture is frontmost; with the user active in another app, cooperative activation (macOS 14+) often keeps fixtures from becoming frontmost, so the rate is load/usage dependent

- timestamp: 2026-10-24T13:06:27Z
  checked: int-3.log (CloseIntegrationTests destroyed-within-1s failure, no PAUSE) and int-4.log (all live tests failed, 10 PAUSEs)
  found: run 4 coincided with the real screen lock (lockstate: CGSSessionScreenIsLocked=1, frontmost loginwindow; the user had stepped away); run 3 shows ~0.7-0.9 s main-actor resume latency on two unrelated pids at 1792864390.7-391.6, about 8 s before the lock
  implication: run 4 is not evidence (real lock). Run 3 is a separate, unexplained stall, possibly lock/screensaver onset; re-check after the fix with the session unlocked

- timestamp: 2026-10-25T00:00:00Z
  checked: scratch probe quitfront (one frontmost fixture quits, 5 rounds) and quitfront2 (two fixtures quit together, 5 rounds), unlocked
  found: a single quit went straight to Warp (0/5). Two quitting together produced didActivateApplication for com.apple.loginwindow in 3/5 rounds, lock flag nil every time
  implication: the trigger is several self-activating apps quitting at once, which parallel integration suites do

- timestamp: 2026-10-25T00:00:00Z
  checked: A/B of the real SessionGate source (HEAD vs fix) on the real NSWorkspace / distributed centres, 2 x 8 rounds of paired fixture quits each, unlocked
  found: HEAD gate paused 4 + 3 = 7 times; the fixed gate paused 0 times
  implication: the fix removes the spurious pause under the real trigger

- timestamp: 2026-10-25T00:00:00Z
  checked: instrumented PaneMacIntegrationTests loops with the fix (20 + 12 runs, unlocked, caffeinate)
  found: 31/32 passed, 0 PAUSE; aMove passed every run. One failure: fix-batch run 2, closeFreezeHideAndQuitAreDecidedByTwoSources at CloseIntegrationTests.swift:58 (unhidden window not .present within 2 s). The Close system did no refresh at all for the fixture in the 2 s after the unhide; in passing runs AXApplicationShown arrives within 4 ms and the refresh 45-60 ms later reads hidden=false. A sweep refresh and a hint refresh coincided just before (followUp at 790.959). Not explained by the gate or the lock; either the Shown hint was lost after the SIGSTOP/SIGCONT freeze step, or it landed before the coinciding refresh read AXHidden. A pre-fix run had a different Close flake (destroyed not within 1 s, with a ~0.8 s main-actor stall). Both are open, separate from this fix
  implication: report as an open issue; not looped further per coordinator

- timestamp: 2026-10-25T00:00:00Z
  checked: proof on the clean tree (instrumentation removed), unlocked, caffeinate, sequential
  found: LiveTrackingTests 15/15; CloseIntegrationTests 5/5; full swift test passed (142, 53, 11, 99); scripts/check-no-appkit.sh OK; no fixtures left
  implication: fix verified; no regression

## Resolution

root_cause: SessionGate.evaluate() paused on frontmost com.apple.loginwindow, which macOS also activates for ~10 ms while unlocked when self-activating apps quit together (3/5 paired quits; a single quit did not); the pause drops pending refreshes and the resume takes 1.5 s quiet + a full refresh + settle, so live systems miss their 1-2 s limits when another fixture quits
fix: loginwindow frontmost counts only when the session dictionary cannot be read; the CGSSessionScreenIsLocked flag decides otherwise
verification: unit test RED->GREEN; live A/B of the gate under the real trigger (7 pauses -> 0); 32 instrumented integration runs with 0 pauses; proof LiveTrackingTests 15/15, CloseIntegrationTests 5/5, full swift test, check-no-appkit OK
oracle_type: specified (SessionGateTests: a readable session without the lock flag must not pause)
files_changed: [Sources/PaneMac/SessionGate.swift, Tests/PaneMacTests/SessionGateTests.swift]
