#!/usr/bin/env bash
set -euo pipefail

NOTES_PATH="CHANGELOG.md"
RELEASE_TAG=""
ASSETS_DIR=""
MANIFEST_PATH=""
ALLOW_UNRELEASED=false

usage() {
  cat <<'USAGE'
Usage: verify-release-notes.sh --notes CHANGELOG.md --tag v0.1.1 [--assets-dir release-assets] [--manifest release-assets/nexus-native-release-manifest.json] [--allow-unreleased]

Verifies Native release notes before publishing a GitHub Release.
The selected notes section must mention Native artifacts, checksums, signing/notarization,
known blockers, validation summary, release manifest metadata, and migration/rollback notes.
When --assets-dir is provided, every nexus-native-*.dmg, matching .dmg.sha256 sidecar,
and the manifest filename must be named in the notes.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes)
      NOTES_PATH="$2"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="$2"
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
    --allow-unreleased)
      ALLOW_UNRELEASED=true
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

if [[ -z "$RELEASE_TAG" ]]; then
  echo "--tag is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$NOTES_PATH" ]]; then
  echo "Release notes file does not exist: $NOTES_PATH" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to verify release notes" >&2
  exit 1
fi

python3 - "$NOTES_PATH" "$RELEASE_TAG" "$ASSETS_DIR" "$MANIFEST_PATH" "$ALLOW_UNRELEASED" <<'PY'
import re
import sys
from pathlib import Path

notes_path = Path(sys.argv[1])
release_tag = sys.argv[2]
assets_dir = Path(sys.argv[3]) if sys.argv[3] else None
manifest_path = Path(sys.argv[4]) if sys.argv[4] else None
allow_unreleased = sys.argv[5].lower() == "true"

text = notes_path.read_text(encoding="utf-8")

heading_patterns = [
    rf"^##\s+\[{re.escape(release_tag)}\].*$",
    rf"^##\s+{re.escape(release_tag)}\b.*$",
]
if allow_unreleased:
    heading_patterns.append(r"^##\s+\[Unreleased\].*$")

lines = text.splitlines()
start = None
for index, line in enumerate(lines):
    if any(re.match(pattern, line) for pattern in heading_patterns):
        start = index
        break

if start is None:
    raise SystemExit(f"Release notes must include a section for {release_tag}")

end = len(lines)
for index in range(start + 1, len(lines)):
    if lines[index].startswith("## "):
        end = index
        break

section = "\n".join(lines[start:end])
lower_section = section.lower()

required_terms = [
    release_tag.lower(),
    "native artifact",
    "checksum",
    "signing/notarization",
    "known blocker",
    "validation summary",
    "release manifest",
    "migration",
    "rollback",
]
missing = [term for term in required_terms if term not in lower_section]

if "automatic updates disabled" not in lower_section and "manual-github-release" not in lower_section:
    missing.append("automatic updates disabled or manual-github-release")

asset_names = []
if assets_dir:
    if not assets_dir.is_dir():
        raise SystemExit(f"Assets directory does not exist: {assets_dir}")
    dmgs = sorted(assets_dir.glob("nexus-native-*.dmg"))
    if not dmgs:
        raise SystemExit(f"No Native DMGs found in {assets_dir}")
    for dmg in dmgs:
        checksum = dmg.with_name(f"{dmg.name}.sha256")
        if not checksum.exists():
            raise SystemExit(f"Missing checksum sidecar: {checksum}")
        asset_names.extend([dmg.name, checksum.name])

if manifest_path:
    if not manifest_path.is_file():
        raise SystemExit(f"Release manifest does not exist: {manifest_path}")
    asset_names.append(manifest_path.name)

missing_assets = [name for name in asset_names if name not in section]
if missing_assets:
    missing.append("asset names: " + ", ".join(missing_assets))

if missing:
    raise SystemExit("Release notes gate is incomplete: " + "; ".join(missing))
PY

echo "Verified Native release notes gate."
