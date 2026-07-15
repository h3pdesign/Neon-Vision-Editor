// ContentView.swift
// Main SwiftUI container for Neon Vision Editor. Hosts the single-document editor UI,
// toolbar actions, AI integration, syntax highlighting, line numbers, and sidebar TOC.

// MARK: - Imports
import SwiftUI
import Foundation
import Observation
import UniformTypeIdentifiers
import OSLog
import Dispatch
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

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        forwardedDelegate?.window?(window, willEncodeRestorableState: state)
    }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        forwardedDelegate?.window?(window, didDecodeRestorableState: state)
    }
}
#endif

private struct ContentViewWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


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

// MARK: - Root View

// Manages the editor area, toolbar, popovers, and bridges to the view model for file I/O and metrics.
struct ContentView: View {
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

    enum PlistViewMode: String, CaseIterable, Identifiable {
        case structure
        case text

        var id: String { rawValue }
    }

    enum ProjectSidebarCreationKind: String {
        case file
        case folder

        var title: String {
            switch self {
            case .file:
                return NSLocalizedString("New File", comment: "Project sidebar creation title for files")
            case .folder:
                return NSLocalizedString("New Folder", comment: "Project sidebar creation title for folders")
            }
        }

        var namePlaceholder: String {
            switch self {
            case .file:
                return NSLocalizedString("File name", comment: "Project sidebar file name placeholder")
            case .folder:
                return NSLocalizedString("Folder name", comment: "Project sidebar folder name placeholder")
            }
        }
    }

    struct DelimitedTableSnapshot: Sendable {
        var header: [String]
        var rows: [[String]]
        let totalRows: Int
        let displayedRows: Int
        let truncated: Bool
    }

    struct DelimitedTableParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct PlistStructureNode: Identifiable, Hashable {
        let id: String
        let key: String
        let kind: String
        let value: String
        let children: [PlistStructureNode]

        var optionalChildren: [PlistStructureNode]? {
            children.isEmpty ? nil : children
        }
    }

    let startupBehavior: StartupBehavior
    let safeModeMessage: String?

    init(startupBehavior: StartupBehavior = .standard, safeModeMessage: String? = nil) {
        self.startupBehavior = startupBehavior
        self.safeModeMessage = safeModeMessage
    }

    var isSafeModeActive: Bool {
        startupBehavior == .safeMode
    }

    var effectiveShowCodeMinimap: Bool {
        showCodeMinimap && !isSafeModeActive
    }

    enum EditorPerformanceThresholds {
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
    static let completionSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "InlineCompletion")
    nonisolated static func plistISO8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    struct CompletionCacheEntry {
        let suggestion: String
        let createdAt: Date
    }

    struct LargeFileEstimateCacheEntry {
        let tabID: UUID?
        let contentRevision: Int?
        let language: String
        let byteThreshold: Int
        let lineThreshold: Int
        let exceedsByteThreshold: Bool
        let exceedsLineThreshold: Bool
    }

    struct SavedDraftTabSnapshot: Codable {
        let name: String
        let content: String
        let language: String
        let fileURLString: String?
    }

    struct SavedDraftSnapshot: Codable {
        let tabs: [SavedDraftTabSnapshot]
        let selectedIndex: Int?
        let createdAt: Date
    }

    // Environment-provided view model and theme/error bindings
    @Environment(EditorViewModel.self) var viewModel
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    @EnvironmentObject var appUpdateManager: AppUpdateManager
    @Environment(\.colorScheme) var colorScheme
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
#endif
#if os(macOS)
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettingsAction
#endif
    @Environment(\.showGrokError) var showGrokError
    @Environment(\.grokErrorMessage) var grokErrorMessage

    // Single-document fallback state (used when no tab model is selected)
    @AppStorage("SelectedAIModel") var selectedModelRaw: String = AIModel.appleIntelligence.rawValue
    @State var singleContent: String = ""
    @State var singleLanguage: String = "plain"
    @State var caretStatus: String = "Ln 1, Col 1"
    @AppStorage("SettingsEditorFontSize") var editorFontSize: Double = 14
    @AppStorage("SettingsEditorFontName") var editorFontName: String = ""
    @AppStorage("SettingsLineHeight") var editorLineHeight: Double = 1.0
    @AppStorage("SettingsShowLineNumbers") var showLineNumbers: Bool = true
    @AppStorage("SettingsHighlightCurrentLine") var highlightCurrentLine: Bool = false
    @AppStorage("SettingsHighlightMatchingBrackets") var highlightMatchingBrackets: Bool = false
    @AppStorage("SettingsShowIndentationGuides") var showIndentationGuides: Bool = false
    @AppStorage("SettingsShowScopeGuides") var showScopeGuides: Bool = false
    @AppStorage("SettingsHighlightScopeBackground") var highlightScopeBackground: Bool = false
    @AppStorage("SettingsShowCodeMinimap") var showCodeMinimap: Bool = false
    @AppStorage("SettingsLineWrapEnabled") var settingsLineWrapEnabled: Bool = true
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
    @AppStorage("ToolbarCollapsed") var startsWithToolbarCollapsed: Bool = false
    @State var isToolbarCollapsed: Bool = false
    @AppStorage("SettingsAppearance") var appearance: String = "system"
    @AppStorage("SettingsTemplateLanguage") private var settingsTemplateLanguage: String = "swift"
    @AppStorage("SettingsThemeName") private var settingsThemeName: String = "Neon Glow"
    @AppStorage("SettingsThemeBoldKeywords") private var settingsThemeBoldKeywords: Bool = false
    @AppStorage("SettingsThemeItalicComments") private var settingsThemeItalicComments: Bool = false
    @AppStorage("SettingsThemeUnderlineLinks") private var settingsThemeUnderlineLinks: Bool = false
    @AppStorage("SettingsThemeBoldMarkdownHeadings") private var settingsThemeBoldMarkdownHeadings: Bool = false
    @AppStorage("SettingsThemeHexOverrides") private var settingsThemeHexOverridesData: Data = Data()
    @State var lastProviderUsed: String = "Apple"
    @State private var highlightRefreshToken: Int = 0
    @State var editorExternalMutationRevision: Int = 0

    // Persisted API tokens for external providers
    @State var grokAPIToken: String = ""
    @State var openAIAPIToken: String = ""
    @State var geminiAPIToken: String = ""
    @State var anthropicAPIToken: String = ""
    @State var openCodeGoAPIToken: String = ""
    @AppStorage("OpenCodeGoModelID") var openCodeGoModelID: String = OpenCodeGoConfig.defaultModel

    // Debounce/cancellation handles for inline completion
    @State var completionDebounceTask: Task<Void, Never>?
    @State var completionTask: Task<Void, Never>?
    @State var lastCompletionTriggerSignature: String = ""
    @State var isApplyingCompletion: Bool = false
    @State var completionCache: [String: CompletionCacheEntry] = [:]
    @State private var pendingHighlightRefresh: DispatchWorkItem?
    @State var pendingSessionPersistenceWorkItem: DispatchWorkItem?
    @State var pendingDraftSnapshotPersistenceWorkItem: DispatchWorkItem?
    @State private var pendingExternalConflictRefresh: DispatchWorkItem?
    @State private var largeFileEstimateCache: LargeFileEstimateCacheEntry?
#if os(iOS) || os(visionOS)
    @AppStorage("EnableTranslucentWindow") var enableTranslucentWindow: Bool = true
#else
    @AppStorage("EnableTranslucentWindow") var enableTranslucentWindow: Bool = false
#endif
#if os(iOS) || os(visionOS)
    @State private var previousKeyboardAccessoryVisibility: Bool? = nil
    @State var markdownPreviewSheetDetent: PresentationDetent = .medium
#endif
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") var macTranslucencyModeRaw: String = "balanced"
#endif

