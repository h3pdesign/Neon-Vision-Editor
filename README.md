<p align="center"><a href="https://apps-h3p.com"><img alt="Docs on h3p apps" src="https://img.shields.io/badge/Docs-h3p%20apps-111827?style=for-the-badge"></a><a href="https://www.patreon.com/h3p"><img alt="Support on Patreon" src="https://img.shields.io/badge/Support%20on-Patreon-F96854?style=for-the-badge&logo=patreon&logoColor=white"></a><a href="https://www.paypal.com/paypalme/HilthartPedersen"><img alt="Support via PayPal" src="https://img.shields.io/badge/Support%20via-PayPal-0070BA?style=for-the-badge&logo=paypal&logoColor=white"></a></p>

<p align="center">
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases"><img alt="Latest Release" src="https://img.shields.io/github/v/tag/h3pdesign/Neon-Vision-Editor?label=release"></a>
  <a href="https://apps.apple.com/de/app/neon-vision-editor/id6758950965"><img alt="Platforms" src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20iPadOS-0A84FF"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/actions/workflows/release-notarized.yml"><img alt="Notarized Release" src="https://img.shields.io/github/actions/workflow/status/h3pdesign/Neon-Vision-Editor/release-notarized.yml?branch=main&label=Notarized%20Release"></a>
  <a href="https://github.com/h3pdesign/homebrew-tap/actions/workflows/update-cask.yml"><img alt="Homebrew Cask Sync" src="https://img.shields.io/github/actions/workflow/status/h3pdesign/homebrew-tap/update-cask.yml?label=Homebrew%20Cask%20Sync"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/SECURITY.md"><img alt="Security Policy" src="https://img.shields.io/badge/security-policy-22C55E"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/commits/main"><img alt="SSH Signed Commits" src="https://img.shields.io/badge/commits-SSH%20signed-2563EB"></a>
  <a href="https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
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

> Status: **active release**  
> Latest release: **v0.6.3**
> Platform target: **macOS 26 (Tahoe)** compatible with **macOS Sequoia**
> Apple Silicon: tested / Intel: not tested
> Last updated (README): **2026-04-29** for latest release **v0.6.3**

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
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><img alt="Stable" src="https://img.shields.io/badge/Stable-22C55E?style=flat-square"></td>
        <td>Direct notarized builds and fastest stable updates</td>
        <td><a href="https://github.com/h3pdesign/Neon-Vision-Editor/releases">GitHub Releases</a></td>
      </tr>
      <tr>
        <td><img alt="Store" src="https://img.shields.io/badge/Store-0A84FF?style=flat-square"></td>
        <td>Apple-managed install/update flow</td>
        <td><a href="https://apps.apple.com/de/app/neon-vision-editor/id6758950965">App Store</a></td>
      </tr>
      <tr>
        <td><img alt="Beta" src="https://img.shields.io/badge/Beta-F59E0B?style=flat-square"></td>
        <td>Early testing of upcoming changes</td>
        <td><a href="https://testflight.apple.com/join/YWB2fGAP">TestFlight</a></td>
      </tr>
    </tbody>
  </table>
</div>

## Download Metrics

<p align="center">
  <img alt="All Downloads" src="https://img.shields.io/github/downloads/h3pdesign/Neon-Vision-Editor/total?style=for-the-badge&label=All%20Downloads&color=0A84FF">
  <img alt="v0.6.3 Downloads" src="https://img.shields.io/github/downloads/h3pdesign/Neon-Vision-Editor/v0.6.3/total?style=for-the-badge&label=v0.6.3&color=22C55E">
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
  <img alt="Unique cloners (14d)" src="https://img.shields.io/static/v1?label=Unique+cloners+%2814d%29&message=650&color=7C3AED&style=for-the-badge">
  <img alt="Unique visitors (14d)" src="https://img.shields.io/static/v1?label=Unique+visitors+%2814d%29&message=242&color=0EA5E9&style=for-the-badge">
</p>
<p align="center">
  <img alt="Clone snapshot (UTC)" src="https://img.shields.io/static/v1?label=Clone+snapshot+%28UTC%29&message=2026-04-29&color=334155&style=flat-square">
  <img alt="View snapshot (UTC)" src="https://img.shields.io/static/v1?label=View+snapshot+%28UTC%29&message=2026-04-29&color=334155&style=flat-square">
</p>

## Project Documentation

