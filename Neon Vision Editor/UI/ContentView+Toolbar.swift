import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

    private var iPhonePromotedActionsCount: Int {
        switch iPhoneToolbarWidth {
        case 430...: return 4
        case 395...: return 3
        default: return 1
        }
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
        case saveFile
        case markdownPreview
        case fontDecrease
        case fontIncrease
        case toggleSidebar
        case toggleProjectSidebar
        case findReplace
        case settings
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
            .saveFile,
            .markdownPreview,
            .fontDecrease,
            .fontIncrease,
            .toggleSidebar,
            .toggleProjectSidebar,
            .findReplace,
            .settings,
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
            .performanceMode,
            .brainDump,
            .welcomeTour,
            .translucentWindow
        ]
    }

    private var iPadAlwaysVisibleActions: [IPadToolbarAction] {
        [.openFile, .newTab, .saveFile, .findReplace, .settings]
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
    private var languagePickerControl: some View {
        Menu {
            ForEach(languageOptions, id: \.self) { lang in
                Button {
                    currentLanguagePickerBinding.wrappedValue = lang
                } label: {
                    if lang == currentLanguagePickerBinding.wrappedValue {
                        Label(languageLabel(for: lang), systemImage: "checkmark")
                    } else {
                        Text(languageLabel(for: lang))
                    }
                }
            }
            Divider()
            Button(action: { presentLanguageSearchSheet() }) {
                Label("Language…", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        } label: {
            Text(toolbarCompactLanguageLabel(currentLanguagePickerBinding.wrappedValue))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .labelsHidden()
        .help("Language")
        .accessibilityLabel("Language picker")
        .accessibilityHint("Choose syntax language for the current tab")
        .frame(width: isIPadToolbarLayout ? 112 : iPhoneLanguagePickerWidth)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .tint(iOSToolbarTintColor)
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
        .disabled(viewModel.selectedTab == nil)
        .help("Save File (Cmd+S)")
        .accessibilityLabel("Save file")
        .accessibilityHint("Saves the current tab")
        .keyboardShortcut("s", modifiers: .command)
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
    private func iPadToolbarActionControl(_ action: IPadToolbarAction) -> some View {
        switch action {
        case .openFile: openFileControl
        case .undo: undoControl
        case .newTab: newTabControl
        case .saveFile: saveFileControl
        case .markdownPreview: markdownPreviewControl
        case .fontDecrease: fontDecreaseControl
        case .fontIncrease: fontIncreaseControl
        case .toggleSidebar: toggleSidebarControl
        case .toggleProjectSidebar: toggleProjectSidebarControl
        case .findReplace: findReplaceControl
        case .settings: settingsControl
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
        if !iPadOverflowActions.isEmpty {
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
                    case .saveFile:
                        Button(action: { saveCurrentTabFromToolbar() }) {
                            Label("Save File", systemImage: "square.and.arrow.down")
                        }
                        .disabled(viewModel.selectedTab == nil)
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
                    case .settings:
                        Button(action: { openSettings() }) {
                            Label("Settings", systemImage: "gearshape")
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
            }
            .help("More Actions")
        }
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
    private var iOSToolbarControls: some View {
        openFileControl
        undoControl
        if iPhonePromotedActionsCount >= 2 { newTabControl }
        if iPhonePromotedActionsCount >= 3 { saveFileControl }
        if iPhonePromotedActionsCount >= 4 { findReplaceControl }
        keyboardAccessoryControl
        Divider()
            .frame(height: 18)
        moreActionsControl
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
            HStack(spacing: 12) {
                languagePickerControl
                iOSToolbarControls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
        ForEach(iPadPromotedActions, id: \.self) { action in
            iPadToolbarActionControl(action)
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
        }
        ForEach(iPadAlwaysVisibleActions, id: \.self) { action in
            iPadToolbarActionControl(action)
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Rectangle())
        }
        if !iPadOverflowActions.isEmpty {
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)
            iPadOverflowMenuControl
        }
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
                        HStack(spacing: 6) {
                            iPadDistributedToolbarControls
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: iPadToolbarMaxWidth, alignment: .center)
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
                        HStack(spacing: 6) {
                            iPadDistributedToolbarControls
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .frame(maxWidth: iPadToolbarMaxWidth, alignment: .center)
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
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Open File… (Cmd+O)")

            Button(action: { viewModel.addNewTab() }) {
                Label("New Tab", systemImage: "plus.square.on.square")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("New Tab (Cmd+T)")

            Button(action: {
                saveCurrentTabFromToolbar()
            }) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .disabled(viewModel.selectedTab == nil)
            .help("Save File (Cmd+S)")

            Button(action: {
                showFindReplace = true
            }) {
                Label("Find", systemImage: "magnifyingglass")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Find & Replace (Cmd+F)")

            Button(action: {
                openSettings()
            }) {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Settings")
        }

        ToolbarItemGroup(placement: .automatic) {
            Menu {
                ForEach(languageOptions, id: \.self) { lang in
                    Button {
                        currentLanguagePickerBinding.wrappedValue = lang
                    } label: {
                        if lang == currentLanguagePickerBinding.wrappedValue {
                            Label(languageLabel(for: lang), systemImage: "checkmark")
                        } else {
                            Text(languageLabel(for: lang))
                        }
                    }
                }
                Divider()
                Button(action: { presentLanguageSearchSheet() }) {
                    Label("Language…", systemImage: "magnifyingglass")
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
                        .foregroundStyle(NeonUIStyle.accentBlue)
                }
                .disabled(currentLanguage != "markdown")
                .help("Toggle Markdown Preview")

                if showMarkdownPreviewPane && currentLanguage == "markdown" {
                    Menu {
                        Button("Default") { markdownPreviewTemplateRaw = "default" }
                        Button("Docs") { markdownPreviewTemplateRaw = "docs" }
                        Button("Article") { markdownPreviewTemplateRaw = "article" }
                        Button("Compact") { markdownPreviewTemplateRaw = "compact" }
                    } label: {
                        Label("Preview Style", systemImage: "textformat.size")
                            .foregroundStyle(NeonUIStyle.accentBlue)
                    }
                    .help("Markdown Preview Template")
                }
            }
            #endif

            Button(action: { undoFromToolbar() }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Undo (Cmd+Z)")
            .keyboardShortcut("z", modifiers: .command)

            if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                Button(action: {
                    showUpdaterDialog(checkNow: true)
                }) {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle")
                        .foregroundStyle(NeonUIStyle.accentBlue)
                }
                .help("Check for Updates")
            }

            #if os(macOS)
            Button(action: {
                openWindow(id: "blank-window")
            }) {
                Label("New Window", systemImage: "macwindow.badge.plus")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("New Window (Cmd+N)")
            #endif

            Button(action: { adjustEditorFontSize(-1) }) {
                Label("Font -", systemImage: "textformat.size.smaller")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Decrease Font Size")

            Button(action: { adjustEditorFontSize(1) }) {
                Label("Font +", systemImage: "textformat.size.larger")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Increase Font Size")

            Button(action: {
                requestClearEditorContent()
            }) {
                Label("Clear", systemImage: "eraser")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Clear Editor")

            Button(action: {
                insertTemplateForCurrentLanguage()
            }) {
                Label("Template", systemImage: "doc.badge.plus")
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Insert Template for Current Language")

            Button(action: {
                toggleSidebarFromToolbar()
            }) {
                Label("Sidebar", systemImage: "sidebar.left")
                    .foregroundStyle(NeonUIStyle.accentBlue)
                    .symbolVariant(viewModel.showSidebar ? .fill : .none)
            }
            .help("Toggle Sidebar (Cmd+Opt+S)")

            Button(action: {
                toggleProjectSidebarFromToolbar()
            }) {
                Label("Project", systemImage: "sidebar.right")
                    .foregroundStyle(NeonUIStyle.accentBlue)
                    .symbolVariant(showProjectStructureSidebar ? .fill : .none)
            }
            .help("Toggle Project Structure Sidebar")

            Button(action: {
                toggleAutoCompletion()
            }) {
                Label("AI", systemImage: "bolt.horizontal.circle")
                    .foregroundStyle(NeonUIStyle.accentBlue)
                    .symbolVariant(isAutoCompletionEnabled ? .fill : .none)
            }
            .help(isAutoCompletionEnabled ? "Disable Code Completion" : "Enable Code Completion")
            .accessibilityLabel("Code Completion")

            Button(action: {
                showBracketHelperBarMac.toggle()
            }) {
                Label("Brackets", systemImage: "chevron.left.chevron.right")
                    .foregroundStyle(NeonUIStyle.accentBlue)
                    .symbolVariant(showBracketHelperBarMac ? .fill : .none)
            }
            .help(showBracketHelperBarMac ? "Hide Bracket Helper Bar" : "Show Bracket Helper Bar")
            .accessibilityLabel("Bracket Helper Bar")

            Button(action: {
                viewModel.isBrainDumpMode.toggle()
                UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
            }) {
                Label("Brain Dump", systemImage: "note.text")
                    .foregroundStyle(NeonUIStyle.accentBlue)
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
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .help("Toggle Translucent Window Background")
            .accessibilityLabel("Translucent Window Background")

        }
#endif
    }
}
