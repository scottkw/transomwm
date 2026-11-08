---
phase: 02-window-control
plan: 08
subsystem: ui
tags: [appkit, swiftui, nsmenu, nsalert, userdefaults, sigstop, debug-tools, swift-testing]

requires:
  - phase: 02-window-control (02-05)
    provides: StatusItemController, MenuCopy, PaneMacApp.run, PermissionController, SetupWindowController.show()
  - phase: 02-window-control (02-06)
    provides: Displays.localizedNames(), live inventory with display UUIDs
  - phase: 02-window-control (02-07)
    provides: WindowInventory.degradedPIDs for the Not responding badge
provides:
  - "ExclusionStore (UserDefaults key excludedBundleIDs): validated, case-insensitive exact matching, ObservableObject + onChange"
  - "Status menu items 3-5: Show Tracked Windows, Don't Arrange “App” toggle, Never Arrange submenu"
  - "Tracked Windows window: TrackedWindowsModel (pure formatting), TrackedWindowsView (Table + footer + states), TrackedWindowsWindowController"
  - "FreezeTest (freezeTestPID): guarded SIGSTOP/SIGCONT with auto-resume, launch-time and quit-time resume; Debug-only Freeze/Resume items and confirmation alert"
  - "StatusItemController.onInventory: fan-out of each re-read inventory (system.events keeps one reader)"
affects: [02-09 sessionPaused footer prefix, 02-10 tab counts, 02-11 synthetic IDs, 02-12 learned minimums, 02-13 exclusion enforcement and Nudge item]

actuals:
  tokens: 11589
  tasks: 3
  commits: 6
plan_head_before: d9819396f79bc505b812df3e4dc6480a5c2aa722
plan_head_after: 807ece67b4dd04df7581548e6a217173b75fb301

tech-stack:
  added: []
  patterns:
    - "Pure formatter enum (TrackedWindowsModel) + thin SwiftUI view, so every UI-SPEC string is unit-tested"
    - "One reader of AXWindowSystem.events (StatusItemController); other UI gets inventories through onInventory"
    - "Destructive NSAlert: destructive button first (rightmost) with no key equivalent, Cancel on Return, Esc mapped by a local key monitor"

key-files:
  created:
    - Sources/PaneMac/ExclusionStore.swift
    - Sources/PaneMac/Shell/TrackedWindowsModel.swift
    - Sources/PaneMac/Shell/TrackedWindowsView.swift
    - Sources/PaneMac/Shell/TrackedWindowsWindowController.swift
    - Sources/PaneMac/Shell/FreezeTest.swift
    - Tests/PaneMacTests/ExclusionStoreTests.swift
    - Tests/PaneMacTests/TrackedWindowsModelTests.swift
    - Tests/PaneMacTests/FreezeTestTests.swift
  modified:
    - Sources/PaneMac/Shell/StatusItemController.swift
    - Sources/PaneMac/Shell/MenuCopy.swift
    - Sources/PaneMac/PaneMacApp.swift
    - Sources/PaneMac/Permission/SetupWindowController.swift
    - Tests/PaneMacTests/MenuCopyTests.swift

key-decisions:
  - "Tracked Windows gets inventories from StatusItemController.onInventory (fired from latest's didSet), not from a second reader of system.events"
  - "ExclusionStore is an ObservableObject (@Published bundleIDs) so the table re-renders badges; onChange stays free for Plan 13"
  - "Footer segments after apps count rows (windows): never dock, excluded and not responding are all per-row badges"
  - "NSAlert has no hasDestructiveAction on the macOS 27 SDK; the Freeze NSButton carries it, and Esc is mapped to Cancel by a local key monitor because Cancel holds Return"
  - "Quit Pane during a freeze resumes the app at once (willTerminate); a crash is undone by resumeRecordedPID() at the next launch"
  - "Xcode Debug builds already compile package code with DEBUG (Freeze selectors are in Pane Debug.debug.dylib, absent from Release), so project.yml is unchanged"

