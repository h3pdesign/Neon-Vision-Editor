import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif



/// MARK: - Types

extension ContentView {
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

        Divider()

        Menu {
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.paginatedFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.paginatedFit.rawValue {
                    Label("Paginated Fit", systemImage: "checkmark")
                } else {
                    Text("Paginated Fit")
                }
            }
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.onePageFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.onePageFit.rawValue {
                    Label("One Page Fit", systemImage: "checkmark")
                } else {
                    Text("One Page Fit")
                }
            }
        } label: {
            Label("PDF Mode", systemImage: "doc.text")
        }

        Menu {
            Button("Default") { markdownPreviewTemplateRaw = "default" }
            Button("Docs") { markdownPreviewTemplateRaw = "docs" }
            Button("Article") { markdownPreviewTemplateRaw = "article" }
            Button("Compact") { markdownPreviewTemplateRaw = "compact" }
            Divider()
            Button("GitHub Docs") { markdownPreviewTemplateRaw = "github-docs" }
            Button("Academic Paper") { markdownPreviewTemplateRaw = "academic-paper" }
            Button("Terminal Notes") { markdownPreviewTemplateRaw = "terminal-notes" }
            Button("Magazine") { markdownPreviewTemplateRaw = "magazine" }
            Button("Minimal Reader") { markdownPreviewTemplateRaw = "minimal-reader" }
            Button("Presentation") { markdownPreviewTemplateRaw = "presentation" }
            Button("Night Contrast") { markdownPreviewTemplateRaw = "night-contrast" }
            Button("Warm Sepia") { markdownPreviewTemplateRaw = "warm-sepia" }
            Button("Dense Compact") { markdownPreviewTemplateRaw = "dense-compact" }
            Button("Developer Spec") { markdownPreviewTemplateRaw = "developer-spec" }
        } label: {
            Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
        }

        Divider()

        Button(action: { copyMarkdownPreviewHTML() }) {
            Label("Copy HTML", systemImage: "doc.on.doc")
        }
        Button(action: { copyMarkdownPreviewMarkdown() }) {
            Label("Copy Markdown", systemImage: "doc.on.clipboard")
        }
    }
#endif

