---
phase: quick-261106-bru
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Sources/TransomMac/Shell/StatusItemController.swift
  - .planning/phases/02-window-control/02-UI-SPEC.md
autonomous: true
requirements: [TILE-08, WIN-01]

estimate:
  tokens: 25000
  raw_tokens: 25000
  tasks: 2
  confidence: low

must_haves:
  truths:
    - "The status item glyph is an SF Symbol template at the symbol's default configuration (no explicit point size), so the image (rectangle.split.2x1 measures 18 x 14 pt, exclamationmark.triangle 17 x 15 pt) fits inside the 22 pt square status item on every menu bar"
    - "Glyph choice, template rendering, paused dimming (appearsDisabled), accessibility descriptions and tooltips are unchanged in all four states (not ready, paused, zoomed in, normal)"
    - "swift build succeeds and the TransomMacTests suite passes with the same count as the HEAD baseline (467 tests in 65 suites)"
    - "The Phase 2 UI-SPEC status-item rule matches the code, so a later UI audit does not reintroduce the fixed size"
    - "Host UAT (user): on the 1x Dell S3425DW the menu bar icon shows its bottom edge, and on the Retina notch display it still reads clearly"
  artifacts:
    - path: "Sources/TransomMac/Shell/StatusItemController.swift"
      provides: "updateGlyph builds the template symbol without a forced size"
      contains: "NSImage(systemSymbolName: symbol, accessibilityDescription: description)"
    - path: ".planning/phases/02-window-control/02-UI-SPEC.md"
      provides: "Surface 1 status-item rule amended to the default symbol size"
      contains: "quick 261106-bru"
  key_links:
    - from: "StatusItemController.updateGlyph"
      to: "statusItem.button.image (NSStatusItem.squareLength)"
      via: "template NSImage at default symbol size"
      pattern: "button.image = image"
---

<objective>
Fix the clipped menu bar icon on non-Retina external displays. On the user's Dell S3425DW (3440x1440 at 1x, non-notch menu bar) the Transom status icon renders with its bottom edge missing; on the laptop's Retina notch display it looks fine.

Root cause (planner measurement on this host, macOS 27.2, 2026-11-06): `StatusItemController.updateGlyph` forces a 16-point regular symbol configuration onto the glyph. At that size `rectangle.split.2x1` is a 23 x 18 pt image, but `NSStatusBar.system.thickness` is 22 pt and the item is `NSStatusItem.squareLength`, so the image is wider than its square item and leaves little vertical margin; on a 1x pixel grid the bottom stroke is lost. With no explicit configuration the same symbol is 18 x 14 pt (the triangle is 17 x 15 pt), which fits the square item with margin at any scale.

Fix: drop the forced size and let AppKit draw the template symbol at its default size. Keep everything else in updateGlyph (symbol choice, `isTemplate`, `appearsDisabled`, tooltips) unchanged. Then amend the one Phase 2 UI-SPEC sentence that prescribed the fixed size so spec and code agree.

Purpose: the status item is the user's only always-visible control surface (pause/resume per TILE-08, the access-needed warning per WIN-01). A clipped glyph on a common external-monitor setup looks broken.
Output: one-statement change plus a one-line comment in StatusItemController.swift; one amended sentence in 02-UI-SPEC.md.

Scope guard: another planner is revising `.planning/phases/08.1.1-*` concurrently. Do not read, edit or stage anything under that path. The working tree already has unrelated changes (`.planning/STATE.md`, `.planning/config.json`, the 08.1.1 UI-SPEC, untracked `.planning/state.json`); stage only the files each task names, by explicit path. Never use `git add -A` or `git add .`. Do not switch branches.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./.claude/CLAUDE.md
@Sources/TransomMac/Shell/StatusItemController.swift
</context>

<tasks>

<task type="tracer">
  <name>Task 1: Draw the status glyph at the default symbol size</name>
  <files>Sources/TransomMac/Shell/StatusItemController.swift</files>
  <read_first>
    - Sources/TransomMac/Shell/StatusItemController.swift lines 262-280 (`updateGlyph()`), and line 26 (the status item is created with `NSStatusItem.squareLength`)
  </read_first>
  <action>
