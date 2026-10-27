# Roadmap: Pane

## Overview

Pane is built bottom-up along its dependency chain: a pure, headless layout model (Phase 1), a non-blocking Accessibility window-control layer (Phase 2), then drag-to-dock nested tiling with crash-safe recovery (Phase 3). Phase 3 is the **first usable release** and must work with zoom and Screen Recording turned off (TILE-10), so the Core Value ships before any risky feature. Phases 4-8 add the differentiators on top (zoom camera, trackpad gestures, overview/Spaces/multi-display, tab groups, saved views + `pane://` URLs + persistence), and Phase 9 polishes and ships a signed, notarised, Homebrew-installable build. Every retrofit-or-never decision (async AX, window lifecycle states, `DeskKey`, coordinate space, bundle ID and signing) lands in Phases 1-3.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Layout Model** - Headless PaneModel: nested split tree, Desktop layer, tab groups, desks, lifecycle states, JSON, undo (completed 2026-10-24)
- [ ] **Phase 2: Window Control** - Accessibility permission, non-blocking window tracking and move/resize, classifier, exclusions, private-API fallback
- [x] **Phase 3: Tiling MVP** - Drag-to-dock nested tiling, reflow, gaps, commands, crash-safe restore; first usable signed release (completed 2026-10-27)
- [ ] **Phase 4: Zoom Camera** - Snapshot overlay stage: zoom out/step/rect zoom, history, click-to-focus, fast settle
- [ ] **Phase 5: Gestures** - Trackpad pinch and pan with ⌥ anywhere and bare on the desktop
- [ ] **Phase 6: Overview, Spaces & Displays** - Overview with Spaces bar, opt-in Mission Control takeover, per-display/per-Space layouts
- [ ] **Phase 7: Tab Groups** - Drop-to-group windows from any apps under a tab strip with group-wide buttons
- [ ] **Phase 8: Saved Views, URLs & Persistence** - Views 1-9, `pane://` commands, layouts restored across restarts and reboots
- [ ] **Phase 9: Polish & Ship** - Settings, onboarding, launch at login, GitHub Releases update check, Homebrew cask

## Phase Details

### Phase 1: Layout Model

**Goal**: As a Pane developer, I want to edit and resolve a nested tile layout in headless tests, so that every later feature rests on correct geometry.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: MODEL-01, MODEL-02, MODEL-03, MODEL-04, MODEL-05, MODEL-06, MODEL-07, MODEL-08, MODEL-09, MODEL-10
**Success Criteria** (what must be TRUE):
  1. `swift test` shows a window inserted beside any tile on any of its four edges and removed again, with every split's child weights summing to 1 and single-child splits collapsing automatically
  2. For any layout, area and gap size, resolved tile rects never overlap and honour every window's minimum size
  3. A desk keyed by display UUID (plus optional Space ID) holds a tiled tree, a floating Desktop layer and tab-group tiles with one selected window; an absent or fullscreen window keeps its reserved slot until it is confirmed closed
  4. Any layout serialises to versioned JSON and round-trips exactly, and every edit can be undone back to the previous layout
  5. `PaneModel` builds and tests without importing AppKit, enforced by a CI check

**Plans:** 6/6 plans complete

Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Walking skeleton: package, core types, dock-beside → resolve → World → versioned JSON, full invariant checker

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Tree edits: remove with proportional redistribution, normalisation (collapse/merge/ε clamp), gap-drag reweigh, seeded edit fuzz
- [x] 01-03-PLAN.md — Geometry: min-size water-filling, unfit reporting, lifecycle exclusion, input validation, resolve property fuzz, drop-zone hit testing
- [x] 01-04-PLAN.md — Desks: Desktop layer, transactional edits with 50-level per-desk undo, hardened persistence (version gate, migration chain, corrupt corpus)
- [x] 01-06-PLAN.md — PaneEngine target with draft WindowSystem protocol, no-AppKit check in `swift test` + CI workflow on macos-26

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 01-05-PLAN.md — Tab groups, lifecycle transitions (reserved slots until closed), drop targets → edits, end-to-end scenario

