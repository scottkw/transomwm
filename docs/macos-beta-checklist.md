# macOS beta checklist: private APIs

Transom reaches five private APIs through `dlopen` and `dlsym`, never by linking, so a symbol Apple removes or changes disables only the feature built on it (D-15). Any macOS update can still break one. Run this check on every macOS beta, and again on the release, before telling users the new macOS is supported (D-18).

## Symbols

Generated from the string literals in `Sources/TransomPrivate`:

```sh
grep -rhoE '"(_AX|SLS|CGS|CoreDock|MT)[A-Za-z]+"' Sources/TransomPrivate | sort -u
```

Re-run it after any change to `TransomPrivate` and update this table.

| Symbol | Framework | File | Capability (`--disable-private=` name) | Needed for the capability to load |
|---|---|---|---|---|
| `_AXUIElementGetWindow` | ApplicationServices | `AXWindowID.swift` | `AXWindowID` | yes |
| `SLSMainConnectionID` | SkyLight | `SkyLightSpaces.swift` | `Spaces` | yes |
| `SLSCopySpacesForWindows` | SkyLight | `SkyLightSpaces.swift` | `Spaces` | yes |
| `SLSManagedDisplayGetCurrentSpace` | SkyLight | `SkyLightSpaces.swift` | `Spaces` | no: each display's current Space |
| `SLSCopyManagedDisplaySpaces` | SkyLight | `SkyLightSpaces.swift` | `Spaces` | no: the overview's Spaces strip |
| `SLSGetSpaceManagementMode` | SkyLight | `SkyLightSpaces.swift` | `Spaces` | no: "Displays have separate Spaces" |
| `SLSIsSymbolicHotKeyEnabled`, or `CGSIsSymbolicHotKeyEnabled` | SkyLight | `SymbolicHotKeys.swift` | `SymbolicHotKeys` | yes (either name) |
| `SLSSetSymbolicHotKeyEnabled`, or `CGSSetSymbolicHotKeyEnabled` | SkyLight | `SymbolicHotKeys.swift` | `SymbolicHotKeys` | yes (either name) |
| `SLSGetSymbolicHotKeyValue`, or `CGSGetSymbolicHotKeyValue` | SkyLight | `SymbolicHotKeys.swift` | `SymbolicHotKeys` | yes (either name) |
| `CoreDockSendNotification` | HIServices | `CoreDock.swift` | `CoreDock` | yes |
| `MTDeviceCreateList` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | yes |
| `MTRegisterContactFrameCallbackWithRefcon` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | one of the two register calls |
| `MTRegisterContactFrameCallback` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | one of the two register calls |
| `MTUnregisterContactFrameCallback` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | yes |
| `MTDeviceStart` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | yes |
| `MTDeviceStop` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | yes |
| `MTDeviceIsBuiltIn` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | no: device details |
| `MTDeviceGetFamilyID` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | no: device details |
| `MTDeviceGetDeviceID` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | no: device details |
| `MTDeviceGetSensorSurfaceDimensions` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | no: device details |
| `MTDeviceGetService` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | no: device details |
| `MTDeviceGetDriverType` | MultitouchSupport | `MultitouchSupport.swift` | `Multitouch` | no: device details |

Framework paths: ApplicationServices is `/System/Library/Frameworks/ApplicationServices.framework`, HIServices is inside it, SkyLight and MultitouchSupport are in `/System/Library/PrivateFrameworks`.

## Capabilities and fallbacks

| `--disable-private=` | Feature | Fallback | Live suite |
|---|---|---|---|
| `AXWindowID` | The window ID behind an Accessibility window | Windows matched by frame against the public window list | `FixtureTrackingTests`, `CloseIntegrationTests`; `FallbackIntegrationTests` runs the fallback |
| `Spaces` | Which Space each window and display is on, the overview's Spaces strip | Single-Space behaviour, no strip | `SpacesIntegrationTests`, then `OverviewSpaceSwitchIntegrationTests` |
| `SymbolicHotKeys` | Turning Mission Control's keys off while the overview uses them | The overview toggle is unavailable; Mission Control keys unchanged | `TakeoverIntegrationTests` |
| `CoreDock` | Opening Mission Control when the overview can't open | A beep and a message | none; check by hand (below) |
| `Multitouch` | Reading the pinch from the trackpad when Trackpad ▸ "Zoom in or out" is off | Gestures from system events only | `MultitouchIntegrationTests` (the VM has no trackpad, so this proves only that the shim loads and runs) |

## Procedure for each beta

1. **Record** the beta's name and build (`sw_vers`) in the results table below.
2. **Read the capability report.** Launch the beta build of Transom in a Tart VM running the beta. It logs each capability as `available` or `off` at launch:

   ```sh
   log show --last 5m --info --predicate 'subsystem == "com.eightabyte.transom" AND category == "private"'
   ```

   Every line should read `available`. An `off` with no `--disable-private=` flag means a required symbol is missing: rerun the grep above against the beta's frameworks to find which.
3. **Run each capability's live suite** in the VM, one suite per session, never on your own Mac:

   ```sh
   TRANSOM_VM=<vm> scripts/vm-session.sh scripts/vm-live-test.sh SpacesIntegrationTests
   ```

   Repeat for each suite in the table above. A symbol can resolve and still change its arguments or results, which only the live suites catch.
4. **Check CoreDock by hand** in the VM: turn on Settings ▸ Zoom & Gestures ▸ "Use the Mission Control keys for the overview", open an app in native full screen (the overview does not open over a full-screen Space), press F3 there, and check that Mission Control opens and the log shows `mission control key → macOS Mission Control` (category `missionControl`).
5. **For any capability that fails**, launch with its flag and check that the fallback works and nothing else breaks:

   ```sh
   scripts/run-debug.sh --disable-private=Spaces
   ```

   The log then shows that capability as `off`. If the fallback holds, ship with the capability left to switch itself off (a function that keeps failing is turned off for the session); if the API changed shape, fix its file in `TransomPrivate` before claiming support for that macOS.
6. **Record** the results, and open an issue for each failure.

## Results

| Date | macOS build | AXWindowID | Spaces | SymbolicHotKeys | CoreDock | Multitouch | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
