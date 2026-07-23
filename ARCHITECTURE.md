# Neon Vision Editor Architecture

Last updated: 2026-07-23 (v0.9.6)

Neon Vision Editor is a native Swift 6 editor for macOS, iOS, iPadOS, and visionOS. The app favors a small editor-first surface: fast file access, lightweight project navigation, native text editing, syntax highlighting, structured document inspection, Markdown/HTML/SVG preview, Git and terminal helpers on macOS, remote-session clients on supported Apple platforms, and optional AI completion.

## Platform and Product Targets

- Main App Store app target: macOS 14.6+, iOS/iPadOS 18.6+, and visionOS 26.5+.
- Direct-distribution target: `Neon Vision Editor Direct`, built for macOS from the direct release scheme and linked with Sparkle.
- Supporting products: the iOS App Clip, Share Extension, and cross-platform unit-test target.
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

- `Data/EditorViewModel.swift` owns tabs, file loading/saving, language selection, dirty state, remote document integration, document snapshots, external file refresh, and large-file safeguards.
- `Data/GitViewModel.swift` owns Git UI state and delegates repository work to `GitService`.
- `Data/SecureTokenStore.swift` stores AI provider tokens in Keychain.
- `Data/SupportPurchaseManager.swift` isolates StoreKit support-purchase state.

`EditorViewModel` is the central editing model and remains `@MainActor`. Tab mutations that may arrive from asynchronous load/save work pass through a serialized `TabCommandQueue`; cached tab-ID and standardized-file-path indexes avoid repeatedly scanning or republishing the full tab array.

A tab ID identifies the UI tab, while `documentResourceID` identifies the file or untitled resource currently represented by that tab. This distinction is required when an empty tab is reused for a project-sidebar file. Document switches may restore the destination resource's caret and viewport; ordinary configuration changes must update the existing native editor rather than replace it.

Avoid moving cross-window or cross-scene state into globals unless it is intentionally process-wide, such as recent files, updater state, or remote-session settings.

## State Ownership and Event Flow

The following ownership boundaries are intentional. Preserve them when adding a feature; moving a value to a more convenient layer can make windows share state or make a native editor apply stale SwiftUI configuration.

- `EditorViewModel` is owned by each editor window. It owns document/tab state and receives file, save, refresh, and selection commands. A detached macOS window creates its own model; process-wide services must not hold a selected tab or caret.
- `ContentView` owns scene-local presentation state: sheets, split visibility, project navigation, transient find/completion state, and the bridges from user actions to the model. Its extension files group those presentations, but do not change the ownership boundary.
- `CustomTextEditor` and its coordinator own native-control lifecycle state only: delegate callbacks, transient TextKit work, visible-range rendering, and deferred highlight/install tasks. Every `updateNSView`/`updateUIView` refreshes the coordinator's `parent`; a configuration change must update the existing control rather than recreate it.
- `@AppStorage` values are durable user preferences, not document or window state. A key may be read by Settings, `ContentView`, and a native editor bridge, so rename or migration work must update all consumers. API tokens remain outside this schema in `SecureTokenStore`/Keychain.
- Notifications carry window-scoped editor commands only when they include a window number. Broadcast notifications are reserved for process-wide updates such as preference changes.

When tracing a change, follow this path: user action or system callback -> `ContentView`/native coordinator -> `EditorViewModel` command -> tab-state mutation -> SwiftUI/native editor update. File presenters and asynchronous loads re-enter through the same command path so indexes, dirty state, and observation registrations remain consistent.

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

## Native Editor Stack

The editor uses native text controls wrapped for SwiftUI:

- macOS: `UI/EditorTextView+macOS.swift` wraps `NSTextView` in `NSScrollView` via `NSViewRepresentable`.
- iOS/iPadOS/visionOS: `UI/EditorTextView+iOS.swift` wraps `UITextView` via `UIViewRepresentable`.
- Shared editor helpers and cross-platform state contracts live in `UI/EditorTextView.swift`.
- macOS native behavior and draw-time overlays live in `UI/EditorTextView+macOSTextView.swift`.
- macOS line numbers use `UI/LineNumberRulerView.swift`; UIKit-family line numbers and invisible-character markers use lightweight viewport overlays.

