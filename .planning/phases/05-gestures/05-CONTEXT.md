# Phase 5: Gestures - Context

**Gathered:** 2026-10-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Trackpad gestures drive the Phase 4 zoom camera:
- ⌥-pinch zooms in and out over any app (GEST-01).
- ⌥-two-finger pan moves the view (GEST-02).
- Pinch and pan on bare wallpaper work without ⌥ (GEST-03).
- Gestures survive sleep/wake and trackpad reconnects, and never leak into the app under the pointer (GEST-04).

If the private multitouch API is unavailable, Transom falls back and still launches.

Out of scope:
- New camera concepts: free-scale zoom and the all-displays overview (Phase 6).
- A Settings UI for gestures (Phase 9).

</domain>

<decisions>
## Implementation Decisions

### A. Pinch feel
- **D-01:** Live pinch, snap on release.
  - While the fingers move, the Phase 4 stage follows the pinch continuously, scaling the overlay between the current view and its parent or child level.
  - On lift, the camera snaps to the nearest layout level (home or a node) with the standard ~250 ms ease-out.
  - Real windows then settle once, using the existing `.cameraMove` → `.cameraSettle` path: one AX write per changed, visible window.
  - Reduce Motion: the live tracking still follows the fingers, but the snap uses the crossfade.
- **D-02:** No free-scale resting camera. The camera always comes to rest on a NodeID view or home, so the Phase 4 model (NodeID targets, history, parking) is unchanged. A settled gesture pushes history exactly like a hotkey move. — **Reversibility:** costly — a free camera would touch Navigator, history, parking and settle.

### B. Pan feel
- **D-03:** Live drag, snap to neighbour.
  - The stage slides with the fingers.
  - On lift, a drag past about one third of the view (or a flick) snaps to the neighbouring area chosen by Phase 4's pan rule (`Navigator.pan`: same depth, longest shared edge, recency).
  - A shorter drag springs back.
  - At home there is no neighbour, so a pan rubber-bands and springs back.

### C. Where gestures apply
- **D-04:** With ⌥ held, pinch and pan act over any app (GEST-01/02).
- **D-05:** Without ⌥, gestures act only while the pointer is over visible bare wallpaper: no window under it, including the empty area of the Desktop tile. Over any window, ⌥ is required (GEST-03).
- **D-06:** Gestures Transom handles are fully consumed, so no scroll or magnify reaches the app under the pointer. All other pinches and scrolls pass through untouched (GEST-04, success criterion 3).
- **D-07:** Gestures follow the zoom switch. When zoom is off (Phase 4 Turn Off Zoom), gestures do nothing and no multitouch device is opened.

### D. Testing (VM has no trackpad)
- **D-08:** Recorded traces plus user UAT.
  - Gesture recognition (pinch scale, pan translation, flick, the snap decision) lives in AppKit-free engine code. It is tested headless with recorded or synthetic touch-frame traces.
  - The event-tap consume/pass-through logic is tested in the Tart VM with synthetic scroll and magnify events.
  - Real-trackpad checks are short checklists the USER runs on their Mac at two points: the spike gate (multitouch vs event-tap comparison) and the final phase UAT.
  - Agents never open windows, start event taps or open multitouch devices on the host.
- **D-09:** The phase-research spike (ROADMAP) compares MultitouchSupport raw touches with event-tap magnify/gesture events (CGEvent types 29/30). It covers visibility over other apps, the ability to consume, the MT callback struct layout and the macOS 27 `int32_t` return. Its live half is a user-run harness on the host trackpad: one small CLI that prints measurements, with no windows and no layout changes. Its results gate the rest of the phase, like the Phase 4 spike.

### E. Post-research decisions (2026-10-28)
- **E-01:** Whether MultitouchSupport ships at all is decided at the spike gate, from measured data. Default: a tap-only product, with the MT shim kept in the spike target. The user picks at the gate.
- **E-02:** One layout level per gesture. A long pinch is clamped (rubber band past one level); pinch again to go further.
- **E-03:** A gesture that starts during a camera move or settle continues from the current tile positions and retargets, like a mid-move tile click in Phase 4.
- **E-04:** Trackpad only. Two-finger pan comes from trackpads, filtered by sender. Mouse wheels and Magic Mouse scroll always pass through untouched. Pinch is trackpad-only by nature.
- **E-05:** A gesture with ⌃ or ⌘ also held passes through (Accessibility scroll-to-zoom uses ⌃). Confirm at user UAT.

