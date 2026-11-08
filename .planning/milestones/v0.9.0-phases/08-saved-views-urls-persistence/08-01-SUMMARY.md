---
phase: 08-saved-views-urls-persistence
plan: 01
subsystem: engine
tags: [saved-views, camera, hotkeys, keyboardshortcuts, toasts, swift-testing]

requires:
  - phase: 04-zoom
    provides: camera dispatch (Navigator.camera, cameraStep refusals), zoomTo, currentView, Back/Forward history
  - phase: 03-arranging
    provides: NoticeQueue, NoticeCopy, toast display switch, hotkey table
provides:
  - ViewSlot (1-9, decoding rejects anything else) and CameraCommand.view / .saveView
  - SavedView / SavedViews on CameraState.savedViews (session-only until 08-03)
  - Arranger.saveView, viewDestination, goView (Arranger+Views.swift)
  - Notice N13-N19 with isBrief; brief toast class (1.5 s, dropped behind a crash notice but still announced)
  - 18 hotkey names view1-9 / saveView1-9 with the ViewChords OS-version rule; Saved Views Shortcuts section; ViewCopy
affects: [08-03 persistence and cross-Space going, 08-05 URLs and CLI]

actuals:
  tokens: 15000
  tasks: 3
  commits: 4

plan_head_before: 7b96181c5d6f53da98393603d31467e91c4eba2a
plan_head_after: 76c4ff78ca1eb05a0f1b052a90ebdba140e5145e

tech-stack:
  added: []
  patterns:
    - "View commands pass cameraStep's shared refusals (paused, full screen) and are then routed to goView/saveView in Navigator.camera"
    - "A brief notice's .unchanged from NoticeQueue.post means dropped; ArrangeController.post announces it anyway"

key-files:
  created:
    - Sources/TransomEngine/SavedViews.swift
    - Sources/TransomEngine/Arranger+Views.swift
    - Sources/TransomMac/Shell/ViewCopy.swift
    - Tests/TransomEngineTests/ArrangerViewsTests.swift
    - Tests/TransomMacTests/ViewCopyTests.swift
  modified:
    - Sources/TransomEngine/Command.swift
    - Sources/TransomEngine/Arranger+Camera.swift
    - Sources/TransomEngine/Navigator.swift
    - Sources/TransomEngine/Notice.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/Input/Hotkeys.swift
    - Sources/TransomMac/Overlay/NoticeQueue.swift
    - Sources/TransomMac/Shell/MenuCopy.swift
    - Sources/TransomMac/Shell/NoticeCopy.swift
    - Sources/TransomMac/Zoom/ShortcutsWindowController.swift

key-decisions:
  - "View commands reuse cameraStep's refusal path (a placeholder success step) so paused/full-screen refusals keep the Phase 4 announcements"
  - "A desk tie between two non-saved desks goes to the smaller DeskKey, so viewDestination is deterministic"
  - "A dropped brief notice is announced from ArrangeController.post (brief + .unchanged means dropped); NoticeQueue.Change is unchanged"
  - "Going to a view whose desk is not shown on the display only logs (08-03 adds the Space/display switch)"

patterns-established:
  - "Saved view = desk + window identities; resolved via Navigator.lowestCommonAncestor of leafNode(of:) on the desk holding most survivors"

requirements-completed: [VIEW-01]

