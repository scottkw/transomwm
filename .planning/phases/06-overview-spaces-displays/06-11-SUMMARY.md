---
phase: 06-overview-spaces-displays
plan: 11
subsystem: mission-control-takeover
status: complete
tags: [takeover, menu, alert, notices, debug, over-02, over-03]
requires:
  - phase: 06-10
    provides: "MissionControlTakeover (state, setPreference, apply, lift, checkDrift, pendingCrashNotice), MissionControlCanary, ArrangeController.takeover"
provides:
  - "HotKeyBackend protocol (LiveHotKeyBackend for SkyLight + Carbon); MissionControlTakeover(defaults:backend:zoomOn:)"
  - "MissionControlTakeover.choose(explain:), isOn, isAvailable, currentChord, debugLine, postCrashNotice(), post/announce callbacks, explainedKey (takeover.explained)"
  - "TakeoverAlert (Surface 5 explanation alert, deferred while busy)"
  - "Notice.takeoverCrashed (N10) and Notice.takeoverApplyFailed (N11)"
  - "O2 Replace Mission Control in the Zoom section, Debug S5, drift check on menu open"
  - "ConflictController.takeover: Restore macOS Window Settings also lifts the takeover"
affects: [06-12]
actuals:
  tokens: 12000
  tasks: 3
  commits: 3
plan_head_before: 6f9b0b31d36ec245eb3c737f2d327ac7d76010b9
plan_head_after: 660bfc031cace949f0331b7e11617bfb1a1e9eed
tech-stack:
  added: []
  patterns:
    - "Private-API side effects go through an injected backend protocol, so host tests use a recording fake and never reach SkyLight or register a Carbon hotkey"
    - "The alert is reached through a closure seam (`choose(explain:)`), so tests answer confirm or decline without a window"
key-files:
  created:
    - Sources/TransomMac/TakeoverAlert.swift
    - Tests/TransomMacTests/TakeoverMenuTests.swift
  modified:
    - Sources/TransomMac/MissionControlTakeover.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Shell/CommandMenu.swift
    - Sources/TransomMac/Shell/OverviewCopy.swift
    - Sources/TransomMac/Shell/NoticeCopy.swift
    - Sources/TransomMac/Overlay/NoticeQueue.swift
    - Sources/TransomMac/ConflictController.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Sources/TransomEngine/Notice.swift
    - Sources/TransomPrivate/SymbolicHotKeys.swift
    - Tests/TransomMacTests/OverviewCopyTests.swift
    - Tests/TransomMacTests/NoticeCopyTests.swift
key-decisions:
  - "Swipe verdict kept (06-SPIKE: skip → kept). No SwipeTakeoverTap.swift. Only the [swipe kept] informative text ships, and there is no ', four-finger swipe' S5 suffix constant at all"
  - "The HotKeyBackend seam covers symbolic-hotkey reads and writes, the capability check, and Carbon registration (KeyboardShortcuts.events). CoreDock stays in ArrangeController.missionControlKey because the takeover never calls it"
  - "Restore macOS Window Settings is wired through ConflictController.takeover: canRestore is true while the takeover is on, and restore() lifts it, then posts N8 even when no Phase 3 originals exist. StatusItemController stays unchanged and the path is unit-tested"
  - "N10 is posted from ArrangeController.start() after the launch's N2/N3, so it queues behind them. A launch-time N11 is posted when ArrangeController.takeover is wired, because the launch apply runs before the post callback exists"
  - "Debug S5 reads 'unavailable (private API off)' whenever the backend is unavailable. TakeoverPolicy reports .unavailable only with the preference on"
  - "After a crash, O2 skips the alert even if takeover.explained is missing (Surface 5: the user has seen it)"
requirements-completed: [OVER-02, OVER-03]
duration: 11min
completed: 2026-10-31
---

# Phase 6 Plan 11: Replace Mission Control User Surface Summary

