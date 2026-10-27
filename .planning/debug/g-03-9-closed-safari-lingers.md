---
status: diagnosed
trigger: "G-03-9: a closed floating Safari window (2174) stays in layout.json as Safari#2174:present on the Space 1 desk; menu says Tracking 10 windows in 4 apps (9 visible + 2174); Safari keeps an optionAll CG entry id 2174 bounds 12 168 574 224 with no Space; AX lists only 669; 03-23's dormant rule keeps it after clean and kill -9 relaunches. Closed TextEdit windows are removed immediately."
created: 2026-10-26T00:00:00Z
updated: 2026-10-27T02:55:00Z
goal: find_root_cause_only
---

## Current Focus

bug_class: Bohrbug (deterministic given the OS fact: CloseRule never closes while the ID is in the CG list)
hypothesis: In the running session CloseRule.decide requires the window ID to be ABSENT from the CG optionAll list before any close (both the AX -25202 row and the terminated row). Safari keeps the closed window's WindowServer window (layer 0, offscreen, no Space) in optionAll, so 2174 is decided .recheck (invalid element) or .noChange (valid unlisted) forever and stays tracked + present. 03-23's isAlive then keeps it dormant across relaunches because it tests the same optionAll presence.
test: headless FakeWindowSystem scenario: window closed (AX invalid, unlisted) but its CG entry stays (inCGList true, no Space)
expecting: today the window is never destroyed (test fails); TextEdit-style close (CG entry leaves) passes
next_action: none (goal find_root_cause_only); hand back ROOT CAUSE FOUND. VM STOPPED under RULE 0 (unexplained VM state change, Evidence 02:45); lock .build/pane-vm.lock deliberately left held.

reasoning_checkpoint:
  hypothesis: "2174 stays tracked and present because CloseRule.decide never returns .closed while the window ID is in the CG optionAll list, and Safari keeps a layer-0, offscreen, no-Space WindowServer entry for the closed window for minutes; LayoutRestore.isAlive uses the same optionAll presence, so 03-23 keeps the ghost dormant across relaunches"
  confirming_evidence:
    - "CloseRule table: every .closed row needs inCGList == false (alive+invalidElement+absent, terminated+absent); present gives .recheck (invalid) or .noChange (valid unlisted)"
    - "VM spaceprobe 02:41 guest (well after the UAT close): Safari AXWindows [669]; CG optionAll layer-0 id 2174 bounds 12 168 574 224 off, SkyLight spaces empty"
    - "Headless probe (fake, 20 refreshes x 5 s): ghost (unlisted, CG kept, no Space) never destroyed and stays .present for both AX answers (invalid and still-valid cached element); isAlive(ghost) == true"
    - "git: CloseRule/WindowTracker/AXAppThread close path unchanged since 02-09 / CR-02, so pre-03-23 builds keep the ghost in the running session too (they only dropped it at relaunch via reattach)"
  falsification_test: "If the tracker closed the ghost (destroyed event) while its CG entry remained, or the ghost's CG entry had a Space / left optionAll at close time like TextEdit's, the hypothesis would be wrong. Headless probe shows no destroy; VM shows the entry lingering with no Space"
  fix_rationale: "Treat a layer-0 CG entry whose SkyLight Spaces are known and empty as not-alive/absent (for isAlive and for CloseRule's CG fact) so the two-source rule and the dormant rule stop counting Safari's ghost as a live window"
  blind_spots: "Which AX answer the ghost's cached element gives (invalid -25202 vs still valid) is not VM-verified (probe /tmp/axghost prepared, not run); what Spaces SkyLight reports for minimized windows, Cmd-H hidden apps' windows and hidden tabs (all candidates for 'no Space'); whether the normal WindowServer close lag keeps the Space; why Safari releases the entry (it was gone by 02:44 after open -a Safari + an injected Cmd-N)"
  candidate_causes:
    - "code: CloseRule requires CG absence for any close (confirmed)"
    - "code: LayoutRestore.isAlive/liveWindows count any layer-0 optionAll entry as alive (confirmed)"
    - "environment/app: Safari keeps the closed window's WindowServer window (layer 0, offscreen, no Space) for minutes (confirmed in VM)"
    - "code: AX destroyed notification not delivered (eliminated as a cause: hints only schedule a refresh, never decide a close)"
  and_gate: "yes: needs (a) Safari's lingering no-Space CG entry AND (b) CloseRule/isAlive treating any optionAll layer-0 entry as alive. TextEdit has (b) but not (a), so its closes work"

