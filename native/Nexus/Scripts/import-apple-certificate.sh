#!/usr/bin/env bash
set -euo pipefail

CERTIFICATE_BASE64=""
CERTIFICATE_PASSWORD=""
KEYCHAIN_PATH=""
KEYCHAIN_PASSWORD=""

usage() {
  cat <<'USAGE'
Usage: import-apple-certificate.sh --certificate-base64 "$APPLE_CERTIFICATE" --certificate-password "$APPLE_CERTIFICATE_PASSWORD" [options]

Imports a base64-encoded Apple Developer ID .p12 certificate into a temporary keychain for release signing.

Options:
  --certificate-base64 value   Base64-encoded .p12 certificate payload.
  --certificate-password value Password for the .p12 certificate.
  --keychain path              Keychain path. Defaults to $RUNNER_TEMP/nexus-signing.keychain-db.
  --keychain-password value    Temporary keychain password. Defaults to a generated process-local value.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --certificate-base64)
      CERTIFICATE_BASE64="$2"
      shift 2
      ;;
    --certificate-password)
      CERTIFICATE_PASSWORD="$2"
      shift 2
      ;;
    --keychain)
      KEYCHAIN_PATH="$2"
      shift 2
      ;;
    --keychain-password)
      KEYCHAIN_PASSWORD="$2"
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

if [[ -z "$CERTIFICATE_BASE64" ]]; then
  echo "--certificate-base64 is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$CERTIFICATE_PASSWORD" ]]; then
  echo "--certificate-password is required" >&2
  usage >&2
  exit 2
fi

if ! command -v security >/dev/null 2>&1; then
  echo "Apple security command is required to import signing certificates" >&2
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 command is required to decode signing certificates" >&2
  exit 1
fi

RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
if [[ -z "$KEYCHAIN_PATH" ]]; then
  KEYCHAIN_PATH="$RUNNER_TEMP/nexus-signing.keychain-db"
fi
if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
  KEYCHAIN_PASSWORD="nexus-keychain-${RANDOM}-${RANDOM}"
fi

CERTIFICATE_PATH="$(mktemp "$RUNNER_TEMP/nexus-certificate.XXXXXX.p12")"
cleanup() {
  rm -f "$CERTIFICATE_PATH"
}
trap cleanup EXIT

decode_certificate() {
  if printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH" 2>/dev/null; then
    return
  fi
  printf '%s' "$CERTIFICATE_BASE64" | base64 -D > "$CERTIFICATE_PATH"
}

decode_certificate

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -P "$CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"
EXISTING_KEYCHAINS="$(security list-keychains -d user | sed 's/[ "]//g')"
security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"

echo "Imported Apple signing certificate into $KEYCHAIN_PATH"