    @State var showFindReplace: Bool = false
    @State var showSettingsSheet: Bool = false
    @State var showUpdateDialog: Bool = false
    @State var findQuery: String = ""
    @State var replaceQuery: String = ""
    @State var findUsesRegex: Bool = false
    @State var findCaseSensitive: Bool = false
    @State var findStatusMessage: String = ""
    @State var findMatchCount: Int = 0
    @State var findScope: SearchScope = .currentFile
    @State var findInFilesScope: SearchScope = .project
    @State var iOSFindCursorLocation: Int = 0
    @State var iOSLastFindFingerprint: String = ""
    @State var showProjectStructureSidebar: Bool = false
    @State var showCompactSidebarSheet: Bool = false
    @State var showCompactProjectSidebarSheet: Bool = false
    @State var projectRootFolderURL: URL? = nil
    @State var gitViewModel = GitViewModel()
    @State var showGitTab: Bool = false
    @State var projectTreeNodes: [ProjectTreeNode] = []
    @State var projectTreeRefreshGeneration: Int = 0
    @State var projectTreeRevealURL: URL? = nil
    @AppStorage("SettingsShowSupportedProjectFilesOnly") var showSupportedProjectFilesOnly: Bool = true
    @AppStorage("SettingsShowHiddenProjectFiles") var showHiddenProjectFiles: Bool = false
    @AppStorage(ProjectIgnoredFolders.defaultsKey) var projectIgnoredFolderNamesRaw: String = ProjectIgnoredFolders.defaultRawValue
    @AppStorage("SettingsShowInvisibleCharacters") var showInvisibleCharacters: Bool = false
    @State var projectOverrideIndentWidth: Int? = nil
    @State var projectOverrideLineWrapEnabled: Bool? = nil
    @State var showProjectFolderPicker: Bool = false
    @State var projectFolderSecurityURL: URL? = nil
    @State var pendingCloseTabID: UUID? = nil
    @State var showUnsavedCloseDialog: Bool = false
    @State var showCloseAllTabsDialog: Bool = false
    @State private var showExternalConflictDialog: Bool = false
    @State private var showRemoteSaveIssueDialog: Bool = false
    @State private var showExternalConflictCompareSheet: Bool = false
    @State private var externalConflictCompareSnapshot: EditorViewModel.ExternalFileComparisonSnapshot?
    @State private var externalConflictDiff: DocumentDiff?
    @State private var showRemoteConflictCompareSheet: Bool = false
    @State private var remoteConflictCompareSnapshot: EditorViewModel.RemoteConflictComparisonSnapshot?
    @State private var remoteConflictDiff: DocumentDiff?
    @State var showCompareTabsPicker: Bool = false
    @State var documentDiffPresentation: DocumentDiffPresentation?
    @State var sidebarCompareDiffPresentation: DocumentDiffPresentation?
    @State var showFolderCompare: Bool = false
    @State var folderDiffPresentation: DocumentDiffPresentation? = nil
    @State var showClearEditorConfirmDialog: Bool = false
    @State var showIOSFileImporter: Bool = false
    @State var showIOSFileExporter: Bool = false
    @State var showUnsupportedFileAlert: Bool = false
    @State var unsupportedFileName: String = ""
    @State var showProjectItemCreationPrompt: Bool = false
    @State var projectItemCreationNameDraft: String = ""
    @State var projectItemCreationKind: ProjectSidebarCreationKind = .file
    @State var projectItemCreationParentURL: URL? = nil
    @State var showProjectItemRenamePrompt: Bool = false
    @State var projectItemRenameNameDraft: String = ""
    @State var projectItemRenameSourceURL: URL? = nil
    @State var showProjectItemDeleteConfirmation: Bool = false
    @State var projectItemDeleteTargetURL: URL? = nil
    @State var projectItemDeleteTargetName: String = ""
    @State var showProjectItemOperationErrorAlert: Bool = false
    @State var projectItemOperationErrorMessage: String = ""
    @State var iosExportDocument: PlainTextDocument = PlainTextDocument(text: "")
    @State var iosExportFilename: String = "Untitled.txt"
    @State var iosExportContentType: UTType = .text
    @State var iosExportTabID: UUID? = nil
    @State var showMarkdownPDFExporter: Bool = false
    @State var markdownPDFExportDocument: PDFExportDocument = PDFExportDocument()
    @State var markdownPDFExportFilename: String = "Markdown-Preview.pdf"
    @State var markdownPDFExportErrorMessage: String?
    @State var markdownPreviewActionStatusMessage: String = ""
    @State var markdownPreviewActionStatusToken: UUID = UUID()
    @State var showQuickSwitcher: Bool = false
    @State var quickSwitcherQuery: String = ""
    @State var showGoToLine: Bool = false
    @State var goToLineInput: String = ""
    @State var showGoToSymbol: Bool = false
    @State var goToSymbolQuery: String = ""
    @State var quickSwitcherProjectFileURLs: [URL] = []
    @State var projectFileIndexSnapshot: ProjectFileIndex.Snapshot = .empty
    @State var isProjectFileIndexing: Bool = false
    @State var projectFileIndexRefreshGeneration: Int = 0
    @State var projectFileIndexTask: Task<Void, Never>? = nil
    @State var projectFolderMonitorSource: DispatchSourceFileSystemObject? = nil
    @State var pendingProjectFolderRefreshWorkItem: DispatchWorkItem? = nil
    @State var codeMinimapViewports: [UUID: CodeMinimapViewport] = [:]
    @State var fileTabBarIsScrolledUnderTOCEdge: Bool = false
    @State var tabDropInsertionTabID: UUID? = nil
    @State var tabDropInsertionBefore: Bool = true
    @State var previousSelectedTabID: UUID? = nil
    @State var quickSwitcherRecentItemIDs: [String] = []
    @State var recentFilesRefreshToken: UUID = UUID()
    @State var sharedImportsRefreshToken: UUID = UUID()
    @State var currentSelectionSnapshotText: String = ""
    @State var codeSnapshotPayload: CodeSnapshotPayload?
    @State var showFindInFiles: Bool = false
    @State var findInFilesQuery: String = ""
    @State var findInFilesCaseSensitive: Bool = false
    @State var findInFilesReplaceQuery: String = ""
    @State var findInFilesResults: [FindInFilesMatch] = []
    @State var findInFilesSelectedMatchIDs: Set<String> = []
    @State var findInFilesStatusMessage: String = ""
    @State var findInFilesSourceMessage: String = ""
    @State var findInFilesTask: Task<Void, Never>?
    @State var findInFilesReplaceTask: Task<Void, Never>?
    @State var isApplyingFindInFilesReplace: Bool = false
    @State var projectSidebarFindInFilesRequestToken: Int = 0
    @State var projectSidebarTerminalRequestToken: Int = 0
    @State var splitSecondaryTabID: UUID?
    @State var statusWordCount: Int = 0
    @State var statusLineCount: Int = 1
    @State var wordCountTask: Task<Void, Never>?
    @AppStorage("SettingsStatusBarShowCursor") var statusBarShowCursor: Bool = true
    @AppStorage("SettingsStatusBarShowLineCount") var statusBarShowLineCount: Bool = true
    @AppStorage("SettingsStatusBarShowWordCount") var statusBarShowWordCount: Bool = true
    @AppStorage("SettingsStatusBarShowEncoding") var statusBarShowEncoding: Bool = true
    @AppStorage("SettingsStatusBarShowLineEndings") var statusBarShowLineEndings: Bool = true
    @AppStorage("SettingsStatusBarShowIndentation") var statusBarShowIndentation: Bool = true
    @AppStorage("SettingsStatusBarShowSelection") var statusBarShowSelection: Bool = true
    @AppStorage("SettingsStatusBarShowFileSize") var statusBarShowFileSize: Bool = false
    @AppStorage("SettingsStatusBarShowGit") var statusBarShowGit: Bool = true
    @AppStorage("SettingsStatusBarShowMarkdownPreview") var statusBarShowMarkdownPreview: Bool = true
    @AppStorage("EditorVimModeEnabled") var vimModeEnabled: Bool = false
    @State var vimInsertMode: Bool = true
    @State var safeModeRecoveryPreparedForNextLaunch: Bool = false
    @State var droppedFileLoadInProgress: Bool = false
    @State var droppedFileProgressDeterminate: Bool = true
    @State var droppedFileLoadProgress: Double = 0
    @State var droppedFileLoadLabel: String = ""
    @State var largeFileModeEnabled: Bool = false
    @State var settingsSheetDetent: PresentationDetent = .large
    @SceneStorage("ProjectSidebarWidth") var projectSidebarWidth: Double = 450
    @State var projectSidebarResizeStartWidth: CGFloat? = nil
#if os(macOS)
    @SceneStorage("TOCSidebarWidth") var tocSidebarWidth: Double = 250
    @State var tocSidebarResizeStartWidth: CGFloat? = nil
    @State var isTOCSidebarResizeHandleHovered: Bool = false
#endif
    @State var delimitedViewMode: DelimitedViewMode = .table
    @State var delimitedTableSnapshot: DelimitedTableSnapshot? = nil
    @State var delimitedColumnWidths: [Int: Double] = [:]
    @State var isBuildingDelimitedTable: Bool = false
    @State var delimitedTableStatus: String = ""
    @State var delimitedParseTask: Task<Void, Never>? = nil
    @State var plistViewMode: PlistViewMode = .structure
    @State var plistStructureNodes: [PlistStructureNode] = []
    @State var plistStructureStatus: String = ""
    @State var isBuildingPlistStructure: Bool = false
    @State var plistParseTask: Task<Void, Never>? = nil
    @AppStorage("SettingsProjectNavigatorPlacement") var projectNavigatorPlacementRaw: String = ProjectNavigatorPlacement.trailing.rawValue
    @AppStorage("SettingsPerformancePreset") var performancePresetRaw: String = PerformancePreset.balanced.rawValue
    @AppStorage("SettingsLargeFileOpenMode") var largeFileOpenModeRaw: String = "deferred"
    @AppStorage("SettingsRemoteSessionsEnabled") private var remoteSessionsEnabled: Bool = false
    @AppStorage("SettingsRemotePreparedTarget") private var remotePreparedTarget: String = ""
    @State private var remoteSessionStore = RemoteSessionStore.shared
#if os(iOS) || os(visionOS)
    @AppStorage("SettingsForceLargeFileMode") var forceLargeFileMode: Bool = false
    @AppStorage("SettingsMobileEditingStatusPresetEnabled") var mobileEditingStatusPresetEnabled: Bool = false
    @AppStorage("SettingsShowKeyboardAccessoryBarIOS") var showKeyboardAccessoryBarIOS: Bool = false
    @AppStorage("SettingsShowBottomActionBarIOS") var showBottomActionBarIOS: Bool = true
    @AppStorage("SettingsUseLiquidGlassToolbarIOS") var shouldUseLiquidGlass: Bool = true
    @AppStorage("SettingsToolbarIconsBlueIOS") var toolbarIconsBlueIOS: Bool = false
    @AppStorage("SettingsToolbarShowSearchIOS") var toolbarShowSearchIOS: Bool = true
    @AppStorage("SettingsToolbarShowCompareIOS") var toolbarShowCompareIOS: Bool = true
    @AppStorage("SettingsToolbarShowEditorUtilityIOS") var toolbarShowEditorUtilityIOS: Bool = true
    @AppStorage("SettingsToolbarShowAppearanceIOS") var toolbarShowAppearanceIOS: Bool = true
    @AppStorage("SettingsToolbarFavoriteCountIOS") var toolbarFavoriteCountIOS: Int = 8
    @AppStorage("SettingsToolbarShowOpenFileIOS") var toolbarShowOpenFileIOS: Bool = true
    @AppStorage("SettingsToolbarShowUndoIOS") var toolbarShowUndoIOS: Bool = true
    @AppStorage("SettingsToolbarShowSettingsIOS") var toolbarShowSettingsIOS: Bool = true
    @AppStorage("SettingsToolbarShowHelpIOS") var toolbarShowHelpIOS: Bool = true
    @AppStorage("SettingsToolbarUseCustomFiveIOS") var toolbarUseCustomFiveIOS: Bool = false
    @AppStorage("SettingsToolbarCustomFiveIDsIOS") var toolbarCustomFiveIDsIOS: String = ""
    @State var isPhoneEditorFocused: Bool = false
    @State var isPhoneSoftwareKeyboardVisible: Bool = false
    @State var isPhoneStatusBarExpanded: Bool = false
    @State var phoneStatusAutoCollapseTask: Task<Void, Never>? = nil
#endif
    @AppStorage("HasSeenWelcomeTourV1") var hasSeenWelcomeTourV1: Bool = false
    @AppStorage("WelcomeTourSeenRelease") var welcomeTourSeenRelease: String = ""
    @AppStorage("AppLaunchCountV1") var appLaunchCount: Int = 0
    @AppStorage("HasShownSupportPromptV1") var hasShownSupportPromptV1: Bool = false
    @AppStorage("SharedImportAccessAllowed") var sharedImportAccessAllowed: Bool = false
    @State var showWelcomeTour: Bool = false
    @State var showEditorHelp: Bool = false
    @State var showSupportPromptSheet: Bool = false
    @State var showSharedImportAccessExplanation: Bool = false
    @State var pendingSharedImportURL: URL? = nil
    @State var pendingSharedImportURLs: [URL] = []
    @State var showSharedImportDestinationDialog: Bool = false
    @State private var sharedImportNotificationObserver: SharedImportNotificationObserver? = nil
#if os(macOS)
    @State var hostWindowNumber: Int? = nil
    @AppStorage("ShowBracketHelperBarMac") var showBracketHelperBarMac: Bool = false
    @AppStorage("SettingsToolbarSymbolsColorMac") var toolbarSymbolsColorMacRaw: String = "blue"
    @State private var windowCloseConfirmationDelegate: WindowCloseConfirmationDelegate? = nil
#endif
    @State var showMarkdownPreviewPane: Bool = false
#if os(macOS)
    @AppStorage("MarkdownPreviewTemplateMac") var markdownPreviewTemplateRaw: String = "default"
#elseif os(iOS) || os(visionOS)
    @AppStorage("MarkdownPreviewTemplateIOS") var markdownPreviewTemplateRaw: String = "default"
#endif
    @AppStorage("MarkdownPreviewBackgroundStyle") var markdownPreviewBackgroundStyleRaw: String = "automatic"
    @AppStorage("MarkdownPreviewDialect") var markdownPreviewDialectRaw: String = ContentView.MarkdownPreviewDialect.gfm.rawValue
    @AppStorage("MarkdownPreviewPDFExportMode") var markdownPDFExportModeRaw: String = "paginated-fit"
    @State var markdownPreviewRenderedHTML: String = ""
    @State var markdownPreviewRenderSignature: String = ""
    @State var markdownPreviewRenderTask: Task<Void, Never>? = nil
    @State var isMarkdownPreviewRendering: Bool = false
    @State var showLanguageSetupPrompt: Bool = false
    @State var languagePromptSelection: String = "plain"
    @State var languagePromptInsertTemplate: Bool = false
    @State var showLanguageSearchSheet: Bool = false
    @State private var whitespaceInspectorMessage: String? = nil
    @State var didApplyStartupBehavior: Bool = false
    @State private var didRunInitialWindowLayoutSetup: Bool = false
    @State private var pendingLargeFileModeReevaluation: DispatchWorkItem? = nil
    @State var liveContainerWidth: CGFloat = 0
    @State var recoverySnapshotIdentifier: String = UUID().uuidString
    @State var lastCaretLocation: Int = 0
    @State var sessionCaretByFileURL: [String: Int] = [:]
#if os(macOS)
    @State var isProjectSidebarResizeHandleHovered: Bool = false
#endif
    let quickSwitcherRecentsDefaultsKey = "QuickSwitcherRecentItemsV1"

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

    var projectNavigatorPlacement: ProjectNavigatorPlacement {
        ProjectNavigatorPlacement(rawValue: projectNavigatorPlacementRaw) ?? .trailing
    }

    private var performancePreset: PerformancePreset {
        PerformancePreset(rawValue: performancePresetRaw) ?? .balanced
    }

    var minimumProjectSidebarWidth: CGFloat { 300 }
    var maximumProjectSidebarWidth: CGFloat { 680 }
    var projectSidebarResizeHandleWidth: CGFloat {
#if os(macOS)
        1
#else
        16
#endif
    }
    var projectSidebarResizeHitTargetWidth: CGFloat {
#if os(macOS)
        22
#else
        16
#endif
    }
#if os(macOS)
    var minimumTOCSidebarWidth: CGFloat { 200 }
    var maximumTOCSidebarWidth: CGFloat { 600 }
    var tocSidebarResizeHandleWidth: CGFloat { 1 }
    var tocSidebarResizeHitTargetWidth: CGFloat { 22 }
#endif

    var clampedProjectSidebarWidth: CGFloat {
        let clamped = min(max(projectSidebarWidth, Double(minimumProjectSidebarWidth)), Double(maximumProjectSidebarWidth))
        return CGFloat(clamped)
    }

#if os(macOS)
    var clampedTOCSidebarWidth: CGFloat {
        let clamped = min(max(tocSidebarWidth, Double(minimumTOCSidebarWidth)), Double(maximumTOCSidebarWidth))
        return CGFloat(clamped)
    }

#endif

    var isDelimitedFileLanguage: Bool {
        let lower = currentLanguage.lowercased()
        return lower == "csv" || lower == "tsv"
    }

    var delimitedSeparator: Character {
        currentLanguage.lowercased() == "tsv" ? "\t" : ","
    }

    var shouldShowDelimitedTable: Bool {
        isDelimitedFileLanguage && delimitedViewMode == .table
    }

    var isPlistDocument: Bool {
        if viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "plist" {
            return true
        }
        let lowerLanguage = currentLanguage.lowercased()
        if lowerLanguage == "plist" {
            return true
        }
        guard lowerLanguage == "xml" else { return false }
        let sample = currentContent.prefix(512).lowercased()
        return sample.contains("<plist")
    }

    var shouldShowPlistStructure: Bool {
        isPlistDocument && plistViewMode == .structure
    }

    var selectedDelimitedViewModePersistenceKey: String? {
        guard let url = viewModel.selectedTab?.fileURL?.standardizedFileURL else { return nil }
        return url.path.isEmpty ? nil : url.path
    }

