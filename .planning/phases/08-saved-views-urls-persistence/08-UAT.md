---
status: testing
phase: 08-saved-views-urls-persistence
source: [08-VERIFICATION.md, 08-UI-SPEC.md host checklist, 08-REVIEW-FIX.md human-verification items]
started: 2026-11-03
updated: 2026-11-03
---

## Current Test
Host item 1.

## Build under test
- Code: `1466f8b` and later docs commits.
- App: `xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, binaries dated 2026-11-03 21:29.

## Host checks (the user runs these, one at a time)

| # | Check | Covers | Result |
|---|---|---|---|
| 1 | Relaunch the new build: layout returns. ⇧⌥3 shows "Saved view 3", ⌥3 goes back, ⌥4 beeps and shows "No view in slot 4" | VIEW-01, chords, toasts, schema 3 upgrade | pending |
| 2 | Split or move a window, then ⌥3. Quit and relaunch Transom, then ⌥3 again | VIEW-02 | pending |
| 3 | Save a view on Desktop 2, go to it from Desktop 1. The Space switches and the camera stays on the saved view | D-03, focus-widen risk | pending |
| 4 | ⌘Q a real app with docked windows: dim "Waiting for {App}…" tile, clicks pass through. Reopen within 30 s: tiles refill. ⌘Q again and do not reopen: tile closes after 30 s. Switch Spaces with one showing | D-12a, D-13, WR-06, A1 | pending |
| 5 | Terminal: symlink per the README, `transom view 3; echo $?` (0), `transom nope; echo $?` (64), `open transom://view/3`, quit Transom, `transom view 3; echo $?` (2) | VIEW-03, VIEW-05, URL via LaunchServices | pending |
| 6 | VoiceOver: ⌥3 reads one joined "View 3…" line | D-04 | pending |
| 7 | Real reboot with a docked tile on Desktop 2. Layout returns, each window in its own tile. Visit Desktop 2: that tile refills | VIEW-04, CR-02, CR-03, D-12b | pending |

Not run (no way to check here, recorded as accepted unless the user can run them): a second physical display; a failed Space switch; a non-US keyboard layout (optional in item 1); a stored display arrangement applied after a reboot (needs a second display).

## Automated results (2026-11-03)
- Host `swift test`: 1,856 tests, no ✘. `scripts/check-no-appkit.sh` OK.
- VM at or after the review fixes: Rematch 3/3, Views 2/2, QuitRestore 3/3, Recovery 2/2, TabGroup 7/7, `vm-cli-check` 15 checks.
- Flake: Rematch's Finder step failed once on a freshly booted, loaded guest and passed on re-run; cause not established.
