<h1 align="center">Neon Vision Editor</h1>

<p align="center">
  <img src="NeonVision%20Editor.png" alt="Neon Vision Editor Logo" width="200"/>
</p>



<p align="center">
  A lightweight, modern macOS text editor focused on speed, readability, and fast syntax highlighting.
</p>

---
Neon Vision Editor is a lightweight, modern macOS text editor focused on **speed, readability, and fast syntax highlighting**.  
It is intentionally minimal: quick edits, fast file access, no IDE bloat.

> Status: **alpha / beta**  
> Platform target: **macOS 26 (Tahoe)**


## Download

Prebuilt binaries are available via **GitHub Releases**:
https://github.com/h3pdesign/Neon-Vision-Editor/releases

- Latest release: **v0.2.3-alpha** (23 Jan 2026)
- Architecture: Apple Silicon (Intel not tested)
- Notarization: *not yet*

If you don’t want to build from source, this is the recommended path.

---

## Why this exists

Modern IDEs are powerful but heavy.  
Classic macOS editors are fast but stagnant.

Neon Vision Editor sits in between:
- Open files instantly
- Read code comfortably
- Edit without friction
- Close the app without guilt

No background indexing. No telemetry. No plugin sprawl.

---

## Features

- Fast loading, including large text files
- Syntax highlighting for common languages  
  (Python, C/C++, JavaScript, HTML, CSS, and others)
- Clean, minimal UI optimized for readability
- Native macOS 26 (Tahoe) look & behavior
- Built with Swift and AppKit


---

## Non-goals (by design)

- ❌ No plugin system (for now)
- ❌ No project/workspace management
- ❌ No code intelligence (LSP, autocomplete, refactors)
- ❌ No Electron, no cross-platform abstraction layer

This is **not** an IDE. That is intentional.

---

## Requirements

- macOS 26 (Tahoe)
- Xcode compatible with macOS 26 toolchain
- Apple Silicon recommended

---

## Build from source

```bash
git clone https://github.com/h3pdesign/Neon-Vision-Editor.git
cd Neon-Vision-Editor
open "Neon Vision Editor.xcodeproj"
