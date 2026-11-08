#!/usr/bin/env bash
# Sets the five release secrets (gifsmith's names) on a repo's `release` environment in one go. Run it yourself in
# Terminal: it prompts for the .p12 password, Key ID and Issuer ID and never prints a secret.
# Usage: scripts/set-release-secrets.sh <DeveloperID.p12> <AuthKey_XXXX.p8> [owner/repo]   (default scottkw/transomwm)
# Export the .p12 from Keychain Access (right-click "Developer ID Application: …" ▸ Export, choose a password).
set -euo pipefail

p12="${1:?usage: set-release-secrets.sh <cert.p12> <AuthKey.p8> [owner/repo]}"
p8="${2:?usage: set-release-secrets.sh <cert.p12> <AuthKey.p8> [owner/repo]}"
repo="${3:-scottkw/transomwm}"
[ -f "$p12" ] || { echo "no file: $p12" >&2; exit 1; }
[ -f "$p8" ] || { echo "no file: $p8" >&2; exit 1; }

read -rsp ".p12 password: " pass; echo
# A wrong password fails here, before anything reaches GitHub.
openssl pkcs12 -in "$p12" -passin "pass:$pass" -nokeys -legacy >/dev/null 2>&1 \
    || openssl pkcs12 -in "$p12" -passin "pass:$pass" -nokeys >/dev/null 2>&1 \
    || { echo "that password does not open $p12" >&2; exit 1; }

default_id="$(basename "$p8" .p8)"; default_id="${default_id#AuthKey_}"
read -rp "App Store Connect Key ID [$default_id]: " key_id; key_id="${key_id:-$default_id}"
read -rp "App Store Connect Issuer ID: " issuer
[ -n "$issuer" ] || { echo "Issuer ID is required" >&2; exit 1; }

set_secret() { printf '%s' "$2" | gh secret set "$1" --env release --repo "$repo"; echo "set $1"; }
set_secret MACOS_CERT_P12_BASE64 "$(base64 -i "$p12")"
set_secret MACOS_CERT_PASSWORD "$pass"
set_secret NOTARY_KEY_ID "$key_id"
set_secret NOTARY_ISSUER_ID "$issuer"
set_secret NOTARY_KEY_P8_BASE64 "$(base64 -i "$p8")"
gh secret list --env release --repo "$repo"
