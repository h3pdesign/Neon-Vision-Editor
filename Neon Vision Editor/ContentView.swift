import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tabs: [Tab]
    @State private var selectedTab: Tab?
    @State private var showSidebar: Bool = true
    @State private var selectedTOCItem: String? = nil
    #if os(iOS)
    @State private var showingDocumentPicker = false
    #endif

    private let languages: [String] = ["Swift", "Python", "C", "C++", "Java", "HTML", "Markdown", "JSON", "Bash"]
    private let languageMap: [String: String] = [
        "swift": "swift", "py": "python", "c": "c", "cpp": "cpp", "java": "java",
        "html": "html", "htm": "html", "md": "markdown", "json": "json", "sh": "bash"
    ]

    var body: some View {
        NavigationSplitView {
            List(tabs, selection: $selectedTab) { tab in
                Text(tab.name)
                    .tag(tab)
                    .foregroundColor(.gray)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .background(Color(.windowBackgroundColor).opacity(0.85))
        } detail: {
            if let selectedTab = selectedTab {
                CustomTextEditor(
                    text: Binding(
                        get: { selectedTab.content },
                        set: { selectedTab.content = $0 }
                    ),
                    language: Binding(
                        get: { selectedTab.language },
                        set: { selectedTab.language = $0 }
                    ),
                    isModified: Binding(
                        get: { selectedTab.isModified },
                        set: { selectedTab.isModified = $0 }
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.textBackgroundColor).opacity(0.85))
                .toolbar {
                    ToolbarItemGroup {
                        Picker("Language", selection: Binding(
                            get: { selectedTab.language },
                            set: { selectedTab.language = $0 }
                        )) {
                            ForEach(languages, id: \.self) { lang in
                                Text(lang).tag(lang.lowercased() as String)
                            }
                        }
                        .labelsHidden()
                        Button(action: { showSidebar.toggle() }) {
                            Image(systemName: "sidebar.left")
                        }
                        Button(action: { openFile() }) {
                            Image(systemName: "folder.badge.plus")
                        }
                        Button(action: { saveFile(for: selectedTab) }) {
                            Image(systemName: "floppydisk")
                        }
                        Button(action: { saveAsFile(for: selectedTab) }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
                .onChange(of: selectedTab.content) { _, _ in
                    selectedTab.isModified = true
                }
                .onChange(of: selectedTab.language) { _, _ in
                    selectedTab.isModified = true
                }
                .onAppear {
                    #if os(macOS)
                    if let window = NSApplication.shared.windows.first {
                        window.title = selectedTab.name
                    }
                    #endif
                }
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    if selectedTab.isModified {
                        promptToSave(for: selectedTab)
                    }
                }
                #elseif os(iOS)
                .onDisappear {
                    if selectedTab.isModified {
                        promptToSave(for: selectedTab)
                    }
                }
                .sheet(isPresented: $showingDocumentPicker) {
                    DocumentPicker { url in
                        handleDocumentPickerSelection(url)
                    }
                }
                #endif
            } else {
                Text("Select a tab or create a new one")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .sourceCode, .swiftSource, .pythonScript, .html, .cSource, .shellScript, .json, UTType("public.markdown") ?? .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let newTab = Tab(
                name: url.lastPathComponent,
                content: content,
                language: languageMap[url.pathExtension.lowercased()] ?? "plaintext"
            )
            modelContext.insert(newTab)
            selectedTab = newTab
            if let window = NSApplication.shared.windows.first {
                window.title = newTab.name
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        #elseif os(iOS)
        showingDocumentPicker = true
        #endif
    }

    #if os(iOS)
    func handleDocumentPickerSelection(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let newTab = Tab(
                name: url.lastPathComponent,
                content: content,
                language: languageMap[url.pathExtension.lowercased()] ?? "plaintext"
            )
            modelContext.insert(newTab)
            selectedTab = newTab
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
        }
    }
    #endif

    func saveFile(for tab: Tab) {
        #if os(macOS)
        guard tab.isModified else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text, .sourceCode, .swiftSource, .pythonScript, .html, .cSource, .shellScript, .json, UTType("public.markdown") ?? .text]
        panel.nameFieldStringValue = tab.name

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tab.content.write(to: url, atomically: true, encoding: .utf8)
            tab.name = url.lastPathComponent
            tab.isModified = false
            if let window = NSApplication.shared.windows.first {
                window.title = tab.name
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        #elseif os(iOS)
        // iOS save logic (simplified, as iOS file handling is complex)
        // Implement UIDocumentPickerViewController for export
        #endif
    }

    func saveAsFile(for tab: Tab) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text, .sourceCode, .swiftSource, .pythonScript, .html, .cSource, .shellScript, .json, UTType("public.markdown") ?? .text]
        panel.nameFieldStringValue = tab.name

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tab.content.write(to: url, atomically: true, encoding: .utf8)
            tab.name = url.lastPathComponent
            tab.isModified = false
            if let window = NSApplication.shared.windows.first {
                window.title = tab.name
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        #elseif os(iOS)
        // iOS save-as logic (simplified)
        #endif
    }

    func promptToSave(for tab: Tab) {
        guard tab.isModified else { return }
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to \(tab.name)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: saveFile(for: tab)
        case .alertSecondButtonReturn: break
        default: tab.isModified = false
        }
        #elseif os(iOS)
        let alert = UIAlertController(title: "Save Changes?", message: "Do you want to save changes to \(tab.name)?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in saveFile(for: tab) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Don't Save", style: .destructive) { _ in tab.isModified = false })
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
        #endif
    }
}

#if os(iOS)
struct DocumentPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.text, .sourceCode, .swiftSource, .pythonScript, .html, .cSource, .shellScript, .json, UTType("public.markdown") ?? .text])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onSelect(url)
            }
        }
    }
}
#endif

