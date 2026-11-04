---
status: complete
phase: 08-saved-views-urls-persistence
source: [08-VERIFICATION.md, 08-UI-SPEC.md host checklist, 08-REVIEW-FIX.md human-verification items]
started: 2026-11-03
updated: 2026-11-04
---

## Current Test
None. All 7 items passed; a reboot on the user's own Mac was not required.

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
| 6 | VoiceOver: ⌥3 reads one joined "View 3…" line | D-04 | pass (2026-11-04) |
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

## VM run on macOS 27.2 (`pane-test-27`, 2026-11-04)
Same method as above, with a fresh guest. The app under test is the same Debug build.
- Item 3: pass. ⌥5 switched from Space 1 to Space 16, and Dictionary stayed framed at +4 s and +8 s.
- Item 4: pass, run three times. Waiting tiles after ⌘Q, each window back in its own tile on reopening, tiles kept for 40 s on a hidden Desktop, gone within 36 s of returning.
- Item 5: pass. Exit codes 0, 64, 1, 2, and URLs through LaunchServices. Plain SSH with no `launchctl asuser` also works on 27 (exit 2 with the app stopped, 0 with it running), which extends A2 to 27.
- Item 7, first attempts: not testable as is. The guest's display UUID changed on each of two reboots (8264526F, then 5E48442F, then F42A9510), so Transom saw a new display each time, quarantined the Desktop 1 desk and refused view 5 ("display not connected"). Whether a real display can do this was not measured. `pane-test` (15.7.7) kept its UUID.
- Live suites on 27: Views 1 of 2 and Rematch 2 of 3 pass, failing the same way on two runs each. `aViewOnAnotherSpaceSwitchesFirst`: "the Arranger never saw Desktop 1". `aPlaceholderIsClickThroughAndBehindRealWindows`: `frontmostApplication` is nil after the desktop click. Suspected cause: NSWorkspace state in the SSH-run test process on 27, because the real app did both flows. Not proven.
- Finding (low): an unanswered "Show window previews?" dialog on another Desktop pulls the user back. ⌃← logged 16 → 1, then 1 → 16 within a second, after the frontmost app quit. Closing the dialog fixed it. Seen on first zoom only; not tried on 15.7.7. The dialog can also sit hidden behind other windows.
- Item 7, with the display UUID carried over: pass. Headless made no difference: three more boots gave three new UUIDs, with vendor 0, model 0 and a placeholder serial. So after a real reboot, and before launching Transom, the old UUID was rewritten to the new one in the guest's layout.json. Everything else was real: boot-session guard, hint matching (score 140), Script Editor's tile back, Dictionary's tile on the hidden Desktop refilled when visited, ⌥5 working. An earlier boot in this run also renumbered Desktop 2 (16 to 4) and its desk was re-keyed by Space UUID. Only one tile on Desktop 1 and one on Desktop 2 were in this run; the two-tile case passed on 15.7.7.

## Accepted without a run
- A reboot on a real display: a real display's UUID staying the same is assumed, not measured.
- The two live tests failing on macOS 27 (above): both flows were done by the real app, except the desktop-click step.
