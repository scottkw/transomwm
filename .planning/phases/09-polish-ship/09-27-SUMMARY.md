---
phase: 09-polish-ship
plan: 27
status: complete
completed: 2026-11-08
---

# 09-27 Summary: going public and the release dry run

- Task 1: user answered "ship-as-planned" with Homebrew deferred (D-26).
- Task 2 (user, with Claude running the API steps the user allowed): repo made public; PR #9 merged to main (0c81ca8)
  after CI passed; `release` environment (required reviewer scottkw, `main` + `v*`) created; five secrets set with
  `scripts/set-release-secrets.sh` (new, 6cb38b8); tag ruleset "Release tags: maintainer only" created; release dry run
  on main passed after correcting NOTARY_KEY_ID.
- Task 3: API checks pass (public, environment, five secrets, ruleset, no releases); D-21 diagnostic recorded in
  deferred-items.md. CI on main failed once on a WakeTimer wall-clock flake, fixed in f7b6b56.
