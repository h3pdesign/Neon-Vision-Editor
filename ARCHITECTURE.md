# Neon Vision Editor Architecture

Last updated: 2026-08-21 (v1.5.1 release-aligned architecture)

Neon Vision Editor is a native Swift 6 editor for macOS, iOS, iPadOS, and visionOS. The app favors a small editor-first surface: fast file access, lightweight project navigation, native text editing, syntax highlighting, structured document inspection, Markdown/HTML/SVG/PDF/PNG preview, project-level Markdown/PDF cards, Finder Quick Look previews, PDF highlights and attached Markdown notes, Git and terminal helpers on macOS, remote-session clients on supported Apple platforms, and optional contextual AI assistance.

<!-- RELEASE_ARCHITECTURE_ALIGNMENT:START -->
## Current Release Alignment

### v1.5.1 (2026-08-21)

- Adds distinct Plasma and Deep Ocean palettes and strengthens High Contrast, Warm Sepia, Nordic Light, Article, Notebook, Terminal Notes, and Developer Slate.
- Adds Ember Glow, Forest Canopy, Ultraviolet, Cobalt, and Mint Paper for a broader set of vivid, differentiated preview styles.
- Adds theme-specific heading accents, semantic color tokens, richer Markdown component styling, and live-preview/export CSS parity.
- Keeps legacy theme identifiers compatible while preventing visible theme palette collisions.
- Separates Neon Editorial and Nordic Light from default palette fallbacks in the affected appearance modes.
- Adds regression coverage for theme uniqueness, vivid component styling, image captions, and export parity.

### v1.5.0 (2026-08-20)

- Adds ten code-snapshot themes, gradient and transparent backgrounds, configurable window details, typography, padding, corners, and responsive export sizes.
- Adds an opaque editor canvas option for true theme backgrounds while retaining translucent sidebars and window chrome.
- Keeps the Markdown formatting toolbar available as a compact translucent control directly below the macOS tab bar.
- Aligns line numbers to the first visual row of wrapped content at every supported editor font size and line height.
- Makes Up and Down arrow navigation move the caret between visual rows, including wrapped text and viewport transitions.
- Routes Command-W from the editor to the selected tab and preserves the unsaved-changes confirmation instead of closing the window.

This block is regenerated from `CHANGELOG.md` after each stable release. The sections below remain the authoritative description of ownership and runtime boundaries.
<!-- RELEASE_ARCHITECTURE_ALIGNMENT:END -->

## Platform and Product Targets

- Main App Store app target: macOS 14.6+, iOS/iPadOS 18.6+, and visionOS 26.5+.
- Direct-distribution target: `Neon Vision Editor Direct`, built for macOS from the direct release scheme and linked with Sparkle.
- Supporting products: the iOS App Clip, Share Extension, Neon Pulse watch app, Neon Pulse Widget extension, and cross-platform unit-test target.
- The main target's `SUPPORTED_PLATFORMS` includes `macosx`, `iphoneos`, `iphonesimulator`, `xros`, and `xrsimulator`.
- `TARGETED_DEVICE_FAMILY = 1,2,7` for the main app, so shared code must remain valid for iPhone, iPad, and Apple Vision Pro.
- The local build matrix covers macOS, iPhone Simulator, and iPad Simulator. visionOS remains a supported main-app build surface but is not currently part of that script's default matrix.

Keep shared models and services platform-neutral. AppKit code must stay behind `#if os(macOS)`. UIKit-family code must account for both iOS and visionOS, with device-specific presentation guarded explicitly.

## Application Entry and Scene Wiring

- `App/NeonVisionEditorApp.swift` owns process-level setup, default settings registration, app update state, runtime safety, and scene wiring.
- `App/AppMenus.swift` owns macOS menu commands and command routing into the active editor context.
- `ContentView` is the main scene root. It is split across focused extension files for toolbar, actions, preview, session persistence, structured data, quick switcher/find, AI completion, startup overlays, and tab/status chrome.
- `Core/ReleaseRuntimePolicy.swift` centralizes behavior that depends on distribution channel, platform, or safe-mode state.

The shell is primarily SwiftUI. Native AppKit/UIKit representables own text-system behavior, and WebKit representables own rendered previews.

## Core State and Tab Command Model

