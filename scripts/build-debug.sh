#!/usr/bin/env bash
# Builds the Developer-ID-signed app (D-03, D-04): "Transom Debug.app" by default, "Transom.app" with --release,
# then checks its signature and designated requirement so TCC grants survive rebuilds.
# Usage: scripts/build-debug.sh [--release]
# Exit: 0 built and verified (last stdout line is the app path), 1 a check failed, 2 bad usage.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

config=Debug product="Transom Debug" identifier=com.eightabyte.transom.debug
case "${1:-}" in
    "") ;;
    --release) config=Release product=Transom identifier=com.eightabyte.transom ;;
    *) echo "build-debug: unknown argument: $1 (usage: scripts/build-debug.sh [--release])" >&2; exit 2 ;;
esac
team=S2K7P43927
app="$root/xcode/.xcode-build/Build/Products/$config/$product.app"

scripts/generate.sh
build=(xcodebuild -project xcode/Transom.xcodeproj -scheme Transom -configuration "$config"
    -derivedDataPath xcode/.xcode-build build)
if command -v xcbeautify >/dev/null 2>&1; then
    "${build[@]}" | xcbeautify >&2
else
    "${build[@]}" >&2
fi

fail() { echo "build-debug: $1" >&2; exit 1; }
[ -d "$app" ] || fail "no app at $app"
codesign --verify --strict --verbose=2 "$app" >&2 || fail "codesign --verify failed for $app"
requirement="$(codesign -d -r- "$app" 2>&1)" || fail "codesign -d -r- failed for $app"
case "$requirement" in *"identifier \"$identifier\""*) ;; *) fail "designated requirement lacks identifier \"$identifier\"" ;; esac
case "$requirement" in *"$team"*) ;; *) fail "designated requirement lacks team $team" ;; esac
echo "$app"
