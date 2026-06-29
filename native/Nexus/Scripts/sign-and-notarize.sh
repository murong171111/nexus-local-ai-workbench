#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS="$PACKAGE_ROOT/Packaging/Nexus.entitlements"
APP_PATH=""
DMG_PATH=""
IDENTITY=""
TEAM_ID=""
APPLE_ID=""
PASSWORD=""
DRY_RUN=false
SKIP_NOTARIZATION=false

usage() {
  cat <<'USAGE'
Usage: sign-and-notarize.sh [--app path/to/Nexus.app] [--dmg path/to/Nexus.dmg] --identity "Developer ID Application: ..." [options]

Signs a Nexus.app bundle and/or DMG with Developer ID, then notarizes and staples the DMG when notarization credentials are supplied.

Options:
  --app path                 App bundle to sign.
  --dmg path                 DMG to sign, notarize, and staple.
  --identity name            Developer ID signing identity.
  --team-id id               Apple Developer Team ID for notarytool.
  --apple-id email           Apple ID for notarytool.
  --password value           App-specific password or keychain profile password for notarytool.
  --skip-notarization        Sign only; do not submit/staple the DMG.
  --dry-run                  Validate inputs and print commands without signing or notarizing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --dmg)
      DMG_PATH="$2"
      shift 2
      ;;
    --identity)
      IDENTITY="$2"
      shift 2
      ;;
    --team-id)
      TEAM_ID="$2"
      shift 2
      ;;
    --apple-id)
      APPLE_ID="$2"
      shift 2
      ;;
    --password)
      PASSWORD="$2"
      shift 2
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_PATH" && -z "$DMG_PATH" ]]; then
  echo "Provide --app, --dmg, or both." >&2
  usage >&2
  exit 2
fi

if [[ -n "$APP_PATH" ]]; then
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle does not exist: $APP_PATH" >&2
    exit 1
  fi
  if [[ ! -x "$APP_PATH/Contents/MacOS/Nexus" ]]; then
    echo "App executable does not exist: $APP_PATH/Contents/MacOS/Nexus" >&2
    exit 1
  fi
fi

if [[ -n "$DMG_PATH" && ! -f "$DMG_PATH" ]]; then
  echo "DMG does not exist: $DMG_PATH" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file does not exist: $ENTITLEMENTS" >&2
  exit 1
fi

if [[ "$DRY_RUN" == false && -z "$IDENTITY" ]]; then
  echo "Developer ID signing identity is required outside --dry-run." >&2
  exit 1
fi

print_command() {
  printf 'Would run:'
  printf ' %q' "$@"
  printf '\n'
}

run_or_print() {
  if [[ "$DRY_RUN" == true ]]; then
    print_command "$@"
  else
    "$@"
  fi
}

signing_identity="$IDENTITY"
if [[ -z "$signing_identity" ]]; then
  signing_identity="Developer ID Application: Example"
fi

if [[ -n "$APP_PATH" ]]; then
  run_or_print codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$signing_identity" \
    "$APP_PATH"
fi

if [[ -n "$DMG_PATH" ]]; then
  run_or_print codesign \
    --force \
    --timestamp \
    --sign "$signing_identity" \
    "$DMG_PATH"

  if [[ "$SKIP_NOTARIZATION" == false ]]; then
    if [[ "$DRY_RUN" == false && ( -z "$TEAM_ID" || -z "$APPLE_ID" || -z "$PASSWORD" ) ]]; then
      echo "Notarization requires --team-id, --apple-id, and --password unless --skip-notarization is set." >&2
      exit 1
    fi
    run_or_print xcrun notarytool submit "$DMG_PATH" \
      --apple-id "${APPLE_ID:-apple@example.com}" \
      --team-id "${TEAM_ID:-TEAMID}" \
      --password "${PASSWORD:-app-specific-password}" \
      --wait
    run_or_print xcrun stapler staple "$DMG_PATH"
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run OK."
else
  echo "Signed${DMG_PATH:+ and notarized} Nexus artifact."
fi
