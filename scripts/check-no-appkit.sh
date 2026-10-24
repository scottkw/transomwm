#!/usr/bin/env bash
# Fails if PaneModel or PaneEngine imports a UI framework (D-23), so they stay headless-testable.
# Usage: scripts/check-no-appkit.sh [dir ...]   (default: Sources/PaneModel Sources/PaneEngine)
# Exit: 0 clean, 1 violation found, 2 a directory is missing or has no .swift files.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
if [ "$#" -eq 0 ]; then set -- Sources/PaneModel Sources/PaneEngine; fi

pattern='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?(AppKit|Cocoa|SwiftUI)([[:space:].]|$)'
files=()
for dir in "$@"; do
    if [ ! -d "$dir" ]; then
        echo "no-appkit: directory not found: $dir" >&2
        exit 2
    fi
    found=()
    while IFS= read -r -d '' f; do found+=("$f"); done < <(find "$dir" -type f -name '*.swift' -print0)
    if [ "${#found[@]}" -eq 0 ]; then
        echo "no-appkit: no .swift files in $dir" >&2
        exit 2
    fi
    files+=("${found[@]}")
done

# grep exits 1 on no match and 2 on a read error; only 0 and 1 are expected here.
status=0
grep -nHE "$pattern" "${files[@]}" || status=$?
if [ "$status" -eq 0 ]; then exit 1; fi
if [ "$status" -ne 1 ]; then
    echo "no-appkit: grep failed with status $status" >&2
    exit 2
fi
echo "no-appkit: OK (${#files[@]} files)"
