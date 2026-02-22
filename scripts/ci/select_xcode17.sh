#!/usr/bin/env bash
set -euo pipefail

get_xcode_major() {
  local version_output major
  if ! version_output="$(xcodebuild -version 2>/dev/null)"; then
    return 1
  fi
  major="$(printf '%s\n' "$version_output" | awk '/^Xcode / {split($2, v, "."); print v[1]; exit}')"
  if [[ -z "$major" || ! "$major" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  echo "$major"
}

has_xcode17_or_newer() {
  local major
  if ! major="$(get_xcode_major)"; then
    return 1
  fi
  [[ "$major" -ge 17 ]]
}

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  xcodebuild -version || true
fi

if has_xcode17_or_newer; then
  exit 0
fi

for candidate in \
  /Applications/Xcode_17.*/Contents/Developer \
  /Applications/Xcode-17.*/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer
do
  for path in $candidate; do
    if [[ -d "$path" ]]; then
      export DEVELOPER_DIR="$path"
      if has_xcode17_or_newer; then
        echo "Using DEVELOPER_DIR=$DEVELOPER_DIR"
        exit 0
      fi
    fi
  done
done

echo "Xcode 17+ is required but not available on this runner." >&2
xcodebuild -version || true
exit 1
