---
phase: 05-gestures
reviewed: 2026-10-30T18:20:30Z
depth: standard
files_reviewed: 42
files_reviewed_list:
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
  - Tests/TransomEngineTests/Fixtures/Gestures/pan-flick.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/pan-left-third.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/pan-reverse.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/pinch-in-commit.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/pinch-out-short.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-down.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-maybegin-start.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-noise.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pan-up.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pinch-in-small.jsonl
  - Tests/TransomEngineTests/Fixtures/Gestures/recorded-pinch-out.jsonl
  - Tests/TransomEngineTests/GestureRecognizerTests.swift
  - Tests/TransomMacIntegrationTests/GestureFollowIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift
  - Tests/TransomMacIntegrationTests/MultitouchIntegrationTests.swift
  - Tests/TransomMacTests/CapabilitiesTests.swift
  - Tests/TransomMacTests/GestureCopyTests.swift
  - Tests/TransomMacTests/GestureTapRulesTests.swift
  - Tests/TransomMacTests/MultitouchDevicesTests.swift
  - Tests/TransomMacTests/StageFollowTests.swift
  - Tests/TransomMacTests/ZoomOffTests.swift
  - scripts/vm-live-test.sh
  - scripts/vm-spike.sh
findings:
  critical: 0
  warning: 10
  info: 7
  total: 17
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-10-30T18:20:30Z
**Depth:** standard
**Files Reviewed:** 42 (scope: `git diff 856c52f^..HEAD -- Sources Tests scripts`)
**Status:** issues_found

## Summary

I reviewed the gesture tap and its rules, the multitouch shim and device lifecycle, the gesture follow in GestureController, ZoomController and StagePanel (the E-03 takeover, spring back and resume), the engine preview and recognizer, the Debug lines and the VM scripts. I traced the follow and takeover paths in ZoomController against `camera.pending`. I found no path that leaves the stage on screen for good, strands a pending move, or settles one twice:
- `interrupted` plus `resume` settles an interrupted move exactly once.
- The `generation` guard drops stale fade and spring-back completions.
- Every open follow is resolved by either the tap's 2.05 s timeout or the recognizer's 2 s fingers-down timeout.

The G-01 fix (`FrameSink`, `7357a32`) is sound. The callback thread only takes a C lock, appends a value type and does an atomic add. No closure sits behind generic lock state. Frames reach main in order, and a list a rescan dropped is filtered out by its tag. There is no deadlock between `Worker.sync` and the callback thread. The struct layout reads are bounded and nil-checked, and the Int32 return is right on both ABIs.

The defects are in the event-tap consume decisions and the main-side event handling:
- A gesture's tail can leak into the app after the latch expires (rest over 2 s) or after a tap re-enable.
- A mayBegin-started pan is split in two, which double-counts the taken counter.
- A stale pinch latch can be kept alive indefinitely.
- The E-04 sender filter turns itself off on a Mac with no trackpad.
- The no-⌥ path does a CG window-list read inside the tap callback that was never measured.
- The crash canary blames every abnormal exit on multitouch and never heals itself.

None of these break windows or input permanently, so none is Critical. Several do break GEST-04 ("never leak into the app") or E-04 on reachable paths.

Headless checks: `swift build` OK; `swift test --filter 'GestureTapRulesTests|GestureRecognizerTests'` passed (22 recognizer tests; the rules suite ran in the TransomMacTests bundle). Nothing that opens a tap, device or window was run.

No `<structural_findings>` block was provided, so there is no fallow section.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Every no-⌥ gesture start does a CG window-list read inside the session tap callback

