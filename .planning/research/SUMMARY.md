# Project Research Summary

**Project:** Pane
**Domain:** macOS zoomable nested-tiling window manager (menu-bar agent app, non-sandboxed, private APIs isolated behind dlsym, distributed outside the Mac App Store)
**Researched:** 2026-10-23
**Confidence:** MEDIUM (HIGH on toolchain/distribution/prior-art behavior; MEDIUM/LOW on the zoom stage, gestures, and private-API behavior)

## Executive Summary

Pane occupies an empty niche on macOS: snap tools (Rectangle, Loop, macOS 15 tiling) are mouse-driven but stateless, tree tilers (AeroSpace, yabai, Amethyst) are stateful but keyboard/config-driven, and no maintained macOS WM has a zoom-out camera. Experts build this class of app as a pure layout model + per-app-threaded Accessibility (AX) control with messaging timeouts + desired-vs-observed reconciliation (frame read-back, echo suppression) + every private API loaded via `dlsym` with a fallback. AeroSpace is the closest structural template (SPM library targets + thin XcodeGen app bundle), Loop the best dlsym-loader pattern (GPL — read, don't copy), Rectangle/Amethyst the distribution path (notarized + Sparkle + Homebrew cask).

The recommended approach is Swift 6 in a single `Package.swift` with four targets — `PaneModel` → `PaneEngine` → `PaneMac` + `PanePrivate` — with only two runtime dependencies (Sparkle 2.10.0, KeyboardShortcuts 3.1.0). The engine sits behind an async `WindowSystem` protocol with a `FakeWindowSystem` so most behavior is headless-testable. The layout model is a flat, value-typed tree with fractional weights, keyed by `DeskKey(displayUUID, spaceID?)`. Zoom is an illusion: a full-screen Core Animation overlay of ScreenCaptureKit snapshots animates, and real windows get exactly one AX write when the camera settles. Tiling must work with the stage disabled, so the Core Value holds by construction.

The dominant risks are all documented in competitors' issue trackers: AX calls blocking on hung apps (AeroSpace needed a year-long rewrite), "AX can't see it" misread as "closed" (lock screen, Spaces, timeouts → destroyed layouts), windows stranded tiny/off-screen after a crash (amplified by Pane's parking design), annual macOS breakage of private APIs, and TCC grant resets from signing changes. Every one has a known mitigation, but most must be designed into Phases 1–2 — they cannot be retrofitted. The highest-uncertainty item is the Phase 4 zoom stage (settle latency, resize storms, terminal re-wrap, WindowServer memory growth from snapshot churn), which needs a feasibility spike.

## Key Findings

### Recommended Stack

See STACK.md. The prescriptive structure is AeroSpace's: real code in SPM targets, XcodeGen only to produce the `.app` (signing, entitlements, Sparkle embed, notarization). System frameworks directly, with small in-house wrappers — third-party AX/MT wrappers are stale or unsuitable.

**Core technologies:**
- **Swift 6 language mode, `swift-tools-version: 6.2`, `.macOS(.v14)`, Swift Testing** — 6.2 is the floor for `.defaultIsolation(MainActor.self)` and still builds on GitHub `macos-26` runners (Xcode 26.6); don't declare 6.4 until CI has Xcode 27.
- **SPM + XcodeGen 2.46.0** — no committed `.pbxproj`; `swift test` runs without TCC.
- **AppKit (NSPanel, NSStatusItem) + SwiftUI only inside NSHostingController** — not the SwiftUI `App`/`Settings`/`MenuBarExtra` shell, which is fragile for LSUIElement apps.
- **Accessibility API (AXUIElement/AXObserver/SetMessagingTimeout)** — the only way to move other apps' windows.
- **ScreenCaptureKit `SCScreenshotManager` (14.0)** — `CGWindowListCreateImage` is unavailable at deployment target ≥15; capture at on-stage size, not native.
- **Core Animation + `NSView.displayLink`/`CADisplayLink` (14.0)** for the stage; Metal only if Instruments proves CA insufficient.
- **CGEventTap** (one active session tap, own thread, re-enable on timeout); **SMAppService.mainApp** for login; **Sparkle 2.10.0**; **KeyboardShortcuts 3.1.0**.
- **Private APIs via `dlopen`/`dlsym` into optional function pointers** — `_AXUIElementGetWindow`, SkyLight SLS*, MultitouchSupport, symbolic hotkeys, CoreDock — all verified resolving on macOS 27.0.1. Never link-time: a missing symbol must degrade a feature, not kill launch.
- **Developer ID + hardened runtime + notarized + stapled, no sandbox** — mandatory now that Homebrew rejects casks failing Gatekeeper; stable dev signing identity + separate debug bundle ID so TCC grants survive rebuilds.

Avoid: OpenMultitouchSupport 4.x (macOS 15 floor + binary blob; port its headers), AXSwift, Silica, HotKey, Loop code (GPL), CocoaPods, ad-hoc signing.

### Expected Features

See FEATURES.md. Evidence is competitors' most-commented issues; the central lesson is that **reliability features are the table stakes users uninstall over.**

**Must have (table stakes):**
- Reliable window tracking with reconciliation (no ghost/lost windows); non-blocking AX with per-app timeouts
- Classifier that floats dialogs/sheets/PiP/popovers + GUI per-app exclusion list
- Native-tab awareness (Finder/Terminal/Safari/Ghostty tabs = one window)
- Gaps, draggable dividers, reflow on close, min-size handling with no overlap
- Multi-display state keyed by display UUID, surviving sleep/wake and replug
- Graceful native-fullscreen handling (reserved slot)
- Restore-on-quit / crash recovery / "bring all windows on-screen"
- Non-looping permission onboarding; Screen Recording optional
- Menu bar with pause; command bus with keyboard commands
- Settings GUI, launch at login, signed/notarized build, Sparkle, Homebrew cask
- Detect conflicting macOS features (Sequoia edge tiling, Stage Manager, click-wallpaper-to-reveal)
- Layout persistence across restarts with window re-matching; `pane://` URL commands

**Should have (differentiators):**
- Drag-to-dock nested tiling with live drop preview — the core market gap (start from yabai's geometry: edge bands ~25%, center ~50%)
- Floating "Desktop" tile as a defined home for floats (answers AeroSpace's "sticky floating" ask)
- Zoom-out camera + step in/out + rectangle zoom + back/forward history (no macOS precedent)
- Trackpad ⌥-pinch/pan; tab groups for any app with a visible tab strip; saved camera views 1–9
- Overview with Spaces bar; opt-in Mission Control replacement
- **Undo last layout change** — not in PROJECT.md; recommended for v1 (cheap given the value-typed model, makes mouse docking forgiving)

**Anti-features (explicitly don't build):** auto-tiling new windows (they land on the Desktop tile), moving windows between native Spaces (needs SIP since 14.5), animating real windows, borders around other apps' windows, a scripting/config DSL as primary interface, a second scrolling/Niri layout engine, Mission Control takeover on by default.

**Defer (v1.x / v2+):** type-to-jump in overview, per-app auto-dock rules, settings export/import, ultrawide max width, focus-follows-mouse, event hooks, per-Space trees beyond DeskKey keying.

### Architecture Approach

See ARCHITECTURE.md. Strictly downward dependencies: App → Engine → Model. **PaneModel** is pure Codable/Sendable values: a flat `[NodeID: Node]` tree (`split | panel | tabs`), normalized fractional weights, a `DesktopLayer` per desk, and a min-size-aware water-filling `resolve()`. **PaneEngine** (no AppKit, MainActor) holds the Reconciler — which classifies every observed frame as echo / user drag / user resize / app refusal / close — and the Planner, which produces a `FramePlan` marking each window *live*, *parked*, or *represented*. **PaneMac** contains MacWindowSystem, per-app AX threads, InputHub, SnapshotService, overlays, and one-file-per-API private shims.

**Major components:**
1. **LayoutTree / Geometry / World (Model)** — tree edits, rect resolution with gaps + minimums, drop-zone hit-testing, desks keyed by `DeskKey`.
2. **Reconciler + Planner + Sessions (Engine)** — desired-vs-observed reconciliation, learned minimums, re-plan budget; drag/resize/rect-zoom sessions.
3. **Camera / Navigator (Engine)** — `{center, scale}` interpolated in log(scale) space (van Wijk & Nuij); targets are NodeIDs, so history and saved views survive reflows.
4. **WindowSystem / StageSink protocols** — the testability seam; `FakeWindowSystem` simulates refusing windows, slow apps, ID churn, lock-screen blanking.
5. **AXBackend** — one thread + CFRunLoop per pid; coalesced latest-wins `setFrame` in size→position→size order with `AXEnhancedUserInterface` toggled.
6. **StageOverlay + SnapshotService** — one non-activating NSPanel per display; freeze→cover→animate→settle→wait→reveal; color+icon placeholder as the same layer type.
7. **SpacesProvider / InputHub / Persistence** — read-only SkyLight; event tap + MT callbacks marshaled to MainActor; debounced atomic JSON with schema version.

**Expensive-to-change decisions that must be locked in Phase 1:** flat value tree + NodeID, fractional weights, `Node.tabs` case, DesktopLayer, `DeskKey(displayUUID, spaceID?)`, `WindowRef` with persisted match hints, window lifecycle states (absent ≠ removed), single top-left global coordinate space, schema version.

### Critical Pitfalls

See PITFALLS.md (25 pitfalls). Top five:

1. **Synchronous/shared-thread AX freezes the whole WM** — `WindowSystem` async from day one; per-app threads, per-app messaging timeout (~1 s), reactive merge that never awaits all apps; verify with a `kill -STOP` test.
2. **"AX can't see it" treated as "closed"** — explicit lifecycle states; closure needs two-source confirmation (invalid-element error + absence from CG/SkyLight list); a timeout never counts as closure; pause reconciliation across lock/sleep; notifications are only hints that trigger a cancellable full refresh.
3. **Parked windows stranded after crash/update** — persist home frames; synchronous restore on quit and before Sparkle relaunch; dirty-flag restore on next launch; "Restore all windows" menu item and `pane://restore`; park by moving, not shrinking.
4. **Private APIs break every year** — dlsym + capability flags + per-API crash canary + a public fallback for each; read-only Spaces; MT callback returns `int32_t` 0 (macOS 27 change); annual June–September beta checklist.
5. **Fighting app frames and zoom resize storms** — read back every write and learn minimums; per-window fight budget; animate only the overlay; at settle resize only changed + visible targets; capture before parking; capture budget + LRU; soak-test WindowServer memory.

Also critical: event-tap callbacks must do no AX work and need a re-enable watchdog; window classifier needs an AX-dump corpus test; lock bundle ID + signing identity early (never ad-hoc for releases); Mission Control takeover must restore symbolic hotkeys after a crash; coordinate conversion at one tested boundary with displays keyed by UUID and debounced reconfiguration.

## Implications for Roadmap

PROJECT.md fixes v1 = all 9 phases. Research supports keeping PLAN.md's 9-phase order but moving specific scope earlier: robustness and identity work into Phases 1–3 so the Core Value ships before any risky feature.

### Phase 1: Layout Model (PaneModel)
**Rationale:** Everything depends on it; several model decisions are a rewrite + migration if changed later.
**Delivers:** flat value tree (split/panel/tabs + DesktopLayer), edits (insert at edge, remove, reweigh, normalize, group), `validate()`, min-size water-filling `resolve()` with gaps, drop-zone hit-testing, `World`/`DeskKey(displayUUID, spaceID?)`, `WindowRef` with match hints, lifecycle states incl. reserved slots, Codable + schema version, undo snapshots, `WindowSystem` protocol draft.
**Addresses:** foundation for every feature.
**Avoids:** Pitfalls 2 (lifecycle states), 6 (constraint-aware solver), 8/14 (state keying, coordinate convention), 20 (persisted identity).
**Uses:** SPM, Swift Testing, Foundation only (CI grep forbids AppKit).

### Phase 2: Window Control (AXBackend + MacWindowSystem)
**Rationale:** The async seam must exist before any engine behavior; bundle ID/signing is decided where permissions are first requested.
**Delivers:** per-app AX threads + timeouts + unresponsiveness tracker; coalesced size→position→size writes with read-back; `_AXUIElementGetWindow` via the PanePrivate dlsym pattern + capability registry; reconciliation with lock/sleep guard; window classifier + AX-dump corpus harness; native-tab detection (at least treat tab siblings as one window); fullscreen state; coordinate conversion + display-UUID matching; AX permission probe with stale-grant UX; FakeWindowSystem; stable dev signing + separate debug bundle ID.
**Avoids:** Pitfalls 1, 2, 4 (pattern), 6, 7, 10, 11, 17.

### Phase 3: Tiling MVP (first usable release)
**Rationale:** The Core Value, built with an identity camera so it can't depend on the stage.
**Delivers:** drag-to-dock with drop preview (detected from frame deltas, not mouse-down hit-tests; bypass modifier; top-edge zone away from Mission Control), reflow, gaps, divider resize, green-button dock/float, Desktop tile, undo, event-tap wrapper + re-enable watchdog, menu bar with pause/restore-all, home frames + restore on quit/crash, command bus + minimal hotkeys, default exclusions, Sequoia edge-tiling detection, single-display correctness, **minimal signed + notarized pipeline** so testers' TCC grants stay stable.
**Avoids:** Pitfalls 3, 5, 12 (top-edge geometry), 15, 18.

### Phase 4: Zoom Camera + Stage
**Rationale:** The headline differentiator and the riskiest phase; needs a solid Reconciler and parking first.
**Delivers:** SnapshotService (SCK one-shot at on-stage size, LRU, color+icon fallback), StageOverlay per display, camera curve, zoom out to everything, step in/out, rect zoom, back/forward history, live/parked/represented FramePlan, adaptive redraw-wait, rebindable hotkeys via KeyboardShortcuts.
**Avoids:** Pitfalls 9 (soak test; settle < 500 ms with 15 windows), 10 (SCK fails soft), 3 (capture before park; crash restore), 16.

### Phase 5: Trackpad Gestures
**Rationale:** Feeds the Phase 4 camera API; needs a stable camera but not a polished overlay.
**Delivers:** own MultitouchSupport shim, ⌥-pinch/pan, pinch on bare desktop, magnify-event fallback, device re-enumeration on wake/hot-plug.
**Avoids:** Pitfall 13 (gestures leaking to the app under the pointer; `int32_t` return), Pitfall 4 (canary).

### Phase 6: Overview, Spaces & Multi-display
**Rationale:** Model keying already exists (Phase 1); this adds read-only SkyLight and full multi-display behavior.
**Delivers:** SpacesProvider with single-Space fallback, desks per Space (skip dirty desks while hidden), orphan/dormant desks on unplug re-attached by UUID, debounced reconfiguration, overview with Spaces bar, opt-in Mission Control takeover with restore watchdog, both "Displays have separate Spaces" modes tested.
**Avoids:** Pitfalls 8, 12, 14, 24.

### Phase 7: Tab Groups
**Rationale:** `Node.tabs` exists from Phase 1 and native-tab detection from Phase 2; adds `setHidden` and the TabStripPanel.
**Delivers:** drop on center to group, tab strip following the group leader (CG bounds polling), group-wide traffic lights, inactive tabs hidden by parking (never minimized).
**Avoids:** Pitfalls 7 (native tabs), 18, 19.

### Phase 8: Saved Views + URL Commands + Persistence Hardening
**Rationale:** Cheap on top of the command bus and NodeID camera targets.
**Delivers:** views 1–9 with layout-aware default chords, `pane://` with allow-list + rate limit, re-matching windows across restarts (score threshold, expiring placeholders).
**Avoids:** Pitfalls 16, 20, 21.

### Phase 9: Polish + Ship
**Delivers:** Settings GUI, onboarding (permissions, the monthly Screen Recording explanation, App Translocation check, disabling conflicting features with originals recorded), SMAppService, Sparkle with restore-home-frames before relaunch, CI designated-requirement check, own Homebrew tap → homebrew/cask, macOS-beta compatibility checklist.
**Avoids:** Pitfalls 3 (update path), 11, 25.

### Phase Ordering Rationale

- Dependency chain from FEATURES/ARCHITECTURE: Model → WindowSystem → Engine/tiling → parking + snapshots → camera → (gestures, overview, tabs, views). Window parking and the command bus are shared infrastructure and must be built before their dependents.
- Core-Value gate at Phase 3: tiling with the stage disabled is a hard acceptance criterion, so zoom failures can't block a usable product.
- Every retrofit-or-never decision (async AX, lifecycle states, DeskKey, coordinate space, bundle ID/signing) sits in Phases 1–2, per AeroSpace's rewrite lesson.
- Moved earlier than PLAN.md implies: display UUID/coordinate handling (6→2), native-tab detection (7→2), minimal notarized pipeline (9→3), edge-tiling detection (9→3).

### Research Flags

Phases likely to need `--research-phase` during planning:
- **Phase 4 (Zoom camera):** no prior art. Needs a feasibility spike: settle latency with Electron-heavy windows, terminal re-wrap, represented-state UX, SCK memory growth over hours, overlay window level vs. menus, CA performance with 100+ layers.
- **Phase 5 (Gestures):** whether a CGEventTap can see/consume magnify events (types 29/30) over other apps is unverified (LOW); MT callback struct layout and macOS 27 return semantics need a one-day spike comparing both paths.
- **Phase 6 (Spaces/Mission Control):** SkyLight signatures, Space-UUID stability across reboots/updates, and symbolic-hotkey state after a crash need verification with deliberate crash tests.
- **Phase 2 (Window control):** moderate. Patterns are documented (AeroSpace), but classifier corpus, native-tab heuristics and lifecycle confirmation rules need careful design.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Model):** pure Swift data structures, fully specified in ARCHITECTURE.md.
- **Phase 3 (Tiling MVP):** mostly specified; drop-zone geometry starts from yabai's numbers and is tuned in UAT.
- **Phase 8 (Views/URLs):** cheap on top of existing infrastructure.
- **Phase 9 (Ship):** Sparkle, notarization and Homebrew are well documented (Rectangle/Amethyst casks as models).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions from the GitHub releases API, availability from Apple doc JSON, local compile + dlsym verification on macOS 27.0.1. Private-API behavior and gesture input are MEDIUM/LOW. |
| Features | MEDIUM | Complaint ranking from primary GitHub issue data (MEDIUM-HIGH); macOS demand for a zoom canvas is inferred (LOW-MEDIUM). |
| Architecture | MEDIUM | Prior-art patterns verified against AeroSpace/yabai/Amethyst source (HIGH); Pane-specific designs (camera, water-filling, represented state, re-matching) have no prior-art validation (MEDIUM/LOW). |
| Pitfalls | MEDIUM-HIGH | Mostly maintainer comments cross-checked across projects; some single-report items (OMS #13, Homebrew date, final Screen Recording prompt behavior on 15.1+). |

**Overall confidence:** MEDIUM — the core tiling path is well understood; the zoom stage and gestures are where real uncertainty lives.

### Gaps to Address

- **Zoom-stage feasibility** (settle time, flicker, memory): Phase 4 spike with measurable criteria before building the full design.
- **Gesture input path:** Phase 5 spike, MT raw touch vs. event-tap magnify events.
- **⌥-hotkey restriction on macOS 15.0–15.1 — sources conflict:** STACK says it applies to all apps (fall back to ⌃⌥); PITFALLS says sandboxed apps only. Test on 15.0/15.1 if available; ship the ⌃⌥ fallback regardless, and check whether default chords type characters on non-US layouts (`UCKeyTranslate`).
- **Per-display vs. per-Space state:** research converged on `DeskKey(displayUUID, spaceID?)` with spaceID nil when SkyLight is unavailable; Space-UUID stability is unverified (test in Phase 6).
- **Open design questions for discuss-phase:** where new windows go (recommend: Desktop tile); dock on every drag with a bypass modifier vs. modifier-only (recommend: default + bypass, validate in UAT); minimize/hide semantics (recommend: Hide keeps slot, Minimize collapses); drop-zone geometry; camera curve.
- **`com.apple.WindowManager` key names** for edge tiling: LOW confidence; verify by reading back, with a System Settings deep-link fallback.
- **Name "Pane":** check for existing macOS apps with the name before release (pending decision in PROJECT.md).
- **Notarization with dlopen of private frameworks:** no library-validation exemption should be needed, but not re-verified against Apple docs; confirm in the Phase 3 minimal pipeline.

## Sources

### Primary (HIGH confidence)
- GitHub API releases and source (read 2026-10-23): AeroSpace (Package.swift, project.yml, MacApp.swift, refresh, axDumps, frozen tree), yabai (view/event_loop/space), Amethyst (Model/ScreenManager), Sparkle 2.10.0, KeyboardShortcuts 3.1.0, OpenMultitouchSupport 4.0.0, XcodeGen 2.46.0, Loop SkyLightSymbolLoader (pattern only, GPL)
- Competitor issue trackers ranked by comments/upvotes: AeroSpace #131, #445, #1615, #1216, #68, #66, #167; yabai #2240, #2500, #2634, #2822, #68, #36; Amethyst #1900, #1896, #1682; Rectangle #912, #1087; Loop #626, #745, #1159; AltTab #447, #4255
- Apple developer documentation JSON for API availability (SCScreenshotManager 14.0, CADisplayLink 14.0, SMAppService 13.0); docs.brew.sh Acceptable Casks
- Local verification on macOS 27.0.1 / Xcode 27.1: Swift Testing, CGWindowListCreateImage deprecation status, dlsym resolution of every private symbol

### Secondary (MEDIUM confidence)
- WWDC22 ScreenCaptureKit session (off-screen single-window capture)
- 9to5Mac / TidBITS / TechRadar on the monthly Screen Recording prompt
- Sparkle documentation; Homebrew 5.0 `--no-quarantine` deprecation (Workbrew)
- Apple Dev Forums / Eternal Storms on the 15.0–15.1 Option-hotkey restriction
- Niri overview, Ghostty tiling-WM docs, HN Omacosy thread

### Tertiary (LOW confidence)
- CGEventTap visibility of system gesture events (no conclusive source)
- `com.apple.WindowManager` edge-tiling key names
- van Wijk & Nuij camera curve (training knowledge)
- Homebrew Gatekeeper enforcement date 2026-09-01; OMS #13 macOS 27 callback behavior (single report)

---
*Research completed: 2026-10-23*
*Ready for roadmap: yes*
