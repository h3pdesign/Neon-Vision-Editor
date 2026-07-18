# Neon Vision Editor Architecture

Last updated: 2026-05-15

Neon Vision Editor is a native Swift 6 editor for macOS, iOS, and iPadOS. The app favors a small editor-first surface: fast file access, lightweight project navigation, native text editing, syntax highlighting, markdown preview, Git helpers on macOS, and optional AI completion.

## Platform Targets

- Main app: macOS 15.0+, iOS 18.6+, iPadOS 18.6+.
- Test target: macOS/iOS/iPadOS with Swift 6 settings.
- `SUPPORTED_PLATFORMS` includes `macosx`, `iphoneos`, and `iphonesimulator`.
- `TARGETED_DEVICE_FAMILY = 1,2`, so iPhone and iPad builds must remain valid for shared code.

Keep shared models and services platform-neutral. AppKit code must stay behind `#if os(macOS)` and UIKit code behind iOS/iPad-compatible guards.

## Application Entry

- `App/NeonVisionEditorApp.swift` owns process-level setup, default settings registration, app update state, and scene wiring.
- `App/AppMenus.swift` owns macOS menu commands and command routing into the active editor context.
- `ContentView` is the main scene root. It is split across focused extension files for toolbar, actions, markdown preview, session persistence, quick switcher/find, AI completion, startup overlays, and tab status.

The app is mostly SwiftUI at the shell level, with AppKit/UIKit representables for editor and platform-specific controls.

## Core State Model

- `Data/EditorViewModel.swift` owns tabs, file loading/saving, language selection, dirty state, remote document integration, document snapshots, and large-file safeguards.
- `Data/GitViewModel.swift` owns Git UI state and delegates repository work to `GitService`.
- `Data/SecureTokenStore.swift` stores AI provider tokens in Keychain.
- `Data/SupportPurchaseManager.swift` isolates StoreKit support-purchase state.

`EditorViewModel` is the central editing model. Avoid moving cross-window or cross-scene state into globals unless it is intentionally process-wide, such as recent files or remote-session settings.

## Editor Stack

The editor uses native text controls wrapped for SwiftUI:

- macOS: `UI/EditorTextView+macOS.swift` wraps `NSTextView` via `NSViewRepresentable`.
- iOS/iPadOS: `UI/EditorTextView+iOS.swift` wraps `UITextView` via `UIViewRepresentable`.
- Shared editor helpers live in `UI/EditorTextView.swift`.
- macOS line numbers use `UI/LineNumberRulerView.swift`.
- iOS/iPadOS line numbers and invisible-character markers are drawn by lightweight overlay views in the UIKit editor container.

Important current behavior:

- Syntax highlighting is regex-based, not TreeSitter-based.
- Highlighting is throttled and bounded for large files.
- iOS invisible characters render in a non-interactive viewport overlay instead of inside `UITextView.draw`, so scroll alignment and typing responsiveness stay stable.
- Go to Line avoids full-document line array allocation on iOS by scanning UTF-16 offsets directly.

## Syntax, Language, and Completion

- `Core/SyntaxHighlighting.swift` defines language patterns, theme colors, regex caching, bracket-scope matching, and fast-path scanners for large JSON/markdown-like content.
- `Core/LanguageDetector.swift` maps file extensions and content heuristics to editor language IDs.
- `Core/CompletionHeuristics.swift` provides local completion context, keyword fallback, document-word matching, and model-suggestion sanitization.
- `UI/ContentView+AICompletion.swift` coordinates local completion and optional provider-backed completion.
- `Models/AIModel.swift` and `AI/AIClient.swift` define AI provider models and request plumbing.

The syntax regex cache is shared by app code, but not every file can depend on it when compiled directly into tests. Keep reusable core files test-target-safe.

## Project Navigation and Search

- `Core/ProjectFileIndex.swift` builds a lightweight file index for Quick Open and Find in Files.
- `UI/SidebarViews.swift` renders Files, Search, Diff, and Git sidebar tabs.
- `UI/ContentView+QuickSwitcherFind.swift` owns Quick Open, symbol navigation, tab comparison entry points, and Find in Files presentation.
- `UI/ContentView+Actions.swift` owns project folder setup, file search execution, file opening actions, and many command handlers.

Find in Files prefers `rg` on macOS when available and falls back to bounded Swift scanning. Search result line locations use cached line-start offsets to avoid repeated prefix rescans.

## Diff and Compare

- `Core/DocumentDiff.swift` builds line-oriented document diffs and hunks.
- `UI/DiffComparisonView.swift` renders full diff comparison views.
- `UI/FolderCompareView.swift` scans folder pairs and presents changed files.
- `SidebarViews.swift` also renders sidebar-hosted diff summaries for tab, disk, Git, and folder compare flows.

Diff building should remain detached for non-trivial inputs. Avoid doing large file reads or diff construction on the main actor.

## Markdown Preview

- `UI/MarkdownPreviewWebView.swift` wraps `WKWebView` for macOS and iOS/iPadOS.
- `UI/ContentView+MarkdownPreviewUI.swift` owns preview presentation and sharing actions.
- `UI/ContentView+MarkdownPreviewExport.swift` owns HTML generation, copy/export helpers, and PDF export options.
- `UI/MarkdownPreviewPDFRenderer.swift` renders preview HTML into PDF output.

