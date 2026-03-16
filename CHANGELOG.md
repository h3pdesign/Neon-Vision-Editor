# Changelog

All notable changes to **Neon Vision Editor** are documented in this file.

The format follows *Keep a Changelog*. Versions use semantic versioning with prerelease tags.

## [v0.5.5] - 2026-03-16

### Highlights
- Stabilized first-open rendering from the project sidebar so file content and syntax highlighting appear on first click without requiring tab switches.
- Hardened startup/session behavior so `Reopen Last Session` reliably wins over conflicting blank-document startup states.
- Refined large-file activation and loading placeholders to avoid misclassifying smaller files as large-file sessions.

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

## [Unreleased]

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
