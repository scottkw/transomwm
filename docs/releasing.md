# Releasing Transom

GitHub Actions builds every release. A `vX.Y.Z` tag runs `.github/workflows/release.yml`, which
builds the universal app, signs it with Developer ID, notarises and staples the app and the DMG,
checks that the in-app updater accepts the DMG and creates a **draft** release with
`Transom-X.Y.Z-universal.dmg` and its `.sha256`. Claude (or the maintainer) publishes it after checking the draft; no approval step (D-28). Pushes and pull requests run the test suite (`.github/workflows/ci.yml`).
Homebrew is deferred for 0.9.0 (Phase 9 D-26): `.github/workflows/tap.yml` runs only by hand; see Homebrew tap.

## Before the first release (one time)

1. **Make `scottkw/transomwm` public** (D-19). While it is private, `releases/latest` returns 404
   to everyone else, so the in-app updater silently finds nothing and the
   Report a Problem link opens a page nobody can see.
2. **Create the `release` environment** (Settings, Environments, New environment, `release`):
   - No required reviewer (D-28): the gate job, the branch/tag policy and the tag ruleset are the guards.
   - Deployment branches and tags: selected only, `main` and the tag pattern `v*`.
3. **Add the five secrets to that environment** (see Secrets).
4. **Add the tag ruleset** (Settings, Rules, Rulesets, New tag ruleset), name "Release tags:
   maintainer only", active, targeting `refs/tags/v*`, with "Restrict creations", "Restrict
   updates" and "Restrict deletions". Bypass list: the Repository admin role, always. Keep the
   admin role to the maintainer.
5. Run a dry run (below) and check it goes green.

## Cutting a release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `xcode/project.yml`. That is the
   only version source; `scripts/release.sh` and the tag gate read it.
2. Write `docs/release-notes-X.Y.Z.md`. It becomes the release body, and the gate refuses a tag
   without it.
3. Check locally: `scripts/release-version.sh vX.Y.Z` prints `X.Y.Z`.
4. Merge to `main` and wait for CI to go green.
5. Dry run on `main` (see Dry run) if anything in the release path changed since the last release.
6. Tag `main` and push the tag:

   ```sh
   git fetch origin
   git tag vX.Y.Z origin/main
   git push origin vX.Y.Z
   ```

7. The `release` job starts on its own once the gate job passes (no approval, D-28). The gate refuses a
   tag that is not on `main`.
8. When the run is green, open the draft (Releases), check the DMG, its `.sha256` and the notes,
   then publish it and mark it latest in one step:

   ```sh
   gh release edit vX.Y.Z --draft=false --latest
   ```

   Publishing from the web page alone left a gifsmith release unmarked, and `releases/latest`
   (which the in-app updater reads) kept returning the previous version. Check:

   ```sh
   curl -s https://api.github.com/repos/scottkw/transomwm/releases/latest | grep tag_name
   ```

   Installed copies see the update once `releases/latest` returns the new tag.

The `gate` job refuses, before any credential is touched, when the tag is not exactly `v` plus
`MARKETING_VERSION`, the release notes are missing, the commit is not on `main`, or a published
release for the tag exists. Its read-only token cannot see drafts, so the `release` job's first
step refuses a tag that already has any release, draft included. That also covers "Re-run failed
jobs", which skips the gate: delete the old draft before re-running.

The `release` job, in order: pins Xcode 26.6 and installs XcodeGen (asserting 2.46.0; if Homebrew
has moved on, check the new version and update the pin), turns Gatekeeper assessments on, creates
a temporary keychain with the Developer ID identity and stores the notary profile
`transom-notary` from the API key, runs `TRANSOM_NOTARY_PROFILE=transom-notary scripts/release.sh`,
deletes the keychain, runs `UpdateRealDMGTests` against the built DMG, and creates the draft.
`release.sh` refuses an app whose designated requirement differs from
`xcode/designated-requirement.txt`: a different one would cost every user the Accessibility grant.

## Dry run

Builds, signs, notarises and verifies on a runner without creating a release. The gate still
refuses a ref that is not on `main`, and the run still pauses for your approval:

```sh
gh workflow run release.yml --repo scottkw/transomwm --ref main
```

The log ends with `dry run, no release created`.

### Locally

`scripts/release.sh --skip-notarize` runs everything except notarising and stapling and needs no
credentials; `--build-only` stops after the verified app. A full local run notarises with the
keychain profile `pane-notary` (its pre-rename name; `TRANSOM_NOTARY_PROFILE` overrides it).
Nothing is uploaded.

## Secrets

Five secrets live in the `release` environment, so only the `release` job, after your approval,
can read them. Only its keychain step uses them.

| Secret | Holds |
|--------|-------|
| `MACOS_CERT_P12_BASE64` | base64 of the "Developer ID Application: Ken Scott (S2K7P43927)" certificate and private key, exported from Keychain Access as .p12 |
| `MACOS_CERT_PASSWORD` | the export password of that .p12 |
| `NOTARY_KEY_P8_BASE64` | base64 of the App Store Connect Team API key (.p8) used for notarisation |
| `NOTARY_KEY_ID` | that API key's Key ID |
| `NOTARY_ISSUER_ID` | the App Store Connect Issuer ID |

