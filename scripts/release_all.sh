#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Run end-to-end release flow in one command.

Usage:
  scripts/release_all.sh <tag> [notarized] [--date YYYY-MM-DD] [--skip-notarized] [--self-hosted] [--github-hosted] [--enterprise-selfhosted] [--autostash] [--dry-run] [--from <step>] [--to <step>] [--retag] [--resume-auto] [--skip-homebrew-wait] [--no-auto-approve-environment] [--replace-assets-from-app <path>]

Examples:
  scripts/release_all.sh v0.8.9
  scripts/release_all.sh v0.8.9 notarized
  scripts/release_all.sh 0.8.9 --date 2026-07-18
  scripts/release_all.sh v0.8.9 --self-hosted
  scripts/release_all.sh v0.8.9 --enterprise-selfhosted
  scripts/release_all.sh v0.8.9 --github-hosted
  scripts/release_all.sh v0.8.9 --autostash
  scripts/release_all.sh v0.8.9 --dry-run
  scripts/release_all.sh v0.8.9 --from notarize
  scripts/release_all.sh v0.8.9 --to preflight
  scripts/release_all.sh v0.8.9 --retag
  scripts/release_all.sh v0.8.9 --resume-auto
  scripts/release_all.sh v0.8.9 --skip-homebrew-wait
  scripts/release_all.sh v0.8.9 --no-auto-approve-environment
  scripts/release_all.sh v0.8.9 --replace-assets-from-app "/Users/h3p/Downloads/Neon Vision Editor.app"
  scripts/release_all.sh v0.8.9 notarized --retag

What it does:
  1) Synchronize local main with origin/main before release checks and again before prep/tagging
     so separately generated download-metrics commits are included
  2) Run release preflight checks (docs + build + icon payload + tests)
  3) Prepare README/CHANGELOG docs
  4) Commit docs changes
  5) Create annotated tag
  6) Push main and tag to origin
  7) Trigger notarized release workflow (GitHub-hosted by default) and approve its
     protected release environment when the current user is an authorized reviewer
  8) Wait for notarized workflow and verify uploaded release asset payload

Asset replacement mode:
  --replace-assets-from-app packages an existing notarized Neon Vision Editor.app as
  Neon.Vision.Editor.app.zip and Neon.Vision.Editor.app.dmg, uploads both to the existing
  release with --clobber, verifies the uploaded assets, and skips all preflight/docs/tag steps.

EOF
}

if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
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
TRIGGER_NOTARIZED=1
USE_SELF_HOSTED=0
ENTERPRISE_SELF_HOSTED=0
AUTOSTASH=0
DRY_RUN=0
START_FROM="docs"
STOP_AFTER="notarize"
STOP_AFTER_SET=0
START_FROM_SET=0
RETAG=0
RESUME_AUTO=0
WAIT_FOR_HOMEBREW_TAP=1
AUTO_APPROVE_RELEASE_ENVIRONMENT=1
REPLACE_ASSETS_APP=""

step_index() {
  case "$1" in
    docs) echo 1 ;;
    preflight) echo 2 ;;
    prep) echo 3 ;;
    notarize) echo 4 ;;
    *)
      echo "Unknown step: $1. Valid steps: docs, preflight, prep, notarize." >&2
      return 1
      ;;
  esac
}

step_enabled() {
  local step="$1"
  local start_idx stop_idx current_idx
  start_idx="$(step_index "$START_FROM")"
  stop_idx="$(step_index "$STOP_AFTER")"
  current_idx="$(step_index "$step")"
  (( current_idx >= start_idx && current_idx <= stop_idx ))
}

gh_retry() {
  local attempts="${GH_RETRY_ATTEMPTS:-8}"
  local base_sleep="${GH_RETRY_BASE_SLEEP:-3}"
  local n=1

  while true; do
    if "$@"; then
      return 0
    fi
    if (( n >= attempts )); then
      return 1
    fi
    echo "GitHub command failed; retrying in $((base_sleep * n))s (${n}/${attempts})..." >&2
    sleep $((base_sleep * n))
    n=$((n + 1))
  done
}

