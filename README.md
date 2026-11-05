# Transom

Transom is a free, open-source (MIT) window manager for macOS in which windows never overlap. You dock windows into nested, tiled spaces by dragging them, and Transom keeps them arranged as windows open, close and resize. Windows live on a zoomable "desk": zoom out to see everything, zoom in to whatever you need.

The core promise is simple: windows dock into nested, non-overlapping tiles by dragging, and stay correctly arranged as windows open, close and resize. If zoom, tabs or anything else fails, tiling must still work.

Transom was renamed from Pane on 2026-10-27.

- Website: https://transomwm.app
- Source: https://github.com/scottkw/transomwm

## Status

Transom is pre-release. There is no public download yet. A notarised 0.3.0 build (the version set in `scripts/release.sh`) has been made locally, but its public release is held.

Phases 1-8.1 of the roadmap are complete, so tiling, zoom, trackpad gestures, the overview, tab groups, saved views, the `transom` command-line tool, restoring layouts after a reboot and the window behaviour options work today.

| Phase | Name | Status |
|---|---|---|
| 1 | Layout Model | Complete |
| 2 | Window Control | Complete |
| 3 | Tiling MVP | Complete |
| 4 | Zoom Camera | Complete |
| 5 | Gestures | Complete |
| 6 | Overview, Spaces & Displays | Complete |
| 7 | Tab Groups | Complete |
| 8 | Saved Views, URLs & Persistence | Complete |
| 8.1 | Window Behaviour Options | Complete |
| 9 | Polish & Ship | Planned |

Known gap: testing so far has used a single display. The multi-display re-checks from Phases 2, 3 and 6 (unplug and re-plug, per-arrangement layouts, "Displays have separate Spaces" off, Tab between displays) are still outstanding, so treat behaviour on a second display as unverified.

## What works today

Transom runs as a menu-bar app (no Dock icon). Everything below is in the code now. Only zoom's window snapshots use Screen Recording, and zoom works without it.

