---
phase: 05-gestures
verified: 2026-10-30T18:53:47Z
status: passed
score: 17/17 must-haves verified (1 accepted N/A)
human_checks_passed: 2026-10-30
covered_files:
  - .planning/phases/05-gestures/05-01-PLAN.md
  - .planning/phases/05-gestures/05-01-SUMMARY.md
  - .planning/phases/05-gestures/05-02-PLAN.md
  - .planning/phases/05-gestures/05-02-SUMMARY.md
  - .planning/phases/05-gestures/05-03-PLAN.md
  - .planning/phases/05-gestures/05-03-SUMMARY.md
  - .planning/phases/05-gestures/05-04-PLAN.md
  - .planning/phases/05-gestures/05-04-SUMMARY.md
  - .planning/phases/05-gestures/05-05-PLAN.md
  - .planning/phases/05-gestures/05-05-SUMMARY.md
  - .planning/phases/05-gestures/05-06-PLAN.md
  - .planning/phases/05-gestures/05-06-SUMMARY.md
  - .planning/phases/05-gestures/05-07-PLAN.md
  - .planning/phases/05-gestures/05-07-SUMMARY.md
  - .planning/phases/05-gestures/05-08-PLAN.md
  - .planning/phases/05-gestures/05-08-SUMMARY.md
  - Package.swift
  - Sources/TransomEngine/Arranger+Camera.swift
  - Sources/TransomEngine/GestureRecognizer.swift
  - Sources/TransomMac/ArrangeController.swift
  - Sources/TransomMac/Input/GestureTap.swift
  - Sources/TransomMac/Input/GestureTapRules.swift
  - Sources/TransomMac/Input/MultitouchDevices.swift
  - Sources/TransomMac/Input/Trackpads.swift
  - Sources/TransomMac/Shell/GestureCopy.swift
  - Sources/TransomMac/Shell/StatusItemController.swift
  - Sources/TransomMac/Zoom/GestureController.swift
  - Sources/TransomMac/Zoom/StagePanel.swift
  - Sources/TransomMac/Zoom/TileLayer.swift
  - Sources/TransomMac/Zoom/ZoomController.swift
  - Sources/TransomMac/Zoom/ZoomInput.swift
  - Sources/TransomPrivate/Capabilities.swift
  - Sources/TransomPrivate/GestureEventFields.swift
  - Sources/TransomPrivate/MultitouchSupport.swift
  - Sources/transom-gesture-spike/main.swift
  - Tests/TransomEngineTests/ArrangerCameraTests.swift
  - Tests/TransomEngineTests/GestureRecognizerTests.swift
  - Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/MultitouchIntegrationTests.swift
  - Tests/TransomMacTests/CapabilitiesTests.swift
  - Tests/TransomMacTests/GestureControllerTests.swift
  - Tests/TransomMacTests/GestureCopyTests.swift
  - Tests/TransomMacTests/GestureTapRulesTests.swift
  - Tests/TransomMacTests/MultitouchDevicesTests.swift
  - Tests/TransomMacTests/StageFollowTests.swift
  - Tests/TransomMacTests/ZoomOffTests.swift
  - scripts/vm-live-test.sh
  - scripts/vm-spike.sh
covered_digest: "v4:sha256:8000f4ec6a4432205bc5f65402f751b3cb3ed307a29be0fd8de3d228f0beed2b"
behavior_unverified: 1
overrides_applied: 1
overrides:
  - truth: "SC4: gestures keep working after the trackpad disconnects and reconnects"
    decision: "Accepted as N/A by the user 2026-10-30: no Magic Trackpad on this Mac (C5); fake-backend tests only"
decision_coverage:
  honored: 9
  total: 9
  not_honored: []
behavior_unverified_items:
  - truth: "SC4: gestures keep working after the trackpad disconnects and reconnects"
    test: "Turn a Magic Trackpad off and on (or Bluetooth off/on) with zoom on, then ⌥-pinch and ⌥-pan on it"
    expected: "TrackpadWatcher re-publishes the new registry ID to the tap, MultitouchDevices rescans, and both gestures work first time"
    why_human: "This Mac has only the built-in trackpad (05-SPIKE C5, UAT item 15 N/A). Hot-plug is covered only by fake-backend unit tests; the tap's sender-set refresh on hot-plug has no test. Since WR-06 the filter fails closed, so a missed refresh makes gestures pass to the app (no leak), not take"
