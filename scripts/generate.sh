#!/usr/bin/env bash
# Generates xcode/Transom.xcodeproj from xcode/project.yml (D-05). The project is gitignored.
# Usage: scripts/generate.sh
# Exit: 0 generated, 2 xcodegen is not installed, otherwise xcodegen's exit status.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "generate: xcodegen not found; install it with: brew install xcodegen" >&2
    exit 2
fi
xcodegen generate --quiet --spec xcode/project.yml
