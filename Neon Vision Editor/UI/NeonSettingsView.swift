import SwiftUI
import Synchronization
#if os(macOS)
import AppKit
#endif
#if canImport(CoreText)
import CoreText
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Theme JSON Caches

// Settings redraw frequently while sliders and pickers change; cache decoded theme blobs by data signature.
private enum SettingsThemeJSONCache {
    private struct State: Sendable {
        var customThemesSignature: Int = 0
        var customThemes: [String: [String: String]] = [:]
        var hexOverridesSignature: Int = 0
        var hexOverrides: [String: [String: String]] = [:]
    }

    nonisolated private static let state = Mutex(State())

    nonisolated static func customThemes(from data: Data) -> [String: [String: String]] {
        let signature = data.count ^ data.hashValue
        return state.withLock { state in
            if signature == state.customThemesSignature { return state.customThemes }
            let decoded = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
            state.customThemesSignature = signature
            state.customThemes = decoded
            return decoded
        }
    }

    nonisolated static func hexOverrides(from data: Data) -> [String: [String: String]] {
        let signature = data.count ^ data.hashValue
        return state.withLock { state in
            if signature == state.hexOverridesSignature { return state.hexOverrides }
            let decoded = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
            state.hexOverridesSignature = signature
            state.hexOverrides = decoded
            return decoded
        }
    }
}


// MARK: - Types

private struct SettingsFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = flowRows(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height
        } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = flowRows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func flowRows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var rows: [FlowRow] = []
        var current = FlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }
            current.append(index: index, size: size, spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct FlowItem {
        let index: Int
        let size: CGSize
    }

    private struct FlowRow {
        var items: [FlowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            width += items.isEmpty ? size.width : spacing + size.width
            height = max(height, size.height)
            items.append(FlowItem(index: index, size: size))
        }
    }
}

struct NeonSettingsView: View {
    private struct SettingsTabPage: View {
        let title: String
        let systemImage: String
        let tag: String
        let content: AnyView

        var body: some View {
            content
                .tabItem { Label(title, systemImage: systemImage) }
                .tag(tag)
        }
    }

    // MARK: - Stored Configuration

    fileprivate static let defaultSettingsTab = "general"
    private static var cachedEditorFonts: [String] = []
    let supportsOpenInTabs: Bool
    let supportsTranslucency: Bool
    @Environment(EditorViewModel.self) private var editorViewModel
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openURL) private var openURL
#if os(visionOS)
    @Environment(\.dismiss) private var dismiss
#endif
    @AppStorage("SettingsOpenInTabs") private var openInTabs: String = "system"
    @AppStorage("SettingsEditorFontName") private var editorFontName: String = ""
    @AppStorage("SettingsUseSystemFont") private var useSystemFont: Bool = false
    @AppStorage("SettingsEditorFontSize") private var editorFontSize: Double = 14
    @AppStorage("SettingsLineHeight") private var lineHeight: Double = 1.0
    @AppStorage("SettingsAppearance") private var appearance: String = "system"
    @AppStorage("SettingsAppLanguageCode") private var appLanguageCode: String = "system"
    @AppStorage("SettingsToolbarSymbolsColorMac") private var toolbarSymbolsColorMacRaw: String = "blue"
    @AppStorage("ToolbarCollapsed") private var isToolbarCollapsed: Bool = false
#if os(iOS) || os(visionOS)
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = true
#else
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
#endif
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
    @AppStorage(AppearanceThemeCloudSync.enabledKey) private var iCloudAppearanceThemeSyncEnabled: Bool = false
    @AppStorage(AppearanceThemeCloudSync.statusKey) private var iCloudAppearanceThemeSyncStatus: String = AppearanceThemeCloudSync.currentStatus
    @AppStorage("SettingsReopenLastSession") private var reopenLastSession: Bool = true
    @AppStorage("SettingsOpenWithBlankDocument") private var openWithBlankDocument: Bool = true
    @AppStorage("SettingsShareImportsAutoOpen") private var shareImportsAutoOpen: Bool = true
#if os(macOS)
    @AppStorage("SettingsShowMenuBarIconMac") private var showMenuBarIconMac: Bool = true
#endif
    @AppStorage("SettingsDefaultNewFileLanguage") private var defaultNewFileLanguage: String = "plain"
    @AppStorage("SettingsConfirmCloseDirtyTab") private var confirmCloseDirtyTab: Bool = true
    @AppStorage("SettingsConfirmClearEditor") private var confirmClearEditor: Bool = true
    @AppStorage("SettingsRemoteSessionsEnabled") private var remoteSessionsEnabled: Bool = false
    @AppStorage("SettingsRemoteHost") private var remoteHost: String = ""
    @AppStorage("SettingsRemoteUsername") private var remoteUsername: String = ""
    @AppStorage("SettingsRemotePort") private var remotePort: Int = 22
    @AppStorage("SettingsRemotePreparedTarget") private var remotePreparedTarget: String = ""
    @AppStorage(AppUpdateManager.autoCheckEnabledKey) private var autoCheckForUpdates: Bool = true
    @AppStorage(AppUpdateManager.updateIntervalKey) private var updateCheckIntervalRaw: String = AppUpdateCheckInterval.daily.rawValue
    @AppStorage(AppUpdateManager.autoDownloadEnabledKey) private var autoDownloadUpdates: Bool = false

    @AppStorage("SettingsShowLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("SettingsHighlightCurrentLine") private var highlightCurrentLine: Bool = false
    @AppStorage("SettingsHighlightMatchingBrackets") private var highlightMatchingBrackets: Bool = false
    @AppStorage("SettingsShowIndentationGuides") private var showIndentationGuides: Bool = false
    @AppStorage("SettingsShowScopeGuides") private var showScopeGuides: Bool = false
    @AppStorage("SettingsHighlightScopeBackground") private var highlightScopeBackground: Bool = false
    @AppStorage("SettingsLineWrapEnabled") private var lineWrapEnabled: Bool = true
    @AppStorage("SettingsShowInvisibleCharacters") private var showInvisibleCharacters: Bool = false
    @AppStorage("SettingsIndentStyle") private var indentStyle: String = "spaces"
    @AppStorage("SettingsIndentWidth") private var indentWidth: Int = 4
    @AppStorage("SettingsStatusBarShowCursor") private var statusBarShowCursor: Bool = true
    @AppStorage("SettingsStatusBarShowLineCount") private var statusBarShowLineCount: Bool = true
    @AppStorage("SettingsStatusBarShowWordCount") private var statusBarShowWordCount: Bool = true
    @AppStorage("SettingsStatusBarShowEncoding") private var statusBarShowEncoding: Bool = true
    @AppStorage("SettingsStatusBarShowLineEndings") private var statusBarShowLineEndings: Bool = true
    @AppStorage("SettingsStatusBarShowIndentation") private var statusBarShowIndentation: Bool = true
    @AppStorage("SettingsStatusBarShowSelection") private var statusBarShowSelection: Bool = true
    @AppStorage("SettingsStatusBarShowFileSize") private var statusBarShowFileSize: Bool = false
    @AppStorage("SettingsStatusBarShowGit") private var statusBarShowGit: Bool = true
    @AppStorage("SettingsAutoIndent") private var autoIndent: Bool = true
    @AppStorage("SettingsAutoCloseBrackets") private var autoCloseBrackets: Bool = false
    @AppStorage("SettingsTrimTrailingWhitespace") private var trimTrailingWhitespace: Bool = false
    @AppStorage("SettingsTrimWhitespaceForSyntaxDetection") private var trimWhitespaceForSyntaxDetection: Bool = false
    @AppStorage("EditorVimModeEnabled") private var vimModeEnabled: Bool = false
    @AppStorage("EditorVimInterceptionEnabled") private var vimInterceptionEnabled: Bool = false
    @AppStorage("SettingsProjectNavigatorPlacement") private var projectNavigatorPlacementRaw: String = ContentView.ProjectNavigatorPlacement.trailing.rawValue
    @AppStorage("SettingsProjectSidebarDisclosureSymbolStyle") private var projectSidebarDisclosureSymbolStyleRaw: String = "chevron"
    @AppStorage("SettingsPerformancePreset") private var performancePresetRaw: String = ContentView.PerformancePreset.balanced.rawValue
    @AppStorage("SettingsLargeFileSyntaxHighlighting") private var largeFileSyntaxHighlightingRaw: String = "minimal"
    @AppStorage("SettingsLargeFileOpenMode") private var largeFileOpenModeRaw: String = "deferred"
#if os(iOS) || os(visionOS)
    @AppStorage("SettingsToolbarShowSearchIOS") private var toolbarShowSearchIOS: Bool = true
    @AppStorage("SettingsToolbarShowCompareIOS") private var toolbarShowCompareIOS: Bool = true
    @AppStorage("SettingsToolbarShowEditorUtilityIOS") private var toolbarShowEditorUtilityIOS: Bool = true
    @AppStorage("SettingsToolbarShowAppearanceIOS") private var toolbarShowAppearanceIOS: Bool = true
    @AppStorage("SettingsToolbarFavoriteCountIOS") private var toolbarFavoriteCountIOS: Int = 8
    @AppStorage("SettingsToolbarShowOpenFileIOS") private var toolbarShowOpenFileIOS: Bool = true
    @AppStorage("SettingsToolbarShowUndoIOS") private var toolbarShowUndoIOS: Bool = true
    @AppStorage("SettingsToolbarShowSettingsIOS") private var toolbarShowSettingsIOS: Bool = true
    @AppStorage("SettingsToolbarShowHelpIOS") private var toolbarShowHelpIOS: Bool = true
    @AppStorage("SettingsToolbarUseCustomFiveIOS") private var toolbarUseCustomFiveIOS: Bool = false
    @AppStorage("SettingsToolbarCustomFiveIDsIOS") private var toolbarCustomFiveIDsIOS: String = ""
    @AppStorage("SettingsToolbarIconsBlueIOS") private var toolbarIconsBlueIOS: Bool = false
    @AppStorage("SettingsMobileEditingStatusPresetEnabled") private var mobileEditingStatusPresetEnabled: Bool = false
#endif

    @AppStorage("SettingsCompletionEnabled") private var completionEnabled: Bool = false
    @AppStorage("SettingsCompletionFromDocument") private var completionFromDocument: Bool = false
    @AppStorage("SettingsCompletionFromSyntax") private var completionFromSyntax: Bool = false
    @AppStorage("SelectedAIModel") private var selectedAIModelRaw: String = AIModel.appleIntelligence.rawValue
    @AppStorage("OpenCodeGoModelID") private var openCodeGoModelID: String = OpenCodeGoConfig.defaultModel
    @AppStorage("SettingsActiveTab") private var settingsActiveTab: String = defaultSettingsTab
    @AppStorage("SettingsTemplateLanguage") private var settingsTemplateLanguage: String = "swift"
    @State private var remoteSessionStore = RemoteSessionStore.shared
    @State private var grokAPIToken: String = ""
    @State private var openAIAPIToken: String = ""
    @State private var geminiAPIToken: String = ""
    @State private var anthropicAPIToken: String = ""
    @State private var openCodeGoAPIToken: String = ""
    @State private var customProviderAPIToken: String = ""
    @AppStorage(CustomProviderConfig.baseURLDefaultsKey) private var customProviderBaseURL: String = ""
    @AppStorage(CustomProviderConfig.modelDefaultsKey) private var customProviderModel: String = ""
    @State private var showSupportPurchaseDialog: Bool = false
    @State private var showDataDisclosureDialog: Bool = false
    @State private var showRemoteConnectSheet: Bool = false
    @State private var showRemoteAttachSheet: Bool = false
    @State private var availableEditorFonts: [String] = []
    @State private var moreSectionTab: String = "support"
    @State private var editorSectionTab: String = "basics"
    @State private var diagnosticsCopyStatus: String = ""
    @State private var remotePreparationStatus: String = ""
    @State private var remoteConnectNickname: String = ""
    @State private var remotePortDraft: String = "22"
    @State private var remoteAttachCodeDraft: String = ""
    @State private var remoteBrowserPathDraft: String = "~"
    @State private var shortcutDrafts: [EditorShortcutAction: String] = [:]
    @State private var showToolbarIconChooser: Bool = false
    @State private var isThemeSelectionHovering: Bool = false
    @State private var isThemeSelectionSelecting: Bool = false
    @State private var themeSelectionScrollbarHideTask: Task<Void, Never>?
#if os(macOS)
    @State private var remoteSSHKeyBookmarkData: Data? = nil
    @State private var remoteSSHKeyDisplayName: String = ""
    @State private var commandLineHelperCopyStatus: String = ""
#endif
    @State private var supportRefreshTask: Task<Void, Never>?
    @State private var isDiscoveringFonts: Bool = false
    private let privacyPolicyURL = URL(string: "https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/PRIVACY.md")
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    private let githubProjectURL = URL(string: "https://github.com/h3pdesign/Neon-Vision-Editor")
    private let githubFeatureRequestURL = URL(string: "https://github.com/h3pdesign/Neon-Vision-Editor/issues/new/choose")

    // MARK: - Theme Storage

    @AppStorage("SettingsThemeName") private var selectedTheme: String = "Neon Glow"
    @AppStorage("SettingsThemeTextColor") private var themeTextHex: String = "#EDEDED"
    @AppStorage("SettingsThemeBackgroundColor") private var themeBackgroundHex: String = "#0E1116"
    @AppStorage("SettingsThemeCursorColor") private var themeCursorHex: String = "#4EA4FF"
    @AppStorage("SettingsThemeSelectionColor") private var themeSelectionHex: String = "#2A3340"
    @AppStorage("SettingsThemeKeywordColor") private var themeKeywordHex: String = "#F5D90A"
    @AppStorage("SettingsThemeStringColor") private var themeStringHex: String = "#4EA4FF"
    @AppStorage("SettingsThemeNumberColor") private var themeNumberHex: String = "#FFB86C"
    @AppStorage("SettingsThemeCommentColor") private var themeCommentHex: String = "#7F8C98"
    @AppStorage("SettingsThemeTypeColor") private var themeTypeHex: String = "#32D269"
    @AppStorage("SettingsThemeBuiltinColor") private var themeBuiltinHex: String = "#EC7887"
    @AppStorage("SavedCustomThemesData") private var savedCustomThemesData: Data = Data()
    @AppStorage("SettingsThemeHexOverrides") private var themeHexOverridesData: Data = Data()
    @State private var showSaveThemeDialog: Bool = false
    @State private var newThemeName: String = ""
    @State private var themeSaveError: String? = nil
    @AppStorage("SettingsThemeBoldKeywords") private var themeBoldKeywords: Bool = false
    @AppStorage("SettingsThemeItalicComments") private var themeItalicComments: Bool = false
    @AppStorage("SettingsThemeUnderlineLinks") private var themeUnderlineLinks: Bool = false
    @AppStorage("SettingsThemeBoldMarkdownHeadings") private var themeBoldMarkdownHeadings: Bool = false
#if os(macOS)
    @AppStorage("MarkdownPreviewTemplateMac") private var markdownPreviewTemplateRaw: String = "default"
#else
    @AppStorage("MarkdownPreviewTemplateIOS") private var markdownPreviewTemplateRaw: String = "default"
#endif
#if os(visionOS)
    @AppStorage("MarkdownPreviewReaderStyleVision") private var markdownPreviewReaderStyleVisionRaw: String = "systemGlass"
#endif
    @AppStorage("MarkdownPreviewBackgroundStyle") private var markdownPreviewBackgroundStyleRaw: String = "automatic"
    @AppStorage("MarkdownPreviewDialect") private var markdownPreviewDialectRaw: String = ContentView.MarkdownPreviewDialect.gfm.rawValue

    // MARK: - Theme Persistence Helpers

    private var inputFieldBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.secondarySystemBackground)
#endif
    }

    private func loadCustomThemes() -> [String: [String: String]] {
        SettingsThemeJSONCache.customThemes(from: savedCustomThemesData)
    }

    private func saveCustomThemes(_ themes: [String: [String: String]]) {
        savedCustomThemesData = (try? JSONEncoder().encode(themes)) ?? Data()
    }

    private func loadHexOverrides() -> [String: [String: String]] {
        SettingsThemeJSONCache.hexOverrides(from: themeHexOverridesData)
    }

    private func saveHexOverrides(_ overrides: [String: [String: String]]) {
        themeHexOverridesData = (try? JSONEncoder().encode(overrides)) ?? Data()
    }

    private var themeBackgroundOverrideKey: String {
        effectiveSettingsColorScheme == .dark ? "backgroundDark" : "backgroundLight"
    }

    private func backgroundHex(from colors: [String: String], themeName: String) -> String {
        colors[themeBackgroundOverrideKey] ?? colors["background"] ?? defaultHex(for: "background", themeName: themeName)
    }

    private func hasBackgroundOverride(_ colors: [String: String]) -> Bool {
        colors["backgroundLight"] != nil || colors["backgroundDark"] != nil || colors["background"] != nil
    }

    private func removeAccidentalDefaultBackgroundOverride(from colors: inout [String: String], themeName: String) {
        let defaultBackground = defaultHex(for: "background", themeName: themeName).lowercased()
        if colors[themeBackgroundOverrideKey]?.lowercased() == defaultBackground {
            colors.removeValue(forKey: themeBackgroundOverrideKey)
        }
        if colors["background"]?.lowercased() == defaultBackground {
            colors.removeValue(forKey: "background")
        }
    }

    private func removeAccidentalDefaultTextOverride(from colors: inout [String: String], themeName: String) {
        let defaultText = defaultHex(for: "text", themeName: themeName).lowercased()
        if colors["text"]?.lowercased() == defaultText && colors["textExplicit"] != "true" {
            colors.removeValue(forKey: "text")
        }
    }

    private func saveCurrentColorsToOverrides(
        for themeName: String? = nil,
        persistText: Bool = false,
        persistBackground: Bool = false
    ) {
        let name = themeName ?? selectedTheme
        var overrides = loadHexOverrides()
        var themeOverrides = overrides[name] ?? [:]
        if !persistText {
            removeAccidentalDefaultTextOverride(from: &themeOverrides, themeName: name)
        }
        if persistText || themeOverrides["text"] != nil {
            themeOverrides["text"] = themeTextHex
            if persistText {
                themeOverrides["textExplicit"] = "true"
            }
        }
        if !persistBackground {
            removeAccidentalDefaultBackgroundOverride(from: &themeOverrides, themeName: name)
        }
        if persistBackground || hasBackgroundOverride(themeOverrides) {
            themeOverrides[themeBackgroundOverrideKey] = themeBackgroundHex
        }
        themeOverrides["cursor"] = themeCursorHex
        themeOverrides["selection"] = themeSelectionHex
        themeOverrides["keyword"] = themeKeywordHex
        themeOverrides["string"] = themeStringHex
        themeOverrides["number"] = themeNumberHex
        themeOverrides["comment"] = themeCommentHex
        themeOverrides["type"] = themeTypeHex
        themeOverrides["builtin"] = themeBuiltinHex
        overrides[name] = themeOverrides
        saveHexOverrides(overrides)
    }

    private func resetTextOverride() {
        var overrides = loadHexOverrides()
        var themeOverrides = overrides[selectedTheme] ?? [:]
        themeOverrides.removeValue(forKey: "text")
        themeOverrides.removeValue(forKey: "textExplicit")
        overrides[selectedTheme] = themeOverrides
        saveHexOverrides(overrides)
    }

    private func hexBinding(
        _ hex: Binding<String>,
        fallback: Color,
        persistText: Bool = false,
        persistBackground: Bool = false
    ) -> Binding<Color> {
        Binding<Color>(
            get: { colorFromHex(hex.wrappedValue, fallback: fallback) },
            set: { newColor in
                hex.wrappedValue = colorToHex(newColor)
                saveCurrentColorsToOverrides(persistText: persistText, persistBackground: persistBackground)
            }
        )
    }

    private var themes: [String] {
        editorThemeNames + loadCustomThemes().keys.sorted()
    }

    private func deleteCustomTheme(_ name: String) {
        var all = loadCustomThemes()
        all.removeValue(forKey: name)
        saveCustomThemes(all)
        var overrides = loadHexOverrides()
        overrides.removeValue(forKey: name)
        saveHexOverrides(overrides)
        if selectedTheme == name {
            selectedTheme = "Neon Glow"
        }
    }

    private func showThemeSelectionScrollbarBriefly() {
        themeSelectionScrollbarHideTask?.cancel()
        isThemeSelectionSelecting = true
        themeSelectionScrollbarHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            isThemeSelectionSelecting = false
        }
    }

    private func saveCustomThemes(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            themeSaveError = "Theme name cannot be empty."
            return
        }
        guard !editorThemeNames.contains(trimmed) else {
            themeSaveError = "A built-in theme with that name already exists."
            return
        }
        let colors: [String: String] = [
            "text": themeTextHex,
            themeBackgroundOverrideKey: themeBackgroundHex,
            "cursor": themeCursorHex,
            "selection": themeSelectionHex,
            "keyword": themeKeywordHex,
            "string": themeStringHex,
            "number": themeNumberHex,
            "comment": themeCommentHex,
            "type": themeTypeHex,
            "builtin": themeBuiltinHex
        ]
        var all = loadCustomThemes()
        all[trimmed] = colors
        saveCustomThemes(all)
        showSaveThemeDialog = false
        themeSaveError = nil
    }

    // MARK: - Static Option Lists

    private let templateLanguages: [String] = [
        "swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust",
        "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp",
        "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb",
        "markdown", "tex", "bash", "zsh", "powershell", "standard", "plain"
    ]

    private let appLanguageOptions: [String] = [
        "system",
        "en",
        "de",
        "zh-Hans"
    ]
    
    // MARK: - Layout State

    private var isCompactSettingsLayout: Bool {
#if os(iOS) || os(visionOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var useTwoColumnSettingsLayout: Bool {
#if os(iOS) || os(visionOS)
        horizontalSizeClass == .regular
#else
        false
#endif
    }

    private var isVisionSettingsLayout: Bool {
#if os(visionOS)
        true
#else
        false
#endif
    }

    private var isIPadRegularSettingsLayout: Bool {
#if os(iOS) || os(visionOS)
        useTwoColumnSettingsLayout
#else
        false
#endif
    }

    private var isIPadDevice: Bool {
#if os(iOS) || os(visionOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    private var vimModeBinding: Binding<Bool> {
        Binding(
            get: { vimModeEnabled && vimInterceptionEnabled },
            set: { enabled in
                vimModeEnabled = enabled
                vimInterceptionEnabled = enabled
                NotificationCenter.default.post(
                    name: .vimModeStateDidChange,
                    object: nil,
                    userInfo: ["insertMode": !enabled]
                )
            }
        )
    }

    private var standardLabelWidth: CGFloat {
        useTwoColumnSettingsLayout ? 180 : 140
    }

    private var startupLabelWidth: CGFloat {
        useTwoColumnSettingsLayout ? 220 : 180
    }

    private enum UI {
        static let space6: CGFloat = 6
        static let space8: CGFloat = 8
        static let space10: CGFloat = 10
        static let space12: CGFloat = 12
        static let space16: CGFloat = 16
        static let space20: CGFloat = 20
        static let fieldCorner: CGFloat = 6
        static let groupPadding: CGFloat = 14
        static let sidePaddingCompact: CGFloat = 12
        static let sidePaddingRegular: CGFloat = 20
        static let sidePaddingIPadRegular: CGFloat = 28
        static let topPadding: CGFloat = 14
        static let bottomPadding: CGFloat = 16
        static let cardCorner: CGFloat = 12
        static let cardStrokeOpacity: Double = 0.15
        static let mobileHeaderTopPadding: CGFloat = 10
        static let cardAccentHeight: CGFloat = 4
#if os(macOS)
        static let macHeaderIconSize: CGFloat = 34
        static let macHeaderBadgeCorner: CGFloat = 10
        static let macSettingsToolbarContentMargin: CGFloat = 52
#endif
    }

    private enum Typography {
        static let sectionHeadline = Font.headline
        static let sectionSubheadline = Font.subheadline
        static let footnote = Font.footnote
        static let monoBody = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let sectionTitle = Font.title3.weight(.semibold)
    }