| Feature | What it does |
|---|---|
| Drag to dock | Drag a window by its title bar to a screen edge or to another window's edge. A drop preview shows the exact frame the window will get, and it docks there on release. Tiles nest as deep as you like. A drop that cannot fit the windows' minimum sizes is shown as blocked and refused. |
| Drag modifiers | Hold ⇧ while dragging to move the window freely: it floats on the Desktop tile instead of docking. Hold ⌘ over another docked tile to swap the two windows. Hold ⌃ for fourths (see Fourths). |
| New windows | Choose menu ▸ Arrange ▸ New Windows ▸ Float or Tile. Float is the default. With Tile, a new window docks beside the focused tile, splitting it along its longer side. Dialogs, panels, excluded apps and windows too small to tile still float. So does a window that opens while you are dragging. |
| Drag to Dock | Choose menu ▸ Arrange ▸ Drag to Dock ▸ Automatically or Hold ⌥. Automatically is the default. With Hold ⌥, a plain drag pulls a docked window out to floating and just moves a floating one, with no docking regions. Hold ⌥ during the drag to show the regions and dock, or to make a tab group. ⇧ still floats and ⌘ still swaps. Press ⌥ after the drag starts. |
| Fourths | Dock a window to the 1st, 2nd, 3rd or 4th fourth of the desk, or to its middle half, as a column or a row. Windows already docked shrink to fit, and with no window on one side the new window grows to fill it. Use the hotkeys, menu ▸ Arrange ▸ Dock to Fourth, or a drag: press ⌃ after the drag starts for columns, or ⌃⌘ for rows, because ⌃-click is a right click. The screen shows the regions, and the preview shows where the window will go. The middle-half region is the central quarter of the screen. With zoom off, a fourth that doesn't fit is refused; with zoom on, windows collapse. |
| Desktop tile | Each layout has a Desktop tile that holds floating windows. New windows open floating there, unless you choose menu ▸ Arrange ▸ New Windows ▸ Tile. You can hide and show the Desktop tile. |
| Reflow | Closing or minimising a docked window reflows its neighbours to fill the space. A minimised window returns to its tile, and a window that leaves native fullscreen returns to its reserved tile. |
| Gaps | Choose the gap between tiles from the Gaps menu: None, 4, 8, 12, 16 or 24 pt (default 8). Drag the gap between two windows to resize both. |
| Green button | Clicking a window's green button toggles it between docked and floating. ⌥-click keeps the normal macOS zoom. |
| Keyboard layout commands | Dock, float, focus or move to a neighbour, swap, grow or shrink a tile, balance, rotate and flip splits, snap floating windows to halves, thirds, quarters, maximised or centred, Arrange All and Float All. Layout edits can be undone. |
| Split with New Finder Window | Splits the current tile with a new Finder window. |
| Exclusions | "Don't Arrange" the frontmost app from the menu or a hotkey. Excluded apps are never moved. The list starts empty. |
| Pause and Resume | Pause Arranging stops Transom moving windows until you resume. |
| Crash-safe restore | Quitting Transom puts every window it moved back on a sensible on-screen frame. After a crash or force-quit, the next launch brings stranded windows back on screen first, then re-applies the layout. A second crash soon after a recovery launch starts Transom paused. Restore All Windows brings everything back on screen at any time, even while paused. |
| Layout restore | Quitting and relaunching Transom while your apps keep running brings each layout back with the same windows in their tiles. |
| Per display and Space | There is one layout per display and Space, kept across Space switches, sleep and wake, and restarts. Fullscreen Spaces get no layout. A desk that changes while its Space is hidden is re-arranged when you next show it. |
| Display arrangements | Layouts are remembered per set of connected displays and switched automatically when you dock or undock. When a display is unplugged, its windows float on a remaining display and go back to their tiles when it returns. Transom waits about 1.5 s for the displays to settle, and never acts while the Mac is asleep or locked. Works with "Displays have separate Spaces" on or off. |
| Overview | ⌃⌥⌘A (or menu ▸ Show Overview, or `transom://overview`) shows every window on every display and Space, with a strip of that display's Spaces along the top. Windows on other Spaces show the last snapshot taken this session, or their app-colour tile. Click a window to go to it (switching Space if needed), or click a Space to switch to it. The arrow keys move the selection, Tab moves to the next display, Return opens the selected window and Esc closes the overview. VoiceOver uses ⌃⌥ for its own commands, so with VoiceOver on, open the overview from the menu or rebind it. |
| Replace Mission Control | Off by default. Turn it on from the menu and F3, ⌃↑ and ⇧F3 open Transom's overview instead of Mission Control; when the overview can't open, Mission Control opens as usual. The four-finger swipe stays with macOS. Transom stores the original shortcut settings first and restores them when you turn it off, on quit and on the next launch after a crash; a crash while it is on turns it off until you turn it back on. Switching Spaces from the overview uses macOS's Move left/right a space shortcuts, so it needs them on. |
| Tab groups | Drag a window onto the middle of another window (docked, or floating on the Desktop) and hold until the outline reads "Group as tabs" (about half a second), then release: both share the tile under one tab strip, from any apps. Click a tab to switch; hidden tabs are moved off screen, never minimised, and come back on quit. A window activated another way (⌘Tab, the Dock) becomes the selected tab. Drag a tab out of the strip to dock or float it again; right-click a tab for Close Tab and Move Out of Group. The strip's buttons close, minimise and float/dock the whole group; Close Group asks first (with "Do not show this again") and waits for any save prompt, continuing after Save or Delete and stopping on Cancel. A Safari window with several tabs joins as one tab. ⌃⌥⌘T / ⇧⌃⌥⌘T switch to the next / previous tab, ⌃⌥⌘L moves the focused tab out, also under menu ▸ Arrange ▸ Tabs. Groups are saved and come back on relaunch. VoiceOver reads the strip as a tab group. |
| Saved views | ⇧⌥1–9 saves the current view to a slot and ⌥1–9 goes back to it, also from another Space: Transom switches there first, then zooms to the windows you saved, even after splits and moves. Saving over a slot replaces it, and saved views survive restarts. `transom://view/3` and `transom://save-view/3` do the same. With zoom off, these keys reach your apps. |
| Command-line tool | `transom view 3` runs any `transom://` command in the running app and reports errors with an exit code. See Command-line tool below. |
| Windows find their tiles again | After Transom or an app relaunches, or the Mac restarts, windows go back to their tiles, matched by app, title, position and order. A tile whose window hasn't come back shows a dim "Waiting for {App}…" that clicks pass through. It closes 30 s after you quit that app, 10 s after the app opens without a match, or 5 min after Transom starts if the app never opens. A tile on a Desktop you aren't on waits until you go there. Closing a window with ⌘W while its app keeps running still closes its tile at once. |
| macOS conflicts | Transom detects Stage Manager (and pauses arranging while it is on), macOS edge tiling, and click-wallpaper-to-reveal-desktop. It explains each conflict and offers to turn the feature off. Restore macOS Window Settings in the menu puts back the values Transom changed. |
| Accessibility setup | A Set Up Transom window guides you through the Accessibility grant. If the grant goes stale (for example after a rebuild with a different signature), Transom detects it and explains the fix instead of looping on prompts. |
| Zoom camera | Zoom out to see every window on a display, step in or out one level of the layout, go back and forward through up to 50 previous views per display, and pan to a neighbouring area. ⌘⇧-drag a rectangle to zoom to the windows it frames (Esc cancels). After zooming out, click a window to zoom in to it and focus it. Double-click a title bar to frame that window, or the bare wallpaper to frame the Desktop; do it again to toggle back. Only an overlay animates (about 250 ms, or a crossfade with Reduce Motion); real windows get one move each when the camera settles. Windows outside the view are moved off screen at their own size, never shrunk, and come back on quit, after a crash and with Restore All Windows. |
| Window snapshots | With Screen Recording granted, the zoom overlay shows one-shot snapshots of each window. Without it, each window is drawn in its app's colour with its icon and title. Transom asks for Screen Recording the first time you zoom, never at setup. |
| Collapsed blocks | With zoom on, a drop that doesn't fit the windows' minimum sizes is accepted: windows that lose room show as blocks in their app's colour until you zoom in. Double-click a block to zoom in to it. With zoom off, such a drop is refused as before. |
| Trackpad gestures | Hold ⌥ and pinch on the trackpad over any app to zoom the desk one level in or out, or ⌥-two-finger pan to slide to a neighbouring area. Over the bare wallpaper, pinch and pan work without ⌥. The desk follows your fingers live, then snaps to the next level or neighbour, or springs back if the gesture was short. The app under your fingers never sees a gesture Transom takes. Other modifiers (⌃, ⌘) and mouse wheels pass through to macOS. Gestures keep working after sleep, and with Reduce Motion the finish is a fade. They work with Trackpad ▸ "Zoom in or out" on or off; with it off, Transom reads the pinch from the trackpad directly. Built-in trackpad tested; an external Magic Trackpad is untested. Pans follow your natural-scrolling setting, like scrolled content. |
| Zoom off | Turn Off Zoom (menu) brings every window home and disables zoom entirely: no overlay, no Screen Recording use, and tiling behaves exactly as without zoom. |
| Slow apps | Each app's Accessibility calls run off the main thread with a timeout, so a frozen app cannot stall Transom or the arranging of other apps' windows. |

