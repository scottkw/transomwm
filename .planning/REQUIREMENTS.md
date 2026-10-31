# Requirements: Transom

**Defined:** 2026-10-23
**Core Value:** Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize.

## v1 Requirements

### Layout Model

- [x] **MODEL-01**: Layout is a nested tree of splits (horizontal/vertical) whose children have fractional sizes that always sum to 1
- [x] **MODEL-02**: A window can be inserted beside any tile on any of its four edges, creating or extending a split
- [x] **MODEL-03**: Removing a window gives its space back and collapses single-child splits automatically
- [x] **MODEL-04**: Tile rects are computed for a given area with gaps, respecting each window's minimum size without overlap
- [x] **MODEL-05**: Each desk has a floating Desktop layer that holds non-docked windows
- [x] **MODEL-06**: A tile can hold a tab group of several windows with one selected
- [x] **MODEL-07**: Desks are keyed by display UUID plus optional Space ID
- [x] **MODEL-08**: Windows have lifecycle states (present, absent, fullscreen, closed) so an absent window keeps its reserved slot
- [x] **MODEL-09**: Layout state serialises to versioned JSON and round-trips exactly
- [x] **MODEL-10**: Every layout change can be undone back to the previous layout

### Window Control

- [x] **WIN-01**: User is guided through granting Accessibility permission, and a stale grant is detected and explained
- [x] **WIN-02**: Transom tracks every standard window of every running app, including windows opened or closed later
- [x] **WIN-03**: A hung or slow app never freezes Transom or delays arranging other apps' windows
- [x] **WIN-04**: Transom moves and resizes windows and learns an app's real minimum size when it refuses a size
- [x] **WIN-05**: Dialogs, sheets, popovers and picture-in-picture windows are never docked (classifier tested against recorded AX dumps)
- [x] **WIN-06**: Native tabs (Finder, Terminal, Safari, etc.) count as one window
- [x] **WIN-07**: A window that goes native fullscreen keeps its tile reserved and returns to it
- [x] **WIN-08**: User can list apps whose windows Transom never arranges
- [x] **WIN-09**: A window is only treated as closed when two sources confirm it; lock screen, sleep and timeouts never close windows

### Tiling

- [x] **TILE-01**: Dragging a window by its title bar to a screen edge or another window's edge shows a drop preview and docks it there on release
- [x] **TILE-02**: Holding a bypass modifier while dragging moves the window freely without docking
- [x] **TILE-03**: When a docked window closes, its neighbours reflow to fill the space
- [x] **TILE-04**: User can set the gap between windows
- [x] **TILE-05**: Dragging the gap between two windows resizes both
- [x] **TILE-06**: The green button toggles a window between docked and floating on the Desktop
- [x] **TILE-07**: New windows open floating on the Desktop tile, never auto-split into the layout
- [x] **TILE-08**: User can pause and resume arranging from the menu bar without quitting
- [x] **TILE-09**: Core commands (dock, float, focus neighbour, undo) are available as hotkeys and menu items through one command dispatcher
- [x] **TILE-10**: Tiling works fully with zoom and Screen Recording turned off
- [x] **TILE-11**: User can swap two docked windows' tiles, by hotkey or by dragging with a modifier
- [x] **TILE-12**: User can balance a split's sizes, rotate a split between horizontal and vertical, and flip its order
- [x] **TILE-13**: From the keyboard, user can move the focused window into a neighbouring tile and grow or shrink its tile
- [x] **TILE-14**: Floating windows on the Desktop tile can be snapped by hotkey to halves, thirds, quarters, maximised and centred
- [x] **TILE-15**: User can hide and show the Desktop tile by hotkey, menu and URL
- [x] **TILE-16**: "Arrange all windows" docks every eligible window, and "Float all windows" returns every window to the Desktop as a normal Mac layout
- [x] **TILE-17**: User can split the current tile with a new Finder window by hotkey and URL
- [x] **TILE-18**: The menu offers "Don't Arrange" for the frontmost app, adding it to the exclusion list in one click
- [x] **TILE-19**: ⌥-clicking the green button performs the normal macOS zoom instead of toggling docked/floating
- [x] **TILE-20**: A minimised docked window lets its neighbours take its space and returns to the same tile when restored

