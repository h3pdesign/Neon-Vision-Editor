# Markdown Project Preview

Status: Proposed feature specification
Target: Neon Vision Editor 1.1
Default placement: Right of the Markdown preview

## Summary

Add an optional project-level Markdown preview panel. It discovers Markdown files in the currently open project folder and presents them as selectable preview cards. The panel supports a responsive grid and a single-column stack, can be placed on either side of the existing Markdown preview, and has an independently resizable width.

This is a navigation and overview surface, not a second editor. Opening a card must focus the existing document tab and preserve the current tab/document ownership model.

## User experience

### Layout

On macOS and regular-width iPad, the preferred arrangement is one coordinated split layout:

```text
Editor | Markdown preview | Markdown project cards
```

The user can switch the cards to the leading side:

```text
Editor | Markdown project cards | Markdown preview
```

The default is trailing/right placement. The cards panel has its own persisted width and must not be implemented as a second copy of the existing project sidebar. When the available window width becomes too small, the panel should collapse or use the stack layout rather than forcing the editor or preview below its minimum readable width.

On iPhone and compact iPad, present the same content as a sheet, popover, or navigation destination. Do not add a third permanently visible column to a compact layout.

### Grid and stack modes

- **Grid** uses `LazyVGrid` with adaptive columns and a minimum card width of approximately 190–220 points.
- **Stack** uses one `LazyVStack` column and is the compact/sidebar presentation.
- The user can change modes from the panel toolbar and from Settings.
- The selected card uses an accent border and background treatment consistent with the existing editor surfaces.

### Card contents

Each card should show:

- Markdown filename and relative project path.
- A short, wrapped excerpt (normally the first heading and a few following lines).
- File size and last-modified state.
- Heading count when available.
- Text-labelled status badges such as `MD`, `12 KB`, `8 headings`, `Modified`, or `Large file`.
- An optional image thumbnail when the Markdown document contains a usable image.

Use semantic colors only as reinforcement. Every color indicator must also have text or an accessibility label so the state is understandable without color perception.

Card actions:

- Click/tap: open or focus the existing editor tab.
- Context menu: Open, Reveal in Project, and Refresh Preview.
- Keyboard: cards are focusable; Return opens the selected card.

### Image thumbnails

Images should be supported, but card previews must remain bounded and safe:

- Resolve relative image links against the Markdown file's directory, while preventing paths from escaping the current project root.
- Support local project images and embedded `data:` images when their decoded size is below a strict thumbnail limit.
- Recognize standard Markdown images and inline HTML image elements without changing the source document.
- Use a single small thumbnail per card by default. Prefer the first valid image, or the first image near the document's title/introductory content.
- Decode and downsample off the main actor; cache thumbnails by source URL, modification date, and appearance/theme revision.
- Show a neutral placeholder with an `Image unavailable` label when the asset is missing, unsupported, oversized, or invalid.
- Do not fetch remote `http`/`https` image URLs automatically. This preserves the existing preview navigation/privacy policy and prevents a project scan from generating network requests. Remote thumbnails may be a later, explicit user opt-in with clear network disclosure.
- Do not load animated or multi-frame assets repeatedly; select a bounded representative frame or use the placeholder.
- Keep the thumbnail decorative and non-interactive. Opening the card remains the document action; opening an image belongs to the full Markdown preview.

Thumbnail layout rules:

- Grid cards may use a 16:9 or 4:3 thumbnail area with a minimum height of approximately 96 points.
- Stack cards should use a compact leading thumbnail, approximately 64–88 points wide, so text remains readable.
- Preserve aspect ratio with a fitted crop or letterbox treatment consistent across cards.
- Never allow an image's intrinsic dimensions to determine card or panel width.
- Respect reduced-transparency, increased-contrast, and Dynamic Type settings; the thumbnail must not be the only way to distinguish card state.

## Architecture

### Existing integration points

The first implementation should stay within the current ownership boundaries:

- `Core/ProjectFileIndex.swift`: source of project-file enumeration and incremental metadata refresh.
- `Core/ProjectIgnoredFolders.swift`: authoritative ignored-folder policy.
- `UI/ContentView+PreviewSplit.swift`: coordinated editor/Markdown-preview/card allocation and placement.
- `UI/ContentView+MarkdownPreviewUI.swift`: preview-related toolbar actions and visibility affordances.
- `UI/NeonSettingsView.swift` and `UI/SettingsInfrastructure.swift`: settings controls and shared preference registration.
- `Data/EditorViewModel.swift`: existing tab-opening/focus commands; cards must call these commands instead of mutating tabs directly.
- Existing theme/surface and macOS resize helpers: panel background, translucency, divider hit target, and cursor behavior.