human_verification:
  - test: "Relaunch on the post-fix build, then smoke-test ⌥-pinch in/out and ⌥-pan over Safari, and plain pinch over bare wallpaper"
    expected: "All four drive the desk; Safari neither zooms nor scrolls; no-⌥ wallpaper pinch is taken immediately"
    why_human: "UAT items 1-3 and 6 ran on code before WR-01..WR-10. WR-01 changed the no-⌥ wallpaper test and WR-02 changed pan start handling; the running Transom Debug (pid started 11:19) predates the fixes"
  - test: "Hold ⌥, pan halfway over Safari, rest fingers ~3 s, keep panning, lift"
    expected: "The stage springs back during the rest; Safari never scrolls, before or after"
    why_human: "Backstop truth (UAT item 10, skipped). WR-03 changed this exact path after UAT; only a headless rules test covers it"
  - test: "Over Safari: hold ⌃ and two-finger scroll; hold ⌘ and pinch; with a mouse, if present, hold ⌥ and wheel-scroll"
    expected: "Transom takes none of them; macOS/Safari behave as without Transom (⌃-scroll Accessibility zoom still works if enabled)"
    why_human: "E-05 says 'Confirm at user UAT'; item 7 and item 8 were skipped. WR-06 changed the sender filter after UAT. VM covers only synthetic chords and a discrete wheel"
  - test: "Turn on Reduce motion, ⌥-pinch apart past halfway, then turn Reduce motion off"
    expected: "The stage follows the fingers live; the finish is a fade, not a zoom"
    why_human: "Backstop truth (UAT item 11, skipped); headless StageFollowTests only"
  - test: "With 'Zoom in or out' on, Apple menu > Sleep, wake, then ⌥-pinch and ⌥-pan"
    expected: "Both work first time, no relaunch"
    why_human: "Backstop truth (UAT item 14, skipped). Host item 18 proved wake only for the multitouch pinch path (setting off)"
  - test: "Turn 'Zoom in or out' off, ⌥-pinch apart with some sideways finger drift and let it commit, then turn the setting back on"
    expected: "One zoom in; no second pan or flicker after the pinch"
    why_human: "WR-10 changed this path after UAT and it is only reachable on a real trackpad with the setting off"
---

# Phase 5: Gestures Verification Report

**Phase Goal:** As a trackpad user, I want to pinch and pan the desk with my fingers, so that zooming and moving around feels direct.
**Mode:** mvp (user-story goal validated by `user-story.validate`: valid)
**Verified:** 2026-10-30T18:53:47Z
**Status:** passed (human checks 1-6 passed on the rebuilt app, 2026-10-30)
**Re-verification:** No, initial verification

## User Flow Coverage

User story: «As a trackpad user, I want to pinch and pan the desk with my fingers, so that zooming and moving around feels direct.»

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Hold ⌥ and pinch apart over any app | Stage follows the fingers; past half a level it snaps one level in toward the tile under the fingers; the app doesn't zoom | `GestureTapRules.start` takes on ⌥ (GestureTapRules.swift:292); `GestureController.feed`/`apply` drive `beginFollow`/`follow` and commit via `controller.zoom(to:)` (GestureController.swift:293-397); host UAT 1 and 17a (built-in trackpad); spike T1 visibility over Safari, Preview, Finder, full-screen | ✓ (hardware evidence predates the review fixes) |
| Hold ⌥ and pinch together | One level out, or springs back when short | Host UAT 2, 17b; VM `anOptionPinchOutPastHalfGoesHome`, `aShortPinchSpringsBackWithoutASettle` | ✓ |
| Hold ⌥ and two-finger pan | Stage slides; past ⅓ or a flick it snaps to the neighbour, else springs back | Host UAT 3, 23; VM `anOptionPanPastAThirdMovesToTheNeighbour`, `aShortPanSpringsBack`; VM UAT 4 (rubber band at home) | ✓ |
| Pinch/pan on bare wallpaper, no ⌥ | Taken; over a window, the app gets it | Host UAT 6; VM `wallpaperWithoutOptionIsTaken`, `aWindowWithoutOptionPasses`, `aNoOptionPinchOnWallpaperZooms` (post-fix) | ✓ (WR-01 changed this test after host UAT) |
| Outcome: "zooming and moving around feels direct" | Live follow, one level per gesture, no lag, no leak | User on host: item 23 "feels fine"; items 1-3 no leak; G-01 re-check ~45 min with no crash | ✓, with 6 short hardware re-checks below |

