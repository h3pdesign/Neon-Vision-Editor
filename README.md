<h1 align="center">Neon Vision Editor</h1>

<p align="center">
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases"><img alt="Latest Release" src="https://img.shields.io/github/v/tag/h3pdesign/Neon-Vision-Editor?label=release"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20iPadOS-0A84FF">
  <a href="https://apps.apple.com/de/app/neon-vision-editor/id6758950965"><img alt="App Store" src="https://img.shields.io/badge/App%20Store-Live-0D96F6"></a>
  <a href="https://testflight.apple.com/join/YWB2fGAP"><img alt="TestFlight" src="https://img.shields.io/badge/TestFlight-Beta-00C7BE"></a>
</p>

<p align="center">
  <img src="NeonVisionEditorIcon.png" alt="Neon Vision Editor Logo" width="200"/>
</p>

<h4 align="center">
  A lightweight, modern editor focused on speed, readability, and automatic syntax highlighting.
</h4>

<p align="center">
  Minimal by design: quick edits, fast file access, no IDE bloat.
</p>

<p align="center">
  h3p apps is a focused portal for product docs, setup guides, and release workflows: <a href="https://apps-h3p.com"> >h3p apps</a>
</p>

<p align="center">
  Release Download: <a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases">GitHub Releases</a>
</p>


> Status: **active release**  
> Latest release: **v0.5.0**
> Platform target: **macOS 26 (Tahoe)** compatible with **macOS Sequoia**
> Apple Silicon: tested / Intel: not tested
> Last updated (README): **2026-03-07** for release line **v0.5.0**

## Download Metrics

<p align="center">
  <img alt="All Downloads" src="https://img.shields.io/github/downloads/h3pdesign/Neon-Vision-Editor/total?style=for-the-badge&label=All%20Downloads&color=0A84FF">
  <img alt="v0.5.0 Downloads" src="https://img.shields.io/github/downloads/h3pdesign/Neon-Vision-Editor/v0.5.0/total?style=for-the-badge&label=v0.5.0&color=22C55E">
</p>

<p align="center"><strong>Release Download + Clone Trend</strong></p>

<p align="center">
  <img src="docs/images/release-download-trend.svg" alt="GitHub release downloads trend chart" width="100%">
</p>

<p align="center"><em>Styled line chart shows per-release totals plus a scaled 14-day git clone volume bar.</em></p>
<p align="center">Git clones (last 14 days): <strong>1508</strong>.</p>
<p align="center">Snapshot total downloads: <strong>560</strong> across releases.</p>

## Project Docs

- Release history: [`CHANGELOG.md`](CHANGELOG.md)
- Contributing guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Privacy: [`PRIVACY.md`](PRIVACY.md)
- Security policy: [`SECURITY.md`](SECURITY.md)
- Release checklists: [`release/`](release/) — TestFlight & App Store preflight docs

## What's New Since v0.4.33

- iPad toolbar keeps key actions visible more consistently (Settings, Search, Project Sidebar, Markdown Preview).
- iPad Markdown Preview now auto-prioritizes preview space by collapsing the project sidebar when needed.
- Settings polish on iOS/iPad: improved German localization coverage, centered tab headers, and cleaner card grouping.
- macOS top-left window controls are more stable during settings/tab transitions.

## Who Is This For?

- Quick note takers who want a fast native editor without IDE overhead.
- Markdown-focused writers who need clean editing and quick preview on Apple devices.
- Developers editing scripts/config files who want syntax highlighting and fast file navigation.

## Download

Prebuilt binaries are available on [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases).

