# Transom

## What This Is

Transom is a free, open-source (MIT) macOS window manager where windows never overlap. They are docked into nested tiled spaces on a zoomable "desk": zoom out to see everything, zoom in to whatever you need. It is a clean-room reimplementation of the ideas in the commercial app TrellisWM, built for public release.

## Core Value

Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, this must still work.

## Requirements

### Validated

- ✓ Pure-Swift layout model: nested split tree with weights, panels, tab groups and a floating Desktop; insert at an edge, remove, resize, minimum sizes; serialisable — Phase 1 (141 tests, debug + release)
- ✓ Drag-to-dock tiling with drop preview, reflow on close, gaps, drag-gap resize, green button docks/floats, crash-safe restore — Phase 3 (925 headless tests, VM UAT; second-display re-check deferred to the first Transom build)

### Active

- [ ] Accessibility-based window control: permission flow, window tracking, move/resize, per-app exclusion list
- [ ] Zoom camera: overlay with window snapshots (colour + icon fallback without Screen Recording), zoom out to everything, step in/out a level, rectangle zoom, back/forward history, hotkeys
- [ ] Trackpad gestures: ⌥-pinch/pan anywhere, pinch on bare desktop
- [ ] Overview of all windows on all displays with a Spaces bar; optional Mission Control replacement; multi-display
- [ ] Tab groups: drop onto the middle of a window to group; tab strip overlay with group-wide traffic lights
- [ ] Saved views 1–9 and `transom://` URL commands
- [ ] Settings, onboarding, launch at login, update check against GitHub Releases (gifsmith-style), signed and notarised builds, Homebrew cask

### Out of Scope

- Licensing, trials, paid tiers, window limits — everything is free
- Mac App Store distribution — private APIs (SkyLight, MultitouchSupport) are required
- Features needing SIP disabled (window transforms, scripting additions) — keeps install simple and safe
- Copying any TrellisWM text, assets, lesson pages, settings values or code — clean-room rule
- Windows/Linux — macOS-only APIs throughout

## Context

- Feature spec comes from a static REA analysis of `TrellisWM-0.9.8.dmg`; see `PLAN.md` (sections 1–5). That analysis used only metadata, symbol names, strings and imports, with no decompilation.
- The shipped app splits into a pure layout model, a behaviour engine and an AppKit layer; Transom mirrors this as `TransomModel`, `TransomEngine` and `Transom.app`.
- Inferred zoom technique (not observed at runtime): a full-screen overlay draws ScreenCaptureKit snapshots; when the camera settles, real windows are resized via AX and off-view windows are parked small.
- Prior art to study (MIT): AeroSpace (closest match), Amethyst, yabai (non-SIP parts), OpenMultitouchSupport.
- Open questions: drop-zone geometry, per-Space vs per-display layout state, camera curve. Transom picks its own values.

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
| MIT license | Matches AeroSpace/Amethyst/yabai ecosystem | — Pending |
| v1 = all 9 phases | User wants full feature parity for public release | — Pending |
| Model / Engine / App layering | Mirrors the reference app's proven split; makes core logic testable | — Pending |
| Snapshot-overlay zoom, no SIP | Only way to "zoom" other apps' windows without disabling SIP | — Pending |
| Model / Engine / App layering | TransomModel is Foundation-only; enforced by `scripts/check-no-appkit.sh` inside `swift test` | ✓ Good (Phase 1) |
| Undo covers user edits only | OS lifecycle reports go through `World.apply`, off the undo stack; a confirmed close purges the window from history | ✓ Good (Phase 1 review) |
| `World.undo` returns restored windows | Model can't know OS state for windows on no desk; the engine re-reports them | — Pending (Phase 2 must honour) |
| Unfit windows reported, never overlapped | Water-filling resolve pins minimums; windows that can't fit get no rect | ✓ Good (Phase 1) |
| GitHub Releases update check instead of Sparkle | User wants the same updater as gifsmith: latest-release check with ETag, notify, Settings toggle + Check for Updates button, sha256 + Team ID verified DMG. Drops the Sparkle dependency; no in-place relaunch | — Pending (Phase 9, decided 2026-10-24) |
| Dock at a tile's exact centre goes left | A plain green click on a floater filling the Desktop tile must dock, not beep (quick 261027-gqo) | ✓ Good (Phase 3) |
| Every refusal and notice is logged | Toasts and VoiceOver lines are invisible over VNC; the log makes VM runs checkable | ✓ Good (Phase 3) |
| Clean-room docs scrub | TrellisWM internal names removed from PLAN.md and research docs | ✓ Good |

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
*Last updated: 2026-10-27 after Phase 3*