### Menu

The status menu has four sections. Arrange holds the layout commands and the Gaps, New Windows and Drag to Dock submenus. Zoom holds the zoom commands, Turn Off or Turn On Zoom, Allow Window Previews… (Screen Recording) and Shortcuts…, a window where you can rebind every hotkey. Safety holds Pause or Resume Arranging, Restore All Windows and Restore macOS Window Settings. Exclusions holds the Don't Arrange toggle and the list of excluded apps. Hold ⌥ while opening the menu to see a Debug submenu: Show Tracked Windows, Nudge Focused Window, the state of the window-ID lookup, the Spaces lookup and the event tap, the zoom and snapshot state, and the gesture state (gestures taken, the gesture tap, and multitouch), the Spaces and Displays state (current Spaces, display arrangement, settling), the Mission Control takeover state, the last overview's open time, saved views, windows waiting to come back, and whether the command-line tool is listening. If multitouch was switched off after a crash, Turn Multitouch Back On re-enables it.

### URL commands

Transom registers the `transom://` URL scheme. Each one runs at most once per second, the dock URLs share that second, and any other URL is rejected.

```sh
open transom://restore          # Restore All Windows
open transom://toggle-desktop   # hide or show the Desktop tile
open transom://split-finder     # Split with New Finder Window
open transom://zoom-out         # zoom out to all windows
open transom://step-out         # zoom out one level
open transom://step-in          # zoom in one level
open transom://back             # previous view
open transom://forward          # next view
open transom://pan-left         # also pan-right, pan-up, pan-down
open transom://frame-window     # frame the focused window, or toggle back
open transom://frame-desktop    # frame the Desktop, or toggle back
open transom://overview         # open or close the overview
open transom://next-tab         # also previous-tab, move-out-of-group (focused tab group)
open transom://view/3          # go to saved view 3 (1-9)
open transom://save-view/3     # save the current view to slot 3
open transom://dock-column-1   # also dock-column-2, -3, -4, dock-column-middle
open transom://dock-row-1      # also dock-row-2, -3, -4, dock-row-middle
```