**File:** `Sources/TransomMac/Input/GestureTapRules.swift:258`, `:292-298`, called from `Sources/TransomMac/Input/GestureTap.swift:214`
**Issue:** When ⌥ is not held, `start()` calls `surface(location)`, and that is `liveSurface` → `CGWindowList.onScreenFrontToBack()`. This is a full `CGWindowListCopyWindowInfo` plus bridging of every window dictionary into Swift, run synchronously in an active head-insert session tap. It runs for **every** trackpad scroll or pinch start on a desk display, which is nearly every scroll the user makes. Under WR-02 it runs twice per pan.
- The project rule is under ~1 ms with no heavy work in the callback.
- 05-SPIKE T5 says this cost was never measured on the host ("the CG-read cost is unmeasured on the host and is re-checked in 05-03's VM tests and 05-08 UAT"). Neither 05-03 nor 05-08 recorded a number.
- On failure, `CGWindowList.read` also logs from inside the callback.

**Failure scenario:** With 40+ windows open, every scroll start in every app stalls all scroll delivery system-wide for the length of the window-list copy, typically several milliseconds and more under load. It adds risk of `tapDisabledByTimeout`, which in turn triggers WR-05.
**Fix:** Publish the hit-test data from main, as `greenButtons` and `GestureTapState` already are, and keep the callback to an array scan:
```swift
// GestureTapState: add
public var windowRects: [(rect: CGRect, layer: Int)]   // front-to-back, own pid removed, refreshed on frame/space/display changes
// GestureTapRules.start: replace surface(location) with
GestureTapRules.surface(at: location, in: state.windowRects, display: displayFrame)
```
If staleness is a concern, defer the no-⌥ decision: pass the first event and take from the second, after main has answered. Either way, measure p99 with a no-⌥ consume run before shipping.

### WR-02: A pan that starts with mayBegin (128) then began (1) is decided twice and split into two gestures

**File:** `Sources/TransomMac/Input/GestureTapRules.swift:191-193`, `Sources/TransomMac/Input/GestureTap.swift:75-86`, `Sources/TransomMac/Zoom/GestureController.swift:210-218`
**Issue:** `first = scrollPhase == 128 || scrollPhase == 1`, so the phase-1 event that follows a 128 calls `start()` again and makes a new `Sequence` with a new `started`. `track()` sees `after.started == now` and `live?.started != now`. It yields `.ended` for the 128 summary and opens a second summary with a new seq. Real pans start this way (`Fixtures/Gestures/recorded-pan-maybegin-start.jsonl`: 128 at t=0, then 1 at t=0.000226).
On main:
- the 128 sample opens a follow and calls `endPick`;
- `.ended(seq1)` then runs `finishFollow`, which sets `lastGesture = .tooSmall`, and `logEnd`, which logs `taken += 1` and "took pan #1 … too small";
- the real gesture follows as seq 2 and is counted again.

**Failure scenario:** Each ⌥-pan that starts with mayBegin inflates "Gestures taken" (G2) by one and logs a spurious "too small" line. "Last gesture" reads "pan, too small" for the whole pan. The surface read runs twice, and the decision can flip between the two events if a modifier changes in between. The recognizer tests feed 128 and 1 into one recognizer, so they never exercise this split.
**Fix:** Treat began as the continuation of a latched mayBegin:
```swift
// Sequence: add `var sawOnlyMayBegin = false`
let continuesMayBegin = input.scrollPhase == 1 && latch.pan?.sawOnlyMayBegin == true
let first = (input.scrollPhase == 128 || input.scrollPhase == 1) && !continuesMayBegin
if first { latch.pan = start(...); latch.pan?.sawOnlyMayBegin = input.scrollPhase == 128 }
else { latch.pan?.sawOnlyMayBegin = false }
```
Then add a GestureTapRules test asserting that 128 → 1 → 2 → 4 is one sequence (one `started`, one summary).

### WR-03: Resting fingers more than 2 s mid-gesture leaks the rest of the gesture to the app