## Goal Achievement

### Observable Truths

Roadmap success criteria are the contract (SC1-SC4); plan must-haves add detail. Hardware means the user's MacBook Air built-in trackpad; VM means synthetic CGEvents in the Tart guest.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: ⌥-pinch zooms in and out over any app (GEST-01) | ✓ VERIFIED | Code: ⌥ start → `taking(.optionHeld)`; a taken pinch consumes every type-29 sub-type except the 61/62 envelopes (C1). Hardware: UAT 1, 2, 17a/b. VM: `anOptionPinchIsConsumedWhole`, `anOptionPinchInPastHalfZoomsOneLevel`, `aLongPinchGoesExactlyOneLevel` (post-fix logs 13:43-13:44, after the last code commit at 13:40) |
| 2 | SC1: ⌥-two-finger pan moves the camera (GEST-02) | ✓ VERIFIED | Hardware: UAT 3, 23. VM: pan suites above, VM UAT 4. Headless: `mayBeginThenBeganIsOneSequence` (WR-02), recorded-trace recognizer tests |
| 3 | SC2: pinch and pan on bare wallpaper work without ⌥; over a window they pass (GEST-03, D-05) | ✓ VERIFIED | Code: no-⌥ start → tracked-window fast path (WR-01), then one CG window-list read → `.wallpaper` taken / `.window`, `.overlay` passed. Hardware: UAT 6 (before WR-01). VM post-fix: `wallpaperWithoutOptionIsTaken`, `aWindowWithoutOptionPasses`, `aNoOptionPinchOnWallpaperZooms`. Headless: `aTrackedWindowUnderThePointerPassesWithNoSurfaceRead`. Desktop-tile variant (UAT 21) not checked on hardware |
| 4 | SC3: a taken gesture is consumed whole, momentum included; nothing reaches the app (D-06) | ✓ VERIFIED | Code: decide-once latch held through momentum end; tap callback returns nil on consume (GestureTap.swift:221). Hardware: spike T2 "Nothing moved" in Safari/Preview; UAT 1-3 no leak. VM: `momentumTailNeverLeaks`, `subTypeFourInsideAnOptionPinchIsConsumed`. Headless: `anOptionPanIsConsumedThroughMomentumAndThePlainScrollAfterPasses`, `aTakenPinchTakesEverySubTypeButTheEnvelopes` |
| 5 | SC3: resting fingers >2 s mid-gesture never leak the tail (backstop, UAT 10) | ⚠️ insufficient_spec | WR-03 orphan latch (GestureTapRules.swift:205-207, 252, 262-267) and headless `aTakenGestureResumedAfterALongRestNeverLeaksItsTail` pass, but this is a backstop truth, the user skipped UAT 10, and WR-03 changed the behaviour after UAT. Human check 2 |
| 6 | SC3: ordinary pinch and scroll inside apps keep working: no-⌥ over a window passes untouched | ✓ VERIFIED | Hardware: spike T3 (7/7), UAT 6 ("Gestures taken" stayed at 60 over Safari). VM: `aWindowWithoutOptionPasses`, `optionPressedMidSequencePasses`; headless `aStrayChangedPassesAndKeepsPassing` |
| 7 | SC3: ⌃/⌘ chords (E-05, incl. ⌃-scroll Accessibility zoom) and mouse wheels (E-04) pass through (backstop, UAT 7-8) | ⚠️ insufficient_spec | Code: chord → `passing(.chord)` (line 291); discrete/unphased scroll → `.pass` (line 211); non-trackpad sender → `.notTrackpad`, fail-closed since WR-06. VM: `controlOrCommandChordsPass`, `aDiscreteWheelWithOptionPasses`. Not on hardware: E-05 explicitly required user confirmation; items 7 and 8 skipped; the sender filter has never seen a real mouse. Human check 3 |
| 8 | SC3: system gestures (four-finger Spaces, Mission Control) unaffected | ✓ VERIFIED | Product mask is scroll + type 29, never bit 30 (`theMaskHasScrollAndGestureButNeverDockControl`). Hardware: spike T4 with the same mask and rules (80 Dock-control events never consumed; Spaces and Mission Control normal); MT callback returns 0 (M2). UAT 24 itself skipped |
| 9 | SC4: gestures keep working after sleep/wake (backstop, UAT 14) | ⚠️ insufficient_spec | Code: wake re-publish (GestureController.swift:124-128), watchdog re-enable every 2 s (ArrangeController.swift:267-272), MT rescan on didWake (MultitouchDevices.swift:79-81). Hardware: UAT 18 (multitouch pinch path, setting off) and spike M3. VM: `wakeRepublishesState`. The tap path (setting on, UAT 14) was skipped. Human check 5 |
| 10 | SC4: gestures keep working after trackpad disconnect/reconnect | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `TrackpadWatcher` (IOKit first-match/terminated) refreshes tap senders; `MultitouchDevices.rescan` re-lists. Only fake-backend `aRescanStopsTheOldListBeforeListingAgain` exercises it. No Magic Trackpad on this Mac (C5, UAT 15 N/A). Needs your decision: accept as N/A here |
| 11 | SC4: private multitouch API unavailable → fallback, Transom still launches | ✓ VERIFIED | MultitouchSupport reached only by `dlopen`/`dlsym` into optionals (MultitouchSupport.swift:51-75); no link in Package.swift, no `@_silgen_name`; `--disable-private=Multitouch` skips the dlopen; `Capabilities` gates on `isLoaded && !MultitouchCanary.tripped`; `MultitouchDevices.start` checks `available()`. VM UAT 19: launched with `--disable-private=Multitouch`, "Multitouch: off, trackpad events only", ⌥-pinch still zoomed. Headless canary tests (trip, retry on new build, turn back on, armed until clean stop). G-01 crash fixed; host re-check ~45 min, no crash |
| 12 | D-07: gestures follow the zoom switch; zoom off runs no gesture tap and opens no multitouch device | ✓ VERIFIED | `updateGestureTap` starts only when `zoomEnabled && tap.isRunning` (ArrangeController.swift:297-305); `multitouch.start()` only from `GestureController.start` or Turn Multitouch Back On while active; WR-09 disarms during Turn Off Zoom's home move (`turningZoomOffDisarmsGestures`). VM: `zoomOffMeansNoGestureTapAndEverythingPasses`, VM UAT 13 (12/12, 15/15, 12/12 reached the tail tap) |
| 13 | D-01/D-02/E-02: live follow, snap one level through `zoomTo` → `.cameraMove` → `.cameraSettle`; camera rests only on a NodeID or home | ✓ VERIFIED | `gestureTarget` → `cameraStep` and `previewMove`/`zoomTo` share `planTiles` (Arranger+Camera.swift:221-272); commit is `controller.zoom(to:)`. VM: 13 GestureFollow tests; VM UAT 5 (one level per pinch). Hardware: UAT 1, 2, 23 |
| 14 | E-03: a gesture during a move continues from the current tiles without a jump | ✓ VERIFIED | `ZoomController.beginFollow` keeps the `interrupted` move and retargets from presentation rects. VM: `aGestureDuringAHotkeyMoveRetargetsWithoutStranding`, `aSpringBackDuringAMoveLetsThatMoveSettle`; VM UAT 9 (6-screenshot series). Frame-rate smoothness not judged on hardware |
| 15 | Reduce Motion: follow still tracks fingers, snap is a crossfade (backstop, UAT 11) | ⚠️ insufficient_spec | Headless `reduceMotionCrossfadesTheSnapAndFadesTheSpringBack` only; UAT 11 and 20 skipped. Human check 4 |
| 16 | Debug lines G1-G4 and refusal announcements | ✓ VERIFIED | `GestureCopy` (AppKit-free) wired into `StatusItemController` (lines 323-336); `GestureCopyTests`. VM UAT 12 (AXAnnouncementRequested "Nothing to zoom in to", "Showing …"), 16, 22. Host: "Gestures taken: 60, 3 ended by timeout", "Multitouch: available, 1 trackpad" |
| 17 | Multitouch pinch source while "Zoom in or out" is off (E-01 = tap+multitouch) | ✓ VERIFIED | `multitouchFrame` → `TwoFingerTracker` → the same recognizer (`aPinchGivesTheSameReleaseAsMultitouchFramesOrTapSamples`); `systemPinchZoomOn` gate. Hardware: UAT 17 (`TrackpadPinch` read 0, ⌥-pinch drove the desk, pans started no zoom), UAT 18. WR-10 changed the pinch/pan hand-off after UAT; human check 6 |