- `Data/EditorViewModel.swift` owns tabs, file loading/saving, language selection, dirty state, remote document integration, document snapshots, external file refresh, and large-file safeguards. `Data/EditorDocument.swift` defines the backend-neutral document contract; `Data/FileBackedTextDocument.swift` keeps large-file source bytes on disk and records edits for streaming atomic saves; `Data/FileBackedTextViewportAdapter.swift` exposes bounded native-editor windows.
- `Data/GitViewModel.swift` owns Git UI state and delegates repository work to `GitService`.
- `Data/SecureTokenStore.swift` stores AI provider tokens in Keychain.
- `Data/SupportPurchaseManager.swift` isolates StoreKit support-purchase state.
- `Data/PDFAnnotationStore.swift` persists PDF highlight records in versioned app-owned JSON under Application Support. It stores page-space geometry and selected text separately from the source PDF and is not a `UserDefaults` document cache.

`EditorViewModel` is the central editing model and remains `@MainActor`. Tab mutations that may arrive from asynchronous load/save work pass through a serialized `TabCommandQueue`; cached tab-ID and standardized-file-path indexes avoid repeatedly scanning or republishing the full tab array.

A tab ID identifies the UI tab, while `documentResourceID` identifies the file or untitled resource currently represented by that tab. This distinction is required when an empty tab is reused for a project-sidebar file. Document switches may restore the destination resource's caret and viewport; ordinary configuration changes must update the existing native editor rather than replace it.

Avoid moving cross-window or cross-scene state into globals unless it is intentionally process-wide, such as recent files, updater state, or remote-session settings.

## State Ownership and Event Flow

The following ownership boundaries are intentional. Preserve them when adding a feature; moving a value to a more convenient layer can make windows share state or make a native editor apply stale SwiftUI configuration.

- `EditorViewModel` is owned by each editor window. It owns document/tab state and receives file, save, refresh, and selection commands. A detached macOS window creates its own model; process-wide services must not hold a selected tab or caret.
- `ContentView` owns scene-local presentation state: sheets, split visibility, project navigation, transient find/completion state, and the bridges from user actions to the model. Its extension files group those presentations, but do not change the ownership boundary.
- PDF note state (`pdfNoteSourceURL`, `pdfNoteTabID`) and the optional existing Markdown preview are also scene-local. The source PDF remains the preview document while its attached note is selected in the editor pane.
- `CustomTextEditor` and its coordinator own UIKit-family text-control lifecycle state only: delegate callbacks, transient TextKit work, visible-range rendering, and deferred highlight/install tasks. `VirtualEditorView` owns the separate macOS Core Text viewport lifecycle. Configuration changes update either native control in place rather than recreating it.
- `@AppStorage` values are durable user preferences, not document or window state. A key may be read by Settings, `ContentView`, and a native editor bridge, so rename or migration work must update all consumers. API tokens remain outside this schema in `SecureTokenStore`/Keychain.
- Notifications carry window-scoped editor commands only when they include a window number. Broadcast notifications are reserved for process-wide updates such as preference changes.

When tracing a change, follow this path: user action or system callback -> `ContentView`/native coordinator -> `EditorViewModel` command -> tab-state mutation -> SwiftUI/native editor update. File presenters and asynchronous loads re-enter through the same command path so indexes, dirty state, and observation registrations remain consistent.

### ContentView Extension Boundaries

The existing `ContentView` extensions are the seams for future focused work. They share scene-local state through `ContentView`; do not move that state into a second model solely to split a file.

| Boundary | Owner and inputs | Output and focused verification |
| --- | --- | --- |
| Commands and navigation | `ContentView+Actions` accepts user/file-system commands and delegates document mutation to `EditorViewModel`. | Open/save/search results and scene presentation; cover tab/resource identity and dirty-buffer conflict tests. |
| Session restoration | `ContentView+SessionPersistence` owns snapshot encoding, deduplication, and restoration requests. | Restored tabs flow through `EditorViewModel`; cover snapshot migration, duplicate untitled tabs, and multi-window isolation. |
| Preview | `ContentView+PreviewSplit`, `ContentView+MarkdownPreviewUI`, and `ContentView+DocumentPreviewUI` consume the selected tab and preview preferences. | Opt-in preview presentation without document mutation; cover preview-mode transitions, render limits, and compact/inline presentation. |
| Project navigation | `ContentView+ProjectSidebar` and `ContentView+QuickSwitcherFind` consume project index/search results. | File-open commands return to `EditorViewModel`; cover ignored folders, cancellation, stable result identity, and existing-tab activation. |
| AI | `ContentView+AICompletion` and `ContentView+AIChat` consume selected text, provider configuration, and cancellation state. | Suggestions/chat state return to the active tab or panel; cover sensitive-content disclosure, cancellation, and stale-result rejection. |
| Editor chrome | `ContentView+Toolbar` and `ContentView+TabChromeStatus` consume scene presentation state and tab observation. | Toolbar actions, selection/reordering, and status presentation; cover preset filtering, overflow ordering, and selected-tab restoration. |