**File:** `Sources/TransomMac/Input/GestureTapRules.swift:185-186`, `:194-196`, `:211-215`, `:229-231`; `Sources/TransomMac/Zoom/GestureController.swift:207-208`
**Issue:** A trackpad sends no events while the fingers are still. After `fingersDownTimeout` (2 s) of quiet:
- Main's `expire` springs the stage back under the user's fingers.
- The tap's latch expires at the next event. That event is phase 2 (scroll) or zoom phase 2, not a start, so `decide` makes a `.midSequence` sequence with `consuming: false` and **passes** every remaining event (changed, ended, momentum) to the app under the pointer.

**Failure scenario:** The user holds ⌥ over Safari, pinches halfway, pauses about 2.5 s, then keeps pinching. Transom's stage springs back and Safari zooms the page. With a pan, Safari scrolls, momentum included. This breaks D-06 / GEST-04 success criterion 3. UAT item 10 (rest mid-scroll) was skipped.
**Fix:** The expiry is not needed for Pitfall 4, because every new start (phase 128/1, zoom phase 1) already decides afresh. When a **consuming** latch expires, keep an orphan marker that consumes the sequence's non-start events (without samples) until the next start of that kind:
```swift
if let pan = latch.pan, isExpired(pan, now: now) {
    latch.pan = pan.consuming ? Sequence(kind: .pan, consuming: true, started: pan.started, lastEvent: now,
                                         optionHeld: pan.optionHeld, passReason: nil, reason: nil, orphan: true) : nil
}
// in the pan branch: `guard sequence.consuming else { return .pass }; return .consume(sequence.orphan ? nil : sample(...))`
```
Main already resolves the stage at 2.05 s, so the orphan tail only needs to be swallowed. Pair this with WR-04, so the pinch orphan expires only on a zoom end or a new zoom start.

### WR-04: A consuming pinch latch is kept alive by non-zoom sub-types and can swallow type-29 events indefinitely

**File:** `Sources/TransomMac/Input/GestureTapRules.swift:216-225`
**Issue:** Inside a pinch latch, `sequence.lastEvent = now` is refreshed by **every** type-29 event. The latch ends only on a zoom sub-type with phase 4/8. Every two-finger scroll also emits type-29 companions (05-SPIKE item 3: sub-types 0, 6 and 32, 1,874 events in one run). If a taken pinch's zoom end is ever lost (dropped event, tap restarted mid-pinch by the watchdog, sub-type change), the consuming latch never reaches `fingersDownTimeout`. It keeps consuming every type-29 event except 61/62 (C1), including the gesture companions of later ordinary scrolls and rotations, until the next zoom phase 1.
**Failure scenario:** After a lost pinch end, ordinary two-finger scrolling in apps loses its type-29 companion events for as long as the user keeps using the trackpad without pauses over 2 s. Smooth-scroll, elastic-scroll and swipe-navigation recognition in apps that use NSEvent gesture phases can misbehave, and nothing in the Debug lines shows it.
**Fix:** Refresh `lastEvent` only on zoom sub-type events, so a latch with no zoom traffic expires in `fingersDownTimeout`:
```swift
if zoom { sequence.lastEvent = now }
```
Optionally also cap the total latch age (for example 10 s) as a backstop.

### WR-05: A tap re-enable mid-gesture drops the open sequences silently, leaking the tail and freezing the stage for 2 s

**File:** `Sources/TransomMac/Input/GestureTap.swift:192-201`
**Issue:** On `.tapDisabledByTimeout`/`.tapDisabledByUserInput` the callback sets `latch = .none` and `pan = pinch = nil` without yielding `.ended`. Every later event of the consumed gesture is a non-start, so it passes as `.midSequence` into the app. On main, the follow gets no more samples and no `.ended`, so the stage stays frozen until `timeoutTimer` fires 2.05 s later and springs it back. The spike recorded a tap disable on the host (item 3 run), so this path does occur.
**Failure scenario:** During an ⌥-pinch over Preview, macOS disables the tap (user input or timeout, made more likely by WR-01). Preview zooms for the rest of the pinch while Transom's stage sits frozen over the screen for about 2 s.
**Fix:** On re-enable, turn open consuming latches into the WR-03 orphan state instead of dropping them. Also yield the open summaries as ended, so main resolves the stage at once:
```swift
for summary in [box.pan, box.pinch].compactMap({ $0 }) {
    var ended = summary; ended.endedByTimeout = true; box.continuation.yield(.ended(ended))
}
box.latch = box.latch.orphaned()   // consuming slots keep swallowing non-start events, no samples
box.pan = nil; box.pinch = nil
```

