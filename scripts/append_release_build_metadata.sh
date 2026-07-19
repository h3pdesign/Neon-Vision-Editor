#!/usr/bin/env bash
# Publish the signed app build so the updater can distinguish rereleases of one tag.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-path> <release-notes-path>" >&2
  exit 2
fi

app_path="$1"
notes_path="$2"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -f "$info_plist" || ! -f "$notes_path" ]]; then
  echo "Missing app Info.plist or release notes." >&2
  exit 1
fi

build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo "Invalid CFBundleVersion: $build_number" >&2
  exit 1
fi

# Replace stale metadata when a fallback reused an existing release body.
perl -0pi -e 's/\n?<!--\s*nve-build\s*:\s*\d+\s*-->\n?/\n/g' "$notes_path"
printf '\n<!-- nve-build: %s -->\n' "$build_number" >> "$notes_path"
