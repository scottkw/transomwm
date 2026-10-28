# Transom

Transom is a free, open-source (MIT) window manager for macOS in which windows never overlap. You dock windows into nested, tiled spaces by dragging them, and Transom keeps them arranged as windows open, close and resize. The longer-term design adds a zoomable "desk": zoom out to see everything, zoom in to whatever you need.

The core promise is simple: windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, tiling must still work.

Transom was renamed from Pane on 2026-10-27.

- Website: https://transomwm.app
- Source: https://github.com/scottkw/transomwm

## Status

Transom is pre-release. There is no public download yet. A notarised 0.3.0 build (the version set in `scripts/release.sh`) has been made locally, but its public release is held.

Phases 1-3 of the roadmap are complete, so tiling works today. Phase 4 (Zoom Camera) is next.

| Phase | Name | Status |
|---|---|---|
| 1 | Layout Model | Complete |
| 2 | Window Control | Complete |
| 3 | Tiling MVP | Complete |
| 4 | Zoom Camera | Planned |
| 5 | Gestures | Planned |
| 6 | Overview, Spaces & Displays | Planned |
| 7 | Tab Groups | Planned |
| 8 | Saved Views, URLs & Persistence | Planned |
| 9 | Polish & Ship | Planned |

Known gap: testing so far has used a single display. The multi-display re-check from Phases 2 and 3 is still outstanding, so treat behaviour on a second display as unverified.

## What works today

Transom runs as a menu-bar app (no Dock icon). Everything below is in the code now, and none of it needs Screen Recording.

| Feature | What it does |
|---|---|
| Drag to dock | Drag a window by its title bar to a screen edge or to another window's edge. A drop preview shows the exact frame the window will get, and it docks there on release. Tiles nest as deep as you like. A drop that cannot fit the windows' minimum sizes is shown as blocked and refused. |
| Drag modifiers | Hold ⇧ while dragging to move the window freely: it floats on the Desktop tile instead of docking. Hold ⌘ over another docked tile to swap the two windows. |
| Desktop tile | Each layout has a Desktop tile that holds floating windows. New windows open floating there. You can hide and show the Desktop tile. |
| Reflow | Closing or minimising a docked window reflows its neighbours to fill the space. A minimised window returns to its tile, and a window that leaves native fullscreen returns to its reserved tile. |
| Gaps | Choose the gap between tiles from the Gaps menu: None, 4, 8, 12, 16 or 24 pt (default 8). Drag the gap between two windows to resize both. |
| Green button | Clicking a window's green button toggles it between docked and floating. ⌥-click keeps the normal macOS zoom. |
| Keyboard layout commands | Dock, float, focus or move to a neighbour, swap, grow or shrink a tile, balance, rotate and flip splits, snap floating windows to halves, thirds, quarters, maximised or centred, Arrange All and Float All. Layout edits can be undone. |
| Split with New Finder Window | Splits the current tile with a new Finder window. |
| Exclusions | "Don't Arrange" the frontmost app from the menu or a hotkey. Excluded apps are never moved. The list starts empty. |
| Pause and Resume | Pause Arranging stops Transom moving windows until you resume. |
| Crash-safe restore | Quitting Transom puts every window it moved back on a sensible on-screen frame. After a crash or force-quit, the next launch brings stranded windows back on screen first, then re-applies the layout. A second crash soon after a recovery launch starts Transom paused. Restore All Windows brings everything back on screen at any time, even while paused. |
| Layout restore | Quitting and relaunching Transom while your apps keep running brings each layout back with the same windows in their tiles. |
| Per display and Space | There is one layout per display and Space. Fullscreen Spaces get no layout. |
| macOS conflicts | Transom detects Stage Manager (and pauses arranging while it is on), macOS edge tiling, and click-wallpaper-to-reveal-desktop. It explains each conflict and offers to turn the feature off. Restore macOS Window Settings in the menu puts back the values Transom changed. |
| Accessibility setup | A Set Up Transom window guides you through the Accessibility grant. If the grant goes stale (for example after a rebuild with a different signature), Transom detects it and explains the fix instead of looping on prompts. |
| Slow apps | Each app's Accessibility calls run off the main thread with a timeout, so a frozen app cannot stall Transom or the arranging of other apps' windows. |

### Menu

The status menu has three sections. Arrange holds the layout commands and the Gaps submenu. Safety holds Pause or Resume Arranging, Restore All Windows and Restore macOS Window Settings. Exclusions holds the Don't Arrange toggle and the list of excluded apps. Hold ⌥ while opening the menu to see a Debug submenu: Show Tracked Windows, Nudge Focused Window, and the state of the window-ID lookup, the Spaces lookup and the event tap.

