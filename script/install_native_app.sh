#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-install}"
APP_NAME="Nexus"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="${NEXUS_INSTALL_DIR:-/Applications}"
TARGET_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

"$ROOT_DIR/script/stage_native_app.sh" --release

mkdir -p "$INSTALL_DIR"
rm -rf "$TARGET_BUNDLE"
cp -R "$SOURCE_BUNDLE" "$TARGET_BUNDLE"

case "$MODE" in
  install)
    echo "Installed $TARGET_BUNDLE"
    ;;
  --run|run)
    /usr/bin/open -n "$TARGET_BUNDLE"
    ;;
  *)
    echo "usage: $0 [install|--run]" >&2
    exit 2
    ;;
esac
