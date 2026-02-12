import SwiftUI
import Combine
import UniformTypeIdentifiers
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum EditorTextSanitizer {
    static func sanitize(_ input: String) -> String {
        // Normalize line endings first so CRLF does not become double newlines.
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result = String.UnicodeScalarView()
        result.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars {
            switch scalar {
            case "\n":
                result.append(scalar)
            case "\t", "\u{000B}", "\u{000C}":
                result.append(" ")
            case "\u{00A0}":
                result.append(" ")
            case "\u{00B7}", "\u{2022}", "\u{2219}", "\u{237D}", "\u{2420}", "\u{2422}", "\u{2423}", "\u{2581}":
                result.append(" ")
            case "\u{00BB}", "\u{2192}", "\u{21E5}":
                result.append(" ")
            case "\u{00B6}", "\u{21A9}", "\u{21B2}", "\u{21B5}", "\u{23CE}", "\u{2424}", "\u{2425}":
                result.append("\n")
            case "\u{240A}", "\u{240D}":
                result.append("\n")
            default:
                let cat = scalar.properties.generalCategory
                if cat == .format || cat == .control || cat == .lineSeparator || cat == .paragraphSeparator {
                    continue
                }
                if (0x2400...0x243F).contains(scalar.value) {
                    continue
                }
                if cat == .spaceSeparator && scalar != " " && scalar != "\t" {
                    result.append(" ")
                    continue
                }
                result.append(scalar)
            }
        }
        return String(result)
    }
}

struct TabData: Identifiable {
    let id = UUID()
    var name: String
    var content: String
    var language: String
    var fileURL: URL?
    var languageLocked: Bool = false
    var isDirty: Bool = false
}

@MainActor
class EditorViewModel: ObservableObject {
    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?
    @Published var showSidebar: Bool = true
    @Published var isBrainDumpMode: Bool = false
    @Published var showingRename: Bool = false
    @Published var renameText: String = ""
    @Published var isLineWrapEnabled: Bool = true
    
    var selectedTab: TabData? {
        get { tabs.first(where: { $0.id == selectedTabID }) }
        set { selectedTabID = newValue?.id }
    }
    
    private let languageMap: [String: String] = [
        "swift": "swift",
        "py": "python",
        "pyi": "python",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "php": "php",
        "phtml": "php",
        "csv": "csv",
        "tsv": "csv",
        "toml": "toml",
        "ini": "ini",
        "yaml": "yaml",
        "yml": "yaml",
        "xml": "xml",
        "sql": "sql",
        "log": "log",
        "vim": "vim",
        "ipynb": "ipynb",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "go": "go",
        "rb": "ruby",
        "rs": "rust",
        "ps1": "powershell",
        "psm1": "powershell",
        "html": "html",
        "htm": "html",
        "css": "css",
        "c": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "hpp": "cpp",
        "hh": "cpp",
        "h": "cpp",
        "cs": "csharp",
        "m": "objective-c",
        "mm": "objective-c",
        "json": "json",
        "jsonc": "json",
        "json5": "json",
        "md": "markdown",
        "markdown": "markdown",
        "env": "dotenv",
        "proto": "proto",
        "graphql": "graphql",
        "gql": "graphql",
        "rst": "rst",
        "conf": "nginx",
        "nginx": "nginx",
        "cob": "cobol",
        "cbl": "cobol",
        "cobol": "cobol",
        "sh": "bash",
        "bash": "bash",
        "zsh": "zsh"
    ]
    
    init() {
        addNewTab()
    }
    
    func addNewTab() {
        // Keep language discovery active for new untitled tabs.
        let newTab = TabData(name: "Untitled \(tabs.count + 1)", content: "", language: "plain", fileURL: nil, languageLocked: false)
        tabs.append(newTab)
        selectedTabID = newTab.id
    }
    
