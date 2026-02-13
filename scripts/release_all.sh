#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Run end-to-end release flow in one command.

Usage:
  scripts/release_all.sh <tag> [--date YYYY-MM-DD] [--skip-notarized] [--self-hosted] [--github-hosted] [--dry-run]

Examples:
  scripts/release_all.sh v0.4.9
  scripts/release_all.sh 0.4.9 --date 2026-02-12
  scripts/release_all.sh v0.4.9 --self-hosted
  scripts/release_all.sh v0.4.9 --github-hosted
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
DRY_RUN=0

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
    --skip-notarized)
      TRIGGER_NOTARIZED=0
      ;;
    --self-hosted)
      USE_SELF_HOSTED=1
      ;;
    --github-hosted)
      USE_SELF_HOSTED=0
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
