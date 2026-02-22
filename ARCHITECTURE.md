# Neon Vision Architecture Guide

## High-Level Overview
Neon Vision is a **native SwiftUI application** targeting macOS 14.0+ (Sonoma/Tahoe). Unlike Electron editors, we rely on Apple's **TextKit 2** and **SwiftUI** for rendering to ensure zero-latency typing.

## Core Modules

### 1. The Editor Engine (`/Core/Editor`)
*   **Backing Store**: We do not load entire files into memory strings. We use a `Rope` data structure (or `mmap` for large files >10MB) to handle inserts/deletes efficiently.
*   **Syntax Highlighting**: Powered by `TreeSitter`.
    *   *Performance Note*: Highlighting runs on a background `DispatchQueue`. The main thread only receives the final `NSAttributedString` for the visible viewport.

### 2. File System & Sandboxing (`/Core/FileSystem`)
*   **Security Scoped Bookmarks**: To support the "Open Recent" menu in a sandboxed environment (required for App Store), we persist security-scoped bookmarks, not just file paths.
*   **Coordinator**: All file writes go through `NSFileCoordinator` to prevent data races with external edits.

### 3. Window Management
*   **Multi-Window**: Neon uses `WindowGroup` with `id` injection to support multiple independent editor instances. State is not shared between windows unless explicitly passed via `AppDependencyContainer`.

## Key Challenges for Contributors
*   **Large Files**: Editing files >100MB is currently experimental. Logic for "chunking" lines lives in `LineManager.swift`.
*   **Vim Mode**: State machine located in `VimInputController.swift`. All key events are intercepted before they reach the standard `NSTextInputClient`.
