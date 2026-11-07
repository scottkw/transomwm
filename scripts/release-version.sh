#!/usr/bin/env bash
# Release version gate (D-11). Prints MARKETING_VERSION from xcode/project.yml after checking that it is
# MAJOR.MINOR.PATCH and that docs/release-notes-<version>.md exists.
# Usage: scripts/release-version.sh [vX.Y.Z]   (with a tag, it must be exactly "v" + the version)
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "release-version: $*" >&2
    exit 1
}

v="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' xcode/project.yml)"
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "xcode/project.yml: MARKETING_VERSION '$v' is not MAJOR.MINOR.PATCH"
[ -f "docs/release-notes-$v.md" ] || fail "docs/release-notes-$v.md is missing"

if [ $# -gt 1 ]; then
    fail "usage: release-version.sh [vX.Y.Z]"
fi
if [ $# -eq 1 ] && [ "$1" != "v$v" ]; then
    fail "tag '$1' does not match version $v (expected v$v)"
fi

echo "$v"