**Research**: Standard patterns (fully specified in research ARCHITECTURE.md); skip phase research
**Scope notes**: Lock the expensive-to-change shapes here: flat value tree keyed by `NodeID`, fractional weights, `Node.tabs` case, `DesktopLayer`, `DeskKey(displayUUID, spaceID?)`, `WindowRef` with persisted match hints, single top-left global coordinate space, schema version. Also: drop-zone hit-testing and a first draft of the `WindowSystem` protocol.

### Phase 2: Window Control

**Goal**: As a Mac user, I want to grant Pane access and have it track and move every window, so that no slow app or lock screen can freeze or lose them.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: WIN-01, WIN-02, WIN-03, WIN-04, WIN-05, WIN-06, WIN-08, WIN-09, SAFE-05
**Success Criteria** (what must be TRUE):
  1. On first launch the user is guided to grant Accessibility; if the grant goes stale (for example after a rebuild), Pane detects it and explains the fix instead of looping on prompts
  2. Pane's tracked-window list shows every standard window of every running app, updates as windows open and close, counts a natively tabbed Finder, Terminal or Safari window as one window, and never includes dialogs, sheets, popovers or picture-in-picture windows (classifier passes the recorded AX-dump corpus)
  3. Pane can move and resize any tracked window on any display, including secondary displays in any arrangement; when an app refuses a size Pane learns its real minimum, and apps on the user's exclusion list are never touched
  4. Freezing an app with `kill -STOP` neither stalls Pane nor delays arranging other apps' windows, and locking the screen, sleeping or an AX timeout never marks a window closed
  5. With `_AXUIElementGetWindow` forced unavailable, Pane still launches and tracks windows through its fallback

**Plans**: 17/17 plans executed

Plans:
**Wave 1**
- [x] 02-01-PLAN.md — Tracer: fixture window tracked end to end on a per-app AX thread; WindowSystem contract, WindowTracker, FakeWindowSystem, fixture app

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-02-PLAN.md — Signed menu-bar app: status item with live header, XcodeGen + Developer ID Pane Debug.app / Pane.app
- [x] 02-03-PLAN.md — Classifier, CG window list, pane-dump and the redacted AX-dump corpus (WIN-05)
- [x] 02-04-PLAN.md — LifecycleSync: OS lifecycle via World.apply and the undo re-query obligation

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02-05-PLAN.md — Accessibility onboarding, stale-grant detection and Reset Permission (WIN-01)
- [x] 02-06-PLAN.md — Live tracking (app launch/quit, AX hints, debounce, sweep) and display UUIDs via one coordinate boundary

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 02-07-PLAN.md — Hung and slow apps: responsiveness tracker, degraded probing, SIGSTOP test (WIN-03)
- [x] 02-08-PLAN.md — Tracked Windows window, Don't Arrange exclusions, Freeze test

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 02-09-PLAN.md — Two-source close confirmation and lock/sleep session gate (WIN-09)

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 02-10-PLAN.md — Native tab groups count as one window (WIN-06)
- [x] 02-11-PLAN.md — Window-ID fallback matching and capability degradation (SAFE-05)

**Wave 7** *(blocked on Wave 6 completion)*
- [x] 02-12-PLAN.md — Latest-wins move/resize pipeline with read-back and learned minimums (WIN-04)

**Wave 8** *(blocked on Wave 7 completion)*
- [x] 02-13-PLAN.md — Exclusion enforcement, persisted minimum hints, Nudge Focused Window

**Gap closure** *(from 02-VERIFICATION, sequential: each plan shares files with the one before)*
- [x] 02-14-PLAN.md — Read-only SkyLight Spaces capability; Space-aware tab groups, single-Space fallback rule and fold guard (WIN-06, WIN-09, SAFE-05)
- [x] 02-15-PLAN.md — Minimum-size learner: one clear refusal confirmed by time, no snaps, in-session hints (WIN-04)
- [x] 02-16-PLAN.md — Window identity: per-element failure counting, fallback IDs re-checked and re-keyed with no destroy/create (SAFE-05, WIN-02)
- [x] 02-17-PLAN.md — Space-switch race without Space data: after `NSWorkspace.activeSpaceDidChangeNotification`, refuse the orphan handoff and new hidden-tab folds for one update; with Space data, no change (WIN-06, WIN-09)

