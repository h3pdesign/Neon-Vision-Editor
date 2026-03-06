#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: scripts/ci/release_preflight.sh <tag>" >&2
  exit 1
fi
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

scripts/ci/select_xcode17.sh

echo "Validating release docs for $TAG..."
./scripts/extract_changelog_section.sh CHANGELOG.md "$TAG" > /tmp/release-notes-"$TAG".md
if grep -nE "^- TODO$" /tmp/release-notes-"$TAG".md >/dev/null; then
  echo "CHANGELOG section for ${TAG} still contains TODO entries." >&2
  exit 1
fi
if grep -nEi "\bTODO\b" /tmp/release-notes-"$TAG".md >/dev/null; then
  echo "CHANGELOG section for ${TAG} still contains unresolved TODO markers." >&2
  exit 1
fi
grep -nE "^> Latest release: \\*\\*${TAG}\\*\\*\\r?$" README.md >/dev/null
grep -nE "^- Latest release: \\*\\*${TAG}\\*\\*\\r?$" README.md >/dev/null
grep -nE "^### ${TAG} \\(summary\\)\\r?$" README.md >/dev/null

echo "Validating README download metrics freshness..."
if gh release view "$TAG" >/dev/null 2>&1; then
  scripts/update_download_metrics.py --check
else
  echo "Skipping metrics freshness check: ${TAG} is not published on GitHub releases yet."
fi

SAFE_TAG="$(echo "$TAG" | tr -c 'A-Za-z0-9_' '_')"
WORK_DIR="/tmp/nve_release_preflight_${SAFE_TAG}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "Running critical runtime tests..."
run_critical_tests() {
  xcodebuild \
    -project "Neon Vision Editor.xcodeproj" \
    -scheme "Neon Vision Editor" \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    -only-testing:"Neon Vision EditorTests/ReleaseRuntimePolicyTests" \
    test >"${WORK_DIR}/test.log" 2>&1
}

if ! run_critical_tests; then
  echo "Primary test pass failed in this environment; retrying once..."
  sleep 3
  run_critical_tests
fi

BUILD_SETTINGS="$(xcodebuild \
  -project "Neon Vision Editor.xcodeproj" \
  -scheme "Neon Vision Editor" \
  -destination "platform=macOS" \
  -showBuildSettings 2>/dev/null)"
BUILT_PRODUCTS_DIR="$(echo "$BUILD_SETTINGS" | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $2; exit}')"
FULL_PRODUCT_NAME="$(echo "$BUILD_SETTINGS" | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}')"
APP="${BUILT_PRODUCTS_DIR%/}/${FULL_PRODUCT_NAME}"
if [[ ! -d "$APP" ]]; then
  APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path "*/Build/Products/Debug/Neon Vision Editor.app" | head -n1)"
fi
if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
  echo "Could not locate built app for icon payload verification." >&2
  exit 1
fi
scripts/ci/verify_icon_payload.sh "$APP"

echo "Preflight checks passed for $TAG."
