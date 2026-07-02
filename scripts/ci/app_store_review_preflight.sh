#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

section() {
  echo
  echo "== $1 =="
}

WORK_DIR="${TMPDIR:-/tmp}/nve_app_store_review_preflight"
DERIVED_DATA="$WORK_DIR/DerivedData"
mkdir -p "$WORK_DIR"
rm -rf "$DERIVED_DATA"
trap 'rm -rf "$DERIVED_DATA"' EXIT

section "Toolchain"
source scripts/ci/select_xcode17.sh

section "Static App Store audits"
scripts/ci/privacy_log_audit.sh
scripts/ci/review_metadata_audit.py
scripts/ci/markdown_preview_remote_audit.sh
python3 scripts/ci/markdown_preview_theme_audit.py

section "Review-critical tests"
xcodebuild \
  -project "Neon Vision Editor.xcodeproj" \
  -scheme "Neon Vision Editor" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -only-testing:"Neon Vision EditorTests/AIClientFactoryTests" \
  -only-testing:"Neon Vision EditorTests/EditorSettingsDefaultsTests" \
  -only-testing:"Neon Vision EditorTests/MarkdownPreviewPDFRendererTests/testAllMarkdownPreviewThemesKeepCompactViewportGuardrails" \
  -only-testing:"Neon Vision EditorTests/MarkdownPreviewPDFRendererTests/testMarkdownPreviewRuntimeFontSizeUsesEditorValue" \
  -only-testing:"Neon Vision EditorTests/ReleaseRuntimePolicyTests" \
  -only-testing:"Neon Vision EditorTests/ToolbarActionSelectionTests" \
  -only-testing:"Neon Vision EditorTests/WindowTranslucencyTests/testMacSettingsWindowPolicyRemainsResizableAndScrollableAtMinimumSize" \
  test

section "visionOS simulator build"
if xcrun simctl list runtimes | grep -Eq 'visionOS (26\.5|26\.)'; then
  xcodebuild \
    -project "Neon Vision Editor.xcodeproj" \
    -scheme "Neon Vision Editor" \
    -destination "generic/platform=visionOS Simulator" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build
else
  echo "No visionOS 26.x simulator runtime found; skipping visionOS simulator build."
fi

echo
echo "App Store review preflight passed."