    func persistedDelimitedViewMode(for key: String) -> DelimitedViewMode? {
        let stored = UserDefaults.standard.dictionary(forKey: "DelimitedViewModeByFilePathV1") as? [String: String] ?? [:]
        guard let rawValue = stored[key] else { return nil }
        return DelimitedViewMode(rawValue: rawValue)
    }

    func persistDelimitedViewMode(_ mode: DelimitedViewMode, for key: String) {
        var stored = UserDefaults.standard.dictionary(forKey: "DelimitedViewModeByFilePathV1") as? [String: String] ?? [:]
        stored[key] = mode.rawValue
        UserDefaults.standard.set(stored, forKey: "DelimitedViewModeByFilePathV1")
    }

    func syncSecondaryViewModesForCurrentTab() {
        if isDelimitedFileLanguage {
            if let key = selectedDelimitedViewModePersistenceKey,
               let persisted = persistedDelimitedViewMode(for: key) {
                delimitedViewMode = persisted
            } else {
                delimitedViewMode = .table
            }
        } else {
            delimitedViewMode = .text
        }

        if isPlistDocument {
            plistViewMode = .structure
        } else {
            plistViewMode = .text
        }
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
            case .subtle: return 0.62
            case .balanced: return 0.50
            case .vibrant: return 0.38
            }
        }

        var toolbarOpacity: Double {
            switch self {
            case .subtle: return 0.54
            case .balanced: return 0.44
            case .vibrant: return 0.34
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
    private var macSolidSurfaceColor: Color {
        currentEditorTheme(colorScheme: colorScheme).background
    }
    private var macChromeBackgroundStyle: AnyShapeStyle {
        if enableTranslucentWindow {
            return macUnifiedTranslucentMaterialStyle
        }
        return AnyShapeStyle(macSolidSurfaceColor)
    }

    private var macToolbarBackgroundStyle: AnyShapeStyle {
        if enableTranslucentWindow {
            return AnyShapeStyle(macTranslucencyMode.material.opacity(macTranslucencyMode.toolbarOpacity))
        }
        return AnyShapeStyle(macSolidSurfaceColor)
    }

    private var macInterPaneBackgroundStyle: AnyShapeStyle {
        if enableTranslucentWindow {
            return macUnifiedTranslucentMaterialStyle
        }
        return AnyShapeStyle(macSolidSurfaceColor)
    }
#elseif os(iOS) || os(visionOS)
    var primaryGlassMaterial: Material { colorScheme == .dark ? .regularMaterial : .ultraThinMaterial }
    var toolbarFallbackColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.34) : Color.white.opacity(0.86)
    }
    var iOSNonTranslucentSurfaceColor: Color {
        currentEditorTheme(colorScheme: colorScheme).background
    }
    var useIOSUnifiedSolidSurfaces: Bool {
        !enableTranslucentWindow
    }
    var toolbarDensityScale: CGFloat { 1.0 }
    var toolbarDensityOpacity: Double { 1.0 }

#endif

    var editorSurfaceBackgroundStyle: AnyShapeStyle {
#if os(macOS)
        if enableTranslucentWindow {
            return macUnifiedTranslucentMaterialStyle
        }
        return AnyShapeStyle(macSolidSurfaceColor)
#else
        if useIOSUnifiedSolidSurfaces {
            return AnyShapeStyle(iOSNonTranslucentSurfaceColor)
        }
        return enableTranslucentWindow ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear)
#endif
    }

    private var settingsSheetDetents: Set<PresentationDetent> {
#if os(iOS) || os(visionOS)
        #if os(visionOS)
        return [.large]
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [.fraction(0.72), .large]
        }
        return [.large]
        #endif
#else
        return [.large]
#endif
    }

#if os(visionOS)
    private var visionSettingsSheetSize: (width: CGFloat, height: CGFloat) {
        switch settingsActiveTab {
        case "appearance":
            return (980, 620)
        case "toolbar", "ai", "remote", "shortcuts", "diagnostics":
            return (860, 540)
        case "general", "editor":
            return (980, 640)
        default:
            return (900, 600)
        }
    }

#endif

#if os(macOS)
    private var macTabBarStripHeight: CGFloat { 36 }
