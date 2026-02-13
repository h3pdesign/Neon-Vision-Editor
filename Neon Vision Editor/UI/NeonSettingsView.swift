import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NeonSettingsView: View {
    private static var cachedEditorFonts: [String] = []
    let supportsOpenInTabs: Bool
    let supportsTranslucency: Bool
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("SettingsOpenInTabs") private var openInTabs: String = "system"
    @AppStorage("SettingsEditorFontName") private var editorFontName: String = ""
    @AppStorage("SettingsUseSystemFont") private var useSystemFont: Bool = false
    @AppStorage("SettingsEditorFontSize") private var editorFontSize: Double = 14
    @AppStorage("SettingsLineHeight") private var lineHeight: Double = 1.0
    @AppStorage("SettingsAppearance") private var appearance: String = "system"
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
    @AppStorage("SettingsReopenLastSession") private var reopenLastSession: Bool = true
    @AppStorage("SettingsOpenWithBlankDocument") private var openWithBlankDocument: Bool = true
    @AppStorage("SettingsDefaultNewFileLanguage") private var defaultNewFileLanguage: String = "plain"
    @AppStorage("SettingsConfirmCloseDirtyTab") private var confirmCloseDirtyTab: Bool = true
    @AppStorage("SettingsConfirmClearEditor") private var confirmClearEditor: Bool = true

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

    @AppStorage("SettingsCompletionEnabled") private var completionEnabled: Bool = false
    @AppStorage("SettingsCompletionFromDocument") private var completionFromDocument: Bool = false
    @AppStorage("SettingsCompletionFromSyntax") private var completionFromSyntax: Bool = false
    @AppStorage("SelectedAIModel") private var selectedAIModelRaw: String = AIModel.appleIntelligence.rawValue
    @AppStorage("SettingsActiveTab") private var settingsActiveTab: String = "general"
    @AppStorage("SettingsTemplateLanguage") private var settingsTemplateLanguage: String = "swift"
#if os(macOS)
    @State private var fontPicker = FontPickerController()
#endif

    @State private var grokAPIToken: String = SecureTokenStore.token(for: .grok)
    @State private var openAIAPIToken: String = SecureTokenStore.token(for: .openAI)
    @State private var geminiAPIToken: String = SecureTokenStore.token(for: .gemini)
    @State private var anthropicAPIToken: String = SecureTokenStore.token(for: .anthropic)
    @State private var showSupportPurchaseDialog: Bool = false
    @State private var availableEditorFonts: [String] = []
    private let privacyPolicyURL = URL(string: "https://github.com/h3pdesign/Neon-Vision-Editor/blob/main/PRIVACY.md")

    @AppStorage("SettingsThemeName") private var selectedTheme: String = "Neon Glow"
    @AppStorage("SettingsThemeTextColor") private var themeTextHex: String = "#EDEDED"
    @AppStorage("SettingsThemeBackgroundColor") private var themeBackgroundHex: String = "#0E1116"
    @AppStorage("SettingsThemeCursorColor") private var themeCursorHex: String = "#4EA4FF"
    @AppStorage("SettingsThemeSelectionColor") private var themeSelectionHex: String = "#2A3340"
    @AppStorage("SettingsThemeKeywordColor") private var themeKeywordHex: String = "#F5D90A"
    @AppStorage("SettingsThemeStringColor") private var themeStringHex: String = "#FF7AD9"
    @AppStorage("SettingsThemeNumberColor") private var themeNumberHex: String = "#FFB86C"
    @AppStorage("SettingsThemeCommentColor") private var themeCommentHex: String = "#7F8C98"
    
    private var inputFieldBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.secondarySystemBackground)
#endif
    }

    private let themes: [String] = [
        "Neon Glow",
        "Arc",
        "Dusk",
        "Aurora",
        "Horizon",
        "Midnight",
        "Mono",
        "Paper",
        "Solar",
        "Pulse",
        "Mocha",
        "Custom"
    ]

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
        static let sidePaddingRegular: CGFloat = 28
        static let topPadding: CGFloat = 18
        static let bottomPadding: CGFloat = 24
    }

    private enum Typography {
        static let sectionHeadline = Font.headline
        static let sectionSubheadline = Font.subheadline
        static let footnote = Font.footnote
        static let monoBody = Font.system(size: 13, weight: .regular, design: .monospaced)
    }

    init(
        supportsOpenInTabs: Bool = true,
        supportsTranslucency: Bool = true
    ) {
        self.supportsOpenInTabs = supportsOpenInTabs
        self.supportsTranslucency = supportsTranslucency
    }

    var body: some View {
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
            aiTab
                .tabItem { Label("AI", systemImage: "brain.head.profile") }
                .tag("ai")
            supportTab
                .tabItem { Label("Support", systemImage: "heart") }
                .tag("support")
        }
