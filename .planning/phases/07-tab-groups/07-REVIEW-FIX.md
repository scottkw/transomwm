---
phase: 07-tab-groups
fixed_at: 2026-11-01T00:00:00Z
review_path: .planning/phases/07-tab-groups/07-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 7: Code Review Fix Report

**Fixed at:** 2026-11-01
**Source review:** .planning/phases/07-tab-groups/07-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (CR-01, WR-01 to WR-04). Info findings IN-01 to IN-07 were out of scope and none was touched.
- Fixed: 5
- Skipped: 0

**Where verification ran:** on the main checkout (`/Users/ken/dev/transomwm`, branch `gsd/phase-01-layout-model`, no worktree), plus one live suite in the Tart VM `pane-test`. Every number below can be reproduced from this tree.

## Fixed Issues

### CR-01: Excluding an app strands its hidden tabs off screen for good

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Sources/TransomEngine/Arranger+Tabs.swift`, `Sources/TransomMac/AXWindowSystem.swift`, `Sources/TransomMac/ArrangeController.swift`, `Tests/TransomEngineTests/ArrangerTabsTests.swift`
**Commit:** 21f3353
**Applied fix:**
- **Ordering, fixed in the shared code.** `AXWindowSystem.setExcludedBundleIDs` first asks `releaseFramesBeforeExcluding` (set by `ArrangeController` to `Arranger.releaseFrames(forExcluding:)`) which windows must go back on screen. It then flips the threads, which drops their queued frames. Last, it queues one write per window on that app's own thread (`writeForTermination`, run off main). The write runs after the flip on the same run loop, so no older park can land after it. Every caller of the setter gets this: the launch call and the `ExclusionStore.onChange` used by "Don't Arrange" and by list edits.
- **What gets released.** `releaseFrames(forExcluding:)` is the quit restore's plan, moved into the engine as `Arranger.restorePlan()` and filtered to the newly excluded bundles. A hidden tab goes to its group's content rect. A camera-parked or zoomed window goes home, which also covers the "same latent problem" the review raised for Phase 4 parks. `restoreForTermination` now calls the same `restorePlan()`.
- **Model.** `release(_:)` now takes the window out of its group in both the docked tree and the floating `FloatingTabGroup` sidecar. A group left with one member dissolves through the existing `remove` paths. A hidden member floats at its group's content rect, not at the parked `info.frame`.
- **Tests.** `ArrangerTabExclusionTests` has two tests: one for a docked hidden member and one for a floating hidden member, whose group dissolves and whose survivor takes the frame.

### WR-01: The reveal read-back needs every edge within 2 pt

**Files modified:** `Sources/TransomEngine/Arranger+Tabs.swift`, `Tests/TransomEngineTests/ArrangerTabsTests.swift`
**Commit:** 107248d
**Applied fix:**
- **Tolerance.** `revealed(_:actual:now:)` now matches on the origin, within 2 pt. Any smaller size counts, and so does a size up to `MinimumSizeLearner.refusalMargin` larger, which is the docked correction's tolerance. A window more than the margin larger still falls through to `retryRefusal` and minimum learning, as before.
- **Timeout.** `revealTimedOut` now sends `.focus(previous)` when the kept member is present.
- **Tests.** `ArrangerTabRevealToleranceTests` has three tests: a read-back 7 pt narrower and 10 pt shorter parks the previous member, a read-back 40 pt taller is not a reveal, and a timeout refocuses the kept member.

### WR-02: When a group's selected member goes absent, its hidden members stay parked

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Sources/TransomEngine/Arranger+Tabs.swift`, `Tests/TransomEngineTests/ArrangerTabsTests.swift`
**Commits:** 490a471, 2a2c5b0 (follow-up after the VM run)
**Status:** fixed: requires human verification (this is a logic and UX change, see the note below)
**Applied fix:**
- **Selected member goes absent.** This covers ⌘M on it, its app hidden, and native full screen, but not Minimize Group. `selectNeighbour(ofAbsent:)` selects the nearest present member, right first, else left, so the group keeps its tile and strip. When the absent member comes back, the current selection stays and the returning member parks. This path sets no focus suppression, so whichever member macOS focuses next is shown.
- **Minimize Group keeps its selection (D-06).** It is tracked in the new `TabGroupState.minimizing`, which is cleared on present, closed and `forget`.
- **No invisible key window.** If macOS focuses a parked member during the suppression window while the group is minimised, focus goes back to the last window focused that is still on screen. If there is none, the focused member is minimised along with its group.
- **Why the follow-up commit.** The first version showed the member in that case. The VM run proved this broke D-06: `minimizeGroupWithTwoWindowsOfOneAppStaysMinimized` failed because macOS made the sibling key. 2a2c5b0 switched the fallback to minimising, which fixed it.
- **Tests:**
  - New: `theSelectedMemberGoingAbsentSelectsAPresentNeighbourAndItsReturnKeepsIt`, `theSelectedMemberGoingAbsentPicksTheRightNeighbourFirst`, `withNoWindowOnScreenToFocusTheFocusedHiddenMemberIsMinimisedWithTheGroup`.
  - Updated: `macOSFocusingTheHiddenMemberAfterTheMinimiseDoesNotBringTheGroupBack` now expects `[.focus(a)]`.
  - Replaced: `aFocusWithin1sOfTheSelectedMemberGoingAbsentDoesNotSwitchTabs`, whose premise is the old behaviour.
  - `whileTheSelectedIsMinimisedTheQuitPlanStillBringsTheHiddenMemberOnScreen` now goes through Minimize Group.
