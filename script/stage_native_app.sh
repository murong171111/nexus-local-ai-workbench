#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---debug}"
APP_NAME="Nexus"
BUNDLE_ID="com.ks.nexus.native"
MIN_SYSTEM_VERSION="13.0"
VERSION="0.1.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$ROOT_DIR/native/Nexus"
BRIDGE_MANIFEST="$ROOT_DIR/crates/nexus-ffi/Cargo.toml"
ICON_SOURCE="$ROOT_DIR/src-tauri/icons/icon.icns"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
BRIDGE_LIBRARY_NAME="libnexus_ffi.dylib"

case "$MODE" in
  --debug|debug)
    SWIFT_CONFIGURATION="debug"
    CARGO_CONFIGURATION="debug"
    ;;
  --release|release)
    SWIFT_CONFIGURATION="release"
    CARGO_CONFIGURATION="release"
    ;;
  *)
    echo "usage: $0 [--debug|--release]" >&2
    exit 2
    ;;
esac

echo "Building Rust bridge ($CARGO_CONFIGURATION)..."
if [[ "$CARGO_CONFIGURATION" == "release" ]]; then
  cargo build --release --manifest-path "$BRIDGE_MANIFEST"
else
  cargo build --manifest-path "$BRIDGE_MANIFEST"
fi

echo "Building Swift app ($SWIFT_CONFIGURATION)..."
swift build --package-path "$PACKAGE_DIR" --configuration "$SWIFT_CONFIGURATION"

BUILD_BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --configuration "$SWIFT_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/NexusNative"
BRIDGE_LIBRARY="$ROOT_DIR/crates/nexus-ffi/target/$CARGO_CONFIGURATION/$BRIDGE_LIBRARY_NAME"

if [[ ! -f "$BUILD_BINARY" ]]; then
  echo "Missing Swift executable: $BUILD_BINARY" >&2
  exit 1
fi

if [[ ! -f "$BRIDGE_LIBRARY" ]]; then
  echo "Missing Rust bridge: $BRIDGE_LIBRARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BRIDGE_LIBRARY" "$APP_RESOURCES/$BRIDGE_LIBRARY_NAME"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_RESOURCES/$APP_NAME.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Staged $APP_BUNDLE"
