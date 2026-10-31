---
phase: 05-gestures
fixed_at: 2026-10-30T21:00:00Z
review_path: .planning/phases/05-gestures/05-REVIEW.md
iteration: 1
findings_in_scope: 10
fixed: 10
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-10-30
**Source review:** .planning/phases/05-gestures/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 10 (WR-01..WR-10). Info items were fixed only when trivial and clearly safe.
- Fixed: 10 warnings, plus IN-02, IN-05 and IN-06
- Skipped: 0 warnings. IN-01, IN-03, IN-04 and IN-07 were left open (see the end of this report).

All work was done on branch `gsd/phase-01-layout-model` in the main checkout, not a worktree. That way the host `swift test`, the VM suites and `scripts/build-debug.sh` all ran against the tree that holds the commits. Rule followed throughout: GEST-04 / D-06. A gesture Transom took never has its tail delivered to the app. When in doubt, the follow ends cleanly (spring back) and the tap keeps consuming until the sequence ends.

## Fixed Issues

### WR-01: Every no-⌥ gesture start does a CG window-list read inside the session tap callback

**Files modified:** `Sources/TransomMac/Input/GestureTapRules.swift`, `Sources/TransomMac/Zoom/GestureController.swift`, `Tests/TransomMacTests/GestureTapRulesTests.swift`
**Commit:** 527f788
**Status:** fixed (mitigation; cost still unmeasured on hardware)
**Applied fix:** `GestureTapState.windowRects` carries the frames of the windows Transom tracks on a desk. It uses the same filter as the green-button rects: dockable, not excluded, present, on a desk. Main publishes it after every Arranger change. A no-⌥ start whose pointer is inside one of these frames passes as "window under pointer" with no `CGWindowListCopyWindowInfo` in the callback. On a tiled desk that is nearly every scroll. The CG read now runs only over gaps, bare wallpaper and untracked windows, and with WR-02 it runs once per pan instead of twice. A stale frame can only make a wallpaper gesture pass, never take a gesture over a window, so D-05 holds. Test: `aTrackedWindowUnderThePointerPassesWithNoSurfaceRead`.
**For the next hardware check:** the residual read (no-⌥ scroll over wallpaper or an untracked window) is still unmeasured. A no-⌥ pinch over bare wallpaper should still feel immediate. Watch for "gesture tap re-enabled after timeout" lines in the gesture log.

### WR-02: A pan that starts with mayBegin (128) then began (1) is decided twice and split into two gestures

**Files modified:** `Sources/TransomMac/Input/GestureTapRules.swift`, `Tests/TransomMacTests/GestureTapRulesTests.swift`
**Commit:** 7fb5a34
**Applied fix:** `Sequence.mayBeginOnly`: a began that follows a latched mayBegin continues that sequence. It is decided once, keeps one start time and gets one tap summary, and the reason rides on the first sample only. A began after a continued or cancelled (8) mayBegin still decides afresh. Test: `mayBeginThenBeganIsOneSequence`.

### WR-03: Resting fingers more than 2 s mid-gesture leaks the rest of the gesture to the app

**Files modified:** `Sources/TransomMac/Input/GestureTapRules.swift`, `Tests/TransomMacTests/GestureTapRulesTests.swift`
**Commit:** f717ba8
**Status:** fixed: requires human verification (UAT item 10 on hardware)
**Applied fix:** when a taken latch expires, it becomes an orphan (`Sequence.orphan`, `GestureTapRules.orphaned`) instead of being dropped. The orphan swallows the rest of its sequence with no samples, momentum included, until its end or the next start of its kind. Main has already sprung the stage back at 2.05 s. A pinch orphan takes its zoom tail, and the other type-29 sub-types only while zoom traffic is recent (see WR-04). Passing latches still expire as before. Changed behaviour: late momentum that arrives more than 0.3 s after a taken pan's lift is now swallowed. It used to pass as a stray. Tests: `aTakenGestureResumedAfterALongRestNeverLeaksItsTail`, plus updated `aStuckLatchIsReleasedByTimeoutOrANewStart` and `quietAfterFingersUpOrphansTheLatchButFingersDownQuietKeepsIt` (renamed).

### WR-04: A consuming pinch latch is kept alive by non-zoom sub-types and can swallow type-29 events indefinitely

**Files modified:** `Sources/TransomMac/Input/GestureTapRules.swift`, `Tests/TransomMacTests/GestureTapRulesTests.swift`
**Commit:** d809f4c
**Applied fix:** only zoom sub-type events refresh a pinch latch's `lastEvent`. Scroll companions (sub-types 0, 6, 32) pass again 2 s after the last zoom event. Test: `scrollCompanionsDoNotKeepALostPinchLatchAlive`.

