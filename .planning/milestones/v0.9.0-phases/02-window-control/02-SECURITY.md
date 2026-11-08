---
phase: "2"
slug: "window-control"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-25"
---

# Phase 2 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Pane ↔ other apps (AX IPC) | AX reads/writes into arbitrary, possibly hung or hostile, processes | Window roles, frames, titles (sensitive) |
| Pane ↔ WindowServer (CGWindowList) | Public window list, untrusted shape | Window IDs, bounds, owner pid, names (sensitive) |
| Pane ↔ private symbols (dlsym) | `_AXUIElementGetWindow` may vanish or misbehave | CGWindowID |
| Pane ↔ disk (`~/Library/Application Support/Pane`) | Exclusions, minimum-size hints; user-writable files | Bundle IDs, sizes |
| Pane ↔ TCC / tccutil | Permission reset for its own bundle ID only | Bundle ID |
| Repo ↔ public (AXDumps corpus) | Captured AX dumps committed to a public repo | Redacted titles, roles, bundle IDs |
| Distributed notifications | Lock/sleep signals from any process | Session state (pause only) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-02-01 | Tampering | PanePrivate/AXWindowID | medium | mitigate | typed dlsym, nil → frame fallback (AXWindowID.swift:10-17) | closed |
| T-02-02 | Information disclosure | AXSnapshotReader / logs | medium | mitigate | titles kept out of description/logs (IDs.swift:101,104) | closed |
| T-02-03 | Denial of service | AXWindowSystem MainActor | high | mitigate | 1 s messaging timeout; AX IPC only on per-app threads (AXAppThread.swift:71-145) | closed |
| T-02-04 | Tampering | Capabilities.parseDisabled | low | mitigate | known names only, unknown logged (Capabilities.swift:16-29,65-67) | closed |
| T-02-05 | Elevation of privilege | Release entitlements | medium | mitigate | no injected base entitlements, hardened runtime (project.yml:18,45; codesign checked) | closed |
| T-02-06 | Tampering | brew install xcodegen | medium | mitigate | homebrew/core 2.46.0 verified; dev-only | closed |
| T-02-07 | Spoofing | Debug vs Release TCC identity | low | mitigate | distinct bundle IDs, signature checked per build (build-debug.sh:31-34) | closed |
| T-02-08 | Information disclosure | pane-dump / AXDumps corpus | high | mitigate | titles redacted, identifier allow-list, leak test (ClassifierCorpusTests.swift:53-60) | closed (developer review pending, see notes) |
| T-02-09 | Tampering | CGWindowList parsing | low | mitigate | incomplete entries skipped and counted (CGWindowList.swift:16-31) | closed |
| T-02-10 | Tampering | CorpusCase.decode | low | mitigate | 64 KiB cap, schema probe, newer version rejected (CorpusCase.swift:60,93-98) | closed |
| T-02-11 | Tampering | LifecycleSync.handle | medium | mitigate | only World.apply; destroy only from CloseRule (LifecycleSync.swift:26-65) | closed |
| T-02-12 | Repudiation | undo path | low | mitigate | revived windows re-queried (LifecycleSync.swift:5-67; tests :174,:190) | closed |
| T-02-13 | Elevation of privilege | TCCReset | high | mitigate | fixed /usr/bin/tccutil, argv no shell, own bundle ID only (TCCReset.swift:7-21) | closed |
| T-02-14 | Denial of service | PermissionProbe | medium | mitigate | detached, 1 s timeout, bounded retries (PermissionProbe.swift:16-43) | closed |
| T-02-15 | Spoofing | Prompt flow | low | mitigate | prompt on first click only; constant deep link (PermissionReducer.swift:82,88) | closed |
| T-02-16 | Denial of service | RefreshScheduler | medium | mitigate | 75 ms cancel-latest per pid; 500 ms display debounce; hint buffer 256 | closed |
| T-02-17 | Denial of service | AXAppThread observers | medium | mitigate | Unmanaged refcon lifetime, ordered teardown (AXAppThread.swift:71-107,252) | closed |
| T-02-18 | Tampering | Hint handling | low | mitigate | hints only schedule refresh; closes only via CloseRule | closed |
| T-02-19 | Denial of service | AXAppThread job queue | high | mitigate | one in-flight + one follow-up; degraded apps probed only (AXWindowSystem.swift:40-41,203-281) | closed |
| T-02-20 | Denial of service | MainActor | high | mitigate | degraded filtered, cached inventory; freeze tests assert <50 ms | closed |
| T-02-21 | Denial of service | FreezeTest | high | mitigate | refuse list, Debug-only, 10 s auto-resume, resume on launch/quit (FreezeTest.swift:11-50) | closed |
| T-02-22 | Tampering | ExclusionStore load | low | mitigate | entries validated, invalid dropped and logged (ExclusionStore.swift:22-38) | closed |
| T-02-23 | Information disclosure | Tracked Windows titles | medium | mitigate | titles rendered only, never logged | closed |
| T-02-24 | Tampering | Close decisions | high | mitigate | two-source close rule; paused/timeouts → noChange (CloseRule.swift:43-56; tests) | closed |
| T-02-25 | Spoofing | SessionGate notifications | low | accept | forged lock only pauses (fail-safe) | closed |
| T-02-26 | Denial of service | Paused refresh loop | low | mitigate | scheduler stopped on pause; one full refresh after 1.5 s quiet | closed |
| T-02-27 | Tampering | TabGroupTracker membership | medium | mitigate | same pid, layer 0, offscreen, 1 pt bounds, N ≥ 2 (TabGroupTracker.swift:38-62) | closed |
| T-02-28 | Repudiation | Group identity after leader close | low | accept | documented; later phases address via visibleMemberID | closed |
| T-02-29 | Tampering | Fallback identity | medium | mitigate | same pid, 1 pt, bound IDs excluded, synthetic IDs avoid CG IDs (FallbackMatcher.swift:19-30) | closed |
| T-02-30 | Denial of service | Broken private API | medium | mitigate | 5 failures → session switch-off, logged once (Capabilities.swift:75-110) | closed |
| T-02-31 | Information disclosure | CGWindowList.names | medium | mitigate | names read only for ambiguous match, in memory, never logged | closed |
| T-02-32 | Tampering | perform / setFrame | medium | mitigate | finite rects within 1,000,000 pt; untracked dropped (Geometry.swift:59-66; AXWindowSystem.swift:162-170) | closed |
| T-02-33 | Tampering | MinimumSizeLearner | medium | mitigate | validated read-backs, only grows (MinimumSizeLearner.swift:19-34) | closed |
| T-02-34 | Denial of service | Frame queue | medium | mitigate | latest-wins slot per window, one drain, paused while degraded | closed |
| T-02-35 | Tampering / DoS | MinimumHintsStore.load | medium | mitigate | 64 KiB cap, schema probe, validated values, bad file moved aside (MinimumHintsStore.swift:16-139) | closed |
| T-02-36 | Tampering | MinimumHintsStore.save | low | mitigate | atomic write; only bundleID/width/height stored | closed |
| T-02-37 | Elevation of privilege | perform on excluded apps | medium | mitigate | ExclusionFilter first in both perform paths; live test (ExclusionIntegrationTests.swift:10-45) | closed |
| T-02-38 | Tampering | SkyLightSpaces.spaces | medium | mitigate | CFNumber-only, 0 dropped, ≤16 Spaces, NULL leaves window out; Space data only narrows candidates (SkyLightSpaces.swift:39-57) | closed |
| T-02-39 | Denial of service | SkyLight symbol removal / signature change | high | mitigate | dlopen/dlsym optionals, forced-off flag, 5-failure session switch-off, nil → single Space (SkyLightSpaces.swift:18-44; Capabilities.swift:85-120) | closed |
| T-02-40 | Spoofing | TabGroupTracker hidden-tab choice | high | mitigate | known other-Space windows never candidates; ambiguous unknowns not taken; fold destroyed only after 2 refreshes (TabGroupTracker.swift:132-176; WindowTracker.swift:80-98) | closed |
| T-02-41 | Tampering | MinimumSizeLearner → hints store | medium | mitigate | 32 pt margin, 1 s confirmation, validated values, store validation intact (MinimumSizeLearner.swift:15-71) | closed |
| T-02-42 | Spoofing | WindowIDResolver identity binding | high | mitigate | lookup's element owns the ID; holders re-identified; unique byID on insert; invariant asserted in every resolver test (WindowIDResolver.swift:73-132) | closed (residual AR-02-06) |
| T-02-43 | Denial of service | CapabilitySession for `_AXUIElementGetWindow` | medium | mitigate | each element counted once (64-cap set); real success resets (WindowIDResolver.swift:48-86) | closed |
| T-02-44 | Repudiation | WindowTracker.rekey | low | mitigate | `windowRekeyed` event, no destroy/create, only key-move site (WindowTracker.swift:215-250) | closed |
| T-02-45 | Spoofing | Orphan handoff without Space data | medium | mitigate | former-tab evidence + Space-switch generation marks refuse handoff (TabGroupTracker.swift:89-153; SpaceSwitchMarks.swift) | closed (residual AR-02-07) |
| T-02-46 | Tampering | Fold guard during Space switch | medium | mitigate | blind switch holds folds, no new hidden tabs (TabGroupTracker.swift:173-175; WindowTracker.swift:82-90) | closed |
| T-02-47 | Spoofing | `activeSpaceDidChangeNotification` source | low | accept | in-process NSWorkspace center | closed |
| T-02-48 | Denial of service | Rapid Space switching | low | accept | only defers folds; residual recorded in 02-17 SUMMARY | closed |
| T-02-SC | Tampering | package installs | low | accept | no package dependencies in any plan | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

