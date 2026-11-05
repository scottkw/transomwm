#!/usr/bin/env bash
# Starts a stopped Tart VM headless, waits for its GUI session, runs one host command with TRANSOM_VM exported, and stops
# the VM again. It never touches this Mac's own processes: every pkill runs in the guest over ssh.
# Usage: TRANSOM_VM=pane-test-27 scripts/vm-session.sh scripts/vm-live-test.sh HoldOptionIntegrationTests TRANSOM_LIVE_DRAG=1
# Env: TRANSOM_VM (required), TRANSOM_VM_USER (default admin), TRANSOM_VM_KEY (default ~/.ssh/pane_vm_ed25519).
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: TRANSOM_VM=<vm> scripts/vm-session.sh <command> [args...]" >&2; exit 2; }
vm="${TRANSOM_VM:?set TRANSOM_VM to a tart VM name}"
user="${TRANSOM_VM_USER:-admin}"
key="${TRANSOM_VM_KEY:-$HOME/.ssh/pane_vm_ed25519}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

mkdir -p .build
if [ -e .build/transom-vm.lock ]; then echo "vm-session: VM busy (.build/transom-vm.lock exists)" >&2; exit 1; fi

tart stop "$vm" >/dev/null 2>&1 || true
tart run --no-graphics "$vm" >".build/tart-$vm.log" 2>&1 &
trap 'tart stop "$vm" >/dev/null 2>&1 || true' EXIT
trap 'exit 130' HUP INT TERM

# `tart ip` can be empty after sleep: only ever ssh with a real address.
guest() {
    local ip
    ip="$(tart ip "$vm" 2>/dev/null || true)"
    [ -n "$ip" ] || return 1
    ssh "${ssh_opts[@]}" "$user@${ip}" "$@"
}

ready=""
for _ in $(seq 1 60); do
    if guest 'who | grep -q console && pgrep -x Finder >/dev/null' 2>/dev/null; then ready=1; break; fi
    sleep 5
done
[ -n "$ready" ] || { echo "vm-session: $vm had no GUI session after 5 minutes" >&2; exit 1; }

# A leftover Transom Debug would fight the fixtures.
guest "pkill -x 'Transom Debug' || true; for i in 1 2 3 4 5; do pgrep -x 'Transom Debug' >/dev/null || exit 0; sleep 1; done; pkill -9 -x 'Transom Debug' || true"

export TRANSOM_VM
rc=0
"$@" || rc=$?
# `tart stop` loses what the guest has not written out: a suite's restored defaults and folders came back undone.
guest sync || true
exit "$rc"
