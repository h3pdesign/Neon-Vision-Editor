#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT="${PROJECT:-Neon Vision Editor.xcodeproj}"
SCHEME="${SCHEME:-Neon Vision Editor}"
CONFIGURATION="${CONFIGURATION:-Debug}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
LOCK_DIR="${LOCK_DIR:-/tmp/nve_xcodebuild.lock}"
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-$ROOT/.DerivedDataMatrix}"
RETRIES="${RETRIES:-2}"

usage() {
  cat <<'EOF'
Usage: scripts/ci/build_platform_matrix.sh [--keep-derived-data]

Runs build verification sequentially for:
  1) macOS
  2) iOS Simulator
  3) iPad Simulator target family

Environment overrides:
  PROJECT, SCHEME, CONFIGURATION, CODE_SIGNING_ALLOWED
  LOCK_DIR, DERIVED_DATA_ROOT, RETRIES
EOF
}

KEEP_DERIVED_DATA=0
for arg in "$@"; do
  case "$arg" in
    --keep-derived-data) KEEP_DERIVED_DATA=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

wait_for_lock() {
  local attempts=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 120 ]]; then
      echo "Timed out waiting for build lock: $LOCK_DIR" >&2
      exit 1
    fi
    sleep 1
  done
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

cleanup() {
  release_lock
  if [[ "$KEEP_DERIVED_DATA" -eq 0 ]]; then
    rm -rf "$DERIVED_DATA_ROOT"
  fi
}

trap cleanup EXIT

is_lock_error() {
  local log_file="$1"
  rg -q "database is locked|build system has crashed|unable to attach DB|unexpected service error" "$log_file"
}

run_build() {
  local name="$1"
  shift
  local platform_slug
  platform_slug="$(echo "$name" | tr '[:upper:] ' '[:lower:]_')"
  local derived_data_path="${DERIVED_DATA_ROOT}/${platform_slug}"
  local log_file="/tmp/nve_build_${platform_slug}.log"
  local attempt=0

  rm -rf "$derived_data_path"

  while :; do
    attempt=$((attempt + 1))
    echo "[$name] Attempt ${attempt}/${RETRIES}"

    if xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$derived_data_path" \
      CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
      "$@" >"$log_file" 2>&1; then
      echo "[$name] BUILD SUCCEEDED"
      return 0
    fi

    if [[ "$attempt" -lt "$RETRIES" ]] && is_lock_error "$log_file"; then
      echo "[$name] Detected lock/build-system transient. Retrying..."
      sleep 2
      rm -rf "$derived_data_path"
      continue
    fi

    echo "[$name] BUILD FAILED (see $log_file)" >&2
    tail -n 40 "$log_file" >&2 || true
    return 1
  done
}

wait_for_lock

run_build "macOS" \
  -destination "generic/platform=macOS" \
  build

run_build "iOS Simulator" \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  build

run_build "iPad Simulator" \
  -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" \
  TARGETED_DEVICE_FAMILY=2 \
  build

echo "Build matrix completed successfully."
