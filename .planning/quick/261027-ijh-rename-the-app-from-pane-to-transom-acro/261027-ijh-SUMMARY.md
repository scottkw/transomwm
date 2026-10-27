---
phase: quick-261027-ijh
plan: 01
subsystem: build, app identity, docs
tags: [rename, transom, swiftpm, xcodegen, codesign]
status: complete
requires: []
provides:
  - Transom* SwiftPM package, targets and test targets
  - Signed Transom.app (com.eightabyte.transom, team S2K7P43927, scheme transom)
affects: [all future phases, release pipeline, VM live tests]
tech-stack:
  added: []
  patterns: [token-anchored Perl rename rules R1-R6, git mv for every path]
key-files:
  created:
    - .planning/quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/261027-ijh-SUMMARY.md
  modified:
    - Package.swift
    - xcode/project.yml
    - xcode/Transom-Info.plist (renamed)
    - xcode/Transom.entitlements (renamed)
    - Sources/** and Tests/** (8 + 4 target directories renamed)
    - scripts/build-debug.sh, scripts/release.sh, scripts/vm-live-test.sh, scripts/check-no-appkit.sh, scripts/generate.sh, scripts/run-debug.sh
    - .github/workflows/ci.yml
    - .claude/CLAUDE.md, PLAN.md, .planning/PROJECT.md, .planning/ROADMAP.md, .planning/REQUIREMENTS.md
decisions:
  - Kept keychain profile pane-notary (stored credential; renaming needs App Store Connect credentials)
  - Kept Tart VM default pane-test and SSH key ~/.ssh/pane_vm_ed25519 (existing host resources)
  - ROADMAP Phase 9 criterion 6 rephrased to avoid the generic noun "pane" so the Phase 4-9 gate holds; REQUIREMENTS SHIP-08 keeps `?pane=` and "Settings pane"
metrics:
  duration: 6 min (wall clock from the start marker)
  completed: 2026-10-27
actuals:
  tokens: 78000
  tasks: 3
  commits: 2
plan_head_before: 882e81c14f45223cdc4df7a15d83c1f67ec4b9f9
plan_head_after: 0d33bba4fa101db8238efa2388f515e0d115db59
---

# Quick 261027-ijh: Rename Pane to Transom Summary

Pane is now Transom everywhere outside history: Transom* SwiftPM modules (moved with git mv), bundle IDs com.eightabyte.transom(.debug), the transom:// scheme, the com.eightabyte.transom logger subsystem, ~/Library/Application Support/Transom, TRANSOM_* env vars and build/Transom-<version>.dmg. A Developer ID-signed Transom.app builds and the 534 headless tests pass.

## Commits

| Task | Commit | Subject |
|------|--------|---------|
| 1 | 221fd39 | refactor: rename Pane to Transom (modules, bundle IDs, transom:// scheme, data folder, scripts) |
| 2 | 0d33bba | docs: rename Pane to Transom in project docs and living planning docs |
| 3 | none | The audit found no missed rename, so no fix commit was needed |

## Gate results

- Task 1 gate: passed (GATE1-PASS).
  - `swift build`: Build complete.
  - Headless `swift test`, with every PANE_* and TRANSOM_* live variable unset: `✔ Test run with 534 tests in 53 suites passed`, the same as the baseline.
  - `scripts/check-no-appkit.sh`: `no-appkit: OK (40 files)`.
  - `scripts/build-debug.sh --release` → `/Users/ken/dev/panewm/xcode/.xcode-build/Build/Products/Release/Transom.app`.
  - Designated requirement: `designated => anchor apple generic and identifier "com.eightabyte.transom" and (... certificate leaf[subject.OU] = S2K7P43927)`.
  - Info.plist values: CFBundleIdentifier com.eightabyte.transom, version 0.3.0, URL scheme `transom`, binary archs `x86_64 arm64`.
  - `scripts/release.sh --build-only` → `/Users/ken/dev/panewm/xcode/.xcode-build/Build/Products/Release/Transom.app`, which is valid and satisfies its designated requirement. It was not notarised and not uploaded.
  - No tracked path outside .planning contains "pane" except inside "panel". The case-insensitive "panel" count is still 348.
  - The only `transoml` hits are in this task's PLAN.md, where the gate text itself mentions the word.
- Task 2 gate: passed (GATE2-PASS). The docs commit touches exactly the five doc files. ROADMAP lines 15-17 and 27-201 have no hunks, and no history artifact changed.
- Task 3 gate:
  - The residual audit returns only allow-listed lines.
  - The code-scope token audit, with the three kept names masked, is empty.
  - `swift package dump-package` shows `"name" : "Transom"` and no Pane*/pane-* names.
  - `swift package resolve` leaves the tree clean. Package.resolved did not change; KeyboardShortcuts stays at 3.1.0 / 772133d9.
