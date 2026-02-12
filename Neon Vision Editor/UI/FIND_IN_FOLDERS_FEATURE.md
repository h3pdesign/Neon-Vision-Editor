# Find in Folders Feature

## Summary

The **Find in Folders** feature allows users to search for text across all files in the currently open project folder. This is a powerful multi-file search capability that complements the existing single-file Find & Replace feature.

## Implementation

### 1. Menu Command (AppMenus.swift)

```swift
CommandMenu("Find") {
    Button("Find & Replace") {
        postWindowCommand(.showFindReplaceRequested)
    }
    .keyboardShortcut("f", modifiers: .command)
    
    Button("Find in Folders...") {
        postWindowCommand(.showFindInFoldersRequested)
    }
    .keyboardShortcut("f", modifiers: [.command, .shift])
}
```

**Keyboard Shortcut:** `⌘⇧F`

### 2. UI Panel (PanelsAndHelpers.swift)

New `FindInFoldersPanel` view with:
- Search query input field
- Regex and case-sensitive toggle options
- Live search with async/await
- Results list showing:
  - Filename and line number
  - Preview of matching line
  - Full file path
- Click to open file at specific line
- Search cancellation support
- Progress indication while searching

### 3. State Management (ContentView.swift)

```swift
@State var showFindInFolders: Bool = false
@State var findInFoldersQuery: String = ""
@State var findInFoldersUseRegex: Bool = false
@State var findInFoldersCaseSensitive: Bool = false
```

Notification handler:
```swift
.onReceive(NotificationCenter.default.publisher(for: .showFindInFoldersRequested)) { notif in
    guard matchesCurrentWindow(notif) else { return }
    findInFoldersQuery = ""
    showFindInFolders = true
}
```

### 4. File Navigation (ContentView+Actions.swift)

New function to open files at specific line numbers:

```swift
func openProjectFileAtLine(url: URL, lineNumber: Int) {
    openProjectFile(url: url)
    
    // Navigate to the line after file loads
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NotificationCenter.default.post(
            name: .moveCursorToLine,
            object: nil,
            userInfo: ["line": lineNumber]
        )
    }
}
```

## Features

### Search Capabilities

✅ **Plain text search** - Fast case-sensitive or case-insensitive matching  
✅ **Regular expression support** - Use regex patterns for advanced searches  
✅ **Multi-file scanning** - Searches all text files in project folder recursively  
✅ **Line-level results** - Shows exact line where match was found  
✅ **Context preview** - Displays matching line content in results  

### Performance Optimizations

✅ **Async/await** - Non-blocking search runs in background  
✅ **Cancellation support** - Stop search anytime by closing panel  
✅ **Result limiting** - Caps at 500 results to prevent UI overload  
✅ **File type filtering** - Only searches text-based file extensions  
✅ **Task cancellation** - Properly cleans up when panel closes  

### File Type Support

The search includes these file extensions:
- **Programming:** swift, py, js, ts, php, java, kt, go, rb, rs, c, cpp, h, hpp, m, mm, cs
- **Web:** html, css, json, xml, yaml, yml
- **Configuration:** toml, md, txt, sh, bash, zsh
- **Extensionless files** (e.g., Makefile, README)

## User Experience

### Workflow

1. User opens a project folder (`⌘⇧O`)
2. User presses `⌘⇧F` (or selects **Find → Find in Folders...**)
3. Search panel opens with focus on search field
4. User types search query
5. User optionally enables Regex or Case Sensitive
6. User presses Return or clicks "Search"
7. Results appear showing all matches across files
8. User clicks a result to open that file at the matching line
9. Panel auto-dismisses when file is opened

### UI States

- **No folder open:** Shows info message prompting user to open folder first
- **Searching:** Shows progress spinner and "Searching..." status
- **Results found:** Shows list of matches with counts
- **No results:** Shows "0 results" and search file count
- **Search cancelled:** Shows "Search cancelled" message

## Edge Cases Handled

✅ **No folder open** - Disabled with helpful message  
✅ **Empty query** - Search button disabled  
✅ **Large projects** - Limits to 500 results, shows file count  
✅ **Binary files** - Skipped via file extension filtering  
✅ **Encoding errors** - Gracefully skips files that can't be read as UTF-8  
✅ **Cancellation** - Task properly cancelled when panel closes  
✅ **Regex errors** - Silently continues search if regex is invalid  

## Design Decisions

### Why Limit to 500 Results?

- **Performance:** Prevents UI lag with thousands of results
- **Usability:** 500+ results usually means query is too broad
- **UX:** Encourages users to refine searches

### Why File Extension Filtering?

- **Speed:** Avoids scanning binary/media files unnecessarily
- **Relevance:** Binary files won't have text matches anyway
- **Safety:** Prevents attempting to read non-text data as UTF-8

### Why Async/Await Instead of Dispatch?

- **Modern Swift:** Leverages Swift Concurrency for cleaner code
- **Cancellation:** Built-in Task cancellation is more robust
- **Readability:** Linear async code is easier to understand

## Testing

To verify the feature works:

1. ✅ Open a project folder with multiple Swift/text files
2. ✅ Press `⌘⇧F` - Panel opens with search field focused
3. ✅ Search for "func" - Shows all function declarations
4. ✅ Enable "Regex" and search for "func \w+\(" - Shows functions with regex
5. ✅ Click a result - Opens file at exact line
6. ✅ Close panel while searching - Search cancels gracefully
7. ✅ Try with no folder open - Shows helpful error message
8. ✅ Search with 0 results - Shows "0 results" message

## Future Enhancements

Potential improvements:

- **Include/exclude patterns** - Filter by file type or path patterns
- **Replace in files** - Extend to support bulk replacements
- **Result highlighting** - Highlight matched text in preview
- **Export results** - Save search results to file
- **Search history** - Remember recent searches
- **Proximity search** - Show surrounding lines for context
- **Parallel scanning** - Use multiple threads for faster searching
- **Incremental results** - Show results as they're found (streaming)

## Related Files

- `PanelsAndHelpers.swift` - FindInFoldersPanel UI implementation
- `AppMenus.swift` - Menu command and keyboard shortcut
- `ContentView.swift` - State management and notification handler
- `ContentView+Actions.swift` - File opening with line navigation

## Integration Points

### Works With

✅ **Open Folder feature** - Requires folder to be open  
✅ **Quick Open** - Complementary file/content navigation  
✅ **Project Structure Sidebar** - Both rely on project folder  
✅ **Recent Files** - Opened files are added to recent list  

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘F` | Find & Replace (current file) |
| `⌘⇧F` | Find in Folders (all files) |
| `⌘O` | Open File |
| `⌘⇧O` | Open Folder |
| `⌘P` | Quick Open |

## Architecture

```
User presses ⌘⇧F
         ↓
AppMenus posts .showFindInFoldersRequested notification
         ↓
ContentView receives notification
         ↓
Sets showFindInFolders = true
         ↓
Sheet presents FindInFoldersPanel
         ↓
User types query and clicks Search
         ↓
performSearch() spawns async Task
         ↓
collectFiles() gathers all text files
         ↓
searchFiles() reads each file line-by-line
         ↓
findMatch() checks each line for query
         ↓
Results update on MainActor
         ↓
User clicks result
         ↓
onOpenFile callback triggers
         ↓
openProjectFileAtLine() opens file and navigates to line
         ↓
Panel dismisses
```

---

**Status:** ✅ Fully Implemented  
**Version:** Added in current release  
**Platform:** macOS, iOS, iPadOS
