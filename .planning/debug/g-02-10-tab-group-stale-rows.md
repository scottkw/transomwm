---
status: diagnosed
trigger: "g-02-10-tab-group-stale-rows: A native tab group is one tracked window. New tabs, tab switches and Cmd-W change its title and tab count, but never add or leave extra rows."
created: 2026-10-27T20:00:00-05:00
updated: 2026-10-27T20:45:00-05:00
audit_acknowledged:
  milestone: v0.9.0
  at: 2026-11-08
  status: diagnosed
---

## Current Focus

bug_class: Bohrbug. It is deterministic given the CG bounds the OS reports. A single Cmd-T reproduces it every time, and no quick sequence is needed.
hypothesis: CONFIRMED (H1). TabGroupTracker treats a window as a hidden tab only when its CG bounds equal the shown tab's AX frame within 1 pt. On macOS 15.7.7 a hidden tab keeps its CG bounds from the moment it was ordered out, and AppKit gives it the group's frame only when it is shown again. So whenever the group's frame differs from the previously shown tab's last frame, the newly shown tab cannot find that tab, and the old tracked identity stays forever.
test: done. E1 reproduced it (Terminal Cmd-N then Cmd-T). E2 healed it by showing the stale tab again, so its bounds matched. E3 stayed correct (Finder Cmd-T, matching bounds). E4 reproduced the Finder variant (resize the shown tab, then Cmd-T).
expecting: n/a
next_action: none (goal find_root_cause_only). Hand back to the caller for a gap plan.

reasoning_checkpoint:
  hypothesis: "Extra rows appear because TabGroupTracker.update finds the previously shown tab (the Cmd-T opener, or the group's last shown tab) only through `slot`. `slot` holds offscreen layer-0 CG entries whose bounds equal the new shown tab's AX frame within 1 pt. On macOS 15.7.7 the old tab's CG bounds are its frame from when it went hidden, so they differ whenever the group frame changed in between. Then no opener, join or handoff applies, the new tab founds its own group, and the old identity is never folded or closed, because CloseRule maps 'valid, unlisted, in CG' to noChange."
  confirming_evidence:
    - "E1: Cmd-N gave 319 at 585x371. Cmd-T gave 321 at 585x399, with 319 hidden at 585x371. Transom then showed rows 319 (no tabs) and 321 (2 tabs): 18 tracked vs 17 real."
    - "E2: Ctrl-Shift-Tab showed 319. AppKit resized it to 585x399, and 321 went hidden at 585x399, which matches. The join rule fired, 319 was folded, and the count went back to 17."
    - "E3: Finder Cmd-T on the 4-tab group (new tab 332 at the same 1000x312) and Finder Cmd-N then Cmd-T (333 and 334, both 1000x312) both stayed one row per group."
    - "E4: Finder group 333/334. Resizing the shown tab 334 to 284 left hidden 333 at 312. Cmd-T created 339 at 312 while 334 went hidden at 284. Transom then showed a stale '333 (2 tabs)' and '339 (3 tabs)': 19 tracked vs 18 real. This is the UAT's '#20 (2 tabs)' + '#213 (4 tabs)' pattern."
    - "The UAT's leftover CG bounds: Terminal #206 220,62 585x371 (the 80x24 Cmd-N frame from before the tab bar) and Finder #20 1000x284, while their groups were 357 and 312 tall."
  falsification_test: "If a Cmd-T or a switch in which the old tab's CG bounds differ by more than 1 pt still left one row, or if one where they match left two rows, H1 would be wrong. E1-E4 covered both cases and each came out as predicted."
  fix_rationale: "The tracker must link the new shown tab to the tab shown just before it on evidence the OS keeps current: that tab left AXWindows in the same refresh the new tab appeared, it is offscreen but still in the CG list, it is not on a known different Space, and the AXTabs count fits. It should not rely on CG bounds, which AppKit does not update for hidden tabs."
  blind_spots: "Which AppKit rule decides a new tab's frame (Finder used the hidden sibling's 312 rather than the shown tab's 284) is inferred from one run. Safari has no AXTabGroup, so it is not affected. The Cmd-W follow path with a non-member next tab was reasoned through, not run live. Behaviour on macOS 26/27 was not checked. The host may sync hidden-tab bounds differently, which would explain why the 02-10 premise looked true there."
  candidate_causes:
    - "code: TabGroupTracker's exact-bounds slot (1 pt) is the only evidence for opener, join and handoff. CONFIRMED."
    - "environment: macOS 15.7.7 AppKit leaves a hidden tab's window-server bounds stale. Terminal grows the window by 28 pt for the tab bar on the first Cmd-T; Finder creates a new tab at a sibling's frame rather than the resized group frame. CONFIRMED as the trigger."
    - "code: CloseRule keeps a valid, unlisted window that is still in the CG list (noChange), and `folded` needs a slot match too, so a misattributed identity never self-corrects. CONFIRMED as the reason the row persists."
    - "timing/code: quick Cmd-T sequences (CR-01/WR-01 races). ELIMINATED: E1 reproduces with 2 s between single key presses."
    - "data: wrong window IDs from the AXWindowID lookup or frame fallback. ELIMINATED: the lookup is available and the IDs match axtabs and CG exactly."
  and_gate: "Yes, two conditions must hold together. (1) The bounds slot misses the old tab, which needs the OS frame divergence plus the 1 pt rule. (2) No rule ever retires the leftover identity: CloseRule returns noChange for valid, unlisted, in-CG windows, folding needs the same slot match, and group leaders are never folded. Either one alone gives no permanent extra row. A match fixes (1), and E2 shows that a later match fixes (2)."

