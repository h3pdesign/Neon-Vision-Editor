# Editor Window Management (macOS)

## The Problem

Neon Vision Editor has several kinds of windows: editor windows (the main `ContentView`), the Console Log window, and the Settings window. macOS APIs like `NSApp.windows` treat them all equally, but the app needs to distinguish editor windows from auxiliary windows for two reasons:

1. **Deciding whether to create a default editor window at launch.** macOS calls `applicationShouldOpenUntitledFile(_:)` early in the launch sequence. If the app says "no", macOS won't create the default window. The Console Log or Settings window being present should not count --- only a real editor window should suppress the default window creation.

2. **Routing file-open commands to the right place.** When the user opens a file (File > Open, Open Recent, double-click in Finder, or drag-and-drop), the app needs to find an `EditorViewModel` that is actually attached to a visible window. If it can't, the file silently loads into a headless view model that nobody can see.

Both of these problems are solved by the **Registered Editor Window** concept.

## What Is a Registered Editor Window?

A "registered editor window" is a macOS `NSWindow` that:

- Hosts a `ContentView` (the main editor UI with tabs, sidebar, text editor, etc.)
- Has an associated `EditorViewModel` instance
- Has been recorded in the `WindowViewModelRegistry` singleton

Non-editor windows (Console Log, Settings, Welcome Tour, etc.) are **never** registered. They exist in `NSApp.windows` but not in the registry.

## WindowViewModelRegistry

Defined in `PanelsAndHelpers.swift`, this is a `@MainActor` singleton that maps `NSWindow.windowNumber` values to `EditorViewModel` instances via weak references:

```
WindowViewModelRegistry.shared
    storage: [Int: WeakEditorViewModelRef]
```

### Key Methods

| Method | Purpose |
|--------|---------|
| `register(_:for:)` | Associates an `EditorViewModel` with a window number. Called when a `ContentView` appears in a window. |
| `unregister(windowNumber:)` | Removes the mapping. Called when a `ContentView` disappears (window closes). |
| `activeViewModel()` | Returns the `EditorViewModel` for the current key/main window, or `nil` if that window isn't an editor. |
| `anyViewModel()` | Returns any live registered `EditorViewModel`. Used as a fallback when the key window is non-editor (e.g., Console Log is focused). |
| `hasRegisteredEditorWindow()` | Returns `true` if at least one editor window is registered. Prunes stale weak refs first. |
| `viewModel(for:)` | Looks up an `EditorViewModel` by window number. |
| `viewModel(containing:)` | Finds which editor window (if any) already has a given file URL open. |

### Weak References

The registry holds `weak` references to `EditorViewModel` instances. When a window closes and its `ContentView` is deallocated, the view model may also be deallocated, leaving a `nil` weak reference. Methods like `hasRegisteredEditorWindow()` and `viewModel(for:)` automatically prune these stale entries.

## Registration Lifecycle

### When a ContentView Appears

`ContentView` includes an invisible `WindowAccessor` view that monitors when the SwiftUI view is placed into an `NSWindow`. When it detects a window, it calls `updateWindowRegistration(_:)`:

```
ContentView.swift:
    .background(
        WindowAccessor { window in
            updateWindowRegistration(window)
        }
    )
```

`updateWindowRegistration` does:
1. Unregisters the old window number (if the view moved between windows)
2. Saves the new `hostWindowNumber`
3. Calls `WindowViewModelRegistry.shared.register(viewModel, for: number)`

### When a ContentView Disappears

The `.onDisappear` modifier on `ContentView` calls:

```swift
WindowViewModelRegistry.shared.unregister(windowNumber: number)
```

This ensures closed editor windows are promptly removed from the registry.

## How File-Open Routing Works

When the user opens a file, the app uses a **three-tier fallback chain** to find the right `EditorViewModel`:

```
1. activeViewModel()     -- the key/main window's editor, if it IS an editor
2. anyViewModel()        -- any live editor window (fallback when Console Log is key)
3. viewModel             -- the app-level EditorViewModel (headless last resort)
```

This chain is used in two places:

- **`AppDelegate.application(_:open:)`** --- handles files opened via Finder, Open Recent, etc.
- **`activeEditorViewModel`** (computed property) --- used by menu commands (File > Open, Save, etc.)

### Duplicate-Tab Prevention

Before this chain runs, `viewModel(containing:)` checks whether any editor window already has the file open. If so, it focuses that tab and brings that window forward instead of opening a duplicate.

## Launch-Time Window Creation

macOS calls `applicationShouldOpenUntitledFile(_:)` during app launch. The app returns `true` only when:

```swift
!WindowViewModelRegistry.shared.hasRegisteredEditorWindow() && pendingOpenURLs.isEmpty
```

This means:
- If no editor window exists (even if Console Log was restored by macOS state restoration), macOS creates the default editor window.
- If files are queued to open (e.g., double-clicked in Finder), the app skips the blank untitled window --- the file-open flow will create or reuse an editor window instead.

## Window Types Summary

| Window | Registered? | Has EditorViewModel? | Counts for "should open untitled"? |
|--------|-------------|---------------------|-------------------------------------|
| Main editor (`ContentView`) | Yes | Yes | Yes |
| "New Window" (`DetachedWindowContentView`) | Yes (its own `EditorViewModel`) | Yes | Yes |
| Console Log | No | No | No |
| Settings | No | No | No |
| Welcome Tour | No | No | No |

## Adding a New Non-Editor Window

If you add a new auxiliary window (like Console Log):

1. Create the `WindowGroup` in `NeonVisionEditorApp.swift` with a unique `id`.
2. Do **not** embed a `WindowAccessor` or call `WindowViewModelRegistry.shared.register(...)`.
3. The window will exist in `NSApp.windows` but won't interfere with editor window detection or file routing.

## Adding a New Editor Window

If you add a new window type that should behave as an editor:

1. Embed a `ContentView` (or ensure it contains a `WindowAccessor` that calls `updateWindowRegistration`).
2. The `ContentView` will automatically register/unregister its `EditorViewModel` with the registry.
3. The window will be included in `hasRegisteredEditorWindow()` checks and will be a valid target for file-open routing.

## Files

| File | What's There |
|------|-------------|
| `Neon Vision Editor/UI/PanelsAndHelpers.swift` | `WindowViewModelRegistry`, `WeakEditorViewModelRef`, `WindowAccessor` |
| `Neon Vision Editor/UI/ContentView.swift` | `updateWindowRegistration(_:)`, `.onDisappear` unregistration |
| `Neon Vision Editor/App/NeonVisionEditorApp.swift` | `applicationShouldOpenUntitledFile`, `application(_:open:)`, `activeEditorViewModel`, scene definitions |
