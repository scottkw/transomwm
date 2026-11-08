---
phase: 05-gestures
plan: 07
subsystem: input
status: complete
tags: [gestures, multitouch, private-api, crash-canary, debug-menu]
requires:
  - "05-01: spike shim (Sources/transom-gesture-spike/Multitouch.swift), validated M1/M2 on macOS 27.2"
  - "05-02: GestureRecognizer.Sample / feed (source-neutral)"
  - "05-03: GestureTapRules.decide, TrackpadWatcher, ArrangeController.updateGestureTap"
  - "05-06: GestureCopy, Debug G1-G3"
provides:
  - "TransomPrivate.MultitouchSupport: the one dlopen/dlsym shim (spike CLI uses it too), isLoaded, DeviceList, Worker, start/stopStreaming, setHandler"
  - "Capability.multitouch (--disable-private=Multitouch) and MultitouchCanary (privateCanary.Multitouch)"
  - "TransomEngine.TwoFingerTracker: two-finger frames to GestureRecognizer samples"
  - "TransomMac.MultitouchDevices: start/stop with the gesture tap, IOKit + wake rescan, canary arm/clear, backend seam"
  - "GestureCopy.Multitouch / multitouchLine (G4), Source.onWithMultitouch (G1); ArrangeController.isMultitouchRunning, multitouchStatus"
affects: [05-08]
tech-stack:
  added: []
  patterns:
    - "Private-API crash canary: arm before the risky call, clear after 2 s of healthy frames or at a clean stop; tripped per OS build + app version"
    - "A second gesture source decides ownership by calling the tap's own GestureTapRules.decide with a synthetic zoom-began input"
key-files:
  created:
    - Sources/TransomPrivate/MultitouchSupport.swift (moved from Sources/transom-gesture-spike/Multitouch.swift)
    - Sources/TransomMac/Input/MultitouchDevices.swift
    - Tests/TransomMacTests/MultitouchDevicesTests.swift
    - Tests/TransomMacIntegrationTests/MultitouchIntegrationTests.swift
  modified:
    - Sources/TransomPrivate/Capabilities.swift
    - Sources/transom-gesture-spike/main.swift
    - Sources/TransomEngine/GestureRecognizer.swift
    - Sources/TransomMac/Zoom/GestureController.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Shell/GestureCopy.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Tests/TransomMacTests/CapabilitiesTests.swift
    - Tests/TransomEngineTests/GestureRecognizerTests.swift
    - Tests/TransomMacTests/GestureCopyTests.swift
    - Tests/TransomMacTests/ZoomOffTests.swift
key-decisions:
  - "C4 gate: multitouch drives a pinch only while System Settings > Trackpad > Zoom in or out is off (CFPreferences com.apple.AppleMultitouchTrackpad TrackpadPinch; absent = on). With it on, the tap sees the pinch and multitouch stays out, so two sources never follow one gesture"
  - "Ownership of a multitouch pinch is GestureTapRules.decide on a synthetic zoom-began at the pointer (⌥ from CGEventSource.flagsState, wallpaper via liveSurface, armed, desk display, ⌃/⌘ pass, sender = device registry ID)"
  - "A started multitouch pinch keeps the stage against tap pan samples (the tap still consumes them); before it leaves the dead zone a tap gesture takes over"
  - "Multitouch lifecycle lives in GestureController.start/stop (exactly when the tap starts/stops), not inline in ArrangeController.updateGestureTap; restoreForTermination's gestures.stop(quit) clears the canary on a clean quit"
  - "MultitouchDevices reuses TrackpadWatcher for IOKit first-match/terminated instead of a second notification-port implementation"
requirements-completed: [GEST-01, GEST-04]
metrics:
  duration: "~56 min"
  completed: 2026-10-30
commits: 4
plan_head_before: b1ebf3f5dd69a494bee5bde417ae988369088c57
plan_head_after: 95e1679925a787ec49b6c304940b9b2797a4fe87
actuals:
  tokens: 16300
  tasks: 3
  commits: 4
---

# Phase 5 Plan 07: Multitouch Pinch Source Summary

E-01 was "tap+multitouch", so this plan shipped. MultitouchSupport now sits in TransomPrivate as a dlopen-only shim. It runs behind `Capability.multitouch` and a per-build crash canary. Its two-finger frames feed the same `GestureRecognizer` the tap feeds, through `TwoFingerTracker`. It supplies pinch only when the tap can't see one, which is when Trackpad ▸ "Zoom in or out" is off. The tap still does all the consuming.

