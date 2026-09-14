# Performance Profiles and Budgets

Run `scripts/benchmark_large_file.sh` on a quiet machine before changing debounces, caches, or rendering paths. It creates deterministic Swift, TypeScript, JSON, NDJSON, CSV, and Markdown files plus separate 500-card Markdown and PDF project fixtures (override with `NVE_BENCHMARK_CARD_COUNT` and `NVE_BENCHMARK_PDF_CARD_COUNT`).

`docs/performance-baselines.json` is the versioned contract for fixture sizes and stable retained-data limits. `scripts/ci/check_performance_budget.py` verifies that the JSON contract still matches the runtime Git and draft-recovery bounds; it deliberately does not gate raw timings, which vary across hardware and simulator runtimes.

## Capture matrix

| Workload | Measure | Baseline and threshold |
| --- | --- | --- |
| Large Markdown typing and preview | Time to first stable preview, typing hitch count, peak resident memory | Record a baseline per supported OS; investigate a regression of more than 20% or any sustained input hitch |
| 500 project cards | Index completion time, visible-card count, peak resident memory | All cards appear; investigate repeated indexing or a retained-card count above the fixture size |
| Large Git diff | Diff preparation time and retained output bytes | Output remains bounded by the existing Git-service cap; investigate truncation bypasses |
| Sidebar/card toggling | Peak resident memory after 20 toggles and whether it returns near baseline | Investigate monotonic growth across toggles |
| Crash recovery | Serialized payload size and restoration duration | Payload stays within the existing recovery budget and restoration remains interactive |

## Recording protocol

1. Use `scripts/capture_performance_profile.sh macos|iphone|ipad` to create the fixture log, raw Allocations trace, and capture record. Provide `NVE_PERFORMANCE_APP_PATH` for macOS or the booted simulator UDID in `NVE_PERFORMANCE_DEVICE_ID` for iPhone/iPad.
2. Start from a fresh launch, keep the same theme and preview layout, and record device/OS/Xcode versions.
3. Repeat each case three times; use the median for time and the largest observed resident memory.
4. Attach the raw `.trace`, `capture.json`, and fixture log to the change that alters a budget. The capture runner deliberately retains raw traces instead of invoking Xcode 27 beta's unreliable command-line XML exporter; inspect those traces in Instruments rather than treating `Document Missing Template Error` as a missing capture.

## Guardrails

- Do not turn a profile result into a universal hard limit until it is stable on macOS, iPhone, and iPad.
- Keep bounded file reads, card excerpts, Git output, and recovery payloads as correctness limits, not only performance optimizations.
- Treat an increase over 20% from the recorded median as a regression requiring either remediation or an explicit documented trade-off.
- Run `python3 scripts/ci/check_performance_budget.py` in CI or release preflight whenever a retained-data limit changes.

## Large-document editing contract

The v1.4.0 large-file path is file-backed rather than a full-document compatibility copy on every edit:

- `FileBackedTextDocument` keeps the source representation on disk, records UTF-16 edits, preserves the detected encoding and line endings, and streams an atomic replacement on save.
- `FileBackedTextViewportAdapter` supplies bounded text windows to the native editor. Viewport generations reject edits against stale windows, while caret and selection state are translated when a window is replaced.
- The macOS virtual text renderer keeps `NSTextView` attached to the active bounded window, requests replacement windows around the scroll anchor, and limits syntax highlighting/minimap work to the visible range. Measure viewport installation and replacement as rendering operations, not as full-document open operations.
- Large editable documents remain editable below the 100 MB partial-open boundary. The 100 MB-and-above path is intentionally read-only and exposes only the first 4 MB for safe inspection.
- Performance investigations must measure viewport replacement, scrolling, typing, save, and external-change handling separately; a full-document allocation in the per-edit path is a regression.

## Swift 6.4 and OS 27 audit (2026-09-14)

The v1.8.0 performance pass keeps optimizations evidence-driven:

- Terminal ANSI parsing and display sanitization run outside the main actor. The UI receives coalesced incremental attributed chunks every 33 ms and appends them to a native `NSTextView`; it does not rebuild the complete 240,000 UTF-16-unit scrollback value on every publication.
- Git diff presentations precompute changed, inline, and side-by-side display rows once. SwiftUI renders those rows with stable identities instead of filtering and rebuilding arrays during body evaluation.
- The Data iteration benchmark in issue #507 measured `withUnsafeBytes` at 0.32 seconds, RawSpan at 0.59 seconds, and `Data.enumerated()` at 2.12 seconds for the benchmark workload. Keep `withUnsafeBytes`; RawSpan is both OS-27-only and slower for this path.
- Foundation's OS 27 implementations of `Data`, `NSData`, `URL`, `NSURL`, and `CFURL` are runtime replacements, so they require no source-level availability branch. Release and platform-matrix builds require Xcode 27 and the OS 27 SDK family; the project index stays on native `URL` and cached `URLResourceValues`, normalizes its root once per scan, and receives the newer runtime automatically on OS 27 while retaining older deployment targets.
- Keep Swift 6 default main-actor isolation for UI ownership, but explicitly move measured parsing and formatting work off the main actor. Do not enable approachable concurrency as a performance switch.
- Do not add yielding accessors, blanket `@inline(always)`, or `@specialized` attributes until an Instruments trace identifies a remaining copy or dispatch hotspot. These features can increase exclusivity complexity or binary size without improving the current workloads.

The optimized Release-GitHub build was exercised on a MacBook Pro M5 Pro with macOS 27.0 (26A428) and Xcode 27.0 (27A266a). A 16,000-line PTY workload reached its completion marker, retained bounded scrollback, and produced no Instruments hang over 250 ms in a 30-second Time Profiler capture. ANSI work appeared on the processing worker; the incremental text bridge appeared only sparsely in CPU samples.

Automated tab switching covered HTML, CSV, Markdown, Swift, and Ada documents. Full accessibility-tree capture itself produced main-thread stalls while serializing very large editor and WebKit accessibility values, so those stalls are automation overhead and are not accepted as tab-switch latency measurements. Use the deterministic tab-switch and virtual-editor XCTest benchmarks plus the existing `TabSwitch` signposts for regression decisions.

No OS 26 runtime is installed on this machine, so an OS 26 versus OS 27 timing comparison remains unmeasured. Record that comparison on identical hardware before attributing a performance change to OS 27 Foundation or Swift runtime behavior.
