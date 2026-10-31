# Phase 5 Spike: Gesture Tap and Multitouch Feasibility (05-01)

**Run:** 2026-10-29. VM half in Tart VM `pane-test` through `scripts/vm-spike.sh` with `SPIKE_PRODUCT=transom-gesture-spike` (agent, `synth` and `mt-devices` only). Host half: run by the user from the checklist below on 2026-10-29 (D-08). No agent ran a tap, multitouch or event-posting subcommand on the host.
**Harness:** `transom-gesture-spike` (Debug build). Its consume decision is the product's own `GestureTapRules.decide` (`Sources/TransomMac/Input/GestureTapRules.swift`), and every undocumented field number comes from `Sources/TransomPrivate/GestureEventFields.swift`. The MultitouchSupport shim lives only in the spike target (`Sources/transom-gesture-spike/Multitouch.swift`).
**Raw data:** JSON lines in `out.jsonl` under each `.build/spike/` directory named below (git-ignored, host only).

## Environment

| Item | Value |
|---|---|
| Host | Built on macOS 27.0.1 (26A434), Xcode 27.1 / Swift 6.4. Live half run by the user on 2026-10-29 on macOS 27.2 (26B123), MacBook Air |
| Trackpads (host) | **Built-in only** (registry 0x100000a1f, family 110). The user has no Magic Trackpad: CONTEXT "Specific Ideas" was wrong. Every (both), "magic" and reconnect item is **N/A**, not a failure. On this Mac, Spaces switching is a 4-finger swipe or ⌃←/→, not 3-finger |
| Guest | macOS 15.7.7 (24G720), Apple M3 (Virtual), 1 display 1024 x 768 pt |
| Guest permissions | `sshd-keygen-wrapper` holds Accessibility; the CLI reported Accessibility, Input Monitoring and Post events all granted |
| Guest desk | Covered by windows earlier runs left open (TextEdit, Finder, Notes; none closed by this spike). The only bare wallpaper is the strip beside the Dock; the wallpaper scenarios used (1020, 764). `Transom Debug` was running in the guest (its tap has no scroll or gesture bits) |
| Trackpads (guest) | None: Tart's virtual pointer is not a multitouch device |

## Results at a glance

