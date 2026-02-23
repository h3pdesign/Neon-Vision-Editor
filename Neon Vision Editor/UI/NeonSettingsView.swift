import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NeonSettingsView: View {
    private static var cachedEditorFonts: [String] = []
    let supportsOpenInTabs: Bool
    let supportsTranslucency: Bool
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("SettingsOpenInTabs") private var openInTabs: String = "system"
    @AppStorage("SettingsEditorFontName") private var editorFontName: String = ""
    @AppStorage("SettingsUseSystemFont") private var useSystemFont: Bool = false
    @AppStorage("SettingsEditorFontSize") private var editorFontSize: Double = 14
    @AppStorage("SettingsLineHeight") private var lineHeight: Double = 1.0
    @AppStorage("SettingsAppearance") private var appearance: String = "system"
#if os(iOS)
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = true
#else
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
#endif
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
    @AppStorage("SettingsReopenLastSession") private var reopenLastSession: Bool = true
    @AppStorage("SettingsOpenWithBlankDocument") private var openWithBlankDocument: Bool = true
    @AppStorage("SettingsDefaultNewFileLanguage") private var defaultNewFileLanguage: String = "plain"
    @AppStorage("SettingsConfirmCloseDirtyTab") private var confirmCloseDirtyTab: Bool = true
    @AppStorage("SettingsConfirmClearEditor") private var confirmClearEditor: Bool = true
    @AppStorage(AppUpdateManager.autoCheckEnabledKey) private var autoCheckForUpdates: Bool = true
    @AppStorage(AppUpdateManager.updateIntervalKey) private var updateCheckIntervalRaw: String = AppUpdateCheckInterval.daily.rawValue
    @AppStorage(AppUpdateManager.autoDownloadEnabledKey) private var autoDownloadUpdates: Bool = false

    @AppStorage("SettingsShowLineNumbers") private var showLineNumbers: Bool = true
    @AppStorage("SettingsHighlightCurrentLine") private var highlightCurrentLine: Bool = false
    @AppStorage("SettingsHighlightMatchingBrackets") private var highlightMatchingBrackets: Bool = false
    @AppStorage("SettingsShowScopeGuides") private var showScopeGuides: Bool = false
    @AppStorage("SettingsHighlightScopeBackground") private var highlightScopeBackground: Bool = false
    @AppStorage("SettingsLineWrapEnabled") private var lineWrapEnabled: Bool = false
    @AppStorage("SettingsIndentStyle") private var indentStyle: String = "spaces"
    @AppStorage("SettingsIndentWidth") private var indentWidth: Int = 4
    @AppStorage("SettingsAutoIndent") private var autoIndent: Bool = true
    @AppStorage("SettingsAutoCloseBrackets") private var autoCloseBrackets: Bool = false
    @AppStorage("SettingsTrimTrailingWhitespace") private var trimTrailingWhitespace: Bool = false
    @AppStorage("SettingsTrimWhitespaceForSyntaxDetection") private var trimWhitespaceForSyntaxDetection: Bool = false
    @AppStorage("SettingsFindKeepFocus") private var findKeepFocus: Bool = false

    @AppStorage("SettingsCompletionEnabled") private var completionEnabled: Bool = false
    @AppStorage("SettingsCompletionFromDocument") private var completionFromDocument: Bool = false
    @AppStorage("SettingsCompletionFromSyntax") private var completionFromSyntax: Bool = false
    @AppStorage("SelectedAIModel") private var selectedAIModelRaw: String = AIModel.appleIntelligence.rawValue
    @AppStorage("SettingsActiveTab") private var settingsActiveTab: String = "general"
    @AppStorage("SettingsTemplateLanguage") private var settingsTemplateLanguage: String = "swift"
    @State private var grokAPIToken: String = ""
    @State private var openAIAPIToken: String = ""
    @State private var geminiAPIToken: String = ""
    @State private var anthropicAPIToken: String = ""
    @State private var showSupportPurchaseDialog: Bool = false
    @State private var showDataDisclosureDialog: Bool = false
    @State private var availableEditorFonts: [String] = []
    @State private var moreSectionTab: String = "support"
    private let privacyPolicyURL = URL(string: "https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/PRIVACY.md")
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

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
    
    private var inputFieldBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.secondarySystemBackground)