Do not add the cards to `ProjectSidebarMode` or overload the project sidebar's left/right placement. The requested placement is relative to the Markdown preview and must remain independent from the project navigator.

### Reuse the existing project index

Extend or compose `ProjectFileIndex` rather than introducing a second filesystem watcher. Its existing snapshot already provides project-root enumeration, ignored-folder filtering, relative paths, modification dates, and file sizes.

The feature should add a Markdown-specific projection of that snapshot:

```swift
enum MarkdownProjectPreviewMode: String {
    case grid
    case stack
}

enum MarkdownProjectPreviewPlacement: String {
    case leading
    case trailing
}

struct MarkdownProjectPreviewSnapshot: Identifiable, Sendable, Hashable {
    let id: String                 // standardized file path
    let url: URL
    let relativePath: String
    let title: String?
    let excerpt: String
    let fileSize: Int64?
    let modificationDate: Date?
    let headingCount: Int
    let isLargeFile: Bool
}

@MainActor
final class MarkdownProjectPreviewModel: ObservableObject {
    // Owns cancellation, snapshots, cache invalidation, and selection only.
}
```

The model must be scene-local, like the editor view model. It must not share a selected file, caret, or tab state between windows.

### Refresh and identity rules

1. Enumerate only the current project root and accepted `.md`/`.markdown` files.
2. Reuse the existing ignored-folder policy and skip hidden files.
3. Sort by standardized relative path for deterministic card order.
4. Use the standardized file path as the stable card identity.
5. Refresh when the project root changes, the project index changes, a file presenter reports an external change, or the user explicitly refreshes.
6. Debounce/coalesce refresh requests; typing in the active editor must not rescan the project.
7. Drop stale asynchronous results when the project root or refresh generation changes.

### Preview extraction and caching

Cards should not instantiate a `WKWebView` for every file. Read a bounded excerpt, extract headings, and discover the first eligible image in a utility task. Cache the result by standardized path, modification date, file size, image source, and theme/layout revision.

- Cap excerpt bytes/lines so large files cannot allocate the entire document.
- Cap image reads and decoded pixel dimensions before creating an `Image`/`NSImage`/`UIImage`.
- Show metadata and `Large file — Open to preview` for files above the existing large-file safety threshold.
- Reuse the existing Markdown parser/highlighting conventions where practical, but keep card rendering lightweight.
- Publish snapshots on the main actor only after cancellation and generation checks.

Image discovery should be syntax-aware enough to ignore fenced code examples, comments, and malformed links. It must not rewrite Markdown or reuse HTML preview DOM state as the source of truth.

## Layout and persistence

Use one parent layout for editor, Markdown preview, and the optional cards panel. Avoid nested geometry readers that independently compete for the same width; that has caused previous preview and resize regressions.

Recommended preferences:

```text
@AppStorage("MarkdownProjectPreviewModeV1")
@AppStorage("MarkdownProjectPreviewPlacementV1")
@AppStorage("MarkdownProjectPreviewEnabledV1")
@SceneStorage("MarkdownProjectPreviewWidthV1")
```

Global preferences belong in the canonical settings registry when consumed by both Settings and the editor shell. The panel width is scene/window state and should remain scene-local.

Recommended width policy:

- Default width: approximately 340 points.
- Grid range: 300–520 points.
- Stack range: 260–420 points.
- Preserve the existing 11-pixel macOS resize hit target.
- Keep the divider's hit surface visually identical to the surrounding editor surface, including translucency mode.
- Hide the panel or fall back to stack mode when editor/preview minimum widths cannot be satisfied.

## Settings and toolbar

Add a **Project Markdown Preview** section under Markdown/Preview settings:

- Enable project card preview.
- Layout: Grid / Stack.
- Placement: Left / Right of Markdown preview.
- Reset panel width.
- Show only Markdown files (enabled by default).

Add a discoverable toolbar toggle near the existing Markdown preview controls. The toggle should reflect visibility without changing the selected tab or preview state.

## Accessibility and visual design

