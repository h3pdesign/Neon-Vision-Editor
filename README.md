<p align="center"><a href="https://apps-h3p.com"><img alt="Docs on h3p apps" src="https://img.shields.io/badge/Docs-h3p%20apps-111827?style=for-the-badge"></a><a href="https://buymeacoffee.com/h3pdesign"><img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Buy%20Me%20a-Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=111827"></a><a href="https://www.patreon.com/h3p"><img alt="Support on Patreon" src="https://img.shields.io/badge/Support%20on-Patreon-F96854?style=for-the-badge&logo=patreon&logoColor=white"></a><a href="https://www.paypal.com/paypalme/HilthartPedersen"><img alt="Support via PayPal" src="https://img.shields.io/badge/Support%20via-PayPal-0070BA?style=for-the-badge&logo=paypal&logoColor=white"></a></p>

<p align="center">
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases"><img alt="Latest Release" src="https://img.shields.io/badge/release-v0.8.3-0A84FF"></a>
  <a href="https://apps.apple.com/de/app/neon-vision-editor/id6758950965"><img alt="Platforms" src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20iPadOS-0A84FF"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/actions/workflows/release-notarized.yml"><img alt="Notarized Release" src="https://img.shields.io/github/actions/workflow/status/h3pdesign/Neon-Vision-Editor/release-notarized.yml?branch=main&label=Notarized%20Release"></a>
  <a href="https://github.com/h3pdesign/homebrew-tap/actions/workflows/update-cask.yml"><img alt="Homebrew Cask Sync" src="https://img.shields.io/github/actions/workflow/status/h3pdesign/homebrew-tap/update-cask.yml?label=Homebrew%20Cask%20Sync"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/SECURITY.md"><img alt="Security Policy" src="https://img.shields.io/badge/security-policy-22C55E"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/commits/main"><img alt="SSH Signed Commits" src="https://img.shields.io/badge/commits-SSH%20signed-2563EB"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/license-Apache--2.0-green.svg"></a>
</p>

<p align="center">&nbsp;</p>

<div align="center">
  <img src="docs/images/readme-wordmark.svg" alt="Neon Vision Editor wordmark" width="680"/><br>
  <img src="docs/images/readme-hero-accent.svg" alt="Neon Vision Editor accent line" width="180"/>
</div>

<p align="center">&nbsp;</p>

<p align="center">
  <img src="docs/images/NeonVisionEditorIcon.png?v=20260310" alt="Neon Vision Editor Logo" width="228"/>
</p>

<p align="center">
  <strong>Neon Vision Editor</strong>
</p>

<p align="center">
  <strong><span style="font-size: 1.2em;">A native editor for markdown, notes, and code across macOS, iPhone, and iPad.</span></strong>
</p>

<p align="center">
  Minimal by design. Quick edits, fast file access, no IDE bloat.
</p>

<p align="center">&nbsp;</p>

<p align="center">
  <strong>Download:</strong>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases">GitHub Releases</a>
  ·
  <a href="https://apps.apple.com/de/app/neon-vision-editor/id6758950965">App Store</a>
  ·
  <a href="https://testflight.apple.com/join/YWB2fGAP">TestFlight</a>
</p>

<p align="center">
  <a href="docs/images/readme-hero-macos-light.png">
    <img src="docs/images/readme-hero-macos-light.png" alt="Neon Vision Editor macOS light editor with code minimap" width="96%">
  </a>
</p>

> Status: **active release**  
> Latest release: **v0.8.3**
> Next release target: **v0.8.4**
> Platform target: **macOS 26 (Tahoe)** compatible with **macOS Sequoia**
> Apple Silicon: tested / Intel: not tested
> Direct GitHub release: **v0.8.3** / iOS App Store approved: **v0.7.8** / iOS App Store review pending: **v0.8.2** / macOS App Store approved: **v0.8.2** / macOS App Store review approved: **v0.8.2**
> Last updated (README): **2026-07-04** for latest release **v0.8.3**

## What's New in v0.8.2 and v0.8.3

### Why Upgrade

- v0.8.3: Fixes the Apple Vision Pro Settings entry path reported during App Store review and hardens settings presentation on first launch.
- v0.8.3: Expands Markdown preview compatibility with GitHub Flavored Markdown, safer re-rendering, and syntax-colored code blocks.
- v0.8.3: Polishes macOS Settings sizing, translucency, and theme controls while keeping iPad editor and preview text sizes aligned.

### v0.8.3 Highlights

- Added GitHub Flavored Markdown as the default preview mode while keeping CommonMark compatibility available.
- Added Markdown code-block language controls and syntax highlighting with theme-aware, higher-contrast colors.
- Enabled line wrap by default for new installs across supported platforms while preserving existing user preferences.
- Reduced editor/preview update overhead so Markdown edits and preview refreshes stay responsive during active typing.
- Required HTTPS for custom AI provider endpoints to keep user-configured network integrations on secure transports.

### v0.8.2 Context

- v0.8.2: Improves visionOS settings with a compact two-pane layout, clearer categories, and less wasted space.
- v0.8.2: Fixes visionOS toolbar placement and spacing so actions use the available window width more predictably.
- v0.8.2: Refines macOS translucent sidebars and resize handling so editor chrome feels cleaner while preserving usable resize hit areas.

### v0.8.2 Highlights

- Reworked visionOS Settings into a narrow category rail and detailed form sections for General, Editor, Appearance, Toolbar, AI, Remote, Shortcuts, and Diagnostics.
- Added compact toolbar settings outside General so long toggle lists no longer create large gaps in the main settings view.
- Tuned macOS sidebar/tab transitions and translucent backgrounds for a smoother editor/sidebar boundary.

## Start Here

