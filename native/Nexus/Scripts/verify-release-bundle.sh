#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
ASSETS_DIR=""
MANIFEST_PATH=""
CHECKSUM_PATH=""
REQUIRE_WIDGET=false
DMG_PATHS=()

usage() {
  cat <<'USAGE'
Usage: verify-release-bundle.sh [--app dist/Nexus.app] [--dmg dist/Nexus.dmg] [--checksum dist/Nexus.dmg.sha256] [--assets-dir release-assets] [--manifest release-assets/nexus-native-release-manifest.json] [--require-widget]

Verifies Native release bundle outputs after build/package steps:
- Nexus.app has Info.plist and an executable.
- Every Native DMG has a matching SHA-256 sidecar.
- nexus-native-release-manifest.json matches the final DMG/checksum assets and keeps automatic updates disabled.
- --require-widget additionally requires Nexus.app/Contents/PlugIns/NexusWidget.appex.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --dmg)
      DMG_PATHS+=("$2")
      shift 2
      ;;
    --checksum)
      CHECKSUM_PATH="$2"
      shift 2
      ;;
    --assets-dir)
      ASSETS_DIR="$2"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    --require-widget)
      REQUIRE_WIDGET=true
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

if [[ -n "$ASSETS_DIR" ]]; then
  if [[ ! -d "$ASSETS_DIR" ]]; then
    echo "Assets directory does not exist: $ASSETS_DIR" >&2
    exit 1
  fi
  while IFS= read -r dmg_path; do
    DMG_PATHS+=("$dmg_path")
  done < <(find "$ASSETS_DIR" -maxdepth 1 -type f -name 'nexus-native-*.dmg' | sort)
  if [[ -z "$MANIFEST_PATH" && -f "$ASSETS_DIR/nexus-native-release-manifest.json" ]]; then
    MANIFEST_PATH="$ASSETS_DIR/nexus-native-release-manifest.json"
  fi
fi

if [[ -z "$APP_PATH" && "${#DMG_PATHS[@]}" -eq 0 && -z "$MANIFEST_PATH" ]]; then
  echo "Nothing to verify. Provide --app, --dmg, --assets-dir, or --manifest." >&2
  usage >&2
  exit 2
fi

if [[ -n "$APP_PATH" ]]; then
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle does not exist: $APP_PATH" >&2
    exit 1
  fi
  if [[ ! -f "$APP_PATH/Contents/Info.plist" ]]; then
    echo "App Info.plist does not exist: $APP_PATH/Contents/Info.plist" >&2
    exit 1
  fi

  executable_name="Nexus"
  if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist" 2>/dev/null || printf 'Nexus')"
  fi
  if [[ -z "$executable_name" ]]; then
    executable_name="Nexus"
  fi
  if [[ ! -x "$APP_PATH/Contents/MacOS/$executable_name" ]]; then
    echo "App executable does not exist: $APP_PATH/Contents/MacOS/$executable_name" >&2
    exit 1
  fi

  if [[ "$REQUIRE_WIDGET" == true ]]; then
    widget_path="$APP_PATH/Contents/PlugIns/NexusWidget.appex"
    if [[ ! -d "$widget_path" ]]; then
      echo "Widget extension is required but missing: $widget_path" >&2
      exit 1
    fi
    if [[ ! -f "$widget_path/Contents/Info.plist" ]]; then
      echo "Widget extension Info.plist is missing: $widget_path/Contents/Info.plist" >&2
      exit 1
    fi
    if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
      widget_extension_point="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$widget_path/Contents/Info.plist" 2>/dev/null || true)"
      if [[ "$widget_extension_point" != "com.apple.widgetkit-extension" ]]; then
        echo "Widget extension point must be com.apple.widgetkit-extension: $widget_path/Contents/Info.plist" >&2
        exit 1
      fi
    fi
  fi
fi

