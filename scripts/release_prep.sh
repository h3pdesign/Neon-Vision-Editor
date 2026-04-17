#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Prepare release docs, commit, and create a tag.

Usage:
  scripts/release_prep.sh <tag> [--date YYYY-MM-DD] [--push]

Examples:
  scripts/release_prep.sh v0.4.6
  scripts/release_prep.sh 0.4.6 --date 2026-02-12
  scripts/release_prep.sh v0.4.6 --push

Notes:
  - Runs scripts/prepare_release_docs.py
  - Auto-syncs MARKETING_VERSION in Xcode project to the release tag version
  - Commits README.md, CHANGELOG.md, and Welcome Tour release page updates
  - Creates annotated tag <tag>
  - With --push, pushes commit and tag to origin/main
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "" ]]; then
  usage
  exit 0
fi

RAW_TAG="$1"
shift || true

TAG="$RAW_TAG"
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

DATE_ARG=()
DO_PUSH=0

while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --date)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "Missing value for --date" >&2
        exit 1
      fi
      DATE_ARG=(--date "$1")
      ;;
    --push)
      DO_PUSH=1
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a git repository." >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists. Aborting release prep before making any changes." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree is not clean. Commit/stash existing changes first." >&2
  exit 1
fi

EXPECTED_VERSION="${TAG#v}"
PBXPROJ_FILE="Neon Vision Editor.xcodeproj/project.pbxproj"
if [[ ! -f "$PBXPROJ_FILE" ]]; then
  echo "Missing ${PBXPROJ_FILE}; cannot validate MARKETING_VERSION." >&2
  exit 1
fi
MARKETING_VERSIONS_BEFORE="$(
  if command -v rg >/dev/null 2>&1; then
    rg --no-filename --only-matching 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' "$PBXPROJ_FILE"
  else
    grep -Eo 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' "$PBXPROJ_FILE"
  fi \
    | awk '{print $3}' \
    | sort -u
)"
if [[ -z "${MARKETING_VERSIONS_BEFORE}" ]]; then
  echo "Could not read MARKETING_VERSION from ${PBXPROJ_FILE}." >&2
  exit 1
fi

if ! printf '%s\n' "$MARKETING_VERSIONS_BEFORE" | grep -Fxq "$EXPECTED_VERSION"; then
  echo "Syncing MARKETING_VERSION to ${EXPECTED_VERSION}..."
  perl -0pi -e "s/MARKETING_VERSION = [0-9]+\\.[0-9]+\\.[0-9]+;/MARKETING_VERSION = ${EXPECTED_VERSION};/g" "$PBXPROJ_FILE"
fi

MARKETING_VERSIONS_AFTER="$(
  if command -v rg >/dev/null 2>&1; then
    rg --no-filename --only-matching 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' "$PBXPROJ_FILE"
  else
    grep -Eo 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' "$PBXPROJ_FILE"
  fi \
    | awk '{print $3}' \
    | sort -u
)"
if [[ -z "${MARKETING_VERSIONS_AFTER}" ]]; then
  echo "Could not read MARKETING_VERSION from ${PBXPROJ_FILE} after sync." >&2
  exit 1
fi
if ! printf '%s\n' "$MARKETING_VERSIONS_AFTER" | grep -Fxq "$EXPECTED_VERSION"; then
  echo "Failed to align MARKETING_VERSION with ${EXPECTED_VERSION}." >&2
  echo "Found MARKETING_VERSION values after sync:" >&2
  printf '  - %s\n' $MARKETING_VERSIONS_AFTER >&2
  exit 1
fi

echo "Preparing release docs for ${TAG}..."
docs_cmd=(scripts/prepare_release_docs.py "$TAG")
if [[ ${#DATE_ARG[@]} -gt 0 ]]; then
  docs_cmd+=("${DATE_ARG[@]}")
fi
"${docs_cmd[@]}"

# Update release-flow timeline SVGs for major/minor release lines (x.y.0),
# including projected upcoming milestones.
if [[ "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.0$ ]]; then
  echo "Updating release flow timeline SVGs for ${TAG}..."
  scripts/update_release_history_svg.py "$TAG"
fi

if [[ -x "scripts/bump_build_number.sh" ]]; then
  echo "Bumping CURRENT_PROJECT_VERSION for release commit..."
  scripts/bump_build_number.sh "$PBXPROJ_FILE"
fi

git add README.md CHANGELOG.md "Neon Vision Editor/UI/PanelsAndHelpers.swift" "$PBXPROJ_FILE" \
  docs/images/neon-vision-release-history-0.1-to-0.5.svg \
  docs/images/neon-vision-release-history-0.1-to-0.5-light.svg

if git diff --cached --quiet; then
  echo "No release metadata/docs changes to commit."
else
  COMMIT_MSG="chore(release): prepare ${TAG}"
  NVE_SKIP_BUILD_NUMBER_BUMP=1 git commit -m "$COMMIT_MSG"
  echo "Created commit: $COMMIT_MSG"
fi

git tag -a "$TAG" -m "Release ${TAG}"
echo "Created tag: ${TAG}"

if [[ "$DO_PUSH" -eq 1 ]]; then
  BRANCH="$(git branch --show-current)"
  if [[ "$BRANCH" != "main" ]]; then
    echo "--push is only supported from main (current: ${BRANCH})." >&2
    exit 1
  fi
  git push origin main
  git push origin "$TAG"
  echo "Pushed main and ${TAG}."
else
  echo "Next steps:"
  echo "  git push origin main"
  echo "  git push origin ${TAG}"
fi
