---
phase: 05-gestures
plan: 03
subsystem: input
status: complete
tags: [gestures, event-tap, iokit, lifecycle, vm]
requires:
  - "05-01: GestureTapRules, GestureEventFields, spike verdict (go with conditions, E-01 tap+multitouch, C1/C3, T6)"
provides:
  - "GestureTap: the product gesture session tap (scroll + type 29, never bit 30), own thread/run loop, watchdog, per-sequence summaries, bounded AsyncStream<GestureTapEvent>"
  - "GestureController: main-actor owner; publishes GestureTapState, logs each gesture once at its end, counters taken/timeouts/passedWithOption/republished, lastSummary, latestSample, timeout timer"
  - "Trackpads / TrackpadWatcher: public IOKit AppleMultitouchDevice enumeration and hot-plug notifications"
  - "ArrangeController.updateGestureTap(reason:), isGestureTapRunning, gestureTapFailedToStart, gestures"
  - "ZoomInput.isBandActive (gestures disarmed during a ⌘⇧-drag)"
  - "GestureTapRules C1: a taken pinch takes every type-29 sub-type except the 61/62 envelopes; GestureTapRules.isExpired"
affects: [05-04, 05-05, 05-06, 05-07, 05-08]
tech-stack:
  added: [IOKit (public, AppleMultitouchDevice matching)]
  patterns:
    - "Second active session tap scoped to the zoom switch (D-07): exists only while zoom is on and the mouse tap runs"
    - "Tap thread keeps one open summary per kind in step with the latch; main logs once per gesture"
    - "Main-side timeout timer writes the line when the tap sees no further event; the late .ended adds none"
key-files:
  created:
    - Sources/TransomMac/Input/GestureTap.swift
    - Sources/TransomMac/Input/Trackpads.swift
    - Sources/TransomMac/Zoom/GestureController.swift
    - Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift
  modified:
    - Sources/TransomMac/Input/GestureTapRules.swift
    - Sources/TransomPrivate/GestureEventFields.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Zoom/ZoomInput.swift
    - Sources/transom-gesture-spike/main.swift
    - Tests/TransomMacTests/GestureTapRulesTests.swift
    - Tests/TransomMacTests/ZoomOffTests.swift
    - scripts/vm-live-test.sh
key-decisions:
  - "C1: a consuming pinch latch takes every type-29 sub-type (4, 0, 6, 32, 5, …) except the 61/62 envelopes, which still pass so an app that saw the start envelope (it comes before zoom began) also sees the end one"
  - "Pan companions: a consuming pan latch does NOT take type-29 events (sub-types 0/6/32). Smallest rule: they carry no scroll motion, the host showed nothing moved, and taking them would let a scroll latch swallow another gesture's type-29 events"
  - "hidRotate = 5 kept but documented as doubtful (host: 4 seen 91x, 5 twice; 4 is IOHID translation); decide no longer depends on it"
  - "C3: trustsTargetPID stays false (field 40 = frontmost app on host and VM)"
  - "E-04 sender filter ON (GestureController.filtersBySender = true): field 87 = the AppleMultitouchDevice registry ID (0x100000a1f, confirmed again with ioreg on the host)"
  - "Quiet after lift (0.3 s, no momentum) is a normal end and logs the took line; only fingers-down quiet (2 s) or a lost pinch end logs 'released … by timeout'"
requirements-completed: [GEST-03, GEST-04]
metrics:
  duration: "~16 min"
  started: 2026-10-29T23:55:12Z
  completed: 2026-10-30T00:11:00Z
actuals:
  tokens: 14900
  tasks: 2
  commits: 3
plan_head_before: 8968fffde9f93fcefaa50fd66128148846944830
plan_head_after: 16eb5ca21af1a2d57c625de91bc78d4e678338f9
---

# Phase 5 Plan 03: Product Gesture Tap Summary

**Transom now has a second session tap for scroll and type-29 gesture events. It exists only while zoom is on and the mouse tap runs. It takes ⌥ gestures, and no-⌥ gestures over bare wallpaper, from first event through momentum end, with every type-29 sub-type inside a taken pinch (spike C1). A main-actor GestureController logs each gesture once and re-publishes the tap's state on wake, display change, Space change and trackpad hot-plug. In the Tart VM, 12 of 12 synthetic leak and pass-through scenarios pass.**

## What was built

- **GestureTap** (`Sources/TransomMac/Input/GestureTap.swift`): the same thread, run loop, start/stop and trial-port watchdog shape as InputTap, which is unchanged. Its mask is `GestureTapRules.mask`. The callback:
  - re-enables the tap after `tapDisabledBy*`, clears the latch and open summaries, and counts the re-enable;
  - otherwise copies the fields, runs `GestureTapRules.decide` with `liveSurface`, and consumes or passes.
  - It keeps one open `GestureTapSummary` per kind in step with the latch. It yields `.sample` for consumed events that carry a sample, and `.ended` when a sequence ends, is replaced by a new start, or is found expired (`endedByTimeout`).
  - Short-circuited sequences only bump a counter. There is no logging, AX or file I/O in the callback.
  - Sequence numbers are per launch, kept in the shared counter lock.