#endif
    }

    private let themes: [String] = editorThemeNames

    private let templateLanguages: [String] = [
        "swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust",
        "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp",
        "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb",
        "markdown", "bash", "zsh", "powershell", "standard", "plain"
    ]
    
    private var isCompactSettingsLayout: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var useTwoColumnSettingsLayout: Bool {
#if os(iOS)
        horizontalSizeClass == .regular
#else
        false
#endif
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
        static let sidePaddingIPadRegular: CGFloat = 40
        static let topPadding: CGFloat = 14
        static let bottomPadding: CGFloat = 16
        static let cardCorner: CGFloat = 12
        static let cardStrokeOpacity: Double = 0.15
    }

    private enum Typography {
        static let sectionHeadline = Font.headline
        static let sectionSubheadline = Font.subheadline
        static let footnote = Font.footnote
        static let monoBody = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let sectionTitle = Font.title3.weight(.semibold)
    }

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

    init(
        supportsOpenInTabs: Bool = true,
        supportsTranslucency: Bool = true
    ) {
        self.supportsOpenInTabs = supportsOpenInTabs
        self.supportsTranslucency = supportsTranslucency
    }

    private var settingsTabs: some View {
        TabView(selection: $settingsActiveTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            editorTab
                .tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
                .tag("editor")
            templateTab
                .tabItem { Label("Templates", systemImage: "doc.badge.plus") }
                .tag("templates")
            themeTab
                .tabItem { Label("Themes", systemImage: "paintpalette") }
                .tag("themes")
            #if os(iOS)
            moreTab
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag("more")
            #else
            supportTab
                .tabItem { Label("Support", systemImage: "heart") }
                .tag("support")
            aiTab
                .tabItem { Label("AI", systemImage: "brain.head.profile") }
                .tag("ai")
            #endif
#if os(macOS)
            if ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution {
                updatesTab
                    .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle") }
                    .tag("updates")
            }
#endif
        }
    }

    var body: some View {
        settingsTabs
#if os(macOS)
        .frame(
            minWidth: macSettingsWindowSize.min.width,
            idealWidth: macSettingsWindowSize.ideal.width,
            minHeight: macSettingsWindowSize.min.height,
            idealHeight: macSettingsWindowSize.ideal.height
        )
        .background(
            SettingsWindowConfigurator(
                minSize: macSettingsWindowSize.min,
                idealSize: macSettingsWindowSize.ideal,
                translucentEnabled: supportsTranslucency && translucentWindow
            )
        )
#endif
        .preferredColorScheme(preferredColorSchemeOverride)
        .onAppear {
            if settingsActiveTab.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settingsActiveTab = "general"
            }
            moreSectionTab = useTwoColumnSettingsLayout ? "support" : "ai"
            selectedTheme = canonicalThemeName(selectedTheme)
            migrateLegacyPinkSettingsIfNeeded()
            loadAvailableEditorFontsIfNeeded()
            if settingsActiveTab == "ai" || (settingsActiveTab == "more" && moreSectionTab == "ai") {
                loadAPITokensIfNeeded()
            }
            if settingsActiveTab == "support" || (settingsActiveTab == "more" && moreSectionTab == "support") {
                Task { await supportPurchaseManager.refreshStoreState() }
            }
            if supportPurchaseManager.supportProduct == nil {
                Task { await supportPurchaseManager.refreshStoreState() }
            }
            appUpdateManager.setAutoCheckEnabled(autoCheckForUpdates)
            appUpdateManager.setUpdateInterval(selectedUpdateInterval)
            appUpdateManager.setAutoDownloadEnabled(autoDownloadUpdates)
#if os(macOS)
            applyAppearanceImmediately()
#endif
        }
        .onChange(of: appearance) { _, _ in
#if os(macOS)
            applyAppearanceImmediately()
#endif
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
            #if os(iOS)
            if newValue == "more" {
                moreSectionTab = "support"
            }
            #else
            if newValue == "ai" {
                loadAPITokensIfNeeded()
            } else if newValue == "support" {
                Task { await supportPurchaseManager.refreshStoreState() }
            }
            #endif
        }
        .onChange(of: moreSectionTab) { _, newValue in
            if newValue == "ai" && settingsActiveTab == "more" {
                loadAPITokensIfNeeded()
            } else if newValue == "support" && settingsActiveTab == "more" {
                Task { await supportPurchaseManager.refreshStoreState() }
            }
        }
        .onChange(of: selectedTheme) { _, newValue in
            let canonical = canonicalThemeName(newValue)
            if canonical != newValue {
                selectedTheme = canonical
            }
        }
        .confirmationDialog("Support Neon Vision Editor", isPresented: $showSupportPurchaseDialog, titleVisibility: .visible) {
            Button("Send Tip \(supportPurchaseManager.supportPriceLabel)") {
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
    }

    private func loadAPITokensIfNeeded() {
        if grokAPIToken.isEmpty { grokAPIToken = SecureTokenStore.token(for: .grok) }
        if openAIAPIToken.isEmpty { openAIAPIToken = SecureTokenStore.token(for: .openAI) }
        if geminiAPIToken.isEmpty { geminiAPIToken = SecureTokenStore.token(for: .gemini) }
        if anthropicAPIToken.isEmpty { anthropicAPIToken = SecureTokenStore.token(for: .anthropic) }
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

    private var generalTab: some View {
        settingsContainer {
            settingsSectionHeader(
                icon: "gearshape",
                title: "General",
                subtitle: "Window behavior, startup defaults, and confirmation preferences."
            )

            if useTwoColumnSettingsLayout {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: UI.space16), GridItem(.flexible(), spacing: UI.space16)], spacing: UI.space16) {
                    windowSection
                    editorFontSection
                    startupSection
                    confirmationsSection
                }
            } else {
                windowSection
                editorFontSection
                startupSection
                confirmationsSection
            }
        }
    }

    private var windowSection: some View {
        GroupBox("Window") {
#if os(iOS)
            VStack(alignment: .leading, spacing: UI.space12) {
                if supportsOpenInTabs {
                    iOSLabeledRow("Open in Tabs") {
                        Picker("", selection: $openInTabs) {
                            Text("Follow System").tag("system")
                            Text("Always").tag("always")
                            Text("Never").tag("never")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                iOSLabeledRow("Appearance") {
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                if supportsTranslucency {
                    iOSToggleRow("Translucent Window", isOn: $translucentWindow)
                }
            }
            .padding(UI.groupPadding)
#else
            VStack(alignment: .leading, spacing: UI.space12) {
                if supportsOpenInTabs {
                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Open in Tabs")
                            .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                        Picker("", selection: $openInTabs) {
                            Text("Follow System").tag("system")
                            Text("Always").tag("always")
                            Text("Never").tag("never")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text("Appearance")
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                if supportsTranslucency {
                    Toggle("Translucent Window", isOn: $translucentWindow)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Translucency Mode")
                            .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                        Picker("", selection: $macTranslucencyModeRaw) {
                            ForEach(MacTranslucencyModeOption.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!translucentWindow)
                    }
                }
            }
            .padding(UI.groupPadding)
#endif
        }
    }

    private var editorFontSection: some View {
        GroupBox("Editor Font") {
#if os(iOS)
            VStack(alignment: .leading, spacing: UI.space12) {
                iOSToggleRow("Use System Font", isOn: $useSystemFont)

                iOSLabeledRow("Font") {
                    Picker("", selection: selectedFontBinding) {
                        Text("System").tag(systemFontSentinel)
                        ForEach(availableEditorFonts, id: \.self) { fontName in
                            Text(fontName).tag(fontName)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.vertical, UI.space6)
                    .padding(.horizontal, UI.space8)
                    .background(inputFieldBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: UI.fieldCorner)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .cornerRadius(UI.fieldCorner)
                }

                iOSLabeledRow("Font Size") {
                    HStack(spacing: UI.space12) {
                        Text("\(Int(editorFontSize)) pt")
                            .font(.body.monospacedDigit())
                            .frame(minWidth: 64, alignment: .trailing)
                        Stepper("", value: $editorFontSize, in: 10...28, step: 1)
                            .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: UI.space8) {
                    HStack(alignment: .firstTextBaseline, spacing: UI.space12) {
                        Text("Line Height")
                            .frame(width: iOSSettingsLabelWidth, alignment: .leading)
                        Spacer(minLength: 0)
                        Text(String(format: "%.2fx", lineHeight))
                            .font(.body.monospacedDigit())
                            .frame(width: 64, alignment: .trailing)
                    }
                    Slider(value: $lineHeight, in: 1.0...1.8, step: 0.05)
                }
            }
            .padding(UI.groupPadding)
#else
            VStack(alignment: .leading, spacing: UI.space12) {
                Toggle("Use System Font", isOn: $useSystemFont)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center, spacing: UI.space12) {
                    Text("Font")
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: UI.space8) {
                        HStack(spacing: UI.space8) {
                            Text(useSystemFont ? "System" : (editorFontName.isEmpty ? "System" : editorFontName))
                                .font(Typography.footnote)
                                .foregroundStyle(.secondary)
                            Button(showFontList ? "Hide Font List" : "Show Font List") {
                                showFontList.toggle()
                            }
                            .buttonStyle(.borderless)
                        }
                        if showFontList {
                            Picker("", selection: selectedFontBinding) {
                                Text("System").tag(systemFontSentinel)
                                ForEach(availableEditorFonts, id: \.self) { fontName in
                                    Text(fontName).tag(fontName)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.vertical, UI.space6)
                            .padding(.horizontal, UI.space8)
                            .background(inputFieldBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: UI.fieldCorner)
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                            .cornerRadius(UI.fieldCorner)
                        }
                    }
                    .frame(maxWidth: isCompactSettingsLayout ? .infinity : 240, alignment: .leading)
#if os(macOS)
                    Button("Choose…") {
                        useSystemFont = false
                        showFontList = true
                    }
                    .disabled(useSystemFont)
#endif
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text("Font Size")
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Stepper(value: $editorFontSize, in: 10...28, step: 1) {
                        Text("\(Int(editorFontSize)) pt")
                    }
                    .frame(maxWidth: isCompactSettingsLayout ? .infinity : 220, alignment: .leading)
                }

                HStack(alignment: .center, spacing: UI.space12) {
                    Text("Line Height")
                        .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
                    Slider(value: $lineHeight, in: 1.0...1.8, step: 0.05)
                        .frame(maxWidth: isCompactSettingsLayout ? .infinity : 240)
                    Text(String(format: "%.2fx", lineHeight))
                        .frame(width: 54, alignment: .trailing)
                }
            }
            .padding(UI.groupPadding)
#endif
        }
    }

    private var startupSection: some View {
        GroupBox("Startup") {
            VStack(alignment: .leading, spacing: UI.space12) {
                Toggle("Open with Blank Document", isOn: $openWithBlankDocument)
                    .disabled(reopenLastSession)
                Toggle("Reopen Last Session", isOn: $reopenLastSession)
                HStack(alignment: .center, spacing: UI.space12) {
                    Text("Default New File Language")
                        .frame(width: isCompactSettingsLayout ? nil : startupLabelWidth, alignment: .leading)
                    Picker("", selection: $defaultNewFileLanguage) {
                        ForEach(templateLanguages, id: \.self) { lang in
                            Text(languageLabel(for: lang)).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Text("Tip: Enable only one startup mode to keep app launch behavior predictable.")
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(UI.groupPadding)
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
    }

    private var confirmationsSection: some View {
        GroupBox("Confirmations") {
            VStack(alignment: .leading, spacing: UI.space12) {
                Toggle("Confirm Before Closing Dirty Tab", isOn: $confirmCloseDirtyTab)
                Toggle("Confirm Before Clearing Editor", isOn: $confirmClearEditor)
            }
            .padding(UI.groupPadding)
        }
    }

#if os(iOS)
    private var iOSSettingsLabelWidth: CGFloat {
        useTwoColumnSettingsLayout ? 176 : 138
    }

    private func iOSLabeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: UI.space12) {
            Text(label)
                .frame(width: iOSSettingsLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iOSToggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: UI.space12) {
            Text(label)
                .frame(width: iOSSettingsLabelWidth, alignment: .leading)
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }
#endif

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
        // Defer font discovery until after the initial settings view appears.
        DispatchQueue.main.async {
            populateEditorFonts()
        }
    }

    private func populateEditorFonts() {
#if os(macOS)
        let names = NSFontManager.shared.availableFonts
#else
        let names = UIFont.familyNames
            .sorted()
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
#endif
        var merged = Array(Set(names)).sorted()
        if !editorFontName.isEmpty && !merged.contains(editorFontName) {
            merged.insert(editorFontName, at: 0)
        }
        Self.cachedEditorFonts = merged
        availableEditorFonts = merged
        syncSelectedFontValue()
    }

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

    private var editorTab: some View {
        settingsContainer(maxWidth: 760) {
            settingsSectionHeader(
                icon: "slider.horizontal.3",
                title: "Editor",
                subtitle: "Display, indentation, editing behavior, and completion sources."
            )
            GroupBox("Editor") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: UI.space10) {
                        Text("Display")
                            .font(Typography.sectionHeadline)
                        Toggle("Show Line Numbers", isOn: $showLineNumbers)
                        Toggle("Highlight Current Line", isOn: $highlightCurrentLine)
                        Toggle("Highlight Matching Brackets", isOn: $highlightMatchingBrackets)
                        Toggle("Show Scope Guides (Non-Swift)", isOn: $showScopeGuides)
                        Toggle("Highlight Scoped Region", isOn: $highlightScopeBackground)
                        Toggle("Line Wrap", isOn: $lineWrapEnabled)
                        Text("When Line Wrap is enabled, scope guides/scoped region are turned off to avoid layout conflicts.")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                        Text("Scope guides are intended for non-Swift languages. Swift favors matching-token highlight.")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                        Text("Invisible character markers are disabled to avoid whitespace glyph artifacts.")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: UI.space10) {
                        Text("Indentation")
                            .font(Typography.sectionHeadline)
                        Picker("Indent Style", selection: $indentStyle) {
                            Text("Spaces").tag("spaces")
                            Text("Tabs").tag("tabs")
                        }
                        .pickerStyle(.segmented)

                        Stepper(value: $indentWidth, in: 2...8, step: 1) {
                            Text("Indent Width: \(indentWidth)")
                        }
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
                        Toggle("Keep Focus in Find Panel After Search", isOn: $findKeepFocus)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

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
        }
    }

    private var templateTab: some View {
        settingsContainer(maxWidth: 640) {
            settingsSectionHeader(
                icon: "doc.badge.plus",
                title: "Templates",
                subtitle: "Control language-specific starter content used when inserting templates."
            )
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
                        .frame(maxWidth: isCompactSettingsLayout ? .infinity : 220, alignment: .leading)
                        .pickerStyle(.menu)
                        .padding(.vertical, UI.space6)
                        .padding(.horizontal, UI.space8)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(8)
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
        }
    }

    private var themeTab: some View {
        let isCustom = selectedTheme == "Custom"
        let palette = themePaletteColors(for: selectedTheme)
        let previewTheme = currentEditorTheme(colorScheme: effectiveSettingsColorScheme)
        return settingsContainer(maxWidth: 760) {
            settingsSectionHeader(
                icon: "paintpalette",
                title: "Themes",
                subtitle: "Pick a preset or customize token colors for your editing environment."
            )
            HStack(alignment: .top, spacing: UI.space16) {
                Group {
#if os(macOS)
                    let listView = List(themes, id: \.self, selection: $selectedTheme) { theme in
                        HStack {
                            Text(theme)
                            Spacer(minLength: 8)
                            if theme == selectedTheme {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .listRowBackground(Color.clear)
                    }
                    .frame(minWidth: 200)
                    .listStyle(.plain)
                    .background(Color.clear)
                    if #available(macOS 13.0, *) {
                        listView.scrollContentBackground(.hidden)
                    } else {
                        listView
                    }
#else
                    let listView = List {
                        ForEach(themes, id: \.self) { theme in
                            HStack {
                                Text(theme)
                                Spacer()
                                if theme == selectedTheme {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
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
                    .frame(minWidth: isCompactSettingsLayout ? nil : 200)
                    .listStyle(.plain)
                    .background(Color.clear)
                    if #available(iOS 16.0, *) {
                        listView.scrollContentBackground(.hidden)
                    } else {
                        listView
                    }
#endif
                }
                .padding(UI.space8)
                .background(settingsCardBackground(cornerRadius: UI.cardCorner))

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

                    themePreviewSnippet(previewTheme: previewTheme)

                    VStack(alignment: .leading, spacing: UI.space10) {
                        Text("Base")
                            .font(Typography.sectionSubheadline)
                            .foregroundStyle(.secondary)

                        colorRow(title: "Text", color: isCustom ? hexBinding($themeTextHex, fallback: .white) : .constant(palette.text))
                            .disabled(!isCustom)
                        colorRow(title: "Background", color: isCustom ? hexBinding($themeBackgroundHex, fallback: .black) : .constant(palette.background))
                            .disabled(!isCustom)
                        colorRow(title: "Cursor", color: isCustom ? hexBinding($themeCursorHex, fallback: .blue) : .constant(palette.cursor))
                            .disabled(!isCustom)
                        colorRow(title: "Selection", color: isCustom ? hexBinding($themeSelectionHex, fallback: .gray) : .constant(palette.selection))
                            .disabled(!isCustom)
                    }
                    .padding(UI.space12)
                    .background(settingsCardBackground(cornerRadius: UI.cardCorner))

                    VStack(alignment: .leading, spacing: UI.space10) {
                        Text("Syntax")
                            .font(Typography.sectionSubheadline)
                            .foregroundStyle(.secondary)

                        colorRow(title: "Keywords", color: isCustom ? hexBinding($themeKeywordHex, fallback: .yellow) : .constant(palette.keyword))
                            .disabled(!isCustom)
                        colorRow(title: "Strings", color: isCustom ? hexBinding($themeStringHex, fallback: .blue) : .constant(palette.string))
                            .disabled(!isCustom)
                        colorRow(title: "Numbers", color: isCustom ? hexBinding($themeNumberHex, fallback: .orange) : .constant(palette.number))
                            .disabled(!isCustom)
                        colorRow(title: "Comments", color: isCustom ? hexBinding($themeCommentHex, fallback: .gray) : .constant(palette.comment))
                            .disabled(!isCustom)
                        colorRow(title: "Types", color: isCustom ? hexBinding($themeTypeHex, fallback: .green) : .constant(palette.type))
                            .disabled(!isCustom)
                        colorRow(title: "Builtins", color: isCustom ? hexBinding($themeBuiltinHex, fallback: .red) : .constant(palette.builtin))
                            .disabled(!isCustom)
                    }
                    .padding(UI.space12)
                    .background(settingsCardBackground(cornerRadius: UI.cardCorner))

                    Text(isCustom ? "Custom theme applies immediately." : "Select Custom to edit colors.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(UI.space12)
                .background(settingsCardBackground(cornerRadius: 14))
            }
#if os(iOS)
            .padding(.top, 20)
#endif
        }
    }

    private var selectedAIModelBinding: Binding<AIModel> {
        Binding(
            get: { AIModel(rawValue: selectedAIModelRaw) ?? .appleIntelligence },
            set: { selectedAIModelRaw = $0.rawValue }
        )
    }

    private var moreTab: some View {
        settingsContainer(maxWidth: 560) {
            VStack(alignment: .leading, spacing: UI.space12) {
                settingsSectionHeader(
                    icon: "ellipsis.circle",
                    title: "More",
                    subtitle: "AI setup, provider credentials, and support options."
                )
                Picker("More Section", selection: $moreSectionTab) {
                    Text("Support").tag("support")
                    Text("AI").tag("ai")
                }
                .pickerStyle(.segmented)
            }
            .padding(UI.groupPadding)
            .background(settingsCardBackground(cornerRadius: 14))

            ZStack {
                if moreSectionTab == "ai" {
                    aiSection
                        .transition(.opacity)
                } else {
                    supportSection
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: moreSectionTab)
        }
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
        }
    }

    private var aiSection: some View {
        VStack(spacing: UI.space20) {
            GroupBox("AI Model") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Picker("Model", selection: selectedAIModelBinding) {
                        Text("Apple Intelligence").tag(AIModel.appleIntelligence)
                        Text("Grok").tag(AIModel.grok)
                        Text("OpenAI").tag(AIModel.openAI)
                        Text("Gemini").tag(AIModel.gemini)
                        Text("Anthropic").tag(AIModel.anthropic)
                    }
                    .pickerStyle(.menu)

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
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(UI.groupPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var supportSection: some View {
        VStack(spacing: 0) {
            GroupBox("Support Development") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Text("In-App Purchase is optional and only used to support the app.")
                        .foregroundStyle(.secondary)
                    Text("Consumable support purchase. Can be purchased multiple times. No subscription and no auto-renewal.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    if supportPurchaseManager.canUseInAppPurchases {
                        Text("Price: \(supportPurchaseManager.supportPriceLabel)")
                            .font(Typography.sectionHeadline)
                        HStack(spacing: UI.space12) {
                            Button(supportPurchaseManager.isPurchasing ? "Purchasing…" : "Send Support Tip") {
                                guard supportPurchaseManager.supportProduct != nil else {
                                    Task { await supportPurchaseManager.refreshPrice() }
                                    supportPurchaseManager.statusMessage = "Loading App Store product. Please try again in a moment."
                                    return
                                }
                                showSupportPurchaseDialog = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                supportPurchaseManager.isPurchasing
                                || supportPurchaseManager.isLoadingProducts
                                || supportPurchaseManager.supportProduct == nil
                            )

                            Button("Refresh Price") {
                                Task { await supportPurchaseManager.refreshPrice() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(supportPurchaseManager.isLoadingProducts)
                        }
                    } else {
                        Text("Direct notarized builds are unaffected: all editor features stay fully available without any purchase.")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                        Text("Support purchase is available only in App Store/TestFlight builds.")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let privacyPolicyURL {
                        Link("Privacy Policy", destination: privacyPolicyURL)
                            .font(.footnote.weight(.semibold))
                    }

                    if let termsOfUseURL {
                        Link("Terms of Use (EULA)", destination: termsOfUseURL)
                            .font(.footnote.weight(.semibold))
                    }

                    if supportPurchaseManager.canBypassInCurrentBuild {
                        Divider()
                        Text("TestFlight/Sandbox: You can bypass purchase for testing.")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: UI.space12) {
                            Button("Bypass Purchase (Testing)") {
                                supportPurchaseManager.bypassForTesting()
                            }
                            Button("Clear Bypass") {
                                supportPurchaseManager.clearBypassForTesting()
                            }
                        }
                    }
                }
                .padding(UI.groupPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

#if os(macOS)
    private var updatesTab: some View {
        settingsContainer(maxWidth: 620) {
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
                        .pickerStyle(.menu)
                        .frame(maxWidth: isCompactSettingsLayout ? .infinity : 220, alignment: .leading)
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
                            Text("Last checked: \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(Typography.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: UI.space6) {
                        Text("Last check result: \(appUpdateManager.lastCheckResultSummary)")
                            .font(Typography.footnote)
                            .foregroundStyle(.secondary)
                        if let pausedUntil = appUpdateManager.pausedUntil, pausedUntil > Date() {
                            Text("Auto-check pause active until \(pausedUntil.formatted(date: .abbreviated, time: .shortened)) (\(appUpdateManager.consecutiveFailureCount) consecutive failures).")
                                .font(Typography.footnote)
                                .foregroundStyle(.orange)
                        }
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
#endif

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func settingsSectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: UI.space12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: UI.space6) {
                Text(title)
                    .font(Typography.sectionTitle)
                Text(subtitle)
                    .font(Typography.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsContainer<Content: View>(maxWidth: CGFloat = 560, @ViewBuilder _ content: () -> Content) -> some View {
        let effectiveMaxWidth = settingsEffectiveMaxWidth(base: maxWidth)
        return ScrollView {
            VStack(alignment: settingsShouldUseLeadingAlignment ? .leading : .center, spacing: UI.space20) {
                content()
            }
            .frame(maxWidth: effectiveMaxWidth, alignment: settingsShouldUseLeadingAlignment ? .leading : .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settingsShouldUseLeadingAlignment ? .topLeading : .top)
            .padding(.top, UI.topPadding)
            .padding(.bottom, UI.bottomPadding)
            .padding(.horizontal, settingsHorizontalPadding)
        }
        .background(settingsContainerBackground)
    }

    private var settingsHorizontalPadding: CGFloat {
#if os(iOS)
        if isCompactSettingsLayout { return UI.sidePaddingCompact }
        if useTwoColumnSettingsLayout { return UI.sidePaddingIPadRegular }
        return UI.sidePaddingRegular
#else
        return isCompactSettingsLayout ? UI.sidePaddingCompact : 4
#endif
    }

    @ViewBuilder
    private var settingsContainerBackground: some View {
#if os(macOS)
        if supportsTranslucency && translucentWindow {
            Color.clear.background(.ultraThinMaterial)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
#else
        Color.clear.background(.ultraThinMaterial)
#endif
    }

    private func settingsEffectiveMaxWidth(base: CGFloat) -> CGFloat {
#if os(iOS)
        if useTwoColumnSettingsLayout { return max(base, 780) }
        return base
#else
        return macSettingsContentMaxWidth
#endif
    }

    private func settingsCardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(UI.cardStrokeOpacity), lineWidth: 1)
            )
    }

    private var effectiveSettingsColorScheme: ColorScheme {
        preferredColorSchemeOverride ?? systemColorScheme
    }

    private func colorRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .frame(width: isCompactSettingsLayout ? nil : standardLabelWidth, alignment: .leading)
            ColorPicker("", selection: color)
                .labelsHidden()
            Spacer()
        }
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

    private var settingsShouldUseLeadingAlignment: Bool {
#if os(iOS)
        true
#else
        false
#endif
    }

#if os(macOS)
    private var macSettingsContentMaxWidth: CGFloat {
        switch settingsActiveTab {
        case "themes":
            return 720
        case "editor":
            return 580
        case "templates":
            return 540
        case "general":
            return 540
        case "ai":
            return 580
        case "updates":
            return 520
        case "support":
            return 520
        default:
            return 540
        }
    }

    private var macSettingsWindowSize: (min: NSSize, ideal: NSSize) {
        switch settingsActiveTab {
        case "themes":
            return (NSSize(width: 740, height: 900), NSSize(width: 840, height: 980))
        case "editor":
            return (NSSize(width: 640, height: 820), NSSize(width: 720, height: 900))
        case "templates":
            return (NSSize(width: 600, height: 760), NSSize(width: 680, height: 840))
        case "general":
            return (NSSize(width: 600, height: 760), NSSize(width: 680, height: 840))
        case "ai":
            return (NSSize(width: 640, height: 780), NSSize(width: 720, height: 860))
        case "updates":
            return (NSSize(width: 580, height: 720), NSSize(width: 660, height: 780))
        case "support":
            return (NSSize(width: 580, height: 720), NSSize(width: 660, height: 780))
        default:
            return (NSSize(width: 600, height: 760), NSSize(width: 680, height: 840))
        }
    }
#endif

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
        case "plain":
            return ""
        default:
            return "TODO\n"
        }
    }

    private func hexBinding(_ hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding<Color>(
            get: { colorFromHex(hex.wrappedValue, fallback: fallback) },
            set: { newColor in hex.wrappedValue = colorToHex(newColor) }
        )
    }

    private func themePreviewSnippet(previewTheme: EditorTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("func computeTotal(_ values: [Int]) -> Int {")
                    .foregroundStyle(previewTheme.syntax.keyword)
                Text("    let sum = values.reduce(0, +)")
                    .foregroundStyle(previewTheme.text)
                Text("    // tax adjustment")
                    .foregroundStyle(previewTheme.syntax.comment)
                Text("    return sum + 42")
                    .foregroundStyle(previewTheme.syntax.number)
                Text("}")
                    .foregroundStyle(previewTheme.syntax.keyword)
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
}

#if os(macOS)
struct SettingsWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let idealSize: NSSize
    let translucentEnabled: Bool

    final class Coordinator {
        var didInitialApply = false
        var pendingApply: DispatchWorkItem?
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
        let work = DispatchWorkItem {
            apply(to: window, coordinator: coordinator)
        }
        coordinator.pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func apply(to window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.minSize = minSize
        // Match native macOS Settings layout: centered preference tabs and hidden title text.
        window.toolbarStyle = .preference
        window.titleVisibility = .hidden
        let targetWidth = max(minSize.width, idealSize.width)
        let targetHeight = max(minSize.height, idealSize.height)
        if abs(targetWidth - window.frame.size.width) > 1 || abs(targetHeight - window.frame.size.height) > 1 {
            // Keep the top edge visually stable while adapting size per tab.
            var frame = window.frame
            let oldHeight = frame.size.height
            frame.size = NSSize(width: targetWidth, height: targetHeight)
            frame.origin.y += oldHeight - targetHeight
            if coordinator.didInitialApply {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.allowsImplicitAnimation = true
                    window.animator().setFrame(frame, display: true)
                }
            } else {
                window.setFrame(frame, display: true, animate: false)
                coordinator.didInitialApply = true
            }
        }

        // Keep settings-window translucency in sync without relying on editor view events.
        window.isOpaque = !translucentEnabled
        window.backgroundColor = translucentEnabled ? .clear : NSColor.windowBackgroundColor
        window.titlebarAppearsTransparent = translucentEnabled
        if translucentEnabled {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }
        if #available(macOS 13.0, *) {
            window.titlebarSeparatorStyle = translucentEnabled ? .none : .automatic
        }
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
