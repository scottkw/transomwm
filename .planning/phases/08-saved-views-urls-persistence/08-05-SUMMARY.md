---
phase: 08-saved-views-urls-persistence
plan: 05
subsystem: shell
tags: [cli, cfmessageport, url-scheme, rate-limit, xcodegen, code-signing, swift-testing, vm-live]

requires:
  - phase: 08-saved-views-urls-persistence
    provides: "08-01 ViewSlot and CameraCommand.view/.saveView; 08-03 the go-view flow, the views log category and the ViewCopy Debug line"
provides:
  - transom://view/{n} and transom://save-view/{n} with a byte-exact path rule; each slot limited on its own
  - TransomURL.helpLines, slot(digit:) and registeredScheme(in:) (moved from AppDelegate)
  - CLICommandLine, CLICopy and CLIProtocol in TransomEngine
  - the transom-cli executable target; Transom.app/Contents/Helpers/transom in the Xcode build
  - CommandGate (one allow-list and limiter for URL opens and CLI requests) and CLIListener
  - ArrangeController.decide(_:from:afterSwitch:), answerCLI(_:), cliReply(for:), silenced(_:of:), cliListener; CommandSource.cli and isSilent
  - the "Command-line tool: ..." Debug line
  - scripts/release.sh checks for the bundled helper
affects: [08-06 inserts the "Waiting for windows" Debug line above the CLI line, 08-07 proves the installed bundle in the VM and writes the README]

actuals:
  tokens: 18000
  tasks: 3
  commits: 4

plan_head_before: 914a1c08985dbf97843035dfc6c43f9eb2250ddb
plan_head_after: d41e602aae5707a359167bb2cdf53bd9d49cf907

tech-stack:
  added: []
  patterns:
    - "A command's effects are decided synchronously, so a request can be answered before they run"
    - "A beep in the unsilenced effects is the refusal signal; the reply takes the text VoiceOver would hear"

key-files:
  created:
    - Sources/TransomEngine/CLICommandLine.swift
    - Sources/TransomEngine/CLICopy.swift
    - Sources/TransomEngine/CLIProtocol.swift
    - Sources/transom-cli/main.swift
    - Sources/TransomMac/CommandGate.swift
    - Sources/TransomMac/CLIListener.swift
    - Tests/TransomEngineTests/CLICommandLineTests.swift
    - Tests/TransomEngineTests/CLICopyTests.swift
    - Tests/TransomEngineTests/CLIProtocolTests.swift
    - Tests/TransomMacTests/CLIListenerTests.swift
  modified:
    - Sources/TransomEngine/TransomURL.swift
    - Sources/TransomMac/AppDelegate.swift
    - Sources/TransomMac/ArrangeController.swift
    - Sources/TransomMac/TransomMacApp.swift
    - Sources/TransomMac/Shell/StatusItemController.swift
    - Sources/TransomMac/Shell/ViewCopy.swift
    - Package.swift
    - xcode/project.yml
    - scripts/release.sh
    - Tests/TransomEngineTests/TransomURLTests.swift
    - Tests/TransomMacTests/AppDelegateTests.swift
    - Tests/TransomMacTests/ViewCopyTests.swift

key-decisions:
  - "The Xcode target is transom-tool with PRODUCT_NAME transom: a target named transom would share a build folder with Transom on a case-insensitive volume"
  - "A URL refused for a view shows no toast either (N16, N18, N19 are silenced on URL and CLI routes), which 08-03's filter still let through"
  - "CLICopy.ascii also replaces every other non-printable or non-ASCII character with ?, so whoever answers on the port cannot send terminal escapes"
  - "A view on another Space goes through dispatch: viewSwitch(for:) runs first on every route, and decide runs after the switch"

patterns-established:
  - "Host-safe IPC test: a private test port, a frozen clock, a stub decision and the built tool spawned with TRANSOM_CLI_PORT"

requirements-completed: []

