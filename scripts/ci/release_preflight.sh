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

section() {
  echo
  echo "== $1 =="
}

validate_readme_metrics_snapshot() {
  local tag="$1"
  local target_published_date="$2"
  local readme_line readme_date readme_tag clone_date view_date newest_tag

  readme_line="$(grep -E '^> Last updated \(README\): \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\* for latest release \*\*v[^*]+\*\*$' README.md || true)"
  if [[ -z "$readme_line" ]]; then
    echo "README metrics snapshot line is missing or malformed." >&2
    return 1
  fi
  readme_date="$(sed -E 's/^> Last updated \(README\): \*\*([0-9]{4}-[0-9]{2}-[0-9]{2})\*\* for latest release \*\*v[^*]+\*\*$/\1/' <<<"$readme_line")"
  readme_tag="$(sed -E 's/^> Last updated \(README\): \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\* for latest release \*\*(v[^*]+)\*\*$/\1/' <<<"$readme_line")"
  clone_date="$(grep -E 'Clone snapshot \(UTC\).*message=[0-9]{4}-[0-9]{2}-[0-9]{2}' README.md | sed -E 's/.*message=([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/' | head -n1)"
  view_date="$(grep -E 'View snapshot \(UTC\).*message=[0-9]{4}-[0-9]{2}-[0-9]{2}' README.md | sed -E 's/.*message=([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/' | head -n1)"

  if [[ -z "$clone_date" || -z "$view_date" ]]; then
    echo "README traffic snapshot badges are missing or malformed." >&2
    return 1
  fi

  newest_tag="$(printf '%s\n%s\n' "$tag" "$readme_tag" | sort -V | tail -n1)"
  if [[ "$newest_tag" != "$readme_tag" ]]; then
    echo "README metrics latest release ($readme_tag) is older than target $tag." >&2
    return 1
  fi

  if [[ -n "$target_published_date" ]]; then
    if [[ "$readme_date" < "$target_published_date" || "$clone_date" < "$target_published_date" || "$view_date" < "$target_published_date" ]]; then
      echo "README metrics snapshots are older than $tag publish date ($target_published_date)." >&2
      echo "Run scripts/update_download_metrics.py before release preflight." >&2
      return 1
    fi
  fi

  echo "README metrics snapshot is current enough for $tag (README: $readme_date, clone: $clone_date, view: $view_date; latest release: $readme_tag)."
}

section "Toolchain"
scripts/ci/select_xcode17.sh

section "Release metadata"
echo "Validating release docs for $TAG..."
scripts/ci/validate_release_metadata.sh "$TAG"
./scripts/extract_changelog_section.sh CHANGELOG.md "$TAG" > /tmp/release-notes-"$TAG".md

section "README metrics"
if [[ "${NVE_RELEASE_PREFLIGHT_REQUIRE_README_METRICS:-0}" != "1" ]]; then
  echo "Skipping README download + traffic metrics freshness; metrics are maintained separately."
elif gh release view "$TAG" >/dev/null 2>&1; then
  echo "Validating README download + traffic metrics freshness..."
  is_draft="$(gh release view "$TAG" --json isDraft --jq '.isDraft' 2>/dev/null || echo "false")"
  if [[ "$is_draft" == "true" ]]; then
    echo "Skipping metrics freshness check: ${TAG} exists as a draft release."
  else
    published_date="$(gh release view "$TAG" --json publishedAt --jq '.publishedAt[0:10]' 2>/dev/null || true)"
    validate_readme_metrics_snapshot "$TAG" "$published_date"
  fi
else
  echo "Skipping metrics freshness check: ${TAG} is not published on GitHub releases yet."
fi

section "Static audits"
scripts/ci/privacy_log_audit.sh
scripts/ci/markdown_preview_remote_audit.sh
python3 scripts/ci/markdown_preview_theme_audit.py
echo "Skipping App Clip card asset check; App Clip cards are App Store metadata, not GitHub release artifacts."
scripts/ci/localization_audit.py

SAFE_TAG="$(echo "$TAG" | tr -c 'A-Za-z0-9_' '_')"
WORK_DIR="/tmp/nve_release_preflight_${SAFE_TAG}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

section "Critical runtime tests"
echo "Running critical runtime tests..."
run_critical_tests() {
  xcodebuild \
    -project "Neon Vision Editor.xcodeproj" \
    -scheme "Neon Vision Editor" \
    -destination "platform=macOS" \
    -derivedDataPath "${WORK_DIR}/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    -only-testing:"Neon Vision EditorTests/ReleaseRuntimePolicyTests" \
    -only-testing:"Neon Vision EditorTests/SyntaxHighlightingRegressionTests/testBoldKeywordSelectionOverlaysUseStableContiguousLayoutPolicy" \
    -only-testing:"Neon Vision EditorTests/MarkdownPreviewPDFRendererTests/testAllMarkdownPreviewThemesKeepCompactViewportGuardrails" \
    -only-testing:"Neon Vision EditorTests/WindowTranslucencyTests/testMacSettingsWindowPolicyRemainsResizableAndScrollableAtMinimumSize" \
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
section "Icon payload"
scripts/ci/verify_icon_payload.sh "$APP"

echo "Preflight checks passed for $TAG."
