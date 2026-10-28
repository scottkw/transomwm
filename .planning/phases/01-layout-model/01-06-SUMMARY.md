---
phase: 01-layout-model
plan: 06
subsystem: infra
tags: [swift, spm, swift-testing, github-actions, bash]

requires:
  - phase: 01-layout-model (plan 01)
    provides: Package.swift skeleton, Rect, WindowRef, WindowState
provides:
  - PaneEngine library product and target depending on PaneModel
  - Draft async WindowSystem protocol with DisplayInfo, WindowInfo, WindowInventory, WindowEvent, WindowCommand
  - scripts/check-no-appkit.sh (exit 0 clean, 1 violation, 2 missing/empty dir)
  - NoAppKitTests suite that runs the check in every `swift test`
  - .github/workflows/ci.yml on macos-26 (check, build, test)
affects: [02-window-system, engine, ci]

actuals:
  tokens: 2014
  tasks: 2
  commits: 2
plan_head_before: 216511a3e16604d83f2c8f025789fa747e40cf42
plan_head_after: b7a876d6142bd5a376d8b2d1d29db5eb20242aaa

tech-stack:
  added: [GitHub Actions (actions/checkout@v5)]
  patterns:
    - "Guardrail scripts live in scripts/ and are run by a Swift Testing suite via Foundation Process, so local `swift test` enforces what CI enforces"

key-files:
  created:
    - Sources/PaneEngine/WindowSystem.swift
    - scripts/check-no-appkit.sh
    - Tests/PaneModelTests/NoAppKitTests.swift
    - .github/workflows/ci.yml
  modified:
    - Package.swift

key-decisions:
  - "PaneEngine value types get explicit public initializers so Phase 2 (another module) can construct them"
  - "WindowEvent and WindowCommand are also Equatable, Sendable, matching the value structs, so scenario tests can compare event/command logs"
  - "NoAppKitTests runs the script with /bin/bash (macOS bash 3.2); the script was checked to work under 3.2 with set -u and empty arrays"

patterns-established:
  - "No-AppKit guardrail: a UI-framework import in Sources/PaneModel or Sources/PaneEngine fails swift test and CI"

requirements-completed: [MODEL-07, MODEL-08]

coverage:
  - id: D1
    description: "PaneEngine target compiles with the draft WindowSystem protocol and value types, importing only PaneModel"
    requirement: MODEL-07
    verification:
      - kind: other
        ref: "swift build && swift build --target PaneEngine"
        status: pass
      - kind: other
        ref: "grep -rhE '^import ' Sources/PaneEngine | sort -u  -> import PaneModel"
        status: pass
    human_judgment: false
  - id: D2
    description: "WindowInfo/WindowEvent carry lifecycle states (WindowState) and DisplayInfo/spaceChanged carry display UUID + Space ID for desk keys"
    requirement: MODEL-08
    verification:
      - kind: other
        ref: "swift build --target PaneEngine"
        status: pass
    human_judgment: true
    rationale: "Draft protocol only; whether its shape fits Phase 2's AXWindowSystem is a design judgment no test asserts yet"
  - id: D3
    description: "scripts/check-no-appkit.sh exits 0 on real sources, 1 on UI-framework imports (plain, attributed, scoped), 2 on a missing or empty directory"
    verification:
      - kind: unit
        ref: "Tests/PaneModelTests/NoAppKitTests.swift#NoAppKitTests"
        status: pass
      - kind: other
        ref: "scripts/check-no-appkit.sh Sources/DoesNotExist -> 2"
        status: pass
    human_judgment: false
  - id: D4
    description: "swift test fails when a real AppKit import lands in Sources/PaneEngine"
    verification:
      - kind: other
        ref: "temporary Sources/PaneEngine/Probe.swift with `import AppKit` -> realSourcesAreClean failed; probe removed"
        status: pass
    human_judgment: false
  - id: D5
    description: "CI workflow on macos-26 with contents: read runs the check, swift build and swift test"
    verification:
      - kind: other
        ref: "ruby YAML parse check from 01-06-PLAN Task 2 -> ci.yml OK"
        status: pass
    human_judgment: true
    rationale: "No git remote yet, so the workflow has never run on a real GitHub runner"

duration: 2min
completed: 2026-10-24
status: complete
---

# Phase 1 Plan 06: PaneEngine and No-AppKit Guardrail Summary

**PaneEngine target with the draft async WindowSystem protocol, plus a no-AppKit import check enforced by every `swift test` and by a macos-26 GitHub Actions workflow**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-10-24T05:53:50Z
- **Completed:** 2026-10-24T05:55:44Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- `PaneEngine` library (depends on `PaneModel`) holding only the draft `WindowSystem` protocol and its `Equatable, Sendable` value types: `DisplayInfo`, `WindowInfo`, `WindowInventory`, `WindowEvent`, `WindowCommand`
- `scripts/check-no-appkit.sh` catches plain, `@preconcurrency`/`@_exported` and scoped (`import struct Cocoa.NSRect`) imports, ignores comments and `AppKitty`, and refuses to pass vacuously on a missing/empty directory
- `NoAppKitTests` (9 test cases) runs the script on the real sources and on fail-first fixtures; the full suite is 101 tests in 11 suites, all passing
- `.github/workflows/ci.yml`: `macos-26`, `permissions: contents: read`, steps checkout, `swift --version`, the check, `swift build`, `swift test`

## Task Commits

1. **Task 1: PaneEngine target with the draft WindowSystem protocol** - `d2034d0` (feat)
2. **Task 2: No-AppKit check in `swift test`, and the CI workflow** - `b7a876d` (feat)

## Files Created/Modified
- `Package.swift` - added PaneEngine product and target; everything else unchanged
- `Sources/PaneEngine/WindowSystem.swift` - draft protocol and value types, `import PaneModel` only
- `scripts/check-no-appkit.sh` - executable no-AppKit import check
- `Tests/PaneModelTests/NoAppKitTests.swift` - runs the script from the repo root resolved via `#filePath`
- `.github/workflows/ci.yml` - CI job

## Decisions Made
- Added public memberwise-style initializers to the value structs; without them Phase 2 code in another module could not construct them.
- Made `WindowEvent` and `WindowCommand` `Equatable, Sendable` too (the plan named the conformance for "all" value types).
- Doc comment states D-09's coordinate space (top-left origin), fire-and-forget/coalescing commands, and that Phase 2 provides `AXWindowSystem` and `FakeWindowSystem`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. Extra check beyond the plan: a temporary `Sources/PaneEngine/Probe.swift` containing `import AppKit` made `realSourcesAreClean` fail under `swift test`; the probe was deleted before committing.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 2 can implement `AXWindowSystem` / `FakeWindowSystem` against the draft protocol; the shape is expected to change once real AX behaviour is wired in.
- The CI workflow has not run on GitHub (no remote). The first push should confirm the `macos-26` runner's Xcode 26.6 builds tools-version 6.2.
- MODEL-08 is also declared by a sibling plan still in progress (01-05), so it stays unchecked in REQUIREMENTS.md until that plan finishes.

---
*Phase: 01-layout-model*
*Completed: 2026-10-24*

## Self-Check: PASSED

All 4 created files exist; commits d2034d0 and b7a876d are ancestors of HEAD.