Zoom URLs act on the display under the pointer. Dock URLs act on the focused window.

Debug builds register `transom-debug://` instead.

### Command-line tool

Transom ships a `transom` command that runs the same commands as the `transom://` URLs and reports errors with an exit code. Install it with:

```sh
sudo mkdir -p /usr/local/bin && sudo ln -sf /Applications/Transom.app/Contents/Helpers/transom /usr/local/bin/transom
```

Run `transom help` to see every command. It never starts Transom: if Transom isn't running it says so and exits with code 2.

### Hotkeys

These are the default global hotkeys. Rebind any of them in the Shortcuts window (status menu ▸ Zoom ▸ Shortcuts…).

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
| `⇧⌃⌥⌘1–4` | Dock the focused window to the 1st–4th column, left to right |
| `⇧⌃⌥⌘5` | Dock the focused window to the middle half column |
| `⇧⌃⌥⌘6–9` | Dock the focused window to the 1st–4th row, top to bottom |
| `⇧⌃⌥⌘0` | Dock the focused window to the middle half row |
| `⌃⌥⌘N` | Split with New Finder Window |
| `⌃⌥⌘P` | Pause or Resume Arranging |
| `⌃⌥⌘E` | Don't Arrange the frontmost app (toggle) |
| `⌃⌥⌘0` | Restore All Windows |
| `⌃⌥⌘A` | Show Overview (or close it) |
| `⌃⌥⌘T` / `⇧⌃⌥⌘T` | Next / previous tab in the focused tab group |
| `⌃⌥⌘L` | Move the focused window out of its tab group |
| `⌃⌥⌘O` | Zoom Out to All Windows |
| `⌃⌥⌘,` | Zoom Out One Level |
| `⌃⌥⌘.` | Zoom In One Level |
| `⌃⌥⌘[` | Back to the previous view |
| `⌃⌥⌘]` | Forward to the next view |
| `⌃⌥⌘Home` / `End` / `PgUp` / `PgDn` | Pan left / right / up / down (fn⌃⌥⌘ arrows on a laptop) |
| `⌃⌥⌘M` | Frame the focused window, or toggle back |
| `⌃⌥⌘G` | Frame the Desktop, or toggle back |
| `⌥1–9` | Go to view 1–9 |
| `⇧⌥1–9` | Save view 1–9 |