struct CustomTextEditor: View {
    @Binding var text: String
    @Binding var language: String
    @Binding var isModified: Bool
    @Environment(\.colorScheme) private var colorScheme: SwiftUI.ColorScheme

    var body: some View {
        #if os(macOS)
        CustomTextViewRepresentable(
            text: $text,
            language: language,
            isModified: $isModified,
            colorScheme: colorScheme
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black.opacity(0.85) : Color.white.opacity(0.85))
        #elseif os(iOS)
        CustomTextViewRepresentableiOS(
            text: $text,
            language: language,
            isModified: $isModified,
            colorScheme: colorScheme
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark ? Color.black.opacity(0.85) : Color.white.opacity(0.85))
        #endif
    }
}

#if os(macOS)
struct CustomTextViewRepresentable: NSViewRepresentable {
    @Binding var text: String
    let language: String
    @Binding var isModified: Bool
    let colorScheme: SwiftUI.ColorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.delegate = context.coordinator
        textView.string = text
        updateHighlighting(textView: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
                updateHighlighting(textView: textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextViewRepresentable

        init(_ parent: CustomTextViewRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.isModified = true
            parent.updateHighlighting(textView: textView)
        }
    }

    private func updateHighlighting(textView: NSTextView) {
        let attributedString = NSMutableAttributedString(string: textView.string)
        let range = NSRange(location: 0, length: textView.string.utf16.count)

        // Base attributes
        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: range)
        attributedString.addAttribute(.foregroundColor, value: colorScheme == .dark ? NSColor.white : NSColor.black, range: range)

        // Vibrant Light highlighting
        if language == "swift" {
            // Keywords (pink: 0.983822 0 0.72776 1)
            let keywords = ["func", "class", "struct", "let", "var"]
            for keyword in keywords {
                let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b", options: [])
                regex?.enumerateMatches(in: textView.string, options: [], range: range) { match, _, _ in
                    guard let matchRange = match?.range else { return }
                    attributedString.addAttribute(.foregroundColor, value: NSColor(red: 0.983822, green: 0, blue: 0.72776, alpha: 1), range: matchRange)
                    attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), range: matchRange)
                }
            }