**Replace Mission Control now sits in the Zoom section as a checkmark toggle. The first time you choose it, a modeless alert explains what it does, with {Keys} read from hotkey 32. The plan adds toasts N10 (crash) and N11 (couldn't apply), makes Restore macOS Window Settings lift the takeover too, adds Debug S5, a drift check when the menu opens, and on/off announcements. Everything is tested against an injected fake backend, so host tests never touch the real Mission Control shortcuts. Swipe: kept, no tap.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-10-31T21:17:47Z
- **Completed:** 2026-10-31T21:28:27Z
- **Tasks:** 3 (Task 3 was the "kept" branch: nothing to change)
- **Files modified:** 15

## Accomplishments

- `HotKeyBackend` seam, the handoff's first requirement. `MissionControlTakeover` now goes through `LiveHotKeyBackend` (SkyLight plus KeyboardShortcuts). Tests use `FakeHotKeys`, which records writes and Carbon registrations and can refuse writes to simulate a failed read-back.
- O2 "Replace Mission Control" comes after Frame Desktop and before Allow Window Previews…, and only shows with zoom on. It is checked while the takeover is on. Without the private symbols it reads "Replace Mission Control (unavailable)" and is disabled.
- `choose(explain:)`: on turns it off at once (no alert, no toast, announces "Mission Control keys restored"). Off shows the alert unless it was confirmed before or a crash turned the takeover off. The confirmed flag is saved only on confirm. A successful turn-on announces "Mission Control keys show the overview".
- `TakeoverAlert` works like ExplainerAlert: informational, Return confirms, Esc or closing means Not Now, it waits while a drag is in progress, a mouse button is down, or the overview is open, and it reads {Keys} when it appears.
- N10 and N11 are wired through the NoticeQueue. N11's glyph is the warning orange.
- Restore macOS Window Settings is enabled while the takeover is on. Choosing it lifts the takeover, then shows N8.
- Debug S5 sits between S4 and S6. The status menu opening runs `checkDrift()`.

## Task Commits

1. **Task 1 (tracer): O2 → alert confirm → takeover on → S5 "on, F3 and ⌃↑"**: `589afc6` (feat)
2. **Task 2: N10/N11, Restore hook, announcements, drift on menu open**: `fa527ca` (test, RED), `660bfc0` (feat, GREEN)
3. **Task 3: swipe variant**: no commit. The verdict is **swipe kept, no tap**: `SwipeTakeoverTap.swift` does not exist, and `grep -c 'four-finger swipe' OverviewCopy.swift` = 0 (no suffix constant either)

## Verification

- Task 1 gate: `swift test --filter 'TakeoverMenuTests|OverviewCopyTests'` printed "Test run with 21 tests in 2 suites passed", with no ✘. The tracer gate re-ran it end-to-end and it passed.
- Task 2 gate: `swift test --filter 'NoticeCopyTests|NoticeQueueTests|TakeoverMenuTests|ConflictControllerTests'` printed "Test run with 44 tests in 4 suites passed", with no ✘. RED was confirmed first: the build failed on the missing `Notice.takeoverCrashed`.
- Full host `swift test`: 809 / 363 / 193 / 83 passed. Live suites are gated off, and no host test constructs a takeover with the live backend.
- Task 3: `swift build` OK, and 06-SPIKE.md records "swipe kept".
- `scripts/check-no-appkit.sh` OK. CommandMenuTests (zoomSection signature) passed: 16 tests.
- Acceptance greps: the alert message (1), "(unavailable)" (1), the [swipe kept] sentence (1), N10 text (1), N11 text (1), and `checkDrift()` in StatusItemController (1).
- Guest read-back with the read-only `/tmp/transom-hkread` probe: `32=enabled 108=enabled 113=enabled`. This plan made no VM writes.

## Decisions Made

See `key-decisions` in the frontmatter above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Public `SymbolicHotKeys.Value` initializer**
- **Found during:** Task 1
- **Issue:** The fake backend could not create a `Value`, because the memberwise init is internal to TransomPrivate.
- **Fix:** Added `public init(keyCode:modifiers:)`.
- **Files modified:** Sources/TransomPrivate/SymbolicHotKeys.swift
- **Commit:** 589afc6

**2. [Rule 3 - Blocking] Exhaustive switches over `Notice`**
- **Found during:** Task 2
- **Issue:** The new cases had to reach `NoticeQueue.merged` (Overlay/NoticeQueue.swift) and `ArrangeController.displayUUID`, which were not in the plan's file list.
- **Fix:** Neither case merges, and both use the default display.
- **Commit:** 660bfc0

**3. [Rule 1 - Bug] S5 unavailable with the preference off**
- **Found during:** Task 1
- **Issue:** With the private API off and the preference off, the policy reported `.off`, so S5 would say "off" rather than why.
- **Fix:** `debugLine` returns `.unavailable` whenever the backend is unavailable.
- **Commit:** 589afc6

**4. [Design] Where the Restore hook lives**
- **Planned:** The plan put the Restore hook in StatusItemController (`conflicts.canRestore || takeover.isOn`).
- **Done:** It lives in `ConflictController` (a `takeover` property), so the behaviour is unit-testable without creating a real NSStatusItem on the host. The behaviour is the same, and N8 now also shows when only the takeover was restored.

**5. [Design] Alert test seam**
- **Planned:** The plan put the alert's test seam on TakeoverAlert.
- **Done:** The seam is the `explain` closure passed to `MissionControlTakeover.choose(explain:)`. StatusItemController passes one that shows TakeoverAlert, and tests answer it directly. No window is ever shown in tests.

**6. [Scope] Menu-open drift test**
- **Planned:** A test of drift on menu open.
- **Done:** That test calls `checkDrift()` directly, and a grep confirms `menuWillOpen` calls it. StatusItemController itself is not constructed in tests, because it would add a real status item to the host menu bar.

## Known Stubs

None.

## Next Phase Readiness

- 06-12 UAT should check on the host and in the VM: the alert's look and keys, Esc and close mean Not Now, the O2 checkmark, N10 after kill -9, N11 (hard to cause on purpose), and Restore macOS Window Settings with the takeover on.

## Self-Check: PASSED

- FOUND: Sources/TransomMac/TakeoverAlert.swift, Tests/TransomMacTests/TakeoverMenuTests.swift
- FOUND commits: 589afc6, fa527ca, 660bfc0
- NOT PRESENT (by design): Sources/TransomMac/Input/SwipeTakeoverTap.swift
