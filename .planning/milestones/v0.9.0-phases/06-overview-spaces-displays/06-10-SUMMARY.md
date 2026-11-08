---
phase: 06-overview-spaces-displays
plan: 10
subsystem: mission-control-takeover
status: complete
tags: [takeover, symbolic-hotkeys, carbon-hotkeys, coredock, crash-safety, canary, over-02, over-03]
requires:
  - phase: 06-01
    provides: "SymbolicHotKeys (isEnabled/setEnabled/value), CoreDock.send, 06-SPIKE Takeover ID set and Abort persistence"
  - phase: 06-09
    provides: "Overview toggle, refusal copy, dispatchAppKitEvents"
provides:
  - "TakeoverStore protocol and TakeoverPolicy (takenIDs, apply, afterReadBack, lift, afterRestore, launch, trigger, drift) in TransomEngine"
  - "TakeoverKeys.carbonModifiers(nx:) and missionControlKeyCode 160"
  - "MissionControlCanary (privateCanary.MissionControl) with turnBackOn, noticed and markNoticed"
  - "MissionControlTakeover: UserDefaultsTakeoverStore (takeover.originals), state, launchRestore, setPreference, apply, lift(reason:), zoomChanged(on:), checkDrift, pendingCrashNotice, crashNoticeShown, onTrigger"
  - "ArrangeController.takeover and missionControlKey() (overview, CoreDock Mission Control, or beep and refusal)"
  - "Launch restore before the Arranger starts; quit, logout and SIGTERM lift"
affects: [06-11, 06-12]
actuals:
  tokens: 11300
  tasks: 3
  commits: 4
plan_head_before: 974b17b1e4d090f2f1fa4b8d6bdd35183ad311a1
plan_head_after: dc9e0a65356f04665dcbd21a62800ef9bd6d41b5
tech-stack:
  added: []
  patterns:
    - "Create the KeyboardShortcuts event stream synchronously (it registers the Carbon hotkey right then), and iterate it in a Task. Creating it inside the Task registers late, and the first key press is lost"
    - "Stored originals are cleared only after a read-back matches. A restore that did not take keeps them for the next launch"
key-files:
  created:
    - Sources/TransomEngine/TakeoverPolicy.swift
    - Sources/TransomMac/MissionControlTakeover.swift
    - Tests/TransomEngineTests/TakeoverPolicyTests.swift
    - Tests/TransomEngineTests/TakeoverKeysTests.swift
    - Tests/TransomMacIntegrationTests/TakeoverIntegrationTests.swift
  modified:
    - Sources/TransomPrivate/Capabilities.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Tests/TransomMacTests/CapabilitiesTests.swift
key-decisions:
  - "Taken IDs: 32 (only while the user has it on), 108, and 113 from the spike (TakeoverPolicy.spikeExtra = [113], taken only while enabled). 34 is allowed by the policy but not taken. 33, 35, 79-82, 115 and 117 are rejected"
  - "Each taken ID's live chord is registered as a Carbon hotkey, so F3, ⌃↑ (or the user's chord) and ⇧F3 all trigger. 108 falls back to key code 160 if it has no value"
  - "Stored originals are cleared only when the restore read-back matches them. Otherwise they stay for the next launch, and a later apply adds missing IDs without overwriting stored ones"
  - "The crash notice (N10) shows once: a `noticed` flag lives in the canary dictionary. The canary stays armed for the same build and version until the user chooses Replace Mission Control again"
  - "Lift clears the canary only when the takeover was on, so quitting while it is off after a crash keeps it off"
  - "Zoom off lifts at the start of turning off, not after the home moves, so F3 goes back to macOS at once"
  - "ArrangeController.takeover is optional and only the app sets it. Host tests never construct a takeover, so no symbolic-hotkey call can run on the host"
requirements-completed: [OVER-02, OVER-03]
coverage:
  - id: D1
    description: "Takeover decision table: never-overwrite apply, read-back, taken IDs, launch restore first, canary off with N10 once, lift, trigger, drift"
    requirement: OVER-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/TakeoverPolicyTests.swift"
        status: pass
      - kind: unit
        ref: "Tests/TransomEngineTests/TakeoverKeysTests.swift"
        status: pass
      - kind: unit
        ref: "Tests/TransomMacTests/CapabilitiesTests.swift#MissionControlCanaryTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "In the VM, apply disables 32/108/113; F3, ⌃↑ and ⇧F3 each open the overview and dismiss it while its key panel is up; zoom off lifts and zoom on re-applies; lift restores the originals and clears the store and the canary"
    requirement: OVER-02
    verification:
      - kind: integration
        ref: "scripts/vm-live-test.sh TakeoverIntegrationTests#missionControlKeysOpenTheOverviewAndLiftRestores"
        status: pass
    human_judgment: false
  - id: D3
    description: "An unlifted takeover (dropped without a lift) is restored by the next launch; state offAfterCrash with N10 pending once"
    requirement: OVER-03
    verification:
      - kind: integration
        ref: "scripts/vm-live-test.sh TakeoverIntegrationTests#launchRestoresUnliftedState"
        status: pass
    human_judgment: false
  - id: D4
    description: "Host check on 27.2: kill -9 Transom with the takeover on, relaunch, F3 opens Mission Control at once"
    requirement: OVER-03
    verification: []
    human_judgment: true
    rationale: "A real crash and relaunch of the app bundle on the user's Mac is the UI-SPEC backstop (06-12 UAT); agents never change the host's symbolic hotkeys"
