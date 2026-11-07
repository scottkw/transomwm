#!/usr/bin/env bash
# Release pipeline for Transom, run locally and by the GitHub Actions release job (D-11): builds the
# universal Developer ID Release app through build-debug.sh --release, refuses to continue on any signing
# problem (RESEARCH Pitfall 1), then notarises and staples the app, builds
# build/Transom-<version>-universal.dmg, signs, notarises and staples it, writes its sha256 to
# build/Transom-<version>-universal.dmg.sha256 and prints that last. Nothing is uploaded.
# The version comes from MARKETING_VERSION in xcode/project.yml. The app's designated requirement must
# equal xcode/designated-requirement.txt exactly: a different one would cost every user the Accessibility
# grant on update, so change that file only on purpose. Notarisation uses the keychain profile named by
# TRANSOM_NOTARY_PROFILE (default pane-notary, stored once with `xcrun notarytool store-credentials`).
# Usage: scripts/release.sh [--build-only | --skip-notarize]
#   --build-only     build and verify the app, print its path, stop
#   --skip-notarize  everything except notarising and stapling (no credentials needed)
# Exit: 0 success, 1 a check failed, 2 bad usage.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

build_only=0 notarize=1
case "${1:-}" in
    "") ;;
    --build-only) build_only=1 ;;
    --skip-notarize) notarize=0 ;;
    *) echo "release: unknown argument: $1 (usage: scripts/release.sh [--build-only | --skip-notarize])" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "release: too many arguments" >&2; exit 2; }

fail() { echo "release: $1" >&2; exit 1; }

version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' xcode/project.yml)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "xcode/project.yml: MARKETING_VERSION '$version' is not MAJOR.MINOR.PATCH"
team=S2K7P43927
signer="Developer ID Application: Ken Scott ($team)"
# The local notary keychain profile was stored before the rename and keeps that name; CI sets its own.
profile="${TRANSOM_NOTARY_PROFILE:-pane-notary}"
# The name the updater and the cask download; the .sha256 beside it is written after stapling.
dmg="build/Transom-$version-universal.dmg"
staging=build/dmg-staging

# 1. Build and verify. build-debug.sh already checks the designated requirement (identifier + team).
# An incremental build can keep an old signed copy of the tool in Contents/Helpers (08-05), so start from no bundle.
rm -rf "xcode/.xcode-build/Build/Products/Release/Transom.app"
app="$(scripts/build-debug.sh --release | tail -n 1)"
[ -d "$app" ] || fail "no app at $app"

# Captured first: grep -q closing the pipe early would trip pipefail.
details="$(codesign -dvv "$app" 2>&1)"
grep -q '^Timestamp=' <<<"$details" || fail "no secure timestamp on $app"
codesign --verify --strict --deep --verbose=2 "$app" >&2 || fail "codesign --verify --strict --deep failed"
requirement="$(codesign -d -r- "$app" 2>&1 | sed -n 's/^designated => //p')"
expected="$(cat xcode/designated-requirement.txt)"
[ "$requirement" = "$expected" ] || fail "designated requirement changed (users would lose the Accessibility grant):
  built:     $requirement
  committed: $expected"
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
[ "$scheme" = transom ] || fail "URL scheme is $scheme, want transom"

# The bundled command-line tool (D-09): notarisation checks every executable, and so does this.
helper="$app/Contents/Helpers/transom"
[ -x "$helper" ] || fail "no executable tool at $helper"
details="$(codesign -dv --verbose=4 "$helper" 2>&1)"
grep -q '^Timestamp=' <<<"$details" || fail "no secure timestamp on $helper"
grep -q 'flags=.*runtime' <<<"$details" || fail "no hardened runtime on $helper"
grep -q "^TeamIdentifier=$team\$" <<<"$details" || fail "$helper is not signed by team $team"
entitlements="$(codesign -d --entitlements - "$helper" 2>/dev/null)"
for forbidden in get-task-allow application-identifier; do
    case "$entitlements" in *"$forbidden"*) fail "forbidden entitlement on $helper: $forbidden" ;; esac
