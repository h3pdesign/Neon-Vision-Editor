// ContentView.swift
// Main SwiftUI container for Neon Vision Editor. Hosts the single-document editor UI,
// toolbar actions, AI integration, syntax highlighting, line numbers, and sidebar TOC.

///MARK: - Imports
import SwiftUI
import Foundation
import Observation
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

#if os(macOS)
private final class WindowCloseConfirmationDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) weak var forwardedDelegate: NSWindowDelegate?
    var shouldConfirm: (() -> Bool)?
    var hasDirtyTabs: (() -> Bool)?
    var saveAllDirtyTabs: (() -> Bool)?
    var dialogTitle: (() -> String)?
    var dialogMessage: (() -> String)?

    private var isPromptInFlight = false
    private var allowNextClose = false

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (forwardedDelegate?.responds(to: selector) ?? false)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwardedDelegate?.responds(to: selector) == true {
            return forwardedDelegate
        }
        return super.forwardingTarget(for: selector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowNextClose {
            allowNextClose = false
            return forwardedDelegate?.windowShouldClose?(sender) ?? true
        }

        let needsPrompt = shouldConfirm?() == true && hasDirtyTabs?() == true
        if !needsPrompt {
            return forwardedDelegate?.windowShouldClose?(sender) ?? true
        }

        if isPromptInFlight {
            return false
        }
        isPromptInFlight = true

        let alert = NSAlert()
        alert.messageText = dialogTitle?() ?? "Save changes before closing?"
        alert.informativeText = dialogMessage?() ?? "One or more tabs have unsaved changes."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            self.isPromptInFlight = false
            switch response {
            case .alertFirstButtonReturn:
                if self.saveAllDirtyTabs?() == true {
                    self.allowNextClose = true
                    sender.performClose(nil)
                }
            case .alertSecondButtonReturn:
                self.allowNextClose = true
                sender.performClose(nil)
            default:
                break
            }
        }
        return false
    }
}
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
    enum StartupBehavior {
        case standard
        case forceBlankDocument
    }

    enum ProjectNavigatorPlacement: String, CaseIterable, Identifiable {
        case leading
        case trailing

        var id: String { rawValue }
    }

    enum PerformancePreset: String, CaseIterable, Identifiable {
        case balanced
        case largeFiles
        case battery

        var id: String { rawValue }
    }

    enum DelimitedViewMode: String, CaseIterable, Identifiable {
        case table
        case text

        var id: String { rawValue }
    }

    struct DelimitedTableSnapshot: Sendable {
        let header: [String]
        let rows: [[String]]
        let totalRows: Int
        let displayedRows: Int
        let truncated: Bool
    }

    let startupBehavior: StartupBehavior

    init(startupBehavior: StartupBehavior = .standard) {
        self.startupBehavior = startupBehavior
    }

    private enum EditorPerformanceThresholds {
        static let largeFileBytes = 12_000_000
        static let largeFileBytesHTMLCSV = 4_000_000
        static let largeFileBytesMobile = 8_000_000
        static let largeFileBytesHTMLCSVMobile = 3_000_000
        static let heavyFeatureUTF16Length = 450_000
        static let largeFileLineBreaks = 40_000
        static let largeFileLineBreaksHTMLCSV = 15_000
        static let largeFileLineBreaksMobile = 25_000
        static let largeFileLineBreaksHTMLCSVMobile = 10_000
    }
    private static let completionSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "InlineCompletion")

    private struct CompletionCacheEntry {
        let suggestion: String
        let createdAt: Date
    }

    private struct SavedDraftTabSnapshot: Codable {
        let name: String
        let content: String
        let language: String
        let fileURLString: String?
    }

    private struct SavedDraftSnapshot: Codable {
        let tabs: [SavedDraftTabSnapshot]
        let selectedIndex: Int?
        let createdAt: Date
    }

    // Environment-provided view model and theme/error bindings
    @Environment(EditorViewModel.self) var viewModel
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
    @State var editorExternalMutationRevision: Int = 0

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
#if os(iOS)
    @AppStorage("EnableTranslucentWindow") var enableTranslucentWindow: Bool = true
#else
    @AppStorage("EnableTranslucentWindow") var enableTranslucentWindow: Bool = false
#endif
#if os(iOS)
    @State private var previousKeyboardAccessoryVisibility: Bool? = nil
    @State private var markdownPreviewSheetDetent: PresentationDetent = .medium
#endif
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif

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
    @State var showCompactProjectSidebarSheet: Bool = false
    @State var projectRootFolderURL: URL? = nil
    @State var projectTreeNodes: [ProjectTreeNode] = []
    @State var projectTreeRefreshGeneration: Int = 0
    @AppStorage("SettingsShowSupportedProjectFilesOnly") var showSupportedProjectFilesOnly: Bool = true
    @State var projectOverrideIndentWidth: Int? = nil
    @State var projectOverrideLineWrapEnabled: Bool? = nil
    @State var showProjectFolderPicker: Bool = false
    @State var projectFolderSecurityURL: URL? = nil
    @State var pendingCloseTabID: UUID? = nil
    @State var showUnsavedCloseDialog: Bool = false
    @State var showCloseAllTabsDialog: Bool = false
    @State private var showExternalConflictDialog: Bool = false
    @State private var showExternalConflictCompareSheet: Bool = false
    @State private var externalConflictCompareSnapshot: EditorViewModel.ExternalFileComparisonSnapshot?
    @State var showClearEditorConfirmDialog: Bool = false
    @State var showIOSFileImporter: Bool = false
    @State var showIOSFileExporter: Bool = false
    @State var showUnsupportedFileAlert: Bool = false
    @State var unsupportedFileName: String = ""
    @State var iosExportDocument: PlainTextDocument = PlainTextDocument(text: "")
    @State var iosExportFilename: String = "Untitled.txt"
    @State var iosExportTabID: UUID? = nil
    @State var showQuickSwitcher: Bool = false
    @State var quickSwitcherQuery: String = ""
    @State var quickSwitcherProjectFileURLs: [URL] = []
    @State private var quickSwitcherRecentItemIDs: [String] = []
    @State var showFindInFiles: Bool = false
    @State var findInFilesQuery: String = ""
    @State var findInFilesCaseSensitive: Bool = false
    @State var findInFilesResults: [FindInFilesMatch] = []
    @State var findInFilesStatusMessage: String = ""
    @State private var findInFilesTask: Task<Void, Never>?
    @State private var statusWordCount: Int = 0
    @State private var wordCountTask: Task<Void, Never>?
    @State var vimModeEnabled: Bool = UserDefaults.standard.bool(forKey: "EditorVimModeEnabled")
    @State var vimInsertMode: Bool = true
    @State var droppedFileLoadInProgress: Bool = false
    @State var droppedFileProgressDeterminate: Bool = true
    @State var droppedFileLoadProgress: Double = 0
    @State var droppedFileLoadLabel: String = ""
    @State var largeFileModeEnabled: Bool = false
    @SceneStorage("ProjectSidebarWidth") private var projectSidebarWidth: Double = 260
    @State private var projectSidebarResizeStartWidth: CGFloat? = nil
    @State private var delimitedViewMode: DelimitedViewMode = .table
    @State private var delimitedTableSnapshot: DelimitedTableSnapshot? = nil
    @State private var isBuildingDelimitedTable: Bool = false
    @State private var delimitedTableStatus: String = ""
    @State private var delimitedParseTask: Task<Void, Never>? = nil
    @AppStorage("SettingsProjectNavigatorPlacement") var projectNavigatorPlacementRaw: String = ProjectNavigatorPlacement.trailing.rawValue
    @AppStorage("SettingsPerformancePreset") var performancePresetRaw: String = PerformancePreset.balanced.rawValue
#if os(iOS)
    @AppStorage("SettingsForceLargeFileMode") var forceLargeFileMode: Bool = false
    @AppStorage("SettingsShowKeyboardAccessoryBarIOS") var showKeyboardAccessoryBarIOS: Bool = false
    @AppStorage("SettingsShowBottomActionBarIOS") var showBottomActionBarIOS: Bool = true
    @AppStorage("SettingsUseLiquidGlassToolbarIOS") var shouldUseLiquidGlass: Bool = true
    @AppStorage("SettingsToolbarIconsBlueIOS") var toolbarIconsBlueIOS: Bool = false
#endif
    @AppStorage("HasSeenWelcomeTourV1") var hasSeenWelcomeTourV1: Bool = false
    @AppStorage("WelcomeTourSeenRelease") var welcomeTourSeenRelease: String = ""
    @State var showWelcomeTour: Bool = false
#if os(macOS)
    @State private var hostWindowNumber: Int? = nil
    @AppStorage("ShowBracketHelperBarMac") var showBracketHelperBarMac: Bool = false
    @State private var windowCloseConfirmationDelegate: WindowCloseConfirmationDelegate? = nil
#endif
    @State var showMarkdownPreviewPane: Bool = false
#if os(macOS)
    @AppStorage("MarkdownPreviewTemplateMac") var markdownPreviewTemplateRaw: String = "default"
#elseif os(iOS)
    @AppStorage("MarkdownPreviewTemplateIOS") var markdownPreviewTemplateRaw: String = "default"
#endif
    @State private var showLanguageSetupPrompt: Bool = false
    @State private var languagePromptSelection: String = "plain"
    @State private var languagePromptInsertTemplate: Bool = false
    @State private var showLanguageSearchSheet: Bool = false
    @State private var languageSearchQuery: String = ""
    @State private var whitespaceInspectorMessage: String? = nil
    @State private var didApplyStartupBehavior: Bool = false
    @State private var didRunInitialWindowLayoutSetup: Bool = false
    @State private var pendingLargeFileModeReevaluation: DispatchWorkItem? = nil
    @State private var recoverySnapshotIdentifier: String = UUID().uuidString
    @State private var lastCaretLocation: Int = 0
    @State private var sessionCaretByFileURL: [String: Int] = [:]
    private let quickSwitcherRecentsDefaultsKey = "QuickSwitcherRecentItemsV1"

#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
    var appleModelAvailable: Bool { true }
#else
    var appleModelAvailable: Bool { false }
#endif

    var activeProviderName: String {
        let trimmed = lastProviderUsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Apple" {
            return selectedModel.displayName
        }
        return trimmed
    }

    private var projectNavigatorPlacement: ProjectNavigatorPlacement {
        ProjectNavigatorPlacement(rawValue: projectNavigatorPlacementRaw) ?? .trailing
    }

    private var performancePreset: PerformancePreset {
        PerformancePreset(rawValue: performancePresetRaw) ?? .balanced
    }

    private var clampedProjectSidebarWidth: CGFloat {
        let clamped = min(max(projectSidebarWidth, 220), 520)
        return CGFloat(clamped)
    }

    private var isDelimitedFileLanguage: Bool {
        let lower = currentLanguage.lowercased()
        return lower == "csv" || lower == "tsv"
    }

    private var delimitedSeparator: Character {
        currentLanguage.lowercased() == "tsv" ? "\t" : ","
    }

    private var shouldShowDelimitedTable: Bool {
        isDelimitedFileLanguage && delimitedViewMode == .table
    }
#if os(macOS)
    private enum MacTranslucencyMode: String {
        case subtle
        case balanced
        case vibrant

        var material: Material {
            switch self {
            case .subtle, .balanced:
                return .thickMaterial
            case .vibrant:
                return .regularMaterial
            }
        }

        var opacity: Double {
            switch self {
            case .subtle: return 0.98
            case .balanced: return 0.93
            case .vibrant: return 0.90
            }
        }
    }

    private var macTranslucencyMode: MacTranslucencyMode {
        MacTranslucencyMode(rawValue: macTranslucencyModeRaw) ?? .balanced
    }

    private let bracketHelperTokens: [String] = ["(", ")", "{", "}", "[", "]", "<", ">", "'", "\"", "`", "()", "{}", "[]", "\"\"", "''"]
    private var macUnifiedTranslucentMaterialStyle: AnyShapeStyle {
        AnyShapeStyle(macTranslucencyMode.material.opacity(macTranslucencyMode.opacity))
    }
    private var macChromeBackgroundStyle: AnyShapeStyle {
        if enableTranslucentWindow {
            return macUnifiedTranslucentMaterialStyle
        }
        return AnyShapeStyle(Color(nsColor: .textBackgroundColor))
    }
