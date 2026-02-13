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
> Latest release: **v0.4.11**
> Platform target: **macOS 26 (Tahoe)** compatible with **macOS Sequoia**
> Apple Silicon: tested / Intel: not tested

## Download

Prebuilt binaries are available on [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases).

- Latest release: **v0.4.11**
- TestFlight beta: [Join here](https://testflight.apple.com/join/YWB2fGAP)
- Architecture: Apple Silicon (Intel not tested)
- Notarization: *is finally there*

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
- Optional support purchase flow (StoreKit 2) in Settings. **(NEW in v0.4.5)**
- Cross-platform theme settings panel with improved settings organization. **(NEW in v0.4.5)**
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

### v0.4.11 (summary)

- ExpressionEngine language support in the editor language set.
- Plain text drag-and-drop support so dropped string content opens correctly in the editor.
- Release/docs metadata with TestFlight beta link surfaced in project documentation and download guidance.
- Release pipeline compatibility for hosted environments with Xcode 16 fallback handling.
- Notarized release publishing now hard-fails when icon payload validation fails, preventing bad assets from being published.

### v0.4.10 (summary)

- Release gate in `scripts/release_all.sh` now waits for a successful `Pre-release CI` run on the pushed commit before triggering notarization.
- Hosted notarized workflow now allows an explicit Xcode 16+ fallback path when Xcode 17 is unavailable on GitHub-hosted runners.
- Settings window responsiveness on macOS by deferring/caching editor font list loading.
- Reduced settings-open latency by removing forced full-window redraw calls during appearance application.

### v0.4.9 (summary)

- Pre-release CI workflow on `main`/PR with critical runtime checks, docs validation, and icon payload verification.
- Release dry-run workflow and local `scripts/release_dry_run.sh` command for pre-tag validation.
- Release runtime policy test suite (`ReleaseRuntimePolicyTests`) covering settings-tab routing, theme mapping, find-next cursor behavior, and subscription button state logic.
- Unified release automation in `scripts/release_all.sh` to run preflight checks before tagging and to verify uploaded release assets after notarized publish.
- README changelog summary automation now keeps release summaries version-sorted and limited to the latest three entries.

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

- Tag: `v0.4.11`
- Tagged commit: `TBD`
- Verify local tag target:

```bash
git rev-parse --verify v0.4.11
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
