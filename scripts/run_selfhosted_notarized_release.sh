#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Run notarized release using the self-hosted macOS workflow.

Usage:
  scripts/run_selfhosted_notarized_release.sh <tag>

Examples:
  scripts/run_selfhosted_notarized_release.sh v0.4.12
  scripts/run_selfhosted_notarized_release.sh 0.4.12
EOF
}

if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TAG="$1"
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

REPO_SLUG="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
if [[ -z "$REPO_SLUG" ]]; then
  echo "Could not resolve repository slug from gh." >&2
  exit 1
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag ${TAG} does not exist locally. Create/push tag first." >&2
  exit 1
fi

if ! git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Tag ${TAG} not found on origin. Push tag first: git push origin ${TAG}" >&2
  exit 1
fi

RUNNER_LINE="$(
  gh api "repos/${REPO_SLUG}/actions/runners" \
    --jq '.runners[] | select(.status == "online") | [.name, ([.labels[].name] | join(","))] | @tsv' \
    | awk -F '\t' 'index($2, "self-hosted") && index($2, "macOS") { print; exit }'
)"

if [[ -z "$RUNNER_LINE" ]]; then
  echo "No online self-hosted macOS runner found for ${REPO_SLUG}." >&2
  echo "Check: https://github.com/${REPO_SLUG}/settings/actions/runners" >&2
  exit 1
fi

RUNNER_NAME="$(echo "$RUNNER_LINE" | awk -F '\t' '{print $1}')"
echo "Using online runner: ${RUNNER_NAME}"

echo "Triggering self-hosted notarized workflow for ${TAG}..."
gh workflow run release-notarized-selfhosted.yml -f tag="$TAG" -f use_self_hosted=true

sleep 6
RUN_ID="$(
  gh run list --workflow release-notarized-selfhosted.yml --limit 20 \
    --json databaseId,displayTitle \
    --jq ".[] | select(.displayTitle | contains(\"${TAG}\")) | .databaseId" \
    | head -n1
)"

if [[ -z "$RUN_ID" ]]; then
  echo "Could not find self-hosted workflow run for ${TAG}." >&2
  exit 1
fi

echo "Watching run ${RUN_ID}..."
gh run watch "$RUN_ID" --exit-status

echo "Verifying published release asset payload..."
scripts/ci/verify_release_asset.sh "$TAG"

echo "Self-hosted notarized release completed for ${TAG}."