**Score:** 12/17 truths verified (1 present but behaviour-unverified, 4 backstop truths abstained as insufficient_spec)

### What rests only on automated or VM evidence (user-skipped UAT items)

| UAT item | Claim | Evidence left |
|---|---|---|
| 7 | ⌃-scroll / ⌘-pinch pass; E-05 ⌃-scroll Accessibility zoom still works | VM `controlOrCommandChordsPass`, headless `controlOrCommandWithOptionPassesButShiftConsumes` |
| 8 | Mouse wheel / Magic Mouse with ⌥ passes | VM `aDiscreteWheelWithOptionPasses` (discrete only). The trackpad sender filter has never seen a real non-trackpad sender |
| 10 | Resting fingers mid-gesture don't leak | Headless only, and **WR-03 rewrote this path after UAT** |
| 11, 20 | Reduce Motion follow + crossfade; takeover mid-crossfade (known opacity pop) | Headless `StageFollowTests`; VM item 9 without Reduce Motion |
| 14 | Sleep/wake with the tap path (setting on) | VM `wakeRepublishesState`; host item 18 covered only the multitouch path |
| 21 | No-⌥ pinch over the Desktop tile's empty area | VM wallpaper tests outside the Desktop tile; host item 6 |
| 24 | Four-finger Spaces / Mission Control with zoom on | Spike T4 on hardware with the same mask; product mask unit test |