### WR-05: A tap re-enable mid-gesture drops the open sequences silently, leaking the tail and freezing the stage for 2 s

**Files modified:** `Sources/TransomMac/Input/GestureTap.swift`, `Tests/TransomMacTests/GestureTapRulesTests.swift`
**Commit:** 0bb43db
**Applied fix:** on `tapDisabledByTimeout` / `tapDisabledByUserInput`, the callback yields each open summary as ended by timeout. Main then resolves the stage at once instead of after 2 s. Taken latches become orphans through `Latch.orphaned()`, so the rest of the consumed gesture is still swallowed. Passing latches are dropped. Test: `aReEnabledTapOrphansTakenSequencesAndDropsPassingOnes`, at rules level. The callback path itself can't be driven: a real tap-disabled event can't be produced headless or in the VM.

### WR-06: The E-04 sender filter turns off when no trackpad is found, and Magic Mouse is identified by one unverified family constant

**Files modified:** `Sources/TransomMac/Input/GestureTapRules.swift`, `Sources/TransomMac/Input/Trackpads.swift`, `Sources/TransomMac/Zoom/GestureController.swift`, `Sources/TransomPrivate/MultitouchSupport.swift`, `Sources/transom-gesture-spike/main.swift`, `Tests/TransomMacTests/GestureTapRulesTests.swift`
**Commit:** 86c143e
**Applied fix:**
- The filter now fails closed. An event whose sender is not a known trackpad always passes, including when no trackpad is found (E-04 strict). Synthetic events (sender 0) are still judged.
- `GestureController.filtersBySender` is removed. An empty set can no longer mean "off".
- The spike's listen and `--no-sender-filter` modes keep their behaviour through an explicit `GestureTapState.filtersBySender`, which the product never sets.
- The Magic Mouse family check now lives once, in `MultitouchSupport.isTrackpad(family:)`, used by `MultitouchSupport.Info` and `Trackpads`.

Test: `onlyKnownTrackpadSendersAreTaken`, extended.
**Not done:** positive trackpad identification by IOKit driver class. It can't be verified without hardware. "Not family 112" still stands in for "trackpad".

### WR-07: GestureController.handle processes buffered tap events after `stop()`, so a stage can appear after the tap is gone

**Files modified:** `Sources/TransomMac/Zoom/GestureController.swift`, `Tests/TransomMacTests/GestureControllerTests.swift` (new)
**Commit:** 2472a61
**Applied fix:** `handle` drops every event while inactive. It also drops events whose seq is at or below `seqFloor`, the tap's `lastSeq` read just before the current start. This covers samples and `.ended`. The commit also includes IN-05: `loggedByTimer` is cleared at stop. Test: `onlyTheRunningTapsEventsAreHandled`, which covers the pure `isCurrent` gate.

### WR-08: The crash canary blames every abnormal exit on multitouch and never heals itself

**Files modified:** `Sources/TransomPrivate/Capabilities.swift`, `Sources/TransomMac/Shell/GestureCopy.swift`, `Sources/TransomMac/Shell/StatusItemController.swift`, `Sources/TransomMac/ArrangeController.swift`, `Tests/TransomMacTests/CapabilitiesTests.swift`
**Commit:** 39240af
**Applied fix:** the protection stays the same. A launch that died with multitouch running still starts the next launch tap-only, for the same OS build and app version, so a real multitouch crash can't loop. The new part is a way back:
- While Debug G4 reads "Multitouch: off after a crash last launch", the Debug submenu shows **Turn Multitouch Back On**.
- It calls `MultitouchCanary.turnBackOn()`, which clears the canary key and the launch's tripped flag. `tripped` is now a lock-protected value instead of a `static let`.
- With the gesture tap running, the trackpads open at once. Otherwise they open at the next tap start (zoom on).
- The canary is armed again at that open, so a real crash afterwards trips it again.

Test: `turningMultitouchBackOnClearsTheCanary`.
**Not done:** the review's "two consecutive unclean exits" rule. The user asked for the smallest reset.

### WR-09: Gestures stay armed during Turn Off Zoom's home move and can hijack it

**Files modified:** `Sources/TransomMac/ArrangeController.swift`, `Sources/TransomMac/Zoom/GestureController.swift`, `Tests/TransomMacTests/GestureControllerTests.swift`
**Commit:** 14ea5db
**Applied fix:** `ArrangeController.isTurningOff`. `GestureController.disarmReason(...)` treats it as paused (disarm reason "zoom paused"). `setZoomEnabled(false)` re-publishes right after setting `turningOff`. Test: `turningZoomOffDisarmsGestures`.

### WR-10: When a multitouch pinch ends, the tap's still-running pan sequence takes the stage over

