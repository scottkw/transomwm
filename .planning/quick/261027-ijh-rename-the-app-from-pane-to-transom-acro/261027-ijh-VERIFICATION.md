---
phase: quick-261027-ijh
verified: 2026-10-27T18:55:00Z
status: passed
score: 7/7 must-haves verified
covered_files:
  - ".claude/CLAUDE.md"
  - ".github/workflows/ci.yml"
  - ".planning/quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/261027-ijh-PLAN.md"
  - ".planning/quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/261027-ijh-SUMMARY.md"
  - "PLAN.md"
  - "Package.swift"
  - "Sources/TransomApp/main.swift"
  - "Sources/TransomEngine/TransomURL.swift"
  - "Sources/TransomMac/AppDelegate.swift"
  - "Sources/TransomMac/MinimumHintsStore.swift"
  - "Sources/TransomMac/TransomMacApp.swift"
  - "Tests/TransomEngineTests/TransomURLTests.swift"
  - "Tests/TransomMacIntegrationTests/IntegrationSupport.swift"
  - "scripts/build-debug.sh"
  - "scripts/check-no-appkit.sh"
  - "scripts/generate.sh"
  - "scripts/release.sh"
  - "scripts/run-debug.sh"
  - "scripts/vm-live-test.sh"
  - "xcode/Transom-Info.plist"
  - "xcode/Transom.entitlements"
  - "xcode/project.yml"
covered_digest: "v3:sha256:87366041516441637271966b10159b72cd8105b5a2a865e0b9237764ac9c4051"
behavior_unverified: 0
overrides_applied: 0
---

# Quick 261027-ijh: Rename Pane to Transom, Verification Report

**Goal:** Rename the app from Pane to Transom across the repo: Transom.app, `com.eightabyte.transom` and `.transom.debug`, `transom://`, Application Support/Transom (no migration), Transom* modules, types and files, TRANSOM_* env vars, scripts and CI. Living docs only; .planning history unchanged; words containing "panel" untouched.
**Verified:** 2026-10-27
**Status:** passed
**Re-verification:** No (initial verification)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | swift build succeeds; the full headless swift test (no live var set) passes 534 tests, as at the baseline | VERIFIED | I ran `swift test` with every PANE_* and TRANSOM_* var unset. It ran four Swift Testing runs: 193 tests in 20 suites, 198 in 30, 42 in 20 (the integration suites, all skipped for "needs a process with the Accessibility grant") and 534 in 53. All passed, exit 0. Every run reported more than 0 tests. The four XCTest harness lines report 0 tests because there are no XCTest cases; they are not Swift Testing runs |
| 2 | Release Transom.app is signed as com.eightabyte.transom, team S2K7P43927; release.sh --build-only checks pass | VERIFIED | I did not rebuild it, because signing needs the keychain. I inspected the existing `xcode/.xcode-build/Build/Products/Release/Transom.app` read-only. Its binary was built at 13:35:23, 30 s before commit 221fd39 at 13:35:53. Designated requirement: `identifier "com.eightabyte.transom" ... leaf[subject.OU] = S2K7P43927`. It has a Developer ID authority and a secure timestamp, and `codesign --verify --strict` is OK. Archs are `x86_64 arm64`. Info.plist: version 0.3.0, CFBundleName Transom, URL name com.eightabyte.transom, scheme `transom`. The binary's strings contain no Pane/pane except "panel" |
| 3 | Every SwiftPM target, product, directory and test target is Transom*, moved with git mv so history follows | VERIFIED | `swift package dump-package` names the package `Transom` and the targets transom-dump, TransomApp, TransomEngine(+Tests), TransomFixtureApp, TransomMac(+Tests, +IntegrationTests), TransomModel(+Tests), TransomPrivate and TransomTestSupport. `git ls-files` outside .planning has no `[Pp]ane([^l]|$)` path. Commit 221fd39 has 214 R entries. The exceptions are in the Info section |
| 4 | transom:// (transom-debug://) via TransomURL / TransomURLRateLimiter; logger subsystem com.eightabyte.transom; data folder Application Support/Transom with no migration; TRANSOM_* env vars; .build/transom-vm.lock; build/Transom-<version>.dmg | VERIFIED | All 19 `Logger(subsystem:)` calls use `com.eightabyte.transom`. MinimumHintsStore.defaultDirectory is `appending(path: "Transom")`, and LayoutStore uses the same directory. No data-folder migration exists; Persistence.swift has only the old schema migrations. project.yml sets TRANSOM_URL_SCHEME to transom-debug for Debug and transom for Release, and Info.plist uses `$(TRANSOM_URL_SCHEME)`. AppDelegate uses `TransomURL.parse`. The env vars in the code are only TRANSOM_LIVE(_DRAG/_FULLSCREEN), TRANSOM_FIXTURE_APP and TRANSOM_VM(_USER/_KEY). release.sh has `dmg="build/Transom-$version.dmg"` and checks the scheme against `transom` |
| 5 | No word that merely contains "pane" changed: panel count 348, no "transoml" | VERIFIED | The panel count is 348 at both 82697cf and HEAD. The per-word counts of `*panel*` identifiers are identical before and after the rename. The only "transoml" hits are in this task's PLAN.md, which quotes the gate. No `Transom[a-rt-z]` run-on exists except `transomtests`, the intended VM directory (R5) |
| 6 | The only Pane leftovers are on the allow-list | VERIFIED | I ran the Task 3 audit greps (`-niw pane` and `Pane[A-Z]`, history excluded) through the allow-list filter, and they printed nothing. Code-scope leftovers are only pane-notary (release.sh:6, :30), and the VM default pane-test and pane_vm_ed25519 key (vm-live-test.sh:6, :16, :17). Doc leftovers are SHIP-08 (REQUIREMENTS:123), the PROJECT.md:57 rename decision row, ROADMAP Phase 1-3 history, and CLAUDE.md:65 (pane-notary) and :175 (generic "pane") |
| 7 | No .planning history artifact changed; one building code commit, then one docs commit | VERIFIED | Between 82697cf and HEAD, `.planning` changes are only PROJECT.md, REQUIREMENTS.md, ROADMAP.md and this task's PLAN.md. 0d33bba touches exactly the 5 doc files. ROADMAP hunks start at lines 1, 5, 22 and 230+, so none fall in 15-17 or 27-201 |

