#!/usr/bin/env bash
# Profile only the current native implementation against recorded release data.
# No checkout switching, old-tab execution, normal-editor state, or publication.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:?Usage: profile_native_document_tabs.sh OUTPUT_DIRECTORY [edit|preview|both]}"
MODE="${2:-edit}"
RUNS="${NVE_PROFILE_RUNS:-3}"
case "$RUNS" in 1|3) ;; *) echo 'NVE_PROFILE_RUNS must be 1 or 3' >&2; exit 2 ;; esac
case "$MODE" in edit|preview) MODES=("$MODE") ;; both) MODES=(edit preview) ;; *) echo 'Mode must be edit, preview, or both' >&2; exit 2 ;; esac
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
PROFILE_DIR="$(mktemp -d /private/tmp/neon-native-profile.XXXXXX)"
cleanup() {
    case "$PROFILE_DIR" in /private/tmp/neon-native-profile.*) rm -rf -- "$PROFILE_DIR" ;; esac
}
trap cleanup EXIT
APP="$PROFILE_DIR/Native Controller Profile.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PROFILE_DIR/source"
cp -R "$ROOT/Project/Sources/Neon Vision Editor/." "$PROFILE_DIR/source/"
cp "$ROOT/Project/Sources/Neon Pulse Shared/NeonPulseShared.swift" "$PROFILE_DIR/source/"
cp "$ROOT/scripts/tab_release_parity.swift" "$PROFILE_DIR/source/"
# Test-only entry point and first-frame qualification in the disposable copy.
perl -0pi -e 's/^\@main$/#if !NVE_TAB_PARITY_APP\n\@main\n#endif/m' "$PROFILE_DIR/source/App/NeonVisionEditorApp.swift"
perl -0pi -e 's/EditorPerformanceMonitor\.shared\.markTabSwitchFirstDraw\(tabID: documentID\)/if TabReleaseParityRunner.canRecordDraw(tabID: documentID, contentRevision: installedContentRevision, window: window) { EditorPerformanceMonitor.shared.markTabSwitchFirstDraw(tabID: documentID) }/' "$PROFILE_DIR/source/UI/VirtualEditorView+macOS.swift"
cp -R "$PROFILE_DIR/source/Resources/." "$APP/Contents/Resources/"
for localization in "$PROFILE_DIR/source/"*.lproj; do cp -R "$localization" "$APP/Contents/Resources/"; done
SOURCES=()
while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(rg --files -0 "$PROFILE_DIR/source" -g '*.swift')
xcrun swiftc -O -whole-module-optimization -num-threads 8 -parse-as-library -swift-version 6 \
    -default-isolation MainActor -enable-upcoming-feature MemberImportVisibility \
    -module-name Neon_Vision_Editor -target arm64-apple-macos14.6 \
    -D NVE_TAB_PARITY_APP -D USE_FOUNDATION_MODELS -D MACOS_27_AGENTIC_EDITOR \
    "${SOURCES[@]}" -o "$APP/Contents/MacOS/NativeProfile" > "$OUTPUT/compile.log" 2>&1
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string h3p.NeonTabParity.NativeController' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string NativeProfile' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Native Controller Profile' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :NSPrincipalClass string NSApplication' "$PLIST"
codesign --force --sign - "$APP" > "$OUTPUT/signing.log" 2>&1
if [[ -n "${NVE_PARITY_RENDER_DIR:-}" ]]; then
  for variant in small large; do
    lines=200
    [[ "$variant" != large ]] || lines=12000
    open -n -W --env NVE_RUN_TAB_PARITY=1 --env NSUnbufferedIO=YES --env NVE_PARITY_PREVIEW_MODE=preview \
      --env "NVE_PARITY_SKIP_CAPTURE=${NVE_PARITY_SKIP_CAPTURE:-0}" \
      --env NVE_PARITY_EXTERNAL_CAPTURE=1 \
      --env "NVE_RENDER_MARKDOWN_LINES=$lines" \
      --env "NVE_PARITY_RENDER_DIR=$OUTPUT/render-$variant" \
      --stdout "$OUTPUT/render-$variant.log" --stderr "$OUTPUT/render-$variant-error.log" "$APP" \
      --args -ApplePersistenceIgnoreState YES &
    launch_pid=$!
    launched_at=$SECONDS
    sampled=0
    while kill -0 "$launch_pid" 2>/dev/null; do
      if (( SECONDS - launched_at > 25 && sampled == 0 )); then
        sampled=1
        fixture_pid=$(pgrep -f "$APP/Contents/MacOS/NativeProfile" | head -1 || true)
        if [[ -n "$fixture_pid" ]]; then
          sample "$fixture_pid" 1 -file "$OUTPUT/render-$variant.sample.txt" > "$OUTPUT/render-$variant-sample.log" 2>&1 || true
        fi
      fi
      if [[ -f "$OUTPUT/render-$variant.log" ]]; then
        while read -r marker number screenshot; do
          [[ "$marker" == RENDER_CAPTURE_READY && ! -f "$screenshot.captured" ]] || continue
          /usr/sbin/screencapture -x -l "$number" "$screenshot" || { wait "$launch_pid"; exit 1; }
          touch "$screenshot.captured"
        done < "$OUTPUT/render-$variant.log"
      fi
      sleep 0.1
    done
    wait "$launch_pid"
    rg -q '^TAB_RELEASE_PARITY_COMPLETE$' "$OUTPUT/render-$variant.log"
  done
  echo "Completed isolated pane/render checks (capture skipped: ${NVE_PARITY_SKIP_CAPTURE:-0}): $OUTPUT"
fi
for MODE in "${MODES[@]}"; do
  for ((iteration=1; iteration<=RUNS; iteration++)); do
    env -u NVE_PARITY_RENDER_DIR NVE_RUN_TAB_PARITY=1 NVE_PARITY_PREVIEW_MODE="$MODE" python3 -c '
import os, subprocess, sys
try:
    # Windows restored from an aborted run would replace the fixture scene.
    result = subprocess.run([sys.argv[1], "-ApplePersistenceIgnoreState", "YES"], env=os.environ, timeout=90)
    sys.exit(result.returncode)
except subprocess.TimeoutExpired:
    print("TAB_RELEASE_PARITY_ERROR foreground run exceeded 90 seconds", file=sys.stderr)
    sys.exit(124)
' "$APP/Contents/MacOS/NativeProfile" > "$OUTPUT/native-$MODE-$iteration.log" 2>&1
    rg -q '^TAB_RELEASE_PARITY_COMPLETE$' "$OUTPUT/native-$MODE-$iteration.log"
  done
  echo "$RUNS completed native-only $MODE runs: $OUTPUT"
done
