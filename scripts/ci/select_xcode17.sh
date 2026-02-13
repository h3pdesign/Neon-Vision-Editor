#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  xcodebuild -version
fi

if xcodebuild -version | awk '/Xcode/ {split($2, v, "."); if (v[1] >= 17) exit 0; exit 1}'; then
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
      if xcodebuild -version | awk '/Xcode/ {split($2, v, "."); if (v[1] >= 17) exit 0; exit 1}'; then
        echo "Using DEVELOPER_DIR=$DEVELOPER_DIR"
        exit 0
      fi
    fi
  done
done

echo "Xcode 17+ is required but not available on this runner." >&2
xcodebuild -version || true
exit 1
