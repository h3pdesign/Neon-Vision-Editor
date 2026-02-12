# Logging System Implementation

## Overview

A comprehensive console logging system has been added to Neon Vision Editor to provide real-time visibility into application operations, AI requests, file operations, and debugging information.

## Date

February 11, 2026

## Summary

This document describes the implementation of a centralized logging system with a dedicated console window UI that tracks all major application operations including AI model usage, file operations, code completion requests, and system events.

---

## New Files Created

### 1. `AppLogger.swift` - Core Logging Infrastructure

**Purpose**: Centralized, observable logging system that maintains a list of log entries.

**Key Components**:

#### `LogEntry` Struct
- `id`: Unique identifier (UUID)
- `timestamp`: Date of the log entry
- `level`: Log severity (DEBUG, INFO, WARNING, ERROR)
- `category`: Logical grouping (AI, Editor, App, Completion, Network, etc.)
- `message`: Human-readable log message
- `formattedTimestamp`: HH:mm:ss.SSS formatted timestamp

#### `LogEntry.LogLevel` Enum
- **DEBUG**: Development/diagnostic information (gray color)
- **INFO**: General informational messages (primary color)
- **WARNING**: Potentially problematic situations (orange color)
- **ERROR**: Error conditions (red color)

Each level has associated:
- Icon (SF Symbol)
- Color for UI display
- Raw string value

#### `AppLogger` Class
**Architecture**: `@MainActor` observable singleton using `ObservableObject`

**Properties**:
- `entries`: Published array of all log entries
- `maxEntries`: Maximum number of entries to retain (default: 1000)
- `filterLevel`: Optional filter by log level
- `filterCategory`: Optional filter by category string

**Methods**:
```swift
// Main logging method
func log(_ message: String, level: LogEntry.LogLevel = .info, category: String = "General")

// Convenience methods
func debug(_ message: String, category: String = "General")
func info(_ message: String, category: String = "General")
func warning(_ message: String, category: String = "General")
func error(_ message: String, category: String = "General")

// Utility methods
func clear() // Clear all entries
var filteredEntries: [LogEntry] // Get filtered entries
var categories: [String] // Get unique categories
```

**Behavior**:
- Automatically trims oldest entries when `maxEntries` is exceeded
- Prints to Xcode console in DEBUG builds only
- Thread-safe with `@MainActor` annotation

---

### 2. `ConsoleLogWindow.swift` - User Interface

**Purpose**: Rich, interactive log viewer window with filtering, search, and export capabilities.

#### Main View: `ConsoleLogWindow`

**Toolbar Features**:
1. **Search Field**
   - Real-time text search across messages and categories
   - Case-insensitive matching
   - Max width: 300pt

2. **Level Filter Picker**
   - Filter by log level (All, DEBUG, INFO, WARNING, ERROR)
   - Menu-style picker with icons
   - Width: 140pt

3. **Display Options (Toggles)**
   - Show/hide timestamps
   - Show/hide level icons
   - Auto-scroll to bottom

4. **Statistics**
   - Live count of filtered entries
   - Caption font, secondary color

5. **Action Buttons**
   - **Clear**: Remove all log entries
   - **Export**: Save logs to text file with timestamp

**Log Display**:
- `LazyVStack` for performance with large log counts
- Auto-scrolling to latest entry when enabled
- Empty state with helpful messages
- Hover effects on log rows

**Filtering**:
```swift
private var filteredEntries: [LogEntry] {
    // Filters by both level and search text
    // Case-insensitive search in message and category
}
```

**Export Functionality**:
```swift
private func exportLogs() {
    // Creates NSSavePanel
    // Formats logs as: [timestamp] [level] [category] message
    // Saves with ISO8601 date in filename
}
```

#### Sub-View: `LogEntryRow`

**Purpose**: Individual log entry display with rich formatting

**Features**:
- Conditional icon display (16pt width)
- Monospaced timestamp (85pt width, caption font)
- Category badge (monospaced, min 80pt, rounded background)
- Message text (monospaced body font, text selection enabled)
- Hover effect (6% opacity secondary background)
- Context menu:
  - Copy Message
  - Copy Full Entry (with timestamp and metadata)

**Layout**:
```
[Icon] [Timestamp] [Category Badge] [Message .....................]
```

---

## Integration Points

### 1. Application Lifecycle (`NeonVisionEditorApp.swift`)

#### Window Registration
```swift
WindowGroup("Console Log", id: "console-log") {
    ConsoleLogWindow()
        .background(NonRestorableWindow())
}
.defaultSize(width: 900, height: 600)
```

#### Menu Command
```swift
CommandMenu("Diag") {
    Button("Show Console Log") {
        openWindow(id: "console-log")
    }
    .keyboardShortcut("l", modifiers: [.command, .shift])
    // ... existing items
}
```