**Files modified:** `Sources/TransomMac/Zoom/GestureController.swift`, `Tests/TransomMacTests/GestureControllerTests.swift`
**Commit:** 3ca01f9
**Status:** fixed: requires human verification (only reachable with "Zoom in or out" off, on a real trackpad)
**Applied fix:** while a started multitouch pinch owns the stage, each tap sequence whose sample is dropped goes into `suppressed`. It stays dropped until its `.ended`, its timeout, or a stop. Test: `aSequenceShutOutByAMultitouchPinchStaysOutUntilItsEnd`, which covers the pure `dropsSample` gate.

### Info items fixed (trivial, clearly safe)

- **IN-02** (b5be378): `transom-gesture-spike synth` exits unless `kern.hv_vmm_present` is 1. Verified: the host reads 0 and the Tart guest reads 1.
- **IN-05** (in 2472a61): `loggedByTimer` is cleared at stop.
- **IN-06** (d4d9958): `endPick(reason: "gesture")` moved from the first consumed sample to the recognizer's `.started`. VM `aGestureEndsPickMode` still passes.

## Skipped Issues

None of the in-scope warnings. Info items left open:

- **IN-01** (stopStreaming stops devices it never started): not trivial. The spike starts every device (`all: true`), so the started set would have to be recorded per list. Can't be verified without a Magic Mouse.
- **IN-03** (rescan mid-pinch leaves stale trackers): needs an `onRescan` callback and follow handling. Not trivial.
- **IN-04** (unbounded `Worker.sync`): changes threading and failure semantics of the private-API worker. Not trivial.
- **IN-07** (pan direction with natural scrolling off): needs a product decision, not a code fix.

## Verification

Gates ran in the main checkout (`/Users/ken/dev/transomwm`), which holds every commit above, so the numbers are reproducible from this tree.

| Run | Result |
|---|---|
| `scripts/check-no-appkit.sh` | OK (45 files) |
| Host `swift test` (full, sequential, `.build/review-fix-full.log`) | 193 + 315 + 75 + 690 = 1,273 tests passed, 0 failed (was 1,264; +9 new tests) |
| `swift test --filter GestureTapRulesTests` | 25 tests passed |
| `swift test --filter GestureControllerTests` | 3 tests passed |
| `swift test --filter 'MultitouchCanaryTests\|GestureCopyTests\|MultitouchDevicesTests'` | 19 tests passed |
| VM `GestureTapIntegrationTests` | 12 passed (20.4 s) |
| VM `GestureFollowIntegrationTests` | 13 passed (58.7 s) |
| VM `InputTapIntegrationTests` | 3 passed (1.1 s) |
| VM `ZoomSettleIntegrationTests` | 2 passed (19.7 s) |
| VM `MultitouchIntegrationTests` | 1 passed |
| `scripts/build-debug.sh` | built and verified: `xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, valid signature, satisfies its designated requirement. Not launched |

VM: Tart `pane-test` (macOS 15.7.7), one suite per `scripts/vm-live-test.sh` invocation, fixtures only. The VM was stopped afterwards and no fixture or test process was left in the guest. VM logs: `.build/reviewfix-vm-*.log`.

## Left for the user's next hardware check

1. **WR-01:** with ⌥ not held, pinch and scroll over bare wallpaper and over docked windows. Expected: wallpaper is taken immediately, windows behave as before. Watch for "gesture tap re-enabled after timeout" in the gesture log. The residual CG read cost is still unmeasured.
2. **WR-03 (UAT item 10):** hold ⌥, pinch or pan halfway over Safari, rest your fingers about 2.5 s, then keep going and lift. Expected: the stage springs back during the rest, and Safari neither zooms nor scrolls afterwards.
3. **WR-06 (UAT item 8):** if a USB/Bluetooth mouse or Magic Mouse is around, ⌥-scroll with it. Expected: the app scrolls and Transom does nothing. Also re-check that ⌥-pinch and ⌥-pan on the built-in trackpad still work. The filter now rejects any sender that isn't the IOKit `AppleMultitouchDevice` registry ID, so a mismatch would make every trackpad gesture pass.
4. **WR-10:** with "Zoom in or out" off, ⌥-pinch with some finger drift and let it commit. Expected: no second pan or flicker after the pinch.
5. **WR-08:** only after a canary trip. Hold ⌥ and open the menu bar icon ▸ Debug ▸ Turn Multitouch Back On. Expected: G4 reads "Multitouch: available, 1 trackpad".
6. A Transom Debug process started at 11:19, before these fixes, is still running on the host. The app on disk is rebuilt, so quit and relaunch to test the fixes.

---

_Fixed: 2026-10-30_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