coverage:
  - id: D1
    description: "transom://view/{n} and save-view/{n} run the hotkey commands; every other path form is rejected, and each slot has its own rate limit"
    requirement: VIEW-03
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/TransomURLTests.swift#theViewCommandsParse, #malformedViewURLsAreRejected, #eachSlotIsLimitedSeparately"
        status: pass
    human_judgment: false
  - id: D2
    description: "The built CLI crosses a CFMessagePort through the shared gate: exit 0 silent, 1 for rate limit and refusal, 2 with no listener, 64 for usage; bad requests are rejected"
    requirement: VIEW-05
    verification:
      - kind: integration
        ref: "Tests/TransomMacTests/CLIListenerTests.swift"
        status: pass
    human_judgment: false
  - id: D3
    description: "Exact help text, usage messages and exit codes; one help line per allow-listed command"
    requirement: VIEW-05
    verification:
      - kind: unit
        ref: "Tests/TransomEngineTests/CLICommandLineTests.swift, CLICopyTests.swift, CLIProtocolTests.swift"
        status: pass
    human_judgment: false
  - id: D4
    description: "Refusal replies carry the VoiceOver text, and URL and CLI refusals stay silent on screen"
    requirement: VIEW-05
    verification:
      - kind: unit
        ref: "Tests/TransomMacTests/CLIListenerTests.swift#aRefusalRepliesItsAnnouncement, #anEmptySlotRepliesItsToastText, #zoomOffRefusesTheCLIAndNothingElseSeesIt, #aSilentRouteKeepsToastsButNotRefusals"
        status: pass
    human_judgment: false
  - id: D5
    description: "The dispatch split keeps the go-view flow, including a view on another Space"
    verification:
      - kind: e2e
        ref: "scripts/vm-live-test.sh ViewsIntegrationTests"
        status: pass
    human_judgment: false
  - id: D6
    description: "Debug and universal Release bundles contain a signed, hardened-runtime Contents/Helpers/transom; release.sh refuses a bundle without it"
    requirement: VIEW-05
    verification:
      - kind: other
        ref: "scripts/build-debug.sh and scripts/release.sh --build-only, then Contents/Helpers/transom help"
        status: pass
    human_judgment: false
  - id: D7
    description: "The installed helper finds its bundle (through a symlink too), names the right channel, and reaches a running app with a real command"
    requirement: VIEW-05
    verification: []
    human_judgment: true
    rationale: "Assumptions A3 and Pitfall 10 can only be proved against a running Transom, which never happens on this host; 08-07 proves them in the VM"

duration: 22min
completed: 2026-11-04
status: complete
---

# Phase 8 Plan 05: URLs and the Bundled CLI Summary

**`transom view 3` checks the command with the URL parser, crosses a CFMessagePort to the running app's shared gate, runs the same command as the hotkey and exits 0/1/2/64 with the UI-SPEC's exact text; the signed tool ships at `Contents/Helpers/transom`**

## Performance

- **Duration:** 22 min
- **Started:** 2026-11-04T00:37:38Z
- **Completed:** 2026-11-04T00:59:30Z
- **Tasks:** 3
- **Files modified:** 22

## Accomplishments

- `transom://view/{n}` and `transom://save-view/{n}` parse by byte comparison, so `/%33`, `/03`, `/3/` and the bare forms are rejected; each slot has its own rate limit.
- One `CommandGate` holds the allow-list check and the limiter for URL opens and CLI requests, so `transom://view/3` and `transom view 3` count as one command.
- `ArrangeController.dispatch` is now a synchronous `decide` followed by its effects, and `answerCLI` returns the reply before the effects run.
- The tool prints the exact help and messages, stays ASCII, and uses no API that opens or launches anything (D-08).
- Debug and universal Release bundles carry a signed tool with the hardened runtime; `scripts/release.sh --build-only` passes with its new checks.

## Task Commits

1. **Task 1: Tracer, `transom view 3` through to the hotkey's command** - `69961cf` (feat)
2. **Task 2: Exact copy, exit codes, rejected forms, Debug line** - `193d36a` (test), `631491b` (feat)
3. **Task 3: Ship the CLI at Contents/Helpers/transom** - `d41e602` (feat)

## Notes the plan asked for

**Swift import shapes (Assumption A6, confirmed by compiling):**
- `CFMessagePortCallBack` closure: `{ _, msgid, data, info in ... }` returning `Unmanaged<CFData>?`, with `msgid: Int32`, `data: CFData?` and `info: UnsafeMutableRawPointer?`. It is non-capturing and uses `MainActor.assumeIsolated` inside.
- `CFMessagePortSendRequest(remote, msgid, data, sendTimeout, rcvTimeout, CFRunLoopMode.defaultMode.rawValue, &reply)` with `var reply: Unmanaged<CFData>?`, read with `takeRetainedValue()`.