#if os(iOS) || os(visionOS)
    private enum MobileCardEmphasis {
        case primary
        case secondary
    }
#endif

#if os(macOS)
    private enum MacTranslucencyModeOption: String, CaseIterable, Identifiable {
        case subtle
        case balanced
        case vibrant

        var id: String { rawValue }

        var title: String {
            switch self {
            case .subtle: return "Subtle"
            case .balanced: return "Balanced"
            case .vibrant: return "Vibrant"
            }
        }
    }
#endif

    private enum ProjectSidebarDisclosureSymbolStyleOption: String, CaseIterable, Identifiable {
        case chevron
        case triangle
        case caret
        case plusMinus

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chevron: return "Chevron"
            case .triangle: return "Triangle"
            case .caret: return "Caret"
            case .plusMinus: return "Plus/Minus"
            }
        }
    }

    init(
        supportsOpenInTabs: Bool = true,
        supportsTranslucency: Bool = true
    ) {
        self.supportsOpenInTabs = supportsOpenInTabs
        self.supportsTranslucency = supportsTranslucency
    }

#if os(visionOS)
    private static let visionSettingsTabTags = ["general", "editor", "appearance", "toolbar", "ai", "remote", "shortcuts", "diagnostics"]
#endif

    // MARK: - Tab Routing

    private var validSettingsTabTags: Set<String> {
#if os(visionOS)
        return Set(Self.visionSettingsTabTags)
#else
        var tags: Set<String> = ["general", "editor", "templates", "themes"]
#if os(iOS)
        tags.insert("more")
#else
        tags.formUnion(["support", "ai", "remote"])
        if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
            tags.insert("updates")
        }
#endif
        return tags
#endif
    }

    private func normalizeSettingsActiveTabIfNeeded() {
        let normalized = settingsActiveTab.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || !validSettingsTabTags.contains(normalized) {
            settingsActiveTab = Self.defaultSettingsTab
        }
    }

    private var orderedSettingsTabTags: [String] {
#if os(visionOS)
        Self.visionSettingsTabTags
#elseif os(iOS)
        ["general", "editor", "templates", "themes", "more"]
#else
        var tags = ["general", "editor", "templates", "themes", "support", "ai", "remote"]
        if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
            tags.append("updates")
        }
        return tags
#endif
    }

    private func moveSettingsTabSelection(by delta: Int) {
        let availableTags = orderedSettingsTabTags.filter { validSettingsTabTags.contains($0) }
        guard !availableTags.isEmpty else { return }
        normalizeSettingsActiveTabIfNeeded()
        let currentIndex = availableTags.firstIndex(of: settingsActiveTab) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), availableTags.count - 1)
        settingsActiveTab = availableTags[nextIndex]
    }

    @ViewBuilder
    private var settingsTabs: some View {
#if os(visionOS)
        AnyView(visionSettingsSplitLayout)
#else
        TabView(selection: $settingsActiveTab) {
            SettingsTabPage(
                title: localized("General"),
                systemImage: "gearshape",
                tag: "general",
                content: AnyView(generalTab)
            )
            SettingsTabPage(
                title: localized("Editor"),
                systemImage: "slider.horizontal.3",
                tag: "editor",
                content: AnyView(editorTab)
            )
            SettingsTabPage(
                title: localized("Templates"),
                systemImage: "doc.badge.plus",
                tag: "templates",
                content: AnyView(templateTab)
            )
            SettingsTabPage(
                title: localized("Themes"),
                systemImage: "paintpalette",
                tag: "themes",
                content: AnyView(themeTab)
            )
            #if os(iOS) || os(visionOS)
            SettingsTabPage(
                title: localized("More"),
                systemImage: "ellipsis.circle",
                tag: "more",
                content: AnyView(moreTab)
            )
            #else
            SettingsTabPage(
                title: localized("Support"),
                systemImage: "heart",
                tag: "support",
                content: AnyView(supportTab)
            )
            SettingsTabPage(
                title: localized("AI"),
                systemImage: "brain.head.profile",
                tag: "ai",
                content: AnyView(aiTab)
            )
            SettingsTabPage(
                title: localized("Remote"),
                systemImage: "rectangle.connected.to.line.below",
                tag: "remote",
                content: AnyView(remoteTab)
            )
            SettingsTabPage(
                title: localized("Shortcuts"),
                systemImage: "command",
                tag: "shortcuts",
                content: AnyView(shortcutsTab)
            )
            #endif
#if os(macOS)
            if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                SettingsTabPage(
                    title: localized("Updates"),
                    systemImage: "arrow.triangle.2.circlepath.circle",
                    tag: "updates",
                    content: AnyView(updatesTab)
                )
            }
#endif
        }
#if os(iOS) || os(visionOS)
        .animation(.easeOut(duration: 0.22), value: settingsActiveTab)
#endif
#endif
    }