### Notes (non-blocking)

1. **T-02-08:** all 11 corpus cases still carry `confirmedBy: "executor-proposed"`. Code controls and the leak test are in place and an audit scan found no sensitive strings, but the planned developer review of the corpus diff moved to phase UAT. Do it before pushing to the public remote.
2. **T-02-24:** `ClosedIDCache` is written but `contains(_:at:)` is never called; ID-reuse protection actually comes from removing the closed window (WindowTracker.swift:247-249). Dead state — candidate for cleanup in code review.
3. **T-02-05:** `scripts/build-debug.sh --release` checks signature/identifier/team but not entitlements; adding a get-task-allow check would catch a regression.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-25 | A forged `com.apple.screenIsLocked` only pauses reconciliation; nothing closes, unlock/wake triggers a full refresh | 02-09-PLAN threat model | 2026-10-24 |
| AR-02-02 | T-02-28 | A tab group keeps its leader's identity after the leader tab closes; Phases 3-4 address windows via `visibleMemberID` | 02-10-PLAN threat model | 2026-10-25 |
| AR-02-03 | T-02-SC | No package-manager installs in phase 2; XcodeGen covered by T-02-06 | all phase 2 plans | 2026-10-24 |
| AR-02-04 | T-02-47 | NSWorkspace's notification center is in-process; a spurious mark only defers a handoff or fold by one update | 02-17-PLAN threat model | 2026-10-25 |
| AR-02-05 | T-02-48 | Constant Space switching only defers folds; windows are never lost | 02-17-PLAN threat model | 2026-10-25 |
| AR-02-06 | T-02-42 / T-02-44 | REVIEW IN-13: chained re-keys in one refresh, or an unlisted holder, can hand one window's tracked entry to another; needs two lookup failures in a row on a new window; nothing destroyed | project lead (deferred, Info) | 2026-10-25 |
| AR-02-07 | T-02-45 | REVIEW IN-14 plus late notification: a partial Space map, or a notification reaching main after ingest, leaves the handoff unprotected; pinned by a known-limit test | project lead (deferred, Info) | 2026-10-25 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-25 | 38 | 38 | 0 | gsd-security-auditor (ASVS L1) |
| 2026-10-25 | 49 | 49 | 0 | gsd-security-auditor (ASVS L1), gap plans 02-14..02-17 |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-25
