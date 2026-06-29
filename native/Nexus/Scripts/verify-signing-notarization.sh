#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
DMG_PATH=""
REQUIRE_APP_SIGNATURE=false
REQUIRE_DMG_SIGNATURE=false
REQUIRE_NOTARIZATION=false

usage() {
  cat <<'USAGE'
Usage: verify-signing-notarization.sh [--app dist/Nexus.app] [--dmg dist/Nexus.dmg] [--require-app-signature] [--require-dmg-signature] [--require-notarization]

Verifies Native macOS signing and notarization evidence after release signing steps:
- codesign --verify validates the signed Nexus.app bundle.
- codesign --verify validates the signed DMG.
- spctl assesses signed app/DMG Gatekeeper acceptance when available.
- xcrun stapler validate proves a notarized DMG ticket is stapled when --require-notarization is set.
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
    --require-app-signature)
      REQUIRE_APP_SIGNATURE=true
      shift
      ;;
    --require-dmg-signature)
      REQUIRE_DMG_SIGNATURE=true
      shift
      ;;
    --require-notarization)
      REQUIRE_NOTARIZATION=true
      REQUIRE_DMG_SIGNATURE=true
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

verify_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required to verify signing/notarization evidence." >&2
    exit 1
  fi
}

verify_app_signature() {
  local app_path="$1"
  if [[ ! -d "$app_path" ]]; then
    echo "App bundle does not exist: $app_path" >&2
    exit 1
  fi
  verify_tool codesign
  codesign --verify --deep --strict --verbose=2 "$app_path"
  codesign --display --verbose=2 "$app_path" >/dev/null
  if command -v spctl >/dev/null 2>&1; then
    spctl --assess --type execute --verbose=2 "$app_path"
  fi
}

verify_dmg_signature() {
  local dmg_path="$1"
  if [[ ! -f "$dmg_path" ]]; then
    echo "DMG does not exist: $dmg_path" >&2
    exit 1
  fi
  verify_tool codesign
  codesign --verify --verbose=2 "$dmg_path"
  codesign --display --verbose=2 "$dmg_path" >/dev/null
  if command -v spctl >/dev/null 2>&1; then
    spctl --assess --type open --verbose=2 "$dmg_path"
  fi
}

verify_dmg_notarization() {
  local dmg_path="$1"
  if [[ ! -f "$dmg_path" ]]; then
    echo "DMG does not exist: $dmg_path" >&2
    exit 1
  fi
  verify_tool xcrun
  xcrun stapler validate "$dmg_path"
}

if [[ "$REQUIRE_APP_SIGNATURE" == true ]]; then
  if [[ -z "$APP_PATH" ]]; then
    echo "--require-app-signature requires --app." >&2
    exit 2
  fi
  verify_app_signature "$APP_PATH"
fi

if [[ "$REQUIRE_DMG_SIGNATURE" == true ]]; then
  if [[ -z "$DMG_PATH" ]]; then
    echo "--require-dmg-signature requires --dmg." >&2
    exit 2
  fi
  verify_dmg_signature "$DMG_PATH"
fi

if [[ "$REQUIRE_NOTARIZATION" == true ]]; then
  if [[ -z "$DMG_PATH" ]]; then
    echo "--require-notarization requires --dmg." >&2
    exit 2
  fi
  verify_dmg_notarization "$DMG_PATH"
fi

echo "Verified Native signing/notarization evidence."