done
archs="$(lipo -archs "$helper")"
case " $archs " in *" x86_64 "*) ;; *) fail "$helper lacks x86_64 (has: $archs)" ;; esac
case " $archs " in *" arm64 "*) ;; *) fail "$helper lacks arm64 (has: $archs)" ;; esac

if [ "$build_only" = 1 ]; then
    echo "$app"
    exit 0
fi

# Submits $1 and waits; notarytool's exit code alone does not separate Accepted from Invalid.
notarize() {
    local out id
    out="$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait 2>&1)" || true
    echo "$out" >&2
    grep -q 'status: Accepted' <<<"$out" && return 0
    id="$(awk '$1 == "id:" { print $2; exit }' <<<"$out")"
    fail "notarisation of $1 not accepted (submission ${id:-unknown}); see: xcrun notarytool log ${id:-<id>} --keychain-profile $profile"
}

# Runs `xcrun stapler staple|validate $2` up to 5 times, 20 s apart: on GitHub's macOS runners the
# ticket lookup sometimes drops (NSURLError -1005, stapler error 68).
staple_retry() {
    local attempt
    for attempt in 1 2 3 4 5; do
        xcrun stapler "$1" "$2" >&2 && return 0
        if [ "$attempt" -lt 5 ]; then
            echo "stapler $1 failed (attempt $attempt of 5), retrying in 20 s" >&2
            sleep 20
        fi
    done
    fail "stapler $1 $2 failed after 5 attempts"
}

mkdir -p build

# 2. Notarise and staple the app, so a copy dragged out of the DMG passes Gatekeeper offline.
if [ "$notarize" = 1 ]; then
    rm -f build/Transom.zip
    ditto -c -k --keepParent "$app" build/Transom.zip
    notarize build/Transom.zip
    staple_retry staple "$app"
fi

# 3. DMG, signed (and notarised and stapled unless skipping).
rm -rf "$staging" "$dmg" "$dmg.sha256"
mkdir -p "$staging"
ditto "$app" "$staging/Transom.app"
if command -v create-dmg >/dev/null 2>&1; then
    # --app-drop-link adds the /Applications link itself; --skip-jenkins avoids a Finder AppleScript
    # and its Automation prompt. --notarize submits, waits and staples. Layout: UI-SPEC Surface 8.
    # shortcut: --skip-jenkins also skips the AppleScript that applies the window size, icon positions and
    # hidden extension, so those flags are inert; drop --skip-jenkins on a Mac that grants Finder automation.
    extra=()
    [ "$notarize" = 1 ] && extra=(--notarize "$profile")
    create-dmg --volname "Transom $version" --window-size 540 380 --icon-size 128 \
        --icon "Transom.app" 140 180 --hide-extension "Transom.app" --app-drop-link 400 180 --skip-jenkins \
        --codesign "$signer" ${extra[@]+"${extra[@]}"} "$dmg" "$staging/" >&2 || fail "create-dmg failed"
else
    echo "release: create-dmg not found, falling back to hdiutil" >&2
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname "Transom $version" -srcfolder "$staging" -format UDZO "$dmg" >&2 \
        || fail "hdiutil could not build $dmg"
    codesign --timestamp --sign "$signer" "$dmg" >&2 || fail "codesign of $dmg failed"
    if [ "$notarize" = 1 ]; then
        notarize "$dmg"
        staple_retry staple "$dmg"
    fi
fi

# 4. Verify.
[ -f "$dmg" ] || fail "no DMG at $dmg"
hdiutil verify "$dmg" >&2 || fail "hdiutil verify failed for $dmg"
codesign --verify --strict --verbose=2 "$dmg" >&2 || fail "DMG signature invalid"
if [ "$notarize" = 1 ]; then
    assessment="$(spctl -a -vvv -t exec "$app" 2>&1)" || true
    echo "$assessment" >&2
    grep -q 'source=Notarized Developer ID' <<<"$assessment" || fail "spctl does not report Notarized Developer ID"
    staple_retry validate "$dmg"
fi
# Relative name inside build/, so `shasum -c` works there and in the release job.
(cd build && shasum -a 256 "Transom-$version-universal.dmg") > "$dmg.sha256"
cat "$dmg.sha256"
