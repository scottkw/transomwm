---
phase: 02-window-control
fixed_at: 2026-10-25T21:07:06Z
review_path: .planning/phases/02-window-control/02-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 2: Code Review Fix Report

**Fixed at:** 2026-10-25T21:07:06Z
**Source review:** .planning/phases/02-window-control/02-REVIEW.md (gap-closure review, iteration 4, `b63a0d4..54278c8`)
**Iteration:** 1 (first fix round for this review)

**Summary:**
- Findings in scope: 3 (CR-01, WR-01, WR-02; fix scope critical_warning; IN-01..15 not in scope)
- Fixed: 3
- Skipped: 0

**Where the fixes and the checks ran:** in the main checkout (`/Users/ken/dev/panewm`, branch `gsd/phase-01-layout-model`), not in an isolated worktree. The root-pin guard (`rootpin.sh`) has to pass before every commit, and it requires the main checkout to be the git toplevel. The reviewer's probe package also depends on that path. Every number below can be reproduced from that tree at `5a0894a`.

**Verification (main checkout, at HEAD `5a0894a`):**
- `swift build`: complete.
- `swift test --skip PaneMacIntegrationTests`: 470 tests pass (142 + 97 + 231). The review counted 463.
- `scripts/check-no-appkit.sh`: OK (25 files).
- `caffeinate -d -i swift test --filter PaneMacIntegrationTests`: 24 tests in 12 suites pass. One is skipped: `aWindowMovedOntoTheSecondDisplayReportsThatDisplay` needs two displays. The lockstate check said `locked: nil`. Afterwards `pgrep -fl PaneFixtureApp` found nothing.
- Each fix has a `test(02)` commit before its `fix(02)` commit. Every new test failed against the unfixed code. The D1 tests crashed the test process with the same `Duplicate values for key` trap the review reported.
- Reviewer harnesses, re-run at HEAD:
  - **Probe4 `crash` (D1):** exit 0. The output is `D1 cmdT+click: [(10, 10, 3)]`, then the same again. At review time it exited 133.
  - **Probe4 `dup` (D2):** `cmdT+click: [(10, 40, 4)]`, then `click 50: [(10, 50, 4)]`. That is one row throughout, with no `created 40`.
  - **Probe4 `race` (R1):** `stale-CG: [(10, 40, 2)]`. Every later step has one row, ending at `[(10, 10, 2)]`. There is no `created 40` and no `DESTROYED`.
  - **Probe4 `orphan` (O1):** unchanged. Without Space data, and with the twin answered, the closed group 30 is destroyed and 50 is created. With the shown twin unanswered, the result is still `[(30, 50, 1)]`. That is IN-14, which is out of scope.
  - **Probe4 `c3` (C3b):** unchanged. The merged window 20 is destroyed on the third refresh, which is what the fold guard intends.
  - **Probe3 (C1-C7), Probe4c and Probe4d:** byte-identical to their output on the pre-fix code. Probe4d still shows the IN-13 chained re-key, which is out of scope.

## Fixed Issues

### CR-01: A tab-count change during a tab switch crashes Pane, or leaves one tab group tracked as two windows for good

**Files modified:** `Sources/PaneEngine/TabGroupTracker.swift`, `Tests/PaneEngineTests/TabScenarioTests.swift`, `Tests/PaneEngineTests/TabGroupTrackerTests.swift`
**Commits:** 7c3350f (tests, RED), 231d86b (fix)
**Status:** fixed: requires human verification (logic)
**Applied fix:**
- **The rebind gate refuses only on proof of different Spaces.** `mayRebind` is now `!differ(space(v.id), group.spaces)`. A changed AXTabs count alone comes from Cmd-T, a background tab or a closed tab, so it no longer refuses. `Group.boundTabCount` is removed, because nothing else read it. Without Space data, this lets more of the C5 variant through. That is the accepted single-Space limit. C5 currently has equal tab counts, so its tests and Probe3's C5 are unchanged.
- **A refused member never takes its old group's tabs.** `pool` removes the refused group's members from `candidates` before the blind-switch filter and the ranking run.
- **No group is founded under an identity a group already holds.** A new group is skipped if its leader already leads a group, or if `v` is itself another group's leader. In that case `v` stays that group's window, through the tracker's default identity.
- **Backstop:** `tabCount` is built with `Dictionary(_:uniquingKeysWith: max)`, so a duplicate leader can no longer trap.

