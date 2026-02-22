#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: scripts/ci/verify_release_asset.sh <tag>" >&2
  exit 1
fi
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

WORK_DIR="/tmp/nve_release_asset_verify_${TAG}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

gh release download "$TAG" -p Neon.Vision.Editor.app.zip -D "$WORK_DIR"
ditto -x -k "$WORK_DIR/Neon.Vision.Editor.app.zip" "$WORK_DIR/extracted"

APP="$WORK_DIR/extracted/Neon Vision Editor.app"
REQUIRE_ICONSTACK=1 scripts/ci/verify_icon_payload.sh "$APP"
echo "Release asset verification passed for $TAG."