Any later extraction must first add or retain the focused test named in this table, preserve `EditorViewModel` and scene ownership, and pass the cross-platform build matrix.

## Local Document Lifecycle and External Refresh

Open local files use event-driven file presentation instead of selection-time polling:

- `OpenDocumentObservationCenter` maintains one `NSFilePresenter` for each distinct open local file URL.
- File-presenter callbacks are serialized on utility queues and coalesced before metadata and content are read, covering ordinary writes, atomic-save moves, and deletions without duplicating work.
- Modification date, byte count, and content fingerprints distinguish unchanged provider notifications from real document changes.
- A clean tab reloads in place, including when inactive. Its document resource identity remains stable so caret, selection, source viewport, minimap viewport, encoding, line endings, and preview source can be preserved.
- A dirty tab is never overwritten automatically. It enters the existing conflict flow: **Keep Local**, **Reload from Disk**, or **Compare**.
- Pending, completed, and review-needed tab sets are aggregated into one status-area message for single or multiple documents.

This produces a lightweight cross-device shared-file experience when iCloud Drive or a network folder delivers changes. The storage provider remains the synchronization transport; Neon Vision Editor supplies open-tab observation, refresh, and conflict protection and does not upload document contents itself.

Project-sidebar refresh is a separate operation. It reports visible progress on macOS, iOS, and iPadOS and refreshes the project tree/index without forcing open-document checks during ordinary tab selection.

## Native Editor Stack and Virtual Text Rendering

The editor uses platform-native rendering and input surfaces wrapped for SwiftUI:

- macOS: `UI/VirtualEditorView+macOS.swift` provides the production Core Text viewport renderer via `NSViewRepresentable`; it does not bind a full document string into SwiftUI.
- iOS/iPadOS/visionOS: `UI/EditorTextView+iOS.swift` wraps `UITextView` via `UIViewRepresentable`.
- Shared editor helpers and cross-platform state contracts live in `UI/EditorTextView.swift`.
- macOS drawing, line numbers, selection, hit testing, input, overlay scrollers, and viewport lifecycle live in `UI/VirtualEditorView+macOS.swift` and `UI/MacOverlayScrollers.swift`.
- UIKit-family line numbers and invisible-character markers use lightweight viewport overlays in `UI/EditorTextView+iOS.swift`.

The v1.4.0 editor uses a backend-neutral document core plus a virtualized native text-rendering path for large editable documents:

- `Data/EditorDocument.swift` defines `EditorDocumentStorageKind`, `EditorDocumentViewport`, and the bounded-window/edit contract shared by in-memory and file-backed documents.
- `Data/FileBackedTextDocument.swift` keeps the unchanged source on disk, represents edits as replacement pieces, and streams atomic saves without materializing the full document for every mutation.
- `Data/FileBackedTextViewportAdapter.swift` bridges bounded document windows into the editor layer.
- The macOS `VirtualEditorView` installs only the active bounded viewport, translates caret and selection when the window moves, and rejects stale viewport generations. A file-backed document completes its line index before activation; scrolling only reads and decodes the bounded window around its anchor line.
- Virtualized viewport syntax highlighting and minimap updates are anchored to the visible range. Generation checks prevent late highlight or viewport work from replacing newer content or restoring stale selection state.

This is a rendering and document-storage boundary, not a second document model. Every editable macOS document uses the Core Text virtual renderer; ordinary documents can use an in-memory `EditorDocument`, while large documents can use file-backed bounded windows. Both continue to save through the same document lifecycle and conflict pipeline. UIKit-family platforms retain their separate `UITextView` implementation.

Important editor invariants:

- In macOS wrap mode, SwiftUI allocates the source pane and the virtual canvas treats the current viewport width as authoritative. Visual-fragment caches are keyed by logical line, wrap mode, and available width so preview/sidebar transitions cannot reuse stale rows.
- Overlay scrollbars do not consume editor layout width. The same viewport width drives wrapping, drawing, hit testing, selection, and writable content allocation.
- Do not force document frames or transition-time widths to repair split-layout symptoms. Preview, sidebar, tab, and window changes must naturally reallocate the source pane and trigger one width-consistent virtual-row reflow.
- In no-wrap mode, the virtual canvas may expand horizontally and expose the overlay horizontal scroller.
- Line-number mode preserves the virtual renderer's gutter-aware leading origin; hit testing and selection must use the same gutter geometry as drawing.
- Document installs distinguish resource switches, completed file loads, and external in-place edits. External refresh preserves the viewport, while a real resource switch restores that document's stored caret/viewport state.
- iOS/iPadOS caret restoration is separate from focus restoration. Switching tabs restores position without making the editor first responder or showing the keyboard.
- On iPhone, editor scrolling uses UIKit's `.onDrag` keyboard dismissal; iPad retains its non-dismissal behavior for pointer and hardware-keyboard workflows.
- SwiftUI editor identity is tied to the tab, not the syntax language, so changing language or formatting settings updates the representable in place. The macOS virtualized bridge likewise updates the existing native control and swaps only its bounded viewport. It never relies on a compatibility `Binding<String>`.
- The macOS renderer intentionally uses Core Text rather than TextKit for bounded visual rows. Writing Tools remain disabled because the editor is plain-text/source-oriented. Treat a future renderer migration as a cross-platform editor project, not an isolated layout cleanup.

