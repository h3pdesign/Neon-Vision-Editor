// ContentView.swift
// Main SwiftUI container for Neon Vision Editor. Hosts the single-document editor UI,
// toolbar actions, AI integration, syntax highlighting, line numbers, and sidebar TOC.

///MARK: - Imports
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif


// Utility: quick width calculation for strings with a given font (AppKit-based)
extension String {
#if os(macOS)
    func width(usingFont font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        let size = (self as NSString).size(withAttributes: attributes)
        return size.width
    }
#endif
}

///MARK: - Root View
//Manages the editor area, toolbar, popovers, and bridges to the view model for file I/O and metrics.
struct ContentView: View {
    private static let completionSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "InlineCompletion")

    private struct CompletionCacheEntry {
        let suggestion: String
        let createdAt: Date
    }

    // Environment-provided view model and theme/error bindings
    @EnvironmentObject var viewModel: EditorViewModel
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    @EnvironmentObject var appUpdateManager: AppUpdateManager
    @Environment(\.colorScheme) var colorScheme
#if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
#endif
#if os(macOS)
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettingsAction
#endif
    @Environment(\.showGrokError) var showGrokError
    @Environment(\.grokErrorMessage) var grokErrorMessage

    // Single-document fallback state (used when no tab model is selected)
    @AppStorage("SelectedAIModel") private var selectedModelRaw: String = AIModel.appleIntelligence.rawValue
    @State var singleContent: String = ""
    @State var singleLanguage: String = "plain"
    @State var caretStatus: String = "Ln 1, Col 1"
    @AppStorage("SettingsEditorFontSize") var editorFontSize: Double = 14
    @AppStorage("SettingsEditorFontName") var editorFontName: String = ""
    @AppStorage("SettingsLineHeight") var editorLineHeight: Double = 1.0
    @AppStorage("SettingsShowLineNumbers") var showLineNumbers: Bool = true
    @AppStorage("SettingsHighlightCurrentLine") var highlightCurrentLine: Bool = false
    @AppStorage("SettingsHighlightMatchingBrackets") var highlightMatchingBrackets: Bool = false
    @AppStorage("SettingsShowScopeGuides") var showScopeGuides: Bool = false
    @AppStorage("SettingsHighlightScopeBackground") var highlightScopeBackground: Bool = false
    @AppStorage("SettingsLineWrapEnabled") var settingsLineWrapEnabled: Bool = false
    // Removed showHorizontalRuler and showVerticalRuler AppStorage properties
    @AppStorage("SettingsIndentStyle") var indentStyle: String = "spaces"
    @AppStorage("SettingsIndentWidth") var indentWidth: Int = 4
    @AppStorage("SettingsAutoIndent") var autoIndentEnabled: Bool = true
    @AppStorage("SettingsAutoCloseBrackets") var autoCloseBracketsEnabled: Bool = false
    @AppStorage("SettingsTrimTrailingWhitespace") var trimTrailingWhitespaceEnabled: Bool = false
    @AppStorage("SettingsCompletionEnabled") var isAutoCompletionEnabled: Bool = false
    @AppStorage("SettingsCompletionFromDocument") var completionFromDocument: Bool = false
    @AppStorage("SettingsCompletionFromSyntax") var completionFromSyntax: Bool = false
    @AppStorage("SettingsReopenLastSession") var reopenLastSession: Bool = true
    @AppStorage("SettingsOpenWithBlankDocument") var openWithBlankDocument: Bool = true
    @AppStorage("SettingsConfirmCloseDirtyTab") var confirmCloseDirtyTab: Bool = true
    @AppStorage("SettingsConfirmClearEditor") var confirmClearEditor: Bool = true
    @AppStorage("SettingsActiveTab") var settingsActiveTab: String = "general"
    @AppStorage("SettingsTemplateLanguage") private var settingsTemplateLanguage: String = "swift"
    @AppStorage("SettingsThemeName") private var settingsThemeName: String = "Neon Glow"
    @State var lastProviderUsed: String = "Apple"
    @State private var highlightRefreshToken: Int = 0

    // Persisted API tokens for external providers
    @State var grokAPIToken: String = ""
    @State var openAIAPIToken: String = ""
    @State var geminiAPIToken: String = ""
    @State var anthropicAPIToken: String = ""

    // Debounce/cancellation handles for inline completion
    @State private var completionDebounceTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var lastCompletionTriggerSignature: String = ""
    @State private var isApplyingCompletion: Bool = false
    @State private var completionCache: [String: CompletionCacheEntry] = [:]
    @State private var pendingHighlightRefresh: DispatchWorkItem?
    @AppStorage("EnableTranslucentWindow") var enableTranslucentWindow: Bool = false

    @State var showFindReplace: Bool = false
    @State var showSettingsSheet: Bool = false
    @State var showUpdateDialog: Bool = false
    @State var findQuery: String = ""
    @State var replaceQuery: String = ""
    @State var findUsesRegex: Bool = false
    @State var findCaseSensitive: Bool = false
    @State var findStatusMessage: String = ""
    @State var iOSFindCursorLocation: Int = 0
    @State var iOSLastFindFingerprint: String = ""
    @State var showProjectStructureSidebar: Bool = false
    @State var showCompactSidebarSheet: Bool = false
    @State var projectRootFolderURL: URL? = nil
    @State var projectTreeNodes: [ProjectTreeNode] = []
    @State var projectTreeRefreshGeneration: Int = 0
    @State var showProjectFolderPicker: Bool = false
    @State var projectFolderSecurityURL: URL? = nil
    @State var pendingCloseTabID: UUID? = nil
    @State var showUnsavedCloseDialog: Bool = false
    @State var showClearEditorConfirmDialog: Bool = false
    @State var showIOSFileImporter: Bool = false
    @State var showIOSFileExporter: Bool = false
    @State var iosExportDocument: PlainTextDocument = PlainTextDocument(text: "")
    @State var iosExportFilename: String = "Untitled.txt"
    @State var iosExportTabID: UUID? = nil
    @State var showQuickSwitcher: Bool = false
    @State var quickSwitcherQuery: String = ""
    @State var vimModeEnabled: Bool = UserDefaults.standard.bool(forKey: "EditorVimModeEnabled")
    @State var vimInsertMode: Bool = true
    @State var droppedFileLoadInProgress: Bool = false
    @State var droppedFileProgressDeterminate: Bool = true
    @State var droppedFileLoadProgress: Double = 0
    @State var droppedFileLoadLabel: String = ""
    @State var largeFileModeEnabled: Bool = false
#if os(iOS)
    @AppStorage("SettingsForceLargeFileMode") var forceLargeFileMode: Bool = false
    @AppStorage("SettingsShowKeyboardAccessoryBarIOS") var showKeyboardAccessoryBarIOS: Bool = true
    @AppStorage("SettingsShowBottomActionBarIOS") var showBottomActionBarIOS: Bool = true
    @AppStorage("SettingsUseLiquidGlassToolbarIOS") var shouldUseLiquidGlass: Bool = true
#endif
    @AppStorage("HasSeenWelcomeTourV1") var hasSeenWelcomeTourV1: Bool = false
    @AppStorage("WelcomeTourSeenRelease") var welcomeTourSeenRelease: String = ""
    @State var showWelcomeTour: Bool = false
#if os(macOS)
    @State private var hostWindowNumber: Int? = nil
    @AppStorage("ShowBracketHelperBarMac") var showBracketHelperBarMac: Bool = false
#endif
    @State private var showLanguageSetupPrompt: Bool = false
    @State private var languagePromptSelection: String = "plain"
    @State private var languagePromptInsertTemplate: Bool = false
    @State private var whitespaceInspectorMessage: String? = nil
    @State private var didApplyStartupBehavior: Bool = false

#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
    var appleModelAvailable: Bool { true }
#else
    var appleModelAvailable: Bool { false }
#endif

    var activeProviderName: String { lastProviderUsed }
#if os(macOS)
    private let bracketHelperTokens: [String] = ["(", ")", "{", "}", "[", "]", "<", ">", "'", "\"", "`", "()", "{}", "[]", "\"\"", "''"]
#elseif os(iOS)
    var primaryGlassMaterial: Material { .ultraThinMaterial }
    var toolbarFallbackColor: Color { Color(.systemBackground) }
    var toolbarDensityScale: CGFloat { 1.0 }
    var toolbarDensityOpacity: Double { 1.0 }
#endif

    var selectedModel: AIModel {
        get { AIModel(rawValue: selectedModelRaw) ?? .appleIntelligence }
        set { selectedModelRaw = newValue.rawValue }
    }

    private func promptForGrokTokenIfNeeded() -> Bool {
        if !grokAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Grok API Token Required"
        alert.informativeText = "Enter your Grok API token to enable suggestions. You can obtain this from your Grok account."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            grokAPIToken = token
            SecureTokenStore.setToken(token, for: .grok)
            return true
        }
#endif
        return false
    }

    private func promptForOpenAITokenIfNeeded() -> Bool {
        if !openAIAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "OpenAI API Token Required"
        alert.informativeText = "Enter your OpenAI API token to enable suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            openAIAPIToken = token
            SecureTokenStore.setToken(token, for: .openAI)
            return true
        }
