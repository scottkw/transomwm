# Transom

## What This Is

Transom is a free, open-source (MIT) macOS window manager. Docked windows never overlap: they sit in nested tiles that fill the screen on a zoomable "desk", so you can zoom out to see everything and zoom in to whatever you need. Windows you don't dock float on top like normal macOS windows. It is a clean-room reimplementation of the ideas in the commercial app TrellisWM. v0.9.0, the first public release, shipped on 2026-11-07 as a Developer ID signed and notarised DMG on GitHub Releases.

## Core Value

Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, this must still work.

## Requirements

### Validated

- ✓ Pure-Swift layout model: nested split tree with weights, panels, tab groups and a floating Desktop; insert at an edge, remove, resize, minimum sizes; serialisable — Phase 1 (141 tests, debug + release)
- ✓ Accessibility-based window control: permission flow, window tracking (incl. native tab groups), move/resize, per-app exclusion list — Phase 2 (UAT 17/18 in the Tart VM; multi-display deferred)
- ✓ Drag-to-dock tiling with drop preview, reflow on close, gaps, drag-gap resize, green button docks/floats, crash-safe restore — Phase 3 (925 headless tests, VM UAT; second-display re-check deferred to the first Transom build)

- ✓ Zoom camera: snapshot overlay (colour + icon fallback without Screen Recording), zoom out, step in/out, rectangle zoom, back/forward history, hotkeys — v0.9.0 (Phase 4)
- ✓ Trackpad gestures: ⌥-pinch/pan anywhere, pinch on bare desktop — v0.9.0 (Phase 5; hardware re-checks for GEST-04 still open)
- ✓ Overview of all windows with a Spaces bar, opt-in Mission Control takeover, per-display/per-Space layouts — v0.9.0 (Phase 6; four-finger swipe stays with macOS; multi-display hardware checks deferred)
- ✓ Tab groups: drop onto the middle of a window to group; tab strip with group-wide buttons — v0.9.0 (Phase 7; live UAT pending)
- ✓ Saved views 1–9, `transom://` URL commands and a CLI; layouts restored across restarts — v0.9.0 (Phase 8)
- ✓ Window behaviour options: auto-tile or float new windows; automatic or key-held docking regions — v0.9.0 (Phase 8.1)
- ✓ No Desktop tile: docked windows fill the screen, floaters sit on top — v0.9.0 (Phase 8.1.1)
- ✓ Settings, onboarding, launch at login, GitHub Releases update check, signed and notarised DMG — v0.9.0 (Phase 9; on-screen items not yet seen by a person, D-29)

### Active

Next milestone not yet defined. Carried forward from v0.9.0 (see `.planning/milestones/v0.9.0-MILESTONE-AUDIT.md`):

- [ ] Homebrew cask (SHIP-05, deferred by D-26)
- [ ] Hands-on check of the 0.9.0 on-screen items (Settings, onboarding, DMG first open, menu-bar glyphs, update dot, launch at next login); fixes go into 0.9.1
- [ ] Multi-display and trackpad-reconnect hardware checks (Phases 2, 3, 5, 6)

### Out of Scope

- Licensing, trials, paid tiers, window limits — everything is free
- Mac App Store distribution — private APIs (SkyLight, MultitouchSupport) are required
- Features needing SIP disabled (window transforms, scripting additions) — keeps install simple and safe
- Copying any TrellisWM text, assets, lesson pages, settings values or code — clean-room rule
- Windows/Linux — macOS-only APIs throughout
- Taking over the four-finger Spaces swipe — it stays with macOS (user decision 2026-10-31, OVER-02 amended)
- A Desktop tile for floating windows — removed in Phase 8.1.1; floaters behave like normal macOS windows

## Context

