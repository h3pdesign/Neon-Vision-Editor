# Changelog

All notable changes to **Neon Vision Editor** are documented in this file.

The format follows *Keep a Changelog*. Versions use semantic versioning with prerelease tags.

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
- Release pipeline guard failures caused by placeholder release notes (`TODO`) in the tag section.

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