## Highlighting, Minimap, and Scroll Performance

- Syntax highlighting is regex-based, not TreeSitter-based.
- `Core/SyntaxHighlighting.swift` owns patterns, theme colors, regex caching, bracket-scope matching, and bounded scanners for large JSON/Markdown-like content.
- Highlight work is generation-checked and bounded to relevant ranges. Stale asynchronous passes must not restore an old selection or viewport.
- Geometry-triggered macOS redraw is coalesced and limited to visible virtual rows. Ordinary scrolling must not force full-document layout or display invalidation.
- Minimap snapshots are keyed by tab, content revision, external-refresh revision, language, and large-file mode. Viewport publication uses thresholds so scrolling does not republish insignificant changes.
- Line-number invalidation remains viewport-focused and must not retile or force editor-wide layout from draw callbacks.
- Tab state publishes targeted structure, content, metadata, and persistence revisions. Selection, bounded viewport loading, SwiftUI updates, document projection, minimap/TOC/preview work, and first draw are signposted; completed tab-switch samples are retained locally for comparison.
- Files below the 100 MB partial-open boundary remain editable. Responsive mode can use bounded viewport installation and deferred work for large editable documents; edits are applied through the active viewport and generation-checked rather than rebuilding a full document string. Files at or above 100 MB open as a clearly marked, read-only partial preview of the first 4 MB and cannot overwrite the source. Chunked installs and runtime limits protect typing, highlighting, undo, and memory use without imposing read-only mode on ordinary large editable files.

## Syntax, Language, Crash Reports, and Completion

- `Core/LanguageDetector.swift` maps file extensions and bounded content heuristics to editor language IDs. It also recognizes common Apple crash reports and crash/log content carried in generic `.txt` files.
- `Core/AppleCrashReportParser.swift` parses both legacy text and newer JSON-style Apple crash reports into bounded, severity-tagged sections while preserving access to the raw text.
- `Core/CompletionHeuristics.swift` provides local completion context, keyword fallback, document-word matching, and model-suggestion sanitization.
- `UI/ContentView+AICompletion.swift` coordinates local completion and optional provider-backed completion.
- `Models/AIModel.swift` and `AI/AIClient.swift` define provider models and request plumbing.
- `Core/AppleFMHelper.swift` owns optional on-device Apple Foundation Models access behind compile-time imports, runtime availability, and user settings.

The language registry treats TeX/LaTeX and Typst as source text rather than rendered document formats. `.tex`, `.latex`, `.bib`, `.sty`, and `.cls` files map to the `tex` profile; `.typ` files and bounded Typst/CeTZ content heuristics map to `typst`. NVE provides editing, completion guidance, and syntax highlighting for these files; compilation and PDF generation remain external toolchain workflows, normally launched through the macOS terminal.

## Contextual AI Chat and Sidebar

- `UI/AIChatSidebarView.swift` owns the chat surface, message rendering, context-scope controls, quick actions, saved sessions, and cloud-context disclosures.
- `AIChatConversation` owns scene-local messages, in-flight request cancellation, retry state, and persisted saved sessions. It must not become a process-wide source of selected-tab or editor state.
- `AIChatContext` is an explicit request snapshot. It may include the current selection, current file, or project structure only when the user selects those scopes; project structure contains names and paths rather than file contents.
- Quick actions cover code explanation, bug review, refactoring, tests, documentation, Markdown/story writing, README drafting, and `requirements.txt` drafting. The prompt policy requires language-appropriate syntax, normalized spelling, evidence-based project documentation, and clear uncertainty instead of invented commands or dependencies.
- Context sent to a cloud provider is disclosed before transmission. `AIChatSensitiveContentDetector` warns about likely credentials, tokens, passwords, and private keys; the user must confirm or remove the sensitive material. Apple Intelligence remains an optional on-device provider when the build and OS support it.
- Provider credentials remain in `SecureTokenStore`/Keychain. Chat history stores message text and context summaries only; it must not persist API tokens or silently attach fresh editor contents during restore.
- The sidebar is a presentation surface over the existing editor model. Sending a request must use a captured context snapshot so later tab changes cannot alter an in-flight request, and stale results must not replace newer conversation state.
- The chat surface uses a compact provider/status header, a single-row composer, a context attachment chip, and a lightweight empty state with suggested prompts. These are shared SwiftUI presentation changes; provider behavior, persistence, disclosure, and response actions remain unchanged.

