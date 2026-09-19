#!/usr/bin/env bash
set -euo pipefail

# Run after archive creation, before exportArchive re-signs nested code.
# Embedded frameworks are owned by Xcode's copy task, not a second build phase.
archive_path="${1:?Usage: prepare_apple_silicon_archive.sh <archive.xcarchive>}"
app="$archive_path/Products/Applications/Neon Vision Editor.app"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
[[ -d "$sparkle" ]] || { echo "Missing archived Sparkle framework" >&2; exit 1; }

binary_list="$(mktemp)"
trap 'rm -f "$binary_list"' EXIT
find "$sparkle" -type f -print0 > "$binary_list"
while IFS= read -r -d '' binary; do
  if /usr/bin/file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    architectures="$(/usr/bin/lipo -archs "$binary")"
    if [[ " $architectures " == *" x86_64 "* ]]; then
      /usr/bin/lipo -remove x86_64 "$binary" -output "$binary"
    fi
    [[ "$(/usr/bin/lipo -archs "$binary")" == "arm64" ]] || {
      echo "Unexpected archived architecture: $binary" >&2
      exit 1
    }
  fi
done < "$binary_list"