VM-only UAT passes (synthetic events, not hardware): items 4, 5, 9, 12, 13, 16, 19, 22.

### Review fixes that changed behaviour after the user's UAT

All 10 warnings were fixed in commits 527f788..d4d9958, after the hardware UAT, which ran on the build after `7357a32`. Each is covered by new headless tests, and the VM suites re-ran green after the last code commit. None was re-checked on hardware:

| Fix | Behaviour change | Hardware re-check |
|---|---|---|
| WR-01 (527f788) | No-⌥ start over a tracked window's frame passes with no CG read in the callback | Check 1 (wallpaper still taken at once) |
| WR-02 (7fb5a34) | mayBegin→began pan is one sequence | Check 1 |
| WR-03 (f717ba8) | Expired taken latch becomes an orphan that swallows its tail; late momentum >0.3 s after lift is now swallowed | Check 2 |
| WR-04 (d809f4c) | Only zoom sub-types keep a pinch latch alive | Covered by check 1 |
| WR-05 (0bb43db) | Tap re-enable orphans taken sequences and ends open ones at once | Not reproducible on demand (callback path untestable headless/VM) |
| WR-06 (86c143e) | Sender filter fails closed: no trackpad found → every sender-bearing event passes | Check 1 (the built-in trackpad must still be recognised) and check 3 (mouse) |
| WR-07 (2472a61) | Buffered events after stop/restart dropped | n/a |
| WR-08 (39240af) | Debug ▸ Turn Multitouch Back On after a canary trip | Only after a trip; not requested |
| WR-09 (14ea5db) | Gestures disarmed during Turn Off Zoom's home move | n/a (VM-safe) |
| WR-10 (3ca01f9) | Tap sequences shut out by a multitouch pinch stay out until their end | Check 6 |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/TransomMac/Input/GestureTapRules.swift` | Pure consume rules, mask, state | ✓ VERIFIED | 336 lines; used by GestureTap callback and spike `main.swift:258` |
| `Sources/TransomMac/Input/GestureTap.swift` | Session tap on own thread, watchdog | ✓ VERIFIED | Wired from `ArrangeController.updateGestureTap` |
| `Sources/TransomMac/Input/Trackpads.swift` | IOKit trackpad IDs + hot-plug watcher | ✓ VERIFIED | Feeds `GestureController.refresh` |
| `Sources/TransomMac/Zoom/GestureController.swift` | Samples → recognizer → follow → commit | ✓ VERIFIED | 510 lines, wired |
| `Sources/TransomEngine/GestureRecognizer.swift` | GestureTuning, recognizer, TwoFingerTracker | ✓ VERIFIED | AppKit-free (`check-no-appkit.sh` OK, 45 files) |
| `Sources/TransomEngine/Arranger+Camera.swift` | previewMove, stillMove, gestureTarget | ✓ VERIFIED | Shares `planTiles` with zoomTo; calls `cameraStep` |
| `Sources/TransomMac/Zoom/ZoomController.swift`, `StagePanel.swift` | `.following`, beginFollow, follow, springBack, retarget | ✓ VERIFIED | |
| `Sources/TransomMac/Shell/GestureCopy.swift` | G1-G4 strings | ✓ VERIFIED | |
| `Sources/TransomPrivate/MultitouchSupport.swift` | dlsym shim | ✓ VERIFIED | |
| `Sources/TransomMac/Input/MultitouchDevices.swift` | Device lifecycle, canary, rescan | ✓ VERIFIED | |
| `Sources/transom-gesture-spike/Multitouch.swift` | Spike-only shim (05-01) | ✓ Intentionally moved | Promoted to `TransomPrivate/MultitouchSupport.swift` by 05-07; the spike now imports it |
| `Tests/TransomMacIntegrationTests/Gesture*IntegrationTests.swift` | VM suites | ✓ VERIFIED | 12 + 13 passed post-fix |

### Key Link Verification

The `verify.key-links` tool couldn't parse most `from:` fields, which mix a path with a symbol name, so these links were checked by grep.

| From | To | Via | Status |
|------|----|----|--------|
| GestureTap callback | `GestureTapRules.decide` | GestureTap.swift:219 | WIRED |
| Spike `main.swift` | `GestureTapRules.decide` | main.swift:258 | WIRED |
| GestureTapRules | GestureEventFields | field constants | WIRED |
| ArrangeController | GestureTap | `updateGestureTap` (start, access lost, watchdog, zoom on/off, quit) | WIRED |
| GestureController.refresh | Trackpads | `Trackpads.current()` → `trackpadSenders` | WIRED |
| `previewMove` / `zoomTo` | `planTiles` | Arranger+Camera.swift:221, 235, 244 | WIRED |
| `gestureTarget` | `Navigator.cameraStep` | Arranger+Camera.swift:258 | WIRED |
| GestureController release | `ArrangeController.zoom(to:)` | GestureController.swift:393 | WIRED |
| ZoomController run | `StagePanel.retarget(to:)` | ZoomController.swift:106 | WIRED |
| Capabilities `.multitouch` | `MultitouchSupport.isLoaded` + canary | Capabilities.swift:60 | WIRED |
| Multitouch frames | `TwoFingerTracker` | GestureController.swift:421 (not MultitouchDevices as planned) | WIRED (alternative location) |
| StatusItemController | GestureCopy | lines 323-336 | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Gesture tap state | deskDisplays, windowRects, trackpadSenders | `arranger` didSet → `gestures.publish()`; IOKit | Yes | ✓ FLOWING |
| Follow stage | tile rects | `previewMove`/`stillMove` from the live Arranger | Yes | ✓ FLOWING |
| Debug G1-G4 | taken, timeouts, lastGesture, multitouch status | GestureController counters, MultitouchDevices | Yes | ✓ FLOWING |

### Behavioral Spot-Checks (run by the verifier, headless, host)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Package builds | `swift build` | Build complete | ✓ PASS |
| Phase 5 headless suites | `swift test --filter 'GestureTapRulesTests\|GestureControllerTests\|GestureRecognizerTests\|GestureCopyTests\|MultitouchDevicesTests\|MultitouchCanaryTests\|CapabilitiesTests\|StageFollowTests'` | 60 tests in 8 suites + 22 tests in 1 suite passed, 0 failed | ✓ PASS |
| Model/Engine AppKit-free | `scripts/check-no-appkit.sh` | OK (45 files) | ✓ PASS |
| Full host suite (from log, not re-run) | `.build/review-fix-full.log` | 193 + 315 + 75 + 690 = 1,273 passed | ✓ (recorded) |
| VM suites (from logs, not re-run) | `.build/reviewfix-vm-*.log`, written 13:43-13:45, after the last code commit at 13:40 | 12 + 13 + 3 + 2 + 1 passed | ✓ (recorded) |
| Debug app is post-fix | `stat` on `Transom Debug.app/Contents/MacOS/Transom Debug` | built 13:46, after the fixes; a Transom Debug process started 11:19 (pre-fix) is still running | ⚠️ relaunch needed |

No event tap, multitouch device, window or Transom was opened on the host by the verifier.

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| none | n/a | No `scripts/*/tests/probe-*.sh` declared. The spike CLI is user-run hardware tooling, not a probe | SKIPPED |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| GEST-01 | 05-01, 02, 04, 05, 07, 08 | ⌥-pinch on the trackpad zooms in and out anywhere | ✓ SATISFIED | Truths 1, 13, 17; host UAT 1, 2, 17 |
| GEST-02 | 05-02, 04, 05, 08 | ⌥-two-finger pan moves the view | ✓ SATISFIED | Truth 2; host UAT 3, 23 |
| GEST-03 | 05-03, 04, 08 | Pinch and pan on bare desktop work without ⌥ | ✓ SATISFIED (Desktop-tile case unverified on hardware) | Truth 3; host UAT 6 (pre-WR-01); VM post-fix |
| GEST-04 | 05-01, 03, 06, 07, 08 | Keep working after sleep/wake and reconnect, never leak into the app | ? NEEDS HUMAN | No-leak core verified (truths 4, 6, 8). Resting-finger leak (truth 5), chords/mouse (truth 7), tap-path wake (truth 9) need hardware re-checks. Reconnect (truth 10) can't be tested on this Mac |

No orphaned requirements: REQUIREMENTS.md maps only GEST-01..04 to Phase 5, and every plan claims at least one of them.

### Decision Coverage

All 9 trackable CONTEXT.md decisions are honored by the shipped artifacts (`check.decision-coverage-verify`: 9/9).

### Test Quality Audit

| Test File | Linked Req | Active | Skipped | Circular | Assertion Level | Verdict |
|-----------|-----------|--------|---------|----------|-----------------|---------|
| GestureTapRulesTests | GEST-03, 04 | 25 | 0 | No | Value/behavioral (decision per event) | OK |
| GestureRecognizerTests | GEST-01, 02 | 22 | 0 | No. Recorded fixtures come from real host traces (spike) | Value | OK |
| GestureControllerTests, StageFollowTests, GestureCopyTests | GEST-01, 04 | pass | 0 | No | Value | OK |
| MultitouchDevicesTests, MultitouchCanaryTests, CapabilitiesTests | GEST-04 | pass | 0 | No (fake backend) | Behavioral | OK, but hot-plug is fake-only |
| GestureTap/GestureFollow/Multitouch integration | GEST-01..04 | 12/13/1 | `.enabled(if: IntegrationEnv.trusted)`, a VM gate, not a skip | No | Behavioral (downstream event counts, camera state) | OK |

Disabled tests on requirements: 0. Circular patterns: 0. Insufficient assertions: 0.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (phase sources) | n/a | No TBD/FIXME/XXX/TODO/HACK/placeholder | n/a | n/a |
| GestureController / GestureRecognizer | n/a | IN-07: pan direction follows natural scrolling | ℹ️ Info | Decided 2026-10-30: by design, pans follow the scroll setting like other apps; documented in UI-SPEC and GestureRecognizer |
| MultitouchDevices / GestureController | n/a | IN-03: rescan mid-pinch leaves stale trackers | ℹ️ Info | Rare (wake or hot-plug mid-pinch); open |
| MultitouchSupport | n/a | IN-01, IN-04 (stop of never-started devices; unbounded `Worker.sync`) | ℹ️ Info | Open, documented in 05-REVIEW-FIX |
| UAT risk | n/a | Reduce Motion takeover mid-crossfade can pop tiles to full opacity (item 20) | ℹ️ Info | Known, not looked at |

### Human Verification Required

All automated checks pass. These six hardware steps take about 5 minutes. Run them on the rebuilt `Transom Debug.app`.

1. **Relaunch + smoke test (WR-01, WR-02, WR-06).** Quit the running Transom Debug (menu bar icon ▸ Quit), relaunch it with `open "/Users/ken/dev/transomwm/xcode/.xcode-build/Build/Products/Debug/Transom Debug.app"` and turn zoom on. Over Safari, ⌥-pinch apart, ⌥-pinch together, ⌥-two-finger pan; then without ⌥, pinch apart over bare wallpaper. *Expected:* all four move the desk; Safari neither zooms nor scrolls; the wallpaper pinch starts at once.
2. **Resting fingers (WR-03, item 10).** Hold ⌥, pan halfway over Safari, rest your fingers about 3 s, keep panning, lift. *Expected:* the stage springs back during the rest; Safari never scrolls.
3. **Chords and mouse (E-05, item 7; WR-06, item 8).** Over Safari, hold ⌃ and two-finger scroll, then hold ⌘ and pinch. If a mouse is around, hold ⌥ and wheel-scroll. *Expected:* Transom does nothing; Safari/macOS behave normally (⌃-scroll Accessibility zoom works if you use it).
4. **Reduce Motion (item 11).** Turn on Accessibility ▸ Display ▸ Reduce motion, ⌥-pinch apart past halfway, then turn it off. *Expected:* the screen follows your fingers; the finish is a fade.
5. **Sleep/wake on the tap path (item 14).** With "Zoom in or out" on: Apple menu ▸ Sleep, wake, then ⌥-pinch and ⌥-pan. *Expected:* both work first time.
6. **Multitouch hand-off (WR-10).** Turn Trackpad ▸ "Zoom in or out" off, ⌥-pinch apart with a little sideways drift and let it commit, then turn the setting back on. *Expected:* one zoom in, no extra pan or flicker afterwards.

**Decision, not a step:** trackpad reconnect (SC4, truth 10) can't be tested on this Mac, which has no Magic Trackpad (C5). Accept it as N/A, or test it later on a Mac that has one.

### Gaps Summary

No blocking gaps. Every artifact exists, is substantive and is wired. Every key link holds, and the headless, VM and recorded full suites are green on the current tree. The phase goal works on hardware for its core flows: ⌥-pinch and ⌥-pan over apps, no-⌥ pinch on wallpaper, no leak, multitouch with the setting off, sleep/wake on the multitouch path, and the G-01 crash fixed. What remains open is evidence:

- Four backstop truths were skipped at UAT: resting fingers, chords and mice, Reduce Motion, and sleep/wake on the tap path.
- Five review fixes changed gesture behaviour after the hardware UAT: WR-01, WR-02, WR-03, WR-06 and WR-10.
- The Transom Debug process still running on the host predates those fixes.

Hence `human_needed`, with the six steps above.

---

## Human Verification Result (2026-10-30)

The user ran all six steps on the rebuilt `Transom Debug.app` (built-in trackpad): 1 smoke test, 2 resting fingers, 3 chords, 4 Reduce Motion, 5 sleep/wake with "Zoom in or out" on, 6 multitouch hand-off. All six passed. Trackpad reconnect (truth 10) was accepted as N/A. IN-07: pans follow the natural-scrolling setting, by design. Status: **passed**.

_Verified: 2026-10-30T18:53:47Z_
_Verifier: Claude (gsd-verifier)_