## Markdown and PDF Project Preview Cards

`UI/MarkdownProjectPreview.swift` and `UI/ContentView+MarkdownProjectPreview.swift` provide an optional project-level Markdown/PDF overview beside the existing Markdown preview. This is a navigation surface, not a second editor or a replacement for the project sidebar.

- `MarkdownProjectPreviewModel` projects the existing `ProjectFileIndex` snapshot; it does not create a second filesystem watcher or mutate editor tabs directly.
- The project content filter supports Markdown, PDF, or both. Accepted Markdown extensions are `.md`, `.markdown`, `.mdown`, `.mkdn`, and `.mdx`; PDF cards use `.pdf`. Cards use the standardized file path as identity and are refreshed when the project root or index changes, or when the user explicitly refreshes.
- PDF cards use bounded metadata plus a first-page thumbnail and page count; they do not create a second PDF renderer or rewrite the source file.
- Excerpt and heading extraction are bounded to a 96 KiB text prefix. The first eligible local image is decoded off the main actor, capped at 4 MiB, and downsampled to a 640-pixel thumbnail. Remote HTTP(S) images are never fetched automatically, and paths must remain inside the project root.
- A 100 MiB file is marked as large while the card remains metadata-only; opening the file continues through the existing large-file safeguards.
- Grid and stack layouts share the same card model. macOS supports leading/trailing placement around the Markdown preview and a scene-local resizable width with a 480-point minimum and 500-point default so the card header and filters remain readable; regular-width iPad supports the coordinated split with a fixed card column. Compact iPhone layouts do not add a third permanent column.
- Card activation calls the existing `EditorViewModel` file-opening path, preserving tab identity, caret state, dirty-buffer protection, and window ownership. Context-menu actions reveal the source or refresh the projection without rewriting Markdown.

`Core/NVELock.swift` is the shared lock abstraction used by regex/detection caches and completion gates. Its non-generic storage/destructor box is intentional: it keeps Swift 6 synchronization code compatible with supported deployment targets and avoids a verified Xcode 26.5 release-optimizer crash. Replacing that storage shape requires both the local platform matrix and a compatible remote archive.

The syntax regex cache is shared by app code, but reusable core files must remain test-target-safe when compiled directly into tests.

## Structured Document Modes

`UI/ContentView+StructuredData.swift` owns optional structured presentations while retaining raw-text access:

- CSV/TSV documents can switch between an editable table and text. Table parsing, row limits, column sizing, and serialization remain bounded; truncated snapshots are read-only.
- Property lists can switch between a parsed hierarchy and text.
- Apple crash reports can switch between categorized summary and raw report text, with exception, termination, signal, and faulting-thread details emphasized by severity.
- Recognized log documents can switch between structured event rows and raw text without creating a second document store.
- `Core/PlainTextJSONStructuring.swift` and `UI/ContentView+PlainTextJSON.swift` own the explicit AI-assisted plain-text-to-JSON proposal, validation, and create-or-replace flow. Provider output is never applied before it parses as JSON and the user confirms the proposal.

Parsing and snapshot construction run away from the main actor for non-trivial input. Structured views are alternate presentations of the same tab content, not independent document stores.

## Project Navigation, Search, and Tabs

- `Core/ProjectFileIndex.swift` builds an incremental file index for Quick Open and Find in Files.
- `Core/ProjectIgnoredFolders.swift` owns the default ignored folder list and recent project-folder history.
- `UI/SidebarViews.swift` renders Files, Search, Diff, Git, and macOS Terminal surfaces.
- iPhone and compact-width iPad use a condensed project header and tighter file rows so more of the hierarchy remains visible. macOS keeps its desktop spacing and two-line project-path presentation.
- `UI/ContentView+QuickSwitcherFind.swift` owns Quick Open, symbol navigation, comparison entry points, and Find in Files presentation.
- `UI/ContentView+Actions.swift` owns project setup, file search execution, file opening, Copy Current Editor Reference, and document-transform command handlers.
- The command palette exposes Sort Lines and Sort & Deduplicate Lines through the same transform path; line-sort behavior is covered by `Neon Vision EditorTests/LineSortTests.swift`.
- `UI/ContentView+TabChromeStatus.swift` owns tab selection/reordering chrome, selected/previous-tab markers, external-refresh status, and status-bar presentation.