Important editor invariants:

- In macOS wrap mode, SwiftUI allocates the source pane and AppKit owns the document width. `NSTextView` is not horizontally resizable, its text container tracks the text-view width, and the scroll view has no horizontal scroll path.
- Do not force document frames or transition-time text-container widths to repair split-layout symptoms. Preview, sidebar, tab, and window changes must naturally reallocate the source pane and let TextKit reflow.
- In no-wrap mode, the text view may expand horizontally and expose the native horizontal scroller.
- Line-number mode preserves AppKit's ruler-aware leading document origin; zero is not always the correct horizontal origin when the vertical ruler is visible.
- Document installs distinguish resource switches, completed file loads, and external in-place edits. External refresh preserves the viewport, while a real resource switch restores that document's stored caret/viewport state.
- iOS/iPadOS caret restoration is separate from focus restoration. Switching tabs restores position without making the editor first responder or showing the keyboard.
- SwiftUI editor identity is tied to the tab, not the syntax language, so changing language or formatting settings updates the representable in place.
- The current editor intentionally uses TextKit 1 layout APIs for its line-number and overlay drawing paths. Writing Tools are disabled because the editor is plain-text/source-oriented. Treat a future TextKit 2 migration as a cross-platform editor project, not an isolated rendering cleanup.

## Highlighting, Minimap, and Scroll Performance

- Syntax highlighting is regex-based, not TreeSitter-based.
- `Core/SyntaxHighlighting.swift` owns patterns, theme colors, regex caching, bracket-scope matching, and bounded scanners for large JSON/Markdown-like content.
- Highlight work is generation-checked and bounded to relevant ranges. Stale asynchronous passes must not restore an old selection or viewport.
- Geometry-triggered macOS redraw is coalesced and limited to the visible character range for larger documents. Ordinary scrolling must not force full TextKit layout or display invalidation.
- Minimap snapshots are keyed by tab, content revision, external-refresh revision, language, and large-file mode. Viewport publication uses thresholds so scrolling does not republish insignificant changes.
- Line-number invalidation remains viewport-focused and must not retile or force editor-wide layout from draw callbacks.
- Files at or above the large-file threshold open as bounded, read-only partial previews; chunked installs and large-file runtime limits protect typing, highlighting, undo, and memory use.

## Syntax, Language, Crash Reports, and Completion

- `Core/LanguageDetector.swift` maps file extensions and bounded content heuristics to editor language IDs. It also recognizes common Apple crash reports and crash/log content carried in generic `.txt` files.
- `Core/AppleCrashReportParser.swift` parses both legacy text and newer JSON-style Apple crash reports into bounded, severity-tagged sections while preserving access to the raw text.
- `Core/CompletionHeuristics.swift` provides local completion context, keyword fallback, document-word matching, and model-suggestion sanitization.
- `UI/ContentView+AICompletion.swift` coordinates local completion and optional provider-backed completion.
- `Models/AIModel.swift` and `AI/AIClient.swift` define provider models and request plumbing.
- `Core/AppleFMHelper.swift` owns optional on-device Apple Foundation Models access behind compile-time imports, runtime availability, and user settings.

`Core/NVELock.swift` is the shared lock abstraction used by regex/detection caches and completion gates. Its non-generic storage/destructor box is intentional: it keeps Swift 6 synchronization code compatible with supported deployment targets and avoids a verified Xcode 26.5 release-optimizer crash. Replacing that storage shape requires both the local platform matrix and a compatible remote archive.

The syntax regex cache is shared by app code, but reusable core files must remain test-target-safe when compiled directly into tests.

## Structured Document Modes

`UI/ContentView+StructuredData.swift` owns optional structured presentations while retaining raw-text access:

- CSV/TSV documents can switch between an editable table and text. Table parsing, row limits, column sizing, and serialization remain bounded; truncated snapshots are read-only.
- Property lists can switch between a parsed hierarchy and text.
- Apple crash reports can switch between categorized summary and raw report text, with exception, termination, signal, and faulting-thread details emphasized by severity.

Parsing and snapshot construction run away from the main actor for non-trivial input. Structured views are alternate presentations of the same tab content, not independent document stores.

## Project Navigation, Search, and Tabs

