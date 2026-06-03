#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "privacy log audit requires rg" >&2
  exit 1
fi

echo "[privacy-log-audit] checking release log patterns"

if rg -n 'AIActivityLog\.record\([^)]*tab\.name|print\([^)]*tab\.content|NSLog\([^)]*(token|apiKey|content|prompt)' "Neon Vision Editor"; then
  echo "[privacy-log-audit] sensitive logging pattern found" >&2
  exit 1
fi

echo "[privacy-log-audit] OK"