**Keyboard Shortcut**: `Cmd+Shift+L`

#### Startup Logging
```swift
.onAppear { 
    appDelegate.viewModel = viewModel
    AppLogger.shared.info("Neon Vision Editor launched", category: "App")
}
```

#### Apple Intelligence Health Checks
```swift
.task {
    AppLogger.shared.info("Checking Apple Intelligence availability...", category: "AI")
    // ... health check code
    AppLogger.shared.info("Apple Intelligence ready (RTT: X.Xms)", category: "AI")
    // OR
    AppLogger.shared.error("Apple Intelligence error: ...", category: "AI")
}
```

---

### 2. AI "Suggest Code" Command (`NeonVisionEditorApp.swift`)

**Logging Points**:

1. **Request Initiated**
```swift
AppLogger.shared.info("Suggest Code requested for \(tab.language) file", category: "AI")
```

2. **Provider Selection**
```swift
AppLogger.shared.info("Using Apple Intelligence", category: "AI")
AppLogger.shared.info("Using Grok AI", category: "AI")
AppLogger.shared.info("Using OpenAI", category: "AI")
AppLogger.shared.info("Using Gemini AI", category: "AI")
AppLogger.shared.info("Using Anthropic Claude", category: "AI")
```

3. **Fallback Scenarios**
```swift
AppLogger.shared.warning("No external AI provider configured, falling back to Apple Intelligence", category: "AI")
```

4. **Errors**
```swift
AppLogger.shared.error("No AI provider available", category: "AI")
```

5. **Completion with Metrics**
```swift
let duration = Date().timeIntervalSince(startTime)
AppLogger.shared.info("AI suggestion completed in X.XXs, XXX characters", category: "AI")
```

---

### 3. AI Model Selection (`ContentView.swift`)

```swift
.onReceive(NotificationCenter.default.publisher(for: .selectAIModelRequested)) { notif in
    // ... model selection code
    AppLogger.shared.info("AI model selected: \(modelRawValue)", category: "AI")
}
```

---

### 4. File Operations (`EditorViewModel.swift`)

#### Opening Files
```swift
func openFile(url: URL) {
    AppLogger.shared.info("Opening file: \(url.lastPathComponent)", category: "Editor")
    // ... file open logic
    AppLogger.shared.info("File opened successfully: \(url.lastPathComponent) (\(detectedLang))", category: "Editor")
    // OR on error:
    AppLogger.shared.error("Failed to open file: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
}
```

#### Saving Files
```swift
func saveFile(tab: TabData) {
    AppLogger.shared.info("Saving file: \(url.lastPathComponent)", category: "Editor")
    // ... save logic
    AppLogger.shared.info("File saved successfully: \(url.lastPathComponent)", category: "Editor")
    // OR on error:
    AppLogger.shared.error("Failed to save file: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
}
```

#### Save As
```swift
func saveFileAs(tab: TabData) {
    AppLogger.shared.info("Saving file as: \(url.lastPathComponent)", category: "Editor")
    // ... save logic
    AppLogger.shared.info("File saved as: \(url.lastPathComponent)", category: "Editor")
    // OR on error:
    AppLogger.shared.error("Failed to save file as: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
}
```

---

### 5. Code Completion (`ContentView.swift`)

**Migration**: Replaced simple `debugLog()` function with `AppLogger`

**Before**:
```swift
private func debugLog(_ message: String) {
#if DEBUG
    print(message)
#endif
}
```

**After**:
```swift
private func debugLog(_ message: String) {
    // Use AppLogger instead of simple print
    AppLogger.shared.debug(message, category: "Completion")
}
```

**Log Messages** (all at DEBUG level, "Completion" category):
- `[Completion][Fallback][Grok] request failed`
- `[Completion][Fallback][OpenAI] request failed`
- `[Completion][Fallback][Gemini] request failed`
- `[Completion][Fallback][Anthropic] request failed`
- `[Completion][Grok] request failed`
- `[Completion][OpenAI] request failed`
- `[Completion][Gemini] request failed`
- `[Completion][Anthropic] request failed`

---

## Log Categories

### Standard Categories

| Category | Purpose | Example Messages |
|----------|---------|------------------|
| `App` | Application lifecycle | "Neon Vision Editor launched" |
| `AI` | AI model operations | "Using Anthropic Claude", "AI suggestion completed in 2.21s" |
| `Editor` | File operations | "Opening file: example.swift", "File saved successfully" |
| `Completion` | Code completion | "[Completion][Grok] request failed" |
| `Network` | Network operations | *(Future use)* |
| `Cache` | Caching operations | *(Future use)* |
| `General` | Uncategorized | Default category |

---

## Usage Examples

### For Developers

#### Adding New Logs

