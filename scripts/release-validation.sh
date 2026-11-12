#!/usr/bin/env bash
# Shared, read-only verification for exported release bundles. Source this file.
# Never repair signatures here: archive/export must produce the correct nested code.
release_die() { printf 'error: %s\n' "$*" >&2; return 1; }

verify_release_code() {
  local code="$1" info entitlements
  [[ -e "$code" ]] || { release_die "Missing signed component: $code"; return 1; }
  codesign --verify --strict --verbose=2 "$code" || return
  info="$(codesign -dvvv "$code" 2>&1)" || return
  [[ "$info" == *"Authority=Developer ID Application:"* ]] || { release_die "Not Developer ID signed: $code"; return 1; }
  [[ "$info" =~ flags=.*runtime ]] || { release_die "Hardened runtime missing: $code"; return 1; }
  [[ "$info" == *"Timestamp="* ]] || { release_die "Secure timestamp missing: $code"; return 1; }
  [[ "$info" == *"TeamIdentifier=FDMSRXXN73"* ]] || { release_die "Unexpected signing team: $code"; return 1; }
  entitlements="$(codesign -d --entitlements :- "$code" 2>/dev/null)" || return
  [[ "$entitlements" != *"get-task-allow"* ]] || { release_die "Debug entitlement present: $code"; return 1; }
}

verify_release_app() {
  local app="$1" component framework
  [[ -d "$app" && ! -L "$app" ]] || { release_die "Expected an app directory: $app"; return 1; }
  codesign --verify --deep --strict --verbose=2 "$app" || return
  verify_release_code "$app" || return
  framework="$app/Contents/Frameworks/Sparkle.framework"
  verify_release_code "$framework" || return
  for component in XPCServices/Downloader.xpc XPCServices/Installer.xpc Autoupdate Updater.app; do
    verify_release_code "$framework/Versions/Current/$component" || return
  done
}
