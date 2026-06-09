#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Replace ZIP and DMG assets in an existing GitHub release from an existing notarized app.

Usage:
  scripts/replace_release_assets.sh <tag> --app "/path/to/Neon Vision Editor.app" [--skip-verify] [--keep-work-dir]

Examples:
  scripts/replace_release_assets.sh v0.7.7 --app "/Users/h3p/Downloads/Neon Vision Editor.app"
  scripts/replace_release_assets.sh 0.7.7 --app "/Users/h3p/Downloads/Neon Vision Editor.app" --skip-verify

What it does:
  1) Validate that the GitHub release already exists.
  2) Validate the provided app bundle path.
  3) Package Neon.Vision.Editor.app.zip and Neon.Vision.Editor.app.dmg.
  4) Upload both assets to the existing release with --clobber.
  5) Verify the uploaded assets unless --skip-verify is passed.

It does not run release preflight, docs prep, tagging, retagging, or notarization.
EOF
}

if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TAG="$1"
shift || true
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

APP_PATH=""
SKIP_VERIFY=0
KEEP_WORK_DIR=0

while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --app)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "Missing value for --app" >&2
        exit 1
      fi
      APP_PATH="$1"
      ;;
    --skip-verify)
      SKIP_VERIFY=1
      ;;
    --keep-work-dir)
      KEEP_WORK_DIR=1
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

if [[ -z "$APP_PATH" ]]; then
  echo "Missing required --app \"/path/to/Neon Vision Editor.app\"" >&2
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ "$(basename "$APP_PATH")" != "Neon Vision Editor.app" ]]; then
  echo "Expected app bundle named 'Neon Vision Editor.app', got: $(basename "$APP_PATH")" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil is required." >&2
  exit 1
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
  echo "GitHub release does not exist: $TAG" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nve_replace_release_assets_${TAG}.XXXXXX")"
if [[ "$KEEP_WORK_DIR" -eq 0 ]]; then
  trap 'rm -rf "$WORK_DIR"' EXIT
else
  echo "Keeping work dir: $WORK_DIR"
fi

ZIP_PATH="$WORK_DIR/Neon.Vision.Editor.app.zip"
DMG_PATH="$WORK_DIR/Neon.Vision.Editor.app.dmg"

echo "Packaging ZIP from: $APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Packaging DMG from: $APP_PATH"
hdiutil create \
  -volname "Neon Vision Editor" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Replacing release assets in $TAG..."
gh release upload "$TAG" "$ZIP_PATH" "$DMG_PATH" --clobber

if [[ "$SKIP_VERIFY" -eq 0 ]]; then
  echo "Verifying uploaded release assets..."
  scripts/ci/verify_release_asset.sh "$TAG"
fi

echo "Replaced release assets for $TAG."
