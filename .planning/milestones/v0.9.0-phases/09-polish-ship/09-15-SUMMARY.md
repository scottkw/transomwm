---
phase: 09-polish-ship
plan: 15
subsystem: release-ci
status: complete
tags: [github-actions, notarization, homebrew, ci]
requires: [09-13, 09-14]
provides:
  - tag-triggered signed, notarised draft release (release.yml)
  - cask bump on publish (tap.yml + packaging/homebrew/transom.rb.template)
  - PR signing-identity guard and D-21 parallel diagnostic (ci.yml)
  - maintainer release runbook (docs/releasing.md)
affects: [09-27, 09-28]
tech-stack:
  added: []
  patterns:
    - gifsmith gate/release split (no-secrets gate, release environment, temporary keychain, keychain deleted before tests)
    - github.* values reach run scripts only through env
    - only GitHub's own actions, pinned by full SHA
key-files:
  created:
    - .github/workflows/release.yml
    - .github/workflows/tap.yml
    - packaging/homebrew/transom.rb.template
    - docs/releasing.md
  modified:
    - .github/workflows/ci.yml
decisions:
  - "release.yml gate checks main ancestry for dispatch dry runs too (gifsmith): a dry run signs and notarises, so it may only build main"
  - "release.yml requires a 'Test run with N>=1 tests ... passed' line after swift test --filter UpdateRealDMGTests, since an empty filter also exits 0"
  - "tap.yml no-ops through git diff --cached --quiet (same version and hash), validates the tag as vX.Y.Z before it reaches sed"
  - "ci.yml parallel diagnostic tees the full swift test log into the uploaded artifact, because GitHub's log viewer drops the rest of a very long Swift Testing line (likely cause of the D-21 'early exit')"
metrics:
  duration: ~25 min
  completed: 2026-11-07
actuals:
  tokens: 6100
  tasks: 3
  commits: 3
plan_head_before: 96fbb5ff865a46c10539157e51368c5eaae4b38e
plan_head_after: e31c34aca69df605a486559f18853a5a68aec0ec
---

# Phase 9 Plan 15: Release and tap workflows Summary

A `vX.Y.Z` tag now runs a no-secrets gate, then a reviewer-gated `release` job that signs with a temporary keychain, notarises through `TRANSOM_NOTARY_PROFILE=transom-notary scripts/release.sh`, deletes the keychain, checks the DMG with `UpdateRealDMGTests` and creates a draft release with the DMG and its `.sha256`. Publishing the release runs `tap.yml`, which checks the published DMG's hash and pushes a Rectangle-style cask to `scottkw/homebrew-transom`. All of this was checked statically only; no workflow was run.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Tracer: release.yml, from a v tag through the gate to a draft release | 5f43925 | .github/workflows/release.yml |
| 2 | tap.yml and the cask template | 05896ec | .github/workflows/tap.yml, packaging/homebrew/transom.rb.template |
| 3 | CI identity guard, D-21 diagnostic, runbook | e31c34a | .github/workflows/ci.yml, docs/releasing.md |

## Verification (static only)

- Task 1: `.build/09-15-t1.log` = `ok` (YAML parses, `gate` and `release` jobs exist, `environment: release`, `needs: gate`). All 14 required strings are present. Actions pinned by SHA: 2. `@vN` pins: 0. `run:.*${{` lines: 0.
- Task 2: the cask rendered with 0.9.0 and 64 zeros is valid Ruby (`.build/09-15-t2.log`: Syntax OK). `tap.yml` parses. All six cask lines are present. `auto_updates`: 0. `homebrew-transom` in tap.yml: 2.
- Task 3: `.build/09-15-t3.log` = `ok` (ci.yml has `workflow_dispatch`). `swift test --no-parallel`, the team guard, `--draft=false --latest` and `HOMEBREW_TAP_TOKEN` are all present.
- Extra checks:
  - Every `run:` block in the three workflows was pulled out with Ruby. None contains `${{`, and all pass `shellcheck`.
  - The CI identity guard passes on the current `xcode/project.yml`.
  - The guard fails, with a `::error::`, on a copy where the team ID was changed.
- **Not run:** the workflows themselves. GitHub Actions on this private repo is blocked by a billing or spending limit, and the plan forbids triggering them anyway. The first real runs are the 09-27 dry run and the v0.9.0 tag. `actionlint` is not installed. `brew style` refused a cask that is not inside a tap. That `brew style` attempt reinstalled and pruned the style gems in Homebrew's own vendored bundle, which is harmless.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] YAML plain-scalar colon in the dry-run step**
- **Found during:** Task 1. The verify parse failed.
- **Issue:** `run: echo "dry run: no release created"` is not valid YAML: a `: ` inside a plain scalar.
- **Fix:** changed it to `run: echo 'dry run, no release created'`. `docs/releasing.md` quotes the new text.
- **Commit:** 5f43925

**2. [Rule 2 - Correctness] Filter gate for UpdateRealDMGTests**
- **Issue:** `swift test --filter` exits 0 when no test matches, so the step could pass without verifying anything.
- **Fix:** the step tees the output and requires a `Test run with N tests ... passed` line with N ≥ 1.
- **Commit:** 5f43925

**3. [Rule 2 - Consistency] ci.yml checkout pinned by SHA**
- **Issue:** `actions/checkout@v5` broke this plan's rule that actions are pinned by SHA.
- **Fix:** pinned it to gifsmith's v7.0.1 SHA and added `persist-credentials: false`. ci.yml also gained `defaults.run.shell: bash`, so the tee pipeline uses pipefail.
- **Commit:** e31c34a

**4. [Orchestrator note] Log-truncation finding**
- Recorded in `docs/releasing.md` (CI notes): Swift Testing prints every test argument on one line, GitHub's log viewer drops the rest of a very long line, and the D-21 "early exit" was most likely a real failure hidden that way.
- The ci.yml shortcut comment says the same.
- The parallel dispatch uploads the full log as an artifact, so the log can be read in full.
- **Commit:** e31c34a

## Threat Flags

None beyond the plan's threat model. T-09-30..34 are mitigated as specified:
- Secrets are read only in the release-environment job, and `.p12`/`.p8` are removed right after import.
- The keychain is deleted before `swift test`.
- Inputs reach scripts only through env (checked by script extraction).
- The published DMG's hash must match the `.sha256` asset and the API digest.
- The tap token is scoped and used only in tap.yml.
- The PR identity guard is in place.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: .github/workflows/release.yml, .github/workflows/tap.yml, packaging/homebrew/transom.rb.template, docs/releasing.md, .github/workflows/ci.yml
- FOUND commits: 5f43925, 05896ec, e31c34a (ancestors of HEAD)