In `updateGlyph()`, the `let image =` statement spans two lines: `NSImage(systemSymbolName: symbol, accessibilityDescription: description)?` followed by a chained call that applies a 16-point regular symbol configuration. Delete the second line (the whole chained configuration call) and remove the now-dangling optional-chaining `?` at the end of the first line, so the statement reads `let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)` and nothing more. Do not replace it with any other symbol configuration (no text style, no scale, no weight): the user decision for this task is to let macOS size the template symbol for each menu bar.

Leave every other line of `updateGlyph()` exactly as it is: the `paused` / `zoomed` / symbol-and-description selection, `image?.isTemplate = true`, `button.image = image`, `button.appearsDisabled = paused`, and the tooltip line. Do not touch the `statusItem` declaration (`NSStatusItem.squareLength` stays) or any other method.

Add one sentence to the existing `///` doc comment above `updateGlyph()` explaining why there is no explicit size, so nobody re-adds it. Write it in plain words without naming the removed initializer argument, for example: "No explicit symbol size: the default (18 x 14 pt) fits the 22 pt square item on every menu bar; a forced 16 pt image measured 23 x 18 pt and lost its bottom edge on a 1x display."

Do not launch the app, run scripts/run-debug.sh or scripts/build-debug.sh, or set TRANSOM_LIVE: the visual check is host UAT by the user. Run the verify command, then stage only this file by explicit path (`git add Sources/TransomMac/Shell/StatusItemController.swift`), confirm `git diff --cached --name-only` prints exactly that path, and commit with the message "fix(quick-261106-bru): menu bar glyph at default symbol size so it is not clipped on 1x displays" followed by a blank line and the trailer "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>".
  </action>
  <verify>
    <automated>rm -f .build/q261106.log && swift build && swift test --filter TransomMacTests > .build/q261106.log 2>&1; ! grep -q "✘" .build/q261106.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/q261106.log && test "$(grep -v '^ *//' Sources/TransomMac/Shell/StatusItemController.swift | grep -c 'SymbolConfiguration')" = 0 && test "$(grep -v '^ *//' Sources/TransomMac/Shell/StatusItemController.swift | grep -c 'pointSize')" = 0 && grep -q 'let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)$' Sources/TransomMac/Shell/StatusItemController.swift && grep -q 'image?.isTemplate = true' Sources/TransomMac/Shell/StatusItemController.swift && grep -q 'button.appearsDisabled = paused' Sources/TransomMac/Shell/StatusItemController.swift</automated>
    <human-check>Host UAT by the user (the agent cannot see the external monitor). Run `scripts/run-debug.sh` on the host, then: (1) on the Dell S3425DW (1x, non-notch menu bar) the Transom icon shows all four edges of the split rectangle, including the bottom edge; (2) on the laptop's Retina notch display the icon still reads clearly and is not noticeably undersized next to other menu bar icons; (3) choose Pause in the menu and confirm the dimmed glyph is also unclipped on both displays. If (2) looks too small, report it as a follow-up rather than reintroducing a fixed point size.</human-check>
  </verify>
  <done>Baselines at HEAD: comment-filtered `SymbolConfiguration` count 1 and `pointSize` count 1 in StatusItemController.swift; after: both 0. `swift build` succeeds and `swift test --filter TransomMacTests` reports "Test run with 467 tests in 65 suites passed" (HEAD baseline, measured 2026-11-06) with no ✘. The commit touches only Sources/TransomMac/Shell/StatusItemController.swift.</done>
</task>

<task type="auto">
  <name>Task 2: Amend the Phase 2 UI-SPEC status-item rule</name>
  <files>.planning/phases/02-window-control/02-UI-SPEC.md</files>
  <read_first>
    - .planning/phases/02-window-control/02-UI-SPEC.md lines 116-121 ("Surface 1 — Status item and menu", the "**Status item:**" paragraph)
  </read_first>
  <action>