- Feature spec comes from a static REA analysis of `TrellisWM-0.9.8.dmg`; see `PLAN.md` (sections 1–5). That analysis used only metadata, symbol names, strings and imports, with no decompilation.
- The shipped app splits into a pure layout model, a behaviour engine and an AppKit layer; Transom mirrors this as `TransomModel`, `TransomEngine` and `Transom.app`.
- Inferred zoom technique (not observed at runtime): a full-screen overlay draws ScreenCaptureKit snapshots; when the camera settles, real windows are resized via AX and off-view windows are parked small.
- Prior art to study (MIT): AeroSpace (closest match), Amethyst, yabai (non-SIP parts), OpenMultitouchSupport.
- Open questions: drop-zone geometry, per-Space vs per-display layout state, camera curve. Transom picks its own values.
- State after v0.9.0 (2026-11-08): about 35,700 lines of Swift in `Sources` and 78,400 including tests; 11 phases, 162 plans, about 1,000 tests. Released at https://github.com/scottkw/transomwm/releases/tag/v0.9.0.
- Known debt (full list in the v0.9.0 audit): on-screen items never seen by a person (D-29), hardware-deferred multi-display checks, flaky live tests (FreezeTest, CloseIntegration two-source, Overview Esc miss, the macOS 27.2 Overview helper exit D-24), about 1,250 `swift format --strict` findings, CI disabled since 2026-10-28.
- User feedback: Transom felt complicated; prefer plain macOS behaviour (led to removing the Desktop tile).

## Constraints

- **Platform**: macOS 14+, Apple Silicon and Intel — matches the reference app's floor and keeps ScreenCaptureKit available
- **Tech stack**: Swift + Swift Package Manager; AppKit for overlays; SwiftUI acceptable for Settings
- **Testability**: `TransomModel` and `TransomEngine` must not import AppKit, so they can be unit-tested headless
- **Private APIs**: each one (`_AXUIElementGetWindow`, SkyLight, MultitouchSupport, CoreDock) isolated in one file with a fallback; they can break on any macOS update
- **Legal**: clean room — implementers work from the spec and public prior art, never from the binary
- **License**: MIT

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Name "Pane" → "Transom" | "Pane" is taken by several Mac window managers. Renamed after Phase 3: app Transom (`com.eightabyte.transom`, `transom://`), repo and folder `transomwm`, domain transomwm.app; no data migration (never shipped) | ✓ Decided 2026-10-27 |
| MIT license | Matches AeroSpace/Amethyst/yabai ecosystem | ✓ Good (shipped v0.9.0) |
| v1 = all 9 phases | User wants full feature parity for public release | ✓ Good (shipped as v0.9.0 with 8.1 and 8.1.1 inserted) |
| Model / Engine / App layering | Mirrors the reference app's proven split; makes core logic testable | ✓ Good |
| Snapshot-overlay zoom, no SIP | Only way to "zoom" other apps' windows without disabling SIP | ✓ Good (Phase 4) |
| Model / Engine / App layering | TransomModel is Foundation-only; enforced by `scripts/check-no-appkit.sh` inside `swift test` | ✓ Good (Phase 1) |
| Undo covers user edits only | OS lifecycle reports go through `World.apply`, off the undo stack; a confirmed close purges the window from history | ✓ Good (Phase 1 review) |
| `World.undo` returns restored windows | Model can't know OS state for windows on no desk; the engine re-reports them | ✓ Good (honoured by 02-04) |
| Unfit windows reported, never overlapped | Water-filling resolve pins minimums; windows that can't fit get no rect | ✓ Good (Phase 1) |
| GitHub Releases update check instead of Sparkle | User wants the same updater as gifsmith: latest-release check with ETag, notify, Settings toggle + Check for Updates button, sha256 + Team ID verified DMG. Drops the Sparkle dependency; no in-place relaunch | ✓ Good (shipped in Phase 9) |
| Dock at a tile's exact centre goes left | A plain green click on a floater filling the Desktop tile must dock, not beep (quick 261027-gqo) | ✓ Good (Phase 3) |
| Every refusal and notice is logged | Toasts and VoiceOver lines are invisible over VNC; the log makes VM runs checkable | ✓ Good (Phase 3) |
| Clean-room docs scrub | TrellisWM internal names removed from PLAN.md and research docs | ✓ Good |
| Remove the Desktop tile (8.1.1) | Users found it complicated; docked windows fill the screen and floaters act like normal windows | ✓ Good |
| New windows float unless the user opts in (8.1) | Auto-tiling by default is a top frustration with other tiling WMs | ✓ Good |
| Ship 0.9.0 with on-screen UAT recorded as not seen (D-29) | Release first; anything found in use goes into 0.9.1 | ⚠️ Revisit |
| Defer the Homebrew cask (D-26) | Not needed for the first GitHub release | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-11-08 after v0.9.0 milestone*