    func renameTab(tab: TabData, newName: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].name = newName
        }
    }
    
    func updateTabContent(tab: TabData, content: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            let previous = tabs[index].content
            tabs[index].content = content
            if content != previous {
                tabs[index].isDirty = true
            }

            let isLargeContent = (content as NSString).length >= 1_000_000
            if isLargeContent {
                let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
                if !tabs[index].languageLocked,
                   let mapped = LanguageDetector.shared.preferredLanguage(for: tabs[index].fileURL) ??
                                languageMap[nameExt] {
                    tabs[index].language = mapped
                }
                return
            }
            
            // Early lock to Swift if clearly Swift-specific tokens are present
            let lower = content.lowercased()
            let swiftStrongTokens: Bool = (
                lower.contains(" import swiftui") ||
                lower.hasPrefix("import swiftui") ||
                lower.contains("@main") ||
                lower.contains(" final class ") ||
                lower.contains("public final class ") ||
                lower.contains(": view") ||
                lower.contains("@published") ||
                lower.contains("@stateobject") ||
                lower.contains("@mainactor") ||
                lower.contains("protocol ") ||
                lower.contains("extension ") ||
                lower.contains("import appkit") ||
                lower.contains("import uikit") ||
                lower.contains("import foundationmodels") ||
                lower.contains("guard ") ||
                lower.contains("if let ")
            )
            if swiftStrongTokens {
                tabs[index].language = "swift"
                tabs[index].languageLocked = true
                return
            }
            
            if !tabs[index].languageLocked {
                // If the tab name has a known extension, honor it and lock
                let nameExt = URL(fileURLWithPath: tabs[index].name).pathExtension.lowercased()
                if let extLang = languageMap[nameExt], !extLang.isEmpty {
                    // If the extension suggests C# but content looks like Swift, prefer Swift and do not lock.
                    if extLang == "csharp" {
                        let looksSwift = lower.contains("import swiftui") || lower.contains(": view") || lower.contains("@main") || lower.contains(" final class ")
                        if looksSwift {
                            tabs[index].language = "swift"
                            tabs[index].languageLocked = true
                        } else {
                            tabs[index].language = extLang
                            tabs[index].languageLocked = true
                        }
                    } else {
                        tabs[index].language = extLang
                        tabs[index].languageLocked = true
                    }
                } else {
                    let result = LanguageDetector.shared.detect(text: content, name: tabs[index].name, fileURL: tabs[index].fileURL)
                    let detected = result.lang
                    let scores = result.scores
                    let current = tabs[index].language
                    let swiftScore = scores["swift"] ?? 0
                    let csharpScore = scores["csharp"] ?? 0

                    // Derive strong Swift tokens and C# context similar to the detector to control switching behavior
                    // (let lower = content.lowercased()) -- removed duplicate since defined above
                    let swiftStrongTokens: Bool = (
                        lower.contains(" final class ") ||
                        lower.contains("public final class ") ||
                        lower.contains(": view") ||
                        lower.contains("@published") ||
                        lower.contains("@stateobject") ||
                        lower.contains("@mainactor") ||
                        lower.contains("protocol ") ||
                        lower.contains("extension ") ||
                        lower.contains("import swiftui") ||
                        lower.contains("import appkit") ||
                        lower.contains("import uikit") ||
                        lower.contains("import foundationmodels") ||
                        lower.contains("guard ") ||
                        lower.contains("if let ")
                    )

                    let hasUsingSystem = lower.contains("\nusing system;") || lower.contains("\nusing system.")
                    let hasNamespace = lower.contains("\nnamespace ")
                    let hasMainMethod = lower.contains("static void main(") || lower.contains("static int main(")
                    let hasCSharpAttributes = (lower.contains("\n[") && lower.contains("]\n") && !lower.contains("@"))
                    let csharpContext = hasUsingSystem || hasNamespace || hasMainMethod || hasCSharpAttributes

                    // Avoid switching from Swift to C# unless there is very strong C# evidence and margin
                    if current == "swift" && detected == "csharp" {
                        let requireMargin = 25
                        if swiftStrongTokens && !csharpContext {
                            // Keep Swift when Swift-only tokens are present and no C# context exists
                        } else if !(csharpContext && csharpScore >= swiftScore + requireMargin) {
                            // Not enough evidence to switch away from Swift
                        } else {
                            tabs[index].language = "csharp"
                            tabs[index].languageLocked = false
                        }
                    } else {
                        // Never downgrade an already-detected language to plain while editing.
                        // This avoids syntax-highlight flicker when detector confidence drops temporarily.
                        if detected == "plain" && current != "plain" {
                            return
                        }
                        // For all other cases, accept the detection
                        tabs[index].language = detected
                        // If Swift is confidently detected or Swift-only tokens are present, lock to prevent flip-flops
                        if detected == "swift" && (result.confidence >= 5 || swiftStrongTokens) {
                            tabs[index].languageLocked = true
                        }
                    }
                }
            }
        }
    }
    
    func updateTabLanguage(tab: TabData, language: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index].language = language
            tabs[index].languageLocked = true
        }
    }
    
    func closeTab(tab: TabData) {
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            addNewTab()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs.first?.id
        }
    }
    
    func saveFile(tab: TabData) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tabs[index].fileURL {
            do {
                AppLogger.shared.info("Saving file: \(url.lastPathComponent)", category: "Editor")
                let clean = sanitizeTextForEditor(tabs[index].content)
                tabs[index].content = clean
                try clean.write(to: url, atomically: true, encoding: .utf8)
                tabs[index].isDirty = false
                AppLogger.shared.info("File saved successfully: \(url.lastPathComponent)", category: "Editor")
            } catch {
                AppLogger.shared.error("Failed to save file: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
            }
        } else {
            saveFileAs(tab: tab)
        }
    }
    
    func saveFileAs(tab: TabData) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
