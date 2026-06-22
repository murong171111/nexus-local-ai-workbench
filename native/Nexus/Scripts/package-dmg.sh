#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PACKAGE_ROOT/build/Release/Nexus.app"
OUTPUT_DMG="$PACKAGE_ROOT/build/Release/Nexus.dmg"
VOLUME_NAME="Nexus"
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: package-dmg.sh [--app path/to/Nexus.app] [--output path/to/Nexus.dmg] [--volume-name Nexus] [--dry-run]

Packages a built Nexus.app bundle into a read-only DMG.
The DMG is unsigned and not notarized; Apple Developer signing and notarization remain separate M3 release steps.
Use --dry-run to validate the app bundle, staging layout, and hdiutil command without creating a disk image.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DMG="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
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

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle does not exist: $APP_PATH" >&2
  exit 1
fi

if [[ ! -x "$APP_PATH/Contents/MacOS/Nexus" ]]; then
  echo "App executable does not exist: $APP_PATH/Contents/MacOS/Nexus" >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required to package a macOS DMG" >&2
  exit 1
fi

output_dir="$(dirname "$OUTPUT_DMG")"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/nexus-dmg.XXXXXX")"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$output_dir"
rm -f "$OUTPUT_DMG"
cp -R "$APP_PATH" "$staging_dir/Nexus.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil_args=(
  create
  -volname "$VOLUME_NAME"
  -srcfolder "$staging_dir"
  -fs HFS+
  -srcowners off
  -anyowners
  -nospotlight
  -ov
  -format UDZO
  "$OUTPUT_DMG"
)

if [[ "$DRY_RUN" == true ]]; then
  test -d "$staging_dir/Nexus.app"
  test -L "$staging_dir/Applications"
  printf 'Dry run OK. Would run: hdiutil'
  printf ' %q' "${hdiutil_args[@]}"
  printf '\n'
  exit 0
fi

hdiutil "${hdiutil_args[@]}"

echo "Packaged $OUTPUT_DMG"
