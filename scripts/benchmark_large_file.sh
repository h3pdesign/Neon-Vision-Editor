#!/bin/sh
set -eu

line_count="${1:-100000}"
work_dir="${TMPDIR:-/tmp}/nve_large_file_benchmark"
open_after="${NVE_BENCHMARK_OPEN:-0}"
card_count="${NVE_BENCHMARK_CARD_COUNT:-500}"

mkdir -p "$work_dir"

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

write_swift_sample() {
  awk -v max="$line_count" 'BEGIN {
    for (i = 1; i <= max; i++) {
      printf("let value%d = %d // benchmark line with invisible markers candidate\n", i, i)
    }
  }' > "$1"
}

write_json_sample() {
  awk -v max="$line_count" 'BEGIN {
    print "{ \"items\": ["
    for (i = 1; i <= max; i++) {
      comma = i == max ? "" : ","
      printf("  { \"id\": %d, \"title\": \"Item %d\", \"enabled\": true }%s\n", i, i, comma)
    }
    print "] }"
  }' > "$1"
}

write_markdown_sample() {
  awk -v max="$line_count" 'BEGIN {
    print "# Large Markdown Benchmark\n"
    for (i = 1; i <= max; i++) {
      printf("## Section %d\n\n- item `%d`\n- text with **bold** and [link](https://example.com/%d)\n\n", i, i, i)
    }
  }' > "$1"
}

write_project_preview_samples() {
  project_dir="$1"
  mkdir -p "$project_dir"
  index=1
  while [ "$index" -le "$card_count" ]; do
    cat > "$project_dir/card-${index}.md" <<EOF
# Preview Card ${index}

This fixture represents a Markdown project card with **formatted text** and a [link](https://example.com/${index}).

## Details

- Stable fixture ${index}
- Used to measure project-preview indexing and card rendering
EOF
    index=$((index + 1))
  done
}

report_file() {
  file="$1"
  label="$2"
  lines="$(wc -l < "$file" | tr -d ' ')"
  bytes="$(wc -c < "$file" | tr -d ' ')"
  printf "%-12s %9s lines %12s bytes  %s\n" "$label" "$lines" "$bytes" "$file"
}

swift_file="${work_dir}/large-${line_count}.swift"
json_file="${work_dir}/large-${line_count}.json"
markdown_file="${work_dir}/large-${line_count}.md"
preview_project_dir="${work_dir}/project-preview-${card_count}"

start="$(now_ms)"
write_swift_sample "$swift_file"
write_json_sample "$json_file"
write_markdown_sample "$markdown_file"
rm -rf "$preview_project_dir"
write_project_preview_samples "$preview_project_dir"
end="$(now_ms)"

echo "Neon Vision Editor large-file smoke samples"
echo "Work dir: $work_dir"
echo "Generation ms: $((end - start))"
report_file "$swift_file" "Swift"
report_file "$json_file" "JSON"
report_file "$markdown_file" "Markdown"
printf "%-12s %9s cards                     %s\n" "Previews" "$card_count" "$preview_project_dir"
echo
echo "Release smoke checklist:"
echo "1. Open the Swift file, toggle invisible characters, and scroll from top to bottom."
echo "2. Open the JSON file and confirm large-file syntax highlighting stays responsive."
echo "3. Open the Markdown file, open preview, switch templates, then export PDF."
echo "4. Run Find in Files for 'benchmark line' and confirm results remain interactive."
echo "5. Compare the Swift file against a modified copy and confirm large diffs are guarded."
echo "6. Open the project-preview folder and record indexing completion time, peak memory, and retained card count."

if [ "$open_after" = "1" ]; then
  /usr/bin/open -a "Neon Vision Editor" "$swift_file" "$json_file" "$markdown_file" "$preview_project_dir"
fi
