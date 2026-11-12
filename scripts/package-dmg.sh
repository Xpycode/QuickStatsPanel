#!/usr/bin/env bash
# package-dmg.sh — build a notarized, stapled QuickStatsPanel DMG from a
# Release (developer-id-exported) QuickStatsPanel.app.
#
# Adapted from ClipSmart's scripts/package-dmg.sh (see docs 61), simplified:
#   • Sparkle nested signatures are verified after archive/export; never repaired here.
#     Generate the signed feed separately with make-appcast.sh after this succeeds.
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
# Output: 04_Exports/QuickStatsPanel-<VERSION>-<BUILD>.dmg (never overwritten).

set -euo pipefail

VERSION="${1:?usage: package-dmg.sh VERSION APP_PATH}"
APP="${2:?usage: package-dmg.sh VERSION APP_PATH}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Sign by the cert's SHA-1 hash to avoid Unicode matching on "MÜLLER".
SIGN_ID="${SIGN_ID:-D3002F5085B4512CAE0CC1A6DF30FAF717D83B62}"
OUT_DIR="${OUT_DIR:-$REPO/04_Exports}"
source "$REPO/scripts/release-validation.sh"
[[ -d "$APP" ]] || { release_die "App not found: $APP"; exit 1; }
PLIST="$APP/Contents/Info.plist"
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
[[ "$BUILT_VERSION" == "$VERSION" && "$BUNDLE_ID" == com.sim.QuickStatsPanel ]]   || { release_die "App identity/version does not match QuickStatsPanel $VERSION"; exit 1; }
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ && "$BUILD" =~ ^[0-9]+$ ]]   || { release_die "Expected numeric release version/build"; exit 1; }
DMG="$OUT_DIR/QuickStatsPanel-$VERSION-$BUILD.dmg"
APPZIP="$OUT_DIR/QuickStatsPanel-$VERSION-$BUILD-app.zip"
[[ ! -e "$DMG" && ! -L "$DMG" && ! -e "$APPZIP" && ! -L "$APPZIP" ]]   || { release_die "Output already exists; choose a new OUT_DIR"; exit 1; }
verify_release_app "$APP"
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
  if out="$(xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait 2>&1)"; then
    :
  else
    status=$?
    printf '%s\n' "$out" >&2
    return "$status"
  fi
  echo "$out"
  status="$(printf '%s\n' "$out" | grep -Eo 'status: [A-Za-z]+' | tail -1 | awk '{print $2}' || true)"
  if [ "$status" != "Accepted" ]; then
    echo "✗ Notarization result: ${status:-unknown} — fetching log…"
    subid="$(printf '%s\n' "$out" | grep -Eo '  id: [0-9a-f-]+' | head -1 | awk '{print $2}' || true)"
    [ -n "${subid:-}" ] && xcrun notarytool log "$subid" "${NOTARY_ARGS[@]}" || true
    return 1
  fi
}

echo "▸ [1/6] Exported app and all Sparkle components verified."

echo "▸ [2/6] Zipping + notarizing the app…"
ditto -c -k --keepParent "$APP" "$APPZIP"
notarize "$APPZIP"
rm -f "$APPZIP"

echo "▸ [3/6] Stapling the app…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "▸ [4/6] Building drag-to-Applications DMG…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/QuickStatsPanel.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -format UDZO "$DMG"
rm -rf "$STAGING"

echo "▸ [5/6] Signing, notarizing + stapling the DMG…"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "▸ [6/6] Verifying Gatekeeper acceptance…"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "✓ Done: $DMG"
ls -lh "$DMG"
