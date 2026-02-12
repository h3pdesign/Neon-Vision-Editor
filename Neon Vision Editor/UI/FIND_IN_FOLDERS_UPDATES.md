# Find in Folders - UI Enhancement Updates

## Summary

Enhanced the **Find in Folders** feature to include a folder selector UI at the top of the panel, using the same `folder.badge.plus` icon as the Project Structure sidebar. The feature now requires the Project Structure sidebar to be open and ensures bidirectional synchronization between the panel and sidebar.

## Changes Made

### 1. PanelsAndHelpers.swift - FindInFoldersPanel

#### Added Parameters
```swift
@Binding var projectRoot: URL?  // Changed from let to @Binding
@Binding var showProjectStructureSidebar: Bool  // New binding
let onOpenFolder: () -> Void  // New callback
let onSetProjectFolder: (URL) -> Void  // New callback
```

#### New Folder Selector Section
Added a prominent folder selector section at the top of the panel:

```swift
VStack(alignment: .leading, spacing: 6) {
    HStack {
        Image(systemName: "folder")
            .foregroundStyle(.secondary)
        Text("Search Location:")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer()
        Button(action: {
            dismiss()
            onOpenFolder()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "folder.badge.plus")  // Same icon as Project Structure
                Text("Choose Folder")
            }
        }
        .buttonStyle(.bordered)
    }
    
    if let projectRoot {
        // Shows folder path in a styled box
        HStack {
            Text(projectRoot.path)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    } else {
        // Shows warning when no folder selected
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("No folder selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }
}
```

#### Enhanced Validation
Updated search controls to require both folder and sidebar:

```swift
.disabled(projectRoot == nil || !showProjectStructureSidebar)
```

New warning message when sidebar is closed:
```swift
if !showProjectStructureSidebar {
    HStack {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        Text("Project Structure sidebar must be open to search")
            .font(.caption)
            .foregroundStyle(.orange)
    }
    .padding(.vertical, 8)
}
```

### 2. ContentView.swift

#### Updated Sheet Presentation
Changed from passing `projectRoot` as a let to binding it:

```swift
.sheet(isPresented: $showFindInFolders) {
    FindInFoldersPanel(
        searchQuery: $findInFoldersQuery,
        useRegex: $findInFoldersUseRegex,
        caseSensitive: $findInFoldersCaseSensitive,
        projectRoot: $projectRootFolderURL,  // Now a binding
        showProjectStructureSidebar: $showProjectStructureSidebar,  // New binding
        onOpenFile: { url, lineNumber in
            openProjectFileAtLine(url: url, lineNumber: lineNumber)
        },
        onOpenFolder: {
            openProjectFolder()
        },
        onSetProjectFolder: { url in
            setProjectFolder(url)
        }
    )
}
```

#### Auto-Open Sidebar
Updated notification handler to automatically open sidebar:

```swift
.onReceive(NotificationCenter.default.publisher(for: .showFindInFoldersRequested)) { notif in
    guard matchesCurrentWindow(notif) else { return }
    findInFoldersQuery = ""
    showFindInFolders = true
    // Automatically show the project structure sidebar when opening Find in Folders
    if projectRootFolderURL != nil {
        showProjectStructureSidebar = true
    }
}
```

### 3. Documentation Updates (FIND_IN_FOLDERS_FEATURE.md)

- Added folder selector description to UI Panel section
- Updated workflow to include folder selection steps
- Added new UI states for sidebar closed scenario
- Enhanced edge cases to cover folder changes and sidebar requirements
- Added design rationale for requiring sidebar to be open
- Expanded testing checklist to verify folder selector integration

## User Experience Flow

### Opening Find in Folders

**Scenario 1: No Folder Open**
1. User presses `⌘⇧F`
2. Panel opens showing:
   - Orange warning box: "No folder selected"
   - "Choose Folder" button prominently displayed
   - Search field and button disabled
