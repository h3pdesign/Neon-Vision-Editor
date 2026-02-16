#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Run end-to-end release flow in one command.

Usage:
  scripts/release_all.sh <tag> [notarized] [--date YYYY-MM-DD] [--skip-notarized] [--self-hosted] [--github-hosted] [--enterprise-selfhosted] [--autostash] [--dry-run]

Examples:
  scripts/release_all.sh v0.4.9
  scripts/release_all.sh v0.4.9 notarized
  scripts/release_all.sh 0.4.9 --date 2026-02-12
  scripts/release_all.sh v0.4.9 --self-hosted
  scripts/release_all.sh v0.4.9 --enterprise-selfhosted
  scripts/release_all.sh v0.4.9 --github-hosted
  scripts/release_all.sh v0.4.9 --autostash
  scripts/release_all.sh v0.4.9 --dry-run

What it does:
  1) Run release preflight checks (docs + build + icon payload + tests)
  2) Prepare README/CHANGELOG docs
  3) Commit docs changes
  4) Create annotated tag
  5) Push main and tag to origin
  6) Trigger notarized release workflow (GitHub-hosted by default)
  7) Wait for notarized workflow and verify uploaded release asset payload

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
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a git repository." >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

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

if [[ "$AUTOSTASH" -eq 1 ]]; then
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
    run_line="$(gh run list \
      --workflow pre-release-ci.yml \
      --limit 50 \
      --json databaseId,status,conclusion,headSha,event,createdAt \
      --jq ".[] | select(.headSha == \"${sha}\" and .event == \"push\") | \"\(.databaseId)\t\(.status)\t\(.conclusion // \"\")\"" | head -n1)"

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

if [[ "$AUTOSTASH" -eq 0 && -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit/stash changes first, or rerun with --autostash." >&2
  exit 1
fi

echo "Verifying release docs are up to date for ${TAG}..."
docs_check_cmd=(scripts/prepare_release_docs.py "$TAG" --check)
if [[ ${#DATE_ARG[@]} -gt 0 ]]; then
  docs_check_cmd+=("${DATE_ARG[@]}")
fi
"${docs_check_cmd[@]}"

echo "Running release preflight for ${TAG}..."
scripts/ci/release_preflight.sh "$TAG"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry-run requested. Preflight completed; no commits/tags/workflows were created."
  exit 0
fi

echo "Running release prep for ${TAG}..."
prep_cmd=(scripts/release_prep.sh "$TAG")
if [[ ${#DATE_ARG[@]} -gt 0 ]]; then
  prep_cmd+=("${DATE_ARG[@]}")
fi
prep_cmd+=(--push)
"${prep_cmd[@]}"

echo "Tag push completed."

if [[ "$TRIGGER_NOTARIZED" -eq 1 ]]; then
  RELEASE_SHA="$(git rev-parse HEAD)"
  wait_for_pre_release_ci "$RELEASE_SHA"

  echo "Triggering notarized workflow for ${TAG}..."
  if [[ "$ENTERPRISE_SELF_HOSTED" -eq 1 ]]; then
    echo "Enterprise self-hosted mode enabled (expects self-hosted runner labels and GH_HOST if required)."
  fi
  if [[ "$USE_SELF_HOSTED" -eq 1 ]]; then
    gh workflow run release-notarized-selfhosted.yml -f tag="$TAG" -f use_self_hosted=true
    WORKFLOW_NAME="release-notarized-selfhosted.yml"
    echo "Triggered: ${WORKFLOW_NAME} (tag=${TAG}, use_self_hosted=true)"
  else
    gh workflow run release-notarized.yml -f tag="$TAG"
    WORKFLOW_NAME="release-notarized.yml"
    echo "Triggered: ${WORKFLOW_NAME} (tag=${TAG})"
  fi

  echo "Waiting for ${WORKFLOW_NAME} run..."
  sleep 6
  RUN_ID="$(gh run list --workflow "$WORKFLOW_NAME" --limit 20 --json databaseId,displayTitle --jq ".[] | select(.displayTitle | contains(\"${TAG}\")) | .databaseId" | head -n1)"
  if [[ -z "$RUN_ID" ]]; then
    echo "Could not find workflow run for ${TAG}." >&2
    exit 1
  fi
  gh run watch "$RUN_ID"
  scripts/ci/verify_release_asset.sh "$TAG"
fi

echo
echo "Done."
echo "Check runs:"
echo "  gh run list --workflow pre-release-ci.yml --limit 5"
echo "  gh run list --workflow release-dry-run.yml --limit 5"
echo "  gh run list --workflow release-notarized.yml --limit 5"
echo "  gh run list --workflow release-notarized-selfhosted.yml --limit 5"