## Symptoms

expected: closing a floating Safari window removes it from the World/layout.json and the tracked count drops (as for TextEdit)
actual: VM Pane 0.3.7/1005 (HEAD): after Cmd-W on new floating Safari window 2174, layout.json still lists Safari#2174:present on the Space 1 desk; menu "Tracking 10 windows in 4 apps" (9 visible + 2174). Safari keeps a CGWindowList optionAll entry id 2174 bounds 12 168 574 224 with NO Space (SkyLight none); Safari AX windows = [669]. After a clean relaunch and a kill -9 relaunch, 2174 stays dormant on the Space 1 desk (03-23 rule: layer-0 CG entry with same windowID+pid). TextEdit closes are removed immediately.
errors: none reported
reproduction: Tart VM pane-test; open -a Safari; Cmd-N (new floating window); Cmd-W; inspect layout.json and menu count
started: observed in 03 VM UAT re-run after 03-23 (b6103b5). Unknown whether pre-03-23 builds kept 2174 present in the running session.

## Eliminated

- hypothesis: the AX destroyed notification is not delivered for Safari, so the close is never noticed
  evidence: AXWindowSystem.handle(_:) only schedules a refresh for any hint; closes are decided only by CloseRule in WindowTracker.decide on every refresh/5 s sweep. Even with the notification, CloseRule needs the CG entry gone. Headless probe with 20 refreshes never closes the ghost
  timestamp: 2026-10-27T02:50Z

- hypothesis: 03-23 broke runtime close detection (the running session would have closed it before 03-23)
  evidence: git log: CloseRule.swift last changed in 02-09; WindowTracker close path in 02-09 (CR-02 touched only minimums); AXAppThread.observe untouched; 03-23 touched only restore/inventory/liveWindows. Pre-03-23 builds keep the ghost tracked+present in the running session the same way; they only dropped it at the next relaunch (reattach closed untracked windows)
  timestamp: 2026-10-27T02:52Z

## Evidence

- timestamp: 2026-10-27T02:30Z
  checked: Sources/PaneEngine/CloseRule.swift, WindowTracker.decide/ingest, AXWindowSystem.sweep/refresh/ingest/handle, AXAppThread.observe, CGWindowList.snapshot
  found: a tracked window is declared closed ONLY by WindowTracker.decide -> CloseRule.decide == .closed -> remove + .windowDestroyed (LifecycleSync then closes it in the World). Every .closed row requires inCGList == false; inCG is built from CGWindowList.snapshot() = CGWindowListCopyWindowInfo([.optionAll]) (on- and offscreen, any Space or none). alive+invalidElement+present -> .recheck (8 quick rechecks at 250 ms, then every 5 s sweep, forever); alive+valid unlisted+present -> .noChange ("hidden tab, other Space"). AX hints (incl. UIElementDestroyed) only schedule a refresh.
  implication: any window whose app keeps an optionAll entry after closing is never closed by the running session, whatever AX says.

- timestamp: 2026-10-27T02:41Z (guest)
  checked: VM /tmp/spaceprobe Safari (Pane 0.3.7/1005 running; layout.json had been restored by the UAT cleanup, so 2174 not in it)
  found: Safari pid 911 AXWindows [669]; CG optionAll layer 0: 2174 bounds 12 168 574 224 off spaces EMPTY; 669 on spaces 1; also 1332-1335 bounds 0 0 1024 24 off spaces EMPTY (never AX-listed). The UAT closed 2174 well before this (UAT log written 21:39 host = 02:39 guest)
  implication: Safari keeps the closed window's WindowServer window as layer 0, offscreen, NO Space for minutes. g-03-8 shows real hidden-Space windows report their Space (41) -- the Space set separates a hidden-Space window from this ghost; kCGWindowIsOnscreen does NOT (hidden-Space Notes 150 was also off).

