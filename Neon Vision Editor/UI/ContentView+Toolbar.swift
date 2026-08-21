import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct ToolbarActionSelection {
    static let supportedVisibleCounts: Set<Int> = [4, 5, 6, 7, 8, 10]
    static let universallyAvailableMobileActionIDs: Set<String> = ["settings", "help"]

    static func visibleLimit(requestedCount: Int, fallback: Int) -> Int {
        supportedVisibleCounts.contains(requestedCount) ? requestedCount : fallback
    }

    static func selectedIDs(from rawValue: String) -> Set<String> {
        Set(
            rawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func isAllowedByPreset(
        actionID: String,
        preset: ToolbarPreset,
        customIDsRawValue: String,
        universalIDs: Set<String> = []
    ) -> Bool {
        if universalIDs.contains(actionID) {
            return true
        }
        if preset == .custom {
            return selectedIDs(from: customIDsRawValue).contains(actionID)
        }
        return preset.mobileIDs.contains(actionID)
    }

    static func orderedIDs(from rawValue: String, fallback: [String]) -> [String] {
        let selected = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var result: [String] = []
        for id in selected where !result.contains(id) {
            result.append(id)
        }
        for id in fallback where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    static func visibleActions<Action>(
        enabledActions: [Action],
        requestedCount: Int,
        preset: ToolbarPreset? = nil
    ) -> [Action] {
        // Named presets define the toolbar's complete direct action set. The
        // count preference applies only while composing a Custom toolbar.
        if let preset, preset != .custom {
            return enabledActions
        }
        let limit = visibleLimit(requestedCount: requestedCount, fallback: enabledActions.count)
        return Array(enabledActions.prefix(limit))
    }

    static func overflowActions<Action: Hashable>(
        enabledActions: [Action],
        visibleActions: [Action]
    ) -> [Action] {
        let visible = Set(visibleActions)
        return enabledActions.filter { !visible.contains($0) }
    }

    static func honorsSectionVisibility(preset: ToolbarPreset) -> Bool {
        preset == .custom
    }

    static func toggledSelectionRawValue(
        toggledID: String,
        currentRawValue: String,
        orderedIDs: [String],
        limit: Int
    ) -> String {
        var selected = selectedIDs(from: currentRawValue)
        if selected.contains(toggledID) {
            selected.remove(toggledID)
        } else if selected.count < limit {
            selected.insert(toggledID)
        }
        return orderedIDs
            .filter { selected.contains($0) }
            .joined(separator: ",")
    }
}

enum ToolbarPreset: String, CaseIterable, Identifiable {
    case standard
    case writing
    case developer
    case review
    case focus
    case all
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .writing: return "Writing"
        case .developer: return "Development"
        case .review: return "Git Review"
        case .focus: return "Focus"
        case .all: return "All Actions"
        case .custom: return "Custom"
        }
    }

    var compactTitle: String {
        switch self {
        case .standard: return "Std"
        case .writing: return "Write"
        case .developer: return "Dev"
        case .review: return "Git"
        case .focus: return "Focus"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }

    var toolbarLabel: String {
        switch self {
        case .standard: return "Standard"
        case .writing: return "Write"
        case .developer: return "Dev"
        case .review: return "Review"
        case .focus: return "Focus"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "checkmark.circle"
        case .writing: return "doc.text"
        case .developer: return "hammer"
        case .review: return "arrow.triangle.branch"
        case .focus: return "moon"
        case .all: return "square.grid.3x3"
        case .custom: return "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .standard: return NeonUIStyle.accentBlue
        case .writing: return .pink
        case .developer: return .orange
        case .review: return .purple
        case .focus: return .indigo
        case .all: return .teal
        case .custom: return .mint
        }
    }

    /// Ordered macOS toolbar actions for each preset.
    var macOSIDs: [String] {
        switch self {
        case .standard:
            return [
                "openFile", "newTab", "closeAllTabs", "saveFile", "saveFileAs", "newWindow",
                "codeMinimap", "previewActions", "markdownProjectPreview", "findReplace", "findInFiles",
                "toggleSidebar", "toggleProjectSidebar", "brainDump", "help", "languageIndicator", "settings"
            ]
        case .writing:
            return ["openFile", "newTab", "saveFile", "findReplace", "editorLayout", "previewActions", "markdownProjectPreview", "settings", "help"]
        case .developer:
            return ["openFile", "newTab", "saveFile", "codeSnapshot", "findReplace", "findInFiles", "compare", "splitEditor", "gitChanges", "settings"]
        case .review:
            return ["openFile", "findReplace", "findInFiles", "compare", "splitEditor", "gitChanges", "editorLayout", "settings", "help"]
        case .focus:
            return ["openFile", "saveFile", "findReplace", "editorLayout", "previewActions", "settings"]
        case .all:
            return [
                "openFile", "newTab", "closeAllTabs", "saveFile", "saveFileAs", "newWindow", "codeSnapshot",
                "editorLayout", "previewActions", "markdownProjectPreview", "findReplace", "findInFiles",
                "compare", "splitEditor", "gitChanges", "settings", "help"
            ]
        case .custom:
            return []
        }
    }

    /// Ordered mobile/visionOS actions. The available width still determines how
    /// many are pinned; the rest are placed in the overflow menu.
    var mobileIDs: [String] {
        switch self {
        case .standard:
            return [
                "openFile", "undo", "newTab", "saveFile", "findReplace", "findInFiles", "markdownPreview",
                "markdownProjectPreview", "codeMinimap", "toggleSidebar", "toggleProjectSidebar", "brainDump", "gitChanges", "settings", "help"
            ]
        case .writing:
            return ["openFile", "undo", "saveFile", "findReplace", "markdownPreview", "markdownProjectPreview", "markdownPreviewStyle", "lineWrap", "settings", "help"]
        case .developer:
            return ["openFile", "undo", "newTab", "saveFile", "findReplace", "findInFiles", "compareTabs", "gitChanges", "splitEditor", "settings", "help"]
        case .review:
            return ["openFile", "findReplace", "findInFiles", "compareDisk", "compareTabs", "gitChanges", "splitEditor", "settings", "help"]
        case .focus:
            return ["openFile", "undo", "saveFile", "findReplace", "markdownPreview", "settings", "help"]
        case .all:
            return [
                "openFile", "undo", "settings", "help", "clearEditor", "insertTemplate",
                "newTab", "saveFile", "saveFileAs", "codeSnapshot", "markdownPreview",
                "markdownProjectPreview", "codeMinimap", "indentationGuides", "markdownPreviewExport",
                "markdownPreviewStyle", "closeAllTabs", "toggleSidebar", "toggleProjectSidebar",
                "findReplace", "findInFiles", "compareDisk", "compareTabs", "gitChanges",
                "splitEditor", "editorLayout", "previewActions", "lineWrap", "codeCompletion",
                "keyboardAccessory", "hideKeyboard", "performanceMode", "brainDump", "welcomeTour",
                "translucentWindow", "toolbarIconColor", "fontDecrease", "fontIncrease"
            ]
        case .custom:
            return []
        }
    }

    static var mobileSelectableIDs: [String] {
        var result: [String] = []
        for id in allCases.flatMap(\.mobileIDs) where !result.contains(id) {
            result.append(id)
        }
        return result
    }
}

enum ToolbarIconOption: String, CaseIterable, Identifiable {
    case openFile, undo, settings, help, clearEditor, insertTemplate, newTab, saveFile, saveFileAs
    case codeSnapshot, markdownPreview, markdownProjectPreview, codeMinimap, indentationGuides, markdownPreviewExport
    case markdownPreviewStyle, closeAllTabs, toggleSidebar, toggleProjectSidebar, findReplace, findInFiles
    case languageIndicator
    case compareDisk, compareTabs, compare, gitChanges, splitEditor, editorLayout, previewActions
    case lineWrap, codeCompletion, keyboardAccessory, hideKeyboard, fontDecrease, fontIncrease
    case performanceMode, brainDump, welcomeTour, translucentWindow, toolbarIconColor

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
        case .markdownProjectPreview: return "Markdown Cards"
        case .codeMinimap: return "Code Minimap"
        case .indentationGuides: return "Indentation Guides"
        case .markdownPreviewExport: return "Export PDF"
        case .markdownPreviewStyle: return "Preview Style"
        case .closeAllTabs: return "Close All Tabs"
        case .toggleSidebar: return "Toggle Sidebar"
        case .toggleProjectSidebar: return "Toggle Project Sidebar"
        case .languageIndicator: return "Language Indicator"
        case .findReplace: return "Find"
        case .findInFiles: return "Find in Files"
        case .compareDisk: return "Compare with Disk"
        case .compareTabs: return "Compare Tabs"
        case .compare: return "Compare Menu"
        case .gitChanges: return "Git Changes"
        case .splitEditor: return "Side by Side"
        case .editorLayout: return "Editor Layout"
        case .previewActions: return "Preview Actions"
        case .lineWrap: return "Line Wrap"
        case .codeCompletion: return "Code Completion"
        case .keyboardAccessory: return "Keyboard Bar"
        case .hideKeyboard: return "Hide Keyboard"
        case .fontDecrease: return "Decrease Font Size"
        case .fontIncrease: return "Increase Font Size"
        case .performanceMode: return "Performance Mode"
        case .brainDump: return "Brain Dump"
        case .welcomeTour: return "Welcome Tour"
        case .translucentWindow: return "Translucent Window"
        case .toolbarIconColor: return "Blue Icons"
        }
    }
}

// MARK: - Toolbar Content

extension ContentView {
    // MARK: - Provider Badge and macOS Menus

    private var compactActiveProviderName: String {
        activeProviderName.components(separatedBy: " (").first ?? activeProviderName
    }

    private var providerBadgeLabelText: String {
#if os(macOS)
        if compactActiveProviderName == "Apple" {
            return "AI Provider \(compactActiveProviderName)"
        }
#endif
        return compactActiveProviderName
    }

    private var providerBadgeIsAppleCompletionActive: Bool {
        compactActiveProviderName == "Apple" && isAutoCompletionEnabled
    }

    private var providerBadgeForegroundColor: Color {
        providerBadgeIsAppleCompletionActive ? .green : .secondary
    }

