import SwiftUI
import Highlightr
import UniformTypeIdentifiers
import Combine
import SwiftData
import AppKit // Explicitly import for NSColor

// MARK: - ContentViewModel
// Manages the state and logic for the editor, including tabs and SwiftData persistence
class ContentViewModel: ObservableObject {
    @Published var text: String = "" // Current text content (legacy, now managed per tab)
    @Published var selectedLanguage: String = "swift" // Current language (managed per tab)
    @Published var tabs: [Item] = [] // Array of open tabs
    @Published var selectedTab: Item? = nil // Currently selected tab
    
    let languages: [String] = ["HTML", "C", "Swift", "Python", "C++", "Java", "Bash", "JSON"] // Available languages
    let languageMap: [String: String] = [
        "html": "html",
        "htm": "html",
        "c": "c",
        "h": "c",
        "swift": "swift",
        "py": "python",
        "cpp": "cpp",
        "java": "java",
        "sh": "bash",
        "json": "json"
    ] // Maps file extensions to languages
    
    private var modelContext: ModelContext // Store context passed from view
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Initialize by loading existing tabs
        loadTabs()
    }
    
    func openFile() {
        // Opens a file and adds it as a new tab
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [
            .text,
            .sourceCode,
            UTType.html,
            UTType.cSource,
            UTType.swiftSource,
            UTType.pythonScript,
            UTType("public.shell-script")!
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                if let lang = languageMap[url.pathExtension.lowercased()] {
                    selectedLanguage = lang
                }
                let newItem = Item(name: url.lastPathComponent, content: content, language: selectedLanguage)
                tabs.append(newItem)
                selectedTab = newItem
                saveToSwiftData(url.lastPathComponent)
            } catch {
                print("Error opening file: \(error)")
            }
        }
    }
    
    func saveFile() {
        // Saves the content of the selected tab to a file
        guard let selectedItem = selectedTab else { return }
        let savePanel = NSOpenPanel()
        savePanel.allowedContentTypes = [
            .text,
            .sourceCode,
            UTType.html,
            UTType.cSource,
            UTType.swiftSource,
            UTType.pythonScript,
            UTType("public.shell-script")!
        ]
        savePanel.nameFieldStringValue = selectedItem.name
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try selectedItem.content.write(to: url, atomically: true, encoding: .utf8)
                saveToSwiftData(selectedItem.name)
            } catch {
                print("Error saving file: \(error)")
            }
        }
    }
    
    func addNewTab() {
        // Adds a new empty tab
        let newItem = Item(name: "Note \(tabs.count + 1)", content: "", language: "swift")
        tabs.append(newItem)
        selectedTab = newItem
        saveToSwiftData(newItem.name)
    }
    
    func renameTab(_ item: Item, to newName: String) {
        // Renames the selected tab
        item.name = newName.isEmpty ? item.name : newName
        saveToSwiftData(item.name)
    }
    
    func removeTab(_ item: Item) {
        // Removes the specified tab and updates the selection
        if let index = tabs.firstIndex(of: item) {
            tabs.remove(at: index)
            if selectedTab == item {
                selectedTab = tabs.last ?? nil
            }
            do {
                try modelContext.save()
                modelContext.delete(item)
            } catch {
                print("Failed to delete from SwiftData: \(error)")
            }
        }
    }
    
    func updateContent(_ content: String) {
        // Updates the content of the selected tab
        if let selectedItem = selectedTab {
            selectedItem.content = content
            saveToSwiftData(selectedItem.name)
        }
    }
    
    func updateLanguage(_ language: String) {
        // Updates the language of the selected tab
        if let selectedItem = selectedTab {
            selectedItem.language = language
            saveToSwiftData(selectedItem.name)
        }
    }
    
    private func saveToSwiftData(_ name: String) {
        // Saves or updates the selected tab's data in SwiftData
        if let selectedItem = selectedTab {
            do {
                try modelContext.save()
                if let existingItem = try modelContext.fetch(FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)]))
                    .first(where: { $0.name == name }) {
                    existingItem.content = selectedItem.content
                    existingItem.language = selectedItem.language
                } else {
                    modelContext.insert(selectedItem)
                }
            } catch {
                print("Failed to save to SwiftData: \(error)")
            }
        }
    }
    
    func loadTabs() {
        // Loads existing tabs from SwiftData on app startup
        do {
            let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)])
            tabs = try modelContext.fetch(descriptor)
            if let firstTab = tabs.first {
                selectedTab = firstTab
            } else {
                // If no tabs exist, add a default tab
                addNewTab()
            }
        } catch {
            print("Failed to load tabs: \(error)") // Logs any errors during loading
            // Fallback to add a default tab if loading fails
            addNewTab()
        }
    }
}

