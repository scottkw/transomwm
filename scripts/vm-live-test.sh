#!/usr/bin/env bash
# Runs live AX integration suites inside the Tart test VM, never on this Mac: builds the test bundles here
# (nothing runs), copies them plus Xcode's test runtime into the VM, and runs them there with TRANSOM_LIVE=1.
# Usage: scripts/vm-live-test.sh <filter> [VAR=value ...]
#   e.g. scripts/vm-live-test.sh FixtureShapesTests        scripts/vm-live-test.sh ArrangeIntegrationTests TRANSOM_LIVE_DRAG=1
# Env: TRANSOM_VM (tart VM name, default pane-test), TRANSOM_VM_USER (default admin), TRANSOM_VM_KEY (default ~/.ssh/pane_vm_ed25519).
# The VM's SSH session needs the Accessibility grant (sshd-keygen-wrapper), as the UAT harness already has.
# Transom is quit in the VM for the run (its tiling would fight the fixtures) and relaunched after if it was running.
set -euo pipefail

filter="${1:?usage: scripts/vm-live-test.sh <filter> [VAR=value ...]}"
shift
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
# The VM name and SSH key defaults keep their pre-rename names: they are existing host resources, not repo artifacts.
vm="${TRANSOM_VM:-pane-test}"
key="${TRANSOM_VM_KEY:-$HOME/.ssh/pane_vm_ed25519}"
ip="$(tart ip "$vm")"
# `tart ip` can be empty after sleep: only ever ssh with a real address.
[ -n "$ip" ] || { echo "vm-live-test: tart ip gave no address for $vm" >&2; exit 1; }
host="${TRANSOM_VM_USER:-admin}@$ip"
ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# One VM user at a time, shared with the UAT re-check plans. TRANSOM_VM_LOCK_HELD: scripts/vm-session.sh holds it for this run.
mkdir -p .build
if [ -z "${TRANSOM_VM_LOCK_HELD:-}" ]; then
    mkdir .build/transom-vm.lock 2>/dev/null || { echo "vm-live-test: VM busy (.build/transom-vm.lock exists)" >&2; exit 1; }
    trap 'rmdir .build/transom-vm.lock' EXIT
fi

scratch=.build/vm
swift build --build-tests --scratch-path "$scratch"
stage="$scratch/stage"
rm -rf "$stage" && mkdir -p "$stage"
dev="$(xcode-select -p)"
plat="$dev/Platforms/MacOSX.platform/Developer"
cp -R "$scratch/debug/TransomMacIntegrationTests.xctest" "$scratch/debug/TransomFixtureApp" "$scratch"/debug/*.bundle "$stage/"
# TRANSOM_VM_APP: a built app bundle to stage beside the tests (scripts/vm-quit-check.sh).
if [ -n "${TRANSOM_VM_APP:-}" ]; then cp -R "$TRANSOM_VM_APP" "$stage/"; fi
cp -R "$plat"/Library/Frameworks/{XCTest,XCUIAutomation,Testing}.framework "$plat"/Library/Frameworks/_Testing_*.framework \
    "$plat"/Library/PrivateFrameworks/*.framework "$plat"/usr/lib/{libXCTestSwiftSupport,lib_TestingInterop}.dylib \
    "$dev/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper" "$stage/"
rsync -a --delete -e "ssh ${ssh_opts[*]}" "$stage/" "$host:transomtests/"

# shellcheck disable=SC2029  # filter and extra env expand here on purpose
# -t: a Ctrl-C or a dropped session reaches the guest, where the trap still clears the fixtures and relaunches Transom.
ssh -t "${ssh_opts[@]}" "$host" "
    cd ~/transomtests && xattr -cr .
    was_running=\$(pgrep -x Transom >/dev/null && echo 1 || true)
    cleanup() { pkill -x TransomFixtureApp || true; if [ -n \"\$was_running\" ]; then open -a /Applications/Transom.app; fi; }
    trap cleanup EXIT
    trap 'exit 130' HUP INT TERM
    if [ -n \"\$was_running\" ]; then
        osascript -e 'quit app \"Transom\"'
        for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Transom >/dev/null || break; sleep 0.5; done
        if pgrep -x Transom >/dev/null; then echo 'vm-live-test: Transom is still running in the VM' >&2; exit 1; fi
    fi
    # A sleeping guest display shifts NSScreen geometry by -768 pt (04-UAT, Pitfall 11): wake it, keep it awake.
    caffeinate -u -t 2
    rc=0
    env TRANSOM_LIVE=1 $* caffeinate -dimsu ./swiftpm-testing-helper --test-bundle-path \"\$PWD/TransomMacIntegrationTests.xctest/Contents/MacOS/TransomMacIntegrationTests\" \
        --testing-library swift-testing --filter '$filter' || rc=\$?
    exit \$rc
"