```swift
// Information
AppLogger.shared.info("User action completed", category: "UI")

// Warning
AppLogger.shared.warning("Cache size exceeds threshold", category: "Cache")

// Error
AppLogger.shared.error("Network request failed: \(error)", category: "Network")

// Debug (development only)
AppLogger.shared.debug("Cache hit for key: \(key)", category: "Cache")
```

#### Custom Categories

```swift
// Create meaningful categories for different subsystems
AppLogger.shared.info("Theme changed to Dark Mode", category: "Theme")
AppLogger.shared.info("Syntax highlighting updated", category: "Syntax")
AppLogger.shared.error("Plugin failed to load: \(name)", category: "Plugins")
```

---

### For End Users

#### Opening the Console

**Menu**: `Diag` → `Show Console Log`  
**Keyboard**: `Cmd+Shift+L`

#### Filtering Logs

1. **By Level**: Use the picker to show only specific levels
   - "All Levels" (default)
   - "DEBUG" - development information
   - "INFO" - general messages
   - "WARNING" - potential issues
   - "ERROR" - actual errors

2. **By Search**: Type in the search field
   - Searches both message content and categories
   - Case-insensitive
   - Real-time filtering

3. **Combined**: Use both level filter and search together

#### Using Display Options

- **Clock Icon**: Toggle timestamps on/off
- **Star Icon**: Toggle level icons on/off
- **Arrow Down Icon**: Enable/disable auto-scroll to bottom

#### Copying Log Entries

- **Right-click** any log entry
- Choose "Copy Message" (message only)
- Or "Copy Full Entry" (includes timestamp, level, category)

#### Exporting Logs

1. Click the **export button** (↑ icon) in toolbar
2. Choose save location
3. Logs are saved as plain text with format:
   ```
   [HH:mm:ss.SSS] [LEVEL] [Category] Message
   ```
4. Filename includes current date: `console-log-2026-02-11T12:34:56Z.txt`

#### Clearing Logs

- Click the **trash icon** to remove all log entries
- Useful for starting a fresh debugging session

---

## Example Log Output

### Application Startup
```
[12:34:56.123] [INFO] [App] Neon Vision Editor launched
[12:34:56.345] [INFO] [AI] Checking Apple Intelligence availability...
[12:34:56.567] [INFO] [AI] Apple Intelligence ready (RTT: 222.4ms)
```

### File Operations
```
[12:35:10.123] [INFO] [Editor] Opening file: MyCode.swift
[12:35:10.145] [INFO] [Editor] File opened successfully: MyCode.swift (swift)
[12:35:25.678] [INFO] [Editor] Saving file: MyCode.swift
[12:35:25.689] [INFO] [Editor] File saved successfully: MyCode.swift
```

### AI Suggest Code Flow
```
[12:36:00.234] [INFO] [AI] Suggest Code requested for swift file
[12:36:00.245] [INFO] [AI] Using Anthropic Claude
[12:36:02.456] [INFO] [AI] AI suggestion completed in 2.21s, 347 characters
```

### AI Model Switch
```
[12:37:15.678] [INFO] [AI] AI model selected: grok
[12:37:20.123] [INFO] [AI] Suggest Code requested for python file
[12:37:20.134] [INFO] [AI] Using Grok AI
[12:37:22.890] [INFO] [AI] AI suggestion completed in 2.76s, 412 characters
```

### Code Completion Errors
```
[12:38:45.234] [DEBUG] [Completion] [Completion][Grok] request failed
[12:38:45.345] [DEBUG] [Completion] [Completion][Fallback][OpenAI] request failed
```

### File Operation Errors
```
[12:40:10.456] [ERROR] [Editor] Failed to open file: data.json - Permission denied
[12:40:25.789] [ERROR] [Editor] Failed to save file: script.py - Disk full
```

---

## Technical Details

### Performance Considerations

1. **Lazy Loading**: `LazyVStack` ensures only visible entries are rendered
2. **Entry Limit**: Automatic trimming to 1000 entries prevents memory growth
3. **Efficient Filtering**: Uses Swift's built-in `filter` operations
4. **Minimal Overhead**: Logging is lightweight; main thread operations are brief

### Memory Management

- Old entries automatically removed when exceeding `maxEntries`
- Each `LogEntry` is a value type (struct)
- Observer pattern updates UI only when entries change
- No retain cycles due to proper use of `@ObservedObject`

### Thread Safety

- `@MainActor` annotation ensures all logging happens on main thread
- Published properties automatically dispatch updates
- No manual thread synchronization needed

### Accessibility

- All controls have `.help()` modifiers for tooltips
- Text is selectable in log messages
- Keyboard navigation supported throughout
- Color contrast meets accessibility guidelines

---

## Future Enhancement Possibilities

### Potential Features