- Use existing editor surface/background styles rather than introducing a new opaque panel color.
- Use 14–18 point corner radii, a subtle separator border, and restrained shadows only where the surrounding window already uses them.
- Use system semantic colors (`accentColor`, `secondary`, `orange`, `green`, `purple`, `red`) and support dark, light, translucent, increased-contrast, and reduced-transparency modes.
- Provide VoiceOver labels containing filename, relative path, size, heading count, and status.
- Ensure focus order follows visual order in both grid and stack modes.
- Support Dynamic Type and at least 44-point touch targets on iPhone/iPad.
- Do not make color the only signal for modified, large, or error states.

## Verification plan

### Unit tests

- Markdown-only filtering, hidden/ignored-folder filtering, and deterministic sorting.
- Stable identity across refreshes.
- Cache invalidation when modification date or file size changes.
- Cancellation when the project root changes during a refresh.
- Large-file excerpt limits.
- Relative image resolution stays inside the project root.
- Missing, oversized, malformed, data, and remote image cases produce the correct thumbnail or placeholder.
- Image cache invalidates when the image asset changes even if the Markdown file itself does not.

### UI tests

- Open a project containing nested Markdown files.
- Verify Grid and Stack modes.
- Verify left and right placement around the Markdown preview.
- Resize the panel and relaunch the window to verify width restoration.
- Select a card and confirm the existing tab is focused rather than duplicated.
- Change the project root and confirm no cards from the previous project remain.
- Exercise translucent and opaque themes, dark/light appearance, keyboard focus, and compact iPad presentation.

### Performance checks

- No filesystem scan on every keystroke.
- No one-WebView-per-card allocation.
- Refreshes are cancellable and coalesced.
- Large projects remain responsive while cards appear progressively.
- Confirm memory and main-thread work with a project containing hundreds of Markdown files.
- Confirm a project containing many large images does not decode all assets eagerly.

## Rollout order

1. Add the Markdown projection model and tests using the existing project index.
2. Add the stack panel and card interaction.
3. Add lazy grid mode and bounded preview caching.
4. Integrate leading/trailing placement into the existing preview split.
5. Add the independent resizer and persistence.
6. Complete compact-platform presentation, accessibility, large-file safeguards, and performance testing.

## Review decisions and risks

### Decisions

- The feature is a project navigator, not an editor or a replacement for the existing project sidebar.
- The right side of the Markdown preview is the default placement.
- Grid and stack are two presentations of one model, not separate data paths.
- Existing file-index, ignored-folder, tab-opening, theme, and resize abstractions remain authoritative.

### Risks to control

- A third column can starve the editor or preview; enforce minimum widths in one parent layout.
- Duplicated watchers can create stale cards and unnecessary filesystem work; reuse `ProjectFileIndex` refresh events.
- Full Markdown rendering per card can exhaust memory; use bounded excerpts and caching.
- Persisted placement/width can become invalid after a window or platform change; clamp only at the layout boundary and provide a reset action.
- Shared Swift files must remain platform-neutral; AppKit resize code stays behind `#if os(macOS)`.

### Acceptance criteria

The feature is ready for release only when all of the following are true:

- Every visible card belongs to the current project root; cards from the previous project disappear after a root change.
- Selecting a card focuses or opens exactly one existing tab and never creates a duplicate for the same standardized URL.
- Grid/stack and leading/trailing choices survive relaunch without changing the existing project-sidebar preference.
- Editor, Markdown preview, and card-panel minimum widths remain valid while the window is resized.
- The divider has the same surface/transparency behavior as adjacent editor regions in both appearance modes.
- Refreshing or typing does not leave stale excerpts, stale selection, or a stuck resize cursor.
- A project with hundreds of Markdown files remains interactive and does not create one WebKit view per card.
- Local and embedded Markdown images render as bounded thumbnails; remote images do not trigger implicit network requests.
- The feature has an accessible keyboard/VoiceOver path and color is never the sole state indicator.

### Deferred decisions

Keep these out of the first slice unless a concrete product requirement appears:

- Pinning/favoriting cards.
- Full rendered Markdown thumbnails.
- Cross-project recent-card history.
- Drag-and-drop reordering.
- A separate database or persistent document cache.

This specification is ready for implementation as a phased feature. The first implementation slice should be the model, stack panel, and tests; grid, placement, and resizing should follow only after that slice is validated.