retry_cmd() {
  local attempts="${RETRY_ATTEMPTS:-3}"
  local sleep_seconds="${RETRY_SLEEP_SECONDS:-6}"
  local n=1

  while true; do
    if "$@"; then
      return 0
    fi
    if (( n >= attempts )); then
      return 1
    fi
    echo "Command failed; retrying (${n}/${attempts})..."
    sleep "$sleep_seconds"
    n=$((n + 1))
  done
}

sync_main_with_origin() {
  local reason="${1:-release prep}"
  local current_branch local_main_sha origin_main_sha has_release_metadata_changes=0

  current_branch="$(git branch --show-current)"
  if [[ "$current_branch" != "main" ]]; then
    echo "Release prep must run from main (current: ${current_branch})." >&2
    exit 1
  fi

  echo "Synchronizing main with origin/main before ${reason}..."
  retry_cmd git fetch origin main >/dev/null
  local_main_sha="$(git rev-parse HEAD)"
  origin_main_sha="$(git rev-parse origin/main)"

  if [[ "$local_main_sha" == "$origin_main_sha" ]]; then
    echo "Local main is aligned with origin/main."
    return 0
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    if working_tree_has_only_release_metadata_changes; then
      has_release_metadata_changes=1
    else
      echo "Local main is not aligned with origin/main, and the working tree contains non-release changes." >&2
      echo "  local main:  ${local_main_sha}" >&2
      echo "  origin/main: ${origin_main_sha}" >&2
      exit 1
    fi
  fi

  if git merge-base --is-ancestor HEAD origin/main; then
    if [[ "$has_release_metadata_changes" -eq 1 ]]; then
      echo "Local main is behind origin/main. Fast-forwarding while preserving release metadata changes..."
      git rebase --autostash origin/main
    else
      echo "Local main is behind origin/main. Fast-forwarding..."
      git merge --ff-only origin/main
    fi
    return 0
  fi

  if git merge-base --is-ancestor origin/main HEAD; then
    echo "Local main already contains origin/main; continuing."
    return 0
  fi

  echo "Local main and origin/main both moved. Refusing to create an implicit release merge." >&2
  echo "Rebase the local commits onto origin/main, then rerun the release." >&2
  echo "  local main:  ${local_main_sha}" >&2
  echo "  origin/main: ${origin_main_sha}" >&2
  exit 1
}

