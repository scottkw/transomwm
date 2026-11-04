---
status: testing
phase: 08-saved-views-urls-persistence
source: [08-VERIFICATION.md, 08-UI-SPEC.md host checklist, 08-REVIEW-FIX.md human-verification items]
started: 2026-11-03
updated: 2026-11-04
---

## Current Test
Host item 6 (VoiceOver), the only check left for the user. Items 3, 4, 5, 7 ran in the VM on macOS 15.7.7 and are to be repeated on a macOS 27 VM.

## Build under test
- Code: `1466f8b` and later docs commits.
- App: `xcode/.xcode-build/Build/Products/Debug/Transom Debug.app`, binaries dated 2026-11-03 21:29.

## Host checks (the user runs these, one at a time)

| # | Check | Covers | Result |
|---|---|---|---|
| 1 | Relaunch the new build: layout returns. ⇧⌥3 shows "Saved view 3", ⌥3 goes back, ⌥4 beeps and shows "No view in slot 4" | VIEW-01, chords, toasts, schema 3 upgrade | pass (2026-11-04) |
| 2 | Split or move a window, then ⌥3. Quit and relaunch Transom, then ⌥3 again | VIEW-02 | pass (2026-11-04) |
| 3 | Save a view on Desktop 2, go to it from Desktop 1. The Space switches and the camera stays on the saved view | D-03, focus-widen risk | pass in VM, 15.7.7 (2026-11-04) |
| 4 | ⌘Q a real app with docked windows: dim "Waiting for {App}…" tile, clicks pass through. Reopen within 30 s: tiles refill. ⌘Q again and do not reopen: tile closes after 30 s. Switch Spaces with one showing | D-12a, D-13, WR-06, A1 | pass in VM, 15.7.7 (2026-11-04); look of the tile not seen |
| 5 | Terminal: symlink per the README, `transom view 3; echo $?` (0), `transom nope; echo $?` (64), `open transom://view/3` (`transom-debug://` on a Debug build), quit Transom, `transom view 3; echo $?` (2) | VIEW-03, VIEW-05, URL via LaunchServices | pass in VM, 15.7.7 (2026-11-04) |
| 6 | VoiceOver: ⌥3 reads one joined "View 3…" line | D-04 | pending |
| 7 | Real reboot with a docked tile on Desktop 2. Layout returns, each window in its own tile. Visit Desktop 2: that tile refills | VIEW-04, CR-02, CR-03, D-12b | pass in VM, 15.7.7 (2026-11-04) |

Not run (no way to check here, recorded as accepted unless the user can run them): a second physical display; a failed Space switch; a non-US keyboard layout (optional in item 1); a stored display arrangement applied after a reboot (needs a second display).

## Automated results (2026-11-03)
- Host `swift test`: 1,856 tests, no ✘. `scripts/check-no-appkit.sh` OK.
- VM at or after the review fixes: Rematch 3/3, Views 2/2, QuitRestore 3/3, Recovery 2/2, TabGroup 7/7, `vm-cli-check` 15 checks.
- Flake: Rematch's Finder step failed once on a freshly booted, loaded guest and passed on re-run; cause not established.

## VM run of items 3, 4, 5, 7 (2026-11-04)
Bundled Debug app, real chords posted in the guest, real apps (Script Editor, Dictionary). Guest macOS 15.7.7; the host is 27.2, so these do not prove macOS 27.
- Item 3: ⌥5 from Space 1 switched to Space 3. Dictionary stayed framed at 1008x672 at +4 s and +8 s, with no widening.
- Item 4 (settles WR-06/A1 for this app): after ⌘Q, panels sat at each tile. Reopening filled each window's own tile. Quit, then 40 s on another Space: panels hidden and tiles kept. Back on the desk, tiles were gone by about 36 s later. Panels have sharingType none, so screenshots cannot show the tile's look; click-through is from the Rematch VM test.
- Item 5: exit codes 0, 64, 1, 2 from the installed symlink. `open transom-debug://save-view/6` then `transom view 6` exit 0.
- Item 7: real `shutdown -r`. macOS reopened Dictionary and an Untitled Script Editor window. Script Editor documents refilled their own tiles, Untitled floated, Dictionary kept its Desktop 2 tile, ⌥5 worked, boot session updated. Not run: a Desktop 2 tile whose app does not come back after a reboot (engine tests only).
- Finding: `open` launched a second Transom Debug from a stale registered copy, alongside the running one. There is no single-instance guard, so two copies of the same bundle ID run together. Not fixed.
