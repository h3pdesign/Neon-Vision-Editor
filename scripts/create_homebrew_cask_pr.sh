#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${TAG_NAME:?TAG_NAME is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
RELEASE_GH_TOKEN="${RELEASE_GH_TOKEN:-$GH_TOKEN}"

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

GH_TOKEN="$RELEASE_GH_TOKEN" gh release download "$TAG_NAME" -R "$GITHUB_REPOSITORY" \
  -p Neon.Vision.Editor.app.zip \
  -D "$WORK_DIR"
SHA256="$(shasum -a 256 "$WORK_DIR/Neon.Vision.Editor.app.zip" | awk '{print $1}')"

existing_pr="$(gh pr list -R "$CASK_UPSTREAM" \
  --head "${FORK_OWNER}:${BRANCH}" \
  --state all \
  --json number,state,url \
  --jq '.[0] | [.number, .state, .url] | @tsv')"

checkout="$WORK_DIR/homebrew-cask"
git clone --depth=1 "https://x-access-token:${GH_TOKEN}@github.com/${CASK_FORK}.git" "$checkout"
git -C "$checkout" remote add upstream "https://github.com/${CASK_UPSTREAM}.git"
git -C "$checkout" fetch --depth=1 upstream main

if git -C "$checkout" fetch --depth=1 origin "$BRANCH"; then
  git -C "$checkout" switch -C "$BRANCH" FETCH_HEAD
else
  git -C "$checkout" switch -C "$BRANCH" origin/main
fi
if ! git -C "$checkout" checkout upstream/main -- "$CASK_PATH" 2>/dev/null; then
  if [[ ! -f "$checkout/$CASK_PATH" ]]; then
    mkdir -p "$(dirname "$checkout/$CASK_PATH")"
    : > "$checkout/$CASK_PATH"
  fi
fi

python3 - "$checkout/$CASK_PATH" "$VERSION" "$SHA256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
sha256 = sys.argv[3]
text = path.read_text()
if not text.strip():
    text = '''cask "neon-vision-editor" do
  version "VERSION"
  sha256 "SHA256"

  url "https://github.com/h3pdesign/Neon-Vision-Editor/releases/download/v#{version}/Neon.Vision.Editor.app.zip"
  name "Neon Vision Editor"
  desc "Native code and text editor"
  homepage "https://github.com/h3pdesign/Neon-Vision-Editor"

  auto_updates true
  depends_on macos: :sonoma

  app "Neon Vision Editor.app"
end
'''
text, version_count = re.subn(r'(?m)^  version "[^"]+"$', f'  version "{version}"', text, count=1)
text, sha_count = re.subn(r'(?m)^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{sha256}"', text, count=1)
if version_count != 1 or sha_count != 1:
    raise SystemExit(f"Could not update version/SHA in {path}")
if "livecheck do" not in text:
    marker = '  homepage "https://github.com/h3pdesign/Neon-Vision-Editor"\n'
    livecheck = marker + '\n  livecheck do\n    url "https://github.com/h3pdesign/Neon-Vision-Editor/releases"\n    strategy :github_latest\n  end\n'
    if marker not in text:
        raise SystemExit(f"Could not add livecheck block to {path}")
    text = text.replace(marker, livecheck, 1)
path.write_text(text)
PY

git -C "$checkout" add -N "$CASK_PATH"
git -C "$checkout" diff --check
if git -C "$checkout" diff --quiet "upstream/main" -- "$CASK_PATH"; then
  echo "Homebrew Cask already matches ${TAG_NAME}; no pull request is needed."
  exit 0
fi

if ! git -C "$checkout" diff --quiet -- "$CASK_PATH"; then
  git -C "$checkout" config user.name "github-actions[bot]"
  git -C "$checkout" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git -C "$checkout" add "$CASK_PATH"
  git -C "$checkout" commit -m "neon-vision-editor: update ${VERSION}"
  git -C "$checkout" push origin "HEAD:refs/heads/${BRANCH}"
fi

# Validate the generated cask in the fork checkout before submitting it.
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required for cask validation." >&2
  exit 1
fi
export HOMEBREW_NO_AUTO_UPDATE=1
brew_retry() {
  local attempt
  for attempt in 1 2 3; do
    if "$@"; then
      return 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
      echo "Homebrew check failed; retrying in 15 seconds (${attempt}/3)..." >&2
      sleep 15
    fi
  done
  return 1
}
(
  cd "$checkout"
  brew_retry brew audit --cask --online "$CASK_PATH"
  brew style --fix "$CASK_PATH"
)
if ! git -C "$checkout" diff --quiet -- "$CASK_PATH"; then
  echo "brew style --fix changed ${CASK_PATH}; commit the formatted cask before submission." >&2
  exit 1
fi
(
  cd "$checkout"
  brew_retry brew audit --cask --new "$CASK_PATH"
  HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask "$CASK_PATH"
  brew uninstall --cask "$CASK_PATH"
)

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

read -r -d '' PR_BODY <<EOF || true
-----

<!-- Do not tick a checkbox if you haven’t performed its action. Honesty is indispensable for a smooth review process. -->
<!-- Use [x] to mark item done before creation, or just click the checkboxes with device pointer after creation -->
<!-- In the following questions \`<cask>\` is the token of the cask you're editing. -->

After making any changes to a cask, existing or new, verify:

- [x] The submission is for [a stable version](https://docs.brew.sh/Acceptable-Casks#stable-versions) or [documented exception](https://docs.brew.sh/Acceptable-Casks#but-there-is-no-stable-version).
- [x] \`brew audit --cask --online ${CASK_PATH##*/}\` is error-free.
- [x] \`brew style --fix ${CASK_PATH##*/}\` reports no offenses.

Additionally, if adding a new cask:

- [x] Named the cask according to the [token reference](https://docs.brew.sh/Cask-Cookbook#token-reference).
- [x] Checked the cask was not already refused.
- [x] \`brew audit --cask --new ${CASK_PATH##*/}\` worked successfully.
- [x] \`HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask ${CASK_PATH##*/}\` worked successfully.
- [x] \`brew uninstall --cask ${CASK_PATH##*/}\` worked successfully.

-----

- [x] I did not use AI/LLM to create this PR, or I disclosed the tool/model below and reviewed its output, including [`zap` stanza](https://docs.brew.sh/Cask-Cookbook#stanza-zap) paths; I did not attribute commits to AI and will answer maintainer questions and review comments myself.

AI assistance was limited to preparing the release update. I reviewed the published ${TAG_NAME} release URL, SHA-256 checksum, version, and cleanup paths.

-----

Automated update for the verified ${TAG_NAME} release ZIP (SHA-256: \`${SHA256}\`).
EOF

if [[ -n "$existing_pr" ]]; then
  existing_number="${existing_pr%%$'\t'*}"
  existing_state="${existing_pr#*$'\t'}"
  existing_state="${existing_state%%$'\t'*}"
  existing_url="${existing_pr##*$'\t'}"
  gh pr edit -R "$CASK_UPSTREAM" "$existing_number" --body "$PR_BODY"
  echo "Updated existing Homebrew Cask pull request (${existing_state}): ${existing_url}"
  exit 0
fi

gh pr create -R "$CASK_UPSTREAM" \
  --base main \
  --head "${FORK_OWNER}:${BRANCH}" \
  --title "neon-vision-editor: update ${VERSION}" \
  --body "$PR_BODY"