#if os(iOS)
    private var iOSToolbarChromeStyle: GlassChromeStyle { .single }
    private var iOSToolbarTintColor: Color {
        if toolbarIconsBlueIOS {
            return NeonUIStyle.accentBlue
        }
        return colorScheme == .dark ? Color.white.opacity(0.95) : Color.primary.opacity(0.92)
    }

    private var isIPadToolbarLayout: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        // During first render on iOS, horizontalSizeClass can transiently be nil.
        // Treat nil as regular so the full iPad toolbar appears immediately.
        if horizontalSizeClass == .compact { return false }
        return true
    }

    private var iPhoneToolbarWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.width ?? 390
    }

    private var activeWindowWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let normalWindowWidths = scenes
            .flatMap(\.windows)
            .filter { window in
                !window.isHidden &&
                window.alpha > 0.01 &&
                window.windowLevel == .normal &&
                window.bounds.width > 0
            }
            .map { $0.bounds.width }
        if let width = normalWindowWidths.max() {
            return width
        }
        return scenes.first?.screen.bounds.width ?? 1024
    }

    private var iPhoneLanguagePickerWidth: CGFloat {
        switch iPhoneToolbarWidth {
        case 430...: return 108
        case 395...: return 100
        default: return 94
        }
    }

    private var iPadToolbarMaxWidth: CGFloat {
        // Use live window width (not full screen width) so Stage Manager/split sizes
        // immediately rebalance promoted vs overflow actions.
        let target = activeWindowWidth - 28
        return min(max(target, 560), 1320)
    }


    private enum IPadToolbarAction: String, CaseIterable, Hashable {
        case openFile
        case undo
        case newTab
        case closeAllTabs
        case saveFile
        case codeSnapshot
        case markdownPreview
        case fontDecrease
        case fontIncrease
        case toggleSidebar
        case toggleProjectSidebar
        case findReplace
        case findInFiles
        case compareDisk
        case compareTabs
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
            .fontDecrease,
            .fontIncrease,
            .toggleSidebar,
            .toggleProjectSidebar,
            .findReplace,
            .findInFiles,
            .compareDisk,
            .compareTabs,
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

    private func toggleKeyboardAccessoryBar() {
        showKeyboardAccessoryBarIOS.toggle()
        NotificationCenter.default.post(
            name: .keyboardAccessoryBarVisibilityChanged,
            object: showKeyboardAccessoryBarIOS
        )
    }

    private func toggleBrainDumpModeIOSAware() {
#if os(iOS)
        viewModel.isBrainDumpMode = false
        UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
#else
        viewModel.isBrainDumpMode.toggle()
        UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
#endif
    }

    private var iPadPinnedOverflowActions: Set<IPadToolbarAction> {
        [
            .closeAllTabs,
            .performanceMode,
            .brainDump,
            .welcomeTour,
            .translucentWindow
        ]
    }

    private var iPadAlwaysVisibleActions: [IPadToolbarAction] {
        [.openFile, .newTab, .saveFile, .findReplace, .findInFiles, .settings, .help]
    }

    private var iPadPromotedActionSlotCount: Int {
        switch iPadToolbarMaxWidth {
        case 1200...: return 11
        case 1080...: return 10
        case 980...: return 9
        case 900...: return 9
        case 820...: return 8
        case 740...: return 7
        case 660...: return 6
        default: return 5
        }
    }

    private var iPadPromotedActions: [IPadToolbarAction] {
        let eligible = iPadActionPriority.filter {
            !iPadPinnedOverflowActions.contains($0) &&
            !iPadAlwaysVisibleActions.contains($0)
        }
        return Array(eligible.prefix(iPadPromotedActionSlotCount))
    }

    private var iPadOverflowActions: [IPadToolbarAction] {
        iPadActionPriority.filter {
            !iPadAlwaysVisibleActions.contains($0) &&
            (iPadPinnedOverflowActions.contains($0) || !iPadPromotedActions.contains($0))
        }
    }

    @ViewBuilder
    private var newTabControl: some View {
        Button(action: { viewModel.addNewTab() }) {
            Image(systemName: "plus.square.on.square")
        }
        .help("New Tab (Cmd+T)")
        .accessibilityLabel("New tab")
        .accessibilityHint("Creates a new editor tab")
        .keyboardShortcut("t", modifiers: .command)
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
#if os(iOS)
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
#if os(iOS)
        .tint(iOSToolbarTintColor)
        .menuStyle(.button)
#endif
    }

    @ViewBuilder
    private var activeProviderBadgeControl: some View {
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
            .help(providerBadgeTooltip)
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
        .keyboardShortcut("o", modifiers: .command)
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
        .keyboardShortcut("s", modifiers: .command)
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
        .keyboardShortcut("s", modifiers: [.command, .option])
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
        .keyboardShortcut("f", modifiers: .command)
    }

    @ViewBuilder
    private var findInFilesControl: some View {
        Button(action: { showFindInFiles = true }) {
            Image(systemName: "text.magnifyingglass")
        }
        .help("Find in Files (Cmd+Shift+F)")
        .accessibilityLabel("Find in Files")
        .accessibilityHint("Searches across files in the current project")
        .keyboardShortcut("f", modifiers: [.command, .shift])
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
                Button("Default") { markdownPreviewTemplateRaw = "default" }
                Button("Docs") { markdownPreviewTemplateRaw = "docs" }
                Button("Article") { markdownPreviewTemplateRaw = "article" }
                Button("Compact") { markdownPreviewTemplateRaw = "compact" }
                Divider()
                Button("GitHub Docs") { markdownPreviewTemplateRaw = "github-docs" }
                Button("Academic Paper") { markdownPreviewTemplateRaw = "academic-paper" }
                Button("Terminal Notes") { markdownPreviewTemplateRaw = "terminal-notes" }
                Button("Magazine") { markdownPreviewTemplateRaw = "magazine" }
                Button("Minimal Reader") { markdownPreviewTemplateRaw = "minimal-reader" }
                Button("Presentation") { markdownPreviewTemplateRaw = "presentation" }
                Button("Night Contrast") { markdownPreviewTemplateRaw = "night-contrast" }
                Button("Warm Sepia") { markdownPreviewTemplateRaw = "warm-sepia" }
                Button("Dense Compact") { markdownPreviewTemplateRaw = "dense-compact" }
                Button("Developer Spec") { markdownPreviewTemplateRaw = "developer-spec" }
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

        Divider()

        Menu {
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.paginatedFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.paginatedFit.rawValue {
                    Label("Paginated Fit", systemImage: "checkmark")
                } else {
                    Text("Paginated Fit")
                }
            }
            Button(action: { markdownPDFExportModeRaw = MarkdownPDFExportMode.onePageFit.rawValue }) {
                if markdownPDFExportModeRaw == MarkdownPDFExportMode.onePageFit.rawValue {
                    Label("One Page Fit", systemImage: "checkmark")
                } else {
                    Text("One Page Fit")
                }
            }
        } label: {
            Label("PDF Mode", systemImage: "doc.text")
        }

        Menu {
            Button("Default") { markdownPreviewTemplateRaw = "default" }
            Button("Docs") { markdownPreviewTemplateRaw = "docs" }
            Button("Article") { markdownPreviewTemplateRaw = "article" }
            Button("Compact") { markdownPreviewTemplateRaw = "compact" }
            Divider()
            Button("GitHub Docs") { markdownPreviewTemplateRaw = "github-docs" }
            Button("Academic Paper") { markdownPreviewTemplateRaw = "academic-paper" }
            Button("Terminal Notes") { markdownPreviewTemplateRaw = "terminal-notes" }
            Button("Magazine") { markdownPreviewTemplateRaw = "magazine" }
            Button("Minimal Reader") { markdownPreviewTemplateRaw = "minimal-reader" }
            Button("Presentation") { markdownPreviewTemplateRaw = "presentation" }
            Button("Night Contrast") { markdownPreviewTemplateRaw = "night-contrast" }
            Button("Warm Sepia") { markdownPreviewTemplateRaw = "warm-sepia" }
            Button("Dense Compact") { markdownPreviewTemplateRaw = "dense-compact" }
            Button("Developer Spec") { markdownPreviewTemplateRaw = "developer-spec" }
        } label: {
            Label(NSLocalizedString("Preview Style", comment: "Markdown preview style menu label"), systemImage: "paintbrush")
        }

        Divider()

        Button(action: { copyMarkdownPreviewHTML() }) {
            Label("Copy HTML", systemImage: "doc.on.doc")
        }
        Button(action: { copyMarkdownPreviewMarkdown() }) {
            Label("Copy Markdown", systemImage: "doc.on.clipboard")
        }
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
        case .fontDecrease: fontDecreaseControl
        case .fontIncrease: fontIncreaseControl
        case .toggleSidebar: toggleSidebarControl
        case .toggleProjectSidebar: toggleProjectSidebarControl
        case .findReplace: findReplaceControl
        case .findInFiles: findInFilesControl
        case .compareDisk: compareDiskControl
        case .compareTabs: compareTabsControl
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
        Menu {
                ForEach(iPadOverflowActions, id: \.self) { action in
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

                Button(action: { toolbarIconsBlueIOS.toggle() }) {
                    Label("Blue Toolbar Icons", systemImage: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
                }
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

            Button(action: {
                toolbarIconsBlueIOS.toggle()
            }) {
                Label("Blue Toolbar Icons", systemImage: toolbarIconsBlueIOS ? "checkmark.circle.fill" : "circle")
            }

        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More Actions")
    }

    @ViewBuilder
    private var iOSScrollableToolbarControls: some View {
        openFileControl
        undoControl
        settingsControl
        helpControl
        clearEditorControl
        insertTemplateControl
        newTabControl
        saveFileControl
        saveFileAsControl
        codeSnapshotControl
        markdownPreviewControl
        markdownPreviewExportControl
        markdownPreviewStyleControl
        closeAllTabsControl
        toggleSidebarControl
        toggleProjectSidebarControl
        findReplaceControl
        findInFilesControl
        compareDiskControl
        compareTabsControl
        lineWrapControl
        codeCompletionControl
        keyboardAccessoryControl
        hideKeyboardControl
        performanceModeControl
        brainDumpControl
        welcomeTourControl
        translucentWindowControl
        toolbarIconColorControl
        iOSVerticalSurfaceDivider
    }

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
                        iOSScrollableToolbarControls
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
        markdownPreviewExportControl
        markdownPreviewStyleControl
        ForEach(iPadActionPriority.filter { $0 != .settings && $0 != .help }, id: \.self) { action in
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
            settingsControl
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
            helpControl
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
            iPadOverflowMenuControl
                .padding(.trailing, 8)
        }
        .frame(maxWidth: iPadToolbarMaxWidth, minHeight: 52, alignment: .leading)
        .accessibilityLabel("Editor toolbar")
        .accessibilityHint("Swipe horizontally to reveal more editor actions")
    }
#endif

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
#if os(iOS)
        if isIPadToolbarLayout {
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
#else
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

                Button(action: { presentCompareTabsPicker() }) {
                    Label("Compare Open Tabs…", systemImage: "rectangle.split.2x1")
                }
                .disabled(viewModel.selectedTab == nil)
            } label: {
                Label("Compare", systemImage: "rectangle.split.2x1")
                    .foregroundStyle(macToolbarSymbolColor)
            }
            .help("Open Diff View")
            .accessibilityLabel("Compare")
            .accessibilityHint("Opens the diff view for the current document")

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

                if showMarkdownPreviewPane && currentLanguage == "markdown" {
                    Menu {
                        markdownPreviewExportToolbarMenuContent
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.down")
                            .foregroundStyle(macToolbarSymbolColor)
                    }
                    .help(NSLocalizedString("Markdown Preview Export Options", comment: "Toolbar help for markdown preview export options"))

                    Menu {
                        Button("Default") { markdownPreviewTemplateRaw = "default" }
                        Button("Docs") { markdownPreviewTemplateRaw = "docs" }
                        Button("Article") { markdownPreviewTemplateRaw = "article" }
                        Button("Compact") { markdownPreviewTemplateRaw = "compact" }
                        Divider()
                        Button("GitHub Docs") { markdownPreviewTemplateRaw = "github-docs" }
                        Button("Academic Paper") { markdownPreviewTemplateRaw = "academic-paper" }
                        Button("Terminal Notes") { markdownPreviewTemplateRaw = "terminal-notes" }
                        Button("Magazine") { markdownPreviewTemplateRaw = "magazine" }
                        Button("Minimal Reader") { markdownPreviewTemplateRaw = "minimal-reader" }
                        Button("Presentation") { markdownPreviewTemplateRaw = "presentation" }
                        Button("Night Contrast") { markdownPreviewTemplateRaw = "night-contrast" }
                        Button("Warm Sepia") { markdownPreviewTemplateRaw = "warm-sepia" }
                        Button("Dense Compact") { markdownPreviewTemplateRaw = "dense-compact" }
                        Button("Developer Spec") { markdownPreviewTemplateRaw = "developer-spec" }
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
#endif
    }
}