patterns-established:
  - "KeyClosableWindow (renamed from SetupWindow): Esc/Cmd-W close any Pane window in an accessory app"

requirements-completed: [WIN-08, WIN-02, WIN-03]

coverage:
  - id: D1
    description: "ExclusionStore: empty start, case-insensitive exact match, validation (empty, blank, unbundled:, 256 chars, slash), dropped invalid stored entries, persistence across instances, toggle round-trip, onChange, display-name sort"
    requirement: WIN-08
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/ExclusionStoreTests.swift (9 tests)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Menu and freeze copy: Don't Arrange “App”, fallback, No apps excluded, Freeze/Resume items, not-allowed title, alert message"
    requirement: WIN-08
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/MenuCopyTests.swift#exclusionCopyQuotesTheAppName(), Tests/PaneMacTests/FreezeTestTests.swift#freezeCopyUsesTheAppName()"
        status: pass
    human_judgment: false
  - id: D3
    description: "Tracked Windows formatting: sort order, closed rows dropped, kind vocabulary, rounded frames, placeholders, badges, footer segments and wake prefix, table state"
    requirement: WIN-02
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/TrackedWindowsModelTests.swift (12 tests)"
        status: pass
    human_judgment: false
  - id: D4
    description: "FreezeTest guard: refusal list, pid persisted before SIGSTOP, auto-resume, Resume Now, single freeze, launch-time resume"
    requirement: WIN-03
    verification:
      - kind: unit
        ref: "Tests/PaneMacTests/FreezeTestTests.swift (8 tests, recording signal function only)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Live Tracked Windows window, Don't Arrange / Never Arrange menu and Debug Freeze flow on a real app"
    requirement: WIN-02
    verification:
      - kind: other
        ref: "scripts/build-debug.sh && scripts/build-debug.sh --release (both signed and verified); unbundled PaneApp launch smoke (alive after 4 s)"
        status: pass
    human_judgment: true
    rationale: "Table layout, truncation, horizontal scroll, alert key handling and real SIGSTOP of a user app need a person (plan human-check)"

duration: 10min
completed: 2026-10-24
status: complete
---

# Phase 2 Plan 08: Tracked Windows, Exclusions and Freeze Test Summary

**A live SwiftUI Tracked Windows table (ten UI-SPEC columns, footer, no-permission/loading/empty states) fed from the status item's single event reader, a UserDefaults exclusion list behind "Don't Arrange “App”" and "Never Arrange", and a Debug-only Freeze test that persists the pid before SIGSTOP and resumes it after 10 s, on quit and at every launch.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-10-24T16:44:02Z
- **Completed:** 2026-10-24T16:54:17Z
- **Tasks:** 3
- **Files modified:** 13 source/test files (+3 RED evidence records)

## Accomplishments
- `ExclusionStore` keeps validated bundle IDs (1-255 chars, `[A-Za-z0-9.-]`) under `excludedBundleIDs`. It starts empty, matches case-insensitively and exactly, and drops invalid stored entries with an error log that has no content in it.
- Status menu: "Show Tracked Windows" (item 3), the frontmost-app "Don't Arrange “App”" toggle (item 4) with a disabled fallback for Pane, apps without a bundle ID and non-regular apps, and a sorted "Never Arrange" submenu (item 5) with "No apps excluded" when it is empty.
- Tracked Windows: a 960×480 window (minimum 720×320, autosave `TrackedWindows`). It has the ten columns at their UI-SPEC minimum widths, middle-truncated titles with tooltips, monospaced numbers, "Excluded" and "Not responding" text badges, rows that update without animation, a 28 pt footer with the summary and capability caption, and `ContentUnavailableView` states.
- Freeze test: refuses Pane itself, pid ≤ 1, loginwindow, Finder, Dock and SystemUIServer. Only one app can be frozen at a time. The pid is persisted before SIGSTOP and auto-resumed after 10 s. "Resume “App” Now" replaces the item while an app is frozen. The confirmation alert cancels on both Return and Esc.

## Task Commits

