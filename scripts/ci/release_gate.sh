#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: scripts/ci/release_gate.sh <tag>" >&2
  exit 1
fi

if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "Running platform build matrix gate for ${TAG}..."
run_build_matrix() {
  scripts/ci/build_platform_matrix.sh
}

if ! run_build_matrix; then
  echo "Platform build matrix failed once; retrying..."
  sleep 6
  run_build_matrix
fi

echo "Running release preflight gate for ${TAG}..."
scripts/ci/release_preflight.sh "$TAG"

echo "Release gate passed for ${TAG}."
