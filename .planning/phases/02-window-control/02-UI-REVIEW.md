# Phase 2 — UI Review

**Audited:** 2026-10-25
**Baseline:** 02-UI-SPEC.md (approved design contract)
**Screenshots:** not captured. This is a native AppKit app with no dev server. The Debug app was not launched: with Accessibility already granted, no Pane window appears on its own, and reaching the menu, the Tracked Windows window or the setup states would mean scripting clicks on the menu bar (SystemUIServer). That breaks the "never interact with other apps' windows" rule. Every visual item below is code-derived and marked `needs_human_review` where only a rendered check can settle it.
**Interaction captures:** off (workflow.ui_interaction_capture is false)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Every contract string matches word for word. But the menu header says "No windows to track" while the first sweep is still loading, and it counts windows the footer leaves out, so the two surfaces can disagree |
| 2. Visuals | 3/4 | The structure follows the state matrix. Reset-failed stacks duplicate "Open System Settings" buttons, and with form B it can show two callouts at once |
| 3. Color | 4/4 | Only semantic colours are used, there are no hex literals, and Pane never applies the accent itself. Destructive red appears only in the two places the contract allows |
| 4. Typography | 3/4 | It uses 3 sizes and 2 weights as declared, but there is one `.system(size: 16)` the rules don't strictly allow |
| 5. Spacing | 3/4 | The tokens match. The GroupBox callouts add `.padding(12)` on top of GroupBox's own inset, so the inner padding is probably about 2× the contract |
| 6. Experience Design | 3/4 | State coverage is complete and the Freeze guard is correct. The menu header has no loading state, and the table rebuilds per-row AppKit lookups on every inventory event |

**Overall: 19/24**

---

## Top 3 Priority Fixes

1. **The menu header and footer count different things, and the header has no loading state** (WARNING). `StatusItemController.swift:99-100` builds the header from `latest.windows.count`, which includes `.closed` entries. Its app count also includes never-dock and closed windows. The Tracked Windows footer (`TrackedWindowsModel.footer`) counts only non-closed rows, so the menu can say "Tracking 14 windows" while the footer says "12 windows". Before `initialRefreshComplete`, the header also says "No windows to track" while the table shows "Looking for windows…". **Fix:** compute the header from `latest.windows.filter { $0.state != .closed }`. Show "Looking for windows…" when `!latest.initialRefreshComplete`, reusing `TrackedWindowsModel.state` so both surfaces share one rule.
2. **The reset-failed state duplicates controls** (WARNING). With callout E visible, `SetupView.swift:85` renders a second "Open System Settings" button inside the callout, next to the default "Open System Settings" in the button row (`SetupView.swift:101-103`). If the failed reset started from form B, `SetupView.swift:26-27` shows callout B (with its own "Reset Permission") *and* callout E at the same time. The user then sees two Settings buttons and an offer to run the reset that just failed. **Fix:** hide callout B when `resetFailedCode != nil`. Drop the callout E button and keep the default button in the row; this keeps the contract's intent and needs a one-line UI-SPEC amendment.
3. **The GroupBox callout padding is doubled** (WARNING, needs_human_review). `SetupView.swift:131-137` wraps the content in `.padding(12)` inside `GroupBox`, and SwiftUI's macOS GroupBox already insets its content. The effective inner padding is therefore likely about 16–20pt rather than the contract's 12pt. **Fix:** remove `.padding(12)`, or confirm with a screenshot that the inset is 12pt.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

These match the contract exactly: S1–S5 headings and bodies, steps S1.1–S1.3, callout B and E copy (`SetupView.swift:54-172`, `MenuCopy.swift:43-46`), and the menu strings (`MenuCopy.swift`). They use curly quotes (U+201C/D), U+2026 and U+25B8 correctly. Plurals use explicit branches, never "(s)" (`MenuCopy.swift:68-70`, `TrackedWindowsModel.swift:108`).

- WARNING: the header counts windows inconsistently and has no loading copy (see Fix 1). `StatusItemController.swift:99-100`.
- WARNING: in the ID column, `.help("")` is set for real IDs (`TrackedWindowsView.swift:94`) and `.help("")` for placeholder titles (`:88`). These are empty tooltips, which are harmless but noisy. Use a conditional modifier instead.
- WARNING: the bare "Freeze" button label (`StatusItemController.swift:234`) was flagged by the UI checker and is still bare. The contract allows it, but "Freeze “App”" would be clearer.
- Minor: when ready, `bundleName` falls back to the process name for unbundled runs (`StatusItemController.swift:269-273`). That is acceptable and logged.

### Pillar 2: Visuals (3/4)

- The hero uses the 48pt hierarchical symbol per state with the right colours and `accessibilityHidden` (`SetupView.swift:38-50`). Callout E's icon is labelled "Error" (`:81`). The template glyph is 16pt regular (`StatusItemController.swift:82-85`).
- The button order is Quit leftmost, then the secondary button, then the default rightmost (`SetupView.swift:89-106`), matching the matrix.
- WARNING: in the reset-failed state, the callouts and buttons are duplicated (Fix 2).
- WARNING (needs_human_review): the Tracked Windows `Table` doesn't set a style, so whether it shows `controlBackgroundColor` with alternating rows as the contract requires depends on the SwiftUI default. Add `.tableStyle(.bordered(alternatesRowBackgrounds: true))` or `.alternatingRowBackgrounds()` to make it explicit, then confirm visually.
- needs_human_review: long `CFBundleName` wrapping in the setup window, and the template glyph in light, dark and tinted menu bars (the UI-SPEC backstops).

