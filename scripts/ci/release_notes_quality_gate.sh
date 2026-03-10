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
  "### Hero Screenshot"
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

hero_block="$(awk '/^### Hero Screenshot/{flag=1; next} /^### /{flag=0} flag {print}' "${SECTION_FILE}")"
if ! printf '%s\n' "${hero_block}" | grep -Eq '!\[[^]]*\]\([^)]*\)'; then
  echo "Release notes for ${TAG} need a hero screenshot markdown image under '### Hero Screenshot'." >&2
  exit 1
fi

why_upgrade_count="$(awk '/^### Why Upgrade/{flag=1; next} /^### /{flag=0} flag && /^- /{count++} END{print count+0}' "${SECTION_FILE}")"
if (( why_upgrade_count < 3 )); then
  echo "Release notes for ${TAG} require at least 3 bullets under '### Why Upgrade'." >&2
  exit 1
fi

echo "Validating README What's New heading..."
mapfile -t RELEASE_TAGS < <(grep -E '^## \[v[^]]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' CHANGELOG.md | sed -E 's/^## \[(v[^]]+)\].*$/\1/')
PREV_TAG=""
for i in "${!RELEASE_TAGS[@]}"; do
  if [[ "${RELEASE_TAGS[$i]}" == "${TAG}" ]]; then
    if (( i + 1 < ${#RELEASE_TAGS[@]} )); then
      PREV_TAG="${RELEASE_TAGS[$((i + 1))]}"
    fi
    break
  fi
done

if [[ -n "${PREV_TAG}" ]]; then
  grep -nE "^## What's New Since ${PREV_TAG}\\r?$" README.md >/dev/null
else
  grep -nE "^## What's New in ${TAG}\\r?$" README.md >/dev/null
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required for milestone checks." >&2
  exit 1
fi

MILESTONE_TITLE="${TAG#v}"
echo "Validating milestone ${MILESTONE_TITLE} is closed out..."
MILESTONE_NUM="$(gh api repos/h3pdesign/Neon-Vision-Editor/milestones --paginate --jq ".[] | select(.title == \"${MILESTONE_TITLE}\") | .number" | head -n1 || true)"
if [[ -z "${MILESTONE_NUM}" ]]; then
  echo "No milestone found with title '${MILESTONE_TITLE}'." >&2
  exit 1
fi

OPEN_ISSUES_JSON="$(gh issue list --state open --milestone "${MILESTONE_TITLE}" --limit 200 --json number,title,url)"
OPEN_COUNT="$(printf '%s' "${OPEN_ISSUES_JSON}" | jq 'length')"
if [[ "${OPEN_COUNT}" != "0" ]]; then
  echo "Milestone ${MILESTONE_TITLE} still has ${OPEN_COUNT} open issue(s):" >&2
  printf '%s' "${OPEN_ISSUES_JSON}" | jq -r '.[] | "- #\(.number): \(.title) (\(.url))"' >&2
  exit 1
fi

echo "Release-notes quality gate passed for ${TAG}."