- Jump: [Install](#install) | [Features](#features) | [Contributing](#contributing-quickstart)
- Quick install: [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases), [App Store](https://apps.apple.com/de/app/neon-vision-editor/id6758950965), [TestFlight](https://testflight.apple.com/join/YWB2fGAP)
- Need help quickly: [Troubleshooting](#troubleshooting) | [FAQ](#faq) | [Known Issues](#known-issues)

### Start in 60s (Source Build)

1. `git clone https://github.com/h3pdesign/Neon-Vision-Editor.git`
2. `cd Neon-Vision-Editor`
3. `xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" -destination 'platform=macOS,name=My Mac' build`
4. `open "Neon Vision Editor.xcodeproj"` and run, then use `Cmd+P` for Quick Open.

| For | Not For |
|---|---|
| Fast native editing across macOS, iOS, iPadOS | Full IDE workflows with deep refactoring/debugger stacks |
| Markdown writing and script/config edits with highlighting | Teams that require complete Intel Mac validation today |
| Users who want low overhead and quick file access | Users expecting full desktop-IDE parity on iPhone |

## Table of Contents

<p align="center">
  <a href="#start-here">Start Here</a> ·
  <a href="#release-channels">Release Channels</a> ·
  <a href="#core-workflows">Core Workflows</a> ·
  <a href="#download-metrics">Download Metrics</a> ·
  <a href="#project-documentation">Project Documentation</a> ·
  <a href="#features">Features</a>
</p>
<p align="center">
  <a href="#release-spotlight">Release Spotlight</a> ·
  <a href="#platform-matrix">Platform Matrix</a> ·
  <a href="#roadmap-near-term">Roadmap (Near Term)</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="#changelog">Changelog</a> ·
  <a href="#contributing-quickstart">Contributing Quickstart</a> ·
  <a href="#support--feedback">Support & Feedback</a>
</p>

## Release Channels

<div align="center">
  <table>
    <thead>
      <tr>
        <th>Channel</th>
        <th>Best for</th>
        <th>Delivery</th>
        <th>Current status</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><img alt="Stable" src="https://img.shields.io/badge/Stable-22C55E?style=flat-square"></td>
        <td>Direct notarized builds and fastest stable updates</td>
        <td><a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases">GitHub Releases</a></td>
        <td>v0.8.3 release docs current; v0.8.3 direct download current</td>
      </tr>
      <tr>
        <td><img alt="Store" src="https://img.shields.io/badge/Store-0A84FF?style=flat-square"></td>
        <td>Apple-managed install/update flow</td>
        <td><a href="https://apps.apple.com/de/app/neon-vision-editor/id6758950965">App Store</a></td>
        <td>v0.8.2 public listing current</td>
      </tr>
      <tr>
        <td><img alt="Beta" src="https://img.shields.io/badge/Beta-F59E0B?style=flat-square"></td>
        <td>Early testing of upcoming changes</td>
        <td><a href="https://testflight.apple.com/join/YWB2fGAP">TestFlight</a></td>
        <td>Newest beta availability may vary by review state</td>
      </tr>
    </tbody>
  </table>
</div>

## Download Metrics

<p align="center">
  <img alt="All Downloads" src="https://img.shields.io/static/v1?label=All+Downloads&message=3338&color=0A84FF&style=for-the-badge">
  <img alt="v0.8.3 Downloads" src="https://img.shields.io/static/v1?label=v0.8.3&message=56&color=22C55E&style=for-the-badge">
</p>

<p align="center"><strong>Release Download + Traffic Trend</strong></p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/release-download-trend-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/release-download-trend-light.svg">
    <img src="docs/images/release-download-trend-light.svg" alt="GitHub release downloads trend chart" width="96%">
  </picture>
</p>

<p align="center"><em>Styled line chart shows per-release totals with 14-day traffic counters for clones and views.</em></p>
<p align="center">
  <img alt="Unique cloners (14d)" src="https://img.shields.io/static/v1?label=Unique+cloners+%2814d%29&message=470&color=7C3AED&style=for-the-badge">
  <img alt="Unique visitors (14d)" src="https://img.shields.io/static/v1?label=Unique+visitors+%2814d%29&message=118&color=0EA5E9&style=for-the-badge">
</p>
<p align="center">
  <img alt="Clone snapshot (UTC)" src="https://img.shields.io/static/v1?label=Clone+snapshot+%28UTC%29&message=2026-07-04&color=334155&style=flat-square">
  <img alt="View snapshot (UTC)" src="https://img.shields.io/static/v1?label=View+snapshot+%28UTC%29&message=2026-07-04&color=334155&style=flat-square">
</p>

## Project Documentation

| Document | Purpose |
|---|---|
| [`CHANGELOG.md`](CHANGELOG.md) | Full release history and milestone issue coverage |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Local setup, build, and contribution workflow |
| [`PRIVACY.md`](PRIVACY.md) | Privacy guarantees and data-handling policy |
| [`SECURITY.md`](SECURITY.md) | Security policy and responsible disclosure |
| [`release/`](release/) | TestFlight, App Store, and release preflight checklists |

## Who Is This For?

| Best For | Why Neon Vision Editor |
|---|---|
| Quick note takers | Fast native startup and low UI overhead for quick edits |
| Markdown-focused writers | Clean editing with quick preview workflows on Apple devices |
| Developers editing scripts/config files | Syntax highlighting + fast file navigation without full IDE complexity |

## Why This Instead of a Full IDE?

| Advantage | What It Means |
|---|---|
| Faster startup | Lower overhead for short edit sessions |
| Focused surface | Editor-first workflow without project-system bloat |
| Native Apple behavior | Consistent experience on macOS, iOS, and iPadOS |

## Download

Prebuilt binaries are available on [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases).

The direct GitHub release is currently ahead of the App Store version. The App Store version may temporarily lag while updates are in Apple review.

| Channel | Platform | Best For | Download | Release Track | Notes |
|---|---|---|---|---|---|
| **Stable** | macOS | Direct notarized builds and fastest stable updates | [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases) | **v0.8.2** | Current direct download |
| **Store** | iOS / iPadOS | Apple-managed installs and updates | [Neon Vision Editor on the App Store](https://apps.apple.com/de/app/neon-vision-editor/id6758950965) | **v0.7.8** | Current public App Store listing |
| **Store** | macOS | Apple-managed installs and updates | [Neon Vision Editor on the App Store](https://apps.apple.com/de/app/neon-vision-editor/id6758950965) | **v0.8.2** | Current public App Store listing |
| **Store Review** | iOS / iPadOS | Upcoming App Store update | App Store Connect review | **v0.8.2** | In Apple review |
| **Store Review** | macOS | Upcoming App Store update | App Store Connect review | **v0.8.2** | Pending Apple review |
| **Beta** | iOS / iPadOS / macOS | Testing upcoming changes before stable | [TestFlight Invite](https://testflight.apple.com/join/YWB2fGAP) | **v0.8.2** | Early access builds for feedback; availability may vary by review state |

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

### Command line helper

The macOS app bundles an optional `nve` helper for terminal workflows. Install it only when you want a shell command:

1. Open **Settings > Support**.
2. Copy the **Command Line Helper** install command.
3. Run it in Terminal to link the bundled helper into `$HOME/bin`.

```bash
nve README.md
nve --wait --new-window "Neon Vision Editor/UI/ContentView.swift"
nve --line 42 "Neon Vision Editor/UI/ContentView.swift"
```

Development builds can also link the repository copy:

```bash
ln -sf "$PWD/scripts/nve" "$HOME/.local/bin/nve"
```

Permission model: the helper is optional and user-linked. It calls macOS Launch Services through `/usr/bin/open` and does not read file contents itself. Neon Vision Editor handles the document-open request inside the sandbox with user-selected read/write file access and security-scoped file access. It does not require Full Disk Access, Accessibility access, administrator permission, background services, or telemetry. See [`docs/CommandLineHelper.md`](docs/CommandLineHelper.md).

### Gatekeeper (macOS 26 Tahoe)

If macOS blocks first launch:

1. Open **System Settings**.
2. Go to **Privacy & Security**.
3. In **Security**, find the blocked app message.
4. Click **Open Anyway**.
5. Confirm the dialog.

## Core Workflows

<p align="center">
  <img alt="Project Sidebar" src="https://img.shields.io/badge/Project%20Sidebar-450pt%20Tabs-0891B2?style=for-the-badge">
  <img alt="Find in Files" src="https://img.shields.io/badge/Find%20in%20Files-Stays%20Open-2563EB?style=for-the-badge">
  <img alt="Markdown Preview" src="https://img.shields.io/badge/Markdown%20Preview-Toolbar%20Style%20%2B%20Export-DB2777?style=for-the-badge">
  <img alt="Remote Sessions" src="https://img.shields.io/badge/Remote%20Sessions-Opt--In%20Broker-0F766E?style=for-the-badge">
  <img alt="Code Minimap" src="https://img.shields.io/badge/Code%20Minimap-Optional%20Navigation-9333EA?style=for-the-badge">
  <img alt="Quick Open" src="https://img.shields.io/badge/Quick%20Open-Fast%20File%20Jump-7C3AED?style=for-the-badge">
</p>
<p align="center"><sub>Project Sidebar keeps Files, Search, Diff, Git, and Terminal in one stable surface. Remote Sessions stay opt-in and user-triggered. Markdown Preview keeps style and export in one toolbar flow.</sub></p>

## Features

Neon Vision Editor keeps the surface minimal and focuses on fast writing/coding workflows.
Platform-specific availability is tracked in the [Platform Matrix](#platform-matrix) section below.

<p align="center">
  <strong>Editing Core</strong>
</p>
<p align="center">
  <img alt="Fast Editing" src="https://img.shields.io/badge/Fast%20Editing-Tabbed%20%2B%20Large%20Files-22C55E?style=for-the-badge">
  <img alt="Invisible Characters" src="https://img.shields.io/badge/Invisible%20Chars-iPhone%20%2B%20iPad%20Aligned-14B8A6?style=for-the-badge">
  <img alt="Tabs" src="https://img.shields.io/badge/Tabs-Double--Click%20Close-4F46E5?style=for-the-badge">
  <img alt="Syntax Highlighting" src="https://img.shields.io/badge/Syntax-Swift%206%20Ready-0A84FF?style=for-the-badge">
  <img alt="TeX Support" src="https://img.shields.io/badge/TeX%2FLaTeX-Syntax%20Highlighting-14B8A6?style=for-the-badge">
  <img alt="Regex Find Replace" src="https://img.shields.io/badge/Find%20%26%20Replace-Regex%20Ready-F59E0B?style=for-the-badge">
  <img alt="Code Minimap" src="https://img.shields.io/badge/Code%20Minimap-Off%20By%20Default-9333EA?style=for-the-badge">
  <img alt="Vim Mode" src="https://img.shields.io/badge/Vim%20Mode-Hardware%20Keyboard-059669?style=for-the-badge">
</p>
<p align="center">
  <strong>Navigation & Preview</strong>
</p>
<p align="center">
  <img alt="Quick Open" src="https://img.shields.io/badge/Quick%20Open-Cmd%2BP-7C3AED?style=for-the-badge">
  <img alt="Project Sidebar" src="https://img.shields.io/badge/Project%20Sidebar-Files%20%2F%20Search%20%2F%20Diff%20%2F%20Git-0891B2?style=for-the-badge">
  <img alt="Terminal Sidebar" src="https://img.shields.io/badge/Terminal-Sidebar%20Session-6366F1?style=for-the-badge">
  <img alt="CLI" src="https://img.shields.io/badge/CLI-nve%20Helper-111827?style=for-the-badge">
  <img alt="Indexed Search" src="https://img.shields.io/badge/Find%20in%20Files-No%20Default%20Replace%20Selection-2563EB?style=for-the-badge">
  <img alt="Diff View" src="https://img.shields.io/badge/Diff%20View-Stable%20Sidebar%20Width-16A34A?style=for-the-badge">
  <img alt="Markdown Preview" src="https://img.shields.io/badge/Markdown-Preview%20Templates-DB2777?style=for-the-badge">
  <img alt="Markdown PDF Export" src="https://img.shields.io/badge/Markdown%20PDF-Paginated%20%2B%20One--Page-7C3AED?style=for-the-badge">
  <img alt="Remote Sessions" src="https://img.shields.io/badge/Remote-Browse%20%2B%20Explicit%20Save-0F766E?style=for-the-badge">
</p>
<p align="center">
  <strong>Platform, Output & Customization</strong>
</p>
<p align="center">
  <img alt="Cross Platform" src="https://img.shields.io/badge/Cross--Platform-macOS%20%7C%20iOS%20%7C%20iPadOS-2563EB?style=for-the-badge">
  <img alt="Text Export" src="https://img.shields.io/badge/Text%20Export-Markdown%20%2B%20Swift%20Types-0A84FF?style=for-the-badge">
  <img alt="Code Snapshot" src="https://img.shields.io/badge/Code%20Snapshot-Share%20Images-F97316?style=for-the-badge">
  <img alt="Themes" src="https://img.shields.io/badge/Themes-Prism%20Daylight-DB2777?style=for-the-badge">
  <img alt="iCloud Settings Sync" src="https://img.shields.io/badge/iCloud-Appearance%20%2B%20Themes-0EA5E9?style=for-the-badge">
</p>
<p align="center">
  <strong>Safety & Privacy</strong>
</p>
<p align="center">
  <img alt="Safety" src="https://img.shields.io/badge/Safety-Unsupported%20File%20Guards-EA580C?style=for-the-badge">
  <img alt="Safe Mode" src="https://img.shields.io/badge/Safe%20Mode-Startup%20Recovery-E11D48?style=for-the-badge">
  <img alt="Privacy" src="https://img.shields.io/badge/Privacy-No%20Telemetry-111827?style=for-the-badge">
</p>

### Editing Core

- Fast loading for regular and large text files with tabbed editing.
- Broad Swift 6-ready syntax highlighting (including TeX/LaTeX), inline completion with Tab-to-accept, and regex Find/Replace with Replace All.
- Optional Code Minimap gives a compact file overview and click-to-jump navigation without changing the default editor surface.
- Invisible-character markers on iPhone and iPad render in a lightweight overlay so spaces, tabs, and newlines stay aligned while scrolling.
- Optional Vim workflow support and starter templates for common languages.

### Navigation & Workflow

- Quick Open (`Cmd+P`), project sidebar navigation, and recursive project tree rendering.
- Files, Search, Diff, and Git share larger card-style sidebar tabs with visible grey inactive states and a consistent 450 pt default width.
- The macOS project sidebar includes a Terminal tab that keeps output while switching tabs, offers project/home working-directory choices, and provides clear/restart controls.
- `scripts/nve` opens files from the terminal and supports `--wait`, `--new-window`, and `--line` compatibility flags.
- Find in Files keeps results visible on Mac and iPad when a match opens, while replacement targets start unselected by default.
- Remote Sessions are opt-in: macOS owns SSH-key login and can publish an attach code so iPhone and iPad can browse, open, edit, and explicitly save supported remote text files through the Mac-hosted broker.
- Project quick actions (`Expand All` / `Collapse All`), recent project folders, supported-files-only filtering, and default ignored heavy folders (`.git`, `.build`, `node_modules`, `DerivedData`).

### Settings & Sync

- Optional iCloud Appearance & Theme Sync keeps appearance, theme colors, custom theme data, formatting toggles, and Markdown preview theme behavior aligned across signed-in devices.
- Sync status includes the latest local iCloud result and timestamp. Documents, API tokens, remote sessions, and editor contents are not synced.

### Compare & Save

- Native side-by-side diff view for Compare with Disk and Compare Open Tabs workflows, with change navigation.
- Cross-platform `Save As…` and Close All Tabs with confirmation.
- Remote saves are explicit and conflict-aware; if the remote revision changes, the app offers a compare-before-reload path instead of overwriting silently.

### Preview, Platform, and Safety

- Native Markdown preview templates on macOS/iOS/iPadOS plus iPhone bottom-sheet preview.
- `.svg` file support via XML mode and bracket helper on all platforms.
- Markdown and Swift source exports declare their content types correctly on iOS.
- Unsupported-file open/import safety guards, remote text-file limits, and session restore for previously opened project folder.

### Customization & Diagnostics

- Built-in theme collection: Dracula, One Dark Pro, Nord, Tokyo Night, Gruvbox, and Neon Glow.
- Grouped settings, optional StoreKit support flow, and AI Activity Log diagnostics on macOS.

## Release Spotlight

<p align="center">
  <img alt="Release Spotlight" src="https://img.shields.io/badge/RELEASE%20SPOTLIGHT-v0.8.1%20App%20Store%20Compliance-22C55E?style=for-the-badge">
  <img alt="GitHub Release" src="https://img.shields.io/badge/GitHub-Release%20Workflow-0A84FF?style=for-the-badge">
  <img alt="Preview Panes" src="https://img.shields.io/badge/Preview-SVG%20%2B%20HTML-0891B2?style=for-the-badge">
</p>

- iPadOS App Store builds keep terminal and shell-execution entry points macOS-only.
- GitHub can now create and publish release tags, ZIP, DMG, checksums, and notes from the manual release workflow.
- SVG and HTML previews open beside source files, and Markdown preview can passively render embedded HTML.
- No release behavior changes network access, token storage, sandboxing, or telemetry posture.

## Architecture At A Glance

```mermaid
flowchart LR
  Mac["Platform: macOS shell (SwiftUI + AppKit bridges)"]
  IOS["Platform: iOS/iPadOS shell (SwiftUI + UIKit bridges)"]
  ACT["App Layer: user actions (toolbar/menu/shortcuts)"]
  VM["App Layer: EditorViewModel (@MainActor state owner)"]
  CMD["App Layer: command reducers (Flux-style mutations)"]
  IO["Core: file I/O + load/sanitize pipeline"]
  HL["Core: syntax highlighting + runtime limits"]
  FIND["Core: find/replace + selection engine"]
  PREV["Core: markdown preview renderer"]
  MINI["Core: code minimap snapshot builder"]
  REMOTE["Core: RemoteSessionStore (opt-in broker + SSH owner)"]
  GIT["Core: GitService (macOS-only shell bridge)"]
  TERM["Core: sidebar terminal runner (macOS-only)"]
  SAFE["Core: unsupported-file safety guards"]
  STORE["Infra: tabs + session restore store"]
  PREFS["Infra: settings + persistence"]
  SEC["Infra: SecureTokenStore (Keychain)"]
  UPD["Infra: release update manager"]

  Mac --> ACT
  IOS --> ACT
  ACT --> VM
  VM --> CMD
  CMD --> STORE
  VM --> IO
  VM --> HL
  VM --> FIND
  VM --> PREV
  VM --> MINI
  VM --> REMOTE
  VM --> GIT
  VM --> TERM
  VM --> SAFE
  VM --> PREFS
  VM --> UPD
  PREFS --> STORE
  IO --> STORE
  VM --> SEC
  REMOTE --> SEC

  classDef platform stroke:#2563EB,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;
  classDef app stroke:#059669,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;
  classDef core stroke:#EA580C,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;
  classDef infra stroke:#9333EA,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;

  class Mac,IOS platform;
  class ACT,VM,CMD app;
  class IO,HL,FIND,PREV,MINI,REMOTE,GIT,TERM,SAFE core;
  class STORE,PREFS,SEC,UPD infra;
```

- `EditorViewModel` is the single UI-facing orchestration point per window/scene.
- Commands mutate editor state predictably; session/tabs persist through store services.
- File access and parsing stay off the main thread; UI state changes stay on the main thread.
- Platform shells stay thin and route interactions into shared app/core services.
- Remote sessions stay opt-in; macOS owns SSH-key login while iPhone and iPad attach through the Mac-hosted broker.
- Security-sensitive credentials and SSH-key bookmarks remain in Keychain (`SecureTokenStore`), not plain prefs.
- Color key in diagram: blue = platform shell, green = app orchestration, orange = core services, purple = infrastructure.

Full architecture reference: [`architecture.md`](architecture.md). The reference tracks the current Swift 6 cross-platform structure, platform guards, editor rendering paths, performance rules, and release verification workflow.

### Architecture principles

- Keep UI mutations on the main thread (`@MainActor`) and heavy work off the UI thread.
- Keep window/scene state isolated to avoid accidental cross-window coupling.
- Keep security defaults strict: tokens in Keychain, no telemetry by default.
- Keep platform wrappers thin and push shared behavior into common services.

## Platform Matrix

Most editor features are shared across macOS, iOS, and iPadOS.

### Shared Across All Platforms

- Fast text editing with syntax highlighting.
- Markdown preview templates (Default, Docs, Article, Compact).
- Project sidebar with supported-files filter and larger card-style tabs; Git and Terminal are macOS-only.
- Unsupported-file safety alerts.
- SVG (`.svg`) support via XML mode.
- Close All Tabs with confirmation.
- Bracket helper and grouped Settings cards.
- Optional remote attach clients on iPhone and iPad when a Mac-hosted broker session is active.
- Cross-platform release gate covers macOS, iOS Simulator, and iPad Simulator builds.

### Platform-Specific Differences

| Capability | macOS | iOS | iPadOS | Notes |
|---|---|---|---|---|
| Quick Open<br><sub>`Cmd+P`</sub> | ![Full](https://img.shields.io/badge/Full-22C55E?style=flat-square) | ![Limit](https://img.shields.io/badge/Limit-F59E0B?style=flat-square) | ![Full](https://img.shields.io/badge/Full-22C55E?style=flat-square) | iOS needs a hardware keyboard<br>for shortcut-driven flow. |
| Project Sidebar Tabs<br><sub>v0.6.9</sub> | ![Full](https://img.shields.io/badge/Full-22C55E?style=flat-square) | ![Compact](https://img.shields.io/badge/Compact-F59E0B?style=flat-square) | ![Full](https://img.shields.io/badge/Full-22C55E?style=flat-square) | Files/Search/Diff/Git use larger card targets;<br>regular-width sidebar defaults to 450 pt. |
| Find in Files<br><sub>v0.6.8-v0.6.9</sub> | ![Sidebar](https://img.shields.io/badge/Sidebar-0891B2?style=flat-square) | ![Sheet](https://img.shields.io/badge/Sheet-DB2777?style=flat-square) | ![Sidebar](https://img.shields.io/badge/Sidebar-0891B2?style=flat-square) | Mac/iPad results stay open when opening a match;<br>replacement targets start unselected. |
| Invisible Characters<br><sub>v0.6.9</sub> | ![Native](https://img.shields.io/badge/Native-0A84FF?style=flat-square) | ![Overlay](https://img.shields.io/badge/Overlay-22C55E?style=flat-square) | ![Overlay](https://img.shields.io/badge/Overlay-22C55E?style=flat-square) | iPhone/iPad markers draw in a lightweight viewport overlay<br>to stay aligned while scrolling. |
| Line Wrap Default<br><sub>v0.8.2</sub> | ![On New Installs](https://img.shields.io/badge/On_New_Installs-22C55E?style=flat-square) | ![On New Installs](https://img.shields.io/badge/On_New_Installs-22C55E?style=flat-square) | ![On New Installs](https://img.shields.io/badge/On_New_Installs-22C55E?style=flat-square) | Fresh installs start with wrapping enabled;<br>existing preferences are preserved everywhere. |
| No-Wrap Long Lines<br><sub>v0.7.8</sub> | ![Horizontal](https://img.shields.io/badge/Horizontal-0A84FF?style=flat-square) | ![Horizontal](https://img.shields.io/badge/Horizontal-0A84FF?style=flat-square) | ![Horizontal](https://img.shields.io/badge/Horizontal-0A84FF?style=flat-square) | Long lines continue through horizontal scrolling<br>instead of clipping at the right edge. |
| Cursor Status<br><sub>v0.7.8</sub> | ![Live](https://img.shields.io/badge/Live-22C55E?style=flat-square) | ![Live](https://img.shields.io/badge/Live-22C55E?style=flat-square) | ![Live](https://img.shields.io/badge/Live-22C55E?style=flat-square) | Status bar line/column updates after edits,<br>caret movement, scrolling, and line jumps. |
| Code Minimap | ![Opt In](https://img.shields.io/badge/Opt_In-9333EA?style=flat-square) | ![Opt In](https://img.shields.io/badge/Opt_In-9333EA?style=flat-square) | ![Opt In](https://img.shields.io/badge/Opt_In-9333EA?style=flat-square) | Disabled by default; supported languages show<br>a compact overview and click-to-jump navigation. |
| Bracket Helper | ![Toolbar](https://img.shields.io/badge/Toolbar-0A84FF?style=flat-square) | ![Kbd Bar](https://img.shields.io/badge/Kbd_Bar-7C3AED?style=flat-square) | ![Kbd Bar](https://img.shields.io/badge/Kbd_Bar-7C3AED?style=flat-square) | Same behavior across platforms;<br>only the UI surface differs. |
| Markdown Preview | ![Inline](https://img.shields.io/badge/Inline-0891B2?style=flat-square) | ![Sheet](https://img.shields.io/badge/Sheet-DB2777?style=flat-square) | ![Inline](https://img.shields.io/badge/Inline-0891B2?style=flat-square) | Interaction adapts to screen size<br>and platform input model. |
| Diff Workflows<br><sub>v0.6.8-v0.6.9</sub> | ![Inline](https://img.shields.io/badge/Inline-16A34A?style=flat-square) | ![Compact](https://img.shields.io/badge/Compact-F59E0B?style=flat-square) | ![Inline](https://img.shields.io/badge/Inline-16A34A?style=flat-square) | iPhone uses compact sidebar/sheet presentation;<br>Mac/iPad keep stable sidebar width. |
| Git Sidebar<br><sub>v0.6.7+</sub> | ![Available](https://img.shields.io/badge/Available-22C55E?style=flat-square) | ![N/A](https://img.shields.io/badge/N%2FA-6B7280?style=flat-square) | ![N/A](https://img.shields.io/badge/N%2FA-6B7280?style=flat-square) | Git uses a macOS-only service because it shells out<br>to the local Git executable. |
| Remote Sessions | ![SSH Owner](https://img.shields.io/badge/SSH_Owner-0F766E?style=flat-square) | ![Broker Client](https://img.shields.io/badge/Broker_Client-0F766E?style=flat-square) | ![Broker Client](https://img.shields.io/badge/Broker_Client-0F766E?style=flat-square) | Off by default. Mac starts the SSH session;<br>iPhone/iPad attach with a code for browse/open/explicit save. |
| Save As / Text Export<br><sub>v0.6.9</sub> | ![Native](https://img.shields.io/badge/Native-0A84FF?style=flat-square) | ![Exporter](https://img.shields.io/badge/Exporter-22C55E?style=flat-square) | ![Exporter](https://img.shields.io/badge/Exporter-22C55E?style=flat-square) | iOS/iPadOS export declares Markdown and Swift source<br>content types for text saves. |

## Trust & Reliability Signals

- Notarized release pipeline: [release-notarized.yml](https://github.com/h3pdesign/Neon-Vision-Editor/actions/workflows/release-notarized.yml)
- Pre-release verification gate: [pre-release-ci.yml](https://github.com/h3pdesign/Neon-Vision-Editor/actions/workflows/pre-release-ci.yml)
- Security scanning: [CodeQL workflow](https://github.com/h3pdesign/Neon-Vision-Editor/actions/workflows/codeql.yml)
- Homebrew cask sync: [update-cask.yml](https://github.com/h3pdesign/homebrew-tap/actions/workflows/update-cask.yml)

More release integrity details: [Release Integrity](#release-integrity)

## Platform Gallery

- [macOS](#macos)
- [iPad](#ipad)
- [iPhone](#iphone)
- Source image index for docs: [`docs/images/README.md`](docs/images/README.md)
- App Store gallery: [Neon Vision Editor on App Store](https://apps.apple.com/de/app/neon-vision-editor/id6758950965)
- Latest release assets: [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases)

### macOS

<table align="center">
  <tr>
    <td align="center">
      <a href="docs/images/mac-light-editor-sidebar.png">
        <img src="docs/images/mac-light-editor-sidebar.png" alt="Neon Vision Editor macOS light editor with symbol sidebar" width="520">
      </a><br>
      <sub>Light editor workspace with symbol navigation</sub>
    </td>
    <td align="center">
      <a href="docs/images/mac-light-editor-wide.png">
        <img src="docs/images/mac-light-editor-wide.png" alt="Neon Vision Editor macOS wide light editor workspace" width="520">
      </a><br>
      <sub>Wide light editor workspace with toolbar actions</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <a href="docs/images/mac-light-editor-compact.png">
        <img src="docs/images/mac-light-editor-compact.png" alt="Neon Vision Editor macOS compact light editor workspace" width="520">
      </a><br>
      <sub>Compact light editor workspace with focused code view</sub>
    </td>
    <td align="center">
      <a href="docs/images/mac-light-editor-minimap.png">
        <img src="docs/images/mac-light-editor-minimap.png" alt="Neon Vision Editor macOS light editor with code minimap" width="520">
      </a><br>
      <sub>Light editor workspace with code minimap</sub>
    </td>
  </tr>
</table>

### iPad

<table align="center">
  <tr>
    <td align="center">
      <a href="docs/images/ipad-editor-light.png">
        <img src="docs/images/ipad-editor-light.png" alt="iPad editor in light mode" width="520">
      </a><br>
      <sub>Project navigation and editing workflow on iPad</sub>
    </td>
    <td align="center">
      <a href="docs/images/ipad-editor-dark.png">
        <img src="docs/images/ipad-editor-dark.png" alt="iPad editor in dark mode" width="520">
      </a><br>
      <sub>Markdown preview workflow in the editor context</sub>
    </td>
  </tr>
</table>

### iPhone

<div align="center">
  <table width="100%" style="max-width: 760px; margin: 0 auto;">
    <tr>
      <td align="center" width="50%">
        <a href="docs/images/iphone-editor-light-frame-updated.png">
          <img src="docs/images/iphone-editor-light-frame-updated.png" alt="iPhone editor screenshot in light mode with syntax highlighting and keyboard bar" width="280">
        </a><br>
        <sub>Editing workflow with syntax highlighting and accessory bar</sub>
      </td>
      <td align="center" width="50%">
        <a href="docs/images/iphone-menu-dark-frame.png">
          <img src="docs/images/iphone-menu-dark-frame.png" alt="iPhone editor screenshot with dark overflow menu open" width="280">
        </a><br>
        <sub>Overflow menu actions in the editor workflow</sub>
      </td>
    </tr>
    <tr>
      <td align="center" width="50%">
        <a href="docs/images/iphone-markdown-preview-dark.png">
          <img src="docs/images/iphone-markdown-preview-dark.png" alt="iPhone markdown preview screenshot in dark mode with export controls" width="280">
        </a><br>
        <sub>Markdown preview sheet with template, PDF mode, and export action</sub>
      </td>
      <td align="center" width="50%">
        <a href="docs/images/iphone-themes-light-frame.png">
          <img src="docs/images/iphone-themes-light-frame.png" alt="iPhone theme colors editor screenshot in light mode" width="280">
        </a><br>
        <sub>Theme color editing on iPhone</sub>
      </td>
    </tr>
  </table>
</div>

## Release Train

| Track | Current Focus | Status |
|---|---|---|
| Stable direct download | `v0.8.3` notarized GitHub release | Current |
| App Store rollout | Public `v0.8.0`, `v0.8.1` prepared for review follow-up | Preparing App Store review follow-up |
| Post-0.8 stabilization | Crash triage, docs freshness, platform polish, App Store/Xcode Cloud release checks | Next patch train |
| Larger workflow work | Remote workflow hardening, minimap polish, project navigation refinements | Later `v0.8+` work |

## Roadmap (Near Term)

<p align="center">
  <img alt="Now" src="https://img.shields.io/badge/NOW-v0.8.3-22C55E?style=for-the-badge">
  <img alt="Next" src="https://img.shields.io/badge/NEXT-v0.8.4-F59E0B?style=for-the-badge">
  <img alt="Later" src="https://img.shields.io/badge/LATER-v0.8%2B-0A84FF?style=for-the-badge">
</p>

### Now (v0.8.3)

- ![v0.8.3](https://img.shields.io/badge/v0.8.3-22C55E?style=flat-square) focuses on App Store compliance hardening, GitHub-only release automation, SVG/HTML previews, and iPad editor layout polish.
  Tracking: [Release v0.8.3](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.8.3)

### Next (v0.8.4)

- ![v0.8.4](https://img.shields.io/badge/v0.8.4-F59E0B?style=flat-square) targets post-0.8.3 stabilization: App Store review follow-up, README/release metadata freshness, preview polish, and small cross-platform editor fixes.
  Tracking: [Milestones](https://github.com/h3pdesign/Neon-Vision-Editor/milestones)

### Later (v0.8+)

- ![v0.8+](https://img.shields.io/badge/v0.8%2B-0A84FF?style=flat-square) larger workflow expansion after the current cross-platform editor baseline is verified, with remote workflows and navigation surfaces kept opt-in until they are fully hardened.

## Known Issues

- Open known issues (live filter): [label:known-issue](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aknown-issue)

## Troubleshooting

1. App blocked on first launch: use Gatekeeper steps above in `Privacy & Security`.
2. Markdown preview not visible: use the preview action from an open Markdown file; iPhone presents preview in a sheet, while macOS and iPadOS can show it inline.
3. Shortcut not working on iOS: connect a hardware keyboard for shortcut-based flows like `Cmd+P`.
4. Sidebar/layout feels cramped on iPad: switch orientation or close side panels before preview.
5. Settings feel off after updates: quit/relaunch app and verify current release version in Settings.
6. Remote connection refused on a local Mac target: enable **System Settings > General > Sharing > Remote Login**, then start the Remote session again.

## Configuration

- Theme and appearance: `Settings > Designs`
- Appearance/theme iCloud sync: `Settings > Allgemein/General > Window`
- Editor behavior (font, line height, wrapping, snippets, minimap): `Settings > Editor`
- Startup/session behavior: `Settings > Allgemein/General`
- Remote sessions: `Settings > Mehr/More > Remote` or `Settings > Remote` on wider layouts
- Support and purchase options: `Settings > Mehr/More` (platform-dependent)

## FAQ

- **Does Neon Vision Editor support Intel Macs?**  
  Intel is currently not fully validated. If you can help test, see [Help wanted: Intel Mac test coverage](https://github.com/h3pdesign/Neon-Vision-Editor/issues/41).
- **Can I use it offline?**  
  Yes for core editing. Network is only used for explicit actions such as selected AI providers, update checks, GitHub release downloads, or opt-in Remote Sessions.
- **Do I need AI enabled to use the editor?**  
  No. Core editing, navigation, and preview features work without AI.
- **Where are tokens stored?**  
  In Keychain via `SecureTokenStore`, not in `UserDefaults`.

## Keyboard Shortcuts

All shortcuts use `Cmd` (`⌘`). iPad/iOS require a hardware keyboard.

![All](https://img.shields.io/badge/All-22C55E?style=flat-square) ![macOS](https://img.shields.io/badge/macOS-0A84FF?style=flat-square)

<table align="center" width="100%">
  <tr>
    <td width="50%" valign="top">
      <p><img alt="File" src="https://img.shields.io/badge/File-0A84FF?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+N</code></td><td>New Window</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+T</code></td><td>New Tab</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+O</code></td><td>Open File</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+O</code></td><td>Open Folder</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+S</code></td><td>Save</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+S</code></td><td>Save As...</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+W</code></td><td>Close Tab</td><td><img alt="macOS + iPadOS" src="https://img.shields.io/badge/macOS%20%2B%20iPadOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
    <td width="50%" valign="top">
      <p><img alt="Edit" src="https://img.shields.io/badge/Edit-16A34A?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+X</code></td><td>Cut</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+C</code></td><td>Copy</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+V</code></td><td>Paste</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+A</code></td><td>Select All</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Z</code></td><td>Undo</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+Z</code></td><td>Redo</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+D</code></td><td>Add Next Match</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <p><img alt="View" src="https://img.shields.io/badge/View-7C3AED?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+Option+S</code></td><td>Toggle Sidebar</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+D</code></td><td>Brain Dump Mode</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
    <td width="50%" valign="top">
      <p><img alt="Find" src="https://img.shields.io/badge/Find-CA8A04?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+F</code></td><td>Find &amp; Replace</td><td><img alt="All" src="https://img.shields.io/badge/All-22C55E?style=flat-square"></td></tr>
        <tr><td><code>Cmd+G</code></td><td>Find Next</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+F</code></td><td>Find in Files</td><td><img alt="macOS + iPadOS" src="https://img.shields.io/badge/macOS%20%2B%20iPadOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <p><img alt="Editor" src="https://img.shields.io/badge/Editor-DB2777?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+P</code></td><td>Quick Open</td><td><img alt="macOS + iPadOS" src="https://img.shields.io/badge/macOS%20%2B%20iPadOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+L</code></td><td>Go to Line</td><td><img alt="macOS + iPadOS" src="https://img.shields.io/badge/macOS%20%2B%20iPadOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+J</code></td><td>Go to Symbol</td><td><img alt="macOS + iPadOS" src="https://img.shields.io/badge/macOS%20%2B%20iPadOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+V</code></td><td>Toggle Vim<br>Mode</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
    <td width="50%" valign="top">
      <p><img alt="Tools" src="https://img.shields.io/badge/Tools-0891B2?style=flat-square"> <img alt="Diag" src="https://img.shields.io/badge/Diag-6B7280?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+Shift+G</code></td><td>Suggest Code</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+L</code></td><td>AI Activity Log</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+Shift+U</code></td><td>Inspect whitespace<br>at caret</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
  </tr>
</table>

## Changelog

Latest stable: **v0.8.3** (2026-07-02)

### Recent Releases (At a glance)

| Version | Date | Highlights | Fixes | Breaking changes | Migration |
|---|---|---|---|---|---|
| [`v0.8.3`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.8.3) | 2026-07-02 | GitHub Flavored Markdown as the default preview mode while keeping CommonMark compatibility available; Markdown code-block language controls and syntax highlighting with theme-aware, higher-contrast colors; Enabled line wrap by default for new installs across supported platforms while preserving existing user preferences; Reduced editor/preview update overhead so Markdown edits and preview refreshes stay responsive during active typing | Markdown preview crashes when editing heading markers, changing fenced-code language state, or re-rendering malformed intermediate Markdown; Markdown preview text sizing on iPad so preview text tracks the editor font size instead of rendering noticeably larger; first-open Settings placement and macOS Settings window sizing so theme controls, preview cards, and Markdown Preview settings fit without clipping | None noted | None required |
| [`v0.8.2`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.8.2) | 2026-06-29 | Reworked visionOS Settings into a narrow category rail and detailed form sections for General, Editor, Appearance, Toolbar, AI, Remote, Shortcuts, and Diagnostics; compact toolbar settings outside General so long toggle lists no longer create large gaps in the main settings view; Tuned macOS sidebar/tab transitions and translucent backgrounds for a smoother editor/sidebar boundary | clipped visionOS welcome controls, blank visionOS app icon metadata, toolbar alignment, and settings backgrounds; macOS sidebar resize cursor behavior by keeping the resize hit zone usable while hiding visible divider rails; right-sidebar tab bar transition behavior so the fade is only active when a sidebar is visible | None noted | None required |
| [`v0.8.1`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.8.1) | 2026-06-27 | a manual GitHub release workflow with dry-run support, secret preflight checks, draft-before-publish release handling, asset verification, SHA256 checksums, and post-release workflow dispatches; release metadata gates so release docs, README status, project version metadata, and the Welcome Tour What's New page are checked before GitHub release builds; dedicated SVG and HTML preview panes, including passive HTML rendering inside Markdown preview, with preview coordination moved out of the main content view; Split file preview coordination into dedicated preview files and added SVG and HTML web previews beside the source editor | SVG preview rendering so previews fit the pane without adding an extra dark background block; Markdown preview split mode on iPad so no-wrap editor text is horizontally scrollable instead of clipped; iPad toolbar spacing so actions use the full editor toolbar area instead of staying compressed | None noted | None required |

- Full release history: [`CHANGELOG.md`](CHANGELOG.md)
- Latest release: **v0.8.3**
- Compare recent changes: [v0.8.2...v0.8.3](https://github.com/h3pdesign/Neon-Vision-Editor/compare/v0.8.2...v0.8.3)

## Known Limitations

- Intel Mac support is not fully validated yet.
- Vim mode is intentionally lightweight, not full Vim emulation.
- iPhone and iPad workflows still offer a smaller feature set than macOS.

## Privacy & Security

- Privacy policy: [`PRIVACY.md`](PRIVACY.md).
- API keys are stored in Keychain (`SecureTokenStore`), not `UserDefaults`.
- Network traffic uses HTTPS.
- No telemetry.
- External AI requests only occur when code completion is enabled and a provider is selected.
- Remote Sessions are opt-in and user-triggered; when enabled, broker payloads are encrypted and SSH-key bookmarks stay in Keychain.
- Security policy and reporting details: [`SECURITY.md`](SECURITY.md).
- New repository commits are SSH-signed; older historical commits may still predate commit signing.
- Local SSH-signature verification in this clone can use the repo-scoped `.git_allowed_signers` file.

## Release Integrity

- Tag: `v0.8.3`
- Tagged commit: release tag target
- Verify local tag target:

```bash
git rev-parse --verify v0.8.3
```

- Verify downloaded artifact checksum locally:

```bash
shasum -a 256 <downloaded-file>
```

- Verify local SSH commit signatures in this clone:

```bash
git config --local gpg.ssh.allowedSignersFile .git_allowed_signers
git log --show-signature -1
```

## Release Policy

- `Stable`: tagged GitHub releases intended for daily use.
- `Beta`: TestFlight builds may include in-progress UX and platform polish.
- Cadence: fixes/polish can ship between minor tags, with summary notes mirrored in README and `CHANGELOG.md`.

## Requirements

### App Runtime

- Designed and tested for macOS 26 (Tahoe), with compatibility work for macOS 15 Sequoia.
- Xcode deployment target: macOS 15.0; iOS/iPadOS 18.6.
- Apple Silicon recommended

### Build Requirements

- Xcode with the macOS 26 SDK/toolchain for current release assets and icon payloads.
- iOS and iPadOS simulator runtimes installed in Xcode for cross-platform verification

## Build from source

If you already completed the [Start in 60s (Source Build)](#start-in-60s-source-build), you can open and run directly from Xcode.

```bash
git clone https://github.com/h3pdesign/Neon-Vision-Editor.git
cd Neon-Vision-Editor
open "Neon Vision Editor.xcodeproj"
```

## Contributing Quickstart

Contributor guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)

1. Fork the repo and create a focused branch.
2. Implement the smallest safe diff for your change.
3. Build on macOS first.
4. Run cross-platform verification script.
5. Open a PR with screenshots for UI changes and a short risk note.
6. Link to related issue/milestone and call out user-visible impact.

```bash
git clone https://github.com/h3pdesign/Neon-Vision-Editor.git
cd Neon-Vision-Editor
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" -destination 'platform=macOS,name=My Mac' build
```

Lock-safe cross-platform verification (sequential macOS + iOS Simulator + iPad Simulator):

```bash
scripts/ci/build_platform_matrix.sh
```

## Support & Feedback

### Feedback Pulse

Share what works well and what should improve for both the app and the README.

<p align="center">
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20%22%5BPositive%20Feedback%5D%22%20in%3Atitle">
    <img alt="Open Positive Feedback" src="https://img.shields.io/github/issues-search/h3pdesign/Neon-Vision-Editor?query=is%3Aissue%20is%3Aopen%20%22%5BPositive%20Feedback%5D%22%20in%3Atitle&label=Open%20Positive&color=22C55E">
  </a>
  &nbsp;
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20%22%5BNegative%20Feedback%5D%22%20in%3Atitle">
    <img alt="Open Negative Feedback" src="https://img.shields.io/github/issues-search/h3pdesign/Neon-Vision-Editor?query=is%3Aissue%20is%3Aopen%20%22%5BNegative%20Feedback%5D%22%20in%3Atitle&label=Open%20Negative&color=EF4444">
  </a>
</p>
<p align="center">
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/issues/new?template=feature_request.yml&title=%5BPositive%20Feedback%5D%20App%2FREADME%3A%20">Share positive feedback</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/issues/new?template=bug_report.yml&title=%5BNegative%20Feedback%5D%20App%2FREADME%3A%20">Share negative feedback</a>
</p>

- Questions and ideas: [GitHub Discussions](https://github.com/h3pdesign/Neon-Vision-Editor/discussions)
- Project board (Now / Next / Later): [Neon Vision Editor Roadmap](https://github.com/users/h3pdesign/projects/2)
- Known issues: [Known Issues Hub #50](https://github.com/h3pdesign/Neon-Vision-Editor/issues/50)
- Contributor entry points: [good first issue](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3A%22good%20first%20issue%22) | [help wanted](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3A%22help%20wanted%22)
- Issue filters: [enhancement](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aenhancement) | [known-issue](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aknown-issue) | [regression](https://github.com/h3pdesign/Neon-Vision-Editor/issues?q=is%3Aissue%20is%3Aopen%20label%3Aregression)

### Support Neon Vision Editor

Keep it free, sustainable, and improving.

<p align="center">
  <a href="https://buymeacoffee.com/h3pdesign">
    <img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Buy%20Me%20a-Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=111827">
  </a>
  <a href="https://www.patreon.com/h3p">
    <img alt="Support on Patreon" src="https://img.shields.io/badge/Support%20on-Patreon-F96854?style=for-the-badge&logo=patreon&logoColor=white">
  </a>
  <a href="https://www.paypal.com/paypalme/HilthartPedersen">
    <img alt="Support via PayPal" src="https://img.shields.io/badge/Support%20via-PayPal-0070BA?style=for-the-badge&logo=paypal&logoColor=white">
  </a>
</p>

- Neon Vision Editor will always stay free to use.
- No subscriptions and no paywalls.
- Keeping the app alive still has real costs: Apple Developer Program fee, maintenance, updates, and long-term support.
- Optional Support Tip (Consumable): **$4.99** and can be purchased multiple times.
- Your support helps cover Apple developer fees, bug fixes and updates, future improvements and features, and long-term support.
- Thank you for helping keep Neon Vision Editor free for everyone.

- In-app support tip: `Settings > Mehr/More` (platform-dependent)
- External support: [Buy Me a Coffee](https://buymeacoffee.com/h3pdesign)
- External support: [Patreon](https://www.patreon.com/h3p)
- h3p apps portal for docs, setup guides, and release workflows: [>h3p apps](https://apps-h3p.com)
- External support: [PayPal](https://www.paypal.com/paypalme/HilthartPedersen)

### Creator Sites

<p align="center">
  <a href="https://h3p.me/home">
    <img alt="h3p.me Photography" src="https://img.shields.io/badge/h3p.me-Photography%20Portfolio-111827?style=for-the-badge">
  </a>
  <a href="https://apps-h3p.com">
    <img alt="apps-h3p.com Product Hub" src="https://img.shields.io/badge/apps--h3p.com-Apps%20%26%20Docs%20Hub-0A84FF?style=for-the-badge">
  </a>
</p>

- Discussions categories: [Ideas](https://github.com/h3pdesign/Neon-Vision-Editor/discussions/categories/ideas) | [Q&A](https://github.com/h3pdesign/Neon-Vision-Editor/discussions/categories/q-a) | [Showcase](https://github.com/h3pdesign/Neon-Vision-Editor/discussions/categories/show-and-tell)

## Git hooks

To auto-increment Xcode `CURRENT_PROJECT_VERSION` on every commit:

```bash
scripts/install_git_hooks.sh
```

## Changed License

Neon Vision Editor is licensed under the Apache License, Version 2.0.
See [`LICENSE`](LICENSE).

The project moved to Apache-2.0 because it keeps the same permissive open-source
model while adding an explicit patent grant and patent-termination protection for
contributors and downstream users. This better matches a developer tool that may
receive contributions, integrations, and commercial redistribution over time.
