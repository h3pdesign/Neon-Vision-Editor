#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${TAG_NAME:?TAG_NAME is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

VERSION="${TAG_NAME#v}"
ASSET_NAME="Neon.Vision.Editor.app.zip"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "$TAG_NAME" != v* || -z "$VERSION" ]]; then
  echo "Expected a version tag such as v0.9.1; received '${TAG_NAME}'." >&2
  exit 1
fi

gh release download "$TAG_NAME" -R "$GITHUB_REPOSITORY" -p SHA256SUMS.txt -D "$WORK_DIR"
SHA256="$(awk -v asset="$ASSET_NAME" '$2 == asset { print $1; exit }' "$WORK_DIR/SHA256SUMS.txt")"
if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not read the SHA-256 for ${ASSET_NAME} from ${TAG_NAME}." >&2
  exit 1
fi

TITLE="Homebrew Cask update required: ${TAG_NAME}"
export TITLE
EXISTING_URL="$(gh issue list -R "$GITHUB_REPOSITORY" --state open --search "\"${TITLE}\" in:title" --json url,title --jq '.[] | select(.title == env.TITLE) | .url' | head -n1)"
if [[ -n "$EXISTING_URL" ]]; then
  echo "Homebrew Cask handoff already exists: ${EXISTING_URL}"
  exit 0
fi

ASSET_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG_NAME}/${ASSET_NAME}"
gh issue create -R "$GITHUB_REPOSITORY" \
  --title "$TITLE" \
  --body "A verified upstream Homebrew Cask pull request is required for ${TAG_NAME}.\n\n- Asset: ${ASSET_URL}\n- SHA-256: \`${SHA256}\`\n- Cask version: \`${VERSION}\`\n\nCreate the cask branch and pull request from an authenticated contributor session:\n\n\`TAG_NAME=${TAG_NAME} GITHUB_REPOSITORY=${GITHUB_REPOSITORY} bash scripts/create_homebrew_cask_pr.sh\`"
