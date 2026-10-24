# Open-source TrellisWM alternative: plan

Working name: **Arbor** (rename freely).
Target: macOS 14+, Apple Silicon and Intel, Swift, MIT or GPL-3.0.

## 0. Ground rules (clean room)

The product idea (a zoomable, nested-tiling window manager) is not protected. The code, text, icons, lesson pages and settings file are copyrighted.

- Do **not** copy: `Localizable.strings` text, `Lessons/` HTML/JS/CSS, `AppIcon.icns`, `MenuBarIcon.svg`, `ReleaseSettings.json` values, or any decompiled code.
- Do **not** reuse the name "TrellisWM", its bundle ID, `trelliswm://` scheme or website copy.
- The findings below are a **feature spec** written from observation. Build from this spec, not from the binary.
- Skip all licensing (Lemon Squeezy keys, trial, Free/Pro limits). Everything is free.

## 1. What the shipped app is (evidence)

Source: `TrellisWM-0.9.8.dmg` (sha256 `82c54c77…ec003`), REA evidence `ev_c1a9bd3c…`, binary sha256 `eeb7ab75…63d1`.

| Fact | Evidence type |
|---|---|
| Swift app, arm64 only, macOS 14+, menu-bar only (`LSUIElement`) | Info.plist, `lipo` |
| 4 Swift modules: `TrellisWM` (app/macOS glue), `SpacesEngine` (behaviour), `SpacesModel` (pure layout tree), `Licensing` | Swift symbol names |
| Moves windows with the Accessibility API (`AXUIElementSetAttributeValue`, `AXObserver`) | imports |
| Gets window IDs with private `_AXUIElementGetWindow` | imports |
| Reads Spaces and windows with private SkyLight calls (`SLSCopyManagedDisplaySpaces`, `SLSWindowQueryWindows`, iterators) via `dlsym` | strings |
| Raw trackpad input via private `MultitouchSupport.framework` (`MTDeviceCreateList/Start`) | strings |
| Takes over Mission Control: `CGEventTap` + `CGSSetSymbolicHotKeyEnabled` + `CoreDockSendNotification` | imports/strings |
| Window pictures via ScreenCaptureKit (Screen Recording permission is optional) | linked framework, UI text |
| **No** SIP-requiring calls (no window transforms, no scripting additions) | absence in imports (bounded search) |
| Sparkle 2.10 for updates | bundled framework |

**Inference (how the zoom works without SIP):** macOS doesn't let a normal app scale another app's window. So the "zoom" is a full-screen overlay (`StagePanel`/`StageRenderer`) drawing ScreenCaptureKit snapshots. When the camera settles, real windows are resized with AX to match, then the overlay fades out. Off-screen windows get "parked" small (`parkOutOfViewSmall`). Settings like `redrawWait` (0.5 s) back this up.

### Feature list (from UI text and type names)