- `git log --follow -- Sources/TransomEngine/TransomURL.swift` reaches 61cb457 (test(03-15)), which is before the rename.
- No Transom or fixture process was launched. `pgrep -fl 'TransomFixtureApp|PaneFixtureApp'` is empty.

## Allow-listed leftovers (actual grep output)

These come from `git grep -niw pane` and `git grep -n 'Pane[A-Z]'`, run outside the history paths.

**scripts/release.sh**: the keychain profile. It is a credential already stored in the user's keychain. A comment above `profile=` explains why it keeps its name.
```
scripts/release.sh:6:# `xcrun notarytool store-credentials pane-notary`.
scripts/release.sh:30:profile=pane-notary
```

**scripts/vm-live-test.sh**: the Tart VM default name and the SSH key. Both are existing host resources, and a comment above `vm=` explains this. `-w` does not report the key, so it is listed separately.
```
scripts/vm-live-test.sh:6:# Env: TRANSOM_VM (tart VM name, default pane-test), TRANSOM_VM_USER (default admin), TRANSOM_VM_KEY (default ~/.ssh/pane_vm_ed25519).
scripts/vm-live-test.sh:16:vm="${TRANSOM_VM:-pane-test}"
scripts/vm-live-test.sh:17:key="${TRANSOM_VM_KEY:-$HOME/.ssh/pane_vm_ed25519}"
```

**.planning/REQUIREMENTS.md SHIP-08**: `?pane=` and "Settings pane" are the generic UI noun.
```
.planning/REQUIREMENTS.md:123:- [ ] **SHIP-08**: `transom://settings?pane=` opens a specific Settings pane
```

**.planning/PROJECT.md**: the Key Decisions row that records the rename itself.
```
.planning/PROJECT.md:57:| Name "Pane" → "Transom" | "Pane" is taken by several Mac window managers. ...
```

**.planning/ROADMAP.md lines 15-17 and 27-201**: Phase 1-3 history, left untouched.
```
.planning/ROADMAP.md:15, 29, 38, 50, 60, 65, 66, 67, 68, 69, 78, 79, 110, 121, 122, 171, 196, 200
```
(Line 15: "Headless PaneModel"; 29: "As a Pane developer"; 38: "`PaneModel` builds"; 50: "PaneEngine target"; 60-69: Phase 2 success criteria naming Pane; 78: "Pane Debug.app / Pane.app"; 79: "pane-dump"; 110: "`PanePrivate` dlsym pattern"; 121/171/200: `pane://`; 122/196/200: "Pane".)

**.claude/CLAUDE.md after line 20**: the stack section. Following the orchestrator's amendment, every line that named this app's modules, paths, bundle ID, DMG, tap or app name now says Transom: lines 36, 53, 55, 66, 74-77, 90, 106, 109, 143, 146, 158 and 166. Two lines still contain "pane":
```
.claude/CLAUDE.md:65:| `xcrun notarytool` + `xcrun stapler` | ... `notarytool store-credentials pane-notary` once, then `submit --keychain-profile pane-notary --wait`. |
.claude/CLAUDE.md:175:- Log once with `os.Logger(category: "private")`, ... show the status in an About/Diagnostics pane.
```
- Line 65 keeps `pane-notary` because that is the real stored keychain profile, and it matches release.sh.
- Line 175 uses "pane" as the generic UI noun ("About/Diagnostics pane").
- Historical evidence text, such as the prior-art table and the dated sources, never named this app and is unchanged.
- Recommendation: this section is generated from `.planning/research/STACK.md`, which is history and still says Pane. The next GSD CLAUDE.md regeneration would bring the old names back. The user should decide whether to update STACK.md, or to stop regenerating this section from it.

