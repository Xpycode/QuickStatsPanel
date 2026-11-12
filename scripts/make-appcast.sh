#!/usr/bin/env bash
# Prepare a signed Sparkle feed, never publish or notarize anything.
# Usage: make-appcast.sh APP_PATH DMG_PATH SPARKLE_BIN OUTPUT_DIRECTORY
# Requires an already notarized/stapled, developer-id-exported app and DMG.
# Uses only the dedicated quickstatspanel Keychain account; never exports keys.
# OUTPUT_DIRECTORY must not exist. Upload downloads/<DMG name> before appcast.xml.
# Optional RELEASE_NOTES points to a UTF-8 text or HTML fragment embedded in the signed feed.
set -euo pipefail
APP="${1:?usage: make-appcast.sh APP_PATH DMG_PATH SPARKLE_BIN OUTPUT_DIRECTORY}"
DMG="${2:?DMG_PATH required}"
SPARKLE_BIN="${3:?SPARKLE_BIN required}"
OUT="${4:?OUTPUT_DIRECTORY required}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/scripts/release-validation.sh"
ACCOUNT=quickstatspanel
FEED_URL=https://apps.lucesumbrarum.com/quickstatspanel/appcast.xml
[[ ! -e "$OUT" && ! -L "$OUT" ]] || { release_die "Output directory already exists: $OUT"; exit 1; }
[[ -f "$DMG" && ! -L "$DMG" ]] || { release_die "DMG missing or symlink: $DMG"; exit 1; }
[[ -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_keys" ]] \
  || { release_die "Pass the resolved Sparkle bin directory"; exit 1; }
verify_release_app "$APP"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
PLIST="$APP/Contents/Info.plist"
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")
[[ "$PUBLIC_KEY" == "$("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p)" ]] \
  || { release_die "Dedicated Keychain public key differs from the app"; exit 1; }

# The supplied app must actually be the one users receive inside the DMG.
WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
mkdir "$MOUNT"
ATTACHED=false
cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$ATTACHED" == true ]]; then
    if ! hdiutil detach "$MOUNT"; then
      printf 'error: could not detach %s; retained verification workspace %s\n' "$MOUNT" "$WORK" >&2
      exit 1
    fi
  fi
  rm -rf "$WORK"
  exit "$result"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" > "$WORK/attach.log"
ATTACHED=true
ENCLOSED="$MOUNT/QuickStatsPanel.app"
verify_release_app "$ENCLOSED"
python3 "$REPO/scripts/verify-appcast-input.py" "$APP" "$ENCLOSED" "$DMG" "$FEED_URL"
hdiutil detach "$MOUNT"
ATTACHED=false

# Create an immutable candidate directory only after all input gates pass.
mkdir "$OUT"
mkdir "$OUT/downloads"
STAGED_DMG="$OUT/downloads/$(basename "$DMG")"
ditto "$DMG" "$STAGED_DMG"
cmp "$DMG" "$STAGED_DMG"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$ACCOUNT" -p "$STAGED_DMG")"
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$STAGED_DMG" "$SIGNATURE"
python3 - "$PLIST" "$STAGED_DMG" "$SIGNATURE" "$OUT/appcast.xml" "$FEED_URL" "${RELEASE_NOTES:-}" <<'PY'
import base64, email.utils, pathlib, plistlib, sys, urllib.parse, xml.etree.ElementTree as ET
plist_path, dmg_path, signature, output, feed, notes = sys.argv[1:]
p = plistlib.loads(pathlib.Path(plist_path).read_bytes())
if len(base64.b64decode(signature, validate=True)) != 64:
    raise SystemExit('Invalid Ed25519 signature length')
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'QuickStatsPanel Updates'
ET.SubElement(channel, 'link').text = feed
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'QuickStatsPanel ' + p['CFBundleShortVersionString']
ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
minimum = str(p['LSMinimumSystemVersion'])
minimum += '.0' * (2 - minimum.count('.'))
for name, value in [('version', p['CFBundleVersion']), ('shortVersionString', p['CFBundleShortVersionString']), ('minimumSystemVersion', minimum)]:
    ET.SubElement(item, '{'+ns+'}'+name).text = str(value)
if notes:
    ET.SubElement(item, 'description').text = pathlib.Path(notes).read_text(encoding='utf-8')
dmg = pathlib.Path(dmg_path)
ET.SubElement(item, 'enclosure', {
    'url': urllib.parse.urljoin(feed, 'downloads/' + urllib.parse.quote(dmg.name)),
    '{'+ns+'}edSignature': signature,
    'length': str(dmg.stat().st_size), 'type': 'application/octet-stream'
})
ET.indent(rss)
with open(output, 'xb') as f:
    ET.ElementTree(rss).write(f, encoding='utf-8', xml_declaration=True)
PY
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" "$OUT/appcast.xml"
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$OUT/appcast.xml"
printf 'Prepared signed feed and immutable enclosure (not published): %s\n' "$OUT"
