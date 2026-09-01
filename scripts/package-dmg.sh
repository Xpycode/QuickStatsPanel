#!/usr/bin/env bash
# package-dmg.sh — build a notarized, stapled QuickStatsPanel DMG from a
# Release (developer-id-exported) QuickStatsPanel.app.
#
# Adapted from ClipSmart's scripts/package-dmg.sh (see docs 61), simplified:
#   • No Sparkle → no inside-out nested re-signing, no appcast step.
#   • The app is expected to come from `xcodebuild -exportArchive` using the
#     tracked `scripts/exportOptions.plist`. Its `stripSwiftSymbols=false`
#     avoids an Xcode 17 export bug that can mutate the executable after signing.
#     That export uses the developer-id method, which already signs with Developer ID + hardened
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
  # API-key auth. The .p8 private key, its Key ID, and the Issuer UUID live ONLY in
  # 99-AUTH/ (outside this repo, never committed). Nothing secret is hardcoded here:
  #   • KEY_FILE : $NOTARY_KEY, else the sole AuthKey_*.p8 in 99-AUTH/
  #   • KEY_ID   : derived from the AuthKey_<KEYID>.p8 filename
  #   • ISSUER   : $NOTARY_ISSUER, else the one-line file 99-AUTH/notary-issuer
  KEY_FILE="${NOTARY_KEY:-$(ls "$AUTH_DIR"/AuthKey_*.p8 2>/dev/null | head -1)}"
  [ -f "${KEY_FILE:-}" ] || { echo "✗ No notary API key (.p8) in $AUTH_DIR — see docs/61"; exit 1; }
  KEY_ID="$(basename "$KEY_FILE" .p8 | sed 's/^AuthKey_//')"
  ISSUER="${NOTARY_ISSUER:-$(cat "$AUTH_DIR/notary-issuer" 2>/dev/null || true)}"
  [ -n "${ISSUER:-}" ] || { echo "✗ No issuer — set NOTARY_ISSUER or create $AUTH_DIR/notary-issuer"; exit 1; }
  NOTARY_ARGS=(--key "$KEY_FILE" --key-id "$KEY_ID" --issuer "$ISSUER")
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
