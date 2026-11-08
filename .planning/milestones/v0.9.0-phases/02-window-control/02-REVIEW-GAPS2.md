---
phase: 02-window-control
reviewed: 2026-10-27T22:34:05Z
depth: standard
scope: "gap closure 02-18 (G-02-1) and 02-19 (G-02-10), git diff a2e3e53~3..e45cd29"
files_reviewed: 8
files_reviewed_list:
  - Sources/TransomEngine/TabGroupTracker.swift
  - Sources/TransomMac/Permission/PermissionController.swift
  - Sources/TransomMac/Permission/SetupWindowController.swift
  - Sources/TransomTestSupport/FakeWindowSystem.swift
  - Tests/TransomEngineTests/FakeWindowSystemTests.swift
  - Tests/TransomEngineTests/TabGroupTrackerTests.swift
  - Tests/TransomEngineTests/TabScenarioTests.swift
  - Tests/TransomMacTests/SetupWindowTests.swift
findings:
  critical: 1
  warning: 3
  info: 6
  total: 10
status: issues_found
---

# Phase 2: Code Review Report (gap closure 02-18, 02-19)

**Reviewed:** 2026-10-27T22:34:05Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

I reviewed the 02-18 setup-window sizing fix (G-02-1) and the 02-19 timing links in TabGroupTracker (G-02-10), and read WindowTracker, CloseRule and AXSnapshotReader for context.

**02-18 is sound.** `setContentSize(fittingSize)` runs once, inside `makeWindow()`, before the window is ever shown. Every later state change goes through `.preferredContentSize`, and both paths ask for the same size, so they cannot fight. `overrideStateForTesting` has no caller in `Sources/`, and no `Sources/` target uses `@testable`, so no production path can reach it. Only Info items remain.

**02-19 has one regression.** The timing opener runs *before* the room-rule join and the timing join, and it only considers standalone windows. So a Cmd-T in an existing tab group can be handed to any same-app standalone window that "went hidden" in the same refresh. This happens even when the group's shown tab sits exactly in the new tab's slot, a case that worked before this plan. One way to trigger it needs no user action on the other window: a minimized window whose AX read returns -25204. The read failure drops the window out of `visible`, so `wentHidden` reports it as just hidden. The resulting state does not heal: the real group window ends up untracked, and a stale row stays.

Two G-02-10 paths still depend on bounds:
- the orphan handoff (Cmd-W on a group whose only known member is its shown tab), which destroys and recreates the identity;
- the stale-sweep (WR-01) Cmd-T, which still leaves a permanent extra row.

**How this was checked.** I wrote headless probes in a scratch export of e45cd29. They live at `/private/tmp/claude-501/-Users-ken-dev-transomwm/fb58eaa5-8cd9-4b77-941d-64fed871017b/scratchpad/repo/Tests/TransomEngineTests/ReviewProbeTests.swift` and are not committed. I ran them against both the 02-19 tracker and the a2e3e53 (pre-fix) tracker, with `env -u TRANSOM_LIVE swift test`. Nothing was launched. The results are cited inline below.

**The questions in the brief:**
- **Can the timing link merge, destroy or hold?** It can merge or misattribute (CR-01, WR-01). It can hold a hijacked identity forever (CR-01). Destroying comes only through the unchanged orphan-handoff path (WR-02).
- **Space data off, blind switch:** the blind-switch refusal works (`wentHidden` is false when `blindSwitch` holds). With Space data *on*, a switch is not refused when either Space is unknown (IN-04).
- **Ordering and performance:** the ordering defect is CR-01. Performance is fine at real window counts (IN-06).
- **`overrideStateForTesting` from production:** not reachable today (IN-01).
- **`setContentSize` vs `.preferredContentSize`:** no fight found. `makeWindow()` being internal and non-idempotent is IN-02.

## Critical Issues

### CR-01: The timing opener preempts the slot and timing joins, so a Cmd-T in a tab group can be handed to an unrelated window (regression)

**File:** `Sources/TransomEngine/TabGroupTracker.swift:156-164` (with `:172`, `:180` and `:234`)

**Issue:**