### WR-06: The E-04 sender filter turns off when no trackpad is found, and Magic Mouse is identified by one unverified family constant

**File:** `Sources/TransomMac/Input/GestureTapRules.swift:252`, `Sources/TransomMac/Zoom/GestureController.swift:191`, `Sources/TransomMac/Input/Trackpads.swift:13,27`, `Sources/TransomPrivate/MultitouchSupport.swift:41,103`
**Issue:** `!state.trackpadSenders.isEmpty` means an empty set disables the filter. `Trackpads.current()` excludes family 112, so on a desktop Mac whose only multitouch device is a Magic Mouse the set is empty and the filter is off. Magic Mouse scrolls are continuous and phased, so they pass the `isContinuous`/phase guard. They are then taken:
- with ⌥ over any app;
- without ⌥ over wallpaper.

"Not a Magic Mouse" (family ≠ 112, duplicated in two files) also stands in for "is a trackpad". It is unverified for other Magic Mouse models, and it would admit any other multitouch device, such as the Touch Bar on 2016–2022 MacBook Pros, if the framework lists one. UAT item 8 (mouse with ⌥) was skipped.
**Failure scenario:** A Mac mini or iMac user with a Magic Mouse holds ⌥ and scrolls in an editor where ⌥-scroll means something. Transom consumes the scroll and pans the desk instead. That breaks E-04 ("Mouse wheels and Magic Mouse scroll always pass through untouched").
**Fix:** Fail closed: with a non-zero sender and no known trackpad, pass.
```swift
if input.senderID != 0, !state.trackpadSenders.contains(input.senderID) { return passing(.notTrackpad) }
```
Senders that are 0 (synthetic VM events) still go through. Identify trackpads positively, for example by the IOKit driver class (`AppleMultitouchTrackpadHIDEventDriver`) or a trackpad-only property, and keep that one predicate in one file for both `Trackpads` and `MultitouchSupport.Info.isTrackpad`.

### WR-07: GestureController.handle processes buffered tap events after `stop()`, so a stage can appear after the tap is gone

**File:** `Sources/TransomMac/Zoom/GestureController.swift:126-133`, `:138-153`, `:197-220`
**Issue:** The `reader` task lives across stops, and `handle` has no `isActive` check. Samples still in the `AsyncStream` buffer when `stop(reason:)` runs (for example "access lost" from `stopTap`/the watchdog, where zoom stays on) are handled afterwards. `feed` opens a new follow, calls `endPick`, and once a buffered sample crosses the dead zone `beginFollow` orders the stage in. Nothing ends it until `timeoutTimer` fires 2.05 s later. After a watchdog restart (`updateGestureTap`: stop then start), the old tap's samples are handled as if current.
**Failure scenario:** Accessibility is revoked mid-⌥-pinch. The tap stops and `finishFollow` springs the stage back. Then the buffered samples re-open a follow and put the stage back over the screen for about 2 s while the gesture tap is already gone.
**Fix:** Gate on activity and drop sequences from before the current start:
```swift
private var seqFloor: UInt64 = 0
// start(), after tap.start() succeeds:
seqFloor = tap.counters().lastSeq
// handle():
guard isActive else { return }
if case .sample(_, let seq) = event, seq <= seqFloor { return }
```

### WR-08: The crash canary blames every abnormal exit on multitouch and never heals itself