- **GestureController** (`Sources/TransomMac/Zoom/GestureController.swift`):
  - `start()` and `stop(reason:)` own the tap's lifecycle lines.
  - `publish()` sets armed = zoom on && ready && not paused && no move-drag && no rect-zoom band. It fills deskDisplays and fullScreenDisplays the way ZoomInput does, plus finderPID and trackpad senders. It publishes only on change and only while active.
  - `republish(reason:)` re-enumerates trackpads and Finder's pid.
  - It logs each gesture with the UI-SPEC lines: "took …", "released … by timeout …", debug "passed {kind} with ⌥: …" and "passed {kind}: window under pointer / menu or popover under pointer".
  - It keeps the counters, `lastSummary` and `latestSample`, plus a WakeTimer for gestures whose end the tap only sees at the next event.
- **Trackpads / TrackpadWatcher** (`Sources/TransomMac/Input/Trackpads.swift`): use public IOKit only. They enumerate `AppleMultitouchDevice` (registry ID and "Family ID"; family 112 is excluded), release every io_object, and register first-match and terminated notifications on the main run loop.
- **ArrangeController**:
  - `updateGestureTap(reason:)` starts the tap iff `zoomEnabled && tap.isRunning`, restarts it if macOS took it down, and stops it otherwise.
  - It is called from `startTap`, `stopTap` (access lost), the watchdog (which also ticks the gesture tap and logs re-enables), `setZoomEnabled(true)` and `finishZoomOff` (zoom off). `restoreForTermination` stops the gesture tap directly with reason `quit`.
  - `gestures.publish()` runs in the arranger didSet and in accessChanged. `republish` runs on `.displaysChanged` and `.spaceChanged`.
- **ZoomInput**: adds `isBandActive`, and re-publishes the gesture state at band start and end. `deskKey` is now internal so it can be shared.
- **vm-live-test.sh**: runs `caffeinate -u -t 2` in the guest, then runs the helper under `caffeinate -dimsu` (Pitfall 11).

## Spike conditions applied (the plan predates them)

1. **C1** (`GestureTapRules.decide`): `let taken = zoom || hidRotate || hidType == 0` was replaced. A consuming pinch now takes every type-29 sub-type except the 61/62 envelopes. The old "spike gate T2 decides" comment now records the decision. New unit test: `aTakenPinchTakesEverySubTypeButTheEnvelopes` (sub-types 4, 0, 6, 32, 5 and 7 are consumed, envelopes pass, nothing is taken after the zoom ends or inside a passing pinch). VM coverage:
   - product tap: `subTypeFourInsideAnOptionPinchIsConsumed` (0 downstream);
   - spike harness: `synth --scenario alt-pinch-subtype-4` posted 9 events and 0 went downstream (`.build/spike/gesture-synth-20261029-190952`).
   - **Envelopes kept passing**, against the literal "every sub-type". The start envelope arrives before zoom began, so it always reaches the app. Consuming an end envelope that lands inside the latch would leave the app's gesture open. A4 held on the host.
2. **hidRotate**: kept at 5 (published sources). It is now documented as doubtful for real hardware, where sub-type 4 is likely IOHID translation, and decide no longer depends on it.
3. **Pan companions (decided: not taken).** A consuming pan latch leaves type-29 events alone. Sub-types 0, 6 and 32 carry no scroll delta, and the host saw nothing move with them passing. Taking them would mean a pan latch deciding type-29 events, which could swallow a separate rotate or smart-zoom. The trailing sub-type 0 after a zoom ended also passes, because the latch is already gone.
4. **C3**: `trustsTargetPID` stays false, and its doc comment now cites T6.
5. **E-04**: the sender filter is **on**. T6 showed field 87 = 0x100000a1f, and `ioreg` on the host gives the same id for the AppleMultitouchDevice (read-only check). In the VM there is no trackpad, so the sender set is empty and the filter is off there (rules: an empty set means not known).

## Tests

- Host: `swift test --filter ZoomOffTests` ran **2 tests, passed**. `GestureTapRulesTests` ran **20 passed**. `GestureTapRulesTests|ZoomOffTests|TransomEngineTests|TransomModelTests` ran 686 + 193 + 22 passed, no "✘". `scripts/check-no-appkit.sh` OK.
- VM (Tart pane-test, macOS 15.7.7, display woken): `scripts/vm-live-test.sh GestureTapIntegrationTests` ran **12 of 12 passed**:

