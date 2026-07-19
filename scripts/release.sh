#!/usr/bin/env bash
set -euo pipefail

TAG_NAME="${1:-}"
if [[ -z "${TAG_NAME}" ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 2
fi

ARCHIVE_PATH="${ARCHIVE_PATH:-/tmp/NeonVisionEditor.xcarchive}"
ZIP_NAME="Neon.Vision.Editor.app.zip"
CASK_FILE="homebrew-tap/Casks/neon-vision-editor.rb"

# Checkout tag in a detached state (preserves current branch)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD || true)

git fetch --depth=1 origin "refs/tags/${TAG_NAME}"

git checkout -q "${TAG_NAME}"

xcodebuild \
  -project "Neon Vision Editor.xcodeproj" \
  -scheme "Neon Vision Editor" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  MACOSX_DEPLOYMENT_TARGET=15.5 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  archive

APP_PATH="${ARCHIVE_PATH}/Products/Applications/Neon Vision Editor.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found at ${APP_PATH}" >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_NAME}"

./scripts/extract_changelog_section.sh CHANGELOG.md "${TAG_NAME}" > release-notes.md
bash ./scripts/append_release_build_metadata.sh "${APP_PATH}" release-notes.md

gh release create "${TAG_NAME}" \
  --title "Neon Vision Editor ${TAG_NAME}" \
  --notes-file release-notes.md \
  "${ZIP_NAME}"

# Update Homebrew cask to latest release asset and sha256
if [[ -f "${CASK_FILE}" ]]; then
  NEW_VERSION="${TAG_NAME#v}"
  NEW_SHA=$(shasum -a 256 "${ZIP_NAME}" | awk '{print $1}')
  perl -0pi -e "s/version \"[^\"]+\"/version \"${NEW_VERSION}\"/g; s/sha256 \"[^\"]+\"/sha256 \"${NEW_SHA}\"/g" "${CASK_FILE}"
  echo "Updated ${CASK_FILE} to version ${NEW_VERSION} with sha256 ${NEW_SHA}"
else
  echo "Cask file not found at ${CASK_FILE}" >&2
fi

# Return to previous branch
if [[ -n "${CURRENT_BRANCH}" && "${CURRENT_BRANCH}" != "HEAD" ]]; then
  git checkout -q "${CURRENT_BRANCH}"
fi