## Symptoms

expected: Each native tab group, in Finder or Terminal, is one row in Tracked Windows and one window in Transom's count. When a new tab is shown, its CGWindowID changes, and the row follows that change instead of multiplying.
actual: In the live VM run, Transom reported "Tracking 15 windows" while 13 existed (AX and CGWindowList agree on 13). Finder had two rows for one group: a stale #20 ("2 tabs", the group's earlier shown-tab window) and #213 ("4 tabs"), while the real shown tab was #214. The real windows were #214 (4 tabs) plus #14, #17 and #19. Terminal had three rows: #203, a stale #206 (no tabs, frame 220,62 585x371) and #208 ("4 tabs"), while the real windows were #219 (the 4-tab group's shown tab) and #203. The extra rows did not clear after a minute. After a relaunch of Transom Debug the rows were correct (Finder #214 with 4 tabs, Terminal #219 with 4 tabs and #203).
errors: none seen
reproduction: Tart VM pane-test (macOS 15.7.7), Transom Debug running and granted. 1) Make each app frontmost (open -a Terminal / Safari / Finder); in Terminal press Cmd-N first; then press Cmd-T twice. 2) In Terminal, press Cmd-T then immediately Ctrl-Shift-Tab, twice. 3) Press Cmd-W. 4) Compare the menu header and Debug > Show Tracked Windows with /tmp/axtabs Terminal Finder and /tmp/cglist.
started: First live run of Phase 2 UAT test 10 (2026-10-27).

## Eliminated

