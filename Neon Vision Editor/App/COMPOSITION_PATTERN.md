# Composition Pattern in SwiftUI Menu Architecture

## Overview

This document explains the **Composition Pattern** used in the Neon Vision Editor's menu system, specifically how `AppMenuCommands` is structured to provide a clean, maintainable, and testable approach to organizing complex menu hierarchies in SwiftUI applications.

## The Problem

MacOS applications often have extensive menu bars with multiple menus containing dozens of commands. When all menu code lives in the main app file (`NeonVisionEditorApp.swift`), several problems arise:

1. **Code bloat**: The main app file becomes hundreds of lines long, making it hard to navigate
2. **Poor separation of concerns**: Menu logic mixes with app lifecycle, window management, and state management
3. **Difficult testing**: Menu commands are tightly coupled to the app struct
4. **Hard to maintain**: Finding and modifying specific menu items requires scrolling through large files
5. **Dependency management**: Menu commands often need access to multiple state variables, managers, and actions

## The Solution: Composition Pattern

The Composition Pattern separates menu logic into a dedicated struct that **composes** multiple command builders while maintaining access to necessary dependencies through property injection.

### Key Characteristics

1. **Separation**: Menu code lives in `AppMenus.swift`, separate from the main app
2. **Composition**: Individual menu builders are composed into a single `allCommands` property
3. **Dependency Injection**: All required dependencies are passed as properties
4. **Encapsulation**: Helper methods and computed properties are kept private within the menu struct
5. **Type Safety**: Uses SwiftUI's `@CommandsBuilder` result builder for type-safe composition

## Architecture

### Structure Definition

```swift
struct AppMenuCommands {
    // Dependencies - injected from the main app
    let activeEditorViewModel: EditorViewModel
    let recentFilesManager: RecentFilesManager
    let supportPurchaseManager: SupportPurchaseManager
    let openWindow: OpenWindowAction
    
    // State bindings - allow two-way communication
    @Binding var useAppleIntelligence: Bool
    @Binding var showGrokError: Bool
    @Binding var grokErrorMessage: String
    @Binding var appleAIStatus: String
    @Binding var appleAIRoundTripMS: Double?
    
    // Helper methods (private)
    private var activeWindowNumber: Int? { /* ... */ }
    private func postWindowCommand(_ name: Notification.Name, object: Any?) { /* ... */ }
    var appleAIStatusMenuLabel: String { /* ... */ }
    
    // Main composition point
    @CommandsBuilder
    var allCommands: some Commands {
        settingsCommands
        fileCommands
        findCommands
        LanguageMenuCommands(activeEditorViewModel: activeEditorViewModel)
        aiCommands
        viewCommands
        editorCommands
        toolsCommands
        diagCommands
    }
    
    // Individual command builders (private)
    @CommandsBuilder
    private var settingsCommands: some Commands { /* ... */ }
    
    @CommandsBuilder
    private var fileCommands: some Commands { /* ... */ }
    
    // ... more command builders
}
```

### Usage in Main App

The main app file becomes dramatically simpler:

```swift
@main
struct NeonVisionEditorApp: App {
    // State and dependencies defined here
    @StateObject private var viewModel = EditorViewModel()
    // ... other state
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            AppMenuCommands(
                activeEditorViewModel: activeEditorViewModel,
                recentFilesManager: recentFilesManager,
                supportPurchaseManager: supportPurchaseManager,
                openWindow: openWindow,
                useAppleIntelligence: $useAppleIntelligence,
                showGrokError: $showGrokError,
                grokErrorMessage: $grokErrorMessage,
                appleAIStatus: $appleAIStatus,
                appleAIRoundTripMS: $appleAIRoundTripMS
            ).allCommands
        }
    }
}
```

## Benefits

### 1. **Clarity and Organization**

Each menu section is clearly defined in its own computed property:
- `settingsCommands` - Settings menu items
- `fileCommands` - File operations (New, Open, Save, etc.)
- `aiCommands` - AI model selection and configuration
- `viewCommands` - View toggles and options
- `editorCommands` - Editor-specific features
- `toolsCommands` - Tools and utilities
- `diagCommands` - Diagnostic and debugging commands

### 2. **Maintainability**

Adding, modifying, or removing menu items is straightforward:
- Navigate directly to the relevant command builder
- Make changes in isolation
- No risk of affecting other menu sections

### 3. **Dependency Management**

All dependencies are explicitly declared:
- **Read-only dependencies** use `let` (viewModel, managers, actions)
- **Two-way state** uses `@Binding` (flags, status strings)
- Dependencies are injected once at creation time
- No hidden or implicit dependencies

### 4. **Testability**

The composition pattern enables testing in isolation:
```swift
func testAICommands() {
    let mockViewModel = MockEditorViewModel()
    let mockManager = MockRecentFilesManager()
    // ... other mocks
    
    let menus = AppMenuCommands(
        activeEditorViewModel: mockViewModel,
        recentFilesManager: mockManager,
        // ... inject mocks
    )
    
    // Test individual command builders
    // Verify behavior without running the full app
}
```

### 5. **Reusability**

The pattern allows menu commands to be:
- Used across multiple window types
- Shared between different app configurations
- Extended with new command builders without modifying existing code

### 6. **Type Safety**

SwiftUI's `@CommandsBuilder` ensures:
- Compile-time verification of menu structure
- Type-safe composition of command groups
- Automatic menu bar generation

## Pattern Variations

### Standalone Commands Struct

For simple menu sections that don't need many dependencies:

