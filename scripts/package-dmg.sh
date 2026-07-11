#!/usr/bin/env bash
# package-dmg.sh — build a notarized, stapled QuickStatsPanel DMG from a
# Release (developer-id-exported) QuickStatsPanel.app.
#
# Adapted from ClipSmart's scripts/package-dmg.sh (see docs 61), simplified:
#   • No Sparkle → no inside-out nested re-signing, no appcast step.
#   • The app is expected to come from `xcodebuild -exportArchive` with the
#     developer-id method, which already signs with Developer ID + hardened
#     runtime + secure timestamp and WITHOUT get-task-allow. This script
#     VERIFIES that instead of re-signing — if verification fails, re-export
#     rather than patching signatures here.
#   • Notary auth: per-invocation API-key flags by default (the key lives in
#     Syncthing-synced 99-AUTH/, so this works on every Mac without a keychain
#     profile). Set NOTARY_PROFILE to use a stored profile instead.
#
# CHAIN: verify app signature → notarize+staple app → build DMG → sign DMG →
#        notarize+staple DMG → spctl verify.
#
# Usage:  ./scripts/package-dmg.sh VERSION APP_PATH
#   VERSION   marketing version for the DMG name/volume (e.g. 1.0.0)
#   APP_PATH  the developer-id-exported QuickStatsPanel.app
# Env overrides: SIGN_ID (cert SHA-1), NOTARY_PROFILE, OUT_DIR.
#
# Output: 04_Exports/QuickStatsPanel-<VERSION>.dmg

set -euo pipefail

VERSION="${1:?usage: package-dmg.sh VERSION APP_PATH}"
APP="${2:?usage: package-dmg.sh VERSION APP_PATH}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Sign by the cert's SHA-1 hash to avoid Unicode matching on "MÜLLER".
SIGN_ID="${SIGN_ID:-D3002F5085B4512CAE0CC1A6DF30FAF717D83B62}"
OUT_DIR="${OUT_DIR:-$REPO/04_Exports}"
DMG="$OUT_DIR/QuickStatsPanel-$VERSION.dmg"
VOLNAME="QuickStatsPanel $VERSION"

AUTH_DIR="$HOME/ProgrammingProjects/99-AUTH"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
else
  NOTARY_ARGS=(--key "$AUTH_DIR/AuthKey_6HTCUZ9L7L.p8"
               --key-id 6HTCUZ9L7L
               --issuer 935e3a4d-b8fc-4110-a24f-89d7da84b6ab)
fi

echo "▸ App:     $APP"
echo "▸ Version: $VERSION"
echo "▸ Output:  $DMG"
[ -d "$APP" ] || { echo "✗ App not found: $APP"; exit 1; }
mkdir -p "$OUT_DIR"

# notarize <artifact> — submit, wait, and FAIL loudly (with the log) if not Accepted.
notarize() {
  local artifact="$1" out status subid
  out="$(xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait 2>&1)"
  echo "$out"
  status="$(printf '%s\n' "$out" | grep -Eo 'status: [A-Za-z]+' | tail -1 | awk '{print $2}')"
  if [ "$status" != "Accepted" ]; then
    echo "✗ Notarization result: ${status:-unknown} — fetching log…"
    subid="$(printf '%s\n' "$out" | grep -Eo '  id: [0-9a-f-]+' | head -1 | awk '{print $2}')"
    [ -n "${subid:-}" ] && xcrun notarytool log "$subid" "${NOTARY_ARGS[@]}" || true
    return 1
  fi
}

echo "▸ [1/6] Verifying the app signature is notarization-clean…"
codesign --verify --strict --verbose=2 "$APP"
info="$(codesign -dvvv "$APP" 2>&1)"
printf '%s' "$info" | grep -q "Authority=Developer ID Application" \
  || { echo "✗ not Developer ID signed — export with method developer-id"; exit 1; }
printf '%s' "$info" | grep -q "flags=.*runtime" \
  || { echo "✗ hardened runtime missing"; exit 1; }
printf '%s' "$info" | grep -q "Timestamp=" \
  || { echo "✗ no secure timestamp"; exit 1; }
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q get-task-allow; then
  echo "✗ get-task-allow present — this is a dev build, not a developer-id export"; exit 1
fi
echo "  ✓ Developer ID + hardened runtime + timestamp, no get-task-allow"

echo "▸ [2/6] Zipping + notarizing the app…"
APPZIP="$OUT_DIR/QuickStatsPanel-$VERSION-app.zip"
ditto -c -k --keepParent "$APP" "$APPZIP"
notarize "$APPZIP"
rm -f "$APPZIP"

echo "▸ [3/6] Stapling the app…"
xcrun stapler staple "$APP"

echo "▸ [4/6] Building drag-to-Applications DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "▸ [5/6] Signing, notarizing + stapling the DMG…"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "▸ [6/6] Verifying Gatekeeper acceptance…"
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | head -5 || true

echo "✓ Done: $DMG"
ls -lh "$DMG"