#if os(visionOS)
    private var visionSettingsSplitLayout: some View {
        HStack(spacing: 0) {
            visionSettingsCategoryRail
                .frame(width: 204)
            Divider().opacity(0.45)
            visionSettingsDetail
                .frame(minWidth: 520, idealWidth: 580, maxWidth: 640)
        }
        .frame(minWidth: 760, idealWidth: 820, maxWidth: 900, minHeight: 520, idealHeight: 620, maxHeight: 720)
        .background(visionSettingsUnifiedSurface)
        .background(settingsContainerBackground)
        .overlay(alignment: .topTrailing) {
            settingsCloseButton
                .padding(.top, UI.space12)
                .padding(.trailing, UI.space12)
        }
    }

    private var visionSettingsUnifiedSurface: some View {
        Color.clear
    }

    private var visionSettingsCategoryRail: some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            Text(localized("Settings"))
                .font(Typography.sectionHeadline)
                .padding(.horizontal, UI.space12)
                .padding(.bottom, UI.space6)

            visionCategoryButton(id: "general", title: localized("General"), systemImage: "gearshape")
            visionCategoryButton(id: "editor", title: localized("Editor"), systemImage: "slider.horizontal.3")
            visionCategoryButton(id: "appearance", title: localized("Appearance"), systemImage: "paintpalette")
            visionCategoryButton(id: "toolbar", title: localized("Toolbar"), systemImage: "rectangle.topthird.inset.filled")
            visionCategoryButton(id: "ai", title: localized("AI"), systemImage: "brain.head.profile")
            visionCategoryButton(id: "remote", title: localized("Remote"), systemImage: "rectangle.connected.to.line.below")
            visionCategoryButton(id: "shortcuts", title: localized("Shortcuts"), systemImage: "command")
            visionCategoryButton(id: "diagnostics", title: localized("Diagnostics"), systemImage: "stethoscope")

            Spacer(minLength: 0)
        }
        .padding(.top, UI.space20)
        .padding(.horizontal, UI.space12)
        .padding(.bottom, UI.space16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func visionCategoryButton(id: String, title: String, systemImage: String) -> some View {
        Button {
            settingsActiveTab = id
        } label: {
            HStack(spacing: UI.space10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.body.weight(settingsActiveTab == id ? .semibold : .regular))
            .foregroundStyle(settingsActiveTab == id ? Color.primary : Color.secondary)
            .padding(.horizontal, UI.space12)
            .padding(.vertical, UI.space8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(settingsActiveTab == id ? Color.white.opacity(effectiveSettingsColorScheme == .dark ? 0.18 : 0.52) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(settingsActiveTab == id ? [.isSelected] : [])
    }

    private var visionSettingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.space12) {
                visionSettingsDetailContent
            }
            .frame(maxWidth: 580, alignment: .topLeading)
            .padding(.top, UI.space20)
            .padding(.horizontal, UI.space20)
            .padding(.bottom, UI.space20)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var visionSettingsDetailContent: AnyView {
        switch settingsActiveTab {
        case "editor":
            AnyView(
                VStack(alignment: .leading, spacing: UI.space12) {
                    visionDetailHeader(title: localized("Editor"), subtitle: localized("Display, indentation, editing behavior, and completion sources."), icon: "slider.horizontal.3")
                    editorFontSection
                    editorBasicsSettings
                    editorBehaviorSettings
                }
            )
        case "appearance":
            AnyView(visionAppearanceSettings)
        case "toolbar":
            AnyView(visionToolbarSettings)
        case "ai":
            AnyView(
                VStack(alignment: .leading, spacing: UI.space12) {
                    visionDetailHeader(title: localized("AI"), subtitle: localized("AI model, privacy disclosure, and provider credentials."), icon: "brain.head.profile")
                    aiSection
                }
            )
        case "remote":
            AnyView(
                VStack(alignment: .leading, spacing: UI.space12) {
                    visionDetailHeader(title: localized("Remote"), subtitle: localized("Optional, user-triggered remote browsing and editing."), icon: "rectangle.connected.to.line.below")
                    remoteSection
                }
            )
        case "shortcuts":
            AnyView(
                VStack(alignment: .leading, spacing: UI.space12) {
                    visionDetailHeader(title: localized("Shortcuts"), subtitle: localized("Hardware keyboard shortcuts."), icon: "command")
                    visionFormSection(title: localized("Keyboard Shortcuts")) {
                        shortcutSettingsContent
                    }
                }
            )
        case "diagnostics":
            AnyView(
                VStack(alignment: .leading, spacing: UI.space12) {
                    visionDetailHeader(title: localized("Diagnostics"), subtitle: localized("Local troubleshooting details."), icon: "stethoscope")
                    diagnosticsSection
                }
            )
        default:
            AnyView(visionGeneralSettingsForm)
        }
    }

    private func visionDetailHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: UI.space10) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.sectionTitle)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
#endif

    // MARK: - Localization and Store State

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func localized(_ key: String, _ value: CVarArg) -> String {
        String(format: NSLocalizedString(key, comment: ""), value)
    }

    private func localized(_ key: String, _ values: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: values)
    }

    private func appLanguageLabel(for code: String) -> String {
        switch code {
        case "system":
            return localized("Follow System")
        case "de":
            return "Deutsch"
        case "zh-Hans":
            return "简体中文"
        default:
            return "English"
        }
    }

    private func applyAppLanguagePreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        if appLanguageCode == "system" {
            defaults.removeObject(forKey: "AppleLanguages")
            return
        }
        defaults.set([appLanguageCode], forKey: "AppleLanguages")
    }

    private var shouldShowSupportPurchaseControls: Bool {
#if os(iOS) || os(visionOS)
        true
#else
        supportPurchaseManager.canUseInAppPurchases
#endif
    }

    private var supportPriceDisplayLabel: String {
        if let price = supportPurchaseManager.availableSupportPriceLabel {
            return price
        }
        if supportPurchaseManager.hasCheckedStoreAvailability && !supportPurchaseManager.isLoadingProducts {
            return localized("Retry App Store")
        }
        return localized("Loading...")
    }

    private var supportPriceStateLabel: String {
        if supportPurchaseManager.isLoadingProducts && supportPurchaseManager.supportProduct == nil {
            return localized("Loading...")
        }
        if supportPurchaseManager.supportProduct == nil {
            return localized("Retry App Store")
        }
        return localized("Current")
    }

    private var appearanceThemeSyncFingerprint: String {
        [
            appearance,
            String(translucentWindow),
            macTranslucencyModeRaw,
            selectedTheme,
            themeTextHex,
            themeBackgroundHex,
            themeCursorHex,
            themeSelectionHex,
            themeKeywordHex,
            themeStringHex,
            themeNumberHex,
            themeCommentHex,
            themeTypeHex,
            themeBuiltinHex,
            settingsDataFingerprint(savedCustomThemesData),
            settingsDataFingerprint(themeHexOverridesData),
            String(themeBoldKeywords),
            String(themeItalicComments),
            String(themeUnderlineLinks),
            String(themeBoldMarkdownHeadings),
            markdownPreviewBackgroundStyleRaw
        ].joined(separator: "|")
    }

    private func settingsDataFingerprint(_ data: Data) -> String {
        "\(data.count):\(data.hashValue)"
    }

    // MARK: - View Body and Lifecycle

    var body: some View {
        settingsTabs
#if os(macOS)
        .background(settingsWindowBackground)
        .frame(
            minWidth: macSettingsWindowSize.min.width,
            idealWidth: macSettingsWindowSize.ideal.width,
            maxWidth: .infinity,
            minHeight: macSettingsWindowSize.min.height,
            idealHeight: macSettingsWindowSize.ideal.height,
            maxHeight: .infinity
        )
        .background(
            SettingsWindowConfigurator(
                minSize: macSettingsWindowSize.min,
                idealSize: macSettingsWindowSize.ideal,
                translucentEnabled: supportsTranslucency && translucentWindow,
                translucencyModeRaw: macTranslucencyModeRaw,
                appearanceRaw: appearance,
                effectiveColorScheme: effectiveSettingsColorScheme
            )
        )
#endif
        .preferredColorScheme(preferredColorSchemeOverride)
#if os(iOS) || os(visionOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
#if os(iOS)
        .background(
            SettingsKeyboardShortcutBridge(
                onMoveToPreviousTab: { moveSettingsTabSelection(by: -1) },
                onMoveToNextTab: { moveSettingsTabSelection(by: 1) }
            )
            .frame(width: 0, height: 0)
        )
#endif
#endif
        .onAppear {
            normalizeSettingsActiveTabIfNeeded()
            if moreSectionTab.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                moreSectionTab = "support"
            }
            selectedTheme = canonicalThemeName(selectedTheme)
            migrateLegacyPinkSettingsIfNeeded()
            loadAvailableEditorFontsIfNeeded()
            if settingsActiveTab == "ai" || (settingsActiveTab == "more" && moreSectionTab == "ai") {
                loadAPITokensIfNeeded()
            }
            if settingsActiveTab == "support" || (settingsActiveTab == "more" && moreSectionTab == "support") {
                refreshSupportStoreStateIfNeeded()
            }
            appUpdateManager.setAutoCheckEnabled(autoCheckForUpdates)
            appUpdateManager.setUpdateInterval(selectedUpdateInterval)
            appUpdateManager.setAutoDownloadEnabled(autoDownloadUpdates)
            applyAppLanguagePreferenceIfNeeded()
            loadShortcutDraftsIfNeeded()
#if os(macOS)
            applyAppearanceImmediately()
#endif
        }
        .modifier(
            AppearanceThemeSettingsSyncModifier(
                syncEnabled: $iCloudAppearanceThemeSyncEnabled,
                syncStatus: $iCloudAppearanceThemeSyncStatus,
                selectedTheme: $selectedTheme,
                syncFingerprint: appearanceThemeSyncFingerprint,
                canonicalThemeName: canonicalThemeName,
                applyAppearance: {
#if os(macOS)
                    applyAppearanceImmediately()
#endif
                }
            )
        )
        .onChange(of: appearance) { _, _ in
#if os(macOS)
            applyAppearanceImmediately()
#endif
        }
        .onChange(of: appLanguageCode) { _, _ in
            applyAppLanguagePreferenceIfNeeded()
        }
        .onChange(of: showScopeGuides) { _, enabled in
            if enabled && lineWrapEnabled {
                lineWrapEnabled = false
            }
        }
        .onChange(of: highlightScopeBackground) { _, enabled in
            if enabled && lineWrapEnabled {
                lineWrapEnabled = false
            }
        }
        .onChange(of: lineWrapEnabled) { _, enabled in
            if enabled {
                showScopeGuides = false
                highlightScopeBackground = false
            }
        }
        .onChange(of: autoCheckForUpdates) { _, enabled in
            appUpdateManager.setAutoCheckEnabled(enabled)
        }
        .onChange(of: updateCheckIntervalRaw) { _, _ in
            appUpdateManager.setUpdateInterval(selectedUpdateInterval)
        }
        .onChange(of: autoDownloadUpdates) { _, enabled in
            appUpdateManager.setAutoDownloadEnabled(enabled)
        }
        .onChange(of: settingsActiveTab) { _, newValue in
            #if os(visionOS)
            if newValue == "ai" {
                loadAPITokensIfNeeded()
            }
            #elseif os(iOS)
            if newValue == "more" {
                moreSectionTab = "support"
            }
            #else
            if newValue == "ai" {
                loadAPITokensIfNeeded()
            } else if newValue == "support" {
                refreshSupportStoreStateIfNeeded()
            }
            #endif
        }
        .onChange(of: moreSectionTab) { _, newValue in
            if newValue == "ai" && settingsActiveTab == "more" {
                loadAPITokensIfNeeded()
            } else if newValue == "support" && settingsActiveTab == "more" {
                refreshSupportStoreStateIfNeeded()
            }
        }
        .onChange(of: selectedTheme) { _, newValue in
            let canonical = canonicalThemeName(newValue)
            if canonical != newValue {
                selectedTheme = canonical
            }
        }
        .confirmationDialog("Support Neon Vision Editor", isPresented: $showSupportPurchaseDialog, titleVisibility: .visible) {
            Button(supportPurchaseManager.supportTipDialogButtonTitle) {
                Task { await supportPurchaseManager.purchaseSupport() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Optional consumable support purchase. Can be purchased multiple times. No features are locked behind this purchase.")
        }
        .alert(
            "App Store",
            isPresented: Binding(
                get: { supportPurchaseManager.statusMessage != nil },
                set: { if !$0 { supportPurchaseManager.statusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(supportPurchaseManager.statusMessage ?? "")
        }
        .sheet(isPresented: $showDataDisclosureDialog) {
            dataDisclosureDialog
        }
        .sheet(isPresented: $showRemoteConnectSheet) {
            remoteConnectSheet
        }
        .sheet(isPresented: $showRemoteAttachSheet) {
            remoteAttachSheet
        }
        .onDisappear {
            supportRefreshTask?.cancel()
            supportRefreshTask = nil
        }
    }

    // MARK: - Lifecycle Helpers

    private func refreshSupportStoreStateIfNeeded() {
        guard supportRefreshTask == nil else { return }
        supportRefreshTask = Task {
            await supportPurchaseManager.refreshStoreState()
            await MainActor.run {
                supportRefreshTask = nil
            }
        }
    }

    private func loadAPITokensIfNeeded() {
        if grokAPIToken.isEmpty { grokAPIToken = SecureTokenStore.token(for: .grok) }
        if openAIAPIToken.isEmpty { openAIAPIToken = SecureTokenStore.token(for: .openAI) }
        if geminiAPIToken.isEmpty { geminiAPIToken = SecureTokenStore.token(for: .gemini) }
        if anthropicAPIToken.isEmpty { anthropicAPIToken = SecureTokenStore.token(for: .anthropic) }
        if openCodeGoAPIToken.isEmpty { openCodeGoAPIToken = SecureTokenStore.token(for: .openCodeGo) }
        if customProviderAPIToken.isEmpty { customProviderAPIToken = SecureTokenStore.token(for: .customProvider) }
    }

    private var preferredColorSchemeOverride: ColorScheme? {
        ReleaseRuntimePolicy.preferredColorScheme(for: appearance)
    }

#if os(macOS)
    private func applyAppearanceImmediately() {
        let target: NSAppearance?
        switch appearance {
        case "light":
            target = NSAppearance(named: .aqua)
        case "dark":
            target = NSAppearance(named: .darkAqua)
        default:
            target = nil
        }
        NSApp.appearance = target
        for window in NSApp.windows {
            window.appearance = target
        }
    }
#endif

    // MARK: - General Settings

    private var generalTab: some View {
        settingsContainer {
            settingsSectionHeader(
                icon: "gearshape",
                title: LocalizedStringKey(localized("General")),
                subtitle: LocalizedStringKey(localized("Window behavior, startup defaults, and confirmation preferences."))
            )

#if os(iOS) || os(visionOS)
            if useTwoColumnSettingsLayout && !isVisionSettingsLayout {
                iPadQuickSummaryCard
            }
#endif

            if useTwoColumnSettingsLayout {
#if os(visionOS)
                visionGeneralSettingsLayout
#else
                LazyVGrid(columns: settingsTwoColumnGridItems, spacing: settingsTwoColumnGridSpacing) {
                    windowSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    toolbarSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    startupSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    confirmationsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
#endif
            } else {
                windowSection
#if os(iOS) || os(visionOS)
                if isCompactSettingsLayout {
                    startupSection
                    confirmationsSection
                    toolbarSection
                } else {
                    toolbarSection
                    startupSection
                    confirmationsSection
                }
#else
                toolbarSection
                startupSection
                confirmationsSection
#endif
            }
        }
    }

#if os(visionOS)
    private var visionGeneralSettingsLayout: some View { visionGeneralSettingsForm }

    private var visionGeneralSettingsForm: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            visionDetailHeader(
                title: localized("General"),
                subtitle: localized("Window behavior, startup defaults, and confirmation preferences."),
                icon: "gearshape"
            )

            visionFormSection(title: localized("Current Setup")) {
                visionReadOnlyRow(title: localized("Theme"), value: selectedTheme)
                visionReadOnlyRow(title: localized("Editor Font"), value: editorFontSummaryLabel)
                visionReadOnlyRow(title: localized("AI Model"), value: selectedAIModelDisplayName)
            }

            visionFormSection(title: localized("Window"), footnote: localized("Language changes apply after relaunch.")) {
                visionLabeledRow(title: localized("Appearance")) {
                    Picker("", selection: $appearance) {
                        Text(localized("System")).tag("system")
                        Text(localized("Light")).tag("light")
                        Text(localized("Dark")).tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                visionLabeledRow(title: localized("App Language")) {
                    visionSettingsMenu(
                        selection: $appLanguageCode,
                        options: appLanguageOptions,
                        label: appLanguageLabel(for:),
                        maxWidth: 220
                    )
                    .accessibilityLabel(localized("App Language"))
                }
                visionToggleRow(title: localized("iCloud Appearance & Theme Sync"), isOn: $iCloudAppearanceThemeSyncEnabled)
                if iCloudAppearanceThemeSyncEnabled {
                    HStack(spacing: UI.space8) {
                        Button(localized("Sync Now")) {
                            let result = AppearanceThemeCloudSync.syncNow()
                            iCloudAppearanceThemeSyncStatus = result.message
                            if result.didApplyRemoteSettings {
                                selectedTheme = canonicalThemeName(selectedTheme)
                            }
                        }
                        Button(localized("Pull from iCloud")) {
                            let result = AppearanceThemeCloudSync.pullRemoteSettings()
                            iCloudAppearanceThemeSyncStatus = result.message
                            if result.didApplyRemoteSettings {
                                selectedTheme = canonicalThemeName(selectedTheme)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    Text(iCloudAppearanceThemeSyncStatus)
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            visionFormSection(title: localized("Startup"), footnote: localized("Enable only one startup mode to keep app launch behavior predictable.")) {
                Toggle(localized("Open with Blank Document"), isOn: $openWithBlankDocument)
                    .disabled(reopenLastSession)
                Toggle(localized("Reopen Last Session"), isOn: $reopenLastSession)
                Toggle(localized("Automatically Open Shared Imports"), isOn: $shareImportsAutoOpen)
                    .accessibilityHint(localized("When disabled, shared files are saved to the import history without opening editor tabs immediately."))
                visionLabeledRow(title: localized("Default New File Language")) {
                    visionSettingsMenu(
                        selection: $defaultNewFileLanguage,
                        options: templateLanguages,
                        label: languageLabel(for:),
                        maxWidth: 220
                    )
                    .accessibilityLabel(localized("Default New File Language"))
                }
            }

            visionFormSection(title: localized("Confirmations")) {
                Toggle(localized("Confirm Before Closing Dirty Tab"), isOn: $confirmCloseDirtyTab)
                Toggle(localized("Confirm Before Clearing Editor"), isOn: $confirmClearEditor)
            }
        }
        .onChange(of: openWithBlankDocument) { _, isEnabled in
            if isEnabled {
                reopenLastSession = false
            }
        }
        .onChange(of: reopenLastSession) { _, isEnabled in
            if isEnabled {
                openWithBlankDocument = false
            }
        }
    }

    private var visionToolbarSettings: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            visionDetailHeader(
                title: localized("Toolbar"),
                subtitle: localized("Choose which controls stay visible in the visionOS toolbar."),
                icon: "rectangle.topthird.inset.filled"
            )
            visionFormSection(title: localized("Visible Controls")) {
                Toggle(localized("Open File Icon"), isOn: $toolbarShowOpenFileIOS)
                Toggle(localized("Undo Icon"), isOn: $toolbarShowUndoIOS)
                Toggle(localized("Settings Icon"), isOn: $toolbarShowSettingsIOS)
                Toggle(localized("Help Icon"), isOn: $toolbarShowHelpIOS)
                Toggle(localized("Search"), isOn: $toolbarShowSearchIOS)
                Toggle(localized("Compare"), isOn: $toolbarShowCompareIOS)
                Toggle(localized("Editor Tools"), isOn: $toolbarShowEditorUtilityIOS)
                Toggle(localized("Preview & Appearance"), isOn: $toolbarShowAppearanceIOS)
            }
        }
    }

    private var visionAppearanceSettings: some View {
        let isCustom = selectedTheme == "Custom"
        let palette = themePaletteColors(for: selectedTheme)
        let previewTheme = currentEditorTheme(colorScheme: effectiveSettingsColorScheme)
        return VStack(alignment: .leading, spacing: UI.space12) {
            visionDetailHeader(
                title: localized("Appearance"),
                subtitle: localized("Theme and token colors."),
                icon: "paintpalette"
            )
            visionMarkdownPreviewReaderSettings
            themeSelectionPane(includesMarkdownPreviewSettings: false)
            themeCustomizationPane(isCustom: isCustom, palette: palette, previewTheme: previewTheme)
        }
    }

    private var visionMarkdownPreviewReaderSettings: some View {
        let selectedStyle = ContentView.VisionMarkdownPreviewReaderStyle(rawValue: markdownPreviewReaderStyleVisionRaw) ?? .systemGlass
        return visionFormSection(title: localized("Editor & Markdown Preview"), footnote: localized("Changes the editor and preview reading surface, not the window glass.")) {
            Picker(localized("Reading Surface"), selection: $markdownPreviewReaderStyleVisionRaw) {
                ForEach(ContentView.VisionMarkdownPreviewReaderStyle.allCases) { style in
                    Text(localized(style.title)).tag(style.rawValue)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel(localized("Editor and Markdown Preview Reading Surface"))

            Text(localized(selectedStyle.title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visionFormSection<Content: View>(
        title: String,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: UI.space8) {
                content()
            }
            .padding(.horizontal, UI.space12)
            .padding(.vertical, UI.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(effectiveSettingsColorScheme == .dark ? 0.06 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(effectiveSettingsColorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
            )
            if let footnote {
                Text(footnote)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visionReadOnlyRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: UI.space12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)
            Text(value)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func visionLabeledRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: UI.space12) {
            Text(title)
                .foregroundStyle(.primary)
                .frame(width: 190, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func visionToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
    }
#endif

    @ViewBuilder
    private var toolbarSection: some View {
#if os(visionOS)
        settingsCardSection(
            title: LocalizedStringKey(localized("Toolbar")),
            icon: "rectangle.topthird.inset.filled",
            emphasis: .secondary,
            showsAccentStripe: false,
            tip: LocalizedStringKey(localized("Visible groups expand into the available toolbar width and overflow only when the window is too narrow."))
        ) {
            iOSToggleRow(LocalizedStringKey(localized("Open File Icon")), isOn: $toolbarShowOpenFileIOS)
            iOSToggleRow(LocalizedStringKey(localized("Undo Icon")), isOn: $toolbarShowUndoIOS)
            iOSToggleRow(LocalizedStringKey(localized("Settings Icon")), isOn: $toolbarShowSettingsIOS)
            iOSToggleRow(LocalizedStringKey(localized("Help Icon")), isOn: $toolbarShowHelpIOS)
            iOSToggleRow(LocalizedStringKey(localized("Search")), isOn: $toolbarShowSearchIOS)
            iOSToggleRow(LocalizedStringKey(localized("Compare")), isOn: $toolbarShowCompareIOS)
            iOSToggleRow(LocalizedStringKey(localized("Editor Tools")), isOn: $toolbarShowEditorUtilityIOS)
            iOSToggleRow(LocalizedStringKey(localized("Preview & Appearance")), isOn: $toolbarShowAppearanceIOS)
        }
#elseif os(iOS)
        settingsCardSection(
            title: LocalizedStringKey(localized("Toolbar")),
            icon: "rectangle.topthird.inset.filled",
            showsAccentStripe: false,
            tip: LocalizedStringKey(localized("Choose which toolbar groups stay visible on iPhone and iPad."))
        ) {
            iOSLabeledRow(LocalizedStringKey(localized("Visible Toolbar Actions"))) {
                Picker("", selection: $toolbarFavoriteCountIOS) {
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                    Text("7").tag(7)
                    Text("8").tag(8)
                    Text("10").tag(10)
                    Text(localized("All")).tag(99)
                }
                .pickerStyle(.segmented)
            }
            iOSToggleRow(LocalizedStringKey(localized("Open File Icon")), isOn: $toolbarShowOpenFileIOS)
            iOSToggleRow(LocalizedStringKey(localized("Undo Icon")), isOn: $toolbarShowUndoIOS)
            iOSToggleRow(LocalizedStringKey(localized("Settings Icon")), isOn: $toolbarShowSettingsIOS)
            iOSToggleRow(LocalizedStringKey(localized("Help Icon")), isOn: $toolbarShowHelpIOS)
            iOSToggleRow(LocalizedStringKey(localized("Search")), isOn: $toolbarShowSearchIOS)
            iOSToggleRow(LocalizedStringKey(localized("Compare")), isOn: $toolbarShowCompareIOS)
            iOSToggleRow(LocalizedStringKey(localized("Editor Tools")), isOn: $toolbarShowEditorUtilityIOS)
            iOSToggleRow(LocalizedStringKey(localized("Preview & Appearance")), isOn: $toolbarShowAppearanceIOS)
            iOSToggleRow(LocalizedStringKey(localized("Use Custom Icons")), isOn: $toolbarUseCustomFiveIOS)
            if toolbarUseCustomFiveIOS {
                iOSLabeledRow(LocalizedStringKey(localized("Selected Icons"))) {
                    Button(action: { showToolbarIconChooser = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text(toolbarCustomSelectionSummary)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $showToolbarIconChooser) {
            toolbarIconChooserSheet
        }
#else
        EmptyView()
#endif
    }

    private var windowSection: some View {
#if os(iOS) || os(visionOS)
        settingsCardSection(
            title: LocalizedStringKey(localized("Window")),
            icon: "macwindow.badge.plus",
            showsAccentStripe: false,
            tip: LocalizedStringKey(localized("Choose how windows open and how appearance is applied."))
        ) {
            if supportsOpenInTabs {
                iOSLabeledRow(LocalizedStringKey(localized("Open in Tabs"))) {
                    Picker("", selection: $openInTabs) {
                        Text(localized("Follow System")).tag("system")
                        Text(localized("Always")).tag("always")
                        Text(localized("Never")).tag("never")
                    }
                    .pickerStyle(.segmented)
                }
            }

            iOSLabeledRow(LocalizedStringKey(localized("Appearance"))) {
                Picker("", selection: $appearance) {
                    Text(localized("System")).tag("system")
                    Text(localized("Light")).tag("light")
                    Text(localized("Dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }

            iOSLabeledRow(LocalizedStringKey(localized("App Language"))) {
#if os(visionOS)
                visionSettingsMenu(
                    selection: $appLanguageCode,
                    options: appLanguageOptions,
                    label: appLanguageLabel(for:),
                    maxWidth: .infinity
                )
                .accessibilityLabel(localized("App Language"))
#else
                Picker("", selection: $appLanguageCode) {
                    ForEach(appLanguageOptions, id: \.self) { languageCode in
                        Text(appLanguageLabel(for: languageCode)).tag(languageCode)
                    }
                }
                .neonSettingsDropdown(maxWidth: .infinity)
                .accessibilityLabel(localized("App Language"))
#endif
            }

            Text(localized("Language changes apply after relaunch."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            if supportsTranslucency {
                iOSToggleRow(LocalizedStringKey(localized("Translucent Window")), isOn: $translucentWindow)
            }

            iCloudAppearanceThemeSyncControls
        }
#else
        GroupBox(localized("Window")) {
            VStack(alignment: .leading, spacing: UI.space12) {
                if supportsOpenInTabs {
                    HStack(alignment: .center, spacing: UI.space12) {
                        Text(localized("Open in Tabs"))
                            .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                        Picker("", selection: $openInTabs) {
                            Text(localized("Follow System")).tag("system")
                            Text(localized("Always")).tag("always")
                            Text(localized("Never")).tag("never")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text(localized("Appearance"))
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Picker("", selection: $appearance) {
                        Text(localized("System")).tag("system")
                        Text(localized("Light")).tag("light")
                        Text(localized("Dark")).tag("dark")
                    }
                        .pickerStyle(.segmented)
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text(localized("App Language"))
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Picker("", selection: $appLanguageCode) {
                        ForEach(appLanguageOptions, id: \.self) { languageCode in
                            Text(appLanguageLabel(for: languageCode)).tag(languageCode)
                        }
                    }
                    .neonSettingsDropdown(maxWidth: isCompactSettingsLayout ? .infinity : 240)
                    .accessibilityLabel(localized("App Language"))
                }

                Text(localized("Language changes apply after relaunch."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: UI.space12) {
                    Text(localized("Toolbar Symbols"))
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Picker("", selection: $toolbarSymbolsColorMacRaw) {
                        Text(localized("Blue")).tag("blue")
                        Text(localized("Dark Gray")).tag("darkGray")
                        Text(localized("Black")).tag("black")
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(localized("Simple Start Mode"), isOn: $isToolbarCollapsed)
                    .help(localized("Starts the editor with the macOS toolbar collapsed."))
                    .accessibilityHint(localized("Starts the editor with the macOS toolbar collapsed."))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(localized("Show Menu Bar Icon"), isOn: $showMenuBarIconMac)
                    .help(localized("Shows the Welcome Tour shortcut in the macOS menu bar."))
                    .accessibilityHint(localized("Shows or hides the Welcome Tour shortcut in the macOS menu bar."))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if supportsTranslucency {
                    Toggle(localized("Translucent Window"), isOn: $translucentWindow)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text(localized("Translucency Mode"))
                            .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                        Picker("", selection: $macTranslucencyModeRaw) {
                            ForEach(MacTranslucencyModeOption.allCases) { option in
                                Text(localized(option.title)).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!translucentWindow)
                    }
                }

                Divider()

                iCloudAppearanceThemeSyncControls
            }
            .padding(UI.groupPadding)
        }
#endif
    }

    private var iCloudAppearanceThemeSyncControls: some View {
        VStack(alignment: .leading, spacing: UI.space10) {
            Toggle(localized("iCloud Appearance & Theme Sync"), isOn: $iCloudAppearanceThemeSyncEnabled)
                .accessibilityHint("Syncs appearance and theme settings with iCloud Key-Value Store.")

            Text(localized("Syncs only appearance and theme preferences across your signed-in devices. Documents, API tokens, and remote connection details are not synced."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UI.space8) {
                Button(localized("Sync Now")) {
                    let result = AppearanceThemeCloudSync.syncNow()
                    iCloudAppearanceThemeSyncStatus = result.message
                    if result.didApplyRemoteSettings {
                        selectedTheme = canonicalThemeName(selectedTheme)
#if os(macOS)
                        applyAppearanceImmediately()
#endif
                    }
                }
                .disabled(!iCloudAppearanceThemeSyncEnabled)

                Button(localized("Pull from iCloud")) {
                    let result = AppearanceThemeCloudSync.pullRemoteSettings()
                    iCloudAppearanceThemeSyncStatus = result.message
                    if result.didApplyRemoteSettings {
                        selectedTheme = canonicalThemeName(selectedTheme)
#if os(macOS)
                        applyAppearanceImmediately()
#endif
                    }
                }
                .disabled(!iCloudAppearanceThemeSyncEnabled)
            }

            Text(iCloudAppearanceThemeSyncStatus)
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var editorFontSection: some View {
#if os(iOS) || os(visionOS)
        settingsCardSection(
            title: LocalizedStringKey(localized("Editor Font")),
            icon: "textformat",
            emphasis: .secondary,
            showsAccentStripe: false
        ) {
            iOSToggleRow(LocalizedStringKey(localized("Use System Font")), isOn: $useSystemFont)

            iOSLabeledRow(LocalizedStringKey(localized("Font"))) {
                Picker("", selection: selectedFontBinding) {
                    Text(localized("System")).tag(systemFontSentinel)
                    ForEach(availableEditorFonts, id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .neonSettingsDropdown(maxWidth: .infinity)
                .accessibilityLabel(localized("Font"))
            }

            iOSLabeledRow(LocalizedStringKey(localized("Font Size"))) {
                HStack(spacing: UI.space12) {
                    Text(localized("%lld pt", Int64(Int(editorFontSize))))
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 64, alignment: .trailing)
                    Stepper("", value: $editorFontSize, in: 10...28, step: 1)
                        .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: UI.space8) {
                HStack(alignment: .firstTextBaseline, spacing: UI.space12) {
                    Text(localized("Line Height"))
                        .frame(width: iOSSettingsLabelWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(String(format: "%.2fx", lineHeight))
                        .font(.body.monospacedDigit())
                        .frame(width: 64, alignment: .trailing)
                }
                Slider(value: $lineHeight, in: 1.0...1.8, step: 0.05)
            }
        }
#else
        GroupBox(localized("Editor Font")) {
            VStack(alignment: .leading, spacing: UI.space12) {
                Toggle(localized("Use System Font"), isOn: $useSystemFont)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: UI.space12) {
                    Text(localized("Font"))
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: UI.space8) {
                        HStack(spacing: UI.space8) {
                            Text(useSystemFont ? localized("System") : (editorFontName.isEmpty ? localized("System") : editorFontName))
                                .font(Typography.footnote)
                                .foregroundStyle(.secondary)
                            Button(showFontList ? localized("Hide Font List") : localized("Show Font List")) {
                                showFontList.toggle()
                            }
                            .buttonStyle(.borderless)
                        }
                        if showFontList {
                            Picker("", selection: selectedFontBinding) {
                                Text(localized("System")).tag(systemFontSentinel)
                                ForEach(availableEditorFonts, id: \.self) { fontName in
                                    Text(fontName).tag(fontName)
                                }
                            }
                            .neonSettingsDropdown(maxWidth: isCompactSettingsLayout ? .infinity : 240)
                            .accessibilityLabel(localized("Font"))
                        }
                    }
                    .frame(maxWidth: isCompactSettingsLayout ? .infinity : 240, alignment: .leading)
#if os(macOS)
                    Button(localized("Choose…")) {
                        useSystemFont = false
                        showFontList = true
                    }
                    .disabled(useSystemFont)
#endif
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text(localized("Font Size"))
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Stepper(value: $editorFontSize, in: 10...28, step: 1) {
                        Text(localized("%lld pt", Int64(Int(editorFontSize))))
                    }
                    .frame(maxWidth: isCompactSettingsLayout ? .infinity : 220, alignment: .leading)
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text(localized("Line Height"))
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Slider(value: $lineHeight, in: 1.0...1.8, step: 0.05)
                        .frame(maxWidth: isCompactSettingsLayout ? .infinity : 240)
                    Text(String(format: "%.2fx", lineHeight))
                        .frame(width: 54, alignment: .trailing)
                }
            }
            .padding(UI.groupPadding)
        }
#endif
    }

    private var startupSection: some View {
        Group {
#if os(iOS) || os(visionOS)
            settingsCardSection(
                title: LocalizedStringKey(localized("Startup")),
                icon: "bolt.horizontal",
                emphasis: .secondary,
                showsAccentStripe: false
            ) {
                startupSectionContent
            }
#else
            GroupBox(localized("Startup")) {
                startupSectionContent
                    .padding(UI.groupPadding)
            }
#endif
        }
        .onChange(of: openWithBlankDocument) { _, isEnabled in
            if isEnabled {
                reopenLastSession = false
            }
        }
        .onChange(of: reopenLastSession) { _, isEnabled in
            if isEnabled {
                openWithBlankDocument = false
            }
        }
    }

    private var startupSectionContent: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            Toggle(localized("Open with Blank Document"), isOn: $openWithBlankDocument)
                .disabled(reopenLastSession)
            Toggle(localized("Reopen Last Session"), isOn: $reopenLastSession)
            Toggle(localized("Automatically Open Shared Imports"), isOn: $shareImportsAutoOpen)
                .accessibilityHint(localized("When disabled, shared files are saved to the import history without opening editor tabs immediately."))
            HStack(alignment: .center, spacing: UI.space12) {
                Text(localized("Default New File Language"))
                    .frame(width: isCompactSettingsLayout ? nil : startupLabelWidth, alignment: .leading)
#if os(visionOS)
                visionSettingsMenu(
                    selection: $defaultNewFileLanguage,
                    options: templateLanguages,
                    label: languageLabel(for:),
                    maxWidth: isCompactSettingsLayout ? .infinity : 240
                )
                .accessibilityLabel(localized("Default New File Language"))
#else
                Picker("", selection: $defaultNewFileLanguage) {
                    ForEach(templateLanguages, id: \.self) { lang in
                        Text(languageLabel(for: lang)).tag(lang)
                    }
                }
                .neonSettingsDropdown(maxWidth: isCompactSettingsLayout ? .infinity : 240)
                .accessibilityLabel(localized("Default New File Language"))
#endif
            }
            Text(localized("Tip: Enable only one startup mode to keep app launch behavior predictable."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var confirmationsSection: some View {
        Group {
#if os(iOS) || os(visionOS)
            settingsCardSection(
                title: LocalizedStringKey(localized("Confirmations")),
                icon: "checkmark.shield",
                emphasis: .secondary,
                showsAccentStripe: false
            ) {
                confirmationsSectionContent
            }
#else
            GroupBox(localized("Confirmations")) {
                confirmationsSectionContent
                    .padding(UI.groupPadding)
            }
#endif
        }
    }

    private var confirmationsSectionContent: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            Toggle(localized("Confirm Before Closing Dirty Tab"), isOn: $confirmCloseDirtyTab)
            Toggle(localized("Confirm Before Clearing Editor"), isOn: $confirmClearEditor)
        }
    }

#if os(iOS) || os(visionOS)
    // MARK: - iOS Toolbar Customization

    private enum IOSToolbarIconOption: String, CaseIterable, Identifiable {
        case openFile
        case undo
        case settings
        case help
        case clearEditor
        case insertTemplate
        case newTab
        case saveFile
        case saveFileAs
        case codeSnapshot
        case markdownPreview
        case codeMinimap
        case indentationGuides
        case markdownPreviewExport
        case markdownPreviewStyle
        case closeAllTabs
        case toggleSidebar
        case toggleProjectSidebar
        case findReplace
        case findInFiles
        case compareDisk
        case compareTabs
        case splitEditor
        case lineWrap
        case codeCompletion
        case keyboardAccessory
        case hideKeyboard
        case performanceMode
        case brainDump
        case welcomeTour
        case translucentWindow
        case toolbarIconColor

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openFile: return "Open File"
            case .undo: return "Undo"
            case .settings: return "Settings"
            case .help: return "Help"
            case .clearEditor: return "Clear Editor"
            case .insertTemplate: return "Insert Template"
            case .newTab: return "New Tab"
            case .saveFile: return "Save"
            case .saveFileAs: return "Save As"
            case .codeSnapshot: return "Code Snapshot"
            case .markdownPreview: return "Markdown Preview"
            case .codeMinimap: return "Code Minimap"
            case .indentationGuides: return "Indentation Guides"
            case .markdownPreviewExport: return "Export PDF"
            case .markdownPreviewStyle: return "Preview Style"
            case .closeAllTabs: return "Close All Tabs"
            case .toggleSidebar: return "Toggle Sidebar"
            case .toggleProjectSidebar: return "Toggle Project Sidebar"
            case .findReplace: return "Find"
            case .findInFiles: return "Find in Files"
            case .compareDisk: return "Compare with Disk"
            case .compareTabs: return "Compare Tabs"
            case .splitEditor: return "Side by Side"
            case .lineWrap: return "Line Wrap"
            case .codeCompletion: return "Code Completion"
            case .keyboardAccessory: return "Keyboard Bar"
            case .hideKeyboard: return "Hide Keyboard"
            case .performanceMode: return "Performance Mode"
            case .brainDump: return "Brain Dump"
            case .welcomeTour: return "Welcome Tour"
            case .translucentWindow: return "Translucent Window"
            case .toolbarIconColor: return "Blue Icons"
            }
        }
    }

    private var toolbarCustomSelectedIDs: Set<String> {
        ToolbarActionSelection.selectedIDs(from: toolbarCustomFiveIDsIOS)
    }

    private var toolbarCustomSelectionSummary: String {
        "\(toolbarCustomSelectedIDs.count)/\(toolbarCustomIconLimit)"
    }

    private var toolbarCustomIconLimit: Int {
        ToolbarActionSelection.visibleLimit(
            requestedCount: toolbarFavoriteCountIOS,
            fallback: IOSToolbarIconOption.allCases.count
        )
    }

    @ViewBuilder
    private var toolbarIconChooserSheet: some View {
        NavigationStack {
            List {
                Section("Choose up to \(toolbarCustomIconLimit) icons") {
                    ForEach(IOSToolbarIconOption.allCases) { option in
                        Button(action: { toggleToolbarCustomIcon(option.rawValue) }) {
                            HStack {
                                Text(option.title)
                                Spacer()
                                if toolbarCustomSelectedIDs.contains(option.rawValue) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Toolbar Icons")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        toolbarCustomFiveIDsIOS = ""
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showToolbarIconChooser = false }
                }
            }
        }
    }

    private func toggleToolbarCustomIcon(_ rawValue: String) {
        toolbarCustomFiveIDsIOS = ToolbarActionSelection.toggledSelectionRawValue(
            toggledID: rawValue,
            currentRawValue: toolbarCustomFiveIDsIOS,
            orderedIDs: IOSToolbarIconOption.allCases.map(\.rawValue),
            limit: toolbarCustomIconLimit
        )
    }

    private var iOSSettingsLabelWidth: CGFloat {
        #if os(visionOS)
        return useTwoColumnSettingsLayout ? 210 : 156
        #else
        useTwoColumnSettingsLayout ? 176 : 138
        #endif
    }

    private func iOSLabeledRow<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: UI.space12) {
            Text(label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: iOSSettingsLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iOSToggleRow(_ label: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: UI.space12) {
            Text(label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: iOSSettingsLabelWidth, alignment: .leading)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

#if os(visionOS)
    private func visionSettingsMenu(
        selection: Binding<String>,
        options: [String],
        label: @escaping (String) -> String,
        maxWidth: CGFloat?
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if option == selection.wrappedValue {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: UI.space8) {
                Text(label(selection.wrappedValue))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.leading, UI.space12)
            .padding(.trailing, UI.space10)
            .padding(.vertical, UI.space8)
            .frame(minHeight: 38, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        effectiveSettingsColorScheme == .dark
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(0.66)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(effectiveSettingsColorScheme == .dark ? 0.20 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
#endif

    private var selectedAIModelDisplayName: String {
        (AIModel(rawValue: selectedAIModelRaw) ?? .appleIntelligence).displayName
    }

    private var editorFontSummaryLabel: String {
        let fontLabel = useSystemFont ? localized("System") : (editorFontName.isEmpty ? localized("System") : editorFontName)
        return "\(fontLabel) • \(Int(editorFontSize)) pt • \(String(format: "%.2fx", lineHeight))"
    }

    private var mobileSettingsAccentColor: Color {
        switch settingsActiveTab {
        case "general":
            return .teal
        case "editor":
            return .blue
        case "templates":
            return .mint
        case "themes":
            return .orange
        case "ai":
            return .indigo
        case "remote":
            return .cyan
        case "support":
            return .pink
        case "more":
            switch moreSectionTab {
            case "ai":
                return .indigo
            case "remote":
                return .cyan
            default:
                return .pink
            }
        default:
            return .accentColor
        }
    }

    private var iPadQuickSummaryCard: some View {
        settingsCardSection(
            title: LocalizedStringKey(localized("Current Setup")),
            icon: "rectangle.stack.badge.person.crop",
            showsAccentStripe: false,
            tip: LocalizedStringKey(localized("Snapshot updates immediately as settings change."))
        ) {
            VStack(alignment: .leading, spacing: UI.space8) {
                HStack(spacing: UI.space8) {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Theme")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(selectedTheme)
                        .font(.body.weight(.semibold))
                }
                HStack(spacing: UI.space8) {
                    Image(systemName: "textformat")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Editor Font")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(editorFontSummaryLabel)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
                HStack(spacing: UI.space8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("AI Model")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(selectedAIModelDisplayName)
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func settingsCardSection<Content: View>(
        title: LocalizedStringKey,
        icon: String? = nil,
        emphasis: MobileCardEmphasis = .primary,
        showsAccentStripe: Bool = false,
        tip: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let strokeOpacity = settingsMobileCardStrokeOpacity(emphasis: emphasis)
        let shadowOpacity = settingsMobileCardShadowOpacity(emphasis: emphasis)
        return VStack(alignment: .leading, spacing: UI.space12) {
            HStack(alignment: .firstTextBaseline, spacing: UI.space8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mobileSettingsAccentColor)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Typography.sectionHeadline)
            }
            content()
            if let tip {
                Text(tip)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.groupPadding)
        .background(
            RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous)
                .fill(settingsMobileCardFill(emphasis: emphasis))
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous)
                        .stroke(Color.secondary.opacity(strokeOpacity), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(shadowOpacity), radius: emphasis == .primary ? 10 : 6, x: 0, y: emphasis == .primary ? 4 : 2)
        )
        .overlay(alignment: .topLeading) {
            if showsAccentStripe {
                Capsule(style: .continuous)
                    .fill(mobileSettingsAccentColor.opacity(emphasis == .primary ? 0.95 : 0.70))
                    .frame(height: UI.cardAccentHeight)
                    .padding(.horizontal, UI.space12)
                    .padding(.top, UI.space8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous))
        .foregroundStyle(settingsMobileCardForeground)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
#endif

    // MARK: - Font Loading

    private let systemFontSentinel = "__system__"
    @State private var selectedFontValue: String = "__system__"
    @State private var showFontList: Bool = {
#if os(macOS)
        false
#else
        true
#endif
    }()

    private var selectedFontBinding: Binding<String> {
        Binding(
            get: {
                if useSystemFont { return systemFontSentinel }
                if editorFontName.isEmpty { return systemFontSentinel }
                if availableEditorFonts.isEmpty { return systemFontSentinel }
                if !availableEditorFonts.contains(editorFontName) { return systemFontSentinel }
                return editorFontName
            },
            set: { newValue in
                selectedFontValue = newValue
                if newValue == systemFontSentinel {
                    useSystemFont = true
                } else {
                    useSystemFont = false
                    editorFontName = newValue
                }
            }
        )
    }

    private func loadAvailableEditorFontsIfNeeded() {
        if !availableEditorFonts.isEmpty {
            syncSelectedFontValue()
            return
        }
        if !Self.cachedEditorFonts.isEmpty {
            availableEditorFonts = Self.cachedEditorFonts
            syncSelectedFontValue()
            return
        }
        guard !isDiscoveringFonts else { return }
        isDiscoveringFonts = true
        let selectedEditorFont = editorFontName
        // Defer and compute font list off the main thread to avoid settings-open hitches.
        DispatchQueue.global(qos: .userInitiated).async {
            let rawNames = CTFontManagerCopyAvailablePostScriptNames() as NSArray
            var names = Array(Set(rawNames.compactMap { $0 as? String })).sorted()
            if !selectedEditorFont.isEmpty && !names.contains(selectedEditorFont) {
                names.insert(selectedEditorFont, at: 0)
            }
            DispatchQueue.main.async {
                Self.cachedEditorFonts = names
                availableEditorFonts = names
                syncSelectedFontValue()
                isDiscoveringFonts = false
            }
        }
    }

    private var settingsTwoColumnGridSpacing: CGFloat {
#if os(visionOS)
        UI.space12
#else
        UI.space16
#endif
    }

    private var settingsTwoColumnGridItems: [GridItem] {
        [
            GridItem(.flexible(), spacing: settingsTwoColumnGridSpacing),
            GridItem(.flexible(), spacing: settingsTwoColumnGridSpacing)
        ]
    }

#if os(iOS) || os(visionOS)
    private func settingsMobileCardFill(emphasis: MobileCardEmphasis) -> AnyShapeStyle {
#if os(visionOS)
        return AnyShapeStyle(
            effectiveSettingsColorScheme == .dark
                ? Color.white.opacity(emphasis == .primary ? 0.08 : 0.06)
                : Color.white.opacity(emphasis == .primary ? 0.18 : 0.14)
        )
#else
        return AnyShapeStyle(emphasis == .primary ? .regularMaterial : .thinMaterial)
#endif
    }

    private func settingsMobileCardStrokeOpacity(emphasis: MobileCardEmphasis) -> Double {
#if os(visionOS)
        effectiveSettingsColorScheme == .dark ? 0.18 : 0.12
#else
        emphasis == .primary ? 0.24 : 0.16
#endif
    }

    private func settingsMobileCardShadowOpacity(emphasis: MobileCardEmphasis) -> Double {
#if os(visionOS)
        effectiveSettingsColorScheme == .dark ? 0.04 : 0.02
#else
        emphasis == .primary ? 0.10 : 0.04
#endif
    }

    private var settingsMobileCardForeground: Color {
#if os(visionOS)
        Color.primary
#else
        Color.primary
#endif
    }
#endif

    private func syncSelectedFontValue() {
        if useSystemFont || editorFontName.isEmpty {
            selectedFontValue = systemFontSentinel
            return
        }
        selectedFontValue = availableEditorFonts.contains(editorFontName) ? editorFontName : systemFontSentinel
    }

    private var selectedUpdateInterval: AppUpdateCheckInterval {
        AppUpdateCheckInterval(rawValue: updateCheckIntervalRaw) ?? .daily
    }

    // MARK: - Editor Settings

    private var editorTab: some View {
        settingsContainer(maxWidth: editorSettingsMaxWidth) {
            settingsSectionHeader(
                icon: "slider.horizontal.3",
                title: "Editor",
                subtitle: "Display, indentation, editing behavior, and completion sources."
            )

            if isIPadRegularSettingsLayout {
#if os(visionOS)
                HStack(alignment: .top, spacing: settingsTwoColumnGridSpacing) {
                    VStack(alignment: .leading, spacing: settingsTwoColumnGridSpacing) {
                        editorFontSection
                        editorBehaviorSettings
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: settingsTwoColumnGridSpacing) {
                        editorBasicsSettings
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
#else
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: UI.space16), GridItem(.flexible(), spacing: UI.space16)],
                    spacing: UI.space16
                ) {
                    editorFontSection
                    editorBasicsSettings
                    editorBehaviorSettings
                }
#endif
            } else {
                editorSectionPicker
                if editorSectionTab == "basics" {
                    editorFontSection
                    editorBasicsSettings
                } else if editorSectionTab == "behavior" {
                    editorBehaviorSettings
                } else {
                    editorStatusBarSettings
                }
            }
        }
    }

    private var editorSectionPicker: some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            Text("Section")
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            Picker("Section", selection: $editorSectionTab) {
                Text("Basics").tag("basics")
                Text("Behavior").tag("behavior")
#if os(macOS)
                Text("Layout & Status").tag("statusBar")
#endif
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editorBasicsSettings: some View {
#if os(iOS) || os(visionOS)
        VStack(spacing: UI.space16) {
            settingsCardSection(
                title: "Display",
                icon: "eye",
                tip: "Scope visuals are best used with line wrap disabled."
            ) {
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                Toggle("Highlight Current Line", isOn: $highlightCurrentLine)
                Toggle("Highlight Matching Brackets", isOn: $highlightMatchingBrackets)
                Toggle("Show Indentation Guides", isOn: $showIndentationGuides)
                Toggle("Show Scope Guides (Non-Swift)", isOn: $showScopeGuides)
                Toggle("Highlight Scoped Region", isOn: $highlightScopeBackground)
                Toggle("Line Wrap", isOn: $lineWrapEnabled)
                Toggle("Show Invisible Characters", isOn: $showInvisibleCharacters)
                Text("When Line Wrap is enabled, scope guides/scoped region are turned off to avoid layout conflicts.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                Text("Scope guides are intended for non-Swift languages. Swift favors matching-token highlight.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                Text("Invisible character markers may affect rendering performance on very large files.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsCardSection(
                title: "Indentation",
                icon: "increase.indent",
                emphasis: .secondary
            ) {
                Picker("Indent Style", selection: $indentStyle) {
                    Text("Spaces").tag("spaces")
                    Text("Tabs").tag("tabs")
                }
                .pickerStyle(.segmented)

                Stepper(value: $indentWidth, in: 2...8, step: 1) {
                    Text(localized("Indent Width: %lld", Int64(indentWidth)))
                }
            }

            settingsCardSection(
                title: "Layout",
                icon: "sidebar.left",
                emphasis: .secondary
            ) {
                Picker("Project Navigator Position", selection: $projectNavigatorPlacementRaw) {
                    Text("Left").tag(ContentView.ProjectNavigatorPlacement.leading.rawValue)
                    Text("Right").tag(ContentView.ProjectNavigatorPlacement.trailing.rawValue)
                }
                .pickerStyle(.segmented)

                iOSLabeledRow(LocalizedStringKey(localized("Disclosure Icon"))) {
                    Picker("", selection: $projectSidebarDisclosureSymbolStyleRaw) {
                        ForEach(ProjectSidebarDisclosureSymbolStyleOption.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .neonSettingsDropdown(maxWidth: .infinity)
                    .accessibilityLabel(localized("Disclosure Icon"))
                }
            }

            settingsCardSection(
                title: "Status Bar",
                icon: "info.circle",
                emphasis: .secondary,
                tip: "On iPhone and compact iPad layouts, the status pill shows only the first enabled items that fit."
            ) {
                statusBarSettingsContent
            }
        }
#else
        GroupBox("Editor Basics") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Display")
                        .font(Typography.sectionHeadline)
                    Toggle("Show Line Numbers", isOn: $showLineNumbers)
                    Toggle("Highlight Current Line", isOn: $highlightCurrentLine)
                    Toggle("Highlight Matching Brackets", isOn: $highlightMatchingBrackets)
                    Toggle("Show Indentation Guides", isOn: $showIndentationGuides)
                    Toggle("Show Scope Guides (Non-Swift)", isOn: $showScopeGuides)
                    Toggle("Highlight Scoped Region", isOn: $highlightScopeBackground)
                    Toggle("Line Wrap", isOn: $lineWrapEnabled)
                    Toggle("Show Invisible Characters", isOn: $showInvisibleCharacters)
                    Text("When Line Wrap is enabled, scope guides/scoped region are turned off to avoid layout conflicts.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    Text("Scope guides are intended for non-Swift languages. Swift favors matching-token highlight.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    Text("Invisible character markers may affect rendering performance on very large files.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UI.groupPadding)
        }
#endif
    }

    private var statusBarSettingsContent: some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            Toggle("Cursor Position", isOn: $statusBarShowCursor)
            Toggle("Line Count", isOn: $statusBarShowLineCount)
            Toggle("Word Count", isOn: $statusBarShowWordCount)
            Toggle("Encoding", isOn: $statusBarShowEncoding)
            Toggle("Line Endings", isOn: $statusBarShowLineEndings)
            Toggle("Indentation", isOn: $statusBarShowIndentation)
            Toggle("Selection Size", isOn: $statusBarShowSelection)
            Toggle("File Size", isOn: $statusBarShowFileSize)
            Toggle("Git Branch and Changes", isOn: $statusBarShowGit)
#if os(iOS) || os(visionOS)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Editing Mobile Status Preset", isOn: $mobileEditingStatusPresetEnabled)
                Text("On iPhone while typing, the floating status pill can switch to caret, selection, and large-file details only. Expanded details auto-collapse again after a few seconds.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editorStatusBarSettings: some View {
#if os(iOS) || os(visionOS)
        settingsCardSection(
            title: "Status Bar",
            icon: "info.circle",
            emphasis: .secondary,
            tip: "On iPhone and compact iPad layouts, the status pill shows only the first enabled items that fit."
        ) {
            statusBarSettingsContent
        }
#else
        GroupBox("Layout & Status Bar") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Adjust editor layout details and choose which compact document details appear in the status bar.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Indentation")
                        .font(Typography.sectionHeadline)
                    Picker("Indent Style", selection: $indentStyle) {
                        Text("Spaces").tag("spaces")
                        Text("Tabs").tag("tabs")
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $indentWidth, in: 2...8, step: 1) {
                        Text(localized("Indent Width: %lld", Int64(indentWidth)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Layout")
                        .font(Typography.sectionHeadline)
                    Picker("Project Navigator Position", selection: $projectNavigatorPlacementRaw) {
                        Text("Left").tag(ContentView.ProjectNavigatorPlacement.leading.rawValue)
                        Text("Right").tag(ContentView.ProjectNavigatorPlacement.trailing.rawValue)
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text(localized("Disclosure Icon"))
                            .frame(width: standardLabelWidth, alignment: .leading)
                        Picker("", selection: $projectSidebarDisclosureSymbolStyleRaw) {
                            ForEach(ProjectSidebarDisclosureSymbolStyleOption.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .neonSettingsDropdown(maxWidth: 220)
                        .accessibilityLabel(localized("Disclosure Icon"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Status Bar")
                        .font(Typography.sectionHeadline)
                    statusBarSettingsContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(UI.groupPadding)
        }
        .frame(maxWidth: 580, alignment: .leading)
#endif
    }

    private var editorBehaviorSettings: some View {
#if os(iOS) || os(visionOS)
        VStack(spacing: UI.space16) {
            settingsCardSection(
                title: "Performance",
                icon: "speedometer",
                emphasis: .secondary
            ) {
                Picker("Preset", selection: $performancePresetRaw) {
                    Text("Balanced").tag(ContentView.PerformancePreset.balanced.rawValue)
                    Text("Large Files").tag(ContentView.PerformancePreset.largeFiles.rawValue)
                    Text("Battery").tag(ContentView.PerformancePreset.battery.rawValue)
                }
                .pickerStyle(.segmented)
                Text("Balanced keeps default behavior. Large Files and Battery enter performance mode earlier.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                Picker("Large File Syntax", selection: $largeFileSyntaxHighlightingRaw) {
                    Text("Off").tag("off")
                    Text("Minimal").tag("minimal")
                }
                .pickerStyle(.segmented)
                Picker("Large File Open", selection: $largeFileOpenModeRaw) {
                    Text("Standard").tag("standard")
                    Text("Responsive").tag("deferred")
                    Text("Plain Text").tag("plainText")
                }
                .pickerStyle(.segmented)
                Text("Minimal colors only visible JSON lines plus a small buffer using a strict work budget.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                Text("Large File Mode remains editable. Responsive defers costly loading, layout, and syntax work; Plain Text also turns off syntax coloring, previews, and the minimap.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                Text("Files at 100 MB or more open as a read-only 4 MB partial preview so the complete file is never copied into memory.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }

            settingsCardSection(
                title: "Editing",
                icon: "keyboard",
                emphasis: .secondary
            ) {
                Toggle("Auto Indent", isOn: $autoIndent)
                Toggle("Auto Close Brackets", isOn: $autoCloseBrackets)
                Toggle("Trim Trailing Whitespace", isOn: $trimTrailingWhitespace)
                Toggle("Trim Edges for Syntax Detection", isOn: $trimWhitespaceForSyntaxDetection)
                if isIPadDevice {
                    Divider()
                    Toggle("Enable Vim Mode", isOn: vimModeBinding)
                    Text("Requires a hardware keyboard on iPad. Escape returns to Normal mode, and the status line shows INSERT or NORMAL while Vim mode is active.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCardSection(
                title: "Keyboard Shortcuts",
                icon: "command",
                emphasis: .secondary
            ) {
                shortcutSettingsContent
            }

            settingsCardSection(
                title: "Completion",
                icon: "sparkles",
                emphasis: .secondary
            ) {
                Toggle("Enable Completion", isOn: $completionEnabled)
                Toggle("Include Words in Document", isOn: $completionFromDocument)
                Toggle("Include Syntax Keywords", isOn: $completionFromSyntax)
                Text("For lower latency on large files, keep only one completion source enabled.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
#else
        GroupBox("Editor Behavior") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Performance")
                        .font(Typography.sectionHeadline)
                    Picker("Preset", selection: $performancePresetRaw) {
                        Text("Balanced").tag(ContentView.PerformancePreset.balanced.rawValue)
                        Text("Large Files").tag(ContentView.PerformancePreset.largeFiles.rawValue)
                        Text("Battery").tag(ContentView.PerformancePreset.battery.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Text("Balanced keeps default behavior. Large Files and Battery enter performance mode earlier.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)

                    Picker("Large File Syntax", selection: $largeFileSyntaxHighlightingRaw) {
                        Text("Off").tag("off")
                        Text("Minimal").tag("minimal")
                    }
                    .pickerStyle(.segmented)
                    Picker("Large File Open", selection: $largeFileOpenModeRaw) {
                        Text("Standard").tag("standard")
                        Text("Responsive").tag("deferred")
                        Text("Plain Text").tag("plainText")
                    }
                    .pickerStyle(.segmented)
                    Text("Minimal colors only visible JSON lines plus a small buffer using a strict work budget.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    Text("Large File Mode remains editable. Responsive defers costly loading, layout, and syntax work; Plain Text also turns off syntax coloring, previews, and the minimap.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    Text("Files at 100 MB or more open as a read-only 4 MB partial preview so the complete file is never copied into memory.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Editing")
                        .font(Typography.sectionHeadline)
                    Toggle("Auto Indent", isOn: $autoIndent)
                    Toggle("Auto Close Brackets", isOn: $autoCloseBrackets)
                    Toggle("Trim Trailing Whitespace", isOn: $trimTrailingWhitespace)
                    Toggle("Trim Edges for Syntax Detection", isOn: $trimWhitespaceForSyntaxDetection)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Completion")
                        .font(Typography.sectionHeadline)
                    Toggle("Enable Completion", isOn: $completionEnabled)
                    Toggle("Include Words in Document", isOn: $completionFromDocument)
                    Toggle("Include Syntax Keywords", isOn: $completionFromSyntax)
                    Text("For lower latency on large files, keep only one completion source enabled.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UI.groupPadding)
        }
#endif
    }

    // MARK: - Template Settings

    private var templateTab: some View {
        settingsContainer(maxWidth: 640) {
            settingsSectionHeader(
                icon: "doc.badge.plus",
                title: "Templates",
                subtitle: "Control language-specific starter content used when inserting templates."
            )
#if os(iOS) || os(visionOS)
            settingsCardSection(
                title: "Completion Template",
                icon: "doc.text",
                tip: "Template content is inserted exactly as shown."
            ) {
                HStack(alignment: .center, spacing: UI.space12) {
                    Text("Language")
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Picker("", selection: $settingsTemplateLanguage) {
                        ForEach(templateLanguages, id: \.self) { lang in
                            Text(languageLabel(for: lang)).tag(lang)
                        }
                    }
                    .neonSettingsDropdown(maxWidth: isCompactSettingsLayout ? .infinity : 220)
                    .accessibilityLabel(localized("Language"))
                }

                TextEditor(text: templateBinding(for: settingsTemplateLanguage))
                    .font(Typography.monoBody)
                    .frame(minHeight: 200, maxHeight: 320)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                HStack(spacing: UI.space12) {
                    Button("Reset to Default", role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: templateOverrideKey(for: settingsTemplateLanguage))
                    }
                    Button("Use Default Template") {
                        if let fallback = defaultTemplate(for: settingsTemplateLanguage) {
                            UserDefaults.standard.set(fallback, forKey: templateOverrideKey(for: settingsTemplateLanguage))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
#else
            GroupBox("Completion Template") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Language")
                            .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                        Picker("", selection: $settingsTemplateLanguage) {
                            ForEach(templateLanguages, id: \.self) { lang in
                                Text(languageLabel(for: lang)).tag(lang)
                            }
                        }
                        .neonSettingsDropdown(maxWidth: isCompactSettingsLayout ? .infinity : 220)
                        .accessibilityLabel(localized("Language"))
                    }

                    TextEditor(text: templateBinding(for: settingsTemplateLanguage))
                        .font(Typography.monoBody)
                        .frame(minHeight: 200, maxHeight: 320)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    HStack(spacing: UI.space12) {
                        Button("Reset to Default", role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: templateOverrideKey(for: settingsTemplateLanguage))
                        }
                        Button("Use Default Template") {
                            if let fallback = defaultTemplate(for: settingsTemplateLanguage) {
                                UserDefaults.standard.set(fallback, forKey: templateOverrideKey(for: settingsTemplateLanguage))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(UI.groupPadding)
            }
#endif
        }
    }

    // MARK: - Theme Settings

    private var themeTab: some View {
        let isCustom = selectedTheme == "Custom"
        let palette = themePaletteColors(for: selectedTheme)
        let previewTheme = currentEditorTheme(colorScheme: effectiveSettingsColorScheme)
        return settingsContainer(maxWidth: themeSettingsMaxWidth) {
            settingsSectionHeader(
                icon: "paintpalette",
                title: "Themes",
                subtitle: "Pick a preset or customize token colors for your editing environment."
            )
#if os(macOS)
            if isCompactSettingsLayout {
                VStack(alignment: .leading, spacing: UI.space16) {
                    GroupBox {
                        themeSelectionPane(includesMarkdownPreviewSettings: true, showsTitle: true)
                            .padding(UI.groupPadding)
                    }
                    GroupBox {
                        themeCustomizationPane(isCustom: isCustom, palette: palette, previewTheme: previewTheme)
                            .padding(UI.groupPadding)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    GroupBox {
                        themeSelectionPane(
                            includesMarkdownPreviewSettings: false,
                            showsTitle: true,
                            macThemeListMaxHeight: 440,
                            previewTheme: previewTheme
                        )
                            .padding(UI.groupPadding)
                    }
                    .frame(width: 360, alignment: .topLeading)

                    GroupBox {
                        VStack(alignment: .leading, spacing: UI.space16) {
                            themeCustomizationPane(
                                isCustom: isCustom,
                                palette: palette,
                                previewTheme: previewTheme,
                                showsPreview: false
                            )

                            markdownPreviewThemeSettingsCard
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .padding(UI.groupPadding)
                    }
                    .frame(width: 460, alignment: .topLeading)
                }
            }
#else
            Group {
                if isCompactSettingsLayout {
                    VStack(alignment: .leading, spacing: UI.space16) {
                        themeSelectionPane
                        themeCustomizationPane(isCustom: isCustom, palette: palette, previewTheme: previewTheme)
                    }
                } else {
                    HStack(alignment: .top, spacing: isVisionSettingsLayout ? settingsTwoColumnGridSpacing : UI.space16) {
                        themeSelectionPane
                        themeCustomizationPane(isCustom: isCustom, palette: palette, previewTheme: previewTheme)
                    }
                }
            }
#if os(iOS) || os(visionOS)
            .padding(.top, isVisionSettingsLayout ? 0 : 20)
#endif
#endif
        }
        .alert("Save Theme As", isPresented: $showSaveThemeDialog) {
            TextField("Theme Name", text: $newThemeName)
            Button("Save") { saveCustomThemes(name: newThemeName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let error = themeSaveError {
                Text(error)
            } else {
                Text("Enter a name for your custom theme.")
            }
        }
    }

    private var editorSettingsMaxWidth: CGFloat {
#if os(visionOS)
        760
#elseif os(macOS)
        editorSectionTab == "statusBar" ? 560 : 760
#else
        isIPadRegularSettingsLayout ? 1120 : 760
#endif
    }

    private var themeSettingsMaxWidth: CGFloat {
#if os(visionOS)
        940
#elseif os(macOS)
        880
#else
        760
#endif
    }

    private var themeSelectionPane: some View {
        themeSelectionPane(includesMarkdownPreviewSettings: true)
    }

    private var showsThemeSelectionScrollbar: Bool {
        isThemeSelectionHovering || isThemeSelectionSelecting
    }

    private func themeSelectionPane(
        includesMarkdownPreviewSettings: Bool,
        showsTitle: Bool = false,
        macThemeListMaxHeight: CGFloat = 360,
        previewTheme: EditorTheme? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: UI.space12) {
#if os(macOS)
            if showsTitle {
                HStack(alignment: .firstTextBaseline, spacing: UI.space12) {
                    Text("Theme Selection")
                        .font(Typography.sectionSubheadline)
                    if previewTheme != nil {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.secondary)
            }

            if let previewTheme {
                themePreviewSnippet(previewTheme: previewTheme, showsTitle: false)
            }

            ScrollView(.vertical, showsIndicators: showsThemeSelectionScrollbar) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(themes, id: \.self) { theme in
                        themeSelectionRow(theme)
                        if theme != themes.last {
                            Divider()
                                .opacity(0.55)
                        }
                    }
                }
                .padding(.vertical, UI.space6)
            }
            .frame(minWidth: 200, maxHeight: macThemeListMaxHeight)
            .background(settingsCardBackground(cornerRadius: UI.cardCorner))
            .onHover { hovering in
                isThemeSelectionHovering = hovering
            }
#else
            if isCompactSettingsLayout {
                VStack(alignment: .leading, spacing: UI.space10) {
                    Text("Theme")
                        .font(Typography.sectionSubheadline)
                        .foregroundStyle(.secondary)

                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(themes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .neonSettingsDropdown(maxWidth: .infinity)
                    .accessibilityLabel("Theme")

                    Text(selectedTheme)
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                let listView = List {
                    ForEach(themes, id: \.self) { theme in
                        HStack {
                            let isCustomTheme = loadCustomThemes().keys.contains(theme)
                            Text(theme)
                                .foregroundStyle(isCustomTheme ? Color.accentColor : .primary)
                            Spacer()
                            if theme == selectedTheme {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                            if isCustomTheme {
                                Button(role: .destructive) {
                                    deleteCustomTheme(theme)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary.opacity(0.6))
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete custom theme \(theme)")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTheme = theme
                        }
                        .listRowBackground(Color.clear)
                    }
                    Color.clear
                        .frame(height: 96)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .frame(minWidth: 200)
                .listStyle(.plain)
                .background(settingsCardBackground(cornerRadius: UI.cardCorner))
                .clipShape(RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous))
                if #available(iOS 16.0, *) {
                    listView.scrollContentBackground(.hidden)
                } else {
                    listView
                }
            }
#endif
            VStack(alignment: .leading, spacing: UI.space10) {
                Text("Formatting")
                    .font(Typography.sectionSubheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 140), spacing: UI.space12, alignment: .leading),
                        GridItem(.flexible(minimum: 140), spacing: UI.space12, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: UI.space8
                ) {
                    Toggle("Bold keywords", isOn: $themeBoldKeywords)
                    Toggle("Italic comments", isOn: $themeItalicComments)
                    Toggle("Underline links", isOn: $themeUnderlineLinks)
                    Toggle("Bold Markdown headings", isOn: $themeBoldMarkdownHeadings)
                }
            }
            .padding(UI.space12)
            .background(settingsCardBackground(cornerRadius: UI.cardCorner))

            if includesMarkdownPreviewSettings {
                markdownPreviewThemeSettingsCard
            }
        }
        .padding(UI.space8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: selectedTheme) { oldTheme, newTheme in
            saveCurrentColorsToOverrides(for: oldTheme)
            if let colors = loadHexOverrides()[newTheme] ?? loadCustomThemes()[newTheme] {
                themeTextHex = colors["text"] ?? defaultHex(for: "text", themeName: newTheme)
                themeBackgroundHex = backgroundHex(from: colors, themeName: newTheme)
                themeCursorHex = colors["cursor"] ?? defaultHex(for: "cursor", themeName: newTheme)
                themeSelectionHex = colors["selection"] ?? defaultHex(for: "selection", themeName: newTheme)
                themeKeywordHex = colors["keyword"] ?? defaultHex(for: "keyword", themeName: newTheme)
                themeStringHex = colors["string"] ?? defaultHex(for: "string", themeName: newTheme)
                themeNumberHex = colors["number"] ?? defaultHex(for: "number", themeName: newTheme)
                themeCommentHex = colors["comment"] ?? defaultHex(for: "comment", themeName: newTheme)
                themeTypeHex = colors["type"] ?? defaultHex(for: "type", themeName: newTheme)
                themeBuiltinHex = colors["builtin"] ?? defaultHex(for: "builtin", themeName: newTheme)
            } else if newTheme != "Custom" && !loadCustomThemes().keys.contains(newTheme) {
                themeTextHex = defaultHex(for: "text", themeName: newTheme)
                themeBackgroundHex = defaultHex(for: "background", themeName: newTheme)
                themeCursorHex = defaultHex(for: "cursor", themeName: newTheme)
                themeSelectionHex = defaultHex(for: "selection", themeName: newTheme)
                themeKeywordHex = defaultHex(for: "keyword", themeName: newTheme)
                themeStringHex = defaultHex(for: "string", themeName: newTheme)
                themeNumberHex = defaultHex(for: "number", themeName: newTheme)
                themeCommentHex = defaultHex(for: "comment", themeName: newTheme)
                themeTypeHex = defaultHex(for: "type", themeName: newTheme)
                themeBuiltinHex = defaultHex(for: "builtin", themeName: newTheme)
            }
        }
        .onChange(of: effectiveSettingsColorScheme) { _, _ in
            let colors = loadHexOverrides()[selectedTheme] ?? loadCustomThemes()[selectedTheme] ?? [:]
            themeBackgroundHex = backgroundHex(from: colors, themeName: selectedTheme)
        }
    }

    private var markdownPreviewThemeSettingsCard: some View {
        VStack(alignment: .leading, spacing: UI.space10) {
            Text("Markdown Preview")
                .font(Typography.sectionSubheadline)
                .foregroundStyle(.secondary)

            Menu {
                Menu("Template") {
                    ForEach(ContentView.markdownPreviewTemplateOptions) { option in
                        Button(option.title) {
                            markdownPreviewTemplateRaw = option.id
                        }
                    }
                }

                Menu("Background") {
                    ForEach(ContentView.standardMarkdownPreviewBackgroundStyles) { style in
                        Button(style.title) {
                            markdownPreviewBackgroundStyleRaw = style.rawValue
                        }
                    }
                }

                Menu("Dialect") {
                    ForEach(ContentView.MarkdownPreviewDialect.allCases) { dialect in
                        Button(dialect.title) {
                            markdownPreviewDialectRaw = dialect.rawValue
                        }
                    }
                }
            } label: {
                Label("Preview Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Markdown Preview Settings")

            Text("\(markdownPreviewTemplateRaw) • \(markdownPreviewBackgroundStyleRaw) • \(markdownPreviewDialectRaw)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Choose how the Markdown preview surface and parser behave.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.space12)
        .background(settingsCardBackground(cornerRadius: UI.cardCorner))
    }

    private func themeCustomizationPane(
        isCustom: Bool,
        palette: ThemePaletteColors,
        previewTheme: EditorTheme,
        showsPreview: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            HStack(alignment: .firstTextBaseline, spacing: UI.space8) {
                Text("Theme Colors")
                    .font(Typography.sectionHeadline)
                Text(isCustom ? "Custom" : "Preset")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isCustom ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.16))
                    )
                    .foregroundStyle(isCustom ? .blue : .secondary)
            }

            HStack(spacing: UI.space8) {
                Circle().fill(palette.background).frame(width: 12, height: 12)
                Circle().fill(palette.text).frame(width: 12, height: 12)
                Circle().fill(palette.cursor).frame(width: 12, height: 12)
                Circle().fill(palette.selection).frame(width: 12, height: 12)
                Spacer()
                Text(selectedTheme)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, UI.space10)
            .padding(.vertical, UI.space8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
            )

            if showsPreview {
                themePreviewSnippet(previewTheme: previewTheme)
            }

            themeBaseColorControls(previewTheme: previewTheme)
            themeSyntaxColorControls(previewTheme: previewTheme)

            HStack(spacing: UI.space10) {
                Button("Save Theme As…") {
                    newThemeName = ""
                    themeSaveError = nil
                    showSaveThemeDialog = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Save current colors as a new named theme")

                Button("Reset to Defaults") {
                    let n = selectedTheme
                    themeTextHex = defaultHex(for: "text", themeName: n)
                    themeBackgroundHex = defaultHex(for: "background", themeName: n)
                    themeCursorHex = defaultHex(for: "cursor", themeName: n)
                    themeSelectionHex = defaultHex(for: "selection", themeName: n)
                    themeKeywordHex = defaultHex(for: "keyword", themeName: n)
                    themeStringHex = defaultHex(for: "string", themeName: n)
                    themeNumberHex = defaultHex(for: "number", themeName: n)
                    themeCommentHex = defaultHex(for: "comment", themeName: n)
                    themeTypeHex = defaultHex(for: "type", themeName: n)
                    themeBuiltinHex = defaultHex(for: "builtin", themeName: n)
                    var overrides = loadHexOverrides()
                    overrides.removeValue(forKey: n)
                    saveHexOverrides(overrides)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if loadCustomThemes().keys.contains(selectedTheme) {
                    Button(role: .destructive) {
                        deleteCustomTheme(selectedTheme)
                    } label: {
                        Text("Delete Theme")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, UI.space6)

            Text("Colors are editable for all themes. The colored dot shows how the color appears in the current mode. Use Reset to Defaults to restore the theme's original palette. Use Save Theme As… to create a named copy.")
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.space12)
        .background(settingsCardBackground(cornerRadius: 14))
    }

    private func themeBaseColorControls(previewTheme: EditorTheme) -> some View {
        VStack(alignment: .leading, spacing: UI.space10) {
            Text("Base")
                .font(Typography.sectionSubheadline)
                .foregroundStyle(.secondary)

            colorRow(
                title: "Text",
                color: hexBinding($themeTextHex, fallback: .white, persistText: true),
                effectiveColor: previewTheme.text,
                onReset: {
                    themeTextHex = defaultHex(for: "text", themeName: selectedTheme)
                    resetTextOverride()
                }
            )
            colorRow(
                title: "Background",
                color: hexBinding($themeBackgroundHex, fallback: .black, persistBackground: true),
                effectiveColor: previewTheme.background,
                onReset: { themeBackgroundHex = defaultHex(for: "background", themeName: selectedTheme); saveCurrentColorsToOverrides(persistBackground: true) }
            )
            colorRow(
                title: "Cursor",
                color: hexBinding($themeCursorHex, fallback: .blue),
                effectiveColor: previewTheme.cursor,
                onReset: { themeCursorHex = defaultHex(for: "cursor", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
            colorRow(
                title: "Selection",
                color: hexBinding($themeSelectionHex, fallback: .gray),
                effectiveColor: previewTheme.selection,
                onReset: { themeSelectionHex = defaultHex(for: "selection", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(UI.space12)
        .background(settingsCardBackground(cornerRadius: UI.cardCorner))
    }

    private func themeSyntaxColorControls(previewTheme: EditorTheme) -> some View {
        VStack(alignment: .leading, spacing: UI.space10) {
            Text("Syntax")
                .font(Typography.sectionSubheadline)
                .foregroundStyle(.secondary)

            colorRow(
                title: "Keywords",
                color: hexBinding($themeKeywordHex, fallback: .yellow),
                effectiveColor: previewTheme.syntax.keyword,
                onReset: { themeKeywordHex = defaultHex(for: "keyword", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
            colorRow(
                title: "Strings",
                color: hexBinding($themeStringHex, fallback: .blue),
                effectiveColor: previewTheme.syntax.string,
                onReset: { themeStringHex = defaultHex(for: "string", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
            colorRow(
                title: "Numbers",
                color: hexBinding($themeNumberHex, fallback: .orange),
                effectiveColor: previewTheme.syntax.number,
                onReset: { themeNumberHex = defaultHex(for: "number", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
            colorRow(
                title: "Comments",
                color: hexBinding($themeCommentHex, fallback: .gray),
                effectiveColor: previewTheme.syntax.comment,
                onReset: { themeCommentHex = defaultHex(for: "comment", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
            colorRow(
                title: "Types",
                color: hexBinding($themeTypeHex, fallback: .green),
                effectiveColor: previewTheme.syntax.type,
                onReset: { themeTypeHex = defaultHex(for: "type", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
            colorRow(
                title: "Builtins",
                color: hexBinding($themeBuiltinHex, fallback: .red),
                effectiveColor: previewTheme.syntax.builtin,
                onReset: { themeBuiltinHex = defaultHex(for: "builtin", themeName: selectedTheme); saveCurrentColorsToOverrides() }
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(UI.space12)
        .background(settingsCardBackground(cornerRadius: UI.cardCorner))
    }

#if os(macOS)
    private func themeSelectionRow(_ theme: String) -> some View {
        let isCustomTheme = loadCustomThemes().keys.contains(theme)
        let isSelected = theme == selectedTheme
        return HStack(spacing: UI.space8) {
            Text(theme)
                .foregroundStyle(isCustomTheme ? Color.accentColor : .primary)
            Spacer(minLength: UI.space8)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if isCustomTheme {
                Button(role: .destructive) {
                    deleteCustomTheme(theme)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Delete custom theme")
                .accessibilityLabel("Delete custom theme \(theme)")
            }
        }
        .padding(.horizontal, UI.space10)
        .padding(.vertical, UI.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.secondary.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            showThemeSelectionScrollbarBriefly()
            selectedTheme = theme
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSelected ? "\(theme), selected" : theme)
    }
#endif

    private var selectedAIModelBinding: Binding<AIModel> {
        Binding(
            get: { AIModel(rawValue: selectedAIModelRaw) ?? .appleIntelligence },
            set: { selectedAIModelRaw = $0.rawValue }
        )
    }

    // MARK: - AI, Support, and Remote Tabs

    private var moreTab: some View {
        settingsContainer(maxWidth: moreSettingsMaxWidth) {
            VStack(alignment: .leading, spacing: UI.space12) {
                settingsSectionHeader(
                    icon: "ellipsis.circle",
                    title: "More",
                    subtitle: "AI setup, remote preview controls, provider credentials, and support options."
                )
                Picker("More Section", selection: $moreSectionTab) {
                    Text("Support").tag("support")
                    Text("AI").tag("ai")
                    Text("Remote").tag("remote")
#if os(visionOS)
                    Text("Shortcuts").tag("shortcuts")
#endif
                    Text("Diagnostics").tag("diagnostics")
                }
                .pickerStyle(.segmented)
            }
            .padding(UI.groupPadding)
            .background(settingsCardBackground(cornerRadius: 14))

            ZStack {
                if moreSectionTab == "shortcuts" {
#if os(visionOS)
                    shortcutsSection
                        .transition(.opacity)
#else
                    supportSection
                        .transition(.opacity)
#endif
                } else if moreSectionTab == "ai" {
                    aiSection
                        .transition(.opacity)
                } else if moreSectionTab == "remote" {
                    remoteSection
                        .transition(.opacity)
                } else if moreSectionTab == "diagnostics" {
                    diagnosticsSection
                        .transition(.opacity)
                } else {
                    supportSection
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: moreSectionTab)
        }
    }

    private var moreSettingsMaxWidth: CGFloat {
#if os(visionOS)
        760
#else
        560
#endif
    }

    private var aiTab: some View {
        settingsContainer(maxWidth: 560) {
            settingsSectionHeader(
                icon: "brain.head.profile",
                title: "AI",
                subtitle: "AI model, privacy disclosure, and provider credentials."
            )
            aiSection
        }
    }

    private var supportTab: some View {
        settingsContainer(maxWidth: 560) {
            settingsSectionHeader(
                icon: "heart",
                title: "Support",
                subtitle: "Optional consumable support tip and build-specific options."
            )
            supportSection
#if os(macOS)
            commandLineHelperSection
#endif
        }
    }

    private var remoteTab: some View {
        settingsContainer(maxWidth: 560) {
            settingsSectionHeader(
                icon: "rectangle.connected.to.line.below",
                title: "Remote",
                subtitle: "Optional, user-triggered remote browsing and editing with zero startup activity."
            )
            remoteSection
        }
    }

#if os(visionOS)
    private var shortcutsSection: some View {
        settingsCardSection(
            title: "Keyboard Shortcuts",
            icon: "command",
            emphasis: .secondary,
            tip: "Hardware keyboard shortcuts use the same preferences as macOS."
        ) {
            shortcutSettingsContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
#endif

    // MARK: - Remote Session State and Actions

    private var trimmedRemoteHost: String {
        remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRemoteUsername: String {
        remoteUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRemoteConnectNickname: String {
        remoteConnectNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedRemotePort: Int {
        let parsedPort = Int(remotePortDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? remotePort
        return min(max(parsedPort, 1), 65535)
    }

    private var canSubmitRemoteConnectDraft: Bool {
        remoteSessionsEnabled && !trimmedRemoteHost.isEmpty
    }

    private var remoteStatusSummary: String {
        if !remoteSessionsEnabled {
            return "Local workspace only. Remote modules stay inactive until you enable this preview."
        }
        if remoteSessionStore.runtimeState == .failed,
           let attachedBroker = remoteSessionStore.attachedBrokerDescriptor {
            return "The broker session from \(attachedBroker.hostDisplayName) is no longer reachable for \(attachedBroker.targetSummary). Detach this device, then attach again using a fresh code from the active Mac session."
        }
        if remoteSessionStore.runtimeState == .failed,
           let broker = remoteSessionStore.brokerSessionDescriptor {
            return "The Mac-hosted broker session for \(broker.targetSummary) is no longer active. Start Session again on the Mac before sharing a new attach code."
        }
        if let attachedBroker = remoteSessionStore.attachedBrokerDescriptor {
            return "Attached to the Mac broker on \(attachedBroker.hostDisplayName) for \(attachedBroker.targetSummary). This device now browses, opens, edits, and explicitly saves supported remote text files through the Mac-hosted session."
        }
        if let broker = remoteSessionStore.brokerSessionDescriptor {
            return "Broker session active on \(broker.hostDisplayName) for \(broker.targetSummary). The Mac is the SSH owner for this session. Share the attach code with iPhone or iPad so they can browse, open, edit, and explicitly save supported remote text files through the Mac."
        }
        if remoteSessionStore.isRemotePreviewConnecting, let activeTarget = remoteSessionStore.activeTarget {
            return "Connecting to \(activeTarget.connectionSummary). This login is always user-triggered."
        }
        if remoteSessionStore.isRemotePreviewConnected, let activeTarget = remoteSessionStore.activeTarget {
            return "Remote session active for \(activeTarget.connectionSummary). Browse, open, edit, and explicitly save supported remote text files."
        }
        if let activeTarget = remoteSessionStore.activeTarget {
            return "Active target: \(activeTarget.connectionSummary). On macOS, Start Session performs the real SSH login from the Mac when a key is selected, or a TCP connection test otherwise. iPhone and iPad do not start SSH directly."
        }
        if !remoteSessionStore.savedTargets.isEmpty {
            return "Remote preview is enabled. Choose a saved target or create a new local preview target when ready."
        }
        if !remotePreparedTarget.isEmpty {
            return "Saved target: \(remotePreparedTarget). Open Connect to convert it into a reusable local target."
        }
        return "Remote preview is enabled, but no target is selected yet."
    }

    private func presentRemoteConnectSheet() {
        if remoteConnectNickname.isEmpty {
            if let activeTarget = remoteSessionStore.activeTarget {
                remoteConnectNickname = activeTarget.displayTitle
            } else if !trimmedRemoteHost.isEmpty {
                remoteConnectNickname = trimmedRemoteHost
            }
        }
        showRemoteConnectSheet = true
    }

    private func presentRemoteAttachSheet() {
        remoteAttachCodeDraft = ""
        showRemoteAttachSheet = true
    }

    private func connectRemotePreview() {
        guard canSubmitRemoteConnectDraft else { return }
        guard let target = remoteSessionStore.connectPreview(
            nickname: trimmedRemoteConnectNickname,
            host: trimmedRemoteHost,
            username: trimmedRemoteUsername,
            port: sanitizedRemotePort,
            sshKeyBookmarkData: {
#if os(macOS)
                remoteSSHKeyBookmarkData
#else
                nil
#endif
            }(),
            sshKeyDisplayName: {
#if os(macOS)
                remoteSSHKeyDisplayName
#else
                ""
#endif
            }()
        ) else {
            return
        }
        remoteSessionsEnabled = true
        remotePreparedTarget = target.connectionSummary
        remoteConnectNickname = target.nickname
        remotePort = target.port
        remotePortDraft = String(target.port)
        remotePreparationStatus = target.sshKeyBookmarkData == nil
            ? "Local preview target selected. No network connection has been opened."
            : "SSH target selected. The login remains inactive until you start a session."
        showRemoteConnectSheet = false
    }

    private func activateRemoteTarget(_ target: RemoteSessionStore.SavedTarget) {
        remoteSessionsEnabled = true
        remoteSessionStore.activateSavedTarget(id: target.id)
        remotePreparedTarget = target.connectionSummary
        remotePreparationStatus = "Switched to \(target.displayTitle). The workspace remains local."
    }

    private func startRemoteSession() {
        guard remoteSessionsEnabled, remoteSessionStore.isRemotePreviewReady, !remoteSessionStore.isRemotePreviewConnecting else { return }
        remotePreparationStatus = "Connecting to the selected target…"
        Task {
            let didConnect = await remoteSessionStore.startSession()
            await MainActor.run {
                remotePreparationStatus = didConnect
                    ? remoteSessionStore.sessionStatusDetail
                    : (remoteSessionStore.sessionStatusDetail.isEmpty ? "Connection failed." : remoteSessionStore.sessionStatusDetail)
            }
        }
    }

    private func stopRemoteSession() {
        remoteSessionStore.stopSession()
        remotePreparationStatus = remoteSessionStore.sessionStatusDetail.isEmpty
            ? (remoteSessionStore.isRemotePreviewReady ? "Remote session stopped. Target stays selected for later." : "Remote session stopped.")
            : remoteSessionStore.sessionStatusDetail
    }

    private func disconnectRemotePreview() {
        remoteSessionStore.disconnectPreview()
        remotePreparedTarget = ""
        remotePreparationStatus = remoteSessionsEnabled ? "Remote preview target cleared. Workspace remains local." : ""
    }

    private func attachToRemoteBroker() {
        guard remoteSessionsEnabled else { return }
        remotePreparationStatus = "Attaching to the broker…"
        Task {
            let didAttach = await remoteSessionStore.attachToBroker(code: remoteAttachCodeDraft)
            await MainActor.run {
                remotePreparationStatus = didAttach
                    ? remoteSessionStore.sessionStatusDetail
                    : (remoteSessionStore.sessionStatusDetail.isEmpty ? "Broker attach failed." : remoteSessionStore.sessionStatusDetail)
                if didAttach {
                    showRemoteAttachSheet = false
                    remoteBrowserPathDraft = remoteSessionStore.remoteBrowserPath
                }
            }
        }
    }

    private func detachRemoteBroker() {
        remoteSessionStore.detachBrokerClient()
        remotePreparationStatus = remoteSessionStore.sessionStatusDetail.isEmpty
            ? "Detached from the broker."
            : remoteSessionStore.sessionStatusDetail
    }

    private func recoverRemoteBrokerAttachment() {
        remoteSessionStore.detachBrokerClient()
        remotePreparationStatus = "Paste a fresh attach code from the active Mac session to reattach."
        presentRemoteAttachSheet()
    }

    private func removeRemoteTarget(_ target: RemoteSessionStore.SavedTarget) {
        let wasActive = remoteSessionStore.activeTargetID == target.id
        remoteSessionStore.removeSavedTarget(id: target.id)
        if wasActive {
            remotePreparedTarget = ""
            remotePreparationStatus = remoteSessionsEnabled ? "Removed the active remote preview target. Workspace remains local." : ""
        } else {
            remotePreparationStatus = "Removed \(target.displayTitle) from saved local targets."
        }
    }

    private var remoteTargetActiveBadge: some View {
        Text("Active")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private var remoteRuntimeBadgeTitle: String {
        switch remoteSessionStore.runtimeState {
        case .connecting:
            return "Connecting"
        case .active:
            return "Session Active"
        case .failed:
            return "Failed"
        default:
            return "Ready"
        }
    }

    private var remoteSessionRuntimeBadge: some View {
        Text(remoteRuntimeBadgeTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private var remoteBrokerBadge: some View {
        Text("Broker")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    private var remoteBrokerDescriptorCard: some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            HStack(alignment: .firstTextBaseline, spacing: UI.space8) {
                Text("Broker Session")
                    .font(.headline)
                remoteBrokerBadge
            }

            if let broker = remoteSessionStore.brokerSessionDescriptor {
                Text("\(broker.hostDisplayName) • \(broker.ownerPlatform)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(broker.targetSummary)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)

                Text("Capabilities: \(broker.capabilities.map(\.displayTitle).joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if remoteSessionStore.canAttachExternalClients, !remoteSessionStore.brokerAttachCode.isEmpty {
                    Text("Attach Code")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(remoteSessionStore.brokerAttachCode)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)

                    Button("Copy Attach Code") {
                        copyRemoteBrokerAttachCode()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Use this attach code on iPhone or iPad only after the Mac session is already active. The Mac keeps the SSH key and the SSH connection; attached devices work through that Mac-hosted broker session.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(UI.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(inputFieldBackground.opacity(0.85))
        )
    }

    private func copyRemoteBrokerAttachCode() {
        let code = remoteSessionStore.brokerAttachCode
        guard !code.isEmpty else { return }
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = code
#endif
        remotePreparationStatus = localized("Copied the broker attach code.")
    }

    private var remoteHelpSection: some View {
        VStack(alignment: .leading, spacing: UI.space10) {
            Label(localized("How To Connect"), systemImage: "questionmark.circle")
                .font(.headline)

            Text(localized("On the Mac: enable Remote, open Connect, enter the SSH target server host, user, and port, optionally choose an SSH key, then press Connect Locally and Start Session. The SSH target server must be a real machine or service running an SSH server, not an iPhone or iPad simulator."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            Text(localized("If you use your local Mac as the SSH target with 127.0.0.1:22 and see 'connection refused', your Mac is not running an SSH server yet. Open System Settings > General > Sharing and enable Remote Login, then try Start Session again."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            Text(localized("On iPhone or iPad: do not enter an SSH key. Copy the Attach Code from the active Mac broker, open Attach to Broker, paste the code, and attach."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            Text(localized("After attaching: use Remote Browser to open a supported text file, edit it in the editor, and use Save to write it back to the same remote path through the Mac-hosted session. Save As stays local-only."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            Text(localized("If the Mac-hosted broker session disappears while editing, Save will stop and the app will ask you to detach and reattach. Restart the session on the Mac first if needed, then use a fresh attach code."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func remoteTargetCard(_ target: RemoteSessionStore.SavedTarget) -> some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            HStack(alignment: .firstTextBaseline, spacing: UI.space8) {
                Text(target.displayTitle)
                    .font(.headline)
                if remoteSessionStore.activeTargetID == target.id {
                    remoteTargetActiveBadge
                    remoteSessionRuntimeBadge
                }
            }

            Text(target.connectionSummary)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            HStack(spacing: UI.space8) {
                Button(remoteSessionStore.activeTargetID == target.id ? localized("Selected") : localized("Use Saved Target")) {
                    activateRemoteTarget(target)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!remoteSessionsEnabled || remoteSessionStore.activeTargetID == target.id)

                Button(localized("Remove")) {
                    removeRemoteTarget(target)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(UI.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(inputFieldBackground.opacity(0.85))
        )
    }

    private var remoteSessionActionButtons: some View {
        ViewThatFits {
            HStack(spacing: UI.space12) {
                Button(localized("Connect…")) {
                    presentRemoteConnectSheet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!remoteSessionsEnabled)

                Button(localized("Attach…")) {
                    presentRemoteAttachSheet()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionsEnabled || remoteSessionStore.isBrokerClientAttached)

                Button(localized("Start Session")) {
                    startRemoteSession()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionsEnabled || !remoteSessionStore.isRemotePreviewReady || remoteSessionStore.isRemotePreviewConnected || remoteSessionStore.isRemotePreviewConnecting)

                Button(localized("Stop Session")) {
                    stopRemoteSession()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionStore.isRemotePreviewConnected && !remoteSessionStore.isRemotePreviewConnecting)

                Button(localized("Disconnect")) {
                    disconnectRemotePreview()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionStore.isRemotePreviewReady && remotePreparedTarget.isEmpty)

                Button(localized("Detach Broker")) {
                    detachRemoteBroker()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionStore.isBrokerClientAttached)
            }

            VStack(alignment: .leading, spacing: UI.space8) {
                Button(localized("Connect…")) {
                    presentRemoteConnectSheet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!remoteSessionsEnabled)

                Button(localized("Attach…")) {
                    presentRemoteAttachSheet()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionsEnabled || remoteSessionStore.isBrokerClientAttached)

                Button(localized("Start Session")) {
                    startRemoteSession()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionsEnabled || !remoteSessionStore.isRemotePreviewReady || remoteSessionStore.isRemotePreviewConnected || remoteSessionStore.isRemotePreviewConnecting)

                Button(localized("Stop Session")) {
                    stopRemoteSession()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionStore.isRemotePreviewConnected && !remoteSessionStore.isRemotePreviewConnecting)

                Button(localized("Disconnect")) {
                    disconnectRemotePreview()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionStore.isRemotePreviewReady && remotePreparedTarget.isEmpty)

                Button(localized("Detach Broker")) {
                    detachRemoteBroker()
                }
                .buttonStyle(.bordered)
                .disabled(!remoteSessionStore.isBrokerClientAttached)
            }
        }
    }

    private var remoteSavedTargetsList: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            ForEach(Array(remoteSessionStore.savedTargets), id: \.id) { target in
                remoteTargetCard(target)
            }
        }
    }

    private func syncRemotePortDraftFromStoredValue() {
        remotePortDraft = String(remotePort)
    }

    private func applyRemotePortDraft() {
        let sanitizedPort = sanitizedRemotePort
        remotePort = sanitizedPort
        remotePortDraft = String(sanitizedPort)
    }

    private func syncRemoteBrowserPathDraft() {
        remoteBrowserPathDraft = remoteSessionStore.remoteBrowserPath
    }

    private func loadRemoteBrowserPath(_ path: String? = nil) {
        Task {
            let didLoad: Bool
            if remoteSessionStore.isBrokerClientAttached {
                didLoad = await remoteSessionStore.loadAttachedBrokerDirectory(path: path)
            } else {
#if os(macOS)
                didLoad = await remoteSessionStore.loadRemoteDirectory(path: path)
#else
                didLoad = false
#endif
            }
            await MainActor.run {
                syncRemoteBrowserPathDraft()
                if didLoad {
                    remotePreparationStatus = remoteSessionStore.remoteBrowserStatusDetail
                }
            }
        }
    }

    private func browseRemoteParentDirectory() {
        let currentPath = remoteSessionStore.remoteBrowserPath
        guard currentPath != "/" && currentPath != "~" else { return }
        let nsPath = currentPath as NSString
        let parentPath = nsPath.deletingLastPathComponent
        loadRemoteBrowserPath(parentPath.isEmpty ? "/" : parentPath)
    }

    private func browseRemoteHomeDirectory() {
        loadRemoteBrowserPath("~")
    }

    private func applyRemoteBrowserPathDraft() {
        loadRemoteBrowserPath(remoteBrowserPathDraft)
    }

    private func retryRemoteBrowserLoad() {
        let requestedPath = remoteBrowserPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        loadRemoteBrowserPath(requestedPath.isEmpty ? remoteSessionStore.remoteBrowserPath : requestedPath)
    }

    private func openRemoteFile(_ entry: RemoteSessionStore.RemoteFileEntry) {
        Task {
            guard let document = await remoteSessionStore.openRemoteDocument(path: entry.path) else {
                await MainActor.run {
                    remotePreparationStatus = remoteSessionStore.remoteBrowserStatusDetail
                }
                return
            }
            await MainActor.run {
#if os(macOS)
                let activeEditorViewModel = WindowViewModelRegistry.shared.activeViewModel() ?? editorViewModel
#else
                let activeEditorViewModel = editorViewModel
#endif
                activeEditorViewModel.openRemoteDocument(
                    name: document.name,
                    remotePath: document.path,
                    content: document.content,
                    isReadOnly: document.isReadOnly,
                    revisionToken: document.revisionToken
                )
                remotePreparationStatus = document.isReadOnly
                    ? "Opened \(document.name) as a read-only remote file."
                    : "Opened \(document.name) for remote editing."
            }
        }
    }

#if os(macOS)
    private func syncRemoteSSHKeyDraftFromActiveTarget() {
        remoteSSHKeyBookmarkData = remoteSessionStore.activeTarget?.sshKeyBookmarkData
        remoteSSHKeyDisplayName = remoteSessionStore.activeTarget?.sshKeyDisplayName ?? ""
    }

    private func chooseRemoteSSHKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.title = "Select SSH Private Key"
        panel.prompt = "Use Key"

        guard panel.runModal() == .OK, let keyURL = panel.url else { return }

        let didAccess = keyURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                keyURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let bookmarkData = try? keyURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            remotePreparationStatus = "The selected SSH key could not be stored securely."
            return
        }

        remoteSSHKeyBookmarkData = bookmarkData
        remoteSSHKeyDisplayName = keyURL.lastPathComponent
    }

    private func clearRemoteSSHKeySelection() {
        remoteSSHKeyBookmarkData = nil
        remoteSSHKeyDisplayName = ""
    }
#endif

    private var canShowRemoteBrowser: Bool {
        remoteSessionStore.isBrokerClientAttached ||
        (remoteSessionStore.isRemotePreviewConnected && remoteSessionStore.activeTarget?.sshKeyBookmarkData != nil)
    }

    private var showsRemoteBrowserRecoveryActions: Bool {
        remoteSessionStore.isBrokerClientAttached && remoteSessionStore.runtimeState == .failed
    }

    private var showsRemoteBrowserRetryAction: Bool {
        !remoteSessionStore.isRemoteBrowserLoading &&
        remoteSessionStore.remoteBrowserEntries.isEmpty &&
        !remoteSessionStore.remoteBrowserStatusDetail.isEmpty
    }

    private var remoteBrowserSection: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            HStack(spacing: UI.space12) {
                TextField(localized("Remote Path"), text: $remoteBrowserPathDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyRemoteBrowserPathDraft()
                    }

                Button(localized("Refresh")) {
                    loadRemoteBrowserPath(remoteBrowserPathDraft)
                }
                .buttonStyle(.bordered)
                .disabled(remoteSessionStore.isRemoteBrowserLoading)

                Button(localized("Up")) {
                    browseRemoteParentDirectory()
                }
                .buttonStyle(.bordered)
                .disabled(remoteSessionStore.isRemoteBrowserLoading || remoteSessionStore.remoteBrowserPath == "/" || remoteSessionStore.remoteBrowserPath == "~")

                Button(localized("Home")) {
                    browseRemoteHomeDirectory()
                }
                .buttonStyle(.bordered)
                .disabled(remoteSessionStore.isRemoteBrowserLoading || remoteSessionStore.remoteBrowserPath == "~")
            }

            Text("\(localized("Current Path:")) \(remoteSessionStore.remoteBrowserPath)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Text(remoteSessionStore.remoteBrowserStatusDetail.isEmpty ? localized("Browse the active remote session on demand. Supported text files open into the editor and save explicitly back to the remote path.") : remoteSessionStore.remoteBrowserStatusDetail)
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            if showsRemoteBrowserRecoveryActions {
                HStack(spacing: UI.space10) {
                    Button(localized("Retry Load")) {
                        retryRemoteBrowserLoad()
                    }
                    .buttonStyle(.bordered)

                    Button(localized("Detach Broker")) {
                        detachRemoteBroker()
                    }
                    .buttonStyle(.bordered)

                    Button(localized("Reattach…")) {
                        recoverRemoteBrokerAttachment()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(localized("Restart the remote session on the Mac first if it is no longer active, then attach again with a fresh code."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            } else if showsRemoteBrowserRetryAction {
                Button(localized("Retry Load")) {
                    retryRemoteBrowserLoad()
                }
                .buttonStyle(.bordered)
            }

            if remoteSessionStore.isRemoteBrowserLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if remoteSessionStore.remoteBrowserEntries.isEmpty, !remoteSessionStore.remoteBrowserStatusDetail.isEmpty, !remoteSessionStore.isRemoteBrowserLoading {
                Text(localized("No remote entries loaded yet."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: UI.space8) {
                    ForEach(remoteSessionStore.remoteBrowserEntries) { entry in
                        Button {
                            if entry.isDirectory {
                                loadRemoteBrowserPath(entry.path)
                            } else if entry.isSupportedTextFile {
                                openRemoteFile(entry)
                            } else {
                                remotePreparationStatus = String(format: localized("%@ is not a supported text file for remote editing."), entry.name)
                            }
                        } label: {
                            HStack(spacing: UI.space8) {
                                Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .foregroundStyle(.primary)
                                    Text(entry.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if entry.isDirectory {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else if !entry.isSupportedTextFile {
                                    Text(localized("Unsupported"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color.secondary.opacity(0.12))
                                        )
                                } else {
                                    Text(localized("Open Remote"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(UI.space10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(inputFieldBackground.opacity(0.85))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(remoteSessionStore.isRemoteBrowserLoading || (!entry.isDirectory && !entry.isSupportedTextFile))
                        .accessibilityLabel(
                            entry.isDirectory
                                ? String(format: localized("Open remote folder %@"), entry.name)
                                : (entry.isSupportedTextFile ? String(format: localized("Remote file %@"), entry.name) : String(format: localized("Unsupported remote file %@"), entry.name))
                        )
                        .accessibilityHint(
                            entry.isDirectory
                                ? localized("Loads the selected remote folder")
                                : (entry.isSupportedTextFile
                                    ? localized("Opens the selected remote file in the editor for explicit remote save")
                                    : localized("This remote file type is not supported for remote editing"))
                        )
                    }
                }
            }
        }
        .onAppear {
            syncRemoteBrowserPathDraft()
        }
    }

    private var remoteConnectSheet: some View {
        VStack(alignment: .leading, spacing: UI.space16) {
            Text(localized("Remote Connect"))
                .font(.title3.weight(.semibold))

            Text(localized("Connect stores and selects a remote target. On macOS, the Mac is the SSH owner: selecting an SSH key enables the Mac to perform the explicit SSH login only when you start a session. The target must be a real SSH server. Once connected, the Mac can publish an attach code so iPhone and iPad can browse, open, edit, and explicitly save supported text files through that brokered session."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: UI.space12) {
                TextField(localized("Nickname"), text: $remoteConnectNickname)
                    .textFieldStyle(.roundedBorder)
                TextField(localized("Host"), text: $remoteHost)
                    .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
#endif
                TextField(localized("User"), text: $remoteUsername)
                    .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
#endif
                TextField(localized("Port"), text: $remotePortDraft)
                    .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                    .keyboardType(.numberPad)
#endif
                    .onSubmit {
                        applyRemotePortDraft()
                    }

                Text(localized("Port range: 1-65535. Port 22 is the standard SSH port."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

#if os(macOS)
                VStack(alignment: .leading, spacing: UI.space8) {
                    HStack(spacing: UI.space12) {
                        Button(remoteSSHKeyBookmarkData == nil ? localized("Choose SSH Key…") : localized("Change SSH Key…")) {
                            chooseRemoteSSHKey()
                        }
                        .buttonStyle(.bordered)

                        if remoteSSHKeyBookmarkData != nil {
                            Button(localized("Clear Key")) {
                                clearRemoteSSHKeySelection()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text(remoteSSHKeyDisplayName.isEmpty ? localized("No SSH key selected. Without a key, Start Session falls back to a TCP connection test from the Mac to the target host.") : "\(localized("Selected key:")) \(remoteSSHKeyDisplayName)")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
#else
                Text(localized("SSH-key login is currently available on macOS only. iPhone and iPad attach to the active Mac broker instead of handling SSH keys or direct SSH connections."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
#endif
            }

            HStack(spacing: UI.space12) {
                Spacer()

                Button(localized("Cancel")) {
                    showRemoteConnectSheet = false
                }
                .buttonStyle(.bordered)

                Button(localized("Connect Locally")) {
                    connectRemotePreview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmitRemoteConnectDraft)
            }
        }
        .padding(UI.space20)
        .frame(minWidth: 320, idealWidth: 420)
        .onAppear {
            syncRemotePortDraftFromStoredValue()
#if os(macOS)
            syncRemoteSSHKeyDraftFromActiveTarget()
#endif
        }
    }

    private var remoteAttachSheet: some View {
        VStack(alignment: .leading, spacing: UI.space16) {
            Text(localized("Attach to Broker"))
                .font(.title3.weight(.semibold))

            Text(localized("Paste the attach code from the active macOS broker session. This device does not use its own SSH key. After attaching, it browses, opens, edits, and explicitly saves supported text files through the Mac-hosted broker."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            TextField(localized("Attach Code"), text: $remoteAttachCodeDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
#endif
                .lineLimit(4...8)

            HStack(spacing: UI.space12) {
                Spacer()

                Button(localized("Cancel")) {
                    showRemoteAttachSheet = false
                }
                .buttonStyle(.bordered)

                Button(localized("Attach")) {
                    attachToRemoteBroker()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!remoteSessionsEnabled || remoteAttachCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(UI.space20)
        .frame(minWidth: 320, idealWidth: 420)
    }

    // MARK: - Remote Settings UI

    private var remoteSection: some View {
        VStack(spacing: UI.space20) {
#if os(iOS) || os(visionOS)
            settingsCardSection(
                title: "Remote Sessions",
                icon: "rectangle.connected.to.line.below"
            ) {
                iOSToggleRow("Enable Preview", isOn: $remoteSessionsEnabled)

                Text("Remote support is opt-in. When disabled, Neon Vision Editor performs no remote handshake, no background polling, and no startup initialization for remote workflows.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                remoteSessionActionButtons

                Text(remoteStatusSummary)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                remoteHelpSection

                if canShowRemoteBrowser {
                    VStack(alignment: .leading, spacing: UI.space12) {
                        Label("Remote Browser", systemImage: "folder")
                            .font(.headline)
                        remoteBrowserSection
                    }
                    .padding(UI.space12)
                    .background(settingsCardBackground(cornerRadius: 14))
                }

                if remoteSessionStore.brokerSessionDescriptor != nil {
                    remoteBrokerDescriptorCard
                }

                if !remoteSessionStore.savedTargets.isEmpty {
                    remoteSavedTargetsList
                }

                if !remotePreparationStatus.isEmpty {
                    Text(remotePreparationStatus)
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            }

#else
            GroupBox("Remote Sessions") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Toggle("Enable Remote Preview", isOn: $remoteSessionsEnabled)

                    Text("Remote support is opt-in. When disabled, Neon Vision Editor performs no remote handshake, no background polling, and no startup initialization for remote workflows.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)

                    remoteSessionActionButtons

                Text(remoteStatusSummary)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                    remoteHelpSection

                    if canShowRemoteBrowser {
                        GroupBox("Remote Browser") {
                            remoteBrowserSection
                                .padding(UI.groupPadding)
                        }
                    }

                    if remoteSessionStore.brokerSessionDescriptor != nil {
                        remoteBrokerDescriptorCard
                    }

                    if !remoteSessionStore.savedTargets.isEmpty {
                        remoteSavedTargetsList
                    }

                    if !remotePreparationStatus.isEmpty {
                        Text(remotePreparationStatus)
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(UI.groupPadding)
            }
#endif
        }
        .onChange(of: remoteSessionsEnabled) { _, isEnabled in
            if !isEnabled {
                remoteSessionStore.disconnectPreview()
                remotePreparationStatus = ""
            }
        }
        .onChange(of: remotePort) { _, newValue in
            remotePortDraft = String(newValue)
        }
        .onChange(of: remoteSessionStore.remoteBrowserPath) { _, newValue in
            remoteBrowserPathDraft = newValue
        }
    }

    // MARK: - AI and Support UI

    private var aiSection: some View {
        VStack(spacing: UI.space20) {
#if os(iOS) || os(visionOS)
            settingsCardSection(
                title: "AI Model",
                icon: "brain.head.profile"
            ) {
                Picker("Model", selection: selectedAIModelBinding) {
                    Text("Apple Intelligence").tag(AIModel.appleIntelligence)
                    Text("Grok").tag(AIModel.grok)
                    Text("OpenAI").tag(AIModel.openAI)
                    Text("Gemini").tag(AIModel.gemini)
                    Text("Anthropic").tag(AIModel.anthropic)
                    Text("OpenCode Go").tag(AIModel.openCodeGo)
                    Text("Custom (OpenAI-compatible)").tag(AIModel.customProvider)
                }
                .neonSettingsDropdown(maxWidth: .infinity)
                .accessibilityLabel("Model")

                Text("The selected AI model is used for AI-assisted code completion.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                Button("Data Disclosure") {
                    showDataDisclosureDialog = true
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsCardSection(
                title: "AI Provider API Keys",
                icon: "key.fill",
                emphasis: .secondary,
                tip: "Keys are stored in the system Keychain."
            ) {
                VStack(alignment: .center, spacing: UI.space12) {
                    aiKeyRow(title: "Grok", placeholder: "sk-…", value: $grokAPIToken, provider: .grok)
                    aiKeyRow(title: "OpenAI", placeholder: "sk-…", value: $openAIAPIToken, provider: .openAI)
                    aiKeyRow(title: "Gemini", placeholder: "AIza…", value: $geminiAPIToken, provider: .gemini)
                    aiKeyRow(title: "Anthropic", placeholder: "sk-ant-…", value: $anthropicAPIToken, provider: .anthropic)
                    aiKeyRow(title: "OpenCode Go", placeholder: "sk-…", value: $openCodeGoAPIToken, provider: .openCodeGo)
                    aiTextRow(title: "OpenCode Model", placeholder: OpenCodeGoConfig.defaultModel, value: $openCodeGoModelID)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsCardSection(
                title: "Custom Provider",
                icon: "network",
                emphasis: .secondary,
                tip: "Any OpenAI-compatible endpoint (v1 chat completions). The key is optional and stored in the system Keychain."
            ) {
                VStack(alignment: .center, spacing: UI.space12) {
                    aiTextRow(title: "Base URL", placeholder: "https://host/v1", value: $customProviderBaseURL)
                    aiTextRow(title: "Model", placeholder: "model-id", value: $customProviderModel)
                    aiKeyRow(title: "API Key", placeholder: "optional", value: $customProviderAPIToken, provider: .customProvider)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
#else
            GroupBox("AI Model") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Picker("Model", selection: selectedAIModelBinding) {
                        Text("Apple Intelligence").tag(AIModel.appleIntelligence)
                        Text("Grok").tag(AIModel.grok)
                        Text("OpenAI").tag(AIModel.openAI)
                        Text("Gemini").tag(AIModel.gemini)
                        Text("Anthropic").tag(AIModel.anthropic)
                        Text("OpenCode Go").tag(AIModel.openCodeGo)
                        Text("Custom (OpenAI-compatible)").tag(AIModel.customProvider)
                    }
                    .neonSettingsDropdown(maxWidth: 260)
                    .accessibilityLabel("Model")

                    Text("The selected AI model is used for AI-assisted code completion.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)

                    Button("Data Disclosure") {
                        showDataDisclosureDialog = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(UI.groupPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox("AI Provider API Keys") {
                VStack(alignment: .center, spacing: UI.space12) {
                    aiKeyRow(title: "Grok", placeholder: "sk-…", value: $grokAPIToken, provider: .grok)
                    aiKeyRow(title: "OpenAI", placeholder: "sk-…", value: $openAIAPIToken, provider: .openAI)
                    aiKeyRow(title: "Gemini", placeholder: "AIza…", value: $geminiAPIToken, provider: .gemini)
                    aiKeyRow(title: "Anthropic", placeholder: "sk-ant-…", value: $anthropicAPIToken, provider: .anthropic)
                    aiKeyRow(title: "OpenCode Go", placeholder: "sk-…", value: $openCodeGoAPIToken, provider: .openCodeGo)
                    aiTextRow(title: "OpenCode Model", placeholder: OpenCodeGoConfig.defaultModel, value: $openCodeGoModelID)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(UI.groupPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox("Custom Provider") {
                VStack(alignment: .center, spacing: UI.space12) {
                    Text("Any OpenAI-compatible endpoint (v1 chat completions). The key is optional and stored in the system Keychain.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    aiTextRow(title: "Base URL", placeholder: "https://host/v1", value: $customProviderBaseURL)
                    aiTextRow(title: "Model", placeholder: "model-id", value: $customProviderModel)
                    aiKeyRow(title: "API Key", placeholder: "optional", value: $customProviderAPIToken, provider: .customProvider)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(UI.groupPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
#endif
        }
    }

    private var supportSection: some View {
#if os(iOS) || os(visionOS)
        settingsCardSection(
            title: "Support Development",
            icon: "heart.circle.fill",
            emphasis: .secondary,
            tip: "Support is optional. All editor features remain available without a purchase."
        ) {
            supportSectionContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
#else
        VStack(spacing: UI.space16) {
            GroupBox(localized("Support Development")) {
                supportSectionContent
                    .padding(UI.groupPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
#endif
    }

    private var supportSectionContent: some View {
        VStack(alignment: .leading, spacing: UI.space12) {
            Text(localized("In-App Purchase is optional and only used to support the app."))
                .foregroundStyle(.secondary)
            Text(localized("Consumable support purchase. Can be purchased multiple times. No subscription and no auto-renewal."))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            if shouldShowSupportPurchaseControls {
                VStack(alignment: .leading, spacing: UI.space8) {
                Text(localized("App Store Price"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: UI.space8) {
                    Text(supportPriceStateLabel)
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(supportPriceDisplayLabel)
                        .font(Typography.sectionTitle)
                        .monospacedDigit()
                        .accessibilityLabel(localized("App Store Price"))
                        .accessibilityValue(supportPriceDisplayLabel)
                }
                if supportPurchaseManager.supportProduct == nil
                    && supportPurchaseManager.hasCheckedStoreAvailability
                    && !supportPurchaseManager.isLoadingProducts {
                    Text(localized("Tap Retry App Store to load the App Store price."))
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                if let lastRefresh = supportPurchaseManager.lastSuccessfulPriceRefreshAt {
                    Text(
                        localized(
                            "Last updated: %@",
                            lastRefresh.formatted(date: .abbreviated, time: .shortened)
                        )
                    )
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(localized("Last updated"))
                    .accessibilityValue(lastRefresh.formatted(date: .abbreviated, time: .shortened))
                }
                }
                .padding(UI.space12)
                .background(
                    RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous)
                        .stroke(Color.primary.opacity(UI.cardStrokeOpacity), lineWidth: 1)
                )

                supportActionGrid

                if supportPurchaseManager.shouldShowStoreUnavailableMessage {
                    Text(localized("Direct notarized builds are unaffected: all editor features stay fully available without any purchase."))
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(localized("Direct notarized builds are unaffected: all editor features stay fully available without any purchase."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                patreonSupportButton
            }

            supportLinksGrid
        }
    }

    private var supportActionGrid: some View {
        SettingsFlowLayout(spacing: UI.space10, rowSpacing: UI.space8) {
            Button(supportPurchaseManager.isPurchasing ? localized("Purchasing…") : supportPurchaseManager.supportPurchaseButtonTitle) {
                guard supportPurchaseManager.canUseInAppPurchases else {
                    Task { await supportPurchaseManager.purchaseSupport() }
                    return
                }
                guard supportPurchaseManager.supportProduct != nil else {
                    Task { await supportPurchaseManager.refreshPrice() }
                    supportPurchaseManager.statusMessage = localized("Loading App Store product. Please try again in a moment.")
                    return
                }
                showSupportPurchaseDialog = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                supportPurchaseManager.isPurchasing
            )

            Button {
                Task { await supportPurchaseManager.refreshPrice() }
            } label: {
                if supportPurchaseManager.isLoadingProducts {
                    HStack(spacing: UI.space8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localized("Retry App Store"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                } else {
                    HStack(spacing: UI.space6) {
                        Image(systemName: "arrow.clockwise")
                        Text(localized("Retry App Store"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(supportPurchaseManager.isLoadingProducts)

            if let externalURL = SupportPurchaseManager.externalSupportURL {
                patreonSupportButton(for: externalURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var patreonSupportButton: some View {
        if let externalURL = SupportPurchaseManager.externalSupportURL {
            patreonSupportButton(for: externalURL)
        }
    }

    private func patreonSupportButton(for externalURL: URL) -> some View {
        Button {
            openURL(externalURL)
        } label: {
            Label(localized("Support via Patreon"), systemImage: "safari")
        }
        .buttonStyle(.borderedProminent)
    }

    private var supportLinksGrid: some View {
        SettingsFlowLayout(spacing: UI.space16, rowSpacing: UI.space8) {
            if let githubProjectURL {
                Link(destination: githubProjectURL) {
                    Label(localized("GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.footnote.weight(.semibold))
                }
            }

            if let githubFeatureRequestURL {
                Link(destination: githubFeatureRequestURL) {
                    Label(localized("Feature Request"), systemImage: "lightbulb")
                        .font(.footnote.weight(.semibold))
                }
            }

            if let privacyPolicyURL {
                Link(destination: privacyPolicyURL) {
                    Label(localized("Privacy Policy"), systemImage: "hand.raised")
                        .font(.footnote.weight(.semibold))
                }
            }

            if let termsOfUseURL {
                Link(destination: termsOfUseURL) {
                    Label(localized("Terms of Use"), systemImage: "doc.text")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

#if os(macOS)
    // MARK: - Command Line Helper

    private var commandLineHelperSection: some View {
        GroupBox(localized("Command Line Helper")) {
            VStack(alignment: .leading, spacing: UI.space12) {
                Text(localized("The bundled nve helper opens files and folders from Terminal through macOS Launch Services. It is optional and user-installed: Neon Vision Editor never creates shell links automatically."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(commandLineHelperInstallCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(UI.space10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .accessibilityLabel(localized("Command line helper install command"))
                    .accessibilityValue(commandLineHelperInstallCommand)

                HStack(spacing: UI.space12) {
                    Button {
                        copyCommandLineHelperInstallCommand()
                    } label: {
                        Label(localized("Copy Install Command"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    if !commandLineHelperCopyStatus.isEmpty {
                        Text(commandLineHelperCopyStatus)
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(localized("After linking, add $HOME/bin to PATH if your shell does not already include it, then use nve README.md or nve --new-window path/to/file. The helper does not run background services, collect telemetry, or request Full Disk Access, Accessibility, or administrator privileges."))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(UI.groupPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commandLineHelperInstallCommand: String {
        let helperPath = Bundle.main.url(forResource: "nve", withExtension: nil)?.path
            ?? "\(Bundle.main.bundlePath)/Contents/Resources/nve"
        return """
        mkdir -p "$HOME/bin"
        ln -sf \(shellQuoted(helperPath)) "$HOME/bin/nve"
        """
    }

    private func copyCommandLineHelperInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandLineHelperInstallCommand, forType: .string)
        commandLineHelperCopyStatus = localized("Copied.")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
#endif

    // MARK: - Diagnostics and Updates

    private var diagnosticsSection: some View {
        let events = EditorPerformanceMonitor.shared.recentFileOpenEvents(limit: 8).reversed()
        return VStack(spacing: UI.space16) {
#if os(iOS) || os(visionOS)
            settingsCardSection(
                title: "Diagnostics",
                icon: "stethoscope",
                emphasis: .secondary,
                tip: "Safe local diagnostics for update and file-open troubleshooting."
            ) {
                diagnosticsSectionContent(events: Array(events))
            }
#else
            GroupBox("Diagnostics") {
                diagnosticsSectionContent(events: Array(events))
                    .padding(UI.groupPadding)
            }
#endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticsSectionContent(events: [EditorPerformanceMonitor.FileOpenEvent]) -> some View {
        let reliability = RuntimeReliabilityMonitor.shared.diagnosticSnapshot()
        let minimapLatency = EditorPerformanceMonitor.shared.lastMinimapViewportLatencyMilliseconds
        return VStack(alignment: .leading, spacing: UI.space10) {
            Text("App")
                .font(.subheadline.weight(.semibold))
            Text(localized("Version: %@ (%@)", reliability.appVersion, reliability.buildNumber))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            Text(localized("Last launch phase: %@", reliability.lastLaunchPhase))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            Text(localized("Safe mode: %lld failed launches, next launch requested: %@", Int64(reliability.consecutiveFailedLaunches), reliability.safeModeRequestedForNextLaunch ? "yes" : "no"))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            Text(localized("Markdown preview: %@ / %@", markdownPreviewTemplateRaw, markdownPreviewBackgroundStyleRaw))
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            Text("Minimap viewport: \(minimapLatency.map { "\($0) ms" } ?? "not measured")")
                .font(Typography.footnote)
                .foregroundStyle(.secondary)

            Divider()

            if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                Text("Updater")
                    .font(.subheadline.weight(.semibold))
                Text(localized("Last check result: %@", appUpdateManager.lastCheckResultSummary))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                if let checkedAt = appUpdateManager.lastCheckedAt {
                    Text(localized("Last checked: %@", checkedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                if let pausedUntil = appUpdateManager.pausedUntil, pausedUntil > Date() {
                    Text(localized("Auto-check pause active until %@ (%lld consecutive failures).", pausedUntil.formatted(date: .abbreviated, time: .shortened), appUpdateManager.consecutiveFailureCount))
                        .font(Typography.footnote)
                        .foregroundStyle(.orange)
                }
                Text(localized("Staged update: %@", appUpdateManager.stagedUpdateVersionSummary))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                Text(localized("Last install attempt: %@", appUpdateManager.lastInstallAttemptSummary))
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)

                Text("Recent updater log")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    Text(appUpdateManager.recentLogSnippet)
                        .font(Typography.monoBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)

                Divider()
            }

            Text("File Open Timing")
                .font(.subheadline.weight(.semibold))
            if events.isEmpty {
                Text("No recent file-open snapshots yet.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                        HStack(spacing: 8) {
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("\(event.elapsedMilliseconds) ms")
                                .font(.caption.monospacedDigit())
                            Text(event.success ? "ok" : "fail")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(event.success ? .green : .red)
                            if let bytes = event.byteCount {
                                Text("\(bytes) bytes")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack(spacing: UI.space10) {
                Button("Copy Diagnostics") {
                    copyDiagnosticsToClipboard()
                }
                .buttonStyle(.borderedProminent)
                Button("Clear Diagnostics") {
                    appUpdateManager.resetDiagnostics()
                    EditorPerformanceMonitor.shared.clearRecentFileOpenEvents()
                    diagnosticsCopyStatus = "Cleared"
                }
                if !diagnosticsCopyStatus.isEmpty {
                    Text(diagnosticsCopyStatus)
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var diagnosticsExportText: String {
        let events = EditorPerformanceMonitor.shared.recentFileOpenEvents(limit: 12)
        let reliability = RuntimeReliabilityMonitor.shared.diagnosticSnapshot()
        let minimapLatency = EditorPerformanceMonitor.shared.lastMinimapViewportLatencyMilliseconds
        var lines: [String] = []
        lines.append("Neon Vision Editor Diagnostics")
        lines.append("Timestamp: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("App.version: \(reliability.appVersion)")
        lines.append("App.build: \(reliability.buildNumber)")
        lines.append("Editor.lineWrap: \(lineWrapEnabled)")
        lines.append("Editor.lineNumbers: \(showLineNumbers)")
        lines.append("Editor.fontSize: \(Int(editorFontSize.rounded()))")
        lines.append("Editor.performancePreset: \(performancePresetRaw)")
        lines.append("Editor.largeFileSyntax: \(largeFileSyntaxHighlightingRaw)")
        lines.append("Editor.largeFileOpenMode: \(largeFileOpenModeRaw)")
        lines.append("Editor.minimapViewportLatencyMs: \(minimapLatency.map { String($0) } ?? "not measured")")
        lines.append("Window.translucency: \(translucentWindow)")
        lines.append("Reliability.lastLaunchPhase: \(reliability.lastLaunchPhase)")
        lines.append("Reliability.consecutiveFailedLaunches: \(reliability.consecutiveFailedLaunches)")
        lines.append("Reliability.safeModeRequestedForNextLaunch: \(reliability.safeModeRequestedForNextLaunch)")
        lines.append("MarkdownPreview.template: \(markdownPreviewTemplateRaw)")
        lines.append("MarkdownPreview.background: \(markdownPreviewBackgroundStyleRaw)")
        if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
            lines.append("Updater.lastCheckResult: \(AppUpdateManager.sanitizedDiagnosticSummary(appUpdateManager.lastCheckResultSummary))")
            lines.append("Updater.lastCheckedAt: \(appUpdateManager.lastCheckedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never")")
            lines.append("Updater.stagedVersion: \(appUpdateManager.stagedUpdateVersionSummary)")
            lines.append("Updater.lastInstallAttempt: \(AppUpdateManager.sanitizedDiagnosticSummary(appUpdateManager.lastInstallAttemptSummary))")
            if let pausedUntil = appUpdateManager.pausedUntil, pausedUntil > Date() {
                lines.append("Updater.pauseUntil: \(pausedUntil.formatted(date: .abbreviated, time: .shortened))")
            }
            lines.append("Updater.consecutiveFailures: \(appUpdateManager.consecutiveFailureCount)")
            lines.append("Updater.logSnippet:")
            lines.append(appUpdateManager.recentLogSnippet)
        }
        lines.append("FileOpenEvents.count: \(events.count)")
        for event in events {
            lines.append(
                "- \(event.timestamp.formatted(date: .omitted, time: .shortened)) | \(event.elapsedMilliseconds) ms | \(event.success ? "ok" : "fail") | bytes=\(event.byteCount.map(String.init) ?? "n/a")"
            )
        }
        return lines.joined(separator: "\n")
    }

    private func copyDiagnosticsToClipboard() {
        let text = diagnosticsExportText
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
        diagnosticsCopyStatus = "Copied"
    }

#if os(macOS)
    private var updatesTab: some View {
        settingsContainer(maxWidth: 620) {
            settingsSectionHeader(
                icon: "arrow.triangle.2.circlepath.circle",
                title: "Updates",
                subtitle: "Update checks, intervals, and automatic installation behavior."
            )
            GroupBox("GitHub Release Updates") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Check Interval")
                            .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                        Picker("", selection: $updateCheckIntervalRaw) {
                            ForEach(AppUpdateCheckInterval.allCases) { interval in
                                Text(interval.title).tag(interval.rawValue)
                            }
                        }
                        .neonSettingsDropdown(maxWidth: isCompactSettingsLayout ? .infinity : 220)
                        .accessibilityLabel("Check Interval")
                    }
                    .disabled(!autoCheckForUpdates)

                    Toggle("Automatically install updates when available", isOn: $autoDownloadUpdates)
                        .disabled(!autoCheckForUpdates)

                    HStack(spacing: UI.space8) {
                        Button("Check Now") {
                            Task { await appUpdateManager.checkForUpdates(source: .manual) }
                        }
                        .buttonStyle(.borderedProminent)

                        if let checkedAt = appUpdateManager.lastCheckedAt {
                            Text(localized("Last checked: %@", checkedAt.formatted(date: .abbreviated, time: .shortened)))
                                .font(Typography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: UI.space6) {
                        Text(localized("Last check result: %@", appUpdateManager.lastCheckResultSummary))
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                        if let pausedUntil = appUpdateManager.pausedUntil, pausedUntil > Date() {
                            Text(localized("Auto-check pause active until %@ (%lld consecutive failures).", pausedUntil.formatted(date: .abbreviated, time: .shortened), appUpdateManager.consecutiveFailureCount))
                                .font(Typography.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    if appUpdateManager.isUserVisibleUpdateInProgress {
                        VStack(alignment: .leading, spacing: UI.space8) {
                            Text("Update Activity")
                                .font(.subheadline.weight(.semibold))
                            if appUpdateManager.isInstalling {
                                ProgressView(value: appUpdateManager.installProgress, total: 1.0) {
                                    Text(appUpdateManager.userVisibleUpdateStatusTitle)
                                        .font(Typography.footnote)
                                }
                                Text("\(Int((appUpdateManager.installProgress * 100).rounded()))%")
                                    .font(Typography.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView {
                                    Text(appUpdateManager.userVisibleUpdateStatusTitle)
                                        .font(Typography.footnote)
                                }
                            }
                            if let detail = appUpdateManager.userVisibleUpdateStatusDetail,
                               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(detail)
                                    .font(Typography.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(UI.space12)
                        .background(
                            RoundedRectangle(cornerRadius: UI.cardCorner, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Update activity")
                        .accessibilityValue(
                            appUpdateManager.isInstalling
                                ? "\(Int((appUpdateManager.installProgress * 100).rounded())) percent"
                                : appUpdateManager.userVisibleUpdateStatusTitle
                        )
                    }

                    Text("Uses GitHub release assets only. App Store Connect releases are not used by this updater.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(UI.groupPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shortcutsTab: some View {
        settingsContainer(maxWidth: 620) {
            settingsSectionHeader(
                icon: "command",
                title: "Keyboard Shortcuts",
                subtitle: "Customize key bindings for editor actions."
            )
#if os(macOS)
            GroupBox("Keyboard Shortcuts") {
                shortcutSettingsContent
                    .padding(UI.groupPadding)
            }
#else
            shortcutSettingsContent
                .padding(UI.space12)
                .background(settingsCardBackground(cornerRadius: UI.cardCorner))
#endif
        }
    }
#endif

    // MARK: - Shared Dialogs and Layout Helpers

    private var dataDisclosureDialog: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: UI.space16) {
                    Text("Data Disclosure")
                        .font(.title3.weight(.semibold))

                    Text("The application does not collect analytics data, usage telemetry, advertising identifiers, device fingerprints, or background behavioral metrics. No automatic data transmission to developer-controlled servers occurs.")
                    Text("AI-assisted code completion is an optional feature. External network communication only occurs when a user explicitly enables AI completion and selects an external AI provider within the application settings.")
                    Text("When AI completion is triggered, the application transmits only the minimal contextual text necessary to generate a completion suggestion. This typically includes the code immediately surrounding the cursor position or the active selection.")
                    Text("The application does not automatically transmit full project folders, unrelated files, entire file system contents, contact data, location data, or device-specific identifiers.")
                    Text("Authentication credentials (API keys) for external AI providers are stored securely in the system keychain and are transmitted only to the user-selected provider for the purpose of completing the AI request.")
                    Text("All external communication is performed over encrypted HTTPS connections. If AI completion is disabled, the application performs no external AI-related network requests.")

                    HStack {
                        Spacer()
                        Button("Close") {
                            showDataDisclosureDialog = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, UI.space8)
                }
                .font(Typography.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(UI.space20)
            }
            .navigationTitle("AI Data Disclosure")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func settingsSectionHeader(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
#if os(iOS) || os(visionOS)
        Group {
            if isIPadRegularSettingsLayout {
                HStack(alignment: .top, spacing: UI.space12) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: UI.space6) {
                        Text(title)
                            .font(Typography.sectionTitle)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, UI.space6)
                .padding(.bottom, UI.space6)
            } else {
                HStack(alignment: .top, spacing: UI.space12) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36, alignment: .center)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: UI.space6) {
                        Text(title)
                            .font(Typography.sectionTitle)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, UI.mobileHeaderTopPadding)
                .padding(.bottom, UI.space6)
            }
        }
#else
        HStack(alignment: .top, spacing: UI.space12) {
            ZStack {
                RoundedRectangle(cornerRadius: UI.macHeaderBadgeCorner, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: UI.macHeaderBadgeCorner, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: UI.macHeaderIconSize, height: UI.macHeaderIconSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: UI.space6) {
                Text(title)
                    .font(Typography.sectionTitle)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
        .padding(.bottom, UI.space6)
#endif
    }

    private func settingsContainer<Content: View>(maxWidth: CGFloat = 560, @ViewBuilder _ content: () -> Content) -> some View {
        let effectiveMaxWidth = settingsEffectiveMaxWidth(base: maxWidth)
        return ScrollView {
            VStack(alignment: settingsShouldUseLeadingAlignment ? .leading : .center, spacing: settingsVerticalSpacing) {
                content()
            }
            .frame(maxWidth: effectiveMaxWidth, alignment: settingsShouldUseLeadingAlignment ? .leading : .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settingsShouldUseLeadingAlignment ? .topLeading : .top)
            .padding(.top, settingsTopPadding)
            .padding(.bottom, settingsBottomPadding)
            .padding(.horizontal, settingsHorizontalPadding)
#if os(iOS) || os(visionOS)
            .animation(.easeOut(duration: 0.22), value: settingsActiveTab)
#endif
        }
        .scrollClipDisabled(false)
        .scrollIndicators(.automatic)
        .contentMargins(.top, settingsScrollContentTopMargin, for: .scrollContent)
        .background(settingsContainerBackground)
#if os(visionOS)
        .overlay(alignment: .topTrailing) {
            settingsCloseButton
                .padding(.top, UI.space12)
                .padding(.trailing, UI.space12)
        }
#endif
    }

    private var settingsScrollContentTopMargin: CGFloat {
#if os(macOS)
        // Settings uses a transparent full-size titlebar; reserve the native toolbar strip
        // so scrolled rows do not render under the preference icons.
        UI.macSettingsToolbarContentMargin
#else
        isIPadRegularSettingsLayout ? UI.space6 : 0
#endif
    }

#if os(visionOS)
    private var settingsCloseButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Close Settings")
    }
#endif

    private var settingsVerticalSpacing: CGFloat {
#if os(iOS) || os(visionOS)
        #if os(visionOS)
        return isIPadRegularSettingsLayout ? UI.space8 : UI.space16
        #else
        isIPadRegularSettingsLayout ? UI.space12 : UI.space20
        #endif
#else
        UI.space20
#endif
    }

    private var settingsTopPadding: CGFloat {
#if os(iOS) || os(visionOS)
        isIPadRegularSettingsLayout ? UI.space6 : UI.topPadding
#else
        UI.topPadding
#endif
    }

    private var settingsBottomPadding: CGFloat {
#if os(iOS) || os(visionOS)
        isIPadRegularSettingsLayout ? UI.space12 : UI.bottomPadding
#else
        UI.bottomPadding
#endif
    }

    private var settingsHorizontalPadding: CGFloat {
#if os(iOS) || os(visionOS)
        if isCompactSettingsLayout { return UI.sidePaddingCompact }
        #if os(visionOS)
        if useTwoColumnSettingsLayout { return UI.space20 }
        #endif
        if useTwoColumnSettingsLayout { return UI.sidePaddingIPadRegular }
        return UI.sidePaddingRegular
#else
        return isCompactSettingsLayout ? UI.sidePaddingCompact : 4
#endif
    }

    @ViewBuilder
    private var settingsContainerBackground: some View {
#if os(macOS)
        Color.clear
#elseif os(visionOS)
        Color.clear
#else
        Color.clear.background(.ultraThinMaterial)
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var settingsWindowBackground: some View {
        if supportsTranslucency && translucentWindow {
            Color.clear.background(.ultraThinMaterial)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
#endif

    private func settingsEffectiveMaxWidth(base: CGFloat) -> CGFloat {
#if os(iOS) || os(visionOS)
        #if os(visionOS)
        if useTwoColumnSettingsLayout { return max(base, 880) }
        #endif
        if useTwoColumnSettingsLayout { return max(base, 1120) }
        return base
#else
        return min(max(base, macSettingsContentMaxWidth), macSettingsThemeContentMaxWidth)
#endif
    }

    private func settingsCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(settingsCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(UI.cardStrokeOpacity), lineWidth: 1)
            )
    }

    private var settingsCardFill: some ShapeStyle {
#if os(macOS)
        effectiveSettingsColorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
#elseif os(visionOS)
        effectiveSettingsColorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.16)
#else
        .regularMaterial
#endif
    }

    private var effectiveSettingsColorScheme: ColorScheme {
        preferredColorSchemeOverride ?? systemColorScheme
    }

    // MARK: - Theme and Form Helpers

    private func colorRow(
        title: String,
        color: Binding<Color>,
        effectiveColor: Color? = nil,
        onReset: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
            if let effectiveColor {
                Circle()
                    .fill(effectiveColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            }
            ColorPicker("", selection: color, supportsOpacity: true)
                .labelsHidden()
            if let onReset {
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
                .accessibilityLabel("Reset \(title) to default")
            }
            Spacer()
        }
    }

    private func defaultHex(for colorKey: String, themeName: String) -> String {
        let palette = themePaletteColors(for: themeName)
        let color: Color
        switch colorKey {
        case "text": color = palette.text
        case "background": color = palette.background
        case "cursor": color = palette.cursor
        case "selection": color = palette.selection
        case "keyword": color = palette.keyword
        case "string": color = palette.string
        case "number": color = palette.number
        case "comment": color = palette.comment
        case "type": color = palette.type
        case "builtin": color = palette.builtin
        default: return "#000000"
        }
        return colorToHex(color)
    }

    private func aiKeyRow(title: String, placeholder: String, value: Binding<String>, provider: APITokenKey) -> some View {
        Group {
            if isCompactSettingsLayout {
                VStack(alignment: .leading, spacing: UI.space8) {
                    Text(title)
                    SecureField(placeholder, text: value)
                        .textFieldStyle(.plain)
                        .padding(.vertical, UI.space6)
                        .padding(.horizontal, UI.space8)
                        .background(inputFieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: UI.fieldCorner)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(UI.fieldCorner)
                        .onChange(of: value.wrappedValue) { _, new in
                            SecureTokenStore.setToken(new, for: provider)
                        }
                }
            } else {
                HStack(spacing: UI.space12) {
                    Text(title)
                        .frame(width: standardLabelWidth, alignment: .leading)
                    SecureField(placeholder, text: value)
                        .textFieldStyle(.plain)
                        .padding(.vertical, UI.space6)
                        .padding(.horizontal, UI.space8)
                        .background(inputFieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: UI.fieldCorner)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(UI.fieldCorner)
                        .frame(maxWidth: 360)
                        .onChange(of: value.wrappedValue) { _, new in
                            SecureTokenStore.setToken(new, for: provider)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isCompactSettingsLayout ? .leading : .center)
    }

    // Plain-text settings row for non-secret provider config (base URL, model).
    // The binding is persisted by its @AppStorage source, so no extra write here.
    private func aiTextRow(title: String, placeholder: String, value: Binding<String>) -> some View {
        Group {
            if isCompactSettingsLayout {
                VStack(alignment: .leading, spacing: UI.space8) {
                    Text(title)
                    TextField(placeholder, text: value)
                        .textFieldStyle(.plain)
                        .padding(.vertical, UI.space6)
                        .padding(.horizontal, UI.space8)
                        .background(inputFieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: UI.fieldCorner)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(UI.fieldCorner)
#if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
#endif
                }
            } else {
                HStack(spacing: UI.space12) {
                    Text(title)
                        .frame(width: standardLabelWidth, alignment: .leading)
                    TextField(placeholder, text: value)
                        .textFieldStyle(.plain)
                        .padding(.vertical, UI.space6)
                        .padding(.horizontal, UI.space8)
                        .background(inputFieldBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: UI.fieldCorner)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(UI.fieldCorner)
                        .frame(maxWidth: 360)
#if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
#endif
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isCompactSettingsLayout ? .leading : .center)
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
        case "tex": return "TeX"
        case "html": return "HTML"
        case "expressionengine": return "ExpressionEngine"
        case "css": return "CSS"
        case "standard": return "Standard"
        default: return lang.capitalized
        }
    }

    // MARK: - Platform Layout

    private var settingsShouldUseLeadingAlignment: Bool {
#if os(iOS) || os(visionOS)
        true
#else
        false
#endif
    }

#if os(macOS)
    private var macSettingsContentMaxWidth: CGFloat {
        760
    }

    private var macSettingsThemeContentMaxWidth: CGFloat {
        880
    }

    private var macSettingsWindowSize: (min: NSSize, ideal: NSSize) {
        // Keep a stable window envelope across tabs to avoid toolbar-tab jump/overflow relayout.
        Self.macSettingsWindowSizePolicy()
    }

    nonisolated static func macSettingsWindowSizePolicy() -> (min: NSSize, ideal: NSSize) {
        (NSSize(width: 620, height: 320), NSSize(width: 920, height: 1040))
    }
#endif

    // MARK: - Template Defaults

    private func migrateLegacyPinkSettingsIfNeeded() {
        if themeStringHex.uppercased() == "#FF7AD9" {
            themeStringHex = "#4EA4FF"
        }
    }

    private func templateOverrideKey(for language: String) -> String {
        "TemplateOverride_\(language)"
    }

    private func templateBinding(for language: String) -> Binding<String> {
        Binding<String>(
            get: { UserDefaults.standard.string(forKey: templateOverrideKey(for: language)) ?? defaultTemplate(for: language) ?? "" },
            set: { newValue in UserDefaults.standard.set(newValue, forKey: templateOverrideKey(for: language)) }
        )
    }

    private func defaultTemplate(for language: String) -> String? {
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
            return "fn main() {\n    println!(\"Hello\");\n}\n"
        case "c":
            return "#include <stdio.h>\n\nint main(void) {\n    printf(\"Hello\\n\");\n    return 0;\n}\n"
        case "cpp":
            return "#include <iostream>\n\nint main() {\n    std::cout << \"Hello\" << std::endl;\n    return 0;\n}\n"
        case "csharp":
            return "using System;\n\nclass Program {\n    static void Main() {\n        Console.WriteLine(\"Hello\");\n    }\n}\n"
        case "objective-c":
            return "#import <Foundation/Foundation.h>\n\nint main(int argc, const char * argv[]) {\n    @autoreleasepool {\n        NSLog(@\"Hello\");\n    }\n    return 0;\n}\n"
        case "php":
            return "<?php\n\nfunction main() {\n    // TODO: Add code here\n}\n\nmain();\n"
        case "html":
            return "<!doctype html>\n<html>\n<head>\n  <meta charset=\"utf-8\" />\n  <title>Document</title>\n</head>\n<body>\n\n</body>\n</html>\n"
        case "expressionengine":
            return "{exp:channel:entries channel=\"news\" limit=\"10\"}\n  <article>\n    <h2>{title}</h2>\n    <p>{summary}</p>\n  </article>\n{/exp:channel:entries}\n"
        case "css":
            return "body {\n  margin: 0;\n  font-family: system-ui, sans-serif;\n}\n"
        case "json":
            return "{\n  \"key\": \"value\"\n}\n"
        case "yaml":
            return "key: value\n"
        case "toml":
            return "key = \"value\"\n"
        case "sql":
            return "SELECT *\nFROM table_name;\n"
        case "bash", "zsh":
            return "#!/usr/bin/env \(language)\n\n"
        case "markdown":
            return "# Title\n\n"
        case "tex":
            return "\\documentclass{article}\n\\usepackage[utf8]{inputenc}\n\n\\begin{document}\n\\section{Title}\n\n\n\\end{document}\n"
        case "plain":
            return ""
        default:
            return "TODO\n"
        }
    }

    // MARK: - Shortcut and Preview Helpers

    @ViewBuilder
    private var shortcutSettingsContent: some View {
        VStack(alignment: .leading, spacing: UI.space8) {
            ForEach(EditorShortcutAction.allCases) { action in
                HStack(alignment: .center, spacing: UI.space10) {
                    Text(action.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("cmd+shift+p", text: shortcutDraftBinding(for: action))
                        .textFieldStyle(.roundedBorder)
#if os(iOS) || os(visionOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 190, alignment: .trailing)
                }
            }
            Text("Format: cmd+<key>, optional shift/alt/ctrl. Example: cmd+shift+f")
                .font(Typography.footnote)
                .foregroundStyle(.secondary)
            if !shortcutConflictMessage.isEmpty {
                Text(shortcutConflictMessage)
                    .font(Typography.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Reset to Defaults") {
                resetShortcutDraftsToDefaults()
            }
            .buttonStyle(.bordered)
        }
    }

    private var shortcutConflictMessage: String {
        var collisionMap: [EditorShortcutDescriptor: [String]] = [:]
        for action in EditorShortcutAction.allCases {
            let raw = shortcutDrafts[action] ?? ShortcutPreferences.rawShortcut(for: action)
            guard let descriptor = ShortcutPreferences.parseShortcut(raw) else { continue }
            collisionMap[descriptor, default: []].append(action.title)
        }
        let collisions = collisionMap.values.filter { $0.count > 1 }
        guard let first = collisions.first else { return "" }
        return "Conflict: " + first.joined(separator: ", ") + " share the same shortcut."
    }

    private func loadShortcutDraftsIfNeeded() {
        if shortcutDrafts.count == EditorShortcutAction.allCases.count { return }
        var drafts: [EditorShortcutAction: String] = [:]
        for action in EditorShortcutAction.allCases {
            drafts[action] = ShortcutPreferences.rawShortcut(for: action)
        }
        shortcutDrafts = drafts
    }

    private func resetShortcutDraftsToDefaults() {
        ShortcutPreferences.resetAllToDefaults()
        var drafts: [EditorShortcutAction: String] = [:]
        for action in EditorShortcutAction.allCases {
            drafts[action] = action.defaultShortcut.normalizedStorageValue
        }
        shortcutDrafts = drafts
    }

    private func shortcutDraftBinding(for action: EditorShortcutAction) -> Binding<String> {
        Binding(
            get: {
                shortcutDrafts[action] ?? ShortcutPreferences.rawShortcut(for: action)
            },
            set: { newValue in
                shortcutDrafts[action] = newValue
                ShortcutPreferences.setRawShortcut(newValue, for: action)
            }
        )
    }

    private func themePreviewSnippet(previewTheme: EditorTheme, showsTitle: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTitle {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                themePreviewLine(
                    "# Release Notes",
                    color: previewTheme.syntax.meta,
                    weight: previewTheme.boldMarkdownHeadings ? .bold : .regular
                )
                themePreviewLine(
                    "[docs](https://example.com/theme-guide)",
                    color: previewTheme.syntax.string,
                    underline: previewTheme.underlineLinks
                )
                themePreviewLine(
                    "func computeTotal(_ values: [Int]) -> Int {",
                    color: previewTheme.syntax.keyword,
                    weight: previewTheme.boldKeywords ? .bold : .regular
                )
                Text("    let sum = values.reduce(0, +)")
                    .foregroundStyle(previewTheme.text)
                themePreviewLine(
                    "    // tax adjustment",
                    color: previewTheme.syntax.comment,
                    italic: previewTheme.italicComments
                )
                Text("    return sum + 42")
                    .foregroundStyle(previewTheme.syntax.number)
                themePreviewLine(
                    "}",
                    color: previewTheme.syntax.keyword,
                    weight: previewTheme.boldKeywords ? .bold : .regular
                )
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .padding(UI.space10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(previewTheme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(previewTheme.selection.opacity(0.7), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func themePreviewLine(
        _ text: String,
        color: Color,
        weight: Font.Weight = .regular,
        italic: Bool = false,
        underline: Bool = false
    ) -> some View {
        let line = Text(text)
            .foregroundStyle(color)
            .font(.system(size: 12, weight: weight, design: .monospaced))
        let formattedLine = italic ? line.italic() : line
        if underline {
            formattedLine.underline()
        } else {
            formattedLine
        }
    }
}

#if os(iOS)
// MARK: - iPad Keyboard Shortcut Bridge

// Hidden responder used only to expose Command-Arrow tab switching on iPad hardware keyboards.
private struct SettingsKeyboardShortcutBridge: UIViewRepresentable {
    let onMoveToPreviousTab: () -> Void
    let onMoveToNextTab: () -> Void

    func makeUIView(context: Context) -> SettingsKeyboardCommandView {
        let view = SettingsKeyboardCommandView()
        view.onMoveToPreviousTab = onMoveToPreviousTab
        view.onMoveToNextTab = onMoveToNextTab
        return view
    }

    func updateUIView(_ uiView: SettingsKeyboardCommandView, context: Context) {
        uiView.onMoveToPreviousTab = onMoveToPreviousTab
        uiView.onMoveToNextTab = onMoveToNextTab
        uiView.refreshFirstResponderStatus()
    }
}

private final class SettingsKeyboardCommandView: UIView {
    var onMoveToPreviousTab: (() -> Void)?
    var onMoveToNextTab: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return [] }
        let previousTabCommand = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .command, action: #selector(handlePreviousTabCommand))
        previousTabCommand.discoverabilityTitle = "Previous Settings Tab"
        let nextTabCommand = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .command, action: #selector(handleNextTabCommand))
        nextTabCommand.discoverabilityTitle = "Next Settings Tab"
        return [previousTabCommand, nextTabCommand]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshFirstResponderStatus()
    }

    func refreshFirstResponderStatus() {
        guard window != nil, UIDevice.current.userInterfaceIdiom == .pad else { return }
        DispatchQueue.main.async { [weak self] in
            _ = self?.becomeFirstResponder()
        }
    }

    @objc private func handlePreviousTabCommand() {
        onMoveToPreviousTab?()
    }

    @objc private func handleNextTabCommand() {
        onMoveToNextTab?()
    }
}
#endif

#if os(macOS)
// MARK: - macOS Settings Window Configurator

// SwiftUI settings windows need a small AppKit bridge for stable chrome, sizing, and Escape/Command-W handling.
@MainActor
struct SettingsWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let idealSize: NSSize
    let translucentEnabled: Bool
    let translucencyModeRaw: String
    let appearanceRaw: String
    let effectiveColorScheme: ColorScheme

    final class Coordinator: @unchecked Sendable {
        var didInitialApply = false
        var pendingApply: DispatchWorkItem?
        var lastTranslucentEnabled: Bool?
        var lastTranslucencyModeRaw: String?
        var didConfigureWindowChrome = false
        var observedWindowNumber: Int?
        nonisolated(unsafe) var didBecomeKeyObserver: NSObjectProtocol?
        nonisolated(unsafe) var willCloseObserver: NSObjectProtocol?
        nonisolated(unsafe) var keyDownMonitor: Any?

        deinit {
            if let observer = didBecomeKeyObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = willCloseObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            scheduleApply(to: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleApply(to: nsView.window, coordinator: context.coordinator)
    }

    private func scheduleApply(to window: NSWindow?, coordinator: Coordinator) {
        coordinator.pendingApply?.cancel()
        guard let window else { return }
        let work = DispatchWorkItem {
            apply(to: window, coordinator: coordinator)
        }
        coordinator.pendingApply = work
        let delay: DispatchTimeInterval = coordinator.didInitialApply ? .milliseconds(30) : .milliseconds(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        ensureObservers(for: window, coordinator: coordinator)
        let isFirstApply = !coordinator.didInitialApply
        coordinator.lastTranslucentEnabled = translucentEnabled
        coordinator.lastTranslucencyModeRaw = translucencyModeRaw
        enforceResizableSettingsWindowBounds(on: window)

        // Always enforce native macOS Settings toolbar chrome; other window updaters may have changed it.
        window.toolbarStyle = .preference
        window.titleVisibility = .hidden
        window.title = ""
        if isFirstApply {
            applyInitialSettingsWindowFrame(to: window)
        } else {
            clampSettingsWindowToVisibleFrame(window)
        }

        if !coordinator.didConfigureWindowChrome {
            // Keep settings chrome stable for the lifetime of this window.
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            if #available(macOS 13.0, *) {
                window.titlebarSeparatorStyle = .none
            }
            coordinator.didConfigureWindowChrome = true
        }
        window.isOpaque = !translucentEnabled
        // Keep a non-clear background to avoid fully transparent titlebar artifacts.
        window.backgroundColor = translucencyEnabledColor(enabled: translucentEnabled)
        // Some macOS states restore the title from the selected settings tab.
        // Force an empty, hidden title for native Settings appearance.
        window.title = ""
        window.titleVisibility = .hidden
        window.representedURL = nil
        coordinator.didInitialApply = true
    }

    private func applyInitialSettingsWindowFrame(to window: NSWindow) {
        let targetFrame = initialWindowFrame(for: window)
        let current = window.frame
        guard current.width < targetFrame.width - 24 ||
              current.height < targetFrame.height - 24 else {
            clampSettingsWindowToVisibleFrame(window)
            return
        }
        setSettingsWindowFrame(targetFrame, on: window)
    }

    private func enforceResizableSettingsWindowBounds(on window: NSWindow) {
        let maximumSize = maximumWindowSize(for: window)
        window.styleMask.insert(.resizable)
        window.minSize = minSize
        window.maxSize = maximumSize
        window.contentMinSize = minSize
        window.contentMaxSize = maximumSize
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }

    private func initialWindowSize(for window: NSWindow) -> NSSize {
        let maximumSize = maximumWindowSize(for: window)
        return NSSize(
            width: min(max(minSize.width, idealSize.width), maximumSize.width),
            height: min(max(minSize.height, idealSize.height), maximumSize.height)
        )
    }

    private func initialWindowFrame(for settingsWindow: NSWindow) -> NSRect {
        let size = initialWindowSize(for: settingsWindow)
        let referenceWindow = preferredReferenceWindow(excluding: settingsWindow)
        let referenceFrame = referenceWindow?.frame ?? settingsWindow.frame
        let proposedFrame = NSRect(
            x: round(referenceFrame.midX - size.width / 2),
            y: round(referenceFrame.midY - size.height / 2),
            width: size.width,
            height: size.height
        )
        return clampedSettingsWindowFrame(proposedFrame, for: settingsWindow)
    }

    private func maximumWindowSize(for window: NSWindow) -> NSSize {
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maxWidth = max(minSize.width, (visibleFrame?.width ?? idealSize.width) - 24)
        let maxHeight = max(minSize.height, (visibleFrame?.height ?? idealSize.height) - 24)
        return NSSize(
            width: maxWidth,
            height: maxHeight
        )
    }

    private func clampSettingsWindowToVisibleFrame(_ settingsWindow: NSWindow) {
        let frame = clampedSettingsWindowFrame(settingsWindow.frame, for: settingsWindow)
        setSettingsWindowFrame(frame, on: settingsWindow)
    }

    private func clampedSettingsWindowFrame(_ proposedFrame: NSRect, for settingsWindow: NSWindow) -> NSRect {
        guard let visibleFrame = settingsWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return proposedFrame
        }
        var frame = proposedFrame
        let maximumSize = maximumWindowSize(for: settingsWindow)
        frame.size.width = min(max(frame.size.width, minSize.width), maximumSize.width)
        frame.size.height = min(max(frame.size.height, minSize.height), maximumSize.height)
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.size.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.size.height)
        return frame
    }

    private func setSettingsWindowFrame(_ frame: NSRect, on settingsWindow: NSWindow) {
        let current = settingsWindow.frame
        guard abs(frame.origin.x - current.origin.x) > 1 ||
              abs(frame.origin.y - current.origin.y) > 1 ||
              abs(frame.size.width - current.size.width) > 1 ||
              abs(frame.size.height - current.size.height) > 1 else { return }
        settingsWindow.setFrame(frame, display: true, animate: false)
    }

    static func settingsWindowBackgroundColor(
        translucentEnabled: Bool,
        translucencyModeRaw: String,
        appearanceRaw: String,
        effectiveColorScheme: ColorScheme
    ) -> NSColor {
        guard translucentEnabled else { return NSColor.windowBackgroundColor }
        let isDark: Bool
        switch appearanceRaw {
        case "light":
            isDark = false
        case "dark":
            isDark = true
        default:
            isDark = effectiveColorScheme == .dark
        }
        let whiteLevel: CGFloat
        let alpha: CGFloat
        switch translucencyModeRaw {
        case "subtle":
            whiteLevel = isDark ? 0.18 : 0.90
            alpha = 0.70
        case "vibrant":
            whiteLevel = isDark ? 0.12 : 0.82
            alpha = 0.46
        default:
            whiteLevel = isDark ? 0.15 : 0.86
            alpha = 0.58
        }
        return NSColor(calibratedWhite: whiteLevel, alpha: alpha)
    }

    private func translucencyEnabledColor(enabled: Bool) -> NSColor {
        Self.settingsWindowBackgroundColor(
            translucentEnabled: enabled,
            translucencyModeRaw: translucencyModeRaw,
            appearanceRaw: appearanceRaw,
            effectiveColorScheme: effectiveColorScheme
        )
    }

    private func ensureObservers(for window: NSWindow, coordinator: Coordinator) {
        let windowNumber = window.windowNumber
        if coordinator.observedWindowNumber == windowNumber {
            ensureKeyboardMonitor(for: window, coordinator: coordinator)
            return
        }
        if let observer = coordinator.didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.didBecomeKeyObserver = nil
        }
        if let observer = coordinator.willCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.willCloseObserver = nil
        }
        if let monitor = coordinator.keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            coordinator.keyDownMonitor = nil
        }
        coordinator.observedWindowNumber = windowNumber
        ensureKeyboardMonitor(for: window, coordinator: coordinator)

        coordinator.didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak coordinator] _ in
            Task { @MainActor in
                coordinator?.didInitialApply = true
            }
        }

        coordinator.willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak coordinator] _ in
            Task { @MainActor in
                coordinator?.didInitialApply = false
            }
        }
    }

    private func ensureKeyboardMonitor(for window: NSWindow, coordinator: Coordinator) {
        if coordinator.keyDownMonitor != nil { return }
        coordinator.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window else { return event }
            if event.keyCode == 53 {
                window.performClose(nil)
                return nil
            }
            let commandWPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command &&
                event.charactersIgnoringModifiers?.lowercased() == "w"
            if commandWPressed {
                window.performClose(nil)
                return nil
            }
            return event
        }
    }

    private func preferredReferenceWindow(excluding settingsWindow: NSWindow) -> NSWindow? {
        if let key = NSApp.keyWindow, key !== settingsWindow, key.isVisible {
            return key
        }
        if let main = NSApp.mainWindow, main !== settingsWindow, main.isVisible {
            return main
        }
        return NSApp.windows.first(where: { window in
            window !== settingsWindow && window.isVisible && window.level == .normal
        })
    }
}
#endif

#if DEBUG && canImport(SwiftUI) && canImport(PreviewsMacros)
#Preview {
    NeonSettingsView(
        supportsOpenInTabs: true,
        supportsTranslucency: true
    )
}
#endif
