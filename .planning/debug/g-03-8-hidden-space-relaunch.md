---
status: diagnosed
trigger: "G-03-8 (SAFE-06 / Phase 3 SC4): after a Pane relaunch, layout.json keeps the Space 2 desk but its docked list comes back empty (Notes/Reminders gone); Space 1 restores fine"
created: 2026-10-26T00:00:00Z
updated: 2026-10-27T01:45:00Z
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (deterministic: 4/4 VM relaunches in this session, plus 3 earlier; headless repro fails every run)
hypothesis: CONFIRMED. LayoutRestore.reattach (run once at the first complete inventory) closes every saved window the fresh WindowTracker does not track; AXWindows lists only the shown Space's windows and the tracker creates windows only from AXWindows, so every saved window on a Space not shown at launch is closed.
next_action: none (goal find_root_cause_only); hand back ROOT CAUSE FOUND

reasoning_checkpoint:
  hypothesis: "Saved windows on a Space not shown at launch are removed by LayoutRestore.reattach because a fresh WindowTracker never tracks them: AXWindows omits them and the tracker only creates windows from AXWindows entries"
  confirming_evidence:
    - "VM spaceprobe on Space 1: AXWindows err 0 count 0 for Notes and Reminders, while CG optionAll lists ids 150/693 (offscreen) and SLSCopySpacesForWindows says Space 41"
    - "VM layout.json timeline: Space 41 entries present after the clean quit (and after SIGKILL), gone 12 s after relaunch; same for the recovery launch"
    - "Headless probe with a fresh FakeWindowSystem at relaunch: inventory ids [1]; LayoutRestore.reattach removed [3]; Space 2 desk docked [] floating []"
    - "Keeping window 3 out of the removal (throwaway patch, reverted) makes the same probe pass, world == saved after showing Space 2"
  falsification_test: "If AXWindows listed hidden-Space windows, or the drop happened at the quit write, the VM probe would show count > 0 / layout.json (b) would already be empty. Neither happened"
  fix_rationale: "Keeping a saved window whose identity is still alive in CG (same windowID and pid) as a dormant entry removes the only path that deletes it; its first windowCreated re-attaches it (admit skips windows already on a desk)"
  blind_spots: "Not checked: a window on a hidden Space of a SECOND display (same AX rule expected); minimized windows on a hidden Space; how long a dormant entry of a window closed on a never-shown Space should live"
  candidate_causes:
    - "code: LayoutRestore.reattach treats untracked as closed (confirmed)"
    - "environment: AXWindows scope is the shown Space only (confirmed, macOS 15.7.7)"
    - "data/persistence: quit write drops hidden desks (eliminated: layout.json intact after quit)"
  and_gate: "yes: needs both (a) the OS fact that AXWindows omits hidden-Space windows and (b) reattach closing untracked windows at one fixed instant. Either alone does not drop anything. The test gap (c) is why it was not caught"

## Symptoms

