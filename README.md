<h1 align="center">Neon Vision Editor</h1>

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
> Latest release: **v0.4.31**
> Platform target: **macOS 26 (Tahoe)** compatible with **macOS Sequoia**
> Apple Silicon: tested / Intel: not tested

## Download

Prebuilt binaries are available on [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases).

- Latest release: **v0.4.31**
- Apple AppStore [On the AppStore](https://apps.apple.com/de/app/neon-vision-editor/id6758950965)
- TestFlight beta: [Join here](https://testflight.apple.com/join/YWB2fGAP)
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

- Fast loading for regular and large text files.
- Tabbed editing with per-file language support.
- Automatic syntax highlighting for many languages and formats.
- AI Activity Log diagnostics window on macOS for startup/provider visibility.
- Full Flux/command-pattern action flow for deterministic editor command handling.
- Swift 6 concurrency hardening across critical runtime paths.
- Optional support purchase flow (StoreKit 2) in Settings.
- Cross-platform theme settings panel with improved settings organization.
- Inline code completion with Tab-to-accept ghost suggestions.
- Starter templates for all languages with one-click insert.
- Document-type handling for `.plist`, `.sh`, and general text so Finder/iOS can route those files straight into the editor.
- Toolbar Map card in the welcome tour now scales to fill a taller inner frame, keeping the button cards inside the border.
- Regex Find/Replace with Replace All.
- Project tree sidebar plus Quick Open (`Cmd+P`).
- Recursive project tree rendering for nested folders in the sidebar.
- Last-session restore now includes the previously opened project folder.
- Optional Vim mode (basic normal/insert workflow).
- Multi-window workflow with focused-window commands.
- Native Swift/AppKit editor experience.
- No telemetry.

<p align="left">
  <img src="NeonVisionEditorApp.png" alt="Neon Vision Editor App" width="1100"/>
</p>

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+N` | New Window |
| `Cmd+T` | New Tab |
| `Cmd+O` | Open File |
| `Cmd+S` | Save |
| `Cmd+W` | Close Tab |
| `Cmd+P` | Quick Open |
| `Cmd+F` | Find & Replace |
| `Cmd+Shift+V` | Toggle Vim Mode |
| `Cmd+Option+S` | Toggle Sidebar |
| `Cmd+Option+L` | Toggle Line Wrap |
| `Cmd+Shift+D` | Toggle Brain Dump Mode |
| `Tab` | Accept code completion (when shown) |

## Changelog

### v0.4.31 (summary)

- Added an AI Activity Log on macOS with a dedicated diagnostics window and menu entry to inspect startup/provider events.
- Added centralized macOS app command wiring for settings, AI diagnostics, updater, editor actions, and window-level command routing.
- Added a full Flux/command-pattern redesign completed in a parallel session.
- Improved release automation resiliency in `scripts/release_all.sh` with fail-fast `gh` auth checks, workflow/runner prechecks, stricter workflow status handling, and retryable asset verification.
- Improved settings startup behavior to preserve user-selected tabs/preferences and avoid redundant refresh work when opening Settings.

### v0.4.30 (summary)

- Added a native macOS Markdown preview web view with template presets (Default, Docs, Article, Compact) and toolbar access.
- Added richer Markdown-to-HTML rendering for headings, lists, blockquotes, code fences, links, and inline formatting in preview mode.
- Improved Markdown code-block typography/spacing in preview so fenced blocks render with tighter, editor-like line density.
- Improved editor-to-binding synchronization safeguards while the text view has focus to prevent stale-state overwrites during active interaction.
- Fixed cursor/caret jump regressions where selection could unexpectedly snap to a much earlier position after paste/update timing races.

### v0.4.29 (summary)

- Added explicit English (`en`) and German (`de`) support strings for the Support/IAP settings surface to keep release copy consistent across locales.
- Added support-price freshness state with a visible “Last updated” timestamp in Support settings after successful App Store product refreshes.
- Improved updater version normalization so release tags with suffix metadata (for example `+build`, `(build 123)`, or prefixed release labels) are compared using the semantic core version.
- Improved Support settings refresh UX with a loading spinner on the “Retry App Store” action and clearer status messaging when price data is temporarily unavailable.
- Fixed updater detection for same-version releases where build numbers differ, ensuring higher build updates are still detected correctly.

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

- Tag: `v0.4.31`
- Tagged commit: `1c31306`
- Verify local tag target:

```bash
git rev-parse --verify v0.4.31
```

- Verify downloaded artifact checksum locally:

```bash
shasum -a 256 <downloaded-file>
```

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