### URL commands

Transom registers the `transom://` URL scheme with three commands. Each one runs at most once per second, and any other URL is rejected.

```sh
open transom://restore          # Restore All Windows
open transom://toggle-desktop   # hide or show the Desktop tile
open transom://split-finder     # Split with New Finder Window
```

Debug builds register `transom-debug://` instead.

### Hotkeys

These are the default global hotkeys. They are fixed for now. A recorder to rebind them is planned for the Settings window (Phase 9).

| Hotkey | Command |
|---|---|
| `⌃⌥⌘D` | Dock Window: dock the focused floating window |
| `⌃⌥⌘F` | Float Window: float the focused docked window |
| `⌃⌥⌘Z` | Undo Layout Change |
| `⌃⌥⌘H` | Hide or show the Desktop tile |
| `⌃⌥⌘←` | Focus the neighbouring tile to the left |
| `⌃⌥⌘→` | Focus the neighbouring tile to the right |
| `⌃⌥⌘↑` | Focus the neighbouring tile above |
| `⌃⌥⌘↓` | Focus the neighbouring tile below |
| `⌃⌥⌘⇧←` | Move Window left: into the tile across that edge, or snap a floating window to the left half |
| `⌃⌥⌘⇧→` | Move Window right: into the tile across that edge, or snap a floating window to the right half |
| `⌃⌥⌘⇧↑` | Move Window up: into the tile across that edge, or snap a floating window to the top half |
| `⌃⌥⌘⇧↓` | Move Window down: into the tile across that edge, or snap a floating window to the bottom half |
| `⌃⌥⌘S` | Swap with Previous Window: swap with the docked window focused before it |
| `⌃⌥⌘=` | Grow Tile by a tenth of its split's length |
| `⌃⌥⌘-` | Shrink Tile by a tenth of its split's length |
| `⌃⌥⌘B` | Balance Split |
| `⌃⌥⌘R` | Rotate Layout, from the desk's root split |
| `⌃⌥⌘X` | Flip Split |
| `⌃⌥⌘1` | Snap floating window: Left Third |
| `⌃⌥⌘2` | Snap floating window: Center Third |
| `⌃⌥⌘3` | Snap floating window: Right Third |
| `⌃⌥⌘U` | Snap floating window: Top Left Quarter |
| `⌃⌥⌘I` | Snap floating window: Top Right Quarter |
| `⌃⌥⌘J` | Snap floating window: Bottom Left Quarter |
| `⌃⌥⌘K` | Snap floating window: Bottom Right Quarter |
| `⌃⌥⌘↩` | Snap floating window: Maximize |
| `⌃⌥⌘C` | Snap floating window: Center |
| `⌃⌥⌘⇧D` | Arrange All Windows: dock every eligible floating window (one undo step) |
| `⌃⌥⌘⇧F` | Float All Windows: float every docked window (one undo step) |
| `⌃⌥⌘N` | Split with New Finder Window |
| `⌃⌥⌘P` | Pause or Resume Arranging |
| `⌃⌥⌘E` | Don't Arrange the frontmost app (toggle) |
| `⌃⌥⌘0` | Restore All Windows |

## Planned features

None of the following is in the code yet. Each line summarises the goal in `.planning/ROADMAP.md`.

| Phase | Feature | Status |
|---|---|---|
| 4 | Zoom Camera: zoom out to see every window on a display, step in or out one level of the layout, ⌘⇧-drag a rectangle to zoom to the windows it frames, go back and forward through previous views, and click a window to zoom to it and focus it. Zoomed views show window snapshots with Screen Recording, or app colour and icon without it. Turning zoom off leaves tiling fully working. | Planned |
| 5 | Gestures: ⌥-pinch and ⌥-two-finger pan on the trackpad over any app, and pinch and pan on the bare desktop without ⌥. | Planned |
| 6 | Overview, Spaces & Displays: an overview of every window on every display with a Spaces bar, an opt-in Mission Control takeover, and layouts kept per display and per Space across unplugging, sleep and docking. | Planned |
| 7 | Tab Groups: drop a window on the middle of another to group them under one tab strip, with windows from any apps, docked or floating. | Planned |
| 8 | Saved Views, URLs & Persistence: save views to slots 1-9, run more commands through `transom://` URLs and a bundled `transom` command-line tool, and restore layouts across app relaunches and reboots. | Planned |
| 9 | Polish & Ship: a Settings window (gaps, appearance, gestures, hotkeys, exclusions, Mission Control replacement), first-run onboarding, launch at login, an update check against GitHub Releases, a Homebrew cask, and a `transom://settings` URL that opens a given Settings section. | Planned |

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel (release builds are universal)
- The Accessibility permission, which Transom needs to move other apps' windows. The Set Up Transom window walks you through granting it.