1. **Task 1: Exclusion list and menu** - `3cfc6a9` (test, RED), `3beb91f` (feat, GREEN)
2. **Task 2: Tracked Windows window** - `526063d` (test, RED), `7a74775` (feat, GREEN)
3. **Task 3: Guarded Freeze test** - `55b8c05` (test, RED), `807ece6` (feat, GREEN)

No refactor commits were needed.

## TDD Gate Compliance
- Each task has a `test(02-08)` commit before its `feat(02-08)` commit.
- **RED evidence:** `tdd/02-08-task{1,2,3}-red.json`. The classifier returned `RED_EVIDENCE_OK` for all three, with targets `matchingIsCaseInsensitiveAndExact()`, `rowsSortByAppNameIgnoringCaseAndDiacriticsThenWindowID()` and `freezeRecordsThePIDBeforeStopping()`.
- **Semantic assessment:** every target compiled and failed on `#expect`/`#require` assertions against no-op stubs, never on a build or load fault. The Task 2 RED was rerun after a first attempt failed to compile (MainActor-isolated row type). That attempt was not recorded as RED. Two tests passed against the stubs by design because they assert "empty" or "no signal": `aFreshStoreIsEmpty` and `nothingRecordedSendsNothing`.

## Files Created/Modified
- `Sources/PaneMac/ExclusionStore.swift`: exclusion list, validation, `sortedEntries(displayNames:)`, `onChange`
- `Sources/PaneMac/Shell/TrackedWindowsModel.swift`: `TrackedWindowRow`, `TrackedWindowsState`, `rows`/`footer`/`state`/`kindText`/`frameText`
- `Sources/PaneMac/Shell/TrackedWindowsView.swift`: `TrackedWindowsFeed` and the SwiftUI view
- `Sources/PaneMac/Shell/TrackedWindowsWindowController.swift`: NSWindow host
- `Sources/PaneMac/Shell/FreezeTest.swift`: guarded SIGSTOP/SIGCONT
- `Sources/PaneMac/Shell/StatusItemController.swift`: items 3-5, the Debug Freeze/Resume item and alert, `onInventory`
- `Sources/PaneMac/Shell/MenuCopy.swift`: exclusion and freeze copy
- `Sources/PaneMac/PaneMacApp.swift`: owns the store, the window controller and FreezeTest; `resumeRecordedPID()` runs first; resume on willTerminate
- `Sources/PaneMac/Permission/SetupWindowController.swift`: `SetupWindow` renamed to the shared internal `KeyClosableWindow`

## Decisions Made
See `key-decisions` in the frontmatter. The footer counts are worth noting. The plan's example "1 excluded · 1 not responding" doesn't say whether it counts windows or apps. Pane counts rows, so each number matches the badges you can see in the table. The menu's "{n} apps not responding" line still counts apps.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `NSAlert.hasDestructiveAction` does not exist**
- **Found during:** Task 3
- **Issue:** The plan says to set `alert.hasDestructiveAction = true` "where the API exists". The macOS 27 SDK has no such member, and the build failed.
- **Fix:** Only the Freeze `NSButton` carries `hasDestructiveAction`. Cancel has Return. A local key monitor maps Esc (key code 53) to Cancel while the alert is up, because NSAlert's automatic Esc binding is lost once Cancel's key equivalent becomes Return.
- **Files modified:** Sources/PaneMac/Shell/StatusItemController.swift
- **Committed in:** 807ece6

**2. [Rule 2 - Missing critical] Resume the frozen app when Pane quits**
- **Found during:** Task 3
- **Issue:** The prohibition says a freeze must never leave an app stopped after Pane quits. The launch-time resume covers crashes only at the next launch.
- **Fix:** A `willTerminate` observer calls `resumeNow()`. `freeze(pid:)` also re-checks the pid guard (pid ≤ 1, own pid), and the alert re-checks `isAllowed` and `isTerminated` after confirmation.
- **Files modified:** Sources/PaneMac/PaneMacApp.swift, Sources/PaneMac/Shell/FreezeTest.swift, Sources/PaneMac/Shell/StatusItemController.swift
- **Committed in:** 807ece6

