# Phase 5: Gestures - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-28
**Phase:** 05-gestures
**Areas discussed:** Pinch feel, Pan feel, Testing, Bare desktop

---

## Pinch feel

| Option | Description | Selected |
|--------|-------------|----------|
| Live, snap on release | Overlay follows the fingers; on lift it snaps to the nearest layout level, then windows settle once | ✓ |
| Discrete steps | A pinch past a threshold fires one Step In / Step Out | |
| Free zoom, no snapping | Camera can rest at any scale; needs a new free-camera model | |

**User's choice:** Live, snap on release

## Pan feel

| Option | Description | Selected |
|--------|-------------|----------|
| Live drag, snap to neighbour | Overlay slides with the fingers; past about one third (or a flick) snaps to the neighbour, otherwise springs back | ✓ |
| Discrete pan | A swipe past a threshold fires one pan command | |

**User's choice:** Live drag, snap to neighbour

## Testing (the VM has no trackpad)

| Option | Description | Selected |
|--------|-------------|----------|
| Recorded traces + your UAT | Headless traces, synthetic VM event-tap tests, user-run real-trackpad checklists at the spike and the final UAT | ✓ |
| Allow bounded host runs | Agents run short fixture-only gesture tests on the host | |

**User's choice:** Recorded traces + your UAT

## Bare desktop

| Option | Description | Selected |
|--------|-------------|----------|
| Pointer over wallpaper only | No-⌥ gestures only over visible wallpaper | ✓ |
| Wallpaper + zoom overlay | Also without ⌥ while the zoom overlay is on screen | |

**User's choice:** Pointer over wallpaper only

## Claude's Discretion

- MT shim internals, primary vs fallback path (from spike data), gesture thresholds, re-enumeration, crash canary, Debug lines.

## Deferred Ideas

- Gesture settings UI → Phase 9.