coverage:
  - id: D1
    description: "⇧⌥{n} saves the pointer display's view (pending target while a move runs) and ⌥{n} zooms back to the smallest node holding the saved windows"
    requirement: VIEW-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerViewsTests.swift#savingThenGoingBackZoomsToTheSavedWindows"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every Surface 1 save/go edge case on one display (empty slot, all gone, display gone, nothing to save, replace, already there, refusals, focus, history)"
    requirement: VIEW-01
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/ArrangerViewsTests.swift (16 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Brief toast class, N13-N19 copy and glyphs, ViewCopy, ViewChords 15.0/15.1 rule, 18 hotkey names and the Saved Views Shortcuts section"
    requirement: VIEW-01
    verification:
      - kind: unit
        ref: "NoticeQueueTests, NoticeCopyTests, ViewCopyTests, HotkeyTableTests, ShortcutsModelTests, ZoomCopyTests, MenuCopyTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "⌥3 / ⇧⌥3 really fire on the host keyboard (incl. a non-US layout) and the toasts show on the right display"
    verification: []
    human_judgment: true
    rationale: "Global hotkeys and toast panels are live UI; this plan has no VM test (08-03 adds the VM views test)"

duration: 11min
completed: 2026-11-03
status: complete
---

# Phase 8 Plan 01: Saved Views Tracer Summary

**⇧⌥{n} stores a view as a desk plus window identities and ⌥{n} zooms the camera back to the lowest common ancestor of the windows still there, with brief 1.5 s "Saved view {n}" / "View {n}" toasts and 18 rebindable chords that follow the macOS 15.0/15.1 rule.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-11-03T20:35:23Z
- **Completed:** 2026-11-03T20:46:21Z
- **Tasks:** 3
- **Files modified:** 21 (5 created)

## Accomplishments
- Engine: `ViewSlot`, `CameraCommand.view/.saveView`, `SavedViews` on `CameraState`, and `Arranger+Views.swift` (`saveView`, `viewDestination`, `goView`) routed through the existing camera dispatch, so refusals, history and zoom-off gating are shared.
- Every UI-SPEC Surface 1 outcome on one display pinned by an engine test: N16 on an empty slot, N17 + home when every window closed (slot kept), N18 when the saved display is gone, N19 when the view holds no windows, replace without confirmation, already-there is no refusal, focus moves into the view, Back history pushed and no undo step.
- Shell: N13-N19 copy and glyphs, the brief toast class (1.5 s, replaces non-crash toasts, dropped behind a crash notice but still announced), 18 hotkey names with `ViewChords`, the "Saved Views" Shortcuts section and footer.

## Task Commits

1. **Task 1: Tracer, save and go on one desk** - `e6e470b` (feat)
2. **Task 2: Save and go rules** - `15624db` (feat)
3. **Task 3: Brief toast class, copy and chord rule tests** - `3759049` (feat)
4. **Threat T-08-03 test: slot decoding** - `76c4ff7` (test)

## Files Created/Modified
- `Sources/TransomEngine/SavedViews.swift` - SavedView and the nine-slot table (no API empties a slot, D-16)
- `Sources/TransomEngine/Arranger+Views.swift` - save, destination resolution, go
- `Sources/TransomEngine/Command.swift` - ViewSlot, the two camera cases
- `Sources/TransomEngine/Navigator.swift` - routes view commands after cameraStep's shared refusals
- `Sources/TransomEngine/Notice.swift` - N13-N19 and `isBrief`
- `Sources/TransomMac/Input/Hotkeys.swift` - 18 names, `ViewChords`, entries
- `Sources/TransomMac/Overlay/NoticeQueue.swift` - `isBrief` requirement, `briefDuration`, drop behind crash
- `Sources/TransomMac/ArrangeController.swift` - toast display for view notices; announces a dropped brief notice
- `Sources/TransomMac/Shell/ViewCopy.swift`, `NoticeCopy.swift`, `MenuCopy.swift`, `Zoom/ShortcutsWindowController.swift` - copy and the Shortcuts section

## Decisions Made
- View commands reuse cameraStep's refusal path, so paused and full-screen refusals keep the Phase 4 beep and announcement. Not-ready is refused by the shell's `dispatchCamera` before the engine sees it (unchanged).
- A tie between two desks that are both not the saved desk goes to the smaller DeskKey, so the result is deterministic.
- A dropped brief notice is announced from `ArrangeController.post`. A brief notice can only get `.unchanged` back when it is dropped, so `NoticeQueue.Change` stays as it was.

## Exhaustive-switch arms and access changes (requested by the plan)
- Arms added in: `NoticeCopy.text` / `glyph`, `Notice.merged(with:)` (NoticeQueue.swift), `MenuCopy.cameraTitle`, `ArrangeController.displayUUID(of:)`, `Navigator.cameraStep`, `Notice.isCrashNotice`.
- No arms were needed in `ZoomInput.swift` or `CommandMenu.swift`. `ZoomCopy.shortcutTitle` needed no change because its default arm already delegates to `MenuCopy.commandTitle`.
- No Arranger member dropped `private`. The tests write `camera` and `world` through `@testable`, and `world.addDesk` / `reflow` are already public.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing test] T-08-03 slot decoding test**
- **Found during:** final threat-model check
- **Issue:** The threat register says a unit test decodes 0 and 10 as errors. No task listed that test.
- **Fix:** Added `aSlotOutsideOneToNineFailsToDecode` to ArrangerViewsTests.
- **Commit:** 76c4ff7

### Plan adjustments (no behaviour change)
- **Tracer fixture:** In Phase 3, docking a, b, c gives `a | b | (Desktop tile / c)`, so no node holds only A and B. The tracer saves the `(Desktop tile / c)` view with a floating d instead (windows c and d). This also covers the showsDesktop rule.
- **"A later split puts C beside A":** Tested as Swap with Previous moving c into a's old tile. The target is re-resolved from identities to c's new leaf.
- **Toast.swift unchanged:** The announcement for a dropped brief notice is posted in `ArrangeController.post` (one line).

## Issues Encountered
None.

## Known Stubs
None. `goView` deliberately only logs when the destination desk isn't shown on the display; 08-03 Task 3 replaces that branch.

## User Setup Required
None.

## Next Phase Readiness
- 08-03 can persist `camera.savedViews.sorted`, make `viewDestination` public as `viewDestination(slot:)`, and replace the "not shown on this display" branch.
- Nothing live ran on the host. Full `swift test` passed (live suites are gated by TRANSOM_LIVE, which was unset), and `scripts/check-no-appkit.sh` passed.

## Self-Check: PASSED