Find in Files prefers `rg` on macOS when available and falls back to bounded Swift scanning. Search locations use cached line-start offsets. Project tree/index work must retain cancellation and ignored-folder filtering so dependency and build folders do not dominate refresh work.

The Project Sidebar Files filter offers All Files, Modified, Images, PNG, PDF, and Markdown views. PNG and PDF remain supported preview documents in the project tree even though they are not editable source text.

The scrollable tab strip gives each tab a stable ID and uses `ScrollViewReader` to reveal a newly opened or selected tab when it lies outside the visible strip. This navigation must not trigger filesystem polling or broad tab-state publication.

## Diff and Compare

- `Core/DocumentDiff.swift` builds line-oriented document diffs and hunks.
- `UI/DiffComparisonView.swift` renders full document comparisons.
- `UI/FolderCompareView.swift` scans folder pairs and presents changed files.
- `SidebarViews.swift` renders sidebar-hosted diff summaries for tab, disk, Git, and folder-compare flows.

Diff building remains detached for non-trivial inputs. External-file and remote-session conflict views reuse this comparison layer rather than implementing separate diff engines.

## PDF Preview, Highlights, and Notes

- `UI/PDFAnnotationWorkspace.swift` wraps the native PDF view for macOS and UIKit-family platforms while keeping the source PDF read-only.
- PDF and PNG previews open automatically from the toolbar, macOS Launch Services/context-menu opening, paste/drop, and restored tabs. Markdown/HTML/SVG preview remains an explicit preview action.
- Selecting PDF text and choosing Highlight stores the page index, normalized page-space rectangle, selected text, and creation date in `PDFAnnotationStore`. The source PDF is never rewritten; standardized file paths avoid full-document hashing or repeated large reads.
- Notes reuse the existing editor on the left while the source PDF stays on the right. The attached Markdown file is named `<pdf-name>.pdf.notes.md` and is created only after non-whitespace note content exists. Empty or cancelled notes do not trigger Save As and do not create a file.
- An existing Markdown note preview can be shown beside the PDF when explicitly enabled; it reuses the existing `markdownPreviewPane` renderer and is off by default.

## Preview and Export

- `UI/MarkdownPreviewWebView.swift` wraps an ephemeral `WKWebView` on macOS, iOS/iPadOS, and visionOS.
- `UI/ContentView+PreviewSplit.swift` owns the editor/preview allocation and chooses inline versus compact presentation.
- `UI/ContentView+MarkdownPreviewUI.swift` owns preview controls and sharing actions.
- `UI/ContentView+MarkdownPreviewExport.swift` owns HTML generation, copy/export helpers, and PDF options.
- `UI/MarkdownPreviewPDFRenderer.swift` renders one-page or paginated PDF output.
- `UI/ContentView+DocumentPreviewUI.swift` selects native PDF/PNG preview surfaces and automatic activation paths.
- `Neon Vision Editor Quick Look/PreviewViewController.swift` owns the Finder Quick Look extension lifecycle. `PreviewModel.swift`, `MarkdownQuickLookView.swift`, and `EditorView.swift` provide bounded read-only Markdown and source previews without launching the main editor or modifying files.

Markdown, HTML, and SVG previews are opt-in. PDF and PNG previews open automatically when their documents are opened. Compact iPhone layouts use a sheet; macOS, regular-width iPad, and visionOS can use inline panes. Preview reloads are coalesced and preserve relative scroll position.

Web previews use a non-persistent data store, block unsolicited HTTP(S) navigation, and open deliberate external link activations through the system. Raw HTML preview preserves author CSS, colors, backgrounds, and local relative assets while supplying readable defaults only when the document does not define them.

PDF export measures the rendered document, keeps capture anchored at the top, and uses full-document capture plus pagination safeguards so long Markdown documents are not truncated after the first pages.

## Git, Terminal, and Remote Sessions

- `Core/GitService.swift` is a macOS-only actor that shells out to Git.
- `Data/GitViewModel.swift` exposes status, history, fetch/pull/push, and commit details to SwiftUI.
- `UI/SidebarViews+GitTab.swift` renders Git-specific sidebar content.
- `UI/PanelsAndHelpers.swift` contains the PTY-backed macOS terminal surface used by the sidebar and standalone terminal panel.
- `scripts/nve` is the direct macOS command-line helper that forwards file-open requests through Launch Services.
- `Core/RemoteSessionStore.swift` owns saved remote targets, broker state, remote browsing, open/save, and revision conflicts.

Git and terminal process execution remain macOS-only. The command-line helper is not an embedded executable in App Store builds, does not read file contents itself, and must not request Full Disk Access, Accessibility, administrator permission, or weakened App Sandbox settings.