- `Core/ProjectFileIndex.swift` builds an incremental file index for Quick Open and Find in Files.
- `Core/ProjectIgnoredFolders.swift` owns the default ignored folder list and recent project-folder history.
- `UI/SidebarViews.swift` renders Files, Search, Diff, Git, and macOS Terminal surfaces.
- `UI/ContentView+QuickSwitcherFind.swift` owns Quick Open, symbol navigation, comparison entry points, and Find in Files presentation.
- `UI/ContentView+Actions.swift` owns project setup, file search execution, file opening, and command handlers.
- `UI/ContentView+TabChromeStatus.swift` owns tab selection/reordering chrome, selected/previous-tab markers, external-refresh status, and status-bar presentation.

Find in Files prefers `rg` on macOS when available and falls back to bounded Swift scanning. Search locations use cached line-start offsets. Project tree/index work must retain cancellation and ignored-folder filtering so dependency and build folders do not dominate refresh work.

The scrollable tab strip gives each tab a stable ID and uses `ScrollViewReader` to reveal a newly opened or selected tab when it lies outside the visible strip. This navigation must not trigger filesystem polling or broad tab-state publication.

## Diff and Compare

- `Core/DocumentDiff.swift` builds line-oriented document diffs and hunks.
- `UI/DiffComparisonView.swift` renders full document comparisons.
- `UI/FolderCompareView.swift` scans folder pairs and presents changed files.
- `SidebarViews.swift` renders sidebar-hosted diff summaries for tab, disk, Git, and folder-compare flows.

Diff building remains detached for non-trivial inputs. External-file and remote-session conflict views reuse this comparison layer rather than implementing separate diff engines.

## Preview and Export

- `UI/MarkdownPreviewWebView.swift` wraps an ephemeral `WKWebView` on macOS, iOS/iPadOS, and visionOS.
- `UI/ContentView+PreviewSplit.swift` owns the editor/preview allocation and chooses inline versus compact presentation.
- `UI/ContentView+MarkdownPreviewUI.swift` owns preview controls and sharing actions.
- `UI/ContentView+MarkdownPreviewExport.swift` owns HTML generation, copy/export helpers, and PDF options.
- `UI/MarkdownPreviewPDFRenderer.swift` renders one-page or paginated PDF output.

Markdown, HTML, and SVG previews are opt-in. Compact iPhone layouts use a sheet; macOS, regular-width iPad, and visionOS can use inline panes. Preview reloads are coalesced and preserve relative scroll position.

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
- Hosted and self-hosted notarized workflows are mirrored in `.github/workflows/` and `scripts/workflow-templates/`; changes to one path must keep its template counterpart synchronized.
- Homebrew Cask handoff uses a short-lived GitHub App installation token to update a fork branch. The workflow summary exposes the exact upstream compare/PR URL when automatic upstream PR creation is not permitted.
- `SHA256SUMS.txt`, release asset checksums, code-signature verification, notarization, appcast signatures, and Homebrew hashes all describe the same published ZIP/DMG artifacts and must be regenerated together when an asset is replaced.

Release reruns may operate on an existing tag, so workflows preserve historic download baselines and distinguish release version from build number. Security scanning uses repository-managed CodeQL configuration; do not add a competing advanced workflow unless the repository intentionally switches away from Default Setup.

## Performance and Concurrency Principles

- Keep typing, scrolling, selection, line-number, and minimap work on the smallest visible range possible.
- Do not do file IO, metadata scans, process execution, diff building, PDF preparation, structured parsing, or large language detection on the main actor.
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
- updater version/build comparison and distribution-specific behavior;
- representative syntax highlighting through the lightweight Sequoia runner.

For release or build-setting changes, local success is not the finish line: verify the relevant Xcode Cloud/App Store archive or remote notarized workflow and inspect the produced bundle for forbidden or missing frameworks.

For UI changes, also verify:

- VoiceOver labels and traits describe the same controls.
- Keyboard navigation reaches the editor, tab strip, sidebar, toolbar, sheets, settings, structured modes, and preview.
- Focus is not trapped in overlays, diff panes, preview panes, or modal surfaces.
- Compact iPhone, regular iPad, macOS split-pane, and visionOS layouts remain usable.