expected: Docked windows on every Space come back to their own layouts after quitting and relaunching Pane (apps keep running)
actual: In the Tart VM, after a Pane relaunch, layout.json keeps the Space 2 desk but its docked list is empty (Notes#150, reminders#693 gone). Space 1 (visible at launch) restores fine (UAT 10)
errors: none reported
reproduction: VM pane-test; dock Notes + Reminders on Space 2; switch to Space 1; quit Pane; relaunch Pane; inspect layout.json
started: reproduced 3 times (03-18, 03-22 executors); likely since multi-desk restore (03-05/03-07)

## Eliminated

- hypothesis: the quit path (writeCleanExit / restoreForTermination) writes the hidden desk out empty
  evidence: VM layout.json after a clean quit and after SIGKILL still holds Space 41 docked [Notes#150] floating [reminders#693]
  timestamp: 2026-10-27T01:33Z

- hypothesis: a later sweep or event (not reattach) drops the windows after the restore
  evidence: headless probe: LayoutRestore.reattach(saved, tracked: inventory) alone returns removed [3]; the World already lacks it right after the restoring inventory; LifecycleSync only closes on events for tracked windows, and the tracker never tracked it
  timestamp: 2026-10-27T01:40Z

- hypothesis: FakeWindowSystem lists hidden-Space windows in AX (verifier's wording)
  evidence: FakeWindowSystem.showSpace sets listedInAX false for off-Space windows (correct AX model). The gap is the TEST: its relaunch keeps the same fake, whose tracker still knows the hidden windows from session 1
  timestamp: 2026-10-26T20:33Z

## Evidence

- timestamp: 2026-10-26T20:30Z
  checked: Sources/PaneEngine/WindowTracker.swift ingest (lines ~100-190)
  found: a window is only created (windowCreated, entered in `windows`) from an observation with `listedInAXWindows == true`. Unlisted observations (the cached-element probes) only feed CloseRule for windows already known.
  implication: a window AX does not list is never tracked by a fresh WindowTracker, whatever CG/SkyLight say.

- timestamp: 2026-10-26T20:31Z
  checked: Sources/PaneEngine/Arranger.swift process(.inventory) lines 194-204 and LayoutRestore.reattach
  found: the restore runs once, at the first inventory with initialRefreshComplete; LayoutRestore.reattach keeps a saved window only if its identity is in `tracked` (non-synthetic), else applies `.closed` to it.
  implication: any saved window not tracked at the first complete inventory is deleted from the World for good.

- timestamp: 2026-10-26T20:33Z
  checked: Tests/PaneEngineTests/ArrangerMultiDeskRestoreTests.swift lines 120-123; FakeWindowSystem.refresh/showSpace
  found: the fake does hide off-Space windows from AX (showSpace sets listedInAX = false), but the "relaunch" replaces only `harness.arranger`; it keeps `harness.fake`, whose WindowTracker already tracks all 8 windows from the first session (probed by cached element, still known). So `fake.inventory()` hands the fresh Arranger the hidden-Space windows.
  implication: the test models "Arranger restarts, window system keeps its memory", which a real relaunch never does (a fresh AXWindowSystem has an empty tracker).

- timestamp: 2026-10-26T20:36Z
  checked: VM (macOS 15.7.7), Space 1 shown, /tmp/spaceprobe Notes Reminders (AX + CG optionAll + SLSCopySpacesForWindows)
  found: display current Space 1, Spaces [1, 41]. Notes pid 1477: AXWindows err 0 count 0; AXChildren windows []; CG optionAll has layer-0 id 150 (370,37 642x664) onscreen=off, SkyLight spaces 41. Reminders pid 3365: AXWindows err 0 count 0; CG id 693 (12,25 768x692) off, spaces 41.
  implication: CONFIRMS the AX half: AXWindows answers success with an empty list for windows on a Space that is not shown. CG optionAll and SkyLight still see them, with stable IDs.

- timestamp: 2026-10-27T01:25Z
  checked: VM, Space 41 shown, spaceprobe
  found: AXWindows lists Notes id 150 and Reminders id 693 (same IDs), CG onscreen=on, spaces 41. Notes docks (Ctrl-Opt-Cmd-D); Reminders refuses to shrink below 768 pt (AX set to 360 wide reads back 768), so it cannot dock beside Notes (642 min) on the 1024-pt display; it stays floating on the Space 41 desk. (side note, not this bug)
  implication: repro uses Notes docked + Reminders floating on Space 41.

- timestamp: 2026-10-27T01:31Z
  checked: VM, /tmp/cycle.sh quit: layout.json (a) before quit, (b) after clean quit, (c) 12 s after relaunch, Space 1 shown throughout
  found: (a) Space 41 docked [Notes#150] floating [reminders#693]; (b) identical, session cleanExit true; (c) Space 41 desk key kept, docked [] floating []. Space 1 desk identical in a/b/c. Pane log of the relaunch has only capability/permission lines (the restore path logs nothing on success, only faults).
  implication: the quit write is innocent; the saved Space 41 windows are dropped inside the relaunched session, after the first write (which writes pendingRestore unchanged). Both docked and floating saved windows are dropped.

- timestamp: 2026-10-27T01:30Z
  checked: VM, after the relaunch, showed Space 41 (Ctrl-Right) and read layout.json
  found: Space 41 desk: docked [] floating [Notes#150, reminders#693]. Same windowIDs and pids as before the relaunch.
  implication: identity (windowID/pid/bundleID) survives the relaunch; the windows come back only as NEW floating windows through admit(); the tile is lost. If the saved entries had been kept, the identity would match exactly when the Space is shown.

- timestamp: 2026-10-27T01:33Z
  checked: Arranger.admit / handle(.windowCreated) / LifecycleSync.handle / AXWindowSystem.perform
  found: admit returns early when deskKey(of:) != nil (window already on a desk); LifecycleSync ignores windowCreated; perform drops commands for untracked windows ("window not tracked"); planShown plans only shown desks and keeps lastRequested for present windows on hidden desks.
  implication: a saved window kept dormant in its desk would be re-attached for free by its first windowCreated when its Space is shown (no new admit, no tile change). Only gap: no lastRequested seed for it, so the first plan of its desk sends a setFrame that is dropped while it is untracked and not resent until a correction.

- timestamp: 2026-10-27T01:33Z
  checked: VM, crash-recovery path: /tmp/cycle.sh crash kill (pkill -9 Pane, relaunch)
  found: (b) after SIGKILL: Space 41 entries intact, cleanExit false; (c) after relaunch: session recoveryLaunch true, Space 41 docked [] floating []
  implication: the recovery launch drops them the same way (same reattach call; rescueStranded/showParkedDesktops only touch tracked windows)

- timestamp: 2026-10-27T01:40Z
  checked: headless probe test (temporary Tests/PaneEngineTests/ZZG038ProbeTests.swift, deleted): session 1 on one fake (window 1 on Space 1, window 3 on Space 2, both docked, back to Space 1); relaunch on a NEW Harness/FakeWindowSystem with the same windows, showSpace(1, notifies: false), refreshAll, .restore(saved), .inventory
  found: relaunch inventory ids [1]; LayoutRestore.reattach removed [3]; Space 2 desk docked [] floating []; after switchDisplay to 2: docked [] floating [3] (frame = its old tile). Two expectations fail. ArrangerMultiDeskRestoreTests passes in the same run.
  implication: deterministic headless repro of the VM symptom, including the "comes back floating" detail

- timestamp: 2026-10-27T01:42Z
  checked: same probe with a throwaway one-line patch in LayoutRestore.reattach skipping window 3 (reverted; git diff clean)
  found: removed []; Space 2 docked [3] after restore; showing Space 2 sends one setFrame for 3 (its tile, no lastRequested seed) and ends docked [3], world == saved; test passes
  implication: keeping the saved entry dormant is sufficient for re-attachment; admit/LifecycleSync need no change. The unseeded lastRequested is a detail for the fix (live, that first setFrame is dropped as "window not tracked" and then not resent)

- timestamp: 2026-10-27T01:44Z
  checked: VM min-size-hints.json
  found: a com.apple.reminders 768x692 entry appeared during this session (my Reminders dock attempt on build 1004, which predates CR-02). Removed with Pane quit; backup /tmp/hints-g038-backup.json in the guest
  implication: unrelated to G-03-8; matches the CR-02 fix already at HEAD

## Resolution

root_cause: "AND of two facts. (1) macOS AX: kAXWindowsAttribute lists only the windows on the Space currently shown (VM: AXWindows success, count 0, for Notes/Reminders whose windows 150/693 are on Space 41, while CG optionAll and SkyLight still report them). WindowTracker.ingest creates a window only from an AXWindows entry, so a freshly launched AXWindowSystem has never tracked any window on a hidden Space. (2) Arranger.process(.inventory) runs LayoutRestore.reattach exactly once, at the first complete inventory, and reattach closes (World.apply(.closed)) every saved window whose identity is not tracked. So every docked or floating window of every desk whose Space is not shown at launch is deleted from the World; the desk key survives, empty, and the next save writes it. Same on normal, recovery and crash-loop launches. Not caught because ArrangerMultiDeskRestoreTests relaunches only the Arranger and reuses the FakeWindowSystem, whose tracker still knows the hidden windows from session 1."
fix: ""
verification: ""
files_changed: []
