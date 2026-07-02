# Changelog

All notable changes to **Neon Vision Editor** are documented in this file.

The format follows *Keep a Changelog*. Versions use semantic versioning with prerelease tags.

## [v0.8.3] - 2026-07-02

### Why Upgrade
- Fixes the Apple Vision Pro Settings entry path reported during App Store review and hardens settings presentation on first launch.
- Expands Markdown preview compatibility with GitHub Flavored Markdown, safer re-rendering, and syntax-colored code blocks.
- Polishes macOS Settings sizing, translucency, and theme controls while keeping iPad editor and preview text sizes aligned.

### Highlights
- Added GitHub Flavored Markdown as the default preview mode while keeping CommonMark compatibility available.
- Added Markdown code-block language controls and syntax highlighting with theme-aware, higher-contrast colors.
- Enabled line wrap by default for new installs across supported platforms while preserving existing user preferences.
- Reduced editor/preview update overhead so Markdown edits and preview refreshes stay responsive during active typing.
- Required HTTPS for custom AI provider endpoints to keep user-configured network integrations on secure transports.

### Fixes
- Fixed Markdown preview crashes when editing heading markers, changing fenced-code language state, or re-rendering malformed intermediate Markdown.
- Fixed Markdown preview text sizing on iPad so preview text tracks the editor font size instead of rendering noticeably larger.
- Fixed first-open Settings placement and macOS Settings window sizing so theme controls, preview cards, and Markdown Preview settings fit without clipping.
- Restored translucent Settings surfaces in translucent mode and kept vibrant syntax colors distinct from code-block backgrounds.

### Breaking changes
- None.

### Migration
- None.

## [v0.8.2] - 2026-06-29

### Why Upgrade
- Improves visionOS settings with a compact two-pane layout, clearer categories, and less wasted space.
- Fixes visionOS toolbar placement and spacing so actions use the available window width more predictably.
- Refines macOS translucent sidebars and resize handling so editor chrome feels cleaner while preserving usable resize hit areas.

### Highlights
- Reworked visionOS Settings into a narrow category rail and detailed form sections for General, Editor, Appearance, Toolbar, AI, Remote, Shortcuts, and Diagnostics.
- Added compact toolbar settings outside General so long toggle lists no longer create large gaps in the main settings view.
- Tuned macOS sidebar/tab transitions and translucent backgrounds for a smoother editor/sidebar boundary.

### Fixes
- Fixed clipped visionOS welcome controls, blank visionOS app icon metadata, toolbar alignment, and settings backgrounds.
- Fixed macOS sidebar resize cursor behavior by keeping the resize hit zone usable while hiding visible divider rails.
- Fixed right-sidebar tab bar transition behavior so the fade is only active when a sidebar is visible.

### Breaking changes
- None.

### Migration
- None.

## [v0.8.1] - 2026-06-27

### Why Upgrade
- Hardens iPadOS App Store builds by keeping terminal and shell-execution entry points macOS-only, so iPadOS remains a text editor and previewer without code execution.
- Adds a GitHub-only release workflow that can create and publish the release tag, ZIP, DMG, checksums, and release notes from GitHub without local release commands.
- Fixes iPad editor layout issues so the toolbar uses the available editor width and no-wrap Markdown editing can scroll horizontally beside the preview.

### Highlights
- Added a manual GitHub release workflow with dry-run support, secret preflight checks, draft-before-publish release handling, asset verification, SHA256 checksums, and post-release workflow dispatches.
- Added release metadata gates so release docs, README status, project version metadata, and the Welcome Tour What's New page are checked before GitHub release builds.
- Added dedicated SVG and HTML preview panes, including passive HTML rendering inside Markdown preview, with preview coordination moved out of the main content view.
- Split file preview coordination into dedicated preview files and added SVG and HTML web previews beside the source editor.
- Refined iPad top chrome so the editor toolbar fills the available width dynamically while keeping compact controls usable.
- Hardened iPadOS App Store builds by keeping terminal and shell-execution entry points macOS-only.

### Fixes
- Fixed SVG preview rendering so previews fit the pane without adding an extra dark background block.
- Fixed Markdown preview split mode on iPad so no-wrap editor text is horizontally scrollable instead of clipped.
- Fixed iPad toolbar spacing so actions use the full editor toolbar area instead of staying compressed.
- Fixed HTML and SVG preview split visibility so supported preview files can render beside the original source.
- Removed iPadOS-visible terminal affordances from toolbar/help surfaces so the iPad app remains a text editor and previewer without code execution.

### Breaking changes
- None.

### Migration
- None.

### Issues
- None.

## [v0.8.0] - 2026-06-23

### Why Upgrade
- Restores macOS 15 tab bar mouse hit-testing so tabs can be selected and closed normally.
- Fixes macOS translucent editor startup rendering so line numbers no longer appear on a white strip.
- Improves the Welcome Tour release page layout and reduces lightweight completion-trigger allocation while typing.

### Highlights
- Added Xcode Cloud/App Store release runbook and preflight checks for the 0.8.0 release path.
- Kept macOS 26+ tab strip edge fades while skipping the SwiftUI mask on pre-26 macOS where it can intercept tab clicks.
- Updated the Welcome Tour release summary for current App Store-facing changes.

### Fixes
- Fixed macOS 15 tab switching and close-button clicks by avoiding the tab strip fade mask on pre-26 macOS.
- Fixed translucent macOS line-number ruler startup rendering so the ruler stays transparent when the editor background is transparent.
- Fixed the macOS Welcome Tour "What's New" layout so release cards no longer clip or leave stale content at the left edge.
- Reduced completion-trigger scan allocation by checking UTF-16 code units instead of creating one-character substrings.

### Breaking changes
- None.

### Migration
- None.

