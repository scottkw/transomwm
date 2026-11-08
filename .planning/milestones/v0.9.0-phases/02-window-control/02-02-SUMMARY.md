---
phase: 02-window-control
plan: 02
subsystem: app-shell
tags: [swift, appkit, nsstatusitem, xcodegen, codesign, developer-id, hardened-runtime, swift-testing]

requires:
  - phase: 02-window-control
    plan: 01
    provides: "AXWindowSystem (events, inventory(), capabilityReport, start()), PaneMacApp.run, PaneApp main.swift, PaneMac library product"
provides:
  - "StatusItemController: menu-bar item (rectangle.split.2x1 template, 16 pt) with a menu rebuilt in menuNeedsUpdate from the cached inventory"
  - "MenuCopy: plural-correct header, degraded line, capability item, 32-grapheme app-name truncation"
  - "xcode/project.yml + xcode/Pane.entitlements: XcodeGen spec for Developer-ID-signed, hardened Pane Debug.app / Pane.app"
  - "scripts/generate.sh, scripts/build-debug.sh [--release], scripts/run-debug.sh [--no-build] [args...]"
affects: [02-05, 02-08, 02-13, phase-03]

actuals:
  tokens: 5764
  tasks: 2
  commits: 4
plan_head_before: 5b262a31efd671a1dacc7df21ca8f57258ab9a8e
plan_head_after: 4616bfbb0637ed3e0012e77f68fdd060c3618694

tech-stack:
  added: ["XcodeGen 2.46.0 (dev tool, Homebrew homebrew/core, homepage github.com/yonaskolb/XcodeGen)"]
  patterns:
    - "Status menu rebuilt in menuNeedsUpdate from a cached WindowInventory that a MainActor Task refreshes after every WindowEvent"
    - "Menu copy lives in a nonisolated pure enum (MenuCopy) so it is unit-tested without AppKit"
    - "Entitlements are declared as `properties` in project.yml because XcodeGen rewrites the entitlements file on every generate"
    - "Build scripts print progress to stderr and the app path as the last stdout line"

key-files:
  created:
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Tests/PaneMacTests/MenuCopyTests.swift
    - xcode/project.yml
    - xcode/Pane.entitlements
    - scripts/generate.sh
    - scripts/build-debug.sh
    - scripts/run-debug.sh
    - .planning/phases/02-window-control/tdd/02-02-red.json
  modified:
    - Sources/PaneMac/PaneMacApp.swift
    - .gitignore

key-decisions:
  - "xcode/project.yml declares com.apple.security.app-sandbox=false under entitlements.properties, because XcodeGen overwrites Pane.entitlements on each generate (it wrote an empty dict without them)"
  - "The target uses `scheme: {}` so `xcodebuild -scheme Pane` resolves (Assumption A4 confirmed: manual Developer ID signing of Debug works with no provisioning profile and no keychain prompt)"
  - "PaneMacApp keeps the StatusItemController in a static; it owns the AXWindowSystem, so withExtendedLifetime was dropped"
  - "Release builds universal (arm64 + x86_64) by default with -warnings-as-errors, matching the Intel support floor"

patterns-established:
  - "Later plans add status-menu sections as add…Items(to:) methods in StatusItemController and their copy as MenuCopy functions with tests"

requirements-completed: [WIN-01, WIN-02, SAFE-05]