**The cause.** For a brand-new tab (`isNew`, AXTabs >= 2) whose opener is not in its slot, lines 158-164 pick `opener` from *standalone* windows that `wentHidden`. Both joins only run when `opener == nil`: the room-rule join (line 172) and the timing join (line 180). A Cmd-T inside an existing group never has a slot opener, because the group's shown tab is a leader or member, not `standalone`. So any same-app standalone window W that went hidden in that refresh wins the new tab. This happens whatever W's bounds are, and even when the group's shown tab matches the new tab's slot exactly. `nearest` only ranks the standalone windows against each other; the group never competes. That contradicts the type doc (lines 60-62: "told apart by the slot, then by origin and width").

**Probe P1.** Group B is 20 (shown) and 21, all at `frame`. Standalone W is 10, elsewhere. In one refresh, W goes hidden and Cmd-T in B opens 50 at `frame`.
- 02-19 result: `groupFor[50] == identity(10)`. W's group is {10, 20, 50}, and **window 20 is now a member of both groups**.
- Rows at tracker level: `[[10, 50, 3], [20, 20, 2]]`.
- Pre-fix tracker (a2e3e53): `[[10, 10, 1], [20, 50, 3]]`, which is correct.

**Probe P6, the realistic trigger.** W is *minimized*: listed in AXWindows and offscreen in CG. In the Cmd-T refresh its read returns `.failure(.cannotComplete)`. `AXSnapshotReader.read` produces exactly this for -25204 (`AXSnapshotReader.swift:97`). WindowTracker drops failed reads from `visible` (`WindowTracker.swift:69-72`), so `wentHidden(10)` is true.
- Rows after the refresh: `[[10, 50, 3], [20, 20, 2]]`.
- Once W reads normally again, the state is stable for 8 more refreshes: `[[10, 10, 3], [20, 20, 2]]`.
  - The live group window showing tab 50 has no row at all. Both 10 and 50 resolve to identity 10, and WindowTracker drops the second one (`WindowTracker.swift:115`).
  - W's row claims 3 tabs.
  - B's row 20 is stale forever, because CloseRule gives `noChange` for a valid, unlisted, in-CG window.
- Pre-fix, the same input gives `[[10, 10, 1], [20, 50, 3]]`.

**Why it matters.** This breaks the 02-19 promise ("one tracked identity per tab group through Cmd-T") with no recovery. A Phase 3 tile for identity 10 would drive the wrong window. Space data does not protect against it unless W is *known* to be on another Space; a minimized window on the current Space is not. The existing tests miss it because every timing-opener scenario has no tab group already present.

**Fix:** Let group evidence compete before any standalone is taken by timing. Run the slot join first, and skip the timing opener whenever a group whose shown tab went hidden can take the tab:

```swift
var index = list.firstIndex { $0.members.contains(v.id) }
// ... refusal block unchanged ...
// Slot join first: exact group evidence beats timing.
if index == nil, v.tabCount >= 2, opener == nil {
    index = list.indices.first { i in
        i != refused && list[i].members.count < v.tabCount && !list[i].members.isDisjoint(with: candidates)
            && !Self.differ(shownSpace, list[i].spaces)
    }
}
let groupWentHidden = list.indices.contains { i in
    i != refused && wentHidden(list[i].shown) && list[i].members.count < v.tabCount
        && !Self.differ(space(list[i].shown), shownSpace) && !Self.differ(list[i].spaces, shownSpace)
}
if opener == nil, index == nil, !groupWentHidden, isNew, v.tabCount >= 2 {
    // timing opener (lines 159-163), unchanged
}
```

An alternative is to put the standalone windows that went hidden and the groups' shown tabs that went hidden into one `nearest` call. Add P1 and P6 as tracker-level tests in all three Space modes. Correct the "told apart by the slot" sentence in the type doc.

## Warnings

### WR-01: `wentHidden` reads "missing from `visible`" as "unlisted", but `visible` also drops listed windows whose AX read failed

**File:** `Sources/TransomEngine/TabGroupTracker.swift:120-125`, `:127`; `Sources/TransomEngine/WindowTracker.swift:69-72`