#endif

    var useIOSUnifiedTopHost: Bool {
#if os(iOS) || os(visionOS)
        UIDevice.current.userInterfaceIdiom == .phone || UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    var tabBarLeadingPadding: CGFloat {
#if os(iOS) || os(visionOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Keep tabs clear of iPad window controls in narrow/multitasking layouts.
            return horizontalSizeClass == .compact ? 112 : 10
        }
#else
        if shouldUseSplitView {
            return 4
        }
#endif
        return 10
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
        updateWindowChrome(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.updateWindowChrome(window)
        }
        if let number {
            WindowViewModelRegistry.shared.register(viewModel, for: number)
        }
    }

    private func updateWindowChrome(_ window: NSWindow? = nil) {
        guard let targetWindow = window ?? hostWindowNumber.flatMap({ NSApp.window(withWindowNumber: $0) }) else { return }
        targetWindow.subtitle = windowSubtitleText
        if #available(macOS 11.0, *) {
            targetWindow.titlebarSeparatorStyle = .none
        }
        if !enableTranslucentWindow {
            let bg = currentEditorTheme(colorScheme: colorScheme).background
            targetWindow.backgroundColor = NSColor(bg)
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
                    Button(action: {
                        requestBracketHelperInsert(token)
                    }) {
                        Text(token)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Insert \(token)"))
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
                // Caret notifications can arrive for every typed character. Keep this path
                // layout-only; content metrics refresh from the document-change pipeline.
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorSelectionDidChange)) { notif in
                let selection = (notif.object as? String) ?? ""
                currentSelectionSnapshotText = selection
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorViewportDidChange)) { notif in
                guard let idString = notif.userInfo?[EditorCommandUserInfo.documentID] as? String,
                      let documentID = UUID(uuidString: idString),
                      let top = notif.userInfo?[EditorCommandUserInfo.viewportTopFraction] as? Double,
                      let height = notif.userInfo?[EditorCommandUserInfo.viewportHeightFraction] as? Double else { return }
                codeMinimapViewports[documentID] = CodeMinimapViewport(
                    topFraction: top,
                    heightFraction: height
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .editorRequestCodeSnapshotFromSelection)) { _ in
                presentCodeSnapshotComposer()
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

        let viewWithDroppedFileLoadEvents = AnyView(
            viewWithClipboardEvents
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
        )

        let viewWithSelectionObservers = AnyView(
            viewWithDroppedFileLoadEvents
            .onChange(of: viewModel.selectedTab?.id) { _, _ in
                editorExternalMutationRevision &+= 1
                updateLargeFileModeForCurrentContext()
                scheduleLargeFileModeReevaluation(after: 0.9)
                scheduleHighlightRefresh()
                if let selectedID = viewModel.selectedTab?.id {
                    scheduleExternalConflictRefresh(for: selectedID)
                }
                restoreCaretForSelectedSessionFileIfAvailable()
                scheduleSessionPersistence()
            }
            .onChange(of: viewModel.selectedTab?.isLoadingContent ?? false) { _, isLoading in
                if isLoading {
                    let shouldPreEnableLargeMode =
                        droppedFileLoadInProgress ||
                        viewModel.selectedTab?.isLargeFileCandidate == true ||
                        currentDocumentUTF16Length >= 300_000
                    if shouldPreEnableLargeMode, !largeFileModeEnabled {
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
            .onChange(of: viewModel.pendingRemoteSaveIssue?.tabID) { _, issueTabID in
                if issueTabID != nil {
                    showRemoteSaveIssueDialog = true
                }
            }
        )

        return viewWithSelectionObservers
            .onChange(of: showRemoteSaveIssueDialog) { _, isPresented in
                if !isPresented, viewModel.pendingRemoteSaveIssue != nil {
                    viewModel.dismissRemoteSaveIssue()
                }
            }
    }

    private func handlePastedTextNotification(_ notif: Notification) {
        guard let pasted = notif.object as? String else {
            DispatchQueue.main.async {
                updateLargeFileModeForCurrentContext()
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
            updateLargeFileModeForCurrentContext()
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
            updateLargeFileModeForCurrentContext()
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
            updateLargeFileModeForCurrentContext()
            scheduleHighlightRefresh()
        }
    }

    func updateLargeFileMode(for text: String) {
        if droppedFileLoadInProgress {
            if !largeFileModeEnabled {
                largeFileModeEnabled = true
                scheduleHighlightRefresh()
            }
            return
        }
        if viewModel.selectedTab?.isLoadingContent == true {
            if (viewModel.selectedTab?.isLargeFileCandidate == true || currentDocumentUTF16Length >= 300_000),
               !largeFileModeEnabled {
                largeFileModeEnabled = true
                scheduleHighlightRefresh()
            }
            return
        }
        if viewModel.selectedTab?.isLargeFileCandidate == true {
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
        #if os(iOS) || os(visionOS)
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
        let estimate = largeFileEstimate(
            for: text,
            language: lowerLanguage,
            byteThreshold: byteThreshold,
            lineThreshold: lineThreshold,
            isCSVLike: isCSVLike
        )
        let exceedsByteThreshold = estimate.exceedsByteThreshold
        let exceedsLineThreshold = estimate.exceedsLineThreshold
#if os(iOS) || os(visionOS)
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

    private func largeFileEstimate(
        for text: String,
        language: String,
        byteThreshold: Int,
        lineThreshold: Int,
        isCSVLike: Bool
    ) -> (exceedsByteThreshold: Bool, exceedsLineThreshold: Bool) {
        let selectedTab = viewModel.selectedTab
        let tabID = selectedTab?.id
        let revision = selectedTab?.contentRevision
        if let revision,
           let cached = largeFileEstimateCache,
           cached.tabID == tabID,
           cached.contentRevision == revision,
           cached.language == language,
           cached.byteThreshold == byteThreshold,
           cached.lineThreshold == lineThreshold {
            return (cached.exceedsByteThreshold, cached.exceedsLineThreshold)
        }

        let exceedsByteThreshold = text.utf8.count >= byteThreshold
        let exceedsLineThreshold = largeFileLineEstimate(
            text,
            lineThreshold: lineThreshold,
            isCSVLike: isCSVLike,
            shortCircuit: exceedsByteThreshold
        )
        if let revision {
            largeFileEstimateCache = LargeFileEstimateCacheEntry(
                tabID: tabID,
                contentRevision: revision,
                language: language,
                byteThreshold: byteThreshold,
                lineThreshold: lineThreshold,
                exceedsByteThreshold: exceedsByteThreshold,
                exceedsLineThreshold: exceedsLineThreshold
            )
        }
        return (exceedsByteThreshold, exceedsLineThreshold)
    }

    private func largeFileLineEstimate(
        _ text: String,
        lineThreshold: Int,
        isCSVLike: Bool,
        shortCircuit: Bool
    ) -> Bool {
        if shortCircuit { return true }
        var lineBreaks = 0
        var currentLineLength = 0
        let csvLongLineThreshold = 16_000
        for codeUnit in text.utf16 {
            if codeUnit == 10 {
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
    }

    private func updateLargeFileModeForCurrentContext() {
        if droppedFileLoadInProgress {
            if !largeFileModeEnabled {
                largeFileModeEnabled = true
                scheduleHighlightRefresh()
            }
            return
        }
        if viewModel.selectedTab?.isLoadingContent == true {
            if (viewModel.selectedTab?.isLargeFileCandidate == true || currentDocumentUTF16Length >= 300_000),
               !largeFileModeEnabled {
                largeFileModeEnabled = true
                scheduleHighlightRefresh()
            }
            return
        }
        if viewModel.selectedTab?.isLargeFileCandidate == true || currentDocumentUTF16Length >= 300_000 {
            if !largeFileModeEnabled {
                largeFileModeEnabled = true
                scheduleHighlightRefresh()
            }
            return
        }
        guard let snapshot = currentContentSnapshot(maxUTF16Length: 280_000) else { return }
        updateLargeFileMode(for: snapshot)
    }

    private func currentContentSnapshot(maxUTF16Length: Int) -> String? {
        let snapshot = currentContentBinding.wrappedValue
        guard (snapshot as NSString).length <= maxUTF16Length else { return nil }
        return snapshot
    }

    private func refreshSecondaryContentViewsIfNeeded() {
        guard let snapshot = currentContentSnapshot(maxUTF16Length: 280_000) else {
            scheduleWordCountRefreshForLargeContent()
            if shouldShowDelimitedTable {
                scheduleDelimitedTableRebuild()
            } else {
                delimitedParseTask?.cancel()
                isBuildingDelimitedTable = false
                delimitedTableSnapshot = nil
            }
            if shouldShowPlistStructure {
                plistParseTask?.cancel()
                isBuildingPlistStructure = false
                plistStructureNodes = []
            }
            return
        }
        scheduleWordCountRefresh(for: snapshot)
        if shouldShowDelimitedTable {
            scheduleDelimitedTableRebuild()
        }
        if shouldShowPlistStructure {
            schedulePlistStructureRebuild(for: snapshot)
        }
    }

    private func scheduleWordCountRefreshForLargeContent() {
        wordCountTask?.cancel()
        if statusWordCount != 0 {
            statusWordCount = 0
        }
        let snapshot = currentContentBinding.wrappedValue
        let expectedTabID = viewModel.selectedTabID
        let expectedContentRevision = viewModel.selectedTab?.contentRevision
        wordCountTask = Task(priority: .utility) {
            let lineCount = Self.lineCount(for: snapshot)
            await MainActor.run {
                guard viewModel.selectedTabID == expectedTabID else { return }
                if let expectedContentRevision,
                   viewModel.selectedTab?.contentRevision != expectedContentRevision {
                    return
                }
                statusLineCount = lineCount
            }
        }
    }

    nonisolated static func lineCount(for text: String) -> Int {
        guard !text.isEmpty else { return 1 }
        var lineCount = 1
        for codeUnit in text.utf16 where codeUnit == 10 {
            lineCount += 1
        }
        return lineCount
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
                NotificationCenter.default.post(
                    name: .vimModeStateDidChange,
                    object: nil,
                    userInfo: ["insertMode": vimInsertMode]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                toggleSidebarFromToolbar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBrainDumpModeRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
#if os(iOS) || os(visionOS)
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

        let viewWithPanelTriggers = viewWithEditorActions
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
            .onReceive(NotificationCenter.default.publisher(for: .showGoToLineRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                goToLineInput = currentCaretLineNumber.map(String.init) ?? ""
                showGoToLine = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showGoToSymbolRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                goToSymbolQuery = ""
                showGoToSymbol = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .compareCurrentTabAgainstDiskRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                compareCurrentTabAgainstDisk()
            }
            .onReceive(NotificationCenter.default.publisher(for: .compareOpenTabsRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                presentCompareTabsPicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecentFileRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                guard let url = notif.object as? URL else { return }
                _ = viewModel.openFile(url: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .recentFilesDidChange)) { _ in
                recentFilesRefreshToken = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharedImportsDidChange)) { _ in
                sharedImportsRefreshToken = UUID()
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
                guard canPresentStartupPrompt else { return }
                showWelcomeTour = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showEditorHelpRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                dismissTransientSheetsForCommand()
                showEditorHelp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSupportPromptRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                showWelcomeTour = false
                showEditorHelp = false
                showUpdateDialog = false
                showSupportPromptSheet = true
            }

        let viewWithSharedImportRequests = viewWithPanelTriggers
            .onReceive(NotificationCenter.default.publisher(for: .sharedImportURLRequested)) { notif in
                guard let url = notif.object as? URL else { return }
                handleSharedImportURL(url)
            }

        let viewWithJSONTools = viewWithSharedImportRequests
            .onReceive(NotificationCenter.default.publisher(for: .formatJSONDocumentRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                formatJSONDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .combineJSONLinesRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                combineJSONLines()
            }

        let viewWithPanels = viewWithJSONTools
            .onReceive(NotificationCenter.default.publisher(for: .toggleProjectStructureSidebarRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                toggleProjectSidebarFromToolbar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleCodeMinimapRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                guard !isSafeModeActive else { return }
                showCodeMinimap.toggle()
            }
#if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .showIntegratedTerminalRequested)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                showTerminalInProjectSidebar()
            }
#endif
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
                macOSTOCSplitLayout
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
                .background(editorSurfaceBackgroundStyle)
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
        .background(
            FindReplaceWindowPresenter(
                isPresented: $showFindReplace,
                findQuery: $findQuery,
                replaceQuery: $replaceQuery,
                useRegex: $findUsesRegex,
                caseSensitive: $findCaseSensitive,
                matchCount: $findMatchCount,
                statusMessage: $findStatusMessage,
                scope: $findScope,
                onPreviewChanged: { refreshFindPreview() },
                onFindNext: {
                    findNext()
                    refreshFindMatchCount()
                },
                onJumpToMatch: { jumpToCurrentFindMatch() },
                onReplace: {
                    replaceSelection()
                    refreshFindPreview()
                },
                onReplaceAll: {
                    replaceAll()
                    refreshFindPreview()
                },
                onScopeChange: { newScope in
                    if newScope == .project {
                        showFindReplace = false
                        showFindInFiles = true
                    }
                },
                onClose: { showFindReplace = false }
            )
            .frame(width: 0, height: 0)
        )
        .onDisappear {
            handleWindowDisappear()
        }
        .onChange(of: viewModel.tabsObservationToken) { _, _ in
            if activeSplitSecondaryTabID == nil {
                splitSecondaryTabID = nil
            }
            updateWindowChrome()
        }
        .onChange(of: largeFileOpenModeRaw) { _, _ in
            updateWindowChrome()
        }
        .onChange(of: remoteSessionsEnabled) { _, _ in
            updateWindowChrome()
        }
        .onChange(of: remotePreparedTarget) { _, _ in
            updateWindowChrome()
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
            .alert(
                "PDF Export Failed",
                isPresented: Binding(
                    get: { markdownPDFExportErrorMessage != nil },
                    set: { if !$0 { markdownPDFExportErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(markdownPDFExportErrorMessage ?? "")
            }
            .alert("Allow Shared Imports?", isPresented: $showSharedImportAccessExplanation) {
                Button("Not Now", role: .cancel) {
                    cancelSharedImportAccess()
                }
                Button("Continue") {
                    confirmSharedImportAccess()
                }
            } message: {
                Text("Neon Vision Editor uses a shared app container only to receive files sent from the system Share menu. iOS may ask for permission because this storage is shared between the main app and the Share Extension.")
            }
            .confirmationDialog(
                "Open Shared Import",
                isPresented: $showSharedImportDestinationDialog,
                titleVisibility: .visible
            ) {
                Button(sharedImportOpenNewTabsTitle) {
                    openPendingSharedImportsInNewTabs()
                }
                if canReplaceCurrentTabWithPendingSharedImport {
                    Button("Replace Current Tab", role: viewModel.selectedTab?.isDirty == true ? .destructive : nil) {
                        replaceCurrentTabWithPendingSharedImport()
                    }
                }
                Button("Cancel", role: .cancel) {
                    cancelPendingSharedImportDestination()
                }
            } message: {
                Text(sharedImportDestinationMessage)
            }
            .navigationTitle("Neon Vision Editor")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .background(
                IPadKeyboardShortcutBridge(
                    onCloseTab: {
                        if let tab = viewModel.selectedTab {
                            requestCloseTab(tab)
                        }
                    },
                    onNewTab: { viewModel.addNewTab() },
                    onOpenFile: { openFileFromToolbar() },
                    onSave: { saveCurrentTabFromToolbar() },
                    onFind: { showFindReplace = true },
                    onFindInFiles: { showFindInFiles = true },
                    onGoToLine: {
                        goToLineInput = currentCaretLineNumber.map(String.init) ?? ""
                        showGoToLine = true
                    },
                    onGoToSymbol: {
                        goToSymbolQuery = ""
                        showGoToSymbol = true
                    },
                    onQuickOpen: {
                        quickSwitcherQuery = ""
                        showQuickSwitcher = true
                    },
                    onToggleSidebar: { toggleSidebarFromToolbar() },
                    onToggleProjectSidebar: { toggleProjectSidebarFromToolbar() }
                )
                .frame(width: 0, height: 0)
            )
#endif
    }

    private var rootViewWithStateObservers: some View {
        applyUpdateVisibilityObservers(to: basePlatformRootView)
            .onAppear {
                handleSettingsAndEditorDefaultsOnAppear()
            }
            .onChange(of: settingsLineWrapEnabled) { _, enabled in
                let target = projectOverrideLineWrapEnabled ?? enabled
                if viewModel.isLineWrapEnabled != target {
                    viewModel.isLineWrapEnabled = target
                }
            }
            .onChange(of: viewModel.isLineWrapEnabled) { _, enabled in
                guard projectOverrideLineWrapEnabled == nil else { return }
                if settingsLineWrapEnabled != enabled {
                    settingsLineWrapEnabled = enabled
                }
            }
            .onChange(of: settingsThemeName) { _, _ in
                scheduleHighlightRefresh()
            }
            .onChange(of: themeFormattingRefreshSignature) { _, _ in
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
                scheduleSessionPersistence()
                scheduleUnsavedDraftSnapshotPersistence()
            }
            .onChange(of: viewModel.selectedTabID) { previousTabID, selectedTabID in
                guard previousTabID != selectedTabID else { return }
                previousSelectedTabID = previousTabID
            }
            .onChange(of: viewModel.showSidebar) { _, _ in
                persistSessionIfReady()
            }
            .onChange(of: showProjectStructureSidebar) { _, isPresented in
                persistSessionIfReady()
                if !isPresented {
                    projectSidebarFindInFilesRequestToken = 0
                }
            }
            .onChange(of: showSupportedProjectFilesOnly) { _, _ in
                refreshProjectBrowserState()
            }
            .onChange(of: showHiddenProjectFiles) { _, _ in
                refreshProjectBrowserState()
            }
            .onChange(of: projectIgnoredFolderNamesRaw) { _, _ in
                refreshProjectBrowserState()
            }
            .onChange(of: showMarkdownPreviewPane) { _, _ in
                persistSessionIfReady()
            }
	    }

    private func applyUpdateVisibilityObservers<Content: View>(to view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .whitespaceScalarInspectionResult)) { notif in
                guard matchesCurrentWindow(notif) else { return }
                if let msg = notif.userInfo?[EditorCommandUserInfo.inspectionMessage] as? String {
                    whitespaceInspectorMessage = msg
                }
            }
            .onChange(of: appUpdateManager.automaticPromptToken) { _, _ in
                if appUpdateManager.consumeAutomaticPromptIfNeeded() {
                    showUpdaterDialog(checkNow: false)
                }
            }
            .onChange(of: appUpdateManager.isInstalling) { _, isInstalling in
                if isInstalling && !showUpdateDialog {
                    showUpdaterDialog(checkNow: false)
                }
            }
            .onChange(of: appUpdateManager.awaitingInstallCompletionAction) { _, awaitingAction in
                if awaitingAction && !showUpdateDialog {
                    showUpdaterDialog(checkNow: false)
                }
            }
    }

    private var rootViewWithPlatformLifecycleObservers: some View {
        rootViewWithStateObservers
#if os(iOS) || os(visionOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                handleAppDidBecomeActive()
            }
#elseif os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                handleAppDidBecomeActive()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                handleAppWillResignActive()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                handleAppWillResignActive()
            }
#endif
    }

    private var lifecycleConfiguredRootView: some View {
        rootViewWithPlatformLifecycleObservers
            .onAppear {
                startSharedImportNotificationObserverIfNeeded()
                consumePendingSharedImportsIfNeeded()
            }
            .onDisappear {
                sharedImportNotificationObserver?.stop()
                sharedImportNotificationObserver = nil
            }
            .onOpenURL { url in
                if ShareImportHandoff.isShareImportURL(url) {
                    handleSharedImportURL(url)
                } else {
                    viewModel.openFile(url: url)
                }
            }
#if os(iOS) || os(visionOS)
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
#if os(iOS) || os(visionOS)
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
#if os(macOS)
            isToolbarCollapsed = startsWithToolbarCollapsed
#endif
#if os(iOS) || os(visionOS)
            if UIDevice.current.userInterfaceIdiom == .pad && projectSidebarWidth < Double(minimumProjectSidebarWidth) {
                projectSidebarWidth = Double(minimumProjectSidebarWidth)
            }
#endif
            didRunInitialWindowLayoutSetup = true
        }

        applyStartupBehaviorIfNeeded()

        // Keep iOS tab/editor layout stable by forcing Brain Dump off on mobile.
#if os(iOS) || os(visionOS)
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
                guard canPresentStartupPrompt else { return }
                showWelcomeTour = true
            }
        }
        if appLaunchCount >= 5 && !hasShownSupportPromptV1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard canPresentStartupPrompt, !hasShownSupportPromptV1 else { return }
                hasShownSupportPromptV1 = true
                showSupportPromptSheet = true
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

    private func scheduleExternalConflictRefresh(for tabID: UUID, delay: TimeInterval = 0.15) {
        pendingExternalConflictRefresh?.cancel()
        let work = DispatchWorkItem {
            pendingExternalConflictRefresh = nil
            guard viewModel.selectedTabID == tabID else { return }
            viewModel.refreshExternalConflictForTab(tabID: tabID)
        }
        pendingExternalConflictRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

#if !os(macOS)
    private func shouldThrottleHeavyEditorFeatures(in nsText: NSString? = nil) -> Bool {
        if effectiveLargeFileModeEnabled { return true }
        let length = nsText?.length ?? currentDocumentUTF16Length
        return length >= EditorPerformanceThresholds.heavyFeatureUTF16Length
    }
#endif

    private struct ModalPresentationModifier: ViewModifier {
        let contentView: ContentView

#if os(iOS) || os(visionOS)
        private var isiPhone: Bool {
            UIDevice.current.userInterfaceIdiom == .phone
        }

        private var findReplaceSheetMaxWidth: CGFloat? {
            isiPhone ? nil : 380
        }

        private var findReplaceSheetDetents: Set<PresentationDetent> {
            isiPhone ? [.height(448), .medium] : [.height(390)]
        }

        private var findInFilesSheetDetents: Set<PresentationDetent> {
            isiPhone ? [.large] : [.height(700), .large]
        }

        @ViewBuilder
        private var findReplaceSheetContent: some View {
            FindReplacePanel(
                findQuery: contentView.$findQuery,
                replaceQuery: contentView.$replaceQuery,
                useRegex: contentView.$findUsesRegex,
                caseSensitive: contentView.$findCaseSensitive,
                matchCount: contentView.$findMatchCount,
                statusMessage: contentView.$findStatusMessage,
                scope: contentView.$findScope,
                onPreviewChanged: { contentView.refreshFindPreview() },
                onFindNext: {
                    contentView.findNext()
                    contentView.refreshFindMatchCount()
                },
                onJumpToMatch: { contentView.jumpToCurrentFindMatch() },
                onReplace: {
                    contentView.replaceSelection()
                    contentView.refreshFindPreview()
                },
                onReplaceAll: {
                    contentView.replaceAll()
                    contentView.refreshFindPreview()
                },
                onScopeChange: { newScope in
                    if newScope == .project {
                        contentView.showFindReplace = false
                        contentView.showFindInFiles = true
                    }
                },
                onClose: { contentView.showFindReplace = false }
            )
            .frame(maxWidth: findReplaceSheetMaxWidth)
            .presentationDetents(findReplaceSheetDetents)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }

        @ViewBuilder
        private var findInFilesSheetContent: some View {
            FindInFilesPanel(
                query: contentView.$findInFilesQuery,
                caseSensitive: contentView.$findInFilesCaseSensitive,
                replaceQuery: contentView.$findInFilesReplaceQuery,
                selectedMatchIDs: contentView.$findInFilesSelectedMatchIDs,
                results: contentView.findInFilesResults,
                statusMessage: contentView.findInFilesStatusMessage,
                sourceMessage: contentView.findInFilesSourceMessage,
                isApplyingReplace: contentView.isApplyingFindInFilesReplace,
                onSearch: { contentView.startFindInFiles() },
                onClear: { contentView.clearFindInFiles() },
                onToggleSelection: { contentView.toggleFindInFilesMatchSelection($0) },
                onSelectAll: { contentView.selectAllFindInFilesMatches() },
                onSelectNone: { contentView.clearFindInFilesSelection() },
                onApplyReplace: { contentView.applyProjectWideReplaceFromFindInFiles() },
                onCancelReplace: { contentView.cancelProjectWideReplaceFromFindInFiles() },
                onSelect: { contentView.selectFindInFilesMatch($0) },
                onClose: { contentView.showFindInFiles = false }
            )
            .presentationDetents(findInFilesSheetDetents)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
#endif

#if !os(macOS)
        private func applyingFindReplaceSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(isPresented: contentView.$showFindReplace) {
#if canImport(UIKit)
                findReplaceSheetContent
#else
                FindReplacePanel(
                    findQuery: contentView.$findQuery,
                    replaceQuery: contentView.$replaceQuery,
                    useRegex: contentView.$findUsesRegex,
                    caseSensitive: contentView.$findCaseSensitive,
                    matchCount: contentView.$findMatchCount,
                    statusMessage: contentView.$findStatusMessage,
                    onPreviewChanged: { contentView.refreshFindPreview() },
                    onFindNext: {
                        contentView.findNext()
                        contentView.refreshFindMatchCount()
                    },
                    onJumpToMatch: { contentView.jumpToCurrentFindMatch() },
                    onReplace: {
                        contentView.replaceSelection()
                        contentView.refreshFindPreview()
                    },
                    onReplaceAll: {
                        contentView.replaceAll()
                        contentView.refreshFindPreview()
                    },
                    onClose: { contentView.showFindReplace = false }
                )
                .frame(width: 420)
#endif
            })
        }
#endif

#if canImport(UIKit)
        private func applyingSettingsSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(isPresented: contentView.$showSettingsSheet) {
                ConfiguredSettingsView(
                    supportsOpenInTabs: false,
                    supportsTranslucency: false,
                    editorViewModel: contentView.viewModel,
                    supportPurchaseManager: contentView.supportPurchaseManager,
                    appUpdateManager: contentView.appUpdateManager
                )
#if os(iOS) || os(visionOS)
                #if os(visionOS)
                .frame(
                    minWidth: contentView.visionSettingsSheetSize.width,
                    idealWidth: contentView.visionSettingsSheetSize.width,
                    minHeight: contentView.visionSettingsSheetSize.height,
                    idealHeight: contentView.visionSettingsSheetSize.height
                )
                #endif
                .presentationDetents(contentView.settingsSheetDetents, selection: contentView.$settingsSheetDetent)
                .presentationDragIndicator(.visible)
                #if os(visionOS)
                .presentationContentInteraction(.resizes)
                #else
                .presentationContentInteraction(UIDevice.current.userInterfaceIdiom == .pad ? .resizes : .scrolls)
                #endif
#endif
            })
        }

        private func applyingProjectFolderPickerSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(isPresented: contentView.$showProjectFolderPicker) {
                ProjectFolderPicker(
                    onPick: { url in
                        contentView.setProjectFolder(url)
                        contentView.$showProjectFolderPicker.wrappedValue = false
                    },
                    onCancel: { contentView.$showProjectFolderPicker.wrappedValue = false }
                )
            })
        }
#endif

        private func applyingQuickSwitcherSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(isPresented: contentView.$showQuickSwitcher) {
                QuickFileSwitcherPanel(
                    query: contentView.$quickSwitcherQuery,
                    items: contentView.quickSwitcherItems,
                    statusMessage: contentView.quickSwitcherStatusMessage,
                    onSelect: { contentView.selectQuickSwitcherItem($0) },
                    onTogglePin: { contentView.toggleQuickSwitcherPin($0) }
                )
            })
        }

        private func applyingGoToLineSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(isPresented: contentView.$showGoToLine) {
                GoToLinePanel(
                    lineInput: contentView.$goToLineInput,
                    currentLineCount: contentView.currentDocumentLineCount,
                    onGoToLine: { contentView.submitGoToLine($0) },
                    onClose: { contentView.showGoToLine = false }
                )
            })
        }

        private func applyingGoToSymbolSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(isPresented: contentView.$showGoToSymbol) {
                GoToSymbolPanel(
                    query: contentView.$goToSymbolQuery,
                    items: contentView.filteredDocumentSymbols,
                    onSelect: { contentView.selectDocumentSymbol($0) },
                    onClose: { contentView.showGoToSymbol = false }
                )
            })
        }

        private func applyingCodeSnapshotSheet(to view: AnyView) -> AnyView {
            AnyView(view.sheet(item: contentView.$codeSnapshotPayload) { payload in
                CodeSnapshotComposerView(payload: payload)
            })
        }

        private func applyingFindInFilesSheet(to view: AnyView) -> AnyView {
#if os(macOS)
            AnyView(view.onChange(of: contentView.showFindInFiles) { _, isPresented in
                guard isPresented else { return }
                contentView.showProjectStructureSidebar = true
                contentView.projectSidebarFindInFilesRequestToken &+= 1
                contentView.showFindInFiles = false
            })
#elseif os(iOS) || os(visionOS)
            AnyView(view.onChange(of: contentView.showFindInFiles) { _, isPresented in
                guard isPresented else { return }
                if contentView.horizontalSizeClass == .compact {
                    contentView.showCompactProjectSidebarSheet = true
                } else {
                    contentView.showProjectStructureSidebar = true
                }
                contentView.projectSidebarFindInFilesRequestToken &+= 1
                contentView.showFindInFiles = false
            })
#else
            AnyView(view.sheet(isPresented: contentView.$showFindInFiles) {
                findInFilesSheetContent
            })
#endif
        }

        private func applyingCompareSheets(to view: AnyView) -> AnyView {
            AnyView(
                view
                .sheet(isPresented: contentView.$showCompareTabsPicker) {
                    CompareTabsPickerView(
                        tabs: contentView.comparableOpenTabs,
                        backgroundStyle: contentView.compareSheetBackgroundStyle,
                        onSelect: { tabID in
                            contentView.compareSelectedTab(with: tabID)
                        },
                        onCancel: {
                            contentView.showCompareTabsPicker = false
                        }
                    )
#if os(macOS)
                    .presentationBackground(contentView.compareSheetBackgroundStyle)
#endif
                    .presentationCornerRadius(28)
                }
                .sheet(item: contentView.$documentDiffPresentation) { presentation in
                    DiffComparisonView(
                        title: presentation.title,
                        leftTitle: presentation.leftTitle,
                        rightTitle: presentation.rightTitle,
                        diff: presentation.diff,
                        onClose: {
                            contentView.documentDiffPresentation = nil
                        }
                    ) {
                        EmptyView()
                    }
                }
                .sheet(isPresented: contentView.$showFolderCompare) {
                    FolderCompareView(
                        onOpenFile: { contentView.openProjectFile(url: $0) },
                        onShowDiff: { presentation in
                            contentView.folderDiffPresentation = presentation
                        }
                    )
                }
                .sheet(item: contentView.$folderDiffPresentation) { presentation in
                    DiffComparisonView(
                        title: presentation.title,
                        leftTitle: presentation.leftTitle,
                        rightTitle: presentation.rightTitle,
                        diff: presentation.diff,
                        onClose: {
                            contentView.folderDiffPresentation = nil
                        }
                    ) {
                        EmptyView()
                    }
                }
                .sheet(isPresented: contentView.$showGitTab) {
                    NavigationStack {
                        GitTabView(
                            gitViewModel: contentView.gitViewModel,
                            translucentBackgroundEnabled: contentView.enableTranslucentWindow,
                            onShowDiff: { title, leftTitle, rightTitle, leftContent, rightContent in
                                contentView.showGitTab = false
                                contentView.presentGitDiff(
                                    title: title,
                                    leftTitle: leftTitle,
                                    rightTitle: rightTitle,
                                    leftContent: leftContent,
                                    rightContent: rightContent
                                )
                            }
                        )
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { contentView.showGitTab = false }
                                }
                            }
                    }
#if os(macOS)
                    .frame(minWidth: 700, minHeight: 500)
#else
                    .presentationDetents([.large])
#endif
                }
            )
        }

        private func applyingLanguageSheets(to view: AnyView) -> AnyView {
            AnyView(
                view
                .sheet(isPresented: contentView.$showLanguageSetupPrompt) {
                    contentView.languageSetupSheet
                }
                .sheet(isPresented: contentView.$showLanguageSearchSheet) {
                    contentView.languageSearchSheet
                }
            )
        }