On macOS 15.0 and 15.1 the defaults are ⌃⌥1–9 and ⇧⌃⌥1–9. If ⌥ with a number types a character you need on your keyboard, rebind them in Shortcuts.

## Planned features

Phase 9 is not in the code yet. Each line summarises the goal in `.planning/ROADMAP.md`.

| Phase | Feature | Status |
|---|---|---|
| 9 | Polish & Ship: a Settings window (gaps, appearance, gestures, hotkeys, exclusions, Mission Control replacement, New Windows, Drag to Dock), first-run onboarding, launch at login, an update check against GitHub Releases, a Homebrew cask, and a `transom://settings` URL that opens a given Settings section. | Planned |

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel (release builds are universal)
- The Accessibility permission, which Transom needs to move other apps' windows. The Set Up Transom window walks you through granting it.

Screen Recording is optional. It is used only for window snapshots in the zoom overlay; without it, zoom draws app-colour and icon tiles. macOS 15 and later re-ask for Screen Recording about once a month.

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
| `scripts/vm-cli-check.sh` | Builds "Transom Debug.app" and checks its `transom` command's exit codes against the running app inside a Tart VM. |

Signing notes:

- The scripts and `xcode/project.yml` hard-code the maintainer's Developer ID team. A fork must change it to its own team.
- macOS keys the Accessibility grant to the app's code signature. A stable signature keeps the grant across rebuilds, while ad-hoc signing resets it on every build. The separate Debug bundle ID keeps development and release grants apart.
- Notarising needs notarytool credentials stored once in the keychain, under the profile name set in `scripts/release.sh`.

## Project layout

| Target | Kind | Role |
|---|---|---|
| `TransomModel` | library | The pure layout model: nested split tree with weights, the Desktop layer, tab groups, desks keyed by display and Space, resolving tiles to non-overlapping rects with minimum sizes, undo and versioned JSON. Foundation only. |
| `TransomEngine` | library | Behaviour with no UI: the Arranger, the one `Command` enum every route dispatches, drag sessions, window tracking and classification, crash recovery, layout restore, the `transom://` parser and the `WindowSystem` protocol. |
| `TransomMac` | library | The AppKit layer: Accessibility window system, event tap, hotkeys, status menu, overlays (drop preview, gap handles, toasts), the zoom stage and snapshot capture, the Shortcuts window, permission flow, stores and conflict handling. |
| `TransomPrivate` | library | Every private API, each behind a fallback (see Private APIs). |
| `TransomApp` | executable | The app entry point; it starts `TransomMac`. |
| `TransomFixtureApp` | executable | A test fixture that opens real windows of every shape the integration tests need and reports their IDs and frames. |
| `transom-cli` | executable | The `transom` command-line tool, shipped at `Contents/Helpers/transom`. It sends commands to the running app over a local message port and never starts the app. |
| `transom-dump` | executable | Records one window of a running app as a redacted, labelled case for the window classifier's test corpus. |
| `TransomTestSupport` | library | `FakeWindowSystem`, a simulated window system for headless engine tests. |

Test targets: `TransomModelTests`, `TransomEngineTests`, `TransomMacTests` and `TransomMacIntegrationTests`.

Two rules shape the layout:

- `TransomModel` and `TransomEngine` never import AppKit, Cocoa, SwiftUI or another UI framework, so they can be tested headless. `scripts/check-no-appkit.sh` enforces this in CI, and `Tests/TransomModelTests/NoAppKitTests.swift` runs the same check inside `swift test`.
- ScreenCaptureKit is used only in `Sources/TransomMac/Zoom/SnapshotCapture.swift`, and `NoScreenCaptureTests` enforces it, so tiling never depends on Screen Recording.
- Each private API lives in its own file in `TransomPrivate`, is loaded at runtime rather than linked, and has a fallback, because any macOS update can break it.