#endif
        return false
    }

    private func promptForGeminiTokenIfNeeded() -> Bool {
        if !geminiAPIToken.isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Gemini API Key Required"
        alert.informativeText = "Enter your Gemini API key to enable suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "AIza..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            geminiAPIToken = token
            SecureTokenStore.setToken(token, for: .gemini)
            return true
        }
#endif
        return false
    }

    private func promptForAnthropicTokenIfNeeded() -> Bool {
        if !anthropicAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Anthropic API Token Required"
        alert.informativeText = "Enter your Anthropic API token to enable suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.placeholderString = "sk-ant-..."
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty { return false }
            anthropicAPIToken = token
            SecureTokenStore.setToken(token, for: .anthropic)
            return true
        }
#endif
        return false
    }

    #if os(macOS)
    @MainActor
    private func performInlineCompletion(for textView: NSTextView) {
        completionTask?.cancel()
        completionTask = Task(priority: .utility) {
            await performInlineCompletionAsync(for: textView)
        }
    }

    @MainActor
    private func performInlineCompletionAsync(for textView: NSTextView) async {
        let completionInterval = Self.completionSignposter.beginInterval("inline_completion")
        defer { Self.completionSignposter.endInterval("inline_completion", completionInterval) }

        let sel = textView.selectedRange()
        guard sel.length == 0 else { return }
        let loc = sel.location
        guard loc > 0, loc <= (textView.string as NSString).length else { return }
        let nsText = textView.string as NSString
        if Task.isCancelled { return }
        if shouldThrottleHeavyEditorFeatures(in: nsText) { return }

        let prevChar = nsText.substring(with: NSRange(location: loc - 1, length: 1))
        var nextChar: String? = nil
        if loc < nsText.length {
            nextChar = nsText.substring(with: NSRange(location: loc, length: 1))
        }

        // Auto-close braces/brackets/parens if not already closed
        let pairs: [String: String] = ["{": "}", "(": ")", "[": "]"]
        if let closing = pairs[prevChar] {
            if nextChar != closing {
                // Insert closing and move caret back between pair
                let insertion = closing
                textView.insertText(insertion, replacementRange: sel)
                textView.setSelectedRange(NSRange(location: loc, length: 0))
                return
            }
        }

        // If previous char is '{' and language is swift, javascript, c, or cpp, insert code block scaffold
        if prevChar == "{" && ["swift", "javascript", "c", "cpp"].contains(currentLanguage) {
            // Get current line indentation
            let fullText = textView.string as NSString
            let lineRange = fullText.lineRange(for: NSRange(location: loc - 1, length: 0))
            let lineText = fullText.substring(with: lineRange)
            let indentPrefix = lineText.prefix(while: { $0 == " " || $0 == "\t" })

            let indentString = String(indentPrefix)
            let indentLevel = indentString.count
            let indentSpaces = "    " // 4 spaces

            // Build scaffold string
            let scaffold = "\n\(indentString)\(indentSpaces)\n\(indentString)}"

            // Insert scaffold at caret position
            textView.insertText(scaffold, replacementRange: NSRange(location: loc, length: 0))

            // Move caret to indented empty line
            let newCaretLocation = loc + 1 + indentLevel + indentSpaces.count
            textView.setSelectedRange(NSRange(location: newCaretLocation, length: 0))
            return
        }

        // Model-backed completion attempt
        let doc = textView.string
        // Limit completion context by both recent lines and UTF-16 length for lower latency.
        let nsDoc = doc as NSString
        let contextPrefix = completionContextPrefix(in: nsDoc, caretLocation: loc)
        let cacheKey = completionCacheKey(prefix: contextPrefix, language: currentLanguage, caretLocation: loc)

        if let cached = cachedCompletion(for: cacheKey) {
            Self.completionSignposter.emitEvent("completion_cache_hit")
            applyInlineSuggestion(cached, textView: textView, selection: sel)
            return
        }

        let modelInterval = Self.completionSignposter.beginInterval("model_completion")
        let suggestion = await generateModelCompletion(prefix: contextPrefix, language: currentLanguage)
        Self.completionSignposter.endInterval("model_completion", modelInterval)
        if Task.isCancelled { return }
        storeCompletionInCache(suggestion, for: cacheKey)

        applyInlineSuggestion(suggestion, textView: textView, selection: sel)
    }

    private func completionContextPrefix(in nsDoc: NSString, caretLocation: Int, maxUTF16: Int = 3000, maxLines: Int = 120) -> String {
        let startByChars = max(0, caretLocation - maxUTF16)

        var cursor = caretLocation
        var seenLines = 0
        while cursor > 0 && seenLines < maxLines {
            let searchRange = NSRange(location: 0, length: cursor)
            let found = nsDoc.range(of: "\n", options: .backwards, range: searchRange)
            if found.location == NSNotFound {
                cursor = 0
                break
            }
            cursor = found.location
            seenLines += 1
        }
        let startByLines = cursor
        let start = max(startByChars, startByLines)
        return nsDoc.substring(with: NSRange(location: start, length: caretLocation - start))
    }

    private func completionCacheKey(prefix: String, language: String, caretLocation: Int) -> String {
        let normalizedPrefix = String(prefix.suffix(320))
        var hasher = Hasher()
        hasher.combine(language)
        hasher.combine(caretLocation / 32)
        hasher.combine(normalizedPrefix)
        return "\(language):\(caretLocation / 32):\(hasher.finalize())"
    }

    private func cachedCompletion(for key: String) -> String? {
        pruneCompletionCacheIfNeeded()
        guard let entry = completionCache[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > 20 {
            completionCache.removeValue(forKey: key)
            return nil
        }
        return entry.suggestion
    }

    private func storeCompletionInCache(_ suggestion: String, for key: String) {
        completionCache[key] = CompletionCacheEntry(suggestion: suggestion, createdAt: Date())
        pruneCompletionCacheIfNeeded()
    }

    private func pruneCompletionCacheIfNeeded() {
        if completionCache.count <= 220 { return }
        let cutoff = Date().addingTimeInterval(-20)
        completionCache = completionCache.filter { $0.value.createdAt >= cutoff }
        if completionCache.count <= 200 { return }
        let sorted = completionCache.sorted { $0.value.createdAt > $1.value.createdAt }
        completionCache = Dictionary(uniqueKeysWithValues: sorted.prefix(200).map { ($0.key, $0.value) })
    }

    private func applyInlineSuggestion(_ suggestion: String, textView: NSTextView, selection: NSRange) {
        guard let accepting = textView as? AcceptingTextView else { return }
        let currentText = textView.string as NSString
        let currentSelection = textView.selectedRange()
        guard currentSelection.length == 0, currentSelection.location == selection.location else { return }
        let nextRangeLength = min(suggestion.count, currentText.length - selection.location)
        let nextText = nextRangeLength > 0 ? currentText.substring(with: NSRange(location: selection.location, length: nextRangeLength)) : ""
        if suggestion.isEmpty || nextText.starts(with: suggestion) {
            accepting.clearInlineSuggestion()
            return
        }
        accepting.showInlineSuggestion(suggestion, at: selection.location)
    }

    private func shouldThrottleHeavyEditorFeatures(in nsText: NSString? = nil) -> Bool {
        if largeFileModeEnabled { return true }
        let length = nsText?.length ?? (currentContentBinding.wrappedValue as NSString).length
        return length >= 120_000
    }

    private func shouldScheduleCompletion(for textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let location = selection.location
        guard location > 0, location <= nsText.length else { return false }
        if shouldThrottleHeavyEditorFeatures(in: nsText) { return false }

        let prevChar = nsText.substring(with: NSRange(location: location - 1, length: 1))
        let triggerChars: Set<String> = [".", "(", ")", "{", "}", "[", "]", ":", ",", "\n", "\t", " "]
        if triggerChars.contains(prevChar) { return true }

        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if prevChar.rangeOfCharacter(from: wordChars) == nil { return false }

        if location >= nsText.length { return true }
        let nextChar = nsText.substring(with: NSRange(location: location, length: 1))
        let separator = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return nextChar.rangeOfCharacter(from: separator) != nil
    }

    private func completionDebounceInterval(for textView: NSTextView) -> TimeInterval {
        let docLength = (textView.string as NSString).length
        if docLength >= 80_000 { return 0.9 }
        if docLength >= 25_000 { return 0.7 }
        return 0.45
    }

    private func completionTriggerSignature(for textView: NSTextView) -> String {
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return "" }
        let location = selection.location
        guard location > 0, location <= nsText.length else { return "" }

        let prevChar = nsText.substring(with: NSRange(location: location - 1, length: 1))
        let nextChar: String
        if location < nsText.length {
            nextChar = nsText.substring(with: NSRange(location: location, length: 1))
        } else {
            nextChar = ""
        }
        // Keep signature cheap while specific enough to skip duplicate notifications.
        return "\(location)|\(prevChar)|\(nextChar)|\(nsText.length)"
    }
    #endif

    private func externalModelCompletion(prefix: String, language: String) async -> String {
        // Try Grok
        if !grokAPIToken.isEmpty {
            do {
                guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else { return "" }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(grokAPIToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "grok-2-latest",
                    "messages": [["role": "user", "content": prompt]],
                    "temperature": 0.5,
                    "max_tokens": 64,
                    "n": 1,
                    "stop": [""]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return sanitizeCompletion(content)
                }
            } catch {
                debugLog("[Completion][Fallback][Grok] request failed")
            }
        }
        // Try OpenAI
        if !openAIAPIToken.isEmpty {
            do {
                guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return "" }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(openAIAPIToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": [["role": "user", "content": prompt]],
                    "temperature": 0.5,
                    "max_tokens": 64,
                    "n": 1,
                    "stop": [""]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return sanitizeCompletion(content)
                }
            } catch {
                debugLog("[Completion][Fallback][OpenAI] request failed")
            }
        }
        // Try Gemini
        if !geminiAPIToken.isEmpty {
            do {
                let model = "gemini-1.5-flash-latest"
                let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
                guard let url = URL(string: endpoint) else { return "" }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(geminiAPIToken, forHTTPHeaderField: "x-goog-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "contents": [["parts": [["text": prompt]]]],
                    "generationConfig": ["temperature": 0.5, "maxOutputTokens": 64]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    return sanitizeCompletion(text)
                }
            } catch {
                debugLog("[Completion][Fallback][Gemini] request failed")
            }
        }
        // Try Anthropic
        if !anthropicAPIToken.isEmpty {
            do {
                guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return "" }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(anthropicAPIToken, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "claude-3-5-haiku-latest",
                    "max_tokens": 64,
                    "temperature": 0.5,
                    "messages": [["role": "user", "content": prompt]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let contentArr = json["content"] as? [[String: Any]],
                   let first = contentArr.first,
                   let text = first["text"] as? String {
                    return sanitizeCompletion(text)
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? [String: Any],
                   let contentArr = message["content"] as? [[String: Any]],
                   let first = contentArr.first,
                   let text = first["text"] as? String {
                    return sanitizeCompletion(text)
                }
            } catch {
                debugLog("[Completion][Fallback][Anthropic] request failed")
            }
        }
        return ""
    }

    private func appleModelCompletion(prefix: String, language: String) async -> String {
        let client = AppleIntelligenceAIClient()
        var aggregated = ""
        var firstChunk: String?
        for await chunk in client.streamSuggestions(prompt: "Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.\n\n\(prefix)\n\nCompletion:") {
            if firstChunk == nil, !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                firstChunk = chunk
                break
            } else {
                aggregated += chunk
            }
        }
        let candidate = sanitizeCompletion((firstChunk ?? aggregated))
        await MainActor.run { lastProviderUsed = "Apple" }
        return candidate
    }

    private func generateModelCompletion(prefix: String, language: String) async -> String {
        switch selectedModel {
        case .appleIntelligence:
            return await appleModelCompletion(prefix: prefix, language: language)
        case .grok:
            if grokAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                return res
            }
            do {
                guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(grokAPIToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "grok-2-latest",
                    "messages": [["role": "user", "content": prompt]],
                    "temperature": 0.5,
                    "max_tokens": 64,
                    "n": 1,
                    "stop": [""]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    await MainActor.run { lastProviderUsed = "Grok" }
                    return sanitizeCompletion(content)
                }
                // If no content, fallback to Apple
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][Grok] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Grok (fallback to Apple)" }
                return res
            }
        case .openAI:
            if openAIAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                return res
            }
            do {
                guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(openAIAPIToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": [["role": "user", "content": prompt]],
                    "temperature": 0.5,
                    "max_tokens": 64,
                    "n": 1,
                    "stop": [""]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    await MainActor.run { lastProviderUsed = "OpenAI" }
                    return sanitizeCompletion(content)
                }
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][OpenAI] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "OpenAI (fallback to Apple)" }
                return res
            }
        case .gemini:
            if geminiAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                return res
            }
            do {
                let model = "gemini-1.5-flash-latest"
                let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
                guard let url = URL(string: endpoint) else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(geminiAPIToken, forHTTPHeaderField: "x-goog-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "contents": [["parts": [["text": prompt]]]],
                    "generationConfig": ["temperature": 0.5, "maxOutputTokens": 64]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let first = candidates.first,
                   let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    await MainActor.run { lastProviderUsed = "Gemini" }
                    return sanitizeCompletion(text)
                }
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][Gemini] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Gemini (fallback to Apple)" }
                return res
            }
        case .anthropic:
            if anthropicAPIToken.isEmpty {
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                return res
            }
            do {
                guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                    let res = await appleModelCompletion(prefix: prefix, language: language)
                    await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                    return res
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(anthropicAPIToken, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let prompt = """
                Continue the following \(language) code snippet with a few lines or tokens of code only. Do not add prose or explanations.

                \(prefix)

                Completion:
                """
                let body: [String: Any] = [
                    "model": "claude-3-5-haiku-latest",
                    "max_tokens": 64,
                    "temperature": 0.5,
                    "messages": [["role": "user", "content": prompt]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let contentArr = json["content"] as? [[String: Any]],
                   let first = contentArr.first,
                   let text = first["text"] as? String {
                    await MainActor.run { lastProviderUsed = "Anthropic" }
                    return sanitizeCompletion(text)
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? [String: Any],
                   let contentArr = message["content"] as? [[String: Any]],
                   let first = contentArr.first,
                   let text = first["text"] as? String {
                    await MainActor.run { lastProviderUsed = "Anthropic" }
                    return sanitizeCompletion(text)
                }
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                return res
            } catch {
                debugLog("[Completion][Anthropic] request failed")
                let res = await appleModelCompletion(prefix: prefix, language: language)
                await MainActor.run { lastProviderUsed = "Anthropic (fallback to Apple)" }
                return res
            }
        }
    }

    private func sanitizeCompletion(_ raw: String) -> String {
        // Remove code fences and prose, keep first few lines of code only
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove opening and closing code fences if present
        while result.hasPrefix("```") {
            if let fenceEndIndex = result.firstIndex(of: "\n") {
                result = String(result[fenceEndIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }
        if let closingFenceRange = result.range(of: "```") {
            result = String(result[..<closingFenceRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Keep a single line only
        if let firstLine = result.components(separatedBy: .newlines).first {
            result = firstLine
        }

        // Trim leading whitespace so the ghost text aligns at the caret
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep the completion short and code-like
        if result.count > 40 {
            let idx = result.index(result.startIndex, offsetBy: 40)
            result = String(result[..<idx])
            if let lastSpace = result.lastIndex(of: " ") {
                result = String(result[..<lastSpace])
            }
        }

        // Filter out suggestions that are mostly prose
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_()[]{}.,;:+-/*=<>!|&%?\"'` \t")
        if result.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return ""
        }

        return result
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print(message)
#endif
    }

#if os(macOS)
    private func matchesCurrentWindow(_ notif: Notification) -> Bool {
        guard let target = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int else {
            return true
        }
        guard let hostWindowNumber else { return false }
        return target == hostWindowNumber
    }

    private func updateWindowRegistration(_ window: NSWindow?) {
        let number = window?.windowNumber
        if hostWindowNumber != number, let old = hostWindowNumber {
            WindowViewModelRegistry.shared.unregister(windowNumber: old)
        }
        hostWindowNumber = number
        if let number {
            WindowViewModelRegistry.shared.register(viewModel, for: number)
        }
    }

    private func requestBracketHelperInsert(_ token: String) {
        let targetWindow = hostWindowNumber ?? NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
        var userInfo: [String: Any] = [EditorCommandUserInfo.bracketToken: token]
        if let targetWindow {
            userInfo[EditorCommandUserInfo.windowNumber] = targetWindow
        }
        NotificationCenter.default.post(
            name: .insertBracketHelperTokenRequested,
            object: nil,
            userInfo: userInfo
        )
    }
#else
    private func matchesCurrentWindow(_ notif: Notification) -> Bool { true }
#endif

#if os(macOS)
    private var bracketHelperBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bracketHelperTokens, id: \.self) { token in
                    Button(token) {
                        requestBracketHelperInsert(token)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }
#endif

    private func withBaseEditorEvents<Content: View>(_ view: Content) -> some View {
        let viewWithClipboardEvents = view
            .onReceive(NotificationCenter.default.publisher(for: .caretPositionDidChange)) { notif in
                if let line = notif.userInfo?["line"] as? Int, let col = notif.userInfo?["column"] as? Int {
                    if line <= 0 {
                        caretStatus = "Pos \(col)"
                    } else {
                        caretStatus = "Ln \(line), Col \(col)"
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pastedText)) { notif in
                handlePastedTextNotification(notif)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pastedFileURL)) { notif in
                handlePastedFileNotification(notif)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomEditorFontRequested)) { notif in
                let delta: Double = {
                    if let d = notif.object as? Double { return d }
                    if let n = notif.object as? NSNumber { return n.doubleValue }
                    return 1
                }()
                adjustEditorFontSize(delta)
            }
            .onReceive(NotificationCenter.default.publisher(for: .droppedFileURL)) { notif in
                handleDroppedFileNotification(notif)
            }

        return viewWithClipboardEvents
            .onReceive(NotificationCenter.default.publisher(for: .droppedFileLoadStarted)) { notif in
                droppedFileLoadInProgress = true
                droppedFileProgressDeterminate = (notif.userInfo?["isDeterminate"] as? Bool) ?? true
                droppedFileLoadProgress = 0
                droppedFileLoadLabel = "Reading file"
                largeFileModeEnabled = (notif.userInfo?["largeFileMode"] as? Bool) ?? false
            }
            .onReceive(NotificationCenter.default.publisher(for: .droppedFileLoadProgress)) { notif in
                // Recover even if "started" was missed.
                droppedFileLoadInProgress = true
                if let determinate = notif.userInfo?["isDeterminate"] as? Bool {
                    droppedFileProgressDeterminate = determinate
                }
                let fraction: Double = {
                    if let v = notif.userInfo?["fraction"] as? Double { return v }
                    if let v = notif.userInfo?["fraction"] as? NSNumber { return v.doubleValue }
                    if let v = notif.userInfo?["fraction"] as? Float { return Double(v) }
                    if let v = notif.userInfo?["fraction"] as? CGFloat { return Double(v) }
                    return droppedFileLoadProgress
                }()
                droppedFileLoadProgress = min(max(fraction, 0), 1)
                if (notif.userInfo?["largeFileMode"] as? Bool) == true {
                    largeFileModeEnabled = true
                }
                if let name = notif.userInfo?["fileName"] as? String, !name.isEmpty {
                    droppedFileLoadLabel = name
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .droppedFileLoadFinished)) { notif in
                let success = (notif.userInfo?["success"] as? Bool) ?? true
                droppedFileLoadProgress = success ? 1 : 0
                droppedFileProgressDeterminate = true
                if (notif.userInfo?["largeFileMode"] as? Bool) == true {
                    largeFileModeEnabled = true
                }
                if !success, let message = notif.userInfo?["message"] as? String, !message.isEmpty {
                    findStatusMessage = "Drop failed: \(message)"
                    droppedFileLoadLabel = "Import failed"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.35 : 2.5)) {
                    droppedFileLoadInProgress = false
                }
            }
            .onChange(of: viewModel.selectedTab?.id) { _, _ in
                updateLargeFileMode(for: currentContentBinding.wrappedValue)
                scheduleHighlightRefresh()
            }
            .onChange(of: currentLanguage) { _, newValue in
                settingsTemplateLanguage = newValue
            }
    }

    private func handlePastedTextNotification(_ notif: Notification) {
        guard let pasted = notif.object as? String else {
            DispatchQueue.main.async {
                updateLargeFileMode(for: currentContentBinding.wrappedValue)
                scheduleHighlightRefresh()
            }
            return
        }
        let result = LanguageDetector.shared.detect(text: pasted, name: nil, fileURL: nil)
        if let tab = viewModel.selectedTab {
            if let idx = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
               !viewModel.tabs[idx].languageLocked,
               viewModel.tabs[idx].language == "plain",
               result.lang != "plain" {
                viewModel.tabs[idx].language = result.lang
            }
        } else if singleLanguage == "plain", result.lang != "plain" {
            singleLanguage = result.lang
        }
        DispatchQueue.main.async {
            updateLargeFileMode(for: currentContentBinding.wrappedValue)
            scheduleHighlightRefresh()
        }
    }

    private func handlePastedFileNotification(_ notif: Notification) {
        var urls: [URL] = []
        if let url = notif.object as? URL {
            urls = [url]
        } else if let list = notif.object as? [URL] {
            urls = list
        }
        guard !urls.isEmpty else { return }
        for url in urls {
            viewModel.openFile(url: url)
        }
        DispatchQueue.main.async {
            updateLargeFileMode(for: currentContentBinding.wrappedValue)
            scheduleHighlightRefresh()
        }
    }

    private func handleDroppedFileNotification(_ notif: Notification) {
        guard let fileURL = notif.object as? URL else { return }
        if let preferred = LanguageDetector.shared.preferredLanguage(for: fileURL) {
            if let tab = viewModel.selectedTab {
                if let idx = viewModel.tabs.firstIndex(where: { $0.id == tab.id }),
                   !viewModel.tabs[idx].languageLocked,
                   viewModel.tabs[idx].language == "plain" {
                    viewModel.tabs[idx].language = preferred
                }
            } else if singleLanguage == "plain" {
                singleLanguage = preferred
            }
        }
        DispatchQueue.main.async {
            updateLargeFileMode(for: currentContentBinding.wrappedValue)
            scheduleHighlightRefresh()
        }
    }

    func updateLargeFileMode(for text: String) {
#if os(iOS)
        let isLarge = forceLargeFileMode || text.utf8.count >= 2_000_000
#else
        let isLarge = text.utf8.count >= 2_000_000
#endif
        if largeFileModeEnabled != isLarge {
            largeFileModeEnabled = isLarge
            scheduleHighlightRefresh()
        }
    }

    func recordDiagnostic(_ message: String) {
#if DEBUG
        print("[NVE] \(message)")
#endif
    }

    func adjustEditorFontSize(_ delta: Double) {
        let clamped = min(28, max(10, editorFontSize + delta))
        if clamped != editorFontSize {
            editorFontSize = clamped
            scheduleHighlightRefresh()
        }
    }

    private func pastedFileURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed), FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if trimmed.hasPrefix("/") && FileManager.default.fileExists(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }
        return nil
    }

    private func withCommandEvents<Content: View>(_ view: Content) -> some View {
        let viewWithEditorActions = view
            .onReceive(NotificationCenter.default.publisher(for: .clearEditorRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                requestClearEditorContent()
            }
            .onChange(of: isAutoCompletionEnabled) { _, enabled in
                if enabled && viewModel.isBrainDumpMode {
                    viewModel.isBrainDumpMode = false
                    UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
                }
                syncAppleCompletionAvailability()
                if enabled && currentLanguage == "plain" && !showLanguageSetupPrompt {
                    showLanguageSetupPrompt = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleVimModeRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                vimModeEnabled.toggle()
                UserDefaults.standard.set(vimModeEnabled, forKey: "EditorVimModeEnabled")
                UserDefaults.standard.set(vimModeEnabled, forKey: "EditorVimInterceptionEnabled")
                vimInsertMode = !vimModeEnabled
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                toggleSidebarFromToolbar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBrainDumpModeRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                viewModel.isBrainDumpMode.toggle()
                UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTranslucencyRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                if let enabled = notif.object as? Bool {
                    enableTranslucentWindow = enabled
                    UserDefaults.standard.set(enabled, forKey: "EnableTranslucentWindow")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vimModeStateDidChange)) { notif in
                if let isInsert = notif.userInfo?["insertMode"] as? Bool {
                    vimInsertMode = isInsert
                }
            }

        let viewWithPanels = viewWithEditorActions
            .onReceive(NotificationCenter.default.publisher(for: .showFindReplaceRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                showFindReplace = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showQuickSwitcherRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                quickSwitcherQuery = ""
                showQuickSwitcher = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showWelcomeTourRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                showWelcomeTour = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleProjectStructureSidebarRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                showProjectStructureSidebar.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAPISettingsRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                openAPISettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showUpdaterRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                let shouldCheckNow = (notif.object as? Bool) ?? true
                showUpdaterDialog(checkNow: shouldCheckNow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAIModelRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                guard let modelRawValue = notif.object as? String,
                      let model = AIModel(rawValue: modelRawValue) else { return }
                selectedModelRaw = model.rawValue
            }

        return viewWithPanels
    }

    private func withTypingEvents<Content: View>(_ view: Content) -> some View {
#if os(macOS)
        view
            .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { notif in
                guard isAutoCompletionEnabled && !viewModel.isBrainDumpMode && !isApplyingCompletion else { return }
                guard let changedTextView = notif.object as? NSTextView else { return }
                guard let activeTextView = NSApp.keyWindow?.firstResponder as? NSTextView, changedTextView === activeTextView else { return }
                if let hostWindowNumber,
                   let changedWindowNumber = changedTextView.window?.windowNumber,
                   changedWindowNumber != hostWindowNumber {
                    return
                }
                guard shouldScheduleCompletion(for: changedTextView) else { return }
                let signature = completionTriggerSignature(for: changedTextView)
                guard !signature.isEmpty else { return }
                if signature == lastCompletionTriggerSignature {
                    return
                }
                lastCompletionTriggerSignature = signature
                completionDebounceTask?.cancel()
                completionTask?.cancel()
                let debounce = completionDebounceInterval(for: changedTextView)
                completionDebounceTask = Task { @MainActor [weak changedTextView] in
                    let delay = UInt64((debounce * 1_000_000_000).rounded())
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled, let changedTextView else { return }
                    lastCompletionTriggerSignature = ""
                    performInlineCompletion(for: changedTextView)
                }
            }
#else
        view
#endif
    }

    @ViewBuilder
    private var platformLayout: some View {
#if os(macOS)
        Group {
            if shouldUseSplitView {
                NavigationSplitView {
                    sidebarView
                } detail: {
                    editorView
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 600)
                .background(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
            } else {
                editorView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
#else
        NavigationStack {
            Group {
                if shouldUseSplitView {
                    NavigationSplitView {
                        sidebarView
                    } detail: {
                        editorView
                    }
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 600)
                    .background(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
                } else {
                    editorView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
    }

    // Layout: NavigationSplitView with optional sidebar and the primary code editor.
    var body: some View {
        AnyView(platformLayout)
        .alert("AI Error", isPresented: showGrokError) {
            Button("OK") { }
        } message: {
            Text(grokErrorMessage.wrappedValue)
        }
        .alert(
            "Whitespace Scalars",
            isPresented: Binding(
                get: { whitespaceInspectorMessage != nil },
                set: { if !$0 { whitespaceInspectorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(whitespaceInspectorMessage ?? "")
        }
        .navigationTitle("Neon Vision Editor")
        .onAppear {
            if UserDefaults.standard.object(forKey: "SettingsAutoIndent") == nil {
                autoIndentEnabled = true
            }
            // Always start with completion disabled on app launch/open.
            isAutoCompletionEnabled = false
            UserDefaults.standard.set(false, forKey: "SettingsCompletionEnabled")
            // Keep whitespace marker rendering disabled by default and after migrations.
            UserDefaults.standard.set(false, forKey: "SettingsShowInvisibleCharacters")
            UserDefaults.standard.set(false, forKey: "NSShowAllInvisibles")
            UserDefaults.standard.set(false, forKey: "NSShowControlCharacters")
            viewModel.isLineWrapEnabled = settingsLineWrapEnabled
            syncAppleCompletionAvailability()
        }
        .onChange(of: settingsLineWrapEnabled) { _, enabled in
            if viewModel.isLineWrapEnabled != enabled {
                viewModel.isLineWrapEnabled = enabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whitespaceScalarInspectionResult)) { notif in
            guard matchesCurrentWindow(notif) else { return }
            if let msg = notif.userInfo?[EditorCommandUserInfo.inspectionMessage] as? String {
                whitespaceInspectorMessage = msg
            }
        }
        .onChange(of: viewModel.isLineWrapEnabled) { _, enabled in
            if settingsLineWrapEnabled != enabled {
                settingsLineWrapEnabled = enabled
            }
        }
        .onChange(of: appUpdateManager.automaticPromptToken) { _, _ in
            if appUpdateManager.consumeAutomaticPromptIfNeeded() {
                showUpdaterDialog(checkNow: false)
            }
        }
        .onChange(of: settingsThemeName) { _, _ in
            scheduleHighlightRefresh()
        }
        .onChange(of: highlightMatchingBrackets) { _, _ in
            scheduleHighlightRefresh()
        }
        .onChange(of: showScopeGuides) { _, _ in
            scheduleHighlightRefresh()
        }
        .onChange(of: highlightScopeBackground) { _, _ in
            scheduleHighlightRefresh()
        }
        .onChange(of: viewModel.isLineWrapEnabled) { _, _ in
            scheduleHighlightRefresh()
        }
        .onReceive(viewModel.$tabs) { _ in
            persistSessionIfReady()
        }
        .modifier(ModalPresentationModifier(contentView: self))
        .onAppear {
            // Start with sidebar collapsed by default
            viewModel.showSidebar = false
            showProjectStructureSidebar = false

            applyStartupBehaviorIfNeeded()

            // Restore Brain Dump mode from defaults
            if UserDefaults.standard.object(forKey: "BrainDumpModeEnabled") != nil {
                viewModel.isBrainDumpMode = UserDefaults.standard.bool(forKey: "BrainDumpModeEnabled")
            }

            applyWindowTranslucency(enableTranslucentWindow)
            if !hasSeenWelcomeTourV1 || welcomeTourSeenRelease != WelcomeTourView.releaseID {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showWelcomeTour = true
                }
            }
        }
#if os(macOS)
        .background(
            WindowAccessor { window in
                updateWindowRegistration(window)
            }
            .frame(width: 0, height: 0)
        )
        .onDisappear {
            completionDebounceTask?.cancel()
            completionTask?.cancel()
            lastCompletionTriggerSignature = ""
            pendingHighlightRefresh?.cancel()
            completionCache.removeAll(keepingCapacity: false)
            if let number = hostWindowNumber {
                WindowViewModelRegistry.shared.unregister(windowNumber: number)
            }
        }
#endif
    }

    private func scheduleHighlightRefresh(delay: TimeInterval = 0.05) {
        pendingHighlightRefresh?.cancel()
        let work = DispatchWorkItem {
            highlightRefreshToken &+= 1
        }
        pendingHighlightRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

#if !os(macOS)
    private func shouldThrottleHeavyEditorFeatures(in nsText: NSString? = nil) -> Bool {
        if largeFileModeEnabled { return true }
        let length = nsText?.length ?? (currentContentBinding.wrappedValue as NSString).length
        return length >= 120_000
    }
#endif

    private struct ModalPresentationModifier: ViewModifier {
        let contentView: ContentView

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: contentView.$showFindReplace) {
                    FindReplacePanel(
                        findQuery: contentView.$findQuery,
                        replaceQuery: contentView.$replaceQuery,
                        useRegex: contentView.$findUsesRegex,
                        caseSensitive: contentView.$findCaseSensitive,
                        statusMessage: contentView.$findStatusMessage,
                        onFindNext: { contentView.findNext() },
                        onReplace: { contentView.replaceSelection() },
                        onReplaceAll: { contentView.replaceAll() }
                    )
#if canImport(UIKit)
                    .frame(maxWidth: 420)
#if os(iOS)
                    .presentationDetents([.height(280), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
#endif
#else
                    .frame(width: 420)
#endif
                }
#if canImport(UIKit)
                .sheet(isPresented: contentView.$showSettingsSheet) {
                    NeonSettingsView(
                        supportsOpenInTabs: false,
                        supportsTranslucency: false
                    )
                    .environmentObject(contentView.supportPurchaseManager)
                    .tint(.blue)
#if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
#endif
                }
#endif
#if os(iOS)
                .sheet(isPresented: contentView.$showCompactSidebarSheet) {
                    NavigationStack {
                        SidebarView(content: contentView.currentContent, language: contentView.currentLanguage)
                            .navigationTitle("Sidebar")
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        contentView.$showCompactSidebarSheet.wrappedValue = false
                                    }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
#endif
#if canImport(UIKit)
                .sheet(isPresented: contentView.$showProjectFolderPicker) {
                    ProjectFolderPicker(
                        onPick: { url in
                            contentView.setProjectFolder(url)
                            contentView.$showProjectFolderPicker.wrappedValue = false
                        },
                        onCancel: { contentView.$showProjectFolderPicker.wrappedValue = false }
                    )
                }
#endif
                .sheet(isPresented: contentView.$showQuickSwitcher) {
                    QuickFileSwitcherPanel(
                        query: contentView.$quickSwitcherQuery,
                        items: contentView.quickSwitcherItems,
                        onSelect: { contentView.selectQuickSwitcherItem($0) }
                    )
                }
                .sheet(isPresented: contentView.$showLanguageSetupPrompt) {
                    contentView.languageSetupSheet
                }
                .sheet(isPresented: contentView.$showWelcomeTour) {
                    WelcomeTourView {
                        contentView.$hasSeenWelcomeTourV1.wrappedValue = true
                        contentView.$welcomeTourSeenRelease.wrappedValue = WelcomeTourView.releaseID
                        contentView.$showWelcomeTour.wrappedValue = false
                    }
                }
                .sheet(isPresented: contentView.$showUpdateDialog) {
                    AppUpdaterDialog(isPresented: contentView.$showUpdateDialog)
                        .environmentObject(contentView.appUpdateManager)
                }
                .confirmationDialog("Save changes before closing?", isPresented: contentView.$showUnsavedCloseDialog, titleVisibility: .visible) {
                    Button("Save") { contentView.saveAndClosePendingTab() }
                    Button("Don't Save", role: .destructive) { contentView.discardAndClosePendingTab() }
                    Button("Cancel", role: .cancel) {
                        contentView.$pendingCloseTabID.wrappedValue = nil
                    }
                } message: {
                    if let pendingCloseTabID = contentView.pendingCloseTabID,
                       let tab = contentView.viewModel.tabs.first(where: { $0.id == pendingCloseTabID }) {
                        Text("\"\(tab.name)\" has unsaved changes.")
                    } else {
                        Text("This file has unsaved changes.")
                    }
                }
                .confirmationDialog("Clear editor content?", isPresented: contentView.$showClearEditorConfirmDialog, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) { contentView.clearEditorContent() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all text in the current editor.")
                }
#if canImport(UIKit)
                .fileImporter(
                    isPresented: contentView.$showIOSFileImporter,
                    allowedContentTypes: [.text, .plainText, .sourceCode, .json, .xml, .yaml],
                    allowsMultipleSelection: false
                ) { result in
                    contentView.handleIOSImportResult(result)
                }
                .fileExporter(
                    isPresented: contentView.$showIOSFileExporter,
                    document: contentView.iosExportDocument,
                    contentType: .plainText,
                    defaultFilename: contentView.iosExportFilename
                ) { result in
                    contentView.handleIOSExportResult(result)
                }
#endif
        }
    }

    private var shouldUseSplitView: Bool {
#if os(macOS)
        return viewModel.showSidebar && !viewModel.isBrainDumpMode
#else
        // Keep iPhone layout single-column to avoid horizontal clipping.
        return viewModel.showSidebar && !viewModel.isBrainDumpMode && horizontalSizeClass == .regular
#endif
    }

    private func applyStartupBehaviorIfNeeded() {
        guard !didApplyStartupBehavior else { return }

        if viewModel.tabs.contains(where: { $0.fileURL != nil }) {
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        // Restore last session first when enabled.
        if reopenLastSession {
            let paths = UserDefaults.standard.stringArray(forKey: "LastSessionFileURLs") ?? []
            let selectedPath = UserDefaults.standard.string(forKey: "LastSessionSelectedFileURL")
            let urls = paths.compactMap { URL(string: $0) }

            if !urls.isEmpty {
                viewModel.tabs.removeAll()
                viewModel.selectedTabID = nil

                for url in urls {
                    viewModel.openFile(url: url)
                }

                if let selectedPath, let selectedURL = URL(string: selectedPath) {
                    _ = viewModel.focusTabIfOpen(for: selectedURL)
                }

                if viewModel.tabs.isEmpty {
                    viewModel.addNewTab()
                }
            }
        }

        if openWithBlankDocument {
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        didApplyStartupBehavior = true
        persistSessionIfReady()
    }

    private func persistSessionIfReady() {
        guard didApplyStartupBehavior else { return }
        let urls = viewModel.tabs.compactMap { $0.fileURL?.absoluteString }
        UserDefaults.standard.set(urls, forKey: "LastSessionFileURLs")
        UserDefaults.standard.set(viewModel.selectedTab?.fileURL?.absoluteString, forKey: "LastSessionSelectedFileURL")
    }

    // Sidebar shows a lightweight table of contents (TOC) derived from the current document.
    @ViewBuilder
    var sidebarView: some View {
        if viewModel.showSidebar && !viewModel.isBrainDumpMode {
            SidebarView(content: currentContent,
                        language: currentLanguage)
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 600)
                .animation(.spring(), value: viewModel.showSidebar)
                .safeAreaInset(edge: .bottom) {
                    Divider()
                }
                .background(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
        } else {
            EmptyView()
        }
    }

    // Bindings that resolve to the active tab (if present) or fallback single-document state.
    var currentContentBinding: Binding<String> {
        if let tab = viewModel.selectedTab {
            return Binding(
                get: { tab.content },
                set: { newValue in viewModel.updateTabContent(tab: tab, content: newValue) }
            )
        } else {
            return $singleContent
        }
    }

    var currentLanguageBinding: Binding<String> {
        if let selectedID = viewModel.selectedTabID, let idx = viewModel.tabs.firstIndex(where: { $0.id == selectedID }) {
            return Binding(
                get: { viewModel.tabs[idx].language },
                set: { newValue in viewModel.tabs[idx].language = newValue }
            )
        } else {
            return $singleLanguage
        }
    }

    var currentLanguagePickerBinding: Binding<String> {
        Binding(
            get: { currentLanguageBinding.wrappedValue },
            set: { newValue in
                if let tab = viewModel.selectedTab {
                    viewModel.updateTabLanguage(tab: tab, language: newValue)
                } else {
                    singleLanguage = newValue
                }
            }
        )
    }

    var currentContent: String { currentContentBinding.wrappedValue }
    var currentLanguage: String { currentLanguageBinding.wrappedValue }


    func toggleAutoCompletion() {
        let willEnable = !isAutoCompletionEnabled
        if willEnable && viewModel.isBrainDumpMode {
            viewModel.isBrainDumpMode = false
            UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
        }
        isAutoCompletionEnabled.toggle()
        syncAppleCompletionAvailability()
        if willEnable {
            maybePromptForLanguageSetup()
        }
    }

    private func maybePromptForLanguageSetup() {
        guard currentLanguage == "plain" else { return }
        languagePromptSelection = currentLanguage == "plain" ? "plain" : currentLanguage
        languagePromptInsertTemplate = false
        showLanguageSetupPrompt = true
    }

    private func syncAppleCompletionAvailability() {
#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
        // Keep Apple Foundation Models in sync with the completion master toggle.
        AppleFM.isEnabled = isAutoCompletionEnabled
#endif
    }

    private func applyLanguageSelection(language: String, insertTemplate: Bool) {
        let contentIsEmpty = currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let tab = viewModel.selectedTab {
            viewModel.updateTabLanguage(tab: tab, language: language)
            if insertTemplate, contentIsEmpty, let template = starterTemplate(for: language) {
                viewModel.updateTabContent(tab: tab, content: template)
            }
        } else {
            singleLanguage = language
            if insertTemplate, contentIsEmpty, let template = starterTemplate(for: language) {
                singleContent = template
            }
        }
    }

    private var languageSetupSheet: some View {
        let contentIsEmpty = currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canInsertTemplate = contentIsEmpty

        return VStack(alignment: .leading, spacing: 16) {
            Text("Choose a language for code completion")
                .font(.headline)
            Text("You can change this later from the Language picker.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Language", selection: $languagePromptSelection) {
                ForEach(languageOptions, id: \.self) { lang in
                    Text(languageLabel(for: lang)).tag(lang)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)

            if canInsertTemplate {
                Toggle("Insert starter template", isOn: $languagePromptInsertTemplate)
            }

            HStack {
                Button("Use Plain Text") {
                    applyLanguageSelection(language: "plain", insertTemplate: false)
                    showLanguageSetupPrompt = false
                }
                Spacer()
                Button("Use Selected Language") {
                    applyLanguageSelection(language: languagePromptSelection, insertTemplate: languagePromptInsertTemplate)
                    showLanguageSetupPrompt = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
    }

    private var languageOptions: [String] {
        ["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"]
    }

    private func languageLabel(for lang: String) -> String {
        switch lang {
        case "php": return "PHP"
        case "cobol": return "COBOL"
        case "dotenv": return "Dotenv"
        case "proto": return "Proto"
        case "graphql": return "GraphQL"
        case "rst": return "reStructuredText"
        case "nginx": return "Nginx"
        case "objective-c": return "Objective-C"
        case "csharp": return "C#"
        case "c": return "C"
        case "cpp": return "C++"
        case "json": return "JSON"
        case "xml": return "XML"
        case "yaml": return "YAML"
        case "toml": return "TOML"
        case "csv": return "CSV"
        case "ini": return "INI"
        case "sql": return "SQL"
        case "vim": return "Vim"
        case "log": return "Log"
        case "ipynb": return "Jupyter Notebook"
        case "html": return "HTML"
        case "expressionengine": return "ExpressionEngine"
        case "css": return "CSS"
        case "standard": return "Standard"
        default: return lang.capitalized
        }
    }

    private func starterTemplate(for language: String) -> String? {
        if let override = UserDefaults.standard.string(forKey: templateOverrideKey(for: language)),
           !override.isEmpty {
            return override
        }
        switch language {
        case "swift":
            return "import Foundation\n\n// TODO: Add code here\n"
        case "python":
            return "def main():\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n"
        case "javascript":
            return "\"use strict\";\n\nfunction main() {\n  // TODO: Add code here\n}\n\nmain();\n"
        case "typescript":
            return "function main(): void {\n  // TODO: Add code here\n}\n\nmain();\n"
        case "java":
            return "public class Main {\n    public static void main(String[] args) {\n        // TODO: Add code here\n    }\n}\n"
        case "kotlin":
            return "fun main() {\n    // TODO: Add code here\n}\n"
        case "go":
            return "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello\")\n}\n"
        case "ruby":
            return "def main\n  # TODO: Add code here\nend\n\nmain\n"
        case "rust":
            return "fn main() {\n    // TODO: Add code here\n}\n"
        case "php":
            return "<?php\n\n// TODO: Add code here\n"
        case "cobol":
            return "       IDENTIFICATION DIVISION.\n       PROGRAM-ID. MAIN.\n\n       PROCEDURE DIVISION.\n           DISPLAY \"TODO\".\n           STOP RUN.\n"
        case "dotenv":
            return "# TODO=VALUE\n"
        case "proto":
            return "syntax = \"proto3\";\n\npackage example;\n\nmessage Example {\n  string id = 1;\n}\n"
        case "graphql":
            return "type Query {\n  hello: String\n}\n"
        case "rst":
            return "Title\n=====\n\nWrite here.\n"
        case "nginx":
            return "server {\n    listen 80;\n    server_name example.com;\n\n    location / {\n        return 200 \"TODO\";\n    }\n}\n"
        case "c":
            return "#include <stdio.h>\n\nint main(void) {\n    // TODO: Add code here\n    return 0;\n}\n"
        case "cpp":
            return "#include <iostream>\n\nint main() {\n    // TODO: Add code here\n    return 0;\n}\n"
        case "csharp":
            return "using System;\n\npublic class Program {\n    public static void Main(string[] args) {\n        // TODO: Add code here\n    }\n}\n"
        case "objective-c":
            return "#import <Foundation/Foundation.h>\n\nint main(int argc, const char * argv[]) {\n    @autoreleasepool {\n        // TODO: Add code here\n    }\n    return 0;\n}\n"
        case "html":
            return "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n  <title>Document</title>\n</head>\n<body>\n\n</body>\n</html>\n"
        case "expressionengine":
            return "{exp:channel:entries channel=\"news\" limit=\"10\"}\n  <article>\n    <h2>{title}</h2>\n    <p>{summary}</p>\n  </article>\n{/exp:channel:entries}\n"
        case "css":
            return "/* TODO: Add styles here */\n\nbody {\n  margin: 0;\n}\n"
        case "sql":
            return "-- TODO: Add queries here\n"
        case "markdown":
            return "# Title\n\nWrite here.\n"
        case "yaml":
            return "# TODO: Add config here\n"
        case "json":
            return "{\n  \"todo\": true\n}\n"
        case "xml":
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n  <todo>true</todo>\n</root>\n"
        case "toml":
            return "# TODO = \"value\"\n"
        case "csv":
            return "col1,col2\nvalue1,value2\n"
        case "ini":
            return "[section]\nkey=value\n"
        case "vim":
            return "\" TODO: Add vim config here\n"
        case "log":
            return "INFO: TODO\n"
        case "ipynb":
            return "{\n  \"cells\": [],\n  \"metadata\": {},\n  \"nbformat\": 4,\n  \"nbformat_minor\": 5\n}\n"
        case "bash":
            return "#!/usr/bin/env bash\n\nset -euo pipefail\n\n# TODO: Add script here\n"
        case "zsh":
            return "#!/usr/bin/env zsh\n\nset -euo pipefail\n\n# TODO: Add script here\n"
        case "powershell":
            return "# TODO: Add script here\n"
        case "standard":
            return "// TODO: Add code here\n"
        case "plain":
            return "TODO\n"
        default:
            return "TODO\n"
        }
    }

    private func templateOverrideKey(for language: String) -> String {
        "TemplateOverride_\(language)"
    }

    func insertTemplateForCurrentLanguage() {
        let language = currentLanguage
        guard let template = starterTemplate(for: language) else { return }

        if let tab = viewModel.selectedTab {
            let content = tab.content
            let updated: String
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated = template
            } else {
                updated = content + (content.hasSuffix("\n") ? "\n" : "\n\n") + template
            }
            viewModel.updateTabContent(tab: tab, content: updated)
        } else {
            if singleContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                singleContent = template
            } else {
                singleContent = singleContent + (singleContent.hasSuffix("\n") ? "\n" : "\n\n") + template
            }
        }
    }

    private func detectLanguageWithAppleIntelligence(_ text: String) async -> String {
        // Supported languages in our picker
        let supported = ["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "objective-c", "csharp", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"]

        #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
        // Attempt a lightweight model-based detection via AppleIntelligenceAIClient if available
        do {
            let client = AppleIntelligenceAIClient()
            var response = ""
            for await chunk in client.streamSuggestions(prompt: "Detect the programming or markup language of the following snippet and answer with one of: \(supported.joined(separator: ", ")). If none match, reply with 'swift'.\n\nSnippet:\n\n\(text)\n\nAnswer:") {
                response += chunk
            }
            let detectedRaw = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
            if let match = supported.first(where: { detectedRaw.contains($0) }) {
                return match
            }
        }
        #endif

        // Heuristic fallback
        let lower = text.lowercased()
        // Normalize common C# indicators to "csharp" to ensure the picker has a matching tag
        if lower.contains("c#") || lower.contains("c sharp") || lower.range(of: #"\bcs\b"#, options: .regularExpression) != nil || lower.contains(".cs") {
            return "csharp"
        }
        if lower.contains("<?php") || lower.contains("<?=") || lower.contains("$this->") || lower.contains("$_get") || lower.contains("$_post") || lower.contains("$_server") {
            return "php"
        }
        if lower.range(of: #"\{/?exp:[A-Za-z0-9_:-]+[^}]*\}"#, options: .regularExpression) != nil ||
            lower.range(of: #"\{if(?::elseif)?\b[^}]*\}|\{\/if\}|\{:else\}"#, options: .regularExpression) != nil ||
            lower.range(of: #"\{!--[\s\S]*?--\}"#, options: .regularExpression) != nil {
            return "expressionengine"
        }
        if lower.contains("syntax = \"proto") || lower.contains("message ") || (lower.contains("enum ") && lower.contains("rpc ")) {
            return "proto"
        }
        if lower.contains("type query") || lower.contains("schema {") || (lower.contains("interface ") && lower.contains("implements ")) {
            return "graphql"
        }
        if lower.contains("server {") || lower.contains("http {") || lower.contains("location /") {
            return "nginx"
        }
        if lower.contains(".. code-block::") || lower.contains(".. toctree::") || (lower.contains("::") && lower.contains("\n====")) {
            return "rst"
        }
        if lower.contains("\n") && lower.range(of: #"(?m)^[A-Z_][A-Z0-9_]*=.*$"#, options: .regularExpression) != nil {
            return "dotenv"
        }
        if lower.contains("identification division") || lower.contains("procedure division") || lower.contains("working-storage section") || lower.contains("environment division") {
            return "cobol"
        }
        if text.contains(",") && text.contains("\n") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if lines.count >= 2 {
                let commaCounts = lines.prefix(6).map { line in line.filter { $0 == "," }.count }
                if let firstCount = commaCounts.first, firstCount > 0 && commaCounts.dropFirst().allSatisfy({ $0 == firstCount || abs($0 - firstCount) <= 1 }) {
                    return "csv"
                }
            }
        }
        // C# strong heuristic
        if lower.contains("using system") || lower.contains("namespace ") || lower.contains("public class") || lower.contains("public static void main") || lower.contains("static void main") || lower.contains("console.writeline") || lower.contains("console.readline") || lower.contains("class program") || lower.contains("get; set;") || lower.contains("list<") || lower.contains("dictionary<") || lower.contains("ienumerable<") || lower.range(of: #"\[[A-Za-z_][A-Za-z0-9_]*\]"#, options: .regularExpression) != nil {
            return "csharp"
        }
        if lower.contains("import swift") || lower.contains("struct ") || lower.contains("func ") {
            return "swift"
        }
        if lower.contains("def ") || (lower.contains("class ") && lower.contains(":")) {
            return "python"
        }
        if lower.contains("function ") || lower.contains("const ") || lower.contains("let ") || lower.contains("=>") {
            return "javascript"
        }
        // XML
        if lower.contains("<?xml") || (lower.contains("</") && lower.contains(">")) {
            return "xml"
        }
        // YAML
        if lower.contains(": ") && (lower.contains("- ") || lower.contains("\n  ")) && !lower.contains(";") {
            return "yaml"
        }
        // TOML / INI
        if lower.range(of: #"^\[[^\]]+\]"#, options: [.regularExpression, .anchored]) != nil || (lower.contains("=") && lower.contains("\n[")) {
            return lower.contains("toml") ? "toml" : "ini"
        }
        // SQL
        if lower.range(of: #"\b(select|insert|update|delete|create\s+table|from|where|join)\b"#, options: .regularExpression) != nil {
            return "sql"
        }
        // Go
        if lower.contains("package ") && lower.contains("func ") {
            return "go"
        }
        // Java
        if lower.contains("public class") || lower.contains("public static void main") {
            return "java"
        }
        // Kotlin
        if (lower.contains("fun ") || lower.contains("val ")) || (lower.contains("var ") && lower.contains(":")) {
            return "kotlin"
        }
        // TypeScript
        if lower.contains("interface ") || (lower.contains("type ") && lower.contains(":")) || lower.contains(": string") {
            return "typescript"
        }
        // Ruby
        if lower.contains("def ") || (lower.contains("end") && lower.contains("class ")) {
            return "ruby"
        }
        // Rust
        if lower.contains("fn ") || lower.contains("let mut ") || lower.contains("pub struct") {
            return "rust"
        }
        // Objective-C
        if lower.contains("@interface") || lower.contains("@implementation") || lower.contains("#import ") {
            return "objective-c"
        }
        // INI
        if lower.range(of: #"^;.*$"#, options: .regularExpression) != nil || lower.range(of: #"^\w+\s*=\s*.*$"#, options: .regularExpression) != nil {
            return "ini"
        }
        if lower.contains("<html") || lower.contains("<div") || lower.contains("</") {
            return "html"
        }
        // Stricter C-family detection to avoid misclassifying C#
        if lower.contains("#include") || lower.range(of: #"^\s*(int|void)\s+main\s*\("#, options: .regularExpression) != nil {
            return "cpp"
        }
        if lower.contains("class ") && (lower.contains("::") || lower.contains("template<")) {
            return "cpp"
        }
        if lower.contains(";") && lower.contains(":") && lower.contains("{") && lower.contains("}") && lower.contains("color:") {
            return "css"
        }
        // Shell detection (bash/zsh)
        if lower.contains("#!/bin/bash") || lower.contains("#!/usr/bin/env bash") || lower.contains("declare -a") || lower.contains("[[ ") || lower.contains(" ]] ") || lower.contains("$(") {
            return "bash"
        }
        if lower.contains("#!/bin/zsh") || lower.contains("#!/usr/bin/env zsh") || lower.contains("typeset ") || lower.contains("autoload -Uz") || lower.contains("setopt ") {
            return "zsh"
        }
        // Generic POSIX sh fallback
        if lower.contains("#!/bin/sh") || lower.contains("#!/usr/bin/env sh") || lower.contains(" fi") || lower.contains(" do") || lower.contains(" done") || lower.contains(" esac") {
            return "bash"
        }
        // PowerShell detection
        if lower.contains("write-host") || lower.contains("param(") || lower.contains("$psversiontable") || lower.range(of: #"\b(Get|Set|New|Remove|Add|Clear|Write)-[A-Za-z]+\b"#, options: .regularExpression) != nil {
            return "powershell"
        }
        return "standard"
    }

    ///MARK: - Main Editor Stack
    var editorView: some View {
        let shouldThrottleFeatures = shouldThrottleHeavyEditorFeatures()
        let effectiveBracketHighlight = highlightMatchingBrackets && !shouldThrottleFeatures
        let effectiveScopeGuides = showScopeGuides && !shouldThrottleFeatures
        let effectiveScopeBackground = highlightScopeBackground && !shouldThrottleFeatures
        let content = HStack(spacing: 0) {
            VStack(spacing: 0) {
                if !viewModel.isBrainDumpMode {
                    tabBarView
                }
#if os(macOS)
                if showBracketHelperBarMac {
                    bracketHelperBar
                }
#endif

                // Single editor (no TabView)
                CustomTextEditor(
                    text: currentContentBinding,
                    language: currentLanguage,
                    colorScheme: colorScheme,
                    fontSize: editorFontSize,
                    isLineWrapEnabled: $viewModel.isLineWrapEnabled,
                    isLargeFileMode: largeFileModeEnabled,
                    translucentBackgroundEnabled: enableTranslucentWindow,
                    showLineNumbers: showLineNumbers,
                    showInvisibleCharacters: false,
                    highlightCurrentLine: highlightCurrentLine,
                    highlightMatchingBrackets: effectiveBracketHighlight,
                    showScopeGuides: effectiveScopeGuides,
                    highlightScopeBackground: effectiveScopeBackground,
                    indentStyle: indentStyle,
                    indentWidth: indentWidth,
                    autoIndentEnabled: autoIndentEnabled,
                    autoCloseBracketsEnabled: autoCloseBracketsEnabled,
                    highlightRefreshToken: highlightRefreshToken
                )
                .id(currentLanguage)
                .frame(maxWidth: viewModel.isBrainDumpMode ? 920 : .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, viewModel.isBrainDumpMode ? 24 : 0)
                .padding(.vertical, viewModel.isBrainDumpMode ? 40 : 0)
                .background(
                    Group {
                        if enableTranslucentWindow {
                            Color.clear.background(.ultraThinMaterial)
                        } else {
                            Color.clear
                        }
                    }
                )

                if !viewModel.isBrainDumpMode {
                    wordCountView
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: viewModel.isBrainDumpMode ? .top : .topLeading
            )

            if showProjectStructureSidebar && !viewModel.isBrainDumpMode {
                Divider()
                ProjectStructureSidebarView(
                    rootFolderURL: projectRootFolderURL,
                    nodes: projectTreeNodes,
                    selectedFileURL: viewModel.selectedTab?.fileURL,
                    translucentBackgroundEnabled: enableTranslucentWindow,
                    onOpenFile: { openFileFromToolbar() },
                    onOpenFolder: { openProjectFolder() },
                    onOpenProjectFile: { openProjectFile(url: $0) },
                    onRefreshTree: { refreshProjectTree() }
                )
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            }
        }
        .background(
            Group {
                if viewModel.isBrainDumpMode && enableTranslucentWindow {
                    Color.clear.background(.ultraThinMaterial)
                } else {
                    Color.clear
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        let withEvents = withTypingEvents(
            withCommandEvents(
                withBaseEditorEvents(content)
            )
        )

        return withEvents
        .onChange(of: enableTranslucentWindow) { _, newValue in
            applyWindowTranslucency(newValue)
            // Force immediate recolor when translucency changes so syntax highlighting stays visible.
            highlightRefreshToken &+= 1
        }
        .toolbar {
            editorToolbarContent
        }
        .overlay(alignment: Alignment.topTrailing) {
            if droppedFileLoadInProgress {
                HStack(spacing: 8) {
                    if droppedFileProgressDeterminate {
                        ProgressView(value: droppedFileLoadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                    } else {
                        ProgressView()
                            .frame(width: 16)
                    }
                    Text(droppedFileProgressDeterminate ? "\(droppedFileLoadLabel) \(importProgressPercentText)" : "\(droppedFileLoadLabel) Loading…")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .padding(.top, viewModel.isBrainDumpMode ? 12 : 50)
                .padding(.trailing, 12)
            }
        }
#if os(macOS)
        .toolbarBackground(AnyShapeStyle(Color(nsColor: .windowBackgroundColor)), for: ToolbarPlacement.windowToolbar)
        .toolbarBackgroundVisibility(enableTranslucentWindow ? .hidden : .visible, for: ToolbarPlacement.windowToolbar)
#else
        .toolbarBackground(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.systemBackground)), for: ToolbarPlacement.navigationBar)
#endif
    }

    // Status line: caret location + live word count from the view model.
    @ViewBuilder
    var wordCountView: some View {
        HStack(spacing: 10) {
            if droppedFileLoadInProgress {
                HStack(spacing: 8) {
                    if droppedFileProgressDeterminate {
                        ProgressView(value: droppedFileLoadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 130)
                    } else {
                        ProgressView()
                            .frame(width: 18)
                    }
                    Text(droppedFileProgressDeterminate ? "\(droppedFileLoadLabel) \(importProgressPercentText)" : "\(droppedFileLoadLabel) Loading…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
            }

            if largeFileModeEnabled {
                Text("Large File Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                    )
            }
            Spacer()
            Text(largeFileModeEnabled
                 ? "\(caretStatus)\(vimStatusSuffix)"
                 : "\(caretStatus) • Words: \(viewModel.wordCount(for: currentContent))\(vimStatusSuffix)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.trailing, 16)
        }
        .background(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
    }

    @ViewBuilder
    var tabBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.tabs) { tab in
                    HStack(spacing: 6) {
                        Button {
                            viewModel.selectedTabID = tab.id
                        } label: {
                            Text(tab.name + (tab.isDirty ? " •" : ""))
                                .lineLimit(1)
                                .font(.system(size: 12, weight: viewModel.selectedTabID == tab.id ? .semibold : .regular))
                        }
                        .buttonStyle(.plain)

                        Button {
                            requestCloseTab(tab)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("Close \(tab.name)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(viewModel.selectedTabID == tab.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
#if os(macOS)
        .background(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
#else
        .background(enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.systemBackground)))
#endif
    }

    private var vimStatusSuffix: String {
#if os(macOS)
        guard vimModeEnabled else { return " • Vim: OFF" }
        return vimInsertMode ? " • Vim: INSERT" : " • Vim: NORMAL"
#else
        return ""
#endif
    }

    private var importProgressPercentText: String {
        let clamped = min(max(droppedFileLoadProgress, 0), 1)
        if clamped > 0, clamped < 0.01 { return "1%" }
        return "\(Int(clamped * 100))%"
    }

    private var quickSwitcherItems: [QuickFileSwitcherPanel.Item] {
        var items: [QuickFileSwitcherPanel.Item] = []
        let fileURLSet = Set(viewModel.tabs.compactMap { $0.fileURL?.standardizedFileURL.path })

        for tab in viewModel.tabs {
            let subtitle = tab.fileURL?.path ?? "Open tab"
            items.append(
                QuickFileSwitcherPanel.Item(
                    id: "tab:\(tab.id.uuidString)",
                    title: tab.name,
                    subtitle: subtitle
                )
            )
        }

        for url in projectFileURLs(from: projectTreeNodes) {
            let standardized = url.standardizedFileURL.path
            if fileURLSet.contains(standardized) { continue }
            items.append(
                QuickFileSwitcherPanel.Item(
                    id: "file:\(standardized)",
                    title: url.lastPathComponent,
                    subtitle: standardized
                )
            )
        }

        let query = quickSwitcherQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Array(items.prefix(300)) }
        return Array(
            items.filter {
                $0.title.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
            }
            .prefix(300)
        )
    }

    private func selectQuickSwitcherItem(_ item: QuickFileSwitcherPanel.Item) {
        if item.id.hasPrefix("tab:") {
            let raw = String(item.id.dropFirst(4))
            if let id = UUID(uuidString: raw) {
                viewModel.selectedTabID = id
            }
            return
        }
        if item.id.hasPrefix("file:") {
            let path = String(item.id.dropFirst(5))
            openProjectFile(url: URL(fileURLWithPath: path))
        }
    }

}