- **Note for review:** a member that Minimize Group minimised this way stays minimised. Its tab beeps "Couldn't show" until it is restored from the Dock. Restoring it from the Dock focuses it and selects it (D-08).

### WR-03: Rehoming a group to another Space carries hidden members that stay on the old Space

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/ArrangerTabsTests.swift`
**Commit:** 91a74fd
**Applied fix:**
- **Choice: the simplest correct option.** The whole group is carried only on a display move, where a frame write can still reach the hidden members. A Space move on the same display takes the selected member out alone, and it floats on the new desk. The rest stay grouped on the old desk through `tree.remove` / `desktop.remove`: a neighbour is selected, or the last member takes the leaf, the same way a close leaves them. No member is stranded.
- **Tests.** The display-move test `rehomingTheSelectedMemberMovesTheWholeGroup…` is unchanged and still passes. The new test is `ArrangerTabSpaceRehomeTests.movingTheSelectedMemberToAnotherSpaceTakesItOutAloneAndTheRestStayOnTheOldDesk`.

### WR-04: Switching tabs mid-drag parks the window under the pointer

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/ArrangerTabsTests.swift`
**Commit:** c1dc174
**Applied fix:**
- **Guard.** The replan's parks loop now skips `drag?.window`, mirroring the guard in the frames loop (D-23). A window that was already parked keeps its park record, which covers a torn-off hidden tab.
- **Tests.** `ArrangerTabDragParkTests.aTabSwitchDuringAWholeGroupDragNeverParksTheDraggedWindow`. I confirmed it fails with the source change stashed (2 issues) and passes with it.

## Verification

- **Host `swift test` (full), last run after the final commit:**
  - TransomEngineTests: 961 tests in 101 suites passed.
  - TransomMacTests: 390 tests in 58 suites passed.
  - TransomModelTests: 93 tests in 31 suites passed.
  - TransomMacIntegrationTests: 219 tests in 24 suites passed. The live ones skip on the host as intended.
- **Every touched suite ran and passed:** `ArrangerTabExclusionTests`, `ArrangerTabRevealToleranceTests`, `ArrangerTabSelectTests`, `ArrangerTabActivationTests`, `ArrangerMinimizeGroupTests`, `ArrangerTabSafetyTests`, `ArrangerTabSpaceRehomeTests`, `ArrangerTabDragParkTests`.
- **One unrelated flake.** An earlier full run had one failure, `FreezeTestTests.itResumesByItself`. It is a 1 s timing test in a file I did not touch. It passed 3/3 alone and in the next two full runs.
- **`scripts/check-no-appkit.sh`:** OK (55 files).
- **VM (Tart `pane-test`):** `scripts/vm-live-test.sh TabGroupIntegrationTests` printed "✔ Test run with 5 tests in 1 suite passed after 8.156 seconds." Its log shows `after minimize: frontmost none`; before the WR-02 follow-up it was `frontmost index=0`, a parked key window. I ran one VM job at a time; the script quit and relaunched Transom in the guest and released its lock.
- **Not covered live:** the CR-01 shell write path in `AXWindowSystem.setExcludedBundleIDs`. No live suite drives an exclusion change through `ArrangeController`, because `ExclusionIntegrationTests` uses a bare `AXWindowSystem` with no hook. It is checked by the build, the engine tests of `releaseFrames` and `release`, and code reading only.

## Notes

- **IN-02.** The new `tabs.minimizing` set is not rekeyed on `windowRekeyed`, which is the same class of gap as IN-02. If a member is rekeyed during a Minimize Group, its absence is treated as a ⌘M, so a neighbour is selected. That is safe.

---

_Fixed: 2026-11-01_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
