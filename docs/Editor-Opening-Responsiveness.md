# Editor opening responsiveness: regression contract

Status: draft; the single-line rendering fix is **not complete**. These tests
deliberately expose an existing failure and must not be merged as a green fix.
Track the rendering work in issue #595. The separate YAML lexical-coloring change
is PR #600.

## What the old test missed

The previous probe started after creating and laying out the editor. It also set
the large-file flag, although ordinary 2–3 MB documents do not enable the app's
100 MB policy. It stopped before delayed horizontal-width measurement completed.
Consequently it could pass while ordinary opening blocked the main thread.

The revised probe starts before presentation, measures the first timer interval,
waits for installation and the generation's width task, and observes two further
display-link callbacks. A deliberate 30 ms test-only block verifies that work
before the first callback is counted. Display-link callbacks are display
opportunities, **not evidence of physical first-pixel latency**.
The source string is prepared before the probe; file I/O and decoding are not
measured by this editor-host test.

Attachments contain sizes, mode, durations and callback counts, never document
contents. Assertions retain the original one-second main-run-loop gap limit and
add a 30-second overall opening limit. Complete source, editability and absence
of unsolicited keyboard focus are checked. Fixtures cover formatted and minified
JSON, explicit large-file mode, and a single Unicode string on each side of the
syntax-highlighting cutoff.

## Verified findings, 2026-09-20

On the iPhone 17 Pro simulator (iOS 26.5), against develop `6a44efac`, the revised
baseline passed formatted/default, formatted/large-file and probe-control tests.
Minified JSON (2,665,027 bytes) failed: opening and the longest main-thread gap
were both about 34.28 seconds, with zero display callbacks during that interval.
The final measurement patch reproduced the failure on iPad Pro 11-inch (M5),
iPadOS 26.5: approximately 34.80 seconds with zero display callbacks. Its other
three selected tests passed. The final iPhone control/formatted tests passed
(3/3), and macOS compiled and passed the existing shared YAML tests (6/6).

Uncommitted native-renderer experiments bounded the text-view canvas and glyph
painting while retaining native text storage. An atomic deferred installation
experiment reduced the observed opening interval, but still failed the unchanged
gap limit for every pathological fixture. Release gaps were approximately
1.69 seconds (650,000 emoji), 1.28 seconds (500,000 emoji), and 2.35 seconds
(minified JSON). This is not just Debug overhead. These experiments were removed
from production code; they are not a verified fix or a release-speed comparison.

## Acceptance criteria for the rendering phase

- Pass the unchanged opening contracts in optimized builds on iPhone and iPad,
  then profile a physical device before making production performance claims.
- Keep all source bytes; no inserted line breaks, truncation, read-only fallback,
  or altered save output. Validate insert/delete, undo/redo, selection, copy,
  marked text, cancellation and switching documents during installation.
- Verify visible glyphs and selection at both ends of huge lines, Unicode/bidi,
  horizontal scrolling, font/spacing changes, and wrapping toggles. A timing pass
  without correct rendering and editing is insufficient.
- Preserve macOS behavior and its existing native editor implementation.

## Manual cross-platform and accessibility checklist (not yet completed)

- macOS: open the fixtures, edit/save/reopen, undo/redo, toggle wrap and change
  fonts; reach both ends of long lines without clipping or new freezes.
- iOS: repeat with touch selection and the software keyboard; switch tabs during
  opening and background/foreground the app. Compare resulting file contents.
- iPadOS: repeat in split view, with hardware-keyboard navigation, Shift-selection,
  and pointer scrolling. Confirm editor focus remains in the selected document.
- VoiceOver on all platforms: verify editor label/value, selectable content,
  toolbar traversal and dismissal; ensure no focus trap. The measurement patch
  changes no accessibility elements, labels, traits or focus order.

The only production change in this phase exposes pending opening work and clears
the completed width-task handle without clearing a newer generation's task.
No renderer, opening policy, source formatting or telemetry is changed.

## Exact final verification commands

Run from the repository root. The iPad run builds the Debug test bundle reused
by the iPhone run. iPad exits 65 because the minified-JSON contract fails;
macOS and the selected iPhone tests exit zero. The two additional giant-Unicode
contracts are retained but were only run against the rejected renderer during
this session, not certified against the final baseline.

```sh
xcodebuild -quiet -project 'Neon Vision Editor.xcodeproj' -scheme 'Neon Vision Editor' -destination 'platform=macOS' -derivedDataPath /private/tmp/nve-assessment-phases.NNd3Vz/macos -only-testing:'Neon Vision EditorTests/YAMLPreviewDocumentTests' test CODE_SIGNING_ALLOWED=NO

xcodebuild -quiet -project 'Neon Vision Editor.xcodeproj' -scheme 'Neon Vision Editor' -destination 'platform=iOS Simulator,id=74C545F4-FC05-4BCF-B766-4B3FAAAD6B43' -derivedDataPath /private/tmp/nve-assessment-phases.NNd3Vz/ios -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testOpeningProbeIncludesWorkBeforeFirstRunLoopTick' -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testLargeJSONInstallsCompleteUnicodeBufferWithoutClaimingFocus' -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testChunkedJSONOpeningIncludesDelayedWidthWork' -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testMinifiedJSONInstallsCompleteBufferWithoutBlockingRunLoop' -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 test CODE_SIGNING_ALLOWED=NO

xcodebuild -quiet -project 'Neon Vision Editor.xcodeproj' -scheme 'Neon Vision Editor' -destination 'platform=iOS Simulator,id=14E1291D-622E-465D-8EE0-7E1332B48198' -derivedDataPath /private/tmp/nve-assessment-phases.NNd3Vz/ios -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testOpeningProbeIncludesWorkBeforeFirstRunLoopTick' -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testLargeJSONInstallsCompleteUnicodeBufferWithoutClaimingFocus' -only-testing:'Neon Vision EditorTests/MobileEditorInteractionTests/testChunkedJSONOpeningIncludesDelayedWidthWork' -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 test-without-building CODE_SIGNING_ALLOWED=NO
```