| Test | Result |
|---|---|
| anOptionPinchIsConsumedWhole | 0 downstream, ≥10 samples, one taken `.ended` with 12 consumed |
| zoomOffMeansNoGestureTapAndEverythingPasses | zoom off: no tap, 12/12 downstream; zoom on: tap, 0; zoom off again: tap gone, 12/12 |
| subTypeFourInsideAnOptionPinchIsConsumed (C1) | 0 downstream |
| momentumTailNeverLeaks | 0 downstream, summary taken with 17 consumed, not timed out |
| optionPressedMidSequencePasses | 10/10 downstream |
| aDiscreteWheelWithOptionPasses | 5/5 |
| controlOrCommandChordsPass | 12/12 pinch, 10/10 scroll |
| wallpaperWithoutOptionIsTaken | 0 (pinch and pan with momentum) |
| aWindowWithoutOptionPasses | 12/12, 10/10 |
| aStuckLatchReleasesTheNextScroll | first 4 taken, after 2.2 s the plain pan 10/10 |
| aDisabledGestureTapIsReEnabledByOneTick | enabled after one tick |
| wakeRepublishesState | republish counter grew; stopTap stopped the gesture tap |

- VM regression: `InputTapIntegrationTests|ZoomSettleIntegrationTests|QuitRestoreIntegrationTests` ran 8 of 8 passed.
- No tap, multitouch device, window or Transom launch ran on the host. The VM was started with `tart run pane-test` and stopped at the end.

## Deviations from Plan

1. **[Spike C1] Rule change in GestureTapRules** (commit ea70e5b), with the envelope exception and the pan-companion decision described above. `GestureTapRules.isExpired` was made public so the tap can tell "ended by its own event" from "expired".
2. **[Rule 1 - correctness] A quiet lift is not a timeout.** The plan said to log "released … by timeout" whenever the main timer fires first. But a pan lifted without momentum always ends by the 0.3 s quiet expiry, so every slow pan would have read as a timeout. Now fingers-up quiet logs the normal "took" line, and only fingers-down quiet (2 s) or a pinch that never ended logs "released … by timeout" and counts `timeouts`. The summary carries `fingersUp` for this.
3. **Downstream counter is an active pass-through tail tap, not listen-only.** This is the spike's proven counter ("so it surely runs after the consumer"). It still uses `.tailAppendEventTap` and passes every event.
4. **Restart of a dropped tap.** When macOS takes the gesture tap down while zoom is on and the mouse tap runs, `updateGestureTap` logs a stop and starts it again (the watchdog path). "failed to start" is logged once until a start succeeds.
5. **Trackpad watcher and wake observers live only while the tap runs.** Zoom-off Transom adds no IOKit port or observers (D-07 spirit). `finderPID` is read on start and re-publish, not on every arranger change: it is unused while `trustsTargetPID` is false.
6. **ZoomOffTests "zoom on" half** constructs the controller and calls `gestures.publish()` without dispatching a camera command. On the host that proves no tap and no stage.
7. **Extra spike scenario** `alt-pinch-subtype-4` was added to `transom-gesture-spike synth`, as the orchestrator asked.

## Known Stubs

- `GestureController.latestSample` is stored but has no consumer yet. Intentional: plan 05-04 feeds samples to the recognizer.
- The UI-SPEC debug line "gesture counters: … every 60 s" isn't implemented. It wasn't in this plan's tasks. The counters exist (`taken`, `passedWithOption`, `timeouts`, `GestureTap.counters().shortCircuited`) for 05-06.

## Threat Flags

None beyond the plan's register. T-05-08 (stuck latch) is covered by `aStuckLatchReleasesTheNextScroll`. T-05-09: the callback does no logging or AX. T-05-10: `stopTap`/`accessChanged(false)` and the refused trial port stop the gesture tap. T-05-12: logs hold only kinds, counts, durations and reasons.

## Notes for later plans

- 05-04: `GestureController.handle(.sample)` is where the recognizer goes. The main timer (`expire`) already decides end versus timeout, and the recognizer's `timeout(now:)` polling can hang off the same WakeTimer.
- 05-06: `isGestureTapRunning`, `gestureTapFailedToStart`, `gestures.taken`, `gestures.timeouts` and `gestures.lastSummary` are available. The passed-reason text lives in `GestureController.optionPassText` for now; move it to GestureCopy.
- 05-07: `updateGestureTap(reason:)` and `GestureController.start/stop` are the lifecycle hooks, and `TrackpadWatcher` can be reused for multitouch rescans.
- Magic Trackpad sender IDs (field 87 against the IOKit registry ID) are untested on real hardware (C5).

## Self-Check: PASSED

- FOUND: Sources/TransomMac/Input/GestureTap.swift, Sources/TransomMac/Input/Trackpads.swift, Sources/TransomMac/Zoom/GestureController.swift, Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift
- FOUND commits: ea70e5b, b4b4440, 16eb5ca