Core (TrellisWM's Free tier):
1. **Dock (tile)**: drag a window to a screen edge or another window's edge and it splits that space. Splits nest as deep as you like (`SplitNode`, `PanelNode`, weights).
2. **Float**: the green button toggles docked or floating. Floating windows live on a "Desktop" tile (`DesktopNode`, `HiddenDesktop`).
3. **Zoom/navigate**: ⌥-pinch or a hotkey zooms out to "Everything"; step in or out one level; ⌘⇧-drag a rectangle to zoom to it (`Navigator`, `CameraCurve`, `RectZoom`).
4. **Back/forward history** of views (`recordVisit`, menu bar arrows).
5. **Gaps** with draggable resize handles (`GapHandleWindow`, `resizeBoundary`).
6. **Overview** that replaces Mission Control: every window on every display, Spaces along the top.
7. Turns off conflicting macOS features (Edge tiling, Stage Manager, click wallpaper to reveal desktop).
8. Per-app exclusion list, launch at login, onboarding.

Pro (free in our version):
9. **Tab groups**: drop a window onto the middle of another to make tabs. A tab strip overlay with traffic lights acts on the whole group.
10. **Saved views 1–9** (hotkeys).
11. **URL commands** (`scheme://command`) for Raycast/Alfred/Shortcuts.
12. Unlimited docked windows.

## 2. Architecture (mirror the 3-layer split; it is a good one)

```
ArborModel   (pure Swift, no AppKit) layout tree + geometry. 100% unit-testable.
ArborEngine  (pure Swift)            camera, navigation, drag/drop/resize sessions,
                                     saved views, layout tweens. Talks to a WindowSystem protocol.
Arbor.app    (AppKit)                AX window control, SkyLight Spaces queries, event taps,
                                     multitouch, ScreenCaptureKit, overlays, menu bar, settings.
```

The `WindowSystem` protocol is the seam. The engine gets a fake in tests and `MacWindowSystem` in the app.

### Prior art to read (all permissively licensed; check each licence before copying code)
- **AeroSpace** (MIT, Swift): tree tiling, AX handling, `_AXUIElementGetWindow`, hiding windows off-screen instead of using Spaces. Closest match. Read it first.
- **Amethyst** (MIT, Swift): AX observers, app exclusion.
- **yabai** (MIT, C): SkyLight Spaces queries (only the parts that need no SIP).
- **OpenMultitouchSupport** (MIT): Swift wrapper for raw trackpad input.
- **Niri / PaperWM**: interaction ideas for a canvas-style WM.

## 3. Phases

Estimates assume one experienced Swift dev, part-time.

| # | Phase | Delivers | Estimate |
|---|---|---|---|
| 1 | **Model** | Layout tree (split/panel/group/desktop), insert at edge, remove, reweigh, minimum sizes, rect calculation. Codable for persistence. Unit tests. | 1 week |
| 2 | **Window control** | AX permission flow, track windows (AXObserver for created/destroyed/moved/focused), get window IDs, set frame, app exclusion list. | 1–2 weeks |
| 3 | **Tiling MVP** | Drag a title bar to an edge to dock it (drop preview overlay); close reflows; gaps; drag gap to resize; green button floats/docks. **First usable release.** | 2 weeks |
| 4 | **Camera + zoom** | Overlay stage with ScreenCaptureKit snapshots (app colour + icon fallback without permission), zoom out to everything, step in/out, rectangle zoom, back/forward, hotkeys. Park off-view windows. | 3–4 weeks (hardest part) |
| 5 | **Gestures** | ⌥-pinch/pan via MultitouchSupport, pinch on bare desktop, smooth camera curve. | 1–2 weeks |
| 6 | **Overview + Spaces** | Overview of all displays, Spaces bar (SkyLight read-only), optional Mission Control takeover (event tap + symbolic hotkeys). Multi-display. | 2–3 weeks |
| 7 | **Tab groups** | Drop onto the middle to group; tab strip overlay panel following the window; group traffic lights; hide non-selected tabs. | 2 weeks |
| 8 | **Saved views + URL commands** | ⌥1–9 save/restore, `arbor://` handler, persistence across restarts and display changes. | 1 week |
| 9 | **Polish + ship** | Settings window (SwiftUI is fine), onboarding, disable conflicting macOS features, launch at login (`SMAppService`), Sparkle with your own EdDSA key, Homebrew cask, notarisation. | 2 weeks |

Total: about 4–5 months part-time. Phases 1–3 alone (about a month) give you a working nested tiler.

## 4. Risks

- **Private APIs** (`_AXUIElementGetWindow`, SkyLight, MultitouchSupport, CoreDock) can break on any macOS update. Isolate each one behind one file with a fallback, and never ship to the Mac App Store.
- **Zoom illusion quality**: snapshot latency and apps that redraw slowly after a resize cause flicker. Budget time for `redrawWait`-style tuning.
- **AX is slow and flaky** for some apps (Electron, Java). Use per-app timeouts (`AXUIElementSetMessagingTimeout`) and an exclusion list.
- **Clean-room discipline**: whoever writes code should work from this spec and the public prior art, not from the binary or its strings.

## 5. Open questions (not answered by static analysis)

- Exact drop-zone geometry (how close to an edge counts, how long to hover). Settle these by using the app, then pick your own values.
- How it behaves across macOS Spaces: does each Space get its own tree? `SavedDisplay`/`DisplayStore` suggest per-display state; per-Space state is unconfirmed.
- Camera animation curve details (`CameraCurve`): design your own.
