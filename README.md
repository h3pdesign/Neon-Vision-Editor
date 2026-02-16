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
  Release Download: <a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases">GitHub Releases</a>
</p>

> Status: **active release**  
> Latest release: **v0.4.19**
> Platform target: **macOS 26 (Tahoe)** compatible with **macOS Sequoia**
> Apple Silicon: tested / Intel: not tested

## Download

Prebuilt binaries are available on [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases).

- Latest release: **v0.4.19**
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
- Optional support purchase flow (StoreKit 2) in Settings.
- Cross-platform theme settings panel with improved settings organization.
- Inline code completion with Tab-to-accept ghost suggestions.
- Starter templates for all languages with one-click insert.
- Document-type handling for `.plist`, `.sh`, and general text so Finder/iOS can route those files straight into the editor.
- Toolbar Map card in the welcome tour now scales to fill a taller inner frame, keeping the button cards inside the border.
- Regex Find/Replace with Replace All.
- Project tree sidebar plus Quick Open (`Cmd+P`).
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

### v0.4.19 (summary)

- Added adaptive theme background normalization so selected themes follow appearance mode (light in Light mode, dark in Dark/System-dark mode) without changing theme identity.
- Improved cross-platform editor readability by enforcing mode-aware base/background contrast for all built-in themes, including Neon Glow.
- Fixed macOS line-number ruler behavior where line numbers could disappear near end-of-document when scrolling to the bottom.
- Fixed iOS line-number gutter sync at bottom scroll positions by clamping gutter content offset to valid bounds.

### v0.4.18 (summary)

- Added iOS/macOS regression coverage in the editor refresh path so syntax highlighting remains stable across toolbar/menu and focus transitions.
- Improved editor rendering consistency by preventing view-update color assignments from overriding attributed syntax token colors.
- Fixed iOS issue where opening the toolbar `...` menu could temporarily drop syntax highlighting.
- Fixed macOS issue where moving focus away from the editor/window could temporarily drop syntax highlighting.

### v0.4.17 (summary)

- Added translucency-toggle highlight refresh wiring so editor recoloring is explicitly re-triggered when window translucency changes.
- Improved syntax-highlighting stability during appearance/translucency transitions by forcing an immediate refresh instead of waiting for unrelated edits.
- Fixed a macOS editor bug where toggling translucent window mode could temporarily hide syntax highlighting until another action (for example changing font size) forced a rehighlight.

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

- Tag: `v0.4.19`
- Tagged commit: `TBD`
- Verify local tag target:

```bash
git rev-parse --verify v0.4.19
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