### Issues
- [#150](https://github.com/h3pdesign/Neon-Vision-Editor/issues/150) `[Bug]: Cannot switch between or close tabs with mouse`

## [v0.7.9] - 2026-06-17

### Why Upgrade
- Adds OpenCode Go as an optional AI completion provider with secure Keychain token storage and a configurable model id.
- Adds a custom OpenAI-compatible provider so compatible hosted or local endpoints can be used for completion.
- Reduces unnecessary completion work by skipping model-backed suggestions in obvious comment and string contexts.
- Makes caret status updates cheaper across macOS, iOS, and iPadOS by avoiding temporary prefix-string allocation while preserving UTF-16 editor offsets.
- Updates Xcode project metadata for current Xcode Cloud and release signing expectations.

### Highlights
- Added OpenCode Go (OpenCode Zen) using the shared OpenAI-compatible chat completions client and the deepseek-v4-flash default model.
- Added Settings controls for selecting OpenCode Go, storing its API token, and configuring the OpenCode model id.
- Added a custom OpenAI-compatible provider with user-configured base URL, model, and optional API key, grouped in its own Settings section.
- Added AI Activity Log diagnostics for failed or empty provider responses, including HTTP status and finish reason, so silent fallbacks are now visible.
- Added shared completion heuristics for comment/string detection and regression coverage for local completions and caret position calculations.
- Added Xcode Cloud manifest metadata and aligned project/scheme upgrade metadata with Xcode 27.
- Enabled recommended deployment target build settings and App Group registration across release-related targets.

### Fixes
- Fixed avoidable AI completion requests when the caret is inside comments or unfinished string literals.
- Fixed caret status calculation paths doing extra string allocation during frequent selection and edit updates.
- Fixed OpenCode Go token lookup so inline completion can use saved Keychain credentials even when Settings state has not been loaded in the active window.
- Fixed release project metadata so App Clip, test, app, and share-extension targets use recommended platform deployment targets consistently.

### Breaking changes
- None.

### Migration
- None. Existing provider selection and stored API keys are unchanged; OpenCode Go and custom providers are opt-in.

### Issues
- [#151](https://github.com/h3pdesign/Neon-Vision-Editor/issues/151) `[Feature]: Support OpenCode Go for an AI Provider`

## [v0.7.8] - 2026-06-11

### Why Upgrade
- Fixes iPhone and iPad editor behavior when line wrap is disabled so long lines continue horizontally instead of clipping at the right edge.
- Makes line wrap the default on fresh iPhone installs while preserving existing user preferences and keeping iPad/macOS defaults unchanged.
- Restores live cursor position updates in the status bar when editing, moving the caret, or jumping between lines.
- Prevents macOS Settings content from scrolling underneath the native preference toolbar.
- Makes GitHub release builds more deterministic by preserving the selected Xcode toolchain and preferring stable Xcode installations.

### Highlights
- Enforced horizontal scrollable content width for the iOS/iPadOS native editor in no-wrap mode.
- Added iOS/iPadOS caret position publishing for edit, selection, large-file install, and programmatic navigation paths.
- Aligned macOS cursor column reporting with the existing 1-based status bar display.
- Hardened local and GitHub release workflows so the selected Xcode installation persists through build and notarization steps.

### Fixes
- Fixed no-wrap text being cut off on iPhone and iPad instead of allowing horizontal scrolling.
- Fixed the cursor status staying at `Ln 1, Col 1` on iPhone after caret movement.
- Fixed programmatic line jumps not always refreshing the cursor status immediately.
- Fixed macOS Settings content scrolling underneath the native preference toolbar icons.
- Fixed release scripts losing `DEVELOPER_DIR` after Xcode selection and added bounded retries for Xcode asset-compiler transients.

### Breaking changes
- None.

### Migration
- None. Existing line wrap preferences remain respected.

## [v0.7.7] - 2026-06-08

### Why Upgrade
- Improves iPad Welcome Tour spacing so the What's New cards, page dots, and navigation buttons sit closer together in compact form sheets.
- Makes iPad Find & Replace more compact and visually consistent by removing redundant inner panel surfaces and tightening field, option, and action spacing.
- Cleans up iPhone sidebar density and translucent sheet presentation for table-of-contents and project navigation.

### Highlights
- Rebalanced Welcome Tour form-sheet geometry on iPad with smaller footer controls, iPad-specific sheet heights, and a lighter bottom fade.
- Tightened iPad Find & Replace sheet width, height, internal padding, picker width, and action button typography.
- Made compact iOS table-of-contents rows narrower with reduced marker, indent, horizontal padding, and row inset values.
- Switched compact iOS table-of-contents and project sidebar sheets to translucent backgrounds with hidden navigation bar backgrounds.

### Fixes
- Fixed excessive empty space between Welcome Tour cards and footer buttons on iPad form sheets.
- Fixed iPad Find & Replace showing stacked inner and outer panel backgrounds instead of a single translucent sheet surface.
- Fixed iPad Find & Replace wasting space around fields, toggles, scope selection, and action buttons.
- Fixed compact iPhone table-of-contents rows being too wide and visually heavy.
- Fixed compact iOS sidebar sheet headers appearing as solid white bars over translucent sidebar content.

### Breaking changes
- None.

### Migration
- None. Existing sidebar, search, and Welcome Tour state is reused.

## [v0.7.6] - 2026-06-07

### Why Upgrade
- Fixes Markdown preview clipping on iPhone by tightening compact preview controls and adding regression coverage for constrained preview widths.
- Stabilizes Swift editor scrolling when bold keywords, current-line highlighting, matching-bracket highlighting, and line wrapping settings interact.
- Improves macOS Settings by making the window user-resizable and reorganizing dense editor/theme controls into cleaner, scroll-safe sections.

### Highlights
- Added configurable status bar items for cursor position, line count, word count, encoding, line endings, indentation, selection size, file size, Git branch/changes, and Markdown preview theme.
- Reworked the macOS Themes settings tab into balanced cards with integrated theme preview, theme selection, theme colors, formatting, and Markdown preview controls.
- Added Markdown preview theme audit coverage and compact clipping fixtures for iPhone-sized layouts.
- Added localization audit coverage for settings/status bar strings.
- Added a manual release QA checklist covering Markdown preview themes, editor overlays, Settings resize behavior, status bar density, and project sidebar spacing.

### Fixes
- Fixed iPhone Markdown preview theme content and control cards being clipped in compact layouts.
- Fixed macOS editor flicker and disappearing text while scrolling Swift code with bold keywords, current-line highlighting, matching-bracket highlighting, and line wrap combinations.
- Fixed macOS Settings layout overflow by enabling resize behavior and using scroll-safe content when the user reduces the window size.
- Fixed project sidebar disclosure icon alignment and nested row spacing so outer and inner project items use consistent gaps.
- Fixed release preflight behavior so older release tags are not blocked by newer README metric expectations.
- Tightened Markdown PDF/export guardrails and regression coverage for compact preview rendering.

### Breaking changes
- None.

### Migration
- None. Existing editor, status bar, theme, and Markdown preview preferences are reused.

## [v0.7.5] - 2026-06-04

### Why Upgrade
- Improves toolbar customization on iPhone and iPad by making custom icon slots match the selected visible toolbar action count.
- Adds a 7-action toolbar density option for iPhone layouts that have room for more than five actions without forcing the 8-action scroll-heavy layout.
- Restores iPad toolbar settings behavior so visible actions respond to the configured toolbar count and custom icon selection.

### Highlights
- Added dynamic custom toolbar icon selection for 4, 5, 6, 7, 8, 10, or all visible actions.
- Added focused regression coverage for toolbar action limits, custom action ordering, and iPad-style custom filtering.
- Added release performance smoke measurements for 100k-line and 250k-line large-file sample generation.
- Added a draggable code minimap viewport marker so dragging the marker scrolls the editor to the matching document position.
- Improved current-line and matching-bracket visibility on macOS with draw-time overlays that stay synced with caret movement.

### Fixes
- Fixed custom toolbar icon selection being capped at 5 even when more visible actions were configured.
- Fixed iPad toolbar customization settings not affecting the visible toolbar action row.
- Fixed the macOS minimap marker appearing as a native scrollbar by hiding the editor scrollbar while the minimap is visible.
- Fixed iPhone and iPad toolbar spacing by removing the extra separator before the three-dot menu and tightening the first iPad tab leading gap.
- Fixed iPhone current-line highlighting so it spans the active editor line and uses a vibrant translucent accent instead of gray.
- Fixed macOS matching-bracket highlighting so it no longer depends on syntax-highlight refreshes and no longer leaves stale bracket backgrounds.
- Optimized macOS current-line and bracket overlay drawing by caching bracket highlight rectangles and respecting dirty-rect repaint bounds.

### Issues
- [#145](https://github.com/h3pdesign/Neon-Vision-Editor/issues/145) `[Feature]: add option to add more custom toolbar icons`
- [#146](https://github.com/h3pdesign/Neon-Vision-Editor/issues/146) `[Bug]: Toolbar options doesent work on iPads`

### Breaking changes
- None.

### Migration
- None. Existing custom toolbar preferences are reused.

## [v0.7.4] - 2026-06-03

### Why Upgrade
- Improves launch stability on macOS 26.x beta systems by deferring startup diagnostics and window chrome work until the first editor window has settled.
- Adds release preflight coverage for App Clip metadata, App Clip card assets, privacy-sensitive logging, and remote Markdown preview guardrails.
- Refines Settings and Safe Mode behavior across macOS, iOS, and iPadOS while preserving the lightweight editor workflow.

### Highlights
- Added App Clip release validation for `CFBundleIconName`, associated App Clip domains, parent app entitlements, and 1800 x 1200 RGB card assets.
- Added automated Markdown preview remote-content checks so HTTP/HTTPS images stay clickable placeholders and the preview WebView remains non-persistent with JavaScript disabled.
- Added privacy log auditing to release preflight so tab contents, prompts, tokens, and local file paths are not introduced into release logging paths.
- Improved Safe Mode messaging and behavior by pausing heavier startup features, Markdown preview, and code minimap during recovery launches.
- Made iPad Settings prefer the largest available sheet size and tuned macOS Settings sizing to avoid scrolling when the screen can fit the full window.

### Fixes
- Fixed a macOS startup crash risk by moving launch completion marking, AI health checks, updater checks, and window tabbing policy out of the earliest layout phase.
- Fixed sensitive AI activity log output by redacting bearer tokens, API-key-like strings, user paths, and file URLs.
- Fixed remote Markdown preview privacy by using a non-persistent WebKit data store and blocking automatic HTTP/HTTPS resource navigation.
- Fixed App Clip App Store validation issues by wiring the App Clip icon asset catalog and parent associated App Clip entitlement.

### Breaking changes
- None.

### Migration
- None.

## [v0.7.3] - 2026-05-29

### Why Upgrade
- Hardens remote editing for shared-network workflows by encrypting broker request and response payloads and moving SSH key bookmarks into Keychain storage.
- Keeps API tokens in Keychain for both Debug and Release builds while migrating legacy UserDefaults token values out of plain preferences.
- Improves editor responsiveness across Git history, Markdown preview, line numbers, invisible-character rendering, syntax highlighting, and large-file workflows.

### Highlights
- Added AES-GCM encryption for Remote Broker transport payloads, with attach-token-derived keys and versioned envelopes.
- Replaced remote Markdown image loads with clickable placeholders so Preview no longer fetches external image resources automatically.
- Improved Git history loading by batching commit metadata and shortstat parsing instead of issuing per-commit status work.
- Reduced Markdown preview churn by keying render cache entries to stable tab revisions and avoiding stale debounced content captures.
- Added App Clip project scaffolding for lightweight launch surface validation ahead of wider release testing.

### Fixes
- Fixed iOS Markdown list Return handling so keyboard replacement ranges no longer delete already typed list text.
- Fixed DEBUG API token persistence so provider keys no longer remain in UserDefaults.
- Fixed remote target persistence so SSH security-scoped bookmark payloads are migrated to Keychain and removed from saved target metadata.
- Fixed Markdown Preview resource handling so remote `http` and `https` image URLs remain user-triggered links instead of automatic network requests.
- Fixed avoidable editor invalidation paths in iOS line numbers, macOS invisible-character drawing, and syntax/minimap updates.

### Breaking changes
- None.

### Migration
- None.

## [v0.7.2] - 2026-05-26

### Why Upgrade
- Keeps editor wrapping and no-wrap scrolling more stable when switching modes across macOS, iOS, and iPadOS.
- Improves Markdown list editing by continuing the active list marker after pressing Return on populated list items.
- Adds optional indentation guides as a separate, off-by-default editor visibility feature for users who want clearer nesting cues.

### Highlights
- Added optional indentation guides with toolbar and settings controls while keeping the default editor appearance unchanged.
- Improved wrap/no-wrap mode changes so scroll position is preserved and horizontal scrolling is restored where expected.
- Improved iOS editor inset handling so line numbers, content, and scroll indicators stay aligned after layout changes.
- Improved Markdown list continuation for unordered and numbered list markers using the configured indentation style.

### Features
- Added off-by-default indentation guide rendering for macOS, iOS, and iPadOS editors.
- Added an Indentation Guides action to the appearance toolbar menus and editor settings.

### Fixes
- Fixed wrap mode updates so toggling line wrap no longer leaves stale text container sizing or loses the visible scroll position.
- Fixed no-wrap editor sizing so long lines can use horizontal scrolling on macOS and iOS/iPadOS.
- Fixed iOS editor inset synchronization to avoid drift between the text area, line numbers, and scroll indicators.
- Fixed Return handling in Markdown lists so populated list items continue with the current marker and normalized indentation.

### Breaking changes
- None.

### Migration
- None.

## [v0.7.1] - 2026-05-20

### Why Upgrade
- Delivers a focused UI overhaul for the editor chrome, project sidebar, TOC sidebar, Markdown preview, minimap, and document tab bar.
- Makes sidebar terminal access more direct: the toolbar and menu now open the Terminal tab in the project sidebar instead of a separate terminal sheet.
- Tightens Apple Foundation Models completion behavior so Apple AI completion uses the real Foundation Models path and never returns simulated placeholder text.

### Highlights
- Refined the project/sidebar visual system with more pronounced rounded containers, cleaner tab cards, stronger outlines, clearer project path presentation, and tighter iPhone/iPad row spacing.
- Improved TOC presentation with more distinct symbols, markers, line badges, language-aware items, rounded sidebar chrome, and cleaner spacing across macOS, iOS, and iPadOS.
- Polished Markdown preview and document tab transitions with rounded preview chrome, softer split transitions, and tab fades only where the UI actually needs them.
- Cleaned up minimap/editor/sidebar edges by removing conflicting divider lines, reducing visual noise, and improving translucent pane backgrounds.

### Fixes
- Fixed the macOS toolbar Terminal button so it selects the existing sidebar Terminal tab and preserves that sidebar terminal session while switching tabs.
- Removed the old integrated terminal sheet path that opened a separate terminal window.
- Removed simulated Apple Intelligence completion output and stopped returning unavailable-message text as a completion.
- Fixed Apple Foundation Models health checks and explicit Apple AI calls so they are gated by real system availability instead of a global completion-toggle flag.
- Removed the horizontal separator under document tabs on iOS and iPadOS.
- Reduced overly transparent macOS inter-pane gaps in all translucency modes.
- Reduced iPhone/iPad TOC and project file row gaps for denser, cleaner sidebar navigation.

### Breaking changes
- None.

### Migration
- None.

## [v0.7.0] - 2026-05-19

### Why Upgrade
- Adds a lightweight integrated terminal tab in the sidebar while preserving the current terminal session when switching tabs.
- Improves large-editor navigation with a wider, scroll-synced, color-coded code minimap for supported code files.
- Tightens editor performance, markdown preview/export behavior, sidebar ergonomics, and project tree refresh behavior across macOS, iOS, and iPadOS.

### Highlights
- Added optional code minimap support with section, declaration, import, property, control-flow, comment, and code markers.
- Added an in-app command-line helper section and optional bundled `nve` helper flow that remains user-initiated and sandbox-friendly.
- Added sidebar terminal integration, markdown preview theme refinements, project tree ignored-folder handling, and more reusable ContentView/sidebar structure.

### Fixes
- Fixed minimap scroll sync by deriving viewport fractions from the actual editor viewport and shared minimap offset math.
- Improved minimap readability by widening the strip and avoiding an all-blue accent block.
- Reduced repeated large-file work in folder compare, diff filtering, markdown export, theme resolution, and project-tree refresh paths.
- Improved settings dropdown sizing/alignment and sidebar tab hit targets.

### Breaking changes
- None.

### Migration
- None.

## [v0.6.9] - 2026-05-15

### Why Upgrade
- Invisible-character rendering on iPhone and iPad is more responsive and stays aligned while scrolling.
- Syntax highlighting, completion, Find in Files, and folder compare now avoid several repeated main-thread or allocation-heavy paths.
- Sidebar navigation is easier to tap across macOS, iOS, and iPadOS with larger card-style tab targets.

### Highlights
- Improved project sidebar tab affordance across macOS, iOS, and iPadOS with larger card-style Files/Search/Diff/Git targets and visible grey inactive states.
- Tightened Swift 6 syntax-highlight data flow by marking highlight value types as `Sendable` where they cross background highlight closures.
- Updated architecture and release documentation for the current Swift 6, cross-platform editor structure.

### Fixes
- Fixed iOS invisible-character rendering so space, tab, and newline markers stay aligned while scrolling instead of drifting with reused text content.
- Reduced iOS invisible-character overhead by drawing markers in a non-interactive viewport overlay and avoiding full TextKit invalidation when the preference is unchanged.
- Improved syntax-highlighting responsiveness by compiling regexes outside the shared cache lock and bounding fallback bracket-scope searches near the caret.
- Reduced large JSON fast-highlight allocation churn by comparing JSON literals directly instead of creating temporary substrings.
- Improved local completion responsiveness by reusing the shared document-word regex cache.
- Improved Find in Files result positioning by caching line-start offsets instead of repeatedly rescanning file prefixes.
- Moved Folder Compare file reads and diff construction off the main actor before presenting the diff UI.

### GitHub Issues
**Closed:**
- #131 `[Bug]: Invisible Character Display Option Nearly Unusable`

### Breaking changes
- None.

### Migration
- None.

## [v0.6.8] - 2026-05-14

### Why Upgrade
- App Store uploads now use a valid three-component marketing version after the v0.6.7 train closed.
- iPhone sidebar workflows are more reliable for Find in Files and tab/file diff presentation on compact screens.
- Release metadata validation now catches malformed marketing versions instead of accepting partial matches.

### Highlights
- Bumped the release train to `v0.6.8` while keeping hotfix differentiation in `CURRENT_PROJECT_VERSION`.
- Moved compact iPhone Git/file/tab diff presentation into the project sidebar instead of presenting clipped standalone diff windows.
- Kept iPhone Find in Files result groups compact by showing each file's match count once, in the blue hit badge.
- Preserved v0.6.7 feature work while making the hotfix distributable through App Store Connect.

### Fixes
- Fixed App Store Connect rejection caused by invalid `CFBundleShortVersionString` values such as `0.6.7.1`.
- Fixed release-prep and release-metadata validation so malformed marketing versions like extra numeric components or suffixes are not treated as valid stable versions.
- Fixed compact iPhone Find in Files result headers so the match count is not duplicated above the grouped result.
- Fixed compact iPhone diff presentation clipping by keeping sidebar-hosted diff views inside the project sidebar.

### Breaking changes
- None.

### Migration
- None.

## [v0.6.7] - 2026-05-13

### Why Upgrade
- Swift 6 migration work is now substantially safer across macOS, iOS, and iPadOS with stricter actor isolation fixes and cross-platform build coverage.
- Git workflows are more useful inside the editor with working-tree status, branch history, commit diff viewing, and a visual graph tab.
- Find in Files now lives in the project sidebar on compact devices, making iPhone search navigation and selection more consistent.
- Release automation now validates changelog, README, marketing version, and build-number consistency with short actionable fix guidance before release.

### Highlights
- Migrated project build settings toward Swift 6 language mode and fixed related Sendable/main-actor diagnostics across editor, settings, AI, markdown preview, and remote-session code.
- Added Git service/view-model infrastructure for sandbox-aware repository status, fetch/pull/push actions, history, branch graph data, and commit diff presentation.
- Added Git sidebar tabs for Changes, History, and Graph, including per-commit insertion/deletion summaries and a visual graph canvas for branch history.
- Added structured Git diff presentation using the existing editor diff UI, including translucent styling when enabled.
- Added Find in Files as a project-sidebar tab on macOS/iOS/iPadOS, with compact iPhone layout tuning, sidebar activation from toolbar search, and result selection that opens files and highlights matches.
- Added project sidebar polish for Git/search workflows, including wider graph/history presentation, translucent sidebar surfaces, and compact heading adjustments.
- Added split-editor support for opening two tabs at once and comparing active tabs with sidebar-hosted diff output.
- Added shared release metadata validation used by local prep and CI preflight.
- Updated Neon Glow and Neon Flow built-in palettes with stronger, more readable accent colors across light and dark appearances.

### Fixes
- Fixed macOS project-sidebar file taps so opening files from the sidebar is routed through a main-actor action.
- Fixed iPhone project-sidebar file taps so the compact sidebar dismisses before opening the selected file.
- Fixed iPhone Find in Files keyboard/layout clipping and button wrapping in compact layouts.
- Fixed iPhone file-sidebar behavior so selecting a file opens it and closes the sidebar.
- Fixed remaining Swift 6 test actor-isolation failures in completion, syntax highlighting, release policy, shortcut, recent-file, theme, and translucency tests.
- Fixed release-preflight failures so missing changelog/README/version/build-number requirements now report exact recovery commands.
- Fixed compact iPhone Settings > General ordering so Toolbar settings sit at the bottom.

### Milestone Issues
**Closed:**
- #120 [Feature] Structured plist editor with collapsible sections and type-aware rendering
- #122 [Enhancement] Release automation guardrails for build number and changelog sync

### Breaking changes
- None.

### Migration
- None.

## [v0.6.6] - 2026-05-09

### Why Upgrade
- File opening from Finder/system dialogs is now more robust: existing windows are brought back to the foreground instead of staying in the background.
- Empty startup tabs are now cleanly reused when opening a file, preventing unnecessary extra tabs.
- Large UI monoliths were further modularized, making follow-up fixes significantly lower risk.
- iPad hardware shortcuts can now be configured directly in Settings and keyboard editing is fully reliable (text selection, copy/cut/paste, undo/redo, close tab).
- Toolbar customization on iPhone/iPad is more practical with visibility controls for primary icons and an optional compact custom 5-icon mode.
- `plist` files can now be shown in a structured, collapsible tree view alongside raw text.
- Welcome Tour and support prompt flows now share a consistent modern visual style, with improved spacing and button ergonomics on iPhone, iPad, and macOS.
- Release gating now runs as a single script step that combines the platform matrix build and release preflight checks.

### Highlights
- Improved external file-open routing on macOS: after opening, the target editor window is brought to foreground and activated.
- Added clean untitled tab replacement flow in `EditorViewModel.openFile(url:)` when only a single untouched placeholder tab exists.
- Continued structural split of oversized UI files:
  - `EditorTextView` in shared/macOS/iOS files
  - `ContentView` responsibilities split into focused extensions (session persistence, AI completion, quick switcher/find, markdown preview UI, tab/status chrome)
- Added self-assignable editor shortcuts in Settings (command format like `cmd+shift+f`) with default reset support.
- Added a structured plist mode with sorted dictionary keys, color-coded value-type badges, and collapsible tree rows.
- Added a new Quick Open command (`Open plist Structure`) that switches to structured plist mode when a plist file is active.
- Expanded regression coverage for syntax highlighting (JSON/Markdown/HTML/CSS/C/C#/Swift/Python), shortcut parsing, and Markdown PDF pagination ranges.
- Redesigned Welcome Tour pages around a translucent full-surface layout with feature-specific symbols, a dedicated “What’s New” card format, and tuned navigation controls.
- Redesigned the post-start support prompt to match the Welcome Tour style, with centered content/actions and symbol-backed benefit bullets.
- Added `scripts/ci/release_gate.sh` as the unified final release gate (`build_platform_matrix` + `release_preflight`) and wired `release_all.sh` to use it.
- Added iPhone/iPad toolbar favorite-count control with compact presets (`4`, `5`, `6`, `8`, `10`, `All`) for visible primary actions.
- Added dedicated visibility toggles for the four primary toolbar icons (`Open File`, `Undo`, `Settings`, `Help`) on iPhone/iPad.
- Added an optional compact `Custom 5 Icons` mode with a picker sheet so users can choose up to five specific toolbar actions without cluttering Settings.
- Added user-configurable `Close Tab` shortcut support (`Cmd+W` default) to shared shortcut preferences and iPad keyboard command bridge.
- Updated GitHub Actions workflow dependencies to Node-24-ready action versions (`actions/checkout@v5`, `actions/setup-python@v6`).

### Fixes
- Fixed background-open behavior where files opened externally could load without reliably surfacing the correct editor window.
- Fixed tab proliferation on first open by replacing a pristine untitled tab instead of always creating a second tab.
- Fixed macOS dock-icon click not reactivating the editor window by adding `applicationShouldHandleReopen` delegate.
- Fixed `Reopen Last Session` on sandboxed macOS setups for files outside the app container by performing file-existence checks under active security-scoped resource access.
- Fixed macOS shortcut settings mismatch by wiring menu commands to `ShortcutPreferences` and re-enabling the shortcut section as functional UI.
- Fixed iPad text-selection regressions with Magic Keyboard/trackpad and external mice by stabilizing responder handling and pointer-drag selection behavior in the editor.
- Fixed iPad Magic Keyboard Cmd+A selection not working by registering dedicated `UIKeyCommand` in `EditorTextView+iOS.swift`.
- Fixed iPad hardware-keyboard editing parity by adding explicit `Cmd+C`, `Cmd+X`, `Cmd+V`, `Cmd+Z`, and `Cmd+Shift+Z` command routing in the editor.
- Fixed iPad `Cmd+W` so closing the active tab now works through the iPad keyboard shortcut bridge.
- Fixed iPad pointer/cursor text selection reliability by preventing drag-to-dismiss behavior from competing with editor selection gestures.
- Fixed JSON URL/escape highlighting regressions by enforcing coverage for escaped string patterns and numeric tokens.
- Fixed markdown PDF range slicing edge cases with explicit single-page and dense-block pagination tests.
- Fixed release-flow robustness when release metadata files are already dirty by allowing release scripts to continue when only approved release files changed.
- Fixed compact-toolbar customization scope so reducing visible primary actions no longer affects actions exposed through the `...` (More) menu.
- Added regression test coverage for clean-tab replacement on file open (`EditorViewModelFileOpenTests`).

### Milestone Issues (GitHub #18)
**Closed:**
- #111 [Bug]: OSX: when opening file via standard app, app window is not in foreground
- #124 [Feature]: Toolbar favorites count on iPhone/iPad with independent More menu
- #100 [Bug]: selecting text with Magic Keyboard not possible
- #108 [Feature]: Add structured plist editor support
- #107 [Bug]: not aligned text in language search box
- #106 [Bug]: empty space in search window
- #105 [Bug]: Label for German language not aligned
- #97 [Feature]: Clarify toolbar customization settings
- #109 [Feature]: Add self-assignable key commands

### Breaking changes
- None.

### Migration
- None.

## [v0.6.5] - 2026-05-06

### Why Upgrade
- iPhone search and TOC navigation now reliably jump to the selected result after file load completes.
- SSH-based commit signing is now supported for verified GitHub contributions.
- Codebase security and crash audit passed with zero critical issues.

### Highlights
- Fixed Find in Files result tapping on iPhone: cursor now jumps to the correct match once the target file finishes loading.
- Fixed TOC sidebar item tapping on iPhone: sheet now dismisses after jumping to the selected document section.
- Added SSH commit signing configuration for verified GitHub workflows.
- Completed full security and stability audit: no `fatalError`, `try!`, or sensitive logging found.

### Fixes
- Resolved race condition where `.moveCursorToRange` notifications were posted before file content was available on iPhone.
- Resolved TOC sidebar sheet not dismissing after navigation on compact iOS layouts.
- Replaced unreliable 80ms delay with state-driven file load completion callback for search jumps.

### Milestone Issues (GitHub #17)
**Closed:**
- #96 [Feature]: Improve JSON tools discoverability

### Breaking changes
- None.

### Migration
- None.

## [v0.6.4] - 2026-05-02

### Why Upgrade
- iPad and iPhone workflows are more complete, with toolbar customization, native iPad command menus, and direct share/open-in support for Markdown documents.
- JSON documents now have built-in formatting and one-line combine tools from the app menus.
- Hardware-keyboard editing on iPad is more reliable for search and selection.
- The v0.6.4 quality baseline includes Markdown PDF export regression coverage, mobile parity documentation, and compact-layout accessibility checks.

### Highlights
- Added JSON document actions for `Format JSON` and `Combine JSON Lines`, available from macOS menus and iPadOS/iOS command menus.
- Added Settings controls for iPhone/iPad toolbar groups so Search, Compare, Editor Tools, and Preview/Appearance actions can be shown or hidden.
- Added native iPadOS command menus for File, Find, Tools, Help, Settings, Toolbar Help, and Welcome Tour entry points.
- Added GitHub and Feature Request links to the in-app Support settings section.
- Added iOS document type metadata for Markdown so `.md` and `.markdown` files are advertised as editable text documents in Files/share/open-in flows.
- Added v0.6.4 release QA and mobile parity documents covering PDF export, toolbar/sidebar behavior, compact layout, and accessibility expectations.

### Fixes
- Fixed iPad external-keyboard typing in the Find field so live search preview no longer steals focus after each character.
- Fixed iPad hardware-keyboard Select All handling so `Cmd+A` reaches the editor selection path even with custom key command handling.
- Fixed long Markdown PDF export regression coverage so paginated and one-page export paths are validated against full-document output.
- Fixed iPhone/iPad compact layout documentation and QA coverage for toolbar, sidebar, diff header, preview, and dialog clipping risks.
- Fixed README roadmap and Project Documentation formatting for the v0.6.4 quality release.
- Fixed invisible-character rendering coverage tracked by the v0.6.4 known issue work.

### Milestone Issues Addressed (`0.6.4`)
- [#89](https://github.com/h3pdesign/Neon-Vision-Editor/issues/89) `[Bug]: Add regression coverage for long Markdown PDF exports`
- [#90](https://github.com/h3pdesign/Neon-Vision-Editor/issues/90) `[Docs]: Update README roadmap for v0.6.4 quality release`
- [#91](https://github.com/h3pdesign/Neon-Vision-Editor/issues/91) `[Feature]: Audit mobile parity for toolbar and project sidebar actions`
- [#92](https://github.com/h3pdesign/Neon-Vision-Editor/issues/92) `[Bug]: Audit compact iPhone and iPad layout clipping`
- [#93](https://github.com/h3pdesign/Neon-Vision-Editor/issues/93) `[Docs]: Create v0.6.4 release QA checklist from recent regressions`
- [#94](https://github.com/h3pdesign/Neon-Vision-Editor/issues/94) `Invisible characters do not appear in the iOS editing area`
- [#96](https://github.com/h3pdesign/Neon-Vision-Editor/issues/96) `[Feature]: add JSON format options`
- [#97](https://github.com/h3pdesign/Neon-Vision-Editor/issues/97) `[Feature]: add customization to toolbar/menu`
- [#98](https://github.com/h3pdesign/Neon-Vision-Editor/issues/98) `[Feature]: Add support for iOS 26 status bar`
- [#99](https://github.com/h3pdesign/Neon-Vision-Editor/issues/99) `[Feature]: add button for GitHub into app`
- [#100](https://github.com/h3pdesign/Neon-Vision-Editor/issues/100) `[Bug]: selecting text with Magic Keyboard not possible`
- [#103](https://github.com/h3pdesign/Neon-Vision-Editor/issues/103) `[Bug]: typing in search field not possible with external keyboard`
- [#104](https://github.com/h3pdesign/Neon-Vision-Editor/issues/104) `[Feature]: Add share menu entry`

### Breaking changes
- None.

### Migration
- None.

## [v0.6.3] - 2026-04-28

### Why Upgrade
- Native diff workflows are now available for comparing the current tab against disk and comparing two open tabs.
- iPhone and iPad toolbar/help surfaces are more discoverable, with a dedicated Toolbar Help entry and scrollable compact toolbars.
- Markdown Preview export is more reliable, including complete paginated PDF output and flexible one-page exports with tighter margins.
- Project sidebar actions on iPhone now open the expected file/folder pickers and keep new-file prompts stable.
- Markdown, plain-text extension handling, themes, and support-purchase messaging are more accurate across platforms.

### Highlights
- Added a native side-by-side diff view with change navigation, accessible hunk summaries, Compare with Disk, and Compare Open Tabs entry points.
- Added a full Toolbar Help section that explains toolbar symbols, groups actions by workflow, adapts to iPhone/iPad/macOS widths, and is reachable from the toolbar, macOS Help menu, and menu-bar extra.
- Expanded iPhone/iPad toolbar coverage so commonly used and previously overflow-only actions are visible in the scrollable toolbar, with Toolbar Help pinned next to Settings on iPad.
- Updated the Welcome Tour with the latest major features and a live support-purchase card that avoids premature App Store price-unavailable states.
- Added `.bak` plain-text support and improved `.zshrc`/dotfile loading behavior.
- Improved Markdown language detection and Markdown syntax highlighting for task lists, tables, reference links, front matter, images, autolinks, block quotes, thematic breaks, comments, and metadata-style lines.
- Added the `AMOLED Neon` editor theme and tuned several neon/raw theme string colors for clearer contrast.
- Improved Markdown Preview typography on iPad and PDF export behavior for paginated and single-page output.

### Fixes
- Fixed iOS Save File behavior so saving an existing file no longer behaves like Save As.
- Fixed iPhone project-sidebar toolbar buttons so Open File/Open Folder actions present the expected picker dialogs.
- Fixed iPhone project-sidebar new-file creation so the filename dialog no longer disappears immediately and the new tab is created.
- Fixed iPhone diff-view header sizing so Compare Local vs Disk labels wrap less aggressively on compact widths.
- Fixed Code Snapshot on iPhone to default to Wrap layout for new composer sessions.
- Fixed support-page and Welcome Tour support pricing so primary actions do not show `Unavailable` before StoreKit availability has been checked.
- Fixed one-page Markdown PDF export so a single page uses tighter margins and a flexible page length based on content.
- Fixed paginated Markdown PDF export so all pages include their full captured text content.
- Fixed Settings window close behavior on macOS.
- Fixed translucent-window line-number/theme readability regressions.

### Milestone Issues Addressed (`0.6.3`)
- [#33](https://github.com/h3pdesign/Neon-Vision-Editor/issues/33) `Roadmap: Native side-by-side diff view`
- [#70](https://github.com/h3pdesign/Neon-Vision-Editor/issues/70) `[A11Y]: Define keyboard and VoiceOver behavior for diff navigation`
- [#71](https://github.com/h3pdesign/Neon-Vision-Editor/issues/71) `[Feature]: Compare two open tabs in a native diff view`
- [#72](https://github.com/h3pdesign/Neon-Vision-Editor/issues/72) `[Feature]: Compare current tab against on-disk version`
- [#83](https://github.com/h3pdesign/Neon-Vision-Editor/issues/83) `[Feature]: Change Translucent Window setting makes line numbers hard to read`
- [#84](https://github.com/h3pdesign/Neon-Vision-Editor/issues/84) `[Bug]: Close Settings window`
- [#85](https://github.com/h3pdesign/Neon-Vision-Editor/issues/85) `[Bug]: .bak ext. not supported??`
- [#86](https://github.com/h3pdesign/Neon-Vision-Editor/issues/86) `[Bug]: .zshrc content not showing`
- [#87](https://github.com/h3pdesign/Neon-Vision-Editor/issues/87) `[Bug]: Save File acts like Save As on iOS`
- [#88](https://github.com/h3pdesign/Neon-Vision-Editor/issues/88) `Add .bak extension support as plain text`

### Breaking changes
- None.

### Migration
- None.

## [v0.6.2] - 2026-04-24

### Why Upgrade
- Find-in-files now supports selective project-wide replace with explicit preview and cancellation controls.
- Navigation and edit workflows are faster with direct `Go to Line` and `Go to Symbol` commands.
- macOS sidebar and tour overlays are more comfortable and consistent for daily keyboard/mouse use.
- Project sidebar disclosure controls now align better with file rows and are easier to recognize.

### Highlights
- Added selective project-wide replace from `Find in Files` with match selection controls (`Select All`, `Select None`), apply, and cancel.
- Added `Go to Line` and `Go to Symbol` entry points for faster in-document navigation.
- Improved Code Snapshot composer layout on macOS so settings controls track the snapshot composition width more tightly.
- Added support for opening `.cif` and `.mcif` files as plain-text documents.
- Added a configurable project-sidebar disclosure symbol style (`Chevron`, `Triangle`, `Caret`, `Plus/Minus`) in sidebar/global settings.

### Fixes
- Fixed macOS sidebar disclosure spacing so project disclosure controls are no longer pinned too close to the left edge.
- Fixed project sidebar row alignment so folder/file content columns line up consistently.
- Fixed project sidebar nested-file spacing for improved readability in expanded folders.
- Fixed macOS caret disclosure rendering by mapping to supported SF Symbols.
- Fixed macOS welcome-tour presentation so the tour window opens centered relative to the host editor window.
- Fixed Code Snapshot settings container default width so it no longer spans the full available sheet width on macOS.

### Milestone Issues Addressed (`0.6.2`)
- [#73](https://github.com/h3pdesign/Neon-Vision-Editor/issues/73) `[Feature]: Add project-wide replace with preview`
- [#74](https://github.com/h3pdesign/Neon-Vision-Editor/issues/74) `[Feature]: Add Go to Symbol for the current document`
- [#75](https://github.com/h3pdesign/Neon-Vision-Editor/issues/75) `[Feature]: Add Go to Line command`
- [#76](https://github.com/h3pdesign/Neon-Vision-Editor/issues/76) `[A11Y]: Add left padding and larger hit area for project disclosure controls`
- [#82](https://github.com/h3pdesign/Neon-Vision-Editor/issues/82) `[Feature]: Editor to open CIF files (Crystallographic Information File) or mcif`

### Breaking changes
- None.

### Migration
- None.

## [v0.6.1] - 2026-04-16

### Why Upgrade
- The project sidebar is now more complete for day-to-day file management with better structure controls and direct item actions.
- Markdown Preview toolbar controls are cleaner and more discoverable with dedicated export/style actions plus localized labels.

### Highlights
- Added project sidebar item actions for creating files/folders, plus rename, duplicate, and delete flows.
- Refined project sidebar visual hierarchy and interaction density for clearer navigation in large trees.
- Added a dedicated Markdown Preview style toolbar button and consolidated export options into toolbar menus that appear only when preview is active.
- Expanded localization coverage for new Markdown Preview toolbar strings (including Simplified Chinese additions).

### Fixes
- Fixed missing localization coverage for newly introduced Markdown Preview toolbar labels/help text.
- Fixed Markdown Preview toolbar/menu availability so controls appear only in Markdown Preview mode.

### Closed Issues (Milestone `0.6.1`)
- [#77](https://github.com/h3pdesign/Neon-Vision-Editor/issues/77) `[UI]: Refine project sidebar layout and visual hierarchy`
- [#78](https://github.com/h3pdesign/Neon-Vision-Editor/issues/78) `[Feature]: Add rename, delete, and duplicate actions for project items`

### Breaking changes
- None.

### Migration
- None.

## [v0.6.0] - 2026-03-30

### Why Upgrade
- Remote workflows are clearer on every active surface, with better tab/session state, safer conflict recovery, and more complete iPhone/iPad remote-session support.
- Search, `Find in Files`, and `Find & Replace` are much more mature across macOS, iPhone, and iPad, with stronger keyboard flow, clearer match visibility, better sizing, and cleaner panel layouts.
- Markdown Preview is more polished on all platforms with stronger live-preview readability, full-window themed preview rendering, and clearer export/share feedback.
- iPad editor chrome is more consistent, including tighter toolbar overflow behavior and better default sizing for the project-structure sidebar.
- German localization is more complete, especially in Settings and the recently polished search/preview surfaces.

### Highlights
- Completed the `0.6.0` remote-workflow line with clearer remote tab/document/session state, broker failure clarity, explicit compare-before-reload conflict handling, and safer unsupported-file handling in the remote browser.
- Expanded search and navigation maturity with stronger `Quick Open` ranking, clearer search-source/status messaging, grouped `Find in Files` results, direct toolbar entry points, and improved Return/selection behavior.
- Added more cross-platform keyboard parity on iPad, including sidebar shortcuts, Settings tab navigation, and result-list arrow-key movement in search panels.
- Polished Markdown Preview with clearer export affordances, full-window live preview rendering, larger preview typography, and lightweight copy/export status messaging.
- Continued cross-platform UI refinement for `Find & Replace`, `Find in Files`, project sidebar defaults, toolbar overflow placement, and theme selection visibility.

### Fixes
- Fixed Settings tab selection unexpectedly jumping back to `General`.
- Fixed German localization gaps in Settings `General`, remote flows, search panels, and Markdown Preview controls.
- Fixed theme selection and editor-selection contrast, including aligned selection color behavior for `Neon Glow` and stronger selection emphasis across built-in themes.
- Fixed `Find & Replace` and `Find in Files` usability regressions across macOS, iPhone, and iPad, including close behavior, live match visibility, result counts, clear actions, panel sizing, button readability, and dark-mode contrast.
- Fixed iPad toolbar crowding by moving `Close All Tabs` into the overflow menu and tightening overflow placement inside the glass toolbar.
- Fixed iPad project-structure sidebar default width so the localized title no longer clips on first presentation.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.9] - 2026-03-30

### Why Upgrade
- iPhone project-sidebar controls are visible again after the duplicate title/header was removed.

### Highlights
- Added a small iOS hotfix release for the project-sidebar header regression introduced during the `0.5.8` sidebar cleanup.

### Fixes
- Fixed iPhone project-sidebar header actions so `Open Folder`, `Open File`, refresh, and the sidebar menu remain visible even when the duplicate inline `Project Structure` title is hidden.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.8] - 2026-03-28

### Why Upgrade
- Huge files now reach first content faster through deferred, chunked installation instead of a single blocking editor handoff.
- Large-file sessions stay more responsive while the rest of the document is installed in the background.
- Large-file status is clearer while deferred loading is active, with visible session affordances for the active open mode.
- Remote workflows can now be started from the Mac, attached from iPhone and iPad, and used to browse, open, edit, and explicitly save supported remote text files through the Mac-hosted broker.
- Markdown preview export controls and the project sidebar now use a denser, more polished layout across macOS, iPhone, and iPad.

### Highlights
- Added the `0.5.8` release line for incremental loading of huge files, centered on the deferred/chunked open path tracked in `#28`.
- Expanded the large-file open flow with a lightweight preparation state before the full editor content is installed.
- Completed the large-file session controls so `Standard`, `Deferred`, and `Plain Text` modes remain available when performance mode is active.
- Added a Mac-hosted remote session broker with SSH-key startup, attach codes for iPhone/iPad clients, a remote browser, remote open, explicit remote save, and remote revision-token conflict protection.
- Added clearer Remote settings guidance for local Mac SSH targets, attach-code usage, and the split between the Mac SSH owner and iPhone/iPad broker clients.
- Polished the project sidebar and Markdown preview chrome across platforms with tighter spacing, cleaner separators, and more consistent export-control placement.

### Fixes
- Fixed huge-file first paint stalls by avoiding a single full-text install on initial open.
- Fixed large-file session handoff so caret and editing state remain stable while chunks continue installing.
- Fixed deferred large-file completion so the final editor content still matches the source file exactly after background installation finishes.
- Fixed the macOS Settings crash caused by presenting the Remote tab without injecting the active `EditorViewModel`.
- Fixed stale remote status/help text that still referred to earlier phase-limited transport behavior after broker attach, remote browser, remote open, and explicit save were already implemented.
- Fixed project sidebar chrome and spacing issues across macOS and iPad, including duplicate dividers, over-rounded panel edges, and overly loose disclosure spacing.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.7] - 2026-03-26

### Why Upgrade
- Markdown preview on iPhone now uses a cleaner stacked layout and presents PDF export from the active preview flow.
- Markdown preview controls on macOS and iPad now use a more centered, balanced layout with direct export/share/copy actions.
- Appearance handling is more consistent when macOS follows the system light/dark setting, including Settings and editor window surfaces.
- iPad editor surfaces now avoid stray white seams and mismatched panel backgrounds around sidebars, split panes, and markdown preview.
- App Store support-purchase messaging is safer for review and restricted environments where in-app purchases are unavailable.
- Project indexing and iPad Vim-mode wiring are more complete for the `Quick Open`, `Find in Files`, and keyboard-first editing flows introduced around the `0.5.6` line.

### Highlights
- Completed the project-file index snapshot flow so project refreshes can reuse unchanged entries while continuing to feed `Quick Open` and `Find in Files`.
- Completed iPad Vim-mode integration with a dedicated Settings toggle, shared persistence, and visible mode-state reporting on iPad.
- Expanded the Code Snapshot composer with a `Custom` layout mode, better cross-platform sizing behavior, and cleaner control grouping.

### Fixes
- Fixed iPhone Markdown preview layout so title, controls, and export action read cleanly in a centered vertical flow.
- Fixed iPhone Markdown PDF export so the file exporter is presented from the active preview sheet instead of silently failing behind it.
- Fixed macOS and iPad Markdown preview control layout so template, PDF mode, and actions sit in a centered, platform-appropriate grouping.
- Fixed Code Snapshot spacing, preview sizing defaults, iPhone overflow, and iPad/macOS width behavior across `Fit`, `Wrap`, `Readable`, and `Custom`.
- Fixed macOS appearance switching so editor, sidebar, header, and Settings surfaces stay synchronized when the app follows the system mode.
- Fixed iPad editor chrome so split-pane dividers, project sidebar containers, and related surfaces no longer flash unintended white backgrounds.
- Fixed support-purchase messaging so unavailable StoreKit environments no longer blame App Store login or Screen Time during App Review-style sessions.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.6] - 2026-03-17

### Hero Screenshot
- ![v0.5.6 hero screenshot](docs/images/iphone-themes-light.png)

### Why Upgrade
- Safe Mode now recovers from repeated failed launches without getting stuck on every normal restart.
- Large project folders now get a background file index that feeds `Quick Open` and `Find in Files` instead of relying only on live folder scans.
- Markdown documents can now be exported directly from preview as PDF in both paginated and one-page formats.
- Theme formatting and Settings polish now apply immediately, with better localization and an iPad hardware-keyboard Vim MVP.

### Highlights
- Added Safe Mode startup recovery with repeated-failure detection, blank-document launch fallback, a dedicated startup explanation, and a `Normal Next Launch` recovery action.
- Added a background project file index for larger folders and wired it into `Quick Open`, `Find in Files`, and project refresh flows.
- Added Markdown preview PDF export with paginated and one-page output modes.
- Added an iPad hardware-keyboard Vim MVP with core normal-mode navigation/editing commands and shared mode-state reporting.
- Added theme formatting controls for bold keywords, italic comments, underlined links, and bold Markdown headings across active themes.

### Fixes
- Fixed Safe Mode so a successful launch clears recovery state and normal restarts no longer re-enter Safe Mode unnecessarily.
- Fixed Markdown PDF export clipping so long preview content is captured more reliably across page transitions and document endings.
- Fixed theme-formatting updates so editor styling refreshes immediately without requiring a theme switch.
- Fixed the editor font-size regression introduced by theme-formatting changes by restoring the base font before applying emphasis overrides.
- Fixed duplicated Settings tab headings, icon/title alignment, and formatting-card placement to reduce scrolling and keep the Designs tab denser.
- Fixed German Settings localization gaps and converted previously hard-coded diagnostics strings to localizable text.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.5] - 2026-03-16

### Highlights
- Stabilized first-open rendering from the project sidebar so file content and syntax highlighting appear on first click without requiring tab switches.
- Hardened startup/session behavior so `Reopen Last Session` reliably wins over conflicting blank-document startup states.
- Refined large-file activation and loading placeholders to avoid misclassifying smaller files as large-file sessions.
- Added Share Shot (`Code Snapshot`) creation flow with toolbar + selection-context actions (`camera.viewfinder`) and a styled share/export composer.
- Added TeX/LaTeX language support with syntax highlighting and extension-aware language mapping.

### Fixes
- Fixed a session-restore regression where previously open files could appear empty on first sidebar click until changing tabs.
- Fixed highlight scheduling during document-state transitions (`switch`, `finish load`, external edits) on macOS, iOS, and iPadOS.
- Fixed startup-default conflicts by aligning defaults and runtime startup gating between `Reopen Last Session` and `Open with Blank Document`.
- Fixed macOS shutdown persistence timing by saving session/draft snapshots on `willResignActive` and `willTerminate`.
- Fixed line-number ruler refresh timing to reduce layout churn/flicker and avoid draw-time retile side effects.
- Fixed horizontal viewport carry-over during document transitions so left-edge content no longer opens clipped.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.4] - 2026-03-13

### Hero Screenshot
- ![v0.5.4 hero screenshot](docs/images/ipad-editor-light.png)

### Why Upgrade
- Large files now open through a deferred, chunked install path instead of a single blocking first paint.
- Large-file sessions can switch between `Standard`, `Deferred`, and `Plain Text` modes directly in the editor UI.
- Status and large-file chrome are clearer, with line counts, session indicators, and better release-state visibility.

### Highlights
- Added a dedicated large-file open mode with deferred first paint, chunked text installation, and an optional plain-text session mode for ultra-large documents.

### Fixes
- Fixed large-file responsiveness regressions across project-sidebar reopen, tab switching, line-number visibility, status metrics, and large-file editor rendering stability.

### Breaking changes
- None.

### Migration
- None.

## [v0.5.3] - 2026-03-10

### Added
- Added a new high-readability colorful light theme preset: `Prism Daylight` (also selectable while app appearance is set to dark).
- Added double-click-to-close behavior for tabs on macOS tab strips.
- Added split editor settings sections (`Basics` / `Behavior`) to reduce scrolling in the Editor tab.

### Improved
- Improved custom theme vibrancy by applying the vivid neon syntax profile to `Custom`, so syntax colors remain bright and saturated.
- Improved Cyber Lime readability in light mode by reducing overly bright green token intensity and switching to a blue cursor accent.
- Improved toolbar symbol color options on macOS with clearer separation between `Dark Gray` and `Black`, plus near-white rendering in dark mode for both options.
- Improved translucent macOS toolbar consistency by enforcing `0.8` opacity for toolbar surfaces in translucency mode.

### Fixed
- Fixed toolbar-symbol contrast edge cases in dark mode where gray/black variants could appear too similar.

### Release
- Notarized release published via `scripts/release_all.sh v0.5.3 notarized`.

## [v0.5.2] - 2026-03-09

### Added
- Added editor performance presets in Settings (`Balanced`, `Large Files`, `Battery`) with shared runtime mapping.
- Added configurable project navigator placement (`Left`/`Right`) for project-structure sidebar layout.
- Added richer updater diagnostics details in Settings: staged update summary, last install-attempt summary, and recent sanitized log snippet.
- Added CSV/TSV table mode with a `Table`/`Text` switch, lazy row rendering, and background parsing for larger datasets.
- Added an in-app `Editor Help` sheet that lists core editor actions and keyboard shortcuts.
- Added a dedicated `Support Neon Vision Editor…` entry to the macOS `Help` menu for direct support-dialog access.

### Improved
- Improved iOS/iPadOS large-file responsiveness by lowering automatic large-file thresholds and applying preset-based tuning.
- Improved project-sidebar open flow by short-circuiting redundant opens when the selected file is already active.

### Fixed
- Fixed missing diagnostics reset workflow by adding a dedicated `Clear Diagnostics` action that also clears file-open timing snapshots.
- Fixed macOS editor-window top-bar jumping when toggling the toolbar translucency control by keeping chrome flags stable.
- Fixed CSV/TSV mode header transparency so the mode bar now uses a solid standard window background.
- Fixed settings-window translucency consistency on macOS so title/tab and content regions render as one unified surface.
- Fixed cross-platform updater diagnostics compilation by adding a non-macOS bundle-version reader fallback.
- Fixed macOS system `Help` menu fallback ("no help available") by replacing it with working in-app help actions.

## [v0.5.1] - 2026-03-08

### Added
- Added bulk `Close All Tabs` actions to toolbar surfaces (macOS, iOS, iPadOS), including a confirmation step before closing.
- Added project-structure quick actions to expand all folders or collapse all folders in one step.
- Added six vivid neon syntax themes with distinct color profiles: `Neon Voltage`, `Laserwave`, `Cyber Lime`, `Plasma Storm`, `Inferno Neon`, and `Ultraviolet Flux`.
- Added a lock-safe cross-platform build matrix helper script (`scripts/ci/build_platform_matrix.sh`) to run macOS + iOS Simulator + iPad Simulator builds sequentially.
- Added iPhone Markdown preview as a bottom sheet with toolbar toggle and resizable detents for Apple-guideline-compliant height control.
- Added unsupported-file safety handling across project sidebar, open/import flows, and user-facing unsupported-file alerts instead of crash paths.
- Added a project-sidebar switch to show only supported files (enabled by default).
- Added SVG (`.svg`) editor file support with XML language mapping and syntax-highlighting path reuse.

### Improved
- Improved Markdown preview stability by preserving relative scroll position during preview refreshes.
- Improved Markdown preview behavior for very large files by using a safe plain-text fallback with explicit status messaging instead of full HTML conversion.
- Improved neon syntax vibrancy consistency by extending the raw-neon adjustment profile to additional high-intensity neon themes.
- Improved contributor guidance with a documented lock-safe platform build verification command in `README.md`.
- Improved iPhone markdown preview sheet header density by using inline navigation-title mode to align title height with the `Done/Fertig` action row.

### Fixed
- Fixed diagnostics export safety by redacting token-like updater status fragments before copying.
- Fixed Markdown regression coverage with new tests for Claude-style mixed-content Markdown and code-fence matching behavior.
- Fixed accidental destructive tab-bulk-close behavior by requiring explicit user confirmation before closing all tabs.
- Fixed missing localization for new close-all confirmation/actions by adding English and German strings.

## [v0.5.0] - 2026-03-06

### Added
- Added updater staging hardening with retry/fallback behavior and staged-bundle integrity checks.
- Added explicit accessibility labels/hints for key toolbar actions and updater log/progress controls.
- Added a 0.5.0 quality roadmap milestone with focused issues for updater reliability, accessibility, and release gating.

### Improved
- Improved CSV handling by enabling fast syntax profile earlier and for long-line CSV files to reduce freeze risk.
- Improved settings-window presentation on macOS by enforcing hidden title text in the titlebar.
- Improved README roadmap clarity with direct 0.5.0 milestone and issue links.

### Fixed
- Fixed updater staging resilience when `ditto` fails by retrying and falling back safely to copy-based staging.
- Fixed release preflight to fail on unresolved placeholder entries and stale README download metrics.
- Fixed inconsistent reappearance of the macOS settings tab title in the upper-left window title area.

## [v0.4.34] - 2026-03-04

### Added
- iPhone editor now shows a floating Liquid Glass status pill with live caret and word metrics.
- Added a searchable Language picker (`Cmd+Shift+L`) on macOS, iOS, and iPadOS.

### Improved
- Language picker behavior is now consistent: compact toolbar labels with full language names in selection lists.
- iOS/iPad settings cards were visually simplified by removing accent stripe lines across tabs.

### Fixed
- Wrapped-line numbering on iOS/iPad now uses sticky logical line numbers instead of repeating on every visual wrap row.
- Floating status pill word counts stay in sync with live editor content while typing.

## [v0.4.33] - 2026-03-03

### Added
- Added performance instrumentation for startup first-paint/first-keystroke and file-open latency in debug builds.
- Added iPad hardware-keyboard shortcut bridging for New Tab, Open, Save, Find, Find in Files, and Command Palette.
- Added local runtime reliability monitoring with previous-run crash bucketing and main-thread stall watchdog logging in debug.

### Improved
- Improved command palette behavior with fuzzy matching, command entries, and recent-selection ranking.
- Improved large-file responsiveness by forcing throttle mode during load/import and reevaluating after idle.
- Improved project-wide search on macOS via ripgrep-backed Find in Files with fallback scanning.
- Improved iPad toolbar usability with larger minimum touch targets for promoted actions.

### Fixed
- Fixed iPad keyboard shortcut implementation to avoid deprecated UIKit key-command initializer usage.
- Fixed startup restore flow to recover unsaved draft checkpoints before blank-document startup mode.
- Fixed command/find panels with explicit accessibility labels, hints, and initial focus behavior.

## [v0.4.32] - 2026-02-27

### Added
- Added native macOS `SettingsLink` wiring for the menu bar entry so it opens the Settings scene through the system path.

### Improved
- Improved macOS command integration by preserving the system app-settings command group and standard Settings routing behavior.
- Improved project-folder last-session restoration reliability by keeping security-scoped folder access active before rebuilding the sidebar tree.

### Fixed
- Fixed non-standard Settings shortcut mapping by restoring the macOS standard `Cmd+,` behavior.
- Fixed startup behavior when "Open with Blank Document" is enabled so launch always opens exactly one empty document.

## [v0.4.31] - 2026-02-25

### Added
- Added an AI Activity Log on macOS with a dedicated diagnostics window and menu entry to inspect startup/provider events.
- Added centralized macOS app command wiring for settings, AI diagnostics, updater, editor actions, and window-level command routing.
- Added a full Flux/command-pattern redesign completed in a parallel session.

### Improved
- Improved release automation resiliency in `scripts/release_all.sh` with fail-fast `gh` auth checks, workflow/runner prechecks, stricter workflow status handling, and retryable asset verification.
- Improved settings startup behavior to preserve user-selected tabs/preferences and avoid redundant refresh work when opening Settings.
- Improved Settings responsiveness by moving font discovery off the main thread and reducing unnecessary window configurator reapplication churn.
- Improved Swift 6 readiness with a full concurrency hardening audit completed beyond this patch scope.

### Fixed
- Fixed startup preference regressions that previously re-disabled completion and other editor behaviors on every launch.
- Fixed settings invocation edge cases on macOS by removing duplicate keyboard interception and avoiding double signaling when system Settings handling succeeds.
- Fixed release flow false-success scenarios by requiring notarized workflow success (`gh run watch --exit-status`) and surfacing failed-job logs immediately.

## [v0.4.30] - 2026-02-24

### Added
- Added a native macOS Markdown preview web view with template presets (Default, Docs, Article, Compact) and toolbar access.
- Added richer Markdown-to-HTML rendering for headings, lists, blockquotes, code fences, links, and inline formatting in preview mode.

### Improved
- Improved Markdown code-block typography/spacing in preview so fenced blocks render with tighter, editor-like line density.
- Improved editor-to-binding synchronization safeguards while the text view has focus to prevent stale-state overwrites during active interaction.

### Fixed
- Fixed cursor/caret jump regressions where selection could unexpectedly snap to a much earlier position after paste/update timing races.
- Fixed cursor stability during click placement/editing across Markdown and other text files by preserving live editor state during view updates.

## [v0.4.29] - 2026-02-23

### Added
- Added explicit English (`en`) and German (`de`) support strings for the Support/IAP settings surface to keep release copy consistent across locales.
- Added support-price freshness state with a visible “Last updated” timestamp in Support settings after successful App Store product refreshes.

### Improved
- Improved updater version normalization so release tags with suffix metadata (for example `+build`, `(build 123)`, or prefixed release labels) are compared using the semantic core version.
- Improved Support settings refresh UX with a loading spinner on the “Retry App Store” action and clearer status messaging when price data is temporarily unavailable.

### Fixed
- Fixed updater detection for same-version releases where build numbers differ, ensuring higher build updates are still detected correctly.
- Fixed release automation safety when tags already exist by validating both local and remote tag targets against `HEAD` before proceeding without `--retag`.

## [v0.4.28] - 2026-02-20

### Added
- Added faster large-file loading safeguards to keep full-content attachment reliable across repeated opens.
- Added cross-platform `Save As…` command wiring so renamed saves are accessible from toolbar/menu flows on macOS, iOS, and iPadOS.

### Improved
- Improved large HTML/CSV editing responsiveness by reducing expensive full-buffer sanitization and update-path overhead.
- Improved macOS Settings UX with smoother tab-to-tab size transitions and tighter dynamic window sizing.
- Improved iOS/iPadOS toolbar language picker sizing so compact labels remain single-line and avoid clipping.
- Improved iPadOS toolbar responsiveness by rebalancing promoted actions vs `...` overflow based on live window width.
- Improved iPadOS toolbar overflow stability to prevent temporary clipping/jitter of the `...` menu during interaction.

### Fixed
- Fixed an intermittent large-file regression where only an initial preview-sized portion (around ~500 lines) remained visible after reopen.
- Fixed iPadOS narrow-window tab overlap with window controls by increasing/adjusting tab strip leading clearance.
- Fixed macOS welcome/start screen presentation so it opens centered and remains draggable as a regular window.
- Fixed iPadOS top chrome spacing regression by restoring toolbar placement behavior to the pre-centering baseline.

### Frontend Catch-up (since v0.4.26)
- Consolidated iOS/iPadOS toolbar polish shipped after `v0.4.26`, including language token fitting, overflow action promotion, and menu stability under narrow multitasking layouts.
- Consolidated macOS first-launch UI behavior fixes shipped after `v0.4.26`, including welcome-window positioning and drag behavior consistency.

## [v0.4.27] - 2026-02-19

### Added
- Added compact iOS/iPadOS toolbar language labels and tightened picker widths to free toolbar space on smaller screens.

### Improved
- Improved iPad toolbar density/alignment so more actions are visible before overflow and controls start further left.
- Improved macOS translucent chrome consistency between toolbar, tab strip, and project-sidebar header surfaces.

### Fixed
- Fixed macOS project-sidebar top/header transparency bleed when unified translucent toolbar backgrounds are enabled.

## [v0.4.26] - 2026-02-19

### Added
- Added cross-platform bracket helper insertion controls: keyboard accessory helper on iOS/iPadOS and a toggleable helper bar on macOS.
- Added a dedicated macOS toolbar toggle to show/hide the bracket helper bar on demand.

### Improved
- Improved settings/navigation polish across iOS, iPadOS, and macOS, including tab defaults and visual consistency for support-focused flows.
- Improved release automation reliability for `v0.4.26` by validating and aligning versioning/preflight flow with current project state.

### Fixed
- Fixed iOS/iPadOS build regression in `NeonSettingsView` (`some View` opaque return inference failure).
- Fixed post-rebase project-tree compile break on macOS by restoring refresh-generation state wiring and compatible node construction.
- Fixed toolbar/theme consistency regressions that reintroduced pink-accent styling in iOS settings paths.

## [v0.4.25] - 2026-02-18

### Added
- Added completion/signpost instrumentation (`os_signpost`) for inline completion, syntax highlighting, and file save paths to support performance profiling.

### Improved
- Improved inline code completion responsiveness with trigger-aware scheduling, adaptive debounce, and short-lived context caching.
- Improved editor rendering performance with coalesced highlight refreshes and reduced heavy-feature work on very large documents.

### Fixed
- Fixed redundant save writes by skipping unchanged file content saves via content fingerprinting.
- Fixed macOS syntax-highlighting churn during typing by limiting many highlight passes to local edited regions when safe.

## [v0.4.24] - 2026-02-18

### Added
- Added Lua as a selectable editor language with filename/extension detection and syntax highlighting token support.

### Improved
- Improved iOS settings readability by increasing section contrast so grouped settings remain distinct from the background.
- Improved iOS top toolbar action order by placing Open File first for faster access.

### Fixed
- Fixed iOS toolbar overflow behavior to keep a single working three-dot overflow menu and preserve hidden actions.

## [v0.4.23] - 2026-02-16

### Added
- Added optional support-purchase content to Welcome Tour page 2, including live StoreKit price and direct purchase action.

### Improved
- Improved welcome-tour flow by moving Toolbar Map to the final page and updating toolbar shortcut hints for iPad hardware keyboards.
- Improved Settings editor-layout readability by left-aligning Editor tab section headers, controls, and helper text into a consistent single-column layout.

### Fixed
- Fixed Settings support UI to remove restore-purchase actions where restore flow is not supported in current settings workflow.
- Fixed Refresh Price behavior to re-evaluate StoreKit availability before refreshing product metadata.
- Fixed font chooser instability by removing the macOS `NSFontPanel` bridge path and using the in-settings font list selector flow.

## [v0.4.22] - 2026-02-16

### Added
- Added shared syntax-regex compilation cache to reuse `NSRegularExpression` instances across highlight passes on macOS and iOS.

### Improved
- Improved large-document editor responsiveness by avoiding full syntax-regex reprocessing on caret-only moves and updating only transient line/bracket/scope decorations.
- Improved iOS line-number gutter performance by caching line-count driven rendering and avoiding full gutter text rebuilds when the line count is unchanged.

### Fixed
- Fixed macOS line-number ruler hot-path overhead by replacing per-draw line-number scans with cached UTF-16 line-start indexing and O(log n) lookup.

## [v0.4.21] - 2026-02-16

### Added
- Added curated popular editor themes: Dracula, One Dark Pro, Nord, Tokyo Night, and Gruvbox.

### Improved
- Improved macOS self-hosted updater flow to download and verify releases in-app, then stage installation for background apply on app close/restart.
- Improved updater platform/channel safety by enforcing install actions only for direct-distribution macOS builds (never iOS/App Store).

### Fixed
- Fixed Main Thread Checker violations in `EditorTextView` by ensuring `NSTextView.string` and `selectedRange` snapshot reads occur on the main thread.
- Fixed Neon Glow theme token mapping to match intended palette readability (dark gray comments, exact `#003EFF` string blue).

## [v0.4.20] - 2026-02-16

### Added
- Added iOS editor paste fallback handling that forces safe plain-text insertion when rich pasteboard content is unavailable or unreliable.

### Improved
- Improved syntax token readability across themes with appearance-aware color tuning (darker vibrant tokens in Light mode, brighter tokens in Dark mode), with extra tuning for Neon Glow.

### Fixed
- Fixed iOS paste reliability regressions in the editor input view.
- Fixed line-number gutter/text overlap on large files by making gutter width dynamic based on visible digit count on both iOS and macOS.

## [v0.4.19] - 2026-02-16

### Added
- Added adaptive theme background normalization so selected themes follow appearance mode (light in Light mode, dark in Dark/System-dark mode) without changing theme identity.

### Improved
- Improved cross-platform editor readability by enforcing mode-aware base/background contrast for all built-in themes, including Neon Glow.

### Fixed
- Fixed macOS line-number ruler behavior where line numbers could disappear near end-of-document when scrolling to the bottom.
- Fixed iOS line-number gutter sync at bottom scroll positions by clamping gutter content offset to valid bounds.

## [v0.4.18] - 2026-02-15

### Added
- Added iOS/macOS regression coverage in the editor refresh path so syntax highlighting remains stable across toolbar/menu and focus transitions.

### Improved
- Improved editor rendering consistency by preventing view-update color assignments from overriding attributed syntax token colors.

### Fixed
- Fixed iOS issue where opening the toolbar `...` menu could temporarily drop syntax highlighting.
- Fixed macOS issue where moving focus away from the editor/window could temporarily drop syntax highlighting.

## [v0.4.17] - 2026-02-15

### Added
- Added translucency-toggle highlight refresh wiring so editor recoloring is explicitly re-triggered when window translucency changes.

### Improved
- Improved syntax-highlighting stability during appearance/translucency transitions by forcing an immediate refresh instead of waiting for unrelated edits.

### Fixed
- Fixed a macOS editor bug where toggling translucent window mode could temporarily hide syntax highlighting until another action (for example changing font size) forced a rehighlight.

## [v0.4.16] - 2026-02-14

### Added
- Added a release-doc synchronization gate to `release_all.sh` via `prepare_release_docs.py --check` so releases fail fast when docs are stale.
- Added a delegate-based updater download service that reports live progress into the update dialog.

### Improved
- Improved updater install flow to stay user-driven/manual after verification, with Finder handoff instead of in-place app replacement.
- Improved editor appearance switching so base text colors are enforced immediately on light/dark mode changes across macOS and iOS.

### Fixed
- Fixed light-mode editor base text color to consistently use dark text across themes.
- Fixed dark-mode editor base text color to consistently use light text across themes.
- Fixed updater dialog post-download actions to show manual install choices (`Show in Finder`/`View Releases`) with accurate progress and phase updates.

## [v0.4.15] - 2026-02-14

### Fixed
- Fixed the editor `Highlight Current Line` behavior on macOS so previous line background highlights are cleared and only the active line remains highlighted.

## [v0.4.14] - 2026-02-14

### Added
- Added centralized theme canonicalization with an explicit `Custom` option in settings so legacy/case-variant values resolve consistently across launches.
- Added a fallback GitHub Releases URL path in the updater dialog so `View Releases` always opens, even when no latest-release payload is cached.
- Added keychain-state restore/cleanup steps to notarized release workflows (and workflow templates) to prevent user keychain list/default/login mutations after signing jobs.

### Improved
- Improved macOS translucent-window rendering by enforcing unified toolbar style and full-size content behavior when translucency is enabled.
- Improved cross-platform theme application so iOS/macOS editor text + syntax colors respect the selected settings theme in both translucent and non-translucent modes.
- Improved iOS settings/action tint parity to use blue accent coloring consistent with macOS.

### Fixed
- Fixed updater release-source validation regression that could block manual update checks in local/Xcode runs.
- Fixed toolbar/titlebar visual mismatch where toolbar areas rendered too opaque/white when translucency was enabled.
- Fixed settings theme-selection drift by normalizing persisted theme values and applying canonical names on read/write.

## [v0.4.13] - 2026-02-14

### Added
- Added `scripts/run_selfhosted_notarized_release.sh` helper to trigger/watch the self-hosted notarized release workflow and verify uploaded assets.

### Improved
- Hardened updater repository-source validation to accept both `github.com/{owner}/{repo}` and GitHub REST API paths (`api.github.com/repos/{owner}/{repo}`).
- Improved updater behavior in local Xcode/DerivedData runs by disabling automatic install/relaunch in development runtime.

### Fixed
- Fixed update dialog failures caused by over-strict GitHub release-source path validation.
- Fixed startup reliability by removing eager Keychain token reads/migration on launch paths and treating missing-keychain datastore statuses as non-fatal token-missing cases.
- Fixed local debug key handling by using `UserDefaults` fallback in `DEBUG` builds to avoid blocking `SecItemCopyMatching` behavior during local runs.

## [v0.4.12] - 2026-02-14

### Added
- `scripts/release_all.sh` now accepts `notarized` as a positional alias, so `scripts/release_all.sh v0.4.12 notarized` works directly.

### Improved
- Hosted notarized release workflow now enforces Xcode 17+ to preserve the Tahoe light/dark `AppIcon.icon` pipeline.
- Release asset verification now runs in strict iconstack mode to ensure published assets contain `AppIcon.iconstack`.

### Fixed
- Removed Xcode 16 fallback icon-copy path that could produce Sequoia/non-light-dark icon payloads in release assets.

## [v0.4.11] - 2026-02-13

### Added
- ExpressionEngine language support in the editor language set.
- Plain text drag-and-drop support so dropped string content opens correctly in the editor.

### Improved
- Release/docs metadata with TestFlight beta link surfaced in project documentation and download guidance.
- Release pipeline compatibility for hosted environments with Xcode 16 fallback handling.

### Fixed
- Notarized release publishing now hard-fails when icon payload validation fails, preventing bad assets from being published.
- macOS Settings sizing now enforces a taller default window to avoid clipped controls.

## [v0.4.10] - 2026-02-13

### Added
- Release gate in `scripts/release_all.sh` now waits for a successful `Pre-release CI` run on the pushed commit before triggering notarization.

### Improved
- Hosted notarized workflow now allows an explicit Xcode 16+ fallback path when Xcode 17 is unavailable on GitHub-hosted runners.
- Settings window responsiveness on macOS by deferring/caching editor font list loading.

### Fixed
- Reduced settings-open latency by removing forced full-window redraw calls during appearance application.

## [v0.4.9] - 2026-02-13

### Added
- Pre-release CI workflow on `main`/PR with critical runtime checks, docs validation, and icon payload verification.
- Release dry-run workflow and local `scripts/release_dry_run.sh` command for pre-tag validation.
- Release runtime policy test suite (`ReleaseRuntimePolicyTests`) covering settings-tab routing, theme mapping, find-next cursor behavior, and subscription button state logic.

### Improved
- Unified release automation in `scripts/release_all.sh` to run preflight checks before tagging and to verify uploaded release assets after notarized publish.
- README changelog summary automation now keeps release summaries version-sorted and limited to the latest three entries.
- Notarized workflows now include compatibility fallbacks so older tags without `scripts/ci/*` can still be rebuilt and published.

### Fixed
- Fixed macOS toolbar Settings (gear) button path to open the Settings scene reliably via SwiftUI `openSettings`.
- Hardened release workflows with post-publish verification and rollback behavior (delete bad asset and mark release draft on verification failure).

## [v0.4.8] - 2026-02-12

### Added
- Extended release automation coverage for the next tag cycle, including synchronized README/changelog/welcome-tour release content updates.

### Improved
- macOS settings parity with iOS by wiring the `Open in Tabs` preference into live window tabbing behavior.
- Welcome Tour release highlights are now aligned with distribution content for current App Store/TestFlight-facing builds.

### Fixed
- Release workflow environment compatibility by removing hard `rg` dependency from docs validation steps.
- Release pipeline guard failures caused by placeholder release notes in the tag section.

## [v0.4.7] - 2026-02-12

### Added
- Indentation-based scope detection fallback for Python/YAML to render scoped-region and guide markers when bracket-only matching is not sufficient.
- Release workflow compatibility fallback for doc validation (`grep`-based checks), so release jobs no longer depend on `rg` being preinstalled on runners.

### Improved
- Scope/bracket highlighting stability by dropping stale asynchronous highlight passes and applying only the latest generation.
- Visibility of matched bracket tokens and scope guide markers for easier detection on iOS and macOS.

### Fixed
- Settings window opening/persistence path now uses the native Settings scene behavior, avoiding custom frame persistence conflicts.
- iOS appearance override handling for light/dark/system now applies consistently across app windows/scenes.

## [v0.4.6] - 2026-02-12

### Added
- Self-hosted notarized release workflow for macOS (`release-notarized-selfhosted.yml`) targeting macOS runners with Xcode 17+.
- Automated icon payload preflight in notarized release pipelines to block publishing assets with missing AppIcon renditions.
- Release automation wiring so `scripts/release_all.sh --notarized` triggers the self-hosted notarized workflow.

### Improved
- Release tooling robustness in `release_all.sh` / `release_prep.sh` for optional arguments and end-to-end docs flow.
- Welcome Tour release page automation now derives the first card from the selected changelog section during release prep.
- Notarized workflow now validates toolchain requirements for icon-composer-based app icon assets.

### Fixed
- Support purchase testing bypass is now hidden in distributed release builds (kept only for debug/simulator testing paths).
- Replaced deprecated receipt URL usage in support purchase gating with StoreKit transaction environment checks.
- Restored release icon source mapping to `AppIcon.icon` (dark/light icon pipeline) instead of using the fallback iOS icon set in release builds.

## [v0.4.5] - 2026-02-11

### Added
- Optional support purchase flow (StoreKit 2) with a dedicated Settings -> Support tab.
- Local StoreKit testing file (`SupportOptional.storekit`) and App Store review notes (`docs/AppStoreReviewNotes.md`).
- New cross-platform theme settings panel and iOS app icon asset catalog set.

### Improved
- Settings architecture cleanup: editor options consolidated into Settings dialog/sheet and aligned with toolbar actions.
- Language detection and syntax highlighting stability for newly opened tabs and ongoing edits.
- Sequoia/Tahoe compatibility guards and cross-platform settings presentation behavior.
- Consolidated macOS app icon source to a single `Resources/AppIcon.icon` catalog (removed duplicate `Assets.xcassets/AppIcon.icon`).

### Fixed
- iOS build break caused by missing settings sheet state binding in `ContentView`.
- Find panel behavior (`Cmd+F`, initial focus, Enter-to-find-next) and highlight-current-line setting application.
- Line number ruler rendering overlap/flicker issues from previous fragment enumeration logic.
- Editor text sanitization paths around paste/tab/open flows to reduce injected visible whitespace glyph artifacts.
- Prevented reintroduced whitespace/control glyph artifacts (`U+2581`, `U+2400`–`U+243F`) during typing/paste by hardening sanitizer checks in editor update paths.
- macOS line-number gutter redraw/background mismatch so the ruler keeps the same window/editor tone without white striping.

## [v0.4.4-beta] - 2026-02-09

### Added
- Inline code completion ghost text with Tab-to-accept behavior.
- Starter templates for all languages and a toolbar insert button.
- Welcome tour release highlights and a full toolbar/shortcut guide.
- Language detection tests and a standalone test target.
- Document-type registration so `.plist`, `.sh`, and general text files open directly in the editor on macOS and iOS/iPadOS.
- Release Assistant helper app plus scripted workflow for uploading `v0.4.4-beta`.

### Improved
- Language detection coverage and heuristics, including C and C# recognition.
- Toolbar Map card in the welcome tour now wraps the button grid inside a taller inner frame to keep the cards inside the border.

### Fixed
- Language picker behavior to lock the selected language and prevent unwanted resets.

## [v0.4.3-beta] - 2026-02-08

### Added
- Syntax highlighting for **COBOL**, **Dotenv**, **Proto**, **GraphQL**, **reStructuredText**, and **Nginx**.
- Language picker/menu entries for the new languages.
- Sample fixtures for manual verification of detection and highlighting.
- macOS document-type registration for supported file extensions.

### Improved
- Extension and dotfile language detection for `.cob`, `.cbl`, `.cobol`, `.env*`, `.proto`, `.graphql`, `.gql`, `.rst`, and `.conf`.
- Opening files from Finder/Open With now reuses the active window when available.

## [v0.4.2-beta] - 2026-02-08

### Added
- Syntax highlighting profiles for **Vim** (`.vim`), **Log** (`.log`), and **Jupyter Notebook JSON** (`.ipynb`).
- Language picker/menu entries for `vim`, `log`, and `ipynb` across toolbar and app command menus.

### Improved
- Extension and dotfile language detection for `.vim`, `.log`, `.ipynb`, and `.vimrc`.
- Header-file default mapping by treating `.h` as `cpp` for more practical C/C++ highlighting.

### Fixed
- Scoped toolbar and menu commands to the active window to avoid cross-window side effects.
- Routed command actions to the focused window's `EditorViewModel` in multi-window workflows.
- Unified state persistence for Brain Dump mode and translucent window background toggles.
- Removed duplicate `Cmd+F` shortcut binding conflict between toolbar and command menu.
- Stabilized command/event handling across macOS and iOS builds.

## [v0.4.1-beta] - 2026-02-07

### Improved
- Prepared App Store security and distribution readiness for the `v0.4.1-beta` release.
- Added release/distribution documentation and checklist updates for submission flow.

## [v0.4.0-beta] - 2026-02-07

### Improved
- Improved editor UX across macOS, iOS, and iPadOS layouts.
- Refined cross-platform editor behavior and UI polish for the first beta line.

## [v0.3.3-alpha] - 2026-02-06

### Documentation
- Updated README content and presentation.

## [v0.3.2-alpha] - 2026-02-06

### Changed
- Refactored the editor architecture by splitting `ContentView` into focused files/extensions.

### Added
- Right-side project structure sidebar with recursive folder tree browsing.
- Dedicated blank-window flow with isolated editor state.
- Enhanced find/replace controls (regex, case-sensitive, replace-all status).

### Fixed
- Markdown highlighting over-coloring edge cases.
- Window/sidebar translucency consistency and post-refactor access-control issues.

## [v0.3.1-alpha] - 2026-02-06

### Fixed
- Line number ruler scrolling and update behavior.
- Translucency rendering conflicts in line-number drawing.

## [v0.3.0-alpha] - 2026-02-06

### Changed
- Established the `v0.3.x` alpha release line.
- Consolidated docs/release presentation updates and baseline packaging cleanup for the next iteration.

## [v0.2.9-alpha] - 2026-02-05

### Improved
- Improved Apple Foundation Models integration and streaming reliability.
- Added stronger availability checks and fallback behavior for model completion.

### Fixed
- Fixed streaming delta handling and optional-unwrapping issues in Apple FM output flow.

## [v0.2.8-1-alpha] - 2026-02-05

### Notes
- Re-tag of the Apple Foundation Models integration/stability update line.
- No functional differences documented from `v0.2.9-alpha` content.

## [v0.2.8-alpha] - 2026-02-05

### Improved
- Improved Apple Foundation Models integration and health-check behavior.
- Added synchronous and streaming completion APIs with graceful fallback.

### Fixed
- Fixed stream content delta computation and robustness in partial-response handling.

## [v0.2.7-alpha] - 2026-02-04

### Added
- Added Grok and Gemini provider support for inline code completion.

### Fixed
- Fixed exhaustive switch coverage in AI client factory/provider routing.

## [v0.2.6-alpha] - 2026-01-31

### Changed
- Packaged and uploaded the next alpha iteration for distribution.

## [v0.2.5-alpha] - 2026-01-25

### Improved
- Delayed hover popovers to reduce accidental toolbar popups.
- Improved auto language detection after drag-and-drop editor input.

## [v0.2.4-alpha] - 2026-01-25

### Changed
- Integrated upstream/mainline changes as part of alpha iteration merge.

## [v0.2.3-alpha] - 2026-01-23

### Improved
- Improved line numbering behavior for more consistent rendering.
- Added syntax highlighting support for **Bash** and **Zsh**.
- Added a function to open multiple files at once.

### Fixed
- Fixed line number rendering issues during scrolling and in larger files.

## [v0.2.2-alpha] - 2026-01-22

### Enhanced
- Added automatic language selection using the Apple FM model.
- Updated toolbar layout and implemented AI selector support.

## [v0.2.1-alpha] - 2026-01-21

### Improved
- Updated UI with sidebar/layout fixes.
- Fixed language selector behavior for syntax highlighting.
- Improved focus behavior for text view interactions.
