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
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-$ROOT/.DerivedDataMatrix}"
export DERIVED_DATA_ROOT
trap 'rm -rf "$DERIVED_DATA_ROOT"' EXIT
scripts/ci/build_platform_matrix.sh --keep-derived-data

echo "Running release preflight gate for ${TAG}..."
export NVE_RELEASE_DERIVED_DATA_PATH="$DERIVED_DATA_ROOT/macos"
scripts/ci/release_preflight.sh "$TAG"

echo "Release gate passed for ${TAG}."