## Testing

`swift test` runs the headless suites (model, engine and Mac unit tests) on any Mac, with no permissions needed. CI (`.github/workflows/ci.yml`, on `macos-26`) runs `scripts/check-no-appkit.sh`, then `swift build` and `swift test` in both debug and release.

The live Accessibility suites in `Tests/TransomMacIntegrationTests` skip unless the process is trusted for Accessibility and `TRANSOM_LIVE=1` is set. They open and move real windows, so run them only inside a Tart macOS VM through `scripts/vm-live-test.sh`, never on your own Mac:

```sh
scripts/vm-live-test.sh <filter> [VAR=value ...]
scripts/vm-live-test.sh FixtureShapesTests
```

The script builds the test bundles on the host without running them, copies them into the VM and runs them there with `TRANSOM_LIVE=1`. `TRANSOM_VM`, `TRANSOM_VM_USER` and `TRANSOM_VM_KEY` override the VM name, the SSH user and the SSH key. Their defaults are in the script header. The VM's SSH session needs the Accessibility grant.

`scripts/vm-session.sh` starts a stopped VM for one command and stops it after, as in `TRANSOM_VM=<vm> scripts/vm-session.sh scripts/vm-live-test.sh <filter>`. `scripts/vm-bundle-check.sh <suite>` runs a suite against the real `Transom Debug.app`, built into its own folder and copied into the VM.

## Private APIs