**Tests:**
- `cmdTAndASwitchToTheLeaderInOneRefreshStayOneGroup` (D1) and `cmdTAndASwitchToAnotherTabInOneRefreshStayOneGroup` (D2), in `TabScenarioTests`, all three modes. Each ends as one group with the right shown tab and tab count, `created == [10]`, nothing destroyed, and the suite's two safety invariants hold after every refresh.
- `aMemberWhoseTabCountDiffersFromItsGroupsLeavesItWhileTheShownTabIsStillThere` is inverted into `aMemberWhoseTabCountChangedStillRebindsItsGroupWhileTheShownTabIsStillThere`.
- The Space-data variants are `aMemberOnAnotherSpaceNeverTakesItsOldGroupsTabs` (the refused member's group excludes 30) and `aRefusedLeaderNeverFoundsASecondGroupUnderItsIdentity` (one `tabCount` key, no `groupFor` entry). `aMemberOnAnotherSpaceNeverRebindsTheGroup` still covers the refusal.

**Human check:** in a real app with native tabs (Safari, Finder, Terminal), press Cmd-T and then Ctrl-Shift-Tab quickly, and also press Cmd-T and click an older tab. Tracked Windows should keep one row whose tab count and shown title follow.

### WR-01: A sweep's CG snapshot taken before the AX read defeats the Cmd-T rule

**Files modified:** `Sources/PaneEngine/TabGroupTracker.swift`, `Sources/PaneMac/AXWindowSystem.swift` (comment only), `Tests/PaneEngineTests/TabGroupTrackerTests.swift`, `Tests/PaneEngineTests/TabScenarioTests.swift`
**Commits:** 8b51573 (tests, RED), 13fc543 (fix)
**Status:** fixed: requires human verification (logic)
**Option chosen, and why:** an engine rule, not a fresh per-app CG snapshot.
- A platform-only fix, re-reading CG after AX in `refresh`, would leave the tracker itself exposed. The `race` probe drives the tracker directly, and that probe has to pass.
- A platform-only fix could not be tested deterministically either.
- The engine rule needs about six lines, and it can be pinned with pure tests.

**Applied fix:**
- A shown tab that is brand new (missing from the previous CG list) and is also missing from the CG list it is resolved against marks that list as stale (`staleCG`). The list then predates the AX read, as a sweep's does.
- In a stale list only, the opener's onscreen CG entry may be a candidate. The opener is the tracked standalone window that was listed last refresh (`mayBeOpener`).
- No other onscreen window becomes a candidate, so the change touches nothing else.
- The new tab takes its opener, and the group stays under the opener's identity.
- The `AXWindowSystem.refresh` comment ("Read after AX answered") now says that a sweep's shared list predates every app's AX read, and that TabGroupTracker allows for it.

**Tests:**
- `aNewTabMissingFromAStaleCGListStillTakesTheWindowItWasOpenedFrom` (TabGroupTracker). It adds an onscreen same-frame untracked window 5, which must stay out.
- `cmdTSeenWithAStaleSweepCGListStaysOneWindow`, which is R1 through the real `WindowTracker`. There is one row at every step, `created == [10]`, and nothing is destroyed.

**Remaining limits:**
- The Space lookup in that update still reads the stale list, so the new tab has no Space entry for one update. Each Space rule treats an unknown Space as "not different", so no rule refuses on it.
- Two tracked same-frame windows that are both onscreen and both listed last refresh still resolve to the older one. That was already the opener rule's behaviour.

### WR-02: A failing element still switches `_AXUIElementGetWindow` off for every app, through tab or Space switches

**Files modified:** `Sources/PaneMac/AX/WindowIDResolver.swift`, `Tests/PaneMacTests/WindowIDResolverTests.swift`
**Commits:** 69ee7bf (tests, RED), 5a0894a (fix)
**Status:** fixed
**Applied fix:** counting and the first-failure wait now use separate sets.
- **Why the reviewer's version was not used.** Its prune keeps an element counted while it is listed or cached. That fixes Space switches, where the element is still carried as `known`. It would not fix tab switches. `knownWindowIDs` holds only a group's shown tab, so a hidden tab's element leaves the cache one refresh later and would count again.
- **`counted` (new).** It holds the elements whose failure was counted, and it is never pruned by listing. Its size is capped at 64 (`countedCap`), and the oldest entry is dropped first, so elements of closed windows cannot pile up.
- **`failed` (unchanged).** It is still pruned to the listed elements. It still drives `firstFailure`, so an element that comes back waits for its own CG entry before the frame match, as 02-16 designed.
- A success removes the element from both sets.

**Tests:**
- `aFailingElementCountsAgainOnlyAfterItLeftAXWindows` is inverted into `aFailingElementCountsOnceEvenAfterItLeftAXWindows` (1 counted failure, not 2).
- `roundTripsOfOneFailingElementNeverSwitchTheLookupOff(staysCached:)` covers five round trips, both while the element stays cached (another Space) and after it left the cache (a hidden tab). The capability stays on with 1 counted failure.
- `fiveDistinctFailingElementsSwitchTheLookupOffOnce` and `aSuccessBetweenFailuresKeepsTheLookupOn` still pass.

**Limit:** if more than 64 distinct elements of one app fail, with successes in between, the oldest one can count once more. That needs four more failures with no success in between to matter.

## Not fixed (out of scope)

IN-13 (chained re-key, Probe4d) and IN-14 (a blind switch with a partial Space map, Probe4 `orphan`) did not fall out of these fixes, and their outputs are unchanged. The accepted known limits in the 02-14 to 02-17 SUMMARYs were left alone.

## Earlier rounds (summary)

- **Iteration 1** fixed the original review's 12 findings (CR-01..04, WR-01..08). These covered:
  - the probe loop exit
  - Cmd-T and merge identity
  - same-frame twin rejection
  - refusal learning
  - a failed CG list
  - stopped apps
  - AX registration checks
  - queued writes for excluded apps
  - the private-lookup fallback
  - `displayUUID` after a frame write
  - the lock, hang and burst tests
- **Iteration 2** fixed the re-review's 4 findings (`dfc57d1` and its siblings):
  - the AXTabs-capped, tiered hidden-tab selection
  - the confirmed-refusal minimum learning
  - stable identity when the private lookup later succeeds
  - checked per-window AX registrations
- **Iteration 3's** findings were closed by gap plans 02-14 to 02-17, not by this fixer. The review this round worked from rates them.

---

_Fixed: 2026-10-25T21:07:06Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
