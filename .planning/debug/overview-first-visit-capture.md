---
status: awaiting_human_verify
trigger: "Phase 6 UAT B1: first visit to another Space soon after a relaunch captures 0 windows, so the overview keeps app-icon tiles for that Space"
created: 2026-11-01
updated: 2026-11-01
---

## Symptoms

- **Expected (D-03, 06-UI-SPEC):** after visiting Desktop 2 and coming back, the overview's Desktop 2 thumbnail shows real snapshots of its windows (the visit capture after arrival).
- **Actual (VM UAT B1, 06-UAT.md):** with 2 docked fixture windows on Desktop 2 and Transom relaunched on Desktop 1, the first visit (~3 s, about 20 s after the relaunch) logged `space 3 captured 0 windows after visit`; the thumbnail stayed app icons (`.build/0612-uat-vm-shots/b1-overview-warm.png`). A second, longer visit (~9 s) logged `space 3 captured 2 windows after visit` and then showed real previews (`b1-overview-warm2.png`).
- **Errors:** none.
- **Timeline:** seen once in the VM UAT run (cd9bd48). Not checked on the host.
- **Repro (VM only):** docked fixture windows on Desktop 2; relaunch Transom on Desktop 1; switch to Desktop 2, stay ~3 s, switch back; ⌃⌥⌘A; look at Desktop 2's thumbnail and the log line.
- **Unconfirmed hypothesis from the UAT agent:** the capture ~1 s after arrival (OverviewController.spaceDidSettle → visitTasks / capturedVisit) runs before that Space's windows are tracked/visible after a relaunch (windows on a never-visited Space may not be in the arranger, CG on-screen list, or SCShareableContent yet), and capturedVisit then marks the visit done so nothing retries.

## Relevant code

- Sources/TransomMac/Overview/OverviewController.swift (spaceDidSettle, visitTasks, capturedVisit, the "captured N windows after visit" log)
- Sources/TransomMac/ArrangeController.swift ~L212-213 (spaceChanged → overview().spaceDidSettle)
- Sources/TransomMac/Zoom/ZoomController.swift / SnapshotCapture.swift (capture path, SCShareableContent)
- Sources/TransomEngine Arranger (which windows are known for a Space after relaunch)

## Constraints