### Safety & Recovery

- [x] **SAFE-01**: On quit, every window Transom moved returns to a sensible on-screen frame
- [x] **SAFE-02**: After a crash or force-quit, the next launch restores stranded windows on-screen
- [x] **SAFE-03**: "Restore all windows" brings every window back on-screen from the menu and by URL
- [x] **SAFE-04**: Transom detects macOS edge tiling, Stage Manager and click-wallpaper-to-reveal, explains the conflict and offers to turn them off, restoring originals on request
- [x] **SAFE-05**: A missing or broken private API disables only its own feature; Transom still launches
- [x] **SAFE-06**: Quitting and relaunching Transom while apps keep running restores each display's layout with the same windows in their tiles

### Zoom

- [x] **ZOOM-01**: User can zoom out to see every window on the display at once
- [x] **ZOOM-02**: User can step in or out one level of the layout tree
- [x] **ZOOM-03**: User can ⌘⇧-drag a rectangle to zoom to the windows it frames
- [x] **ZOOM-04**: User can go back and forward through previous views
- [x] **ZOOM-05**: Zoomed views show live window snapshots, or app colour and icon when Screen Recording isn't granted
- [x] **ZOOM-06**: Clicking a window in a zoomed view zooms in to it and focuses it
- [x] **ZOOM-07**: After a zoom settles, real windows are arranged at their new sizes within 500 ms for 15 windows, without visible flashing of stale layouts (the 500 ms is the write path only: from the first AX write to the last read-back; the capture budget and the 250 ms animation are separate. 04-01 verdict, 2026-10-28)
- [x] **ZOOM-08**: Zoom hotkeys are rebindable
- [x] **ZOOM-09**: User can move the view to the neighbouring area left, right, up or down by hotkey and URL
- [x] **ZOOM-10**: User can frame the focused window on its own and toggle back, by hotkey, URL or double-clicking its title bar
- [x] **ZOOM-11**: User can frame the Desktop on its own and toggle back, by hotkey, URL or double-clicking the Desktop
- [x] **ZOOM-12**: Esc cancels a ⌘⇧-drag rectangle zoom in progress
- [x] **ZOOM-13**: A tile too small for its window's minimum size shows as a collapsed block in the app's colour with its icon, and double-clicking it zooms in to it

### Gestures

- [x] **GEST-01**: ⌥-pinch on the trackpad zooms in and out anywhere
- [x] **GEST-02**: ⌥-two-finger pan moves the view
- [x] **GEST-03**: Pinch and pan on bare desktop work without ⌥
- [x] **GEST-04**: Gestures keep working after sleep/wake and trackpad reconnect, and never leak into the app under the pointer

### Overview, Spaces & Displays

- [x] **OVER-01**: Overview shows every window on every display, with Spaces along the top; clicking a window goes to it
- [ ] **OVER-02**: User can opt in to having Mission Control's swipe and shortcut open Transom's overview instead
- [ ] **OVER-03**: If Transom crashes while replacing Mission Control, the system shortcuts are restored on next launch
- [ ] **OVER-04**: Each display (and each Space) keeps its own layout
- [x] **OVER-05**: Unplugging and re-plugging a display, or sleep/wake, restores that display's layout
- [x] **OVER-06**: Transom remembers layouts per display arrangement and applies the matching one automatically when the arrangement changes (e.g. docking and undocking a laptop)

### Tab Groups

- [ ] **TABS-01**: Dropping a window on the middle of another and pausing groups them under one tab strip
- [ ] **TABS-02**: Clicking a tab switches the visible window; other tabs stay hidden
- [ ] **TABS-03**: A group's close, minimise and dock/float buttons act on the whole group
- [ ] **TABS-04**: A tab can be dragged out to become its own window
- [ ] **TABS-05**: Tab groups work for windows from different apps, docked or floating
- [ ] **TABS-06**: Right-clicking a tab offers closing it and moving it out of the group