// MARK: - ContentView
// This is the main view that displays the editor interface with a sidebar and tabbed content area
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext // Provides access to the SwiftData context for persistence
    @StateObject private var viewModel = ContentViewModel(modelContext: ModelContext(using: ModelContainer(for: Item.self)))
    @State private var isRenaming: [UUID: Bool] = [:] // Tracks which tab is being renamed
    @FocusState private var isFocused: Bool // Manages focus state for renaming
    
    var body: some View {
        // Horizontal stack to layout sidebar and content side by side
        HStack(spacing: 0) {
            // Sidebar section to list and manage tabs
            List(viewModel.tabs, id: \Item.id, selection: $viewModel.selectedTab) { item in
                // Horizontal stack for each tab item in the list
                HStack {
                    if isRenaming[item.id] ?? false { // Use optional binding with nil coalescing
                        TextField("Tab Name", text: Binding(
                            get: { item.name },
                            set: { viewModel.renameTab(item, to: $0) }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .foregroundColor(.black) // Changed to black for renaming text
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85)) // Match sidebar background
                        .focused($isFocused) // Enable focus management
                        .onSubmit {
                            isRenaming[item.id] = false // Commit rename on Enter
                            isFocused = false
                        }
                        .onExitCommand {
                            isRenaming[item.id] = false // Commit on focus loss
                            isFocused = false
                        }
                    } else {
                        Text(item.name) // Displays the tab's name
                            .foregroundColor(.black) // Changed to black
                            .font(.system(size: 12)) // Smaller font size
                    }
                    Spacer() // Pushes the close button to the right
                    Button("x") {
                        viewModel.removeTab(item) // Calls method to remove the tab
                    }
                    .buttonStyle(.borderless) // Removes default button styling
                    .foregroundColor(.red) // Colors the close button red
                }
                .listRowSeparator(.hidden) // Hide default separator
                .padding(.vertical, 4) // Add vertical padding to separate tabs
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.7)) // Darker background to distinguish tabs
                .cornerRadius(4) // Slight rounding for separation
                .onTapGesture(count: 2) {
                    isRenaming[item.id] = true // Enable renaming on double-click
                    isFocused = true // Focus the text field
                }
                .onTapGesture(count: 1) {
                    if isRenaming[item.id] ?? false {
                        isRenaming[item.id] = false // Return to normal on single click away
                        isFocused = false
                    }
                }
            }
            .frame(width: 200) // Fixed width for the sidebar
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85)) // Applies a semi-transparent background
            .listStyle(SidebarListStyle()) // Applies a sidebar-specific list style
            .frame(minHeight: 0) // Ensure minimum height to prevent collapse
            
            // Tabbed content area to display the selected tab's content with scroll
            ScrollView {
                VStack(spacing: 0) {
                    if let selectedItem = viewModel.selectedTab {
                        // Language picker for the selected tab
                        Picker("Language", selection: Binding(
                            get: { viewModel.selectedLanguage }, // Gets the current language
                            set: { viewModel.selectedLanguage = $0 } // Sets the new language
                        )) {
                            ForEach(viewModel.languages, id: \.self) { lang in
                                Text(lang).tag(lang.lowercased()) // Creates options for language selection
                            }
                        }
                        .pickerStyle(MenuPickerStyle()) // Uses a menu-style picker
                        .padding(.horizontal) // Adds horizontal padding
                        .frame(height: 30) // Fixed height for the picker
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85)) // Semi-transparent background
                        
                        // Custom text editor for the selected tab's content
                        CustomTextEditor(text: Binding(
                            get: { selectedItem.content }, // Gets the content of the selected item
                            set: { viewModel.updateContent($0); print("Content updated to: \($0)") } // Updates content when changed with debug
                        ), language: Binding(
                            get: { selectedItem.language }, // Gets the language of the selected item
                            set: { viewModel.updateLanguage($0) } // Updates language when changed
                        ), highlightr: HighlightrViewModel().highlightr)
                        .frame(maxWidth: .infinity, maxHeight: .infinity) // Expands to fill available space
                    } else {
                        Text("No tabs open") // Displayed when no tabs are selected
                            .foregroundColor(.primary) // Dynamic color for light/dark mode using SwiftUI's .primary
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Expands to fill remaining space
        }
        .frame(minWidth: 1000, minHeight: 600) // Minimum dimensions for the window
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85)) // Semi-transparent background
        // Temporarily removed overlay to test if it blocks interactions
        // .overlay(
        //     Rectangle()
        //         .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        //         .edgesIgnoringSafeArea(.all)
        // )
        .onAppear {
            // Load tabs when the view appears
            print("ContentView appeared, loading tabs. Tabs count: \(viewModel.tabs.count)")
            viewModel.loadTabs()
            print("After load, tabs count: \(viewModel.tabs.count), selectedTab: \(String(describing: viewModel.selectedTab))")
        }
    }
}

