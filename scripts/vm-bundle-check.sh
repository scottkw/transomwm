#!/usr/bin/env bash
# Runs a suite against the real bundled app inside the Tart test VM, never on this Mac: builds "Transom Debug.app" into its
# own derived-data folder, so a Debug app running from xcode/.xcode-build is left alone, and hands it to scripts/vm-live-test.sh.
# Usage: scripts/vm-bundle-check.sh <suite> [path to an already built Transom Debug.app]
# Env: as scripts/vm-live-test.sh. The VM must not be running Transom Debug.
set -euo pipefail

suite="${1:?usage: scripts/vm-bundle-check.sh <suite> [path to an already built Transom Debug.app]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
app="${2:-}"
if [ -z "$app" ]; then
    scripts/generate.sh
    xcodebuild -project xcode/Transom.xcodeproj -scheme Transom -configuration Debug -derivedDataPath .build/vm-bundle-app build >&2
    app=".build/vm-bundle-app/Build/Products/Debug/Transom Debug.app"
fi
TRANSOM_VM_APP="$app" scripts/vm-live-test.sh "$suite" TRANSOM_LIVE_DRAG=1
