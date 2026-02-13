#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Validate release readiness without creating a tag or pushing.

Usage:
  scripts/release_dry_run.sh <tag>

Example:
  scripts/release_dry_run.sh v0.4.9
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

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_WORKTREE="/tmp/nve_release_dry_run_${TAG}_$$"

git -C "$ROOT" worktree add "$TMP_WORKTREE" HEAD >/dev/null
cleanup() {
  git -C "$ROOT" worktree remove "$TMP_WORKTREE" --force >/dev/null 2>&1 || true
}
trap cleanup EXIT

(
  cd "$TMP_WORKTREE"
  scripts/ci/release_preflight.sh "$TAG"
  scripts/release_prep.sh "$TAG"
)

echo "Dry-run finished. Release content for ${TAG} validated in temporary worktree."
