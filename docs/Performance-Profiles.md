# Performance Profiles and Budgets

## Native tab activation regression harness

`VirtualEditorPerformanceTests.testTabSwitchActivationBenchmarkRecordsRealSwiftUIViewportAndDraw` attaches the actual SwiftUI representable to a disposable macOS window, switches between Markdown, Swift and single-line Unicode JSON, and waits for the renderer's real first-draw stage. It reports cold samples and warm median/tail samples. It does not manually mark viewport/draw events and does not open user documents.

Run the focused suite in **Release** with elevated Xcode access:

```bash
xcodebuild -project 'Neon Vision Editor.xcodeproj' -scheme 'Neon Vision Editor' \
  -configuration Release-GitHub ENABLE_TESTABILITY=YES DEAD_CODE_STRIPPING=NO \
  COPY_PHASE_STRIP=NO STRIP_INSTALLED_PRODUCT=NO CODE_SIGNING_ALLOWED=NO \
  -destination 'platform=macOS' \
  -only-testing:'Neon Vision EditorTests/VirtualEditorPerformanceTests' test
```

The test-only overrides enable `@testable` linking without changing shipping settings; Swift still uses Release optimization. The 100 ms warm median / 250 ms warm tail limits are regression ceilings, not an instant-switch claim. This harness isolates native editor activation; separately profile the complete application with preview on/off, cold file-provider reads, multiple windows, and iPhone/iPad hardware. Keep raw traces, median/p95, OS/toolchain, fixture sizes and build configuration with results. Do not equate fixture generation, simulator builds or the native harness with end-to-end device proof.

Initial macOS reads use immutable document snapshots and independent coordinated file handles. Captured indexes are validated against file identity and data generation, not size/mtime alone. Providers without supported version identifiers use a cancellable 256 KiB-chunk fingerprint check of the indexed source bytes; prepared indexes require a complete-source scan on that fallback path, so network/provider cold activation can remain slower. Fingerprints are accumulated during existing index passes without retaining the whole file. Completed reads install only for matching resource/document/activation/revisions. Warm render states are bounded to eight entries with a 16 MiB conservative retention-cost budget, keyed by revisions, caret, theme/font/wrapping and viewport width. This budget estimates retained text/attributed-line cost; use Allocations to measure actual Core Text heap residency. Markdown HTML has a separate six-entry / 8 MiB UTF-8 cache; local-image renders continue bypassing HTML reuse.

### Local optimized harness evidence — 2026-10-14

Xcode 27.0 (27A266a), macOS destination, development 1.9.4/build 1086. All runs used a disposable SwiftUI-hosted native editor window and the same Markdown/Swift/single-line Unicode JSON fixtures, with preview excluded from this native activation benchmark. Test-only linking overrides above were enabled; these are not bit-identical shipping binaries.

| Fresh test-host process | Cold first-draw samples, ms (Swift / JSON / Markdown) | Warm median, ms | Warm p95, ms |
| --- | --- | --- | --- |
| Full regression pass | 9 / 93 / 31 | 2 | 5 |
| Repeat 2 | 100 / 431 / 186 | 3 | 32 |
| Repeat 3 | 358 / 101 / 154 | 5 | 32 |

The full optimized regression pass ran 183 tests with zero failures, including actual WebKit in-place updates/fallback and focus retention, native keyboard/accessibility contracts, lazy snapshot ownership, same-resource document replacement and cancellation. Raw local results/logs are `/private/tmp/NeonOptimization20261014-complete.xcresult`, `/private/tmp/NeonOptimization20261014-perf2.xcresult`, `/private/tmp/NeonOptimization20261014-perf3.xcresult` and their `neon-optimization-*` logs. Temporary result locations are not durable CI artifacts; hosted CI uploads its own runtime results.

PR #772 follow-up (development build 1087): the same-size/preserved-timestamp snapshot regression failed all four rewrite cases before the fix. The final optimized document/layout/activation pass ran 142 tests with zero failures. Fresh-host warm medians were 7 ms (p95 38 ms), 4 ms (p95 32 ms), and 3 ms (p95 7 ms in the complete targeted pass). Two earlier combined passes exceeded the unchanged 100 ms warm ceiling at 113 and 122 ms; those timing failures are retained, not erased or treated as a proven source-validation regression. This benchmark uses in-memory documents, outside the file-validation path. It now logs per-activation UI/viewport/draw stages and window activation/visibility to diagnose scheduling variability. Results are `/private/tmp/nve-pr772-red-exact-20261014.xcresult`, `/private/tmp/nve-pr772-green-20261014.xcresult`, `/private/tmp/nve-pr772-final-20261014.xcresult`, `/private/tmp/nve-pr772-perf-repeat1-20261014.xcresult`, `/private/tmp/nve-pr772-stages-20261014.xcresult`, and `/private/tmp/nve-pr772-final-stages-20261014.xcresult`, with matching log files.

Recorded passing warm runs meet the regression budget, but timings vary across test processes. Cold activation varies considerably and is **not guaranteed instant**. This is not a before/after comparison against v1.9.3, nor proof of complete-app startup, preview-enabled switching, file-provider latency, hardware memory behavior or physical-device accessibility. Those remain separate profiling/sign-off tasks.

Compatible inert Markdown pages update only `main.content`, preserving equal nodes and relative scroll position. Document, base URL, script policy or HTML-shell changes, ambiguous markers, unsafe elements and JavaScript failures fall back to a full navigation. Content scripts remain disabled; no telemetry or new network requests are introduced.

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
- The macOS virtual text renderer draws visible lines with Core Text in `VirtualEditorCanvas`, an `NSView` implementing `NSTextInputClient`. It requests bounded viewport replacements around the scroll anchor and limits syntax highlighting/minimap work to the visible range. Measure viewport installation and replacement as rendering operations, not as full-document open operations.
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

## Primary-screen terminal follow-up

The development terminal now incrementally decodes UTF-8 bytes and parses cursor/erase controls on its output worker. The native text bridge applies immutable changed-suffix patches at the existing 33 ms cadence; retained screen text remains capped at 240,000 UTF-16 units. Alternate-screen applications remain unsupported. The high-volume PTY regression checks completion and bounded output, but is not a substitute for Instruments timing or memory evidence. Re-capture the terminal profile after this screen-rendering change; the v1.8.0 trace above describes the previous append-only implementation.

The full three-run macOS/iPhone/iPad workload matrix remains required before issue #318 is complete. Build success and unit-test results do not supply those profiling measurements.
