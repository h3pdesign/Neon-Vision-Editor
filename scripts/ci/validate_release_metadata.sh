#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: scripts/ci/validate_release_metadata.sh <tag>" >&2
  exit 2
fi
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

EXPECTED_VERSION="${TAG#v}"
PBXPROJ_FILE="Neon Vision Editor.xcodeproj/project.pbxproj"
WELCOME_TOUR_FILE="Neon Vision Editor/UI/PanelsAndHelpers.swift"
SAFE_TAG="$(printf '%s' "$TAG" | tr -c 'A-Za-z0-9_' '_')"
CHANGELOG_SECTION_FILE="/tmp/release-metadata-${SAFE_TAG}.md"
trap 'rm -f "$CHANGELOG_SECTION_FILE"' EXIT

fail() {
  local message="$1"
  local fix="$2"
  echo "Release metadata check failed: ${message}" >&2
  echo "Fix: ${fix}" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing ${path}" "Restore ${path}, then run scripts/release_prep.sh ${TAG}."
}

require_file CHANGELOG.md
require_file README.md
require_file "$PBXPROJ_FILE"
require_file "$WELCOME_TOUR_FILE"

if ! ./scripts/extract_changelog_section.sh CHANGELOG.md "$TAG" >"$CHANGELOG_SECTION_FILE" 2>/dev/null; then
  fail "CHANGELOG.md has no section for ${TAG}" "Run scripts/release_prep.sh ${TAG} to add/update release docs."
fi

if grep -nEi "\bTODO\b" "$CHANGELOG_SECTION_FILE" >/dev/null; then
  fail "CHANGELOG.md section for ${TAG} still contains TODO markers" "Replace TODOs in CHANGELOG.md, then rerun scripts/ci/release_preflight.sh ${TAG}."
fi

grep -nE "^> Latest release: \\*\\*${TAG}\\*\\*\\r?$" README.md >/dev/null || \
  fail "README.md latest-release badge does not point to ${TAG}" "Run scripts/release_prep.sh ${TAG}."

grep -nE "^- Latest release: \\*\\*${TAG}\\*\\*\\r?$" README.md >/dev/null || \
  fail "README.md latest-release bullet does not point to ${TAG}" "Run scripts/release_prep.sh ${TAG}."

grep -nE "^\\| .*\\(https://github\\.com/h3pdesign/Neon-Vision-Editor/releases/tag/${TAG}\\) \\|" README.md >/dev/null || \
  fail "README.md release table has no row for ${TAG}" "Run scripts/release_prep.sh ${TAG}."

grep -F "title: \"What’s New in ${TAG}\"" "$WELCOME_TOUR_FILE" >/dev/null || \
  fail "Welcome Tour does not identify ${TAG}" "Run scripts/release_prep.sh ${TAG}; it updates the Welcome Tour release cards."

MARKETING_VERSIONS="$(
  if command -v rg >/dev/null 2>&1; then
    rg --no-filename --only-matching 'MARKETING_VERSION = [^;]+;' "$PBXPROJ_FILE"
  else
    grep -Eo 'MARKETING_VERSION = [^;]+;' "$PBXPROJ_FILE"
  fi | awk '{gsub(/;/, "", $3); print $3}' | sort -u
)"

if [[ -z "$MARKETING_VERSIONS" ]]; then
  fail "could not read MARKETING_VERSION from ${PBXPROJ_FILE}" "Restore project build settings, then run scripts/release_prep.sh ${TAG}."
fi

if [[ "$MARKETING_VERSIONS" != "$EXPECTED_VERSION" ]]; then
  fail "MARKETING_VERSION is not ${EXPECTED_VERSION} (found: ${MARKETING_VERSIONS//$'\n'/, })" "Run scripts/release_prep.sh ${TAG}; it syncs MARKETING_VERSION automatically."
fi

BUILD_NUMBERS="$(
  if command -v rg >/dev/null 2>&1; then
    rg --no-filename --only-matching 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ_FILE"
  else
    grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ_FILE"
  fi | awk '{print $3}' | sort -u
)"

if [[ -z "$BUILD_NUMBERS" ]]; then
  fail "could not read CURRENT_PROJECT_VERSION from ${PBXPROJ_FILE}" "Restore project build settings, then run scripts/bump_build_number.sh \"${PBXPROJ_FILE}\"."
fi

if [[ "$(printf '%s\n' "$BUILD_NUMBERS" | wc -l | tr -d ' ')" != "1" ]]; then
  fail "CURRENT_PROJECT_VERSION values are inconsistent (${BUILD_NUMBERS//$'\n'/, })" "Normalize build numbers, or rerun scripts/release_prep.sh ${TAG}."
fi

echo "Release metadata is valid for ${TAG}."
