# Open Folder Feature - Auto-Show Sidebar

## Summary

When the user opens a folder via **File → Open Folder...** (or `⌘⇧O`), the Project Structure Sidebar now automatically opens to display the folder contents.

## Implementation

### 1. Menu Command (AppMenus.swift)
```swift
Button("Open Folder...") {
    postWindowCommand(.openProjectFolderRequested)
}
.keyboardShortcut("o", modifiers: [.command, .shift])
```

### 2. Notification Handler (ContentView.swift)
```swift
.onReceive(NotificationCenter.default.publisher(for: .openProjectFolderRequested)) { notif in
    guard matchesCurrentWindow(notif) else { return }
    openProjectFolder()
    // Automatically show the project structure sidebar when opening a folder
    showProjectStructureSidebar = true
}
```

### 3. Folder Setter (ContentView+Actions.swift)
```swift
func setProjectFolder(_ folderURL: URL) {
    // ... setup code ...
    projectRootFolderURL = folderURL
    projectTreeNodes = buildProjectTree(at: folderURL)
    
    // Automatically show the project structure sidebar when a folder is set
    showProjectStructureSidebar = true
}
```

## User Experience

1. User selects **File → Open Folder...** or presses `⌘⇧O`
2. Folder picker appears
3. User selects a folder
4. **Project Structure Sidebar automatically opens** showing folder contents
5. User can immediately browse and click files to open them

## Design Rationale

**Why auto-show the sidebar?**

- ✅ **Immediate feedback** - User sees their folder contents right away
- ✅ **Intent clarity** - Opening a folder implies wanting to browse it
- ✅ **Reduces clicks** - No need to manually toggle the sidebar
- ✅ **Matches expectations** - Similar to IDEs like Xcode, VS Code, etc.
- ✅ **Discoverable** - New users immediately see the feature working

**Alternative considered:**
- ❌ Requiring manual sidebar toggle after opening folder - Too many steps
- ❌ Opening sidebar only on first use - Inconsistent behavior

## Behavior Consistency

The sidebar auto-shows in **all** folder opening scenarios:

1. **Menu Command** - File → Open Folder... (`⌘⇧O`)
2. **Toolbar Button** - "Open Folder" button (if present)
3. **Programmatic** - Any code calling `setProjectFolder()`
4. **iOS Document Picker** - When selecting folders on iOS/iPadOS

This is achieved by placing the `showProjectStructureSidebar = true` logic in the central `setProjectFolder()` function.

## Edge Cases Handled

- **Already open sidebar** - No visual disruption, just ensures it stays open
- **Multi-window** - Only affects the window where the folder was opened
- **Empty folders** - Sidebar still opens (shows empty state)
- **Permission errors** - Sidebar opens but shows empty/error state

## Future Enhancements

Potential improvements:
- Remember user's preference to keep sidebar closed/open
- Add setting: "Auto-show Project Structure when opening folders"
- Animate sidebar opening for smoother UX
- Focus first file in tree after opening

## Testing

To verify the feature:

1. ✅ Press `⌘⇧O` with sidebar closed → Sidebar opens
2. ✅ Press `⌘⇧O` with sidebar open → Sidebar stays open
3. ✅ Use File menu → Same behavior as keyboard shortcut
4. ✅ Use toolbar button → Sidebar opens
5. ✅ Open folder in second window → Only that window's sidebar opens

## Related Files

- `AppMenus.swift` - Menu command definition
- `ContentView.swift` - Notification handler
- `ContentView+Actions.swift` - Folder opening logic
- `PanelsAndHelpers.swift` - Notification name definition
