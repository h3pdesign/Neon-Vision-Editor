#!/usr/bin/env bash
set -euo pipefail

allow_beta_toolchain=0
max_upgrade_marker=2600
project="Neon Vision Editor.xcodeproj"
app_store_scheme="Neon Vision Editor AppStore"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-beta-toolchain)
      allow_beta_toolchain=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--allow-beta-toolchain]" >&2
      exit 64
      ;;
  esac
  shift
done

cd "$(dirname "$0")/../.."

fail() {
  echo "error: $*" >&2
  exit 1
}

scripts/ci/storekit_configuration_audit.sh

# Select a full Xcode installation even when the host's xcode-select currently
# points at CommandLineTools. The shared selector prefers the newest stable
# Xcode 17+ installation and rejects beta Xcode unless explicitly allowed for
# local metadata checks.
if [[ "$allow_beta_toolchain" -eq 1 ]]; then
  export NVE_ALLOW_BETA_XCODE=1
fi
if ! source scripts/ci/select_xcode17.sh; then
  fail "A compatible public Xcode 17+ installation that can open this project is not available."
fi

active_developer_dir="$DEVELOPER_DIR"
if [[ "$active_developer_dir" == *Xcode-beta.app/* ]]; then
  echo "warning: allowing beta toolchain for local metadata checks only; do not upload this archive to App Store Connect." >&2
fi

xcode_version="$(xcodebuild -version 2>/dev/null || true)"
printf '%s\n' "$xcode_version"
[[ "$xcode_version" == Xcode* ]] || fail "xcodebuild is not available from a full Xcode installation."

major="$(printf '%s\n' "$xcode_version" | awk '/^Xcode / {split($2, v, "."); print v[1]; exit}')"
[[ "$major" =~ ^[0-9]+$ ]] || fail "Unable to read Xcode major version."
[[ "$major" -ge 17 ]] || fail "Xcode 17 or newer is required."

if ! xcodebuild -list -project "$project" >/tmp/nve_xcode_cloud_preflight_schemes.txt; then
  fail "Xcode cannot open $project."
fi

if ! grep -qx "        $app_store_scheme" /tmp/nve_xcode_cloud_preflight_schemes.txt; then
  fail "Shared App Store scheme '$app_store_scheme' was not found."
fi
rm -f /tmp/nve_xcode_cloud_preflight_schemes.txt

project_marker="$(awk '/LastUpgradeCheck = / {gsub(/[^0-9]/, "", $3); print $3; exit}' "$project/project.pbxproj")"
[[ -n "$project_marker" ]] || fail "Unable to read LastUpgradeCheck from $project."
if [[ "$project_marker" -gt "$max_upgrade_marker" ]]; then
  fail "$project has Xcode $project_marker project metadata. Re-save it with the latest public GM Xcode before Xcode Cloud release."
fi

while IFS= read -r scheme_file; do
  scheme_marker="$(awk -F'"' '/LastUpgradeVersion = / {print $2; exit}' "$scheme_file")"
  [[ -n "$scheme_marker" ]] || continue
  if [[ "$scheme_marker" -gt "$max_upgrade_marker" ]]; then
    fail "$scheme_file has Xcode $scheme_marker scheme metadata. Re-save it with the latest public GM Xcode before Xcode Cloud release."
  fi
done < <(find "$project/xcshareddata/xcschemes" -name '*.xcscheme' -print)

echo "Xcode Cloud release preflight passed for scheme '$app_store_scheme'."
