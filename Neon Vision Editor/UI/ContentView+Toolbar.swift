import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct ToolbarActionSelection {
    static let supportedVisibleCounts: Set<Int> = [4, 5, 6, 7, 8, 10]

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

    static func visibleActions<Action: RawRepresentable>(
        enabledActions: [Action],
        customIDsRawValue: String,
        usesCustomSelection: Bool,
        requestedCount: Int
    ) -> [Action] where Action.RawValue == String {
        let limit = visibleLimit(requestedCount: requestedCount, fallback: enabledActions.count)
        if usesCustomSelection {
            let selected = selectedIDs(from: customIDsRawValue)
            let picked = enabledActions.filter { selected.contains($0.rawValue) }
            if !picked.isEmpty {
                return Array(picked.prefix(limit))
            }
        }
        return Array(enabledActions.prefix(limit))
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
            Button(NSLocalizedString(option.title, comment: "")) {
                selectMarkdownPreviewTemplate(option.id)
            }
        }

        Divider()

        ForEach(Self.markdownPreviewTemplateOptions.dropFirst(4)) { option in
            Button(NSLocalizedString(option.title, comment: "")) {
                selectMarkdownPreviewTemplate(option.id)
            }
        }
    }

#if os(macOS)
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

        Divider()

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
#endif

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
    }

    private var enabledIOSPrimaryToolbarActions: [IOSPrimaryToolbarAction] {
        var actions: [IOSPrimaryToolbarAction] = []
        if toolbarShowOpenFileIOS { actions.append(.openFile) }
        if toolbarShowUndoIOS { actions.append(.undo) }
        if toolbarShowSettingsIOS { actions.append(.settings) }
        if toolbarShowHelpIOS { actions.append(.help) }
        if toolbarShowEditorUtilityIOS {
            actions.append(contentsOf: [.clearEditor, .insertTemplate])
        }
        actions.append(contentsOf: [
            .newTab,
            .saveFile,
            .saveFileAs,
            .codeSnapshot
        ])
        if toolbarShowAppearanceIOS {
            actions.append(contentsOf: [.markdownPreview, .codeMinimap, .indentationGuides])
        }
        actions.append(contentsOf: [
            .markdownPreviewExport,
            .markdownPreviewStyle,
            .closeAllTabs,
            .toggleSidebar,
            .toggleProjectSidebar
        ])
        if toolbarShowSearchIOS {
            actions.append(contentsOf: [.findReplace, .findInFiles])
        }
        if toolbarShowCompareIOS {
            actions.append(contentsOf: [.compareDisk, .compareTabs, .splitEditor])
        }
        if toolbarShowAppearanceIOS {
            actions.append(.lineWrap)
        }
        if toolbarShowEditorUtilityIOS {
            actions.append(contentsOf: [.codeCompletion, .keyboardAccessory])
        }
        actions.append(.hideKeyboard)
        if toolbarShowEditorUtilityIOS {
            actions.append(contentsOf: [.performanceMode, .brainDump])
        }
        actions.append(.welcomeTour)
        if toolbarShowAppearanceIOS {
            actions.append(.translucentWindow)
        }
#if os(iOS)
        actions.append(.toolbarIconColor)
#endif
        return actions
    }

    private var visibleIOSPrimaryToolbarActions: [IOSPrimaryToolbarAction] {
        ToolbarActionSelection.visibleActions(
            enabledActions: enabledIOSPrimaryToolbarActions,
            customIDsRawValue: toolbarCustomFiveIDsIOS,
            usesCustomSelection: toolbarUseCustomFiveIOS,
            requestedCount: toolbarFavoriteCountIOS
        )
    }

    @ViewBuilder
    private func iOSPrimaryToolbarActionControl(_ action: IOSPrimaryToolbarAction) -> some View {
        switch action {
        case .openFile: openFileControl
        case .undo: undoControl
        case .settings: settingsControl
        case .help: helpControl
        case .clearEditor: clearEditorControl
        case .insertTemplate: insertTemplateControl
        case .newTab: newTabControl
        case .saveFile: saveFileControl
        case .saveFileAs: saveFileAsControl
        case .codeSnapshot: codeSnapshotControl
        case .markdownPreview: markdownPreviewControl
        case .codeMinimap: codeMinimapControl
        case .indentationGuides: indentationGuidesControl
        case .markdownPreviewExport: markdownPreviewExportControl
        case .markdownPreviewStyle: markdownPreviewStyleControl
        case .closeAllTabs: closeAllTabsControl
        case .toggleSidebar: toggleSidebarControl
        case .toggleProjectSidebar: toggleProjectSidebarControl
        case .findReplace: findReplaceControl
        case .findInFiles: findInFilesControl
        case .compareDisk: compareDiskControl
        case .compareTabs: compareTabsControl
        case .splitEditor: splitEditorControl
        case .lineWrap: lineWrapControl
        case .codeCompletion: codeCompletionControl
        case .keyboardAccessory: keyboardAccessoryControl
        case .hideKeyboard: hideKeyboardControl
        case .performanceMode: performanceModeControl
        case .brainDump: brainDumpControl
        case .welcomeTour: welcomeTourControl
        case .translucentWindow: translucentWindowControl
        case .toolbarIconColor: toolbarIconColorControl
        }
    }


    private enum IPadToolbarAction: String, CaseIterable, Hashable {
        case openFile
        case undo
        case newTab
        case closeAllTabs
        case saveFile
        case codeSnapshot
        case markdownPreview
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
        case splitEditor
        case settings
        case help
        case codeCompletion
        case performanceMode
        case lineWrap
        case keyboardAccessory
        case clearEditor
        case insertTemplate
        case brainDump
        case welcomeTour
        case translucentWindow
    }

    private var iPadActionPriority: [IPadToolbarAction] {
        [
            .openFile,
            .undo,
            .newTab,
            .closeAllTabs,
            .saveFile,
            .codeSnapshot,
            .markdownPreview,
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
            .splitEditor,
            .settings,
            .help,
            .codeCompletion,
            .lineWrap,
            .keyboardAccessory,
            .clearEditor,
            .insertTemplate,
            .performanceMode,
            .brainDump,
            .welcomeTour,
            .translucentWindow
        ]
    }

    private var enabledIPadActionPriority: [IPadToolbarAction] {
        iPadActionPriority.filter { toolbarActionIsEnabled($0) }
    }

    private func toolbarActionIsEnabled(_ action: IPadToolbarAction) -> Bool {
        switch action {
        case .findReplace, .findInFiles:
            return toolbarShowSearchIOS
        case .compareDisk, .compareTabs, .splitEditor:
            return toolbarShowCompareIOS
        case .clearEditor, .insertTemplate, .codeCompletion, .keyboardAccessory, .brainDump, .performanceMode:
            return toolbarShowEditorUtilityIOS
        case .fontDecrease, .fontIncrease, .markdownPreview, .markdownPreviewExport, .markdownPreviewStyle, .codeMinimap, .indentationGuides, .lineWrap, .translucentWindow:
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

    private func toggleBrainDumpModeIOSAware() {
#if os(iOS) || os(visionOS)
        viewModel.isBrainDumpMode = false
        UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
#else
        viewModel.isBrainDumpMode.toggle()
        UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
#endif
    }

    private var visibleIPadToolbarActions: [IPadToolbarAction] {
        let enabled = enabledIPadActionPriority.filter { $0 != .settings && $0 != .help }
        return ToolbarActionSelection.visibleActions(
            enabledActions: enabled,
            customIDsRawValue: toolbarCustomFiveIDsIOS,
            usesCustomSelection: toolbarUseCustomFiveIOS,
            requestedCount: toolbarFavoriteCountIOS
        )
    }

    private var iPadOverflowActions: [IPadToolbarAction] {
        let visible = Set(visibleIPadToolbarActions)
        return enabledIPadActionPriority.filter {
            $0 != .settings &&
            $0 != .help &&
            !visible.contains($0)
        }
    }

#if os(visionOS)
    private var visionOSToolbarActions: [IPadToolbarAction] {
        enabledIPadActionPriority.filter {
            $0 != .settings &&
            $0 != .help &&
            visionOSToolbarActionIsEnabled($0)
        }
    }

    private var visionOSPinnedToolbarActionCount: Int {
        (toolbarShowSettingsIOS ? 1 : 0) + (toolbarShowHelpIOS ? 1 : 0)
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
        return Array(visionOSToolbarActions.prefix(max(0, min(visionOSToolbarActions.count, visibleCount))))
    }

    private func visionOSOverflowActions(visibleActions: [IPadToolbarAction]) -> [IPadToolbarAction] {
        let visible = Set(visibleActions)
        return visionOSToolbarActions.filter { !visible.contains($0) }
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
#if os(iOS) || os(visionOS)
        .keyboardShortcut("t", modifiers: .command)
#endif
    }

    @ViewBuilder
    private var settingsControl: some View {
        Button(action: { openSettings() }) {
            Image(systemName: "gearshape")
        }
        .help("Settings (Cmd+,)")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens app settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    @ViewBuilder
    private var helpControl: some View {
        Button(action: { showEditorHelp = true }) {
            Image(systemName: "questionmark.circle")
        }
        .help("Toolbar Help")
        .accessibilityLabel("Toolbar Help")
        .accessibilityHint("Opens help for all toolbar actions")
        .keyboardShortcut("?", modifiers: .command)
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
            Text(toolbarCompactLanguageLabel(currentLanguagePickerBinding.wrappedValue))
                .lineLimit(1)
                .truncationMode(.tail)
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
                .frame(width: isIPadToolbarLayout ? 112 : iPhoneLanguagePickerWidth)
#endif
        }
        .labelsHidden()
        .help("Language")
        .accessibilityLabel("Language picker")
        .accessibilityHint("Choose syntax language for the current tab")
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
        .keyboardShortcut("l", modifiers: [.command, .option])
    }

    @ViewBuilder
    private var openFileControl: some View {
        Button(action: { openFileFromToolbar() }) {
            Image(systemName: "folder")
        }
        .help("Open File… (Cmd+O)")
        .accessibilityLabel("Open file")
        .accessibilityHint("Opens a file picker")
#if os(iOS) || os(visionOS)
        .keyboardShortcut("o", modifiers: .command)
#endif
    }

    @ViewBuilder
    private var undoControl: some View {
        Button(action: { undoFromToolbar() }) {
            Image(systemName: "arrow.uturn.backward")
        }
        .help("Undo (Cmd+Z)")
        .keyboardShortcut("z", modifiers: .command)
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
#if os(iOS) || os(visionOS)
        .keyboardShortcut("s", modifiers: .command)
#endif
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
        .keyboardShortcut("s", modifiers: [.command, .shift])
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
    private var toggleSidebarControl: some View {
        Button(action: { toggleSidebarFromToolbar() }) {
            Image(systemName: "sidebar.left")
        }
        .help("Toggle Sidebar (Cmd+Opt+S)")
#if os(iOS) || os(visionOS)
        .keyboardShortcut("s", modifiers: [.command, .option])
#endif
    }

    @ViewBuilder
    private var toggleProjectSidebarControl: some View {
        Button(action: { toggleProjectSidebarFromToolbar() }) {
            Image(systemName: "sidebar.right")
        }
        .help("Toggle Project Structure Sidebar")
    }

    @ViewBuilder
    private var findReplaceControl: some View {
        Button(action: { showFindReplace = true }) {
            Image(systemName: "magnifyingglass")
        }
        .help("Find & Replace (Cmd+F)")
#if os(iOS) || os(visionOS)
        .keyboardShortcut("f", modifiers: .command)
#endif
    }

    @ViewBuilder
    private var findInFilesControl: some View {
        Button(action: { showFindInFiles = true }) {
            Image(systemName: "text.magnifyingglass")
        }
        .help("Find in Files (Cmd+Shift+F)")
        .accessibilityLabel("Find in Files")
        .accessibilityHint("Searches across files in the current project")
#if os(iOS) || os(visionOS)
        .keyboardShortcut("f", modifiers: [.command, .shift])
#endif
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
    private var brainDumpControl: some View {
        Button(action: {
            toggleBrainDumpModeIOSAware()
        }) {
            Image(systemName: "note.text")
                .symbolVariant(viewModel.isBrainDumpMode ? .fill : .none)
        }
        .help("Brain Dump Mode")
        .accessibilityLabel("Brain Dump Mode")
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
        .help("Performance Mode")
        .accessibilityLabel("Performance Mode")
    }

    @ViewBuilder
    private var markdownPreviewControl: some View {
        Button(action: {
            toggleMarkdownPreviewFromToolbar()
        }) {
            Image(systemName: showMarkdownPreviewPane ? "doc.richtext.fill" : "doc.richtext")
        }
        .disabled(currentLanguage != "markdown")
        .help("Toggle Markdown Preview")
        .accessibilityLabel("Markdown Preview")
    }

    @ViewBuilder
    private var codeMinimapControl: some View {
        Button(action: {
            showCodeMinimap.toggle()
        }) {
            Image(systemName: showCodeMinimap ? "map.fill" : "map")
        }
        .disabled(!supportsCodeMinimap(language: currentLanguage))
        .help(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap")
        .accessibilityLabel("Code Minimap")
        .accessibilityHint("Toggles the code minimap for code files")
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
        .accessibilityHint("Toggles light indentation guide lines in the editor")
    }

    @ViewBuilder
    private var markdownPreviewExportControl: some View {
        if showMarkdownPreviewPane && currentLanguage == "markdown" {
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
        if showMarkdownPreviewPane && currentLanguage == "markdown" {
            Menu {
                markdownPreviewTemplateMenuItems
            } label: {
                Image(systemName: "paintbrush")
            }
            .help(NSLocalizedString("Markdown Preview Template", comment: "Toolbar help for markdown preview style menu"))
            .accessibilityLabel(NSLocalizedString("Markdown Preview Template", comment: "Accessibility label for markdown preview style menu"))
        }
    }

    @ViewBuilder
    private var markdownPreviewExportToolbarMenuContent: some View {
        Button(action: { exportMarkdownPreviewPDF() }) {
            Label("Export PDF", systemImage: "square.and.arrow.down")
        }
        .help("Export Markdown Preview as PDF")

        Divider()

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
        .accessibilityHint("Toggles blue toolbar icon coloring")
    }

    // MARK: - iPad Toolbar Composition

    @ViewBuilder
    private func iPadToolbarActionControl(_ action: IPadToolbarAction) -> some View {
        switch action {
        case .openFile: openFileControl
        case .undo: undoControl
        case .newTab: newTabControl
        case .closeAllTabs: closeAllTabsControl
        case .saveFile: saveFileControl
        case .codeSnapshot: codeSnapshotControl
        case .markdownPreview: markdownPreviewControl
        case .markdownPreviewExport: markdownPreviewExportControl
        case .markdownPreviewStyle: markdownPreviewStyleControl
        case .codeMinimap: codeMinimapControl
        case .indentationGuides: indentationGuidesControl
        case .fontDecrease: fontDecreaseControl
        case .fontIncrease: fontIncreaseControl
        case .toggleSidebar: toggleSidebarControl
        case .toggleProjectSidebar: toggleProjectSidebarControl
        case .findReplace: findReplaceControl
        case .findInFiles: findInFilesControl
        case .compareDisk: compareDiskControl
        case .compareTabs: compareTabsControl
        case .splitEditor: splitEditorControl
        case .settings: settingsControl
        case .help: helpControl
        case .codeCompletion: codeCompletionControl
        case .performanceMode: performanceModeControl
        case .lineWrap: lineWrapControl
        case .keyboardAccessory: keyboardAccessoryControl
        case .clearEditor: clearEditorControl
        case .insertTemplate: insertTemplateControl
        case .brainDump: brainDumpControl
        case .welcomeTour: welcomeTourControl
        case .translucentWindow: translucentWindowControl
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
                        .keyboardShortcut("z", modifiers: .command)
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
                    case .codeSnapshot:
                        Button(action: { presentCodeSnapshotComposer() }) {
                            Label("Create Code Snapshot", systemImage: "camera.viewfinder")
                        }
                        .disabled(!canCreateCodeSnapshot)
                    case .markdownPreview:
                        Button(action: { toggleMarkdownPreviewFromToolbar() }) {
                            Label(
                                "Markdown Preview",
                                systemImage: showMarkdownPreviewPane ? "doc.richtext.fill" : "doc.richtext"
                            )
                        }
                        .disabled(currentLanguage != "markdown")
                    case .markdownPreviewExport:
                        markdownPreviewExportToolbarMenuContent
                    case .markdownPreviewStyle:
                        Menu {
                            markdownPreviewTemplateMenuItems
                        } label: {
                            Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
                        }
                    case .codeMinimap:
                        Button(action: { showCodeMinimap.toggle() }) {
                            Label(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap", systemImage: showCodeMinimap ? "map.fill" : "map")
                        }
                        .disabled(!supportsCodeMinimap(language: currentLanguage))
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
                        Button(action: { showFindInFiles = true }) {
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
                    case .splitEditor:
                        Button(action: { toggleSplitEditorFromToolbar() }) {
                            Label(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor", systemImage: "rectangle.split.2x1")
                        }
                        .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)
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
                    }
                }

                Button(action: { saveCurrentTabAsFromToolbar() }) {
                    Label("Save As…", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(viewModel.selectedTab == nil)
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button(action: { dismissKeyboard() }) {
                    Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
                }

#if os(iOS)
                Button(action: { toolbarIconsBlueIOS.toggle() }) {
                    Label("Blue Toolbar Icons", systemImage: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
                }
#endif
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 40, height: 40, alignment: .center)
                .contentShape(Rectangle())
        }
        .help("More Actions")
        .frame(minWidth: 40, minHeight: 40)
    }

    @ViewBuilder
    private var moreActionsControl: some View {
        Menu {
            Button(action: {
                openSettings()
            }) {
                Label("Settings", systemImage: "gearshape")
            }

            Button(action: {
                showEditorHelp = true
            }) {
                Label("Toolbar Help", systemImage: "questionmark.circle")
            }

            Button(action: {
                requestClearEditorContent()
            }) {
                Label("Clear Editor", systemImage: "eraser")
            }

            Button(action: { insertTemplateForCurrentLanguage() }) {
                Label("Insert Template", systemImage: "doc.badge.plus")
            }
            
            Button(action: { presentLanguageSearchSheet() }) {
                Label("Language…", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button(action: { openFileFromToolbar() }) {
                Label("Open File…", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(action: { undoFromToolbar() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)

            Button(action: { saveCurrentTabFromToolbar() }) {
                Label("Save File", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.selectedTab == nil)
            .keyboardShortcut("s", modifiers: .command)

            Button(action: { presentCodeSnapshotComposer() }) {
                Label("Create Code Snapshot", systemImage: "camera.viewfinder")
            }
            .disabled(!canCreateCodeSnapshot)

            Button(action: { toggleMarkdownPreviewFromToolbar() }) {
                Label(
                    "Markdown Preview",
                    systemImage: showMarkdownPreviewPane ? "doc.richtext.fill" : "doc.richtext"
                )
            }
            .disabled(currentLanguage != "markdown")

            Button(action: { showCodeMinimap.toggle() }) {
                Label(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap", systemImage: showCodeMinimap ? "map.fill" : "map")
            }
            .disabled(!supportsCodeMinimap(language: currentLanguage))

            Button(action: { showIndentationGuides.toggle() }) {
                Label(showIndentationGuides ? "Hide Indentation Guides" : "Show Indentation Guides", systemImage: "text.alignleft")
            }

            if showMarkdownPreviewPane && currentLanguage == "markdown" {
                Menu {
                    markdownPreviewExportToolbarMenuContent
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.down")
                }
            }

            Button(action: { requestCloseAllTabsFromToolbar() }) {
                Label("Close All Tabs", systemImage: "xmark.square")
            }
            .disabled(viewModel.tabs.isEmpty)

            Button(action: { saveCurrentTabAsFromToolbar() }) {
                Label("Save As…", systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(viewModel.selectedTab == nil)
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(action: { toggleSidebarFromToolbar() }) {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(action: { toggleProjectSidebarFromToolbar() }) {
                Label("Toggle Project Structure Sidebar", systemImage: "sidebar.right")
            }

            Button(action: { showFindReplace = true }) {
                Label("Find & Replace", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(action: { showFindInFiles = true }) {
                Label("Find in Files…", systemImage: "text.magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(action: { compareCurrentTabAgainstDisk() }) {
                Label("Compare with Disk", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(viewModel.selectedTab?.fileURL == nil)

            Button(action: { presentCompareTabsPicker() }) {
                Label("Compare Open Tabs…", systemImage: "rectangle.split.2x1")
            }
            .disabled(viewModel.selectedTab == nil)

            Button(action: { viewModel.isLineWrapEnabled.toggle() }) {
                Label("Enable Wrap / Disable Wrap", systemImage: "text.justify")
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button(action: { toggleAutoCompletion() }) {
                Label(isAutoCompletionEnabled ? "Disable Code Completion" : "Enable Code Completion", systemImage: "text.badge.plus")
            }

            Button(action: {
                toggleKeyboardAccessoryBar()
            }) {
                Label(
                    showKeyboardAccessoryBarIOS ? "Hide Keyboard Snippet Bar" : "Show Keyboard Snippet Bar",
                    systemImage: showKeyboardAccessoryBarIOS ? "keyboard.chevron.compact.down.fill" : "keyboard.chevron.compact.down"
                )
            }

            Button(action: { dismissKeyboard() }) {
                Label("Hide Keyboard", systemImage: "keyboard.chevron.compact.down")
            }

            Button(action: {
                forceLargeFileMode.toggle()
                updateLargeFileMode(for: currentContentBinding.wrappedValue)
            }) {
                Label(forceLargeFileMode ? "Disable Performance Mode" : "Enable Performance Mode", systemImage: "speedometer")
            }

            Button(action: {
                toggleBrainDumpModeIOSAware()
            }) {
                Label("Brain Dump Mode", systemImage: "note.text")
            }
            
            Button(action: {
                showWelcomeTour = true
            }) {
                Label("Welcome Tour", systemImage: "sparkles.rectangle.stack")
            }

            Button(action: {
                enableTranslucentWindow.toggle()
                UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
                NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
            }) {
                Label("Translucent Window Background", systemImage: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
            }

#if os(iOS)
            Button(action: {
                toolbarIconsBlueIOS.toggle()
            }) {
                Label("Blue Toolbar Icons", systemImage: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
            }
#endif

        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More Actions")
    }

    // MARK: - iPhone Toolbar Composition

    @ViewBuilder
    private var iPhonePrimaryToolbarCluster: some View {
        GlassSurface(
            enabled: shouldUseLiquidGlass,
            material: primaryGlassMaterial,
            fallbackColor: toolbarFallbackColor,
            shape: .capsule,
            chromeStyle: iOSToolbarChromeStyle
        ) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        languagePickerControl
                        ForEach(visibleIOSPrimaryToolbarActions, id: \.self) { action in
                            iOSPrimaryToolbarActionControl(action)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
                }
                moreActionsControl
                    .padding(.trailing, 12)
            }
            .frame(minHeight: 56)
        }
    }

    @ViewBuilder
    var iPhoneUnifiedToolbarRow: some View {
        iPhonePrimaryToolbarCluster
            .frame(maxWidth: .infinity, alignment: .center)
            .scaleEffect(toolbarDensityScale)
            .opacity(toolbarDensityOpacity)
            .animation(.easeOut(duration: 0.18), value: toolbarDensityScale)
            .animation(.easeOut(duration: 0.18), value: toolbarDensityOpacity)
            .tint(iOSToolbarTintColor)
    }

    @ViewBuilder
    private var iPadDistributedToolbarControls: some View {
        languagePickerControl
        ForEach(visibleIPadToolbarActions, id: \.self) { action in
            iPadToolbarActionControl(action)
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var iPadScrollableToolbarControls: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    iPadDistributedToolbarControls
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            settingsControl
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
            helpControl
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
            iPadOverflowMenuControl
                .padding(.trailing, 8)
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
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                }

                Spacer(minLength: 0)

                if toolbarShowSettingsIOS {
                    settingsControl
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                }

                if toolbarShowHelpIOS {
                    helpControl
                        .frame(minWidth: 40, minHeight: 40)
                        .contentShape(Rectangle())
                }

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

    private func toolbarCompactLanguageLabel(_ lang: String) -> String {
        switch lang {
        case "swift": return "Sw"
        case "python": return "Py"
        case "javascript": return "JS"
        case "typescript": return "TS"
        case "php": return "PHP"
        case "java": return "Jv"
        case "kotlin": return "Kt"
        case "go": return "Go"
        case "ruby": return "Rb"
        case "rust": return "Rs"
        case "cobol": return "Cob"
        case "dotenv": return "Env"
        case "proto": return "Prt"
        case "graphql": return "GQL"
        case "rst": return "RST"
        case "nginx": return "Ngnx"
        case "sql": return "SQL"
        case "html": return "HTML"
        case "expressionengine": return "EE"
        case "css": return "CSS"
        case "c": return "C"
        case "cpp": return "C++"
        case "csharp": return "C#"
        case "objective-c": return "ObjC"
        case "json": return "JSON"
        case "xml": return "XML"
        case "yaml": return "YML"
        case "toml": return "TML"
        case "csv": return "CSV"
        case "ini": return "INI"
        case "vim": return "Vim"
        case "log": return "Log"
        case "ipynb": return "JNB"
        case "markdown": return "MD"
        case "tex": return "TeX"
        case "bash": return "Sh"
        case "zsh": return "zsh"
        case "powershell": return "PS"
        case "standard": return "Std"
        case "plain": return "Txt"
        default: return lang.capitalized
        }
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
        ToolbarItem(placement: .automatic) {
            Button(action: { isToolbarCollapsed.toggle() }) {
                Image(systemName: isToolbarCollapsed ? "chevron.down" : "chevron.up")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help(isToolbarCollapsed ? "Show Toolbar" : "Collapse Toolbar")
            .accessibilityLabel("Toggle Toolbar")
        }

        if !isToolbarCollapsed {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { openFileFromToolbar() }) {
                Label("Open", systemImage: "folder")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Open File… (Cmd+O)")

            Button(action: { viewModel.addNewTab() }) {
                Label("New Tab", systemImage: "plus.square.on.square")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("New Tab (Cmd+T)")

            Button(action: { requestCloseAllTabsFromToolbar() }) {
                Label("Close All Tabs", systemImage: "xmark.square")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Close All Tabs")

            Button(action: {
                saveCurrentTabFromToolbar()
            }) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(viewModel.selectedTab == nil)
            .help("Save File (Cmd+S)")

            Button(action: { presentCodeSnapshotComposer() }) {
                Label("Code Snapshot", systemImage: "camera.viewfinder")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(!canCreateCodeSnapshot)
            .help("Create Code Snapshot from Selection")

            Button(action: {
                showFindReplace = true
            }) {
                Label("Find", systemImage: "magnifyingglass")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Find & Replace (Cmd+F)")

            Button(action: {
                showFindInFiles = true
            }) {
                Label("Find in Files", systemImage: "text.magnifyingglass")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Find in Files (Cmd+Shift+F)")

            Menu {
                Button(action: { compareCurrentTabAgainstDisk() }) {
                    Label("Compare with Disk", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(viewModel.selectedTab?.fileURL == nil)
                .help("Compare Current Tab with Saved File")

                Button(action: { presentCompareTabsPicker() }) {
                    Label("Compare Open Tabs…", systemImage: "rectangle.split.2x1")
                }
                .disabled(viewModel.selectedTab == nil)
                .help("Compare Current Tab with Another Open Tab")

                Button(action: { toggleSplitEditorFromToolbar() }) {
                    Label(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor", systemImage: "rectangle.split.2x1")
                }
                .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)
                .help(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor")

                Button(action: { showFolderCompare = true }) {
                    Label("Folder Compare…", systemImage: "folder.badge.gearshape")
                }
                .help("Compare Two Folders")
            } label: {
                Label("Compare", systemImage: "rectangle.split.2x1")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Compare Files, Tabs, or Folders")
            .accessibilityLabel("Compare")
            .accessibilityHint("Opens compare actions for files, tabs, and folders")

            Button(action: { toggleSplitEditorFromToolbar() }) {
                Label("Side by Side", systemImage: "rectangle.split.2x1")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .disabled(!canOpenSplitEditor && splitSecondaryTabID == nil)
            .help(splitSecondaryTabID == nil ? "Open Two Tabs Side by Side" : "Close Side by Side Editor")

            Button(action: {
                openSettings()
            }) {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Settings")

            Button(action: {
                showEditorHelp = true
            }) {
                Label("Toolbar Help", systemImage: "questionmark.circle")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Toolbar Help (Cmd+?)")
        }

        ToolbarItemGroup(placement: .automatic) {
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
                Text(toolbarCompactLanguageLabel(currentLanguagePickerBinding.wrappedValue))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .labelsHidden()
            .help("Language")
            .controlSize(.large)
            .frame(width: 92)
            .padding(.vertical, 2)

            Button(action: { presentLanguageSearchSheet() }) {
                Image(systemName: "magnifyingglass")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .help("Language… (Cmd+Shift+L)")

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
            }

            #if os(macOS) || os(iOS)
            if canShowMarkdownPreviewPane {
                Button(action: {
                    toggleMarkdownPreviewFromToolbar()
                }) {
                    Label("Markdown Preview", systemImage: showMarkdownPreviewPane ? "doc.richtext.fill" : "doc.richtext")
                        .foregroundStyle(macToolbarSymbolColor)
                }
                .disabled(currentLanguage != "markdown")
                .help("Toggle Markdown Preview")

                Button(action: {
                    showCodeMinimap.toggle()
                }) {
                    Label("Code Minimap", systemImage: showCodeMinimap ? "map.fill" : "map")
                        .foregroundStyle(macToolbarSymbolColor)
                        .symbolVariant(showCodeMinimap ? .fill : .none)
                }
                .disabled(!supportsCodeMinimap(language: currentLanguage))
                .help(showCodeMinimap ? "Hide Code Minimap" : "Show Code Minimap")
                .accessibilityLabel("Code Minimap")

                if showMarkdownPreviewPane && currentLanguage == "markdown" {
                    Menu {
                        markdownPreviewExportToolbarMenuContent
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.down")
                            .foregroundStyle(macToolbarSymbolColor)
                    }
                    .help(NSLocalizedString("Markdown Preview Export Options", comment: "Toolbar help for markdown preview export options"))

                    Menu {
                        markdownPreviewTemplateMenuItems
                    } label: {
                        Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
                            .foregroundStyle(macToolbarSymbolColor)
                    }
                    .help(NSLocalizedString("Markdown Preview Template", comment: "Toolbar help for markdown preview style menu"))
                }
            }
            #endif

            Button(action: { undoFromToolbar() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Undo (Cmd+Z)")
            .keyboardShortcut("z", modifiers: .command)

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
            Button(action: {
                openWindow(id: "blank-window")
            }) {
                Label("New Window", systemImage: "macwindow.badge.plus")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("New Window (Cmd+N)")
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

            Button(action: {
                toggleSidebarFromToolbar()
            }) {
                Label("Sidebar", systemImage: "sidebar.left")
                    .foregroundStyle(macToolbarSymbolColor)
                    .symbolVariant(viewModel.showSidebar ? .fill : .none)
            }
            .help("Toggle Sidebar (Cmd+Opt+S)")

            Button(action: {
                toggleProjectSidebarFromToolbar()
            }) {
                Label("Project", systemImage: "sidebar.right")
                    .foregroundStyle(macToolbarSymbolColor)
                    .symbolVariant(showProjectStructureSidebar ? .fill : .none)
            }
            .help("Toggle Project Structure Sidebar")

#if os(macOS)
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
#else
        ToolbarItem(placement: .automatic) {
            EmptyView()
        }
#endif
    }
}