**Research**: Moderate. Patterns are documented (AeroSpace), but the window classifier corpus, native-tab heuristics and two-source close-confirmation rules need careful design
**Scope notes**: Pulled forward per research: coordinate conversion at one tested boundary plus display-UUID matching (from Phase 6) and native-tab detection (from Phase 7). Also: per-app AX threads with ~1 s messaging timeouts, coalesced size-position-size writes with read-back, the `PanePrivate` dlsym pattern and capability registry, `FakeWindowSystem`, fullscreen state detection (tile return is verified in Phase 3 under WIN-07), stable dev signing identity and a separate debug bundle ID so TCC grants survive rebuilds.

### Phase 3: Tiling MVP

**Goal**: As a Mac user, I want to drag windows into nested tiles that reflow as windows open and close, so that my windows never overlap.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: TILE-01, TILE-02, TILE-03, TILE-04, TILE-05, TILE-06, TILE-07, TILE-08, TILE-09, TILE-10, TILE-11, TILE-12, TILE-13, TILE-14, TILE-15, TILE-16, TILE-17, TILE-18, TILE-19, TILE-20, WIN-07, SAFE-01, SAFE-02, SAFE-03, SAFE-04, SAFE-06
**Success Criteria** (what must be TRUE):
  1. Dragging a window by its title bar to a screen edge or another window's edge shows a drop preview and docks it there on release, nesting as deep as the user likes; holding the bypass modifier moves it freely, new windows open floating on the Desktop tile, and the green button toggles a window between docked and floating
  2. Closing a docked window reflows its neighbours to fill the space, dragging the gap between two windows resizes both, the user can change the gap size, and a window that leaves native fullscreen returns to its reserved tile
  3. From the menu bar and from hotkeys, routed through one command dispatcher, the user can dock, float, focus a neighbour, undo the last layout change, pause and resume arranging, and "Restore all windows" (also via `pane://restore`)
  4. Quitting Pane returns every window it moved to a sensible on-screen frame, a crash or force-quit is followed on next launch by stranded windows coming back on-screen, and Pane detects macOS edge tiling, Stage Manager and click-wallpaper-to-reveal, explains the conflict, offers to turn them off and can restore the originals; quitting and relaunching Pane while apps keep running brings each layout back with the same windows in their tiles
  5. All of the above works with zoom absent and Screen Recording denied, and testers install it as a Developer ID-signed, notarised build whose Accessibility grant survives updates
  6. User can swap two tiles, balance, rotate and flip a split, move the focused window into a neighbouring tile and resize its tile from the keyboard, and snap floating Desktop windows to halves, thirds, quarters, maximised and centred by hotkey
  7. User can hide and show the Desktop, arrange all or float all windows, split a tile with a new Finder window and mark the frontmost app "Don't Arrange" from the menu; ⌥-clicking the green button gives the normal macOS zoom, and a minimised docked window returns to its tile

**Plans:** 26/26 plans complete (9 gap-closure plans from UAT)

Plans:
**Wave 1**
- [x] 03-01-PLAN.md — Desktop tile in the model: `Node.desktop(hidden:)`, reserved `NodeID.desktop`, hide/show, persisted from schema 1

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 03-02-PLAN.md — Layout edits and geometry: swap, balance, rotate (its own inverse), flip, grow/shrink, two-child resize, neighbour and boundary lookups, snap targets
- [x] 03-03-PLAN.md — Non-undo World paths: `windowRekeyed` re-points desks and undo snapshots, floating-frame facts, reflow, Undo keeps floating positions

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 03-04-PLAN.md — Tracer: pure Arranger + ArrangeController (the single events reader), ⌃⌥⌘D/F/Z via KeyboardShortcuts 3.1.0, reflow on close, minimise and fullscreen

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 03-05-PLAN.md — One layout per display and Space: current Space from SkyLight, `spaceChanged`, fullscreen Spaces get no desk, re-home rule

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 03-06-PLAN.md — Layout stays correct: echo rule, app-initiated moves, floating facts, windows that lose their room float (N1 toast)

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 03-07-PLAN.md — layout.json: validated atomic store, re-attach by window ID on relaunch (SAFE-06), no titles stored