duration: 12min
completed: 2026-10-31
---

# Phase 6 Plan 10: Mission Control Takeover Engine Summary

**The Mission Control takeover now works. It stores the original shortcut states, disables hotkeys 32, 108 and 113, and reads them back before catching their live chords as Carbon hotkeys. The launch restore runs before the Arranger starts, there is a crash canary, and quit and zoom-off lift the takeover. The VM confirmed that F3, ⌃↑ and ⇧F3 open the overview and, while its key panel is up, close it again.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-10-31T21:03:47Z
- **Completed:** 2026-10-31T21:15:51Z
- **Tasks:** 3
- **Files modified:** 9

## Taken ID set

| ID | Chord (15.7.7) | Taken | Why |
|---|---|---|---|
| 32 | ⌃↑ (vk 126, 0x840000) | yes, while the user has it on | Mission Control |
| 108 | F3 (vk 160, 0x800000) | yes | Mission Control key |
| 113 | ⇧F3 (vk 160, 0x820000) | yes, while enabled | 06-SPIKE: still opened Mission Control with 32/108 off |
| 34 | ⌃⇧↑ | no (allowed by the policy, not taken) | 06-SPIKE: did not open Mission Control |
| 33, 35, 79-82, 115, 117 | — | never (rejected) | D-08 |

## Accomplishments

- `TakeoverPolicy` (pure, Foundation only) decides apply, read-back, lift, launch, trigger and drift over an injected `TakeoverStore`. The decision table is in its doc comment, and 18 tests cover it.
- `MissionControlTakeover` is the only writer of symbolic-hotkey state. Apply follows a fixed order: store originals (synchronised to disk), disable, read back, and only then register Carbon hotkeys and arm the canary. If the read-back fails, it restores the originals and ends in `.offApplyFailed`.
- `launchRestore()` runs in `TransomMacApp.run` right after the activation policy is set and before `arrangeController.start()`. The AppDelegate restore calls `lift(reason: .quit)` first, so ⌘Q, logout and SIGTERM all give the shortcuts back.
- Zoom off lifts the takeover and sets `.liftedForZoom`, keeping the preference. Zoom on re-applies it silently when the preference is on. Each trigger runs `checkDrift()` first.
- The Mission Control key dismisses or opens the overview. When the overview can't open, it opens macOS Mission Control through CoreDock. Without CoreDock it beeps and announces the overview refusal.
- **Answered from the handoff:** Carbon hotkeys (F3, ⌃↑ and ⇧F3) **do fire while the overview's non-activating StagePanel is key**. Each chord dismissed the open overview in the VM.

## Task Commits

1. **Task 1: Tracer, apply → key 160 opens the overview → lift restores (VM live)**: `4ddb3e2` (feat)
2. **Task 2: TakeoverPolicy decision table, TakeoverKeys, MissionControlCanary**: `a830b03` (test, RED), `1d19a03` (feat, GREEN)
3. **Task 3: Launch restore, quit lift, zoom lift and re-apply, drift, CoreDock fallback, unlifted-state VM test**: `dc9e0a6` (feat)

## Files Created/Modified

- `Sources/TransomEngine/TakeoverPolicy.swift`: `TakeoverStore`, `TakeoverPolicy`, `TakeoverKeys`
- `Sources/TransomMac/MissionControlTakeover.swift`: `UserDefaultsTakeoverStore` (validates IDs against `candidateIDs`) and the controller
- `Sources/TransomPrivate/Capabilities.swift`: `MissionControlCanary`
- `Sources/TransomMac/ArrangeController.swift`: `takeover`, `missionControlKey()`, `toggleOverview(trigger:) -> Bool` split out, zoom hooks
- `Sources/TransomMac/TransomMacApp.swift`: launch restore before start, quit lift
- Tests: `TakeoverPolicyTests`, `TakeoverKeysTests`, `MissionControlCanaryTests`, `TakeoverIntegrationTests` (2 VM tests)

## Verification

