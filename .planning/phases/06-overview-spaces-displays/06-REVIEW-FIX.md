---
phase: 06-overview-spaces-displays
fixed_at: 2026-10-31T22:15:30Z
review_path: .planning/phases/06-overview-spaces-displays/06-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 10
skipped: 2
status: partial
---

# Phase 6: Code Review Fix Report

**Fixed at:** 2026-10-31T22:15:30Z
**Source review:** .planning/phases/06-overview-spaces-displays/06-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 12 (2 critical, 10 warning; the 6 info findings are out of scope)
- Fixed: 10 (WR-10 only partly: see its entry)
- Skipped: 2 (WR-05, WR-06)

## Verification

- **Where the gates ran:** builds and host tests ran in the isolated worktree (`.claude/worktrees/rf-06-…`), which was fast-forwarded into `gsd/phase-01-layout-model` afterwards. The main checkout holds the same source tree, so the results can be reproduced there.
- **Host, headless:** full `swift test` passed (Swift Testing: 193 + 366 + 814 tests passed, 0 failures; the 83 live integration tests were skipped because `TRANSOM_LIVE` was not set). `scripts/check-no-appkit.sh` passed (53 files). `swift format lint --strict` on the changed files gave no findings.
- **Regression tests failed before their fix:** CR-01, CR-02 (both tests), WR-02, WR-03, WR-07, WR-09 and WR-10 each had a test that failed first and passes after the fix. WR-01 has a test but was not run before the fix, because the old code traps and would crash the test process. WR-04 is covered by a new `LayoutStore.backUp` test. WR-08 and WR-11 have no headless test.
- **VM:** `scripts/vm-live-test.sh TakeoverIntegrationTests` printed "Test run with 2 tests in 1 suite passed", which proves the new VM gate is open inside the guest. Afterwards `/tmp/transom-hkread` read 32, 108 and 113 back as enabled on the guest, the same as before the run. On the host, `kern.hv_vmm_present` reads 0, so the gate refuses to run the suite there.

## Fixed Issues