In the "**Status item:**" paragraph under "## Surface 1 — Status item and menu", keep the first sentence (the `NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)` one) unchanged. Replace only the second sentence, the one that prescribes the 16-point regular symbol configuration, with: "The glyph is an SF Symbol template at the symbol's default configuration, with no explicit point size, so AppKit fits it to every menu bar." Then append, in the same paragraph, one sentence recording the change: "Amended 2026-11-06 by quick 261106-bru: the earlier fixed 16 pt configuration produced a 23 x 18 pt image, wider than the 22 pt square item, and lost its bottom edge on a 1x external display." Do not edit any other line of this file, and do not edit any other UI-SPEC (the 03 glyph table carries no size and needs no change; never touch `.planning/phases/08.1.1-*`).

Stage only this file by explicit path (`git add .planning/phases/02-window-control/02-UI-SPEC.md`), confirm `git diff --cached --name-only` prints exactly that path, and commit with the message "docs(quick-261106-bru): Phase 2 UI-SPEC status glyph uses the default symbol size" followed by a blank line and the trailer "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>". Leave the quick-task directory files (PLAN, SUMMARY) and STATE.md to the orchestrator's docs commit.
  </action>
  <verify>
    <automated>test "$(grep -c 'pointSize: 16' .planning/phases/02-window-control/02-UI-SPEC.md)" = 0 && test "$(grep -c 'quick 261106-bru' .planning/phases/02-window-control/02-UI-SPEC.md)" = 1 && grep -q 'statusItem(withLength: NSStatusItem.squareLength)' .planning/phases/02-window-control/02-UI-SPEC.md && ns="$(git diff HEAD --numstat -- .planning/phases/02-window-control/02-UI-SPEC.md)" && test "$(printf '%s\n' "$ns" | awk '{s+=$1+$2} END {print s+0}')" -le 2</automated>
  </verify>
  <done>Baselines at HEAD: `pointSize: 16` count 1 and `quick 261106-bru` count 0 in 02-UI-SPEC.md; after: 0 and 1. The diff of 02-UI-SPEC.md is one changed line (at most 1 insertion and 1 deletion; run the numstat check before committing). The commit touches only .planning/phases/02-window-control/02-UI-SPEC.md.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| none new | Cosmetic AppKit image sizing inside the app's own status item. No input, file, network, permission or private-API path changes |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-bru-01 | Spoofing | StatusItemController.updateGlyph (the access-needed and paused glyphs are the user's only always-visible state signal) | low | mitigate | Only the image size changes. Symbol selection, `isTemplate`, `appearsDisabled` and the accessibility descriptions/tooltips stay as they are; Task 1's verify asserts the template and dimming lines are still present, and the host UAT checks the paused glyph on both displays |
| T-bru-SC | Tampering | npm/pip/cargo installs | low | accept | No package installs in this plan; Package.swift is not touched |
</threat_model>

<verification>
- `rm -f .build/q261106.log && swift build && swift test --filter TransomMacTests > .build/q261106.log 2>&1; ! grep -q "✘" .build/q261106.log && grep -E "Test run with [1-9][0-9]* tests? .*passed" .build/q261106.log` passes (467 tests in 65 suites at HEAD)
- `scripts/check-no-appkit.sh` still exits 0 (no Model/Engine file is touched; sanity only)
- `git show --name-only --format= HEAD~1` prints only Sources/TransomMac/Shell/StatusItemController.swift and `git show --name-only --format= HEAD` prints only .planning/phases/02-window-control/02-UI-SPEC.md
- Nothing under .planning/phases/08.1.1-* appears in either commit
</verification>

<success_criteria>
- The menu bar glyph is drawn at the symbol's default size in every state, so it fits the 22 pt square status item
- Glyph choice, template rendering, paused dimming and accessibility text are unchanged
- TransomMacTests is green at the baseline count
- The Phase 2 UI-SPEC matches the code and records why the size changed
- Host UAT pending with the user: bottom edge visible on the 1x Dell display, icon still clear on the Retina notch display
</success_criteria>

<output>
Create `.planning/quick/261106-bru-fix-menu-bar-icon-clipped-on-non-retina-/261106-bru-SUMMARY.md` when done
</output>