**Score:** 7/7 truths verified (0 present, behavior-unverified)

### Diff integrity (no non-name changes)

I took the pre-rename content of every file changed or renamed in 221fd39, including the two D+A pairs, and applied the plan's rename rules R1-R6 to it. Compared with the committed content, every file is byte-identical except for two added lines. Both are the comments the plan asked for:

- `scripts/release.sh`: `# The notary keychain profile was stored before the rename and keeps that name; ...`
- `scripts/vm-live-test.sh`: `# The VM name and SSH key defaults keep their pre-rename names: ...`

This matches the diffstat: 720 insertions against 718 deletions. The docs commit 0d33bba is word-level Pane→Transom substitution, plus the rephrased ROADMAP Phase 9 criterion 6 that the SUMMARY declares ("a `transom://settings` URL opens a given Settings section directly (query key as in SHIP-08)"). Package.resolved is unchanged.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Package.swift` | package Transom | VERIFIED | dump-package `"name" : "Transom"` |
| `xcode/project.yml` | bundle ID com.eightabyte.transom | VERIFIED | Release com.eightabyte.transom, Debug .debug, product TransomMac |
| `xcode/Transom-Info.plist` | `$(TRANSOM_URL_SCHEME)` | VERIFIED | present; URL name com.eightabyte.transom |
| `Sources/TransomEngine/TransomURL.swift` | parser and rate limiter | VERIFIED | used by AppDelegate:55 |
| `Sources/TransomMac/TransomMacApp.swift` | composition root | VERIFIED | `Sources/TransomApp/main.swift` calls `TransomMacApp.run` |
| `Sources/TransomMac/MinimumHintsStore.swift` | `appending(path: "Transom"` | VERIFIED | line 20; used by TransomMacApp:41, :58 |
| `scripts/release.sh` | `dmg="build/Transom-$version.dmg"` | VERIFIED | line 31 |
| `scripts/vm-live-test.sh` | `.build/transom-vm.lock` | VERIFIED | present |
| `Tests/TransomMacIntegrationTests/IntegrationSupport.swift` | TRANSOM_LIVE | VERIFIED | live gate under the new name; the suites skip headless |

### Key Link Verification

| From | To | Status | Details |
|------|----|--------|---------|
| project.yml `product: TransomMac` | Package.swift library TransomMac | WIRED | package `Transom` path `..` |
| Transom-Info.plist `$(TRANSOM_URL_SCHEME)` | project.yml TRANSOM_URL_SCHEME | WIRED | the built app's Info.plist resolves to `transom` |
| build-debug.sh / release.sh identifier | project.yml PRODUCT_BUNDLE_IDENTIFIER | WIRED | both use com.eightabyte.transom; the built app's DR matches |
| check-no-appkit.sh defaults | Sources/TransomModel, Sources/TransomEngine | WIRED | `no-appkit: OK (40 files)`, exit 0 |
| vm-live-test.sh staging | TransomMacIntegrationTests.xctest / TransomFixtureApp | WIRED | names are present (not run, by rule) |

### User-visible string spot-check (misses)

- Menu: `Quit Transom` (StatusItemController:95); accessibility labels "Transom", "Transom: Accessibility access needed", "Transom: arranging paused".
- Setup window: title `Set Up Transom`; "Quit Transom", "Transom is ready", "Let Transom arrange your windows".
- Notice and conflict copy: "Transom quit unexpectedly...", "Restore macOS Window Settings in the Transom menu".
- About: the app has no About copy in Sources/TransomMac/Shell, so there is nothing to rename.
- Logger: 19 of 19 calls use com.eightabyte.transom. Data path: Application Support/Transom. URL: TransomURL with the build's registered scheme. Info.plist keys: CFBundleURLName com.eightabyte.transom, CFBundleName Transom (built app).

No user-visible "Pane" remains in Sources/Tests/scripts/xcode/.github.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Headless test suite | `env -u PANE_* -u TRANSOM_* swift test` | 193 + 198 + 42 + 534 tests passed, exit 0 | PASS |
| No-AppKit guard | `scripts/check-no-appkit.sh` | `no-appkit: OK (40 files)` | PASS |
| Package graph | `swift package dump-package` | Transom, all targets Transom* | PASS |
| Signed artifact | `codesign -d -r-`, `codesign --verify --strict`, PlistBuddy, lipo | DR com.eightabyte.transom / S2K7P43927, valid, universal, 0.3.0, scheme transom | PASS |

### Probe Execution

Step 7c: not applicable. The task declares no probe scripts.

### Anti-Patterns Found

None were introduced. The only added lines are the two explanatory comments, and neither contains a debt marker.

### Info (non-blocking)

1. **The `git log --follow` claim is slightly overstated in the SUMMARY.** At git's default 50% similarity, two files show as delete plus add in 221fd39, and `git log --follow` stops at the rename commit:
   - `Sources/TransomApp/main.swift`: all 3 of its lines changed.
   - `Tests/TransomEngineTests/TransomURLTests.swift`: R049, which is under the default threshold. The SUMMARY says it "is detected as a rename" at 49%; that holds only with a lower `-M`.

   History is still reachable with `git log --follow -M30%` (TransomURLTests reaches 61cb457) and `git show -M1%`. This limit is inherent to git; there is no gap to fix.
2. **.claude/CLAUDE.md stack section was edited** (lines 36-166). Plan Task 2 said to leave it unchanged. The SUMMARY attributes the change to an orchestrator amendment, which I can't confirm from the artifacts. The result matches the "living docs" goal, but `.planning/research/STACK.md` still says Pane, so a future GSD CLAUDE.md regeneration would bring the old names back. The orchestrator or user should decide whether to update STACK.md.
3. **Untouched by design:** WINDOWS.md entries still cite `Sources/PaneMac/...` paths. The Tart VM has the old Pane.app installed. The new bundle ID resets TCC grants. STATE.md still has the "Pending: Rename to Transom" item. The repo rename to transomwm and the folder move are still to do. All of these are already listed in the SUMMARY as orchestrator follow-ups.

### Human Verification Required

None.

### Gaps Summary

No gaps. The rename is mechanical and complete. I replayed the plan's rename rules on every changed file, and the code commit matches them exactly except for the two required comments. Nothing containing "panel" changed, the headless suites pass at baseline counts, and the only Pane leftovers are the allow-listed host resources, the generic noun, and history.

---

_Verified: 2026-10-27_
_Verifier: Claude (gsd-verifier)_