**Issue:** `listedIDs = Set(visible.map(\.id))`. WindowTracker builds `visible` only from listed observations with `.success` reads, a resolved window ID and a frame. So a window that is still listed in AXWindows but timed out (-25204), returned a per-attribute error, or had no ID or frame this refresh counts as unlisted. If it is also offscreen in CG (minimized, or a hidden tab's own group window), `wentHidden` is true. The 02-19 doc comment assumes `wentHidden` means "AppKit just hid this tab".

`canBeHiddenTab` has the same gap. `listedTabCount` lacks the window, so a listed single window that could not be read passes as a possible hidden tab.

CR-01 is the worst consequence. The timing join (line 180) has the same exposure: a minimized group whose shown tab's read fails can be joined by a non-member tabbed window.

**Fix:** Pass in the IDs that are actually listed in AXWindows, whatever the read result, and use them for `listedIDs` and `canBeHiddenTab`. For example, add `listed: Set<UInt32>` to `update`, built in WindowTracker as `Set(app.windows.compactMap { $0.listedInAXWindows ? $0.windowID : nil })`. Then:

```swift
func wentHidden(_ id: UInt32) -> Bool {
    !blindSwitch && wasListed.contains(id) && !listed.contains(id) && inCG.contains(id) && !onScreen.contains(id) && !invalid.contains(id)
}
```

### WR-02: The orphan handoff still needs a bounds match, so Cmd-W in a group first seen with stale hidden tabs destroys and recreates its identity

**File:** `Sources/TransomEngine/TabGroupTracker.swift:189-196` (the `Self.matches(previous.bounds, group.frame)` term at line 193)

**Issue:**

**Where the gap is.** 02-19 moved the opener and the join to timing evidence, but the orphan handoff still compares the next tab's *previous* CG bounds with the group frame. On macOS 15.7.7 those are the stale hidden-tab bounds (debug E2: AppKit gives the tab the group frame only when it shows it).

**How it is reached.** A group seen first with stale hidden tabs has only its shown tab as a member. Every Transom relaunch does that, and relaunching is the recovery path the debug file records (Terminal 219 with 216, 208 and 206 all mismatched). Cmd-W on the shown tab then misses the handoff:
- line 110 empties `members`;
- the next tab founds a fresh group;
- WindowTracker's `.closed` path destroys the old identity (`WindowTracker.swift:362-372`).

**Probe P2T.** The sweep sees 219 (AXTabs 3) with 216 and 208 hidden 28 pt shorter. Cmd-W on 219 shows 216 at the group frame. Events: `windowCreated(219)`, `windowCreated(216)`, `windowDestroyed(219)`. Rows: `[[216, 216, 2]]`.

The row count stays right, but one live window was reported as closed and reopened. Phase 3 would reflow its tile. The new `cmdWInAResizedGroupFollowsTheNextTab` test passes only because every tab there was already a known member. This path predates 02-19, but it has the same root cause, and the 02-19 summary's claim that "Cmd-W ... nothing destroyed" does not hold here.

**Fix:** Pick the handoff by evidence that stays current:
- the group's shown tab left the CG list this refresh;
- v was an offscreen, untracked entry of this pid last refresh;
- v's AXTabs is at most the group's last `tabCount - 1`;
- the Spaces do not differ.

Break ties with `nearest(_:to:)` instead of requiring `matches`. Add a tracker test that seeds a group with stale-bounds hidden tabs on its first update and then closes the shown tab.

### WR-03: A stale sweep CG list combined with a taller first Cmd-T still leaves a permanent extra row

**File:** `Sources/TransomEngine/TabGroupTracker.swift:122-125`, `:158-164`

**Issue:**

**The race.** In the WR-01 race the sweep's CG list predates Cmd-T: the opener is still *onscreen* in it and the new tab is missing. The slot path allows for this (line 153: `staleCG && mayBeOpener`), but the new timing opener requires `!onScreen.contains(id)`, so it finds nothing.

**Why it never heals.** On the next refresh the opener is offscreen, but `wasListed` comes from the stale refresh's AX read, which already lacked the opener. So `wentHidden` and `mayBeOpener` are both false from then on. The new tab founds its own group, and the opener stays a standalone row (CloseRule `noChange`) until that exact tab is shown again. That is the G-02-10 symptom.

**Probe P3T.** Rows `[[10, 10, 1], [40, 40, 2]]` after 4 refreshes, with 2 `windowCreated`. Pre-fix gives the same. The existing `cmdTSeenWithAStaleSweepCGListStaysOneWindow` passes only because its new tab has the opener's bounds.

**Fix:** In the timing opener, accept the stale-list case the way the slot filter does:

```swift
let hidden = standalone.map(\.windowID).filter { id in
    mayBeOpener(id) && canBeHiddenTab(id) && !Self.differ(space(id), shownSpace)
        && (wentHidden(id) || staleCG && !listedIDs.contains(id) && inCG.contains(id) && !invalid.contains(id))
}
```

Add a variant of `cmdTSeenWithAStaleSweepCGListStaysOneWindow` with a 28 pt taller new tab.

## Info

### IN-01: `overrideStateForTesting` is compiled into release builds

**File:** `Sources/TransomMac/Permission/PermissionController.swift:25-29`

**Issue:** It is `internal` and has no caller in `Sources/`, and no `Sources/` target uses `@testable`, so production cannot reach it today. Still, any future TransomMac code could set `.ready` without the reducer, the probe or tracking.

**Fix:** Wrap it in `#if DEBUG ... #endif`. `swift test` builds debug, so `SetupWindowTests` still compiles.

### IN-02: `makeWindow()` is now internal and not idempotent

**File:** `Sources/TransomMac/Permission/SetupWindowController.swift:40-64`

**Issue:** A second call builds a new window, overwrites `self.window` and `permission.setupWindow`, and orphans the first window, which is still delegate-wired. Only `show()` (`window ?? makeWindow()`) guards against this.

**Fix:** Keep the builder `private` and expose `func windowForTesting() -> NSWindow { window ?? makeWindow() }`, or start `makeWindow()` with `if let window { return window }`.

### IN-03: `SetupWindowTests.waitFor` keeps spinning after success, and its 2 s budget may flake

**File:** `Tests/TransomMacTests/SetupWindowTests.swift:48-51`

**Issue:** `for _ in 0..<200 where !condition()` skips the sleep once the condition holds but still runs the loop up to 200 times, recomputing `fittingSize` each time. The 2 s ceiling for SwiftUI to re-render an unshown window may be tight on a loaded CI runner.

**Fix:** Use `for _ in 0..<500 { if condition() { return true }; try? await Task.sleep(for: .milliseconds(10)) }; return condition()`.

### IN-04: With Space data on, a Space switch refuses no timing link when a Space is unknown

**File:** `Sources/TransomEngine/TabGroupTracker.swift:103`, `:122-125`, `:160`, `:182-183`

**Issue:** `blindSwitch` only covers `spaces == nil`. With Space data on, every window the switch hid "went hidden", and only `differ` stops the timing opener or join. `differ` is false whenever either set is empty: a hidden tab may report no Space, and a just-created tab may not have one yet.

**Fix:** When `spaceChanged` is true, require `confirmed` Spaces for the timing links. That means a non-empty intersection, not just "not known to differ".

### IN-05: The known-limit scenario pins a wrong 3-row result as its expected value

**File:** `Tests/TransomEngineTests/TabScenarioTests.swift:265-293`

**Issue:** Without Space data it expects `[[5, 5, 1], [10, 10, 1], [40, 40, 2]]`: three rows for two real windows, with 10 a stale row. The type doc (line 62) describes this limit as "an identity misattributed, never a window lost" and does not mention the leftover row.

**Fix:** Wrap the no-Space-data expectations in `withKnownIssue { ... }` so a later fix shows up as a pass, and state in the doc comment that a stale row remains.

### IN-06: `order` recomputes `tier` inside the sort comparator

**File:** `Sources/TransomEngine/TabGroupTracker.swift:207-225`

**Issue:** Each comparison calls `tier` twice, and each call scans `standalone` and every group's members linearly. `found` (line 215) also uses `candidates.contains` inside a filter. This is harmless at real per-app window counts, and performance is out of v1 scope.

**Fix:** Build `let rankKey = Dictionary(uniqueKeysWithValues: eligible.map { ($0, order($0)) })` once and sort on it. Optional.

---

_Reviewed: 2026-10-27T22:34:05Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