### CR-01: A failed launch re-attach plus any arrangement settle saves the wrong layout under the wrong arrangement and drops a stored layout set

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Tests/TransomEngineTests/ArrangerDisplaySettleTests.swift`
**Commit:** 20111d8
**Applied fix:** `unattached` now records the arrangement the saved World was saved under, and `snapshot` returns that arrangement while the World is unattached. While unattached, `displaysSettled` neither stores nor takes a layout set: the decision uses an empty set list, so it can only be `.same` or `.new`. Settling still blocks frame writes, and windows from a vanished display are still cascaded. A one-shot internal `reattachFault` seam stands in for the re-attach failure, because no real World can make it throw. Regression test: `aSettleAfterAFailedReattachKeepsTheSavedLayoutAndItsSets`.

### CR-02: Layout sets are never re-keyed by Space UUID and are missing from the Space table

**Files modified:** `Sources/TransomEngine/SpaceRekey.swift`, `Sources/TransomMac/ArrangeController.swift`, `Tests/TransomEngineTests/SpaceRekeyTests.swift`
**Commit:** ace0a3e
**Applied fix:** `SpaceRekey.table(for:layoutSets:uuids:)` now lists the Space IDs of every layout set, and `write()` passes the snapshot's sets. The new `SpaceRekey.rekey(_ file:live:)` re-keys the World and every set's World with the same table. A set that cannot be rebuilt keeps its saved keys. `ArrangeController.rekeyed` uses it and logs quarantined desks from the sets too. Tests: `theTableListsTheSpacesOfEveryLayoutSet`, `everyLayoutSetIsRekeyedWithTheWorld`. `merged` (a known set replacing the current desks on the displays it covers) was left alone: that is the D-09 design.

### WR-01: Takeover originals in UserDefaults can crash every launch

**Files modified:** `Sources/TransomMac/MissionControlTakeover.swift`, `Tests/TransomMacTests/TakeoverMenuTests.swift`
**Commit:** 63f1485
**Applied fix:** Only canonical keys are read (`String(Int32(key)) == key`), so no two keys can map to one ID and `uniqueKeysWithValues` cannot trap. Ignored keys are logged. Test: `nonCanonicalOriginalKeysAreIgnoredNotATrap`.

### WR-03: After a failed apply the preference stays on and the menu can never turn it off

**Files modified:** `Sources/TransomMac/MissionControlTakeover.swift`, `Tests/TransomMacTests/TakeoverMenuTests.swift`
**Commit:** 9c25bcc
**Applied fix:** On `.applyFailed`, `takeover.enabled` is set to false. Clicking O2 then turns the takeover on again, and the next launch does not re-apply or repeat N11. `aRefusedApplyRestoresTheOriginalsAndPostsN11` was extended to check this.

### WR-02: A failed restore leaves Mission Control shortcuts disabled for the whole session

**Files modified:** `Sources/TransomMac/MissionControlTakeover.swift`, `Sources/TransomMac/ConflictController.swift`, `Tests/TransomMacTests/TakeoverMenuTests.swift`
**Commit:** d69551e
**Applied fix:** `canRestore` is now also true while takeover originals are stored. With the takeover off, `restore()` calls the new `MissionControlTakeover.retryRestore()`. The launch restore now logs an error when the read-back differs, where before it logged success. Test: `restoreMacOSWindowSettingsRetriesAFailedLaunchRestore`.
**Not done:** Two parts of the suggestion were left out. There is no new user-facing notice, because it would need new UI copy. The restore path still respects a forced-off capability, because the `--disable-private` kill switch exists in case the private API misbehaves.

### WR-04: Quarantined desks are deleted from layout.json on the first launch write, with no backup

**Files modified:** `Sources/TransomMac/LayoutStore.swift`, `Sources/TransomMac/ArrangeController.swift`, `Tests/TransomMacTests/LayoutStoreTests.swift`
**Commit:** c0013f3
**Applied fix:** The new `LayoutStore.backUp(_:)` copies layout.json to `layout.json.pre-rekey-<unix seconds>`. Each copy gets its own timestamp, so no earlier backup is replaced. `rekeyed` makes the copy before any desk is quarantined, so the copy exists before the launch write. If the copy fails, the launch keeps the saved Space IDs rather than drop any desk. Test: `aBackupCopiesTheFileAndKeepsEarlierBackups`. The second-collision and `default:<uuid>` causes of quarantine are unchanged, but they now always leave a backup.

### WR-07: SpaceSwitcher posts ⌃←/⌃→ into the frontmost app when the user has turned those hotkeys off

**Files modified:** `Sources/TransomEngine/SpaceSwitchPlan.swift`, `Sources/TransomMac/SpaceSwitcher.swift`, `Tests/TransomEngineTests/SpaceSwitchPlanTests.swift`
**Commit:** 8b53c86
**Status:** fixed: requires human verification
**Applied fix:** The default chords are now used only when the hotkey getter is missing. A readable but disabled move hotkey means there is no route: the plan returns `[]`, and `switchTo` refuses (it beeps and shows "Couldn't switch"). `switchTo` now checks `from == to` before planning, so an empty plan no longer reads as success. The deadline is now 1 s plus 400 ms for each chord after the first. The old test `disabledMoveHotkeysMeanTheDefaultChords` became `disabledMoveHotkeysMeanNoRoute`. This reverses the 06-07 plan and RESEARCH Pattern 3 rule ("disabled → default chords"). The spike showed that macOS ignores the chord of a disabled hotkey, so the old rule only sent the chord to the frontmost app. Please confirm this is the behaviour you want.

### WR-08: A new display change between "settled" and its Task can end settling mid-change

**Files modified:** `Sources/TransomMac/ArrangeController.swift`
**Commit:** a2eabd0
**Status:** fixed: requires human verification
**Applied fix:** `displaysSettled()` returns unless `system.settlerState == .idle`, checked both before and after `await system.inventory()`. The newer change's own `onSettled` then ends settling. There is no headless test, because ArrangeController needs a live `AXWindowSystem`.

### WR-09: A display settle while the launch restore is still pending relabels the saved layout

**Files modified:** `Sources/TransomEngine/Arranger.swift`, `Sources/TransomMac/ArrangeController.swift`, `Tests/TransomEngineTests/ArrangerDisplaySettleTests.swift`
**Commit:** b27ee4e
**Status:** fixed: requires human verification
**Applied fix:** `arrangement = id` now runs after the pending-restore branch. In that branch the Arranger re-attaches under the saved arrangement. If that succeeds, it calls `displaysSettled` again, which stores the saved layout as its arrangement's set and applies a known set for `id`. After each settle, `ArrangeController` recomputes `launchSettlePending`: true only while the restore still waits and the live displays differ from the saved arrangement. Test: `aSettleDuringThePendingRestoreStoresTheSavedLayoutAndAppliesTheLiveSet`. One thing to know: floating windows are re-homed to their current display before the saved layout is stored as a set, just as in the existing launch settle path.

### WR-10: The G-03-9 ghost rule does not close tabbed ghosts (partly fixed)

**Files modified:** `Sources/TransomEngine/WindowTracker.swift`, `Tests/TransomEngineTests/CloseScenarioTests.swift`
**Commit:** ba8313f
**Status:** fixed: requires human verification (terminated path only)
**Applied fix:** For a terminated app, the remaining members of a closed tab group no longer count CG entries on no Space. A dead app's tab group made only of ghosts now closes. Test: `aTerminatedAppsGhostTabGroupCloses`.
**Not fixed: the alive-app path.** There, `isKnownTabMember` is checked before `cgSpacesKnownEmpty`. Changing that order needs VM evidence, because an alive app's hidden tabs also report no Space, and the wrong choice would close live tab groups. Check it in UAT with the VM `ghost` spike on a Safari window with several tabs.

### WR-11: Live takeover tests change the host's real symbolic hotkeys with no VM gate

**Files modified:** `Tests/TransomMacIntegrationTests/IntegrationSupport.swift`, `Tests/TransomMacIntegrationTests/TakeoverIntegrationTests.swift`, `Tests/TransomMacIntegrationTests/OverviewSpaceSwitchIntegrationTests.swift`
**Commit:** cd02991
**Applied fix:** The new `IntegrationEnv.inVM` reads `kern.hv_vmm_present`, as the spike's `requireVM()` does. TakeoverIntegrationTests and OverviewSpaceSwitchIntegrationTests now require it as well as `IntegrationEnv.trusted`. Other live suites were not gated: some, such as FrameWriteIntegrationTests' two-display test, can only run on real hardware. The suite was checked in the VM; see Verification.

## Skipped Issues

### WR-05: A dormant desk whose stale Space ID a newly created Space takes during the session silently inherits that Space

**File:** `Sources/TransomEngine/SpaceRekey.swift:40-48`
**Reason:** skipped: needs design and hardware/VM evidence. The short fix moves dormant desks to a reserved synthetic ID range. That would break a known case: within one boot, a Space whose display comes back can return under the same ID, and its desk re-attaches today. Nobody has checked how macOS numbers Spaces across a display reconnect. The other fix compares UUIDs at each Spaces refresh. It needs a hook in AXWindowSystem when Spaces are refreshed, a new Arranger input to move or quarantine a desk, and a race fix so `.spaceChanged` events cannot reach the desk first. That is too large to add safely as a review fix. No data is lost today: the desk is relabelled, not deleted. Plan it as its own task.
**Original issue:** An unmatched desk keeps its previous-boot ID. A Space created later in the session can receive that ID and inherit the dormant layout. `write()` then records the new UUID for it, which makes the mismatch permanent.

### WR-06: SpaceSwitcher targets the wrong Space on multi-display setups

**File:** `Sources/TransomMac/SpaceSwitcher.swift:19-40`
**Reason:** skipped: needs hardware evidence. The finding assumes macOS numbers "Desktop n", and its "Switch to Desktop n" shortcuts, across all displays. The VM cannot run multiple displays, and per the instructions I did not guess at the numbering. Warping the pointer for the move-chord fallback also depends on unverified behaviour (which display macOS treats as active). **Add to 06-UAT:** on two displays, with two desktops on the main display and one or more on the second, pick a second-display Space in the overview strip (by click and by Return). Record which display switches and what label the strip shows.
**Original issue:** `SpaceInfo.index` counts desktops per display, so a pick on a non-main display may post the main display's "Desktop n" chord. The move fallback acts on the display macOS considers active, not on the target display.

---

_Fixed: 2026-10-31T22:15:30Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
