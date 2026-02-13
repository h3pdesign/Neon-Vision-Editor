#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

chmod +x .githooks/pre-commit scripts/bump_build_number.sh
git config core.hooksPath .githooks

echo "Git hooks installed. pre-commit will auto-bump CURRENT_PROJECT_VERSION."