#if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tabs[index].name
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [
            .text,
            .swiftSource,
            .pythonScript,
            .javaScript,
            .html,
            .css,
            .cSource,
            .json,
            mdType
        ]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                AppLogger.shared.info("Saving file as: \(url.lastPathComponent)", category: "Editor")
                let clean = sanitizeTextForEditor(tabs[index].content)
                tabs[index].content = clean
                try clean.write(to: url, atomically: true, encoding: .utf8)
                tabs[index].fileURL = url
                tabs[index].name = url.lastPathComponent
                if let mapped = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()] {
                    tabs[index].language = mapped
                    tabs[index].languageLocked = true
                }
                tabs[index].isDirty = false
                AppLogger.shared.info("File saved as: \(url.lastPathComponent)", category: "Editor")
            } catch {
                AppLogger.shared.error("Failed to save file as: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
            }
        }
#else
        // iOS/iPadOS: explicit Save As panel is not available here yet.
        // Keep document dirty so user can export/share via future document APIs.
        AppLogger.shared.warning("Save As is currently only available on macOS.", category: "Editor")
#endif
    }
    
    func openFile() {
#if os(macOS)
        let panel = NSOpenPanel()
        // Allow opening any file type, including hidden dotfiles like .zshrc
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            openFile(url: url)
        }
#else
        // iOS/iPadOS: document picker flow can be added here.
        AppLogger.shared.warning("Open File panel is currently only available on macOS.", category: "Editor")
#endif
    }
    
    func openFile(url: URL) {
        if focusTabIfOpen(for: url) { return }
        
        // Start security-scoped resource access (important for bookmarked URLs)
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            AppLogger.shared.info("Opening file: \(url.lastPathComponent)", category: "Editor")
            let raw = try String(contentsOf: url, encoding: .utf8)
            let content = sanitizeTextForEditor(raw)
            let extLang = LanguageDetector.shared.preferredLanguage(for: url) ?? languageMap[url.pathExtension.lowercased()]
            let detectedLang = extLang ?? LanguageDetector.shared.detect(text: content, name: url.lastPathComponent, fileURL: url).lang
            let newTab = TabData(name: url.lastPathComponent,
                                 content: content,
                                 language: detectedLang,
                                 fileURL: url,
                                 languageLocked: extLang != nil,
                                 isDirty: false)
            tabs.append(newTab)
            selectedTabID = newTab.id
            
            // Add to recent files
            RecentFilesManager.shared.addRecentFile(url)
            
            AppLogger.shared.info("File opened successfully: \(url.lastPathComponent) (\(detectedLang))", category: "Editor")
        } catch {
            AppLogger.shared.error("Failed to open file: \(url.lastPathComponent) - \(error.localizedDescription)", category: "Editor")
        }
    }

    private func sanitizeTextForEditor(_ input: String) -> String {
        EditorTextSanitizer.sanitize(input)
    }


    func hasOpenFile(url: URL) -> Bool {
        indexOfOpenTab(for: url) != nil
    }

    func focusTabIfOpen(for url: URL) -> Bool {
        if let existingIndex = indexOfOpenTab(for: url) {
            selectedTabID = tabs[existingIndex].id
            return true
        }
        return false
    }

    private func indexOfOpenTab(for url: URL) -> Int? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        return tabs.firstIndex { tab in
            guard let fileURL = tab.fileURL else { return false }
            return fileURL.resolvingSymlinksInPath().standardizedFileURL == target
        }
    }

    func markTabSaved(tabID: UUID, fileURL: URL? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if let fileURL {
            tabs[index].fileURL = fileURL
            tabs[index].name = fileURL.lastPathComponent
            if let mapped = LanguageDetector.shared.preferredLanguage(for: fileURL) ?? languageMap[fileURL.pathExtension.lowercased()] {
                tabs[index].language = mapped
                tabs[index].languageLocked = true
            }
        }
        tabs[index].isDirty = false
    }
    
    func wordCount(for text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }
}
