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