Screen Recording is not needed today. It will be needed only for window snapshots in the planned zoom (Phase 4). Without it, zoom is planned to fall back to app-colour and icon tiles.

## Building from source

All code lives in Swift Package Manager targets, so the everyday loop needs no Xcode project:

```sh
swift build
swift test
```

The package declares `swift-tools-version: 6.2` and uses the Swift 6 language mode, so you need a Swift 6.2 or newer toolchain (Xcode 26 or later). The only runtime dependency is [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 3.1.0, pinned exactly.

Building the signed `.app` uses XcodeGen and Xcode:

| Script | What it does |
|---|---|
| `scripts/generate.sh` | Runs XcodeGen on `xcode/project.yml` to generate `xcode/Transom.xcodeproj`. The generated project is gitignored. Install XcodeGen with `brew install xcodegen`. |
| `scripts/build-debug.sh` | Builds the signed "Transom Debug.app" (bundle ID `com.eightabyte.transom.debug`), or with `--release` the signed "Transom.app" (`com.eightabyte.transom`). It then verifies the signature and designated requirement and prints the app path. |
| `scripts/run-debug.sh` | Builds "Transom Debug.app" and launches it through LaunchServices, so macOS attributes the permission grant to Transom and not to your terminal. Extra arguments are passed to the app, for example `--disable-private=AXWindowID`. `--no-build` skips the build. |
| `scripts/release.sh` | The local release pipeline: builds the universal Developer ID app, notarises and staples it, builds `build/Transom-0.3.0.dmg`, signs, notarises and staples the DMG, and prints its sha256. `--build-only` stops after building and verifying the app. `--skip-notarize` does everything except notarising and stapling. It uploads nothing. |
| `scripts/check-no-appkit.sh` | Fails if `TransomModel` or `TransomEngine` imports a UI framework. |
| `scripts/vm-live-test.sh` | Runs the live integration tests inside a Tart VM (see Testing). |

Signing notes:

- The scripts and `xcode/project.yml` hard-code the maintainer's Developer ID team. A fork must change it to its own team.
- macOS keys the Accessibility grant to the app's code signature. A stable signature keeps the grant across rebuilds, while ad-hoc signing resets it on every build. The separate Debug bundle ID keeps development and release grants apart.
- Notarising needs notarytool credentials stored once in the keychain, under the profile name set in `scripts/release.sh`.

## Project layout

| Target | Kind | Role |
|---|---|---|
| `TransomModel` | library | The pure layout model: nested split tree with weights, the Desktop layer, tab groups, desks keyed by display and Space, resolving tiles to non-overlapping rects with minimum sizes, undo and versioned JSON. Foundation only. |
| `TransomEngine` | library | Behaviour with no UI: the Arranger, the one `Command` enum every route dispatches, drag sessions, window tracking and classification, crash recovery, layout restore, the `transom://` parser and the `WindowSystem` protocol. |
| `TransomMac` | library | The AppKit layer: Accessibility window system, event tap, hotkeys, status menu, overlays (drop preview, gap handles, toasts), permission flow, stores and conflict handling. |
| `TransomPrivate` | library | Every private API, each behind a fallback (see Private APIs). |
| `TransomApp` | executable | The app entry point; it starts `TransomMac`. |
| `TransomFixtureApp` | executable | A test fixture that opens real windows of every shape the integration tests need and reports their IDs and frames. |
| `transom-dump` | executable | Records one window of a running app as a redacted, labelled case for the window classifier's test corpus. |
| `TransomTestSupport` | library | `FakeWindowSystem`, a simulated window system for headless engine tests. |

Test targets: `TransomModelTests`, `TransomEngineTests`, `TransomMacTests` and `TransomMacIntegrationTests`.

Two rules shape the layout:

- `TransomModel` and `TransomEngine` never import AppKit, Cocoa, SwiftUI or another UI framework, so they can be tested headless. `scripts/check-no-appkit.sh` enforces this in CI, and `Tests/TransomModelTests/NoAppKitTests.swift` runs the same check inside `swift test`.
- Each private API lives in its own file in `TransomPrivate`, is loaded at runtime rather than linked, and has a fallback, because any macOS update can break it.

## Testing

`swift test` runs the headless suites (model, engine and Mac unit tests) on any Mac, with no permissions needed. CI (`.github/workflows/ci.yml`, on `macos-26`) runs `scripts/check-no-appkit.sh`, then `swift build` and `swift test` in both debug and release.

The live Accessibility suites in `Tests/TransomMacIntegrationTests` skip unless the process is trusted for Accessibility and `TRANSOM_LIVE=1` is set. They open and move real windows, so run them only inside a Tart macOS VM through `scripts/vm-live-test.sh`, never on your own Mac:

```sh
scripts/vm-live-test.sh <filter> [VAR=value ...]
scripts/vm-live-test.sh FixtureShapesTests
```

The script builds the test bundles on the host without running them, copies them into the VM and runs them there with `TRANSOM_LIVE=1`. `TRANSOM_VM`, `TRANSOM_VM_USER` and `TRANSOM_VM_KEY` override the VM name, the SSH user and the SSH key. Their defaults are in the script header. The VM's SSH session needs the Accessibility grant.

## Private APIs

| API | File | Used for | Fallback when missing or disabled |
|---|---|---|---|
| `_AXUIElementGetWindow` | `Sources/TransomPrivate/AXWindowID.swift` | The window ID behind an Accessibility window | Matching windows by frame against the public window list |
| SkyLight Spaces (`SLSCopySpacesForWindows`, `SLSManagedDisplayGetCurrentSpace`) | `Sources/TransomPrivate/SkyLightSpaces.swift` | Which Space each window is on, and each display's current Space | Single-Space behaviour |

Both are reached through `dlopen` and `dlsym`, never linked, so a removed symbol leaves only that feature degraded and Transom still launches. A capability whose function keeps failing is switched off for the rest of the session. To test a fallback, launch with `--disable-private=AXWindowID,Spaces` (one or both names). `Sources/TransomPrivate/Capabilities.swift` logs each capability as available or off under the `private` log category, and logs any unknown name.

MultitouchSupport (for trackpad gestures, Phase 5) and CoreDock (for the Mission Control takeover, Phase 6) are planned and not yet in the code.

## Data stored

Files in `~/Library/Application Support/Transom`:

| File | Contents |
|---|---|
| `layout.json` | The layouts (desks, tile trees, Desktop tiles), each moved window's pre-park and wanted frames, and a session record used to detect a crash on the next launch. Window titles are never written, and the file is owner-only. |
| `min-size-hints.json` | Minimum window sizes Transom has learned, per app bundle ID. Only bundle IDs and sizes, nothing per window. |

Both files are validated on load. A file that fails validation is moved aside with a `.corrupt` suffix and Transom starts empty. A `layout.json` from a newer schema is left untouched and nothing is saved that session.

Preferences in Transom's user defaults:

| Key | Contents |
|---|---|
| `excludedBundleIDs` | The Don't Arrange list |
| `gap` | The gap between tiles |
| `conflictNotNow` | macOS conflicts you chose not to be asked about again |
| `windowManagerOriginals` | The original values of the macOS window settings Transom changed, for Restore macOS Window Settings |
| `freezeTestPID` | Debug builds only: the app paused by the Debug menu's freeze test, so it is resumed after a crash |
| `KeyboardShortcuts_<name>` | Hotkey bindings, stored by the KeyboardShortcuts library |

When you choose Turn Off for a macOS conflict, Transom writes only these boolean keys in the `com.apple.WindowManager` domain: `GloballyEnabled` (Stage Manager), `EnableTilingByEdgeDrag` and `EnableTopTilingByEdgeDrag` (edge tiling), and `EnableStandardClickToShowDesktop` (click wallpaper).

## Privacy

- Transom does not read window contents and does not capture the screen.
- It has no network code and sends nothing anywhere.
- Through Accessibility it reads window metadata: each app's window list and, per window, role, subrole, modal, main, minimised and fullscreen state, identifier, title, position, size, title-bar buttons and child elements. To split with a new Finder window it presses Finder's menu item through Accessibility, with no Apple Events.
- Window titles stay in memory. They help classify windows, match windows when the private window-ID lookup is off, and label rows in the Debug menu's Tracked Windows list. They are never written to disk.
- Logs go to the macOS unified log under the `com.eightabyte.transom` subsystem.
- The window snapshots planned for Phase 4 will be used only to draw the zoom overlay.

## Clean room

Transom is inspired by the commercial app TrellisWM and contains no code, text or assets from it. Its implementers work from a feature spec and public prior art, never from the TrellisWM binary. No code is copied from AeroSpace, Amethyst, yabai or Loop either. Loop is GPL-3.0, which is incompatible with Transom's MIT license, so it is read for patterns only.

## License

Transom is MIT licensed. The LICENSE file has not been added to the repo yet.