**Built helper paths:**
- `xcode/.xcode-build/Build/Products/Debug/Transom Debug.app/Contents/Helpers/transom`
- `xcode/.xcode-build/Build/Products/Release/Transom.app/Contents/Helpers/transom`
- SwiftPM's is `.build/debug/transom-cli`, used by the tests.

## Decisions Made

See `key-decisions`. In addition, `CLIListener` keeps the gate call so the host-safe test exercises the same code as the app, with `decide` as the only stub, instead of the app passing it a whole handler.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Refused views still showed a toast on URL routes**
- **Found during:** Task 1
- **Issue:** The UI-SPEC says N16 shows nothing for a URL, and "same silence on screen for refusals" for the CLI. The 08-03 filter dropped only the beep and the announcement, so `viewEmpty`, `viewDisplayGone` and `viewNothingToSave` still toasted. A beeping non-camera command also still announced from a URL.
- **Fix:** One `ArrangeController.silenced(_:of:)` for URL and CLI routes.
- **Files modified:** Sources/TransomMac/ArrangeController.swift
- **Verification:** `CLIListenerTests#aSilentRouteKeepsToastsButNotRefusals`
- **Committed in:** 69961cf

**2. [Rule 2 - Missing critical] The helper needed its own entitlements file and Release settings**
- **Found during:** Task 3
- **Issue:** With no file, Xcode signed the helper with `com.apple.application-identifier`, which needs a provisioning profile, and the plan did not disable `get-task-allow` for the tool in Release. Either could break notarisation or launch.
- **Fix:** The tool uses `CODE_SIGN_ENTITLEMENTS: Transom.entitlements` and `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` in Release. `release.sh` refuses either entitlement on the helper. The tool's Info.plist is embedded in the binary, so its signature carries `com.eightabyte.transom.cli`.
- **Files modified:** xcode/project.yml, scripts/release.sh
- **Verification:** `scripts/release.sh --build-only` passes; `codesign -d --entitlements -` shows only `app-sandbox: false`
- **Committed in:** d41e602

**3. [Rule 2 - Missing critical] CLICopy.ascii strips control characters**
- **Found during:** Task 2
- **Issue:** The tool prints whatever reason the port's owner sends, and the name can be taken first (T-08-16, accepted), so a reply could carry terminal escapes.
- **Fix:** Everything outside printable ASCII becomes "?".
- **Files modified:** Sources/TransomEngine/CLICopy.swift
- **Verification:** `CLICopyTests#asciiReplacesEverythingElse`
- **Committed in:** 631491b

### Smaller differences from the plan's wording

- The Xcode target is `transom-tool`, not `transom`; the product is still `transom` (see key-decisions).
- `cliReply(for:)` has no `command:` parameter: the tool names the command in its own fallback line, so the app never used it.
- `CLIListener(name:gate:now:decide:)` takes the gate and a decision rather than a whole handler; the `now` seam keeps the rate-limit test independent of process start time.
- The RED commit `193d36a` failed on missing API and also had a test that did not compile (a mutating call inside `#expect`), fixed in `631491b`.

---

**Total deviations:** 3 auto-fixed (1 bug, 2 missing critical)
**Impact on plan:** All needed for the UI-SPEC's silence rule or for notarisation and terminal safety. No scope creep.

## Issues Encountered

- After changing the tool's entitlements, an incremental Release build kept the old signed copy in `Contents/Helpers`, though `Products/Release/transom` was right. The new `release.sh` check caught it, and removing the built `.app` fixed it. `release.sh` doesn't clean, so a changed helper signature needs a fresh `.app`.

## Verification

- `swift test` on the host: 226, 428, 99 and 1058 tests passed across the four bundles, no failures. The IPC tests used private port names only.
- `scripts/check-no-appkit.sh`: OK. All task acceptance greps pass.
- VM: `scripts/vm-live-test.sh ViewsIntegrationTests` passed 2 tests, including `aViewOnAnotherSpaceSwitchesFirst`, after the dispatch split.
- On this Mac the bundled helper was run only with `help`. No command reached a running Transom and no `transom://` URL was opened.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for 08-06 and 08-07. 08-07 must prove these in the VM against the installed bundle:
- the helper finds its bundle, also through the `/usr/local/bin` symlink (A3);
- whether an SSH session sees the GUI session's port (Pitfall 10); run it with `launchctl asuser` if not.

VIEW-03 and VIEW-05 stay open in REQUIREMENTS.md, because 08-07 also claims them.

---
*Phase: 08-saved-views-urls-persistence*
*Completed: 2026-11-04*

## Self-Check: PASSED