## Kept-name decisions

- **pane-notary**: renaming it means re-running `xcrun notarytool store-credentials` with App Store Connect credentials the executor does not have.
- **Tart VM `pane-test` and `~/.ssh/pane_vm_ed25519`**: these name existing host resources, and the executor must not touch the VM. Only their env var names changed (TRANSOM_VM, TRANSOM_VM_USER, TRANSOM_VM_KEY). To rename them later, run `tart rename pane-test transom-test`, move the key pair, and update the two defaults.

## Deviations from Plan

1. **[Rule 3 - Gate conflict] ROADMAP Phase 9 success criterion 6 rephrased.** It read "`pane://settings?pane=` opens a given Settings pane". The Task 2 gate requires no `[Pp]ane([^l]|$)` anywhere from "### Phase 4" to "## Progress", so the generic noun could not stay there the way it does in REQUIREMENTS SHIP-08. It now reads "a `transom://settings` URL opens a given Settings section directly (query key as in SHIP-08)". The design itself is unchanged, and SHIP-08 stays the source of truth for the `?pane=` key.
2. **ROADMAP line 307** ("Check the name "Pane" for existing macOS apps before release") became "Transom". The check is still worth doing for the new name.
3. **PLAN.md module diagram re-aligned.** The longer names pushed the columns out of line, so the code block's column spacing was adjusted (lines 55-59).
4. **CLAUDE.md stack section updated**, following the orchestrator amendment and as described above.
5. **The rename was detected for every file except one.** `Sources/PaneApp/main.swift` shows as delete + add in commit 221fd39 because all 3 of its lines changed (`import TransomMac`, `TransomMacApp.run`). git mv was used, but git's similarity-based rename detection cannot pair a 3-line file whose every line changed. Every other file, including TransomURLTests.swift at 49%, is detected as a rename.

## Notes for the orchestrator

- graft/ is untracked and gitignored, so it was not edited.
- There is no README or LICENSE in the repo, and none was created.
- No panewm URLs were found in tracked files outside .planning.
- WINDOWS.md open entries 2 and 3 still cite `Sources/PaneMac/AXWindowSystem.swift` and `Sources/PaneMac/SessionGate.swift`. Those files now live under `Sources/TransomMac/`. WINDOWS.md was not edited because it is history.
- The Tart VM still has /Applications/Pane.app installed. vm-live-test.sh now quits and relaunches `Transom`, so a Transom build must be installed in the VM before the next live run.
- The new bundle ID resets the TCC Accessibility grant (and Screen Recording, when used) on the host and in the VM.
- The STATE.md "Pending: Rename to Transom" section and the "Name Pane" blocker are left to the orchestrator.
- The executor did not rename the GitHub repo to scottkw/transomwm or move ~/dev/panewm.
- The gitignored xcode/Pane.xcodeproj was deleted. XcodeGen now generates xcode/Transom.xcodeproj.
- Old data folders (~/Library/Application Support/Pane) on the host and in the VM are now ignored, and no migration was added (locked decision).

## Known Stubs

None introduced.

## Self-Check: PASSED

- FOUND: Package.swift, xcode/Transom-Info.plist, xcode/Transom.entitlements, Sources/TransomEngine/TransomURL.swift, Sources/TransomMac/TransomMacApp.swift, Tests/TransomMacIntegrationTests/IntegrationSupport.swift
- FOUND: 221fd39, 0d33bba (both ancestors of HEAD)