#if os(iOS) || os(visionOS)
        private func applyingCompactIOSSheets(to view: AnyView) -> AnyView {
            AnyView(
                view
                .sheet(isPresented: contentView.$showCompactSidebarSheet) {
                    NavigationStack {
                        SidebarView(
                            content: contentView.currentContent,
                            language: contentView.currentLanguage,
                            contentUTF16Length: contentView.currentDocumentUTF16Length,
                            translucentBackgroundEnabled: true
                        )
                            .navigationTitle(Text(NSLocalizedString("Sidebar", comment: "")))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(NSLocalizedString("Done", comment: "")) {
                                        contentView.$showCompactSidebarSheet.wrappedValue = false
                                    }
                                }
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
                }
                .sheet(isPresented: contentView.$showCompactProjectSidebarSheet, onDismiss: {
                    contentView.projectSidebarFindInFilesRequestToken = 0
                }) {
                    NavigationStack {
                        ProjectStructureSidebarView(
                            rootFolderURL: contentView.projectRootFolderURL,
                            nodes: contentView.projectTreeNodes,
                            selectedFileURL: contentView.viewModel.selectedTab?.fileURL,
                            showSupportedFilesOnly: contentView.showSupportedProjectFilesOnly,
                            showHiddenFiles: contentView.showHiddenProjectFiles,
                            ignoredFolderNamesRaw: contentView.$projectIgnoredFolderNamesRaw,
                            translucentBackgroundEnabled: true,
                            boundaryEdge: nil,
                            onOpenFile: { contentView.openFileFromCompactProjectSidebar() },
                            onOpenFolder: { contentView.openProjectFolderFromCompactProjectSidebar() },
                            onOpenProjectFolder: { contentView.setProjectFolder($0) },
                            onToggleSupportedFilesOnly: { contentView.showSupportedProjectFilesOnly = $0 },
                            onToggleHiddenFiles: { contentView.showHiddenProjectFiles = $0 },
                            onOpenProjectFile: { url in
                                contentView.showCompactProjectSidebarSheet = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    contentView.openProjectFile(url: url)
                                }
                            },
                            onRefreshTree: { contentView.refreshProjectBrowserState() },
                            onCreateProjectFile: { contentView.startProjectItemCreationFromCompactProjectSidebar(kind: .file, in: $0) },
                            onCreateProjectFolder: { contentView.startProjectItemCreationFromCompactProjectSidebar(kind: .folder, in: $0) },
                            onRenameProjectItem: { contentView.startProjectItemRename($0) },
                            onDuplicateProjectItem: { contentView.duplicateProjectItem($0) },
                            onDeleteProjectItem: { contentView.requestDeleteProjectItem($0) },
                            onToggleGitTab: { contentView.showGitTab = true },
                            onShowGitDiff: { title, leftTitle, rightTitle, leftContent, rightContent in
                                contentView.presentGitDiff(
                                    title: title,
                                    leftTitle: leftTitle,
                                    rightTitle: rightTitle,
                                    leftContent: leftContent,
                                    rightContent: rightContent
                                )
                            },
                            findInFilesQuery: contentView.$findInFilesQuery,
                            findInFilesCaseSensitive: contentView.$findInFilesCaseSensitive,
                            findInFilesReplaceQuery: contentView.$findInFilesReplaceQuery,
                            findInFilesSelectedMatchIDs: contentView.$findInFilesSelectedMatchIDs,
                            findInFilesResults: contentView.findInFilesResults,
                            findInFilesStatusMessage: contentView.findInFilesStatusMessage,
                            findInFilesSourceMessage: contentView.findInFilesSourceMessage,
                            isApplyingFindInFilesReplace: contentView.isApplyingFindInFilesReplace,
                            onFindInFilesSearch: { contentView.startFindInFiles() },
                            onFindInFilesClear: { contentView.clearFindInFiles() },
                            onToggleFindInFilesSelection: { contentView.toggleFindInFilesMatchSelection($0) },
                            onSelectAllFindInFilesMatches: { contentView.selectAllFindInFilesMatches() },
                            onSelectNoFindInFilesMatches: { contentView.clearFindInFilesSelection() },
                            onApplyFindInFilesReplace: { contentView.applyProjectWideReplaceFromFindInFiles() },
                            onCancelFindInFilesReplace: { contentView.cancelProjectWideReplaceFromFindInFiles() },
                            onSelectFindInFilesMatch: { match in
                                contentView.showCompactProjectSidebarSheet = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    contentView.selectFindInFilesMatch(match)
                                }
                            },
                            keepsFindInFilesOpenOnSelect: false,
                            activateFindInFilesToken: contentView.projectSidebarFindInFilesRequestToken,
                            activateTerminalToken: contentView.projectSidebarTerminalRequestToken,
                            compareDiffPresentation: contentView.sidebarCompareDiffPresentation,
                            onCloseCompareDiff: { contentView.sidebarCompareDiffPresentation = nil },
                            revealURL: contentView.projectTreeRevealURL,
                            gitFileStatusMap: contentView.gitViewModel.fileStatusMap,
                            gitViewModel: contentView.gitViewModel
                        )
                        .navigationTitle(Text(NSLocalizedString("Project Structure", comment: "")))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(NSLocalizedString("Done", comment: "")) {
                                    contentView.$showCompactProjectSidebarSheet.wrappedValue = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.large])
                    .presentationBackground(.ultraThinMaterial)
                }
                .sheet(isPresented: contentView.markdownPreviewSheetPresentationBinding) {
                    NavigationStack {
                        contentView.markdownPreviewPane
                            .navigationTitle(Text(NSLocalizedString("Markdown Preview", comment: "")))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button(NSLocalizedString("Done", comment: "")) {
                                        contentView.showMarkdownPreviewPane = false
                                    }
                                }
                            }
                    }
                    .presentationDetents([.fraction(0.35), .medium, .large], selection: contentView.$markdownPreviewSheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                }
            )
        }