**Wave 7** *(blocked on Wave 6 completion)*
- [x] 03-08-PLAN.md — park/focus/raise in both window systems; hide/show the Desktop tile (save before park); ⌃⌥⌘ arrows focus neighbours

**Wave 8** *(blocked on Wave 7 completion)*
- [x] 03-09-PLAN.md — Split with New Finder Window by AX menu press (no Apple Events), N9

**Wave 9** *(blocked on Wave 8 completion)*
- [x] 03-10-PLAN.md — Menu regrouped (Arrange/Safety/Exclusions, Debug with ⌥) through one dispatcher, items built once; Pause/Resume; Gaps; Don't Arrange ⌃⌥⌘E

**Wave 10** *(blocked on Wave 9 completion)*
- [x] 03-11-PLAN.md — Drag to dock: active event tap with watchdog, drag sessions, 150 ms WYSIWYG preview, ⇧ bypass, ⌘ swap, blocked drops

**Wave 11** *(blocked on Wave 10 completion)*
- [x] 03-12-PLAN.md — Keyboard layout commands: move/snap halves, swap previous, grow/shrink, balance/rotate/flip, thirds/quarters/maximise/centre, Arrange All, Float All

**Wave 12** *(blocked on Wave 11 completion)*
- [x] 03-13-PLAN.md — Green button toggles dock/float (⌥ keeps native zoom), edge resize, gap handles

**Wave 13** *(blocked on Wave 12 completion)*
- [x] 03-14-PLAN.md — Crash recovery: stranded windows first, layout re-applied, crash loop starts paused; Restore All Windows ⌃⌥⌘0

**Wave 14** *(blocked on Wave 13 completion)*
- [x] 03-15-PLAN.md — Quit restore with bounded per-app writes; `pane://restore`, `toggle-desktop`, `split-finder`

**Wave 15** *(blocked on Wave 14 completion)*
- [x] 03-16-PLAN.md — macOS conflicts: Stage Manager pause, edge tiling, click wallpaper; Turn Off with read-back, alerts, Restore macOS Window Settings

**Wave 16** *(blocked on Wave 15 completion)*
- [x] 03-17-PLAN.md — `scripts/release.sh`: secure timestamp, notarise, staple, DMG; local notarised 0.3.0 DMG, public release held for the Transom rename (blocking checkpoint for the notarised run)

**Gap closure, Wave 1** *(from 03-UAT.md)*
- [x] 03-18-PLAN.md — G-03-4: the tap's window-0 fallback picks the topmost layer-0 window (pure, tested), so plain green-button clicks toggle dock/float; D-33 kept
- [x] 03-19-PLAN.md — G-03-5: PendingFocus keeps a focus hint until the new window is tracked, so commands act on a second window of an app
- [x] 03-20-PLAN.md — G-03-3: gap drag re-bases split weights to laid-out sizes (pinned side) and holds the live move across mid-drag replans
- [x] 03-21-PLAN.md — G-03-6: the Desktop minimum ignores floaters that would push docked windows out

**Gap closure, Wave 2** *(blocked on 03-20 and 03-21)*
- [x] 03-22-PLAN.md — G-03-6: a docked window refusing its tile from its minimum is retried once and learned, then floats; under-32 pt overflow tolerated

**Gap closure (G-03-8), Wave 1** *(from the 03 re-verify; no plan dependency)*
- [x] 03-23-PLAN.md — G-03-8: saved windows on a Space not shown at relaunch stay dormant in their desk while alive in the CG list and re-attach in their tiles when shown; pruned when they close or their app quits; VM re-check of UAT 17