### Pillar 3: Color (4/4)

- There are no hex or `rgb(` literals anywhere in `Sources/PaneMac`. All colours are `NSColor` semantic names or `.secondary` / `.primary`.
- The accent appears only through `.borderedProminent` + `.defaultAction` on the one default button per state (`SetupView.swift:115`), and on system selection and focus rings.
- systemRed appears only on the Freeze button (`hasDestructiveAction`, `StatusItemController.swift:236`) and on callout E's icon (`SetupView.swift:80`). systemOrange appears only on the stale-A hero and the "Not responding" badge at 15% (`TrackedWindowsView.swift:110`). systemGreen appears only on the Ready hero.
- Minor: the footer uses `.foregroundStyle(.secondary)` (`TrackedWindowsView.swift:67`) where the contract names `secondaryLabelColor`. They render the same, but this is inconsistent with the explicit `Color(nsColor:)` used elsewhere.

### Pillar 4: Typography (3/4)

- Sizes in use: `.title` + `.semibold` (22), `.body` / `.headline` (13 / 13 semibold), and `.caption` (11). That is 3 sizes and 2 weights, as declared. There is no `lineSpacing`.
- `.monospacedDigit()` is on ID, Frame and Min Size (`TrackedWindowsView.swift:92,101,103`).
- WARNING: `.font(.system(size: 16))` on the callout E icon (`SetupView.swift:79`). The contract says "never `.system(size:)`" and names the 48pt hero as "the one allowed fixed size". The 16pt is specified for this icon, but the size rule should either list it as a second exception or the code should use `.imageScale` / `.font(.headline)` so the icon tracks the title.
- Minor: the "Looking for windows…" loading text (`TrackedWindowsView.swift:47`) has no font, so it inherits the ContentUnavailableView label style, which is larger than headline. The contract says heading. needs_human_review.

### Pillar 5: Spacing (3/4)

The tokens match: the 20pt inset (`SetupView.swift:33`), 480pt width (440 + 2×20), 16pt block stack, 12pt heading→body, 8pt steps, 8pt spinner gap, 12pt button gap, 24pt above the buttons (16 + `.padding(.top, 8)`), 4pt icon→name, badges at 8/4 with radius 4, and a 28pt footer with a 12pt inset.

- WARNING: GroupBox padding is doubled (Fix 3).
- Minor: callout E's icon→title gap is `HStack(spacing: 8)` (`SetupView.swift:77`). The contract doesn't specify this gap; 8 sits on the scale, so it is acceptable.

### Pillar 6: Experience Design (3/4)

Coverage: the setup window covers every reducer state, including resetting (all controls disabled, close blocked: `SetupWindowController.swift:61-63`). Tracked Windows covers no-permission, loading, empty, populated and refreshing-after-wake. Unavailable Debug actions get explanatory disabled titles. Freeze puts Return on Cancel, adds a local Esc monitor, re-checks after the modal, and persists the pid before SIGSTOP. ⌘W/Esc close via `KeyClosableWindow`. Window open and focus behaviour matches the contract.

- WARNING: the menu header has no loading state (Fix 1).
- WARNING: on every render (every inventory event), the Tracked Windows body calls `NSRunningApplication(processIdentifier:)` per row for icons (`TrackedWindowsView.swift:78`), per pid for names (`:130-136`), and `Displays.localizedNames()` (`:30`). With many windows and frequent events this is wasted main-thread work, and it can make the live table stutter. Cache icons and names per pid in the feed when the inventory changes.
- WARNING: in `StatusItemController.swift:93`, the menu treats `.resetting` as stale ("Fix…") even when the reset started from form B. The menu item happens to be the same label, but the header switches to "Accessibility access isn't working" (`MenuCopy.swift:34`) while the setup window still shows the S1 heading. The two surfaces then show mismatched state copy during a form-B reset.
- Minor: the glyph subscription keys only on `ready` (`StatusItemController.swift:41-42`). That is correct for the two-glyph contract, but any future per-state tooltip won't update.
- Registry audit: not applicable (no shadcn, no third-party registries).

---

## Files Audited

- /Users/ken/dev/panewm/Sources/PaneMac/Shell/StatusItemController.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Shell/MenuCopy.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Shell/Nudge.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Shell/FreezeTest.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Shell/TrackedWindowsView.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Shell/TrackedWindowsWindowController.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Shell/TrackedWindowsModel.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Permission/SetupView.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Permission/SetupWindowController.swift
- /Users/ken/dev/panewm/Sources/PaneMac/Permission/PermissionController.swift (grep only)
- /Users/ken/dev/panewm/.planning/phases/02-window-control/02-UI-SPEC.md, 02-CONTEXT.md