is_allowed_release_dirty_path() {
  local path="$1"
  case "$path" in
    CHANGELOG.md|README.md|index.html|\
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

release_exists_and_is_published() {
  local tag_name="$1"
  local is_draft

  if ! gh_retry gh release view "$tag_name" >/dev/null 2>&1; then
    return 1
  fi

  is_draft="$(gh_retry gh release view "$tag_name" --json isDraft --jq '.isDraft')"
  [[ "$is_draft" != "true" ]]
}

print_release_state_summary() {
  local label="$1"
  local current_branch head_sha origin_main_sha local_tag_state remote_tag_state dirty_count

  current_branch="$(git branch --show-current)"
  head_sha="$(git rev-parse --short HEAD)"
  origin_main_sha="$(git rev-parse --short origin/main 2>/dev/null || echo "unknown")"
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    local_tag_state="$(git rev-parse --short "${TAG}^{commit}")"
  else
    local_tag_state="missing"
  fi
  if retry_cmd git ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null | grep -q "refs/tags/${TAG}"; then
    remote_tag_state="present"
  else
    remote_tag_state="missing"
  fi
  dirty_count="$(git status --porcelain | wc -l | tr -d ' ')"

  echo
  echo "Release state (${label}):"
  echo "  tag: ${TAG}"
  echo "  branch: ${current_branch}"
  echo "  HEAD: ${head_sha}"
  echo "  origin/main: ${origin_main_sha}"
  echo "  local tag: ${local_tag_state}"
  echo "  remote tag: ${remote_tag_state}"
  echo "  dirty paths: ${dirty_count}"
  echo "  README metrics: maintained separately"
}

while [[ "${1:-}" != "" ]]; do
  case "$1" in
    notarized|--notarized)
      TRIGGER_NOTARIZED=1
      ;;
    --date)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "Missing value for --date" >&2
        exit 1
      fi
      DATE_ARG=(--date "$1")
      ;;
    --skip-notarized)
      TRIGGER_NOTARIZED=0
      ;;
    --self-hosted)
      USE_SELF_HOSTED=1
      ;;
    --github-hosted)
      USE_SELF_HOSTED=0
      ;;
    --enterprise-selfhosted)
      ENTERPRISE_SELF_HOSTED=1
      USE_SELF_HOSTED=1
      ;;
    --autostash)
      AUTOSTASH=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --from)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "Missing value for --from" >&2
        exit 1
      fi
      START_FROM="$1"
      START_FROM_SET=1
      step_index "$START_FROM" >/dev/null
      ;;
    --to)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "Missing value for --to" >&2
        exit 1
      fi
      STOP_AFTER="$1"
      STOP_AFTER_SET=1
      step_index "$STOP_AFTER" >/dev/null
      ;;
    --retag)
      RETAG=1
      ;;
    --resume-auto)
      RESUME_AUTO=1
      ;;
    --skip-homebrew-wait)
      WAIT_FOR_HOMEBREW_TAP=0
      ;;
    --no-auto-approve-environment)
      AUTO_APPROVE_RELEASE_ENVIRONMENT=0
      ;;
    --replace-assets-from-app)
      shift
      if [[ -z "${1:-}" ]]; then
        echo "Missing value for --replace-assets-from-app" >&2
        exit 1
      fi
      REPLACE_ASSETS_APP="$1"
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

if [[ -n "$REPLACE_ASSETS_APP" ]]; then
  scripts/replace_release_assets.sh "$TAG" --app "$REPLACE_ASSETS_APP"
  exit 0
fi

if [[ "$TRIGGER_NOTARIZED" -eq 0 && "$STOP_AFTER_SET" -eq 0 ]]; then
  STOP_AFTER="prep"
fi

if [[ "$STOP_AFTER" != "notarize" ]]; then
  TRIGGER_NOTARIZED=0
fi

if [[ "$RESUME_AUTO" -eq 1 ]]; then
  local_tag_exists=0
  remote_tag_exists=0
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    local_tag_exists=1
  fi
  if retry_cmd git ls-remote --tags origin "refs/tags/${TAG}" 2>/dev/null | grep -q "refs/tags/${TAG}$"; then
    remote_tag_exists=1
  fi
  if [[ "$local_tag_exists" -eq 0 && "$remote_tag_exists" -eq 1 ]]; then
    git fetch origin "refs/tags/${TAG}:refs/tags/${TAG}" >/dev/null 2>&1 || true
    if git rev-parse "$TAG" >/dev/null 2>&1; then
      local_tag_exists=1
    fi
  fi
  if [[ "$START_FROM_SET" -eq 0 ]]; then
    if [[ "$local_tag_exists" -eq 1 && "$remote_tag_exists" -eq 1 && "$TRIGGER_NOTARIZED" -eq 1 ]]; then
      START_FROM="notarize"
    elif [[ "$local_tag_exists" -eq 1 ]]; then
      START_FROM="prep"
    else
      START_FROM="docs"
    fi
  fi
  if [[ "$local_tag_exists" -eq 1 && "$remote_tag_exists" -eq 0 ]]; then
    CURRENT_BRANCH="$(git branch --show-current)"
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
      echo "Local tag ${TAG} exists but origin tag is missing, and current branch is ${CURRENT_BRANCH}." >&2
      echo "Switch to main and push the tag first:" >&2
      echo "  git checkout main && git push origin ${TAG}" >&2
      exit 1
    fi
  fi
  echo "Resume-auto selected: from=${START_FROM} to=${STOP_AFTER} (local_tag=${local_tag_exists}, remote_tag=${remote_tag_exists})"