#elseif os(iOS)
    var primaryGlassMaterial: Material { colorScheme == .dark ? .regularMaterial : .ultraThinMaterial }
    var toolbarFallbackColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.34) : Color.white.opacity(0.86)
    }
    private var iOSNonTranslucentSurfaceColor: Color {
        currentEditorTheme(colorScheme: colorScheme).background
    }
    private var useIOSUnifiedSolidSurfaces: Bool {
        !enableTranslucentWindow
    }
    var toolbarDensityScale: CGFloat { 1.0 }
    var toolbarDensityOpacity: Double { 1.0 }

    private var canShowMarkdownPreviewOnCurrentDevice: Bool {
        horizontalSizeClass == .regular
    }
#endif

    private var editorSurfaceBackgroundStyle: AnyShapeStyle {
#if os(macOS)
        if enableTranslucentWindow {
            return macUnifiedTranslucentMaterialStyle
        }
        return AnyShapeStyle(Color(nsColor: .textBackgroundColor))
#else
        if useIOSUnifiedSolidSurfaces {
            return AnyShapeStyle(iOSNonTranslucentSurfaceColor)
        }
        return enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear)
#endif
    }

    var canShowMarkdownPreviewPane: Bool {
#if os(iOS)
        true
#else
        true
#endif
    }

    private var canShowMarkdownPreviewSplitPane: Bool {
#if os(iOS)
        canShowMarkdownPreviewOnCurrentDevice
#else
        true
#endif
    }

#if os(iOS)
    private var shouldPresentMarkdownPreviewSheetOnIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone &&
        showMarkdownPreviewPane &&
        currentLanguage == "markdown" &&
        !brainDumpLayoutEnabled
    }

    private var markdownPreviewSheetPresentationBinding: Binding<Bool> {
        Binding(
            get: { shouldPresentMarkdownPreviewSheetOnIPhone },
            set: { isPresented in
                if !isPresented {
                    showMarkdownPreviewPane = false
                }
            }
        )
    }
#endif

    private var settingsSheetDetents: Set<PresentationDetent> {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [.fraction(0.96)]
        }
        return [.large]
#else
        return [.large]
#endif
    }

#if os(macOS)
    private var macTabBarStripHeight: CGFloat { 36 }
#endif

    private var useIPhoneUnifiedTopHost: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    private var tabBarLeadingPadding: CGFloat {
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Keep tabs clear of iPad window controls in narrow/multitasking layouts.
            return horizontalSizeClass == .compact ? 112 : 96
        }
#endif
        return 10
    }

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
        let length = nsText?.length ?? currentDocumentUTF16Length
        return length >= EditorPerformanceThresholds.heavyFeatureUTF16Length
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
        if message.contains("[Completion]") || message.contains("AI ") || message.contains("[AI]") {
            AIActivityLog.record(message, source: "Completion")
        }
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
        installWindowCloseConfirmationDelegate(window)
        if let number {
            WindowViewModelRegistry.shared.register(viewModel, for: number)
        }
    }

    private func saveAllDirtyTabsForWindowClose() -> Bool {
        let dirtyTabIDs = viewModel.tabs.filter(\.isDirty).map(\.id)
        guard !dirtyTabIDs.isEmpty else { return true }
        for tabID in dirtyTabIDs {
            guard viewModel.tabs.contains(where: { $0.id == tabID }) else { continue }
            viewModel.saveFile(tabID: tabID)
            guard let updated = viewModel.tabs.first(where: { $0.id == tabID }), !updated.isDirty else {
                return false
            }
        }
        return true
    }

    private func windowCloseDialogMessage() -> String {
        let dirtyCount = viewModel.tabs.filter(\.isDirty).count
        if dirtyCount <= 1 {
            return "You have unsaved changes in one tab."
        }
        return "You have unsaved changes in \(dirtyCount) tabs."
    }

    private func installWindowCloseConfirmationDelegate(_ window: NSWindow?) {
        guard let window else {
            windowCloseConfirmationDelegate = nil
            return
        }

        let delegate: WindowCloseConfirmationDelegate
        if let existing = windowCloseConfirmationDelegate {
            delegate = existing
        } else {
            delegate = WindowCloseConfirmationDelegate()
            windowCloseConfirmationDelegate = delegate
        }

        if window.delegate !== delegate {
            if let current = window.delegate, current !== delegate {
                delegate.forwardedDelegate = current
            }
            window.delegate = delegate
        }

        delegate.shouldConfirm = { confirmCloseDirtyTab }
        delegate.hasDirtyTabs = { viewModel.tabs.contains(where: \.isDirty) }
        delegate.saveAllDirtyTabs = { saveAllDirtyTabsForWindowClose() }
        delegate.dialogTitle = { "Save changes before closing?" }
        delegate.dialogMessage = { windowCloseDialogMessage() }
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
        .background(editorSurfaceBackgroundStyle)
    }
#endif

    private func withBaseEditorEvents<Content: View>(_ view: Content) -> some View {
        let viewWithClipboardEvents = view
            .onReceive(NotificationCenter.default.publisher(for: .caretPositionDidChange)) { notif in
                if let location = notif.userInfo?["location"] as? Int, location >= 0 {
                    lastCaretLocation = location
                    if let selectedURL = viewModel.selectedTab?.fileURL?.standardizedFileURL {
                        sessionCaretByFileURL[selectedURL.absoluteString] = location
                    }
                }
                if let line = notif.userInfo?["line"] as? Int, let col = notif.userInfo?["column"] as? Int {
                    if line <= 0 {
                        caretStatus = "Pos \(col)"
                    } else {
                        caretStatus = "Ln \(line), Col \(col)"
                    }
                }
#if os(iOS)
                // Keep floating status pill word count in sync with live buffer while typing.
                let liveText = liveEditorBufferText() ?? currentContent
                scheduleWordCountRefresh(for: liveText)
#endif
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
                updateLargeFileModeForCurrentContext()
                scheduleLargeFileModeReevaluation(after: 0.9)
                scheduleHighlightRefresh()
                if let selectedID = viewModel.selectedTab?.id {
                    viewModel.refreshExternalConflictForTab(tabID: selectedID)
                }
                restoreCaretForSelectedSessionFileIfAvailable()
                persistSessionIfReady()
            }
            .onChange(of: viewModel.selectedTab?.isLoadingContent ?? false) { _, isLoading in
                if isLoading {
                    if !largeFileModeEnabled {
                        largeFileModeEnabled = true
                    }
                } else {
                    scheduleLargeFileModeReevaluation(after: 0.8)
                }
                scheduleHighlightRefresh()
            }
            .onChange(of: currentLanguage) { _, newValue in
                settingsTemplateLanguage = newValue
            }
            .onChange(of: viewModel.pendingExternalFileConflict?.tabID) { _, conflictTabID in
                if conflictTabID != nil {
                    showExternalConflictDialog = true
                }
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
        if let tab = viewModel.selectedTab,
           !tab.languageLocked,
           tab.language == "plain",
           result.lang != "plain" {
            viewModel.setTabLanguage(tabID: tab.id, language: result.lang, lock: false)
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
            if let tab = viewModel.selectedTab,
               !tab.languageLocked,
               tab.language == "plain" {
                viewModel.setTabLanguage(tabID: tab.id, language: preferred, lock: false)
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
        if droppedFileLoadInProgress || viewModel.selectedTab?.isLoadingContent == true {
            if !largeFileModeEnabled {
                largeFileModeEnabled = true
                scheduleHighlightRefresh()
            }
            return
        }
        let lowerLanguage = currentLanguage.lowercased()
        let isHTMLLike = ["html", "htm", "xml", "svg", "xhtml"].contains(lowerLanguage)
        let isCSVLike = ["csv", "tsv"].contains(lowerLanguage)
        let useAggressiveThresholds = isHTMLLike || isCSVLike
        #if os(iOS)
        var byteThreshold = useAggressiveThresholds
            ? EditorPerformanceThresholds.largeFileBytesHTMLCSVMobile
            : EditorPerformanceThresholds.largeFileBytesMobile
        var lineThreshold = useAggressiveThresholds
            ? EditorPerformanceThresholds.largeFileLineBreaksHTMLCSVMobile
            : EditorPerformanceThresholds.largeFileLineBreaksMobile
        #else
        var byteThreshold = useAggressiveThresholds
            ? EditorPerformanceThresholds.largeFileBytesHTMLCSV
            : EditorPerformanceThresholds.largeFileBytes
        var lineThreshold = useAggressiveThresholds
            ? EditorPerformanceThresholds.largeFileLineBreaksHTMLCSV
            : EditorPerformanceThresholds.largeFileLineBreaks
        #endif
        switch performancePreset {
        case .balanced:
            break
        case .largeFiles:
            byteThreshold = max(1_000_000, Int(Double(byteThreshold) * 0.75))
            lineThreshold = max(5_000, Int(Double(lineThreshold) * 0.75))
        case .battery:
            byteThreshold = max(750_000, Int(Double(byteThreshold) * 0.55))
            lineThreshold = max(3_000, Int(Double(lineThreshold) * 0.55))
        }
        let byteCount = text.utf8.count
        let exceedsByteThreshold = byteCount >= byteThreshold
        let exceedsLineThreshold: Bool = {
            if exceedsByteThreshold { return true }
            var lineBreaks = 0
            var currentLineLength = 0
            let csvLongLineThreshold = 16_000
            for codeUnit in text.utf16 {
                if codeUnit == 10 { // '\n'
                    lineBreaks += 1
                    currentLineLength = 0
                    if lineBreaks >= lineThreshold {
                        return true
                    }
                    continue
                }
                if isCSVLike {
                    currentLineLength += 1
                    if currentLineLength >= csvLongLineThreshold {
                        return true
                    }
                }
            }
            return false
        }()
#if os(iOS)
        let isLarge = forceLargeFileMode
            || exceedsByteThreshold
            || exceedsLineThreshold
#else
        let isLarge = exceedsByteThreshold
            || exceedsLineThreshold
#endif
        if largeFileModeEnabled != isLarge {
            largeFileModeEnabled = isLarge
            scheduleHighlightRefresh()
        }
    }

    private func updateLargeFileModeForCurrentContext() {
        updateLargeFileMode(for: currentContentBinding.wrappedValue)
    }

    private func scheduleLargeFileModeReevaluation(after delay: TimeInterval) {
        pendingLargeFileModeReevaluation?.cancel()
        let work = DispatchWorkItem {
            updateLargeFileModeForCurrentContext()
        }
        pendingLargeFileModeReevaluation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
#if os(iOS)
                viewModel.isBrainDumpMode = false
                UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
#else
                viewModel.isBrainDumpMode.toggle()
                UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
#endif
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
            .onReceive(NotificationCenter.default.publisher(for: .findNextRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                findNext()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showQuickSwitcherRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                quickSwitcherQuery = ""
                showQuickSwitcher = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNextMatchRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                addNextMatchSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showFindInFilesRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                if findInFilesQuery.isEmpty {
                    findInFilesQuery = findQuery
                }
                showFindInFiles = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showWelcomeTourRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                showWelcomeTour = true
            }
        .onReceive(NotificationCenter.default.publisher(for: .toggleProjectStructureSidebarRequested)) { notif in
            guard matchesCurrentWindow(notif) else { return }
            toggleProjectSidebarFromToolbar()
        }
            .onReceive(NotificationCenter.default.publisher(for: .openProjectFolderRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                openProjectFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAPISettingsRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                openAPISettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSettingsRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                if let tab = notif.object as? String, !tab.isEmpty {
                    openSettings(tab: tab)
                } else {
                    openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeSelectedTabRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                guard let tab = viewModel.selectedTab else { return }
                requestCloseTab(tab)
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
                .background(editorSurfaceBackgroundStyle)
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
                    .background(
                        enableTranslucentWindow
                        ? AnyShapeStyle(.ultraThinMaterial)
                        : (useIOSUnifiedSolidSurfaces ? AnyShapeStyle(iOSNonTranslucentSurfaceColor) : AnyShapeStyle(Color.clear))
                    )
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
        lifecycleConfiguredRootView
#if os(macOS)
        .background(
            WindowAccessor { window in
                updateWindowRegistration(window)
            }
            .frame(width: 0, height: 0)
        )
        .onDisappear {
            handleWindowDisappear()
        }
#endif
    }

    private var basePlatformRootView: some View {
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
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .background(
                IPadKeyboardShortcutBridge(
                    onNewTab: { viewModel.addNewTab() },
                    onOpenFile: { openFileFromToolbar() },
                    onSave: { saveCurrentTabFromToolbar() },
                    onFind: { showFindReplace = true },
                    onFindInFiles: { showFindInFiles = true },
                    onQuickOpen: {
                        quickSwitcherQuery = ""
                        showQuickSwitcher = true
                    }
                )
                .frame(width: 0, height: 0)
            )
#endif
    }

    private var lifecycleConfiguredRootView: some View {
        basePlatformRootView
            .onAppear {
                handleSettingsAndEditorDefaultsOnAppear()
            }
            .onChange(of: settingsLineWrapEnabled) { _, enabled in
                let target = projectOverrideLineWrapEnabled ?? enabled
                if viewModel.isLineWrapEnabled != target {
                    viewModel.isLineWrapEnabled = target
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .whitespaceScalarInspectionResult)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                if let msg = notif.userInfo?[EditorCommandUserInfo.inspectionMessage] as? String {
                    whitespaceInspectorMessage = msg
                }
            }
            .onChange(of: viewModel.isLineWrapEnabled) { _, enabled in
                guard projectOverrideLineWrapEnabled == nil else { return }
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
            .onChange(of: viewModel.tabsObservationToken) { _, _ in
                persistSessionIfReady()
                persistUnsavedDraftSnapshotIfNeeded()
            }
            .onChange(of: viewModel.showSidebar) { _, _ in
                persistSessionIfReady()
            }
            .onChange(of: showProjectStructureSidebar) { _, _ in
                persistSessionIfReady()
            }
            .onChange(of: showSupportedProjectFilesOnly) { _, _ in
                refreshProjectTree()
            }
            .onChange(of: showMarkdownPreviewPane) { _, _ in
                persistSessionIfReady()
            }
#if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if let selectedID = viewModel.selectedTab?.id {
                    viewModel.refreshExternalConflictForTab(tabID: selectedID)
                }
            }
#elseif os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if let selectedID = viewModel.selectedTab?.id {
                    viewModel.refreshExternalConflictForTab(tabID: selectedID)
                }
            }
#endif
            .onOpenURL { url in
                viewModel.openFile(url: url)
            }
#if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                persistSessionIfReady()
                persistUnsavedDraftSnapshotIfNeeded()
            }
#endif
            .modifier(ModalPresentationModifier(contentView: self))
            .onAppear {
                handleStartupOnAppear()
            }
    }

    private func handleSettingsAndEditorDefaultsOnAppear() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: quickSwitcherRecentsDefaultsKey) {
            quickSwitcherRecentItemIDs = saved
        }
        if UserDefaults.standard.object(forKey: "SettingsAutoIndent") == nil {
            autoIndentEnabled = true
        }
#if os(iOS)
        if defaults.object(forKey: "SettingsShowKeyboardAccessoryBarIOS") == nil {
            showKeyboardAccessoryBarIOS = false
        }
#endif
#if os(macOS)
        if defaults.object(forKey: "ShowBracketHelperBarMac") == nil {
            showBracketHelperBarMac = false
        }
#endif
        let completionResetMigrationKey = "SettingsMigrationCompletionResetV1"
        if !defaults.bool(forKey: completionResetMigrationKey) {
            defaults.set(false, forKey: "SettingsCompletionEnabled")
            defaults.set(true, forKey: completionResetMigrationKey)
            isAutoCompletionEnabled = false
        } else {
            isAutoCompletionEnabled = defaults.bool(forKey: "SettingsCompletionEnabled")
        }
        viewModel.isLineWrapEnabled = effectiveLineWrapEnabled
        syncAppleCompletionAvailability()
    }

    private func handleStartupOnAppear() {
        EditorPerformanceMonitor.shared.markFirstPaint()

        if !didRunInitialWindowLayoutSetup {
            // Start with sidebars collapsed only once; otherwise toggles can get reset on layout transitions.
            viewModel.showSidebar = false
            showProjectStructureSidebar = false
            didRunInitialWindowLayoutSetup = true
        }

        applyStartupBehaviorIfNeeded()

        // Keep iOS tab/editor layout stable by forcing Brain Dump off on mobile.
#if os(iOS)
        viewModel.isBrainDumpMode = false
        UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
#else
        if UserDefaults.standard.object(forKey: "BrainDumpModeEnabled") != nil {
            viewModel.isBrainDumpMode = UserDefaults.standard.bool(forKey: "BrainDumpModeEnabled")
        }
#endif

        applyWindowTranslucency(enableTranslucentWindow)
        if !hasSeenWelcomeTourV1 || welcomeTourSeenRelease != WelcomeTourView.releaseID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showWelcomeTour = true
            }
        }
    }

