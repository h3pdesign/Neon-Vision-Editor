#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: scripts/capture_performance_profile.sh <macos|iphone|ipad> [output-directory]

Creates deterministic workload fixtures, records a 30-second Instruments trace,
and writes a capture record beside it. Run each platform three times and retain
the raw .trace files as the authoritative Instruments artifacts.

Environment:
  NVE_PERFORMANCE_APP_PATH     macOS .app path (required for macOS)
  NVE_PERFORMANCE_DEVICE_ID    Simulator UDID (required for iPhone/iPad)
  NVE_PERFORMANCE_BUNDLE_ID    App bundle identifier (default h3p.Neon-Vision-Editor)
  NVE_PERFORMANCE_DURATION     Trace duration in seconds (default 30)
  NVE_PERFORMANCE_INSTRUMENT   allocations, time-profiler, or animation-hitches
                               (default allocations)
  NVE_BENCHMARK_CARD_COUNT, NVE_BENCHMARK_PDF_CARD_COUNT, NVE_BENCHMARK_OPEN
EOF
}

platform="${1:-}"
output_dir="${2:-$ROOT/performance-artifacts/$(date +%Y%m%d-%H%M%S)-${platform}}"
case "$platform" in macos|iphone|ipad) ;; *) usage >&2; exit 2 ;; esac

duration="${NVE_PERFORMANCE_DURATION:-30}"
bundle_id="${NVE_PERFORMANCE_BUNDLE_ID:-h3p.Neon-Vision-Editor}"
instrument_id="${NVE_PERFORMANCE_INSTRUMENT:-allocations}"
case "$instrument_id" in
  allocations)
    instrument_name="Allocations"
    trace_slug="allocations"
    ;;
  time-profiler)
    instrument_name="Time Profiler"
    trace_slug="time-profiler"
    ;;
  animation-hitches|core-animation)
    # Current Instruments exposes Core Animation commit/render timing through
    # the Animation Hitches template rather than a standalone template.
    instrument_name="Animation Hitches"
    trace_slug="animation-hitches"
    ;;
  *)
    echo "Unsupported NVE_PERFORMANCE_INSTRUMENT: $instrument_id" >&2
    usage >&2
    exit 2
    ;;
esac
mkdir -p "$output_dir"

NVE_BENCHMARK_OPEN=0 scripts/benchmark_large_file.sh 100000 > "$output_dir/fixture.log"
fixture_root="${TMPDIR:-/tmp}/nve_large_file_benchmark"
markdown_file="$fixture_root/large-100000.md"
trace="$output_dir/${platform}-${trace_slug}.trace"
capture_json="$output_dir/capture.json"

tool_version="$(xcrun xctrace version 2>/dev/null || xcrun xctrace --version 2>/dev/null || echo unavailable)"
os_version="$(sw_vers -productVersion 2>/dev/null || uname -sr)"
machine="$(uname -m)"
record_status=0
pid=""

run_isolated() {
  # macOS does not provide setsid(1). A separate session prevents xctrace's
  # time-limit interrupt from terminating this shell before it writes JSON.
  python3 - "$@" <<'PY'
import subprocess
import sys

result = subprocess.run(sys.argv[1:], start_new_session=True)
raise SystemExit(result.returncode)
PY
}

write_capture_manifest() {
  python3 - "$capture_json" "$platform" "$duration" "$bundle_id" "$tool_version" "$os_version" "$machine" "$instrument_name" "$1" "$record_status" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "schemaVersion": 1,
    "capturedAt": datetime.now(timezone.utc).isoformat(),
    "platform": sys.argv[2],
    "durationSeconds": int(sys.argv[3]),
    "bundleIdentifier": sys.argv[4],
    "xctraceVersion": sys.argv[5],
    "hostOS": sys.argv[6],
    "hostArchitecture": sys.argv[7],
    "instrument": sys.argv[8],
    "captureStatus": sys.argv[9],
    "xctraceExitStatus": int(sys.argv[10]),
    "traceExport": "raw-trace-retained-xcode27-workaround",
    "fixture": {
        "largeFileLines": 100000,
        "markdownCards": 500,
        "pdfCards": 500
    },
    "manualWorkload": [
        "Open the generated large Markdown document and enable preview.",
        "Type continuously while preview is visible.",
        "Open each generated project-card directory, wait for indexing, then toggle the card view 20 times.",
        "Open the generated large Git diff fixture and verify retained output stays bounded.",
        "Restart after saving an unsaved-draft recovery fixture."
    ]
}, indent=2) + "\n", encoding="utf-8")
PY
}

# Persist the complete fixture and environment context before recording. xctrace
# can terminate its parent process at the time limit on Xcode 27 beta, while
# the raw trace itself is still successfully finalized.
write_capture_manifest "recording"

if [[ "$platform" == "macos" ]]; then
  app_path="${NVE_PERFORMANCE_APP_PATH:-}"
  if [[ ! -d "$app_path" ]]; then
    echo "NVE_PERFORMANCE_APP_PATH must name a built macOS .app." >&2
    exit 2
  fi
  # Reuse the existing matching app instance; performance capture must never
  # create a row of duplicate editor windows.
  pid="$(pgrep -f "${app_path}/Contents/MacOS" | head -n1 || true)"
  /usr/bin/open -a "$app_path" "$markdown_file"
  if [[ -z "$pid" ]]; then
    for _ in {1..20}; do
      pid="$(pgrep -f "${app_path}/Contents/MacOS" | head -n1 || true)"
      [[ -n "$pid" ]] && break
      sleep 1
    done
  fi
  [[ -n "$pid" ]] || { echo "Could not find the launched app process." >&2; exit 1; }
  run_isolated xcrun xctrace record --template "$instrument_name" --attach "$pid" --time-limit "${duration}s" --output "$trace" --no-prompt || record_status=$?
else
  device_id="${NVE_PERFORMANCE_DEVICE_ID:-}"
  [[ -n "$device_id" ]] || { echo "NVE_PERFORMANCE_DEVICE_ID is required for simulator capture." >&2; exit 2; }
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl launch "$device_id" "$bundle_id" >/dev/null
  for _ in {1..20}; do
    pid="$(xcrun simctl spawn "$device_id" launchctl list 2>/dev/null | awk -v bundle="$bundle_id" '$3 ~ "UIKitApplication:" bundle { print $1; exit }' || true)"
    [[ -n "$pid" ]] && break
    sleep 1
  done
  [[ -n "$pid" ]] || { echo "Could not find the launched simulator app process." >&2; exit 1; }
  run_isolated xcrun xctrace record --template "$instrument_name" --device "$device_id" --attach "$pid" --time-limit "${duration}s" --output "$trace" --no-prompt || record_status=$?
fi

if [[ ! -d "$trace" ]]; then
  echo "xctrace did not create a trace (exit ${record_status})." >&2
  exit "${record_status:-1}"
fi
write_capture_manifest "completed"

echo "Performance capture written to $output_dir"
