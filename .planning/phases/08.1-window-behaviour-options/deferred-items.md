
## Found during 08.1-06

- `Tests/TransomMacTests/FreezeTestTests.swift` `itResumesByItself` failed once in a full `swift test` run (`.build/081-06-t3-full.log`): its 1 s deadline passed before a 50 ms resume timer ran. It passed 3 of 3 alone and in a full re-run. Likely timing under load, not reproduced, not fixed. 08.1-06 didn't touch this code.

## Found during 08.1-07

- **Fixed in 986890d (WR-03).** `Sources/TransomEngine/Arranger+NewWindows.swift` `autoTile`: a window that already had focus when Transom launched isn't in `focusOrder` until focus changes, because `.windowFocused` fires only on a change. In the real app, a window docked by `transom-debug://dock-column-1` right after launch didn't count as the focused tile, so the next new window went beside the largest tile, the Desktop, not beside it. Seen on both OSes in `OptionsBundleIntegrationTests`, which pins neither way. The tile is still valid and doesn't overlap, so this isn't fixed here. A fix would seed `focusOrder` at the first sweep, which also touches swap and view navigation.
- `scripts/vm-cli-check.sh` leaves the Finder window from `open "$HOME"` open in the guest: the plan asked for the rest of the script to stay as it is, and closing a Finder window over SSH needs Apple Events or a posted key. It's harmless to the suites, which track fixtures or open a fresh folder.
- `FreezeTestTests.itResumesByItself` did not recur in 08.1-07's one full `swift test` run.