**Gap closure (G-03-10), Wave 1** *(from the 03-23 review-fix VM checks; no plan dependency)*
- [x] 03-24-PLAN.md — G-03-10: the initial sweep counts only when it ran unpaused, so a start while locked restores every saved desk after unlock (AXWindowSystem + fake mirror, locked-start regression); AX-read failure just after unlock recorded as a non-goal

**Gap closure (G-03-4 reopened, G-03-11), Waves 1-2** *(from the 03-24 VM hand checks; 03-26 blocked on 03-25)*
- [x] 03-25-PLAN.md — G-03-11/G-03-4: per-window wanted frame only user actions write (kept while docked); floaters planned from it so a Desktop that shrinks and grows back returns them; a refused floater read-back stops a boundary drag at its real size; Float and the green button go to the pre-dock frame (or a 90% centred frame) so every toggle is visible
- [x] 03-26-PLAN.md — G-03-4/G-03-11: wanted frames saved in layout.json (optional key, old files load with none, validated like home frames); re-attach keeps frames the user changed while Pane was not running and drops stranded ones

**UI hint**: yes
**Research**: Standard patterns; drop-zone geometry starts from yabai's numbers (edge bands ~25%, centre ~50%) and is tuned in UAT
**Scope notes**: First usable release. Pulled forward per research: crash restore, edge-tiling detection and a minimal signed + notarised pipeline (an enabler for SHIP-05, which completes in Phase 9 with the Homebrew cask; confirm notarisation works with dlopen of private frameworks). Drags are detected from frame deltas, not mouse-down hit-tests; keep the top-edge zone clear of Mission Control. Includes the event-tap wrapper with re-enable watchdog, persisted home frames, default exclusions and single-display correctness. The `pane://` scheme is registered here with `restore`, `toggle-desktop` and `split-finder` (TILE-15, TILE-17); Phase 8 generalises it. Basic layout restore (SAFE-06) re-attaches by unchanged window IDs while apps keep running; reboot/app-relaunch re-matching stays in Phase 8 (VIEW-04). Default hotkeys for all new commands are Pane's own choices (clean-room rule: no copying TrellisWM's settings values).

### Phase 4: Zoom Camera

**Goal**: As a Mac user, I want to zoom out to see every window and zoom back in to any of them, so that I can find and focus any window fast.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: ZOOM-01, ZOOM-02, ZOOM-03, ZOOM-04, ZOOM-05, ZOOM-06, ZOOM-07, ZOOM-08, ZOOM-09, ZOOM-10, ZOOM-11, ZOOM-12, ZOOM-13
**Success Criteria** (what must be TRUE):
  1. User can zoom out to see every window on the display at once, step in or out one level of the layout tree, and ⌘⇧-drag a rectangle to zoom to the windows it frames
  2. User can go back and forward through previous views, and clicking a window in a zoomed view zooms in to it and focuses it
  3. Zoomed views show live window snapshots when Screen Recording is granted and app colour plus icon when it isn't; denying Screen Recording never breaks zoom
  4. After a zoom settles, 15 real windows are at their new sizes within 500 ms with no visible flash of a stale layout, and windows parked out of view still come back on-screen on quit, after a crash and via "Restore all windows"
  5. User can rebind every zoom hotkey, and turning zoom off leaves Phase 3 tiling fully working
  6. User can move the view to a neighbouring area, frame the focused window or the Desktop on its own and toggle back (including by double-click), cancel a rectangle zoom with Esc, and tiles too small for their window show as collapsed app-colour blocks that zoom in on double-click

**Plans**: TBD
**UI hint**: yes
**Research**: Needs phase research. Start with a feasibility spike with measurable criteria: settle latency with Electron-heavy windows, terminal re-wrap, represented-state UX, ScreenCaptureKit memory growth over hours (soak test), overlay window level versus menus, Core Animation performance with 100+ layers
**Scope notes**: Only the snapshot overlay animates; real windows get one AX write when the camera settles (changed and visible targets only). Capture before parking; park by moving, not shrinking. Camera targets are `NodeID`s so history and saved views survive reflows.

### Phase 5: Gestures

**Goal**: As a trackpad user, I want to pinch and pan the desk with my fingers, so that zooming and moving around feels direct.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: GEST-01, GEST-02, GEST-03, GEST-04
**Success Criteria** (what must be TRUE):
  1. ⌥-pinch on the trackpad zooms in and out over any app, and ⌥-two-finger pan moves the camera
  2. Pinch and pan on the bare desktop work without holding ⌥
  3. Gestures Pane handles never reach the app under the pointer, while ordinary pinch and scroll inside apps keep working
  4. Gestures keep working after sleep/wake and after the trackpad disconnects and reconnects; if the private multitouch API is unavailable Pane falls back and still launches

**Plans**: TBD
**Research**: Needs phase research. One-day spike comparing MultitouchSupport raw touches against event-tap magnify events (types 29/30, visibility over other apps unverified); verify MT callback struct layout and the macOS 27 `int32_t` return semantics
**Scope notes**: Own MultitouchSupport shim (port OpenMultitouchSupport headers, don't depend on 4.x), magnify-event fallback, device re-enumeration on wake and hot-plug, per-API crash canary.

### Phase 6: Overview, Spaces & Displays

**Goal**: As a multi-display user, I want to see every window on every display and Space in one overview, so that I can jump anywhere and keep each layout.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: OVER-01, OVER-02, OVER-03, OVER-04, OVER-05, OVER-06
**Success Criteria** (what must be TRUE):
  1. Opening the overview shows every window on every display with the Spaces along the top, and clicking a window goes to it
  2. User can opt in to Mission Control's swipe and shortcut opening Pane's overview and opt out to get the system behaviour back; if Pane crashes while the takeover is on, the next launch restores the system shortcuts
  3. Each display and each Space keeps its own layout, and switching Spaces leaves the other layouts untouched
  4. Unplugging and re-plugging a display, or sleeping and waking the Mac, restores that display's layout, with "Displays have separate Spaces" both on and off
  5. Pane remembers a layout set per display arrangement and switches to the matching one automatically when a laptop is docked or undocked

**Plans**: TBD
**UI hint**: yes
**Research**: Needs phase research. Verify SkyLight signatures, Space-UUID stability across reboots and macOS updates, and symbolic-hotkey state after deliberate crash tests
**Scope notes**: Read-only SkyLight `SpacesProvider` with a single-Space fallback; skip dirty desks while their Space is hidden; orphan/dormant desks on unplug re-attached by display UUID; debounced display reconfiguration; Mission Control takeover is opt-in with a restore watchdog. The read-only SkyLight Spaces lookup (`SkyLightSpaces`, capability `Spaces`, single-Space fallback) landed in Phase 2 (02-14), so Phase 6 builds its `SpacesProvider` on it rather than re-adding it. When the Spaces lookup is unavailable, build a public-API fallback map of window→Space by co-visibility between `NSWorkspace.activeSpaceDidChangeNotification` events, so same-frame tab groups on different Spaces stay separate (closes phase 2 known limit: C5 single-Space merge; covers only Spaces visited since launch). Also closes deferred G-03-9: a window whose only CG entry has no Space (Safari keeps closed windows' entries for minutes) must count as closed, not alive (see .planning/debug/g-03-9-closed-safari-lingers.md).

### Phase 7: Tab Groups

**Goal**: As a Mac user, I want to group windows from any apps into one tabbed tile, so that related windows share space without overlapping.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: TABS-01, TABS-02, TABS-03, TABS-04, TABS-05, TABS-06
**Success Criteria** (what must be TRUE):
  1. Dropping a window on the middle of another and pausing groups them under one tab strip that follows the group as it moves and resizes
  2. Clicking a tab switches the visible window, and the other tabs stay hidden (not minimised)
  3. The group's close, minimise and dock/float buttons act on the whole group
  4. Dragging a tab out of the strip makes it its own window again
  5. Tab groups work for windows from different apps, both docked and floating on the Desktop tile
  6. Right-clicking a tab offers close and move-out

**Plans**: TBD
**UI hint**: yes
**Research**: Standard patterns; builds on `Node.tabs` (Phase 1), native-tab detection (Phase 2) and window parking (Phase 4)
**Scope notes**: Tab strip panel tracks the group leader via CG bounds polling; inactive tabs are hidden by parking, never minimised.

### Phase 8: Saved Views, URLs & Persistence

**Goal**: As a power user, I want to save views to hotkeys and run Pane from pane:// URLs, so that my layouts and automations survive restarts.
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: VIEW-01, VIEW-02, VIEW-03, VIEW-04, VIEW-05
**Success Criteria** (what must be TRUE):
  1. User can save the current view to slots 1-9 and return to it with a hotkey, and it still lands on the right windows after the layout changes and after Pane restarts
  2. Raycast, Alfred, Shortcuts or a shell `open pane://...` can run Pane commands, and unknown commands are rejected without side effects
  3. After quitting and relaunching Pane, or rebooting the Mac, layouts come back with each window re-matched to its tile, and windows that never return leave a placeholder that expires rather than a permanent hole
  4. A bundled `pane` command-line tool runs every `pane://` command and exits non-zero with a message on errors

**Plans**: TBD
**Research**: Standard patterns; cheap on top of the Phase 3 command dispatcher and Phase 4 `NodeID` camera targets
**Scope notes**: Layout-aware default chords for views; `pane://` with an allow-list and rate limit; re-matching uses persisted match hints with a score threshold.

### Phase 9: Polish & Ship

**Goal**: As a new user, I want to install Pane with Homebrew and be guided through setup, so that it starts at login and keeps itself updated.
**Mode:** mvp
**Depends on**: Phase 5, Phase 6, Phase 7, Phase 8
**Requirements**: SHIP-01, SHIP-02, SHIP-03, SHIP-04, SHIP-05, SHIP-06, SHIP-07, SHIP-08
**Success Criteria** (what must be TRUE):
  1. The Settings window lets the user change gaps, appearance, gestures, hotkeys, exclusions and Mission Control replacement
  2. On first run, onboarding walks the user through Accessibility, optional Screen Recording and the conflicting macOS features, without looping on permission prompts
  3. User can turn on launch at login, and Pane starts at the next login
  4. Settings (opened from the menu-bar icon) has an Updates section: an automatic-check toggle and a "Check for Updates" button; when GitHub has a newer release Pane notifies the user, and the downloaded DMG is opened only after its sha256 digest and Team ID verify
  5. `brew install --cask` installs a Developer ID-signed, notarised Pane that opens without Gatekeeper warnings
  6. The menu bar shows back, forward and saved-view controls (current view highlighted) that the user can choose and reorder in Settings; the menu has "Report a Problem", the icon shows a dot when an update is waiting, and `pane://settings?pane=` opens a given Settings pane

**Plans**: TBD
**UI hint**: yes
**Research**: Standard patterns; port gifsmith's GitHub Releases updater (`~/dev/gifsmith/internal/update`, `internal/services/updates.go`) to Swift; notarisation and Homebrew are well documented (Rectangle and Amethyst casks as models)
**Scope notes**: SwiftUI only inside `NSHostingController`. Onboarding includes the monthly Screen Recording explanation and an App Translocation check. CI checks the designated requirement so TCC grants survive updates. Own Homebrew tap first, then homebrew/cask. Add a macOS-beta compatibility checklist for the private APIs. Check the name "Pane" for existing macOS apps before release.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Layout Model | 6/6 | Complete    | 2026-10-24 |
| 2. Window Control | 17/17 | In Progress | - |
| 3. Tiling MVP | 26/26 | Complete    | 2026-10-27 |
| 4. Zoom Camera | 0/TBD | Not started | - |
| 5. Gestures | 0/TBD | Not started | - |
| 6. Overview, Spaces & Displays | 0/TBD | Not started | - |
| 7. Tab Groups | 0/TBD | Not started | - |
| 8. Saved Views, URLs & Persistence | 0/TBD | Not started | - |
| 9. Polish & Ship | 0/TBD | Not started | - |
