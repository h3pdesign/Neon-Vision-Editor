#!/bin/sh
set -eu

tag="${1:-v0.7.0}"

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required." >&2
    exit 127
fi

echo "## ${tag} issue changelog draft"
echo
echo "### Closed issues"
gh issue list --state closed --limit 50 --json number,title,labels \
    --jq '.[] | "- #\(.number) \(.title)"'
echo
echo "### Open release candidates"
gh issue list --state open --limit 50 --json number,title,labels \
    --jq '.[] | "- #\(.number) \(.title)"'