**File:** `Sources/TransomPrivate/Capabilities.swift:131-168`, `Sources/TransomMac/Input/MultitouchDevices.swift:100`, `:119-121`
**Issue:** Since `7357a32` the canary is armed for as long as multitouch runs, which is the whole zoom-on session, normally the app's whole lifetime. It clears only at a clean stop. So it trips on any of these, none of which need involve MultitouchSupport:
- a crash in unrelated code (AX, an engine precondition, AppKit);
- `kill -9` or Force Quit;
- a jetsam kill;
- a kernel panic or power loss;
- an Xcode stop during development.

After a trip, multitouch stays off until the macOS build or the app version changes, which can be weeks. There is no retry count, no reset in the UI (Debug only says "off after a crash last launch"), and `isTripped()` never clears a matching canary.
**Failure scenario:** A user with "Zoom in or out" off, the exact C4 audience, has Transom crash once in AX code. From then on ⌥-pinch does nothing until the next macOS update.
**Fix:** Require evidence that points at multitouch. Options:
- Trip only after two consecutive armed unclean exits (store a count in the canary dictionary).
- Use the existing clean-exit record (`writeCleanExit`) and trip only if the previous session was unclean **and** the canary was armed.
- Add a "Retry multitouch" item in the Debug submenu that clears the key.

### WR-09: Gestures stay armed during Turn Off Zoom's home move and can hijack it

**File:** `Sources/TransomMac/Zoom/GestureController.swift:164-180`; `Sources/TransomMac/ArrangeController.swift:652-668`
**Issue:** `setZoomEnabled(false)` sets `turningOff`, starts the home moves and waits up to 3 s for their reveal. In that window `zoomEnabled` is still true and `publish()` does not look at `turningOff`, so the tap stays armed. An ⌥-gesture then takes over the home move (E-03). If it commits, `ZoomController.run(Y)` supersedes the home move (`interrupted[uuid] = nil`), so `revealed(uuid, moveID:)` never matches `awaitingHome`. Zoom-off completes only through the 3 s `zoomOffFallback`, with the camera moved away from home in the meantime and Y's stage purged mid-settle.
**Failure scenario:** The user picks Turn Off Zoom and pinches while the desk moves home. The view zooms somewhere else, about 3 s pass, then everything snaps to the zoom-off layout.
**Fix:** Expose `isTurningOff` from ArrangeController and disarm while it is true:
```swift
let disarm: GestureTapState.DisarmReason? =
    !controller.isReady() ? .notReady
    : (!arranger.pauseReasons.isEmpty || controller.isTurningOff) ? .zoomPaused
    : arranger.isDragging || controller.isRectZoomActive ? .rectZoomOrDrag : nil
```
Call `gestures.publish()` right after `turningOff = true`.

### WR-10: When a multitouch pinch ends, the tap's still-running pan sequence takes the stage over

**File:** `Sources/TransomMac/Zoom/GestureController.swift:268-281`, `:408-410`
**Issue:** While a started multitouch follow owns the stage, `feed` drops samples of any tap sequence (`open.seq >= multitouchSeqBase, open.started, !open.ended → return`) but records nothing about them. When the pinch ends, `finishFollow` sets `follow = nil`. Tap events trail multitouch by about 63 ms (05-SPIKE M4), so the next late phase-2 sample of the same consumed ⌥-pan seq finds no follow and opens a **new** pan follow mid-sequence. That follow can lock an axis, `beginFollow` takes over the pinch's committing move (E-03), and it then springs back or commits a second, unintended pan on a flick.
**Failure scenario:** With "Zoom in or out" off, the user ⌥-pinches with some centroid drift, so the tap also consumes a pan. The pinch commits, and the stage jumps into a pan follow and either flickers back or pans one more area.
**Fix:** Remember tap sequences suppressed by a multitouch follow and ignore them until their `.ended`:
```swift
private var suppressed: Set<UInt64> = []
// feed(): instead of a bare return
if let open = follow, open.seq >= Self.multitouchSeqBase, open.started, !open.ended { suppressed.insert(seq); return }
if suppressed.contains(seq) { return }
// handle(.ended): suppressed.remove(summary.seq); expire(): suppressed.remove(seq)
```