fi

if (( "$(step_index "$START_FROM")" > "$(step_index "$STOP_AFTER")" )); then
  echo "--from ${START_FROM} is after --to ${STOP_AFTER}." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a git repository." >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REPO_SLUG="$(gh_retry gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
if [[ -z "$REPO_SLUG" ]]; then
  echo "Could not resolve repository slug from gh." >&2
  exit 1
fi

AUTO_STASHED=0
cleanup_autostash() {
  if [[ "$AUTO_STASHED" -eq 1 ]]; then
    if git stash pop --index >/dev/null 2>&1; then
      echo "Restored stashed working tree changes."
    else
      echo "Auto-stash restore had conflicts. Changes remain in stash list; resolve manually." >&2
    fi
  fi
}
trap cleanup_autostash EXIT

REQUIRES_CLEAN_TREE=0
if step_enabled prep; then
  REQUIRES_CLEAN_TREE=1
fi

if [[ "$AUTOSTASH" -eq 1 && "$REQUIRES_CLEAN_TREE" -eq 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    STASH_MSG="release_all autostash ${TAG} $(date +%Y-%m-%dT%H:%M:%S)"
    git stash push --include-untracked -m "$STASH_MSG" >/dev/null
    AUTO_STASHED=1
    echo "Auto-stashed dirty working tree before release."
  fi
fi

wait_for_pre_release_ci() {
  local sha="$1"
  local timeout_seconds=1800
  local interval_seconds=15
  local elapsed=0

  echo "Waiting for Pre-release CI on ${sha}..."
  while (( elapsed <= timeout_seconds )); do
    local run_line
    run_line="$(gh_retry gh run list \
      --workflow pre-release-ci.yml \
      --limit 50 \
      --json databaseId,status,conclusion,headSha,event,createdAt \
      --jq ".[] | select(.headSha == \"${sha}\" and .event == \"push\") | \"\(.databaseId)\t\(.status)\t\(.conclusion // \"\")\"" | head -n1 || true)"

    if [[ -n "$run_line" ]]; then
      local run_id run_status run_conclusion
      run_id="$(echo "$run_line" | awk -F '\t' '{print $1}')"
      run_status="$(echo "$run_line" | awk -F '\t' '{print $2}')"
      run_conclusion="$(echo "$run_line" | awk -F '\t' '{print $3}')"

      echo "Pre-release CI run ${run_id}: status=${run_status} conclusion=${run_conclusion:-pending}"
      if [[ "$run_status" == "completed" ]]; then
        if [[ "$run_conclusion" == "success" ]]; then
          echo "Pre-release CI passed."
          return 0
        fi
        echo "Pre-release CI failed for ${sha}. Not starting notarized release." >&2
        return 1
      fi
    else
      echo "Pre-release CI run for ${sha} not visible yet; retrying..."
    fi

    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  echo "Timed out waiting for Pre-release CI on ${sha}. Not starting notarized release." >&2
  return 1
}

wait_for_homebrew_tap_update() {
  local since="$1"
  local timeout_seconds=1800
  local interval_seconds=15
  local elapsed=0

  echo "Waiting for homebrew-tap run (since ${since})..."
  while (( elapsed <= timeout_seconds )); do
    local tap_line
    tap_line="$(gh_retry gh run list -R h3pdesign/homebrew-tap \
      --workflow update-cask.yml \
      --event repository_dispatch \
      --limit 30 \
      --json databaseId,status,conclusion,displayTitle,createdAt \
      --jq ".[] | select(.displayTitle == \"notarized_release\" and .createdAt >= \"${since}\") | \"\(.databaseId)\t\(.status)\t\(.conclusion // \"\")\"" | head -n1 || true)"

    if [[ -n "$tap_line" ]]; then
      local run_id run_status run_conclusion
      run_id="$(echo "$tap_line" | awk -F '\t' '{print $1}')"
      run_status="$(echo "$tap_line" | awk -F '\t' '{print $2}')"
      run_conclusion="$(echo "$tap_line" | awk -F '\t' '{print $3}')"
      echo "homebrew-tap run ${run_id}: status=${run_status} conclusion=${run_conclusion:-pending}"
      if [[ "$run_status" == "completed" ]]; then
        if [[ "$run_conclusion" == "success" ]]; then
          echo "homebrew-tap update passed."
          return 0
        fi
        echo "homebrew-tap update failed (${run_id})." >&2
        return 1
      fi
    else
      echo "homebrew-tap run not visible yet; retrying..."
    fi

    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  echo "Timed out waiting for homebrew-tap update run." >&2
  return 1
}

approve_pending_release_environment() {
  local run_id="$1"
  local environment_ids environment_id

  if [[ "$AUTO_APPROVE_RELEASE_ENVIRONMENT" -eq 0 ]]; then
    return 0
  fi

  environment_ids="$(
    gh_retry gh api "repos/${REPO_SLUG}/actions/runs/${run_id}/pending_deployments" \
      --jq '.[] | select(.current_user_can_approve == true) | .environment.id'
  )" || return 1

  [[ -n "$environment_ids" ]] || return 0

  while IFS= read -r environment_id; do
    [[ -n "$environment_id" ]] || continue
    echo "Approving protected release environment ${environment_id} for workflow run ${run_id}..."
    gh_retry gh api -X POST "repos/${REPO_SLUG}/actions/runs/${run_id}/pending_deployments" \
      -F "environment_ids[]=${environment_id}" \
      -f state=approved \
      -f comment="Release ${TAG} approved after local release validation."
  done <<< "$environment_ids"
}

wait_for_workflow_run() {
  local run_id="$1"
  local timeout_seconds="${GH_WORKFLOW_TIMEOUT_SECONDS:-14400}"
  local interval_seconds="${GH_WORKFLOW_POLL_SECONDS:-15}"
  local elapsed=0
  local last_state=""

  while (( elapsed <= timeout_seconds )); do
    approve_pending_release_environment "$run_id" || \
      echo "Could not review pending release environments yet; continuing to monitor." >&2

    local run_state status conclusion
    if ! run_state="$(
      gh_retry gh run view "$run_id" \
        --json status,conclusion \
        --jq '[.status, (.conclusion // "")] | join("|")'
    )"; then
      echo "Could not read workflow run ${run_id}; retrying without redispatching." >&2
      sleep "$interval_seconds"
      elapsed=$((elapsed + interval_seconds))
      continue
    fi

    status="${run_state%%|*}"
    conclusion="${run_state#*|}"
    if [[ "$run_state" != "$last_state" ]]; then
      echo "Workflow run ${run_id}: status=${status} conclusion=${conclusion:-pending}"
      last_state="$run_state"
    fi

    if [[ "$status" == "completed" ]]; then
      [[ "$conclusion" == "success" ]]
      return
    fi

    sleep "$interval_seconds"
    elapsed=$((elapsed + interval_seconds))
  done

  echo "Timed out waiting for workflow run ${run_id}." >&2
  return 1
}

assert_workflow_exists() {
  local workflow_name="$1"
  if ! gh_retry gh workflow view "$workflow_name" >/dev/null 2>&1; then
    echo "Workflow ${workflow_name} is not available in this repository." >&2
    exit 1
  fi
}

required_secrets_available() {
  local names
  names="$(gh_retry gh api "repos/${REPO_SLUG}/actions/secrets" --jq '.secrets[].name' 2>/dev/null || true)"
  [[ -n "$names" ]] || return 1

  local missing=0
  local secret_name
  for secret_name in "$@"; do
    if ! printf '%s\n' "$names" | grep -Fxq "$secret_name"; then
      echo "Missing required GitHub Actions secret: ${secret_name}" >&2
      missing=1
    fi
  done

  [[ "$missing" -eq 0 ]]
}

assert_required_actions_secrets() {
  local required=(
    MACOS_CERT_P12
    MACOS_CERT_PASSWORD
    KEYCHAIN_PASSWORD
    MACOS_APP_PROVISIONING_PROFILE
    MACOS_SHARE_EXTENSION_PROVISIONING_PROFILE
    APPLE_TEAM_ID
    APPLE_ID
    APPLE_APP_SPECIFIC_PASSWORD
    NVE_SPARKLE_PRIVATE_KEY
    METRIC_TOKEN
    METRICS_SIGNING_SSH_KEY
  )

  if [[ "$WAIT_FOR_HOMEBREW_TAP" -eq 1 ]]; then
    required+=(TAP_BOT_TOKEN)
  fi

  if ! required_secrets_available "${required[@]}"; then
    echo "Required release secrets are missing or could not be verified. Not starting notarized release." >&2
    echo "Check: https://github.com/${REPO_SLUG}/settings/secrets/actions" >&2
    exit 1
  fi
}

assert_online_self_hosted_macos_runner() {
  local runner_line
  runner_line="$(
    gh_retry gh api "repos/${REPO_SLUG}/actions/runners" \
      --jq '.runners[] | select(.status == "online") | [.name, ([.labels[].name] | join(","))] | @tsv' \
      | awk -F '\t' 'index($2, "self-hosted") && index($2, "macOS") { print; exit }'
  )"

  if [[ -z "$runner_line" ]]; then
    echo "No online self-hosted macOS runner found for ${REPO_SLUG}." >&2
    echo "Check: https://github.com/${REPO_SLUG}/settings/actions/runners" >&2
    exit 1
  fi
  echo "Using online runner: $(echo "$runner_line" | awk -F '\t' '{print $1}')"
}