// MARK: - CustomTextEditor
// A custom NSViewRepresentable to integrate NSTextView with syntax highlighting
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String // Binding to the text content
    @Binding var language: String // Binding to the language for highlighting
    let highlightr: Highlightr // Highlightr instance for syntax highlighting
    
    func makeNSView(context: Context) -> NSTextView {
        // Creates a text storage with Highlightr for syntax highlighting
        let textStorage = CodeAttributedString(highlightr: highlightr)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = true
        textContainer.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude) // Enable vertical scrolling
        layoutManager.addTextContainer(textContainer)
        
        // Configures the NSTextView
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true // Allows editing
        textView.isSelectable = true // Allows selection
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) // Monospaced font
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85) // Semi-transparent background
        textView.textColor = NSColor(white: 0.2, alpha: 0.85) // Adjusted to dark grey to match intended theme
        textView.delegate = context.coordinator // Sets the coordinator as delegate
        
        // Adds a scroll view to handle large content
        let scrollView = NSScrollView(frame: textView.bounds)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true // Enables vertical scrolling
        scrollView.hasHorizontalScroller = true // Enables horizontal scrolling
        scrollView.autoresizingMask = [.width, .height] // Resizes with the view
        scrollView.autohidesScrollers = true // Hides scrollers when not needed
        
        // Initializes the text view with the current text and language
        DispatchQueue.main.async {
            textView.string = self.text
            textStorage.beginEditing()
            if let highlightedText = self.highlightr.highlight(self.text, as: self.language) {
                textStorage.setAttributedString(highlightedText)
            }
            textStorage.endEditing()
            textStorage.language = self.language
            print("TextEditor initialized with text: \(self.text)") // Debug log
        }
        
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        // Updates the text view when the bound text or language changes
        if nsView.string != text {
            nsView.string = text
            let textStorage = nsView.textStorage as! CodeAttributedString
            textStorage.beginEditing()
            if let highlightedText = highlightr.highlight(text, as: language) {
                textStorage.setAttributedString(highlightedText)
            }
            textStorage.endEditing()
            textStorage.language = language
            print("TextEditor updated with text: \(text)") // Debug log
        }
    }
    
    func makeCoordinator() -> Coordinator {
        // Creates a coordinator to handle text view delegate methods
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor // Reference to the parent view
        var language: String // Tracks the current language
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
            self.language = parent.language
        }
        
        func textDidChange(_ notification: Notification) {
            // Updates the bound text when the text view changes
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
                print("Text changed to: \(textView.string)") // Debug log
            }
        }
    }
}

// MARK: - HighlightrViewModel
// Manages the Highlightr instance for syntax highlighting
class HighlightrViewModel {
    let highlightr: Highlightr = {
        // Initializes Highlightr with the custom Vibrant Light theme
        if let h = Highlightr() {
            if let themePath = Bundle.main.path(forResource: "Vibrant Light", ofType: "xccolortheme") {
                print("Loading theme from: \(themePath)") // Debug log for theme path
                h.setTheme(to: "Vibrant Light")
            } else {
                print("Failed to find Vibrant Light theme. Falling back to vs2015.")
                h.setTheme(to: "vs2015")
            }
            return h
        } else {
            fatalError("Highlightr initialization failed. Ensure the package is correctly added via Swift Package Manager.")
        }
    }()
}
