#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: scripts/ci/release_notes_quality_gate.sh <tag>" >&2
  exit 1
fi
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ ! -f "CHANGELOG.md" || ! -f "README.md" ]]; then
  echo "Missing CHANGELOG.md or README.md." >&2
  exit 1
fi

echo "Running docs sync check for ${TAG}..."
scripts/prepare_release_docs.py "${TAG}" --check

echo "Validating changelog section for ${TAG}..."
SECTION_FILE="/tmp/release-notes-gate-${TAG}.md"
scripts/extract_changelog_section.sh CHANGELOG.md "${TAG}" > "${SECTION_FILE}"
if grep -nEi "\\bTODO\\b" "${SECTION_FILE}" >/dev/null; then
  echo "Release notes for ${TAG} contain unresolved TODO markers." >&2
  exit 1
fi

echo "Validating release notes structure..."
required_headings=(
  "### Why Upgrade"
  "### Highlights"
  "### Fixes"
  "### Breaking changes"
  "### Migration"
)
for heading in "${required_headings[@]}"; do
  if ! grep -nF "${heading}" "${SECTION_FILE}" >/dev/null; then
    echo "Release notes for ${TAG} are missing required heading: ${heading}" >&2
    exit 1
  fi
done

why_upgrade_count="$(awk '/^### Why Upgrade/{flag=1; next} /^### /{flag=0} flag && /^- /{count++} END{print count+0}' "${SECTION_FILE}")"
if (( why_upgrade_count < 3 )); then
  echo "Release notes for ${TAG} require at least 3 bullets under '### Why Upgrade'." >&2
  exit 1
fi

echo "Validating README What's New heading..."
RELEASE_TAGS=()
while IFS= read -r release_tag; do
  RELEASE_TAGS+=("${release_tag}")
done < <(grep -E '^## \[v[^]]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}\r?$' CHANGELOG.md | sed -E 's/\r$//' | sed -E 's/^## \[(v[^]]+)\].*$/\1/')
PREV_TAG=""
for i in "${!RELEASE_TAGS[@]}"; do
  if [[ "${RELEASE_TAGS[$i]}" == "${TAG}" ]]; then
    if (( i + 1 < ${#RELEASE_TAGS[@]} )); then
      PREV_TAG="${RELEASE_TAGS[$((i + 1))]}"
    fi
    break
  fi
done

# A correction release may deliberately document an earlier viable fallback
# instead of its immediate predecessor. The release-doc generator writes this
# line only for such an explicit override; keep the gate aligned with it while
# requiring that the referenced release really exists in the changelog.
DOCUMENTED_PREV_TAG="$(sed -nE 's/^> Previous viable fallback: \*\*(v[^*]+)\*\*$/\1/p' README.md)"
if [[ -n "${DOCUMENTED_PREV_TAG}" ]]; then
  if ! grep -qF "## [${DOCUMENTED_PREV_TAG}]" CHANGELOG.md; then
    echo "README previous viable fallback ${DOCUMENTED_PREV_TAG} is not present in CHANGELOG.md." >&2
    exit 1
  fi
  PREV_TAG="${DOCUMENTED_PREV_TAG}"
fi

current_semver="${TAG#v}"
prev_semver="${PREV_TAG#v}"
if [[ -n "${PREV_TAG}" ]] && [[ "${current_semver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "${prev_semver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  IFS=. read -r current_major current_minor current_patch <<<"${current_semver}"
  IFS=. read -r prev_major prev_minor prev_patch <<<"${prev_semver}"
  if [[ "${prev_major}" == "${current_major}" ]] \
    && [[ "${prev_minor}" == "${current_minor}" ]] \
    && (( current_patch == prev_patch + 1 )); then
    grep -nE "^## What's New in ${PREV_TAG} and ${TAG}\\r?$" README.md >/dev/null
  else
    grep -nE "^## What's New Since ${PREV_TAG}\\r?$" README.md >/dev/null
  fi
elif [[ -n "${PREV_TAG}" ]]; then
  grep -nE "^## What's New Since ${PREV_TAG}\\r?$" README.md >/dev/null
else
  grep -nE "^## What's New in ${TAG}\\r?$" README.md >/dev/null
fi

bash scripts/ci/release_milestone_preflight.sh "${TAG}"

echo "Release-notes quality gate passed for ${TAG}."
