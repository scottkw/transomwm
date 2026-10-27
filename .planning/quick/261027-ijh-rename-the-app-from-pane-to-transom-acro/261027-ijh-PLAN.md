---
phase: quick-261027-ijh
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Package.swift
  - Package.resolved
  - Sources/** (8 target directories renamed with git mv, contents rewritten)
  - Tests/** (4 test-target directories renamed with git mv, contents rewritten)
  - xcode/project.yml
  - xcode/Pane-Info.plist -> xcode/Transom-Info.plist
  - xcode/Pane.entitlements -> xcode/Transom.entitlements
  - scripts/build-debug.sh
  - scripts/check-no-appkit.sh
  - scripts/generate.sh
  - scripts/release.sh
  - scripts/run-debug.sh
  - scripts/vm-live-test.sh
  - .github/workflows/ci.yml
  - .claude/CLAUDE.md
  - PLAN.md
  - .planning/PROJECT.md
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md
autonomous: true
requirements: [SAFE-03]

estimate:
  tokens: 110000
  raw_tokens: 110000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "`swift build` succeeds, and the full headless `swift test` (no live variable set under either name) reports 'Test run with 534 tests' passed, the same count as the pre-rename baseline recorded at 82697cf"
    - "`scripts/build-debug.sh --release` builds xcode/.xcode-build/Build/Products/Release/Transom.app. Its designated requirement names identifier \"com.eightabyte.transom\" and team S2K7P43927, and `scripts/release.sh --build-only` passes: secure timestamp, universal binary, version 0.3.0, URL scheme `transom`"
    - "Every SwiftPM target, product, directory and test target is Transom* (TransomModel, TransomEngine, TransomMac, TransomPrivate, TransomApp, TransomFixtureApp, TransomTestSupport, transom-dump, and TransomModelTests, TransomEngineTests, TransomMacTests, TransomMacIntegrationTests). Every path rename used git mv, so `git log --follow` reaches pre-rename history"
    - "The URL scheme is transom:// (transom-debug:// in Debug), parsed by TransomURL and throttled by TransomURLRateLimiter. The os.Logger subsystem is com.eightabyte.transom. The data folder is ~/Library/Application Support/Transom, with no migration code. The environment variables are TRANSOM_*. The VM lock is .build/transom-vm.lock. release.sh writes build/Transom-<version>.dmg"
    - "No word that merely contains 'pane' changed: the case-insensitive 'panel' count outside .planning, .claude and PLAN.md stays 348, and no 'transoml' appears anywhere"
    - "The only places still saying Pane are the leftovers on the allow-list (keychain profile pane-notary, Tart VM pane-test and its SSH key, the generic noun 'Settings pane' in SHIP-08, the history sections of ROADMAP Phases 1-3, the rename decision row in PROJECT.md, and the CLAUDE.md stack section mirrored from research/STACK.md). The SUMMARY lists each one"
    - "No .planning history artifact changed (phases/, debug/, quick/ other than this task, research/, ui-reviews/, WINDOWS.md, STATE.md). The rename lands in one code commit that builds, followed by one docs commit"
  artifacts:
    - path: "Package.swift"
      provides: "Package Transom with Transom* products and targets"
      contains: "name: \"Transom\""
    - path: "xcode/project.yml"
      provides: "XcodeGen spec for Transom.app / Transom Debug.app with the new bundle IDs and scheme"
      contains: "PRODUCT_BUNDLE_IDENTIFIER: com.eightabyte.transom"
    - path: "xcode/Transom-Info.plist"
      provides: "CFBundleURLTypes with the per-configuration scheme"
      contains: "$(TRANSOM_URL_SCHEME)"
    - path: "Sources/TransomEngine/TransomURL.swift"
      provides: "TransomURL parser and TransomURLRateLimiter"
    - path: "Sources/TransomMac/TransomMacApp.swift"
      provides: "App composition root, renamed from PaneMacApp"
    - path: "Sources/TransomMac/MinimumHintsStore.swift"
      provides: "Data folder ~/Library/Application Support/Transom"
      contains: "appending(path: \"Transom\""
    - path: "scripts/release.sh"
      provides: "Release pipeline producing build/Transom-<version>.dmg, checking identifier com.eightabyte.transom and scheme transom"
      contains: "dmg=\"build/Transom-$version.dmg\""
    - path: "scripts/vm-live-test.sh"
      provides: "VM live-test runner using TRANSOM_* variables and .build/transom-vm.lock"
      contains: ".build/transom-vm.lock"
    - path: "Tests/TransomMacIntegrationTests/IntegrationSupport.swift"
      provides: "Live gate on TRANSOM_LIVE=1"
      contains: "TRANSOM_LIVE"
  key_links:
    - from: "xcode/project.yml (packages: Transom, product TransomMac)"
      to: "Package.swift library TransomMac"
      via: "XcodeGen local package reference path .."
      pattern: "product: TransomMac"
    - from: "xcode/Transom-Info.plist $(TRANSOM_URL_SCHEME)"
      to: "xcode/project.yml TRANSOM_URL_SCHEME per configuration (transom-debug / transom)"
      via: "Info.plist build-setting expansion"
      pattern: "TRANSOM_URL_SCHEME: transom"
    - from: "scripts/build-debug.sh and scripts/release.sh identifier checks"
      to: "xcode/project.yml PRODUCT_BUNDLE_IDENTIFIER"
      via: "codesign -d -r- designated requirement"
      pattern: "identifier=com.eightabyte.transom"
    - from: "scripts/check-no-appkit.sh default directories"
      to: "Sources/TransomModel and Sources/TransomEngine"
      via: "NoAppKitTests runs the script inside swift test"
      pattern: "Sources/TransomModel Sources/TransomEngine"
    - from: "scripts/vm-live-test.sh staging copy"
      to: "TransomMacIntegrationTests.xctest and TransomFixtureApp build products"
      via: "swift build --build-tests --scratch-path .build/vm"
      pattern: "TransomMacIntegrationTests.xctest"
---

<objective>
Rename the app from Pane to Transom across the repo, following the user's locked decisions of 2026-10-27 (listed in <locked_decisions> below). One mechanical commit renames the code, build, scripts and CI and still builds and passes every headless test. A second commit updates the human docs and the living .planning docs. History artifacts stay untouched.

Purpose: "Pane" is already used by several macOS window managers. The public 0.3.0 release is on hold until the rename is done (STATE.md "Pending: Rename to Transom").
Output: git-mv'd Transom* targets, files and types; new bundle IDs, URL scheme, logger subsystem, data folder, env vars and DMG name; a signed Transom.app proven by build-debug.sh --release and release.sh --build-only; updated docs; and a SUMMARY that lists every intentional leftover.

Baselines recorded by the planner at HEAD 82697cf (the gates below compare against them):
- Full headless `swift test`: "Test run with 534 tests in 53 suites passed".
- Case-insensitive "panel" occurrences outside .planning, .claude and PLAN.md: 348. "transom" occurrences outside .planning: 0.
- graft/ is gitignored and untracked (`git ls-files graft` is empty), so there are no index cards to edit. The graft MCP rebuilds its graph itself.
- No README or LICENSE file is tracked, so there is nothing to rename. Do NOT create them.
- No tracked file outside .planning mentions panewm or any repo URL, so there are no URLs to update.
- No "pane" anywhere in Sources or Tests is a generic UI noun. The only generic-noun uses are in .planning/REQUIREMENTS.md SHIP-08 (`?pane=` query key and "Settings pane") and the .claude/CLAUDE.md stack section ("About/Diagnostics pane"). Both stay.
- The model enum case `.panel`, and NSPanel, HandlePanel, ToastPanel, nonactivatingPanel, gapPanels, PreviewPanel*, panelJSON, isPresentPanel, rebuildPanels, panelRect, panelKind and buildPanels, all contain "pane" inside another word and must stay byte-identical.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.claude/CLAUDE.md
@Package.swift
@xcode/project.yml
@scripts/build-debug.sh
@scripts/release.sh
@scripts/vm-live-test.sh

<locked_decisions>
User decisions, 2026-10-27. Do not revisit them.
- App name: Transom (Transom.app, "Transom Debug.app"), plus display, menu, About and setup copy ("Set Up Transom", "Quit Transom").
- Bundle IDs: com.eightabyte.transom and com.eightabyte.transom.debug.
- URL scheme: transom:// (transom-debug:// in Debug). Types: TransomURL, TransomURLRateLimiter.
- Data folder: ~/Library/Application Support/Transom. NO migration code: the app never shipped.
- os.Logger subsystem: com.eightabyte.transom.
- SwiftPM targets and directories: TransomModel, TransomEngine, TransomMac, TransomPrivate, TransomApp, TransomFixtureApp, TransomTestSupport, transom-dump; test targets TransomModelTests, TransomEngineTests, TransomMacTests, TransomMacIntegrationTests. File and type names follow (TransomMacApp, restoredByTransom, ...).
- Env vars: TRANSOM_LIVE, TRANSOM_LIVE_DRAG, TRANSOM_LIVE_FULLSCREEN, TRANSOM_FIXTURE_APP, TRANSOM_URL_SCHEME, TRANSOM_VM, TRANSOM_VM_USER, TRANSOM_VM_KEY.
- Xcode: xcode/project.yml; xcode/Pane-Info.plist becomes xcode/Transom-Info.plist.
- Scripts: build-debug.sh, release.sh (must produce build/Transom-<version>.dmg), vm-live-test.sh, check-no-appkit.sh. VM lock: .build/transom-vm.lock.
- Every path moves with git mv. Version stays 0.3.0.
- Never edit .planning history (phases/, debug/, quick/ other than this task's directory, research/, milestones). Living docs only: PROJECT.md ("What This Is", Constraints), ROADMAP.md (overview and future phases), and REQUIREMENTS.md.
- Keychain profile `pane-notary`: keep it unless renaming is free. Planner decision: KEEP. Renaming means re-running `xcrun notarytool store-credentials` with App Store Connect credentials the executor does not have.
- Planner decision (discretion): KEEP the vm-live-test.sh defaults for the Tart VM name `pane-test` and the SSH key `~/.ssh/pane_vm_ed25519`. Only their env var names change. They name existing host resources (memory: tart-vm-desktop-testing), and the executor must not touch the VM. The user can later rename them with `tart rename` and a key move.
</locked_decisions>

<rename_rules>
The ONLY content substitutions allowed in code scope. All are case-sensitive Perl regexes, applied in this order in ONE `perl -pi` invocation (each rule a separate `s///g` in the same -e program). Never use a blind case-insensitive replace.
- R1: `com\.eightabyte\.pane(?![a-z])` becomes `com.eightabyte.transom`. This covers .debug, the test suite domains `.tests.*` and `.unknown-test-*`, the logger subsystem and CFBundleURLName.
- R2: `PANE(?=_|://)` becomes `TRANSOM`. This covers every env var and the uppercase-scheme rejection literal in the URL tests.
- R3a: `Panes(?=[A-Z])` becomes `Transoms` (test names such as aClampTheAppAppliesLateIsStillPanesOwn and aFloaterMovedBackOntoPanesLastWriteIsNotMovedAway).
- R3b: `(?<![A-Za-z])panes(?=[A-Z])` becomes `transoms` (panesOwnWriteComingBackWithin2PointsIsNotAMove).
- R4: `Pane(?![a-z])` becomes `Transom`. This covers module and type names (PaneModel ... PaneURLRateLimiter, PaneFixtureTabs), restoredByPane, aStoppedAppNeitherStallsPaneNor..., copy such as "Pane's", "Set Up Pane", "Pane Debug", Pane.app, Pane-Info.plist, Pane.entitlements, build/Pane-$version.dmg, build/Pane.zip, the data-folder literal "Pane", `pgrep -x Pane` and `quit app "Pane"`. Because a lowercase letter must not follow, Panel and Panels never match.
- R5: `panetests` becomes `transomtests` (the VM scratch directory in vm-live-test.sh).
- R6: `(?<![A-Za-z0-9_])pane(?![a-z_])(?!-notary)(?!-test(?!-))` becomes `transom`. This covers pane-dump, pane://, pane-debug, the bare scheme value `pane` in project.yml, release.sh and the AppDelegate comment, .build/pane-vm.lock, and the UserDefaults test-suite prefix `pane-test-\(UUID...)`. It deliberately leaves pane-notary, the Tart VM default `pane-test` (not followed by "-") and `pane_vm_ed25519` (underscore follows) unchanged. `.panel` never matches because "l" follows.
Code scope = tracked text files under Package.swift, Sources, Tests, scripts, xcode, .github. Enumerate them with `git grep -lzI -E 'pane|Pane|PANE' -- Package.swift Sources Tests scripts xcode .github` and pipe the list to `xargs -0 perl -pi -e ...`.
</rename_rules>

<interfaces>
Path renames (git mv). Directories first, then the five files that live inside or beside them:
- Sources/PaneModel → Sources/TransomModel; Sources/PaneEngine → Sources/TransomEngine; Sources/PaneMac → Sources/TransomMac; Sources/PanePrivate → Sources/TransomPrivate; Sources/PaneApp → Sources/TransomApp; Sources/PaneFixtureApp → Sources/TransomFixtureApp; Sources/PaneTestSupport → Sources/TransomTestSupport; Sources/pane-dump → Sources/transom-dump
- Tests/PaneModelTests → Tests/TransomModelTests; Tests/PaneEngineTests → Tests/TransomEngineTests; Tests/PaneMacTests → Tests/TransomMacTests; Tests/PaneMacIntegrationTests → Tests/TransomMacIntegrationTests
- Sources/TransomEngine/PaneURL.swift → Sources/TransomEngine/TransomURL.swift
- Sources/TransomMac/PaneMacApp.swift → Sources/TransomMac/TransomMacApp.swift
- Tests/TransomEngineTests/PaneURLTests.swift → Tests/TransomEngineTests/TransomURLTests.swift
- xcode/Pane-Info.plist → xcode/Transom-Info.plist
- xcode/Pane.entitlements → xcode/Transom.entitlements
After these moves, `git ls-files | grep -v '^\.planning/' | grep -E '[Pp]ane([^l]|$)'` must print nothing. (Today it lists more than 200 paths.)
</interfaces>
</context>

<tasks>

<task type="tracer">
  <name>Task 1: End-to-end mechanical rename, SwiftPM modules to Xcode project to signed Transom.app, in one building commit</name>
  <files>Package.swift, Package.resolved, Sources/** (git mv + rewrite), Tests/** (git mv + rewrite), xcode/project.yml, xcode/Transom-Info.plist, xcode/Transom.entitlements, scripts/build-debug.sh, scripts/check-no-appkit.sh, scripts/generate.sh, scripts/release.sh, scripts/run-debug.sh, scripts/vm-live-test.sh, .github/workflows/ci.yml</files>
  <precondition>`git status --short` shows nothing except ` M .planning/config.json` and `?? .planning/state.json` (plus this task's .planning/quick directory). HEAD is 82697cf or a docs-only descendant.</precondition>
  <action>
Implements every locked decision in <locked_decisions> for code, build, scripts and CI. Work in this order:

1. Run every git mv in <interfaces>: directories first, then the five files. Confirm with the path check at the end of <interfaces>. Do not use plain mv: history must follow the paths.

2. Run the single Perl pass from <rename_rules> (R1 to R6, in order) over the code scope it defines. Do not touch .planning, .claude or PLAN.md in this task. They belong to the docs commit (Task 2).

3. Hand-check and finish these spots (Read each file once):
   - Package.swift: package name Transom; library products TransomModel, TransomEngine and TransomMac; every target and test target uses the Transom* names; the executable target is transom-dump. Keep the KeyboardShortcuts dependency line exactly as is.
   - xcode/project.yml: `name: Transom`; packages key Transom (path ..); INFOPLIST_FILE Transom-Info.plist; target Transom; source ../Sources/TransomApp; dependency `package: Transom`, `product: TransomMac`; entitlements path Transom.entitlements; Debug PRODUCT_NAME "Transom Debug" with com.eightabyte.transom.debug and TRANSOM_URL_SCHEME transom-debug; Release PRODUCT_NAME Transom with com.eightabyte.transom and TRANSOM_URL_SCHEME transom. MARKETING_VERSION stays "0.3.0".
   - xcode/Transom-Info.plist: CFBundleURLName com.eightabyte.transom; the scheme string is the TRANSOM_URL_SCHEME build-setting expansion.
   - scripts/release.sh: header names Transom 0.3.0 and build/Transom-0.3.0.dmg; identifier com.eightabyte.transom; dmg path build/Transom-$version.dmg; build/Transom.zip; staging copy Transom.app; volume name "Transom $version"; the scheme check compares against transom and says "want transom". `profile=pane-notary` and the store-credentials header line are KEPT (locked decision). Directly above the profile line, add one comment explaining that the keychain profile was stored before the rename and keeps its name, so no new store-credentials run is needed. Write the comment by concept and do not repeat the profile string in it.
   - scripts/vm-live-test.sh: TRANSOM_VM, TRANSOM_VM_USER and TRANSOM_VM_KEY; TRANSOM_LIVE=1 in the guest env; .build/transom-vm.lock in mkdir, the message and the trap; TransomMacIntegrationTests.xctest and TransomFixtureApp in the copy, the test-bundle path and pkill; the guest directory transomtests; `pgrep -x Transom`, `quit app "Transom"` and /Applications/Transom.app. The defaults for the VM name and the SSH key path are KEPT (planner decision). Above the vm= line, add one comment explaining that the VM name and key keep their pre-rename names because they are existing host resources. Write it by concept, without repeating those strings.
   - scripts/check-no-appkit.sh: the default directories are Sources/TransomModel and Sources/TransomEngine, and the header comment names TransomModel and TransomEngine.
   - scripts/build-debug.sh: Debug "Transom Debug" with com.eightabyte.transom.debug; --release Transom with com.eightabyte.transom; the xcodebuild project is xcode/Transom.xcodeproj and the scheme is Transom.
   - scripts/generate.sh and scripts/run-debug.sh: comments and paths name Transom (xcode/Transom.xcodeproj, "Transom Debug.app").
   - .github/workflows/ci.yml: the comment names TRANSOM_LIVE=1.
   - Sources/TransomMac/MinimumHintsStore.swift: the folder literal is "Transom" and its doc comment says Application Support/Transom. Add NO migration or fallback to the old folder (locked decision: never shipped).
   - Tests/TransomEngineTests/TransomURLTests.swift: the uppercase-scheme rejection case now reads TRANSOM://restore, and every other case uses transom:// or transom-debug://. Tests/TransomMacTests/AppDelegateTests.swift uses urlScheme "transom-debug".

4. Prove nothing outside the rename changed: the case-insensitive "panel" count over `git grep -ohiE 'panel' -- . ':!.planning' ':!.claude' ':!PLAN.md'` is still 348, and `git grep -niE 'transoml'` finds nothing. Fix any difference before going on.

5. Build hygiene: delete the gitignored, generated xcode/Pane.xcodeproj. XcodeGen now writes xcode/Transom.xcodeproj, and the stale project only causes confusion. If xcodebuild later fails on stale package identity, delete the gitignored xcode/.xcode-build build output once and retry. Never use ad-hoc signing.

6. Run `swift package resolve`. If Package.resolved changes (for example its originHash), keep the change and stage it. If it does not change, leave it alone. The KeyboardShortcuts pin (3.1.0, revision 772133d9…) must not change.

7. Run the gates in <verify>, in order. They are headless only: never set PANE_LIVE or TRANSOM_LIVE, never launch the app or TransomFixtureApp, and never use the Tart VM. build-debug.sh and release.sh --build-only only build and codesign; they do not notarise, staple or upload.

8. Commit, staging explicit pathspecs only: `git add -A -- Package.swift Package.resolved Sources Tests scripts xcode .github`. Then confirm `git diff --cached --name-only` lists nothing under .planning or .claude and never .planning/config.json, .planning/state.json or .planning/milestone.lock. Message: "refactor: rename Pane to Transom (modules, bundle IDs, transom:// scheme, data folder, scripts)". Write a short body listing the kept pane-notary profile and the kept VM name and key, and end it with the trailer line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  </action>
  <verify>
    <automated>swift build && env -u PANE_LIVE -u PANE_LIVE_DRAG -u PANE_LIVE_FULLSCREEN -u TRANSOM_LIVE -u TRANSOM_LIVE_DRAG -u TRANSOM_LIVE_FULLSCREEN swift test > .build/rename-test.log 2>&1 && grep -E 'Test run with 534 tests in [0-9]+ suites passed' .build/rename-test.log && scripts/check-no-appkit.sh && scripts/build-debug.sh --release | tail -n 1 | grep -E '/Release/Transom\.app$' && codesign -d -r- xcode/.xcode-build/Build/Products/Release/Transom.app 2>&1 | grep -q 'identifier "com.eightabyte.transom"' && test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' xcode/.xcode-build/Build/Products/Release/Transom.app/Contents/Info.plist)" = com.eightabyte.transom && scripts/release.sh --build-only | tail -n 1 | grep -E '/Release/Transom\.app$' && test -z "$(git ls-files | grep -v '^\.planning/' | grep -E '[Pp]ane([^l]|$)')" && test "$(git grep -ohiE 'panel' -- . ':!.planning' ':!.claude' ':!PLAN.md' | wc -l | tr -d ' ')" = 348</automated>
  </verify>
  <done>Commit 1 exists and builds. Running swift build, the full headless swift test (534 tests passed), check-no-appkit, build-debug.sh --release and release.sh --build-only on that commit all succeed. Transom.app carries com.eightabyte.transom, team S2K7P43927 and scheme transom. No tracked path outside .planning contains "pane" except inside "panel", and the panel count is unchanged at 348.</done>
</task>

<task type="auto">
  <name>Task 2: Docs commit, covering the CLAUDE.md project section, PLAN.md and the living .planning docs (history untouched)</name>
  <files>.claude/CLAUDE.md, PLAN.md, .planning/PROJECT.md, .planning/ROADMAP.md, .planning/REQUIREMENTS.md</files>
  <action>
Hand-edit with the Edit tool (scoped replacements). Do not run the Task 1 Perl pass over these files: R6 would wrongly rewrite the generic-noun "pane" in SHIP-08.
- .claude/CLAUDE.md: edit ONLY the project section, between the GSD:project-start and GSD:project-end markers (lines 1-20). The heading becomes **Transom**, the description says "Transom is a free, open-source (MIT) macOS window manager ...", and the Testability constraint names TransomModel and TransomEngine. That section is sourced from PROJECT.md, so its text must match the edited PROJECT.md word for word. Leave the stack section (GSD:stack-start to GSD:stack-end) unchanged: it is generated from .planning/research/STACK.md, which is history. Task 3 lists its leftovers.
- PLAN.md (the original spec): line 3 becomes "Name: **Transom**." Lines 55-58 of the module diagram name TransomModel, TransomEngine and Transom.app. Leave line 77's "split/panel/group/desktop" and line 83's "overlay panel" alone (they say panel).
- .planning/PROJECT.md: the title becomes "# Transom". "What This Is" says "Transom is ...". The Constraints Testability line names TransomModel and TransomEngine. Also fix the other present-tense lines that name the app, modules or scheme: Active requirement "Saved views 1–9 and `transom://` URL commands"; Context, "Transom mirrors this as `TransomModel`, `TransomEngine` and `Transom.app`" and "Transom picks its own values"; and the Key Decisions row "Model / Engine / App layering", whose outcome now says TransomModel. KEEP the Key Decisions row 'Name "Pane" → "Transom"' exactly as it is: it records the rename.
- .planning/ROADMAP.md: change ONLY the title ("# Roadmap: Transom"), the Overview paragraph, the Phases-list lines for Phases 4-9, and the detail sections from "### Phase 4: Zoom Camera" up to "## Progress". In Phase 8, `pane://` becomes `transom://`, and "a bundled `pane` command-line tool" becomes `transom`. Every app mention ("Pane's overview", "run Pane from", "install Pane", "a notarised Pane") becomes Transom. Do NOT touch the Phase-list lines for Phases 1-3 (lines 15-17) or the detail sections "### Phase 1" to "### Phase 3" (lines 27-201). They are history (locked decision).
- .planning/REQUIREMENTS.md: the title becomes "# Requirements: Transom". Every requirement line naming the app becomes Transom (WIN-02/03/04/08, SAFE-01/04/05/06, OVER-02/03/06, SHIP-03/04, and the Out of Scope rows "Transom is free" and "Transom is GUI-first"). VIEW-03 says `transom://` URLs. VIEW-05 says a bundled `transom` command-line tool and `transom://` URLs. In SHIP-08, change only the scheme, giving `transom://settings?pane=` ... "opens a specific Settings pane". The `?pane=` query key and "Settings pane" are the generic UI noun and stay (case-by-case decision).
- Do not edit STATE.md (the orchestrator owns it), WINDOWS.md (a tool-managed ledger that records pre-rename paths as history), or anything under phases/, debug/, quick/ (except this task's directory), research/ or ui-reviews/.
Commit, staging exactly these five files with `git add -- .claude/CLAUDE.md PLAN.md .planning/PROJECT.md .planning/ROADMAP.md .planning/REQUIREMENTS.md`. Message: "docs: rename Pane to Transom in project docs and living planning docs". End it with the trailer line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  </action>
  <verify>
    <automated>D=$(git log -1 --format=%H --grep="^docs: rename Pane to Transom") && C=$(git log -1 --format=%H --grep="^refactor: rename Pane to Transom") && test -n "$D" && test -n "$C" && test "$(git diff --name-only "$D^" "$D" | LC_ALL=C sort | tr '\n' ' ')" = ".claude/CLAUDE.md .planning/PROJECT.md .planning/REQUIREMENTS.md .planning/ROADMAP.md PLAN.md " && test -z "$(sed -n '/GSD:project-start/,/GSD:project-end/p' .claude/CLAUDE.md | grep -E '[Pp]ane([^l]|$)')" && test "$(head -n 1 .planning/PROJECT.md)" = "# Transom" && test "$(head -n 1 .planning/ROADMAP.md)" = "# Roadmap: Transom" && test -z "$(sed -n '/^### Phase 4:/,/^## Progress/p' .planning/ROADMAP.md | grep -E '[Pp]ane([^l]|$)')" && git diff -U0 "$D^" "$D" -- .planning/ROADMAP.md | awk '/^@@/{split($2,a,","); l=substr(a[1],2)+0; if ((l>=15 && l<=17) || (l>=27 && l<202)) bad=1} END{exit bad}' && test -z "$(grep -nE '(^|[^A-Za-z])[Pp]ane([^l]|$)|Pane[A-Z]' .planning/REQUIREMENTS.md | grep -v 'SHIP-08')" && test -z "$(git diff --name-only "$C^" "$D" -- .planning/phases .planning/debug .planning/research .planning/ui-reviews .planning/STATE.md .planning/WINDOWS.md)"</automated>
  </verify>
  <done>Commit 2 touches exactly the five doc files. The CLAUDE.md project section, the ROADMAP title, overview and Phases 4-9, and REQUIREMENTS (except SHIP-08's generic-noun "pane") all say Transom. The ROADMAP Phase 1-3 history lines and every .planning history artifact are byte-identical to HEAD before the rename.</done>
</task>

<task type="auto">
  <name>Task 3: Residual audit, checking that the remaining Pane mentions are only the allow-listed leftovers, and record them in the SUMMARY</name>
  <files>.planning/quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/261027-ijh-SUMMARY.md</files>
  <action>
Run the user's two audit greps outside the .planning history. The history pathspec excludes .planning/phases, .planning/debug, .planning/quick, .planning/research, .planning/ui-reviews, .planning/STATE.md and .planning/WINDOWS.md. The greps are `git grep -niw pane` and `git grep -n 'Pane[A-Z]'`. Every hit must belong to this allow-list and nothing else:
- scripts/release.sh: the keychain profile pane-notary (the header store-credentials line and the profile= line). Kept: it is a credential name already stored in the user's keychain.
- scripts/vm-live-test.sh: the Tart VM default pane-test (the usage comment and the vm= line). Kept: it is an existing host VM. The SSH key ~/.ssh/pane_vm_ed25519 also stays, but -w does not report it; list it anyway.
- .planning/REQUIREMENTS.md SHIP-08: the `?pane=` query key and "Settings pane", which use the generic UI noun.
- .planning/PROJECT.md: the Key Decisions row recording "Pane" → "Transom".
- .planning/ROADMAP.md lines 15-17 and 27-201: Phase 1-3 history.
- .claude/CLAUDE.md after line 20: the stack section, generated from .planning/research/STACK.md, which is history. Recommend in the SUMMARY that the user decide whether to update STACK.md and regenerate. The section still carries prescriptive old names such as the PaneModel/PaneEngine rows of the Package Layout table, Pane.xcodeproj, Application Support/Pane and Pane-<version>-<arch>.dmg.
If any other hit appears, it is a missed rename. Fix it in code scope with the Task 1 rules, re-run the full Task 1 verify, and commit it as "fix: finish Pane to Transom rename leftovers" with the same trailer. Do not amend earlier commits.
Also confirm the package resolution is consistent. `swift package dump-package` must name the package Transom and contain no product or target name starting with Pane. `swift package resolve` must leave the tree clean. `git status --short` must show only .planning/config.json, .planning/state.json and this task's SUMMARY.
Write the SUMMARY (per the summary template) with these parts:
- Both commit hashes.
- The gate results: the 534-test count, build-debug and release.sh --build-only output paths, and the designated-requirement line.
- The full allow-list above, with the actual grep output lines pasted under each entry.
- The kept-name decisions (pane-notary; the pane-test VM and SSH key).
- Notes for the orchestrator:
  - graft/ is untracked and gitignored, so it was not edited.
  - No README or LICENSE exists in the repo.
  - No panewm URLs were found.
  - WINDOWS.md open entries 2 and 3 still cite Sources/PaneMac/... paths, which now live under Sources/TransomMac/.
  - The Tart VM still has /Applications/Pane.app installed, so vm-live-test.sh's quit/relaunch now targets Transom and a Transom build must be installed in the VM before the next live run.
  - The new bundle ID resets the TCC Accessibility grant.
  - The STATE.md "Pending: Rename to Transom" section and the "Name Pane" blocker are left for the orchestrator.
  - The orchestrator still has to rename the GitHub repo to scottkw/transomwm and move ~/dev/panewm, and the executor did neither.
  </action>
  <verify>
    <automated>H=(':!.planning/phases' ':!.planning/debug' ':!.planning/quick' ':!.planning/research' ':!.planning/ui-reviews' ':!.planning/STATE.md' ':!.planning/WINDOWS.md'); test -z "$( { git grep -niw pane -- . "${H[@]}"; git grep -n 'Pane[A-Z]' -- . "${H[@]}"; } | awk -F: '!( ($1==".claude/CLAUDE.md" && $2>20) || ($1==".planning/ROADMAP.md" && (($2>=15 && $2<=17) || ($2>=27 && $2<202))) || ($1==".planning/PROJECT.md" && /Name "Pane"/) || ($1==".planning/REQUIREMENTS.md" && /SHIP-08/) || ($1=="scripts/release.sh" && /pane-notary/) || ($1=="scripts/vm-live-test.sh" && /pane-test/) )')" && P='(^|[^A-Za-z])[Pp]ane([^a-z]|$)|Pane[A-Z]|[a-z]Pane([^l]|$)|PANE([^L]|$)|[Pp]anes[A-Z]|panetests'; test -z "$(git grep -nIE "$P" -- Package.swift Sources Tests scripts xcode .github | sed -E 's/pane-notary|pane-test([^-]|$)|pane_vm_ed25519/KEPT/g' | grep -E "$P")" && swift package dump-package | grep -q '"name" : "Transom"' && ! swift package dump-package | grep -qE '"name" : "(Pane|pane-)' && test -f .planning/quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/261027-ijh-SUMMARY.md</automated>
  </verify>
  <done>Both audit greps outside the history return only allow-listed lines. The code-scope token audit, with the three kept host-resource names masked, returns nothing. dump-package shows package Transom with no Pane* names. The working tree is clean apart from the never-staged config.json and state.json. The SUMMARY lists every leftover with its reason and the orchestrator follow-ups.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| other apps → transom:// URL handler | Any process can open a URL in the app's scheme through LaunchServices. The rename changes the scheme string but not the strict parser or the 1/s rate limit (T-03-40) |
| build → signed bundle | The designated requirement (identifier + team) is what TCC trusts. The identifier changes with the rename |
| app → ~/Library/Application Support/Transom | layout.json and min-size-hints.json, written 0600, rejected whole on doubt |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-ijh-01 | Spoofing | TransomURL.parse / AppDelegate URL dispatch | medium | mitigate | Only the scheme literal changes. TransomURLTests (strict-shape and uppercase-scheme rejection cases, rewritten by R2/R6) and AppDelegateTests (allow-list + rate limit) must still pass inside the 534-test gate. A missed rename shows up as failing cases, not as silently accepting the old scheme |
| T-ijh-02 | Spoofing / Elevation | Code signature designated requirement | high | mitigate | build-debug.sh --release and release.sh --build-only check `identifier "com.eightabyte.transom"` plus team S2K7P43927, a secure timestamp, and the absence of get-task-allow, disable-library-validation and apple-events entitlements. Release keeps CODE_SIGN_INJECT_BASE_ENTITLEMENTS NO and hardened runtime. Never ad-hoc sign |
| T-ijh-03 | Tampering | Blind substring rename corrupting unrelated identifiers (panel, NSPanel, .panel model case) | medium | mitigate | Rules R1-R6 are token-anchored. Gates: panel count stays 348, no "transoml", the 534-test count is unchanged, and the code-scope token audit is empty except for the three kept names |
| T-ijh-04 | Information disclosure | Data folder rename | low | accept | No migration is added (locked decision: never shipped). The old ~/Library/Application Support/Pane on the developer's and the VM's machines is simply ignored. File modes and reject-whole logic are unchanged |
| T-ijh-05 | Repudiation | os.Logger subsystem | low | accept | The subsystem changes to com.eightabyte.transom. Privacy annotations are untouched. Bug-report instructions must use the new subsystem (docs follow in Phase 9) |
| T-ijh-SC | Tampering | SwiftPM dependencies | low | accept | No package is added or upgraded. The KeyboardShortcuts exact 3.1.0 pin and its revision in Package.resolved must not change (Task 1 step 6) |
</threat_model>

<verification>
- Task 1 automated chain: build, 534 headless tests, no-AppKit, signed Transom.app (Release) with identifier com.eightabyte.transom, release.sh --build-only, no pane-named tracked paths, panel count 348.
- Task 2 automated chain: the docs commit touches exactly five files, ROADMAP Phase 1-3 lines have no hunks, and no history artifact changed.
- Task 3 automated chain: the residual audit returns only allow-listed lines, and dump-package shows Transom.
- `git log --follow --oneline -- Sources/TransomEngine/TransomURL.swift | tail -n 1` reaches a commit from before the rename (history follows the git mv).
- Nothing was launched: no TransomFixtureApp or Transom process was started on the host (`pgrep -fl 'TransomFixtureApp|PaneFixtureApp'` is empty), and no tag, release, notarisation or upload happened.
</verification>

<success_criteria>
- Two commits (three only if Task 3 found a missed rename): a building code rename, then a docs-only commit, each with the Co-Authored-By trailer.
- Transom.app (Release) is built and Developer-ID signed as com.eightabyte.transom. It is not notarised and not uploaded. Version 0.3.0.
- The headless suite still runs 534 tests and passes.
- The SUMMARY lists every intentional leftover and the orchestrator follow-ups (repo rename, directory move, STATE.md, VM app install, TCC re-grant).
</success_criteria>

<output>
Create `.planning/quick/261027-ijh-rename-the-app-from-pane-to-transom-acro/261027-ijh-SUMMARY.md` when done
</output>
