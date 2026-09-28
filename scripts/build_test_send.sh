#!/usr/bin/env bash
#
# Build the DouX tweak in CI, inject it into a decrypted TikTok IPA locally,
# and Taildrop the result to an iPhone. One command, fully unattended.
#
# Usage:
#   scripts/build_test_send.sh [ipa] [device] [scheme]
#
# Defaults:
#   ipa    = ~/Downloads/com.zhiliaoapp.musically-47.0.0-Decrypted.ipa
#   device = jacobs-iphone
#   scheme = rootless
#
set -euo pipefail

IPA="${1:-$HOME/Downloads/com.zhiliaoapp.musically-47.0.0-Decrypted.ipa}"
DEVICE="${2:-jacobs-iphone}"
SCHEME="${3:-rootless}"
REPO="${DOUX_REPO:-jmswangit/TokMods}"
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

cd "$(dirname "$0")/.."

if [[ ! -f "$IPA" ]]; then
  echo "!! IPA not found: $IPA" >&2
  exit 1
fi
if [[ ! -x "$TS" ]]; then
  echo "!! Tailscale CLI not found at $TS" >&2
  exit 1
fi

echo "==> Triggering CI build ($SCHEME)"
gh workflow run build-deb.yml --repo "$REPO" -f scheme="$SCHEME"
sleep 8
RUN_ID="$(gh run list --repo "$REPO" --workflow build-deb.yml --limit 1 --json databaseId -q '.[0].databaseId')"
echo "    run id: $RUN_ID"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status

echo "==> Downloading deb artifact"
rm -rf /tmp/doux-build && mkdir -p /tmp/doux-build
gh run download "$RUN_ID" --repo "$REPO" -n "doux-deb-$SCHEME" -D /tmp/doux-build
DEB="$(ls /tmp/doux-build/*.deb | head -1)"
echo "    deb: $DEB"

echo "==> Injecting tweak into IPA"
rm -f output/injected.ipa output/patched-final.ipa output/tweak.deb
python3 scripts/ipa_packager.py --ipa "$IPA" --tweak_url "$DEB"

echo "==> Taildropping to $DEVICE"
"$TS" file cp output/patched-final.ipa "$DEVICE:"

echo "==> Done"
ls -lh output/patched-final.ipa