verify_checksum() {
  local dmg_path="$1"
  local checksum_path="${2:-$1.sha256}"

  if [[ ! -f "$dmg_path" ]]; then
    echo "DMG does not exist: $dmg_path" >&2
    exit 1
  fi
  if [[ ! -f "$checksum_path" ]]; then
    echo "Checksum sidecar does not exist: $checksum_path" >&2
    exit 1
  fi

  local expected
  local actual
  expected="$(awk '{print $1; exit}' "$checksum_path")"
  actual="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
  if [[ "${#expected}" -ne 64 ]]; then
    echo "Invalid SHA-256 checksum in $checksum_path" >&2
    exit 1
  fi
  if [[ "$expected" != "$actual" ]]; then
    echo "Checksum mismatch for $dmg_path: sidecar=$expected actual=$actual" >&2
    exit 1
  fi
}

if [[ "${#DMG_PATHS[@]}" -gt 0 ]]; then
  for dmg_path in "${DMG_PATHS[@]}"; do
    if [[ -n "$CHECKSUM_PATH" && "${#DMG_PATHS[@]}" -eq 1 ]]; then
      verify_checksum "$dmg_path" "$CHECKSUM_PATH"
    else
      verify_checksum "$dmg_path"
    fi
  done
fi

if [[ -n "$MANIFEST_PATH" ]]; then
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "Release manifest does not exist: $MANIFEST_PATH" >&2
    exit 1
  fi
  if [[ "${#DMG_PATHS[@]}" -eq 0 ]]; then
    echo "Manifest verification requires --dmg or --assets-dir DMG inputs." >&2
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to verify release manifest JSON" >&2
    exit 1
  fi

  python3 - "$MANIFEST_PATH" "${DMG_PATHS[@]}" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
dmg_paths = [Path(path) for path in sys.argv[2:]]
dmgs = {path.name for path in dmg_paths}
dmg_sizes = {path.name: path.stat().st_size for path in dmg_paths}
sidecars = {f"{path.name}.sha256" for path in dmg_paths}
sidecar_checksums = {}
for path in dmg_paths:
    sidecar_path = path.with_name(f"{path.name}.sha256")
    checksum = sidecar_path.read_text(encoding="utf-8").split()[0].strip()
    sidecar_checksums[sidecar_path.name] = checksum

data = json.loads(manifest_path.read_text(encoding="utf-8"))
if data.get("schemaVersion") != 1:
    raise SystemExit("Release manifest schemaVersion must be 1")
if data.get("app") != "Nexus":
    raise SystemExit("Release manifest app must be Nexus")
if data.get("updateChannel") != "manual-github-release":
    raise SystemExit("Release manifest updateChannel must be manual-github-release")
if data.get("automaticUpdatesEnabled") is not False:
    raise SystemExit("Release manifest automaticUpdatesEnabled must be false")

artifacts = data.get("artifacts")
if not isinstance(artifacts, list) or not artifacts:
    raise SystemExit("Release manifest must include artifacts")

manifest_dmgs = set()
for artifact in artifacts:
    dmg = artifact.get("dmg")
    checksum_file = artifact.get("checksumFile")
    sha256 = artifact.get("sha256")
    size_bytes = artifact.get("sizeBytes")
    if not dmg or not checksum_file:
        raise SystemExit("Release manifest artifact is missing dmg or checksumFile")
    if not isinstance(sha256, str) or len(sha256) != 64:
        raise SystemExit(f"Release manifest artifact has invalid sha256: {dmg}")
    if not isinstance(size_bytes, int) or size_bytes <= 0:
        raise SystemExit(f"Release manifest artifact has invalid sizeBytes: {dmg}")
    manifest_dmgs.add(dmg)
    if checksum_file not in sidecars:
        raise SystemExit(f"Release manifest references missing checksum sidecar: {checksum_file}")
    if sha256 != sidecar_checksums.get(checksum_file):
        raise SystemExit(f"Release manifest sha256 must match checksum sidecar: {dmg}")
    if size_bytes != dmg_sizes.get(dmg):
        raise SystemExit(f"Release manifest sizeBytes must match DMG size: {dmg}")

missing = dmgs - manifest_dmgs
extra = manifest_dmgs - dmgs
if missing:
    raise SystemExit(f"Release manifest is missing DMGs: {', '.join(sorted(missing))}")
if extra:
    raise SystemExit(f"Release manifest references unknown DMGs: {', '.join(sorted(extra))}")
PY
fi

echo "Verified Native release bundle outputs."
