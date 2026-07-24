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

release_state="$(
  gh release view "$TAG" \
    --json isDraft,isPrerelease,publishedAt,assets \
    --jq '[.isDraft, .isPrerelease, (.publishedAt // ""), ([.assets[].name] | sort | join(","))] | @tsv'
)"
IFS=$'\t' read -r IS_DRAFT IS_PRERELEASE PUBLISHED_AT ASSET_NAMES <<< "$release_state"
if [[ "$IS_DRAFT" == "true" || "$IS_PRERELEASE" == "true" || -z "$PUBLISHED_AT" ]]; then
  echo "Release ${TAG} is not a published stable release." >&2
  exit 1
fi
for required_asset in Neon.Vision.Editor.app.zip Neon.Vision.Editor.app.dmg SHA256SUMS.txt; do
  if ! tr ',' '\n' <<< "$ASSET_NAMES" | grep -Fxq "$required_asset"; then
    echo "Release ${TAG} is missing ${required_asset}." >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d /tmp/nve_release_asset_verify.XXXXXX)"
MOUNT_POINT=""
cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

gh release download "$TAG" -p Neon.Vision.Editor.app.zip -D "$WORK_DIR"
gh release download "$TAG" -p Neon.Vision.Editor.app.dmg -D "$WORK_DIR"
gh release download "$TAG" -p SHA256SUMS.txt -D "$WORK_DIR"
(cd "$WORK_DIR" && shasum -a 256 -c SHA256SUMS.txt)
ditto -x -k "$WORK_DIR/Neon.Vision.Editor.app.zip" "$WORK_DIR/extracted"

APP="$WORK_DIR/extracted/Neon Vision Editor.app"
/usr/bin/codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
REQUIRE_ICONSTACK=0 scripts/ci/verify_icon_payload.sh "$APP"

MOUNT_POINT="$WORK_DIR/dmg-mount"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$WORK_DIR/Neon.Vision.Editor.app.dmg" -nobrowse -mountpoint "$MOUNT_POINT" -quiet
if [[ ! -d "$MOUNT_POINT/Neon Vision Editor.app" ]]; then
  echo "Mounted DMG does not contain app bundle." >&2
  exit 1
fi

APP_IN_DMG="${MOUNT_POINT}/Neon Vision Editor.app"
/usr/bin/codesign --verify --deep --strict "$APP_IN_DMG"
xcrun stapler validate "$APP_IN_DMG"
REQUIRE_ICONSTACK=0 scripts/ci/verify_icon_payload.sh "$APP_IN_DMG"
echo "Release asset verification passed for $TAG."
