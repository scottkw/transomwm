#!/usr/bin/env bash
# Checks the bundled `transom` tool against the real app inside the Tart test VM, never on this Mac (08-07): builds a fresh
# "Transom Debug.app" here (nothing runs), copies it into the VM, installs its tool through a symlink as the README does,
# and runs every exit code from UI-SPEC Surface 5 over the real channel. Last line: "vm-cli-check: N checks passed", and
# only then is the exit 0: a failed or a skipped check exits 1.
# Usage: scripts/vm-cli-check.sh
# Env: TRANSOM_VM (tart VM name, default pane-test), TRANSOM_VM_USER (default admin), TRANSOM_VM_KEY (default ~/.ssh/pane_vm_ed25519).
# Transom is quit in the VM for the run and relaunched after if it was running. Nothing stays in the guest: the bundle
# copy, the symlink, the changed default and whatever the Debug app wrote to Application Support are all put back.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
vm="${TRANSOM_VM:-pane-test}"
key="${TRANSOM_VM_KEY:-$HOME/.ssh/pane_vm_ed25519}"
host="${TRANSOM_VM_USER:-admin}@$(tart ip "$vm")"
ssh_opts=(-i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# One VM user at a time, shared with vm-live-test.sh, vm-spike.sh and the UAT re-check plans.
mkdir -p .build
mkdir .build/transom-vm.lock 2>/dev/null || { echo "vm-cli-check: VM busy (.build/transom-vm.lock exists)" >&2; exit 1; }
trap 'rmdir .build/transom-vm.lock' EXIT

# An incremental build can keep an old signed copy of the tool in Contents/Helpers (08-05), so start from no bundle.
rm -rf "xcode/.xcode-build/Build/Products/Debug/Transom Debug.app"
app="$(scripts/build-debug.sh | tail -n 1)"
[ -x "$app/Contents/Helpers/transom" ] || { echo "vm-cli-check: no Contents/Helpers/transom in $app" >&2; exit 1; }

guest=.build/vm-cli-check-guest.sh
cat >"$guest" <<'GUEST'
set -u
app="$HOME/transomcli/Transom Debug.app"
cli="$HOME/transomcli/bin/transom"
support="$HOME/Library/Application Support/Transom"
domain=com.eightabyte.transom.debug
uid="$(id -u)" user="$(id -un)"
tmp="$(mktemp -d)"
was_running="" support_saved="" zoom_saved="" keep_tmp="" passed=0 failed=0 skipped=0

# Before the trap: that Transom Debug isn't this run's to quit, and nothing else has changed yet.
if pgrep -x "Transom Debug" >/dev/null; then
    echo "vm-cli-check: Transom Debug is already running in the VM" >&2
    rm -rf "$HOME/transomcli" "$tmp"
    exit 1
fi

gone_within_10s() {
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do pgrep -x "Transom Debug" >/dev/null || return 0; sleep 0.5; done
    return 1
}
stop_app() {
    pgrep -x "Transom Debug" >/dev/null || return 0
    osascript -e 'quit app "Transom Debug"' >/dev/null || true
    gone_within_10s
}
cleanup() {
    # Gone before the folder is restored: the app answers SIGTERM with a clean-exit write, which would overwrite it.
    if ! stop_app; then
        pkill -x "Transom Debug" || true
        gone_within_10s || { pkill -9 -x "Transom Debug" || true; sleep 0.5; }
    fi
    if [ -n "$support_saved" ]; then
        rm -rf "$support"
        if [ -d "$tmp/support" ] && ! ditto "$tmp/support" "$support"; then
            echo "vm-cli-check: could not restore $support; the backup stays at $tmp/support" >&2
            keep_tmp=1
        fi
    fi
    case "$zoom_saved" in
        "") ;;
        unset) defaults delete "$domain" zoomEnabled 2>/dev/null || true ;;
        1) defaults write "$domain" zoomEnabled -bool true ;;
        *) defaults write "$domain" zoomEnabled -bool false ;;
    esac
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true
    rm -rf "$HOME/transomcli"
    [ -n "$keep_tmp" ] || rm -rf "$tmp"
    if [ -n "$was_running" ]; then open -a /Applications/Transom.app; fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

