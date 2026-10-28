# Phase 5: Gestures - Research

**Researched:** 2026-10-28
**Domain:** macOS trackpad input (CGEventTap gesture/scroll events, private MultitouchSupport.framework), live-follow camera on the Phase 4 stage
**Confidence:** MEDIUM overall. Event-type and field semantics are HIGH (verified locally against AppKit's own decoder on macOS 27.0.1 and four independent sources). Whether a session tap can *consume* a magnify over other apps on macOS 14–27 is MEDIUM: there is strong indirect evidence and no direct proof. The spike decides it.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### A. Pinch feel
- **D-01:** Live pinch, snap on release.
  - While the fingers move, the Phase 4 stage follows the pinch continuously, scaling the overlay between the current view and its parent or child level.
  - On lift, the camera snaps to the nearest layout level (home or a node) with the standard ~250 ms ease-out.
  - Real windows then settle once, using the existing `.cameraMove` → `.cameraSettle` path: one AX write per changed, visible window.
  - Reduce Motion: the live tracking still follows the fingers, but the snap uses the crossfade.
- **D-02:** No free-scale resting camera. The camera always comes to rest on a NodeID view or home, so the Phase 4 model (NodeID targets, history, parking) is unchanged. A settled gesture pushes history exactly like a hotkey move. — **Reversibility:** costly — a free camera would touch Navigator, history, parking and settle.

#### B. Pan feel
- **D-03:** Live drag, snap to neighbour.
  - The stage slides with the fingers.
  - On lift, a drag past about one third of the view (or a flick) snaps to the neighbouring area chosen by Phase 4's pan rule (`Navigator.pan`: same depth, longest shared edge, recency).
  - A shorter drag springs back.
  - At home there is no neighbour, so a pan rubber-bands and springs back.

#### C. Where gestures apply
- **D-04:** With ⌥ held, pinch and pan act over any app (GEST-01/02).
- **D-05:** Without ⌥, gestures act only while the pointer is over visible bare wallpaper: no window under it, including the empty area of the Desktop tile. Over any window, ⌥ is required (GEST-03).
- **D-06:** Gestures Transom handles are fully consumed, so no scroll or magnify reaches the app under the pointer. All other pinches and scrolls pass through untouched (GEST-04, success criterion 3).
- **D-07:** Gestures follow the zoom switch. When zoom is off (Phase 4 Turn Off Zoom), gestures do nothing and no multitouch device is opened.

#### D. Testing (VM has no trackpad)
- **D-08:** Recorded traces plus user UAT.
  - Gesture recognition (pinch scale, pan translation, flick, the snap decision) lives in AppKit-free engine code. It is tested headless with recorded or synthetic touch-frame traces.
  - The event-tap consume/pass-through logic is tested in the Tart VM with synthetic scroll and magnify events.
  - Real-trackpad checks are short checklists the USER runs on their Mac at two points: the spike gate (multitouch vs event-tap comparison) and the final phase UAT.
  - Agents never open windows, start event taps or open multitouch devices on the host.
- **D-09:** The phase-research spike (ROADMAP) compares MultitouchSupport raw touches with event-tap magnify/gesture events (CGEvent types 29/30). It covers visibility over other apps, the ability to consume, the MT callback struct layout and the macOS 27 `int32_t` return. Its live half is a user-run harness on the host trackpad: one small CLI that prints measurements, with no windows and no layout changes. Its results gate the rest of the phase, like the Phase 4 spike.

### Claude's Discretion
- MultitouchSupport shim internals in `Sources/TransomPrivate/` (own dlsym shim modelled on OpenMultitouchSupport headers; never depend on OpenMultitouchSupport 4.x).
- Which path is primary and which is fallback, decided from the spike data. If neither works, gestures turn off with a Debug-menu status line, and hotkeys, URLs and menu still drive zoom.
- Gesture thresholds: pinch dead-zone, the one-third pan threshold tuning, flick velocity, rubber-band strength.
- Device re-enumeration on wake and hot-plug (both the built-in trackpad and a Magic Trackpad), and a per-API crash canary in the Capabilities registry.
- Debug-menu lines for multitouch device and gesture state.

### Deferred Ideas (OUT OF SCOPE)
- Gesture settings (sensitivity, on/off, no-⌥ wallpaper toggle) belong in the Phase 9 Settings window.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GEST-01 | ⌥-pinch on the trackpad zooms in and out anywhere | Gesture tap with `(1 << 29)` in its mask decodes magnify (HID type 8) and latches the whole sequence at its first event when ⌥ is held (Pattern 2). The pure `GestureRecognizer` turns magnification into progress toward `stepIn`/`stepOut` (Pattern 3). The stage's follow mode tracks it, then snaps through the existing `zoomTo` → `.cameraMove` → `.cameraSettle` (Pattern 4). Spike gates T1/T2. |
| GEST-02 | ⌥-two-finger pan moves the view | Same latch on phased continuous scroll events (`scrollWheelEventScrollPhase` / `MomentumPhase`). Momentum is swallowed through its end. Axis lock, then the ⅓-view threshold or a flick, choose `Navigator.pan(edge:)`; otherwise spring back, or rubber-band at home (Pattern 3). |
| GEST-03 | Pinch and pan on bare desktop work without ⌥ | At latch time only, the wallpaper test: target PID is Finder or none, then one `CGWindowList.topmostWindow` read, which already excludes Transom's own panels (Pattern 2, Pitfall 6). |
| GEST-04 | Gestures keep working after sleep/wake and trackpad reconnect, and never leak into the app under the pointer | The tap path doesn't depend on the device: events come through whichever trackpad produced them, so it survives reconnects. Add a tap watchdog and re-publish on `screensDidWake`. The MT path, if shipped, re-enumerates on IOKit first-match/terminated notifications plus `didWake`. "Never leak": consume from the sequence's first event through momentum end, never start consuming mid-sequence, and a latch timeout guarantees release (Pitfalls 1–4). A crash canary covers the private API (Pattern 6). |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

These carry the same authority as locked decisions:
- **Testability:** `TransomModel` and `TransomEngine` must not import AppKit, enforced by `scripts/check-no-appkit.sh`, which also forbids Cocoa, SwiftUI, WebKit, Quartz and Carbon. Gesture recognition and snap math go in `TransomEngine`, using plain `Double` types.
- **Private APIs:** each one goes in **one file** in `TransomPrivate`, reached with `dlopen`/`dlsym` and never linked, with a fallback, logged availability, and an entry in the `Capabilities` registry plus the `--disable-private=` switch.
- **Clean room:** never consult the TrellisWM binary. **Loop is GPL-3.0**: read it for patterns only. In this research, these GPL or non-commercial sources were read for facts only and **must not be copied**: rokartur/BetterCmdTab (GPL-3), moonbai-studio/tungsten-edge (GPL-3) and bitvibelabs/TicTap ("free for noncommercial use"). These are MIT/0BSD and may be adapted with attribution: OpenMultitouchSupport, ScrollToZoom, Mac-trackpad-mapper, Hammerspoon touchdevice, noswoosh, InstantSpaceSwitcher and iss.
- **Do not depend on OpenMultitouchSupport 4.x.** It needs macOS 15 and ships a binary XCFramework (STACK.md "What NOT to Use").
- **Event taps:** keep the callback under ~1 ms, do no AX/file I/O/logging inside it, re-enable on `tapDisabledByTimeout`/`tapDisabledByUserInput`, run a watchdog, and use the narrowest mask (STACK.md Input; PITFALLS 5).
- **Live tests run only in the Tart VM** (`scripts/vm-live-test.sh`, `scripts/vm-spike.sh`). Every `swift test --filter` gate must show a non-zero executed count. Agents never open windows, event taps or multitouch devices on the host (CONTEXT D-08, user memory).
- **Swift 6 language mode, tools-version 6.2.** `TransomMac` uses `.defaultIsolation(MainActor.self)`, so the tap and MT callbacks must be `nonisolated` and bridge to main explicitly.
- **Python rules** (venv) don't apply: no Python in this phase.
- **Ponytail / "smallest change"** and "need 3 real examples before abstracting": don't build a generic input-device abstraction. Build one gesture tap and, only if the spike says so, one MT shim.

## Summary

Every two-finger trackpad gesture already reaches a CGEventTap as public or near-public events:
- A pinch is a stream of **CGEvent type 29** (`kCGSEventGesture`) events whose sub-type field 110 is 8 (zoom), with the phase in field 132 and the magnification in field 113. AppKit's own `NSEvent(cgEvent:)` turns exactly that into `NSEventTypeMagnify`. This was verified on this machine (macOS 27.0.1).
- A two-finger pan is a stream of ordinary `scrollWheel` (22) events with public phase and momentum fields.
- **Type 30 is not magnify at the CGEvent level.** It is `kCGSEventDockControl` (Spaces/Mission Control swipes). `NSEvent.EventTypeMask.magnify` equals `1 << 30`, so putting it in a CGEventTap mask silently taps Dock swipes instead of pinches. This is the most expensive trap in the phase.

Raw MultitouchSupport touches can't be consumed. On macOS 27 a non-zero callback return may starve the *system* gesture recognizer, but that is one beta report and must never be relied on. So **an active session event tap is required on every path**, because D-06/GEST-04 need it. The MT path adds three things: pinch for users who turned off "Zoom in or out" in Trackpad settings (no magnify events are generated then, so nothing leaks), insurance if a future macOS hides gesture events from taps, and possibly lower latency. It costs a private framework, device enumeration, hot-plug and sleep handling, and a crash canary.

The recommended architecture:
1. A **separate gesture tap**, created only while zoom is on, keeps Phase 3/4's mouse-only `InputTap` and the zoom-off guarantee untouched. A pure `GestureTapRules` latches each scroll or magnify sequence at its first event and consumes it through momentum end.
2. A pure, AppKit-free `GestureRecognizer` in TransomEngine turns the latched samples into progress and a snap decision.
3. A **follow mode** on `ZoomController`/`StagePanel` shows the stage at once from cached snapshots, lerps tiles between the engine's *previewed* move (a non-committing `zoomTo`), and on lift either commits through the normal `zoomTo` → `.cameraMove` path (which already retargets from presentation rects) or springs back with no engine involvement.

**Primary recommendation:** Run the spike first, with a `transom-gesture-spike` CLI the user runs on the host plus a VM half. Default decision rule: if the tap gates T1–T5 pass, **the event tap is primary for both recognition and consumption**, and the MT shim stays in the spike target, not shipped. Ship MT as a secondary recogniser only if the spike shows a real gap the tap can't fill: pinch-zoom disabled in Trackpad settings, magnify not delivered over wallpaper, or a measured latency lead of ≥ 30 ms. In that case it gets a crash canary and IOKit hot-plug. Confirm this with the user at the spike gate (Open Question 1).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Seeing and consuming gesture/scroll events | Shell: `TransomMac/Input` gesture tap (own thread, own CFRunLoop) | Pure rules `GestureTapRules` (TransomMac, CoreGraphics types, unit-tested) | Only an active session tap can swallow events. The decision must be synchronous in the callback, so it can't wait for main |
| Wallpaper hit test (D-05) | Tap thread at latch time (target PID check, then one CG window list read) | Main publishes `GestureTapState` (armed, desk displays, Finder PID) | No AX in the tap (PITFALLS 5); the CG list read is precedent from `ZoomTapRules.needsWindow` |
| Gesture recognition (scale, translation, axis lock, flick, snap decision) | Engine: `TransomEngine/GestureRecognizer.swift` (pure, `Double`) | — | D-08: AppKit-free, headless-testable with traces |
| Snap targets | Engine: existing `Arranger.cameraStep(.stepIn/.stepOut/.pan(edge))` | `Navigator.stepIn/stepOut/pan` | D-02/D-03 reuse Phase 4's rules unchanged |
| Preview of a move (no commit) | Engine: new non-mutating `Arranger.previewMove(to:displayUUID:)` split out of `zoomTo` | — | `zoomTo` sets `camera.pending` (line 251). Live follow must not create pending moves or history |
| Live stage tracking | Shell: `ZoomController` follow phase + `StagePanel.follow(progress:)` | Snapshot cache (04-04) | Overlay-only animation (Phase 4 D-A); real windows move once at settle |
| Commit and settle | Existing `zoomTo` → `.cameraMove` → `ZoomController.run` (retarget from presentation) → `.cameraSettle` | History push at settle (unchanged) | D-01/D-02: one AX write per changed visible window, history like a hotkey |
| Raw touches (only if the spike keeps MT) | `TransomPrivate/MultitouchSupport.swift` (dlsym shim) | `TransomMac` device manager (IOKit notifications, wake) | Private-API isolation constraint |
| Crash canary, capability | `TransomPrivate/Capabilities.swift` (new `.multitouch` case) + a `UserDefaults` canary | Debug submenu line | PITFALLS 4 (AeroSpace #101 pattern) |
| Gesture on/off with zoom (D-07) | `ArrangeController.setZoomEnabled` creates/destroys the gesture tap (and MT devices) | — | Zoom off must stay exactly Phase 3 |

## Standard Stack

### Core (all system frameworks: no new dependencies)

| API | Availability | Purpose | Why Standard |
|-----|--------------|---------|--------------|
| `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, ...)` | macOS 10.4+ | See and consume scroll and gesture events | The only public mechanism that can swallow input for other apps. Already used by `InputTap` [VERIFIED: Sources/TransomMac/Input/InputTap.swift:187-189 read this session] |
| CGEvent scroll fields `scrollWheelEventScrollPhase` (99), `scrollWheelEventMomentumPhase` (123), `scrollWheelEventIsContinuous` (88), `scrollWheelEventPointDeltaAxis1/2` (96/97) | public | Pan deltas, phases, momentum | Public SDK fields [VERIFIED: SDK CGEventTypes.h, quoted in "Verified Event Facts"] |
| Gesture event type 29 with fields 110 / 113 / 132 | undocumented, stable since 10.5 | Pinch (magnify) detection | Verified on macOS 27.0.1 through AppKit's own `NSEvent(cgEvent:)` bridge (see Verified Event Facts) |
| `NSEvent(cgEvent:)` | macOS 10.5+ | Oracle in the spike and in tests (cross-checks field decoding); never in the hot path | Public; maps the private fields to `.magnify`, `.magnification`, `.phase` |
| `CGEvent(scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:)` + `CGEvent(source:)` with `type = CGEventType(rawValue: 29)!` | 10.13+ / 10.4+ | Synthetic scroll and magnify for VM tests | Verified to build correct events in memory on macOS 27.0.1 (probe below) |
| IOKit `IOServiceAddMatchingNotification` (`kIOFirstMatchNotification` / `kIOTerminatedNotification`) on `IOServiceMatching("AppleMultitouchDevice")` | public | MT hot-plug (only if MT ships) | Used by ScrollToZoom (MIT) [CITED: github.com/alphaArgon/ScrollToZoom STZMagicZoom.c]. Class present on this host [VERIFIED: `ioreg -c AppleMultitouchDevice`] |
| `NSWorkspace.didWakeNotification` / `screensDidWakeNotification` | public | Re-publish tap state; MT re-enumeration | Already observed by `SessionGate` [VERIFIED: Sources/TransomMac/SessionGate.swift:32-35] |

### Private (only if the spike keeps the MT path): `MultitouchSupport.framework`

Every symbol below is exported on this host. This is a static read of the dyld shared cache with `xcrun dyld_info -exports /System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`, run 2026-10-28 on macOS 27.0.1 (26A434). Output excerpt, verbatim:
```
_MTDeviceCreateFromService   _MTDeviceIsBuiltIn   _MTDeviceGetDeviceID   _MTDeviceGetSensorSurfaceDimensions
_MTDeviceStop   _MTDeviceCreateList   _MTDeviceGetService   _MTDeviceGetFamilyID   _MTDeviceCreateDefault
_MTDeviceRelease   _MTDeviceIsAvailable   _MTDeviceStart   _MTDeviceIsRunning   _MTDeviceGetDriverType
_MTDeviceIsMTHIDDevice   _MTDeviceIsAlive   _MTRegisterContactFrameCallback
_MTRegisterContactFrameCallbackWithRefcon   _MTUnregisterContactFrameCallback
```
[VERIFIED: dyld_info exports, presence only. Signatures are prior art (below), not verified.]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| A separate gesture tap | Widen `InputTap.mask` | One tap, but scroll events would hit the Phase 3 tap's callback with zoom off. That breaks "zoom off = Phase 3 exactly" and adds per-scroll cost system-wide while zoom is off (Loop #626 scroll lag). Rejected |
| Field-number decoding in the callback | `NSEvent(cgEvent:)` in the callback | Public, but allocates per event. Gesture events run about 200/s while fingers rest. NSEvent built off main reportedly returns empty touch data [CITED (GPL, facts only): moonbai-studio/tungsten-edge FullscreenIntentMonitor.swift]. Needs an `autoreleasepool` on a CFRunLoop thread. Use it as the test and spike oracle only |
| Session tap | HID tap (`.cghidEventTap`) | Sees events earlier, and babylock (MIT) blocks gestures there. But it sits below the session tap where `InputTap` lives and adds risk. Session matches the existing tap and iss's proven Dock-swipe suppression |
| Own MT shim | OpenMultitouchSupport 3.0.x / 4.x | 4.x needs macOS 15 and ships a binary blob (STACK.md). Its header declares the `void` callback that OMS #13 says breaks on 27. Rejected |
| `MTRegisterContactFrameCallbackWithRefcon` | Non-refcon register + file-scope global (TicTap style) | The refcon variant is exported on 27 and lets one stable C callback serve every device through its context. Prefer it; fall back to the global only if the refcon symbol is missing |

**Installation:** none. No package is added. A new executable target `transom-gesture-spike` is added to `Package.swift` (pattern: `transom-zoom-spike`, line 34).

**Version verification:** no registry packages. System symbol availability was verified statically (above).

## Package Legitimacy Audit

This phase installs **no external packages**. Only system frameworks and private system frameworks reached by `dlopen`.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Verified Event Facts (read this before writing any tap code)

**SDK, public** (`MacOSX.sdk/.../CoreGraphics.framework/Headers/CGEventTypes.h`, read 2026-10-28):
```
typedef CF_ENUM(uint32_t, CGScrollPhase) {
    kCGScrollPhaseBegan = 1,
    kCGScrollPhaseChanged = 2,
    kCGScrollPhaseEnded = 4,
    kCGScrollPhaseCancelled = 8,
    kCGScrollPhaseMayBegin = 128
...
    kCGMomentumScrollPhaseContinue = 2,
    kCGMomentumScrollPhaseEnd = 3
...
  kCGScrollWheelEventPointDeltaAxis1 = 96,
  kCGScrollWheelEventPointDeltaAxis2 = 97,
  kCGScrollWheelEventScrollPhase = 99,
  kCGScrollWheelEventMomentumPhase = 123,
  kCGEventTargetUnixProcessID = 40,
  kCGEventSourceUserData = 42,
  kCGScrollWheelEventIsContinuous = 88,
  kCGMouseEventWindowUnderMousePointer = 91,
  kCGScrollWheelEventMomentumOptionPhase = 173,
```
(`kCGMomentumScrollPhaseBegin` is 1 and `None` is 0, in the same enum, lines just above the excerpt.) [VERIFIED: SDK header]

The public `CGEventType` enum stops at the mouse/key/scroll/tablet types plus `kCGEventTapDisabledByTimeout = 0xFFFFFFFE`, `kCGEventTapDisabledByUserInput = 0xFFFFFFFF`. **There is no public gesture case.** [VERIFIED: SDK header]

**NSEventPhase is a different bitmask** (`AppKit.framework/Headers/NSEvent.h:216-222`):
```
NSEventPhaseNone = 0, NSEventPhaseBegan = 0x1 << 0, NSEventPhaseStationary = 0x1 << 1,
NSEventPhaseChanged = 0x1 << 2, NSEventPhaseEnded = 0x1 << 3, NSEventPhaseCancelled = 0x1 << 4,
NSEventPhaseMayBegin = 0x1 << 5
```
So CG "changed" is 2 while NS "changed" is 4. **Never compare a CG phase field with `NSEvent.Phase` raw values.** [VERIFIED: SDK header + local probe: a CG scroll with phase 2 came back from `NSEvent(cgEvent:)` as `phase.rawValue == 4`]

Also from NSEvent.h:
- Line 474: *"All the gesture events are sent to the view under the cursor when the NSEventPhaseBegan occurred."* This is the reason the latch decision is made once, at the sequence's first event.
- Line 415: `magnification`: *"change in magnification. This value should be added to the current scaling of an item to get the new scale factor."* So the accumulated scale is additive: `scale = 1 + Σ magnification`. [VERIFIED: SDK header]

**Private gesture fields, cross-checked:**

| Value | Meaning | Sources that agree |
|-------|---------|--------------------|
| event type `29` | `kCGSEventGesture` (pinch, rotate, two-finger touch envelopes) | WebKit `Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h` (`kCGSEventGesture = 29,`), ScrollToZoom `CGEventSPI.h` (`kCGEventGesture = 29`), joshuarli/iss `iss.c` (`enum { kCGSEventGesture = 29, kCGSEventDockControl = 30 };`), mirroir-mcp (`static let gestureEventType: UInt32 = 29`) |
| event type `30` | `kCGSEventDockControl`: **Spaces / Mission Control swipes, NOT magnify** | WebKit (`kCGSEventDockControl = 30,`), ScrollToZoom (`kCGEventDockControl = 30,`), iss |
| field `110` | gesture HID sub-type: `8` = zoom (pinch), `5` = rotate, `61`/`62` = gesture started/ended envelope | WebKit (`kCGEventGestureHIDType = (CGEventField)110;`, `kCGHIDEventTypeGestureStarted = 61, kCGHIDEventTypeGestureEnded = 62,`), ScrollToZoom (`kIOHIDEventTypeZoom = 8`, `kIOHIDEventTypeRotation = 5`), mirroir (`GestureKind: 8 zoom, 5 rotate`) |
| field `113` | zoom value (the magnification delta) | WebKit (`kCGEventGestureZoomValue = (CGEventField)113;`), ScrollToZoom |
| field `132` | gesture phase, CG phase values (1/2/4/8/128) | WebKit (`kCGEventGesturePhase = (CGEventField)132;`), iss, mirroir (`1 began, 2 changed, 4 ended`) |
| field `55` | the real event type (iss reads this rather than the callback's `type`) | WebKit (`kCGSEventTypeField = (CGEventField)55;`), iss |
| field `87` | sender registry ID of the HID service (tells the built-in trackpad from a Magic Trackpad on the tap path, and matches `MTDeviceGetService`'s registry entry) | ScrollToZoom (`kCGEventRegistryID = 87`), mirroir (`senderIDField: UInt32 = 87`) |

**Local verification, in memory only, no event posted** (`swiftc -swift-version 6`, macOS 27.0.1, 2026-10-28). Output verbatim:
```
CGEventType(rawValue:29) = 29
magnify: type 29 hid 8 phase 1 zoom 0.05000000074505806 field55 29
scroll: cont 1 phase 1 ptY -12.0 ptX 5.0 field55 22
bg thread decode: type 30 mag 0.05000000074505806 phase 1
scroll: phase 4 momentum 0 precise true dy -12.0
NSEvent.EventTypeMask.magnify raw true gesture true
```
What this shows:
- A CGEvent built as type 29 with field 110 = 8, field 113 = 0.05 and field 132 = 1 is decoded **by AppKit's own bridge, on a background thread**, as `NSEventTypeMagnify` (30) with magnification 0.05 and phase Began. That confirms the field semantics on macOS 27.0.1.
- `CGEventType(rawValue: 29)` is non-nil in Swift.
- A pixel-unit scroll is continuous with point deltas equal to the wheel values.
- `NSEvent.EventTypeMask.magnify.rawValue == 1 << 30`. In a CG tap mask that bit selects Dock control.

[VERIFIED: local probe + 4 sources]

**Session taps can suppress type-29/30 events on current macOS, macOS 27 included:** iss (0BSD, updated 2026-09) creates
`CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, (1ULL << kCGSEventGesture) | (1ULL << kCGSEventDockControl), cb, NULL)`
and returns `NULL` to swallow horizontal Dock swipes. It notes: *"On macOS 27 and later, the real terminal event is passed through after its gesture fields are cleared so the Dock can close its native state."* [CITED: github.com/joshuarli/iss iss.c]. That is direct evidence that consuming type-29/30 at a session tap works. Consuming **magnify bound for an app** is not proven by it: spike gate T2.

## Architecture Patterns

### System Architecture Diagram

```
 trackpad fingers
      │
      ├──────────────► (only if MT ships) MultitouchSupport contact frames ──► MT thread ──► TouchFrame samples ─┐
      │                  callback returns 0 always (never consumes)                                              │
      ▼                                                                                                          │
 WindowServer gesture recogniser                                                                                 │
      │ scrollWheel(22) phases + momentum; type 29 {HID 61 start, 8 zoom, 5 rotate, 62 end}                       │
      ▼                                                                                                          │
 GestureTap (session, head insert, .defaultTap, mask 22|29) ── own thread + CFRunLoop                             │
      │  callback (<1 ms, no AX/log):                                                                            │
      │   read type/fields ─► GestureTapRules.decide(event, state, &latch)                                       │
      │        first event of a sequence?  ── armed? on a desk display?                                          │
      │             ├─ ⌥ held ─────────────────────────────► latch = consume(kind)                              │
      │             ├─ no ⌥: target PID ∉ {Finder, 0} ─────► latch = pass (zero cost)                           │
      │             └─ no ⌥: Finder/0 → CGWindowList.topmostWindow == nil ? consume : pass                      │
      │        later events of the sequence ─► follow the latch (through momentum end / timeout)                 │
      │   consume → yield GestureSample to AsyncStream, return nil │ pass → return event untouched               │
      ▼                                                                                                          │
 main actor: GestureController ◄──────────────────────────────────────────────────────────────────────────────────┘
      │ GestureRecognizer (TransomEngine, pure): scale = 1+Σm, translation, axis lock, velocity, progress
      │ on latch start: arranger.cameraStep(.stepIn(pointer)/.stepOut/.pan(edge)) → previewMove(target) (no commit)
      ▼
 ZoomController.follow(...) → StagePanel.show(cached tiles) + follow(progress) [CATransaction, actions off]
      │ on lift: recognizer.decide()
      ├─ commit  → arranger.handle(.camera / .zoomTo target) → .cameraMove → ZoomController.run (retargets from
      │            presentation rects, 250 ms ease-out or Reduce Motion crossfade) → .cameraSettle → AX writes once
      │            → history push (unchanged Phase 4 path)
      └─ spring back / rubber band → StagePanel animates tiles back to start rects (250 ms) → fadeOut; no engine call
```

### Recommended Project Structure

```
Sources/
├── TransomEngine/
│   ├── GestureRecognizer.swift      # pure state machine: samples → progress/velocity → SnapDecision (Double only)
│   └── Arranger+Camera.swift        # split zoomTo: non-mutating previewMove(to:displayUUID:) + commit part
├── TransomMac/
│   ├── Input/
│   │   ├── GestureTap.swift         # second active session tap (mask 22|29), own thread, watchdog hook
│   │   └── GestureTapRules.swift    # pure latch/consume rules + GestureTapState (copy ZoomTapRules' shape)
│   ├── Zoom/
│   │   ├── GestureController.swift  # main-actor glue: samples → recognizer → previews → ZoomController follow/commit
│   │   ├── ZoomController.swift     # + follow phase (.following), beginFollow/follow/endFollow
│   │   └── StagePanel.swift         # + follow(progress:) and springBack(completion:)
│   └── Input/MultitouchDevices.swift   # ONLY if MT ships: IOKit notifications, wake rescan, per-device start/stop
├── TransomPrivate/
│   ├── MultitouchSupport.swift      # dlsym shim, layout decode, int32 return 0 (built in the spike in any case)
│   └── Capabilities.swift           # + case multitouch = "Multitouch" (only if MT ships)
└── transom-gesture-spike/main.swift # user-run host CLI + VM synthetic half (D-09)
Tests/
├── TransomEngineTests/GestureRecognizerTests.swift  (+ Fixtures/Gestures/*.jsonl traces)
├── TransomMacTests/GestureTapRulesTests.swift
└── TransomMacIntegrationTests/GestureTapIntegrationTests.swift   (TRANSOM_LIVE, VM only)
```

### Pattern 1: A second, zoom-scoped active tap

**What:** `GestureTap` is a sibling of `InputTap`, with the same thread, run-loop and watchdog shape [VERIFIED: InputTap.swift:88-136], and its own mask:
```swift
// [VERIFIED value: CGEventType.scrollWheel.rawValue == 22 (probe); 29 = kCGSEventGesture (4 sources + probe)]
private static let mask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue) | (1 << 29)
// NEVER (1 << 30): that is kCGSEventDockControl (Spaces/Mission Control swipes), not magnify.
```
**When:** create it in `ArrangeController` when zoom is on **and** the shell is ready. Stop and destroy it on Turn Off Zoom, on loss of Accessibility, and in `stopTap()`. The existing 2 s watchdog [VERIFIED: ArrangeController.swift:216-252] ticks both taps.
**Why separate:** `InputTap.mask` is mouse plus flagsChanged only [VERIFIED: InputTap.swift:67-68, `(1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.flagsChanged.rawValue)`]. Keeping scroll out of it means zoom-off Transom adds no per-scroll cost and stays exactly Phase 3.

### Pattern 2: Latch-at-start consume rules (`GestureTapRules`)

**What:** a pure function in the shape of `ZoomTapRules.decide` [VERIFIED: ZoomTapRules.swift:19-34]. A **sequence** is the unit. The decision is made at the sequence's **first** event and applied to every later event of that sequence, including momentum. This mirrors `ZoomTapRules` ("Modifiers are read at mouse-down only") and AppKit's rule that gesture events go to the view under the cursor at Began.

Sequences:
- **Scroll:** starts at the first event with `scrollPhase ∈ {128 mayBegin, 1 began}`, or, if none was seen, at a stray `changed`. That stray case is a pass, because the app already has the start. It ends at `scrollPhase ∈ {8 cancelled}` with no momentum following, or at `momentumPhase == 3 (end)`, or at a new `mayBegin/began`, or after a quiet timeout (300 ms with no event in the sequence). Events with `scrollPhase == 0 && momentumPhase == 0` (discrete mouse wheel, and continuous scroll without phases) are **never consumed**.
- **Magnify:** starts at the first type-29 event with field 110 == 8 (zoom) and phase 1 (began). It ends at a zoom event with phase 4/8, or after the quiet timeout. While latched, consume type-29 events with field 110 ∈ {8 zoom, 5 rotate} and any bare "container" type-29 event (field 110 == 0). **Pass envelope events (61/62) through**: `NSEventTypeBeginGesture`/`EndGesture` "is no longer delivered" to apps (NSEvent.h:53-54), and on 27 the Dock wants terminal events (iss). The spike confirms or flips this (T2 "no stuck state").
- **Rotate-only, smart-magnify and every other type-29 sub-type:** pass.

The decision at sequence start (`state` is published whole from main, like `ZoomTapState`):
1. `state.armed` (zoom on, ready, not paused, no fullscreen Space under the pointer) and the location is inside `state.deskDisplays`, else pass.
2. `flags.contains(.maskAlternate)` → consume. (Just ⌥; ignore ⇧. Pass if ⌘ or ⌃ is also held, so ⌃-pinch and ⌘-scroll chords stay the app's. Check against the Accessibility zoom modifier.)
3. Otherwise the wallpaper test (D-05):
   - `targetPID = field 40`. If it is non-zero and not `state.finderPID` → **pass with no CG read**. This is the common path for every ordinary scroll in every app.
   - Otherwise do one `CGWindowList.topmostWindow(at:)` read. It already excludes Transom's own panels (`excludingPID: getpid()`) and looks through the Dock's full-screen layer-20 window [VERIFIED: CGWindowList.swift:18-41]. `nil` → wallpaper → consume. But `topmost` also returns `nil` when a menu or popover above layer 0 owns the point, so add a variant that returns a tri-state `{window, wallpaper, overlay}` and consume only on `wallpaper`.
   - Whether field 40 is populated at the session tap for scroll and type-29 events is [ASSUMED]. ScrollToZoom reads it in a scroll tap [CITED: STZEventHandling.c `pid_t pid = (int32_t)CGEventGetIntegerValueField(event, kCGEventTargetUnixProcessID);`], but that may be at the annotated session location. Spike T6 measures it. Fallback: do the CG read whenever ⌥ isn't held and the pointer is on a desk display, and measure that cost in T5.
4. Per-sequence safety: a latch older than 2 s with no event, or a new sequence start, always clears it. A stuck latch must never swallow all scrolling (security domain: input DoS).

**Output to main:** consumed events become `GestureSample { kind: .scroll/.magnify, phase, momentumPhase, dx, dy, magnification, location, timestamp, flags, senderID }` on an `AsyncStream` with `bufferingNewest(256)`, like `InputTap.events` [VERIFIED: InputTap.swift:70-73]. The callback does field reads, one lock read of the state, one `yield`, then returns.

### Pattern 3: `GestureRecognizer` (TransomEngine, pure)

**Inputs:** samples with time, kind, phase and deltas. **Outputs:** `.began(kind, origin)`, `.progress(Double, axis/edge or .pinchIn/.pinchOut)`, `.ended(SnapDecision)` where `SnapDecision ∈ {commit(target direction), springBack}`.

Recommended defaults. All are [ASSUMED], tuned at UAT, and are constants in one place:

| Quantity | Formula / value |
|----------|-----------------|
| Pinch scale | `s = 1 + Σ magnification` (Apple: additive, NSEvent.h:415) |
| Pinch progress (one level per gesture) | `p = ln(s) / ln(2)`. One full level per doubling or halving, whatever the tree's size ratio, so a quadrant (4× area) and a half-split need the same finger travel. `p > 0` toward `stepIn` (fingers apart), `p < 0` toward `stepOut` |
| Pinch dead zone | ` |ln s| < 0.03` → no stage, no latch-visible change (avoids jitter). The tap still consumes because it latched at Began |
| Pinch commit | ` |p| ≥ 0.5` at Ended, or flick ` |dp/dt| ≥ 2.0 /s` over the last 80 ms with ` |p| ≥ 0.15` |
| Pan translation | `d = Σ pointDelta` along the locked axis. Axis locks once ` |Σ| ≥ 12 pt`, with the dominant axis winning by ≥ 1.5× |
| Pan progress | `p = |d| / W` (W = the display's visibleFrame width, or height for vertical) |
| Pan commit | `p ≥ 1/3` at fingers-up (scroll phase 4), or flick `v ≥ 800 pt/s` toward the drag with ` |d| ≥ 24 pt`. `v` comes from the last 80 ms of `changed` samples, or the first momentum sample |
| Edge from direction | Natural scrolling: the deltas already follow the fingers. Fingers left (dx < 0) shows the area to the **right**, so `edge = .right`; fingers up shows `.bottom`. Use the deltas as given, so the stage behaves like scrolled content in every app. Field 137 (`isDirectionInverted`) only needs reading if UAT says otherwise |
| Rubber band (no neighbour / home / leaf) | displayed offset `= W · (1 − 1 / (|d| · 0.55 / W + 1)) · sign(d)` (the iOS UIScrollView formula, [ASSUMED]), spring back 250 ms |
| Momentum | Never part of the decision except as the velocity estimate. Swallowed by the tap until momentum end |

Where it lives: `TransomEngine/GestureRecognizer.swift`, AppKit-free. With MT, a `TwoFingerTracker` in the same file maps normalized finger positions to the same samples: scale = the ratio of finger distances, translation = the centroid delta × surface mm → pt. Both sources feed one recognizer.

### Pattern 4: Follow mode on the Phase 4 stage

The Phase 4 stage is shown only while a move runs and is driven by `run(move)` → capture → `show` → `animate` [VERIFIED: ZoomController.swift:69-107]. Live follow needs three changes:

1. **Engine: preview without commit.** `zoomTo` both computes the tiles and commits a pending move (`camera.nextMoveID += 1`, `camera.pending[uuid] = PendingMove(...)`) [VERIFIED: Arranger+Camera.swift:250-251]. Split it:
   - a non-mutating `func previewMove(to target: ViewTarget, displayUUID: String) -> CameraMove?` that runs lines 207–249 unchanged and returns the move with `id: 0`;
   - `zoomTo`, which calls it, then sets `nextMoveID` and `pending` exactly as now.

   Because the preview and the commit use the same tile function, the committed move's tiles equal the previewed ones. The retarget therefore continues with no jump.
2. **Targets:** use the existing non-mutating `cameraStep` [VERIFIED: Navigator.swift:237-239]: `.stepIn` with `pointer:` (the child under the pinch point, `Navigator.stepIn` line 88), `.stepOut`, and `.pan(edge)`, which already refuses at home with `.noArea` (line 280). A `.failure` means rubber band. **No beep or announcement during a gesture**: the gesture path doesn't go through `dispatchCamera`, which beeps.
3. **Shell (`ZoomController` + `StagePanel`):**
   - `beginFollow(displayUUID:, from tiles: [StageTile])`: show the stage **at once** with the cached snapshots or fallback tiles. Do not wait for the capture budget: the first frame must land within one refresh of the first consumed event. Set the phase to `.following`.
   - `follow(preview: CameraMove?, progress: Double)`: in a `CATransaction` with `setDisableActions(true)`, set each tile's frame to `lerp(start, end, progress)`. If there is no preview, apply a rubber-band transform to the start set. If the preview target changes (pan direction reversed, or the pinch crossed zero), rebuild the tile set from the current frames.
   - **Commit:** `GestureController` calls `arranger.handle(.camera(...))`, or `.zoomTo` for the previewed target, which yields `.cameraMove`. `ZoomController.run` sees `active[uuid]` in `.following` and takes the **retarget** branch: `stages[uuid]?.retarget(to:)` animates every tile from its **presentation rect** to the end over 250 ms ease-out [VERIFIED: ZoomController.swift:73-92; StagePanel `retarget` "goes on from its presentation() rect, so a retarget never jumps"]. Settle, reveal and the history push are unchanged. Reduce Motion: `StagePanel.retarget` keeps the move's `crossfade` choice, so `beginFollow` must set `crossfade = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. The live tracking still lerps; only the snap crossfades (D-01).
   - **Spring back:** animate the tiles to their start rects over `StagePanel.moveDuration` (0.25, [VERIFIED: StagePanel.swift:40 `public static let moveDuration = 0.25`]), then `fadeOut` (`revealFade = 0.12`, line 41). No engine call, no AX write, no history.
4. **A gesture during a move or settle:** `currentView` already answers with the pending target [Arranger+Camera.swift:85-87, read earlier this session via cat; not re-quoted]. Let a new gesture begin follow from the current presentation rects with the pending target as its base. If that proves fiddly, the fallback is to consume and drop the gesture, logged. See Open Question 3.
5. **The stage takes clicks while shown** (`ignoresMouseEvents = false`, [VERIFIED: StagePanel.swift:58]), which is fine because the gesture is consumed at the tap before it reaches the stage.

### Pattern 5: MultitouchSupport shim (in the spike; in the product only if gated in)

Declare the C prototypes in Swift with `@convention(c)`, resolve them with `dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)` plus `dlsym`, and use optional function pointers, as `AXWindowID.swift` and `SkyLightSpaces.swift` already do.

The touch struct is **96 bytes**. Four header lineages agree. OpenMultitouchSupport `OpenMTInternal.h` (MIT), verbatim:
```c
typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    MTTouchState state;
    int fingerId;
    int handId;
    MTVector normalizedPosition;
    float total; //total of capacitance
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolutePosition;
    int field14;
    int field15;
    float density; //area density of capacitance
} MTTouch;
```
Offsets: frame 0, (pad), timestamp 8, identifier 16, state 20, fingerId 24, handId 28, normalized position x/y 32/36, velocity 40/44, total 48, pressure 52, angle 56, majorAxis 60, minorAxis 64, absolute position 68–83, field14 84, field15 88, density 92, size 96.

ScrollToZoom's `MTSupportSPI.h` (MIT) lays out the same 96 bytes (`location` at 32, `zDensity` last). TicTap reads `let stride = 96` with x at offset 32 [read for facts only, non-commercial licence]. Mac-trackpad-mapper and Hammerspoon touchdevice (MIT) declare the same field order. Touch states: `MTTouchStateMakeTouch = 3`, `MTTouchStateTouching = 4`, `MTTouchStateBreakTouch = 5` (OMS enum). [CITED: the four headers; MEDIUM. Spike gate M1 checks it on 27.]

The callback, with the safe declaration chosen deliberately:
- The lineages disagree on the count/frame argument types (`int` in OMS, `size_t` in Mac-trackpad-mapper/Hammerspoon, `CFIndex` in ScrollToZoom). Declare **`Int32`**: a 64-bit register read as its low 32 bits is correct either way on arm64 and x86_64 (little-endian).
- Declare an **`Int32` return and always `return 0`**. OMS #13 (one report, macOS 27.0 beta 26A5388g) says a `void`-declared callback leaves garbage that macOS 27 reads as "consume", which stops system 3/4-finger gestures while streaming [CITED: github.com/Kyome22/OpenMultitouchSupport/issues/13]. Returning 0 is harmless where the value is ignored.
- Refcon variant: `MTRegisterContactFrameCallbackWithRefcon(device, cb, refcon)` with `cb(device, touches, count, timestamp, frame, refcon) -> Int32`, refcon last [CITED: Mac-trackpad-mapper `typedef void (*MTFrameCallbackRefconFunction)(MTDeviceRef device, MTTouch touches[], size_t numTouches, double timestamp, size_t frame, void* refcon);`; ScrollToZoom `typedef int (*MTContactCallback)(MTDeviceRef, MTTouch const *touches, CFIndex touchCount, CFTimeInterval, MTFrameID, void *refcon);`].
- Unregister with `MTUnregisterContactFrameCallback(device, cb)` using the **same stable** C function pointer: one file-scope `let`, never a fresh closure.

Device lifetime rules:
- `MTDeviceCreateList()` returns a +1 `CFArray` that **owns** the devices. **Never call `MTDeviceRelease` on a list-owned device.** M5MultitouchSupport #1 and OMS #2 crashed in `_CFRelease` after wake from exactly that over-release; not releasing fixed it [CITED: github.com/mhuusko5/M5MultitouchSupport/issues/1, Kyome22/OpenMultitouchSupport/issues/2]. Keep the array alive while its devices run. On rescan, stop and unregister every old device, then drop the old array.
- Thread: call `MTDeviceStart` from a dedicated thread with its own `CFRunLoop`, like `InputTap`. It is unclear whether `MTDeviceStart` schedules on the calling thread's run loop (Hammerspoon: "the runloop is handled by MTDeviceStart") or on an internal thread (TicTap comment). A dedicated thread is right either way. The spike prints `Thread.isMainThread` in the callback.
- Per-device info for the Debug line and filtering: `MTDeviceIsBuiltIn`, `MTDeviceGetFamilyID` (the host's built-in trackpad reports `"Family ID" = 110`, [VERIFIED: ioreg]; ScrollToZoom names Magic Mouse family `112`, which must be excluded), `MTDeviceGetSensorSurfaceDimensions`, and `MTDeviceGetService` → registry ID, which matches tap field 87.

### Pattern 6: Crash canary and capability (only if MT ships)

- Add `case multitouch = "Multitouch"` to `Capability`, with `fallback` "trackpad gestures from system events". The existing cases are `case axWindowID = "AXWindowID"` and `case spaces = "Spaces"` [VERIFIED: Capabilities.swift:4-14]. `--disable-private=Multitouch` then works for free.
- Canary: before the first risky call in a session (dlopen, CreateList, Start, and the first 2 s of frames), write `UserDefaults` `privateCanary.Multitouch = {osBuild, appVersion, started}`, and clear it after 2 s of healthy frames. At launch, a leftover canary for the same OS build and app version → capability off for this launch, a logged error, Debug line "Multitouch: off (stopped after a crash last launch)". A new OS build or app version retries once. This is AeroSpace #101's pattern (PITFALLS 4).
- The tap path needs no canary: it calls no private function, and an unknown field read just returns 0.

### Anti-Patterns to Avoid
- **`NSEvent.EventTypeMask.magnify` (1<<30) in a CGEventTap mask.** That taps Dock swipes. Use `1 << 29` and decode field 110.
- **Comparing CG phase fields with `NSEvent.Phase` raw values.** They are different bitmasks (changed is 2 vs 4).
- **Starting to consume mid-sequence** (⌥ pressed after the pinch began). The app has already seen Began and will be left mid-gesture. Latch at the first event only.
- **Releasing mid-sequence** (⌥ released during the pinch). Keep consuming until the sequence ends.
- **A CG window list read on every scroll event.** Read at most once per sequence start, and only when the PID test can't decide.
- **Creating `NSEvent` in the hot callback**, especially without `autoreleasepool` on a CFRunLoop thread (the pool never drains).
- **Returning non-zero from the MT callback** to "consume". This is undocumented, may stall pointer movement and system gestures, and is one beta report. Spike-only probe, never shipped without a user decision.
- **Driving the camera through `dispatchCamera`** from a gesture. It beeps and announces refusals. Rubber-band instead.
- **Waiting for a ScreenCaptureKit capture before showing the follow stage.** Use cached snapshots or fallback tiles immediately.

## Spike Design (Plan 1, gates the phase like 04-SPIKE)

**Harness:** `transom-gesture-spike` executable target (depends on `TransomPrivate` and, for the recognizer replay, `TransomEngine`). It has no windows, no NSApplication and no layout changes. JSON lines go to stdout and `--out`. Every subcommand has a hard `--seconds N` limit (default 30, max 120) and a SIGINT handler that stops devices and taps.

The **host half is run by the user** from their terminal. An active tap needs the terminal app to hold Accessibility. The harness prints `AXIsProcessTrusted()`, `CGPreflightListenEventAccess()` and `CGPreflightPostEventAccess()` first and exits with a clear message if consume mode lacks them. The **VM half** runs through a `scripts/vm-spike.sh`-style wrapper and only posts synthetic events.

| Subcommand | Where | What it prints | Gates |
|------------|-------|----------------|-------|
| `mt-devices` | host (user), VM (agent ok) | per device: builtIn, familyID, deviceID, registryID, surface mm, driverType; the `dlsym` table | M1 (enumeration), plus whether Tart's virtual trackpad is an MT device |
| `mt-stream --seconds 20` | host (user) | per frame: device, touch count, per-touch id/state/x/y/vx/vy, callback thread, frame Δt; a summary of layout sanity (x,y ∈ [0,1], ids stable, states ∈ 0…7, timestamps monotonic) | M1 layout, M2 (with the user checklist: 3-finger Spaces swipe and Mission Control still work **while streaming**, 10/10) |
| `tap-listen --seconds 30` | host (user) | listen-only tap, mask 22\|29\|30: type, field 55, field 110, 132, 113, scroll phase/momentum/continuous/point deltas, field 40 target PID, field 87 sender, fields 91/92, ⌥ flag, location; the `NSEvent(cgEvent:)` oracle decode on main for comparison | T1 visibility, T6 field availability |
| `tap-consume --seconds 30 [--require-alt]` | host (user) | active tap with the real `GestureTapRules`. Per sequence: latch decision, events consumed/passed, callback µs (p50/p99), CG reads | T2 consume, T3 pass-through, T5 timing |
| `compare --seconds 30` | host (user) | MT and tap at once: per pinch/pan, first-MT-frame vs first-tap-event lead time | M4 latency |
| `rescan` | host (user) | IOKit add/remove notifications, wake notifications, devices before/after, time to the first frame after re-add | M3 |
| `synth --scenario <name>` | VM (agent) | posts synthetic scroll and magnify sequences at `.cghidEventTap`. A downstream **listen-only tail-append** session tap counts what survives | VM gates V1–V3 (also the 05-xx integration tests) |

**User checklist (host)**, run on both trackpads where it applies, each item 10 trials:
1. Pinch and two-finger scroll over Safari, Preview (a PDF), a Finder window and bare wallpaper, plus one full-screen app.
2. The same with ⌥ held.
3. Turn "Zoom in or out" off in System Settings › Trackpad, then pinch (does any type-29/8 still arrive?).
4. While `mt-stream` runs, do a 3-finger Spaces swipe and open Mission Control.
5. Sleep the Mac, wake it, pinch.
6. Turn the Magic Trackpad off and on (or Bluetooth off and on), then pinch.

**Pass/fail gates:**

| Gate | Pass when |
|------|-----------|
| **T1 tap visibility** | Type 29 with field 110 = 8 and phases 1→2…→4 seen for ≥ 9/10 pinches over each of Safari, Preview, Finder window and **wallpaper**, on both trackpads. Phased scroll (22) seen for ≥ 9/10 pans in the same places |
| **T2 consume** | With ⌥, Safari and Preview content neither zooms nor scrolls in 10/10 pinches and 10/10 pans, momentum included. **No stuck state**: the next plain pinch/scroll works in the app 10/10, with the 61/62 envelopes passed. If stuck, flip to consuming the envelopes and re-run |
| **T3 pass-through** | Without ⌥ over a window, app pinch and scroll are unchanged 10/10. Discrete mouse wheel with ⌥ passes |
| **T4 coexistence** | 3/4-finger swipes and Mission Control work 10/10 while the tap runs (mask has no bit 30) |
| **T5 timing** | Callback p99 < 1 ms including sequence-start CG reads; p50 < 50 µs for passed events. Zero `tapDisabledByTimeout` in 30 s of heavy scrolling |
| **T6 field availability** | Record whether field 40 (target PID) is non-zero for scroll and type-29 at the session tap. Decides the cheap wallpaper path in Pattern 2 |
| **M1 MT layout** | Both devices enumerated with correct builtIn. With 1–5 fingers: x,y ∈ [0,1], stable ids, state transitions 3→4…→5→(6/7), plausible velocities. No crash in 60 s |
| **M2 int32 return** | With `return 0`, system gestures work 10/10 while streaming on macOS 27.0.1 |
| **M3 re-enumeration** | After wake and after a Magic Trackpad off/on, frames resume within 2 s through IOKit notifications. No crash (no `MTDeviceRelease` on list devices) |
| **M4 latency** | Report the median lead of the first MT frame over the first tap event, per gesture kind |

**Decision matrix** (record it in `05-SPIKE.md` and get the user's decision, as Phase 4 did):

| Result | Primary | Fallback / ship MT? |
|--------|---------|---------------------|
| T1–T5 pass; checklist 3 shows no magnify with pinch-zoom disabled; M4 lead < 30 ms | **Event tap** for recognition and consumption | Don't ship MT (the shim stays in the spike target). Pinch is unavailable when the user turned off system pinch-zoom: say so in the Debug line or log. Recommended default |
| T1–T5 pass, and the user wants pinch even with system pinch-zoom off, or M4 lead ≥ 30 ms | Event tap for consumption and pan; **MT for pinch recognition** when no magnify arrives | Ship MT with canary and IOKit rescan |
| T1 fails over some surface (e.g. wallpaper) but T2 passes elsewhere | Tap consumes where events exist; MT recognizes where they don't | Ship MT |
| T2 fails (cannot consume magnify) | — | GEST-04 can't be met publicly. The only option is a macOS-27-only probe of a non-zero MT return (dangerous). Stop and escalate to the user (RULE 0 spirit) |
| T5 fails | Narrow work: CG read only on Finder/0 PID, or publish window rects from main | Re-run T5 |
| Nothing works | Gestures off, with a Debug line "Gestures: unavailable (…)"; hotkeys, URLs and menu still drive zoom (CONTEXT discretion) | — |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deciding where an app's gesture goes | Your own "frontmost/under-pointer app" routing | The tap's latch + field 40 + `CGWindowList.topmostWindow` | WindowServer already routes; one CG read at sequence start is enough |
| Pinch recognition from raw touches (on the tap path) | A two-finger distance recogniser | System magnify events (type 29/8) | The system recogniser handles palm rejection, rotation-vs-pinch disambiguation and accessibility settings |
| Scroll momentum physics | Inertia simulation | The system's momentum events (use only as a velocity estimate) | Matches every other app's feel; we only snap |
| Snap targets | New geometry | `cameraStep(.stepIn/.stepOut/.pan)` and `Navigator.pan` | D-02/D-03 require Phase 4 rules unchanged |
| Retargeting the stage mid-animation | A new animator | `StagePanel.retarget` (continues from `presentation()`) | Already handles crossfade and leaving tiles |
| Tap re-enable after timeout | A new watchdog | `ArrangeController` 2 s watchdog + in-callback re-enable | Proven in Phases 3–4 |
| Device hot-plug detection | Polling `MTDeviceCreateList` | IOKit first-match/terminated notifications on `AppleMultitouchDevice` + `didWake` | Event-driven; ScrollToZoom pattern |
| CGEvent field constants scattered | Magic numbers in callbacks | One documented constants file (`TransomPrivate/GestureEventFields.swift`) with provenance | Private-API isolation rule; field semantics changed for Dock swipes on 26/27 (iss) |

**Key insight:** macOS already recognizes, routes and adds momentum to every trackpad gesture. Transom's only jobs are to (1) decide once per gesture whether it is Transom's, (2) swallow that whole gesture, and (3) map its progress onto existing camera levels. Every extra layer, MT included, has to earn its place with spike data.

## Common Pitfalls

### Pitfall 1: Type 30 is Dock control, not magnify
**What goes wrong:** the mask is copied from NSEvent docs (`NSEventTypeMagnify = 30`), the tap swallows Spaces/Mission Control swipes, and pinches are never seen.
**Why:** NSEvent numbering ≠ CGS numbering for gesture types. NSEvent makes "magnify" from CG type 29 + field 110 = 8.
**How to avoid:** mask `1 << 29` only. A unit test asserts the gesture tap mask has bit 29 set and bit 30 clear.
**Warning signs:** 3-finger swipes stop working while Transom runs.

### Pitfall 2: Leaking the tail of a gesture (momentum, ended)
**What goes wrong:** began/changed are consumed and the momentum scroll after lift reaches the app, so content scrolls after Transom snapped. Or ⌥ is released mid-pinch and the app gets "changed/ended" without "began".
**How to avoid:** latch per sequence. End only at momentum end, cancelled-without-momentum, a new sequence start, or the quiet timeout. Never re-evaluate flags mid-sequence.
**Warning signs:** the page scrolls or zooms slightly right after a Transom snap; VM test V1 counts downstream events > 0.

### Pitfall 3: Mixing up the phase encodings
**What goes wrong:** `phase == 4` read as "changed" (NSEvent) when it is CG "ended".
**How to avoid:** the tap code uses only CG constants (1, 2, 4, 8, 128; momentum 1, 2, 3). Tests compare against `NSEvent(cgEvent:)` only through its `NSEvent.Phase` type.

### Pitfall 4: A stuck latch swallows every scroll system-wide
**What goes wrong:** a missed end event leaves the latch on, and the user can't scroll anywhere.
**How to avoid:** the quiet timeout (300 ms after the last event of a sequence, 2 s hard cap with no events), and any new `mayBegin/began` resets the latch. A unit test feeds a sequence with no end, then a fresh plain scroll, and expects pass. The harness also has a time limit.
**Warning signs:** "scrolling stopped working until I quit Transom".

### Pitfall 5: Tap timeout from slow sequence-start work
**What goes wrong:** the CG window list read (several ms with many windows) on every scroll start in every app pushes the callback past the system limit, and macOS disables the tap (PITFALLS 5).
**How to avoid:** the PID short-circuit (T6), measured p99 (T5), and the existing re-enable plus watchdog. Never AX, log or allocate in the callback.

### Pitfall 6: Wallpaper misclassification
**What goes wrong:**
- Transom's own panels (stage, collapsed blocks, gap handles) are under the pointer and count as "a window", so a no-⌥ pinch over the Desktop tile is passed. Or the reverse: a menu or popover over the wallpaper counts as wallpaper.
- Desktop icons: D-05 says "no window under it". Icons live in Finder's desktop window (excluded by `.excludeDesktopElements`), so a pinch on an icon is treated as wallpaper. That is acceptable, because Finder ignores pinch there.

**How to avoid:** `topmost` already excludes our PID and looks through the Dock's full-display window [VERIFIED: CGWindowList.swift:33-41]. Add the tri-state result so "overlay above layer 0" passes. Use no AX hit test in the tap: Phase 4's Finder `AXGroup` vs `AXImage` test (ZoomInput) is too slow for the callback.
**Warning signs:** a pinch over an open menu zooms the camera.

### Pitfall 7: MT device over-release after wake
**What goes wrong:** `_CFRelease` crash on wake (M5 #1, OMS #2).
**How to avoid:** never call `MTDeviceRelease` on devices from `MTDeviceCreateList`. Keep the array; stop and unregister before dropping it.

### Pitfall 8: `void` MT callback on macOS 27
**What goes wrong:** system 3/4-finger gestures die while Transom streams (OMS #13).
**How to avoid:** `@convention(c) (...) -> Int32` and `return 0`, checked by spike gate M2.

### Pitfall 9: The default device only sees one trackpad
**What goes wrong:** `MTDeviceCreateDefault` picks one of the built-in and Magic Trackpads (OMS #6, owner: "If multiple trackpads were connected, it would be one of them").
**How to avoid:** `MTDeviceCreateList` + IOKit notifications; exclude Magic Mouse (family 112) [CITED: ScrollToZoom `kMTDeviceFamilyMagicMouse = 112`]. On the tap path this doesn't arise.

### Pitfall 10: ⌥ + scroll already means something in apps
**What goes wrong:** with ⌥ held, Transom takes the scroll, so apps lose their own ⌥-scroll. Fast scroll in Zed (and reportedly VS Code) and zoom in some design tools are examples [CITED: git.secluded.site/zed commit "Add holding opt/alt for fast scrolling (#31056)"; LOW. VS Code/Adobe [ASSUMED]].
**How to avoid:** this is the accepted cost of D-04 (user decision). Only phased trackpad scrolls are taken; discrete mouse wheels with ⌥ pass (Pattern 2). Note it in the Phase 9 onboarding copy, and keep a Phase 9 Settings toggle in mind (deferred).
**Magic Mouse:** its one-finger scroll is also phased and continuous, so with ⌥ it would pan. Filter it out by sender registry ID (field 87) only if the user objects (Open Question 4).

### Pitfall 11: VM display sleep shifts geometry
**What goes wrong:** with the guest display asleep, `CGMainDisplayID() == 0` and `NSScreen.screens[0].frame` sits at y = −768, so `deskDisplays` is wrong and synthetic gestures miss their targets [VERIFIED: 04-UAT.md Environment note and Deferred Follow-Ups].
**How to avoid:** VM scripts run `caffeinate -u` and hold `caffeinate -dimsu` in the guest before synthetic gesture tests (the 04-UAT re-test procedure). The product re-publishes `GestureTapState` on `screensDidWake` and display changes.

### Pitfall 12: macOS 27 changes to synthetic gesture events
**What goes wrong:** on macOS 27, synthetic *Dock swipes* need a serialized raw IOHID payload in CGEvent field 4205 to be honoured by the Dock [CITED: iss.c header comment, "macOS 27 and later also require a serialized raw IOHID queue payload on every synthetic phase"]. iss also notes that CGEvent field tags don't survive `CGEventPost` for these events.
**How to avoid:** Transom never posts gestures in the product. Tests synthesize them only in the VM (macOS 15.7.7), and they only need *Transom's tap and a downstream probe tap* to see them, not an app to honour them. Never use `eventSourceUserData` tags to recognise test gesture events; use a downstream tap count.

### Pitfall 13: System pinch-zoom turned off
**What goes wrong:** a user who disabled "Zoom in or out" in Trackpad settings gets no magnify events, so ⌥-pinch does nothing on the tap path [ASSUMED; checklist item 3].
**How to avoid:** the decision matrix row 2 (MT pinch). Otherwise a Debug/log line "Pinch needs Trackpad ▸ Zoom in or out" (no UI this phase).

### Pitfall 14: The private-API canary can fire on a non-MT crash
**What goes wrong:** any crash in the first 2 s after MT start sets the canary and disables gestures.
**How to avoid:** it is cleared after 2 s of healthy frames and retried on a new OS build or app version. The user can force it with `--disable-private=` / defaults. This is accepted conservatism.

## Code Examples

### Gesture tap callback core (shape; mirrors InputTap.makePort)
```swift
// Source: pattern of Sources/TransomMac/Input/InputTap.swift:140-190 (read this session).
// Field numbers: 110/113/132 per WebKit CoreGraphicsTestSPI.h + local NSEvent-bridge probe; 40 public (SDK).
nonisolated enum GestureEventFields {           // TransomPrivate/GestureEventFields.swift
    static let hidType = CGEventField(rawValue: 110)!   // 8 zoom, 5 rotate, 61/62 envelope
    static let zoomValue = CGEventField(rawValue: 113)!
    static let phase = CGEventField(rawValue: 132)!     // CG phase values 1/2/4/8/128
    static let gestureType: UInt32 = 29                 // kCGSEventGesture; 30 is DockControl, never tapped
}

let callback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<GestureTapBox>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = box.port { CGEvent.tapEnable(tap: port, enable: true) }
        box.latch = .none                                   // never resume a half-seen sequence
        return Unmanaged.passUnretained(event)
    }
    let input = GestureTapRules.Input(event: event, type: type)   // field reads only
    let state = box.state.withLock { $0 }
    switch GestureTapRules.decide(input, state: state, latch: &box.latch, topmost: CGWindowList.wallpaperAt) {
    case .consume(let sample):
        if let sample { box.continuation.yield(sample) }
        return nil
    case .pass:
        return Unmanaged.passUnretained(event)
    }
}
```

### MT shim declarations (only the safe shapes)
```swift
// Source: prototypes per OMS OpenMTInternal.h, Mac-trackpad-mapper MultitouchSupport.h, ScrollToZoom MTSupportSPI.h (MIT);
// symbols present per `dyld_info -exports` on macOS 27.0.1. Return type Int32 and `return 0` per OMS #13.
typealias MTDeviceRef = UnsafeMutableRawPointer
typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
typealias FrameCallback = @convention(c) (
    MTDeviceRef?, UnsafeRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?) -> Int32
typealias RegisterWithRefcon = @convention(c) (MTDeviceRef, FrameCallback, UnsafeMutableRawPointer?) -> Void
typealias Unregister = @convention(c) (MTDeviceRef, FrameCallback) -> Void
typealias Start = @convention(c) (MTDeviceRef, Int32) -> Int32      // OSStatus
typealias Stop = @convention(c) (MTDeviceRef) -> Int32
typealias IsBuiltIn = @convention(c) (MTDeviceRef) -> Bool
typealias GetFamilyID = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>) -> Int32

let touchStride = 96          // OMS MTTouch layout (4 lineages agree); normalized x/y at offsets 32/36
private let frameCallback: FrameCallback = { device, touches, count, timestamp, frame, refcon in
    let n = max(0, min(Int(count), 20))           // bound the private count before reading memory
    // decode n touches at touchStride into a fixed-size buffer; hand off; no allocation, no logging
    return 0                                      // NEVER consume: system gestures must keep their frames
}
```

### Synthetic events for VM tests (never posted on the host)
```swift
// Source: in-memory probe run 2026-10-28 (output quoted under Verified Event Facts); ScrollToZoom createZoomEvent (MIT).
func syntheticScroll(dx: Int32, dy: Int32, phase: Int64, momentum: Int64, flags: CGEventFlags, at p: CGPoint) -> CGEvent? {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)       // 128, 1, 2, 4, 8
    e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)  // 0, 1, 2, 3
    e.flags = flags; e.location = p
    return e
}
func syntheticMagnify(_ value: Double, phase: Int64, flags: CGEventFlags, at p: CGPoint) -> CGEvent? {
    guard let e = CGEvent(source: nil), let type = CGEventType(rawValue: 29) else { return nil }
    e.type = type
    e.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)   // zoom
    e.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
    e.setDoubleValueField(CGEventField(rawValue: 113)!, value: value)
    e.flags = flags; e.location = p
    return e
}
// Post at .cghidEventTap so Transom's session tap sees it; count survivors with a listen-only .tailAppendEventTap.
```

### Follow lerp on the stage
```swift
// Source: StagePanel.show/retarget pattern (Sources/TransomMac/Zoom/StagePanel.swift:107-170, read this session).
func follow(progress p: Double) {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for tile in tiles { layers[tile.id]?.frame = localRect(lerp(tile.start, tile.end, min(max(p, 0), 1))) }
    CATransaction.commit()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `void` contact-frame callback (most gists, OMS headers) | `int32_t` return, `return 0` | macOS 27 betas (OMS #13, Aug 2026 report) | A wrong prototype now silences system gestures |
| `MTDeviceCreateDefault` | `MTDeviceCreateList` + IOKit notifications | long-standing; OMS #6 | Both trackpads, hot-plug |
| Synthetic gesture events need only type/fields | macOS 27 validates synthetic Dock swipes against a raw IOHID payload (field 4205) | macOS 27 | Tests must not rely on synthetic gestures being *honoured* on 27; Transom's VM is 15.7 |
| `NSEventTypeBeginGesture`/`EndGesture` | Deprecated, "no longer delivered"; use `phase` | 10.x (SDK) | Pass the 61/62 envelope events; apps use per-event phases |
| OpenMultitouchSupport 3.x | 4.0.0 (2026-05-28) raised the floor to macOS 15 | 2026-05 | Own shim required for a macOS 14 floor |

**Deprecated/outdated:**
- `NSEvent.addGlobalMonitorForEvents` for magnify: magnify and rotate aren't delivered to global monitors [CITED: ochyai/OnomatopeCursor source comment; LOW], and monitors can't consume anyway.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A session `.defaultTap` returning nil for type-29/8 stops the app under the pointer from zooming (magnify consume), on macOS 14–27 | Summary, Pattern 2, T2 | GEST-04 unmeetable publicly; escalation (decision matrix row 4) |
| A2 | Magnify events are generated and visible to the tap over bare wallpaper | Pattern 2, T1 | No-⌥ wallpaper pinch (GEST-03) needs MT |
| A3 | `kCGEventTargetUnixProcessID` (40) is populated at the session tap for scroll and type-29 | Pattern 2 step 3 | A CG read on every no-⌥ sequence start; T5 decides if that is affordable |
| A4 | Passing 61/62 envelope events while consuming zoom/rotate leaves no stuck app state | Pattern 2 | Flip to consuming envelopes (T2 re-run) |
| A5 | Disabling Trackpad "Zoom in or out" stops magnify generation | Pitfall 13, matrix | Changes whether MT is needed |
| A6 | Thresholds: pinch `ln(s)/ln 2` per level, commit at 0.5, dead zone 0.03, flick 2.0/s; pan ⅓, flick 800 pt/s, 24 pt min, 12 pt axis lock, rubber band c = 0.55 | Pattern 3 | Feel only; tuned at UAT |
| A7 | One level per gesture (no chaining) satisfies "nearest layout level" | Pattern 3, Open Q2 | User may expect a long pinch to go up several levels |
| A8 | `MTDeviceStart` from a dedicated CFRunLoop thread delivers callbacks off main | Pattern 5 | Harmless either way; spike prints the thread |
| A9 | The refcon register variant takes `(device, callback, refcon)` and its callback has refcon last | Pattern 5 | Wrong signature = memory corruption; M1 checks, fall back to the non-refcon variant + global |
| A10 | ⌥-scroll means fast scroll in VS Code and zoom in some Adobe tools | Pitfall 10 | Documentation only |
| A11 | A gesture during a move or settle can begin follow from presentation rects using the pending target | Pattern 4.4 | Fallback: consume and drop (feels laggy on double pinch) |
| A12 | Magic Mouse ⌥-scroll panning is acceptable | Pitfall 10, Open Q4 | Filter by sender ID if not |

## Open Questions

1. **Ship MT at all if the tap passes everything?**
   - What we know: the tap is required for consumption in every case. MT only adds pinch with system pinch-zoom off, insurance, and maybe latency.
   - Unclear: whether the user values those enough to carry a private framework and canary. ROADMAP's scope note lists "Own MultitouchSupport shim … magnify-event fallback", which reads as MT-primary.
   - Recommendation: build the shim in the spike target either way, and present the decision matrix at the spike gate. Default: tap-only product, MT kept in the spike for future macOS changes.
2. **Multi-level pinch?** D-01 says "nearest layout level". Recommend one level per gesture for v1: `|p|` clamped to ±1.25 with rubber band past 1. Chaining (rebase at p = 1 onto the next parent/child preview) is a contained follow-up if UAT asks.
3. **Gestures during a move or settle:** recommend follow from presentation rects (A11). Fall back to consume-and-drop if it gets complicated. The planner should give it its own task with a VM test.
4. **Magic Mouse:** pan with ⌥ (simplest), or filter to trackpads by sender registry ID? Recommend allow, and revisit at UAT.
5. **Accessibility zoom modifier conflict:** macOS's "Use scroll gesture with modifier keys to zoom" defaults to ⌃, not ⌥ [ASSUMED]. The rule passes when ⌃/⌘ are also held. Confirm at UAT.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift toolchain / Xcode | build | ✓ | Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27.1 | — |
| Host macOS | spike host half | ✓ | 27.0.1 (26A434) | — |
| MultitouchSupport symbols | MT path | ✓ (static) | exports listed above | Tap-only |
| Built-in trackpad (`AppleMultitouchDevice`, Family ID 110) | spike | ✓ | — | — |
| Magic Trackpad | spike M3, UAT | not attached at research time (no `AppleMultitouchDevice` entry besides the built-in) | — | User attaches it for the checklist |
| Tart + VM `pane-test` | VM synthetic tests | ✓ running | tart 2.40.1; guest macOS 15.7.7 | — |
| Tart virtual trackpad | optional user-driven VM gestures | Tart adds `VZMacTrackpadConfiguration` by default unless `--no-trackpad` [CITED: cirruslabs/tart Sources/tart/Platform/Darwin.swift:125-130] | — | Not needed; agents can't drive it over SSH/VNC |
| Terminal Accessibility grant (host) | `tap-consume`, `compare` | unknown | — | User grants it to their terminal for the spike and revokes it afterwards; listen-only subcommands may need Input Monitoring [ASSUMED] |
| xcodegen, jq | existing scripts | ✓ | /opt/homebrew/bin | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** the Magic Trackpad (the user connects it during the spike and UAT).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing; live suites gated by `TRANSOM_LIVE=1`, VM only |
| Config file | `Package.swift` (TransomEngineTests excludes `Fixtures`; traces are loaded by `#filePath`, as `ClassifierCorpusTests` does) |
| Quick run command | `swift test --filter GestureRecognizerTests` (and `GestureTapRulesTests`). Must show ≥ 1 executed test |
| Full suite command | `swift test` (host, headless, includes `check-no-appkit.sh`). Live: `scripts/vm-live-test.sh GestureTapIntegrationTests` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GEST-01 | Magnify sequence → progress → stepIn/stepOut commit or spring back; Reduce Motion snap uses crossfade | unit (engine traces) | `swift test --filter GestureRecognizerTests` | ❌ Wave 0 |
| GEST-01 | ⌥-magnify latched at Began, consumed through Ended; rotate-only passes; envelopes pass | unit (rules) | `swift test --filter GestureTapRulesTests` | ❌ Wave 0 |
| GEST-01/02 | `previewMove` equals the tiles `zoomTo` commits, and does not change `camera.pending`/`nextMoveID` | unit (engine) | `swift test --filter ArrangerCameraTests` | ✅ file exists (add cases) |
| GEST-02 | Pan: axis lock, ⅓ threshold, flick, rubber band at home, momentum ignored except velocity | unit (traces) | `swift test --filter GestureRecognizerTests` | ❌ Wave 0 |
| GEST-02 | ⌥-scroll sequence consumed through momentum end; discrete wheel passes; ⌥ pressed mid-sequence passes | unit (rules) | `swift test --filter GestureTapRulesTests` | ❌ Wave 0 |
| GEST-03 | No ⌥: Finder/0 PID + wallpaper → consume; window → pass; overlay → pass; own panels ignored | unit (rules, injected `topmost`) | `swift test --filter GestureTapRulesTests` | ❌ Wave 0 |
| GEST-04 (leak) | Synthetic sequences posted at the HID tap: 0 downstream events for ⌥ / wallpaper sequences; all downstream for plain-over-window; zoom off → no gesture tap exists and all pass | VM integration | `scripts/vm-live-test.sh GestureTapIntegrationTests` | ❌ Wave 0 |
| GEST-04 (stuck latch) | A sequence with no end, then a fresh plain scroll → pass; timeout clears | unit | `swift test --filter GestureTapRulesTests` | ❌ Wave 0 |
| GEST-04 (mask) | Gesture tap mask has bit 22 and bit 29 and NOT bit 30; InputTap mask unchanged | unit | `swift test --filter GestureTapRulesTests` | ❌ Wave 0 |
| GEST-04 (wake/reconnect) | The tap re-enables after disable (watchdog); state re-published on screensDidWake; MT rescan (if shipped) | VM integration + user UAT | `scripts/vm-live-test.sh GestureTapIntegrationTests`; UAT checklist 5–6 | ❌ Wave 0 |
| GEST-04 (fallback) | `--disable-private=Multitouch` / canary → still launches, tap path works, Debug line says so | unit (Capabilities) + VM launch | `swift test --filter CapabilitiesTests` | ✅ (add cases, only if MT ships) |
| D-07 | Zoom off → no gesture tap, no MT device opened | unit/shell | `swift test --filter ZoomOffTests` | ✅ (add cases) |
| all | Real-trackpad feel and no leak in Safari/Preview, both trackpads | manual (user) | spike checklist + phase UAT | — |

### Sampling Rate
- **Per task commit:** the touched suite's `swift test --filter …`, with an executed count > 0.
- **Per wave merge:** `swift test`.
- **Phase gate:** full suite green, VM `GestureTapIntegrationTests` green (display woken, `caffeinate -dimsu`), spike gates recorded in `05-SPIKE.md` with the user's decision, and the user's UAT checklist passed on both trackpads.

### Wave 0 Gaps
- [ ] `Tests/TransomEngineTests/GestureRecognizerTests.swift` + `Tests/TransomEngineTests/Fixtures/Gestures/*.jsonl`: synthetic traces generated by a helper, plus traces recorded by `transom-gesture-spike tap-listen --record` from the user's real trackpad (the user runs it).
- [ ] `Tests/TransomMacTests/GestureTapRulesTests.swift`.
- [ ] `Tests/TransomMacIntegrationTests/GestureTapIntegrationTests.swift` with a synthetic-event helper and a downstream listen-only tail tap.
- [ ] `scripts/vm-spike.sh` generalization or a sibling for `transom-gesture-spike synth` (it is hard-wired to the `transom-zoom-spike` product today).
- [ ] `Sources/transom-gesture-spike/main.swift` target in `Package.swift`.

## Security Domain

`security_enforcement` is on (ASVS level 1, block on high).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (OS permission) | Accessibility gates the active tap; tear it down when access is lost (existing `accessChanged` path); no new TCC permission |
| V5 Input Validation | yes | Bound the private MT `count` (0…20) and nil-check the pointer before reading memory; treat every private field as untrusted (clamp magnification to ±1 per event, ignore NaN/∞) |
| V6 Cryptography | no | — |
| V7 Error Handling / Logging | yes | No event contents logged per event; never log keystrokes (`keyDown` is not in any mask); sequence summaries only, at debug level, outside the callback |
| V12/V14 Configuration | yes | `--disable-private=Multitouch`, canary persistence in UserDefaults only (no secrets) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Stuck latch swallows all scrolling (input DoS) | Denial of service | Quiet timeout + hard cap + reset on new sequence; unit test; harness time limits |
| Slow callback disables the tap or lags system input | Denial of service | < 1 ms budget, PID short-circuit, at most one CG read per sequence, watchdog re-enable |
| Wrong private prototype → memory corruption | Tampering/DoS | dlsym optionals, prototypes cross-checked across 4 lineages, `Int32` args, spike M1, crash canary |
| MT callback consuming system gestures | Denial of service | Always `return 0`; spike M2 |
| Synthetic events from another process spoofing gestures to drive the camera | Spoofing | Low impact (camera only, no data); don't trust `eventSourceUserData`; optionally ignore events whose source PID (field 41) is non-zero in the product |
| Keystroke capture concern (privacy) | Information disclosure | Gesture tap mask is 22\|29 only; no key events; T-03-28 precedent |
| Harness left running with consume on | DoS | `--seconds` cap (max 120), SIGINT handler, consume only with ⌥ held |

## Sources

### Primary (HIGH confidence)
- macOS 27.0.1 SDK headers: `CGEventTypes.h` (scroll and gesture phase enums, fields 40/42/88/91/96/97/99/123/173, the `CGEventType` enum), `NSEvent.h` (NSEventPhase values, `magnification`, phase delivery rule at Began, `eventWithCGEvent:`), read 2026-10-28.
- Local in-memory probes (`swiftc -swift-version 6`, macOS 27.0.1): type-29 construction, NSEvent bridge decoding to `.magnify`/0.05/`.began` off main, scroll phase mapping, `EventTypeMask.magnify == 1<<30`.
- `xcrun dyld_info -exports` of MultitouchSupport (symbol presence on 27.0.1).
- `ioreg -c AppleMultitouchDevice` (built-in device class, Family ID 110).
- Repo files read this session: `InputTap.swift`, `ZoomTapRules.swift`, `StagePanel.swift`, `ZoomController.swift`, `Arranger+Camera.swift`, `Navigator.swift`, `ArrangeController.swift`, `CGWindowList.swift`, `SessionGate.swift`, `Capabilities.swift`, `Package.swift`, `04-CONTEXT/SPIKE/UAT.md`, `PITFALLS.md`.

### Secondary (MEDIUM confidence; primary third-party sources read via `gh`)
- WebKit `Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h` (CGS event types 28–31, gesture fields 110–148, HID 61/62, phase enum).
- alphaArgon/ScrollToZoom (MIT): `CGEventSPI.h`, `MTSupportSPI.h`, `STZMagicZoom.c` (IOKit hot-plug, MT refcon callback returning int), `STZStateManager.c` (synthetic zoom events), `STZEventHandling.c`.
- joshuarli/iss (0BSD): session-tap suppression of type 29/30, macOS 27 notes.
- jfarcand/mirroir-mcp (Apache-2.0) `CGEventGesture.swift`: real pinch = container + sub-gesture type-29 events, sender field 87.
- Kyome22/OpenMultitouchSupport (MIT) `OpenMTInternal.h`, `OpenMTManager.m`; issues #2, #6, #13.
- lokxii/Mac-trackpad-mapper and asmagill/hs._asm.undocumented.touchdevice (MIT) MultitouchSupport headers.
- mhuusko5/M5MultitouchSupport issue #1 (sleep over-release crash).
- cirruslabs/tart `Sources/tart/Platform/Darwin.swift` (VZMacTrackpadConfiguration default).
- alandaitch/babylock (MIT) gesture-blocking HID tap.

### Tertiary (LOW confidence)
- bitvibelabs/TicTap `App/TouchStream.swift` (non-commercial licence, facts only): 96-byte stride, int32 return.
- moonbai-studio/tungsten-edge (GPL-3, facts only): NSEvent touches empty when built off main; ~200 gesture events/s.
- Zed commit mirror (git.secluded.site) for ⌥-scroll fast scrolling.
- WebSearch results (LOW per classify-confidence): Hammerspoon gesture constructors, Parallels guest gesture docs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH. System APIs only; symbols and fields verified locally.
- Event semantics (types, fields, phases): HIGH. Four sources plus the AppKit bridge probe on 27.0.1.
- Consume over other apps / wallpaper visibility: MEDIUM. Strong indirect evidence (iss, babylock), no direct proof; spike T1/T2.
- MT struct layout and int32 return: MEDIUM / LOW-MEDIUM. Four lineages agree on the layout; the return semantics rest on one beta report; spike M1/M2.
- Architecture (follow mode, preview split): HIGH for fit with the existing code, MEDIUM for feel.
- Pitfalls: MEDIUM-HIGH.

**Research date:** 2026-10-28
**Valid until:** 2026-11-27 (30 days). Re-check at any macOS 27.x point release or 28 beta, given how often gesture plumbing has changed.