**3. [Rule 3 - Blocking] Single-consumer event stream**
- **Found during:** Task 2
- **Issue:** The plan has the view model "observe the system's events". `AXWindowSystem.events` is single-consumer, and StatusItemController already reads it (02-05 decision).
- **Fix:** StatusItemController forwards each re-read inventory through `onInventory`, which fires from `latest`'s `didSet`, into a `TrackedWindowsFeed`.
- **Files modified:** Sources/PaneMac/Shell/StatusItemController.swift, Sources/PaneMac/Shell/TrackedWindowsView.swift, Sources/PaneMac/PaneMacApp.swift
- **Committed in:** 7a74775

**4. [Rule 3 - Blocking] ⌘W in an accessory app**
- **Found during:** Task 2
- **Issue:** An accessory app has no main menu, so nothing supplies ⌘W.
- **Fix:** Reused the setup window's subclass, renamed from `SetupWindow` to the internal `KeyClosableWindow`. Its Esc-closes behaviour now also applies to Tracked Windows.
- **Files modified:** Sources/PaneMac/Permission/SetupWindowController.swift, Sources/PaneMac/Shell/TrackedWindowsWindowController.swift
- **Committed in:** 7a74775

---

**Total deviations:** 4 auto-fixed (1 missing critical, 3 blocking). **Impact on plan:** all four were needed for the plan's own contract. No scope creep.

## Issues Encountered
- `xcode/project.yml` was not changed. `-showBuildSettings` lists `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`. The `confirmFreeze` selector appears in `Pane Debug.debug.dylib` and not in the Release binary.

## Human checks for phase UAT (end-of-phase)
1. Launch Pane Debug and open Tracked Windows. Expected: every window appears with plausible kinds, frames and displays. A long title is middle-truncated with a tooltip. The table scrolls horizontally at 720 pt wide, and the header stays pinned.
2. Toggle "Don't Arrange “TextEdit”". Expected: the item shows a checkmark, TextEdit rows show "Excluded", and Never Arrange lists TextEdit. Clicking that entry removes it. With no entries, the submenu shows "No apps excluded".
3. Choose Debug ▸ Freeze “TextEdit” for 10 Seconds…. Expected: pressing Return cancels, and Esc also cancels. Click Freeze. TextEdit rows show "Not responding" within about 5 s, and the menu shows "Resume “TextEdit” Now". TextEdit recovers by itself after 10 s.
4. Open the menu with Finder frontmost, then with Pane frontmost. Expected: "Freeze Frontmost App (not allowed)" is shown disabled, and Don't Arrange reads "Don't Arrange Frontmost App" (disabled) for Pane.
5. Freeze TextEdit, then Quit Pane. Expected: TextEdit resumes at once.
6. Release build (`Pane.app`). Expected: no Freeze item in the Debug submenu.

## User Setup Required
None. No external service configuration required.

## Next Phase Readiness
- Plan 13 can subscribe to `ExclusionStore.onChange` and set `WindowInfo.isExcluded`. It also adds the Nudge item above Freeze in the Debug submenu.
- Plans 09-12 fill `sessionPaused`, `tabCount`, synthetic IDs and `learnedMinimum`, and the table already renders all four.
- No blockers.

## Self-Check: PASSED
- All 8 created files exist. Commits 3cfc6a9, 3beb91f, 526063d, 7a74775, 55b8c05 and 807ece6 are on HEAD.
- `swift test` passes all 281 tests (142 + 45 + 11 + 83). `swift test --filter "ExclusionStoreTests|TrackedWindowsModelTests|FreezeTestTests|MenuCopyTests"` passes. `scripts/build-debug.sh` and `scripts/build-debug.sh --release` exit 0 with signature checks passing. `scripts/check-no-appkit.sh` passes.
- No logger call in the new or changed files mentions a window title.

---
*Phase: 02-window-control*
*Completed: 2026-10-24*