pass() { passed=$((passed + 1)); echo "PASS $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1: $2"; }
finish() {
    if [ "$failed" -gt 0 ]; then echo "vm-cli-check: $failed checks failed, $skipped skipped, $passed passed"; exit 1; fi
    if [ "$skipped" -gt 0 ]; then echo "vm-cli-check: $skipped checks skipped, $passed passed"; exit 1; fi
    echo "vm-cli-check: $passed checks passed"
    exit 0
}
# The tool in the GUI session's bootstrap (RESEARCH Pitfall 10); leaves code, out and err. asuser needs root to join the
# session ("Could not switch to audit session" otherwise), and the inner sudo runs the tool as the user again.
run() {
    code=0
    sudo -n launchctl asuser "$uid" sudo -n -u "$user" "$cli" "$@" >"$tmp/out" 2>"$tmp/err" </dev/null || code=$?
    out="$(cat "$tmp/out")" err="$(cat "$tmp/err")"
}
# expect <name> <exit code> <exact stderr> <tool arguments...>
expect() {
    local name="$1" want="$2" message="$3"
    shift 3
    run "$@"
    if [ "$code" = "$want" ] && [ "$err" = "$message" ]; then pass "$name"; else fail "$name" "exit=$code stderr=$err"; fi
}
usage_shown() { case "$out" in "Usage: transom"*) pass "$1" ;; *) fail "$1" "stdout=$out" ;; esac; }

xattr -cr "$app"
if pgrep -x Transom >/dev/null; then
    was_running=1
    osascript -e 'quit app "Transom"' >/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Transom >/dev/null || break; sleep 0.5; done
    if pgrep -x Transom >/dev/null; then echo "vm-cli-check: Transom is still running in the VM" >&2; exit 1; fi
fi
# Debug and Release share this folder, so the installed app gets its own files back. Marked saved only after a good copy:
# cleanup deletes the folder. It starts empty, so slot 7 is known to be empty.
if [ -d "$support" ]; then
    ditto "$support" "$tmp/support" || { echo "vm-cli-check: could not back up $support; leaving it as it is" >&2; exit 1; }
fi
support_saved=1
rm -rf "$support"
caffeinate -u -t 2

mkdir -p "$(dirname "$cli")"
ln -sf "$app/Contents/Helpers/transom" "$cli"

# Before launch.
expect "help exits 0" 0 "" help
usage_shown "help prints usage"
expect "no arguments exits 0" 0 ""
usage_shown "no arguments prints usage"
expect "unknown command exits 64" 64 'transom: unknown command "foo". Run "transom help" to see every command.' foo
expect "bad slot exits 64" 64 'transom: view needs a slot from 1 to 9, as in "transom view 3".' view 0
expect "argument to zoom-out exits 64" 64 "transom: zoom-out takes no argument." zoom-out 3
expect "not running exits 2" 2 "transom: Transom is not running" view 4

# Against the running app. Reaching it at all proves the symlinked tool found its bundle's port (Assumption A3).
zoom_saved="$(defaults read "$domain" zoomEnabled 2>/dev/null || echo unset)"
defaults write "$domain" zoomEnabled -bool true
open "$app"
answered=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    run zoom-out
    if [ "$code" != 2 ]; then answered=1; break; fi
    sleep 0.5
done
if [ -z "$answered" ]; then fail "app answers within 10 s" "exit=$code stderr=$err"; finish; fi
pass "app answers within 10 s"
sleep 1.1

run step-in
expect "repeat within a second exits 1" 1 "transom: refused (rate limit). Each command runs at most once per second." step-in
sleep 1.1

run view 7
case "$code/$err" in
    "1/transom: refused: "*) pass "refusal exits 1"; echo "refused reason: ${err#transom: refused: }" ;;
    *) fail "refusal exits 1" "exit=$code stderr=$err" ;;
esac
if [ "$err" = "transom: refused: No view in slot 7" ]; then
    expect "save-view 4 exits 0" 0 "" save-view 4
    sleep 1.1
    expect "view 4 exits 0" 0 "" view 4
else
    skipped=$((skipped + 1))
    echo "SKIP save-view/view 4: $err"
fi
sleep 1.1

# Assumption A2, recorded and not judged: the same call with no launchctl asuser.
code=0
"$cli" zoom-out >"$tmp/out" 2>"$tmp/err" </dev/null || code=$?
echo "A2 plain-ssh exit=$code"
[ ! -s "$tmp/err" ] || echo "A2 plain-ssh stderr: $(cat "$tmp/err")"
sleep 1.1

if stop_app; then pass "app quits"; else fail "app quits" "Transom Debug is still running"; fi
expect "not running after quit exits 2" 2 "transom: Transom is not running" view 4
finish
GUEST

rsync -a --delete -e "ssh ${ssh_opts[*]}" "$app" "$guest" "$host:transomcli/"
# -t: a Ctrl-C or a dropped session reaches the guest, where the trap still puts everything back.
ssh -t "${ssh_opts[@]}" "$host" 'bash "$HOME/transomcli/vm-cli-check-guest.sh"'
