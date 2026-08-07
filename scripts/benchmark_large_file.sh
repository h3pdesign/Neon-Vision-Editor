#!/bin/sh
set -eu

line_count="${1:-100000}"
work_dir="${TMPDIR:-/tmp}/nve_large_file_benchmark"
open_after="${NVE_BENCHMARK_OPEN:-0}"
card_count="${NVE_BENCHMARK_CARD_COUNT:-500}"
pdf_card_count="${NVE_BENCHMARK_PDF_CARD_COUNT:-500}"

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

write_ndjson_sample() {
  awk -v max="$line_count" 'BEGIN {
    for (i = 1; i <= max; i++) {
      printf("{ \"id\": %d, \"event\": \"benchmark\", \"enabled\": true }\n", i)
    }
  }' > "$1"
}

write_csv_sample() {
  awk -v max="$line_count" 'BEGIN {
    print "id,title,enabled,notes"
    for (i = 1; i <= max; i++) {
      printf("%d,Item %d,true,benchmark row %d\n", i, i, i)
    }
  }' > "$1"
}

write_typescript_sample() {
  awk -v max="$line_count" 'BEGIN {
    for (i = 1; i <= max; i++) {
      printf("export interface Item%d { readonly id: number; title: string }\nconst item%d: Item%d = { id: %d, title: `Item %d` }\n", i, i, i, i, i)
    }
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

write_pdf_preview_samples() {
  project_dir="$1"
  mkdir -p "$project_dir"
  template="$project_dir/.performance-template.pdf"
  python3 - "$template" <<'PY'
import pathlib
import sys

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] /Resources << >> /Contents 4 0 R >>",
    b"<< /Length 0 >>\nstream\n\nendstream",
]
data = bytearray(b"%PDF-1.4\n")
offsets = [0]
for number, body in enumerate(objects, start=1):
    offsets.append(len(data))
    data.extend(f"{number} 0 obj\n".encode())
    data.extend(body)
    data.extend(b"\nendobj\n")
xref = len(data)
data.extend(f"xref\n0 {len(objects) + 1}\n".encode())
data.extend(b"0000000000 65535 f \n")
for offset in offsets[1:]:
    data.extend(f"{offset:010d} 00000 n \n".encode())
data.extend(f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
pathlib.Path(sys.argv[1]).write_bytes(data)
PY
  index=1
  while [ "$index" -le "$pdf_card_count" ]; do
    # A valid, one-page PDF keeps PDFKit/card rendering in the measured path
    # without letting fixture I/O dominate the run.
    cp "$template" "$project_dir/card-${index}.pdf"
    index=$((index + 1))
  done
  rm -f "$template"
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
ndjson_file="${work_dir}/large-${line_count}.ndjson"
csv_file="${work_dir}/large-${line_count}.csv"
typescript_file="${work_dir}/large-${line_count}.ts"
markdown_file="${work_dir}/large-${line_count}.md"
preview_project_dir="${work_dir}/project-preview-${card_count}"
pdf_preview_project_dir="${work_dir}/project-preview-pdf-${pdf_card_count}"

start="$(now_ms)"
write_swift_sample "$swift_file"
write_json_sample "$json_file"
write_ndjson_sample "$ndjson_file"
write_csv_sample "$csv_file"
write_typescript_sample "$typescript_file"
write_markdown_sample "$markdown_file"
rm -rf "$preview_project_dir"
rm -rf "$pdf_preview_project_dir"
write_project_preview_samples "$preview_project_dir"
write_pdf_preview_samples "$pdf_preview_project_dir"
end="$(now_ms)"

echo "Neon Vision Editor large-file smoke samples"
echo "Work dir: $work_dir"
echo "Generation ms: $((end - start))"
report_file "$swift_file" "Swift"
report_file "$json_file" "JSON"
report_file "$ndjson_file" "NDJSON"
report_file "$csv_file" "CSV"
report_file "$typescript_file" "TypeScript"
report_file "$markdown_file" "Markdown"
printf "%-12s %9s cards                     %s\n" "Previews" "$card_count" "$preview_project_dir"
printf "%-12s %9s cards                     %s\n" "PDF previews" "$pdf_card_count" "$pdf_preview_project_dir"
echo
echo "Release smoke checklist:"
echo "1. Open the Swift file, toggle invisible characters, and scroll from top to bottom."
echo "2. Open the JSON file and confirm large-file syntax highlighting stays responsive."
echo "3. Open the NDJSON and CSV files, scroll through them, and confirm visible-range highlighting stays responsive."
echo "4. Open the TypeScript file and confirm typing does not queue stale syntax work."
echo "5. Open the Markdown file, open preview, switch templates, then export PDF."
echo "6. Run Find in Files for 'benchmark line' and confirm results remain interactive."
echo "7. Compare the Swift file against a modified copy and confirm large diffs are guarded."
echo "8. Open both project-preview folders and record indexing completion time, peak memory, and retained card count."

if [ "$open_after" = "1" ]; then
  /usr/bin/open -a "Neon Vision Editor" "$swift_file" "$json_file" "$ndjson_file" "$csv_file" "$typescript_file" "$markdown_file" "$preview_project_dir" "$pdf_preview_project_dir"
fi
