#!/usr/bin/env bash
set -euo pipefail

PROJECT_FILE="${1:-Neon Vision Editor.xcodeproj/project.pbxproj}"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "Project file not found: $PROJECT_FILE" >&2
  exit 2
fi

current="$(awk '/CURRENT_PROJECT_VERSION = [0-9]+;/{gsub(/[^0-9]/, "", $0); print; exit}' "$PROJECT_FILE")"
if [[ -z "${current:-}" ]]; then
  echo "Could not find CURRENT_PROJECT_VERSION in $PROJECT_FILE" >&2
  exit 2
fi

next=$((current + 1))

perl -0pi -e "s/CURRENT_PROJECT_VERSION = $current;/CURRENT_PROJECT_VERSION = $next;/g" "$PROJECT_FILE"

echo "Bumped CURRENT_PROJECT_VERSION: $current -> $next"
