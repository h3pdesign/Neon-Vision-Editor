# Open Folder Command Feature

## Overview

Added a **File → Open Folder...** menu command to Neon Vision Editor, following macOS conventions for opening and browsing folder contents.

## Changes Made

### 1. AppMenus.swift - Added Menu Command

Added "Open Folder..." button to the File menu in the `fileCommands` section:

```swift
Button("Open Folder...") {
    postWindowCommand(.openProjectFolderRequested)
}
.keyboardShortcut("o", modifiers: [.command, .shift])
```

**Keyboard Shortcut**: `⌘⇧O` (Command+Shift+O)

This follows the standard macOS convention where:
- `⌘O` opens individual files
- `⌘⇧O` opens folders/directories

### 2. PanelsAndHelpers.swift - Added Notification

Added new notification name to the `Notification.Name` extension:

```swift
static let openProjectFolderRequested = Notification.Name("openProjectFolderRequested")
```

This follows the existing notification pattern used throughout the app for menu commands.

### 3. ContentView.swift - Added Notification Handler

Added receiver for the folder open notification:

```swift
.onReceive(NotificationCenter.default.publisher(for: .openProjectFolderRequested)) { notif in
    guard matchesCurrentWindow(notif) else { return }
    openProjectFolder()
}
```

This connects the menu command to the existing `openProjectFolder()` function in `ContentView+Actions.swift`.

## Existing Functionality Leveraged

The implementation leverages the existing `openProjectFolder()` function which:

1. **On macOS**:
   - Presents an `NSOpenPanel` configured for directory selection
   - Sets `canChooseDirectories = true` and `canChooseFiles = false`
   - Calls `setProjectFolder()` with the selected URL
   - Automatically shows hidden folders based on panel settings

2. **On iOS**:
   - Sets `showProjectFolderPicker = true` to trigger the document picker
   - Handles security-scoped resource access for sandboxed apps

3. **Project Tree Building**:
   - Builds a hierarchical tree of files and subdirectories
   - Populates the Project Structure Sidebar
   - Enables quick file navigation within the project

## User Experience

### Menu Location
```
File
├── New Window        (⌘N)
├── New Tab           (⌘T)
├── ─────────────────
├── Open File...      (⌘O)          ← Individual file
├── Open Folder...    (⌘⇧O)         ← New! Folder/directory
├── Open Recent       ▶
│   ├── file1.swift
│   ├── file2.md
│   └── Clear Menu
├── ─────────────────
├── Save              (⌘S)
├── Save As...
├── Rename
├── ─────────────────
└── Close Tab         (⌘W)
```

### Workflow

1. User selects **File → Open Folder...** or presses `⌘⇧O`
2. System presents folder picker dialog
3. User selects a folder
4. App loads the folder structure into the Project Structure Sidebar
5. User can now browse and open files from the sidebar

## Design Rationale

### Naming Convention

The command is named **"Open Folder..."** which is:
- ✅ Standard macOS terminology (matching Finder, Xcode, VS Code, etc.)
- ✅ Clear and descriptive
- ✅ Consistent with "Open File..."
- ✅ Uses ellipsis (...) to indicate a dialog will appear

Alternative names considered but rejected:
- ❌ "Open Directory..." - Too technical/Unix-oriented
- ❌ "Browse Folder..." - Implies read-only access
- ❌ "Add Folder..." - Suggests adding to a list rather than opening
- ❌ "Open Project..." - Too IDE-specific, not all folders are "projects"

### Keyboard Shortcut

`⌘⇧O` (Command+Shift+O) is:
- ✅ Standard in most text editors and IDEs (VS Code, Sublime Text, Atom)
- ✅ Memorable: "Shift" modifies "Open" from file to folder
- ✅ Easy to type with one hand
- ✅ Doesn't conflict with existing shortcuts

### Notification Pattern

Uses the notification-based command pattern because:
- ✅ Consistent with other menu commands in the app
- ✅ Supports multi-window apps (window-specific handling)
- ✅ Decouples menu logic from view logic
- ✅ Allows commands to be triggered from multiple sources (menu, toolbar, keyboard)

## Integration with Composition Pattern

This feature integrates seamlessly with the Composition Pattern documented in `COMPOSITION_PATTERN.md`:

1. **Menu command** lives in `AppMenuCommands` struct in `AppMenus.swift`
2. **Action handler** lives in `ContentView+Actions.swift` extension
3. **Notification bridge** connects the two through the standard notification system
4. **No tight coupling** between menu and view layers

## Testing

To test this feature:

1. **Basic Open**:
   - Press `⌘⇧O` or select File → Open Folder...
   - Choose any folder
   - Verify Project Structure Sidebar populates with folder contents

2. **Multi-Window**:
   - Open multiple windows (File → New Window)
   - Press `⌘⇧O` in one window
   - Verify only that window's sidebar updates

3. **Keyboard Shortcut**:
   - Verify `⌘⇧O` triggers the folder picker
   - Verify `⌘O` still opens individual files

4. **Menu Access**:
   - Verify "Open Folder..." appears in File menu
   - Verify it shows `⇧⌘O` as the shortcut hint

## Future Enhancements

Potential improvements for future versions:

1. **Recent Folders**: Add a submenu showing recently opened folders
2. **Folder Bookmarks**: Allow users to bookmark frequently accessed folders
3. **Workspace Files**: Support saving/loading folder configurations
4. **Multi-Folder Projects**: Allow opening multiple root folders simultaneously
5. **Folder Context Menu**: Right-click folder in sidebar to reveal in Finder

## Related Files

- `AppMenus.swift` - Menu command definition
- `ContentView.swift` - Notification receiver
- `ContentView+Actions.swift` - `openProjectFolder()` implementation
- `PanelsAndHelpers.swift` - Notification name definition
- `COMPOSITION_PATTERN.md` - Architecture documentation

## Compatibility

- **macOS**: Full functionality with `NSOpenPanel`
- **iOS/iPadOS**: Uses `UIDocumentPickerViewController` (existing implementation)
- **Sandboxed Apps**: Properly handles security-scoped resources

## Conclusion

The "Open Folder..." feature provides a standard, discoverable way for users to open and browse folder contents, following established macOS conventions and integrating cleanly with the app's composition-based architecture.