| Document | Purpose |
|---|---|
| [`CHANGELOG.md`](CHANGELOG.md) | Full release history and milestone issue coverage |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Local setup, build, and contribution workflow |
| [`PRIVACY.md`](PRIVACY.md) | Privacy guarantees and data-handling policy |
| [`SECURITY.md`](SECURITY.md) | Security policy and responsible disclosure |
| [`release/`](release/) | TestFlight, App Store, and release preflight checklists |
| [`release/v0.6.4-release-qa.md`](release/v0.6.4-release-qa.md) | v0.6.4 quality-release QA for PDF export, mobile parity, docs, and metrics |
| [`release/v0.6.4-mobile-parity-matrix.md`](release/v0.6.4-mobile-parity-matrix.md) | iPhone/iPad toolbar, sidebar, compact layout, and accessibility parity matrix |

## What's New Since v0.6.2

- **Native Diff Workflows:** Compare the current tab against disk or compare two open tabs in the new side-by-side diff view.
- **Toolbar Help:** A new responsive help section explains every toolbar symbol and adapts across iPhone, iPad, and Mac.
- **iPhone/iPad Toolbar Access:** More actions are available in compact scrollable toolbars, with Toolbar Help pinned next to Settings on iPad.
- **Markdown PDF Export:** Paginated exports now include complete text content, and one-page exports use tighter margins with flexible page length.
- **iPhone Project Sidebar Fixes:** Open File, Open Folder, and New File actions now present the expected dialogs and create tabs correctly.
- **Markdown and File Handling:** Improved Markdown detection/highlighting, `.bak` plain-text support, and dotfile handling such as `.zshrc`.
- **Themes and Support Messaging:** Added the AMOLED Neon theme and refined App Store support-price loading states.

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

