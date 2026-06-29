#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGURATION="release"
OUTPUT_APP="$PACKAGE_ROOT/build/Release/Nexus.app"
ARCHS=()
DISABLE_SANDBOX=false
WIDGET_EXTENSION_PATH=""

usage() {
  cat <<'USAGE'
Usage: build-app-bundle.sh [--configuration release|debug] [--arch arm64] [--arch x86_64] [--output path/to/Nexus.app] [--widget-extension path/to/NexusWidget.appex] [--disable-sandbox]

Builds the SwiftPM NexusNative executable and wraps it in a local macOS Nexus.app bundle.
The bundle is unsigned by default; signing, notarization, and DMG packaging remain separate M3 steps.
Use --widget-extension to embed an already-built WidgetKit extension at Nexus.app/Contents/PlugIns/NexusWidget.appex.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --arch)
      ARCHS+=("$2")
      shift 2
      ;;
    --output)
      OUTPUT_APP="$2"
      shift 2
      ;;
    --widget-extension)
      WIDGET_EXTENSION_PATH="$2"
      shift 2
      ;;
    --disable-sandbox)
      DISABLE_SANDBOX=true
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

case "$CONFIGURATION" in
  release|debug) ;;
  *)
    echo "--configuration must be release or debug" >&2
    exit 2
    ;;
esac

swift_args=(build --configuration "$CONFIGURATION" --package-path "$PACKAGE_ROOT")
if [[ "$DISABLE_SANDBOX" == true ]]; then
  swift_args+=(--disable-sandbox)
fi
for arch in "${ARCHS[@]}"; do
  swift_args+=(--arch "$arch")
done

swift "${swift_args[@]}"

configuration_dir="$CONFIGURATION"
if [[ "${#ARCHS[@]}" -eq 0 ]]; then
  product_path="$PACKAGE_ROOT/.build/$configuration_dir/NexusNative"
elif [[ "${#ARCHS[@]}" -eq 1 ]]; then
  product_path="$PACKAGE_ROOT/.build/${ARCHS[0]}-apple-macosx/$configuration_dir/NexusNative"
else
  universal_dir="$PACKAGE_ROOT/.build/universal/$configuration_dir"
  mkdir -p "$universal_dir"
  lipo_inputs=()
  for arch in "${ARCHS[@]}"; do
    lipo_inputs+=("$PACKAGE_ROOT/.build/$arch-apple-macosx/$configuration_dir/NexusNative")
  done
  product_path="$universal_dir/NexusNative"
  lipo -create "${lipo_inputs[@]}" -output "$product_path"
fi

if [[ ! -x "$product_path" ]]; then
  echo "Built executable was not found at $product_path" >&2
  exit 1
fi

if [[ -n "$WIDGET_EXTENSION_PATH" ]]; then
  if [[ ! -d "$WIDGET_EXTENSION_PATH" ]]; then
    echo "Widget extension does not exist: $WIDGET_EXTENSION_PATH" >&2
    exit 1
  fi
  if [[ ! -f "$WIDGET_EXTENSION_PATH/Contents/Info.plist" ]]; then
    echo "Widget extension Info.plist does not exist: $WIDGET_EXTENSION_PATH/Contents/Info.plist" >&2
    exit 1
  fi
fi

contents_dir="$OUTPUT_APP/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
plugins_dir="$contents_dir/PlugIns"

rm -rf "$OUTPUT_APP"
mkdir -p "$macos_dir" "$resources_dir"
install -m 755 "$product_path" "$macos_dir/Nexus"
install -m 644 "$PACKAGE_ROOT/Packaging/Info.plist" "$contents_dir/Info.plist"
install -m 644 "$PACKAGE_ROOT/Packaging/icon.icns" "$resources_dir/icon.icns"
printf 'APPL????' > "$contents_dir/PkgInfo"

if [[ -n "$WIDGET_EXTENSION_PATH" ]]; then
  mkdir -p "$plugins_dir"
  cp -R "$WIDGET_EXTENSION_PATH" "$plugins_dir/NexusWidget.appex"
fi

echo "Built $OUTPUT_APP"