- Reproduce only in the Tart VM `pane-test` (scripts/vm-live-test.sh, ssh admin with ~/.ssh/pane_vm_ed25519, lock .build/transom-vm.lock, one VM job at a time). Screen Recording for `com.eightabyte.transom.debug` in the guest was reset during UAT B7: re-grant it in the guest if needed (or stop and ask if impossible). Never run live tests, event taps, key posting, overlay panels, capture or window-opening code on the host.
- A VM test run passes only if output has "Test run with N tests … passed". `swift test --filter` gates must prove at least one test ran.
- Never touch the user's real layout.json or defaults; never set TRANSOM_LIVE=1 on host; never stage .planning/config.json, .planning/state.json, milestone.lock; never kill node.
- Guest: never quit apps you didn't launch, leave guest on Desktop 1, restore anything changed.
- Builds sequential. Commit trailers: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01HXttRxYZhy1TD5LBCzjqSJ`.
- Fix the root cause with a unit or VM test; rebuild the Debug app (scripts/build-debug.sh) at the end. The host user may be running the current Debug build; rebuilding underneath it is fine, do not launch or quit it.
- Another fix just landed in OverviewController.panel(for:) (98f7d3d, panels stranded off the active Space); keep it intact.
- RULE 0: stop on unknown/catastrophic failure.

## Current Focus

bug_class: Bohrbug (deterministic: 3 of 3 VM runs, 2 of 2 UAT first visits)
hypothesis: CONFIRMED (H1) — a Space change refreshes no app, so windows on a Space AX has not listed since launch are tracked only at the next 5 s sweep; the D-03 capture 1 s after arrival finds none and records the visit as done.
reasoning_checkpoint:
  hypothesis: "The first visit's capture finds 0 windows because AXWindowSystem.spaceDidChange schedules no AX refresh: AX lists a Space's windows only while it shows, so after a launch on Desktop 1 the Desktop 2 windows enter arranger.windows only at the next periodic sweep (0-5 s after arrival), while OverviewController.captureVisit runs at a fixed 1 s and marks the visit captured whatever it found."
  confirming_evidence:
    - "VM test theFirstVisitToASpaceNotYetReadCapturesItsWindows, 3 runs: 0 of 2 tracked before the visit, not tracked within 3 s of arrival, tracked at 4759/4760/4772 ms (the first 5 s sweep after AXWindowSystem.start), nothing cached"
    - "Once tracked, OverviewController.inputs shows 2 of 2 for the display (H4 eliminated)"
    - "UAT log: no capture-failed / shareable-content-failed line in the run; the second visit (windows tracked by then) captured 2"
  falsification_test: "With a refresh scheduled on every Space change, the windows must be tracked well under 1 s after arrival and both snapshots cached within 3 s. If they are still tracked only at ~4.7 s, or tracked early but not cached, H1 is wrong or incomplete."
  fix_rationale: "Refreshing every app 75 ms after a Space change makes the arranger list the shown Space's windows before anything that reads it (the D-03 capture at 1 s, tiling of restored desks), instead of waiting up to 5 s for the sweep. The capture then has real tiles to request. It fixes the source of the stale data, not the capture's symptom."
  blind_spots: "Not checked on the host (macOS 27.2) or with many/slow apps: a refresh of an app slower than ~0.9 s still misses the capture (the capture stays one-shot). Not checked whether AX can lag the activeSpaceDidChange notification on 27.x; the 02-17 Space-switch flag is consumed by the first update whose reads start after the change, as with the existing hint refreshes."
  candidate_causes:
    - "code: spaceDidChange schedules no refresh (the doc line promising one belonged to displaysDidChange, orphaned by ea2f85e)"
    - "code: captureVisit is one-shot at a fixed 1 s and marks a 0 result as done"
    - "environment: SCShareableContent or the CG on-screen list lagging the switch (no capture errors logged; second visits captured fine)"
    - "data: windows tracked but filtered out of inputs (eliminated: inputs show 2 of 2 once tracked)"
  and_gate: "yes: the failure needs both the tracking lag (no refresh on a Space change) and the one-shot capture. Removing the lag removes the failure for apps that answer AX within ~0.9 s; the one-shot capture is kept (it stops repeated captures on repeated Space-change events) and recorded as a known limit."
next_action: optional host re-check (macOS 27.2) of the B1 first visit after a relaunch; then archive to resolved/ and add the knowledge-base entry

## Evidence

- timestamp: 2026-11-01
  checked: OverviewController.spaceDidSettle / captureVisit (L577-602)
  found: captureVisit builds the layout from `Self.inputs(arranger(), …, frontToBack: onScreen)` (tracked, present, on the current Space, in the CG list), sends one request per tile, and sets `capturedVisit[uuid] = space` whatever the image count, 0 included. `overviewImages` returns [:] at once when requests are empty.
  implication: 0 captured means either no tiles (nothing tracked/filtered) or every capture failed; a 0 result also ends the visit, so nothing retries until the next Space change.

- timestamp: 2026-11-01
  checked: AXWindowSystem.spaceDidChange (L621-634), RefreshScheduler, handle(_ hint:)
  found: a Space change only marks every pid `spaceChanged` and yields `.spaceChanged`; it schedules no refresh (the doc comment's "refreshes every app after 500 ms of quiet" is stale — never in the code since ea2f85e). Apps are re-read only on an AX hint (75 ms debounce) or the 5 s periodic sweep. AX lists only the shown Space's windows, so after a relaunch on Desktop 1 the Desktop 2 windows are not in `arranger.windows` (the cold thumbnail draws them from the stored desk via plannedWindows).
  implication: on the first visit after a relaunch, the Desktop 2 windows reach the arranger 0-5 s after arrival unless a hint fires; a capture at 1 s can see none of them. Supports H1, not yet observed.

- timestamp: 2026-11-01
  checked: SnapshotCapture.capture / captureAll
  found: a window missing from scWindows returns nil with no log; a failed capture logs "capture failed window N". captureAll re-reads SCShareableContent once for unknown IDs, then marks them `unlisted`.
  implication: H2 would show no capture-failed log but nonzero requests; H1 shows zero requests. A per-stage count in the log separates them.

- timestamp: 2026-11-01
  checked: the saved UAT guest log .build/0612-uat-vm-transom.log and ~/uat0612/fx.sh, d2.out in the guest
  found: the B1 run is process 6543 (relaunched 23:14:20.6, fixture pid 6499 keyed at launch). First visit: "space 1 → 3" 23:14:50.103, "space 3 captured 0 windows after visit" 23:14:51.185, back at 23:14:53.209 (3.1 s). Second visit 23:15:15.966 → "captured 2 windows" 23:15:17.051. No capture-failed or shareable-content-failed line anywhere in the run. The earlier process 6457 also logged 0 on its first visit (there the fixture app itself was only keyed 1.6 s after the capture). The d2 fixture (two windows 1812/1813 on Desktop 2) reported "frontmost none": it does not activate on its own, so a switch to Desktop 2 need not post a focus hint for it.
  implication: 2 of 2 first visits after a launch captured 0, with no capture error: the capture had nothing to ask for (H1/H4), not failing captures (H2 unlikely). Deterministic, not a one-off.

- timestamp: 2026-11-01
  checked: VM, new test theFirstVisitToASpaceNotYetReadCapturesItsWindows with temporary DIAG lines, run 4 times (1 + 3)
  found: every run: "before the visit 0 of 2 windows tracked", "tracked never after arrival, cached=false" (3 s window), test fails at the cache expectation. DIAG: tracked at 4758.98 / 4760.30 / 4772.02 ms after arrival; overview inputs then show 2 of 2.
  implication: H1 confirmed. The windows wait for the first periodic sweep (AXWindowSystem.start + 5 s), which here lands ~4.8 s after arrival; the 1 s capture had nothing to request. H4 eliminated.

- timestamp: 2026-11-01
  checked: git blame of the "refreshes every app after 500 ms of quiet" line above spaceDidChange
  found: written for displaysDidChange in cdbdf93 (02-06); ea2f85e (03-05) inserted spaceDidChange between it and displaysDidChange, so it now sits on the wrong function and displaysDidChange has no doc comment. No plan or decision records a reason for not refreshing on a Space change.
  implication: no Chesterton's fence against a refresh on Space change; the 02-17 Space-switch flag already expects an update after a switch.

- timestamp: 2026-11-01
  checked: after the fix (d297b03): VM guest state, scripts/build-debug.sh
  found: guest on Desktop 1 (ManagedSpaceID 1), no fixtures, no Transom running, VM lock released. Debug app rebuilt and verified (valid on disk, satisfies its designated requirement); not launched on the host.
  implication: ready for the optional host re-check.

## Eliminated

- hypothesis: H4 — the windows are tracked but filtered out of the overview inputs (state, Spaces, display)
  evidence: once tracked (~4.76 s after arrival) OverviewController.inputs lists 2 of 2 fixture windows for the display
  timestamp: 2026-11-01

## Resolution

root_cause: "Two conditions together (AND-gate). (1) AXWindowSystem.spaceDidChange refreshed no app on a Space change, and AX lists a Space's windows only while it shows, so after a launch on Desktop 1 the Desktop 2 windows reached arranger.windows only at the next 5 s periodic sweep (VM: ~4.76 s after arrival). (2) OverviewController.captureVisit runs once, 1 s after the change, and records the visit as captured whatever it found, so its 0-window result was final for that visit. The doc line promising a refresh ('refreshes every app after 500 ms of quiet') belonged to displaysDidChange and was orphaned onto spaceDidChange by ea2f85e."
fix: "AXWindowSystem.spaceDidChange now schedules a refresh of every app 75 ms after a Space change (scheduler.scheduleAll, the existing cancel-latest debounce), so the shown Space's windows are tracked ~0.4 s after arrival, before the 1 s visit capture. The orphaned doc line moved back to displaysDidChange. captureVisit is unchanged (condition 2 kept: it stops repeat captures on repeated Space-change events); known limit: an app that takes over ~0.9 s to answer AX still misses that visit's capture and gets it on the next visit."
oracle_type: specified (D-03: after a visit, the Space's windows are in the snapshot cache)
verification:
  target_test: { result: pass, runs: "3 of 3 green after the fix: tracked 446 / 487 / 448 ms after arrival, cached=true, 'Test run with 1 test in 1 suite passed'" }
  mutation_check: { result: pass, reason_if_skipped: "no Stryker for Swift; a manual mutant was used", mutant_killed: "scheduleAll delay 75 → 1500 ms: tracked 1887 ms after arrival, cached=false, test failed" }
  no_op_deletion: { result: pass, deletion_justified_by_rca: "n/a: the diff adds one call and moves one doc line" }
  adjacent_tests: { result: pass, suites_run: ["VM: OverviewSpaceSwitchIntegrationTests (4 tests), SpacesIntegrationTests, LiveTrackingTests, TabsIntegrationTests: passed", "VM: OverviewIntegrationTests failed only when run in parallel with OverviewSpaceSwitchIntegrationTests (its Space switches interrupt the open overview); alone: 'Test run with 3 tests in 1 suite passed'", "host: swift test --filter NoScreenCaptureTests, 'Test run with 2 tests in 1 suite passed'"] }
  revert_and_reconfirm: { result: pass, bug_returned_on_revert: true, fixed_on_reapply: true, detail: "fix stashed: 'tracked never after arrival, cached=false', test failed; reapplied: green (3 runs above)" }
  guardrail_verdict: accepted
commit: d297b03
files_changed:
  - Sources/TransomMac/AXWindowSystem.swift
  - Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift
