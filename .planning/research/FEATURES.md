# Feature Research

**Domain:** macOS window manager. Pane is a mouse-first, nested-tiling manager with a zoomable camera over all windows.
**Researched:** 2026-10-23
**Confidence:** MEDIUM overall
- Competitor feature sets: MEDIUM. Taken from project READMEs and docs, cross-checked between at least two sources where possible.
- User complaints: MEDIUM-HIGH. Taken directly from the GitHub API, ranking issues and discussions by comment and upvote counts for each competitor repo.
- Demand for a zoomable canvas on macOS: LOW-MEDIUM. Searches found no mature macOS precedent; the evidence is indirect (Linux prior art, plus feature requests in other projects).

Clean-room note: this file uses only public prior art (open-source competitors, their issue trackers, docs and press) plus Pane's own `PROJECT.md` and `PLAN.md`. No reference-app marketing, UI text or binary content was consulted.

---

## Landscape in one paragraph

macOS window managers split into four families. (1) **Snap tools**: Rectangle (~30k stars), Loop (~12k), Magnet, Moom and macOS 15+ native tiling. These are mouse- or shortcut-driven, keep no layout state and are beginner-friendly. (2) **Tree/BSP tilers**: AeroSpace (~24k), yabai (~30k) and Amethyst (~16k). These are keyboard-first, configured through text files and aimed at developers. AeroSpace states it "will never provide a GUI for configuration". (3) **Scrolling tilers in the Niri/PaperWM style**: PaperWM.spoon, Paneru, rift and OmniWM, all young (2025–26), all keyboard- or trackpad-swipe-driven, and the newer ones include a Niri-style overview. (4) **Zoomable canvases**: these exist only on Linux (Niri overview, driftwm, Phantomat) or as academic ZUI window managers. Public searches found no maintained open-source macOS canvas/zoom WM. **Pane's open space is a stateful nested tiler driven mainly by the mouse and trackpad, with a GUI and a zoom camera.** Snap tools are mouse-driven but stateless. Tilers are stateful but keyboard- and config-driven. Nobody on macOS combines both, and none offers a zoom-out camera.

---

## What users complain about most (evidence-ranked)

These come from GitHub issues and discussions ranked by comment and upvote counts, plus HN threads. They mark where users leave, so they define table stakes better than feature lists do.

| # | Complaint theme | Evidence | Implication for Pane |
|---|---|---|---|
| 1 | **Every macOS release breaks it** | yabai's five most-commented issues are all OS-release threads (Monterey 241, M1 235, Sonoma 172, Ventura 152, Big Sur 112), plus Tahoe at 92. Rectangle has "doesn't work on Sonoma". OmniWM has "Did macOS 26.2 break OmniWM?" | Isolate each private API behind a fallback (already a constraint). Degrade features instead of failing completely. Ship a "compat mode" that turns off private-API features. |
| 2 | **Freezes and lag from blocking AX calls** | AeroSpace's top issue is "Delay/freeze when switching focus & workspace" (62). Its 1.0 blocker #131 is a thread per app. Rectangle: "super slow for Chrome" (50). Amethyst: "sluggish … with Chrome" (41). Loop: "System becomes extremely slow" | AX calls must never run on the main thread or block the UI and overlays. Use a per-app messaging timeout and per-app queues from day one. |
| 3 | **Ghost, lost or disappearing windows** | AeroSpace: "Fight with ghost windows" (40), "Dead windows in list-windows" (24), "phantom window remains", "Floating windows are disappearing" (15 comments, 12 upvotes). rift: "forgets about … Chrome windows". OmniWM: "Floating windows disappear offscreen" | Pane parks windows off-view, so lost windows are the biggest trust risk. It needs (a) reconciliation against the real window list, (b) an "unpark all / panic restore" command, and (c) restore-all-windows on quit, crash and uninstall. |
| 4 | **Native macOS tabs treated as separate windows** | yabai "Handle native tabs properly", open since 2019 (77). AeroSpace #68, open (45). PaperWM, Paneru and Ghostty's own docs report the same | Pane has its own tab groups, so it must detect native tab siblings (same AX parent window, only one visible) and treat them as one window. Getting this wrong corrupts the layout tree. |
| 5 | **Multiple monitors, sleep/wake, display changes** | rift: "layout not restored after display sleep/wake or switching displays" (34), "All windows go to single monitor" (58), "Scrolling mode unusable with multiple monitor" (25). Paneru: "Not responding after wake". PaperWM: "No more tiling after waking". AeroSpace: ultrawide request (34) | Store layout per display, keyed by a stable display identity rather than the index. Handle display add/remove/sleep as first-class events. Test clamshell transitions. |
| 6 | **Dialogs, PiP, popovers and tooltips get tiled** | AeroSpace: "YouTube picture in picture gets tiled" (23), "CleanShot X's supplementary UI" (25), Firefox tooltips treated as windows. rift: "Floating window issues" (72), "app rules don't work" (35) | Pane needs a window classifier (AX role/subrole, missing zoom/fullscreen button, size, level) that sends non-standard windows to floating. Per-app rules should be editable in the GUI. |
| 7 | **Spaces, Mission Control and fullscreen fights** | Amethyst: "Throwing window to a space is broken", three issues with 54–70 comments each after Sonoma 14.5. AeroSpace: Mission Control shows hidden windows "too small". OmniWM requires "Displays have separate Spaces". HN: "Full screen windows seemingly break both completely" | Read Spaces but never move windows between Spaces (that needs SIP since 14.5). Treat native fullscreen windows as leaving the tree temporarily. Make the Mission Control replacement opt-in. |
| 8 | **Hotkeys stop working** | AeroSpace: "not registering key presses on letter keys" (40), "Alt key bindings stop working randomly". Amethyst: "Almost all keybindings stopped working" (open) | Use the Carbon `RegisterEventHotKey` API for plain hotkeys. Use event taps only where unavoidable (Mission Control takeover, gestures), and re-enable a tap when macOS disables it on timeout. |
| 9 | **Permission onboarding loops** | Paneru: "Accessibility permissions requests are DoS-ing" (21), "infinitely requesting accessibility permissions". Loop: "Accessibility Permissions not working on 1.0.0" | Show one clear permission screen, poll for the grant, and never re-prompt in a loop. Explain the stale-TCC-entry case after an update and how to fix it. |
| 10 | **Config friction and no GUI** | HN Omacosy thread: "Why the heck these values are not reachable from the UI", "hard to memorise yet another keyboard shortcut". AeroSpace refuses GUI config | A real Settings window plus discoverable mouse and gesture interactions. This is Pane's opening. |

**Most-requested features in competitors** (AeroSpace feature ideas by upvotes, plus issue counts): max width for nodes on ultrawide displays (37), less freezing (27), scrollable layouts (19), focus-follows-mouse (19), sticky floating windows on every workspace (36-comment issue, scheduled after 1.0), BSP/dwindle (13), grid (12), "show the current tree" (7), and "spaces side-by-side in Mission Control for a quick overview" (6). Two of these, sticky floating windows and seeing the whole arrangement at once, line up directly with Pane's Desktop tile and zoom-out camera.

---

## Feature Landscape

### Table Stakes (Users Expect These)

If any of these is missing, users uninstall within a day. Users give no credit for them but punish their absence.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Reliable window tracking** (created, destroyed, moved, minimised, hidden, app quit) with reconciliation | Complaint #3. Ghost windows destroy trust | HIGH | AXObserver per app, plus a periodic reconciliation pass against the CGWindowList and SkyLight window list. Use `_AXUIElementGetWindow` for stable IDs. Every tree mutation must tolerate a window vanishing mid-operation. |
| **Non-blocking AX control with per-app timeouts** | Complaint #2. Chrome, Electron and Java apps stall the AX API | MEDIUM | One serial queue per app pid plus `AXUIElementSetMessagingTimeout`. The UI thread and overlays never wait on AX. |
| **Automatic floating for dialogs, sheets, PiP, popovers and utility panels** | Complaint #6 | MEDIUM | Classify by role/subrole (`AXStandardWindow` only), presence of the zoom button, minimum size and window level. These windows go to the Desktop tile and are never docked. |
| **Per-app exclusion / always-float list (GUI)** | Every tiler has one, and PROJECT.md requires it | LOW | Bundle-ID list in Settings plus "exclude this app" in the menu bar. Recommended default seeds: System Settings, Calculator, 1Password mini, menu-bar apps. |
| **Gaps (inner/outer) and draggable dividers that resize neighbours** | Every tiler and snap tool, and macOS 15 native, supports padding and resizing adjacent windows | MEDIUM | The divider between tiles is a hit target in a gap overlay. Changing weights keeps the tree's proportions. Respect each app's minimum size (AX gives no min-size, so learn it by observing clamping). |
| **Reflow when windows close, minimise or hide** | The core value in PROJECT.md | MEDIUM | Removing a window collapses its split and siblings absorb the weight. Minimise and Hide should leave a reserved slot, or collapse it (design decision to make in the model phase). |
| **Respect app minimum sizes, no overlap** | macOS native tiling's known failure is that apps refusing to shrink overlap. Pane promises "never overlap" | MEDIUM | After a set-frame, read the frame back. If the app clamped, push the deficit to siblings or mark the tile overflowed. Never silently overlap. |
| **Multi-display support with stable per-display state** | Complaint #5 | HIGH | Key state by display UUID (`CGDisplayCreateUUIDFromDisplayID`), not by index. Survive unplug and replug, sleep/wake and clamshell. Windows on a removed display go to the Desktop tile of the main display and come back when it reconnects. |
| **Native fullscreen handled gracefully** | HN: fullscreen "breaks both completely" | MEDIUM | A window entering native fullscreen leaves the tree, keeping a placeholder, and gets its slot back on exit. The green button's default click is remapped to dock/float, as the spec says, and Option-click still reaches native fullscreen. |
| **Native-tab awareness** | Complaint #4 | MEDIUM | Detect AX tab groups (Finder, Terminal, Safari, Ghostty) and treat them as one window. Required before Pane's own tab groups ship, or the two systems will fight. |
| **Restore-on-quit / crash safety / panic unpark** | Complaint #3, and Pane parks windows off-view | MEDIUM | Persist the last real frames. On quit, crash relaunch or disable, put every window back on screen. Add a "Bring all windows on-screen" menu item and URL command. |
| **Accessibility permission onboarding that does not loop** | Complaint #9 | LOW | Single screen with live polling. Explain a stale TCC entry and provide a reset helper. Screen Recording is optional and requested only when the zoom snapshots need it, as in OmniWM and the PLAN. |
| **Menu-bar presence with pause/enable toggle** | Every tool (AeroSpace, OmniWM, Loop) is menu-bar based. Users need a fast way out when something goes wrong | LOW | Pause stops all window moves but keeps the tree, and resume reapplies it. |
| **Keyboard commands for core actions** | Even mouse-first snap tools (Rectangle, Loop, macOS 15) ship shortcuts. Power users expect focus and move by direction | LOW (once a command bus exists) | Focus left/right/up/down, swap, toggle float, zoom out/in, back/forward, views 1–9. All go through the same command dispatcher as URL commands. |
| **Settings GUI** | Complaint #10. Pane's audience is not AeroSpace's | MEDIUM | SwiftUI. Hotkeys, gaps, exclusions, gestures, Mission Control takeover toggle, Screen Recording status. |
| **Launch at login, signed + notarised build, auto-update, Homebrew cask** | AeroSpace's lack of notarisation is a known hurdle. Rectangle, Loop and OmniWM are all notarised | LOW–MEDIUM | `SMAppService`, Sparkle with an EdDSA key, notarised DMG and a cask. |
| **Coexistence with conflicting macOS features** | macOS 15+ edge tiling, Stage Manager and "click wallpaper to reveal desktop" all react to the same drags and clicks | LOW | Detect the conflicting settings and offer to turn them off, with consent and restore-on-quit. Warn if another WM is running (OmniWM checks for a list of 13). |
| **Layout persistence across Pane restarts** | Paneru and OmniWM ship session restore. Users expect their arrangement to survive a relaunch | MEDIUM–HIGH | The model is Codable. The hard part is re-matching windows after an app or reboot relaunch, because window IDs change. Match by bundle ID, then title, then order (Moom's documented approach), and send unmatched windows to the Desktop tile. |
| **URL scheme for automation** (`pane://…`) | Rectangle, Rectangle Pro, Loop, Moom, BTT and Hammerspoon all expose URL or AppleScript commands. Raycast and Alfred users expect this | LOW | Thin layer over the command bus. Rated table stakes for the power-user slice of the audience, but cheap. Also add `pane://unpark-all`. |

### Differentiators (Competitive Advantage)

These line up with Pane's core value. Each was checked against the competitor set.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Drag-to-dock nested tiling with a live drop preview** | The main gap in the market. Snap tools are mouse-driven but stateless (fixed halves and quarters). Tilers keep state but are keyboard- and config-driven. yabai has modifier-drag drop zones (outer 25% of the target warps toward that edge, centre 50% swaps or stacks), with no GUI and SIP-dependent extras. Nobody on macOS offers drag-a-title-bar-to-split-any-tile with a preview | HIGH | Detect a title-bar drag through AX moved events plus mouse state. Hit-test the cursor against the tile tree: the screen edge docks at the root, a tile's edge band splits that tile, the tile centre makes a tab group. Draw the preview in a borderless overlay. Add a modifier to bypass docking. Recommendation: start from yabai's proven geometry (edge bands about 25% of the target, centre about 50%) and tune it. |
| **Floating "Desktop" tile** (floating windows live in a defined layer or region of the tree) | Answers AeroSpace's popular "sticky floating windows" request (open since 2023, 36 comments) and the "floating windows disappear" bugs. Floating gets a defined home instead of being outside the model | MEDIUM | A `Desktop layer node` in the model. New and unclassified windows land here (see Anti-Features: no auto-tiling). |
| **Zoom-out camera over all windows** ("see everything", step in/out a level, rectangle zoom) | No macOS WM has this. The closest are Niri's Linux overview, OmniWM's overview and rift's niri-style mission control. Users ask to "show the current tree" and for an overview of spaces side by side | VERY HIGH | Snapshot-overlay technique (PLAN.md). The hardest phase. When Screen Recording is denied, fall back to app colour plus icon. Animate only the overlay, never the real windows. |
| **Back/forward view history** | Browser-like navigation. Nobody in the WM space has it | LOW (once the camera exists) | Stack of camera targets (node IDs, not pixel rects, so history survives reflows). |
| **Trackpad gestures** (modifier-pinch/pan anywhere, pinch on bare desktop) | Paneru and rift have swipe-between-windows. Niri has four-finger overview. Nobody on macOS has pinch-to-zoom over windows | HIGH | Private MultitouchSupport. Must not leak gestures to the window under the cursor (Paneru issue "gesture … also sends two-finger gestures to the window"). |
| **Tab groups for any app** (drop on a tile's centre) | Tack (paid, $40) is the only third-party "tabs for any app" tool found. yabai stacks and AeroSpace accordion are the keyboard equivalents and have no visible tab strip. A visible tab strip plus group traffic lights is unique among free tools | HIGH | Overlay panel follows the active window. Hide inactive members by parking them. Interacts with native-tab detection (table stakes). |
| **Saved views 1–9** | Rectangle Pro, Moom and Amethyst save window layouts. Pane saves a camera position, not just frames, which is a new idea | LOW–MEDIUM | A view is (display, camera target node, zoom). Persist it. Must survive display changes (fall back to "everything"). |
| **Overview of all displays with a Spaces bar, as an optional Mission Control replacement** | Mission Control is close to useless with tilers that hide windows (AeroSpace guide). rift and OmniWM built their own overviews. Users want a unified overview | HIGH | Read-only SkyLight Spaces query. The takeover needs an event tap plus symbolic hotkey disabling, so it is **opt-in** and must restore the system hotkeys on quit or crash. |
| **Undo last layout change** | No competitor found offers it. Cheap because the model is serialisable and pure | LOW | Keep a ring buffer of tree snapshots. Recovers from mis-drops, the most likely mouse-first error. Recommended addition to v1 because it makes drag-to-dock forgiving. |
| **Type-to-jump in overview** | Phantomat (Linux) offers it. Fast navigation once there are many windows | MEDIUM | Filter snapshots by app or title. Needs AX titles. v1.x. |
| **Intel + Apple Silicon, macOS 14+** | OmniWM is Apple Silicon and macOS 26+ only | LOW | Already in the constraints. Gives a minor reach advantage. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Auto-tiling every new window** (BSP/dwindle insert on open) | i3, yabai and Amethyst habit. AeroSpace users request dynamic tiling | Conflicts with Pane's "you place it" model. Every new dialog, Electron splash and helper window reshuffles the layout. Paneru markets the opposite ("opening a new window will never cause existing windows to resize") | New windows land on the Desktop tile, or reopen in their remembered slot. Optional per-app "auto-dock into tile X" rules later. |
| **Moving windows between native Spaces** | Amethyst and yabai users want throw-to-space | Broke repeatedly (Amethyst's top issues after 14.5). Reliable versions need SIP disabled | The Spaces bar is read-only. Navigate Spaces, don't manage them. |
| **Scaling or animating real windows** (live zoom, animated moves) | Looks great in Hyprland and Niri demos | No public API scales other apps' windows. Animating via repeated AX set-frame is janky and slow (PaperWM "laggy … unless animations are turned off"). yabai needs SIP for it | Animate only the snapshot overlay, then move real windows once when the camera settles. |
| **Window borders and focus rings drawn around other apps' windows** | Popular ricing request (yabai thread on removing borders, 49 comments) | AeroSpace explicitly refuses it. It means tracking overlays per window and causes lag and z-order bugs | The tab strip and drop preview are Pane's only per-window overlays. Point users to JankyBorders. |
| **Text-config DSL or embedded scripting (Lua) as the main interface** | Power users from AeroSpace and Paneru | Splits the audience. Pane's opening is GUI and mouse | GUI Settings plus a JSON settings file that can be exported and imported (dotfile friendly), plus URL commands. No scripting runtime. |
| **Focus-follows-mouse / mouse-follows-focus** | Very common request (AeroSpace 19 upvotes, Amethyst, PaperWM) | Fights a mouse-first, zoomable UI: hovering during a pan would steal focus | Defer. Revisit after v1 as an opt-in. |
| **Scrolling/Niri column layout as a second layout engine** | Strong trend (AeroSpace 19 upvotes, rift, OmniWM, Paneru) | Doubles the model and engine surface. The camera already provides "infinite space" | Don't add a second layout type. The zoom camera covers the "more room than the screen" need. |
| **Replacing Cmd-Tab or app switchers, status bars, sketchybar integration** | Common in ricing setups | Scope creep with mature alternatives (AltTab, sketchybar) | URL commands plus a simple event hook later, if anyone asks. |
| **Mission Control takeover on by default** | "Replace Mission Control" sounds like a headline feature | Takes system hotkeys and gestures. If Pane crashes with the takeover active, the user loses Mission Control | Opt-in toggle, plus a watchdog that restores symbolic hotkeys on next launch. |
| **Mac App Store build, licences, trials, window limits** | Distribution reach | Private APIs block the App Store. Licensing is out of scope (PROJECT.md) | Notarised DMG, Homebrew cask, Sparkle. |
| **AI features** (OmniWM ships AI issue rewriting) | Trend | No user value for a WM | None. |

---

## Feature Dependencies

```
PaneModel: layout tree (split/panel/group/desktop, weights, min sizes, Codable)
    └──required by──> everything below

Window control (AX tracking, IDs, set-frame, per-app queues, classifier, exclusions)
    └──requires──> PaneModel
    └──required by──> Drag-to-dock, Float/Desktop tile, Reflow, Gaps/resize

Command bus (one dispatcher for hotkeys, menu, URL scheme, gestures)
    └──required by──> Keyboard commands, URL commands, Saved views, Undo

Drag-to-dock (drag detection + hit-test + drop preview overlay)
    └──requires──> Window control, PaneModel insert-at-edge
    └──required by──> Tab groups (the centre drop zone reuses the hit-test)
    └──conflicts──> macOS 15+ edge tiling / Option-drag tiling (must be disabled or detected)

Window parking (move off-view, shrink, restore) + Restore-on-quit/crash
    └──requires──> Window control
    └──required by──> Zoom camera (off-view windows), Tab groups (hidden tabs)

Snapshot service (ScreenCaptureKit, optional; colour+icon fallback)
    └──required by──> Zoom camera, Overview, Type-to-jump

Zoom camera (overlay stage, camera curve, settle → AX resize)
    └──requires──> Snapshot service, Window parking, PaneModel rect calc
    └──required by──> Step in/out, Rectangle zoom, Back/forward history, Saved views, Gestures

Trackpad gestures (MultitouchSupport) ──enhances──> Zoom camera
Overview + Spaces bar (SkyLight read) ──requires──> Snapshot service, Multi-display state
Mission Control takeover ──requires──> Overview, event tap, symbolic-hotkey control
    └──conflicts──> native Mission Control / "Displays have separate Spaces" off

Native-tab detection ──required by──> Tab groups (otherwise the two tab systems fight)
Multi-display state (keyed by UUID) ──required by──> Saved views, Overview, Persistence
Undo ──requires──> Codable model snapshots + command bus
Native fullscreen ──conflicts──> tiling (must temporarily leave the tree)
Stage Manager ──conflicts──> everything (detect and offer to disable)
```

### Dependency Notes

- **Command bus before the first hotkey.** Hotkeys, menu items, URL commands, gestures and saved views all run the same operations. Building the bus in the tiling MVP means URL commands later cost about a day, not a refactor.
- **Window parking is shared infrastructure.** The zoom camera (off-view windows) and tab groups (inactive tabs) both rely on it, and it is the main cause of the "lost windows" complaint. Build it with restore-on-quit, crash recovery and panic unpark before either feature depends on it.
- **Tab groups need native-tab detection first.** Otherwise Finder, Terminal, Safari and Ghostty tabs appear as separate windows and get docked into Pane groups. That is the longest-standing open bug in both yabai and AeroSpace.
- **Drag-to-dock conflicts with macOS 15+ native tiling.** Both respond to dragging toward a screen edge. Onboarding must detect "Tile by dragging windows to screen edges" and offer to turn it off before drag-to-dock is enabled.
- **Saved views depend on the camera and on stable multi-display identity.** A view saved on an external display must degrade predictably when that display is absent.
- **The Mission Control takeover depends on the overview and its crash recovery.** It must not ship before the "restore system hotkeys on next launch" watchdog.

---

## MVP Definition

PROJECT.md says v1 = all nine phases. This is the order in which features become *usable*, with gates. The test is the Core Value: docking must work even if zoom and tabs don't.

### Launch With (v1). The first usable release (PLAN Phases 1–3) must include:

- [ ] Layout tree with insert/remove/reweigh/min sizes, Codable. The foundation.
- [ ] Reliable tracking with reconciliation, per-app AX queues and timeouts. Complaints #2 and #3.
- [ ] Window classifier (dialogs/PiP float) and per-app exclusion list. Complaint #6.
- [ ] Native-tab detection, treated as one window. Complaint #4, and cheap to do early.
- [ ] Drag-to-dock with drop preview, screen-edge and tile-edge zones, bypass modifier. The core value.
- [ ] Reflow on close, gaps, drag-divider resize, min-size handling. The core value.
- [ ] Green button dock/float, Desktop tile for floating windows. The core value.
- [ ] Undo last layout change. Makes mouse docking forgiving, and cheap.
- [ ] Menu bar with pause, "bring all windows on-screen", restore on quit/crash. Trust.
- [ ] Command bus plus a minimal keyboard command set. Foundation for later phases.
- [ ] Multi-display state keyed by display UUID, sleep/wake handling. Complaint #5. Do it before the camera, not after.

### Rest of v1 (PLAN Phases 4–9)

- [ ] Zoom camera, step/rect zoom, back/forward. The headline differentiator.
- [ ] Gestures. Gate: camera stable, gestures not leaking to apps.
- [ ] Overview + Spaces bar, opt-in Mission Control takeover. Gate: hotkey-restore watchdog in place.
- [ ] Tab groups. Gate: native-tab detection proven.
- [ ] Saved views 1–9, `pane://` URL commands. Cheap on top of the command bus and camera.
- [ ] Layout persistence across restarts with window re-matching.
- [ ] Settings GUI, onboarding (including conflict detection), Sparkle, notarisation, cask.

### Add After Validation (v1.x)

- [ ] Type-to-jump search in the overview. Add once users have many windows.
- [ ] Per-app "auto-dock into slot" rules. Add if users complain about re-docking after relaunch.
- [ ] Settings export/import (JSON). Add when dotfile users show up.
- [ ] Max tile width / ultrawide handling. Add if ultrawide users report problems (AeroSpace's top-voted idea).

### Future Consideration (v2+)

- [ ] Focus-follows-mouse (opt-in). Conflicts with the camera interaction model.
- [ ] Event hooks for bars and scripts. Wait for demand.
- [ ] Per-Space trees, if per-display state proves insufficient (open question in PROJECT.md).

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Reliable tracking + reconciliation | HIGH | HIGH | P1 |
| Non-blocking AX (per-app queues/timeouts) | HIGH | MEDIUM | P1 |
| Drag-to-dock + drop preview | HIGH | HIGH | P1 |
| Reflow, gaps, divider resize, min sizes | HIGH | MEDIUM | P1 |
| Float / Desktop tile, green button | HIGH | MEDIUM | P1 |
| Window classifier + exclusions | HIGH | MEDIUM | P1 |
| Native-tab detection | HIGH | MEDIUM | P1 |
| Restore-on-quit / panic unpark | HIGH | LOW | P1 |
| Multi-display + sleep/wake | HIGH | HIGH | P1 |
| Undo last layout change | MEDIUM | LOW | P1 |
| Command bus + keyboard commands | MEDIUM | LOW | P1 |
| Zoom camera (out/in/rect, history) | HIGH (differentiator) | VERY HIGH | P1 (v1 scope per PROJECT.md) |
| Trackpad gestures | MEDIUM | HIGH | P2 |
| Overview + Spaces bar | MEDIUM | HIGH | P2 |
| Mission Control takeover (opt-in) | LOW–MEDIUM | MEDIUM | P2 |
| Tab groups | MEDIUM | HIGH | P2 |
| Saved views 1–9 | MEDIUM | LOW | P2 |
| URL commands | MEDIUM | LOW | P2 |
| Layout persistence across restarts | HIGH | MEDIUM–HIGH | P2 |
| Settings GUI, onboarding, Sparkle, notarisation, cask | HIGH | MEDIUM | P1 for release |
| Type-to-jump in overview | MEDIUM | MEDIUM | P3 |
| Focus-follows-mouse | LOW for this audience | LOW | P3 |

**Priority key:** P1 must have for launch. P2 is in v1 scope (PROJECT.md), but may slip without breaking the core value. P3 is v1.x or later.

---

## Competitor Feature Analysis

| Feature | AeroSpace | yabai | Amethyst | Rectangle / Loop | Paneru / rift / OmniWM | macOS 15+ native | **Pane** |
|---|---|---|---|---|---|---|---|
| Layout model | i3 tree, tiles/accordion | BSP + stack + float | xmonad auto layouts | None (stateless snaps) | Scrolling strip; rift/OmniWM add BSP/dwindle | None (halves/quarters) | **Nested split tree + Desktop float + groups** |
| Primary input | Keyboard + text config | Keyboard + CLI (skhd) | Keyboard | Shortcuts; Loop: trigger-key + cursor radial | Keyboard + swipe | Drag to edge, Option-drag, green-button menu | **Drag + trackpad pinch, hotkeys secondary** |
| Mouse drag to place | Basic mouse move/resize of tiled windows (not verified in this research); no drop preview found | Modifier-drag; edge 25% warp, centre swap/stack | Swap by drag | Snap to edge/corner zones | rift: drag in overview | Edge/corner | **Drag title bar into any tile edge or centre, with preview** |
| GUI settings | Never (by design) | No | Yes | Yes | OmniWM yes; others config | Yes | **Yes** |
| Workspaces | Emulated, windows hidden in corner | Native Spaces (SIP for full control) | Native Spaces | n/a | Native per display + virtual rows | Native | **Read-only Spaces; camera replaces workspaces** |
| Overview | None (Mission Control degraded) | None | None | None | rift niri-style MC; OmniWM Overview with zoom | Mission Control | **Zoom camera + Overview + opt-in MC replacement** |
| Tabs for any app | Accordion (no tab strip) | Stack (no strip) | No | No | Stacks/columns | Native app tabs only | **Tab groups with visible strip + group traffic lights** |
| Saved layouts | No | Scripts | Yes (save workspace) | Rectangle Pro layouts | Paneru session restore; rift save/restore | No | **Saved camera views 1–9 + persisted tree** |
| Automation | CLI | CLI + signals | Limited | URL scheme | CLI/IPC, Lua (Paneru) | Shortcuts | **`pane://` URL commands** |
| SIP required | Never | For Spaces/animation extras | No | No | No | n/a | **Never** |
| Private APIs | Only `_AXUIElementGetWindow` | Many (SkyLight + SA) | Few | None | rift/OmniWM: several | n/a | `_AXUIElementGetWindow`, SkyLight read, MultitouchSupport, CoreDock, each isolated with a fallback |
| Native tabs | Broken (#68 open) | Broken (open since 2019) | n/a | n/a | rift and Paneru claim support | n/a | **Detect and treat as one window (P1)** |
| Notarised | No | No (Homebrew) | Yes | Yes | OmniWM yes | n/a | **Yes** |
| Platform | macOS 13+ | Intel + AS | Intel + AS | Intel + AS | OmniWM: AS + macOS 26+ only | macOS 15+ | **macOS 14+, Intel + AS** |

---

## Open design questions surfaced by this research (to answer in the phase discussion, not here)

1. **Where do new windows go?** Recommendation: the Desktop tile. Alternatively, the remembered slot if one exists. Never auto-split.
2. **Default drag behaviour.** Should docking happen on every title-bar drag (with a bypass modifier) or only while a modifier is held? macOS 15 uses "Option-drag to tile", so users already know a modifier-gated version. Recommendation: dock by default with a visible preview and a hover delay, plus a bypass modifier, then validate in UAT.
3. **Minimise and Hide.** Should they keep the slot or collapse it? Recommendation: keep it (as a placeholder) for Hide, and collapse for Minimise.
4. **Per-display vs per-Space tree.** This research supports per-display as the primary key. Every competitor that relies on native Spaces has suffered from it.

---

## Sources

Primary data (GitHub API, queried 2026-10-23: repo metadata, issues sorted by comments, discussions sorted by comments and upvotes):
- AeroSpace: https://github.com/nikitabobko/AeroSpace (README roadmap, guide https://nikitabobko.github.io/AeroSpace/guide, discussions)
- yabai: https://github.com/asmvik/yabai (issues; config wiki https://github.com/asmvik/yabai/wiki/Configuration for mouse drop zones)
- Amethyst: https://github.com/ianyh/Amethyst
- Rectangle: https://github.com/rxhanson/Rectangle; Rectangle Pro docs https://rectangleapp.com/pro/docs/layouts/
- Loop: https://github.com/mrkai77/Loop; feature comparison https://mintlify.wiki/mrkai77/loop/comparison (self-described as possibly outdated, LOW)
- Paneru: https://github.com/karinushka/paneru
- rift: https://github.com/acsandmann/rift
- OmniWM: https://github.com/OmniNull/OmniWM; known limitations https://omniwm.app/help/known-limitations/
- PaperWM.spoon: https://github.com/mogenson/PaperWM.spoon

Secondary (WebSearch, MEDIUM/LOW):
- Niri overview (25.05): https://github.com/niri-wm/niri/wiki/Overview, https://www.phoronix.com/news/Niri-25.05-Released
- Linux canvas WMs: https://github.com/malbiruk/driftwm, https://github.com/kaolti/phantomat/wiki
- macOS Sequoia native tiling: https://macmost.com/window-tiling-in-macos-sequoia.html, https://www.computerworld.com/article/3550352/how-to-use-window-tiling-with-macos-sequoia.html
- Ghostty on tiling WMs and native tabs: https://ghostty.org/docs/help/macos-tiling-wms
- HN thread on macOS tiling pain points (Omacosy): https://hn.svelte.dev/item/49374830
- Tabs-for-any-app prior art (Tack): https://alternativeto.net/software/tack-window-tabs/about/
- Moom saved layouts / display adaptation: https://manytricks.com/moom/

---
*Feature research for: macOS zoomable nested-tiling window manager (Pane)*
*Researched: 2026-10-23*
