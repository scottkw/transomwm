# AX-dump corpus

Recorded windows of real apps, each with a label a person chose. `ClassifierCorpusTests` checks that
`Classifier.classify` gives every case its label (D-07, WIN-05). The tests also check that the corpus
still covers the required apps, families and kinds, and that no file holds personal data.

## Schema (`CorpusCase`, schemaVersion 1)

| Key | Meaning |
|-----|---------|
| `schemaVersion` | 1. `CorpusCase.decode` rejects newer versions and files over 64 KiB |
| `case` | the file name without `.json`: lower-case letters, digits and `_` |
| `capturedOn` | `macOS`, the app's `appVersion` (CFBundleShortVersionString), `date` (YYYY-MM-DD) |
| `app` | `bundleID`, `family` (`native`, `electron`, `java` or `office`), `activationPolicy`, `hidden` |
| `window` | the `WindowSnapshot` the live system classifies, with the CG fact (`cg`) merged in by window ID |
| `title` | `{ "redacted": true, "length": N }` only |
| `expected` | `kind` (`dockable`, `neverDock` or `notAWindow`), optional `reason` (a `NeverDockReason`), `confirmedBy` |

## Redaction rules

- The window title is stored only as its length.
- `AXIdentifier` is kept only if it is one of the known developer identifiers
  (`ClassifierOverrides.standard.neverDockIdentifiers`: `open_quickly`, `com.mitchellh.ghostty.quickTerminal`).
  Any other identifier is dropped because it may name a document.
- `AXDocument`, URLs, paths, `AXDescription` and tab titles are never read.
- The test fails on any home-directory path or on a `"title"` that holds a string.

## Label policy

- The label comes from `--label` and describes what the window is: a main document, browser or editor
  window is `dockable`; settings, info, dialog and panel windows are `neverDock`; the Finder desktop is
  `notAWindow`. Never run the classifier first and copy its answer (RESEARCH Pitfall 6).
- New cases start as `confirmedBy: "executor-proposed"`. The developer reviews each one and changes it to
  `"developer"`. A wrong label is a review item, never an automatic update.
- If a correct label fails the test, fix the classifier or its override table rather than the label.
  `libreoffice_start_center` did this: the Start Center is LibreOffice's resizable main window but has
  no fullscreen button, so `org.libreoffice.script` joined `fullscreenButtonOptional`.

## Capture procedure

From a terminal that has the Accessibility grant:

```bash
swift build --product transom-dump
open -b <bundleID>                      # or open -a <App>
.build/debug/transom-dump --app <bundleID> --list
.build/debug/transom-dump --app <bundleID> --window <index> --label <dockable|neverDock[:<reason>]|notAWindow> \
    --family <native|electron|java|office> --case <name>
```

`--list` prints index, role, subrole, frame and CG layer (never titles). The case goes to this directory
unless `--out <dir>` is given. transom-dump exits 64 without `--label` and 3 when the process is not trusted.

Settings windows and Finder tabs were opened by pressing menu items through AX from the trusted terminal
(no Apple Events, so no Automation prompt). An app's menu items are only pressable while it is frontmost.

## Cases captured on 2026-10-24 (macOS 27.0.1)

| Case | App | Label | Note |
|------|-----|-------|------|
| `finder_main_window` | Finder 27.0 | dockable | one tab |
| `finder_two_tabs` | Finder 27.0 | dockable | `tabGroup.tabCount` 2 |
| `finder_desktop` | Finder 27.0 | notAWindow | the desktop `AXScrollArea`; no window ID, so no `cg` |
| `safari_browser_window` | Safari 27.0.1 | dockable | |
| `safari_settings` | Safari 27.0.1 | neverDock | AXStandardWindow without a fullscreen button |
| `terminal_window` | Terminal | dockable | |
| `terminal_settings` | Terminal | neverDock | AXDialog |
| `system_settings` | System Settings | neverDock | no fullscreen button; never-dock by default (Assumption A10) |
| `vscode_main_window` | VS Code (electron) | dockable | |
| `android_studio_welcome` | Android Studio 2024.1 (java) | dockable | the Welcome window is a resizable standard window with enabled zoom and fullscreen buttons, so it is labelled dockable |
| `libreoffice_start_center` | LibreOffice 24.2.5.2 (office) | dockable | see Label policy |

## Still to capture by hand

- Picture-in-picture from Safari or Chrome. It needs a playing video: start one, enter PiP, run
  `--list`, then capture the PiP window with `--label neverDock --family native --case safari_pip`
  (or `chrome_pip`).