Remote access is opt-in. macOS owns SSH and broker-host execution; iPhone, iPad, and visionOS are attach clients. Remote-session work must not log document contents, prompts, tokens, or sensitive paths beyond user-visible diagnostics.

## Settings, Themes, and UI Infrastructure

- `UI/NeonSettingsView.swift` owns settings, themes, AI tokens, distribution-appropriate update settings, remote sessions, diagnostics, and keyboard shortcuts.
- `UI/ThemeSettings.swift` defines theme models and contrast correction.
- `UI/GlassSurface.swift`, `PanelsAndHelpers.swift`, `ProjectFolderPicker.swift`, `ConfiguredSettingsView.swift`, and `CodeSnapshotComposerView.swift` provide reusable surfaces.
- `Core/AppearanceThemeCloudSync.swift` owns opt-in iCloud Key-Value sync for appearance/theme preferences only.
- `Core/ShortcutPreferences.swift`, `Core/RecentFilesStore.swift`, and `Core/RuntimeReliabilityMonitor.swift` support preferences, recent files, and startup safety.

Settings iCloud synchronization is separate from document synchronization: it covers appearance and theme preferences, not editor contents, files, remote sessions, or API tokens. Font discovery is cached and performed off the main thread.

### Preference Schema

`UI/SettingsInfrastructure.swift` is the canonical registry for preference keys that cross Settings, editor, and theme boundaries. Feature-local keys may remain beside their owner, but a shared key must be promoted there before another feature consumes it. Before adding or renaming a key, identify its owner, default value, all consumers, cloud-sync eligibility, and migration behavior:

- editor behavior and chrome: `ContentView` and the native editor bridges;
- settings controls and theme persistence: `NeonSettingsView` and `ThemeSettings`;
- appearance/theme cloud sync only: `AppearanceThemeCloudSync`;
- secure provider credentials: `SecureTokenStore`/Keychain, never `@AppStorage` or cloud sync;
- per-window frame/session metadata: macOS-only `MacEditorWindowSessionStore` and `ContentView` frame helpers.
- project Markdown preview preferences: `MarkdownProjectPreviewEnabledV1`, `MarkdownProjectPreviewModeV1`, `MarkdownProjectPreviewPlacementV1`, and `MarkdownProjectPreviewSortOrderV1` are shared Settings/editor preferences; `MarkdownProjectPreviewWidthV1` is scene-local width state.
- `MarkdownProjectPreviewContentFilterV1` stores the project-card choice of Markdown, PDF, or both; Markdown remains the default.

## macOS Window and Session Restoration

The primary editor window and each detached editor window have distinct frame autosave names and distinct `EditorViewModel` instances. `MacEditorWindowSessionStore` retains only detached window IDs. `ContentView` records AppKit move/resize notifications under the corresponding autosave name and restores a saved frame only when it still intersects an attached display. The initial window is hidden during that restore so a smaller fallback frame is not flashed before the persisted frame is applied.

At the next launch, the primary window asks whether to reopen all detached windows or only the first. Do not share a window's `EditorViewModel`, cursor, selected tab, or frame key with another window. `defaultSize` remains a first-launch fallback; persisted AppKit frames are authoritative after a user resize.

## Update and Distribution Boundaries

The App Store and direct macOS products deliberately use separate native targets and framework phases:

- `Neon Vision Editor` is the App Store target. Its Release configuration defines `APP_STORE_BUILD`; macOS, iOS/iPadOS, and visionOS bundles remain free of Sparkle framework and updater code, and Apple manages installation and updates.
- `Neon Vision Editor Direct` is used by the direct GitHub scheme. It links Sparkle only for macOS and consumes the signed `appcast.xml` published through GitHub Pages.
- `Core/SparkleUpdateController.swift` compiles a no-op implementation for App Store builds or when Sparkle cannot be imported, and the supported Sparkle controller only for direct macOS builds.
- `Core/AppUpdateManager.swift` remains the update UI/diagnostics façade and release-comparison layer; direct macOS check paths delegate to Sparkle, while `ReleaseRuntimePolicy` hides updater surfaces for App Store and non-macOS distributions.
- `Info-macOS.plist` supplies the appcast URL for direct builds. Appcast release notes carry an `nve-build` marker so same-version replacement builds compare by `CFBundleVersion`.
- `Package.resolved` is committed under the project workspace because Xcode Cloud may disable automatic dependency resolution even though only the direct target links Sparkle.

Do not reattach Sparkle to the shared/App Store target to simplify project configuration. The framework graph, compilation conditions, runtime policy, archive output, and App Store Connect preparation must agree on the distribution boundary.