## What was built

- **Shim (Task 1).** The spike's shim moved unchanged in its safety rules: the Int32 callback always returns 0, touch counts are bounded to 0...20 and nil-checked, the stride is 96 bytes, and list devices are never released.
  - `--disable-private=Multitouch` skips the `dlopen`.
  - `isLoaded` requires CreateList, Start, Stop, Unregister and one register symbol.
  - Frames go to one `setHandler` closure. The spike keeps its own queue on top of that, and its `Multitouch.swift` is gone (`git grep MTDeviceCreateList -- Sources` lists only the product file).
- **Canary.** `MultitouchCanary` stores `{osBuild, appVersion, started}` under `privateCanary.Multitouch`. `tripped` is decided once per launch:
  - same build and version: off for that launch, logged "multitouch off: crash canary from last launch (build b, version v)";
  - a different build or version: the canary is cleared and multitouch is retried.
  - The capability is `MultitouchSupport.isLoaded && !MultitouchCanary.tripped`.
- **TwoFingerTracker (Task 2, TransomEngine).** Exactly two fingers in state 3 or 4 start a gesture (phase 1) and continue it (phase 2). Any other count ends it (phase 4).
  - Pinch: m = Δdistance / startDistance, so 1 + Σm equals the distance ratio.
  - Pan: centroid Δ in mm × 72/25.4, with y flipped.
- **MultitouchDevices (TransomMac).**
  - `start()` arms the canary, lists devices through the backend, and installs a TrackpadWatcher (IOKit first-match/terminated) plus a `didWake` observer.
  - A rescan closes the old list (stop, unregister, drop) before opening a new one. It logs "added {built-in|external} family f" and "removed registry id".
  - The canary is cleared 2 s after the first frame, or at stop.
  - `MultitouchBackend` is the seam: the real `ShimMultitouchBackend` tags each list's frames with a generation base so stale frames are dropped, and tests use a fake.
- **GestureController.** It starts and stops `multitouch` with the tap.
  - At the first two-finger frame, `takesMultitouchPinch` checks the Trackpad preference and then runs `GestureTapRules.decide` on a synthetic zoom-began.
  - Multitouch sequences use seq numbers ≥ 2^62, so they never collide with the tap's.
  - When the fingers lift, the follow is finished and "took pinch #mN: multitouch, ⌥ held|wallpaper, n frames, ms, outcome" is logged, and the gesture counts in G2.
- **Debug (Task 3).** G4 sits after G3: "Multitouch: available, 1 trackpad / n trackpads / no trackpad found", "off, trackpad events only", or "off after a crash last launch, trackpad events only". The count comes from the open devices, or from the IOKit trackpad list when zoom is off. G1 reads "Gestures: on, trackpad events and multitouch" while devices are open.

## Verification

