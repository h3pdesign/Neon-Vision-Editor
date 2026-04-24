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

project_is_openable() {
  xcodebuild -list -project "Neon Vision Editor.xcodeproj" >/dev/null 2>&1
}

candidate_developer_dirs() {
  local app
  for app in /Applications/Xcode*.app; do
    [[ -d "$app/Contents/Developer" ]] && echo "$app/Contents/Developer"
  done
}

select_best_compatible_xcode() {
  local candidate best_path=""
  local best_version_key=""
  local version major minor patch key

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if ! version="$(DEVELOPER_DIR="$candidate" xcodebuild -version 2>/dev/null | awk '/^Xcode / {print $2; exit}')"; then
      continue
    fi
    major="${version%%.*}"
    if [[ -z "$major" || ! "$major" =~ ^[0-9]+$ || "$major" -lt 17 ]]; then
      continue
    fi
    minor="$(echo "$version" | awk -F. '{print ($2 == "" ? 0 : $2)}')"
    patch="$(echo "$version" | awk -F. '{print ($3 == "" ? 0 : $3)}')"
    key="$(printf "%03d%03d%03d" "$major" "$minor" "$patch")"
    if [[ -z "$best_version_key" || "$key" > "$best_version_key" ]]; then
      best_version_key="$key"
      best_path="$candidate"
    fi
  done < <(candidate_developer_dirs)

  [[ -n "$best_path" ]] || return 1
  export DEVELOPER_DIR="$best_path"
  has_xcode17_or_newer || return 1
  project_is_openable || return 1
  echo "Using DEVELOPER_DIR=$DEVELOPER_DIR"
}

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  xcodebuild -version || true
fi

if has_xcode17_or_newer && project_is_openable; then
  exit 0
fi

if select_best_compatible_xcode; then
  exit 0
fi

echo "A compatible Xcode 17+ installation that can open this project is not available on this runner." >&2
xcodebuild -version || true
exit 1
