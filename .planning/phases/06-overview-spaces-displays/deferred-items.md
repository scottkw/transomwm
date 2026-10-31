# Phase 06 deferred items

## 06-12: intermittent Esc failure in the VM overview suite

- Test: `OverviewIntegrationTests.overviewOpensPerDisplayAndCloses` (the Esc check, line 66: "Esc did not close the overview").
- Seen: it failed in the first two VM runs of 06-12 (`.build/0612-vm-OverviewIntegrationTests.log`, `...-rerun.log`) and then passed three times with the test unchanged (run alone once, whole suite twice: `...-alone.log`, `...-final.log`, `...-after-idle.log`). It last passed at 06-09 (15:57), and no overview code changed after that.
- Ruled out: suite parallelism (the suite is `.serialized` and this test runs first), guest screen saver and display sleep (both off), leftover processes in the guest (none). A diagnostic run showed `holdsKeys` already true right after the overview reopens.
- Unknown: why the posted Esc missed the key panel in those two runs. A possible cause is WindowServer key focus lagging AppKit's `isKeyWindow`, but this is not shown. 06-UAT backstop item covers pressing Esc right after the overview opens on real hardware.
- Not fixed: no change can be tied to a cause yet. Next step if it recurs: log the WindowServer key window (CGWindowList owner of the key window) at the moment Esc is posted.
