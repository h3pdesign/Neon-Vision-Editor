#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${TAG_NAME:?TAG_NAME is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

CASK_FORK="${HOMEBREW_CASK_FORK:-h3pdesign/homebrew-cask}"
CASK_UPSTREAM="${HOMEBREW_CASK_UPSTREAM:-Homebrew/homebrew-cask}"
CASK_PATH="Casks/n/neon-vision-editor.rb"
VERSION="${TAG_NAME#v}"
BRANCH="release/neon-vision-editor-${TAG_NAME//./-}"
FORK_OWNER="${CASK_FORK%%/*}"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ "$TAG_NAME" != v* || -z "$VERSION" ]]; then
  echo "Expected a version tag such as v0.9.1; received '${TAG_NAME}'." >&2
  exit 1
fi

gh release download "$TAG_NAME" -R "$GITHUB_REPOSITORY" \
  -p Neon.Vision.Editor.app.zip \
  -D "$WORK_DIR"
SHA256="$(shasum -a 256 "$WORK_DIR/Neon.Vision.Editor.app.zip" | awk '{print $1}')"

existing_pr=""
if [[ "${HOMEBREW_CASK_PREPARE_ONLY:-false}" != "true" ]]; then
  existing_pr="$(gh pr list -R "$CASK_UPSTREAM" \
    --head "${FORK_OWNER}:${BRANCH}" \
    --state open \
    --json url \
    --jq '.[0].url')"
fi

checkout="$WORK_DIR/homebrew-cask"
git clone --depth=1 "https://x-access-token:${GH_TOKEN}@github.com/${CASK_FORK}.git" "$checkout"
git -C "$checkout" remote add upstream "https://github.com/${CASK_UPSTREAM}.git"
git -C "$checkout" fetch --depth=1 upstream main

if git -C "$checkout" fetch --depth=1 origin "$BRANCH"; then
  git -C "$checkout" switch -C "$BRANCH" FETCH_HEAD
else
  git -C "$checkout" switch -C "$BRANCH" upstream/main
fi

python3 - "$checkout/$CASK_PATH" "$VERSION" "$SHA256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3]
text = path.read_text()
text, version_count = re.subn(r'(?m)^  version "[^"]+"$', f'  version "{version}"', text, count=1)
text, sha_count = re.subn(r'(?m)^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{sha256}"', text, count=1)
if version_count != 1 or sha_count != 1:
    raise SystemExit(f"Could not update version/SHA in {path}")
path.write_text(text)
PY

git -C "$checkout" diff --check
if ! git -C "$checkout" diff --quiet -- "$CASK_PATH"; then
  git -C "$checkout" config user.name "github-actions[bot]"
  git -C "$checkout" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git -C "$checkout" add "$CASK_PATH"
  git -C "$checkout" commit -m "neon-vision-editor: update ${VERSION}"
  git -C "$checkout" push origin "HEAD:refs/heads/${BRANCH}"
fi

if [[ -n "$existing_pr" ]]; then
  echo "Updated Homebrew Cask pull request: ${existing_pr}"
  exit 0
fi

if git -C "$checkout" diff --quiet "upstream/main" -- "$CASK_PATH"; then
  echo "Homebrew Cask already matches ${TAG_NAME}; no pull request is needed."
  exit 0
fi

if [[ "${HOMEBREW_CASK_PREPARE_ONLY:-false}" == "true" ]]; then
  compare_url="https://github.com/${CASK_UPSTREAM}/compare/main...${FORK_OWNER}:${BRANCH}?expand=1"
  echo "Prepared Homebrew Cask branch: ${compare_url}"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "## Homebrew Cask pull request"
      echo
      echo "[Open the prepared ${TAG_NAME} pull request](${compare_url})"
      echo
      echo "Review the generated change, then select **Create pull request**."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

gh pr create -R "$CASK_UPSTREAM" \
  --base main \
  --head "${FORK_OWNER}:${BRANCH}" \
  --title "neon-vision-editor: update ${VERSION}" \
  --body "Automated update for the verified ${TAG_NAME} release ZIP (SHA-256: \`${SHA256}\`)."