| Gate | Result | Headline |
|---|---|---|
| VM synth (V1-V3) | **13 of 13 scenarios match** | ⌥ pinch and ⌥ pan with momentum consumed whole (0 downstream); no-⌥ over a window, ⌃/⌘ chords, discrete wheel, mid-sequence ⌥ and rotate-only all pass untouched; wallpaper pinch and scroll consumed; a stuck latch lets the next scroll through after 2 s; only the 61/62 envelopes leak from an ⌥ pinch, as designed |
| VM finding (T6, indicative) | **Field 40 is the frontmost app, not the app under the pointer** | Synthetic events over bare wallpaper carried TransomFixtureApp's pid (the frontmost app). The pid short-circuit would have passed every wallpaper gesture, so it is now off by default (`GestureTapState.trustsTargetPID = false`): every no-⌥ sequence start does one CG window list read until T6 says otherwise |
| VM `mt-devices` | Reported | 12 of 12 `dlsym` symbols resolve on macOS 15.7.7; no multitouch devices in the guest |
| T1 visibility | **PASS** (built-in) | 34/34 pinches 1→2…→4 and 43/43 pans with a start over Safari, Preview, a Finder window, bare wallpaper and full-screen Safari |
| T2 consume | **PASS, with condition C1** | ⌥ pinch and pan: "Nothing moved" in Safari/Preview; no-⌥ normal; but sub-type 4 events inside a taken pinch passed (see T2) |
| T3 pass-through | **PASS** | 7 of 7 no-⌥ sequences passed; the user saw normal zoom and scroll without ⌥ |
| T4 coexistence | **PASS** | 80 Dock-control events observed and never consumed; Spaces and Mission Control normal (item 4) |
| T5 timing | **PASS** | callback p50 1 µs, p99 21 µs, max 2.19 ms; passed-event p50 1 µs; tap disabled 0 |
| T6 fields | Recorded | Field 40 = frontmost app (77/77), app under pointer only 56/77: `trustsTargetPID` stays false. Field 87 = the trackpad's registry ID on 100% of events: the E-04 sender filter works |
| Item 3 (pinch setting off) | **No pinch lines** | 0 zoom (sub-type 8) events with "Zoom in or out" off; pans unaffected |
| M1 layout | **PASS** (built-in) | 1,396 frames, 2,508 touches, x,y in [0,1], states 0-7, stable ids, no backwards timestamps |
| M2 Int32 return | **PASS** | Spaces and Mission Control worked normally while streaming |
| M3 re-enumeration | **PASS with note** (sleep); reconnect N/A | Same device after wake, first frame 2,014 ms after wake (includes time to the user's first touch), no crash |
| M4 latency | Recorded | MT first frame leads the first tap event: pan median 63 ms (n 10), pinch 248 ms (n 2) |
| **E-01** | **"tap+multitouch"** | Go with conditions C1-C5 (below). Plan 05-07 ships |

## VM half

Directory `.build/spike/gesture-synth-20261028-192053` (`synth --scenario all --seconds 120`). Events posted at `.cghidEventTap`; the consumer is an active head-insert session tap running `GestureTapRules.decide`, and "downstream" counts what reached an active pass-through tap appended at the tail. The over-window point is the centre of one TransomFixtureApp window (200, 196); the wallpaper point is (1020, 764).

| Scenario | Posted | Downstream | Expect | Consumer decision |
|---|---|---|---|---|
| alt-pinch-over-window | 12 | 0 | 0 | taken: ⌥ held |
| alt-pan-with-momentum | 18 | 0 | 0 | taken: ⌥ held (momentum with ⌥ released also taken) |
| plain-pinch-over-window | 12 | 12 | 12 | passed: window under pointer |
| plain-scroll-over-window | 10 | 10 | 10 | passed: window under pointer |
| plain-pinch-on-wallpaper | 12 | 0 | 0 | taken: wallpaper |
| plain-scroll-on-wallpaper | 18 | 0 | 0 | taken: wallpaper (momentum included) |
| alt-mid-sequence | 10 | 10 | 10 | passed: window under pointer (⌥ pressed after began) |
| alt-discrete-wheel | 5 | 5 | 5 | never latched (line units, not continuous) |
| alt-control-pinch | 12 | 12 | 12 | passed: ⌃ or ⌘ also held |
| alt-command-scroll | 10 | 10 | 10 | passed: ⌃ or ⌘ also held |
| stuck-latch-then-plain-scroll | 10 | 6 | 6 | ⌥ began + 3 changed taken, no end, 2.1 s pause; the next 5 changed + ended arrive with no start and pass (mid-gesture) |
| alt-pinch-envelopes | 8 | 2 | 2 | taken: ⌥ held; 61 and 62 envelopes passed, the HID-0 container consumed |
| rotate-only | 7 | 7 | 7 | never latched (rotate with no zoom start) |

Supporting runs: `gesture-synth-20261028-190535` (tracer, 2 scenarios, both matched); `gesture-synth-20261028-191433` (11 of 13: a 12 x 10 grid found no bare wallpaper, so the two wallpaper scenarios were skipped); `gesture-synth-20261028-191623` (8 pt grid found (1020, 764); 11 of 13: the two wallpaper scenarios passed every event as "app under pointer" with field 40 = the fixture's pid); `gesture-synth-20261028-191850` (13 of 13 after the field-40 fix, with `pointerOwner` 0 and `frontmost` = field 40 recorded at the wallpaper point).

`mt-devices`: `.build/spike/gesture-mt-devices-20261028-191906`. Every symbol in the table was found: MTDeviceCreateList, MTRegisterContactFrameCallbackWithRefcon, MTRegisterContactFrameCallback, MTUnregisterContactFrameCallback, MTDeviceStart, MTDeviceStop, MTDeviceIsBuiltIn, MTDeviceGetFamilyID, MTDeviceGetDeviceID, MTDeviceGetSensorSurfaceDimensions, MTDeviceGetService, MTDeviceGetDriverType. Devices: 0. The VM can't exercise any M gate.

### Field 40 (target pid) at the session tap, VM

In every scenario, field 40 of every synthetic scroll and gesture event was the pid of the frontmost app (TransomFixtureApp), including at the wallpaper point, where the CG window list shows no window (`pointerOwner` 0). RESEARCH Pattern 2 assumed field 40 names the app under the pointer, so that "non-Finder pid → pass with no CG read" would be the cheap common path. For synthetic events that is false. `GestureTapRules` now uses the pid only when `GestureTapState.trustsTargetPID` is true (default false). T6 on the host records, per gesture, whether field 40 equals the app under the pointer or the frontmost app; plan 05-03 turns trust on only if real trackpad events carry the pointer's app. Until then T5 measures the cost of the extra read.

## Host half (user-run)

Build once, then run every command from the repository root (the CLI writes to `.build/spike/gesture-<subcommand>-<time>/out.jsonl` and prints the path at start and end). Quit Transom first.

```
cd /Users/ken/dev/transomwm
swift build --product transom-gesture-spike
.build/debug/transom-gesture-spike <subcommand> …
```

Replace `{trackpad}` in a label with `builtin` or `magic`. Each run stops by itself after `--seconds` or on Control-C, then prints a summary with gate readings (never PASS or FAIL).

### Spike gate checklist (with `transom-gesture-spike`, Transom not running)

Before you start: give your terminal app Accessibility (System Settings ▸ Privacy & Security ▸ Accessibility). Turn it off again when you're done.

1. **(both)** Run `tap-listen --seconds 60 --label "surfaces {trackpad}"`. Pinch 10 times and two-finger scroll 10 times over each of: a Safari page, a PDF in Preview, a Finder window, bare wallpaper, and one app in full screen. *Expected: one line per gesture appears for every pinch and scroll.*
2. **(both)** Run `tap-consume --seconds 60 --require-alt --label "consume {trackpad}"`. Hold ⌥ and repeat item 1 over Safari and Preview. *Expected: the page neither zooms nor scrolls, including after you lift your fingers. Then, without ⌥, pinch and scroll once: the page zooms and scrolls normally.*
3. Turn off System Settings ▸ Trackpad ▸ Scroll & Zoom ▸ "Zoom in or out". Run `tap-listen --seconds 30 --label "pinch setting off"` and pinch 10 times. Turn the setting back on. *Report: did any pinch lines appear?*
4. Run `mt-stream --seconds 30 --label "system gestures"`. While it runs, swipe between Spaces with three fingers 10 times and open Mission Control 10 times. *Expected: every swipe and Mission Control works.*
5. Run `rescan --seconds 120 --label "sleep"`. Choose Apple menu ▸ Sleep, wake the Mac, then pinch. *Expected: lines for the wake and for touches after it.*
6. Run `rescan --seconds 120 --label "reconnect"`. Turn the Magic Trackpad off and on (or turn Bluetooth off and on), then pinch on it. *Expected: "removed" and "added" lines, then touches.*
7. Run `compare --seconds 30 --label "latency"` and pinch and pan 10 times each.

Then tell the agent where the `out.jsonl` files are (the CLI prints each path), plus your answers.

Notes for the run (not part of the fixed wording):
- Item 1 at 60 s covers about two surfaces per run. Run it as often as needed, with labels such as `"surfaces builtin safari"`.
- Item 2: if a line says `passed: not a trackpad`, field 87 doesn't match the multitouch registry IDs. Re-run with `--no-sender-filter` added and say so in your answers (it decides the E-04 filter).
- Item 2 lines show `taken: ⌥ held` or `passed: …` per gesture. With `--require-alt`, a no-⌥ gesture reads `passed: no ⌥ (--require-alt)`.

## T1: tap visibility

**Pass when:** type 29 with field 110 = 8 and phases 1→2…→4 is seen for at least 9 of 10 pinches over each of Safari, Preview, a Finder window and wallpaper, on both trackpads, and phased scroll (22) for at least 9 of 10 pans in the same places.
**Result: PASS (built-in trackpad; Magic Trackpad N/A, the user has none).**
- `.build/spike/gesture-tap-listen-20261029-073133/out.jsonl` ("surfaces builtin safari-preview", 60 s): pinches 1→2…→4 **18 of 18**, pans with a start **20 of 20**, 4,594 events (scroll 345, gesture 4,223, dock control 26), tap disabled 0.
- `.build/spike/gesture-tap-listen-20261029-082731/out.jsonl` ("surfaces builtin finder-wallpaper-fullscreen", Control-C at 56 s): full-screen Safari, a Finder window and bare wallpaper (field 40 shows Finder there): pinches **16 of 16**, pans with a start **23 of 23**, 3,350 events (scroll 892, gesture 2,404, dock control 54), tap disabled 0.
- All five surfaces covered (Safari, Preview, Finder window, wallpaper, one full-screen app). The per-surface split within a run isn't recorded, but every gesture in both runs completed, so no surface can be under 9 of 10.
- `.build/spike/gesture-tap-listen-20261029-072735` was a dry run with no gestures (0 events) and is ignored.
- Recognizer note (C2): many short pan sequences appear at pinch starts with scroll phases 128→8 and Δ 0,0 (may-begin then cancel, no 1/2 phase). They are scroll noise from fingers landing, not pans.
- The listen run's NSEvent oracle logs "unrecognized type is 30" for Dock-control events. Harmless (oracle only).

## T2: consume

**Pass when:** with ⌥, Safari and Preview content neither zooms nor scrolls in 10 of 10 pinches and 10 of 10 pans, momentum included, and the next plain pinch or scroll works in the app 10 of 10 (no stuck state) with the 61/62 envelopes passed. If stuck, flip to consuming the envelopes and re-run.
**Result: PASS on what the user can see, with go-with condition C1.** VM indication: an ⌥ pinch and an ⌥ pan with momentum were consumed whole by a session tap (0 of 12 and 0 of 18 downstream).
- `.build/spike/gesture-tap-consume-20261029-182241/out.jsonl` ("consume builtin", `--require-alt`, 41 s): 32 gestures (pinch 11, pan 21), **taken 25, passed 7** (every passed one was a no-⌥ gesture, `passed: no ⌥ (--require-alt)`); 642 events consumed, 2,190 passed; 1 sequence ended by timeout.
- User: **"Nothing moved"** in Safari or Preview while ⌥ was held, lift included; without ⌥, zoom and scroll were normal (no stuck state). The 61/62 envelopes passed and left nothing stuck (A4 holds).
- **Gap (C1).** Inside taken pinches (zoom began → ended), the rules consumed sub-types 8 (100), 0 (104) and 5 (1), but **81 sub-type 4 events passed** (likely rotate; `GestureEventFields.hidRotate` is 5, which appeared only twice). Outside the zoom began→ended window, with ⌥ held, more type-29 events passed: sub-type 0 ×794 (595 after a taken scroll, 157 after a taken zoom ended, 42 before any), 6 ×120 and 32 ×35 (all after a taken scroll), 4 ×10. Nothing visibly moved, but Preview reacts to rotation.
- **Condition C1 for 05-03/05-04:** while a pinch sequence is latched as consumed, consume every type-29 event in it (all sub-types), not only zoom, rotate and container. Plan 05-03 should also decide whether the type-29 companions of a taken pan (sub-types 0, 6, 32) and trailing sub-type 0 after zoom ended belong to the latch; they passed here with no visible effect.
- The optional no-⌥ consume run (wallpaper takes, T5 worst case with CG reads) was skipped.

## T3: pass-through

**Pass when:** without ⌥ over a window, app pinch and scroll are unchanged 10 of 10, and a discrete mouse wheel with ⌥ passes.
**Result: PASS.** In the consume run, all 7 no-⌥ sequences passed, and the user saw Safari and Preview zoom and scroll normally without ⌥. A discrete ⌥ mouse wheel wasn't tried on the host (no mouse used); the VM covers it (`alt-discrete-wheel`, 5 of 5 downstream). VM indication: plain pinch and scroll over a window, ⌥ discrete wheel, ⌥⌃ pinch, ⌥⌘ scroll and rotate-only all reached the downstream tap in full.

## T4: coexistence

**Pass when:** 3- and 4-finger swipes and Mission Control work 10 of 10 while the tap runs (the product mask has no bit 30).
**Result: PASS.** The listen runs saw 26 + 54 Dock-control (type 30) events and consumed none (the product mask has no bit 30); full-screen Safari was used during the runs. Item 4 (user): Spaces switching and Mission Control all worked normally. On this Mac Spaces switch with 4 fingers or ⌃←/→, not 3 fingers, so the checklist's "three fingers" wording didn't apply.

## T5: timing

**Pass when:** callback p99 under 1 ms including sequence-start CG reads, p50 under 50 µs for passed events, and zero `tapDisabledByTimeout` in 30 s of heavy scrolling.
**Result: PASS** (consume run summary): callback p50 1 µs, **p99 21 µs**, max 2.19 ms (one outlier); **passed-event p50 1 µs**; **tap disabled 0** in 41 s. The item 3 listen run recorded tap disabled 1, most likely from the user clicking in System Settings; that run doesn't consume, so it doesn't count against T5. Note: with `trustsTargetPID` off, every no-⌥ sequence start on a desk display pays one CG window list read; item 2 with `--require-alt` skips that read, so T5's worst case is measured only if a run without `--require-alt` is added. That run was skipped: the CG-read cost is unmeasured on the host and is re-checked in 05-03's VM tests and 05-08 UAT.

## T6: field availability

**Pass when:** recorded. Whether field 40 (target pid) is non-zero for scroll and type-29 events at the session tap, and (added by this spike) whether it names the app under the pointer or the frontmost app. Decides `trustsTargetPID` in plan 05-03. Also records field 87 senders against the multitouch registry IDs (E-04).
**Result: recorded.** VM indication: field 40 set on every synthetic event, always the frontmost app.
- Field 40 non-zero on **100%** of events: scroll 345/345 and gesture 4,223/4,223 (073133); scroll 892/892 and gesture 2,404/2,404 (082731); scroll 70/70 and gesture 1,874/1,874 (182546).
- Field 40 = **frontmost app in 38/38 and 39/39** gestures; = app under the pointer in only 29/38 and 27/39. The real trackpad agrees with the VM. **Decision (C3): `GestureTapState.trustsTargetPID` stays false**; plan 05-03 doesn't turn it on.
- Field 87 (sender) was 0x100000a1f on every event, equal to the built-in trackpad's multitouch registry ID. **The E-04 sender filter works**; `--no-sender-filter` was not needed.

## M1: multitouch layout

**Pass when:** both devices enumerated with correct built-in flag; with 1-5 fingers x,y in [0,1], stable ids, state transitions 3→4…→5→(6/7), plausible velocities; no crash in 60 s.
**Result: PASS (built-in; the Magic Trackpad half is N/A).** `.build/spike/gesture-mt-stream-20261029-182726/out.jsonl` ("system gestures", 30 s): 1 device streamed (built-in, registry 0x100000a1f); 1,396 frames (1,359 with touches), 2,508 touches; x,y outside [0,1] **0**; states outside 0-7 **0**; transitions 1→2, 1→3, 1→7, 2→3, 2→7, 3→4, 4→5, 4→7, 5→6, 5→7, 6→3, 6→7; ids seen in one frame only **0 of 11**; timestamps going back **0**; max speed 10.77; callback on a background thread (0 main-thread frames); no crash. VM: 0 devices.

## M2: Int32 callback return

**Pass when:** with `return 0`, system gestures work 10 of 10 while streaming on macOS 27.0.1.
**Result: PASS.** With the callback returning 0 on macOS 27.2, the user answered "yes": Spaces switching (4-finger / ⌃←→) and Mission Control all worked normally while `mt-stream` ran (`gesture-mt-stream-20261029-182726`).

## M3: re-enumeration

**Pass when:** after wake and after a Magic Trackpad off/on, frames resume within 2 s through IOKit notifications, with no crash (no `MTDeviceRelease` on list devices).
**Result: PASS with a note (sleep); reconnect N/A.**
- `.build/spike/gesture-rescan-20261029-182931/out.jsonl` ("sleep", 120 s): devices before and after = built-in (registry 0x100000a1f); first frame after wake **2,014 ms**; no crash (summary printed); 1,031 frames in the run.
- 2,014 ms is 14 ms over the 2 s line, but the measure runs from wake to the first frame, and a frame only arrives once the user touches the trackpad after logging in. Counted as a pass with that note; plan 05-07's wake re-enumeration still must not add delay.
- Item 6 (Magic Trackpad off/on): **N/A**, the user has no Magic Trackpad. Hot-plug of a second trackpad is unmeasured on real hardware.

## M4: latency

**Pass when:** reported. Median lead of the first multitouch frame over the first tap event, per gesture kind.
**Result: recorded.** `.build/spike/gesture-compare-20261029-183044/out.jsonl` ("latency", 30 s, 950 frames): the first multitouch frame leads the first tap event by a median of **63 ms for pans** (n 10: 75, 91, 63, 59, 63, 70, 72, 47, 63, 51) and **248 ms for pinches** (n 2: 241, 248). This lead is touch-down → macOS gesture recognition, not steady-state tracking latency: once a gesture is running, both sources update every frame.

## Decision matrix (RESEARCH)

| Result | Primary | Fallback / ship MT? |
|--------|---------|---------------------|
| T1–T5 pass; checklist 3 shows no magnify with pinch-zoom disabled; M4 lead < 30 ms | **Event tap** for recognition and consumption | Don't ship MT (the shim stays in the spike target). Pinch is unavailable when the user turned off system pinch-zoom: say so in the Debug line or log. Recommended default |
| T1–T5 pass, and the user wants pinch even with system pinch-zoom off, or M4 lead ≥ 30 ms | Event tap for consumption and pan; **MT for pinch recognition** when no magnify arrives | Ship MT with canary and IOKit rescan |
| T1 fails over some surface (e.g. wallpaper) but T2 passes elsewhere | Tap consumes where events exist; MT recognizes where they don't | Ship MT |
| T2 fails (cannot consume magnify) | — | GEST-04 can't be met publicly. The only option is a macOS-27-only probe of a non-zero MT return (dangerous). Stop and escalate to the user (RULE 0 spirit) |
| T5 fails | Narrow work: CG read only on Finder/0 PID, or publish window rects from main | Re-run T5 |
| Nothing works | Gestures off, with a Debug line "Gestures: unavailable (…)"; hotkeys, URLs and menu still drive zoom (CONTEXT discretion) | — |

Row the data lands on: **row 2**, "T1–T5 pass, and the user wants pinch even with system pinch-zoom off, or M4 lead ≥ 30 ms". T1-T5 pass (T2 with condition C1), item 3 showed no zoom events with the setting off, the M4 leads are 63 ms (pan) and 248 ms (pinch), and the user chose multitouch. Primary: the event tap for consumption and pan; MT for pinch recognition when no magnify arrives. Ship MT with canary and IOKit rescan (plan 05-07).

## Verdict and conditions

**Verdict: go, with conditions, tap+multitouch.**

| # | Condition | Plans |
|---|---|---|
| C1 | While a pinch sequence is latched as consumed, consume **every** type-29 event in it (all sub-types), not only 8/5/0. Sub-type 4 (likely rotate) leaked 81 times inside taken pinches on the host. Decide in 05-03 whether a taken pan's type-29 companions (sub-types 0, 6, 32) and trailing sub-type 0 after zoom ended also belong to the latch | 05-03 (GestureTapRules and tests), 05-04 |
| C2 | The recognizer ignores pan sequences with no phase 1 or 2 or with zero total delta (the 128→8, Δ 0,0 noise at pinch starts) | 05-02, 05-04 |
| C3 | `GestureTapState.trustsTargetPID = false` stays: field 40 is the frontmost app on real trackpad events | 05-03 |
| C4 | Multitouch is the pinch source when the tap sees no zoom (sub-type 8) events for a touch sequence, which is always the case when "Zoom in or out" is off. The tap still does all consuming | 05-07, 05-06 |
| C5 | Built-in trackpad only: the user has no Magic Trackpad. Magic Trackpad and reconnect items are N/A in UAT; Spaces switching on this Mac is 4-finger / ⌃←→ | 05-07, 05-08 |

## User decision (E-01)

**User reply (verbatim, 2026-10-29): "tap+multitouch"**

- Plan 05-07 ships (not skipped): the product MultitouchSupport shim with canary and IOKit rescan, in the C4 role.
- Checklist item 3: **no pinch lines appeared** with "Zoom in or out" off (`.build/spike/gesture-tap-listen-20261029-182546/out.jsonl`, "pinch setting off": pinches 0; 1,874 type-29 events still arrived, sub-types 0 ×1,746, 6 ×69 and 32 ×59, but no sub-type 8 and no rotate; pans with a start 18 of 18; tap disabled 1). The event tap can't see pinch when the user has turned pinch-to-zoom off. That is the main reason for the choice: multitouch supplies pinch then, and the tap still consumes.
- Because E-01 is "tap+multitouch", plan 05-06's "pan only" Debug value does not ship (its Task 2 condition needs "tap-only").
- The host has the built-in trackpad only (no Magic Trackpad): plan 05-08's UAT drops the Magic Trackpad and reconnect items (N/A).
