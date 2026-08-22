#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "Usage: scripts/ci/release_milestone_preflight.sh <tag>" >&2
  exit 1
fi
if [[ "$TAG" != v* ]]; then
  TAG="v$TAG"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required for milestone checks." >&2
  exit 1
fi

MILESTONE_TITLE="${TAG#v}"
echo "Validating milestone ${MILESTONE_TITLE} is closed out..."
MILESTONE_RECORD="$(gh api 'repos/h3pdesign/Neon-Vision-Editor/milestones?state=all' --paginate --jq ".[] | select(.title == \"${MILESTONE_TITLE}\") | [.number, .state] | @tsv" | head -n1 || true)"
if [[ -z "${MILESTONE_RECORD}" ]]; then
  echo "No milestone found with title '${MILESTONE_TITLE}'." >&2
  echo "Create it before release prep, assign the release issues, then close it after all assigned issues are resolved:" >&2
  echo "  gh api -X POST repos/h3pdesign/Neon-Vision-Editor/milestones -f title='${MILESTONE_TITLE}'" >&2
  exit 1
fi

IFS=$'\t' read -r MILESTONE_NUM MILESTONE_STATE <<<"${MILESTONE_RECORD}"
if [[ "${MILESTONE_STATE}" != "closed" ]]; then
  echo "Milestone ${MILESTONE_TITLE} must be closed before release (current: ${MILESTONE_STATE})." >&2
  echo "Close it after confirming it has no open issues:" >&2
  echo "  gh api -X PATCH repos/h3pdesign/Neon-Vision-Editor/milestones/${MILESTONE_NUM} -f state=closed" >&2
  exit 1
fi

OPEN_ISSUES_JSON="$(gh issue list --state open --milestone "${MILESTONE_TITLE}" --limit 200 --json number,title,url)"
OPEN_COUNT="$(printf '%s' "${OPEN_ISSUES_JSON}" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)))')"
if [[ "${OPEN_COUNT}" != "0" ]]; then
  echo "Milestone ${MILESTONE_TITLE} still has ${OPEN_COUNT} open issue(s):" >&2
  printf '%s' "${OPEN_ISSUES_JSON}" | python3 -c 'import json, sys; print("\\n".join(f"- #{issue[\"number\"]}: {issue[\"title\"]} ({issue[\"url\"]})" for issue in json.load(sys.stdin)))' >&2
  exit 1
fi