- hypothesis: The extra rows come from quick Cmd-T sequences, the CR-01/WR-01 races (two tab actions in one refresh, or a sweep's CG list taken before the AX read)
  evidence: E1 reproduces with one Cmd-T, 2 s after Cmd-N, with nothing else in the refresh interval. The UAT's Ctrl-Shift-Tab steps are not needed.
  timestamp: 2026-10-27T20:26Z

- hypothesis: Wrong window IDs from the private AXWindowID lookup or the frame fallback
  evidence: The Debug menu shows "Window ID lookup: available". Every ID in Tracked Windows (319, 321, 333, 339, 214) is a real CG ID that matches /tmp/axtabs and /tmp/cgall.
  timestamp: 2026-10-27T20:26Z

- hypothesis: Space data refuses the rebind (mayRebind / differ)
  evidence: All the windows are on the one VM Space. E2 healed under the same Space data as soon as the bounds matched, so Spaces were not what refused.
  timestamp: 2026-10-27T20:27Z

- hypothesis: The initial sweep handles tab groups wrongly
  evidence: After a relaunch the rows are correct. Only windows listed in AXWindows are ever tracked, and hidden tabs are never listed, so a sweep cannot create these rows. Only a window tracked while it was shown can become a stale row.
  timestamp: 2026-10-27T20:21Z

## Evidence

- timestamp: 2026-10-27T20:15Z
  checked: knowledge base (.planning/debug/knowledge-base.md)
  found: The only entry is safari-toolbar-drag-no-dock (drag classifier). Nothing matches tab groups.
  implication: No known-pattern candidate.

- timestamp: 2026-10-27T20:18Z
  checked: Sources/TransomEngine/TabGroupTracker.swift, WindowTracker.swift, CloseRule.swift; TrackedWindowsModel.swift
  found: |
    (a) A group's hidden tabs are recognised only as the pid's offscreen layer-0 CG entries whose bounds equal the listed shown tab's AX frame within boundsTolerance = 1.0 pt (`slot` filter at line 125, `matches` at line 255). Every way the group follows its shown tab depends on that slot:
    - `candidates` (line 132)
    - the Cmd-T `opener` (line 136, which needs `candidates.contains`)
    - the join rule (lines 144-149, which needs `!members.isDisjoint(with: candidates)`)
    - the orphan handoff (lines 152-158, which compares the previous CG bounds to `group.frame` with `matches`)
    The one exception is `index = list.firstIndex { $0.members.contains(v.id) }` (line 137), for a listed window that is already a known member. Members are reset at every rebind to the slot matches plus v (line 178), so a member with stale bounds drops out.
    (b) A tracked identity whose visibleMemberID has left AXWindows but is still in the CG list is decided by CloseRule as `.valid(listed: false)` plus inCG, which gives `.noChange` (hidden tab / other Space). It is never removed.
    (c) `folded` (line 203) covers only tracked standalone windows that became members of another group. Group leaders are never folded, and `standalone` (line 102) leaves out every group leader, so an old group's leader can never be an `opener` either.
    (d) The Tracked Windows ID column shows the identity's windowID (the leader), not visibleMemberID. So "#213 (4 tabs) while the shown tab is #214" is by design (the 02-10 decision) and not a bug in itself.
  implication: If a hidden tab's CG bounds ever differ from the shown tab's AX frame by more than 1 pt, the next shown tab cannot find its group, and CloseRule keeps the old identity forever.

- timestamp: 2026-10-27T20:21Z
  checked: In the live VM, every CG entry (optionAll) of Finder (pid 374) and Terminal (pid 1692), read with a new helper /tmp/cgall, plus /tmp/axtabs. Transom Debug pid 2077 had been relaunched after the UAT run, and its rows were correct.
  found: |
    Terminal group (AX: shown 219, 4 tabs):
    - 219 onscreen at 220,33 585x357
    - hidden 216 at 220,33 585x329
    - hidden 208 at 220,33 585x329
    - hidden 206 at 220,62 585x371
    None of the hidden tabs matches the shown frame within 1 pt.
    Finder group (AX: shown 214, 4 tabs):
    - 214 onscreen at 12,37 1000x312
    - hidden 213 at 12,37 1000x312 (matches)
    - hidden 20 at 12,37 1000x284 (28 pt shorter)
    The 28 pt is the tab bar: Terminal 203 with no tab bar is 21 rows at 329 pt, and 219 with the tab bar is 21 rows at 357 pt.
  implication: TabGroupTracker assumes hidden tabs share the shown tab's bounds, and that is false on macOS 15.7.7. The UAT's stale rows are exactly the windows whose bounds do not match: Finder #20 and Terminal #206.

- timestamp: 2026-10-27T20:26Z
  checked: E1, a live repro in the VM (Transom Debug pid 2077, AXWindowID and Spaces available). Baseline Tracked Windows had 16 rows for 16 real windows. Then `open -a Terminal`, Cmd-N, 2 s, cgall; Cmd-T, 2 s, cgall + axtabs; then Debug > Show Tracked Windows.
  found: |
    - Cmd-N gave 319 onscreen at 365,207 585x371 (80x24, no tabs).
    - Cmd-T gave 321 onscreen at 365,207 585x399 (AXTabs 2), with 319 offscreen at 365,207 585x371. Terminal grows the window downward by the 28 pt tab bar for the new tab only, and the opener stays hidden at its old frame.
    - Tracked Windows showed "18 windows" (17 real). The Terminal rows were 203, 219 (4 tabs), 319 (no tabs) and 321 (2 tabs).
  implication: G-02-10 reproduces deterministically with one Cmd-T on a standalone Terminal window. The opener was not in the slot, so `opener` was nil, and 321 founded its own group. 319 stays a standalone tracked window that CloseRule keeps forever. This matches the UAT's stale #206, which had the same 80x24 frame from before the tab bar, beside the #208 group.

- timestamp: 2026-10-27T20:27Z
  checked: E2, the differential. In the same Terminal group, Ctrl-Shift-Tab showed 319, then a 10 s wait.
  found: AppKit resized 319 to 365,207 585x399 as it was shown, and 321 went hidden at 585x399, which matches. Tracked Windows went back to "17 windows". The Terminal rows were 203, 219 (4 tabs) and 321 (2 tabs). 319 was folded into group 321, as the join and fold rules intend.
  implication: Bounds matching is the deciding variable. The same code under the same Spaces and timing works once the old tab's CG bounds equal the new shown frame. The stale row heals only if the user happens to show that exact tab again.

- timestamp: 2026-10-27T20:28Z
  checked: E3, Finder. First Cmd-T on the existing 4-tab group (shown 214). Then Cmd-N followed by Cmd-T.
  found: |
    - Cmd-T on the group: new tab 332 at 12,37 1000x312, the same frame as 214. Tracked Windows kept one row, "214 (5 tabs)".
    - Cmd-N then Cmd-T: 333 at 14,66 1000x312, then 334 at the same frame with 333 hidden at 1000x312. Finder does not grow the window for the tab bar. Tracked Windows showed one row, "333 (2 tabs)", so the opener rule worked.
    - The count was 18 tracked for 18 real windows.
  implication: When the bounds match, every rule works, including the opener and the join. So the defect is the bounds premise, not the rule logic.

- timestamp: 2026-10-27T20:29Z
  checked: E4, the Finder variant. /tmp/axset resized the shown tab 334 to 14,66 1000x284, then 2 s, then Cmd-T.
  found: |
    - After the resize, hidden 333 stayed at 1000x312. AppKit does not resize hidden tabs with the group.
    - Cmd-T created 339 at 14,66 1000x312 (it took the hidden sibling's frame, not the shown tab's 284), and 334 went hidden at 284.
    - Tracked Windows showed "19 windows" (18 real), with Finder rows "333 (2 tabs)" (stale group) and "339 (3 tabs)".
  implication: |
    This is the UAT's Finder pattern: a stale group leader with its last tab count ("#20 (2 tabs)") beside the new group ("#213 (4 tabs)"). The mechanism, from the code:
    - The resize refresh rebinds group 333 with members = slot matches plus v = {334}, so 333 drops out of the members.
    - At Cmd-T, the candidates are {333}. They are disjoint from group 333's members {334}, so the join rule fails.
    - 333 is a group leader, not a standalone, so it cannot be the opener.
    - 339 founds group 339, taking 333 as a hidden member, and group 333 is left with shown 334 forever.
    Any frame change of a group (the user, /tmp/axset, or Transom's own frame writes in Phase 3) followed by Cmd-T can trigger it.

- timestamp: 2026-10-27T20:31Z
  checked: Sources/TransomTestSupport/FakeWindowSystem.swift, tabGroup / newTab / selectTab (lines 146-180)
  found: The fake opens every tab "in its frame" (`host.frame`). All tabs share one `frame`, and a hidden tab's CG entry always carries the group's current frame.
  implication: No scenario or tracker test can show a hidden tab with stale bounds. That is why 02-10/02-14/02-17 and the CR-01/WR-01 probes all passed while the live OS breaks the premise.

## Resolution

root_cause: |
  TabGroupTracker (Sources/TransomEngine/TabGroupTracker.swift) treats a window as a hidden tab of a listed window only when it is an offscreen layer-0 CG entry whose bounds equal the listed tab's AX frame within 1 pt (`slot`, line 125; `matches`, boundsTolerance 1.0). Every rule that makes a group follow a new shown tab depends on that slot: the Cmd-T opener (line 136), the join (lines 144-149) and the orphan handoff (lines 152-158). The fold of a standalone window (`folded`, line 203) does too.

  On macOS 15.7.7, a hidden native tab keeps the window-server bounds it had when it was ordered out. AppKit applies the group's frame to a tab only when it shows it. So the previously shown tab misses the slot whenever the group frame differs from that tab's last frame:
  - (a) Terminal's first Cmd-T grows the new tab by the 28 pt tab bar, while the opener stays hidden at its pre-tab-bar frame.
  - (b) After the shown tab is resized, Finder creates the next tab at a hidden sibling's frame, and the resized tab goes hidden at its new size.
  The new shown tab then founds its own group under its own identity. The old identity (a standalone opener, or the old group's leader) is never retired. CloseRule decides "AX valid, unlisted, still in the CG list" as noChange (hidden tab / other Space). Group leaders are never folded, and are never `standalone`, so they cannot be an opener. A standalone is folded only through the same bounds slot.

  Result: one extra, permanent row per mismatch. It heals only if that exact stale tab is shown again (E2) or Transom relaunches, because the initial sweep tracks only listed windows. Contributing cause: FakeWindowSystem models every hidden tab at the group's current frame, so the tests could never see this.
fix: |
  Not applied (find_root_cause_only). Suggested direction:
  1. In TabGroupTracker.update, link the new shown tab to the tab shown just before it on temporal evidence instead of CG bounds. A window qualifies as the hand-over tab when all of these hold:
     - It was listed at this pid's last update (`lastListed`), or it is a group's `shown`.
     - It is unlisted now.
     - It is still in the CG list, offscreen, and not AX-invalid.
     - It is not on a known different Space (`differ`).
     - Its count fits: for a brand-new v (`isNew`), the opener rule; otherwise, a group whose `shown` went hidden this refresh.
     Concretely: (i) let `opener` also match a standalone window that was listed last time and is now offscreen and unlisted, regardless of bounds, when `isNew` and v.tabCount >= 2. (ii) Let the join rule also match a group whose `shown` meets those conditions, and allow a group leader as well as `standalone`, so a stale group like Finder #20 is rebound instead of a second group being founded. Keep the bounds slot only as a tie-break and for picking the other hidden members. Pinning tabCount to AXTabs already makes membership size irrelevant to the row.
  2. If this rule can still be ambiguous (two windows of one pid going hidden in one refresh), fall back to the nearest origin and width (both cases kept x, y and width; only the height changed).
  3. Add the missing fidelity to FakeWindowSystem: `newTab(_:in:frame:)` with an optional new-tab frame, and hidden tabs that keep their last shown frame when the group is resized. Then add scenario tests for E1 (Terminal: opener hidden 28 pt shorter, one row, created == [opener]) and E4 (Finder: the shown tab resized, then Cmd-T at a sibling's frame, one row, nothing destroyed). Re-run UAT 10 and then 11, which is blocked on this gap.
  Optional and separate: Tracked Windows could show visibleMemberID next to the identity, since "#213 while the shown tab is #214" read as a bug in the UAT.
verification: |
  Not applicable (diagnose only). The diagnosis was verified live in the VM. E1 reproduced it on demand, E2 healed it by making the bounds match, E3 was correct with matching bounds, and E4 reproduced the Finder stale-group variant. Each matched its prediction.
files_changed: []
