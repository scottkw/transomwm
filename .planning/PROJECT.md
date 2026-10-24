# Pane

## What This Is

Pane is a free, open-source (MIT) macOS window manager where windows never overlap. They are docked into nested tiled spaces on a zoomable "desk": zoom out to see everything, zoom in to whatever you need. It is a clean-room reimplementation of the ideas in the commercial app TrellisWM, built for public release.

## Core Value

Windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, this must still work.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Pure-Swift layout model: nested split tree with weights, panels, tab groups and a floating Desktop; insert at an edge, remove, resize, minimum sizes; serialisable
- [ ] Accessibility-based window control: permission flow, window tracking, move/resize, per-app exclusion list
- [ ] Drag-to-dock tiling with drop preview, reflow on close, gaps, drag-gap resize, green button docks/floats
- [ ] Zoom camera: overlay with window snapshots (colour + icon fallback without Screen Recording), zoom out to everything, step in/out a level, rectangle zoom, back/forward history, hotkeys
- [ ] Trackpad gestures: ⌥-pinch/pan anywhere, pinch on bare desktop
- [ ] Overview of all windows on all displays with a Spaces bar; optional Mission Control replacement; multi-display
- [ ] Tab groups: drop onto the middle of a window to group; tab strip overlay with group-wide traffic lights
- [ ] Saved views 1–9 and `pane://` URL commands
- [ ] Settings, onboarding, launch at login, auto-update (Sparkle), signed and notarised builds, Homebrew cask

### Out of Scope

- Licensing, trials, paid tiers, window limits — everything is free
- Mac App Store distribution — private APIs (SkyLight, MultitouchSupport) are required
- Features needing SIP disabled (window transforms, scripting additions) — keeps install simple and safe
- Copying any TrellisWM text, assets, lesson pages, settings values or code — clean-room rule
- Windows/Linux — macOS-only APIs throughout

## Context

- Feature spec comes from a static REA analysis of `TrellisWM-0.9.8.dmg`; see `PLAN.md` (sections 1–5). That analysis used only metadata, symbol names, strings and imports, with no decompilation.
- The shipped app splits into a pure layout model, a behaviour engine and an AppKit layer; Pane mirrors this as `PaneModel`, `PaneEngine` and `Pane.app`.
- Inferred zoom technique (not observed at runtime): a full-screen overlay draws ScreenCaptureKit snapshots; when the camera settles, real windows are resized via AX and off-view windows are parked small.
- Prior art to study (MIT): AeroSpace (closest match), Amethyst, yabai (non-SIP parts), OpenMultitouchSupport.
- Open questions: drop-zone geometry, per-Space vs per-display layout state, camera curve. Pane picks its own values.

## Constraints

- **Platform**: macOS 14+, Apple Silicon and Intel — matches the reference app's floor and keeps ScreenCaptureKit available
- **Tech stack**: Swift + Swift Package Manager; AppKit for overlays; SwiftUI acceptable for Settings
- **Testability**: `PaneModel` and `PaneEngine` must not import AppKit, so they can be unit-tested headless
- **Private APIs**: each one (`_AXUIElementGetWindow`, SkyLight, MultitouchSupport, CoreDock) isolated in one file with a fallback; they can break on any macOS update
- **Legal**: clean room — implementers work from the spec and public prior art, never from the binary
- **License**: MIT

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Name "Pane" | User choice; check for existing macOS apps with the name before release | — Pending |
| MIT license | Matches AeroSpace/Amethyst/yabai ecosystem | — Pending |
| v1 = all 9 phases | User wants full feature parity for public release | — Pending |
| Model / Engine / App layering | Mirrors the reference app's proven split; makes core logic testable | — Pending |
| Snapshot-overlay zoom, no SIP | Only way to "zoom" other apps' windows without disabling SIP | — Pending |

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
*Last updated: 2026-10-23 after initialization*
