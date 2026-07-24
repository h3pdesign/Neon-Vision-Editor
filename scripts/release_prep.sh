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
  - With --push, refreshes origin/main and preserves allowed release-doc changes
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

is_allowed_release_dirty_path() {
  local path="$1"
  case "$path" in
    CHANGELOG.md|README.md|\
    "Neon Vision Editor/UI/PanelsAndHelpers.swift"|\
    "Neon Vision Editor.xcodeproj/project.pbxproj"|\
    docs/images/neon-vision-release-history-0.1-to-0.5.svg|\
    docs/images/neon-vision-release-history-0.1-to-0.5-light.svg|\
    docs/images/release-download-trend.svg|\
    docs/images/release-download-trend-dark.svg|\
    docs/images/release-download-trend-light.svg)
      return 0
      ;;
  esac
  return 1
}

collect_dirty_paths() {
  {
    git diff --name-only
    git diff --cached --name-only
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

working_tree_has_only_release_metadata_changes() {
  local paths=()
  local dirty_path
  while IFS= read -r dirty_path; do
    paths+=("$dirty_path")
  done < <(collect_dirty_paths)
  if [[ "${#paths[@]}" -eq 0 ]]; then
    return 1
  fi

  local path
  for path in "${paths[@]}"; do
    if ! is_allowed_release_dirty_path "$path"; then
      return 1
    fi
  done
  return 0
}

retry_cmd() {
  local attempts="${RETRY_ATTEMPTS:-3}"
  local base_sleep="${RETRY_BASE_SLEEP:-3}"
  local n=1

  while true; do
    if "$@"; then
      return 0
    fi
    if (( n >= attempts )); then
      return 1
    fi
    echo "Command failed; retrying in $((base_sleep * n))s (${n}/${attempts})..." >&2
    sleep $((base_sleep * n))
    n=$((n + 1))
  done
}

sync_main_before_push() {
  local current_branch local_main_sha origin_main_sha

  current_branch="$(git branch --show-current)"
  if [[ "$current_branch" != "main" ]]; then
    echo "--push is only supported from main (current: ${current_branch})." >&2
    exit 1
  fi

  echo "Synchronizing main with origin/main before release prep..."
  retry_cmd git fetch --tags origin main
  local_main_sha="$(git rev-parse HEAD)"
  origin_main_sha="$(git rev-parse origin/main)"

  if [[ "$local_main_sha" == "$origin_main_sha" ]]; then
    echo "Local main is aligned with origin/main."
    return 0
  fi

  if git merge-base --is-ancestor HEAD origin/main; then
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Local main is behind origin/main. Fast-forwarding while preserving release metadata changes..."
      git rebase --autostash origin/main
    else
      git merge --ff-only origin/main
    fi
    return 0
  fi

  if git merge-base --is-ancestor origin/main HEAD; then
    echo "Local main already contains origin/main; continuing."
    return 0
  fi

  echo "Local main and origin/main both moved. Refusing to create an implicit release merge." >&2
  echo "Rebase the local commits onto origin/main, then rerun release prep." >&2
  echo "  local main:  ${local_main_sha}" >&2
  echo "  origin/main: ${origin_main_sha}" >&2
  exit 1
}

assert_ssh_signing_configuration() {
  local signing_format signing_key signing_probe_commit

  signing_format="$(git config --get gpg.format || true)"
  signing_key="$(git config --get user.signingkey || true)"
  if [[ "$signing_format" != "ssh" || -z "$signing_key" ]]; then
    echo "Release commits require a configured SSH signing key." >&2
    echo "Expected: gpg.format=ssh and user.signingkey=<SSH public key>." >&2
    exit 1
  fi

  if ! signing_probe_commit="$(
    printf '%s\n' "Release signing readiness probe for ${TAG}" \
      | git commit-tree -S HEAD^{tree} -p HEAD
  )" || ! git verify-commit "$signing_probe_commit"; then
    echo "The configured SSH key could not create and verify a signed release commit." >&2
    exit 1
  fi
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a git repository." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  if working_tree_has_only_release_metadata_changes; then
    echo "Working tree has only release metadata changes; continuing release prep."
  else
    echo "Working tree is not clean. Commit/stash existing changes first." >&2
    exit 1
  fi
fi

if [[ "$DO_PUSH" -eq 1 ]]; then
  sync_main_before_push
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists. Aborting release prep before making any changes." >&2
  exit 1
fi

assert_ssh_signing_configuration

EXPECTED_VERSION="${TAG#v}"
PBXPROJ_FILE="Neon Vision Editor.xcodeproj/project.pbxproj"
if [[ ! -f "$PBXPROJ_FILE" ]]; then
  echo "Missing ${PBXPROJ_FILE}; cannot validate MARKETING_VERSION." >&2
  exit 1
fi
MARKETING_VERSIONS_BEFORE="$(
  if command -v rg >/dev/null 2>&1; then
    rg --no-filename --only-matching 'MARKETING_VERSION = [^;]+;' "$PBXPROJ_FILE"
  else
    grep -Eo 'MARKETING_VERSION = [^;]+;' "$PBXPROJ_FILE"
  fi \
    | awk '{gsub(/;/, "", $3); print $3}' \
    | sort -u
)"
if [[ -z "${MARKETING_VERSIONS_BEFORE}" ]]; then
  echo "Could not read MARKETING_VERSION from ${PBXPROJ_FILE}." >&2
  exit 1
fi

if ! printf '%s\n' "$MARKETING_VERSIONS_BEFORE" | grep -Fxq "$EXPECTED_VERSION"; then
  echo "Syncing MARKETING_VERSION to ${EXPECTED_VERSION}..."
  perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${EXPECTED_VERSION};/g" "$PBXPROJ_FILE"
fi

MARKETING_VERSIONS_AFTER="$(
  if command -v rg >/dev/null 2>&1; then
    rg --no-filename --only-matching 'MARKETING_VERSION = [^;]+;' "$PBXPROJ_FILE"
  else
    grep -Eo 'MARKETING_VERSION = [^;]+;' "$PBXPROJ_FILE"
  fi \
    | awk '{gsub(/;/, "", $3); print $3}' \
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

scripts/ci/validate_release_metadata.sh "$TAG"

git add README.md CHANGELOG.md index.html "Neon Vision Editor/UI/PanelsAndHelpers.swift" "$PBXPROJ_FILE" \
  docs/images/neon-vision-release-history-0.1-to-0.5.svg \
  docs/images/neon-vision-release-history-0.1-to-0.5-light.svg

if git diff --cached --quiet; then
  echo "No release metadata/docs changes to commit."
else
  COMMIT_MSG="chore(release): prepare ${TAG}"
  NVE_SKIP_BUILD_NUMBER_BUMP=1 git commit -S -m "$COMMIT_MSG"
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
