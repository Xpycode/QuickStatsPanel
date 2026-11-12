#!/usr/bin/env bash
# Disposable shell fixtures: no real codesign, Gatekeeper, keys, apps or mounts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/release-validation.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/QuickStatsPanel.app"
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/Current"
mkdir -p "$FW/XPCServices/Downloader.xpc" "$FW/XPCServices/Installer.xpc" "$FW/Updater.app"
touch "$FW/Autoupdate"
MODE=valid
codesign() {
  if [[ "$1" == --verify ]]; then
    [[ "$MODE" != invalid_signature ]]
  elif [[ "$2" == --entitlements ]]; then
    [[ "$MODE" != debug ]] || printf '<key>com.apple.security.get-task-allow</key><true/>\n'
    return 0
  else
    [[ "$MODE" == adhoc ]] || printf 'Authority=Developer ID Application: Fixture\n'
    [[ "$MODE" == no_runtime ]] || printf 'flags=0x10000(runtime)\n'
    [[ "$MODE" == no_timestamp ]] || printf 'Timestamp=Fixture timestamp\n'
    [[ "$MODE" == wrong_team ]] || printf 'TeamIdentifier=FDMSRXXN73\n'
    return 0
  fi
}
verify_release_app "$APP"
for MODE in invalid_signature adhoc no_runtime no_timestamp wrong_team debug; do
  if verify_release_app "$APP" >/dev/null 2>&1; then
    printf 'FAIL: accepted %s\n' "$MODE" >&2
    exit 1
  fi
done
MODE=valid
rm "$FW/Autoupdate"
if verify_release_app "$APP" >/dev/null 2>&1; then
  printf 'FAIL: accepted missing Sparkle helper\n' >&2
  exit 1
fi
printf 'Passed signature fixtures: valid bundle plus seven rejection cases.\n'
