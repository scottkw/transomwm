#!/usr/bin/env bash
# Runs live AX integration suites inside the Tart test VM, never on this Mac: builds the test bundles here
# (nothing runs), copies them plus Xcode's test runtime into the VM, and runs them there with PANE_LIVE=1.
# Usage: scripts/vm-live-test.sh <filter> [VAR=value ...]
#   e.g. scripts/vm-live-test.sh FixtureShapesTests        scripts/vm-live-test.sh ArrangeIntegrationTests PANE_LIVE_DRAG=1
# Env: PANE_VM (tart VM name, default pane-test), PANE_VM_USER (default admin), PANE_VM_KEY (default ~/.ssh/pane_vm_ed25519).
# The VM's SSH session needs the Accessibility grant (sshd-keygen-wrapper), as the UAT harness already has.
# Pane is quit in the VM for the run (its tiling would fight the fixtures) and relaunched after if it was running.
set -euo pipefail

filter="${1:?usage: scripts/vm-live-test.sh <filter> [VAR=value ...]}"
shift
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
vm="${PANE_VM:-pane-test}"
key="${PANE_VM_KEY:-$HOME/.ssh/pane_vm_ed25519}"
host="${PANE_VM_USER:-admin}@$(tart ip "$vm")"
ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# One VM user at a time, shared with the UAT re-check plans.
mkdir -p .build
mkdir .build/pane-vm.lock 2>/dev/null || { echo "vm-live-test: VM busy (.build/pane-vm.lock exists)" >&2; exit 1; }
trap 'rmdir .build/pane-vm.lock' EXIT

scratch=.build/vm
swift build --build-tests --scratch-path "$scratch"
stage="$scratch/stage"
rm -rf "$stage" && mkdir -p "$stage"
dev="$(xcode-select -p)"
plat="$dev/Platforms/MacOSX.platform/Developer"
cp -R "$scratch/debug/PaneMacIntegrationTests.xctest" "$scratch/debug/PaneFixtureApp" "$scratch"/debug/*.bundle "$stage/"
cp -R "$plat"/Library/Frameworks/{XCTest,XCUIAutomation,Testing}.framework "$plat"/Library/Frameworks/_Testing_*.framework \
    "$plat"/Library/PrivateFrameworks/*.framework "$plat"/usr/lib/{libXCTestSwiftSupport,lib_TestingInterop}.dylib \
    "$dev/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper" "$stage/"
rsync -a --delete -e "ssh ${ssh_opts[*]}" "$stage/" "$host:panetests/"

# shellcheck disable=SC2029  # filter and extra env expand here on purpose
# -t: a Ctrl-C or a dropped session reaches the guest, where the trap still clears the fixtures and relaunches Pane.
ssh -t "${ssh_opts[@]}" "$host" "
    cd ~/panetests && xattr -cr .
    was_running=\$(pgrep -x Pane >/dev/null && echo 1 || true)
    cleanup() { pkill -x PaneFixtureApp || true; if [ -n \"\$was_running\" ]; then open -a /Applications/Pane.app; fi; }
    trap cleanup EXIT
    trap 'exit 130' HUP INT TERM
    if [ -n \"\$was_running\" ]; then
        osascript -e 'quit app \"Pane\"'
        for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Pane >/dev/null || break; sleep 0.5; done
        if pgrep -x Pane >/dev/null; then echo 'vm-live-test: Pane is still running in the VM' >&2; exit 1; fi
    fi
    rc=0
    env PANE_LIVE=1 $* ./swiftpm-testing-helper --test-bundle-path \"\$PWD/PaneMacIntegrationTests.xctest/Contents/MacOS/PaneMacIntegrationTests\" \
        --testing-library swift-testing --filter '$filter' || rc=\$?
    exit \$rc
"