- Latest release: **v0.5.0**
- Channel: **Stable** (GitHub Releases)
- Apple AppStore [On the AppStore](https://apps.apple.com/de/app/neon-vision-editor/id6758950965)
- TestFlight beta: [Join here](https://testflight.apple.com/join/YWB2fGAP)
- Channel: **Beta** (TestFlight)
- Architecture: Apple Silicon (Intel not tested)
- Notarization: *is finally implemented*

## Getting Started (30 Seconds)

1. Install using `curl` or Homebrew (below), or download the latest `.zip`/`.dmg` from [Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases).
2. Move `Neon Vision Editor.app` to `/Applications`.
3. Launch the app.
4. Open a file with `Cmd+O`.
5. Use `Cmd+P` for Quick Open and `Cmd+F` for Find & Replace.
6. Toggle Vim mode with `Cmd+Shift+V` if needed.

## Install

### Quick install (curl)

Install the latest release directly:

```bash
curl -fsSL https://raw.githubusercontent.com/h3pdesign/Neon-Vision-Editor/main/scripts/install.sh | sh
```

Install without admin password prompts (user-local app folder):

```bash
curl -fsSL https://raw.githubusercontent.com/h3pdesign/Neon-Vision-Editor/main/scripts/install.sh | sh -s -- --appdir "$HOME/Applications"
```

### Homebrew

```bash
brew tap h3pdesign/tap
brew install --cask neon-vision-editor
```

Tap repository: [h3pdesign/homebrew-tap](https://github.com/h3pdesign/homebrew-tap)

If Homebrew asks for an admin password, it is usually because casks install into `/Applications`.
Use this to avoid that:

```bash
brew install --cask --appdir="$HOME/Applications" neon-vision-editor
```

### Gatekeeper (macOS 26 Tahoe)

If macOS blocks first launch:

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. In **Security**, find the blocked app message.
4. Click **Open Anyway**.
5. Confirm the dialog.

## Features

Neon Vision Editor keeps the surface minimal, but covers the workflows used most often while writing, coding, and reviewing files.

| Area | Highlights | macOS | iOS | iPadOS |
|---|---|---|---|---|
| Core Experience | Fast loading for regular and large text files; tabbed editing; broad syntax highlighting; native Swift/AppKit feel; multi-window workflows | Full | Full | Full |
| Editing & Productivity | Inline code completion (Tab accept); Regex Find/Replace (incl. Replace All); optional Vim mode; one-click language templates; curated built-in themes | Full | Full | Full |
| Markdown | Native Markdown preview templates (Default, Docs, Article, Compact); improved toolbar access to preview workflows | Full | No | Full |
| Projects & Files | Project sidebar + Quick Open (`Cmd+P`); recursive folder tree; last-session project restore; cross-platform `Save As…`; direct handling for `.plist` / `.sh` / text files | Full | Full | Full |
| Settings & Support | Grouped settings with improved localization and tab structure; optional StoreKit 2 support purchase flow | Full | Full | Full |
| Architecture & Reliability | Flux/command-pattern command flow; Swift concurrency hardening; macOS AI Activity Log diagnostics; privacy-first/no telemetry | Full | Partial | Partial |

Feature checklist (explicit):

- Vim support (optional normal/insert workflow).
- Regex Find/Replace with Replace All.
- Inline code completion with Tab-to-accept.
- Native Markdown preview templates (macOS + iPadOS).
- Quick Open (`Cmd+P`) and project sidebar navigation.
- Recursive project tree rendering for nested folders.
- Cross-platform `Save As…` support.
- Bracket helper on all platforms (macOS toolbar helper, iOS/iPad keyboard bar).
- Starter templates for common languages.
- Built-in theme collection (Dracula, One Dark Pro, Nord, Tokyo Night, Gruvbox, Neon Glow).
- Session restore including previously opened project folder.
- Optional Support purchase flow in Settings (StoreKit 2).
- AI Activity Log diagnostics window on macOS.

## Platform Matrix

Availability legend: `Full` = complete support, `Partial` = available with platform constraints, `No` = currently unavailable.

| Capability | macOS | iOS | iPadOS | Notes |
|---|---|---|---|---|
| Fast text editing + syntax highlighting | Full | Full | Full | Optimized for regular and large files. |
| Markdown preview templates | Full | No | Full | Presets: Default, Docs, Article, Compact. |
| Project sidebar | Full | Full | Full | Folder tree + nested structure rendering. |
| Quick Open (`Cmd+P`) | Full | Partial | Full | iOS requires hardware keyboard for shortcut use. |
| Bracket helper | Full | Full | Full | macOS: toolbar helper, iOS/iPadOS: keyboard snippet bar. |
| Settings tabs + grouped cards | Full | Full | Full | Localized UI with grouped preference cards. |

<p align="left">
  <img src="NeonVisionEditorApp.png" alt="Neon Vision Editor App" width="1100"/>
</p>

## Visual Quick Links

- macOS main editor screenshot: [`docs/images/macos-main.png`](docs/images/macos-main.png)
- iPad Markdown Preview screenshot: [`docs/images/ipad-markdown-preview.png`](docs/images/ipad-markdown-preview.png)
- iPhone editor screenshot: [`docs/images/iphone-editor.png`](docs/images/iphone-editor.png)
- App Store gallery: [Neon Vision Editor on App Store](https://apps.apple.com/de/app/neon-vision-editor/id6758950965)
- Latest release assets: [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases)

## 1-Minute Demo Flow

1. Open a file and check syntax highlighting: [`docs/images/macos-main.png`](docs/images/macos-main.png)
2. Use Quick Open and jump between project files: [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases)
3. Toggle Markdown Preview on iPad: [`docs/images/ipad-markdown-preview.png`](docs/images/ipad-markdown-preview.png)
4. Adjust settings/theme and continue editing: [`docs/images/iphone-editor.png`](docs/images/iphone-editor.png)

## Roadmap (Near Term)

- 0.5.0 milestone: quality + trust release (updater reliability, CSV safety, cross-platform polish, accessibility, release gating). Tracking: [Milestone 0.5.0](https://github.com/h3pdesign/Neon-Vision-Editor/milestone/1)
- Auto-update reliability hardening. Tracking: [#36](https://github.com/h3pdesign/Neon-Vision-Editor/issues/36)
- CSV/large-file safety and table-mode path. Tracking: [#25](https://github.com/h3pdesign/Neon-Vision-Editor/issues/25), [#26](https://github.com/h3pdesign/Neon-Vision-Editor/issues/26)
- Toolbar consistency and action discoverability across sizes. Tracking: [#14](https://github.com/h3pdesign/Neon-Vision-Editor/issues/14)
- Accessibility completion pass (VoiceOver + keyboard focus). Tracking: [#37](https://github.com/h3pdesign/Neon-Vision-Editor/issues/37)
- Release engineering lock-in checks for 0.5.0. Tracking: [#38](https://github.com/h3pdesign/Neon-Vision-Editor/issues/38)

## Known Issues

- Open known issues (live filter): [label:known-issue](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aknown-issue)

## Troubleshooting

1. App blocked on first launch: use Gatekeeper steps above in `Privacy & Security`.
2. Markdown preview not visible: ensure you are on macOS or iPadOS (not available on iPhone).
3. Shortcut not working on iOS: connect a hardware keyboard for shortcut-based flows like `Cmd+P`.
4. Sidebar/layout feels cramped on iPad: switch orientation or close side panels before preview.
5. Settings feel off after updates: quit/relaunch app and verify current release version in Settings.

## Configuration

- Theme and appearance: `Settings > Designs`
- Editor behavior (font, line height, wrapping, snippets): `Settings > Editor`
- Startup/session behavior: `Settings > Allgemein/General`
- Support and purchase options: `Settings > Mehr/More` (platform-dependent)

## FAQ

- **Does Neon Vision Editor support Intel Macs?**  
  Intel is currently not fully validated.
- **Can I use it offline?**  
  Yes for core editing; network is only needed for optional external services (for example selected AI providers).
- **Do I need AI enabled to use the editor?**  
  No. Core editing, navigation, and preview features work without AI.
- **Where are tokens stored?**  
  In Keychain via `SecureTokenStore`, not in `UserDefaults`.

## Keyboard Shortcuts

All shortcuts use `Cmd` (`⌘`). iPad/iOS require a hardware keyboard.

### File

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+N` | New Window | macOS |
| `Cmd+T` | New Tab | All |
| `Cmd+O` | Open File | All |
| `Cmd+Shift+O` | Open Folder | macOS |
| `Cmd+S` | Save | All |
| `Cmd+Shift+S` | Save As… | All |
| `Cmd+W` | Close Tab | macOS |

### Edit

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+X` | Cut | All |
| `Cmd+C` | Copy | All |
| `Cmd+V` | Paste | All |
| `Cmd+A` | Select All | All |
| `Cmd+Z` | Undo | All |
| `Cmd+Shift+Z` | Redo | All |
| `Cmd+D` | Add Next Match | macOS |

### View

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+Option+S` | Toggle Sidebar | All |
| `Cmd+Shift+D` | Brain Dump Mode | macOS |

### Find

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+F` | Find & Replace | All |
| `Cmd+G` | Find Next | macOS |
| `Cmd+Shift+F` | Find in Files | macOS |

### Editor

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+P` | Quick Open | macOS |
| `Cmd+D` | Add next match | macOS |
| `Cmd+Shift+V` | Toggle Vim Mode | macOS |

### Tools

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+Shift+G` | Suggest Code | macOS |

### Diag

| Shortcut | Action | Platforms |
|---|---|---|
| `Cmd+Shift+L` | AI Activity Log | macOS |
| `Cmd+Shift+U` | Inspect Whitespace at Caret | macOS |

## Changelog

### v0.5.0 (summary)

- Added updater staging hardening with retry/fallback behavior and staged-bundle integrity checks.
- Added explicit accessibility labels/hints for key toolbar actions and updater log/progress controls.
- Added a 0.5.0 quality roadmap milestone with focused issues for updater reliability, accessibility, and release gating.
- Improved CSV handling by enabling fast syntax profile earlier and for long-line CSV files to reduce freeze risk.
- Improved settings-window presentation on macOS by enforcing hidden title text in the titlebar.

### v0.4.34 (summary)

- iPhone editor now shows a floating Liquid Glass status pill with live caret and word metrics.
- Added a searchable Language picker (`Cmd+Shift+L`) on macOS, iOS, and iPadOS.
- Language picker behavior is now consistent: compact toolbar labels with full language names in selection lists.
- iOS/iPad settings cards were visually simplified by removing accent stripe lines across tabs.
- Wrapped-line numbering on iOS/iPad now uses sticky logical line numbers instead of repeating on every visual wrap row.

### v0.4.33 (summary)

- Added performance instrumentation for startup first-paint/first-keystroke and file-open latency in debug builds.
- Added iPad hardware-keyboard shortcut bridging for New Tab, Open, Save, Find, Find in Files, and Command Palette.
- Added local runtime reliability monitoring with previous-run crash bucketing and main-thread stall watchdog logging in debug.
- Improved command palette behavior with fuzzy matching, command entries, and recent-selection ranking.
- Improved large-file responsiveness by forcing throttle mode during load/import and reevaluating after idle.

Full release history: [`CHANGELOG.md`](CHANGELOG.md)

## Known Limitations

- Intel Macs are not fully validated.
- Vim support is intentionally basic (not full Vim emulation).
- iOS/iPad editor functionality is still more limited than macOS.

## Privacy & Security

- Privacy policy: [`PRIVACY.md`](PRIVACY.md).
- API keys are stored in Keychain (`SecureTokenStore`), not `UserDefaults`.
- Network traffic uses HTTPS.
- No telemetry.
- External AI requests only occur when code completion is enabled and a provider is selected.
- Security policy and reporting details: [`SECURITY.md`](SECURITY.md).

## Release Integrity

- Tag: `v0.5.0`
- Tagged commit: `1c31306`
- Verify local tag target:

```bash
git rev-parse --verify v0.5.0
```

- Verify downloaded artifact checksum locally:

```bash
shasum -a 256 <downloaded-file>
```

## Release Policy

- `Stable`: tagged GitHub releases intended for daily use.
- `Beta`: TestFlight builds may include in-progress UX and platform polish.
- Cadence: fixes/polish can ship between minor tags, with summary notes mirrored in README and `CHANGELOG.md`.

## Requirements

- macOS 26 (Tahoe)
- Xcode compatible with macOS 26 toolchain
- Apple Silicon recommended

## Build from source

```bash
git clone https://github.com/h3pdesign/Neon-Vision-Editor.git
cd Neon-Vision-Editor
open "Neon Vision Editor.xcodeproj"
```

## Contributing Quickstart

Contributor guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)

```bash
git clone https://github.com/h3pdesign/Neon-Vision-Editor.git
cd Neon-Vision-Editor
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" -destination 'platform=macOS,name=My Mac' build
```

## Support & Feedback

- Questions and ideas: [GitHub Discussions](https://github.com/h3pdesign/Neon-Vision-Editor/discussions)
- Known issues: [label:known-issue](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aknown-issue)
- Feature requests: [label:enhancement](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aenhancement)

## Git hooks

To auto-increment Xcode `CURRENT_PROJECT_VERSION` on every commit:

```bash
scripts/install_git_hooks.sh
```

## Support

If you want to support development:

- [Patreon](https://www.patreon.com/h3p)
- [My site h3p.me](https://h3p.me/home)

## License

Neon Vision Editor is licensed under the MIT License.
See [`LICENSE`](LICENSE).
