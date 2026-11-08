# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v0.9.0 — Transom 0.9.0: first public release

**Shipped:** 2026-11-07 (closed 2026-11-08)
**Phases:** 11 | **Plans:** 162 | **Sessions:** not recorded

### What Was Built
- A headless, Foundation-only layout model (`TransomModel`) with undo, JSON migration and minimum-size water-filling
- Non-blocking Accessibility window control with a classifier, exclusions and private-API fallbacks
- Drag-to-dock nested tiling with crash-safe restore that works with zoom and Screen Recording off
- Zoom camera, trackpad gestures, overview with a Spaces bar, tab groups, saved views with `transom://` URLs and a CLI
- Window behaviour options (8.1) and removal of the Desktop tile (8.1.1)
- Settings, onboarding, launch at login, a GitHub Releases update check, and a signed, notarised DMG

### What Worked
- Building bottom-up (model, then window control, then tiling) shipped the Core Value in Phase 3 before any risky feature
- Keeping Model and Engine free of AppKit gave about 1,000 headless tests and a fake window system that reproduced most bugs
- Running live and UAT tests in Tart macOS VMs (15.7 and 27.2) kept the host safe and caught OS-version differences
- Debug sessions with recorded evidence made each failure diagnosable later

### What Was Inefficient
- Two inserted phases (8.1, 8.1.1) reworked tiling semantics late; 8.1.1 alone took 27 plans
- Live integration tests were flaky across macOS versions (SSH-run Space-change notifications, helper run-loop exits), costing many plans of test-setup fixes
- Most on-screen UAT was never seen by a person (D-29), and multi-display checks waited on hardware
- CI was disabled mid-milestone after an undiagnosed runner crash

### Patterns Established
- Every refusal and notice is logged, so VM runs can be checked without watching the screen
- Private APIs live only in `TransomPrivate` behind `dlopen`/`dlsym` with a named fallback
- Live-test rules: bounded, fixture-only runs with a three-run limit per suite before stopping to diagnose

### Key Lessons
1. Ask early whether a feature makes the app feel complicated; the Desktop tile cost a whole inserted phase to remove
2. Budget human UAT time per phase, or the debt piles up at release
3. Keep CI green and enabled; a disabled CI hides regressions across 30-plus plans
4. Treat test-harness gaps (SSH sessions, helper run loops) as their own work item, not product bugs

### Cost Observations
- Model mix: not recorded
- Sessions: not recorded
- Notable: 1,319 commits in 16 days (2026-10-23 to 2026-11-07)

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v0.9.0 | not recorded | 11 | First milestone; VM-based live testing; two urgent inserted phases |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v0.9.0 | about 1,000 | not measured | not recorded |

### Top Lessons (Verified Across Milestones)

1. (Needs a second milestone to verify)