#if os(macOS)
    private func handleWindowDisappear() {
        completionDebounceTask?.cancel()
        completionTask?.cancel()
        lastCompletionTriggerSignature = ""
        pendingHighlightRefresh?.cancel()
        pendingLargeFileModeReevaluation?.cancel()
        completionCache.removeAll(keepingCapacity: false)
        if let number = hostWindowNumber,
           let window = NSApp.window(withWindowNumber: number),
           let delegate = windowCloseConfirmationDelegate,
           window.delegate === delegate {
            window.delegate = delegate.forwardedDelegate
        }
        windowCloseConfirmationDelegate = nil
        if let number = hostWindowNumber {
            WindowViewModelRegistry.shared.unregister(windowNumber: number)
        }
    }
#endif

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
        let length = nsText?.length ?? currentDocumentUTF16Length
        return length >= EditorPerformanceThresholds.heavyFeatureUTF16Length
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
#if os(iOS)
                    .presentationDetents(contentView.settingsSheetDetents)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
#endif
                }
#endif
#if os(iOS)
                .sheet(isPresented: contentView.$showCompactSidebarSheet) {
                    NavigationStack {
                        SidebarView(
                            content: contentView.currentContent,
                            language: contentView.currentLanguage,
                            translucentBackgroundEnabled: false
                        )
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
                .sheet(isPresented: contentView.$showCompactProjectSidebarSheet) {
                    NavigationStack {
                        ProjectStructureSidebarView(
                            rootFolderURL: contentView.projectRootFolderURL,
                            nodes: contentView.projectTreeNodes,
                            selectedFileURL: contentView.viewModel.selectedTab?.fileURL,
                            showSupportedFilesOnly: contentView.showSupportedProjectFilesOnly,
                            translucentBackgroundEnabled: false,
                            onOpenFile: { contentView.openFileFromToolbar() },
                            onOpenFolder: { contentView.openProjectFolder() },
                            onToggleSupportedFilesOnly: { contentView.showSupportedProjectFilesOnly = $0 },
                            onOpenProjectFile: { contentView.openProjectFile(url: $0) },
                            onRefreshTree: { contentView.refreshProjectTree() }
                        )
                        .navigationTitle("Project Structure")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    contentView.$showCompactProjectSidebarSheet.wrappedValue = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: contentView.markdownPreviewSheetPresentationBinding) {
                    NavigationStack {
                        contentView.markdownPreviewPane
                            .navigationTitle("Markdown Preview")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        contentView.showMarkdownPreviewPane = false
                                    }
                                }
                            }
                    }
                    .presentationDetents([.fraction(0.35), .medium, .large], selection: contentView.$markdownPreviewSheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
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
                .sheet(isPresented: contentView.$showFindInFiles) {
                    FindInFilesPanel(
                        query: contentView.$findInFilesQuery,
                        caseSensitive: contentView.$findInFilesCaseSensitive,
                        results: contentView.findInFilesResults,
                        statusMessage: contentView.findInFilesStatusMessage,
                        onSearch: { contentView.startFindInFiles() },
                        onSelect: { contentView.selectFindInFilesMatch($0) }
                    )
                }
                .sheet(isPresented: contentView.$showLanguageSetupPrompt) {
                    contentView.languageSetupSheet
                }
                .sheet(isPresented: contentView.$showLanguageSearchSheet) {
                    contentView.languageSearchSheet
                }
#if os(macOS)
                .background(
                    WelcomeTourWindowPresenter(
                        isPresented: contentView.$showWelcomeTour,
                        makeContent: {
                            WelcomeTourView {
                                contentView.$hasSeenWelcomeTourV1.wrappedValue = true
                                contentView.$welcomeTourSeenRelease.wrappedValue = WelcomeTourView.releaseID
                                contentView.$showWelcomeTour.wrappedValue = false
                            }
                        }
                    )
                    .frame(width: 0, height: 0)
                )
#else
                .sheet(isPresented: contentView.$showWelcomeTour) {
                    WelcomeTourView {
                        contentView.$hasSeenWelcomeTourV1.wrappedValue = true
                        contentView.$welcomeTourSeenRelease.wrappedValue = WelcomeTourView.releaseID
                        contentView.$showWelcomeTour.wrappedValue = false
                    }
                }
#endif
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
                .confirmationDialog("Are you sure you want to close all tabs?", isPresented: contentView.$showCloseAllTabsDialog, titleVisibility: .visible) {
                    Button("Close All Tabs", role: .destructive) {
                        contentView.closeAllTabsFromToolbar()
                    }
                    Button("Cancel", role: .cancel) { }
                }
                .confirmationDialog("File changed on disk", isPresented: contentView.$showExternalConflictDialog, titleVisibility: .visible) {
                    if let conflict = contentView.viewModel.pendingExternalFileConflict {
                        Button("Reload from Disk", role: .destructive) {
                            contentView.viewModel.resolveExternalConflictByReloadingDisk(tabID: conflict.tabID)
                        }
                        Button("Keep Local and Save") {
                            contentView.viewModel.resolveExternalConflictByKeepingLocal(tabID: conflict.tabID)
                        }
                        Button("Compare") {
                            Task {
                                if let snapshot = await contentView.viewModel.externalConflictComparisonSnapshot(tabID: conflict.tabID) {
                                    await MainActor.run {
                                        contentView.externalConflictCompareSnapshot = snapshot
                                        contentView.showExternalConflictCompareSheet = true
                                    }
                                }
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    if let conflict = contentView.viewModel.pendingExternalFileConflict {
                        if let modified = conflict.diskModifiedAt {
                            Text("\"\(conflict.fileURL.lastPathComponent)\" changed on disk at \(modified.formatted(date: .abbreviated, time: .shortened)).")
                        } else {
                            Text("\"\(conflict.fileURL.lastPathComponent)\" changed on disk.")
                        }
                    } else {
                        Text("The file changed on disk while you had unsaved edits.")
                    }
                }
                .sheet(isPresented: contentView.$showExternalConflictCompareSheet, onDismiss: {
                    contentView.externalConflictCompareSnapshot = nil
                }) {
                    if let snapshot = contentView.externalConflictCompareSnapshot {
                        NavigationStack {
                            VStack(spacing: 12) {
                                Text("Compare Local vs Disk: \(snapshot.fileName)")
                                    .font(.headline)
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Local")
                                            .font(.subheadline.weight(.semibold))
                                        TextEditor(text: .constant(snapshot.localContent))
                                            .font(.system(.footnote, design: .monospaced))
                                            .disabled(true)
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Disk")
                                            .font(.subheadline.weight(.semibold))
                                        TextEditor(text: .constant(snapshot.diskContent))
                                            .font(.system(.footnote, design: .monospaced))
                                            .disabled(true)
                                    }
                                }
                                .frame(maxHeight: .infinity)
                                HStack {
                                    Button("Use Disk", role: .destructive) {
                                        if let conflict = contentView.viewModel.pendingExternalFileConflict {
                                            contentView.viewModel.resolveExternalConflictByReloadingDisk(tabID: conflict.tabID)
                                        }
                                        contentView.showExternalConflictCompareSheet = false
                                    }
                                    Spacer()
                                    Button("Keep Local and Save") {
                                        if let conflict = contentView.viewModel.pendingExternalFileConflict {
                                            contentView.viewModel.resolveExternalConflictByKeepingLocal(tabID: conflict.tabID)
                                        }
                                        contentView.showExternalConflictCompareSheet = false
                                    }
                                }
                            }
                            .padding(16)
                            .navigationTitle("External Change")
                        }
                    }
                }
                .confirmationDialog("Clear editor content?", isPresented: contentView.$showClearEditorConfirmDialog, titleVisibility: .visible) {
                    Button("Clear", role: .destructive) { contentView.clearEditorContent() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will remove all text in the current editor.")
                }
                .alert("Can’t Open File", isPresented: contentView.$showUnsupportedFileAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(String(
                        format: NSLocalizedString(
                            "The file \"%@\" is not supported and can’t be opened.",
                            comment: "Unsupported file alert message"
                        ),
                        contentView.unsupportedFileName
                    ))
                }
#if canImport(UIKit)
                .fileImporter(
                    isPresented: contentView.$showIOSFileImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
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
        return viewModel.showSidebar && !brainDumpLayoutEnabled
#else
        // Keep iPhone layout single-column to avoid horizontal clipping.
        return viewModel.showSidebar && !brainDumpLayoutEnabled && horizontalSizeClass == .regular
#endif
    }

    private var effectiveIndentWidth: Int {
        projectOverrideIndentWidth ?? indentWidth
    }

    private var effectiveLineWrapEnabled: Bool {
        projectOverrideLineWrapEnabled ?? settingsLineWrapEnabled
    }

    private func applyStartupBehaviorIfNeeded() {
        guard !didApplyStartupBehavior else { return }

        if startupBehavior == .forceBlankDocument {
            viewModel.resetTabsForSessionRestore()
            viewModel.addNewTab()
            projectRootFolderURL = nil
            clearProjectEditorOverrides()
            projectTreeNodes = []
            quickSwitcherProjectFileURLs = []
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        if viewModel.tabs.contains(where: { $0.fileURL != nil }) {
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        if restoreUnsavedDraftSnapshotIfAvailable() {
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        if openWithBlankDocument {
            viewModel.resetTabsForSessionRestore()
            viewModel.addNewTab()
            projectRootFolderURL = nil
            clearProjectEditorOverrides()
            projectTreeNodes = []
            quickSwitcherProjectFileURLs = []
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        // Restore last session first when enabled.
        if reopenLastSession {
            if projectRootFolderURL == nil, let restoredProjectFolderURL = restoredLastSessionProjectFolderURL() {
                setProjectFolder(restoredProjectFolderURL)
            }
            let urls = restoredLastSessionFileURLs()
            let selectedURL = restoredLastSessionSelectedFileURL()

            if !urls.isEmpty {
                viewModel.resetTabsForSessionRestore()

                for url in urls {
                    viewModel.openFile(url: url)
                }

                if let selectedURL {
                    _ = viewModel.focusTabIfOpen(for: selectedURL)
                }

                if viewModel.tabs.isEmpty {
                    viewModel.addNewTab()
                }
            }
        }

#if os(iOS)
        // Keep mobile layout in a valid tab state so the file tab bar always has content.
        if viewModel.tabs.isEmpty {
            viewModel.addNewTab()
        }
#endif

        restoreLastSessionViewContextIfAvailable()
        restoreCaretForSelectedSessionFileIfAvailable()
        didApplyStartupBehavior = true
        persistSessionIfReady()
    }

    private func persistSessionIfReady() {
        guard didApplyStartupBehavior else { return }
        let fileURLs = viewModel.tabs.compactMap { $0.fileURL }
        UserDefaults.standard.set(fileURLs.map(\.absoluteString), forKey: "LastSessionFileURLs")
        UserDefaults.standard.set(viewModel.selectedTab?.fileURL?.absoluteString, forKey: "LastSessionSelectedFileURL")
        persistLastSessionViewContext()
        persistLastSessionProjectFolderURL(projectRootFolderURL)
#if os(iOS)
        persistLastSessionSecurityScopedBookmarks(fileURLs: fileURLs, selectedURL: viewModel.selectedTab?.fileURL)
#elseif os(macOS)
        persistLastSessionSecurityScopedBookmarksMac(fileURLs: fileURLs, selectedURL: viewModel.selectedTab?.fileURL)
#endif
    }

    private func restoredLastSessionFileURLs() -> [URL] {
#if os(macOS)
        let bookmarked = restoreSessionURLsFromSecurityScopedBookmarksMac()
        if !bookmarked.isEmpty {
            return bookmarked
        }
#elseif os(iOS)
        let bookmarked = restoreSessionURLsFromSecurityScopedBookmarks()
        if !bookmarked.isEmpty {
            return bookmarked
        }
#endif
        let stored = UserDefaults.standard.stringArray(forKey: "LastSessionFileURLs") ?? []
        var urls: [URL] = []
        var seen: Set<String> = []
        for raw in stored {
            guard let parsed = restoredSessionURL(from: raw) else { continue }
            let standardized = parsed.standardizedFileURL
            // Only restore files that still exist; avoids empty placeholder tabs on launch.
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            let key = standardized.absoluteString
            if seen.insert(key).inserted {
                urls.append(standardized)
            }
        }
        return urls
    }

    private func restoredLastSessionSelectedFileURL() -> URL? {
#if os(macOS)
        if let bookmarked = restoreSelectedURLFromSecurityScopedBookmarkMac() {
            return bookmarked
        }
#elseif os(iOS)
        if let bookmarked = restoreSelectedURLFromSecurityScopedBookmark() {
            return bookmarked
        }
#endif
        guard let selectedPath = UserDefaults.standard.string(forKey: "LastSessionSelectedFileURL"),
              let selectedURL = restoredSessionURL(from: selectedPath) else {
            return nil
        }
        let standardized = selectedURL.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    private func restoredSessionURL(from raw: String) -> URL? {
        // Support both absolute URL strings ("file:///...") and legacy plain paths.
        if let url = URL(string: raw), url.isFileURL {
            return url
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return nil
    }

    private var lastSessionShowSidebarKey: String { "LastSessionShowSidebarV1" }
    private var lastSessionShowProjectSidebarKey: String { "LastSessionShowProjectSidebarV1" }
    private var lastSessionShowMarkdownPreviewKey: String { "LastSessionShowMarkdownPreviewV1" }
    private var lastSessionCaretByFileURLKey: String { "LastSessionCaretByFileURLV1" }

    private var lastSessionProjectFolderURLKey: String { "LastSessionProjectFolderURL" }

    private func persistLastSessionViewContext() {
        let defaults = UserDefaults.standard
        defaults.set(viewModel.showSidebar, forKey: lastSessionShowSidebarKey)
        defaults.set(showProjectStructureSidebar, forKey: lastSessionShowProjectSidebarKey)
        defaults.set(showMarkdownPreviewPane, forKey: lastSessionShowMarkdownPreviewKey)

        if let selectedURL = viewModel.selectedTab?.fileURL {
            let key = selectedURL.standardizedFileURL.absoluteString
            if !key.isEmpty {
                sessionCaretByFileURL[key] = max(0, lastCaretLocation)
            }
        }
        defaults.set(sessionCaretByFileURL, forKey: lastSessionCaretByFileURLKey)
    }

    private func restoreLastSessionViewContextIfAvailable() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: lastSessionShowSidebarKey) != nil {
            viewModel.showSidebar = defaults.bool(forKey: lastSessionShowSidebarKey)
        }
        if defaults.object(forKey: lastSessionShowProjectSidebarKey) != nil {
            showProjectStructureSidebar = defaults.bool(forKey: lastSessionShowProjectSidebarKey)
        }
        if defaults.object(forKey: lastSessionShowMarkdownPreviewKey) != nil {
            showMarkdownPreviewPane = defaults.bool(forKey: lastSessionShowMarkdownPreviewKey)
        }
        sessionCaretByFileURL = defaults.dictionary(forKey: lastSessionCaretByFileURLKey) as? [String: Int] ?? [:]
    }

    private func restoreCaretForSelectedSessionFileIfAvailable() {
        guard let selectedURL = viewModel.selectedTab?.fileURL?.standardizedFileURL else { return }
        guard let location = sessionCaretByFileURL[selectedURL.absoluteString], location >= 0 else { return }
        var userInfo: [String: Any] = [
            EditorCommandUserInfo.rangeLocation: location,
            EditorCommandUserInfo.rangeLength: 0
        ]
#if os(macOS)
        if let hostWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = hostWindowNumber
        }
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(name: .moveCursorToRange, object: nil, userInfo: userInfo)
        }
    }

    private func persistLastSessionProjectFolderURL(_ folderURL: URL?) {
        guard let folderURL else {
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderURLKey)
#if os(macOS)
            UserDefaults.standard.removeObject(forKey: macLastSessionProjectFolderBookmarkKey)
#elseif os(iOS)
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderBookmarkKey)
#endif
            return
        }

        UserDefaults.standard.set(folderURL.absoluteString, forKey: lastSessionProjectFolderURLKey)
#if os(macOS)
        if let bookmark = makeSecurityScopedBookmarkDataMac(for: folderURL) {
            UserDefaults.standard.set(bookmark, forKey: macLastSessionProjectFolderBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: macLastSessionProjectFolderBookmarkKey)
        }
#elseif os(iOS)
        if let bookmark = makeSecurityScopedBookmarkData(for: folderURL) {
            UserDefaults.standard.set(bookmark, forKey: lastSessionProjectFolderBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderBookmarkKey)
        }
#endif
    }

    private func restoredLastSessionProjectFolderURL() -> URL? {
#if os(macOS)
        if let bookmarked = restoreProjectFolderURLFromSecurityScopedBookmarkMac() {
            return bookmarked
        }
#elseif os(iOS)
        if let bookmarked = restoreProjectFolderURLFromSecurityScopedBookmark() {
            return bookmarked
        }
#endif
        guard let raw = UserDefaults.standard.string(forKey: lastSessionProjectFolderURLKey),
              let parsed = restoredSessionURL(from: raw) else {
            return nil
        }
        let standardized = parsed.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

#if os(macOS)
    private var macLastSessionBookmarksKey: String { "MacLastSessionFileBookmarks" }
    private var macLastSessionSelectedBookmarkKey: String { "MacLastSessionSelectedFileBookmark" }
    private var macLastSessionProjectFolderBookmarkKey: String { "MacLastSessionProjectFolderBookmark" }

    private func persistLastSessionSecurityScopedBookmarksMac(fileURLs: [URL], selectedURL: URL?) {
        let bookmarkData = fileURLs.compactMap { makeSecurityScopedBookmarkDataMac(for: $0) }
        UserDefaults.standard.set(bookmarkData, forKey: macLastSessionBookmarksKey)
        if let selectedURL, let selectedData = makeSecurityScopedBookmarkDataMac(for: selectedURL) {
            UserDefaults.standard.set(selectedData, forKey: macLastSessionSelectedBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: macLastSessionSelectedBookmarkKey)
        }
    }

    private func restoreSessionURLsFromSecurityScopedBookmarksMac() -> [URL] {
        guard let saved = UserDefaults.standard.array(forKey: macLastSessionBookmarksKey) as? [Data], !saved.isEmpty else {
            return []
        }
        var urls: [URL] = []
        var seen: Set<String> = []
        for data in saved {
            guard let url = resolveSecurityScopedBookmarkMac(data) else { continue }
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            let key = standardized.absoluteString
            if seen.insert(key).inserted {
                urls.append(standardized)
            }
        }
        return urls
    }

    private func restoreSelectedURLFromSecurityScopedBookmarkMac() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: macLastSessionSelectedBookmarkKey),
              let resolved = resolveSecurityScopedBookmarkMac(data) else {
            return nil
        }
        let standardized = resolved.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    private func restoreProjectFolderURLFromSecurityScopedBookmarkMac() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: macLastSessionProjectFolderBookmarkKey),
              let resolved = resolveSecurityScopedBookmarkMac(data) else {
            return nil
        }
        let standardized = resolved.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    private func makeSecurityScopedBookmarkDataMac(for url: URL) -> Data? {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    private func resolveSecurityScopedBookmarkMac(_ data: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return resolved
    }
#endif

    private var unsavedDraftSnapshotRegistryKey: String { "UnsavedDraftSnapshotRegistryV1" }
    private var unsavedDraftSnapshotKey: String { "UnsavedDraftSnapshotV2.\(recoverySnapshotIdentifier)" }
    private var maxPersistedDraftTabs: Int { 20 }
    private var maxPersistedDraftUTF16Length: Int { 2_000_000 }

    private func persistUnsavedDraftSnapshotIfNeeded() {
        let defaults = UserDefaults.standard
        let dirtyTabs = viewModel.tabs.filter(\.isDirty)
        var registry = defaults.stringArray(forKey: unsavedDraftSnapshotRegistryKey) ?? []

        guard !dirtyTabs.isEmpty else {
            defaults.removeObject(forKey: unsavedDraftSnapshotKey)
            registry.removeAll { $0 == unsavedDraftSnapshotKey }
            defaults.set(registry, forKey: unsavedDraftSnapshotRegistryKey)
            return
        }

        var savedTabs: [SavedDraftTabSnapshot] = []
        savedTabs.reserveCapacity(min(dirtyTabs.count, maxPersistedDraftTabs))
        for tab in dirtyTabs.prefix(maxPersistedDraftTabs) {
            let content = tab.content
            let nsContent = content as NSString
            let clampedContent = nsContent.length > maxPersistedDraftUTF16Length
                ? nsContent.substring(to: maxPersistedDraftUTF16Length)
                : content
            savedTabs.append(
                SavedDraftTabSnapshot(
                    name: tab.name,
                    content: clampedContent,
                    language: tab.language,
                    fileURLString: tab.fileURL?.absoluteString
                )
            )
        }

        let selectedIndex: Int? = {
            guard let selectedID = viewModel.selectedTabID else { return nil }
            return dirtyTabs.firstIndex(where: { $0.id == selectedID })
        }()

        let snapshot = SavedDraftSnapshot(tabs: savedTabs, selectedIndex: selectedIndex, createdAt: Date())
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: unsavedDraftSnapshotKey)
        if !registry.contains(unsavedDraftSnapshotKey) {
            registry.append(unsavedDraftSnapshotKey)
            defaults.set(registry, forKey: unsavedDraftSnapshotRegistryKey)
        }
    }

    private func restoreUnsavedDraftSnapshotIfAvailable() -> Bool {
        let defaults = UserDefaults.standard
        let keys = defaults.stringArray(forKey: unsavedDraftSnapshotRegistryKey) ?? []
        guard !keys.isEmpty else { return false }

        var snapshots: [SavedDraftSnapshot] = []
        for key in keys {
            guard let data = defaults.data(forKey: key),
                  let snapshot = try? JSONDecoder().decode(SavedDraftSnapshot.self, from: data),
                  !snapshot.tabs.isEmpty else {
                continue
            }
            snapshots.append(snapshot)
        }
        guard !snapshots.isEmpty else { return false }

        snapshots.sort { $0.createdAt < $1.createdAt }
        let mergedTabs = snapshots.flatMap(\.tabs)
        guard !mergedTabs.isEmpty else { return false }

        let restoredTabs = mergedTabs.map { saved in
            EditorViewModel.RestoredTabSnapshot(
                name: saved.name,
                content: saved.content,
                language: saved.language,
                fileURL: saved.fileURLString.flatMap(URL.init(string:)),
                languageLocked: true,
                isDirty: true,
                lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil
            )
        }
        viewModel.restoreTabsFromSnapshot(restoredTabs, selectedIndex: nil)

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: unsavedDraftSnapshotRegistryKey)
        return true
    }

#if os(iOS)
    private var lastSessionBookmarksKey: String { "LastSessionFileBookmarks" }
    private var lastSessionSelectedBookmarkKey: String { "LastSessionSelectedFileBookmark" }
    private var lastSessionProjectFolderBookmarkKey: String { "LastSessionProjectFolderBookmark" }

    private func persistLastSessionSecurityScopedBookmarks(fileURLs: [URL], selectedURL: URL?) {
        let bookmarkData = fileURLs.compactMap { makeSecurityScopedBookmarkData(for: $0) }
        UserDefaults.standard.set(bookmarkData, forKey: lastSessionBookmarksKey)
        if let selectedURL, let selectedData = makeSecurityScopedBookmarkData(for: selectedURL) {
            UserDefaults.standard.set(selectedData, forKey: lastSessionSelectedBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSessionSelectedBookmarkKey)
        }
    }

    private func restoreSessionURLsFromSecurityScopedBookmarks() -> [URL] {
        guard let saved = UserDefaults.standard.array(forKey: lastSessionBookmarksKey) as? [Data], !saved.isEmpty else {
            return []
        }
        var urls: [URL] = []
        var seen: Set<String> = []
        for data in saved {
            guard let url = resolveSecurityScopedBookmark(data) else { continue }
            let key = url.standardizedFileURL.absoluteString
            if seen.insert(key).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func restoreSelectedURLFromSecurityScopedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionSelectedBookmarkKey) else { return nil }
        return resolveSecurityScopedBookmark(data)
    }

    private func restoreProjectFolderURLFromSecurityScopedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionProjectFolderBookmarkKey),
              let resolved = resolveSecurityScopedBookmark(data) else { return nil }
        let standardized = resolved.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    private func makeSecurityScopedBookmarkData(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    private func resolveSecurityScopedBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return resolved
    }
#endif

    // Sidebar shows a lightweight table of contents (TOC) derived from the current document.
    @ViewBuilder
    var sidebarView: some View {
        if viewModel.showSidebar && !brainDumpLayoutEnabled {
            SidebarView(
                content: sidebarTOCContent,
                language: currentLanguage,
                translucentBackgroundEnabled: enableTranslucentWindow
            )
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 600)
                .safeAreaInset(edge: .bottom) {
                    Divider()
                }
                .background(editorSurfaceBackgroundStyle)
        } else {
            EmptyView()
        }
    }

    // Bindings that resolve to the active tab (if present) or fallback single-document state.
    var currentContentBinding: Binding<String> {
        if let selectedID = viewModel.selectedTabID,
           viewModel.selectedTab != nil {
            return Binding(
                get: {
                    viewModel.selectedTab?.content ?? singleContent
                },
                set: { newValue in
                    viewModel.updateTabContent(tabID: selectedID, content: newValue)
                }
            )
        } else {
            return $singleContent
        }
    }

    var currentLanguageBinding: Binding<String> {
        if let selectedID = viewModel.selectedTabID,
           viewModel.selectedTab != nil {
            return Binding(
                get: {
                    viewModel.selectedTab?.language ?? singleLanguage
                },
                set: { newValue in
                    viewModel.updateTabLanguage(tabID: selectedID, language: newValue)
                }
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
                    viewModel.updateTabLanguage(tabID: tab.id, language: newValue)
                } else {
                    singleLanguage = newValue
                }
            }
        )
    }

    var currentContent: String { currentContentBinding.wrappedValue }
    var currentLanguage: String { currentLanguageBinding.wrappedValue }

    private var currentDocumentUTF16Length: Int {
        if let tab = viewModel.selectedTab {
            return tab.contentUTF16Length
        }
        return (singleContent as NSString).length
    }

    private var sidebarTOCContent: String {
        if largeFileModeEnabled || currentDocumentUTF16Length >= 400_000 {
            return ""
        }
        return currentContent
    }

    private var brainDumpLayoutEnabled: Bool {
#if os(macOS)
        return viewModel.isBrainDumpMode
#else
        return false
#endif
    }


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
            viewModel.updateTabLanguage(tabID: tab.id, language: language)
            if insertTemplate, contentIsEmpty, let template = starterTemplate(for: language) {
                viewModel.updateTabContent(tabID: tab.id, content: template)
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

    var languageOptions: [String] {
        ["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"]
    }

    func languageLabel(for lang: String) -> String {
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

    var filteredLanguageOptions: [String] {
        let query = languageSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return languageOptions }
        let lower = query.lowercased()
        return languageOptions.filter { lang in
            lang.localizedCaseInsensitiveContains(lower) || languageLabel(for: lang).localizedCaseInsensitiveContains(lower)
        }
    }

    func presentLanguageSearchSheet() {
        languageSearchQuery = ""
        showLanguageSearchSheet = true
    }

    private var languageSearchSheet: some View {
        NavigationStack {
            List(filteredLanguageOptions, id: \.self) { lang in
                Button {
                    currentLanguagePickerBinding.wrappedValue = lang
                    showLanguageSearchSheet = false
                } label: {
                    HStack {
                        Text(languageLabel(for: lang))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if currentLanguage == lang {
                            Image(systemName: "checkmark")
                                .foregroundStyle(NeonUIStyle.accentBlue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageLabel(for: lang))
            }
            .navigationTitle("Select Language")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $languageSearchQuery, prompt: "Search language")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showLanguageSearchSheet = false }
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
#endif
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
        editorExternalMutationRevision &+= 1
        let sourceContent = liveEditorBufferText() ?? currentContentBinding.wrappedValue
        let updated: String
        if sourceContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated = template
        } else {
            updated = sourceContent + (sourceContent.hasSuffix("\n") ? "\n" : "\n\n") + template
        }
        currentContentBinding.wrappedValue = updated
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
    @ViewBuilder
    private var projectStructureSidebarPanel: some View {
#if os(macOS)
        VStack(spacing: 0) {
            Rectangle()
                .fill(macChromeBackgroundStyle)
                .frame(height: macTabBarStripHeight)
            projectStructureSidebarBody
        }
        .frame(
            minWidth: clampedProjectSidebarWidth,
            idealWidth: clampedProjectSidebarWidth,
            maxWidth: clampedProjectSidebarWidth
        )
#else
        projectStructureSidebarBody
            .frame(
                minWidth: clampedProjectSidebarWidth,
                idealWidth: clampedProjectSidebarWidth,
                maxWidth: clampedProjectSidebarWidth
            )
#endif
    }

    private var projectSidebarResizeHandle: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startWidth = projectSidebarResizeStartWidth ?? clampedProjectSidebarWidth
                if projectSidebarResizeStartWidth == nil {
                    projectSidebarResizeStartWidth = startWidth
                }
                let delta = value.translation.width
                let proposed: CGFloat
                switch projectNavigatorPlacement {
                case .leading:
                    proposed = startWidth + delta
                case .trailing:
                    proposed = startWidth - delta
                }
                let clamped = min(max(proposed, 220), 520)
                projectSidebarWidth = Double(clamped)
            }
            .onEnded { _ in
                projectSidebarResizeStartWidth = nil
            }

        return ZStack {
            Color.clear
            Rectangle()
                .fill(Color.secondary.opacity(0.32))
                .frame(width: 1)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel("Resize Project Sidebar")
        .accessibilityHint("Drag left or right to adjust project sidebar width")
    }

    private var projectStructureSidebarBody: some View {
        ProjectStructureSidebarView(
            rootFolderURL: projectRootFolderURL,
            nodes: projectTreeNodes,
            selectedFileURL: viewModel.selectedTab?.fileURL,
            showSupportedFilesOnly: showSupportedProjectFilesOnly,
            translucentBackgroundEnabled: enableTranslucentWindow,
            onOpenFile: { openFileFromToolbar() },
            onOpenFolder: { openProjectFolder() },
            onToggleSupportedFilesOnly: { showSupportedProjectFilesOnly = $0 },
            onOpenProjectFile: { openProjectFile(url: $0) },
            onRefreshTree: { refreshProjectTree() }
        )
    }

    private var delimitedModeControl: some View {
        HStack(spacing: 10) {
            Picker("CSV/TSV View Mode", selection: $delimitedViewMode) {
                Text("Table").tag(DelimitedViewMode.table)
                Text("Text").tag(DelimitedViewMode.text)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
            .accessibilityLabel("CSV or TSV view mode")
            .accessibilityHint("Switch between table mode and raw text mode")

            if shouldShowDelimitedTable {
                if isBuildingDelimitedTable {
                    ProgressView()
                        .scaleEffect(0.85)
                } else if let snapshot = delimitedTableSnapshot {
                    Text(
                        snapshot.truncated
                        ? "Showing \(snapshot.displayedRows) / \(snapshot.totalRows) rows"
                        : "\(snapshot.totalRows) rows"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if !delimitedTableStatus.isEmpty {
                    Text(delimitedTableStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var delimitedTableView: some View {
        Group {
            if isBuildingDelimitedTable {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Building table view…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = delimitedTableSnapshot {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(snapshot.rows.enumerated()), id: \.offset) { index, row in
                                delimitedRowView(cells: row, isHeader: false, rowIndex: index)
                            }
                        } header: {
                            delimitedRowView(cells: snapshot.header, isHeader: true, rowIndex: nil)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(delimitedTableStatus.isEmpty ? "No rows found." : delimitedTableStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            Group {
                if enableTranslucentWindow {
                    Color.clear.background(editorSurfaceBackgroundStyle)
                } else {
                    #if os(iOS)
                    iOSNonTranslucentSurfaceColor
                    #else
                    Color.clear
                    #endif
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CSV or TSV table")
    }

    private func delimitedRowView(cells: [String], isHeader: Bool, rowIndex: Int?) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(size: 12, weight: isHeader ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, isHeader ? 7 : 6)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 1)
                    }
            }
        }
        .background(
            isHeader
            ? Color.secondary.opacity(0.12)
            : ((rowIndex ?? 0).isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear)
        )
    }

    private func scheduleDelimitedTableRebuild(for text: String) {
        guard isDelimitedFileLanguage else {
            delimitedParseTask?.cancel()
            isBuildingDelimitedTable = false
            delimitedTableSnapshot = nil
            delimitedTableStatus = ""
            return
        }
        guard shouldShowDelimitedTable else { return }

        delimitedParseTask?.cancel()
        isBuildingDelimitedTable = true
        delimitedTableStatus = "Parsing…"
        let separator = delimitedSeparator
        delimitedParseTask = Task {
            let source = text
            let parsed = await Task.detached(priority: .utility) {
                Self.buildDelimitedTableSnapshot(from: source, separator: separator, maxRows: 5000, maxColumns: 60)
            }.value
            guard !Task.isCancelled else { return }
            isBuildingDelimitedTable = false
            switch parsed {
            case .success(let snapshot):
                delimitedTableSnapshot = snapshot
                delimitedTableStatus = ""
            case .failure(let message):
                delimitedTableSnapshot = nil
                delimitedTableStatus = message
            }
        }
    }

    private nonisolated static func buildDelimitedTableSnapshot(
        from text: String,
        separator: Character,
        maxRows: Int,
        maxColumns: Int
    ) -> Result<DelimitedTableSnapshot, String> {
        guard !text.isEmpty else { return .failure("No data in file.") }
        var rows: [[String]] = []
        rows.reserveCapacity(min(maxRows, 512))
        var totalRows = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            totalRows += 1
            if rows.count < maxRows {
                rows.append(parseDelimitedLine(String(line), separator: separator, maxColumns: maxColumns))
            }
        }
        guard !rows.isEmpty else { return .failure("No rows found.") }
        let rawHeader = rows.removeFirst()
        let visibleColumns = max(rawHeader.count, rows.first?.count ?? 0)
        let header: [String] = {
            if rawHeader.isEmpty {
                return (0..<visibleColumns).map { "Column \($0 + 1)" }
            }
            return rawHeader.enumerated().map { idx, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Column \(idx + 1)" : trimmed
            }
        }()
        let normalizedRows = rows.map { row in
            if row.count >= visibleColumns { return row }
            return row + Array(repeating: "", count: visibleColumns - row.count)
        }
        return .success(
            DelimitedTableSnapshot(
                header: header,
                rows: normalizedRows,
                totalRows: totalRows,
                displayedRows: rows.count,
                truncated: totalRows > maxRows
            )
        )
    }

    private nonisolated static func parseDelimitedLine(
        _ line: String,
        separator: Character,
        maxColumns: Int
    ) -> [String] {
        if line.isEmpty { return [""] }
        var result: [String] = []
        result.reserveCapacity(min(32, maxColumns))
        var field = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            if next == separator {
                                result.append(field)
                                field.removeAll(keepingCapacity: true)
                            } else {
                                field.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
                continue
            }
            if char == separator && !inQuotes {
                result.append(field)
                field.removeAll(keepingCapacity: true)
                if result.count >= maxColumns {
                    return result
                }
                continue
            }
            field.append(char)
        }
        result.append(field)
        if result.count > maxColumns {
            return Array(result.prefix(maxColumns))
        }
        return result
    }

    var editorView: some View {
        @Bindable var bindableViewModel = viewModel
        let shouldThrottleFeatures = shouldThrottleHeavyEditorFeatures()
        let effectiveBracketHighlight = highlightMatchingBrackets && !shouldThrottleFeatures
        let effectiveScopeGuides = showScopeGuides && !shouldThrottleFeatures
        let effectiveScopeBackground = highlightScopeBackground && !shouldThrottleFeatures
        let content = HStack(spacing: 0) {
            if showProjectStructureSidebar && projectNavigatorPlacement == .leading && !brainDumpLayoutEnabled {
                projectStructureSidebarPanel
                projectSidebarResizeHandle
            }

            VStack(spacing: 0) {
                if !useIPhoneUnifiedTopHost && !brainDumpLayoutEnabled {
                    tabBarView
                }
#if os(macOS)
                if showBracketHelperBarMac {
                    bracketHelperBar
                }
#endif

                if isDelimitedFileLanguage && !brainDumpLayoutEnabled {
                    delimitedModeControl
                }

                Group {
                    if shouldShowDelimitedTable && !brainDumpLayoutEnabled {
                        delimitedTableView
                    } else {
                        // Single editor (no TabView)
                        CustomTextEditor(
                            text: currentContentBinding,
                            documentID: viewModel.selectedTabID,
                            externalEditRevision: editorExternalMutationRevision,
                            language: currentLanguage,
                            colorScheme: colorScheme,
                            fontSize: editorFontSize,
                            isLineWrapEnabled: $bindableViewModel.isLineWrapEnabled,
                            isLargeFileMode: largeFileModeEnabled,
                            translucentBackgroundEnabled: enableTranslucentWindow,
                            showKeyboardAccessoryBar: {
#if os(iOS)
                                showKeyboardAccessoryBarIOS
#else
                                true
#endif
                            }(),
                            showLineNumbers: showLineNumbers,
                            showInvisibleCharacters: false,
                            highlightCurrentLine: highlightCurrentLine,
                            highlightMatchingBrackets: effectiveBracketHighlight,
                            showScopeGuides: effectiveScopeGuides,
                            highlightScopeBackground: effectiveScopeBackground,
                            indentStyle: indentStyle,
                            indentWidth: effectiveIndentWidth,
                            autoIndentEnabled: autoIndentEnabled,
                            autoCloseBracketsEnabled: autoCloseBracketsEnabled,
                            highlightRefreshToken: highlightRefreshToken,
                            isTabLoadingContent: viewModel.selectedTab?.isLoadingContent ?? false,
                            onTextMutation: { mutation in
                                viewModel.applyTabContentEdit(
                                    tabID: mutation.documentID,
                                    range: mutation.range,
                                    replacement: mutation.replacement
                                )
                            }
                        )
                        .id(currentLanguage)
                    }
                }
                .frame(maxWidth: brainDumpLayoutEnabled ? 920 : .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, brainDumpLayoutEnabled ? 24 : 0)
                .padding(.vertical, brainDumpLayoutEnabled ? 40 : 0)
                .background(
                    Group {
                        if enableTranslucentWindow {
                            Color.clear.background(editorSurfaceBackgroundStyle)
                        } else {
                            #if os(iOS)
                            iOSNonTranslucentSurfaceColor
                            #else
                            Color.clear
                            #endif
                        }
                    }
                )

                if !brainDumpLayoutEnabled {
#if os(macOS)
                    wordCountView
#endif
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: brainDumpLayoutEnabled ? .top : .topLeading
            )

            if canShowMarkdownPreviewSplitPane && showMarkdownPreviewPane && currentLanguage == "markdown" && !brainDumpLayoutEnabled {
                Divider()
                markdownPreviewPane
                    .frame(minWidth: 280, idealWidth: 420, maxWidth: 680, maxHeight: .infinity)
            }

            if showProjectStructureSidebar && projectNavigatorPlacement == .trailing && !brainDumpLayoutEnabled {
                projectSidebarResizeHandle
                projectStructureSidebarPanel
            }
        }
        .background(
            Group {
                if brainDumpLayoutEnabled && enableTranslucentWindow {
                    Color.clear.background(editorSurfaceBackgroundStyle)
                } else {
                    #if os(iOS)
                    useIOSUnifiedSolidSurfaces ? iOSNonTranslucentSurfaceColor : Color.clear
                    #else
                    Color.clear
                    #endif
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

#if os(iOS)
        let contentWithTopChrome = useIPhoneUnifiedTopHost
            ? AnyView(
                content.safeAreaInset(edge: .top, spacing: 0) {
                    iPhoneUnifiedTopChromeHost
                }
            )
            : AnyView(content)
#else
        let contentWithTopChrome = AnyView(content)
#endif

        let withEvents = withTypingEvents(
            withCommandEvents(
                withBaseEditorEvents(contentWithTopChrome)
            )
        )

        return withEvents
        .onAppear {
            if isDelimitedFileLanguage {
                delimitedViewMode = .table
                scheduleDelimitedTableRebuild(for: currentContent)
            } else {
                delimitedViewMode = .text
            }
            scheduleWordCountRefresh(for: currentContent)
        }
        .onChange(of: currentContent) { _, newValue in
            scheduleWordCountRefresh(for: newValue)
            if shouldShowDelimitedTable {
                scheduleDelimitedTableRebuild(for: newValue)
            }
        }
        .onChange(of: delimitedViewMode) { _, newValue in
            if newValue == .table {
                scheduleDelimitedTableRebuild(for: currentContent)
            } else {
                delimitedParseTask?.cancel()
                isBuildingDelimitedTable = false
            }
        }
        .onChange(of: currentLanguage) { _, _ in
            if isDelimitedFileLanguage {
                if delimitedViewMode == .text {
                    // Keep explicit user choice when already in text mode.
                } else {
                    delimitedViewMode = .table
                }
                if shouldShowDelimitedTable {
                    scheduleDelimitedTableRebuild(for: currentContent)
                }
            } else {
                delimitedViewMode = .text
                delimitedParseTask?.cancel()
                isBuildingDelimitedTable = false
                delimitedTableSnapshot = nil
                delimitedTableStatus = ""
            }
        }
        .onDisappear {
            wordCountTask?.cancel()
            delimitedParseTask?.cancel()
        }
        .onChange(of: enableTranslucentWindow) { _, newValue in
            applyWindowTranslucency(newValue)
            // Force immediate recolor when translucency changes so syntax highlighting stays visible.
            highlightRefreshToken &+= 1
        }
#if os(iOS)
        .onChange(of: showKeyboardAccessoryBarIOS) { _, isVisible in
            NotificationCenter.default.post(
                name: .keyboardAccessoryBarVisibilityChanged,
                object: isVisible
            )
        }
        .onChange(of: horizontalSizeClass) { _, newClass in
            if UIDevice.current.userInterfaceIdiom == .pad && newClass != .regular && showMarkdownPreviewPane {
                showMarkdownPreviewPane = false
            }
        }
        .onChange(of: showSettingsSheet) { _, isPresented in
            if isPresented {
                if previousKeyboardAccessoryVisibility == nil {
                    previousKeyboardAccessoryVisibility = showKeyboardAccessoryBarIOS
                }
                showKeyboardAccessoryBarIOS = false
            } else if let previousKeyboardAccessoryVisibility {
                showKeyboardAccessoryBarIOS = previousKeyboardAccessoryVisibility
                self.previousKeyboardAccessoryVisibility = nil
            }
        }
#endif
#if os(macOS)
        .onChange(of: macTranslucencyModeRaw) { _, _ in
            // Keep all chrome/background surfaces in lockstep when mode changes.
            highlightRefreshToken &+= 1
        }
#endif
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
                .padding(.top, brainDumpLayoutEnabled ? 12 : 50)
                .padding(.trailing, 12)
            }
        }
#if os(iOS)
        .overlay(alignment: .bottomTrailing) {
            if !brainDumpLayoutEnabled {
                floatingStatusPill
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
        }
#endif
        .onChange(of: currentLanguage) { _, newLanguage in
            if newLanguage != "markdown", showMarkdownPreviewPane {
                showMarkdownPreviewPane = false
            }
        }
#if os(macOS)
        .toolbarBackground(
            macChromeBackgroundStyle,
            for: ToolbarPlacement.windowToolbar
        )
        .toolbarBackgroundVisibility(Visibility.visible, for: ToolbarPlacement.windowToolbar)
        .tint(NeonUIStyle.accentBlue)
#else
        .toolbarBackground(
            enableTranslucentWindow
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(Color(.systemBackground)),
            for: ToolbarPlacement.navigationBar
        )
#endif
    }

#if os(macOS) || os(iOS)
    @ViewBuilder
    private var markdownPreviewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Markdown Preview")
                    .font(.headline)
                Spacer()
                Picker("Template", selection: $markdownPreviewTemplateRaw) {
                    Text("Default").tag("default")
                    Text("Docs").tag("docs")
                    Text("Article").tag("article")
                    Text("Compact").tag("compact")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(editorSurfaceBackgroundStyle)

            MarkdownPreviewWebView(html: markdownPreviewHTML(from: currentContent))
                .accessibilityLabel("Markdown Preview Content")
        }
        .background(editorSurfaceBackgroundStyle)
    }

    private var markdownPreviewTemplate: String {
        switch markdownPreviewTemplateRaw {
        case "docs", "article", "compact":
            return markdownPreviewTemplateRaw
        default:
            return "default"
        }
    }

    private var markdownPreviewRenderByteLimit: Int { 180_000 }
    private var markdownPreviewFallbackCharacterLimit: Int { 120_000 }

    private func markdownPreviewHTML(from markdownText: String) -> String {
        let bodyHTML = markdownPreviewBodyHTML(from: markdownText)
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(markdownPreviewCSS(template: markdownPreviewTemplate))
        </style>
        </head>
        <body class="\(markdownPreviewTemplate)">
        <main class="content">
        \(bodyHTML)
        </main>
        </body>
        </html>
        """
    }

    private func markdownPreviewBodyHTML(from markdownText: String) -> String {
        let byteCount = markdownText.lengthOfBytes(using: .utf8)
        if byteCount > markdownPreviewRenderByteLimit {
            return largeMarkdownFallbackHTML(from: markdownText, byteCount: byteCount)
        }
        return renderedMarkdownBodyHTML(from: markdownText) ?? "<pre>\(escapedHTML(markdownText))</pre>"
    }

    private func largeMarkdownFallbackHTML(from markdownText: String, byteCount: Int) -> String {
        let previewText = String(markdownText.prefix(markdownPreviewFallbackCharacterLimit))
        let truncated = previewText.count < markdownText.count
        let statusSuffix = truncated ? " (truncated preview)" : ""
        return """
        <section class="preview-warning">
          <p><strong>Large Markdown file</strong></p>
          <p class="preview-warning-meta">Rendering full Markdown is skipped for stability (\(byteCount) bytes)\(statusSuffix).</p>
        </section>
        <pre>\(escapedHTML(previewText))</pre>
        """
    }

    private func renderedMarkdownBodyHTML(from markdownText: String) -> String? {
        let html = simpleMarkdownToHTML(markdownText).trimmingCharacters(in: .whitespacesAndNewlines)
        return html.isEmpty ? nil : html
    }

    private func simpleMarkdownToHTML(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        var paragraphLines: [String] = []
        var insideCodeFence = false
        var codeFenceLanguage: String?
        var insideUnorderedList = false
        var insideOrderedList = false
        var insideBlockquote = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.map { inlineMarkdownToHTML($0) }.joined(separator: "<br/>")
            result.append("<p>\(paragraph)</p>")
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func closeLists() {
            if insideUnorderedList {
                result.append("</ul>")
                insideUnorderedList = false
            }
            if insideOrderedList {
                result.append("</ol>")
                insideOrderedList = false
            }
        }

        func closeBlockquote() {
            if insideBlockquote {
                flushParagraph()
                closeLists()
                result.append("</blockquote>")
                insideBlockquote = false
            }
        }

        func closeParagraphAndInlineContainers() {
            flushParagraph()
            closeLists()
        }

        for rawLine in lines {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if insideCodeFence {
                    result.append("</code></pre>")
                    insideCodeFence = false
                    codeFenceLanguage = nil
                } else {
                    closeBlockquote()
                    closeParagraphAndInlineContainers()
                    insideCodeFence = true
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeFenceLanguage = lang.isEmpty ? nil : lang
                    if let codeFenceLanguage {
                        result.append("<pre><code class=\"language-\(escapedHTML(codeFenceLanguage))\">")
                    } else {
                        result.append("<pre><code>")
                    }
                }
                continue
            }

            if insideCodeFence {
                result.append("\(escapedHTML(line))\n")
                continue
            }

            if trimmed.isEmpty {
                closeParagraphAndInlineContainers()
                closeBlockquote()
                continue
            }

            if let heading = markdownHeading(from: trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append("<h\(heading.level)>\(inlineMarkdownToHTML(heading.text))</h\(heading.level)>")
                continue
            }

            if isMarkdownHorizontalRule(trimmed) {
                closeBlockquote()
                closeParagraphAndInlineContainers()
                result.append("<hr/>")
                continue
            }

            var workingLine = trimmed
            let isBlockquoteLine = workingLine.hasPrefix(">")
            if isBlockquoteLine {
                if !insideBlockquote {
                    closeParagraphAndInlineContainers()
                    result.append("<blockquote>")
                    insideBlockquote = true
                }
                workingLine = workingLine.dropFirst().trimmingCharacters(in: .whitespaces)
            } else {
                closeBlockquote()
            }

            if let unordered = markdownUnorderedListItem(from: workingLine) {
                flushParagraph()
                if insideOrderedList {
                    result.append("</ol>")
                    insideOrderedList = false
                }
                if !insideUnorderedList {
                    result.append("<ul>")
                    insideUnorderedList = true
                }
                result.append("<li>\(inlineMarkdownToHTML(unordered))</li>")
                continue
            }

            if let ordered = markdownOrderedListItem(from: workingLine) {
                flushParagraph()
                if insideUnorderedList {
                    result.append("</ul>")
                    insideUnorderedList = false
                }
                if !insideOrderedList {
                    result.append("<ol>")
                    insideOrderedList = true
                }
                result.append("<li>\(inlineMarkdownToHTML(ordered))</li>")
                continue
            }

            closeLists()
            paragraphLines.append(workingLine)
        }

        closeBlockquote()
        closeParagraphAndInlineContainers()
        if insideCodeFence {
            result.append("</code></pre>")
        }
        return result.joined(separator: "\n")
    }

    private func markdownHeading(from line: String) -> (level: Int, text: String)? {
        let pattern = "^(#{1,6})\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let hashesRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (line[hashesRange].count, String(line[textRange]))
    }

    private func isMarkdownHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "***" || compact == "---" || compact == "___"
    }

    private func markdownUnorderedListItem(from line: String) -> String? {
        let pattern = "^[-*+]\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange])
    }

    private func markdownOrderedListItem(from line: String) -> String? {
        let pattern = "^\\d+[\\.)]\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange])
    }

    private func inlineMarkdownToHTML(_ text: String) -> String {
        var html = escapedHTML(text)
        var codeSpans: [String] = []

        html = replacingRegex(in: html, pattern: "`([^`]+)`") { match in
            let content = String(match.dropFirst().dropLast())
            let token = "__CODE_SPAN_\(codeSpans.count)__"
            codeSpans.append("<code>\(content)</code>")
            return token
        }

        html = replacingRegex(in: html, pattern: "!\\[([^\\]]*)\\]\\(([^\\)\\s]+)\\)") { match in
            let parts = captureGroups(in: match, pattern: "!\\[([^\\]]*)\\]\\(([^\\)\\s]+)\\)")
            guard parts.count == 2 else { return match }
            return "<img src=\"\(parts[1])\" alt=\"\(parts[0])\"/>"
        }

        html = replacingRegex(in: html, pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)") { match in
            let parts = captureGroups(in: match, pattern: "\\[([^\\]]+)\\]\\(([^\\)\\s]+)\\)")
            guard parts.count == 2 else { return match }
            return "<a href=\"\(parts[1])\">\(parts[0])</a>"
        }

        html = replacingRegex(in: html, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\(String($0.dropFirst(2).dropLast(2)))</strong>" }
        html = replacingRegex(in: html, pattern: "__([^_]+)__") { "<strong>\(String($0.dropFirst(2).dropLast(2)))</strong>" }
        html = replacingRegex(in: html, pattern: "\\*([^*]+)\\*") { "<em>\(String($0.dropFirst().dropLast()))</em>" }
        html = replacingRegex(in: html, pattern: "_([^_]+)_") { "<em>\(String($0.dropFirst().dropLast()))</em>" }

        for (index, codeHTML) in codeSpans.enumerated() {
            html = html.replacingOccurrences(of: "__CODE_SPAN_\(index)__", with: codeHTML)
        }
        return html
    }

    private func replacingRegex(in text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let segment = String(output[range])
            output.replaceSubrange(range, with: transform(segment))
        }
        return output
    }

    private func captureGroups(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return []
        }
        var groups: [String] = []
        for idx in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: idx), in: text) {
                groups.append(String(text[range]))
            }
        }
        return groups
    }

    private func markdownPreviewCSS(template: String) -> String {
        let basePadding: String
        let fontSize: String
        let lineHeight: String
        let maxWidth: String
        switch template {
        case "docs":
            basePadding = "22px 30px"
            fontSize = "15px"
            lineHeight = "1.7"
            maxWidth = "900px"
        case "article":
            basePadding = "32px 48px"
            fontSize = "17px"
            lineHeight = "1.8"
            maxWidth = "760px"
        case "compact":
            basePadding = "14px 16px"
            fontSize = "13px"
            lineHeight = "1.5"
            maxWidth = "none"
        default:
            basePadding = "18px 22px"
            fontSize = "14px"
            lineHeight = "1.6"
            maxWidth = "860px"
        }

        return """
        :root { color-scheme: light dark; }
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          font-size: \(fontSize);
          line-height: \(lineHeight);
        }
        .content {
          max-width: \(maxWidth);
          padding: \(basePadding);
          margin: 0 auto;
        }
        .preview-warning {
          margin: 0.5em 0 0.8em;
          padding: 0.75em 0.9em;
          border-radius: 9px;
          border: 1px solid color-mix(in srgb, #f59e0b 45%, transparent);
          background: color-mix(in srgb, #f59e0b 12%, transparent);
        }
        .preview-warning p {
          margin: 0;
        }
        .preview-warning-meta {
          margin-top: 0.4em !important;
          font-size: 0.92em;
          opacity: 0.9;
        }
        h1, h2, h3, h4, h5, h6 {
          line-height: 1.25;
          margin: 1.1em 0 0.55em;
          font-weight: 700;
        }
        h1 { font-size: 1.85em; border-bottom: 1px solid color-mix(in srgb, currentColor 18%, transparent); padding-bottom: 0.25em; }
        h2 { font-size: 1.45em; border-bottom: 1px solid color-mix(in srgb, currentColor 13%, transparent); padding-bottom: 0.2em; }
        h3 { font-size: 1.2em; }
        p, ul, ol, blockquote, table, pre { margin: 0.65em 0; }
        ul, ol { padding-left: 1.3em; }
        li { margin: 0.2em 0; }
        blockquote {
          margin-left: 0;
          padding: 0.45em 0.9em;
          border-left: 3px solid color-mix(in srgb, currentColor 30%, transparent);
          background: color-mix(in srgb, currentColor 6%, transparent);
          border-radius: 6px;
        }
        code {
          font-family: "SF Mono", "Menlo", "Monaco", monospace;
          font-size: 0.9em;
          padding: 0.12em 0.35em;
          border-radius: 5px;
          background: color-mix(in srgb, currentColor 10%, transparent);
        }
        pre {
          overflow-x: auto;
          padding: 0.8em 0.95em;
          border-radius: 9px;
          background: color-mix(in srgb, currentColor 8%, transparent);
          border: 1px solid color-mix(in srgb, currentColor 14%, transparent);
          line-height: 1.35;
          white-space: pre;
        }
        pre code {
          display: block;
          padding: 0;
          background: transparent;
          border-radius: 0;
          font-size: 0.88em;
          line-height: 1.35;
          white-space: pre;
        }
        table {
          border-collapse: collapse;
          width: 100%;
          border: 1px solid color-mix(in srgb, currentColor 16%, transparent);
          border-radius: 8px;
          overflow: hidden;
        }
        th, td {
          text-align: left;
          padding: 0.45em 0.55em;
          border-bottom: 1px solid color-mix(in srgb, currentColor 10%, transparent);
        }
        th {
          background: color-mix(in srgb, currentColor 7%, transparent);
          font-weight: 600;
        }
        a {
          color: #2f7cf6;
          text-decoration: none;
          border-bottom: 1px solid color-mix(in srgb, #2f7cf6 45%, transparent);
        }
        img {
          max-width: 100%;
          height: auto;
          border-radius: 8px;
        }
        hr {
          border: 0;
          border-top: 1px solid color-mix(in srgb, currentColor 15%, transparent);
          margin: 1.1em 0;
        }
        """
    }

    private func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
#endif

#if os(iOS)
    @ViewBuilder
    private var iPhoneUnifiedTopChromeHost: some View {
        VStack(spacing: 0) {
            iPhoneUnifiedToolbarRow
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            tabBarView
        }
        .background(
            enableTranslucentWindow
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(iOSNonTranslucentSurfaceColor)
        )
    }

    private var floatingStatusPillText: String {
        let base = largeFileModeEnabled
            ? "\(caretStatus)\(vimStatusSuffix)"
            : "\(caretStatus) • Words: \(statusWordCount)\(vimStatusSuffix)"
        if largeFileModeEnabled {
            return "\(base) • Large File"
        }
        return base
    }

    private var floatingStatusPill: some View {
        GlassSurface(
            enabled: shouldUseLiquidGlass,
            material: primaryGlassMaterial,
            fallbackColor: toolbarFallbackColor,
            shape: .capsule,
            chromeStyle: .single
        ) {
            Text(floatingStatusPillText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(iOSToolbarForegroundColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .accessibilityLabel("Editor status")
        .accessibilityValue(floatingStatusPillText)
    }

    private var iOSToolbarForegroundColor: Color {
        if toolbarIconsBlueIOS {
            return NeonUIStyle.accentBlue
        }
        return colorScheme == .dark ? Color.white.opacity(0.95) : Color.primary.opacity(0.92)
    }
#endif

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
                 : "\(caretStatus) • Words: \(statusWordCount)\(vimStatusSuffix)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.trailing, 16)
        }
        .background(editorSurfaceBackgroundStyle)
    }

    @ViewBuilder
    var tabBarView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if viewModel.tabs.isEmpty {
                        Button {
                            viewModel.addNewTab()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Untitled 1")
                                    .lineLimit(1)
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NeonUIStyle.accentBlue)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.18))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(viewModel.tabs) { tab in
                            HStack(spacing: 8) {
                                Button {
                                    viewModel.selectTab(id: tab.id)
                                } label: {
                                    Text(tab.name + (tab.isDirty ? " •" : ""))
                                        .lineLimit(1)
                                        .font(.system(size: 12, weight: viewModel.selectedTabID == tab.id ? .semibold : .regular))
                                        .padding(.leading, 10)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    requestCloseTab(tab)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.trailing, 10)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .help("Close \(tab.name)")
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(viewModel.selectedTabID == tab.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                            )
                        }
                    }
                }
                .padding(.leading, tabBarLeadingPadding)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
            }
            Divider().opacity(0.45)
        }
        .frame(minHeight: 42, maxHeight: 42, alignment: .center)
#if os(macOS)
        .background(macChromeBackgroundStyle)
#else
        .background(
            enableTranslucentWindow
            ? AnyShapeStyle(.ultraThinMaterial)
            : (useIOSUnifiedSolidSurfaces ? AnyShapeStyle(iOSNonTranslucentSurfaceColor) : AnyShapeStyle(Color(.systemBackground)))
        )
        .contentShape(Rectangle())
        .zIndex(10)
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
        let commandItems: [QuickFileSwitcherPanel.Item] = [
            .init(id: "cmd:new_tab", title: "New Tab", subtitle: "Create a new empty tab"),
            .init(id: "cmd:open_file", title: "Open File", subtitle: "Open files from disk"),
            .init(id: "cmd:save_file", title: "Save", subtitle: "Save current tab"),
            .init(id: "cmd:save_as", title: "Save As", subtitle: "Save current tab to a new file"),
            .init(id: "cmd:find_replace", title: "Find and Replace", subtitle: "Search and replace in current document"),
            .init(id: "cmd:find_in_files", title: "Find in Files", subtitle: "Search across project files"),
            .init(id: "cmd:toggle_sidebar", title: "Toggle Sidebar", subtitle: "Show or hide the outline sidebar")
        ]
        items.append(contentsOf: commandItems)

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

        for url in quickSwitcherProjectFileURLs {
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

        let query = quickSwitcherQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return Array(
                items
                    .sorted { quickSwitcherRecencyScore(for: $0.id) > quickSwitcherRecencyScore(for: $1.id) }
                    .prefix(300)
            )
        }

        let ranked = items.compactMap { item -> (QuickFileSwitcherPanel.Item, Int)? in
            guard let score = quickSwitcherMatchScore(for: item, query: query) else { return nil }
            return (item, score + quickSwitcherRecencyScore(for: item.id))
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending
            }
            return $0.1 > $1.1
        }

        return Array(ranked.prefix(300).map(\.0))
    }

    private func selectQuickSwitcherItem(_ item: QuickFileSwitcherPanel.Item) {
        rememberQuickSwitcherSelection(item.id)
        if item.id.hasPrefix("cmd:") {
            performQuickSwitcherCommand(item.id)
            return
        }
        if item.id.hasPrefix("tab:") {
            let raw = String(item.id.dropFirst(4))
            if let id = UUID(uuidString: raw) {
                viewModel.selectTab(id: id)
            }
            return
        }
        if item.id.hasPrefix("file:") {
            let path = String(item.id.dropFirst(5))
            openProjectFile(url: URL(fileURLWithPath: path))
        }
    }

    private func performQuickSwitcherCommand(_ commandID: String) {
        switch commandID {
        case "cmd:new_tab":
            viewModel.addNewTab()
        case "cmd:open_file":
            openFileFromToolbar()
        case "cmd:save_file":
            saveCurrentTabFromToolbar()
        case "cmd:save_as":
            saveCurrentTabAsFromToolbar()
        case "cmd:find_replace":
            showFindReplace = true
        case "cmd:find_in_files":
            showFindInFiles = true
        case "cmd:toggle_sidebar":
            viewModel.showSidebar.toggle()
        default:
            break
        }
    }

    private func rememberQuickSwitcherSelection(_ itemID: String) {
        quickSwitcherRecentItemIDs.removeAll { $0 == itemID }
        quickSwitcherRecentItemIDs.insert(itemID, at: 0)
        if quickSwitcherRecentItemIDs.count > 30 {
            quickSwitcherRecentItemIDs = Array(quickSwitcherRecentItemIDs.prefix(30))
        }
        UserDefaults.standard.set(quickSwitcherRecentItemIDs, forKey: quickSwitcherRecentsDefaultsKey)
    }

    private func quickSwitcherRecencyScore(for itemID: String) -> Int {
        guard let index = quickSwitcherRecentItemIDs.firstIndex(of: itemID) else { return 0 }
        return max(0, 120 - (index * 5))
    }

    private func quickSwitcherMatchScore(for item: QuickFileSwitcherPanel.Item, query: String) -> Int? {
        let normalizedQuery = query.lowercased()
        let title = item.title.lowercased()
        let subtitle = item.subtitle.lowercased()
        if title.hasPrefix(normalizedQuery) {
            return 320
        }
        if title.contains(normalizedQuery) {
            return 240
        }
        if subtitle.contains(normalizedQuery) {
            return 180
        }
        if isFuzzyMatch(needle: normalizedQuery, haystack: title) {
            return 120
        }
        if isFuzzyMatch(needle: normalizedQuery, haystack: subtitle) {
            return 90
        }
        return nil
    }

    private func isFuzzyMatch(needle: String, haystack: String) -> Bool {
        if needle.isEmpty { return true }
        var cursor = haystack.startIndex
        for ch in needle {
            var found = false
            while cursor < haystack.endIndex {
                if haystack[cursor] == ch {
                    found = true
                    cursor = haystack.index(after: cursor)
                    break
                }
                cursor = haystack.index(after: cursor)
            }
            if !found { return false }
        }
        return true
    }

    private func startFindInFiles() {
        guard let root = projectRootFolderURL else {
            findInFilesResults = []
            findInFilesStatusMessage = "Open a project folder first."
            return
        }
        let query = findInFilesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            findInFilesResults = []
            findInFilesStatusMessage = "Enter a search query."
            return
        }

        findInFilesTask?.cancel()
        findInFilesStatusMessage = "Searching…"

        let caseSensitive = findInFilesCaseSensitive
        findInFilesTask = Task {
            let results = await ContentView.findInFiles(
                root: root,
                query: query,
                caseSensitive: caseSensitive,
                maxResults: 500
            )
            guard !Task.isCancelled else { return }
            findInFilesResults = results
            if results.isEmpty {
                findInFilesStatusMessage = "No matches found."
            } else {
                findInFilesStatusMessage = "\(results.count) matches"
            }
        }
    }

    private func selectFindInFilesMatch(_ match: FindInFilesMatch) {
        openProjectFile(url: match.fileURL)
        var userInfo: [String: Any] = [
            EditorCommandUserInfo.rangeLocation: match.rangeLocation,
            EditorCommandUserInfo.rangeLength: match.rangeLength
        ]
#if os(macOS)
        if let hostWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = hostWindowNumber
        }
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .moveCursorToRange, object: nil, userInfo: userInfo)
        }
    }

    private func scheduleWordCountRefresh(for text: String) {
        if largeFileModeEnabled || currentDocumentUTF16Length >= 300_000 {
            wordCountTask?.cancel()
            if statusWordCount != 0 {
                statusWordCount = 0
            }
            return
        }
        let snapshot = text
        wordCountTask?.cancel()
        wordCountTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let count = viewModel.wordCount(for: snapshot)
            await MainActor.run {
                statusWordCount = count
            }
        }
    }

}