Markdown preview is device-aware: compact iPhone layouts use sheet-style presentation where needed, while wider macOS/iPad layouts can use split-pane preview.

## Git Integration

- `Core/GitService.swift` is a macOS-only actor that shells out to Git.
- `Data/GitViewModel.swift` exposes repository status, history, fetch/pull/push, and commit details to SwiftUI.
- `UI/SidebarViews+GitTab.swift` renders Git-specific sidebar content.

Git integration is unavailable on iOS/iPadOS. Keep all process execution and AppKit assumptions behind macOS guards.

## Project and Terminal Workflow

- `UI/SidebarViews.swift` owns the project sidebar tabs for Files, Search, Diff, Git, and the macOS-only Terminal tab.
- `Core/ProjectFileIndex.swift` builds the searchable project index off the main actor and skips configured heavy folders.
- `Core/ProjectIgnoredFolders.swift` owns the default ignored folder list (`.git`, `.build`, `node_modules`, `DerivedData`) and recent project folder history.
- `UI/PanelsAndHelpers.swift` contains the lightweight integrated terminal surface used by both the sidebar tab and standalone terminal panel.
- `scripts/nve` is the macOS command-line helper that forwards terminal file-open requests into the app through Launch Services.
- `docs/CommandLineHelper.md` documents the helper permission model, App Sandbox boundaries, and App Store Connect impact.

Terminal process execution remains macOS-only. Project tree/index work must keep cancellation checks and ignored-folder filtering in both the tree and search index paths so large dependency/build folders do not dominate sidebar refreshes.
The current `nve` helper is not an embedded app-bundle executable; it does not read file contents and must not request Full Disk Access, Accessibility, or administrator permission.

## Remote Sessions

- `Core/RemoteSessionStore.swift` owns saved remote targets, broker process/session state, remote file browsing, open/save, and remote conflict details.
- Remote session UI is in `NeonSettingsView` and integrates with `EditorViewModel` for remote document tabs.
- Remote sessions are disabled by default through `SettingsRemoteSessionsEnabled`.

Remote-session work must avoid logging document contents, prompts, tokens, or sensitive paths beyond user-visible diagnostics.

## Settings, Themes, and UI Infrastructure

- `UI/NeonSettingsView.swift` owns settings tabs, theme selection, AI tokens, update settings, remote sessions, diagnostics, and keyboard shortcut settings.
- `UI/ThemeSettings.swift` defines theme models and contrast correction.
- `UI/GlassSurface.swift`, `PanelsAndHelpers.swift`, `ProjectFolderPicker.swift`, `ConfiguredSettingsView.swift`, and `CodeSnapshotComposerView.swift` provide reusable UI surfaces.
- `Core/AppearanceThemeCloudSync.swift` owns opt-in iCloud Key-Value sync for appearance/theme preferences only.
- `Core/ShortcutPreferences.swift`, `Core/RecentFilesStore.swift`, `Core/ReleaseRuntimePolicy.swift`, and `Core/RuntimeReliabilityMonitor.swift` support preferences, recent files, release behavior, and startup safety.

Settings font discovery is cached and performed off the main thread to avoid settings-open hitches.

## Updates and Release Support

- `Core/AppUpdateManager.swift` owns GitHub release checks, asset selection, download/install flow, and sanitized diagnostics.
- `UI/AppUpdaterDialog.swift` renders update status and install actions.
- Release and validation scripts live in `scripts/` and `scripts/ci/`.
- The preferred cross-platform build check is `scripts/ci/build_platform_matrix.sh`.
- `scripts/release_prep.sh`, `scripts/release_all.sh`, `scripts/benchmark_large_file.sh`, and `scripts/ci/release_gate.sh` provide release preparation, notarized publishing, large-file checks, and release readiness validation.

The update manager must keep network calls user-controlled or settings-controlled and must not expose sensitive diagnostics.

## Performance Principles

- Keep typing, scrolling, and selection work on the smallest visible range possible.
- Do not do file IO, process execution, diff building, PDF rendering, or large parsing on the main actor.
- Prefer cached regexes and cached line-start offsets for repeated search/highlight work.
- Keep project indexing bounded by size and cancellation checks.
- Avoid computed SwiftUI properties that sort/filter large collections every render unless the input is already bounded.
- Treat iPhone compact layout as a first-class performance target, especially sidebar, search, preview, and invisible-character rendering.

## Testing and Verification

Use targeted tests for changed logic, then the platform matrix for shared or UI-affecting changes:

```bash
scripts/ci/build_platform_matrix.sh
```

This validates macOS, iOS Simulator, and iPad Simulator builds with code signing disabled. Remove any `.DerivedData*` folders created during manual verification before finishing.

For UI changes, also verify:

- VoiceOver labels and traits still describe the same controls.
- Keyboard navigation still reaches the editor, sidebar tabs, toolbar actions, sheets, and settings controls.
- Focus is not trapped in overlays, diff panes, preview panes, or modal surfaces.
- Compact iPhone and regular iPad layouts remain usable.
