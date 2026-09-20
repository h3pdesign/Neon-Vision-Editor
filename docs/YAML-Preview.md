# Syntax-colored YAML preview

## 1. User problem

YAML needs a readable, syntax-colored source preview like a Markdown code block, not a JSON-style object tree.

## 2. Solution

Open a `.yaml` or `.yml` file (or select YAML as its language), then select the existing Preview eye action. The header shows the current filename. Indentation, comments, tags, scalar spelling, and order are preserved; keys, strings, comments, numbers, booleans, and anchors receive light/dark colors. This is lexical highlighting, not a YAML parser or validator. Page boundaries may divide long lines or multiline tokens.

## 3. Scope

Reuses the existing preview pane/sheet and Markdown web surface. No formatter, tree editor, external parser dependency, or source mutation. The SwiftUI UI-patterns skill guided local state ownership and cancellable view-lifetime tasks.

## 4. Alternatives

A decoded tree would lose comments and source presentation. One unlimited rendered block would recreate large-file layout problems. Bounded source pages keep every character accessible without rendering the whole file at once.

## 5. Phases

This phase adds preview routing, bounded coloring, and regression tests. Full YAML semantic validation and formatting are outside scope.

## 6. Patch

`YAMLPreviewDocument` prepares source pages and escaped, syntax-colored HTML off the main actor. `YAMLPreviewView` owns loading, page selection, cancellation, and error states. The shared preview routing exposes the feature on macOS, iOS, and iPadOS. Existing editor cleanup changes are preserved separately.

## 7. Acceptance criteria

- Both YAML extensions and the YAML language choice enable Preview.
- Preview retains exact source content across pages; opening it never modifies or saves the document.
- Keys and values receive readable colors in light/dark appearances.
- Rapid edits, document switches, and dismissal invalidate obsolete work.
- JSON, Markdown, and other preview modes retain their routing.

## 8. Verification checklist

Automated tests cover routing, exact paged-source reconstruction, Unicode, long lines, empty/oversized input, colors, HTML escaping, and cancellation. Run these alongside JSON preview and layout regressions on all three platforms.

Verified 2026-09-20: 35 selected tests passed on macOS, 35 on iPhone 17 Pro (iOS 26.5), and 35 on iPad Pro 11-inch M5 (iPadOS 26.5), with zero final failures. An initial iPad simulator busy/launch failure passed on retry. Exact commands and logs are retained in `/private/tmp/nve-yaml.Y3NZSh/verification.md`; generated build directories were removed.

Manual release checks (not yet executed):

- **macOS:** open YAML and YML; use Preview, resize the pane, select/copy source, navigate Previous/Next with keyboard, close/reopen, and verify the filename. Switch files and windows; confirm independent page state. Check existing Markdown/JSON previews.
- **iPhone:** check the preview sheet, filename, scrolling, paging, Done/close, rapid edits and file switching. Open a 2.5 MB YAML and a very long line; confirm the source editor remains unchanged. Check light/dark and larger accessibility text settings.
- **iPadOS:** repeat in full-screen and narrow multitasking; verify pane/sheet transitions, hardware-keyboard traversal and activation, dismissal, and independent scenes.
- **Accessibility:** Previous/Next retain native button labels, disabled traits, and visual focus order. The web source has a “YAML source” label and remains readable without relying on color. No explicit focus capture is introduced. Verify VoiceOver on all platforms can enter/read/leave the source and reach close/Done without a focus trap; confirm keyboard traversal on Mac/iPad. Live VoiceOver checks remain pending.

## 9. Security and privacy

Source is escaped before insertion into HTML. Content JavaScript is disabled and a restrictive content security policy blocks network/resources/scripts. No telemetry, network requests, file writes, or external YAML tag evaluation are introduced.

## 10. Performance

Preparation and highlighting run in cancellable background tasks. Each page contains at most 200 newline separators or 16,384 Unicode scalars. Preview input is limited to 16 MB; excessive or file-backed documents show an explicit message, leaving editing available. Only the selected page is rendered. Preview limits never truncate or overwrite the source file.
