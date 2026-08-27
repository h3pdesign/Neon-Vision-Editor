#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Prepare release docs and a signed release commit for the hosted GitHub release workflow.

Usage:
  scripts/release_prep.sh <tag> [--date YYYY-MM-DD] [--push]
  scripts/release_prep.sh --next [--minor|--major] [--date YYYY-MM-DD] [--push]

Examples:
  scripts/release_prep.sh v0.4.6
  scripts/release_prep.sh 0.4.6 --date 2026-02-12
  scripts/release_prep.sh --next --push

Notes:
  - Runs scripts/prepare_release_docs.py
  - Auto-syncs MARKETING_VERSION in Xcode project to the release tag version
  - With --push, refreshes origin/develop, creates release/<version>, and opens a PR into main
  - Commits README.md, ARCHITECTURE.md, CHANGELOG.md, and Welcome Tour release page updates
  - With --next, chooses the next stable tag; patch releases are capped at .9
  - Does not create a tag: the canonical GitHub-hosted workflow tags only after its gates pass
  - With --push, pushes only the prepared release branch and requests merge auto-merge
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--next" ]]; then
  shift
  NEXT_BUMP="--patch"
  if [[ "${1:-}" == "--minor" || "${1:-}" == "--major" ]]; then
    NEXT_BUMP="$1"
    shift
  fi
  TAG="$(scripts/next_release_version.py "$NEXT_BUMP")"
  echo "Selected next release tag: ${TAG}"
else
  RAW_TAG="$1"
  shift || true
  TAG="$RAW_TAG"
  if [[ "$TAG" != v* ]]; then
    TAG="v$TAG"
  fi
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
    CHANGELOG.md|README.md|ARCHITECTURE.md|\
    "Neon Vision Editor/UI/PanelsAndHelpers.swift"|\
    "Neon Vision Editor.xcodeproj/project.pbxproj"|\
    site/index.html|site/changelog.html|\
    site/de/index.html|site/da/index.html|site/fr/index.html|\
    site/es/index.html|site/ja/index.html|site/zh-Hans/index.html|\
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

sync_develop_before_push() {
  local current_branch local_develop_sha origin_develop_sha

  current_branch="$(git branch --show-current)"
  if [[ "$current_branch" != "develop" ]]; then
    echo "--push is only supported from develop (current: ${current_branch})." >&2
    exit 1
  fi

  echo "Synchronizing develop with origin/develop before release prep..."
  retry_cmd git fetch --tags origin develop
  local_develop_sha="$(git rev-parse HEAD)"
  origin_develop_sha="$(git rev-parse origin/develop)"

  if [[ "$local_develop_sha" == "$origin_develop_sha" ]]; then
    echo "Local develop is aligned with origin/develop."
    return 0
  fi

  if git merge-base --is-ancestor HEAD origin/develop; then
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Local develop is behind origin/develop. Fast-forwarding while preserving release metadata changes..."
      git rebase --autostash origin/develop
    else
      git merge --ff-only origin/develop
    fi
    return 0
  fi

  if git merge-base --is-ancestor origin/develop HEAD; then
    echo "Local develop already contains origin/develop; continuing."
    return 0
  fi

  echo "Local develop and origin/develop both moved. Refusing to create an implicit release merge." >&2
  echo "Rebase the local commits onto origin/develop, then rerun release prep." >&2
  echo "  local develop:  ${local_develop_sha}" >&2
  echo "  origin/develop: ${origin_develop_sha}" >&2
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
  sync_develop_before_push
  RELEASE_BRANCH="release/${TAG#v}"
  if git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}" || git ls-remote --exit-code --heads origin "${RELEASE_BRANCH}" >/dev/null 2>&1; then
    echo "Release branch ${RELEASE_BRANCH} already exists. Refusing to overwrite it." >&2
    exit 1
  fi
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists. Aborting release prep before making any changes." >&2
  exit 1
fi

echo "Validating release input before changing project metadata..."
scripts/ci/release_notes_quality_gate.sh "$TAG" --preflight

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

if [[ -x "scripts/bump_build_number.sh" ]]; then
  echo "Bumping CURRENT_PROJECT_VERSION for release commit..."
  scripts/bump_build_number.sh "$PBXPROJ_FILE"
fi

RELEASE_BUILD_NUMBER="$(awk '/CURRENT_PROJECT_VERSION = [0-9]+;/{gsub(/[^0-9]/, "", $0); print; exit}' "$PBXPROJ_FILE")"
if [[ -z "$RELEASE_BUILD_NUMBER" ]]; then
  echo "Could not read CURRENT_PROJECT_VERSION after bumping the release build." >&2
  exit 1
fi

echo "Preparing release docs for ${TAG}..."
docs_cmd=(scripts/prepare_release_docs.py "$TAG" --build "$RELEASE_BUILD_NUMBER")
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

scripts/ci/validate_release_metadata.sh "$TAG"

if [[ "$DO_PUSH" -eq 1 ]]; then
  # Keep validation failures on develop. Create the release branch only after
  # all generated metadata has passed its gates.
  git switch -c "${RELEASE_BRANCH}"
  RELEASE_BRANCH_CREATED=1
  trap 'status=$?; if [[ "$status" -ne 0 && "$RELEASE_BRANCH_CREATED" -eq 1 ]]; then git switch develop >/dev/null 2>&1 || true; git branch -D "$RELEASE_BRANCH" >/dev/null 2>&1 || true; fi; exit "$status"' EXIT
fi

git add README.md ARCHITECTURE.md CHANGELOG.md site/index.html site/changelog.html site/de/index.html site/da/index.html site/fr/index.html \
  site/es/index.html site/ja/index.html site/zh-Hans/index.html "Neon Vision Editor/UI/PanelsAndHelpers.swift" "$PBXPROJ_FILE" \
  docs/images/neon-vision-release-history-0.1-to-0.5.svg \
  docs/images/neon-vision-release-history-0.1-to-0.5-light.svg

if git diff --cached --quiet; then
  echo "No release metadata/docs changes to commit."
else
  COMMIT_MSG="chore(release): prepare ${TAG}"
  NVE_SKIP_BUILD_NUMBER_BUMP=1 git commit -S -m "$COMMIT_MSG"
  echo "Created commit: $COMMIT_MSG"
fi

if [[ "$DO_PUSH" -eq 1 ]]; then
  RELEASE_BRANCH_CREATED=0
  trap - EXIT
  BRANCH="$(git branch --show-current)"
  if [[ "$BRANCH" != "release/${TAG#v}" ]]; then
    echo "Release preparation expected branch release/${TAG#v} (current: ${BRANCH})." >&2
    exit 1
  fi
  git push -u origin "${BRANCH}"
  if gh pr view "${BRANCH}" --repo "${GH_REPO:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}" >/dev/null 2>&1; then
    echo "Updated existing release pull request."
  else
    gh pr create \
      --base main \
      --head "${BRANCH}" \
      --title "chore(release): prepare ${TAG}" \
      --body "Release preparation for ${TAG}."
  fi
  # Preserve the develop ancestry so main can merge back into develop without
  # replaying or duplicating the release commits.
  gh pr merge "${BRANCH}" --auto --merge --delete-branch || \
    echo "Auto-merge is unavailable; leaving the release pull request open."
else
  echo "Next steps:"
  echo "  git switch develop"
  echo "  scripts/release_prep.sh ${TAG} --push"
fi
echo "After the release PR merges, dispatch .github/workflows/release-github-only.yml with tag=${TAG} and ref=main."