### Saved Views & Commands

- [ ] **VIEW-01**: User can save the current view to slots 1–9 and return to it with a hotkey
- [ ] **VIEW-02**: Saved views survive layout changes and app restarts
- [ ] **VIEW-03**: Transom commands run from `transom://` URLs (for Raycast, Alfred, Shortcuts, scripts)
- [ ] **VIEW-04**: Layouts persist across reboots and app relaunches (new window IDs), with windows re-matched to their tiles
- [ ] **VIEW-05**: A bundled `transom` command-line tool runs the same commands as `transom://` URLs and reports errors with a non-zero exit code

### Ship

- [ ] **SHIP-01**: Settings window covers gaps, appearance, gestures, hotkeys, exclusions and Mission Control replacement
- [ ] **SHIP-02**: First-run onboarding walks through permissions and conflicting macOS features
- [ ] **SHIP-03**: User can launch Transom at login
- [ ] **SHIP-04**: Transom checks the GitHub repo's latest release (automatically, toggleable, and via a "Check for Updates" button in the Settings window opened from the menu-bar icon), notifies the user when a newer version exists, and downloads and verifies the release DMG (sha256 digest + Developer ID Team ID) before opening it — same design as gifsmith's `internal/update`
- [ ] **SHIP-05**: Releases are Developer ID signed, notarised, and installable with `brew install --cask`
- [ ] **SHIP-06**: Menu bar shows back, forward and saved-view buttons with the current view highlighted, and Settings lets the user choose and reorder which controls appear, down to icon only
- [ ] **SHIP-07**: The menu includes "Report a Problem", and the menu bar icon shows a dot when an update is available
- [ ] **SHIP-08**: `transom://settings?pane=` opens a specific Settings pane

## v2 Requirements

- **V2-01**: Type-to-jump to a window in overview
- **V2-02**: Per-app rules that dock an app's windows automatically
- **V2-03**: Export/import settings
- **V2-04**: Maximum tile width on ultrawide displays
- **V2-05**: Focus follows mouse
- **V2-06**: Event hooks for scripts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Licensing, trials, paid tiers, window limits | Transom is free |
| Mac App Store | Private APIs required |
| Features needing SIP disabled | Keeps install safe and simple |
| Moving windows between native Spaces | Needs SIP since macOS 14.5 |
| Auto-tiling every new window | Research: top source of user frustration; new windows go to the Desktop tile |
| Animating real windows during zoom | Causes resize storms; only the snapshot overlay animates |
| Borders drawn around other apps' windows | Fragile, performance cost, low value |
| Scripting language / text-config DSL as main interface | Transom is GUI-first; URL commands cover automation |
| Second (scrolling) layout engine | Scope; one model done well |
| Mission Control takeover on by default | Risky; opt-in only |
| Copying any TrellisWM text, assets or code | Clean-room rule |

## Traceability

Populated by the roadmapper on 2026-10-23.