```swift
struct LanguageMenuCommands: Commands {
    let activeEditorViewModel: EditorViewModel
    
    var body: some Commands {
        CommandMenu("Language") {
            // Menu items
        }
    }
}
```

This conforms to the `Commands` protocol directly and can be used alongside `AppMenuCommands`.

### Computed Property Composition

```swift
@CommandsBuilder
var allCommands: some Commands {
    settingsCommands
    fileCommands
    LanguageMenuCommands(activeEditorViewModel: activeEditorViewModel)
    aiCommands
}
```

The `@CommandsBuilder` automatically merges all individual command groups into a cohesive menu structure.

## When to Use This Pattern

### ✅ Use when:
- Your app has more than 3-4 menu groups
- Menu commands need access to multiple dependencies
- You want to separate menu logic from app logic
- You need to test menu behavior independently
- Multiple developers work on different menu sections

### ❌ Don't use when:
- Your app has minimal menu items (< 10 commands total)
- All menus are simple and don't require much logic
- You're building a single-window app with no complex state
- The overhead of dependency injection outweighs the benefits

## Best Practices

### 1. **Keep Command Builders Focused**

Each command builder should handle one menu or logical group:
```swift
// Good - focused on file operations
private var fileCommands: some Commands {
    CommandGroup(replacing: .newItem) { /* ... */ }
    CommandGroup(after: .newItem) { /* ... */ }
    CommandGroup(replacing: .saveItem) { /* ... */ }
}

// Avoid - mixing unrelated commands
private var miscCommands: some Commands {
    // File, Edit, and Window commands all mixed together
}
```

### 2. **Use Private for Implementation Details**

Mark individual command builders as `private`:
```swift
@CommandsBuilder
private var settingsCommands: some Commands { /* ... */ }
```

Only expose the main `allCommands` property publicly.

### 3. **Minimize Dependencies**

Only inject what's actually needed:
```swift
// Good - minimal dependencies
struct AppMenuCommands {
    let activeEditorViewModel: EditorViewModel
    @Binding var useAppleIntelligence: Bool
}

// Avoid - passing everything "just in case"
struct AppMenuCommands {
    let everySingleObjectInTheApp: /* ... */
}
```

### 4. **Use Bindings for Two-Way State**

When menu commands need to both read and write state:
```swift
@Binding var useAppleIntelligence: Bool

// In command:
Toggle("Use Apple Intelligence", isOn: $useAppleIntelligence)
```

### 5. **Group Related Functionality**

Keep related commands together within a builder:
```swift
private var viewCommands: some Commands {
    CommandGroup(after: .toolbar) {
        Button("Toggle Sidebar") { /* ... */ }
        Button("Toggle Project Structure Sidebar") { /* ... */ }
        Divider()
        Button("Brain Dump Mode") { /* ... */ }
    }
}
```

## Comparison with Other Patterns

### vs. Direct Implementation (Anti-pattern)

```swift
// Anti-pattern - everything in the main app
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { /* ... */ }
        .commands {
            CommandGroup(...) { /* 50 lines */ }
            CommandGroup(...) { /* 50 lines */ }
            CommandGroup(...) { /* 50 lines */ }
            // ... hundreds more lines
        }
    }
}
```

**Problems**: Unreadable, unmaintainable, untestable

### vs. Multiple Command Structs (Fragmented pattern)

```swift
// Fragmented - too many separate pieces
struct SettingsCommands: Commands { /* ... */ }
struct FileCommands: Commands { /* ... */ }
struct EditCommands: Commands { /* ... */ }
// ... 10 more structs

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { /* ... */ }
        .commands {
            SettingsCommands()
            FileCommands()
            EditCommands()
            // ... 10 more initializations
        }
    }
}
```

**Problems**: Too fragmented, dependency injection becomes repetitive, hard to see overall structure

### ✅ Composition Pattern (Balanced)

```swift
struct AppMenuCommands {
    // Dependencies injected once
    // All command builders in one place
    // Main app stays clean
    var allCommands: some Commands { /* ... */ }
}
```

**Benefits**: Balance of organization and simplicity

## Real-World Example: Neon Vision Editor

In Neon Vision Editor, the composition pattern manages 9 distinct menu sections:

1. **Settings** - App preferences
2. **File** - New, Open, Save, Close operations
3. **Find** - Search functionality
4. **Language** - Syntax highlighting selection
5. **AI** - AI provider selection and configuration
6. **View** - UI toggles (sidebar, translucency, etc.)
7. **Editor** - Editor-specific features (Vim mode, quick open)
8. **Tools** - Code suggestions and utilities
9. **Diag** - Diagnostics, console, and debugging

Without the composition pattern, these ~300 lines of menu code would bloat the main app file, making it difficult to maintain and extend.

## Conclusion

The Composition Pattern for SwiftUI menus provides:
- **Clean separation** between app logic and menu logic
- **Explicit dependency management** through property injection
- **Maintainable code** through focused command builders
- **Testability** through dependency injection
- **Scalability** for growing menu complexity

This pattern is particularly valuable for professional macOS applications where menu bars are complex and central to the user experience.

## Further Reading

- [SwiftUI Commands Documentation](https://developer.apple.com/documentation/swiftui/commands)
- [Result Builders in Swift](https://docs.swift.org/swift-book/LanguageGuide/AdvancedOperators.html#ID630)
- [Dependency Injection Patterns](https://www.swiftbysundell.com/articles/different-flavors-of-dependency-injection-in-swift/)
- [SwiftUI Architecture Best Practices](https://www.hackingwithswift.com/articles/227/structuring-swiftui-apps)