coverage:
  - id: D1
    description: "Menu copy is plural-correct (No windows to track / Tracking 1 window in 1 app / Tracking 12 windows in 5 apps), the degraded line is absent at 0, the capability item names the Window ID lookup state, and app names are cut at 32 graphemes plus U+2026"
    requirement: WIN-02
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MenuCopyTests.swift"
        status: pass
    human_judgment: false
  - id: D2
    description: "Pane runs as an accessory app with a menu-bar item whose menu shows the live tracking header, the Debug capability item and Quit Pane"
    requirement: WIN-02
    verification:
      - kind: other
        ref: "swift build --product PaneApp; unbundled PaneApp still running 3 s after launch"
        status: pass
    human_judgment: true
    rationale: "Menu contents, live counts and glyph legibility in light/dark/tinted menu bars need a real menu-bar session (UI-SPEC backstop)"
  - id: D3
    description: "scripts/build-debug.sh builds Pane Debug.app signed with Developer ID Application (S2K7P43927), hardened runtime, DR identifier com.eightabyte.pane.debug, LSUIElement true"
    requirement: WIN-01
    verification:
      - kind: other
        ref: "scripts/build-debug.sh && codesign -d -r- / --verbose=2 checks (identifier, S2K7P43927, flags=0x10000(runtime))"
        status: pass
    human_judgment: false
  - id: D4
    description: "scripts/build-debug.sh --release builds Pane.app with identifier com.eightabyte.pane and no get-task-allow entitlement"
    verification:
      - kind: other
        ref: "scripts/build-debug.sh --release && codesign -d -r- ... | grep identifier && ! codesign -d --entitlements - ... | grep get-task-allow"
        status: pass
    human_judgment: false
  - id: D5
    description: "scripts/run-debug.sh --no-build --disable-private=AXWindowID launches Pane Debug through LaunchServices and it is still running 3 s later"
    requirement: SAFE-05
    verification:
      - kind: other
        ref: "scripts/run-debug.sh --no-build --disable-private=AXWindowID && sleep 3 && pgrep -f 'Pane Debug.app/Contents/MacOS/Pane Debug'"
        status: pass
    human_judgment: false
  - id: D6
    description: "xcode/Pane.xcodeproj and xcode/.xcode-build are gitignored; only project.yml and Pane.entitlements are tracked under xcode/"
    verification:
      - kind: other
        ref: "git check-ignore -q xcode/Pane.xcodeproj && git check-ignore -q xcode/.xcode-build"
        status: pass
    human_judgment: false
  - id: D7
    description: "The Accessibility grant for Pane Debug survives a rebuild (same designated requirement)"
    requirement: WIN-01
    verification: []
    human_judgment: true
    rationale: "TCC grant persistence needs System Settings and a real relaunch after a rebuild"

duration: 6min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 02: Menu-bar shell and signed app bundle Summary

**Pane is now a menu-bar app: a `rectangle.split.2x1` template status item whose menu reads "Tracking N windows in M apps" from the live inventory, with the Window ID capability under Debug. XcodeGen builds it as a Developer-ID-signed, hardened `Pane Debug.app` (com.eightabyte.pane.debug) or `Pane.app` (com.eightabyte.pane, no get-task-allow), launched through LaunchServices.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-10-24T15:25:54Z
- **Completed:** 2026-10-24T15:32:04Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- `MenuCopy` gives plural-correct status copy with no "(s)", and cuts app names at 32 graphemes. Six Swift Testing cases cover it, emoji included
- `StatusItemController` puts a 16 pt template glyph in the menu bar. The menu is rebuilt on open: the header, the degraded line (only when > 0), Debug ▸ "Window ID lookup: …", and "Quit Pane" (⌘Q)
- `xcode/project.yml` wraps `Sources/PaneApp` plus the `PaneMac` product. It sets LSUIElement, hardened runtime, manual Developer ID signing for team S2K7P43927, and a bundle ID per config
- `build-debug.sh` checks `codesign --verify --strict` and the designated requirement (identifier + team) on every build. `run-debug.sh` launches with `open -n … --args` so TCC attributes the process to Pane

## Task Commits

1. **Task 1: Menu-bar status item with a live, plural-correct tracking header** - `c155a0f` (test, RED), `36fe081` (feat, GREEN MenuCopy), `df75336` (feat, StatusItemController + PaneMacApp)
2. **Task 2: Developer-ID-signed Pane Debug.app and Pane.app via XcodeGen** - `4616bfb` (feat)

## TDD Gate Compliance (Task 1)

- **RED** `c155a0f`: `swift test --filter MenuCopyTests` exited 1. The classifier returned `RED_EVIDENCE_OK` (swift-testing, 6 tests, 6 failing) for the target `headerIsPluralCorrect(windows:apps:expected:)`. The record is at `.planning/phases/02-window-control/tdd/02-02-red.json`. Semantic assessment: the build succeeded, and every test ran and failed on its planned copy assertion, because the committed `MenuCopy` skeleton returns empty strings.
- **GREEN** `36fe081`: all 6 MenuCopyTests pass. The full `swift test` passes (142 + 8 + 2 + 14).
- **REFACTOR:** none needed.
- `StatusItemController` is AppKit glue with no unit test, as the plan intends. It was checked by `swift build --product PaneApp` and by launches, both unbundled and through LaunchServices.