### Claude's Discretion
- MultitouchSupport shim internals in `Sources/TransomPrivate/` (own dlsym shim modelled on OpenMultitouchSupport headers; never depend on OpenMultitouchSupport 4.x).
- Which path is primary and which is fallback, decided from the spike data. If neither works, gestures turn off with a Debug-menu status line, and hotkeys, URLs and menu still drive zoom.
- Gesture thresholds: pinch dead-zone, the one-third pan threshold tuning, flick velocity, rubber-band strength.
- Device re-enumeration on wake and hot-plug (both the built-in trackpad and a Magic Trackpad), and a per-API crash canary in the Capabilities registry.
- Debug-menu lines for multitouch device and gesture state.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §Phase 5: goal, success criteria, research note (one-day spike) and scope notes (own MT shim, magnify fallback, re-enumeration, crash canary).
- `.planning/REQUIREMENTS.md`: GEST-01..GEST-04.

### Stack and pitfalls
- `.planning/research/STACK.md`: Private API Access (MultitouchSupport row), Input (gesture spike flagged LOW confidence) and What NOT to Use (OpenMultitouchSupport 4.x).
- `.planning/research/PITFALLS.md`: private-API breakage and event-tap timeout pitfalls.

### Camera this phase drives
- `.planning/phases/04-zoom-camera/04-CONTEXT.md`: camera model, one write per settle, zoom-off guarantee.
- `.planning/phases/04-zoom-camera/04-UI-SPEC.md`: stage, timing and Reduce Motion rules.
- `.planning/phases/04-zoom-camera/04-SPIKE.md`: spike gate format and VM measurement traps.
- `.planning/phases/04-zoom-camera/04-UAT.md`: VM environment notes (display sleep shifts geometry; wake the display before live runs).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/TransomEngine/Navigator.swift`: `pan`, `stepIn`/`stepOut` and `target(_:in:)` choose snap targets.
- `Sources/TransomEngine/Arranger+Camera.swift`: `zoomTo`, the `.cameraMove`/`.cameraSettle` protocol and history push at settle.
- `Sources/TransomMac/Zoom/ZoomController.swift` and `StagePanel.swift`: the stage, snapshot cache and reveal. Live tracking needs a "follow" mode on the stage before the settle animation.
- `Sources/TransomMac/Input/InputTap.swift`: one active session tap on its own thread. Its mask (line 67) is mouse-only today; gestures add scroll/magnify/gesture types. Keep the callback under ~1 ms with no AX calls.
- `Sources/TransomMac/Input/ZoomTapRules.swift`: pure consume/pass decision rules, a pattern to copy for gesture consume rules.
- `Sources/TransomMac/Zoom/ZoomInput.swift`: wallpaper hit-test (Finder AXGroup "desktop" vs AXImage icon, confirmed in Phase 4 UAT), reusable for D-05.
- `Sources/TransomPrivate/Capabilities.swift`: capability registry and `--disable-private=` switch for the new MultitouchSupport capability.

### Established Patterns
- Each private API is in its own file in TransomPrivate, loaded with dlopen/dlsym and never linked, with a fallback and logged availability.
- TransomModel and TransomEngine are AppKit-free (`scripts/check-no-appkit.sh`).
- Every live test runs only in the VM; every `swift test --filter` gate must show a non-zero executed count.

### Integration Points
- `ArrangeController` owns the tap and ZoomInput lifecycle and the zoom on/off switch (D-07), plus wake and display-change observers for re-enumeration.
- Status menu Debug submenu: multitouch status lines.

</code_context>

<specifics>
## Specific Ideas

- The host has both a built-in trackpad and a Magic Trackpad; the user's UAT should cover both, including disconnecting and reconnecting the Magic Trackpad.

</specifics>

<deferred>
## Deferred Ideas

- Gesture settings (sensitivity, on/off, no-⌥ wallpaper toggle) belong in the Phase 9 Settings window.

</deferred>
