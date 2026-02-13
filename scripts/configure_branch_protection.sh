#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-h3pdesign/Neon-Vision-Editor}"
BRANCH="${2:-main}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

echo "Applying branch protection on ${REPO}:${BRANCH}..."
gh api --method PUT "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Pre-release CI / preflight"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true
}
JSON

echo "Branch protection updated successfully."
