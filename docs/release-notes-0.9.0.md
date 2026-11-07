# Transom 0.9.0

The first public release of Transom, a free, open-source (MIT) window manager for macOS in which windows never overlap. Drag a window to a screen edge or to another window's edge and it docks into a tile; Transom keeps the tiles arranged as windows open, close and resize.

## Requirements

- macOS 14 (Sonoma) or later
- Apple silicon or Intel (the build is universal)
- The Accessibility permission. Screen Recording is optional: it only adds live window pictures to the zoomed-out view.

## Install

- Homebrew: `brew install --cask scottkw/transom/transom`
- Or download `Transom-0.9.0-universal.dmg` below, open it, and drag Transom to Applications. Transom is Developer ID-signed and notarized by Apple.

To check the download, put the DMG and `Transom-0.9.0-universal.dmg.sha256` in the same folder and run:

```sh
shasum -a 256 -c Transom-0.9.0-universal.dmg.sha256
```

It should print `Transom-0.9.0-universal.dmg: OK`.

## What Transom does

- **Docking and nested tiles.** Drag to dock, nest tiles as deep as you like, dock to halves, corners, thirds and fourths from the keyboard, float any window, and undo layout changes. Closing or minimising a window reflows its neighbours.
- **Zoom.** Zoom out to see every window on a display, step in and out one level, go back and forward through earlier views, or ⌘⇧-drag a rectangle to zoom to it. Zoom can be turned off entirely.
- **Trackpad gestures.** Hold ⌥ and pinch or pan over any app; over the wallpaper no ⌥ is needed.
- **Overview and Spaces.** ⌃⌥⌘A shows every window on every display and Space. One layout per display and Space, remembered across restarts and display changes.
- **Tab groups.** Drop a window onto another and hold to group them under one tab strip, from any apps.
- **Saved views.** ⇧⌥1–9 saves a view and ⌥1–9 goes back to it.
- **`transom://` URLs and the `transom` command-line tool** run every command from scripts and launchers.

## New in this release

- **Settings** (⌘, from the Transom menu): General, Arranging, Zoom & Gestures, Shortcuts, Exclusions, Menu Bar and Updates. `transom://settings?pane=updates` and `transom settings updates` open a given tab.
- **First-run setup** walks you through moving Transom to Applications, Accessibility, optional Screen Recording, opening at login and turning off macOS features that move windows.
- **Launch at login**, from setup or Settings ▸ General.
- **Update check.** Transom asks GitHub for the latest release when it opens and once a day (turn this off in Settings ▸ Updates). Download and Open checks the disk image's SHA-256, Developer ID team and notarization before opening it.
- **Homebrew cask** in the `scottkw/transom` tap. A Homebrew install is told to run `brew upgrade --cask transom`.
- **Menu bar controls.** Optional Back, Forward and saved-view buttons next to the Transom icon, set up in Settings ▸ Menu Bar.
- **Report a Problem…** opens a GitHub issue with your Transom and macOS versions (never window titles or app names).
- A highlight color that follows your macOS accent color or a color you choose, an app icon and menu-bar glyph, and labels on collapsed blocks.

## Fixes

- On macOS 27, closing a window whose app keeps it alive (common with document and preference windows) now frees its tile. Before, Transom kept the window tracked.
- Closing a whole native tab group whose app keeps the windows alive now frees the group's tile. Before, Transom kept the group tracked on macOS 27 and macOS 15.

## Known issues

- Testing so far has used a single display. The multi-display re-checks (unplug and re-plug, per-arrangement layouts, "Displays have separate Spaces" off, Tab between displays in the overview) are outstanding, so treat behaviour on a second display as unverified.
- Transom has been tested on macOS 15 and macOS 27, not on macOS 14.
- An external Magic Trackpad is untested; the built-in trackpad is tested.