Set them (the plain ones prompt without echoing):

```sh
base64 -i cert.p12 | gh secret set MACOS_CERT_P12_BASE64 --env release --repo scottkw/transomwm
gh secret set MACOS_CERT_PASSWORD --env release --repo scottkw/transomwm
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_P8_BASE64 --env release --repo scottkw/transomwm
gh secret set NOTARY_KEY_ID --env release --repo scottkw/transomwm
gh secret set NOTARY_ISSUER_ID --env release --repo scottkw/transomwm
```

Delete the exported .p12 afterwards.

### Rotating

- Signing certificate: export a fresh .p12, set `MACOS_CERT_P12_BASE64` and `MACOS_CERT_PASSWORD`
  as above. A certificate from the same team keeps the designated requirement; anything else fails
  `release.sh` on purpose.
- Notary API key: create a new Team key in App Store Connect (Users and Access, Integrations, App
  Store Connect API), set `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID` (and `NOTARY_ISSUER_ID` if it
  changed), then revoke the old key.
- Run a dry run after any rotation.

## Homebrew tap (deferred, D-26)

Not used for 0.9.0. To turn it on later: create `scottkw/homebrew-transom`, the `tap` environment and
`HOMEBREW_TAP_TOKEN` as below, add `release: types: [published]` back to `tap.yml`'s triggers, and put
the `brew install --cask` line back in the README and release notes.

`tap.yml` downloads the published `Transom-X.Y.Z-universal.dmg` and its `.sha256`, hashes the DMG,
requires that hash to match the `.sha256` asset (and the release API's asset digest), renders
`packaging/homebrew/transom.rb.template` and pushes `Casks/transom.rb` to
`scottkw/homebrew-transom`. A re-run with the same version and hash changes nothing. It skips a
prerelease and refuses any tag that is not `releases/latest`, so mark the release latest when you
publish it, and a re-run cannot move the cask back to an older version.

`HOMEBREW_TAP_TOKEN` is a fine-grained personal access token with **Contents: read and write on
`scottkw/homebrew-transom` only**, nothing else. It lives in the `tap` environment, not in the
repository secrets, so a workflow edited on some other branch cannot read it. Only `tap.yml` uses it.

Create the environment (Settings, Environments, New environment, `tap`) with deployment branches
and tags set to selected only, `main` and the tag pattern `v*` (a published release runs on its
tag, a re-run from Actions on `main`). A required reviewer is optional. Then set the token:

```sh
gh secret set HOMEBREW_TAP_TOKEN --env tap --repo scottkw/transomwm
```

If the token was a repository secret before, delete that copy:
`gh secret delete HOMEBREW_TAP_TOKEN --repo scottkw/transomwm`.

Users install with `brew install --cask scottkw/transom/transom`. The cask has no `auto_updates`:
Transom's updater downloads the DMG but you install it, so `brew upgrade` keeps managing the cask.
Its `uninstall` removes the "Transom" login item; a Debug build registers its own
"Transom Debug" login item, which the cask never touches.

## CI notes

- `ci.yml` fails a pull request that changes `PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom`,
  `DEVELOPMENT_TEAM: S2K7P43927` or `CODE_SIGN_IDENTITY: "Developer ID Application"` in
  `xcode/project.yml`. PRs can't sign, so this is the cheap guard for the designated requirement.
- **Keep test arguments short.** Swift Testing prints every argument of a parameterised test on one
  log line, and GitHub's log viewer drops everything after a very long line, including the failure
  that follows it. A run can look as if it stopped with no message.
- **Parallel tests (D-21, D-27).** CI runs `swift test` in parallel. An earlier "silent early exit"
  on the runner was the log truncation above hiding a real failure, not a crash: a full parallel run
  (2349 tests, 16.8 s) showed one ordinary failing test. If a run seems to stop with no message, look
  for a very long log line before assuming a crash.

## macOS betas

Before claiming support for a new macOS, run [macos-beta-checklist.md](macos-beta-checklist.md): it lists
every private symbol Transom resolves and how to check each one on the beta.

## Name check (D-18, D-20)

Checked 2026-11-06, before the first public release:

- No Homebrew cask or formula is named `transom` (`Casks/t/transom.rb` in homebrew-cask and
  `Formula/t/transom.rb` in homebrew-core both 404).
- No Mac App Store app named Transom turned up. The App Store has an iPad app, "Transom Note-Taker
  for Writers" (Void Media), which can run on Apple silicon Macs.
- Several unrelated GitHub repos are named transom, among them macOS apps: a clipboard manager, a
  brightness controller, a browser-profile manager and a remote-windows tool. That is a naming
  overlap, not a trademark finding.
- The user kept the name Transom on 2026-11-06 (D-20). `transomwm.app` is registered.
