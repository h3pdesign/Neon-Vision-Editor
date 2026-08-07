#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-h3pdesign/Neon-Vision-Editor}"
APP_NAME="Neon Vision Editor.app"
INSTALL_DIR="/Applications"

usage() {
  cat <<EOF
Install Neon Vision Editor from the latest GitHub release.

Usage:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install.sh | sh -s -- --appdir "\$HOME/Applications"

Options:
  --appdir PATH   Install destination (default: /Applications)
EOF
}

while [ "${1:-}" != "" ]; do
  case "$1" in
    --appdir)
      shift
      INSTALL_DIR="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

mkdir -p "${INSTALL_DIR}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  if [ -n "${MOUNT_POINT:-}" ] && mount | grep -q "on ${MOUNT_POINT} "; then
    hdiutil detach "${MOUNT_POINT}" -quiet || true
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Fetching latest release metadata for ${REPO}..."
RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")"

# Prefer the actual app assets, not the source zipball.
ASSET_URL="$(printf '%s' "${RELEASE_JSON}" | python3 -c '
import json
import re
import sys

try:
    release = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)

assets = release.get("assets") or []
urls = [a.get("browser_download_url", "") for a in assets if isinstance(a, dict)]

# Prefer the ZIP so a normal install does not need to mount a disk image.
preferred = next((u for u in urls if re.search(r"Neon\.Vision\.Editor\.app\.zip$", u)), "")
if preferred:
    print(preferred)
    raise SystemExit(0)

preferred = next((u for u in urls if re.search(r"Neon\.Vision\.Editor\.app\.dmg$", u)), "")
if preferred:
    print(preferred)
    raise SystemExit(0)

fallback = next((u for u in urls if re.search(r"\.(zip|dmg)$", u)), "")
print(fallback)
')"
if [ -z "${ASSET_URL}" ]; then
  echo "Could not find an app .zip or .dmg asset in the latest release." >&2
  exit 1
fi

CHECKSUM_URL="$(printf '%s' "${RELEASE_JSON}" | python3 -c '
import json
import sys

try:
    release = json.load(sys.stdin)
except Exception:
    print("")
    raise SystemExit(0)

for asset in release.get("assets") or []:
    if isinstance(asset, dict) and asset.get("name") == "SHA256SUMS.txt":
        print(asset.get("browser_download_url", ""))
        break
')"
if [ -z "${CHECKSUM_URL}" ]; then
  echo "The latest release does not include SHA256SUMS.txt; refusing an unverified install." >&2
  exit 1
fi

ASSET_FILE="${TMP_DIR}/$(basename "${ASSET_URL}")"
echo "Downloading $(basename "${ASSET_URL}")..."
curl -fL "${ASSET_URL}" -o "${ASSET_FILE}"
curl -fsSL "${CHECKSUM_URL}" -o "${TMP_DIR}/SHA256SUMS.txt"

EXPECTED_SHA256="$(awk -v asset="$(basename "${ASSET_FILE}")" '$2 == asset { print $1; exit }' "${TMP_DIR}/SHA256SUMS.txt")"
ACTUAL_SHA256="$(shasum -a 256 "${ASSET_FILE}" | awk '{ print $1 }')"
if [ -z "${EXPECTED_SHA256}" ] || [ "${EXPECTED_SHA256}" != "${ACTUAL_SHA256}" ]; then
  echo "Downloaded asset checksum does not match the published release checksum." >&2
  exit 1
fi

APP_PATH=""
case "${ASSET_FILE}" in
  *.zip)
    echo "Extracting archive..."
    ditto -xk "${ASSET_FILE}" "${TMP_DIR}/extract"
    APP_PATH="$(find "${TMP_DIR}/extract" -maxdepth 3 -name "${APP_NAME}" -print -quit)"
    ;;
  *.dmg)
    echo "Mounting disk image..."
    MOUNT_POINT="$(hdiutil attach "${ASSET_FILE}" -nobrowse -quiet | awk '/\/Volumes\// {print $3; exit}')"
    if [ -z "${MOUNT_POINT}" ]; then
      echo "Failed to mount DMG." >&2
      exit 1
    fi
    APP_PATH="$(find "${MOUNT_POINT}" -maxdepth 3 -name "${APP_NAME}" -print -quit)"
    ;;
esac

if [ -z "${APP_PATH}" ] || [ ! -d "${APP_PATH}" ]; then
  echo "Could not find ${APP_NAME} in downloaded asset." >&2
  exit 1
fi

echo "Installing to ${INSTALL_DIR}..."
if [ -d "${INSTALL_DIR}/${APP_NAME}" ]; then
  rm -rf "${INSTALL_DIR}/${APP_NAME}"
fi
ditto "${APP_PATH}" "${INSTALL_DIR}/${APP_NAME}"

echo
echo "Installed: ${INSTALL_DIR}/${APP_NAME}"
if [ "${INSTALL_DIR}" = "/Applications" ] && [ ! -w "/Applications" ]; then
  echo "Tip: use --appdir \"\$HOME/Applications\" to avoid admin password prompts."
fi
