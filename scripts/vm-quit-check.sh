#!/usr/bin/env bash
# Quits the real bundled app from outside inside the Tart test VM, never on this Mac (OutsideQuitIntegrationTests): builds
# "Transom Debug.app" into its own derived-data folder, so a Debug app running from xcode/.xcode-build is left alone,
# and hands it to scripts/vm-live-test.sh. Pass: its output ends with "Test run with 1 test ... passed".
# Usage: scripts/vm-quit-check.sh [path to an already built Transom Debug.app]
# Env: as scripts/vm-live-test.sh. The VM must not be running Transom Debug.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
app="${1:-}"
if [ -z "$app" ]; then
    scripts/generate.sh
    xcodebuild -project xcode/Transom.xcodeproj -scheme Transom -configuration Debug -derivedDataPath .build/vm-quit-app build >&2
    app=".build/vm-quit-app/Build/Products/Debug/Transom Debug.app"
fi
TRANSOM_VM_APP="$app" scripts/vm-live-test.sh OutsideQuitIntegrationTests
