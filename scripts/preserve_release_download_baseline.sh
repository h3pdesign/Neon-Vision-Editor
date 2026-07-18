#!/usr/bin/env bash
# Preserve cumulative downloads when a release replaces GitHub asset IDs.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <tag> <release-notes-path>" >&2
  exit 2
fi

tag="$1"
notes_path="$2"

if ! gh release view "$tag" >/dev/null 2>&1; then
  exit 0
fi

existing_body="$(gh release view "$tag" --json body --jq '.body')"
existing_baseline="$(printf '%s\n' "$existing_body" | sed -nE 's/.*nve-download-baseline:[[:space:]]*([0-9]+).*/\1/p' | head -n1)"
existing_baseline="${existing_baseline:-0}"
current_downloads="$(gh release view "$tag" --json assets --jq '[.assets[].downloadCount] | add // 0')"
baseline=$((existing_baseline + current_downloads))

if (( baseline > 0 )); then
  printf '\n<!-- nve-download-baseline: %s -->\n' "$baseline" >> "$notes_path"
fi