| Channel | Best For | Download | Release Track | Notes |
|---|---|---|---|---|
| **Stable** | Direct notarized builds and fastest stable updates | [GitHub Releases](https://github.com/h3pdesign/Neon-Vision-Editor/releases) | **v0.6.3** | Apple Silicon tested, Intel not fully validated |
| **Store** | Apple-managed installs and updates | [Neon Vision Editor on the App Store](https://apps.apple.com/de/app/neon-vision-editor/id6758950965) | App Store | Automatic Store delivery/update flow |
| **Beta** | Testing upcoming changes before stable | [TestFlight Invite](https://testflight.apple.com/join/YWB2fGAP) | TestFlight | Early access builds for feedback |

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

## Core Workflows

<p align="center">
  <img alt="Project Sidebar" src="https://img.shields.io/badge/Project%20Sidebar-Create%20%2F%20Rename%20%2F%20Delete-0891B2?style=for-the-badge">
  <img alt="Markdown Preview" src="https://img.shields.io/badge/Markdown%20Preview-Toolbar%20Style%20%2B%20Export-DB2777?style=for-the-badge">
  <img alt="Quick Open" src="https://img.shields.io/badge/Quick%20Open-Fast%20File%20Jump-7C3AED?style=for-the-badge">
</p>
<p align="center"><sub>Project Sidebar keeps file-tree actions close. Markdown Preview keeps style and export in one toolbar flow. Quick Open keeps file navigation immediate.</sub></p>

## Features

Neon Vision Editor keeps the surface minimal and focuses on fast writing/coding workflows.
Platform-specific availability is tracked in the [Platform Matrix](#platform-matrix) section below.

<p align="center">
  <strong>Editing Core</strong>
</p>
<p align="center">
  <img alt="Fast Editing" src="https://img.shields.io/badge/Fast%20Editing-Tabbed%20%2B%20Large%20Files-22C55E?style=for-the-badge">
  <img alt="Tabs" src="https://img.shields.io/badge/Tabs-Double--Click%20Close-4F46E5?style=for-the-badge">
  <img alt="Syntax Highlighting" src="https://img.shields.io/badge/Syntax-Multi--Language-0A84FF?style=for-the-badge">
  <img alt="TeX Support" src="https://img.shields.io/badge/TeX%2FLaTeX-Syntax%20Highlighting-14B8A6?style=for-the-badge">
  <img alt="Regex Find Replace" src="https://img.shields.io/badge/Find%20%26%20Replace-Regex%20Ready-F59E0B?style=for-the-badge">
  <img alt="Vim Mode" src="https://img.shields.io/badge/Vim%20Mode-Hardware%20Keyboard-059669?style=for-the-badge">
</p>
<p align="center">
  <strong>Navigation & Preview</strong>
</p>
<p align="center">
  <img alt="Quick Open" src="https://img.shields.io/badge/Quick%20Open-Cmd%2BP-7C3AED?style=for-the-badge">
  <img alt="Project Sidebar" src="https://img.shields.io/badge/Project%20Sidebar-Recursive%20Navigation-0891B2?style=for-the-badge">
  <img alt="Indexed Search" src="https://img.shields.io/badge/Find%20in%20Files-Background%20Index-2563EB?style=for-the-badge">
  <img alt="Diff View" src="https://img.shields.io/badge/Diff%20View-Tab%20%2B%20Disk%20Compare-16A34A?style=for-the-badge">
  <img alt="Markdown Preview" src="https://img.shields.io/badge/Markdown-Preview%20Templates-DB2777?style=for-the-badge">
  <img alt="Markdown PDF Export" src="https://img.shields.io/badge/Markdown%20PDF-Paginated%20%2B%20One--Page-7C3AED?style=for-the-badge">
</p>
<p align="center">
  <strong>Platform, Output & Customization</strong>
</p>
<p align="center">
  <img alt="Cross Platform" src="https://img.shields.io/badge/Cross--Platform-macOS%20%7C%20iOS%20%7C%20iPadOS-2563EB?style=for-the-badge">
  <img alt="Code Snapshot" src="https://img.shields.io/badge/Code%20Snapshot-Share%20Images-F97316?style=for-the-badge">
  <img alt="Themes" src="https://img.shields.io/badge/Themes-Prism%20Daylight-DB2777?style=for-the-badge">
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
- Broad syntax highlighting (including TeX/LaTeX), inline completion with Tab-to-accept, and regex Find/Replace with Replace All.
- Optional Vim workflow support and starter templates for common languages.

### Navigation & Workflow

- Quick Open (`Cmd+P`), project sidebar navigation, and recursive project tree rendering.
- Project quick actions (`Expand All` / `Collapse All`) and supported-files-only filter.
- Native side-by-side diff view for Compare with Disk and Compare Open Tabs workflows, with change navigation.
- Cross-platform `Save As…` and Close All Tabs with confirmation.

### Preview, Platform, and Safety

- Native Markdown preview templates on macOS/iOS/iPadOS plus iPhone bottom-sheet preview.
- `.svg` file support via XML mode and bracket helper on all platforms.
- Unsupported-file open/import safety guards and session restore for previously opened project folder.

### Customization & Diagnostics

- Built-in theme collection: Dracula, One Dark Pro, Nord, Tokyo Night, Gruvbox, and Neon Glow.
- Grouped settings, optional StoreKit support flow, and AI Activity Log diagnostics on macOS.

## Release Spotlight

<p align="center">
  <img alt="Release Spotlight" src="https://img.shields.io/badge/RELEASE%20SPOTLIGHT-Code%20Snapshot-F97316?style=for-the-badge">
</p>

- Create polished share images directly from selected code.
- Toolbar button: click <img src="docs/images/code-snapshot-toolbar-icon.svg" alt="Code Snapshot toolbar icon" width="16" valign="middle"> in the top toolbar (`Create Code Snapshot`).
- Selection menu: right-click selected text and choose `Create Code Snapshot`.
- Composer controls: choose appearance, background, frame style, line numbers, and padding.
- Export: use `Share` to generate a PNG snapshot and share/save it.

<p align="center">
  <a href="docs/images/code-snapshot-showcase.svg">
    <img src="docs/images/code-snapshot-showcase.svg" alt="Code Snapshot preview showing styled code card on gradient background" width="920">
  </a><br>
  <sub>Styled export preview for social sharing, changelogs, and issue discussions.</sub>
</p>

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
  VM --> SAFE
  VM --> PREFS
  VM --> UPD
  PREFS --> STORE
  IO --> STORE
  VM --> SEC

  classDef platform stroke:#2563EB,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;
  classDef app stroke:#059669,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;
  classDef core stroke:#EA580C,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;
  classDef infra stroke:#9333EA,stroke-width:3px,fill:transparent,font-family:ui-monospace\, SFMono-Regular\, Menlo\, Monaco\, Consolas\, Liberation Mono\, monospace,font-size:13px;

  class Mac,IOS platform;
  class ACT,VM,CMD app;
  class IO,HL,FIND,PREV,SAFE core;
  class STORE,PREFS,SEC,UPD infra;

  linkStyle 0,1 stroke:#2563EB,stroke-width:2px;
  linkStyle 2,3 stroke:#059669,stroke-width:2px;
  linkStyle 5,6,7,8,9,13 stroke:#EA580C,stroke-width:2px;
  linkStyle 4,10,11,12,14 stroke:#9333EA,stroke-width:2px;
```

- `EditorViewModel` is the single UI-facing orchestration point per window/scene.
- Commands mutate editor state predictably; session/tabs persist through store services.
- File access and parsing stay off the main thread; UI state changes stay on the main thread.
- Platform shells stay thin and route interactions into shared app/core services.
- Security-sensitive credentials remain in Keychain (`SecureTokenStore`), not plain prefs.
- Color key in diagram: blue = platform shell, green = app orchestration, orange = core services, purple = infrastructure.

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
- Project sidebar with supported-files filter.
- Unsupported-file safety alerts.
- SVG (`.svg`) support via XML mode.
- Close All Tabs with confirmation.
- Bracket helper and grouped Settings cards.

### Platform-Specific Differences

| Capability | macOS | iOS | iPadOS | Notes |
|---|---|---|---|---|
| Quick Open<br><sub>`Cmd+P`</sub> | ![Full](https://img.shields.io/badge/Full-22C55E?style=flat-square) | ![Limit](https://img.shields.io/badge/Limit-F59E0B?style=flat-square) | ![Full](https://img.shields.io/badge/Full-22C55E?style=flat-square) | iOS needs a hardware keyboard<br>for shortcut-driven flow. |
| Bracket Helper | ![Toolbar](https://img.shields.io/badge/Toolbar-0A84FF?style=flat-square) | ![Kbd Bar](https://img.shields.io/badge/Kbd_Bar-7C3AED?style=flat-square) | ![Kbd Bar](https://img.shields.io/badge/Kbd_Bar-7C3AED?style=flat-square) | Same behavior across platforms;<br>only the UI surface differs. |
| Markdown Preview | ![Inline](https://img.shields.io/badge/Inline-0891B2?style=flat-square) | ![Sheet](https://img.shields.io/badge/Sheet-DB2777?style=flat-square) | ![Inline](https://img.shields.io/badge/Inline-0891B2?style=flat-square) | Interaction adapts to screen size<br>and platform input model. |

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
      <a href="docs/images/NeonVisionEditorApp.png">
        <img src="docs/images/NeonVisionEditorApp.png" alt="Neon Vision Editor macOS app screenshot" width="520">
      </a><br>
      <sub>General editing workflow on macOS</sub>
    </td>
    <td align="center">
      <a href="docs/images/macos-editor-light-frame.png">
        <img src="docs/images/macos-editor-light-frame.png" alt="Neon Vision Editor macOS editor screenshot in framed light appearance" width="520">
      </a><br>
      <sub>Wide editing workspace with tabs and status bar context</sub>
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

## Release Flow (Completed + Upcoming)

<p align="center">
  <a href="docs/images/neon-vision-release-history-0.1-to-0.5-light.svg">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/neon-vision-release-history-0.1-to-0.5.svg">
      <source media="(prefers-color-scheme: light)" srcset="docs/images/neon-vision-release-history-0.1-to-0.5-light.svg">
      <img src="docs/images/neon-vision-release-history-0.1-to-0.5-light.svg" alt="Neon Vision Editor release flow timeline with upcoming milestones" width="100%">
    </picture>
  </a>
</p>
<p align="center"><sub>Click to open full-size SVG and zoom. In full view, each card links to release notes or the roadmap hub.</sub></p>

## Roadmap (Near Term)

<p align="center">
  <img alt="Now" src="https://img.shields.io/badge/NOW-v0.6.3-22C55E?style=for-the-badge">
  <img alt="Next" src="https://img.shields.io/badge/NEXT-v0.6.4-F59E0B?style=for-the-badge">
  <img alt="Later" src="https://img.shields.io/badge/LATER-v0.6.5%20to%20v0.7.0-0A84FF?style=for-the-badge">
</p>

### Now (v0.6.3)

- ![v0.6.3](https://img.shields.io/badge/v0.6.3-22C55E?style=flat-square) completed native diff workflows, responsive Toolbar Help, Markdown PDF export fixes, compact iPhone/iPad toolbar parity, and App Store/TestFlight release copy.
  Tracking: [Release v0.6.3](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.6.3)

### Next (v0.6.4)

- ![v0.6.4](https://img.shields.io/badge/v0.6.4-F59E0B?style=flat-square) quality release focused on long Markdown PDF export coverage, mobile toolbar/sidebar parity, compact layout accessibility, README roadmap correctness, and release QA hardening.
  Tracking: [#89](https://github.com/h3pdesign/Neon-Vision-Editor/issues/89), [#90](https://github.com/h3pdesign/Neon-Vision-Editor/issues/90), [#91](https://github.com/h3pdesign/Neon-Vision-Editor/issues/91), [#92](https://github.com/h3pdesign/Neon-Vision-Editor/issues/92), [#93](https://github.com/h3pdesign/Neon-Vision-Editor/issues/93)

### Later (v0.6.5 - v0.7.0)

- ![v0.6.5+](https://img.shields.io/badge/v0.6.5%2B-0A84FF?style=flat-square) larger workflow expansion after the 0.6.4 quality baseline is verified.

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
  Intel is currently not fully validated. If you can help test, see [Help wanted: Intel Mac test coverage](https://github.com/h3pdesign/Neon-Vision-Editor/issues/41).
- **Can I use it offline?**  
  Yes for core editing; network is only needed for optional external services (for example selected AI providers).
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
        <tr><td><code>Cmd+W</code></td><td>Close Tab</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
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
        <tr><td><code>Cmd+Shift+F</code></td><td>Find in Files</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
      </table>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <p><img alt="Editor" src="https://img.shields.io/badge/Editor-DB2777?style=flat-square"></p>
      <table width="100%">
        <tr><th align="left" width="32%">Shortcut</th><th align="left" width="43%">Action</th><th align="left" width="25%">Platforms</th></tr>
        <tr><td><code>Cmd+P</code></td><td>Quick Open</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
        <tr><td><code>Cmd+D</code></td><td>Add next<br>match</td><td><img alt="macOS" src="https://img.shields.io/badge/macOS-0A84FF?style=flat-square"></td></tr>
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

Latest stable: **v0.6.3** (2026-04-28)

### Recent Releases (At a glance)

| Version | Date | Highlights | Fixes | Breaking changes | Migration |
|---|---|---|---|---|---|
| [`v0.6.3`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.6.3) | 2026-04-28 | a native side-by-side diff view with change navigation, accessible hunk summaries, Compare with Disk, and Compare Open Tabs entry points; a full Toolbar Help section that explains toolbar symbols, groups actions by workflow, adapts to iPhone/iPad/macOS widths, and is reachable from the toolbar, macOS Help menu, and menu-bar extra; Expanded iPhone/iPad toolbar coverage so commonly used and previously overflow-only actions are visible in the scrollable toolbar, with Toolbar Help pinned next to Settings on iPad; Updated the Welcome Tour with the latest major features and a live support-purchase card that avoids premature App Store price-unavailable states | iOS Save File behavior so saving an existing file no longer behaves like Save As; iPhone project-sidebar toolbar buttons so Open File/Open Folder actions present the expected picker dialogs; iPhone project-sidebar new-file creation so the filename dialog no longer disappears immediately and the new tab is created | None noted | None required |
| [`v0.6.2`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.6.2) | 2026-04-24 | selective project-wide replace from `Find in Files` with match selection controls (`Select All`, `Select None`), apply, and cancel; `Go to Line` and `Go to Symbol` entry points for faster in-document navigation; Code Snapshot composer layout on macOS so settings controls track the snapshot composition width more tightly; support for opening `.cif` and `.mcif` files as plain-text documents | macOS sidebar disclosure spacing so project disclosure controls are no longer pinned too close to the left edge; project sidebar row alignment so folder/file content columns line up consistently; project sidebar nested-file spacing for improved readability in expanded folders | None noted | None required |
| [`v0.6.1`](https://github.com/h3pdesign/Neon-Vision-Editor/releases/tag/v0.6.1) | 2026-04-16 | project sidebar item actions for creating files/folders, plus rename, duplicate, and delete flows; Refined project sidebar visual hierarchy and interaction density for clearer navigation in large trees; a dedicated Markdown Preview style toolbar button and consolidated export options into toolbar menus that appear only when preview is active; Expanded localization coverage for new Markdown Preview toolbar strings (including Simplified Chinese additions) | missing localization coverage for newly introduced Markdown Preview toolbar labels/help text; Markdown Preview toolbar/menu availability so controls appear only in Markdown Preview mode | None noted | None required |

- Full release history: [`CHANGELOG.md`](CHANGELOG.md)
- Latest release: **v0.6.3**
- Compare recent changes: [v0.6.2...v0.6.3](https://github.com/h3pdesign/Neon-Vision-Editor/compare/v0.6.2...v0.6.3)

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
- Security policy and reporting details: [`SECURITY.md`](SECURITY.md).
- New repository commits are SSH-signed; older historical commits may still predate commit signing.
- Local SSH-signature verification in this clone can use the repo-scoped `.git_allowed_signers` file.

## Release Integrity

- Tag: `v0.6.3`
- Tagged commit: `161e7fc`
- Verify local tag target:

```bash
git rev-parse --verify v0.6.3
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

- macOS 26 (Tahoe)
- Apple Silicon recommended

### Build Requirements

- Xcode with the macOS 26 toolchain
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

## License

Neon Vision Editor is licensed under the MIT License.
See [`LICENSE`](LICENSE).