| Requirement | Phase | Status |
|-------------|-------|--------|
| MODEL-01 | Phase 1 | Complete |
| MODEL-02 | Phase 1 | Complete |
| MODEL-03 | Phase 1 | Complete |
| MODEL-04 | Phase 1 | Complete |
| MODEL-05 | Phase 1 | Complete |
| MODEL-06 | Phase 1 | Complete |
| MODEL-07 | Phase 1 | Complete |
| MODEL-08 | Phase 1 | Complete |
| MODEL-09 | Phase 1 | Complete |
| MODEL-10 | Phase 1 | Complete |
| WIN-01 | Phase 2 | Complete |
| WIN-02 | Phase 2 | Complete |
| WIN-03 | Phase 2 | Complete |
| WIN-04 | Phase 2 | Complete |
| WIN-05 | Phase 2 | Complete |
| WIN-06 | Phase 2 | Complete |
| WIN-07 | Phase 3 | Complete |
| WIN-08 | Phase 2 | Complete |
| WIN-09 | Phase 2 | Complete |
| TILE-01 | Phase 3 | Complete |
| TILE-02 | Phase 3 | Complete |
| TILE-03 | Phase 3 | Complete |
| TILE-04 | Phase 3 | Complete |
| TILE-05 | Phase 3 | Complete |
| TILE-06 | Phase 3 | Complete |
| TILE-07 | Phase 3 | Complete |
| TILE-08 | Phase 3 | Complete |
| TILE-09 | Phase 3 | Complete |
| TILE-10 | Phase 3 | Complete |
| TILE-11 | Phase 3 | Complete |
| TILE-12 | Phase 3 | Complete |
| TILE-13 | Phase 3 | Complete |
| TILE-14 | Phase 3 | Complete |
| TILE-15 | Phase 3 | Complete |
| TILE-16 | Phase 3 | Complete |
| TILE-17 | Phase 3 | Complete |
| TILE-18 | Phase 3 | Complete |
| TILE-19 | Phase 3 | Complete |
| TILE-20 | Phase 3 | Complete |
| SAFE-01 | Phase 3 | Complete |
| SAFE-02 | Phase 3 | Complete |
| SAFE-03 | Phase 3 | Complete |
| SAFE-04 | Phase 3 | Complete |
| SAFE-05 | Phase 2 | Complete |
| SAFE-06 | Phase 3 | Complete |
| ZOOM-01 | Phase 4 | Complete |
| ZOOM-02 | Phase 4 | Complete |
| ZOOM-03 | Phase 4 | Complete |
| ZOOM-04 | Phase 4 | Complete |
| ZOOM-05 | Phase 4 | Complete |
| ZOOM-06 | Phase 4 | Complete |
| ZOOM-07 | Phase 4 | Complete |
| ZOOM-08 | Phase 4 | Complete |
| ZOOM-09 | Phase 4 | Complete |
| ZOOM-10 | Phase 4 | Complete |
| ZOOM-11 | Phase 4 | Complete |
| ZOOM-12 | Phase 4 | Complete |
| ZOOM-13 | Phase 4 | Complete |
| GEST-01 | Phase 5 | Complete |
| GEST-02 | Phase 5 | Complete |
| GEST-03 | Phase 5 | Complete |
| GEST-04 | Phase 5 | Complete |
| OVER-01 | Phase 6 | Complete |
| OVER-02 | Phase 6 | Pending |
| OVER-03 | Phase 6 | Pending |
| OVER-04 | Phase 6 | Pending |
| OVER-05 | Phase 6 | Complete |
| OVER-06 | Phase 6 | Complete |
| TABS-01 | Phase 7 | Pending |
| TABS-02 | Phase 7 | Pending |
| TABS-03 | Phase 7 | Pending |
| TABS-04 | Phase 7 | Pending |
| TABS-05 | Phase 7 | Pending |
| TABS-06 | Phase 7 | Pending |
| VIEW-01 | Phase 8 | Pending |
| VIEW-02 | Phase 8 | Pending |
| VIEW-03 | Phase 8 | Pending |
| VIEW-04 | Phase 8 | Pending |
| VIEW-05 | Phase 8 | Pending |
| SHIP-01 | Phase 9 | Pending |
| SHIP-02 | Phase 9 | Pending |
| SHIP-03 | Phase 9 | Pending |
| SHIP-04 | Phase 9 | Pending |
| SHIP-05 | Phase 9 | Pending |
| SHIP-06 | Phase 9 | Pending |
| SHIP-07 | Phase 9 | Pending |
| SHIP-08 | Phase 9 | Pending |

**Coverage:**
- v1 requirements: 87 total
- Mapped to phases: 87
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-23*
*Last updated: 2026-10-25 — added TILE-11..14, OVER-06, VIEW-05 (features from other macOS window managers); TILE-15..20, ZOOM-09..13, TABS-06, SHIP-06..08 (features from the TrellisWM website)*
