#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PREVIEW_WEBVIEW="Neon Vision Editor/UI/MarkdownPreviewWebView.swift"
PREVIEW_EXPORT="Neon Vision Editor/UI/ContentView+MarkdownPreviewExport.swift"

echo "[markdown-preview-remote-audit] checking remote preview guardrails"

if ! command -v rg >/dev/null 2>&1; then
  echo "[markdown-preview-remote-audit] requires rg" >&2
  exit 1
fi

require_pattern() {
  local pattern="$1"
  local file="$2"
  local description="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "[markdown-preview-remote-audit] missing guardrail: $description" >&2
    exit 1
  fi
}

require_pattern 'websiteDataStore = \.nonPersistent\(\)' "$PREVIEW_WEBVIEW" "non-persistent WebKit data store"
require_pattern 'allowsContentJavaScript = false' "$PREVIEW_WEBVIEW" "JavaScript disabled for preview WebView"
require_pattern 'scheme == "http" \|\| scheme == "https"' "$PREVIEW_WEBVIEW" "remote HTTP/HTTPS preview navigation blocked"
require_pattern 'remote-image-placeholder' "$PREVIEW_EXPORT" "remote images rendered as clickable placeholders"
require_pattern 'Remote image' "$PREVIEW_EXPORT" "remote image placeholder label"

echo "[markdown-preview-remote-audit] OK"
