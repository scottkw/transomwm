#!/usr/bin/env bash
# Local release pipeline for Pane 0.3.0 (D-30): builds the universal Developer ID Release app through
# build-debug.sh --release and refuses to continue on any signing problem (RESEARCH Pitfall 1).
# Usage: scripts/release.sh [--build-only]
#   --build-only   build and verify the app, print its path, stop
# Exit: 0 success, 1 a check failed, 2 bad usage.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

build_only=0
case "${1:-}" in
    "") ;;
    --build-only) build_only=1 ;;
    *) echo "release: unknown argument: $1 (usage: scripts/release.sh [--build-only])" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "release: too many arguments" >&2; exit 2; }

version=0.3.0
identifier=com.eightabyte.pane
team=S2K7P43927
fail() { echo "release: $1" >&2; exit 1; }

# 1. Build and verify. build-debug.sh already checks the designated requirement (identifier + team).
app="$(scripts/build-debug.sh --release | tail -n 1)"
[ -d "$app" ] || fail "no app at $app"

# Captured first: grep -q closing the pipe early would trip pipefail.
details="$(codesign -dvv "$app" 2>&1)"
grep -q '^Timestamp=' <<<"$details" || fail "no secure timestamp on $app"
codesign --verify --strict --deep --verbose=2 "$app" >&2 || fail "codesign --verify --strict --deep failed"
requirement="$(codesign -d -r- "$app" 2>&1)"
case "$requirement" in *"identifier \"$identifier\""*"$team"*) ;; *) fail "designated requirement changed: $requirement" ;; esac
entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)"
for forbidden in get-task-allow disable-library-validation automation.apple-events; do
    case "$entitlements" in *"$forbidden"*) fail "forbidden entitlement present: $forbidden" ;; esac
done
plist="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
archs="$(lipo -archs "$executable")"
case " $archs " in *" x86_64 "*) ;; *) fail "executable lacks x86_64 (has: $archs)" ;; esac
case " $archs " in *" arm64 "*) ;; *) fail "executable lacks arm64 (has: $archs)" ;; esac
shown="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
[ "$shown" = "$version" ] || fail "CFBundleShortVersionString is $shown, want $version"
scheme="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$plist")"
[ "$scheme" = pane ] || fail "URL scheme is $scheme, want pane"

if [ "$build_only" = 1 ]; then
    echo "$app"
    exit 0
fi
