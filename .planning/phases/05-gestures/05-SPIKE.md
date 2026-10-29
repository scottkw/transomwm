# Phase 5 Spike: Gesture Tap and Multitouch Feasibility (05-01)

**Run:** 2026-10-29. VM half in Tart VM `pane-test` through `scripts/vm-spike.sh` with `SPIKE_PRODUCT=transom-gesture-spike` (agent, `synth` and `mt-devices` only). Host half: run by the user from the checklist below (D-08). No agent ran a tap, multitouch or event-posting subcommand on the host.
**Harness:** `transom-gesture-spike` (Debug build). Its consume decision is the product's own `GestureTapRules.decide` (`Sources/TransomMac/Input/GestureTapRules.swift`), and every undocumented field number comes from `Sources/TransomPrivate/GestureEventFields.swift`. The MultitouchSupport shim lives only in the spike target (`Sources/transom-gesture-spike/Multitouch.swift`).
**Raw data:** JSON lines in `out.jsonl` under each `.build/spike/` directory named below (git-ignored, host only).

## Environment

| Item | Value |
|---|---|
| Host | macOS 27.0.1 (26A434), Xcode 27.1 / Swift 6.4. Built here; live half run by the user |
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
| T1-T6 | no observation | Host half, user-run (checklist below) |
| M1-M4 | no observation | Host half, user-run |

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
**Result:** no observation (checklist item 1).

## T2: consume

**Pass when:** with ⌥, Safari and Preview content neither zooms nor scrolls in 10 of 10 pinches and 10 of 10 pans, momentum included, and the next plain pinch or scroll works in the app 10 of 10 (no stuck state) with the 61/62 envelopes passed. If stuck, flip to consuming the envelopes and re-run.
**Result:** no observation (checklist item 2). VM indication: an ⌥ pinch and an ⌥ pan with momentum were consumed whole by a session tap (0 of 12 and 0 of 18 downstream).

## T3: pass-through

**Pass when:** without ⌥ over a window, app pinch and scroll are unchanged 10 of 10, and a discrete mouse wheel with ⌥ passes.
**Result:** no observation (checklist items 1-2). VM indication: plain pinch and scroll over a window, ⌥ discrete wheel, ⌥⌃ pinch, ⌥⌘ scroll and rotate-only all reached the downstream tap in full.

## T4: coexistence

**Pass when:** 3- and 4-finger swipes and Mission Control work 10 of 10 while the tap runs (the product mask has no bit 30).
**Result:** no observation (checklist items 1-2, 4; `tap-listen` also counts Dock-control events it sees, without consuming them).

## T5: timing

**Pass when:** callback p99 under 1 ms including sequence-start CG reads, p50 under 50 µs for passed events, and zero `tapDisabledByTimeout` in 30 s of heavy scrolling.
**Result:** no observation (checklist item 2 summary). Note: with `trustsTargetPID` off, every no-⌥ sequence start on a desk display pays one CG window list read; item 2 with `--require-alt` skips that read, so T5's worst case is measured only if a run without `--require-alt` is added.

## T6: field availability

**Pass when:** recorded. Whether field 40 (target pid) is non-zero for scroll and type-29 events at the session tap, and (added by this spike) whether it names the app under the pointer or the frontmost app. Decides `trustsTargetPID` in plan 05-03. Also records field 87 senders against the multitouch registry IDs (E-04).
**Result:** no observation on the host (checklist item 1 summary). VM indication: field 40 set on every synthetic event, always the frontmost app.

## M1: multitouch layout

**Pass when:** both devices enumerated with correct built-in flag; with 1-5 fingers x,y in [0,1], stable ids, state transitions 3→4…→5→(6/7), plausible velocities; no crash in 60 s.
**Result:** no observation (checklist item 4; `mt-devices` on the host if wanted). VM: 0 devices.

## M2: Int32 callback return

**Pass when:** with `return 0`, system gestures work 10 of 10 while streaming on macOS 27.0.1.
**Result:** no observation (checklist item 4).

## M3: re-enumeration

**Pass when:** after wake and after a Magic Trackpad off/on, frames resume within 2 s through IOKit notifications, with no crash (no `MTDeviceRelease` on list devices).
**Result:** no observation (checklist items 5-6).

## M4: latency

**Pass when:** reported. Median lead of the first multitouch frame over the first tap event, per gesture kind.
**Result:** no observation (checklist item 7).

## Decision matrix (RESEARCH)

| Result | Primary | Fallback / ship MT? |
|--------|---------|---------------------|
| T1–T5 pass; checklist 3 shows no magnify with pinch-zoom disabled; M4 lead < 30 ms | **Event tap** for recognition and consumption | Don't ship MT (the shim stays in the spike target). Pinch is unavailable when the user turned off system pinch-zoom: say so in the Debug line or log. Recommended default |
| T1–T5 pass, and the user wants pinch even with system pinch-zoom off, or M4 lead ≥ 30 ms | Event tap for consumption and pan; **MT for pinch recognition** when no magnify arrives | Ship MT with canary and IOKit rescan |
| T1 fails over some surface (e.g. wallpaper) but T2 passes elsewhere | Tap consumes where events exist; MT recognizes where they don't | Ship MT |
| T2 fails (cannot consume magnify) | — | GEST-04 can't be met publicly. The only option is a macOS-27-only probe of a non-zero MT return (dangerous). Stop and escalate to the user (RULE 0 spirit) |
| T5 fails | Narrow work: CG read only on Finder/0 PID, or publish window rects from main | Re-run T5 |
| Nothing works | Gestures off, with a Debug line "Gestures: unavailable (…)"; hotkeys, URLs and menu still drive zoom (CONTEXT discretion) | — |

Row the data lands on: pending the host half.

## User decision (E-01)

Pending. Reply "tap-only", "tap+multitouch" or "no-go: …", plus whether checklist item 3 showed pinch lines with "Zoom in or out" off (decides the "pan only" Debug value in plan 05-06). No plan from 05-02 onward runs before this is filled in.
