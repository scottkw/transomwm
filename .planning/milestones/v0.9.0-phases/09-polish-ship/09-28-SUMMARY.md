---
phase: 09-polish-ship
plan: 28
subsystem: release
tags: [release, dmg, gatekeeper, notarization, vm-uat]
status: complete
requires: [09-27]
provides: ["public notarised v0.9.0 (DMG + .sha256)", "clean-VM DMG install verification on macOS 15.7"]
affects: [09-UAT.md]
tech-stack:
  added: []
  patterns: ["browser-style quarantine on a curl download for Gatekeeper checks in the VM"]
key-files:
  created: []
  modified: [.planning/phases/09-polish-ship/deferred-items.md]
decisions:
  - "Kept the shared ~/Library/Application Support/Transom in the pane-test guest during the 0.3.0 cleanup (Transom Debug and the live tests use it)"
metrics:
  duration: "about 40 min (Tasks 2-3, including the guest-cleanup checkpoint)"
  completed: 2026-11-08
actuals:
  tokens: 3000
  tasks: 3
  commits: 2
plan_head_before: 06fcdfbb82fbf6f5b41c876056f5bc9ba88d5845
plan_head_after: a8e7648f58d1c40cfd84a969f08c6f44c8e2bb74
---

# Phase 9 Plan 28: Ship v0.9.0 and verify the DMG install Summary

v0.9.0 is public as GitHub's latest release. Its API digest matches the `.sha256` file, which downloads without credentials. On a clean macOS 15.7.7 guest, a download with the quarantine attribute a browser sets matches that `.sha256`. Gatekeeper accepts both the DMG and the installed app as Notarized Developer ID, and the app's designated requirement is the committed one.

## Tasks

| Task | Name | Commit | Result |
|------|------|--------|--------|
| 1 | Tag, release run, publish as latest | (maintainer and orchestrator) | Done. v0.9.0 tagged on main (7c4510a). Run https://github.com/scottkw/transomwm/actions/runs/42445497219 passed (gate + release). Published with `gh release edit v0.9.0 --draft=false --latest` (D-28). The orchestrator's local checks passed: shasum, spctl Notarized Developer ID, DR, version 0.9.0, x86_64 + arm64. |
| 2 | Public release, digest, credential-free download | ee4e34b | releases/latest is v0.9.0, not draft or prerelease. Both assets are uploaded. The digest `sha256:73f49423…3b80` equals the `.sha256` fetched with plain curl. The release notes don't mention "brew" or "Homebrew". `issues/new` answers 302. |
| 3 | Clean DMG install in pane-test (macOS 15.7.7) | a8e7648 | See the list below. |

Task 3 results in pane-test (macOS 15.7.7):
- `shasum -c` printed OK.
- spctl accepted the DMG (`-t open`) and `/Applications/Transom.app` (`-t exec`), both as Notarized Developer ID, Ken Scott (S2K7P43927).
- `designated =>` equals `xcode/designated-requirement.txt`.
- The app's quarantine attribute is `0081;6aeffaa2;Safari;`, carried over from the image.
- There is no `Caskroom/transom` folder, so Transom treats this as a disk-image install.

Logs (untracked):
- `.build/09-28-t2.log`
- `.build/09-28-vm.log`
- `.build/09-28-vm-precheck.log`
- `.build/09-28-vm-inventory.log`

## Deviations from Plan

**1. [Precondition unmet, resolved by the user] Old Transom 0.3.0 in the guest**
- **Found during:** Task 3. Its clean-guest precondition ran at the front of the guest command, so the run stopped with exit 3 before installing anything.
- **What was there:** `/Applications/Transom.app` 0.3.0, installed Oct 27.
- **Fix:** I returned a blocking-human checkpoint. I declined an orchestrator-only "remove" decision. Once the user's own "remove 0.3.0" came back, a Claude Code safety check blocked my guest `rm -rf` command, and that command never ran.
- **Who did the cleanup:** the user ran it in the guest:
  - quit Transom
  - removed `/Applications/Transom.app`
  - `defaults delete com.eightabyte.transom` and removed its plist
  - `tccutil reset All com.eightabyte.transom`, which answered "No such bundle identifier" because the app was already gone
- **Left in place:** `~/Library/Application Support/Transom`. Transom Debug uses the same path and wrote these files.
- **Recorded in:** deferred-items.md, 09-28.

Apart from this, Task 3 ran its `<automated>` verify as written, on the first run after the cleanup.

## Human checks for verify-work (09-UAT.md)

**In the pane-test VM** (start it with its window: `tart run pane-test`):
1. Open Transom from Applications.
   - Allowed: at most macOS's standard confirmation for an app downloaded from the Internet. The quarantine attribute is present, so expect that confirmation.
   - Never acceptable: "cannot be opened", "unidentified developer" or "Apple could not verify".
2. Onboarding starts at Welcome.
3. Grant Accessibility and finish onboarding with "Open Transom at login" ticked. Then Settings ▸ Updates → Check for Updates says "Transom 0.9.0 is up to date."
4. Choose Apple menu ▸ Shut Down with "Reopen windows when logging back in" unticked, and start the VM again with `tart run pane-test`. After the automatic login, Transom's menu-bar icon is there without opening it by hand.

Caveats for the guest checks:
- The shared `layout.json` may give the first launch a restored layout.
- If the Accessibility prompt does not appear, an old TCC grant for the release bundle may have survived the cleanup. Reset it from System Settings ▸ Privacy & Security ▸ Accessibility, or note it.

**On the host** (UI-SPEC host checklist; answer pass or describe):
1. Settings… shows seven tabs, and Gaps agrees with the menu.
2. Menu Bar controls work: Back, Saved Views, reorder, Icon only.
3. `open "transom://settings?pane=updates"` opens Updates, and Check for Updates reports 0.9.0 or newer.
4. Report a Problem… opens a GitHub new-issue page with versions and no window titles or app names. The same details are on the clipboard.
5. A collapsed block shows icon, title and "Collapsed".

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: .planning/phases/09-polish-ship/deferred-items.md (09-28 heading, "Notarized Developer ID" x2, "quarantine" x4)
- FOUND: ee4e34b, a8e7648 (ancestors of HEAD)
- VM: pane-test stopped, no tart process, no `.build/transom-vm.lock`