| API | File | Used for | Fallback when missing or disabled |
|---|---|---|---|
| `_AXUIElementGetWindow` | `Sources/TransomPrivate/AXWindowID.swift` | The window ID behind an Accessibility window | Matching windows by frame against the public window list |
| SkyLight Spaces (`SLSCopySpacesForWindows`, `SLSManagedDisplayGetCurrentSpace`) | `Sources/TransomPrivate/SkyLightSpaces.swift` | Which Space each window is on, and each display's current Space | Single-Space behaviour |
| SkyLight symbolic hotkeys (`SLSSetSymbolicHotKeyEnabled`, `SLSIsSymbolicHotKeyEnabled`) | `Sources/TransomPrivate/SymbolicHotKeys.swift` | Turning Mission Control's shortcuts off while Replace Mission Control is on, and back on | Replace Mission Control is unavailable |
| CoreDock (`CoreDockSendNotification`) | `Sources/TransomPrivate/CoreDock.swift` | Opening macOS Mission Control when the overview can't open while Replace Mission Control is on | A beep and a message instead |
| MultitouchSupport (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart`/`Stop`) | `Sources/TransomPrivate/MultitouchSupport.swift` | Reading the pinch from the trackpad when Trackpad ▸ "Zoom in or out" is off | Gestures come from the event tap only; with "Zoom in or out" off, ⌥-pinch is unavailable. Switched off automatically if Transom crashed while it was running |

All five are reached through `dlopen` and `dlsym`, never linked, so a removed symbol leaves only that feature degraded and Transom still launches. A capability whose function keeps failing is switched off for the rest of the session. To test a fallback, launch with `--disable-private=AXWindowID,Spaces,Multitouch,SymbolicHotKeys,CoreDock` (any of the names). `Sources/TransomPrivate/Capabilities.swift` logs each capability as available or off under the `private` log category, and logs any unknown name.

The SkyLight Spaces lookup now also reads each display's list of Spaces (`SLSCopyManagedDisplaySpaces`) for the overview strip. Without it, Transom learns which windows share a Space from the Spaces you visit, and hides the strip.

## Data stored

Files in `~/Library/Application Support/Transom`:

| File | Contents |
|---|---|
| `layout.json` | Schema 3: one set of layouts per display arrangement (up to 16), keyed by display UUID and macOS Space UUID. A schema 1 or 2 file is migrated on first load. If Spaces are renumbered after a restart, the file is backed up first as `layout.json.pre-rekey-<time>`. The layouts (desks, tile trees including tab groups, Desktop tiles, floating tab groups under `groups`, and saved views under `views`), each moved window's pre-park and wanted frames, and a session record used to detect a crash on the next launch. Window titles are written so windows can be matched to their tiles after a restart; the file is readable only by you. The first relaunch after upgrading from an older version has no saved titles yet, so windows are matched by position and order that once. |
| `min-size-hints.json` | Minimum window sizes Transom has learned, per app bundle ID. Only bundle IDs and sizes, nothing per window. |

Both files are validated on load. A file that fails validation is moved aside with a `.corrupt` suffix and Transom starts empty. A `layout.json` from a newer schema is left untouched and nothing is saved that session.

Preferences in Transom's user defaults:

| Key | Contents |
|---|---|
| `excludedBundleIDs` | The Don't Arrange list |
| `gap` | The gap between tiles |
| `newWindows` | Whether new windows float or tile (`float`, `tile`; default `float`) |
| `dragToDock` | Whether docking regions show on every drag or only while ⌥ is held (`automatic`, `holdOption`; default `automatic`) |
| `conflictNotNow` | macOS conflicts you chose not to be asked about again |
| `windowManagerOriginals` | The original values of the macOS window settings Transom changed, for Restore macOS Window Settings |
| `zoomEnabled` | Whether zoom is on (default on) |
| `zoomPreviewExplainerShown` | Whether the one-time Screen Recording explainer has been shown |
| `zoomTitleBarDoubleClick` | Whether title-bar double-click frames the window (on) or keeps macOS's own action |
| `tabs.confirmCloseGroup` | Whether Close Group asks first (false after "Do not show this again") |
| `takeover.enabled`, `takeover.explained`, `takeover.originals` | Whether Replace Mission Control is on, whether its explanation was shown, and the original Mission Control shortcut settings to restore |
| `privateCanary.Multitouch`, `privateCanary.MissionControl` | Crash markers: set while multitouch or the takeover runs, so a crash turns that feature off on the next launch |
| `freezeTestPID` | Debug builds only: the app paused by the Debug menu's freeze test, so it is resumed after a crash |
| `KeyboardShortcuts_<name>` | Hotkey bindings, stored by the KeyboardShortcuts library |

When you choose Turn Off for a macOS conflict, Transom writes only these boolean keys in the `com.apple.WindowManager` domain: `GloballyEnabled` (Stage Manager), `EnableTilingByEdgeDrag` and `EnableTopTilingByEdgeDrag` (edge tiling), and `EnableStandardClickToShowDesktop` (click wallpaper).

## Privacy

- Without Screen Recording, Transom does not read window contents or capture the screen. With it granted and zoom on, Transom takes one-shot snapshots of on-screen windows only to draw the zoom overlay. Snapshots stay in memory (a 128 MB cache), are never written to disk, and use no continuous stream, so the macOS screen-sharing indicator never shows.
- The zoom overlay itself is visible to system screen recordings on macOS 15.
- It has no network code and sends nothing anywhere.
- Through Accessibility it reads window metadata: each app's window list and, per window, role, subrole, modal, main, minimised and fullscreen state, identifier, title, position, size, title-bar buttons and child elements. To split with a new Finder window it presses Finder's menu item through Accessibility, with no Apple Events.
- Window titles help classify windows, match windows when the private window-ID lookup is off, and label rows in the Debug menu's Tracked Windows list. The only place they are written is `layout.json`, readable only by you, to match windows to their tiles after a restart.
- Logs go to the macOS unified log under the `com.eightabyte.transom` subsystem.

## Clean room

Transom is inspired by the commercial app TrellisWM and contains no code, text or assets from it. Its implementers work from a feature spec and public prior art, never from the TrellisWM binary. No code is copied from AeroSpace, Amethyst, yabai or Loop either. Loop is GPL-3.0, which is incompatible with Transom's MIT license, so it is read for patterns only.

## License

Transom is MIT licensed. See [LICENSE](LICENSE).
