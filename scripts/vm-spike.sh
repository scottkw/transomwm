#!/usr/bin/env bash
# Runs one transom-zoom-spike subcommand inside the Tart test VM, never on this Mac (04-01, CONTEXT E): builds the
# harness and TransomFixtureApp here (nothing runs), copies them into the VM, runs the subcommand there and copies its
# JSON lines (and any recordings or stills) back to .build/spike/<subcommand>-<timestamp>/, whose path is the last line.
# Usage: scripts/vm-spike.sh <subcommand> [args...]      e.g. scripts/vm-spike.sh settle --runs 2 --fixtures 4
# Env: TRANSOM_VM (default pane-test), TRANSOM_VM_USER (default admin), TRANSOM_VM_KEY (default ~/.ssh/pane_vm_ed25519),
#      SPIKE_ENV (extra VAR=value words for the guest run, e.g. "TRANSOM_STAGE_CAPTURABLE=1").
# Transom is quit in the VM for the run (its tiling would fight the harness) and relaunched after if it was running.
set -euo pipefail

subcommand="${1:?usage: scripts/vm-spike.sh <subcommand> [args...]}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
vm="${TRANSOM_VM:-pane-test}"
key="${TRANSOM_VM_KEY:-$HOME/.ssh/pane_vm_ed25519}"
host="${TRANSOM_VM_USER:-admin}@$(tart ip "$vm")"
ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# One VM user at a time, shared with vm-live-test.sh and the UAT re-check plans.
mkdir -p .build
mkdir .build/transom-vm.lock 2>/dev/null || { echo "vm-spike: VM busy (.build/transom-vm.lock exists)" >&2; exit 1; }
trap 'rmdir .build/transom-vm.lock' EXIT

scratch=.build/vm
swift build --scratch-path "$scratch" --product transom-zoom-spike >&2
swift build --scratch-path "$scratch" --product TransomFixtureApp >&2
stage="$scratch/spike-stage"
rm -rf "$stage" && mkdir -p "$stage"
cp -R "$scratch/debug/transom-zoom-spike" "$scratch/debug/TransomFixtureApp" "$scratch"/debug/*.bundle "$stage/"
rsync -a --delete --exclude out -e "ssh ${ssh_opts[*]}" "$stage/" "$host:transomspike/" >&2

args="$(printf '%q ' "$@")"
rc=0
# -t: a Ctrl-C or a dropped session reaches the guest, where the trap still clears the fixtures and relaunches Transom.
# caffeinate on both sides: the host must not sleep mid-run, and the guest display must stay on for captures.
# shellcheck disable=SC2029  # args and SPIKE_ENV expand here on purpose
caffeinate -d -i ssh -t "${ssh_opts[@]}" "$host" "
    cd ~/transomspike && xattr -cr . && rm -rf out && mkdir out
    was_running=\$(pgrep -x Transom >/dev/null && echo 1 || true)
    cleanup() { pkill -x TransomFixtureApp || true; pkill -x less || true; if [ -n \"\$was_running\" ]; then open -a /Applications/Transom.app; fi; }
    trap cleanup EXIT
    trap 'exit 130' HUP INT TERM
    if [ -n \"\$was_running\" ]; then
        osascript -e 'quit app \"Transom\"'
        for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Transom >/dev/null || break; sleep 0.5; done
        if pgrep -x Transom >/dev/null; then echo 'vm-spike: Transom is still running in the VM' >&2; exit 1; fi
    fi
    rc=0
    env ${SPIKE_ENV:-} caffeinate -dimsu ./transom-zoom-spike $args --out ~/transomspike/out/out.jsonl || rc=\$?
    exit \$rc
" >&2 || rc=$?

dest=".build/spike/${subcommand}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dest"
# Recordings and stills leave the guest once copied (T-04-05); .build/ is git-ignored.
rsync -a -e "ssh ${ssh_opts[*]}" --exclude work "$host:transomspike/out/" "$dest/" >&2 || true
ssh "${ssh_opts[@]}" "$host" "rm -rf ~/transomspike/out" || true
[ "$rc" -eq 0 ] || { echo "vm-spike: guest run exited $rc (partial results in $dest)" >&2; echo "$dest"; exit "$rc"; }
echo "$dest"
