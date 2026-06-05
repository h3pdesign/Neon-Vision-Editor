# v0.7.5 Performance Audit

Date: 2026-06-05

## Scope

Audited the editor paths most likely to affect release performance:

- File open and save IO
- Large-file mode thresholds
- Syntax highlighting and language detection
- Code minimap and table of contents
- Find in files and project-wide replace
- Diff preparation
- Markdown preview and PDF export smoke coverage

## Measurements

Large-file sample generation was measured with `scripts/benchmark_large_file.sh`.

| Scenario | Generation time | Largest generated sample |
| --- | ---: | ---: |
| 100k | 263 ms | Markdown: 500,002 lines / 9,266,713 bytes |
| 250k | 570 ms | Markdown: 1,250,002 lines / 23,666,713 bytes |
| 500k | 669 ms | Markdown: 2,500,002 lines / 47,666,713 bytes |

These are sample-generation timings, not full UI render timings. They confirm that reproducible large fixtures exist for manual editor smoke testing.

## Current Guardrails

- File open work is moved off the main actor with detached tasks.
- Large file candidates start at 2 MB in the file loader and skip expensive fingerprints above 1 MB.
- Large-file mode is enabled by byte and line thresholds, with lower thresholds on iOS/iPadOS and for HTML/CSV-like documents.
- Language detection is deferred above 180k UTF-16 units and bypassed above 1M UTF-16 units.
- TOC generation is debounced and disabled above 400k UTF-16 units.
- Diff preparation runs off the main actor and caps dynamic-programming work at 1.2M cells.
- Safe Mode disables heavier startup features, Markdown preview, and code minimap.
- DEBUG performance logging records launch, first paint, first keystroke, and recent file-open timings without document content.

## Findings

### P1: Large diff preparation still splits full documents before the DP guard

`DocumentDiffBuilder.build` splits both full inputs into arrays before checking the dynamic-programming cell cap. The DP cap prevents quadratic work, but very large files still pay full line-array allocation and row generation costs.

Status: addressed for 0.7.5. Diff building now applies an early byte/UTF-16 guard before line splitting and returns a summarized guarded diff for very large inputs.

### P1: Large Markdown PDF export needs an explicit release smoke run

The benchmark script generates Markdown samples and lists preview/export steps, but the audit did not launch the app and export the generated 100k/250k/500k Markdown files. Markdown export is likely one of the highest-memory flows because it involves preview layout and PDF rendering.

Status: partially addressed for 0.7.5. Markdown PDF export now has an explicit source byte guard so stress-size files fail with a clear user-facing error instead of entering an expensive render path. Before tagging, manually run the Markdown preview/export checklist at 100k and 250k. Treat 500k as stress-only and acceptable to guard or fail gracefully.

### P2: `updateLargeFileMode(for:)` can rescan the full text while below threshold

The function computes `text.utf8.count` and may scan UTF-16 line breaks until thresholds are crossed. This is acceptable for normal documents, but repeated calls on near-threshold files can become noticeable.

Status: addressed for 0.7.5. Large-file estimates are cached per selected tab, content revision, language, and threshold tuple.

### P2: Find/replace is off-main but whole-file based

Project-wide replacement runs in a detached task, groups matches by file, then reads and rewrites whole file contents. This is simple and safe, but large matched files can spike memory.

Status: addressed for 0.7.5. Project-wide replacement now skips files at or above the large-file candidate threshold and reports skipped matches/files in the result message.

### P2: TOC large-file guard is good, but the snapshot can still retain large content

TOC refresh captures `content` before the 400k UTF-16 guard runs. Swift strings are copy-on-write, so this is usually cheap, but delayed tasks can retain old large snapshots until cancellation/expiration.

Status: addressed for 0.7.5. Sidebar TOC refresh now receives the selected document length and skips scheduling generation for known-large documents.

### P3: Performance measurements are split between runtime logs and manual smoke docs

The app records recent file-open timings, and release docs record fixture generation. There is not yet one automated command that opens sample files and records app-level file-open latency across macOS/iOS/iPadOS.

Recommendation: add a release-only UI/performance harness later, but do not block 0.7.5 on it.

## Release Recommendation

0.7.5 is acceptable to release after manual large Markdown preview/export smoke testing. The key code-level guardrails from this audit have been addressed. The remaining performance opportunity is a future release-only UI/performance harness that opens sample files and records app-level file-open latency across macOS, iOS, and iPadOS.