#endif

        func body(content: Content) -> some View {
            let baseContent = AnyView(content)
#if !os(macOS)
            let withFindReplace = applyingFindReplaceSheet(to: baseContent)
#else
            let withFindReplace = baseContent
#endif
#if canImport(UIKit)
            let withSettings = applyingSettingsSheet(to: withFindReplace)
#else
            let withSettings = withFindReplace
#endif
#if os(iOS) || os(visionOS)
            let withCompactSheets = applyingCompactIOSSheets(to: withSettings)
#else
            let withCompactSheets = withSettings
#endif
#if canImport(UIKit)
            let withProjectPicker = applyingProjectFolderPickerSheet(to: withCompactSheets)
#else
            let withProjectPicker = AnyView(withCompactSheets)
#endif
            let withQuickSwitcher = applyingQuickSwitcherSheet(to: withProjectPicker)
            let withGoToLine = applyingGoToLineSheet(to: withQuickSwitcher)
            let withGoToSymbol = applyingGoToSymbolSheet(to: withGoToLine)
            let withCodeSnapshot = applyingCodeSnapshotSheet(to: withGoToSymbol)
            let withFindInFiles = applyingFindInFilesSheet(to: withCodeSnapshot)
            let withCompare = applyingCompareSheets(to: withFindInFiles)
            let withLanguage = applyingLanguageSheets(to: withCompare)
            let modalRoot = withLanguage
            modalRoot
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
                .sheet(isPresented: contentView.$showEditorHelp) {
                    EditorHelpView {
                        contentView.$showEditorHelp.wrappedValue = false
                    }
                }
                .sheet(isPresented: contentView.$showSupportPromptSheet) {
                    SupportPromptSheetView {
                        contentView.$showSupportPromptSheet.wrappedValue = false
                    }
                    .environmentObject(contentView.supportPurchaseManager)
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
                                    let diff = await Task.detached(priority: .userInitiated) {
                                        DocumentDiffBuilder.build(
                                            leftContent: snapshot.localContent,
                                            rightContent: snapshot.diskContent
                                        )
                                    }.value
                                    await MainActor.run {
                                        contentView.externalConflictCompareSnapshot = snapshot
                                        contentView.externalConflictDiff = diff
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
                .confirmationDialog(
                    contentView.viewModel.pendingRemoteSaveIssue?.isConflict == true
                        ? "Remote file changed"
                        : (contentView.viewModel.pendingRemoteSaveIssue?.requiresReconnect == true
                            ? "Remote session unavailable"
                            : "Remote save failed"),
                    isPresented: contentView.$showRemoteSaveIssueDialog,
                    titleVisibility: .visible
                ) {
                    if let issue = contentView.viewModel.pendingRemoteSaveIssue {
                        if issue.isConflict {
                            Button("Compare") {
                                Task {
                                    if let snapshot = await contentView.viewModel.remoteConflictComparisonSnapshot(tabID: issue.tabID) {
                                        let diff = await Task.detached(priority: .userInitiated) {
                                            DocumentDiffBuilder.build(
                                                leftContent: snapshot.localContent,
                                                rightContent: snapshot.remoteContent
                                            )
                                        }.value
                                        await MainActor.run {
                                            contentView.remoteConflictCompareSnapshot = snapshot
                                            contentView.remoteConflictDiff = diff
                                            contentView.showRemoteConflictCompareSheet = true
                                        }
                                    }
                                }
                            }
                            Button("Reload from Remote", role: .destructive) {
                                contentView.viewModel.reloadRemoteDocumentAfterConflict(tabID: issue.tabID)
                            }
                        } else if issue.requiresReconnect {
                            Button("Detach Broker", role: .destructive) {
                                contentView.viewModel.detachRemoteBrokerAfterSaveIssue()
                            }
                        } else {
                            Button("Try Save Again") {
                                contentView.viewModel.retryRemoteSave(tabID: issue.tabID)
                            }
                        }
                    }
                    Button("Dismiss", role: .cancel) {
                        contentView.viewModel.dismissRemoteSaveIssue()
                    }
                } message: {
                    if let issue = contentView.viewModel.pendingRemoteSaveIssue {
                        Text(issue.requiresReconnect ? issue.recoveryGuidance : issue.detail)
                    } else {
                        Text("The remote document could not be saved.")
                    }
                }
                .sheet(isPresented: contentView.$showExternalConflictCompareSheet, onDismiss: {
                    contentView.externalConflictCompareSnapshot = nil
                    contentView.externalConflictDiff = nil
                }) {
                    if let snapshot = contentView.externalConflictCompareSnapshot,
                       let diff = contentView.externalConflictDiff {
                        DiffComparisonView(
                            title: "External Change",
                            leftTitle: "Local: \(snapshot.fileName)",
                            rightTitle: "Disk: \(snapshot.fileName)",
                            diff: diff,
                            onClose: {
                                contentView.showExternalConflictCompareSheet = false
                            }
                        ) {
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
                    }
                }
                .sheet(isPresented: contentView.$showRemoteConflictCompareSheet, onDismiss: {
                    contentView.remoteConflictCompareSnapshot = nil
                    contentView.remoteConflictDiff = nil
                }) {
                    if let snapshot = contentView.remoteConflictCompareSnapshot,
                       let diff = contentView.remoteConflictDiff {
                        DiffComparisonView(
                            title: "Remote Conflict",
                            leftTitle: "Local: \(snapshot.fileName)",
                            rightTitle: "Remote: \(snapshot.fileName)",
                            diff: diff,
                            onClose: {
                                contentView.showRemoteConflictCompareSheet = false
                            }
                        ) {
                            HStack {
                                Button("Reload from Remote", role: .destructive) {
                                    contentView.viewModel.reloadRemoteDocumentAfterConflict(tabID: snapshot.tabID)
                                    contentView.showRemoteConflictCompareSheet = false
                                }
                                Spacer()
                            }
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
                .alert(contentView.projectItemCreationKind.title, isPresented: contentView.$showProjectItemCreationPrompt) {
                    TextField(
                        contentView.projectItemCreationKind.namePlaceholder,
                        text: contentView.$projectItemCreationNameDraft
                    )
                    Button("Create") { contentView.confirmProjectItemCreation() }
                    Button("Cancel", role: .cancel) { contentView.cancelProjectItemCreation() }
                } message: {
                    Text(NSLocalizedString("Choose a name for the new item.", comment: "Project item creation prompt message"))
                }
                .alert(NSLocalizedString("Rename Item", comment: "Project item rename alert title"), isPresented: contentView.$showProjectItemRenamePrompt) {
                    TextField(
                        NSLocalizedString("Name", comment: "Project item rename name field placeholder"),
                        text: contentView.$projectItemRenameNameDraft
                    )
                    Button("Rename") { contentView.confirmProjectItemRename() }
                    Button("Cancel", role: .cancel) { contentView.cancelProjectItemRename() }
                } message: {
                    Text(NSLocalizedString("Enter a new name.", comment: "Project item rename prompt message"))
                }
                .confirmationDialog(
                    NSLocalizedString("Delete Item?", comment: "Project item delete confirmation title"),
                    isPresented: contentView.$showProjectItemDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { contentView.confirmDeleteProjectItem() }
                    Button("Cancel", role: .cancel) { contentView.cancelDeleteProjectItem() }
                } message: {
                    if !contentView.projectItemDeleteTargetName.isEmpty {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "This will permanently delete \"%@\".",
                                    comment: "Project item delete confirmation message"
                                ),
                                contentView.projectItemDeleteTargetName
                            )
                        )
                    }
                }
                .alert(NSLocalizedString("Can’t Complete Action", comment: "Project item operation error alert title"), isPresented: contentView.$showProjectItemOperationErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(contentView.projectItemOperationErrorMessage)
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
                    contentType: contentView.iosExportContentType,
                    defaultFilename: contentView.iosExportFilename
                ) { result in
                    contentView.handleIOSExportResult(result)
                }
#endif
        }
    }

    var shouldUseSplitView: Bool {
#if os(macOS)
        return viewModel.showSidebar && !brainDumpLayoutEnabled
#else
        // Keep iPhone layout single-column to avoid horizontal clipping.
        return viewModel.showSidebar && !brainDumpLayoutEnabled && horizontalSizeClass == .regular
#endif
    }

    private var themeFormattingRefreshSignature: Int {
        var signature = 0
        if settingsThemeBoldKeywords { signature |= 1 << 0 }
        if settingsThemeItalicComments { signature |= 1 << 1 }
        if settingsThemeUnderlineLinks { signature |= 1 << 2 }
        if settingsThemeBoldMarkdownHeadings { signature |= 1 << 3 }
        return signature
    }

    private var effectiveIndentWidth: Int {
        projectOverrideIndentWidth ?? indentWidth
    }

    private var effectiveLineWrapEnabled: Bool {
        projectOverrideLineWrapEnabled ?? settingsLineWrapEnabled
    }


    // Sidebar shows a lightweight table of contents (TOC) derived from the current document.
    @ViewBuilder
    var sidebarView: some View {
        if viewModel.showSidebar && !brainDumpLayoutEnabled {
            SidebarView(
                content: sidebarTOCContent,
                language: currentLanguage,
                contentUTF16Length: currentDocumentUTF16Length,
                translucentBackgroundEnabled: enableTranslucentWindow
            )
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 600)
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
                    guard viewModel.selectedTab?.isReadOnlyPreview != true else { return }
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

    var activeSplitSecondaryTabID: UUID? {
        guard let secondaryID = splitSecondaryTabID,
              secondaryID != viewModel.selectedTabID,
              viewModel.tabs.contains(where: { $0.id == secondaryID }) else { return nil }
        return secondaryID
    }

    func tabContentBinding(for tabID: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.tabs.first(where: { $0.id == tabID })?.content ?? ""
            },
            set: { newValue in
                guard viewModel.tabs.first(where: { $0.id == tabID })?.isReadOnlyPreview != true else { return }
                viewModel.updateTabContent(tabID: tabID, content: newValue)
            }
        )
    }

    func tabLanguageBinding(for tabID: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.tabs.first(where: { $0.id == tabID })?.language ?? currentLanguage
            },
            set: { newValue in
                viewModel.updateTabLanguage(tabID: tabID, language: newValue)
            }
        )
    }

    func tabForID(_ tabID: UUID?) -> TabData? {
        guard let tabID else { return nil }
        return viewModel.tabs.first(where: { $0.id == tabID })
    }

    var currentDocumentUTF16Length: Int {
        if let tab = viewModel.selectedTab {
            return tab.contentUTF16Length
        }
        return (singleContent as NSString).length
    }

    var effectiveLargeFileModeEnabled: Bool {
        if largeFileModeEnabled { return true }
        if droppedFileLoadInProgress { return true }
        if viewModel.selectedTab?.isLargeFileCandidate == true { return true }
        return currentDocumentUTF16Length >= 300_000
    }

    private var isSelectedTabReadOnlyPreview: Bool {
        viewModel.selectedTab?.isReadOnlyPreview == true
    }

    private var shouldUseDeferredLargeFileOpenMode: Bool {
        largeFileOpenModeRaw == "deferred" || largeFileOpenModeRaw == "plainText"
    }

    var currentLargeFileOpenModeLabel: String {
        switch largeFileOpenModeRaw {
        case "standard":
            return "Standard"
        case "plainText":
            return "Plain Text"
        default:
            return "Deferred"
        }
    }

    var largeFileStatusBadgeText: String {
        guard effectiveLargeFileModeEnabled else { return "" }
        return "Large File • \(currentLargeFileOpenModeLabel)"
    }

    var remoteSessionStatusBadgeText: String {
        guard remoteSessionsEnabled else { return "" }
        if remoteSessionStore.runtimeState == .failed, remoteSessionStore.isBrokerClientAttached {
            return "Local Workspace • Remote Broker Lost"
        }
        if remoteSessionStore.runtimeState == .failed, remoteSessionStore.hasBrokerSession {
            return "Local Workspace • Remote Broker Failed"
        }
        if remoteSessionStore.runtimeState == .failed {
            return "Local Workspace • Remote Failed"
        }
        if remoteSessionStore.isBrokerClientAttached {
            return "Local Workspace • Remote Broker Attached"
        }
        if remoteSessionStore.hasBrokerSession {
            return "Local Workspace • Remote Broker Active"
        }
        if remoteSessionStore.isRemotePreviewConnecting {
            return "Local Workspace • Remote Connecting"
        }
        if remoteSessionStore.isRemotePreviewConnected {
            return "Local Workspace • Remote Session Active"
        }
        if remoteSessionStore.isRemotePreviewReady {
            return "Local Workspace • Remote Selected"
        }
        return remotePreparedTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Local Workspace • Remote Enabled"
            : "Local Workspace • Remote Ready"
    }

    var remoteSessionBadgeForegroundColor: Color {
        remoteSessionStore.runtimeState == .failed ? .red : .secondary
    }

    var remoteSessionBadgeBackgroundColor: Color {
        remoteSessionStore.runtimeState == .failed
            ? Color.red.opacity(0.16)
            : Color.secondary.opacity(0.16)
    }

    var remoteSessionBadgeAccessibilityValue: String {
        if remoteSessionStore.runtimeState == .failed, remoteSessionStore.isBrokerClientAttached {
            return "Local workspace lost its attached remote broker session. Reattach from Settings using a fresh code."
        }
        if remoteSessionStore.runtimeState == .failed, remoteSessionStore.hasBrokerSession {
            return "Local workspace lost the active macOS remote broker session. Restart the Mac session before attaching again."
        }
        if remoteSessionStore.runtimeState == .failed {
            return "Local workspace remote session failed."
        }
        return remoteSessionStore.isBrokerClientAttached
            ? "Local workspace attached to a remote broker for read-only browsing"
            : (
            remoteSessionStore.hasBrokerSession
            ? "Local workspace with an active remote broker session on macOS"
            : (
            remoteSessionStore.isRemotePreviewConnecting
            ? "Local workspace with a remote session connection in progress"
            : (
                remoteSessionStore.isRemotePreviewConnected
                ? "Local workspace with an active remote session connection"
                : (
                    remoteSessionStore.isRemotePreviewReady
                    ? "Local workspace with a selected remote preview target"
                    : (
                        remotePreparedTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Local workspace with remote preview enabled"
                        : "Local workspace with a prepared remote target"
                    )
                )
            )
            )
        )
    }

    private var windowSubtitleText: String {
        [largeFileStatusBadgeText, remoteSessionStatusBadgeText]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var sidebarTOCContent: String {
        if effectiveLargeFileModeEnabled || currentDocumentUTF16Length >= 400_000 {
            return ""
        }
        return currentContent
    }

    var brainDumpLayoutEnabled: Bool {
#if os(macOS)
        return viewModel.isBrainDumpMode
#else
        return false
#endif
    }


    // MARK: - Main Editor Stack
#if os(iOS) || os(visionOS)
    var iOSSurfaceSeparatorFill: Color {
        if enableTranslucentWindow {
            return .clear
        }
        return iOSNonTranslucentSurfaceColor
    }

    var iOSSurfaceSeparatorLine: Color {
        if enableTranslucentWindow {
            return .clear
        }
        return colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    var iOSPaneDivider: some View {
        ZStack {
            Rectangle()
                .fill(iOSSurfaceSeparatorFill)
            Rectangle()
                .fill(iOSSurfaceSeparatorLine)
                .frame(width: 1)
        }
        .frame(width: enableTranslucentWindow ? 6 : 10)
    }

    var iOSHorizontalSurfaceDivider: some View {
        ZStack {
            Rectangle()
                .fill(iOSSurfaceSeparatorFill)
            Rectangle()
                .fill(iOSSurfaceSeparatorLine)
                .frame(height: 1)
        }
        .frame(height: enableTranslucentWindow ? 4 : 10)
    }

    var iOSVerticalSurfaceDivider: some View {
        ZStack {
            Rectangle()
                .fill(iOSSurfaceSeparatorFill)
            Rectangle()
                .fill(iOSSurfaceSeparatorLine)
                .frame(width: 1)
        }
        .frame(width: 10, height: 18)
    }
#endif

    @MainActor
    func presentGitDiff(
        title: String,
        leftTitle: String,
        rightTitle: String,
        leftContent: String,
        rightContent: String
    ) {
        Task { @MainActor in
            let diff = await Task.detached(priority: .userInitiated) {
                DocumentDiffBuilder.build(leftContent: leftContent, rightContent: rightContent)
            }.value
            await Task.yield()
#if os(iOS) || os(visionOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                sidebarCompareDiffPresentation = DocumentDiffPresentation(
                    title: title,
                    leftTitle: leftTitle,
                    rightTitle: rightTitle,
                    diff: diff
                )
                dismissKeyboard()
                showCompactProjectSidebarSheet = true
                return
            }
#endif
            folderDiffPresentation = DocumentDiffPresentation(
                title: title,
                leftTitle: leftTitle,
                rightTitle: rightTitle,
                diff: diff
            )
        }
    }

    @ViewBuilder
    private func editorPane(
        tabID: UUID?,
        text: Binding<String>,
        language: String,
        isLoading: Bool,
        isReadOnly: Bool,
        lineWrapEnabled: Binding<Bool>,
        effectiveHighlightCurrentLine: Bool,
        effectiveBracketHighlight: Bool,
        effectiveScopeGuides: Bool,
        effectiveScopeBackground: Bool
    ) -> some View {
        let useOuterNoWrapScroll = shouldUseOuterNoWrapEditorScroll(lineWrapEnabled: lineWrapEnabled.wrappedValue)
        HStack(spacing: 0) {
            if useOuterNoWrapScroll {
                GeometryReader { proxy in
                    let scrollableEditorWidth = max(proxy.size.width * 3, proxy.size.width)
                    ScrollView(.horizontal, showsIndicators: true) {
                        editorTextView(
                            tabID: tabID,
                            text: text,
                            language: language,
                            isLoading: isLoading,
                            isReadOnly: isReadOnly,
                            lineWrapEnabled: lineWrapEnabled,
                            effectiveHighlightCurrentLine: effectiveHighlightCurrentLine,
                            effectiveBracketHighlight: effectiveBracketHighlight,
                            effectiveScopeGuides: effectiveScopeGuides,
                            effectiveScopeBackground: effectiveScopeBackground
                        )
                        .frame(width: scrollableEditorWidth, height: proxy.size.height)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorTextView(
                    tabID: tabID,
                    text: text,
                    language: language,
                    isLoading: isLoading,
                    isReadOnly: isReadOnly,
                    lineWrapEnabled: lineWrapEnabled,
                    effectiveHighlightCurrentLine: effectiveHighlightCurrentLine,
                    effectiveBracketHighlight: effectiveBracketHighlight,
                    effectiveScopeGuides: effectiveScopeGuides,
                    effectiveScopeBackground: effectiveScopeBackground
                )
            }

            if effectiveShowCodeMinimap && supportsCodeMinimap(language: language) {
                CodeMinimapView(
                    text: text.wrappedValue,
                    language: language,
                    colorScheme: colorScheme,
                    isLargeFileMode: effectiveLargeFileModeEnabled || isLoading,
                    viewport: tabID.flatMap { codeMinimapViewports[$0] },
                    onSelectLine: { line in
                        moveEditorFromMinimap(to: line, tabID: tabID)
                    },
                    onMoveViewport: { topFraction in
                        moveEditorViewportFromMinimap(to: topFraction, tabID: tabID)
                    }
                )
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func shouldUseOuterNoWrapEditorScroll(lineWrapEnabled: Bool) -> Bool {
#if os(iOS) || os(visionOS)
        UIDevice.current.userInterfaceIdiom == .pad &&
        !lineWrapEnabled &&
        !effectiveLargeFileModeEnabled
#else
        false
#endif
    }

    private func editorTextView(
        tabID: UUID?,
        text: Binding<String>,
        language: String,
        isLoading: Bool,
        isReadOnly: Bool,
        lineWrapEnabled: Binding<Bool>,
        effectiveHighlightCurrentLine: Bool,
        effectiveBracketHighlight: Bool,
        effectiveScopeGuides: Bool,
        effectiveScopeBackground: Bool
    ) -> some View {
        CustomTextEditor(
            text: text,
            documentID: tabID,
            externalEditRevision: editorExternalMutationRevision,
            language: language,
            colorScheme: colorScheme,
            fontSize: editorFontSize,
            isLineWrapEnabled: lineWrapEnabled,
            isLargeFileMode: effectiveLargeFileModeEnabled,
            showsCodeMinimap: effectiveShowCodeMinimap && supportsCodeMinimap(language: language),
            translucentBackgroundEnabled: enableTranslucentWindow,
            showKeyboardAccessoryBar: {
#if os(iOS) || os(visionOS)
                showKeyboardAccessoryBarIOS
#else
                true
#endif
            }(),
            showLineNumbers: showLineNumbers,
            showInvisibleCharacters: showInvisibleCharacters,
            highlightCurrentLine: effectiveHighlightCurrentLine,
            highlightMatchingBrackets: effectiveBracketHighlight,
            showIndentationGuides: showIndentationGuides,
            showScopeGuides: effectiveScopeGuides,
            highlightScopeBackground: effectiveScopeBackground,
            indentStyle: indentStyle,
            indentWidth: effectiveIndentWidth,
            autoIndentEnabled: autoIndentEnabled,
            autoCloseBracketsEnabled: autoCloseBracketsEnabled,
            highlightRefreshToken: highlightRefreshToken,
            isTabLoadingContent: isLoading,
            isReadOnly: isReadOnly,
            onTextMutation: { mutation in
                viewModel.applyTabContentEdit(
                    tabID: mutation.documentID,
                    range: mutation.range,
                    replacement: mutation.replacement
                )
            }
        )
        .id("\(tabID?.uuidString ?? "single")-\(language)")
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func splitEditorPaneHeader(title: String, showsCloseButton: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if showsCloseButton {
                Button {
                    splitSecondaryTabID = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close secondary editor")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(editorSurfaceBackgroundStyle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(showsCloseButton ? "Secondary editor \(title)" : "Primary editor \(title)")
    }

    private func moveEditorFromMinimap(to line: Int, tabID: UUID?) {
        var userInfo: [String: Any] = [:]
        if let tabID {
            userInfo[EditorCommandUserInfo.documentID] = tabID.uuidString
        }
#if os(macOS)
        if let targetWindow = hostWindowNumber ?? NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = targetWindow
        }
#endif
        NotificationCenter.default.post(name: .moveCursorToLine, object: line, userInfo: userInfo)
    }

    private func moveEditorViewportFromMinimap(to topFraction: Double, tabID: UUID?) {
        var userInfo: [String: Any] = [
            EditorCommandUserInfo.viewportTopFraction: min(max(0, topFraction), 1)
        ]
        if let tabID {
            userInfo[EditorCommandUserInfo.documentID] = tabID.uuidString
        }
#if os(macOS)
        if let targetWindow = hostWindowNumber ?? NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = targetWindow
        }
#endif
        NotificationCenter.default.post(name: .scrollEditorViewportToFraction, object: nil, userInfo: userInfo)
    }

#if os(macOS)
    private var macOSTOCSplitLayout: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: clampedTOCSidebarWidth)
                .background(editorSurfaceBackgroundStyle)
            tocSidebarResizeHandle
            editorView
        }
        .background(editorSurfaceBackgroundStyle)
    }

    private var tocSidebarResizeHandle: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startWidth = tocSidebarResizeStartWidth ?? clampedTOCSidebarWidth
                if tocSidebarResizeStartWidth == nil {
                    tocSidebarResizeStartWidth = startWidth
                }
                let proposed = startWidth + value.translation.width
                let clamped = min(max(proposed, minimumTOCSidebarWidth), maximumTOCSidebarWidth)
                tocSidebarWidth = Double(clamped)
            }
            .onEnded { _ in
                tocSidebarResizeStartWidth = nil
                if !isTOCSidebarResizeHandleHovered {
                    MacSidebarResizeCursor.reset()
                }
            }

        return MacSidebarResizeDivider(
            visibleWidth: tocSidebarResizeHandleWidth,
            hitTargetWidth: tocSidebarResizeHitTargetWidth,
            accentWidth: projectSidebarResizeHandleAccentWidth,
            accentColor: projectSidebarHandleAccentColor,
            surfaceStyle: editorSurfaceBackgroundStyle,
            isActive: isTOCSidebarResizeHandleHovered || tocSidebarResizeStartWidth != nil,
            isDragging: tocSidebarResizeStartWidth != nil,
            isHovered: $isTOCSidebarResizeHandleHovered,
            drag: drag,
            accessibilityLabel: "Resize Table of Contents",
            accessibilityHint: "Drag left or right to adjust the table of contents width"
        )
    }
#endif

    private func handleAppDidBecomeActive() {
        if let selectedID = viewModel.selectedTab?.id {
            viewModel.refreshExternalConflictForTab(tabID: selectedID)
        }
        if projectRootFolderURL != nil {
            refreshProjectBrowserState()
        }
        consumePendingSharedImportsIfNeeded()
    }

    private func startSharedImportNotificationObserverIfNeeded() {
        guard sharedImportNotificationObserver == nil else { return }
        let observer = SharedImportNotificationObserver {
            consumePendingSharedImportsIfNeeded()
        }
        observer.start()
        sharedImportNotificationObserver = observer
    }

    private func handleAppWillResignActive() {
        persistSessionIfReady()
        persistUnsavedDraftSnapshotIfNeeded()
    }

    var editorView: some View {
        @Bindable var bindableViewModel = viewModel
        let shouldThrottleFeatures = shouldThrottleHeavyEditorFeatures()
        let effectiveHighlightCurrentLine = highlightCurrentLine && !shouldThrottleFeatures
        let effectiveBracketHighlight = highlightMatchingBrackets && !shouldThrottleFeatures
        let effectiveScopeGuides = showScopeGuides && !shouldThrottleFeatures
        let effectiveScopeBackground = highlightScopeBackground && !shouldThrottleFeatures
        let content = HStack(spacing: 0) {
            if showProjectStructureSidebar && projectNavigatorPlacement == .leading && !brainDumpLayoutEnabled {
                projectStructureSidebarPanel
                projectSidebarResizeHandle
            }

            VStack(spacing: 0) {
                if !useIOSUnifiedTopHost && !brainDumpLayoutEnabled {
                    tabBarView
                }
#if os(macOS)
                if showBracketHelperBarMac {
                    bracketHelperBar
                }
#endif

                if (isDelimitedFileLanguage || isPlistDocument) && !brainDumpLayoutEnabled {
                    structuredDataModeControl
                }

                Group {
                    if shouldShowDelimitedTable && !brainDumpLayoutEnabled {
                        delimitedTableView
                    } else if shouldShowPlistStructure && !brainDumpLayoutEnabled {
                        plistStructureView
                    } else if shouldUseDeferredLargeFileOpenMode,
                              viewModel.selectedTab?.isLoadingContent == true,
                              (viewModel.selectedTab?.isLargeFileCandidate == true ||
                               currentDocumentUTF16Length >= 300_000 ||
                               largeFileModeEnabled) {
                        largeFileLoadingPlaceholder
                    } else {
                        if let secondaryID = activeSplitSecondaryTabID,
                           let secondaryTab = tabForID(secondaryID) {
                            HStack(spacing: 0) {
                                VStack(spacing: 0) {
                                    splitEditorPaneHeader(title: viewModel.selectedTab?.name ?? "Primary Editor")
                                    editorPane(
                                        tabID: viewModel.selectedTabID,
                                        text: currentContentBinding,
                                        language: currentLanguage,
                                        isLoading: viewModel.selectedTab?.isLoadingContent ?? false,
                                        isReadOnly: isSelectedTabReadOnlyPreview,
                                        lineWrapEnabled: $bindableViewModel.isLineWrapEnabled,
                                        effectiveHighlightCurrentLine: effectiveHighlightCurrentLine,
                                        effectiveBracketHighlight: effectiveBracketHighlight,
                                        effectiveScopeGuides: effectiveScopeGuides,
                                        effectiveScopeBackground: effectiveScopeBackground
                                    )
                                }
                                Divider()
                                VStack(spacing: 0) {
                                    splitEditorPaneHeader(title: secondaryTab.name, showsCloseButton: true)
                                    editorPane(
                                        tabID: secondaryID,
                                        text: tabContentBinding(for: secondaryID),
                                        language: secondaryTab.language,
                                        isLoading: secondaryTab.isLoadingContent,
                                        isReadOnly: secondaryTab.isReadOnlyPreview,
                                        lineWrapEnabled: $bindableViewModel.isLineWrapEnabled,
                                        effectiveHighlightCurrentLine: effectiveHighlightCurrentLine,
                                        effectiveBracketHighlight: effectiveBracketHighlight,
                                        effectiveScopeGuides: effectiveScopeGuides,
                                        effectiveScopeBackground: effectiveScopeBackground
                                    )
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Split editor")
                        } else {
                            editorPane(
                                tabID: viewModel.selectedTabID,
                                text: currentContentBinding,
                                language: currentLanguage,
                                isLoading: viewModel.selectedTab?.isLoadingContent ?? false,
                                isReadOnly: isSelectedTabReadOnlyPreview,
                                lineWrapEnabled: $bindableViewModel.isLineWrapEnabled,
                                effectiveHighlightCurrentLine: effectiveHighlightCurrentLine,
                                effectiveBracketHighlight: effectiveBracketHighlight,
                                effectiveScopeGuides: effectiveScopeGuides,
                                effectiveScopeBackground: effectiveScopeBackground
                            )
                            .overlay {
                                if shouldShowStartupOverlay {
                                    startupOverlay
                                }
                            }
                        }
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
                            #if os(iOS) || os(visionOS)
                            iOSNonTranslucentSurfaceColor
                            #else
                            Color.clear
                            #endif
                        }
                    }
                )
                .overlay(alignment: .topTrailing) {
                    if effectiveLargeFileModeEnabled && !brainDumpLayoutEnabled {
                        largeFileSessionBadge
                            .padding(.top, 10)
                            .padding(.trailing, 12)
                            .zIndex(5)
                    }
                }

                if !brainDumpLayoutEnabled {
#if os(macOS)
                    wordCountView
#endif
                }
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: brainDumpLayoutEnabled ? .top : .topLeading
            )

            if isMarkdownPreviewSplitVisible {
#if os(iOS) || os(visionOS)
                iOSPaneDivider
#else
                markdownPreviewSplitTransition
#endif
                markdownPreviewSplitPane
            } else if isWebPreviewSplitVisible {
#if os(iOS) || os(visionOS)
                iOSPaneDivider
#else
                markdownPreviewSplitTransition
#endif
                webPreviewSplitPane
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
#if os(macOS)
                    if enableTranslucentWindow {
                        Color.clear.background(macInterPaneBackgroundStyle)
                    } else {
                        Color.clear
                    }
#elseif os(iOS) || os(visionOS)
                    Color.clear.background(editorSurfaceBackgroundStyle)
#else
                    Color.clear
#endif
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

#if os(iOS) || os(visionOS)
        let contentWithTopChrome = useIOSUnifiedTopHost
            ? AnyView(
                content.safeAreaInset(edge: .top, spacing: 0) {
                    iOSUnifiedTopChromeHost
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
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentViewWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ContentViewWidthPreferenceKey.self) { newValue in
            liveContainerWidth = newValue
        }
        .onAppear {
            syncSecondaryViewModesForCurrentTab()
            refreshSecondaryContentViewsIfNeeded()
        }
        .onChange(of: viewModel.tabsObservationToken) { _, _ in
            refreshSecondaryContentViewsIfNeeded()
        }
        .onChange(of: viewModel.selectedTab?.id) { _, _ in
            syncSecondaryViewModesForCurrentTab()
            refreshSecondaryContentViewsIfNeeded()
        }
        .onChange(of: delimitedViewMode) { _, newValue in
            if newValue == .table {
                if let key = selectedDelimitedViewModePersistenceKey {
                    persistDelimitedViewMode(newValue, for: key)
                }
                refreshSecondaryContentViewsIfNeeded()
            } else {
                if let key = selectedDelimitedViewModePersistenceKey {
                    persistDelimitedViewMode(newValue, for: key)
                }
                delimitedParseTask?.cancel()
                isBuildingDelimitedTable = false
                delimitedTableSnapshot = nil
                delimitedTableStatus = ""
            }
        }
        .onChange(of: plistViewMode) { _, newValue in
            if newValue == .structure {
                refreshSecondaryContentViewsIfNeeded()
            } else {
                plistParseTask?.cancel()
                isBuildingPlistStructure = false
                plistStructureNodes = []
                plistStructureStatus = ""
            }
        }
        .onChange(of: currentLanguage) { _, _ in
            syncSecondaryViewModesForCurrentTab()
            if shouldShowDelimitedTable || shouldShowPlistStructure {
                refreshSecondaryContentViewsIfNeeded()
            } else {
                delimitedParseTask?.cancel()
                isBuildingDelimitedTable = false
                delimitedTableSnapshot = nil
                delimitedTableStatus = ""
                plistParseTask?.cancel()
                isBuildingPlistStructure = false
                plistStructureNodes = []
                plistStructureStatus = ""
            }
        }
        .onDisappear {
            wordCountTask?.cancel()
            delimitedParseTask?.cancel()
            plistParseTask?.cancel()
        }
        .onChange(of: enableTranslucentWindow) { _, newValue in
            applyWindowTranslucency(newValue)
            // Force immediate recolor when translucency changes so syntax highlighting stays visible.
            highlightRefreshToken &+= 1
        }
        .onChange(of: settingsThemeHexOverridesData) { _, _ in
            applyWindowTranslucency(enableTranslucentWindow)
            highlightRefreshToken &+= 1
        }
#if os(iOS) || os(visionOS)
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
#if os(iOS) || os(visionOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    settingsSheetDetent = .large
                }
#endif
                if previousKeyboardAccessoryVisibility == nil {
                    previousKeyboardAccessoryVisibility = showKeyboardAccessoryBarIOS
                }
                showKeyboardAccessoryBarIOS = false
            } else if let previousKeyboardAccessoryVisibility {
                showKeyboardAccessoryBarIOS = previousKeyboardAccessoryVisibility
                self.previousKeyboardAccessoryVisibility = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorFocusDidChange)) { notif in
            let isFocused = (notif.object as? Bool) ?? false
            isPhoneEditorFocused = isFocused
            if isFocused {
                cancelPhoneStatusAutoCollapse()
                isPhoneStatusBarExpanded = false
            } else {
                cancelPhoneStatusAutoCollapse()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isPhoneSoftwareKeyboardVisible = true
            cancelPhoneStatusAutoCollapse()
            isPhoneStatusBarExpanded = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isPhoneSoftwareKeyboardVisible = false
            cancelPhoneStatusAutoCollapse()
            isPhoneStatusBarExpanded = false
        }
        .onChange(of: mobileEditingStatusPresetEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            cancelPhoneStatusAutoCollapse()
            isPhoneStatusBarExpanded = false
        }
#endif
#if os(macOS)
        .onChange(of: macTranslucencyModeRaw) { _, _ in
            // Keep all chrome/background surfaces in lockstep when mode changes.
            applyWindowTranslucency(enableTranslucentWindow)
            highlightRefreshToken &+= 1
        }
        .onChange(of: colorScheme) { _, _ in
            applyWindowTranslucency(enableTranslucentWindow)
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
#if os(iOS) || os(visionOS)
        .overlay(alignment: .bottomTrailing) {
            if !brainDumpLayoutEnabled && !shouldPinFloatingStatusToTop {
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
            macToolbarBackgroundStyle,
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

    private var largeFileLoadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing large file")
                .font(.headline)
            Text("Deferred open mode keeps first paint lightweight and installs the document in chunks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing large file")
        .accessibilityValue("Deferred open mode is loading the editor content")
    }

}