#if os(macOS)
        .frame(minWidth: 900, idealWidth: 980, minHeight: 820, idealHeight: 880)
        .background(
            SettingsWindowConfigurator(
                minSize: NSSize(width: 900, height: 820),
                idealSize: NSSize(width: 980, height: 880)
            )
        )
#endif
        .preferredColorScheme(preferredColorSchemeOverride)
        .onAppear {
            settingsActiveTab = "general"
            loadAvailableEditorFontsIfNeeded()
            if supportPurchaseManager.supportProduct == nil {
                Task { await supportPurchaseManager.refreshStoreState() }
            }
#if os(macOS)
            fontPicker.onChange = { selected in
                useSystemFont = false
                editorFontName = selected.fontName
                editorFontSize = Double(selected.pointSize)
            }
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
        .confirmationDialog("Support Neon Vision Editor", isPresented: $showSupportPurchaseDialog, titleVisibility: .visible) {
            Button("Support \(supportPurchaseManager.supportPriceLabel)") {
                Task { await supportPurchaseManager.purchaseSupport() }
            }
            Button("Restore Purchases") {
                Task { await supportPurchaseManager.restorePurchases() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Optional one-time purchase to support development. No features are locked behind this purchase.")
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
            GroupBox("Window") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    if supportsOpenInTabs {
                        HStack(alignment: .center, spacing: UI.space12) {
                            Text("Open in Tabs")
                                .frame(width: isCompactSettingsLayout ? nil : 140, alignment: .leading)
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
                            .frame(width: isCompactSettingsLayout ? nil : 140, alignment: .leading)
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
                    }
                }
                .padding(UI.groupPadding)
            }

            GroupBox("Editor Font") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Toggle("Use System Font", isOn: $useSystemFont)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Font")
                            .frame(width: isCompactSettingsLayout ? nil : 140, alignment: .leading)
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
                        .frame(maxWidth: isCompactSettingsLayout ? .infinity : 240, alignment: .leading)
                        .onChange(of: selectedFontValue) { _, _ in
                            useSystemFont = (selectedFontValue == systemFontSentinel)
                            if !useSystemFont && !selectedFontValue.isEmpty {
                                editorFontName = selectedFontValue
                            }
                        }
                        .onChange(of: useSystemFont) { _, isSystem in
                            if isSystem {
                                selectedFontValue = systemFontSentinel
                            } else if !editorFontName.isEmpty {
                                selectedFontValue = editorFontName
                            }
                        }
                        .onChange(of: editorFontName) { _, newValue in
                            guard !useSystemFont else { return }
                            if !newValue.isEmpty {
                                selectedFontValue = newValue
                            }
                        }
#if os(macOS)
                        Button("Choose…") {
                            useSystemFont = false
                            fontPicker.open(currentName: editorFontName, size: editorFontSize)
                        }
                        .disabled(useSystemFont)
#endif
                    }

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Font Size")
                            .frame(width: isCompactSettingsLayout ? nil : 140, alignment: .leading)
                        Stepper(value: $editorFontSize, in: 10...28, step: 1) {
                            Text("\(Int(editorFontSize)) pt")
                        }
                        .frame(maxWidth: isCompactSettingsLayout ? .infinity : 220, alignment: .leading)
                    }

                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Line Height")
                            .frame(width: isCompactSettingsLayout ? nil : 140, alignment: .leading)
                        Slider(value: $lineHeight, in: 1.0...1.8, step: 0.05)
                            .frame(maxWidth: isCompactSettingsLayout ? .infinity : 240)
                        Text(String(format: "%.2fx", lineHeight))
                            .frame(width: 54, alignment: .trailing)
                    }
                }
                .padding(UI.groupPadding)
            }

            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Toggle("Open with Blank Document", isOn: $openWithBlankDocument)
                    Toggle("Reopen Last Session", isOn: $reopenLastSession)
                        .disabled(openWithBlankDocument)
                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Default New File Language")
                            .frame(width: isCompactSettingsLayout ? nil : 180, alignment: .leading)
                        Picker("", selection: $defaultNewFileLanguage) {
                            ForEach(templateLanguages, id: \.self) { lang in
                                Text(languageLabel(for: lang)).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(UI.groupPadding)
            }

            GroupBox("Confirmations") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Toggle("Confirm Before Closing Dirty Tab", isOn: $confirmCloseDirtyTab)
                    Toggle("Confirm Before Clearing Editor", isOn: $confirmClearEditor)
                }
                .padding(UI.groupPadding)
            }
        }
    }

    private let systemFontSentinel = "__system__"
    @State private var selectedFontValue: String = "__system__"

    private var selectedFontBinding: Binding<String> {
        Binding(
            get: {
                if useSystemFont { return systemFontSentinel }
                if editorFontName.isEmpty { return systemFontSentinel }
                return editorFontName
            },
            set: { selectedFontValue = $0 }
        )
    }

    private func loadAvailableEditorFontsIfNeeded() {
        if !availableEditorFonts.isEmpty {
            selectedFontValue = useSystemFont ? systemFontSentinel : (editorFontName.isEmpty ? systemFontSentinel : editorFontName)
            return
        }
        if !Self.cachedEditorFonts.isEmpty {
            availableEditorFonts = Self.cachedEditorFonts
            selectedFontValue = useSystemFont ? systemFontSentinel : (editorFontName.isEmpty ? systemFontSentinel : editorFontName)
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
        selectedFontValue = useSystemFont ? systemFontSentinel : (editorFontName.isEmpty ? systemFontSentinel : editorFontName)
    }

    private var editorTab: some View {
        settingsContainer(maxWidth: 760) {
            GroupBox("Editor") {
                VStack(spacing: 16) {
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

                    Divider()

                    VStack(alignment: .leading, spacing: UI.space10) {
                        Text("Editing")
                            .font(Typography.sectionHeadline)
                        Toggle("Auto Indent", isOn: $autoIndent)
                        Toggle("Auto Close Brackets", isOn: $autoCloseBrackets)
                        Toggle("Trim Trailing Whitespace", isOn: $trimTrailingWhitespace)
                        Toggle("Trim Edges for Syntax Detection", isOn: $trimWhitespaceForSyntaxDetection)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: UI.space10) {
                        Text("Completion")
                            .font(Typography.sectionHeadline)
                        Toggle("Enable Completion", isOn: $completionEnabled)
                        Toggle("Include Words in Document", isOn: $completionFromDocument)
                        Toggle("Include Syntax Keywords", isOn: $completionFromSyntax)
                    }
                }
                .padding(UI.groupPadding)
            }
        }
    }

    private var templateTab: some View {
        settingsContainer(maxWidth: 640) {
            GroupBox("Completion Template") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    HStack(alignment: .center, spacing: UI.space12) {
                        Text("Language")
                            .frame(width: isCompactSettingsLayout ? nil : 140, alignment: .leading)
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
                        Button("Reset to Default") {
                            UserDefaults.standard.removeObject(forKey: templateOverrideKey(for: settingsTemplateLanguage))
                        }
                        Button("Use Default Template") {
                            if let fallback = defaultTemplate(for: settingsTemplateLanguage) {
                                UserDefaults.standard.set(fallback, forKey: templateOverrideKey(for: settingsTemplateLanguage))
                            }
                        }
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
        return settingsContainer(maxWidth: 760) {
            HStack(spacing: UI.space16) {
#if os(macOS)
                let listView = List(themes, id: \.self, selection: $selectedTheme) { theme in
                    Text(theme)
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

                VStack(alignment: .leading, spacing: UI.space16) {
                    Text("Theme Colors")
                        .font(Typography.sectionHeadline)
                    Spacer(minLength: 6)

                    colorRow(title: "Text", color: isCustom ? hexBinding($themeTextHex, fallback: .white) : .constant(palette.text))
                        .disabled(!isCustom)
                    colorRow(title: "Background", color: isCustom ? hexBinding($themeBackgroundHex, fallback: .black) : .constant(palette.background))
                        .disabled(!isCustom)
                    colorRow(title: "Cursor", color: isCustom ? hexBinding($themeCursorHex, fallback: .blue) : .constant(palette.cursor))
                        .disabled(!isCustom)
                    colorRow(title: "Selection", color: isCustom ? hexBinding($themeSelectionHex, fallback: .gray) : .constant(palette.selection))
                        .disabled(!isCustom)

                    Divider()

                    Text("Syntax")
                        .font(Typography.sectionSubheadline)
                        .foregroundStyle(.secondary)

                    colorRow(title: "Keywords", color: isCustom ? hexBinding($themeKeywordHex, fallback: .yellow) : .constant(palette.keyword))
                        .disabled(!isCustom)
                    colorRow(title: "Strings", color: isCustom ? hexBinding($themeStringHex, fallback: .pink) : .constant(palette.string))
                        .disabled(!isCustom)
                    colorRow(title: "Numbers", color: isCustom ? hexBinding($themeNumberHex, fallback: .orange) : .constant(palette.number))
                        .disabled(!isCustom)
                    colorRow(title: "Comments", color: isCustom ? hexBinding($themeCommentHex, fallback: .gray) : .constant(palette.comment))
                        .disabled(!isCustom)
                    colorRow(title: "Types", color: .constant(palette.type))
                        .disabled(true)
                    colorRow(title: "Builtins", color: .constant(palette.builtin))
                        .disabled(true)

                    Spacer()
                    Text(isCustom ? "Custom theme applies immediately." : "Select Custom to edit colors.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
#if os(iOS)
            .padding(.top, 20)
#endif
        }
    }

    private var aiTab: some View {
        settingsContainer(maxWidth: 520) {
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

                    Text("Choose the default model used by editor AI actions.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(UI.groupPadding)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, alignment: .center)

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
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var selectedAIModelBinding: Binding<AIModel> {
        Binding(
            get: { AIModel(rawValue: selectedAIModelRaw) ?? .appleIntelligence },
            set: { selectedAIModelRaw = $0.rawValue }
        )
    }

    private var supportTab: some View {
        settingsContainer(maxWidth: 520) {
            GroupBox("Support Development") {
                VStack(alignment: .leading, spacing: UI.space12) {
                    Text("In-App Purchase is optional and only used to support the app.")
                        .foregroundStyle(.secondary)
                    Text("One-time, non-consumable purchase. No subscription and no auto-renewal.")
                        .font(Typography.footnote)
                        .foregroundStyle(.secondary)
                    if supportPurchaseManager.canUseInAppPurchases {
                        Text("Price: \(supportPurchaseManager.supportPriceLabel)")
                            .font(Typography.sectionHeadline)
                        if supportPurchaseManager.hasSupported {
                            Label("Thank you for your support.", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                        HStack(spacing: UI.space12) {
                            Button(supportPurchaseManager.isPurchasing ? "Purchasing…" : "Support the App") {
                                showSupportPurchaseDialog = true
                            }
                            .disabled(supportPurchaseManager.isPurchasing || supportPurchaseManager.isLoadingProducts)

                            Button("Restore Purchases") {
                                Task { await supportPurchaseManager.restorePurchases() }
                            }
                            .disabled(supportPurchaseManager.isLoadingProducts)

                            Button("Refresh Price") {
                                Task { await supportPurchaseManager.refreshProducts() }
                            }
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
    }

    private func settingsContainer<Content: View>(maxWidth: CGFloat = 560, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: isCompactSettingsLayout ? .leading : .center, spacing: UI.space20) {
                content()
            }
            .frame(maxWidth: maxWidth, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isCompactSettingsLayout ? .topLeading : .top)
            .padding(.top, UI.topPadding)
            .padding(.bottom, UI.bottomPadding)
            .padding(.horizontal, isCompactSettingsLayout ? UI.sidePaddingCompact : UI.sidePaddingRegular)
        }
        .background(.ultraThinMaterial)
    }

    private func colorRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .frame(width: isCompactSettingsLayout ? nil : 120, alignment: .leading)
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
                        .frame(width: 120, alignment: .leading)
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
                        .frame(width: 200)
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
}

#if os(macOS)
final class FontPickerController: NSObject, NSFontChanging {
    private var currentFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    var onChange: ((NSFont) -> Void)?

    func open(currentName: String, size: Double) {
        let base = NSFont(name: currentName, size: CGFloat(size)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        currentFont = base
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(base, isMultiple: false)
        NSFontPanel.shared.orderFront(nil)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        let manager = sender ?? NSFontManager.shared
        let converted = manager.convert(currentFont)
        currentFont = converted
        onChange?(converted)
    }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let idealSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView.window)
        }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.minSize = NSSize(
            width: max(window.minSize.width, minSize.width),
            height: max(window.minSize.height, minSize.height)
        )
        let targetWidth = max(window.frame.size.width, idealSize.width)
        let targetHeight = max(window.frame.size.height, idealSize.height)
        if targetWidth != window.frame.size.width || targetHeight != window.frame.size.height {
            window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
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
