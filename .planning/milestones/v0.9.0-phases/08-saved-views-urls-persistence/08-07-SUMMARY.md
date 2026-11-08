---
phase: 08-saved-views-urls-persistence
plan: 07
subsystem: shell
tags: [cli, cfmessageport, vm-live, tart, readme, launchctl]

requires:
  - phase: 08-saved-views-urls-persistence
    provides: "08-05 the bundled tool at Contents/Helpers/transom and its exit codes; 08-06 placeholders on screen"
provides:
  - scripts/vm-cli-check.sh, which checks the built bundle's tool through a symlink against the real app in the VM
  - The measured answers to RESEARCH Assumptions A2 and A3
  - README documentation of every Phase 8 surface
affects: [08 UAT and /gsd-verify-work, Phase 9 release notes]

actuals:
  tokens: 6100
  tasks: 2
  commits: 3

plan_head_before: 37fa7b8d162ecb8354abab4471d91a4a9b79fb9b
plan_head_after: 610d7188348c0fc5b4c336cd06a3c41793cec045

tech-stack:
  added: []
  patterns:
    - "A VM check writes its guest half with a quoted heredoc and copies it in, so nothing needs double escaping"
    - "A VM check that runs the app saves and restores the guest's Application Support folder, which Debug and Release share"

key-files:
  created:
    - scripts/vm-cli-check.sh
  modified:
    - README.md
    - Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift

key-decisions:
  - "A2 measured: plain SSH reaches the app (exit 0), so the README has no SSH note"
  - "The check runs the tool with sudo launchctl asuser: as a normal user, asuser fails with 'Could not switch to audit session'"

patterns-established:
  - "Test clicks that must hit a window's content start 40 pt below its top, clear of the title-bar buttons"

requirements-completed: [VIEW-05, VIEW-03, VIEW-04]

coverage:
  - id: D1
    description: "The built bundle's tool, run through a symlink, returns 0, 1, 2 and 64 with the exact UI-SPEC messages against the real app over the real port"
    requirement: VIEW-05
    verification:
      - kind: e2e
        ref: "scripts/vm-cli-check.sh (.build/0807-t1-vm.log, 15 checks passed)"
        status: pass
    human_judgment: false
  - id: D2
    description: "transom save-view 4 and transom view 4 exit 0 against the running app"
    requirement: VIEW-03
    verification:
      - kind: e2e
        ref: "scripts/vm-cli-check.sh, checks 'save-view 4 exits 0' and 'view 4 exits 0'"
        status: pass
    human_judgment: false
  - id: D3
    description: "A2 (SSH reach) and A3 (bundle found through a symlink) measured on the guest"
    requirement: VIEW-05
    verification:
      - kind: e2e
        ref: ".build/0807-t1-vm.log, 'A2 plain-ssh exit=0' and 'PASS app answers within 10 s'"
        status: pass
    human_judgment: false
  - id: D4
    description: "The README carries the UI-SPEC's additions, the install line, the layout.json contents and the first-relaunch note"
    verification:
      - kind: other
        ref: "Task 2 verify and acceptance greps"
        status: pass
    human_judgment: false
  - id: D5
    description: "After a real reboot of the Mac, windows return to their tiles and a never-reopened app's tiles show the placeholder and close after 5 min"
    requirement: VIEW-04
    verification: []
    human_judgment: true
    rationale: "The plan assigns the real reboot to host UAT; the VM covers only the simulated reboot"
  - id: D6
    description: "The UI-SPEC user host checklist: toasts on screen, the README install line on a real install, and transom against the Release bundle"
    requirement: VIEW-05
    verification: []
    human_judgment: true
    rationale: "The VM check asserts exit codes and text, not what appears on screen, and it runs the Debug bundle; the checklist goes to /gsd-verify-work"

duration: 7min
completed: 2026-11-04
status: complete
---

# Phase 8 Plan 07: The Installed CLI in the VM, and the README Summary

**The signed bundle's `transom` tool, installed through a symlink, returned every UI-SPEC exit code and message against the real app in the Tart VM (15 checks), and the README now documents views, the tool and the new layout.json.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-11-04T01:40:48Z
- **Completed:** 2026-11-04T01:47:56Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `scripts/vm-cli-check.sh` builds a fresh Debug bundle here, runs nothing here, and checks the tool in the guest over the real port.
- Every check ran, none fell to the host checklist: `save-view 4` and `view 4` both exited 0.
- The README has the two URLs, the two hotkey rows and the note, the Command-line tool section, the layout.json row and the first-relaunch note.

## Results the plan asked for

**A2, SSH reach: plain SSH works.** `A2 plain-ssh exit=0` on both runs, on guest macOS 15.7.7. An exit of 0 comes only from the app's `ok` reply, so the call did reach it. This holds even though `launchctl managername` over SSH prints `Background`, so the README has no SSH note. It was not measured on any other macOS version.

**A3, bundle through a symlink: confirmed.** The tool, run through `~/transomcli/bin/transom`, reached `com.eightabyte.transom.debug.cli`. Outside a bundle it would have named the Release port and got no answer.

**Conditional checks:** `view 7` replied "No view in slot 7", so `save-view 4` and `view 4` ran and passed. Nothing was skipped.

