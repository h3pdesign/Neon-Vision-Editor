# Structured JSON preview

## Use

Open a `.json` document (or choose JSON as its language), then use the existing **Preview** eye action. The preview shows the filename, typed values, expandable objects/arrays, and child counts. Keys, strings, numbers, booleans, and null use distinct presentation in light and dark appearance; text type labels ensure color is not the only distinction.

On macOS and regular-width iPad layouts, the preview occupies the existing resizable/secondary preview pane. On compact iPhone/iPad layouts, it uses the existing dismissible preview sheet. Expand/collapse and paging use native buttons, including hardware-keyboard activation. No new global/window-shared state is introduced.

## Scope and safety

This first phase adds the colored tree and validation, not search or value/path copying. It does not replace the editor, format/save the source, call an AI service, or access the network. The SwiftUI patterns skill guided reuse of the existing preview routing and a native List rather than a rendered text block.

Parsing runs in a cancellable background task after a short debounce. Switching documents, editing, and dismissing the view invalidate obsolete work. Key order, duplicate keys, and exact number spelling are retained. Errors identify the line and column of detection.

Preview-specific limits:

- 16 MB of UTF-8 input, 200,000 values, and 128 nested container levels. URL-backed excessive documents are not materialized for this preview.
- 100 children per branch page and at most 2,000 visible rows. Collapse other branches if the visible-row limit is reached.
- Displayed keys are abbreviated after 256 characters and string/number values after 512. These display limits never alter the source.

These bounds trade unlimited tree expansion for predictable UI work. A WebView/full pretty-printed text preview was rejected because it would reintroduce large layout workloads. Full source editing remains separate; the existing extreme single-line UIKit editor limitation in GitHub issue #595 is **not** declared fixed by this preview.

## Integration baseline

The working checkout was fast-forwarded from `1c6f1ce4` to GitHub `main` at `1beaa6ef`, preserving the pre-update edits in the retained stash named `codex-preserve-json-performance-and-preview-title-before-main-update`. Do not apply that stash again over the reconciled changes.

Upstream already supplies ordinary-document string caching and corrected file-backed/in-memory mobile binding selection. Those newer implementations replace the equivalent older local changes. Upstream viewport scroll policy and syntax-formatting precedence are retained. Additional bounded syntax work, Unicode-safe loading chunks, width-measurement improvements, and filename headers are included with this preview. No release was performed.

For the pull request, the feature branch is based on `develop` at `13a92226`. Its application code matches the tested `main` baseline; only unrelated download-metrics documentation differs. No scheme changes are included.

## Acceptance and manual verification

Automated verification on 2026-09-20: macOS 124 passed; iPad simulator 124 passed; iPhone simulator 160 passed with one pre-existing caret-scrolling test failure. A clean checkout of main at `1beaa6ef` reproduced the identical caret assertion and additionally failed the long-line opening-speed test (18.534 seconds, 3-second limit), which the reconciled patch passes. The caret issue is not declared fixed. All 11 new JSON-preview tests pass on each platform.

The parser regression suite covers all JSON types, root primitives, order/duplicate keys, exact large numbers, escapes, malformed input with location, a multi-megabyte array, a 500,000-emoji value, paging, row/depth/size limits, cancellation, and preview-mode toggling.

Interactive checks still required before release:

- **macOS:** open valid and invalid JSON; toggle Preview; expand/collapse and page a large array. Check filename updates, live edits, saved/unsaved source preservation, two independent windows, light/dark themes, keyboard Tab/Shift-Tab and button activation. Check existing Markdown/HTML/PDF previews still route correctly.
- **iPhone:** repeat with the user's actual 2.5 MB JSON; verify the sheet's filename, Done/close controls, expansion, paging, loading cancellation, switching files, background/foreground transitions, and large Dynamic Type. Compare content before and after preview use.
- **iPadOS:** repeat full-screen and in narrow multitasking, including switching between pane and sheet presentation; use a hardware keyboard for navigation, expansion, paging, and dismissal. Verify independent windows/scenes.
- **Accessibility on all three:** VoiceOver reads each key, type, value, nesting level, and container expansion state. Confirm paging context and loading/error text are understandable; check contrast and increased text sizes. Existing preview-header/control traits and ordering are preserved. New rows/buttons use native semantics without programmatic focus capture; verify focus can leave the list and return to close/Done (no focus trap). Live VoiceOver validation remains pending.

Build/test commands and results are retained in the task verification report under `/private/tmp/nve-json-preview.b4nYTe`; generated DerivedData is removed after verification.