## Info

### IN-01: stopStreaming stops and unregisters devices it never started

**File:** `Sources/TransomPrivate/MultitouchSupport.swift:308-319`
**Issue:** `startStreaming` registers and starts only the chosen devices (trackpads). `stopStreaming` calls `MTUnregisterContactFrameCallback` and `MTDeviceStop` on every device in the list, Magic Mouse included. What these calls do on a device the process never started is undocumented.
**Fix:** Record the started devices in `DeviceList`, or filter by `isTrackpad` in the same way, and stop only those.

### IN-02: The spike's `synth` subcommand has no VM guard

**File:** `Sources/transom-gesture-spike/main.swift:548`, `:1397`
**Issue:** `synth` posts synthetic ⌥ scroll and gesture events into the session. Only `vm-spike.sh` keeps it in the guest. Running it directly on the host posts gesture events there, against the project's "agents never … on the host" rule.
**Fix:** Refuse to run `synth` unless `sysctlbyname("kern.hv_vmm_present")` reads 1, or unless an explicit `--i-am-in-the-vm` flag is given.

### IN-03: A rescan mid-pinch leaves stale trackers and an orphaned multitouch follow

**File:** `Sources/TransomMac/Zoom/GestureController.swift:386-399`; `Sources/TransomMac/Input/MultitouchDevices.swift:104-117`
**Issue:** A rescan (IOKit match or terminate of any multitouch device, or wake) gives frames a new generation tag. The old tracker never sees phase 4 and `trackers` is never pruned. At the next phase 1, `multitouchPinch` is overwritten without `finishFollow`, so the started follow is resolved only by the recognizer's 2 s fingers-down timeout: a 2 s frozen stage, then a spring back, and no "took pinch #m" line.
**Fix:** Give MultitouchDevices an `onRescan` callback that clears `trackers` and finishes an open multitouch follow.

### IN-04: Worker.sync blocks main with no bound

**File:** `Sources/TransomPrivate/MultitouchSupport.swift:273-282`
**Issue:** `done.wait()` waits forever for `MTDeviceStart`/`MTDeviceStop` on the worker thread. A driver that wedges, for example when a device is pulled mid-call, would hang main, and the event-tap watchdog with it.
**Fix:** Use `done.wait(timeout: .now() + 2)`, then log and mark multitouch off for the session on timeout.

### IN-05: `loggedByTimer` grows when an `.ended` never arrives

**File:** `Sources/TransomMac/Zoom/GestureController.swift:76`, `:227`
**Issue:** Sequences dropped by the tap re-enable path (WR-05) never send `.ended`, so their seq stays in the set forever. This is a small leak.
**Fix:** Clear it in `stop(reason:)`, or keep only the last few.

### IN-06: A two-finger rest over wallpaper ends pick mode

**File:** `Sources/TransomMac/Zoom/GestureController.swift:279`
**Issue:** `endPick(reason: "gesture")` runs at the first consumed sample, even for 128 → 8 noise with no motion (C2), which the recognizer later treats as "never started".
**Fix:** Move `controller?.endPick(reason: "gesture")` into `apply(.started)`.

### IN-07: Pan direction assumes natural scrolling

**File:** `Sources/TransomEngine/GestureRecognizer.swift:66`, `:176-177`
**Issue:** Directions are derived from scroll deltas "as macOS delivers them (natural scrolling)". With natural scrolling off, an ⌥-pan moves the desk the opposite way relative to the fingers. That may be intended (it follows the user's scroll preference), but it is not stated or tested.
**Fix:** Decide the behaviour and document it in `GestureTuning`/UI-SPEC. If finger-relative motion is wanted, normalise using `NSEvent(cgEvent:)?.isDirectionInvertedFromDevice` on main.

---

_Reviewed: 2026-10-30T18:20:30Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
