# Phase 7: Tab Groups - Context

**Gathered:** 2026-11-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Group windows from any apps into one tabbed tile (TABS-01..06): dropping a window on the middle of another and pausing groups them under one tab strip that follows the group as it moves and resizes; clicking a tab switches the visible window while the others stay hidden (parked, never minimised); the group's close, minimise and dock/float buttons act on the whole group; a tab dragged out of the strip becomes its own window again; right-clicking a tab offers close and move-out. Works for docked groups and for groups floating on the Desktop tile.

Builds on `Node.tabs(windows:selected:)` (Phase 1), native-tab detection (`TabGroupTracker`, Phase 2) and window parking (Phase 4). Roadmap scope note: the tab strip panel tracks the group leader via CG bounds polling; inactive tabs are hidden by parking, never minimised.

Out of scope: a Settings window (Phase 9), saved views and the `transom` CLI (Phase 8), reordering tabs by drag within the strip unless it falls out of the strip implementation for free.

</domain>

<decisions>
## Implementation Decisions

### Making a group
- **D-01:** A centre drop (`DropZone.center`, the middle 50% of a tile) groups only after the pointer has rested there about 0.4 s. Then the drop preview changes to a tab-group outline with a strip. Releasing in the centre before the dwell is refused as today: a drag that misses has no beep, and the window returns (clarified 2026-11-01: the drag-miss path has never beeped; only the keyboard Dock path beeps).
- **D-02:** Works on docked tiles and on floating windows on the Desktop tile. A group made on a floating window floats at that window's frame. Dropping on an existing group's centre adds a tab to it.
- **D-03:** The dropped window becomes the selected tab.

### Tab strip
- **D-04:** A strip about 28 pt tall sits at the top of the group's frame, inside the tile: the member windows get the frame minus the strip, so nothing overlaps (Core Value). Drawn in a non-activating panel that follows the group (CG bounds polling of the selected window, per the scope note).
- **D-05:** Each tab shows app icon + window title; the selected tab is highlighted. Styling follows the existing 04-UI-SPEC / overlay tokens.
- **D-06:** The strip carries the group's own close, minimise and dock/float buttons; each acts on every window of the group. Close sends a normal AX close to each window, so apps still show their unsaved-changes prompts. Minimise minimises the group as one (restoring brings the group back with the same selected tab).
  - *Clarification 2026-11-02 (host UAT item 5, user decision):* Close Group first asks "Close all {n} windows in this tab group?" (Close Group / Cancel, with "Do not show this again", kept as `tabs.confirmCloseGroup`). A member still open 1 s after its close press is checked for a sheet (an app's save prompt, read-only AX): while the prompt is up Close Group waits with no time limit. Save or Don't Save closes the window and the rest of the group closes; Cancel (the window stays open) stops Close Group and nothing else closes. A member still open with no prompt stops it as before. A group changed meanwhile (a member moved out, the group floated or docked) also stops it. Close Tab asks nothing.

### Hidden tabs
- **D-07:** Non-selected members are parked off screen at the group's content size using the Phase 4 parking mechanism, never minimised, and restored on quit / crash recovery / Restore All Windows like other parked windows.
- **D-08:** Clicking a tab unparks it into the group frame and parks the previous one. If a hidden member is activated another way (⌘-Tab, Dock click, app activation, AX focus), the group switches to that tab.
- **D-09:** A native macOS tab group (e.g. Safari tabs, detected by `TabGroupTracker`) joins a Transom group as a single member.

### Leaving a group
- **D-10:** Dragging a tab out of the strip turns into a normal window drag: drop on an edge to dock, anywhere else to float (existing drop zones and preview).
- **D-11:** Right-clicking a tab offers **Close Tab** and **Move Out of Group**; Move Out floats the window beside the group.
- **D-12:** A group reduced to one window dissolves back into a plain tile/floating window. Closing the selected tab selects a neighbour.
- **D-13:** Groups persist in layout.json like tiles (Node.tabs already serialises) and come back on relaunch.

### Claude's Discretion
- Exact dwell time tuning, strip height/padding, tab truncation and overflow when many tabs, keyboard/hotkey for next/previous tab if cheap, how the overview and zoom stage draw a group (likely the selected window plus a tab indicator), VoiceOver labels for tabs, undo granularity for group/ungroup.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/ROADMAP.md` — Phase 7 goal, success criteria, scope notes
- `.planning/REQUIREMENTS.md` — TABS-01..06
- `.planning/PROJECT.md` — Core Value (tiling must work even if tabs fail), constraints
- `.planning/phases/04-zoom-camera/04-UI-SPEC.md` — overlay tokens and parking behaviour the strip and hidden tabs reuse
- `.planning/phases/06-overview-spaces-displays/06-UI-SPEC.md` — current overview/stage drawing a group must fit into
- `.planning/debug/resolved/overview-stuck-after-voiceover.md` — panels must use `NSWindow.leftOnAnotherSpace(_:)` (Displays.swift) before reuse (macOS 27 lock stranding)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/TransomModel/LayoutTree.swift` `Node.tabs(windows:selected:)`; `DropZones.swift` `.center` zone and `LayoutTree.applyDrop` → `group(window, into:)` (TreeEdits.swift); `World.swift`, `Resolve.swift` already handle `.tabs`.
- `Sources/TransomEngine/Arranger.swift` ~L1110 and ~L1432: centre drops refused today ("tab groups from a centre drop are Phase 7"); `Planner.swift` ~L106 centre-target handling.
- `Sources/TransomEngine/TabGroupTracker.swift`: native tab groups per app.
- `Sources/TransomEngine/ViewPlanner.swift` and the Phase 4 park/unpark path (pre-park frames saved in layout.json, restored on quit/crash).
- `Sources/TransomMac/Overlay/PreviewPanel.swift` (drop preview), `GapHandlePanels.swift`, `Toast.swift`: overlay panel patterns; `DragSession.swift` for drag state.

### Established Patterns
- Engine is pure (no AppKit), driven by events → effects; shell executes AX moves.
- Overlay panels are non-activating, `.canJoinAllSpaces`, and re-created when left on another Space.
- Every command reachable by hotkey/menu/URL beeps on refusal (UI-SPEC rule).
- Live tests run only in the Tart VM with fixture windows.

### Integration Points
- Drag pipeline (InputTap → DragSession → Arranger drop) for the centre dwell and tab drag-out.
- Close/minimise/fullscreen lifecycle (`LifecycleSync`, `CloseRule`) for group-wide actions and member closes.
- Focus observation (AX focused window / app activation) for D-08.

</code_context>

<specifics>
## Specific Ideas

- User has a MacBook Air (built-in trackpad, one display); multi-display tab checks go to deferred hardware items like Phase 6.
- Keep testing minimal: unit tests for the engine, a few VM live tests with fixture windows, short host checklist.

</specifics>

<deferred>
## Deferred Ideas

- Reordering tabs by dragging within the strip (if not free).
- Tab-group-specific Settings (Phase 9).

</deferred>