3. User clicks "Choose Folder"
4. Folder picker opens
5. User selects folder
6. Panel updates with folder path
7. Project Structure sidebar automatically opens and updates
8. Search becomes enabled

**Scenario 2: Folder Already Open**
1. User opens folder via `⌘⇧O`
2. Project Structure sidebar opens automatically
3. User presses `⌘⇧F`
4. Panel opens showing:
   - Folder path in gray box at top
   - "Choose Folder" button available to change
   - Project Structure sidebar auto-opens if closed
   - Search field focused and ready

**Scenario 3: Folder Open but Sidebar Closed**
1. User has folder open but closes sidebar
2. User presses `⌘⇧F`
3. Panel opens showing:
   - Folder path displayed
   - Orange warning: "Project Structure sidebar must be open to search"
   - Search disabled until sidebar is opened
4. Sidebar automatically reopens
5. Search becomes enabled

### Changing Folders from Panel

1. User has Find in Folders panel open
2. User clicks "Choose Folder" button
3. Panel dismisses temporarily
4. Folder picker opens
5. User selects new folder
6. Panel can be reopened
7. Both panel and Project Structure sidebar show new folder

## Design Benefits

### Visual Consistency
✅ Uses same `folder.badge.plus` icon as Project Structure  
✅ Folder path display matches sidebar styling  
✅ Consistent warning/info message patterns  

### User Clarity
✅ Always shows what folder is being searched  
✅ Clear call-to-action when no folder selected  
✅ Visual feedback for all states (no folder, folder selected, searching)  

### Workflow Integration
✅ Bidirectional sync: changes in panel update sidebar  
✅ Sidebar requirement ensures users see context  
✅ Auto-opening sidebar reduces manual steps  

### Error Prevention
✅ Search disabled when folder not available  
✅ Search disabled when sidebar closed  
✅ Clear warnings explain why search is disabled  

## Technical Implementation

### Binding Strategy
The panel uses `@Binding` for `projectRoot` and `showProjectStructureSidebar`, allowing:
- Real-time updates when folder changes
- Panel can trigger sidebar state changes
- Proper SwiftUI data flow and reactivity

### Callback Pattern
Three callbacks provide integration:
1. `onOpenFile` - Opens selected search result
2. `onOpenFolder` - Opens system folder picker
3. `onSetProjectFolder` - Updates project root everywhere

### State Validation
Search is only enabled when:
```swift
guard !searchQuery.isEmpty, 
      let root = projectRoot, 
      showProjectStructureSidebar 
else { return }
```

## Icons Used

| Icon | Usage | Context |
|------|-------|---------|
| `folder.badge.plus` | Choose Folder button | Same as Project Structure toolbar |
| `folder` | Folder section header | Indicates search location |
| `exclamationmark.triangle` | Warning states | No folder or sidebar closed |
| `info.circle` | Info messages | General guidance |

## Testing Checklist

### Folder Selection
- [ ] "Choose Folder" button opens folder picker
- [ ] Selecting folder updates panel display
- [ ] Selecting folder updates Project Structure sidebar
- [ ] Canceling folder picker doesn't crash

### Sidebar Integration  
- [ ] Opening panel with folder auto-opens sidebar
- [ ] Closing sidebar disables search
- [ ] Reopening sidebar re-enables search
- [ ] Warning message appears when sidebar closed

### Search States
- [ ] Search disabled when no folder
- [ ] Search disabled when sidebar closed
- [ ] Search enabled when both conditions met
- [ ] Search executes correctly after folder change

### Visual Elements
- [ ] Folder path displays correctly
- [ ] Folder path is selectable/copyable
- [ ] Warning boxes have correct colors
- [ ] Icons match Project Structure style

### Edge Cases
- [ ] Switching folders while panel open
- [ ] Opening panel in multi-window setup
- [ ] Very long folder paths wrap correctly
- [ ] Folder with special characters displays properly

---

**Status:** ✅ Fully Implemented  
**Version:** Enhanced in current release  
**Platform:** macOS, iOS, iPadOS