1. **Log Levels per Category**
   - Set different minimum levels for different categories
   - E.g., DEBUG for "Completion" but INFO for "Editor"

2. **Persistent Logs**
   - Save logs to file automatically
   - Load logs from previous sessions
   - Configurable retention period

3. **Advanced Filtering**
   - Multiple category selection
   - Date/time range filtering
   - Regular expression search
   - Save filter presets

4. **Log Analysis**
   - Statistics dashboard
   - Error frequency tracking
   - Performance metrics visualization
   - AI request success rate

5. **Remote Logging**
   - Optional telemetry
   - Crash report integration
   - Anonymous usage analytics

6. **Performance Profiling**
   - Duration tracking per operation
   - Memory usage logging
   - CPU time measurements

### Integration Ideas

1. **Settings Panel**
   - Configure log retention
   - Set default filters
   - Enable/disable categories
   - Control console appearance

2. **In-App Notifications**
   - Toast notifications for errors
   - Badge count on Diag menu
   - Sound alerts for critical errors

3. **Developer Tools**
   - Network request inspector
   - Database query logger
   - View hierarchy debugger

---

## Testing Recommendations

### Manual Testing Scenarios

1. **Launch and Shutdown**
   - Verify startup log appears
   - Check Apple Intelligence health check

2. **File Operations**
   - Open various file types
   - Save existing files
   - Save As with new names
   - Trigger save errors (read-only files)

3. **AI Operations**
   - Use Suggest Code with each provider
   - Switch between AI models
   - Test fallback scenarios (no API key)
   - Verify timing measurements

4. **UI Functionality**
   - Test all toolbar controls
   - Verify search and filtering
   - Test export functionality
   - Check context menu items
   - Verify auto-scroll behavior

5. **Performance**
   - Generate 1000+ log entries
   - Verify scrolling remains smooth
   - Test search with many entries
   - Check memory usage doesn't grow unbounded

### Automated Testing

```swift
import Testing

@Suite("AppLogger Tests")
struct AppLoggerTests {
    @Test("Log entry creation")
    func testLogEntry() async {
        let logger = AppLogger.shared
        logger.clear()
        
        logger.info("Test message", category: "Test")
        
        #expect(logger.entries.count == 1)
        #expect(logger.entries.first?.message == "Test message")
        #expect(logger.entries.first?.category == "Test")
    }
    
    @Test("Entry limit enforcement")
    func testEntryLimit() async {
        let logger = AppLogger.shared
        logger.clear()
        logger.maxEntries = 10
        
        for i in 0..<20 {
            logger.info("Message \(i)", category: "Test")
        }
        
        #expect(logger.entries.count == 10)
    }
    
    @Test("Filtering by level")
    func testLevelFilter() async {
        let logger = AppLogger.shared
        logger.clear()
        
        logger.info("Info message", category: "Test")
        logger.error("Error message", category: "Test")
        
        logger.filterLevel = .error
        #expect(logger.filteredEntries.count == 1)
        #expect(logger.filteredEntries.first?.level == .error)
    }
}
```

---

## Benefits Summary

### For Developers

✅ **Debugging**: See exactly what's happening with AI requests  
✅ **Visibility**: Track file operations and state changes  
✅ **Performance**: Monitor API response times and durations  
✅ **Diagnostics**: Identify failures and fallback scenarios  

### For End Users

✅ **Transparency**: Understand which AI provider is being used  
✅ **Troubleshooting**: Export logs when reporting issues  
✅ **Confidence**: See real-time confirmation of operations  
✅ **Learning**: Understand how the app works internally  

### For QA/Support

✅ **Issue Reproduction**: Clear trail of user actions  
✅ **Bug Reports**: Exportable logs for analysis  
✅ **Performance Monitoring**: Timing data for optimization  
✅ **Usage Patterns**: Understand how features are used  

---

## Conclusion

The console logging system provides comprehensive visibility into Neon Vision Editor's operations with minimal performance impact. The rich UI makes it accessible to both developers and end users, while the flexible architecture allows for easy expansion to new logging categories and use cases.

All major subsystems (AI, Editor, App lifecycle, Code Completion) are now instrumented with appropriate logging, creating a solid foundation for debugging, support, and future enhancements.

---

## Related Files

### Modified Files
- `NeonVisionEditorApp.swift` - Window registration, menu command, AI logging
- `ContentView.swift` - AI model selection logging, completion logging migration
- `EditorViewModel.swift` - File operation logging

### New Files
- `AppLogger.swift` - Core logging infrastructure
- `ConsoleLogWindow.swift` - UI implementation

### Dependencies
- SwiftUI
- Foundation
- AppKit (macOS only)
- UIKit (iOS fallbacks in ConsoleLogWindow)

---

**Document Version**: 1.0  
**Last Updated**: February 11, 2026  
**Author**: Claude (Anthropic)