## Files Created/Modified
- `Sources/PaneMac/Shell/MenuCopy.swift` - pure copy functions, `maxAppNameLength = 32`
- `Sources/PaneMac/Shell/StatusItemController.swift` - NSStatusItem, NSMenuDelegate, cached `latest` inventory
- `Sources/PaneMac/PaneMacApp.swift` - creates the controller after `.accessory`, refreshes it after `start()`; `--print-inventory-summary` unchanged
- `Tests/PaneMacTests/MenuCopyTests.swift` - the behaviour cases from the plan
- `xcode/project.yml`, `xcode/Pane.entitlements` - XcodeGen spec; entitlements hold only app-sandbox = false
- `scripts/generate.sh`, `scripts/build-debug.sh`, `scripts/run-debug.sh` - check-no-appkit.sh header convention, `set -euo pipefail`
- `.gitignore` - `xcode/*.xcodeproj/`, `xcode/.xcode-build/`

## Decisions Made
See `key-decisions` in the frontmatter. XcodeGen 2.46.0 was installed from homebrew/core after checking that the formula's homepage is github.com/yonaskolb/XcodeGen (T-02-06). Assumption A4 held: manual Developer ID signing of a Debug build needed no profile, codesign showed no keychain prompt, and `scheme: {}` made `-scheme Pane` resolve.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] XcodeGen emptied the committed entitlements file**
- **Found during:** Task 2 (first `scripts/build-debug.sh`)
- **Issue:** with only `entitlements: path:`, `xcodegen generate` rewrites `Pane.entitlements` as an empty `<dict/>`. The committed file would then always show as modified and lose app-sandbox = false.
- **Fix:** declared `properties: com.apple.security.app-sandbox: false` under `entitlements` in project.yml, as in the RESEARCH shape, so the generated file matches the committed one
- **Files modified:** xcode/project.yml
- **Verification:** after generate, `cat xcode/Pane.entitlements` shows the key. The Release entitlements dump shows only `com.apple.security.app-sandbox = false`
- **Committed in:** 4616bfb

---

**Total deviations:** 1 auto-fixed (1 blocking). **Impact on plan:** none. The committed entitlements content is exactly what the plan specifies.

## Issues Encountered
- xcodebuild logs a "CoreSimulator is out of date" notice and an appintents "metadata extraction skipped" warning. Neither is related to this plan and neither fails the build.
- xcbeautify is not installed, so build-debug.sh streams the raw xcodebuild log to stderr. The script uses xcbeautify only when it is on PATH.

## Human checks for phase UAT (end-of-phase)
- Run `scripts/run-debug.sh`, grant "Pane Debug" in System Settings ▸ Privacy & Security ▸ Accessibility, then quit and relaunch with `scripts/run-debug.sh --no-build`. Open the menu-bar item in light mode, then in dark mode. Expected: the glyph is legible in both, the header reads "Tracking N windows in M apps" with plausible numbers, and Debug shows "Window ID lookup: available". After rebuilding with `scripts/build-debug.sh` and relaunching, the grant still holds with no new prompt (coverage D2, D7).

## User Setup Required
None - no external service configuration required. XcodeGen 2.46.0 is now installed at /opt/homebrew (dev tool only).

## Next Phase Readiness
- Plans 05, 08 and 13 add menu items through `add…Items(to:)` methods in StatusItemController and copy through MenuCopy
- Concern for later plans: `StatusItemController` iterates `AXWindowSystem.events`, which is a single AsyncStream. If another consumer (the engine) also iterates it, each event goes to only one of them. Whichever plan adds the second consumer must fan the stream out, or give the menu its own change signal.
- Pane Debug.app runs with `--disable-private=AXWindowID` (it tracks 0 windows until the Plan 11 fallback)

## Self-Check: PASSED
- All 9 created files exist on disk
- Commits c155a0f, 36fe081, df75336 and 4616bfb are ancestors of HEAD, and evaluation-scope resolves them for 02-02
- All five Task 2 `<automated>` verifies pass (Debug build, DR/team/runtime, Release identifier without get-task-allow, LaunchServices launch alive at 3 s, ignore checks). Every acceptance grep meets its threshold. `swift test` passes. Sparkle appears in neither Package.swift nor project.yml

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