**Limit of these checks:** an exit of 0 is the app's reply. No check looked at the screen, so the toast and the move itself stay with the host checklist. `ViewsIntegrationTests` covers view behaviour separately.

## VM logs

- `.build/0807-t1-vm.log`: `scripts/vm-cli-check.sh`, 15 checks passed. This is the tracer gate's re-run after the commit.
- `.build/0807-ViewsIntegrationTests.log`: 2 tests passed.
- `.build/0807-RematchIntegrationTests-1.log`, `-2.log`: 3 tests passed on each run, after the fix below. The failing run is `.build/0807-RematchIntegrationTests.log`.
- Host: `.build/0807-swift-test.log`, full `swift test` passed (226, 430, 100 and 1070 tests, no "✘"), before the one-line test fix. `scripts/check-no-appkit.sh`: OK.

Neither the app nor the tool ran on this Mac. Afterwards the guest had no `~/transomcli`, no Debug app and no fixtures running, and the VM is stopped.

## Task Commits

1. **Task 1: Tracer, the installed tool against the real app** - `222d99c` (test). The tracer gate re-ran its verify after the commit and passed.
2. **Task 2: README** - `1830969` (docs)
3. **Phase gate fix: the placeholder click test** - `610d718` (fix)

## Files Created/Modified

- `scripts/vm-cli-check.sh` - the VM check
- `README.md` - Phase 8 documentation
- `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift` - click point moved below the title bar

## Decisions Made

See `key-decisions`. VIEW-03, VIEW-04 and VIEW-05 are marked complete because this plan's checks passed, as the orchestrator allowed. VIEW-04's real reboot is still open in host UAT (coverage D5).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `launchctl asuser` needs root**
- **Found during:** Task 1
- **Issue:** The plan runs `launchctl asuser "$(id -u)" …`. As the guest's normal user that exits 1 with "Could not switch to audit session 0x186a2: 1: Operation not permitted", so every check would have failed.
- **Fix:** `sudo -n launchctl asuser "$uid" sudo -n -u "$user" "$cli" …`. A probe showed `Aqua` as the manager name and that exit codes pass through.
- **Files modified:** `scripts/vm-cli-check.sh`
- **Verification:** `launchctl managername` inside it prints `Aqua`; the 15 checks pass
- **Committed in:** `222d99c`

**2. [Rule 1 - Bug] The placeholder click test clicked a close button on an empty guest**
- **Found during:** the plan's phase gate
- **Issue:** `aPlaceholderIsClickThroughAndBehindRealWindows` failed at Point(24, 49). The VM had just booted, so no guest window covered the tile, and the first clear point was 16 pt into the fixture window, on its close button by position. The fixture stayed on window 0. The test passed in 08-06 when guest windows moved the point elsewhere. The close-button reading is inferred from the position and the fix, not observed directly.
- **Fix:** The grid starts 40 pt below the tile's top.
- **Files modified:** `Tests/TransomMacIntegrationTests/RematchIntegrationTests.swift`
- **Verification:** `RematchIntegrationTests` passed 3 of 3 tests on two runs in a row
- **Committed in:** `610d718`

**3. [Rule 1 - Bug] README lines the new behaviour made false**
- **Found during:** Task 2
- **Issue:** The Privacy section said titles are never written to disk. The Status section said Phase 8 is next and listed Phase 7 as planned, and "Planned features" said none of its rows are in the code.
- **Fix:** Corrected all four. The Phase 8 status row reads "Built, final checks pending", because host UAT is outstanding, while its "Planned features" row reads "Done" as the plan asked.
- **Files modified:** `README.md`
- **Committed in:** `1830969`

**4. [Rule 2 - Missing critical] Guest clean-up beyond the plan's trap**
- **Found during:** Task 1
- **Issue:** Debug and Release share `Application Support/Transom`, so the run would have changed the installed app's layout.json. The `zoomEnabled` default and the LaunchServices record would also have stayed behind.
- **Fix:** The guest half saves and restores the folder and the default, unregisters the copy and removes `~/transomcli`. It also refuses to start if a Debug app is already running, rather than quit one it did not launch.
- **Files modified:** `scripts/vm-cli-check.sh`
- **Committed in:** `222d99c`

### Smaller additions

- The README also gained rows for `scripts/vm-cli-check.sh` and the `transom-cli` target, and the Debug submenu's three new lines.
- The hotkey rows follow the table's column order, hotkey first, where the UI-SPEC lists the command first.
- The script deletes the built Debug `.app` before building, per 08-05's stale-helper note.

---

**Total deviations:** 4 auto-fixed (1 blocking, 2 bugs, 1 missing critical)
**Impact on plan:** All needed for the checks to run, the phase gate to pass or the README to be true. No scope creep.

## Issues Encountered

`requirements.mark-complete` reported VIEW-04 as `not_found`, because 405f2fe had set its row to "In Progress" by hand and the tool only moves Pending rows. The row was set to Pending and the tool re-run, and it marked VIEW-04 complete.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 8's plans are all done. `/gsd-verify-work` still has to cover:
- the real reboot (D5) and the UI-SPEC user host checklist (D6);
- 08-06's look of a placeholder and Space changes with one shown, and 08-04's ⌘Q of a real app.

---
*Phase: 08-saved-views-urls-persistence*
*Completed: 2026-11-04*

## Self-Check: PASSED
