# Performance Profiles and Budgets

Run `scripts/benchmark_large_file.sh` on a quiet machine before changing debounces, caches, or rendering paths. It creates deterministic Swift, JSON, and Markdown files plus a 500-card Markdown project fixture (override with `NVE_BENCHMARK_CARD_COUNT`).

## Capture matrix

| Workload | Measure | Baseline and threshold |
| --- | --- | --- |
| Large Markdown typing and preview | Time to first stable preview, typing hitch count, peak resident memory | Record a baseline per supported OS; investigate a regression of more than 20% or any sustained input hitch |
| 500 project cards | Index completion time, visible-card count, peak resident memory | All cards appear; investigate repeated indexing or a retained-card count above the fixture size |
| Large Git diff | Diff preparation time and retained output bytes | Output remains bounded by the existing Git-service cap; investigate truncation bypasses |
| Sidebar/card toggling | Peak resident memory after 20 toggles and whether it returns near baseline | Investigate monotonic growth across toggles |
| Crash recovery | Serialized payload size and restoration duration | Payload stays within the existing recovery budget and restoration remains interactive |

## Recording protocol

1. Use Instruments Time Profiler and Allocations on macOS, then the equivalent Simulator profile for iPhone and iPad.
2. Start from a fresh launch, keep the same theme and preview layout, and record device/OS/Xcode versions.
3. Repeat each case three times; use the median for time and the largest observed resident memory.
4. Attach the `.trace` or `.xcresult` artifact and the fixture parameters to the change that alters a budget.

## Guardrails

- Do not turn a profile result into a universal hard limit until it is stable on macOS, iPhone, and iPad.
- Keep bounded file reads, card excerpts, Git output, and recovery payloads as correctness limits, not only performance optimizations.
- Treat an increase over 20% from the recorded median as a regression requiring either remediation or an explicit documented trade-off.
