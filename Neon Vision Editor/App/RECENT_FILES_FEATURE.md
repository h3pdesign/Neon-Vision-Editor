# Recent Files Feature Implementation

## Overview
Added a complete "Open Recent" menu feature to track recently opened files and provide quick access to them from the File menu.

## Changes Made

### 1. New File: `RecentFilesManager.swift`
Created a dedicated manager class to handle recent files:

**Key Features:**
- Tracks up to 10 most recently opened files
- Persists files using security-scoped bookmarks (required for sandboxed Mac apps)
- Stores data in UserDefaults with the key `"RecentFiles"`
- Automatically handles security-scoped resource access
- Provides methods to:
  - Add recent files
  - Remove specific files
  - Clear all recent files
  - Clean up deleted files
  - Check if files still exist

**Why Security-Scoped Bookmarks?**
Security-scoped bookmarks are essential for sandboxed macOS apps to maintain persistent access to files outside the app's container. Standard file paths won't work after app restart in sandboxed environments.

### 2. Updated: `EditorViewModel.swift`
Modified the `openFile(url:)` method to register files with the recent files manager:

```swift
// Add to recent files
RecentFilesManager.shared.addRecentFile(url)
```

This ensures every successfully opened file is automatically added to the recent files list.

### 3. Updated: `NeonVisionEditorApp.swift`

#### Added StateObject for RecentFilesManager:
```swift
@StateObject private var recentFilesManager = RecentFilesManager.shared
```

#### Added "Open Recent" Menu:
Inserted a new menu in the File menu (after "Open File...") that displays:
- A list of recently opened files with **intelligent display names**
  - Shows just the filename if unique (e.g., "Item.swift")
  - Shows parent folders if needed to disambiguate (e.g., "Folder1/Item.swift" vs "Folder2/Item.swift")
  - Automatically increases path depth (up to 3 levels) if conflicts remain
- Each file is clickable to reopen it
- "No Recent Files" message when the list is empty
- "Clear Menu" option to remove all recent files

#### Added Cleanup on Launch:
Added automatic cleanup of deleted files when the app launches:
```swift
recentFilesManager.cleanupDeletedFiles()
```

## Usage

### For Users:
1. **Open a file** normally using File → Open File... or ⌘O
2. **Access recent files** via File → Open Recent
3. **Click any recent file** to reopen it
4. **Clear the list** using File → Open Recent → Clear Menu

**Smart file naming example:**
If you open these files:
- `/Users/me/XCProj/Folder1/Item.swift`
- `/Users/me/XCProj/Folder2/Item.swift`
- `/Users/me/Documents/Config.json`

The menu will show:
- `Folder1/Item.swift`
- `Folder2/Item.swift`
- `Config.json`

This makes it easy to distinguish between files with the same name!

### For Developers:
The `RecentFilesManager` is implemented as a singleton and can be accessed anywhere:

```swift
// Add a file to recent files
RecentFilesManager.shared.addRecentFile(url)

// Remove a specific file
RecentFilesManager.shared.removeRecentFile(url)

// Clear all recent files
RecentFilesManager.shared.clearRecentFiles()

// Check if a file exists
let exists = RecentFilesManager.shared.fileExists(url)

// Clean up deleted files
RecentFilesManager.shared.cleanupDeletedFiles()

// Get unique display names for files (handles duplicates)
let displayNames = RecentFilesManager.shared.uniqueDisplayNames()
// Returns: [URL: String] dictionary

// Get display name for a specific file with custom depth
let name = RecentFilesManager.shared.displayName(for: url, depth: 2)
// Returns: "Folder1/Folder2/Item.swift"
```

## Technical Details

### Intelligent File Disambiguation
The manager automatically generates unique display names for files:

**Example scenarios:**
- Single file named `Item.swift` → displays as `"Item.swift"`
- Two files with same name in different folders:
  - `~/XCProj/Folder1/Item.swift` → displays as `"Folder1/Item.swift"`
  - `~/XCProj/Folder2/Item.swift` → displays as `"Folder2/Item.swift"`
- Files with same name in nested folders:
  - `~/Projects/App/Models/Item.swift` → displays as `"Models/Item.swift"`
  - `~/Projects/App/Views/Item.swift` → displays as `"Views/Item.swift"`
- If 2 levels aren't enough, automatically expands to 3 levels

The `uniqueDisplayNames()` method:
1. Groups files by filename
2. For unique filenames, shows just the filename
3. For duplicates, shows parent folders (2 levels by default)
4. If still ambiguous, increases to 3 levels
5. Returns a dictionary mapping each URL to its display name

### Data Persistence
- Files are stored as security-scoped bookmark data in UserDefaults
- Key: `"RecentFiles"`
- Maximum entries: 10 (configurable via `maxRecentFiles` property)
- Format: Array of bookmark data (encoded as JSON)

### Security Considerations
- Uses `startAccessingSecurityScopedResource()` and `stopAccessingSecurityScopedResource()` for proper sandboxed file access
- Bookmarks are created with `.withSecurityScope` option
- Stale bookmarks are automatically resolved when loading

### Performance
- Manager is marked `@MainActor` to ensure all operations occur on the main thread
- Files are checked for existence asynchronously during cleanup
- Duplicate entries are automatically prevented
- Display name computation is efficient (O(n) where n = number of recent files)

## Future Enhancements

Possible improvements for future versions:
1. Show full file paths in tooltips
2. Group files by parent directory
3. Add keyboard shortcuts for opening recent files (e.g., ⌘⇧T for most recent)
4. Add file icons based on file type
5. Support for "Recent Projects" or "Recent Folders"
6. Allow configuring the maximum number of recent files
7. Pin favorite files to keep them at the top
