#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_pattern() {
  local pattern="$1"
  local file="$2"
  local description="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "[app-store-execution-boundary-audit] missing guardrail: $description" >&2
    exit 1
  fi
}

echo "[app-store-execution-boundary-audit] checking executable-code boundaries"

require_pattern '#if os\(macOS\) && !APP_STORE_BUILD' \
  "Neon Vision Editor/UI/IntegratedTerminalContent.swift" \
  "integrated PTY terminal excluded from App Store builds"
require_pattern '#if os\(macOS\) && !APP_STORE_BUILD' \
  "Neon Vision Editor/UI/ContentView+Actions.swift" \
  "Python project creation excluded from App Store builds"
require_pattern '#if os\(macOS\) && !APP_STORE_BUILD' \
  "Neon Vision Editor/UI/ContentView.swift" \
  "Python project sheet excluded from App Store builds"
require_pattern '#if os\(macOS\) && !APP_STORE_BUILD' \
  "Neon Vision Editor/UI/SidebarViews.swift" \
  "Python project action excluded from App Store builds"
require_pattern '#if os\(macOS\) && !APP_STORE_BUILD' \
  "Neon Vision Editor/UI/NeonSettingsView.swift" \
  "Python interpreter settings excluded from App Store builds"

echo "[app-store-execution-boundary-audit] OK"
