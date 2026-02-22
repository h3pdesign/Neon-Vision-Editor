#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Install release workflow templates into a target repository.

Usage:
  scripts/setup_release_workflows.sh [--target PATH] [--enterprise-selfhosted] [--force] [--commit] [--push]

Options:
  --target PATH   Target git repository root (default: current directory)
  --enterprise-selfhosted
                  Install self-hosted workflow profile for GitHub Enterprise
  --force         Overwrite existing workflow files
  --commit        Commit installed workflow files
  --push          Push commit to origin (implies --commit)

Examples:
  scripts/setup_release_workflows.sh
  scripts/setup_release_workflows.sh --target /path/to/repo --commit
  scripts/setup_release_workflows.sh --target /path/to/repo --enterprise-selfhosted --commit
  scripts/setup_release_workflows.sh --target /path/to/repo --force --commit --push
USAGE
}

TARGET="."
FORCE=0
DO_COMMIT=0
DO_PUSH=0
ENTERPRISE_SELF_HOSTED=0

while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --target)
      shift
      TARGET="${1:-}"
      if [[ -z "$TARGET" ]]; then
        echo "Missing value for --target" >&2
        exit 1
      fi
      ;;
    --force)
      FORCE=1
      ;;
    --enterprise-selfhosted)
      ENTERPRISE_SELF_HOSTED=1
      ;;
    --commit)
      DO_COMMIT=1
      ;;
    --push)
      DO_PUSH=1
      DO_COMMIT=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/workflow-templates"
TARGET="$(cd "$TARGET" && pwd)"

if [[ ! -d "$TARGET/.git" ]]; then
  echo "Target is not a git repository: $TARGET" >&2
  exit 1
fi

mkdir -p "$TARGET/.github/workflows"

if [[ "$ENTERPRISE_SELF_HOSTED" -eq 1 ]]; then
  files=(
    pre-release-ci.yml
    release-notarized-selfhosted.yml
    release-dry-run.yml
  )
else
  files=(
    pre-release-ci.yml
    release-notarized.yml
    release-notarized-selfhosted.yml
    release-dry-run.yml
  )
fi

installed=()
skipped=()
for file in "${files[@]}"; do
  src="$TEMPLATE_DIR/$file"
  dst="$TARGET/.github/workflows/$file"
  if [[ "$ENTERPRISE_SELF_HOSTED" -eq 1 && "$file" == "pre-release-ci.yml" ]]; then
    src="$TEMPLATE_DIR/pre-release-ci-enterprise-selfhosted.yml"
  fi

  if [[ ! -f "$src" ]]; then
    echo "Missing template: $src" >&2
    exit 1
  fi

  if [[ -f "$dst" && "$FORCE" -ne 1 ]]; then
    skipped+=("$file")
    continue
  fi

  cp "$src" "$dst"
  installed+=("$file")
done

echo "Target: $TARGET"
if [[ "$ENTERPRISE_SELF_HOSTED" -eq 1 ]]; then
  echo "Profile: GitHub Enterprise self-hosted"
else
  echo "Profile: Default (GitHub-hosted notarized + optional self-hosted)"
fi
if [[ ${#installed[@]} -gt 0 ]]; then
  echo "Installed/updated workflows:"
  printf '  - %s\n' "${installed[@]}"
else
  echo "No workflow files installed (all existed and --force was not set)."
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "Skipped existing workflows:"
  printf '  - %s\n' "${skipped[@]}"
fi

if [[ "$DO_COMMIT" -eq 1 ]]; then
  add_files=(.github/workflows/pre-release-ci.yml .github/workflows/release-notarized-selfhosted.yml .github/workflows/release-dry-run.yml)
  if [[ "$ENTERPRISE_SELF_HOSTED" -ne 1 ]]; then
    add_files+=(.github/workflows/release-notarized.yml)
  fi
  git -C "$TARGET" add "${add_files[@]}"
  if ! git -C "$TARGET" diff --cached --quiet; then
    git -C "$TARGET" commit -m "chore(ci): install release workflow templates"
    echo "Committed workflow updates."
  else
    echo "Nothing to commit."
  fi
fi

if [[ "$DO_PUSH" -eq 1 ]]; then
  git -C "$TARGET" push
  echo "Pushed workflow updates to origin."
fi

echo "Done."