            // Strings (green: 0 0.743633 0 1)
            let stringRegex = try? NSRegularExpression(pattern: "\".*?\"", options: [])
            stringRegex?.enumerateMatches(in: textView.string, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor(red: 0, green: 0.743633, blue: 0, alpha: 1), range: matchRange)
            }

            // Comments (gray: 0.36526 0.421879 0.475154 1)
            let commentRegex = try? NSRegularExpression(pattern: "//.*?\n|/\\*.*?\\*/", options: [.dotMatchesLineSeparators])
            commentRegex?.enumerateMatches(in: textView.string, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor(red: 0.36526, green: 0.421879, blue: 0.475154, alpha: 1), range: matchRange)
            }

            // Numbers (blue: 0.11 0 0.81 1)
            let numberRegex = try? NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: [])
            numberRegex?.enumerateMatches(in: textView.string, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor(red: 0.11, green: 0, blue: 0.81, alpha: 1), range: matchRange)
            }
        }

        textView.textStorage?.setAttributedString(attributedString)
    }
}
#elseif os(iOS)
struct CustomTextViewRepresentableiOS: UIViewRepresentable {
    @Binding var text: String
    let language: String
    @Binding var isModified: Bool
    let colorScheme: SwiftUI.ColorScheme

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.delegate = context.coordinator
        textView.text = text
        updateHighlighting(textView: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            updateHighlighting(textView: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CustomTextViewRepresentableiOS

        init(_ parent: CustomTextViewRepresentableiOS) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.isModified = true
            parent.updateHighlighting(textView: textView)
        }
    }

    private func updateHighlighting(textView: UITextView) {
        let attributedString = NSMutableAttributedString(string: textView.text)
        let range = NSRange(location: 0, length: textView.text.utf16.count)

        // Base attributes
        attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: range)
        attributedString.addAttribute(.foregroundColor, value: colorScheme == .dark ? UIColor.white : UIColor.black, range: range)

        // Vibrant Light highlighting
        if language == "swift" {
            // Keywords (pink: 0.983822 0 0.72776 1)
            let keywords = ["func", "class", "struct", "let", "var"]
            for keyword in keywords {
                let regex = try? NSRegularExpression(pattern: "\\b\(keyword)\\b", options: [])
                regex?.enumerateMatches(in: textView.text, options: [], range: range) { match, _, _ in
                    guard let matchRange = match?.range else { return }
                    attributedString.addAttribute(.foregroundColor, value: UIColor(red: 0.983822, green: 0, blue: 0.72776, alpha: 1), range: matchRange)
                    attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold), range: matchRange)
                }
            }

            // Strings (green: 0 0.743633 0 1)
            let stringRegex = try? NSRegularExpression(pattern: "\".*?\"", options: [])
            stringRegex?.enumerateMatches(in: textView.text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor(red: 0, green: 0.743633, blue: 0, alpha: 1), range: matchRange)
            }

            // Comments (gray: 0.36526 0.421879 0.475154 1)
            let commentRegex = try? NSRegularExpression(pattern: "//.*?\n|/\\*.*?\\*/", options: [.dotMatchesLineSeparators])
            commentRegex?.enumerateMatches(in: textView.text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor(red: 0.36526, green: 0.421879, blue: 0.475154, alpha: 1), range: matchRange)
            }

            // Numbers (blue: 0.11 0 0.81 1)
            let numberRegex = try? NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: [])
            numberRegex?.enumerateMatches(in: textView.text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor(red: 0.11, green: 0, blue: 0.81, alpha: 1), range: matchRange)
            }
        }

        textView.attributedText = attributedString
    }
}
#endif