if [[ "$REQUIRES_CLEAN_TREE" -eq 1 && "$AUTOSTASH" -eq 0 && -n "$(git status --porcelain)" ]]; then
  if step_enabled prep && working_tree_has_only_release_metadata_changes; then
    echo "Working tree has only release metadata changes; continuing without --autostash."
  else
    echo "Working tree is not clean. Commit/stash changes first, or rerun with --autostash." >&2
    exit 1
  fi
fi

if step_enabled prep; then
  sync_main_with_origin "release checks"
fi
print_release_state_summary "before docs/preflight"

echo "README download metrics are maintained separately; release_all will re-sync main before tagging to include any new metrics commits."

if step_enabled docs; then
  echo "Verifying release docs are up to date for ${TAG}..."
  docs_check_cmd=(scripts/prepare_release_docs.py "$TAG" --check)
  if [[ ${#DATE_ARG[@]} -gt 0 ]]; then
    docs_check_cmd+=("${DATE_ARG[@]}")
  fi
  "${docs_check_cmd[@]}"
fi

if step_enabled preflight; then
  echo "Running release preflight for ${TAG}..."
  scripts/ci/release_gate.sh "$TAG"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry-run requested. Preflight completed; no commits/tags/workflows were created."
  exit 0
fi

assert_tag_matches_head() {
  local tag_name="$1"
  local tag_sha head_sha
  tag_sha="$(git rev-parse "${tag_name}^{commit}")"
  head_sha="$(git rev-parse HEAD)"
  if [[ "$tag_sha" != "$head_sha" ]]; then
    echo "Tag ${tag_name} exists but does not point to HEAD." >&2
    echo "  tag:  ${tag_sha}" >&2
    echo "  head: ${head_sha}" >&2
    echo "Use --retag to repoint the tag before notarized release." >&2
    exit 1
  fi
}

assert_remote_tag_matches_head() {
  local tag_name="$1"
  local remote_sha head_sha
  remote_sha="$(retry_cmd git ls-remote --tags origin "refs/tags/${tag_name}^{}" | awk '{print $1}' | head -n1)"
  if [[ -z "$remote_sha" ]]; then
    remote_sha="$(retry_cmd git ls-remote --tags origin "refs/tags/${tag_name}" | awk '{print $1}' | head -n1)"
  fi
  if [[ -z "$remote_sha" ]]; then
    return 0
  fi
  head_sha="$(git rev-parse HEAD)"
  if [[ "$remote_sha" != "$head_sha" ]]; then
    echo "Remote tag ${tag_name} exists but does not point to HEAD." >&2
    echo "  tag:  ${remote_sha}" >&2
    echo "  head: ${head_sha}" >&2
    echo "Use --retag to repoint the tag before notarized release." >&2
    exit 1
  fi
}

if step_enabled prep; then
  sync_main_with_origin "release prep commit and tag (including external download-metrics commits)"
  print_release_state_summary "before release prep/tag"

  if git rev-parse "$TAG" >/dev/null 2>&1; then
    if [[ "$RETAG" -eq 1 ]]; then
      echo "Retag requested. Deleting existing ${TAG} locally and on origin (if present)..."
      git tag -d "$TAG" >/dev/null 2>&1 || true
      git push origin ":refs/tags/${TAG}" >/dev/null 2>&1 || true
    else
      assert_tag_matches_head "$TAG"
      assert_remote_tag_matches_head "$TAG"
      echo "Tag ${TAG} already exists. Skipping release prep. Use --retag to recreate it."
      if [[ "$(git branch --show-current)" == "main" ]]; then
        git push origin main
        git push origin "$TAG"
      fi
    fi
  fi

  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Running release prep for ${TAG}..."
    prep_cmd=(scripts/release_prep.sh "$TAG")
    if [[ ${#DATE_ARG[@]} -gt 0 ]]; then
      prep_cmd+=("${DATE_ARG[@]}")
    fi
    prep_cmd+=(--push)
    "${prep_cmd[@]}"
    echo "Tag push completed."
  fi
fi

if [[ "$TRIGGER_NOTARIZED" -eq 1 ]] && step_enabled notarize; then
  print_release_state_summary "before notarized workflow"

  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag ${TAG} does not exist. Run prep first or use --from prep." >&2
    exit 1
  fi
  RELEASE_SHA="$(git rev-parse "${TAG}^{commit}")"
  if ! git verify-commit "$RELEASE_SHA"; then
    echo "Release tag ${TAG} does not point to a locally verifiable signed commit." >&2
    exit 1
  fi
  REMOTE_TAG_SHA="$(retry_cmd git ls-remote --tags origin "refs/tags/${TAG}^{}" | awk '{print $1}' | head -n1)"
  if [[ -z "$REMOTE_TAG_SHA" ]]; then
    REMOTE_TAG_SHA="$(retry_cmd git ls-remote --tags origin "refs/tags/${TAG}" | awk '{print $1}' | head -n1)"
  fi
  if [[ -z "$REMOTE_TAG_SHA" ]]; then
    echo "Remote tag ${TAG} is missing on origin. Not starting notarized release." >&2
    exit 1
  fi
  if [[ "$REMOTE_TAG_SHA" != "$RELEASE_SHA" ]]; then
    echo "Remote tag ${TAG} does not match the local release tag. Not starting GitHub release." >&2
    echo "  local:  ${RELEASE_SHA}" >&2
    echo "  remote: ${REMOTE_TAG_SHA}" >&2
    exit 1
  fi

  if release_exists_and_is_published "$TAG" && retry_cmd scripts/ci/verify_release_asset.sh "$TAG"; then
    echo "Release ${TAG} is already published and its assets verify. Skipping GitHub release workflow dispatch."
    exit 0
  fi

  if rg -q '^[[:space:]]*push:' .github/workflows/pre-release-ci.yml; then
    wait_for_pre_release_ci "$RELEASE_SHA"
  else
    echo "Skipping Pre-release CI wait: pre-release-ci.yml does not run on pushes."
  fi

  echo "Triggering GitHub release workflow for ${TAG}..."
  if [[ "$ENTERPRISE_SELF_HOSTED" -eq 1 ]]; then
    echo "Enterprise self-hosted mode enabled (expects self-hosted runner labels and GH_HOST if required)."
  fi
  if [[ "$USE_SELF_HOSTED" -eq 1 ]]; then
    assert_workflow_exists "release-notarized-selfhosted.yml"
    assert_online_self_hosted_macos_runner
    assert_required_actions_secrets
    WORKFLOW_NAME="release-notarized-selfhosted.yml"
    WORKFLOW_DISPATCH_CMD=(gh workflow run "$WORKFLOW_NAME" -f tag="$TAG" -f use_self_hosted=true)
  else
    assert_workflow_exists "release-github-only.yml"
    assert_required_actions_secrets
    WORKFLOW_NAME="release-github-only.yml"
    WORKFLOW_DISPATCH_CMD=(gh workflow run "$WORKFLOW_NAME" -f tag="$TAG" -f ref=main)
  fi

  echo "Dispatching ${WORKFLOW_NAME} for ${TAG}..."
  DISPATCHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  DISPATCH_UNCERTAIN=0
  if ! "${WORKFLOW_DISPATCH_CMD[@]}"; then
    DISPATCH_UNCERTAIN=1
    echo "Workflow dispatch response failed; checking for a created run before retrying." >&2
  else
    echo "Workflow dispatch request accepted."
  fi

  echo "Waiting for ${WORKFLOW_NAME} run..."
  RUN_ID=""
  for dispatch_attempt in 1 2; do
    if [[ "$dispatch_attempt" -eq 2 ]]; then
      if [[ "$DISPATCH_UNCERTAIN" -eq 0 ]]; then
        break
      fi
      echo "No run appeared after the failed response; retrying the dispatch once."
      "${WORKFLOW_DISPATCH_CMD[@]}"
    fi

    for _ in {1..20}; do
      sleep 6
      RUN_ID="$(
        gh_retry gh run list \
          --workflow "$WORKFLOW_NAME" \
          --limit 30 \
          --json databaseId,displayTitle,createdAt \
          --jq "[.[] | select((.displayTitle | contains(\"${TAG}\")) and .createdAt >= \"${DISPATCHED_AT}\")][0].databaseId // empty" || true
      )"
      if [[ -n "$RUN_ID" ]]; then
        break
      fi
    done
    [[ -n "$RUN_ID" ]] && break
  done
  if [[ -z "$RUN_ID" ]]; then
    echo "Could not find workflow run for ${TAG}." >&2
    exit 1
  fi
  if ! wait_for_workflow_run "$RUN_ID"; then
    echo "Workflow run ${RUN_ID} failed. Showing failed job logs..." >&2
    gh_retry gh run view "$RUN_ID" --log-failed || true
    exit 1
  fi
  if ! retry_cmd scripts/ci/verify_release_asset.sh "$TAG"; then
    echo "Release asset verification failed for ${TAG} after retries." >&2
    exit 1
  fi
  if [[ "$WAIT_FOR_HOMEBREW_TAP" -eq 1 ]]; then
    wait_for_homebrew_tap_update "$DISPATCHED_AT"
  else
    echo "Skipping homebrew-tap wait (--skip-homebrew-wait)."
  fi
fi

echo
echo "Done."
echo "Check runs:"
echo "  gh run list --workflow pre-release-ci.yml --limit 5"
echo "  gh run list --workflow release-dry-run.yml --limit 5"
echo "  gh run list --workflow release-github-only.yml --limit 5"
echo "  gh run list --workflow release-notarized-selfhosted.yml --limit 5"
