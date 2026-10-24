#!/usr/bin/env bash
# Builds "Pane Debug.app" and launches it through LaunchServices, so TCC attributes it to Pane and not
# to the terminal (Pitfall 9). Remaining arguments go to the app, e.g. --disable-private=AXWindowID.
# Usage: scripts/run-debug.sh [--no-build] [args...]
# Exit: 0 launched, 1 the build or launch failed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

app="$root/xcode/.xcode-build/Build/Products/Debug/Pane Debug.app"
if [ "${1:-}" = "--no-build" ]; then
    shift
else
    app="$(scripts/build-debug.sh | tail -n 1)"
fi
if [ ! -d "$app" ]; then
    echo "run-debug: no app at $app; run without --no-build first" >&2
    exit 1
fi
open -n "$app" --args "$@"
