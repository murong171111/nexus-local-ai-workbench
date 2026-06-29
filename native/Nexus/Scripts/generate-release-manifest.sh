#!/usr/bin/env bash
set -euo pipefail

ASSETS_DIR="release-assets"
OUTPUT_PATH=""
RELEASE_TAG=""

usage() {
  cat <<'USAGE'
Usage: generate-release-manifest.sh --assets-dir release-assets --tag v0.1.1 [--output release-assets/nexus-native-release-manifest.json]

Generates a JSON release manifest from published Native DMG assets and their .dmg.sha256 sidecars.
The manifest is update metadata for the manual GitHub release channel; it does not enable automatic updates.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assets-dir)
      ASSETS_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="$2"
      shift 2
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

if [[ -z "$RELEASE_TAG" ]]; then
  echo "--tag is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$ASSETS_DIR/nexus-native-release-manifest.json"
fi

if [[ ! -d "$ASSETS_DIR" ]]; then
  echo "Assets directory does not exist: $ASSETS_DIR" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to generate release manifest JSON" >&2
  exit 1
fi

python3 - "$ASSETS_DIR" "$OUTPUT_PATH" "$RELEASE_TAG" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

assets_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])
release_tag = sys.argv[3]

dmgs = sorted(assets_dir.glob("nexus-native-*.dmg"))
if not dmgs:
    raise SystemExit(f"No Native DMGs found in {assets_dir}")

artifacts = []
for dmg in dmgs:
    checksum_file = dmg.with_name(f"{dmg.name}.sha256")
    if not checksum_file.exists():
        raise SystemExit(f"Missing checksum sidecar: {checksum_file}")

    checksum = checksum_file.read_text(encoding="utf-8").split()[0].strip()
    if len(checksum) != 64:
        raise SystemExit(f"Invalid SHA-256 checksum in {checksum_file}")

    digest = hashlib.sha256()
    with dmg.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != checksum:
        raise SystemExit(f"Checksum mismatch for {dmg.name}: sidecar={checksum} actual={actual}")

    artifacts.append(
        {
            "name": dmg.name,
            "dmg": dmg.name,
            "checksumFile": checksum_file.name,
            "sha256": checksum,
            "sizeBytes": dmg.stat().st_size,
        }
    )

manifest = {
    "schemaVersion": 1,
    "app": "Nexus",
    "releaseTag": release_tag,
    "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "updateChannel": "manual-github-release",
    "automaticUpdatesEnabled": False,
    "artifacts": artifacts,
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"Generated {output_path}")
PY