    private var providerBadgeBackgroundColor: Color {
        providerBadgeIsAppleCompletionActive ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12)
    }

    private var providerBadgeTooltip: String {
        "AI Provider for Code Completion"
    }

    @ViewBuilder
    private var markdownPreviewTemplateMenuItems: some View {
        ForEach(Self.markdownPreviewTemplateOptions.prefix(4)) { option in
            Button {
                markdownPreviewTemplateRaw = option.id
            } label: {
                Label(NSLocalizedString(option.title, comment: ""), systemImage: markdownPreviewTemplateRaw == option.id ? "checkmark" : "circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(toolbarMarkdownPreviewThemeSwatchColor(for: option.id), .secondary)
            }
        }

        Divider()

        ForEach(Self.markdownPreviewTemplateOptions.dropFirst(4)) { option in
            Button {
                markdownPreviewTemplateRaw = option.id
            } label: {
                Label(NSLocalizedString(option.title, comment: ""), systemImage: markdownPreviewTemplateRaw == option.id ? "checkmark" : "circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(toolbarMarkdownPreviewThemeSwatchColor(for: option.id), .secondary)
            }
        }
    }

    private func toolbarMarkdownPreviewThemeSwatchColor(for template: String) -> Color {
        switch template {
        case "neon-editorial", "neon-paper": return Color(red: 0.38, green: 0.85, blue: 1.0)
        case "developer-slate", "developer-spec", "api-reference": return Color(red: 0.33, green: 0.90, blue: 0.74)
        case "nordic-light", "docs", "minimal-reader": return Color(red: 0.06, green: 0.46, blue: 0.43)
        case "solarized", "blueprint", "notebook": return Color(red: 0.16, green: 0.63, blue: 0.60)
        case "article", "academic-paper", "warm-sepia": return Color(red: 0.55, green: 0.26, blue: 0.35)
        case "electric-pop": return Color(red: 0.88, green: 0.09, blue: 0.55)
        case "aurora": return Color(red: 0.03, green: 0.50, blue: 0.40)
        case "citrus": return Color(red: 0.85, green: 0.47, blue: 0.02)
        case "plasma": return Color(red: 0.85, green: 0.08, blue: 0.47)
        case "deep-ocean": return Color(red: 0.03, green: 0.49, blue: 0.78)
        case "high-contrast": return Color.black
        case "warm-sepia": return Color(red: 0.66, green: 0.36, blue: 0.14)
        default: return Color.accentColor
        }
    }

#if os(macOS)
    private func isMacToolbarItemVisible(_ id: String) -> Bool {
        if toolbarUseCustomMac || toolbarPresetMacRaw == ToolbarPreset.custom.rawValue {
            return ToolbarActionSelection.selectedIDs(from: toolbarCustomIDsMac).contains(id)
        }
        let preset = ToolbarPreset(rawValue: toolbarPresetMacRaw) ?? .standard
        return preset.macOSIDs.contains(id)
    }

    @ViewBuilder
    private var macLanguageIndicatorControl: some View {
        Menu {
            let selectedLanguage = currentLanguagePickerBinding.wrappedValue
            Button {
                currentLanguagePickerBinding.wrappedValue = selectedLanguage
            } label: {
                Label(languageLabel(for: selectedLanguage), systemImage: "checkmark")
            }
            Button(action: { presentLanguageSearchSheet() }) {
                Label("Language…", systemImage: "magnifyingglass")
            }
            Divider()
            ForEach(languageOptions.filter { $0 != selectedLanguage }, id: \.self) { lang in
                Button {
                    currentLanguagePickerBinding.wrappedValue = lang
                } label: {
                    Text(languageLabel(for: lang))
                }
            }
        } label: {
            HStack(spacing: 0) {
                Text(languageLabel(for: currentLanguagePickerBinding.wrappedValue))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(macToolbarSymbolColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 116, alignment: .center)
        }
        .menuStyle(.borderlessButton)
        .frame(minWidth: 132, alignment: .center)
        .help("Language")
        .accessibilityLabel("Language picker")
        .accessibilityValue(languageLabel(for: currentLanguagePickerBinding.wrappedValue))
        .controlSize(.large)
        .padding(.vertical, 2)
    }

    private var isMacToolbarSecondaryUtilitiesVisible: Bool {
        toolbarUseCustomMac || toolbarPresetMacRaw != ToolbarPreset.standard.rawValue
    }

    private var macToolbarSymbolColor: Color {
        let isDarkMode = colorScheme == .dark
        switch toolbarSymbolsColorMacRaw {
        case "black":
            return isDarkMode
                ? Color(.sRGB, white: 0.94, opacity: 1.0)
                : .black
        case "darkGray":
            return isDarkMode
                ? Color(.sRGB, white: 0.84, opacity: 1.0)
                : Color(.sRGB, white: 0.40, opacity: 1.0)
        default:
            return NeonUIStyle.accentBlue
        }
    }

    @ViewBuilder
    private var markdownPreviewExportToolbarMenuContent: some View {
        Button(action: { exportMarkdownPreviewPDF() }) {
            Label("Export PDF", systemImage: "square.and.arrow.down")
        }
        .help("Export Markdown Preview as PDF")

        Menu {
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.paginatedFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.paginatedFit.rawValue {
                    Label("Paginated Fit", systemImage: "checkmark")
                } else {
                    Text("Paginated Fit")
                }
            }
            .help("Use Paginated Fit PDF Export")
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.onePageFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.onePageFit.rawValue {
                    Label("One Page Fit", systemImage: "checkmark")
                } else {
                    Text("One Page Fit")
                }
            }
            .help("Use One Page Fit PDF Export")
        } label: {
            Label("PDF Mode", systemImage: "doc.text")
        }
        .help("Choose PDF Export Mode")

        Menu {
            markdownPreviewTemplateMenuItems
        } label: {
            Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
        }
        .help(NSLocalizedString("Choose Markdown Preview Style", comment: "Toolbar help for markdown preview style picker"))

        Button(action: { copyMarkdownPreviewHTML() }) {
            Label("Copy HTML", systemImage: "doc.on.doc")
        }
        .help("Copy Markdown Preview HTML")
        Button(action: { copyMarkdownPreviewMarkdown() }) {
            Label("Copy Markdown", systemImage: "doc.on.clipboard")
        }
        .help("Copy Markdown Source")
    }
#endif

    private func selectToolbarPreset(_ preset: ToolbarPreset) {
#if os(macOS)
        toolbarPresetMacRaw = preset.rawValue
        toolbarUseCustomMac = preset == .custom
        if preset == .custom && toolbarCustomIDsMac.isEmpty {
            toolbarCustomIDsMac = ToolbarPreset.all.macOSIDs.joined(separator: ",")
        }
#else
        toolbarPresetIOSRaw = preset.rawValue
        toolbarUseCustomFiveIOS = preset == .custom
        if preset == .custom && toolbarCustomFiveIDsIOS.isEmpty {
            toolbarCustomFiveIDsIOS = ToolbarPreset.mobileSelectableIDs.prefix(toolbarFavoriteCountIOS).joined(separator: ",")
        }
#endif
    }

    private var toolbarPresetMenuControl: some View {
        Menu {
            ForEach(ToolbarPreset.allCases) { preset in
                Button {
                    selectToolbarPreset(preset)
                } label: {
                    Label(preset.title, systemImage: preset.icon)
                        .labelStyle(.titleAndIcon)
                    if currentToolbarPreset == preset {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
#if os(macOS)
            HStack(spacing: 5) {
                Image(systemName: currentToolbarPreset.icon)
                Text(currentToolbarPreset.compactTitle)
                    .lineLimit(1)
            }
            .foregroundStyle(currentToolbarPreset.tint)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 64, alignment: .center)
#else
            HStack(spacing: 4) {
                Image(systemName: currentToolbarPreset.icon)
                Text(currentToolbarPreset.compactTitle)
                    .lineLimit(1)
            }
                .foregroundStyle(currentToolbarPreset.tint)
                .fixedSize()
#endif
        }
        .help("Choose Toolbar Preset")
        .accessibilityLabel("Toolbar Preset")
        .accessibilityValue(currentToolbarPreset.title)
    }

    private var currentToolbarPreset: ToolbarPreset {
#if os(macOS)
        ToolbarPreset(rawValue: toolbarPresetMacRaw) ?? .standard
#else
        effectiveIOSToolbarPreset
#endif
    }

#if os(iOS) || os(visionOS)
    private var effectiveIOSToolbarPreset: ToolbarPreset {
        toolbarUseCustomFiveIOS
            ? .custom
            : ToolbarPreset(rawValue: toolbarPresetIOSRaw) ?? .standard
    }
#endif

    // These controls are shared by the macOS toolbar and the iPad/visionOS
    // action renderer. Keep their declarations outside the mobile-only
    // toolbar layout block so every platform can resolve the same action.
    @ViewBuilder
    private var toggleSidebarControl: some View {
        Button(action: { toggleSidebarFromToolbar() }) {
            Image(systemName: "sidebar.left")
        }
        .help("Toggle Sidebar (Cmd+Opt+S)")
    }

    @ViewBuilder
    private var toggleProjectSidebarControl: some View {
        Button(action: { toggleProjectSidebarFromToolbar() }) {
            Image(systemName: "sidebar.right")
        }
        .help("Toggle Project Structure Sidebar")
    }

    @ViewBuilder
    private var brainDumpControl: some View {
        Button(action: {
            toggleBrainDumpModeIOSAware()
        }) {
            Image(systemName: "note.text")
                .symbolVariant(viewModel.isBrainDumpMode ? .fill : .none)
        }
        .help("Brain Dump Mode")
        .accessibilityLabel("Brain Dump Mode")
        .accessibilityValue(viewModel.isBrainDumpMode ? "On" : "Off")
        .accessibilityHint("Switches to a distraction-free scratch document")
    }

    @ViewBuilder
    private var codeMinimapControl: some View {
        if supportsCodeMinimap(language: currentLanguage) {
            Button(action: {
                showCodeMinimap.toggle()
            }) {
                Image(systemName: showCodeMinimap ? "map.fill" : "map")
            }
            .help(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap")
            .accessibilityLabel("Code Minimap")
            .accessibilityValue(showCodeMinimap ? "Shown" : "Hidden")
            .accessibilityHint("Toggles the code minimap for code files")
        }
    }

    private func toggleBrainDumpModeIOSAware() {
        viewModel.isBrainDumpMode.toggle()
        UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
    }

#if os(iOS) || os(visionOS)
    // MARK: - iOS Toolbar Layout Metrics

    private var iOSToolbarChromeStyle: GlassChromeStyle { .single }
    private var iOSToolbarTintColor: Color {
        if toolbarIconsBlueIOS {
            return NeonUIStyle.accentBlue
        }
        return colorScheme == .dark ? Color.white.opacity(0.95) : Color.primary.opacity(0.92)
    }

    var isIPadToolbarLayout: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        // During first render on iOS, horizontalSizeClass can transiently be nil.
        // Treat nil as regular so the full iPad toolbar appears immediately.
        if horizontalSizeClass == .compact { return false }
        return true
    }

    private var iPhoneToolbarWidth: CGFloat {
        max(liveContainerWidth, 320)
    }

    private var iPhoneLanguagePickerWidth: CGFloat {
        switch iPhoneToolbarWidth {
        case 430...: return 108
        case 395...: return 100
        default: return 94
        }
    }

    private enum IOSPrimaryToolbarAction: String, CaseIterable, Hashable {
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
        case markdownProjectPreview
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
        case gitChanges
        case splitEditor
        case editorLayout
        case previewActions
        case lineWrap
        case codeCompletion
        case keyboardAccessory
        case hideKeyboard
        case performanceMode
        case brainDump
        case welcomeTour
        case translucentWindow
        case toolbarIconColor
        case fontDecrease
        case fontIncrease
    }

    private var enabledIOSPrimaryToolbarActions: [IOSPrimaryToolbarAction] {
        let preset = effectiveIOSToolbarPreset
        // Named presets define their complete action set. The individual
        // visibility switches are only a Custom-toolbar preference.
        let honorsSectionVisibility = ToolbarActionSelection.honorsSectionVisibility(preset: preset)
        var actions: [IOSPrimaryToolbarAction] = []
        if !honorsSectionVisibility || toolbarShowOpenFileIOS { actions.append(.openFile) }
        if !honorsSectionVisibility || toolbarShowUndoIOS { actions.append(.undo) }
        actions.append(contentsOf: [.settings, .help])
        if !honorsSectionVisibility || toolbarShowEditorUtilityIOS {
            actions.append(contentsOf: [.clearEditor, .insertTemplate])
        }
        actions.append(contentsOf: [
            .newTab,
            .saveFile,
            .saveFileAs,
            .codeSnapshot
        ])
        if !honorsSectionVisibility || toolbarShowAppearanceIOS {
            actions.append(contentsOf: [.markdownPreview, .markdownProjectPreview, .codeMinimap, .indentationGuides])
        }
        actions.append(contentsOf: [
            .markdownPreviewExport,
            .markdownPreviewStyle,
            .closeAllTabs,
            .toggleSidebar,
            .toggleProjectSidebar,
            .editorLayout,
            .previewActions
        ])
        if !honorsSectionVisibility || toolbarShowSearchIOS {
            actions.append(contentsOf: [.findReplace, .findInFiles])
        }
        if !honorsSectionVisibility || toolbarShowCompareIOS {
            actions.append(contentsOf: [.compareDisk, .compareTabs, .gitChanges, .splitEditor])
        }
        if !honorsSectionVisibility || toolbarShowAppearanceIOS {
            actions.append(contentsOf: [.lineWrap, .fontDecrease, .fontIncrease])
        }
        if !honorsSectionVisibility || toolbarShowEditorUtilityIOS {
            actions.append(contentsOf: [.codeCompletion, .keyboardAccessory])
        }
        actions.append(.hideKeyboard)
        if !honorsSectionVisibility || toolbarShowEditorUtilityIOS {
            actions.append(contentsOf: [.performanceMode, .brainDump])
        }
        actions.append(.welcomeTour)
        if !honorsSectionVisibility || toolbarShowAppearanceIOS {
            actions.append(.translucentWindow)
        }
#if os(iOS)
        actions.append(.toolbarIconColor)
#endif
        return actions.filter {
            ToolbarActionSelection.isAllowedByPreset(
                actionID: $0.rawValue,
                preset: preset,
                customIDsRawValue: toolbarCustomFiveIDsIOS,
                universalIDs: ToolbarActionSelection.universallyAvailableMobileActionIDs
            )
        }
    }

    private var visibleIOSPrimaryToolbarActions: [IOSPrimaryToolbarAction] {
        ToolbarActionSelection.visibleActions(
            enabledActions: enabledIOSPrimaryToolbarActions,
            requestedCount: toolbarFavoriteCountIOS,
            preset: effectiveIOSToolbarPreset
        )
    }

    private var iPhoneMoreActions: [IOSPrimaryToolbarAction] {
        ToolbarActionSelection.overflowActions(
            enabledActions: enabledIOSPrimaryToolbarActions,
            visibleActions: visibleIOSPrimaryToolbarActions
        )
    }

    private func iOSPrimaryToolbarActionControl(_ action: IOSPrimaryToolbarAction) -> AnyView {
        // This factory is used inside the iPhone toolbar's ForEach. Keeping its
        // 38 branches as one opaque result type causes recursive Swift metadata
        // instantiation on device while the toolbar is laid out (stack overflow).
        // Erase precisely at this dynamic-action boundary.
        switch action {
        case .openFile: AnyView(openFileControl)
        case .undo: AnyView(undoControl)
        case .settings: AnyView(settingsControl)
        case .help: AnyView(helpControl)
        case .clearEditor: AnyView(clearEditorControl)
        case .insertTemplate: AnyView(insertTemplateControl)
        case .newTab: AnyView(newTabControl)
        case .saveFile: AnyView(saveFileControl)
        case .saveFileAs: AnyView(saveFileAsControl)
        case .codeSnapshot: AnyView(codeSnapshotControl)
        case .markdownPreview: AnyView(markdownPreviewControl)
        case .markdownProjectPreview: AnyView(markdownProjectPreviewControl)
        case .codeMinimap: AnyView(codeMinimapControl)
        case .indentationGuides: AnyView(indentationGuidesControl)
        case .markdownPreviewExport: AnyView(markdownPreviewExportControl)
        case .markdownPreviewStyle: AnyView(markdownPreviewStyleControl)
        case .closeAllTabs: AnyView(closeAllTabsControl)
        case .toggleSidebar: AnyView(toggleSidebarControl)
        case .toggleProjectSidebar: AnyView(toggleProjectSidebarControl)
        case .findReplace: AnyView(findReplaceControl)
        case .findInFiles: AnyView(findInFilesControl)
        case .compareDisk: AnyView(compareDiskControl)
        case .compareTabs: AnyView(compareTabsControl)
        case .gitChanges: AnyView(gitChangesControl)
        case .splitEditor: AnyView(splitEditorControl)
        case .editorLayout: AnyView(mobileEditorLayoutControl)
        case .previewActions: AnyView(mobilePreviewActionsControl)
        case .lineWrap: AnyView(lineWrapControl)
        case .codeCompletion: AnyView(codeCompletionControl)
        case .keyboardAccessory: AnyView(keyboardAccessoryControl)
        case .hideKeyboard: AnyView(hideKeyboardControl)
        case .performanceMode: AnyView(performanceModeControl)
        case .brainDump: AnyView(brainDumpControl)
        case .welcomeTour: AnyView(welcomeTourControl)
        case .translucentWindow: AnyView(translucentWindowControl)
        case .toolbarIconColor: AnyView(toolbarIconColorControl)
        case .fontDecrease: AnyView(fontDecreaseControl)
        case .fontIncrease: AnyView(fontIncreaseControl)
        }
    }

    @ViewBuilder
    private var mobileEditorLayoutControl: some View {
        Menu {
            ForEach(EditorLayoutPreset.allCases) { preset in
                Button(action: { applyEditorLayoutPreset(preset) }) {
                    Label(preset.title, systemImage: preset.symbol)
                    if editorLayoutPreset == preset { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "rectangle.3.group")
        }
        .help("Editor Layout Presets")
        .accessibilityLabel("Editor layout presets")
        .accessibilityValue(editorLayoutPreset.title)
    }

    @ViewBuilder
    private var mobilePreviewActionsControl: some View {
        Menu {
            Button(action: { togglePreviewFromToolbar() }) {
                Label(isPreviewVisible ? "Hide \(previewTitle)" : "Show \(previewTitle)", systemImage: previewToolbarIconName)
            }
            .disabled(!isPreviewSupportedDocument)

            Button(action: { toggleMarkdownProjectPreviewFromToolbar() }) {
                Label(isMarkdownProjectPreviewPresented ? "Hide Project Cards" : "Show Project Cards", systemImage: "square.grid.2x2")
            }
            .disabled(projectRootFolderURL == nil || !hasMarkdownOrPDFProjectPreviewFiles || isSafeModeActive)
        } label: {
            Image(systemName: isPreviewVisible ? "eye.fill" : "eye")
        }
        .help("Preview options")
        .accessibilityLabel("Preview options")
    }

    private enum IPadToolbarAction: String, CaseIterable, Hashable {
        case openFile
        case undo
        case newTab
        case closeAllTabs
        case saveFile
        case saveFileAs
        case codeSnapshot
        case markdownPreview
        case markdownProjectPreview
        case markdownPreviewExport
        case markdownPreviewStyle
        case codeMinimap
        case indentationGuides
        case fontDecrease
        case fontIncrease
        case toggleSidebar
        case toggleProjectSidebar
        case findReplace
        case findInFiles
        case compareDisk
        case compareTabs
        case gitChanges
        case splitEditor
        case editorLayout
        case previewActions
        case settings
        case help
        case codeCompletion
        case performanceMode
        case lineWrap
        case keyboardAccessory
        case hideKeyboard
        case clearEditor
        case insertTemplate
        case brainDump
        case welcomeTour
        case translucentWindow
        case toolbarIconColor
    }

    private var iPadActionPriority: [IPadToolbarAction] {
        [
            .openFile,
            .undo,
            .newTab,
            .closeAllTabs,
            .saveFile,
            .saveFileAs,
            .codeSnapshot,
            .markdownPreview,
            .markdownProjectPreview,
            .markdownPreviewExport,
            .markdownPreviewStyle,
            .codeMinimap,
            .indentationGuides,
            .fontDecrease,
            .fontIncrease,
            .toggleSidebar,
            .toggleProjectSidebar,
            .findReplace,
            .findInFiles,
            .compareDisk,
            .compareTabs,
            .gitChanges,
            .splitEditor,
            .editorLayout,
            .previewActions,
            .settings,
            .help,
            .codeCompletion,
            .lineWrap,
            .keyboardAccessory,
            .hideKeyboard,
            .clearEditor,
            .insertTemplate,
            .performanceMode,
            .brainDump,
            .welcomeTour,
            .translucentWindow,
            .toolbarIconColor
        ]
    }

    private var enabledIPadActionPriority: [IPadToolbarAction] {
        let preset = effectiveIOSToolbarPreset
        let honorsSectionVisibility = ToolbarActionSelection.honorsSectionVisibility(preset: preset)
        return iPadActionPriority.filter {
            (!honorsSectionVisibility || toolbarActionIsEnabled($0)) && ToolbarActionSelection.isAllowedByPreset(
                actionID: $0.rawValue,
                preset: preset,
                customIDsRawValue: toolbarCustomFiveIDsIOS,
                universalIDs: ToolbarActionSelection.universallyAvailableMobileActionIDs
            )
        }
    }

    private func toolbarActionIsEnabled(_ action: IPadToolbarAction) -> Bool {
        switch action {
        case .findReplace, .findInFiles:
            return toolbarShowSearchIOS
        case .compareDisk, .compareTabs, .splitEditor:
            return toolbarShowCompareIOS
        case .gitChanges:
            return toolbarShowCompareIOS
        case .clearEditor, .insertTemplate, .codeCompletion, .keyboardAccessory, .brainDump, .performanceMode:
            return toolbarShowEditorUtilityIOS
        case .fontDecrease, .fontIncrease, .markdownPreview, .markdownProjectPreview, .markdownPreviewExport, .markdownPreviewStyle, .codeMinimap, .indentationGuides, .lineWrap, .translucentWindow:
            return toolbarShowAppearanceIOS
        default:
            return true
        }
    }

    private func toggleKeyboardAccessoryBar() {
        showKeyboardAccessoryBarIOS.toggle()
        NotificationCenter.default.post(
            name: .keyboardAccessoryBarVisibilityChanged,
            object: showKeyboardAccessoryBarIOS
        )
    }

    private var visibleIPadToolbarActions: [IPadToolbarAction] {
        return ToolbarActionSelection.visibleActions(
            enabledActions: enabledIPadActionPriority,
            requestedCount: toolbarFavoriteCountIOS,
            preset: effectiveIOSToolbarPreset
        )
    }

    private var iPadOverflowActions: [IPadToolbarAction] {
        ToolbarActionSelection.overflowActions(
            enabledActions: enabledIPadActionPriority,
            visibleActions: visibleIPadToolbarActions
        )
    }

#if os(visionOS)
    private var visionOSPrimaryToolbarActions: [IPadToolbarAction] {
        enabledIPadActionPriority.filter {
            $0 != .settings &&
            $0 != .help &&
            visionOSToolbarActionIsEnabled($0)
        }
    }

    private var visionOSPinnedToolbarActionCount: Int {
        0
    }

    private var visionOSToolbarWidth: CGFloat {
        let measuredWidth = liveContainerWidth > 700 ? liveContainerWidth - 96 : 1040
        return min(max(measuredWidth, 760), 1280)
    }

    private func visibleVisionOSToolbarActions(for width: CGFloat) -> [IPadToolbarAction] {
        let reservedControlWidth = CGFloat(74 + (44 * (visionOSPinnedToolbarActionCount + 1)))
        let outerPadding: CGFloat = 16
        let minimumSpacing: CGFloat = 8
        let availableWidth = max(0, width - reservedControlWidth - outerPadding)
        let visibleCount = Int((availableWidth + minimumSpacing) / (44 + minimumSpacing))
        return Array(visionOSPrimaryToolbarActions.prefix(max(0, min(visionOSPrimaryToolbarActions.count, visibleCount))))
    }

    private func visionOSOverflowActions(visibleActions: [IPadToolbarAction]) -> [IPadToolbarAction] {
        let visible = Set(visibleActions)
        let primaryOverflow = visionOSPrimaryToolbarActions.filter { !visible.contains($0) }
        let utilities = enabledIPadActionPriority.filter { $0 == .settings || $0 == .help }
        return primaryOverflow + utilities
    }

    private func visionOSToolbarSpacing(for width: CGFloat, visibleActionCount: Int, showsOverflow: Bool) -> CGFloat {
        let fixedControlCount = 1 + visibleActionCount + visionOSPinnedToolbarActionCount + (showsOverflow ? 1 : 0)
        let fixedControlWidth = 74 + CGFloat(max(0, fixedControlCount - 1)) * 44
        let gaps = max(1, fixedControlCount - 1)
        let availableSpacing = max(8, (width - fixedControlWidth - 16) / CGFloat(gaps))
        return min(18, availableSpacing)
    }

    private func visionOSToolbarActionIsEnabled(_ action: IPadToolbarAction) -> Bool {
        switch action {
        case .openFile:
            return toolbarShowOpenFileIOS
        case .undo:
            return toolbarShowUndoIOS
        default:
            return true
        }
    }
#endif

    // MARK: - Shared Toolbar Controls

    @ViewBuilder
    private var newTabControl: some View {
        Button(action: { viewModel.addNewTab() }) {
            Image(systemName: "plus.square.on.square")
        }
        .help("New Tab (Cmd+T)")
        .accessibilityLabel("New tab")
        .accessibilityHint("Creates a new editor tab")
    }

    @ViewBuilder
    private var settingsControl: some View {
        Button(action: { openSettings() }) {
            Image(systemName: "gearshape")
        }
        .help("Settings (Cmd+,)")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens app settings")
    }

    @ViewBuilder
    private var helpControl: some View {
        Button(action: { showEditorHelp = true }) {
            Image(systemName: "questionmark.circle")
        }
        .help("Toolbar Help")
        .accessibilityLabel("Toolbar Help")
        .accessibilityHint("Opens help for all toolbar actions")
    }

    @ViewBuilder
    private var languagePickerControl: some View {
        Menu {
            let selectedLanguage = currentLanguagePickerBinding.wrappedValue
            Button {
                currentLanguagePickerBinding.wrappedValue = selectedLanguage
            } label: {
                Label(languageLabel(for: selectedLanguage), systemImage: "checkmark")
            }
            Button(action: { presentLanguageSearchSheet() }) {
                Label("Language…", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            ForEach(languageOptions.filter { $0 != selectedLanguage }, id: \.self) { lang in
                Button {
                    currentLanguagePickerBinding.wrappedValue = lang
                } label: {
                    Text(languageLabel(for: lang))
                }
            }
        } label: {
            Text(toolbarLanguageLabel(for: currentLanguagePickerBinding.wrappedValue))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
#if os(visionOS)
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(NeonUIStyle.accentBlue, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .frame(width: 74)
#elseif os(iOS)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(iOSToolbarTintColor.opacity(0.35), lineWidth: 1)
                )
                .frame(minWidth: isIPadToolbarLayout ? 120 : iPhoneLanguagePickerWidth)
#endif
        }
        .labelsHidden()
#if os(iOS)
        .frame(minWidth: isIPadToolbarLayout ? 132 : iPhoneLanguagePickerWidth)
#endif
        .help("Language")
        .accessibilityLabel("Language picker")
        .accessibilityHint("Choose syntax language for the current tab")
#if os(iOS)
        .accessibilityValue(languageLabel(for: currentLanguagePickerBinding.wrappedValue))
#endif
        .layoutPriority(2)
#if os(visionOS)
        .tint(Color.white.opacity(0.96))
        .menuStyle(.button)
        .buttonStyle(.plain)
#elseif os(iOS)
        .tint(iOSToolbarTintColor)
        .menuStyle(.button)
#endif
    }

    @ViewBuilder
    private var clearEditorControl: some View {
        Button(action: {
            requestClearEditorContent()
        }) {
            Image(systemName: "eraser")
        }
        .help("Clear Editor")
    }

    @ViewBuilder
    private var insertTemplateControl: some View {
        Button(action: { insertTemplateForCurrentLanguage() }) {
            Image(systemName: "doc.badge.plus")
        }
        .help("Insert Template for Current Language")
    }

    @ViewBuilder
    private var lineWrapControl: some View {
        Button(action: {
            viewModel.isLineWrapEnabled.toggle()
        }) {
            Image(systemName: "text.justify")
        }
        .help("Enable Wrap / Disable Wrap (Cmd+Opt+L)")
        .accessibilityLabel("Line Wrap")
        .accessibilityValue(viewModel.isLineWrapEnabled ? "On" : "Off")
        .accessibilityHint("Wraps long lines within the editor")
    }

    @ViewBuilder
    private var openFileControl: some View {
        Button(action: { openFileFromToolbar() }) {
            Image(systemName: "folder")
        }
        .help("Open File… (Cmd+O)")
        .accessibilityLabel("Open file")
        .accessibilityHint("Opens a file picker")
    }

    @ViewBuilder
    private var undoControl: some View {
        Button(action: { undoFromToolbar() }) {
            Image(systemName: "arrow.uturn.backward")
        }
        .help("Undo (Cmd+Z)")
    }

    @ViewBuilder
    private var saveFileControl: some View {
        Button(action: { saveCurrentTabFromToolbar() }) {
            Image(systemName: "square.and.arrow.down")
        }
        .disabled(viewModel.selectedTab == nil || viewModel.selectedTab?.isReadOnlyPreview == true)
        .help("Save File (Cmd+S)")
        .accessibilityLabel("Save file")
        .accessibilityHint("Saves the current tab")
    }

    @ViewBuilder
    private var saveFileAsControl: some View {
        Button(action: { saveCurrentTabAsFromToolbar() }) {
            Image(systemName: "square.and.arrow.down.on.square")
        }
        .disabled(viewModel.selectedTab == nil)
        .help("Save As… (Cmd+Shift+S)")
        .accessibilityLabel("Save As")
        .accessibilityHint("Saves the current tab to a new file")
    }

    @ViewBuilder
    private var closeAllTabsControl: some View {
        Button(action: { requestCloseAllTabsFromToolbar() }) {
            Image(systemName: "xmark.square")
        }
        .disabled(viewModel.tabs.isEmpty)
        .help("Close All Tabs")
        .accessibilityLabel("Close all tabs")
        .accessibilityHint("Closes every open tab")
    }

    @ViewBuilder
    private var fontDecreaseControl: some View {
        Button(action: { adjustEditorFontSize(-1) }) {
            Image(systemName: "textformat.size.smaller")
        }
        .help("Decrease Font Size")
    }

    @ViewBuilder
    private var fontIncreaseControl: some View {
        Button(action: { adjustEditorFontSize(1) }) {
            Image(systemName: "textformat.size.larger")
        }
        .help("Increase Font Size")
    }

    @ViewBuilder
    private var findReplaceControl: some View {
        Button(action: { showFindReplace = true }) {
            Image(systemName: "magnifyingglass")
        }
        .help("Find & Replace (Cmd+F)")
    }

    @ViewBuilder
    private var findInFilesControl: some View {
        Button(action: { requestFindInFilesFromToolbar() }) {
            Image(systemName: "text.magnifyingglass")
        }
        .help("Find in Files (Cmd+Shift+F)")
        .accessibilityLabel("Find in Files")
        .accessibilityHint("Searches across files in the current project")
    }

    @ViewBuilder
    private var compareDiskControl: some View {
        Button(action: { compareCurrentTabAgainstDisk() }) {
            Image(systemName: "doc.text.magnifyingglass")
        }
        .disabled(viewModel.selectedTab?.fileURL == nil)
        .help("Compare with Disk")
        .accessibilityLabel("Compare with Disk")
        .accessibilityHint("Compares the current tab with its saved file")
    }

    @ViewBuilder
    private var compareTabsControl: some View {
        Button(action: { presentCompareTabsPicker() }) {
            Image(systemName: "rectangle.split.2x1")
        }
        .disabled(viewModel.selectedTab == nil)
        .help("Compare Open Tabs")
        .accessibilityLabel("Compare Open Tabs")
        .accessibilityHint("Choose another open tab to compare with the current tab")
    }

    @ViewBuilder
    private var splitEditorControl: some View {
        Button(action: { toggleSplitEditorFromToolbar() }) {
            Image(systemName: splitSecondaryTabID == nil ? "rectangle.split.2x1" : "rectangle")
        }
        .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)
        .help(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor")
        .accessibilityLabel(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor")
        .accessibilityHint("Shows the current tab and another open tab at the same time")
    }

    @ViewBuilder
    private var codeCompletionControl: some View {
        Button(action: {
            toggleAutoCompletion()
        }) {
            Image(systemName: "bolt.horizontal.circle")
                .symbolVariant(isAutoCompletionEnabled ? .fill : .none)
        }
        .help(isAutoCompletionEnabled ? "Disable Code Completion" : "Enable Code Completion")
        .accessibilityLabel("Code Completion")
        .accessibilityValue(isAutoCompletionEnabled ? "On" : "Off")
        .accessibilityHint("Offers completion suggestions while editing")
    }

    @ViewBuilder
    private var performanceModeControl: some View {
        Button(action: {
            forceLargeFileMode.toggle()
            updateLargeFileMode(for: currentContentBinding.wrappedValue)
            recordDiagnostic("Toolbar toggled performance mode: \(forceLargeFileMode ? "on" : "off")")
        }) {
            Image(systemName: forceLargeFileMode ? "speedometer" : "speedometer")
                .symbolVariant(forceLargeFileMode ? .fill : .none)
        }
        .help(forceLargeFileMode ? "Disable Performance Mode" : "Enable Performance Mode")
        .accessibilityLabel("Performance Mode")
        .accessibilityValue(forceLargeFileMode ? "On" : "Off")
        .accessibilityHint("Reduces expensive editor analysis for large documents")
    }

    @ViewBuilder
    private var markdownPreviewControl: some View {
        Button(action: {
            togglePreviewFromToolbar()
        }) {
            Image(systemName: previewToolbarIconName)
        }
        .foregroundStyle(isPreviewVisible ? Color.accentColor : Color.primary)
        .disabled(!isPreviewSupportedDocument)
        .help(isPreviewVisible ? "Hide \(previewTitle)" : "Show \(previewTitle)")
        .accessibilityLabel(previewTitle)
    }

    @ViewBuilder
    private var markdownProjectPreviewControl: some View {
        Button {
            toggleMarkdownProjectPreviewFromToolbar()
        } label: {
            Image(systemName: isMarkdownProjectPreviewPresented ? "square.grid.2x2.fill" : "square.grid.2x2")
        }
        .foregroundStyle(isMarkdownProjectPreviewPresented ? Color.accentColor : Color.primary)
        .disabled(projectRootFolderURL == nil || !hasMarkdownOrPDFProjectPreviewFiles || isSafeModeActive)
        .help(isMarkdownProjectPreviewPresented ? "Hide Project Cards" : "Show Project Cards")
        .accessibilityLabel("Project Cards")
        .accessibilityHint("Shows Markdown and PDF files from the current project as preview cards")
    }

    @ViewBuilder
    private var indentationGuidesControl: some View {
        Button(action: {
            showIndentationGuides.toggle()
        }) {
            Image(systemName: "text.alignleft")
                .symbolVariant(showIndentationGuides ? .fill : .none)
        }
        .help(showIndentationGuides ? "Hide Indentation Guides" : "Show Indentation Guides")
        .accessibilityLabel("Indentation Guides")
        .accessibilityValue(showIndentationGuides ? "Shown" : "Hidden")
        .accessibilityHint("Toggles light indentation guide lines in the editor")
    }

    @ViewBuilder
    private var markdownPreviewExportControl: some View {
        if showMarkdownPreviewPane && isMarkdownPreviewDocument {
            Menu {
                markdownPreviewExportToolbarMenuContent
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help(NSLocalizedString("Markdown Preview Export Options", comment: "Toolbar help for markdown preview export options"))
            .accessibilityLabel(NSLocalizedString("Export Markdown preview as PDF", comment: "Accessibility label for markdown preview export button"))
        }
    }

    @ViewBuilder
    private var markdownPreviewStyleControl: some View {
#if os(visionOS)
        EmptyView()
#else
        if showMarkdownPreviewPane && isMarkdownPreviewDocument {
            Menu {
                markdownPreviewTemplateMenuItems
            } label: {
                Image(systemName: "paintbrush")
            }
            .help(NSLocalizedString("Markdown Preview Template", comment: "Toolbar help for markdown preview style menu"))
            .accessibilityLabel(NSLocalizedString("Markdown Preview Template", comment: "Accessibility label for markdown preview style menu"))
        }
#endif
    }

    @ViewBuilder
    private var markdownPreviewExportToolbarMenuContent: some View {
        Button(action: { exportMarkdownPreviewPDF() }) {
            Label("Export PDF", systemImage: "square.and.arrow.down")
        }
        .help("Export Markdown Preview as PDF")

        Menu {
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.paginatedFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.paginatedFit.rawValue {
                    Label("Paginated Fit", systemImage: "checkmark")
                } else {
                    Text("Paginated Fit")
                }
            }
            .help("Use Paginated Fit PDF Export")
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.onePageFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.onePageFit.rawValue {
                    Label("One Page Fit", systemImage: "checkmark")
                } else {
                    Text("One Page Fit")
                }
            }
            .help("Use One Page Fit PDF Export")
        } label: {
            Label("PDF Mode", systemImage: "doc.text")
        }
        .help("Choose PDF Export Mode")

        Menu {
            markdownPreviewTemplateMenuItems
        } label: {
            Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
        }
        .help(NSLocalizedString("Choose Markdown Preview Style", comment: "Toolbar help for markdown preview style picker"))

        Divider()

        Button(action: { copyMarkdownPreviewHTML() }) {
            Label("Copy HTML", systemImage: "doc.on.doc")
        }
        .help("Copy Markdown Preview HTML")
        Button(action: { copyMarkdownPreviewMarkdown() }) {
            Label("Copy Markdown", systemImage: "doc.on.clipboard")
        }
        .help("Copy Markdown Source")
    }

    @ViewBuilder
    private var keyboardAccessoryControl: some View {
        Button(action: {
            toggleKeyboardAccessoryBar()
        }) {
            Image(systemName: showKeyboardAccessoryBarIOS ? "keyboard.chevron.compact.down.fill" : "keyboard.chevron.compact.down")
        }
        .help(showKeyboardAccessoryBarIOS ? "Hide Keyboard Snippet Bar" : "Show Keyboard Snippet Bar")
        .accessibilityLabel("Keyboard Snippet Bar")
    }

    @ViewBuilder
    private var hideKeyboardControl: some View {
        Button(action: { dismissKeyboard() }) {
            Image(systemName: "keyboard.chevron.compact.down")
        }
        .help("Hide Keyboard")
        .accessibilityLabel("Hide Keyboard")
        .accessibilityHint("Dismisses the software keyboard")
    }

    @ViewBuilder
    private var welcomeTourControl: some View {
        Button(action: {
            showWelcomeTour = true
        }) {
            Image(systemName: "sparkles.rectangle.stack")
        }
        .help("Welcome Tour")
    }

    @ViewBuilder
    private var translucentWindowControl: some View {
        Button(action: {
            enableTranslucentWindow.toggle()
            UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
            NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
        }) {
            Image(systemName: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
        }
        .help("Toggle Translucent Window Background")
        .accessibilityLabel("Translucent Window Background")
        .accessibilityValue(enableTranslucentWindow ? "On" : "Off")
    }

    @ViewBuilder
    private var codeSnapshotControl: some View {
        Button(action: { presentCodeSnapshotComposer() }) {
            Image(systemName: "camera.viewfinder")
        }
        .disabled(!canCreateCodeSnapshot)
        .help("Create Code Snapshot from Selection")
        .accessibilityLabel("Create Code Snapshot")
    }

    @ViewBuilder
    private var toolbarIconColorControl: some View {
        Button(action: { toolbarIconsBlueIOS.toggle() }) {
            Image(systemName: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
        }
        .help("Blue Toolbar Icons")
        .accessibilityLabel("Blue Toolbar Icons")
        .accessibilityValue(toolbarIconsBlueIOS ? "On" : "Off")
        .accessibilityHint("Toggles blue toolbar icon coloring")
    }

    // MARK: - iPad Toolbar Composition

    private func iPadToolbarActionControl(_ action: IPadToolbarAction) -> AnyView {
        switch action {
        case .openFile: AnyView(openFileControl)
        case .undo: AnyView(undoControl)
        case .newTab: AnyView(newTabControl)
        case .closeAllTabs: AnyView(closeAllTabsControl)
        case .saveFile: AnyView(saveFileControl)
        case .saveFileAs: AnyView(saveFileAsControl)
        case .codeSnapshot: AnyView(codeSnapshotControl)
        case .markdownPreview: AnyView(markdownPreviewControl)
        case .markdownProjectPreview: AnyView(markdownProjectPreviewControl)
        case .markdownPreviewExport: AnyView(markdownPreviewExportControl)
        case .markdownPreviewStyle: AnyView(markdownPreviewStyleControl)
        case .codeMinimap: AnyView(codeMinimapControl)
        case .indentationGuides: AnyView(indentationGuidesControl)
        case .fontDecrease: AnyView(fontDecreaseControl)
        case .fontIncrease: AnyView(fontIncreaseControl)
        case .toggleSidebar: AnyView(toggleSidebarControl)
        case .toggleProjectSidebar: AnyView(toggleProjectSidebarControl)
        case .findReplace: AnyView(findReplaceControl)
        case .findInFiles: AnyView(findInFilesControl)
        case .compareDisk: AnyView(compareDiskControl)
        case .compareTabs: AnyView(compareTabsControl)
        case .gitChanges: AnyView(gitChangesControl)
        case .splitEditor: AnyView(splitEditorControl)
        case .editorLayout: AnyView(mobileEditorLayoutControl)
        case .previewActions: AnyView(mobilePreviewActionsControl)
        case .settings: AnyView(settingsControl)
        case .help: AnyView(helpControl)
        case .codeCompletion: AnyView(codeCompletionControl)
        case .performanceMode: AnyView(performanceModeControl)
        case .lineWrap: AnyView(lineWrapControl)
        case .keyboardAccessory: AnyView(keyboardAccessoryControl)
        case .hideKeyboard: AnyView(hideKeyboardControl)
        case .clearEditor: AnyView(clearEditorControl)
        case .insertTemplate: AnyView(insertTemplateControl)
        case .brainDump: AnyView(brainDumpControl)
        case .welcomeTour: AnyView(welcomeTourControl)
        case .translucentWindow: AnyView(translucentWindowControl)
        case .toolbarIconColor: AnyView(toolbarIconColorControl)
        }
    }

    @ViewBuilder
    private var iPadOverflowMenuControl: some View {
        iPadOverflowMenuControl(actions: iPadOverflowActions)
    }

    @ViewBuilder
    private func iPadOverflowMenuControl(actions: [IPadToolbarAction]) -> some View {
        Menu {
                ForEach(actions, id: \.self) { action in
                    switch action {
                    case .openFile:
                        Button(action: { openFileFromToolbar() }) {
                            Label("Open File…", systemImage: "folder")
                        }
                    case .undo:
                        Button(action: { undoFromToolbar() }) {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                    case .newTab:
                        Button(action: { viewModel.addNewTab() }) {
                            Label("New Tab", systemImage: "plus.square.on.square")
                        }
                    case .closeAllTabs:
                        Button(action: { requestCloseAllTabsFromToolbar() }) {
                            Label("Close All Tabs", systemImage: "xmark.square")
                        }
                        .disabled(viewModel.tabs.isEmpty)
                    case .saveFile:
                        Button(action: { saveCurrentTabFromToolbar() }) {
                            Label("Save File", systemImage: "square.and.arrow.down")
                        }
                        .disabled(viewModel.selectedTab == nil)
                    case .saveFileAs:
                        Button(action: { saveCurrentTabAsFromToolbar() }) {
                            Label("Save As…", systemImage: "square.and.arrow.down.on.square")
                        }
                        .disabled(viewModel.selectedTab == nil)
                    case .codeSnapshot:
                        Button(action: { presentCodeSnapshotComposer() }) {
                            Label("Create Code Snapshot", systemImage: "camera.viewfinder")
                        }
                        .disabled(!canCreateCodeSnapshot)
                    case .markdownPreview:
                        Button(action: { togglePreviewFromToolbar() }) {
                            Label(
                                previewTitle,
                                systemImage: previewToolbarIconName
                            )
                        }
                        .disabled(!isPreviewSupportedDocument)
                    case .markdownProjectPreview:
                        markdownProjectPreviewControl
                    case .markdownPreviewExport:
                        markdownPreviewExportToolbarMenuContent
                    case .markdownPreviewStyle:
                        Menu {
                            markdownPreviewTemplateMenuItems
                        } label: {
                            Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
                        }
                    case .codeMinimap:
                        if supportsCodeMinimap(language: currentLanguage) {
                            Button(action: { showCodeMinimap.toggle() }) {
                                Label(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap", systemImage: showCodeMinimap ? "map.fill" : "map")
                            }
                        }
                    case .indentationGuides:
                        Button(action: { showIndentationGuides.toggle() }) {
                            Label(showIndentationGuides ? "Hide Indentation Guides" : "Show Indentation Guides", systemImage: "text.alignleft")
                        }
                    case .fontDecrease:
                        Button(action: { adjustEditorFontSize(-1) }) {
                            Label("Font -", systemImage: "textformat.size.smaller")
                        }
                    case .fontIncrease:
                        Button(action: { adjustEditorFontSize(1) }) {
                            Label("Font +", systemImage: "textformat.size.larger")
                        }
                    case .toggleSidebar:
                        Button(action: { toggleSidebarFromToolbar() }) {
                            Label("Toggle Sidebar", systemImage: "sidebar.left")
                        }
                    case .toggleProjectSidebar:
                        Button(action: { toggleProjectSidebarFromToolbar() }) {
                            Label("Toggle Project Structure Sidebar", systemImage: "sidebar.right")
                        }
                    case .findReplace:
                        Button(action: { showFindReplace = true }) {
                            Label("Find & Replace", systemImage: "magnifyingglass")
                        }
                    case .findInFiles:
                        Button(action: { requestFindInFilesFromToolbar() }) {
                            Label("Find in Files…", systemImage: "text.magnifyingglass")
                        }
                    case .compareDisk:
                        Button(action: { compareCurrentTabAgainstDisk() }) {
                            Label("Compare with Disk", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(viewModel.selectedTab?.fileURL == nil)
                    case .compareTabs:
                        Button(action: { presentCompareTabsPicker() }) {
                            Label("Compare Open Tabs…", systemImage: "rectangle.split.2x1")
                        }
                        .disabled(viewModel.selectedTab == nil)
                    case .gitChanges:
                        gitChangesControl
                    case .splitEditor:
                        Button(action: { toggleSplitEditorFromToolbar() }) {
                            Label(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor", systemImage: "rectangle.split.2x1")
                        }
                        .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)
                    case .editorLayout:
                        mobileEditorLayoutControl
                    case .previewActions:
                        mobilePreviewActionsControl
                    case .settings:
                        Button(action: { openSettings() }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                    case .help:
                        Button(action: { showEditorHelp = true }) {
                            Label("Toolbar Help", systemImage: "questionmark.circle")
                        }
                    case .codeCompletion:
                        Button(action: { toggleAutoCompletion() }) {
                            Label(isAutoCompletionEnabled ? "Disable Code Completion" : "Enable Code Completion", systemImage: "text.badge.plus")
                        }
                    case .performanceMode:
                        Button(action: {
                            forceLargeFileMode.toggle()
                            updateLargeFileMode(for: currentContentBinding.wrappedValue)
                        }) {
                            Label(forceLargeFileMode ? "Disable Performance Mode" : "Enable Performance Mode", systemImage: "speedometer")
                        }
                    case .lineWrap:
                        Button(action: { viewModel.isLineWrapEnabled.toggle() }) {
                            Label("Enable Wrap / Disable Wrap", systemImage: "text.justify")
                        }
                    case .keyboardAccessory:
                        Button(action: { toggleKeyboardAccessoryBar() }) {
                            Label(
                                showKeyboardAccessoryBarIOS ? "Hide Keyboard Snippet Bar" : "Show Keyboard Snippet Bar",
                                systemImage: showKeyboardAccessoryBarIOS ? "keyboard.chevron.compact.down.fill" : "keyboard.chevron.compact.down"
                            )
                        }
                    case .hideKeyboard:
                        Button(action: { dismissKeyboard() }) {
                            Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
                        }
                    case .clearEditor:
                        Button(action: { requestClearEditorContent() }) {
                            Label("Clear Editor", systemImage: "eraser")
                        }
                    case .insertTemplate:
                        Button(action: { insertTemplateForCurrentLanguage() }) {
                            Label("Insert Template", systemImage: "doc.badge.plus")
                        }
                    case .brainDump:
                        Button(action: {
                            toggleBrainDumpModeIOSAware()
                        }) {
                            Label("Brain Dump Mode", systemImage: "note.text")
                        }
                    case .welcomeTour:
                        Button(action: { showWelcomeTour = true }) {
                            Label("Welcome Tour", systemImage: "sparkles.rectangle.stack")
                        }
                    case .translucentWindow:
                        Button(action: {
                            enableTranslucentWindow.toggle()
                            UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
                            NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
                        }) {
                            Label("Translucent Window Background", systemImage: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
                        }
                    case .toolbarIconColor:
                        Button(action: { toolbarIconsBlueIOS.toggle() }) {
                            Label("Blue Toolbar Icons", systemImage: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 40, height: 40, alignment: .center)
                .contentShape(Rectangle())
        }
        .help("More Actions")
        .frame(minWidth: 44, minHeight: 44)
    }

    private func iOSOverflowItem<Content: View>(
        _ actionID: String,
        @ViewBuilder content: () -> Content
    ) -> AnyView {
        if shouldShowIOSOverflowAction(actionID) {
            AnyView(content())
        } else {
            AnyView(EmptyView())
        }
    }

    private func shouldShowIOSOverflowAction(_ actionID: String) -> Bool {
        iPhoneMoreActions.contains { $0.rawValue == actionID }
    }

    @ViewBuilder
    private var moreActionsControl: some View {
        Menu {
            iOSOverflowItem("settings") { Button(action: {
                openSettings()
            }) {
                Label("Settings", systemImage: "gearshape")
            } }

            iOSOverflowItem("help") { Button(action: {
                showEditorHelp = true
            }) {
                Label("Toolbar Help", systemImage: "questionmark.circle")
            } }

            iOSOverflowItem("clearEditor") { Button(action: {
                requestClearEditorContent()
            }) {
                Label("Clear Editor", systemImage: "eraser")
            } }

            iOSOverflowItem("insertTemplate") { Button(action: { insertTemplateForCurrentLanguage() }) {
                Label("Insert Template", systemImage: "doc.badge.plus")
            } }

            Button(action: { presentLanguageSearchSheet() }) {
                Label("Language…", systemImage: "magnifyingglass")
            }

            iOSOverflowItem("newTab") { Button(action: { viewModel.addNewTab() }) {
                Label("New Tab", systemImage: "plus.square.on.square")
            } }

            iOSOverflowItem("openFile") { Button(action: { openFileFromToolbar() }) {
                Label("Open File…", systemImage: "folder")
            } }

            iOSOverflowItem("undo") { Button(action: { undoFromToolbar() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            } }

            iOSOverflowItem("saveFile") { Button(action: { saveCurrentTabFromToolbar() }) {
                Label("Save File", systemImage: "square.and.arrow.down")
            } }
            .disabled(viewModel.selectedTab == nil)

            iOSOverflowItem("codeSnapshot") { Button(action: { presentCodeSnapshotComposer() }) {
                Label("Create Code Snapshot", systemImage: "camera.viewfinder")
            } }
            .disabled(!canCreateCodeSnapshot)

            iOSOverflowItem("markdownPreview") { Button(action: { togglePreviewFromToolbar() }) {
                Label(
                    previewTitle,
                    systemImage: previewToolbarIconName
                )
            } }
            .disabled(!isPreviewSupportedDocument)

            iOSOverflowItem("markdownProjectPreview") {
                Button(action: { toggleMarkdownProjectPreviewFromToolbar() }) {
                    Label(
                        isMarkdownProjectPreviewPresented ? "Hide Project Cards" : "Show Project Cards",
                        systemImage: isMarkdownProjectPreviewPresented ? "square.grid.2x2.fill" : "square.grid.2x2"
                    )
                }
                .disabled(projectRootFolderURL == nil || !hasMarkdownOrPDFProjectPreviewFiles || isSafeModeActive)
            }

            iOSOverflowItem("markdownPreviewStyle") {
                if showMarkdownPreviewPane && isMarkdownPreviewDocument {
                    Menu {
                        markdownPreviewTemplateMenuItems
                    } label: {
                        Label("Preview Style", systemImage: "paintbrush")
                    }
                }
            }

            if supportsCodeMinimap(language: currentLanguage) {
                iOSOverflowItem("codeMinimap") { Button(action: { showCodeMinimap.toggle() }) {
                    Label(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap", systemImage: showCodeMinimap ? "map.fill" : "map")
                } }
            }

            iOSOverflowItem("indentationGuides") { Button(action: { showIndentationGuides.toggle() }) {
                Label(showIndentationGuides ? "Hide Indentation Guides" : "Show Indentation Guides", systemImage: "text.alignleft")
            } }

            if showMarkdownPreviewPane && isMarkdownPreviewDocument {
                iOSOverflowItem("markdownPreviewExport") {
                    Menu {
                        markdownPreviewExportToolbarMenuContent
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.down")
                    }
                }
            }

            iOSOverflowItem("closeAllTabs") { Button(action: { requestCloseAllTabsFromToolbar() }) {
                Label("Close All Tabs", systemImage: "xmark.square")
            } }
            .disabled(viewModel.tabs.isEmpty)

            iOSOverflowItem("saveFileAs") { Button(action: { saveCurrentTabAsFromToolbar() }) {
                Label("Save As…", systemImage: "square.and.arrow.down.on.square")
            } }
            .disabled(viewModel.selectedTab == nil)

            iOSOverflowItem("toggleSidebar") { Button(action: { toggleSidebarFromToolbar() }) {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            } }

            iOSOverflowItem("toggleProjectSidebar") { Button(action: { toggleProjectSidebarFromToolbar() }) {
                Label("Toggle Project Structure Sidebar", systemImage: "sidebar.right")
            } }

            iOSOverflowItem("findReplace") { Button(action: { showFindReplace = true }) {
                Label("Find & Replace", systemImage: "magnifyingglass")
            } }

            iOSOverflowItem("findInFiles") { Button(action: { requestFindInFilesFromToolbar() }) {
                Label("Find in Files…", systemImage: "text.magnifyingglass")
            } }

            iOSOverflowItem("compareDisk") { Button(action: { compareCurrentTabAgainstDisk() }) {
                Label("Compare with Disk", systemImage: "doc.text.magnifyingglass")
            } }
            .disabled(viewModel.selectedTab?.fileURL == nil)

            iOSOverflowItem("compareTabs") { Button(action: { presentCompareTabsPicker() }) {
                Label("Compare Open Tabs…", systemImage: "rectangle.split.2x1")
            } }
            .disabled(viewModel.selectedTab == nil)

            iOSOverflowItem("splitEditor") { Button(action: { toggleSplitEditorFromToolbar() }) {
                Label(
                    splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor",
                    systemImage: "rectangle.split.2x1"
                )
            } }
            .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)

            iOSOverflowItem("editorLayout") {
                Menu {
                    ForEach(EditorLayoutPreset.allCases) { preset in
                        Button(action: { applyEditorLayoutPreset(preset) }) {
                            Label(preset.title, systemImage: preset.symbol)
                            if editorLayoutPreset == preset { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    Label("Editor Layout", systemImage: "rectangle.3.group")
                }
            }

            iOSOverflowItem("previewActions") {
                Menu {
                    Button(action: { togglePreviewFromToolbar() }) {
                        Label(isPreviewVisible ? "Hide \(previewTitle)" : "Show \(previewTitle)", systemImage: previewToolbarIconName)
                    }
                    .disabled(!isPreviewSupportedDocument)

                    Button(action: { toggleMarkdownProjectPreviewFromToolbar() }) {
                        Label(isMarkdownProjectPreviewPresented ? "Hide Project Cards" : "Show Project Cards", systemImage: "square.grid.2x2")
                    }
                    .disabled(projectRootFolderURL == nil || !hasMarkdownOrPDFProjectPreviewFiles || isSafeModeActive)
                } label: {
                    Label("Preview Actions", systemImage: isPreviewVisible ? "eye.fill" : "eye")
                }
            }

            iOSOverflowItem("gitChanges") { Button(action: { showGitChangesEditor.toggle() }) {
                Label(
                    showGitChangesEditor ? "Close Git Changes" : "Open Git Changes",
                    systemImage: "arrow.triangle.branch"
                )
            } }

            iOSOverflowItem("lineWrap") { Button(action: { viewModel.isLineWrapEnabled.toggle() }) {
                Label("Enable Wrap / Disable Wrap", systemImage: "text.justify")
            } }

            iOSOverflowItem("fontDecrease") { Button(action: { adjustEditorFontSize(-1) }) {
                Label("Font -", systemImage: "textformat.size.smaller")
            } }

            iOSOverflowItem("fontIncrease") { Button(action: { adjustEditorFontSize(1) }) {
                Label("Font +", systemImage: "textformat.size.larger")
            } }

            iOSOverflowItem("codeCompletion") { Button(action: { toggleAutoCompletion() }) {
                Label(isAutoCompletionEnabled ? "Disable Code Completion" : "Enable Code Completion", systemImage: "text.badge.plus")
            } }

            iOSOverflowItem("keyboardAccessory") { Button(action: {
                toggleKeyboardAccessoryBar()
            }) {
                Label(
                    showKeyboardAccessoryBarIOS ? "Hide Keyboard Snippet Bar" : "Show Keyboard Snippet Bar",
                    systemImage: showKeyboardAccessoryBarIOS ? "keyboard.chevron.compact.down.fill" : "keyboard.chevron.compact.down"
                )
            } }

            iOSOverflowItem("hideKeyboard") { Button(action: { dismissKeyboard() }) {
                Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
            } }

            iOSOverflowItem("performanceMode") { Button(action: {
                forceLargeFileMode.toggle()
                updateLargeFileMode(for: currentContentBinding.wrappedValue)
            }) {
                Label(forceLargeFileMode ? "Disable Performance Mode" : "Enable Performance Mode", systemImage: "speedometer")
            } }

            iOSOverflowItem("brainDump") { Button(action: {
                toggleBrainDumpModeIOSAware()
            }) {
                Label("Brain Dump Mode", systemImage: "note.text")
            } }
            
            iOSOverflowItem("welcomeTour") { Button(action: {
                showWelcomeTour = true
            }) {
                Label("Welcome Tour", systemImage: "sparkles.rectangle.stack")
            } }

            iOSOverflowItem("translucentWindow") { Button(action: {
                enableTranslucentWindow.toggle()
                UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
                NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
            }) {
                Label("Translucent Window Background", systemImage: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
            } }

#if os(iOS)
            iOSOverflowItem("toolbarIconColor") { Button(action: {
                toolbarIconsBlueIOS.toggle()
            }) {
                Label("Blue Toolbar Icons", systemImage: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
            } }
#endif

        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More Actions")
        .accessibilityLabel("More Actions")
    }

    // MARK: - iPhone Toolbar Composition

    @ViewBuilder
    private var iPhonePrimaryToolbarCluster: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    languagePickerControl
                    toolbarPresetMenuControl
                    ForEach(visibleIOSPrimaryToolbarActions, id: \.self) { action in
                        iOSPrimaryToolbarActionControl(action)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !iPhoneMoreActions.isEmpty {
                moreActionsControl
                    .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    var iPhoneUnifiedToolbarRow: some View {
        iPhonePrimaryToolbarCluster
            .frame(maxWidth: .infinity, alignment: .center)
            .tint(iOSToolbarTintColor)
    }

    @ViewBuilder
    private var iPadDistributedToolbarControls: some View {
        languagePickerControl
        ForEach(visibleIPadToolbarActions, id: \.self) { action in
            iPadToolbarActionControl(action)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var iPadScrollableToolbarControls: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    toolbarPresetMenuControl
                    iPadDistributedToolbarControls
                }
                .padding(.leading, 24)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !iPadOverflowActions.isEmpty {
                iPadOverflowMenuControl
                    .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 52)
        .accessibilityLabel("Editor toolbar")
        .accessibilityHint("Swipe horizontally to reveal more editor actions")
    }

    @ViewBuilder
    var iPadUnifiedToolbarRow: some View {
        GlassSurface(
            enabled: shouldUseLiquidGlass,
            material: primaryGlassMaterial,
            fallbackColor: toolbarFallbackColor,
            shape: .capsule,
            chromeStyle: iOSToolbarChromeStyle
        ) {
            iPadScrollableToolbarControls
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .scaleEffect(toolbarDensityScale, anchor: .center)
        .opacity(toolbarDensityOpacity)
        .animation(.easeOut(duration: 0.18), value: toolbarDensityScale)
        .animation(.easeOut(duration: 0.18), value: toolbarDensityOpacity)
        .tint(iOSToolbarTintColor)
    }

#if os(visionOS)
    @ViewBuilder
    private var visionOSToolbarControls: some View {
        GeometryReader { proxy in
            let width = proxy.size.width > 0 ? proxy.size.width : visionOSToolbarWidth
            let visibleActions = visibleVisionOSToolbarActions(for: width)
            let overflowActions = visionOSOverflowActions(visibleActions: visibleActions)
            let spacing = visionOSToolbarSpacing(
                for: width,
                visibleActionCount: visibleActions.count,
                showsOverflow: !overflowActions.isEmpty
            )

            HStack(spacing: spacing) {
                languagePickerControl

                ForEach(visibleActions, id: \.self) { action in
                    iPadToolbarActionControl(action)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }

                Spacer(minLength: 0)

                if !overflowActions.isEmpty {
                    iPadOverflowMenuControl(actions: overflowActions)
                }
            }
            .frame(width: width, height: 44, alignment: .center)
        }
        .frame(width: visionOSToolbarWidth, height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor toolbar")
    }
#endif
#endif

    // MARK: - Toolbar Labels and Scene Toolbar

#if os(macOS)
    @ViewBuilder
    private var macUtilitiesMenuControl: some View {
        Group {
            Button(action: { openSettings() }) {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Settings (Cmd+,)")
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens app settings")

            Button(action: { showEditorHelp = true }) {
                Label("Toolbar Help", systemImage: "questionmark.circle")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Toolbar Help")
            .accessibilityLabel("Toolbar Help")
            .accessibilityHint("Opens help for all toolbar actions")
        }
    }

    @ViewBuilder
    private var editorLayoutPresetControl: some View {
        Menu {
            ForEach(EditorLayoutPreset.allCases) { preset in
                Button(action: { applyEditorLayoutPreset(preset) }) {
                    Label(preset.title, systemImage: preset.symbol)
                    if editorLayoutPreset == preset { Image(systemName: "checkmark") }
                }
            }
            Divider()
            Button("Preset Details…", systemImage: "info.circle") {
                isEditorLayoutPresetPickerPresented = true
            }
        } label: {
            Image(systemName: "rectangle.3.group")
        }
        .help("Editor Layout Presets")
        .accessibilityLabel("Editor layout presets")
        .accessibilityValue(editorLayoutPreset.title)
        .popover(isPresented: $isEditorLayoutPresetPickerPresented, arrowEdge: .bottom) {
            editorLayoutPresetChooser
        }
    }

    private var editorLayoutPresetChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Editor Layout", systemImage: "rectangle.3.group")
                .font(.headline)
            Text("Choose a focused workspace. Presets change presentation only; your files and content stay untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(EditorLayoutPreset.allCases) { preset in
                Button {
                    applyEditorLayoutPreset(preset)
                    isEditorLayoutPresetPickerPresented = false
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: preset.symbol)
                            .font(.title3)
                            .frame(width: 24)
                            .foregroundStyle(editorLayoutPreset == preset ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if editorLayoutPreset == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(preset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preset.detailLines.joined(separator: "  •  "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        editorLayoutPreset == preset
                            ? Color.accentColor.opacity(0.12)
                            : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.title)
                .accessibilityValue(preset.summary)
                .accessibilityHint("Apply this editor layout")
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    @ViewBuilder
    private var previewActionsControl: some View {
        Menu {
            Button(action: { togglePreviewFromToolbar() }) {
                Label(isPreviewVisible ? "Hide \(previewTitle)" : "Show \(previewTitle)", systemImage: previewToolbarIconName)
            }
            .disabled(!isPreviewSupportedDocument)
            Button(action: openPreviewInSeparateWindow) {
                Label("Open in Separate Window", systemImage: "rectangle.on.rectangle")
            }
            .disabled(!isPreviewSupportedDocument)
            if !isMacToolbarItemVisible("markdownProjectPreview") {
                Divider()
                Button(action: {
                    toggleMarkdownProjectPreviewFromToolbar()
                }) {
                    Label(isMarkdownProjectPreviewPresented ? "Hide Project Cards" : "Show Project Cards", systemImage: "square.grid.2x2")
                }
                .disabled(projectRootFolderURL == nil || !hasMarkdownOrPDFProjectPreviewFiles || isSafeModeActive)
            }
        } label: {
            Image(systemName: isPreviewVisible ? "eye.fill" : "eye")
        }
        .help("Preview options")
        .accessibilityLabel("Preview options")
    }
#endif

    private var gitChangesControl: some View {
        Button(action: { showGitChangesEditor.toggle() }) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(showGitChangesEditor ? Color.accentColor : Color.primary)
                .frame(minWidth: 24, minHeight: 24)
        }
        .help(showGitChangesEditor ? "Close Git Changes" : "Open Git Changes")
        .accessibilityLabel(showGitChangesEditor ? "Close Git Changes" : "Open Git Changes")
    }

    @ToolbarContentBuilder
    var editorToolbarContent: some ToolbarContent {
#if os(visionOS)
        ToolbarItem(placement: .primaryAction) {
            visionOSToolbarControls
        }
#elseif os(iOS)
        if isIPadToolbarLayout && !useIOSUnifiedTopHost {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    GlassSurface(
                        enabled: shouldUseLiquidGlass,
                        material: primaryGlassMaterial,
                        fallbackColor: toolbarFallbackColor,
                        shape: .capsule,
                        chromeStyle: iOSToolbarChromeStyle
                    ) {
                        iPadScrollableToolbarControls
                    }
                    .scaleEffect(toolbarDensityScale, anchor: .center)
                    .opacity(toolbarDensityOpacity)
                    .animation(.easeOut(duration: 0.18), value: toolbarDensityScale)
                    .animation(.easeOut(duration: 0.18), value: toolbarDensityOpacity)
                    .tint(iOSToolbarTintColor)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    GlassSurface(
                        enabled: shouldUseLiquidGlass,
                        material: primaryGlassMaterial,
                        fallbackColor: toolbarFallbackColor,
                        shape: .capsule,
                        chromeStyle: iOSToolbarChromeStyle
                    ) {
                        iPadScrollableToolbarControls
                    }
                    .scaleEffect(toolbarDensityScale, anchor: .center)
                    .opacity(toolbarDensityOpacity)
                    .animation(.easeOut(duration: 0.18), value: toolbarDensityScale)
                    .animation(.easeOut(duration: 0.18), value: toolbarDensityOpacity)
                    .tint(iOSToolbarTintColor)
                }
            }
        }
#elseif os(macOS)
        if isToolbarCollapsed {
        ToolbarItem(placement: .automatic) {
            Button(action: { isToolbarCollapsed.toggle() }) {
                Image(systemName: "chevron.down")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Show Toolbar")
            .accessibilityLabel("Toggle Toolbar")
        }
        }

        if !isToolbarCollapsed {
        ToolbarItemGroup(placement: .primaryAction) {
        Button(action: { isToolbarCollapsed = true }) {
            Image(systemName: "chevron.up")
                .foregroundStyle(macToolbarSymbolColor)
        }
        .help("Collapse Toolbar")
        .accessibilityLabel("Toggle Toolbar")

        macUtilitiesMenuControl
        if isMacToolbarItemVisible("openFile") {
            Button(action: { openFileFromToolbar() }) {
                Label("Open", systemImage: "folder")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Open File… (Cmd+O)")
        }

        if isMacToolbarItemVisible("newTab") {
            Button(action: { viewModel.addNewTab() }) {
                Label("New Tab", systemImage: "plus.square.on.square")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("New Tab (Cmd+T)")
        }

        if isMacToolbarItemVisible("closeAllTabs") {
            Button(action: { requestCloseAllTabsFromToolbar() }) {
                Label("Close All Tabs", systemImage: "xmark.square")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Close All Tabs")
        }

        if isMacToolbarItemVisible("saveFile") {
            Button(action: {
                saveCurrentTabFromToolbar()
            }) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(viewModel.selectedTab == nil)
            .help("Save File (Cmd+S)")
        }

        if isMacToolbarItemVisible("saveFileAs") {
            Button(action: { saveCurrentTabAsFromToolbar() }) {
                Label("Save As", systemImage: "square.and.arrow.down.on.square")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(viewModel.selectedTab == nil)
            .help("Save As… (Cmd+Shift+S)")
        }

        if isMacToolbarItemVisible("newWindow") {
            Button(action: {
                openWindow(value: MacEditorWindowSessionStore.shared.createWindowID())
            }) {
                Label("New Window", systemImage: "macwindow.badge.plus")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("New Window (Cmd+N)")
        }

        if isMacToolbarItemVisible("codeSnapshot") {
            Button(action: { presentCodeSnapshotComposer() }) {
                Label("Code Snapshot", systemImage: "camera.viewfinder")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(!canCreateCodeSnapshot)
            .help("Create Code Snapshot from Selection")
        }

        Button(action: {
            togglePreviewFromToolbar()
        }) {
            Label(previewTitle, systemImage: previewToolbarIconName)
                .foregroundStyle(isPreviewVisible ? Color.accentColor : macToolbarSymbolColor)
        }
        .disabled(!isPreviewSupportedDocument || isSafeModeActive)
        .help(
            isPreviewSupportedDocument
                ? (isPreviewVisible ? "Hide \(previewTitle)" : "Show \(previewTitle)")
                : "Preview is unavailable for this document"
        )
        .accessibilityLabel(previewTitle)

        if isMacToolbarItemVisible("markdownProjectPreview") {
            Button(action: { toggleMarkdownProjectPreviewFromToolbar() }) {
                Label(
                    isMarkdownProjectPreviewPresented ? "Hide Markdown Cards" : "Show Markdown Cards",
                    systemImage: isMarkdownProjectPreviewPresented ? "square.grid.2x2.fill" : "square.grid.2x2"
                )
                .foregroundStyle(isMarkdownProjectPreviewPresented ? Color.accentColor : macToolbarSymbolColor)
            }
            .disabled(projectRootFolderURL == nil || !hasMarkdownOrPDFProjectPreviewFiles || isSafeModeActive)
            .help(isMarkdownProjectPreviewPresented ? "Hide Markdown Cards" : "Show Markdown Cards")
            .accessibilityLabel("Markdown Cards")
            .accessibilityValue(isMarkdownProjectPreviewPresented ? "Shown" : "Hidden")
            .accessibilityHint("Shows Markdown and PDF files from the current project as preview cards")
        }

        if isMacToolbarItemVisible("codeMinimap") {
            codeMinimapControl
                .foregroundStyle(macToolbarSymbolColor)
        }

        if isMacToolbarItemVisible("toggleSidebar") {
            toggleSidebarControl
                .foregroundStyle(macToolbarSymbolColor)
        }

        if isMacToolbarItemVisible("toggleProjectSidebar") {
            toggleProjectSidebarControl
                .foregroundStyle(macToolbarSymbolColor)
        }

        if isMacToolbarItemVisible("brainDump") {
            brainDumpControl
                .foregroundStyle(macToolbarSymbolColor)
        }

        if isMacToolbarItemVisible("findReplace") {
            Button(action: {
                showFindReplace = true
            }) {
                Label("Find", systemImage: "magnifyingglass")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Find & Replace (Cmd+F)")
        }

        if isMacToolbarItemVisible("findInFiles") {
            Button(action: {
                requestFindInFilesFromToolbar()
            }) {
                Label("Find in Files", systemImage: "text.magnifyingglass")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Find in Files (Cmd+Shift+F)")
        }

        if isMacToolbarItemVisible("splitEditor") && !isMacToolbarItemVisible("compare") {
            Button(action: { toggleSplitEditorFromToolbar() }) {
                Label("Side by Side", systemImage: "rectangle.split.2x1")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)
            .help(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor")
        }

        if isMacToolbarItemVisible("gitChanges") {
            gitChangesControl
                .foregroundStyle(macToolbarSymbolColor)
        }

        }

        if isMacToolbarSecondaryUtilitiesVisible {
        ToolbarItemGroup(placement: .primaryAction) {

            #if os(macOS) || os(iOS)
            if !isMacToolbarItemVisible("codeMinimap") {
                Button(action: {
                    showCodeMinimap.toggle()
                }) {
                    Label("Code Minimap", systemImage: showCodeMinimap ? "map.fill" : "map")
                        .foregroundStyle(macToolbarSymbolColor)
                        .symbolVariant(showCodeMinimap ? .fill : .none)
                }
                .disabled(!supportsCodeMinimap(language: currentLanguage))
                .help(
                    supportsCodeMinimap(language: currentLanguage)
                        ? (showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap")
                        : "Code Minimap is unavailable for this document"
                )
                .accessibilityLabel("Code Minimap")
            }
            #endif

            Button(action: { undoFromToolbar() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Undo (Cmd+Z)")

            if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                Button(action: {
                    showUpdaterDialog(checkNow: true)
                }) {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle")
                        .foregroundStyle(macToolbarSymbolColor)
                }
                .help("Check for Updates")
            }

            #if os(macOS)
            if !isMacToolbarItemVisible("newWindow") {
                Button(action: {
                    openWindow(value: MacEditorWindowSessionStore.shared.createWindowID())
                }) {
                    Label("New Window", systemImage: "macwindow.badge.plus")
                        .foregroundStyle(macToolbarSymbolColor)
                }
                .help("New Window (Cmd+N)")
            }
            #endif

            Button(action: { adjustEditorFontSize(-1) }) {
                Label("Font -", systemImage: "textformat.size.smaller")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Decrease Font Size")

            Button(action: { adjustEditorFontSize(1) }) {
                Label("Font +", systemImage: "textformat.size.larger")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Increase Font Size")

            Button(action: {
                requestClearEditorContent()
            }) {
                Label("Clear", systemImage: "eraser")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Clear Editor")

            Button(action: {
                insertTemplateForCurrentLanguage()
            }) {
                Label("Template", systemImage: "doc.badge.plus")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Insert Template for Current Language")

            if !isMacToolbarItemVisible("toggleSidebar") {
                Button(action: {
                    toggleSidebarFromToolbar()
                }) {
                    Label("Sidebar", systemImage: "sidebar.left")
                        .foregroundStyle(macToolbarSymbolColor)
                        .symbolVariant(viewModel.showSidebar ? .fill : .none)
                }
                .help("Toggle Sidebar (Cmd+Opt+S)")
            }

            if !isMacToolbarItemVisible("toggleProjectSidebar") {
                Button(action: {
                    toggleProjectSidebarFromToolbar()
                }) {
                    Label("Project", systemImage: "sidebar.right")
                        .foregroundStyle(macToolbarSymbolColor)
                        .symbolVariant(showProjectStructureSidebar ? .fill : .none)
                }
                .help("Toggle Project Structure Sidebar")
            }

#if os(macOS) && !APP_STORE_BUILD
            Button(action: {
                showTerminalInProjectSidebar()
            }) {
                Label("Terminal", systemImage: "terminal")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Show Terminal in Sidebar")
            .accessibilityLabel("Sidebar Terminal")
#endif

            Button(action: {
                toggleAutoCompletion()
            }) {
                Label("AI", systemImage: "bolt.horizontal.circle")
                    .foregroundStyle(macToolbarSymbolColor)
                    .symbolVariant(isAutoCompletionEnabled ? .fill : .none)
            }
            .help(isAutoCompletionEnabled ? "Disable Code Completion" : "Enable Code Completion")
            .accessibilityLabel("Code Completion")

            Button(action: {
                showBracketHelperBarMac.toggle()
            }) {
                Label("Brackets", systemImage: "chevron.left.chevron.right")
                    .foregroundStyle(macToolbarSymbolColor)
                    .symbolVariant(showBracketHelperBarMac ? .fill : .none)
            }
            .help(showBracketHelperBarMac ? "Hide Bracket Helper Bar" : "Show Bracket Helper Bar")
            .accessibilityLabel("Bracket Helper Bar")

            if !isMacToolbarItemVisible("brainDump") {
                Button(action: {
                    viewModel.isBrainDumpMode.toggle()
                    UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
                }) {
                    Label("Brain Dump", systemImage: "note.text")
                        .foregroundStyle(macToolbarSymbolColor)
                        .symbolVariant(viewModel.isBrainDumpMode ? .fill : .none)
                }
                .help("Brain Dump Mode")
                .accessibilityLabel("Brain Dump Mode")
            }

            Button(action: {
                enableTranslucentWindow.toggle()
                UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
                NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
            }) {
                Label("Translucency", systemImage: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Toggle Translucent Window Background")
            .accessibilityLabel("Translucent Window Background")

        }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            toolbarPresetMenuControl
            macLanguageIndicatorControl

            if isMacToolbarItemVisible("editorLayout") {
                editorLayoutPresetControl
                    .foregroundStyle(macToolbarSymbolColor)
            }

            previewActionsControl
                .foregroundStyle(macToolbarSymbolColor)

            if isMacToolbarItemVisible("compare") {
                Menu {
                    Button(action: { compareCurrentTabAgainstDisk() }) {
                        Label("Compare with Disk", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(viewModel.selectedTab?.fileURL == nil)

                    Button(action: { presentCompareTabsPicker() }) {
                        Label("Compare Open Tabs…", systemImage: "rectangle.split.2x1")
                    }
                    .disabled(viewModel.selectedTab == nil)

                    Button(action: { toggleSplitEditorFromToolbar() }) {
                        Label(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor", systemImage: "rectangle.split.2x1")
                    }
                    .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)

                    Button(action: { showFolderCompare = true }) {
                        Label("Folder Compare…", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                        .foregroundStyle(macToolbarSymbolColor)
                }
                .help("Compare Files, Tabs, or Folders")
                .accessibilityLabel("Compare")
                .accessibilityHint("Opens compare actions for files, tabs, and folders")
            }

            if isAutoCompletionEnabled {
                Text(providerBadgeLabelText)
                    .font(.caption)
                    .foregroundColor(providerBadgeForegroundColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(providerBadgeBackgroundColor, in: Capsule())
                    .padding(.leading, 6)
                    .help(providerBadgeTooltip)
                    .accessibilityLabel("Code completion provider")
            }

        }
        }
#else
        ToolbarItem(placement: .automatic) {
            EmptyView()
        }
#endif
    }
}