- timestamp: 2026-10-27T02:44Z (guest)
  checked: VM, after `open -a Safari` (osascript System Events frontmost query timed out -1712) and an injx Cmd-N; spaceprobe Safari
  found: CG entry 2174 GONE from optionAll; no new Safari window was created
  implication: the ghost is not permanent; Safari released it at some point between 02:41 and 02:44 (likely on its activation / next event-loop work). Mechanism not established.

- timestamp: 2026-10-27T02:45Z (guest)
  checked: VM after a second injx Cmd-N (`key m 45`), allframes, layout.json, VNC screenshot
  found: UNEXPLAINED STATE: a new Finder window 2252 exists; every app window is minimized (Dock shows them; allframes all 'off'; layout floating entries now ':absent', finder#2252 floating present); System Settings is frontmost on Wallpaper. No other ssh/injx/osascript/VNC driver found in the guest. Two Cmd-N keystrokes cannot explain minimize-all + Wallpaper settings.
  implication: RULE 0 -- VM work stopped, no recovery attempted; lock .build/pane-vm.lock left held so no other agent drives the VM until the user looks. axghost probe copied to guest /tmp/axghost but never run.

- timestamp: 2026-10-27T02:50Z
  checked: headless probe (temporary Tests/PaneEngineTests/ZZG039ProbeTests.swift, moved out of the tree to scratchpad/g39/): Safari-like fake, windows 669 and 2174 on Space 1; 2174 becomes unlisted, CG entry kept, onScreen false, space nil; cached element invalid OR still valid; 20 x (advance 5 s + refreshAll). Plus LayoutRestore.isAlive on a layer-0 offscreen entry
  found: both cases: destroyed [] , tracked state present, liveWindows [669, 2174]; isAlive(ghost) == true. 2 tests, 5 failed expectations.
  implication: deterministic headless repro of the running-session half and the relaunch half.

- timestamp: 2026-10-27T02:52Z
  checked: Planner.plan (desktopMinimum), Arranger.minimums, LayoutRestore.reattach, Arranger planShown (03-23)
  found: running session: the ghost is a tracked, present floater, so its learnedMinimum (Safari bundle hint, seeded at creation) joins the Desktop tile minimum (per-axis max over present floaters' minimums) and it gets clamp setFrames like any floater overlapping a tile. Docked windows still win (G-03-6 drop loop), so it can never make a docked window unfit. After relaunch (dormant): not in Arranger.windows, so no minimum and planShown sends it nothing; only layout.json/World bookkeeping.
  implication: severity: no overlap/tiling breakage; a bounded layout effect in the running session only when the ghost's minimum exceeds every other present floater's on that desk (Desktop tile kept >= 574x? when room exists); otherwise counts/bookkeeping.

## Resolution

root_cause: "AND of two facts. (1) Safari (unlike TextEdit) keeps a closed window's WindowServer window in CGWindowListCopyWindowInfo(optionAll) for minutes: layer 0, offscreen, SkyLight Spaces empty (VM: 2174 bounds 12 168 574 224 off, spaces none, AXWindows [669]). (2) Pane counts ANY optionAll entry with the ID as 'still open': CloseRule.decide closes only when inCGList == false (alive+invalidElement+present -> .recheck; valid-unlisted+present -> .noChange), and 03-23's LayoutRestore.isAlive / AXWindowSystem.liveWindows keep any layer-0 entry with the same ID+pid. So in the running session WindowTracker never emits windowDestroyed for 2174 (tracked, present, counted in the menu, kept in the Space 1 desk), and after a clean or kill -9 relaunch reattach keeps it dormant. The AX destroyed notification is irrelevant: hints only schedule a refresh. The close path predates 03-23 (02-09), so pre-03-23 builds kept it present in the running session too and only dropped it at relaunch."
fix: ""
verification: ""
files_changed: []