## Release and CI Architecture

- `scripts/release_prep.sh` synchronizes versions, changelog/release documentation, and release readiness.
- `scripts/release_all.sh` orchestrates direct release modes and resumable hosted/self-hosted notarization paths.
- `scripts/append_release_build_metadata.sh` adds the signed app build number to release notes.
- `scripts/ci/release_gate.sh`, `scripts/ci/build_platform_matrix.sh`, and `scripts/ci/run_syntax_highlighting_regressions.swift` provide release, cross-platform, and focused syntax validation.
- `.github/workflows/release-github-only.yml` builds the direct target, publishes release assets and a signed Sparkle appcast, explicitly dispatches Pages after appcast publication, and can prepare the Homebrew Cask update.
- `.github/workflows/post-release-documentation-sync.yml` waits at least ten minutes after each stable release, regenerates durable README, architecture, website, changelog, and Welcome Tour release surfaces from `CHANGELOG.md`, validates the result, and signed-commits any repaired drift to `main`.
- Hosted and self-hosted notarized workflows are mirrored in `.github/workflows/` and `scripts/workflow-templates/`; changes to one path must keep its template counterpart synchronized.
- Homebrew Cask handoff uses a short-lived GitHub App installation token to update a fork branch. The workflow summary exposes the exact upstream compare/PR URL when automatic upstream PR creation is not permitted.
- `SHA256SUMS.txt`, release asset checksums, code-signature verification, notarization, appcast signatures, and Homebrew hashes all describe the same published ZIP/DMG artifacts and must be regenerated together when an asset is replaced.

Release reruns may operate on an existing tag, so workflows preserve historic download baselines and distinguish release version from build number. Security scanning uses repository-managed CodeQL configuration; do not add a competing advanced workflow unless the repository intentionally switches away from Default Setup.

## Performance and Concurrency Principles

- Keep typing, scrolling, selection, line-number, and minimap work on the smallest visible range possible.
- Do not do file IO, metadata scans, process execution, diff building, PDF preparation, structured parsing, or large language detection on the main actor.
- PDF annotation persistence is asynchronous and lightweight: scroll/selection work must not hash or rewrite the full PDF, and stored geometry must remain in page space so reopening does not depend on a particular zoom level.
- Coalesce provider events, preview reloads, session persistence, and highlight work; cancel superseded tasks by document and generation.
- Prefer cached regexes, cached tab/path indexes, and cached line-start offsets for repeated work.
- Avoid computed SwiftUI properties that sort/filter large collections every render unless input is bounded.
- Treat compact iPhone, regular iPad, and visionOS layouts as first-class surfaces rather than scaling down macOS assumptions.
- Keep compiler-workaround types and explicit concurrency boundaries small, documented, and covered by both local and remote toolchains.

## Testing and Verification

Use targeted tests for isolated logic, then the platform matrix for shared Swift, SwiftUI, editor bridges, project configuration, or platform abstractions:

```bash
scripts/ci/build_platform_matrix.sh
```

The matrix validates macOS, iPhone Simulator, and iPad Simulator builds with code signing disabled. Remove generated `.DerivedData*` folders after manual verification.

Focused regression coverage includes:

- tab/resource identity, cursor/viewport restoration, external refresh, dirty-buffer conflicts, and tab reuse;
- native wrap allocation, ruler-aware origin, line-number geometry, and minimap viewport math;
- Apple crash-report/log detection and structured parsing;
- Markdown long-document PDF pagination;
- Markdown project preview filtering, bounded excerpts/thumbnails, cancellation, stable card identity, placement, resizing, and existing-tab activation;
- PDF/PNG automatic preview activation, PDF highlight persistence and page-space restoration, attached-note creation/empty cleanup, optional existing Markdown preview beside PDF, and PNG/PDF sidebar filters;
- contextual AI scope selection, sensitive-content disclosure, saved-session restore, request cancellation, and stale-result protection;
- TeX/LaTeX extension mapping, content detection, and syntax highlighting;
- updater version/build comparison and distribution-specific behavior;
- representative syntax highlighting through the lightweight Sequoia runner.

For release or build-setting changes, local success is not the finish line: verify the relevant Xcode Cloud/App Store archive or remote notarized workflow and inspect the produced bundle for forbidden or missing frameworks.

For UI changes, also verify:

- VoiceOver labels and traits describe the same controls.
- Keyboard navigation reaches the editor, tab strip, sidebar, toolbar, sheets, settings, structured modes, and preview.
- Focus is not trapped in overlays, diff panes, preview panes, or modal surfaces.
- Compact iPhone, regular iPad, macOS split-pane, and visionOS layouts remain usable.