- `swift test --filter 'CapabilitiesTests|MultitouchCanaryTests'`: **14 tests in 3 suites passed**.
- `swift test --filter 'GestureRecognizerTests|MultitouchDevicesTests'`: **22 tests in GestureRecognizerTests + 5 in MultitouchDevicesTests passed**. These include the invariant test: one pinch as multitouch frames or as tap samples gives the same Release.
- `swift test --filter 'GestureCopyTests|ZoomOffTests'`: **10 tests in 2 suites passed** (includes `zoomOffOpensNoMultitouchDevice`).
- Full `swift test`: 193 + 305 + 75 + 690 tests passed, 0 failures (the FreezeTest flake didn't occur).
- `scripts/check-no-appkit.sh`: OK (45 files).
- VM tracer: `SPIKE_PRODUCT=transom-gesture-spike scripts/vm-spike.sh mt-devices --seconds 10` gave `.build/spike/gesture-mt-devices-20261029-234023`. 12 of 12 symbols were found through the product shim, the log said "Trackpads: none found", there was no crash, and out.jsonl has the MTDeviceCreateList entry.
- VM suite `MultitouchIntegrationTests.noDevicesIsGracefulThroughTheRealShim`: **1 test passed** in the guest (macOS 15.7.7, no MT device). With the real shim it starts with 0 devices, shows status `.available(0)` / "Multitouch: available, no trackpad found", survives a wake rescan, and stops with the canary cleared.
- Host check (read-only): `CFPreferencesCopyAppValue("TrackpadPinch", "com.apple.AppleMultitouchTrackpad")` returned true with the setting on. No tap, device, window or Transom launch on the host.
- Acceptance greps: `case multitouch` 1; `MTDeviceRelease(` 0 in the shim and 0 in MultitouchDevices; Package.swift has no linkerSettings and no framework link; `privateCanary.Multitouch` 1; `kIOFirstMatchNotification` 1 (doc comment: the notification is installed through `TrackpadWatcher`); `TwoFingerTracker` in GestureRecognizer.swift; `multitouchLine` in StatusItemController 1; `zoomOffOpensNoMultitouchDevice` 1.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Multitouch lifecycle placed in GestureController.start/stop**
- **Found during:** Task 2
- **Issue:** The plan put the start/stop in `ArrangeController.updateGestureTap`, but the tap's real start (and its failure) happens inside `GestureController.start()`. Inline in ArrangeController, it would need a separate check of the tap's state.
- **Fix:** `multitouch.start()` runs right after `tap.start()` succeeds, and `multitouch.stop()` runs in `stop()`. ArrangeController exposes `isMultitouchRunning` and `multitouchStatus`. The behaviour is the same: devices run exactly while the tap runs.
- **Commit:** 8efdf52

**2. [Rule 2 - Correctness] Trackpad-preference gate for the multitouch pinch (C4)**
- **Found during:** Task 2
- **Issue:** M4 shows multitouch leads the tap by ~248 ms on a pinch. With system pinch-zoom on, multitouch would start every pinch and then be cancelled when the tap's sample arrived, a visible stage glitch.
- **Fix:** Multitouch drives a pinch only when `TrackpadPinch` reads false. This is the case where checklist item 3 showed the tap gets no zoom events.
- **Commit:** 8efdf52

**3. [Rule 3 - Blocking] Public inits on MultitouchSupport.Info and Frame**
- **Issue:** The fake backend in TransomMacTests can't build these values across modules with internal memberwise inits.
- **Fix:** Added explicit public inits.
- **Commit:** 33de681 / 8efdf52

**4. GestureCopy.swift committed with Task 2**
- `MultitouchDevices.status` returns `GestureCopy.Multitouch`, so the enum and line function went in with Task 2 to keep that commit compiling. The G4 tests and menu line are in Task 3.

**5. Added a VM integration suite (orchestrator handoff)**
- `MultitouchIntegrationTests` checks the graceful "no devices" behaviour in the guest. Plain `scripts/vm-live-test.sh` hung after its build step (see Issues), so I ran the same staged bundle and guest command by hand, in a separate guest directory that was removed afterwards.
- **Commit:** 95e1679

## Issues Encountered

- **swift-package processes stuck in exit (E state).** Since 21:44, before this plan started, several `swift build`/`swift test` processes print their result and then never exit. That includes one from an earlier session (`swift build --build-tests`, pid 83447). Test logs were read as they were written. One of my wrappers, `scripts/vm-live-test.sh MultitouchIntegrationTests` (pid tree under the bx2kni8t0 task), is still waiting on its stuck `swift build` child. The auto-mode classifier refused `kill -9` on those processes. The VM is stopped, so if that child ever exits, the script fails at ssh and its EXIT trap removes `.build/transom-vm.lock`. If the lock dir is still there, remove it before the next VM run.

## Known Stubs

None.

## Threat Flags

None. Every surface is in the plan's threat model (T-05-20..23): the callback returns 0, touches are bounded, no list device is released, no frame is logged, and only device counts and registry IDs are logged.

## Risks for UAT (05-08)

- The `TrackpadPinch` key is confirmed on the host only with the setting **on** (true). Whether it reads false with "Zoom in or out" off is untested. If it doesn't, multitouch never takes a pinch and pinch is lost with the setting off, the same as tap-only.
- With the setting off and ⌥ held, a pan whose finger spacing changes by 3% or more before the tap's pan arrives (~63 ms) could start a multitouch pinch. Once started, that pinch keeps the stage.

## Self-Check: PASSED

- FOUND: Sources/TransomPrivate/MultitouchSupport.swift, Sources/TransomMac/Input/MultitouchDevices.swift, Tests/TransomMacTests/MultitouchDevicesTests.swift, Tests/TransomMacIntegrationTests/MultitouchIntegrationTests.swift
- FOUND commits: 33de681, 8efdf52, 3629f5a, 95e1679
