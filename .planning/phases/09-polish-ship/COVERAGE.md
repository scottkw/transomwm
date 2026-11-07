# API Coverage — GitHub REST API (Releases, Issues) and App Store Connect (notarisation)

> Full coverage by default. Opt-outs are explicit, reasoned decisions.
> Scope: the in-app updater (09-11..09-13, 09-17), Report a Problem (09-17), and the release and tap workflows (09-15, 09-27, 09-28).

| capability | decision | reason |
|---|---|---|
| releases-latest-get | INTEGRATE | |
| releases-conditional-etag | INTEGRATE | |
| release-asset-download | INTEGRATE | |
| release-asset-digest | INTEGRATE | |
| release-create-draft-ci | INTEGRATE | |
| release-publish-latest | INTEGRATE | |
| release-list-ci-guard | INTEGRATE | |
| release-download-tap-ci | INTEGRATE | |
| repo-contents-tap-push | INTEGRATE | |
| notary-store-credentials | INTEGRATE | |
| notary-submit-wait | INTEGRATE | |
| releases-list-in-app | OPT-OUT | not needed: the app only ever installs the latest published release (gifsmith design, D-09) |
| release-by-tag-in-app | OPT-OUT | not needed: Release Notes opens the release page URL built from the validated version |
| prerelease-channel | OPT-OUT | explicitly out of scope: drafts and prereleases are refused by design (gifsmith parity, D-09) |
| authenticated-requests | OPT-OUT | explicitly out of scope: the update check is unauthenticated so nothing about the user is sent (RESEARCH Pitfall 3) |
| release-notes-body-in-app | OPT-OUT | not needed: the Updates tab links to the GitHub release page instead of rendering markdown (UI-SPEC Surface 3) |
| issues-create-api | OPT-OUT | explicitly out of scope: Report a Problem opens the public issues/new web form with a prefilled body; no token or API call (D-15) |
| webhooks | OPT-OUT | not needed: tap.yml reacts to the release: published workflow event |
| notary-log-fetch | OPT-OUT | not needed in the app or CI happy path: release.sh prints the notarytool log command for a rejected submission |