- `swift test --filter 'TakeoverPolicyTests|TakeoverKeysTests|CapabilitiesTests'`: "Test run with 20 tests in 4 suites passed" and "20 tests in 2 suites passed", with no ✘. `scripts/check-no-appkit.sh` OK.
- Full `swift test` on the host: 809 / 350 / 193 / 83 tests passed (live suites gated off; no takeover code ran on the host).
- `scripts/vm-live-test.sh TakeoverIntegrationTests`: "Test run with 2 tests in 1 suite passed".
- Guest read-back after the runs, using a read-only `SLSIsSymbolicHotKeyEnabled` probe: `32=enabled 108=enabled 113=enabled`.
- Acceptance greps: `setEnabled(` appears only in `MissionControlTakeover.swift`; there is no `com.apple.symbolichotkeys` in Sources; `TransomURL.swift` has no takeover entry; `launchRestore()` comes before `arrangeController.start()`; `lift(reason: .quit)` appears once; `zoomChanged(on:` appears twice.

## Decisions Made

See `key-decisions` in the frontmatter above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The first Mission Control key press after apply was lost**
- **Found during:** Task 1 (first VM run: open and close checks were off by one)
- **Issue:** `KeyboardShortcuts.events(for:)` registers the Carbon hotkey when the stream is created. Calling it inside the Task delayed registration until the Task first ran, after `apply()` had already returned.
- **Fix:** Create the stream synchronously in `apply()` and iterate it in the Task.
- **Files modified:** Sources/TransomMac/MissionControlTakeover.swift
- **Verification:** VM rerun passed, with every chord opening and closing the overview
- **Committed in:** 4ddb3e2

**2. [Rule 2 - Safety] Originals are cleared only after a matching restore read-back**
- **Found during:** Task 1
- **Issue:** The plan's lift said "restore, read back, delete". Deleting after a failed restore would lose the user's originals for good.
- **Fix:** `TakeoverPolicy.afterRestore` clears the store only when every ID reads back its original. The launch action list therefore has `.restore` (restore, read back, clear when matched) and no separate `.clearStore`.
- **Committed in:** 4ddb3e2, 1d19a03

**3. [Rule 1 - Plan typo] Carbon mapping row 0x960000**
- **Issue:** The plan says 0x960000 → 0x1200, but 0x960000 includes ⌘ (0x100000), so the correct value is 0x1300.
- **Fix:** The tests use 0x860000 → 0x1200 (⌃⇧↑, 34) and 0x960000 → 0x1300.
- **Committed in:** a830b03

**4. [Scope] MissionControlCanary has no static per-launch `tripped`**
- **Issue:** A process-wide static reading `.standard` defaults would be dead code, and it could trip on its own arm if first read after an apply.
- **Fix:** `MissionControlTakeover.launchRestore()` decides the trip once per launch on its own defaults. `turnBackOn()` is an instance method.
- **Committed in:** 1d19a03

**5. [Signature] `afterReadBack(_:store:)`, `launch(...crashNoticed:...)`, and `MissionControlTakeover(defaults:zoomOn:)`**
- These carry the store, the once-only N10 fact, and the zoom state that the plan's shorter signatures left implicit.

---

**Total deviations:** 5 (2 bugs, 1 safety, 2 shape adjustments)
**Impact on plan:** Behaviour matches every must-have truth. No scope creep.

## Issues Encountered

None beyond the late-registration bug above.

## Handed to 06-11 (in its plan)

- Wire `checkDrift()` into `StatusItemController.menuWillOpen`, and make Restore macOS Window Settings call `setPreference(false)`. That covers the "status menu opens" half of drift and the Restore-settings lift.
- Post N10 from `pendingCrashNotice`, then call `crashNoticeShown()`. Post N11 when the state is `.offApplyFailed`.
- **06-11's host TakeoverMenuTests need an injected fake hotkey backend.** `MissionControlTakeover` calls `SymbolicHotKeys` directly today, and host tests must never reach those calls. Add the seam (closures for isEnabled, setEnabled and value) before writing any host test that constructs a takeover.
- `isOn` (used in 06-11's plan) does not exist yet. Derive it from `state`.

## Known Stubs

None.

## Threat Flags

None. No new surface beyond the plan's threat model: UserDefaults originals are validated against the takeover's own IDs, and no URL or AppleScript entry exists.

## User Setup Required

None. The 06-12 host UAT item stands: turn the takeover on, check F3 and ⌃↑, quit, then `kill -9` and relaunch.

## Next Phase Readiness

06-11 can build the toggle, the alert, N10/N11 and Debug S5 on `state`, `setPreference`, `pendingCrashNotice` and `checkDrift`. The guest was left with 32, 108 and 113 enabled and on Desktop 1. A read-only probe binary remains at `/tmp/transom-hkread` in the guest.

---
*Phase: 06-overview-spaces-displays*
*Completed: 2026-10-31*

## Self-Check: PASSED
